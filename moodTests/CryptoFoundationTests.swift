import Foundation
import Testing
@testable import mood

/// No network, disk crypto store, real accounts, or credential writes.
@Suite("Official Matrix crypto foundation", .serialized)
@MainActor
struct CryptoFoundationTests {
    enum CheckFailure: Error { case invalidFixture, unexpectedRequest, decryptionFailed }

    static func json(_ value: Any) throws -> String {
        String(decoding: try JSONSerialization.data(withJSONObject: value), as: UTF8.self)
    }

    @Test func adapterRefusesEncryptionBeforeKeySharing() throws {
        let machine = try OlmMachine.newInMemory(userId: "@adapter:test.invalid", deviceId: "TEST")
        let engine = CryptoEngine(machine: machine)
        var rejected = false
        do { _ = try engine.encrypt(roomId: "!room:test.invalid", content: "{}") }
        catch CryptoEngine.Failure.roomKeyNotShared { rejected = true }
        #expect(rejected)
        var badResponseRejected = false
        do {
            try engine.markRequestAsSent(requestId: "missing", requestType: .keysUpload,
                                               responseBody: "{\"errcode\":\"M_FORBIDDEN\"}")
        } catch CryptoEngine.Failure.invalidResponse { badResponseRejected = true }
        #expect(badResponseRejected)
    }

    @Test func encryptedStoreSurvivesReopenAndRejectsWrongPassphrase() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let passphrase = UUID().uuidString + UUID().uuidString
        func identity() throws -> [String: String] {
            let machine = try OlmMachine(userId: "@persistent:test.invalid", deviceId: "TEST",
                                         path: folder.path, passphrase: passphrase)
            return machine.identityKeys()
        }
        let original = try identity()
        let reopened = try identity()
        #expect(original == reopened)
        var rejected = false
        do {
            _ = try OlmMachine(userId: "@persistent:test.invalid", deviceId: "TEST",
                               path: folder.path, passphrase: UUID().uuidString)
        } catch { rejected = true }
        #expect(rejected)
    }

    @Test func aliceBobMegolmAndExcludedThirdParty() throws {
        // Official SDK MemoryStore, exposed through a constructor-only UniFFI patch.
        func machine(_ name: String) throws -> OlmMachine {
            try OlmMachine.newInMemory(userId: "@\(name):test.invalid", deviceId: name.uppercased())
        }
        let alice = try machine("alice"), bob = try machine("bob"), third = try machine("third")
        let machines = [alice, bob, third]
        var deviceKeys: [String: [String: Any]] = [:]
        var oneTimeKeys: [String: [String: Any]] = [:]
        for machine in machines {
            let keys = machine.identityKeys()
            #expect(keys.count == 2)
            #expect(keys.values.allSatisfy { !$0.isEmpty })
            for request in try machine.outgoingRequests() {
                if case let .keysUpload(id, body) = request {
                    let object = try #require(JSONSerialization.jsonObject(with: Data(body.utf8)) as? [String: Any])
                    deviceKeys[machine.userId()] = [machine.deviceId(): object["device_keys"]!]
                    oneTimeKeys[machine.userId()] = object["one_time_keys"] as? [String: Any]
                    try machine.markRequestAsSent(requestId: id, requestType: .keysUpload,
                        responseBody: Self.json(["one_time_key_counts": ["signed_curve25519": 50]]))
                }
            }
        }
        #expect(alice.identityKeys() != bob.identityKeys())
        let participants = [alice.userId(), bob.userId()]
        for machine in [alice, bob] {
            try machine.updateTrackedUsers(users: participants)
            for request in try machine.outgoingRequests() {
                if case let .keysQuery(id, users) = request {
                    let keys = deviceKeys.filter { users.contains($0.key) }
                    try machine.markRequestAsSent(requestId: id, requestType: .keysQuery,
                        responseBody: Self.json(["device_keys": keys, "failures": [:]]))
                }
            }
        }
        if let request = try alice.getMissingSessions(users: participants) {
            guard case let .keysClaim(id, requested) = request else { throw CheckFailure.unexpectedRequest }
            var claimed: [String: [String: Any]] = [:]
            for (user, devices) in requested {
                for (device, _) in devices {
                    let keys = try #require(oneTimeKeys[user])
                    let key = try #require(keys.first(where: { $0.key.hasPrefix("signed_curve25519:") }))
                    claimed[user, default: [:]][device] = [key.key: key.value]
                }
            }
            try alice.markRequestAsSent(requestId: id, requestType: .keysClaim,
                responseBody: Self.json(["one_time_keys": claimed, "failures": [:]]))
        }
        let room = "!foundation:test.invalid"
        let settings = EncryptionSettings(algorithm: .megolmV1AesSha2, rotationPeriod: 604800,
            rotationPeriodMsgs: 100, historyVisibility: .shared, onlyAllowTrustedDevices: false,
            errorOnVerifiedUserProblem: false)
        let decryption = DecryptionSettings(senderDeviceTrustRequirement: .untrusted)
        let requests = try alice.shareRoomKey(roomId: room, users: participants, settings: settings)
        #expect(!requests.isEmpty)
        for request in requests {
            guard case let .toDevice(id, eventType, body) = request else { throw CheckFailure.unexpectedRequest }
            let messages = try #require(JSONSerialization.jsonObject(with: Data(body.utf8)) as? [String: [String: Any]])
            if let content = messages[bob.userId()]?[bob.deviceId()] {
                _ = try bob.receiveSyncChanges(events: Self.json(["events": [["type": eventType,
                    "sender": alice.userId(), "content": content]]]),
                    deviceChanges: DeviceLists(changed: [], left: []), keyCounts: [:],
                    unusedFallbackKeys: nil, nextBatchToken: "offline-1", decryptionSettings: decryption)
            }
            try alice.markRequestAsSent(requestId: id, requestType: .toDevice, responseBody: "{}")
        }
        let content = try alice.encrypt(roomId: room, eventType: "m.room.message",
            content: Self.json(["msgtype": "m.text", "body": "bonjour"]))
        #expect(!content.contains("bonjour"))
        let event = try Self.json(["type": "m.room.encrypted", "sender": alice.userId(),
            "event_id": "$foundation", "origin_server_ts": 1,
            "content": JSONSerialization.jsonObject(with: Data(content.utf8))])
        let clear = try bob.decryptRoomEvent(event: event, roomId: room,
            handleVerificationEvents: false, strictShields: true, decryptionSettings: decryption)
        let decoded = try #require(JSONSerialization.jsonObject(with: Data(clear.clearEvent.utf8)) as? [String: Any])
        #expect((decoded["content"] as? [String: Any])?["body"] as? String == "bonjour")
        var excluded = false
        do {
            _ = try third.decryptRoomEvent(event: event, roomId: room,
                handleVerificationEvents: false, strictShields: true, decryptionSettings: decryption)
        } catch { excluded = true }
        #expect(excluded)
    }
}
