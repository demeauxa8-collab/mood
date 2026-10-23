import Foundation
import Security

/// Phase-one adapter only. Networking and app integration belong to phase two.
/// All machine access is serialized; callers must acknowledge successful HTTP responses
/// and await room-key sharing before encrypting. Never log SDK payloads or errors.
@MainActor
final class CryptoEngine {
    enum Failure: Error {
        case randomGeneration, credentialStorage, missingPassphrase, roomKeyNotShared, malformedEvent, invalidResponse
    }

    private let machine: OlmMachine
    private var sharedRooms: Set<String> = []

    init(machine: OlmMachine) { self.machine = machine }

    /// KeychainHelper uses the keychain when available, otherwise its private 0600 file.
    /// The fallback does not protect against an attacker who can read the user's disk.
    @MainActor
    static func open(userId: String, deviceId: String) throws -> CryptoEngine {
        let manager = FileManager.default
        let support = try manager.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                      appropriateFor: nil, create: true)
        // Lossless path encoding prevents slashes and traversal in Matrix identifiers.
        let component = Data(userId.utf8).base64EncodedString()
            .replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "+", with: "-")
        let device = Data(deviceId.utf8).base64EncodedString()
            .replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "+", with: "-")
        let folder = support.appendingPathComponent("Mood/crypto/\(component)/\(device)", isDirectory: true)
        let credential = "crypto.store.\(component).\(device)"
        let passphrase: String
        if let existing = KeychainHelper.load(key: credential) {
            passphrase = existing
        } else {
            // Never silently replace a lost store key (which would strand existing sessions).
            if manager.fileExists(atPath: folder.path),
               !(try manager.contentsOfDirectory(atPath: folder.path)).isEmpty {
                throw Failure.missingPassphrase
            }
            var bytes = [UInt8](repeating: 0, count: 32)
            guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else {
                throw Failure.randomGeneration
            }
            passphrase = Data(bytes).base64EncodedString()
            _ = bytes.withUnsafeMutableBytes { $0.initializeMemory(as: UInt8.self, repeating: 0) }
            guard KeychainHelper.save(key: credential, value: passphrase) else {
                throw Failure.credentialStorage
            }
        }
        let cryptoRoot = support.appendingPathComponent("Mood/crypto", isDirectory: true)
        for directory in [cryptoRoot, folder.deletingLastPathComponent(), folder] {
            try manager.createDirectory(at: directory, withIntermediateDirectories: true,
                                        attributes: [.posixPermissions: 0o700])
            try manager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
            #if !targetEnvironment(macCatalyst)
            try manager.setAttributes([.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
                                      ofItemAtPath: directory.path)
            #endif
        }
        return try CryptoEngine(machine: OlmMachine(userId: userId, deviceId: deviceId,
                                                    path: folder.path, passphrase: passphrase))
    }

    func identityKeys() -> [String: String] { machine.identityKeys() }
    func outgoingRequests() throws -> [Request] { try machine.outgoingRequests() }

    func receiveSyncChanges(events: String, deviceChanges: DeviceLists,
                            keyCounts: [String: Int32], unusedFallbackKeys: [String]?,
                            nextBatchToken: String, settings: DecryptionSettings) throws -> SyncChangesResult {
        sharedRooms.removeAll() // Membership/device changes require a fresh sharing pass.
        return try machine.receiveSyncChanges(events: events, deviceChanges: deviceChanges,
            keyCounts: keyCounts, unusedFallbackKeys: unusedFallbackKeys,
            nextBatchToken: nextBatchToken, decryptionSettings: settings)
    }

    func markRequestAsSent(requestId: String, requestType: RequestType, responseBody: String) throws {
        // The FFI assumes successful Matrix response schemas and can panic on invalid input.
        guard let data = responseBody.data(using: .utf8),
              let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              object["errcode"] == nil else { throw Failure.invalidResponse }
        switch requestType {
        case .keysUpload:
            guard object["one_time_key_counts"] is [String: Int] else { throw Failure.invalidResponse }
        case .keysQuery:
            guard object["device_keys"] is [String: Any] else { throw Failure.invalidResponse }
        case .keysClaim:
            guard object["one_time_keys"] is [String: Any] else { throw Failure.invalidResponse }
        case .roomMessage:
            guard object["event_id"] is String else { throw Failure.invalidResponse }
        case .keysBackup:
            guard object["count"] is Int, object["etag"] is String else { throw Failure.invalidResponse }
        case .toDevice, .signatureUpload: break
        }
        try machine.markRequestAsSent(requestId: requestId, requestType: requestType, responseBody: responseBody)
    }

    func updateTrackedUsers(_ users: [String]) throws {
        sharedRooms.removeAll()
        try machine.updateTrackedUsers(users: users)
    }

    func missingSessions(users: [String]) throws -> Request? {
        try machine.getMissingSessions(users: users)
    }

    func shareRoomKey(roomId: String, users: [String], settings: EncryptionSettings) throws -> [Request] {
        sharedRooms.remove(roomId)
        return try machine.shareRoomKey(roomId: roomId, users: users, settings: settings)
    }

    /// Call only after all shareRoomKey requests were successfully acknowledged.
    /// A second share pass returns no requests once the SDK considers the key shared.
    func confirmRoomKeyShared(roomId: String, users: [String], settings: EncryptionSettings) throws -> [Request] {
        let pending = try machine.shareRoomKey(roomId: roomId, users: users, settings: settings)
        if pending.isEmpty { sharedRooms.insert(roomId) }
        return pending
    }

    func encrypt(roomId: String, content: String) throws -> String {
        guard sharedRooms.contains(roomId) else { throw Failure.roomKeyNotShared }
        return try machine.encrypt(roomId: roomId, eventType: "m.room.message", content: content)
    }

    func decrypt(event: String, settings: DecryptionSettings? = nil) throws -> DecryptedEvent {
        guard let data = event.data(using: .utf8),
              let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let roomId = object["room_id"] as? String else { throw Failure.malformedEvent }
        return try machine.decryptRoomEvent(event: event, roomId: roomId,
            handleVerificationEvents: false, strictShields: true, decryptionSettings: settings ??
                DecryptionSettings(senderDeviceTrustRequirement: .crossSignedOrLegacy))
    }
}
