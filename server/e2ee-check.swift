// Standalone CLI; no app launch. Compile with the pinned generated Swift and host Rust library.
import Foundation

private enum CheckError: Error { case contract, http(Int), cleanup }
private func encoded(_ value: Any) throws -> String {
    String(decoding: try JSONSerialization.data(withJSONObject: value), as: UTF8.self)
}
private func object(_ value: String) throws -> [String: Any] {
    guard let result = try JSONSerialization.jsonObject(with: Data(value.utf8)) as? [String: Any] else {
        throw CheckError.contract
    }
    return result
}
private func escape(_ value: String) -> String {
    value.addingPercentEncoding(withAllowedCharacters: .alphanumerics)!
}

@main private struct LiveCheck {
    struct Account {
        let user: String, password: String, token: String, device: String
    }
    static let base = "http://127.0.0.1:6167/_matrix/client/v3"
    static let decryption = DecryptionSettings(senderDeviceTrustRequirement: .untrusted)

    static func http(_ method: String, _ path: String, _ body: Any? = nil,
                     _ account: Account? = nil, allowChallenge: Bool = false) async throws -> [String: Any] {
        var request = URLRequest(url: URL(string: base + path)!)
        request.httpMethod = method
        request.timeoutInterval = 35
        if let account { request.setValue("Bearer " + account.token, forHTTPHeaderField: "Authorization") }
        if let body {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let response = response as? HTTPURLResponse else { throw CheckError.contract }
        guard (200..<300).contains(response.statusCode) || (allowChallenge && response.statusCode == 401) else {
            throw CheckError.http(response.statusCode)
        }
        guard let result = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw CheckError.contract }
        return result
    }

    static func register(_ label: String, registration: String) async throws -> Account {
        let name = "o1check-" + label + "-" + UUID().uuidString.lowercased()
        let password = UUID().uuidString + UUID().uuidString
        let body: [String: Any] = ["username": name, "password": password, "device_id": "O1CHECK"]
        let challenge = try await http("POST", "/register", body, allowChallenge: true)
        guard let session = challenge["session"] as? String else { throw CheckError.contract }
        var authenticated = body
        authenticated["auth"] = ["type": "m.login.registration_token", "session": session, "token": registration]
        var response = try await http("POST", "/register", authenticated, allowChallenge: true)
        if response["access_token"] == nil {
            authenticated["auth"] = ["type": "m.login.dummy", "session": response["session"] as? String ?? session]
            response = try await http("POST", "/register", authenticated)
        }
        guard let user = response["user_id"] as? String, let token = response["access_token"] as? String,
              let device = response["device_id"] as? String else { throw CheckError.contract }
        return Account(user: user, password: password, token: token, device: device)
    }

    static func dispatch(_ request: Request, machine: OlmMachine, account: Account) async throws {
        let id: String, type: RequestType, response: [String: Any]
        switch request {
        case let .keysUpload(requestId, body):
            id = requestId; type = .keysUpload
            response = try await http("POST", "/keys/upload", object(body), account)
        case let .keysQuery(requestId, users):
            id = requestId; type = .keysQuery
            response = try await http("POST", "/keys/query", ["device_keys": Dictionary(uniqueKeysWithValues: users.map { ($0, [String]()) })], account)
        case let .keysClaim(requestId, keys):
            id = requestId; type = .keysClaim
            response = try await http("POST", "/keys/claim", ["one_time_keys": keys], account)
        case let .toDevice(requestId, eventType, body):
            id = requestId; type = .toDevice
            response = try await http("PUT", "/sendToDevice/\(escape(eventType))/\(escape(id))", ["messages": object(body)], account)
        default: throw CheckError.contract
        }
        try machine.markRequestAsSent(requestId: id, requestType: type, responseBody: encoded(response))
    }

    static func sync(_ account: Account, machine: OlmMachine, since: String?) async throws -> [String: Any] {
        let response = try await http("GET", "/sync?timeout=1000&set_presence=offline" + (since.map { "&since=" + escape($0) } ?? ""), nil, account)
        _ = try machine.receiveSyncChanges(events: encoded(response["to_device"] ?? ["events": []]),
            deviceChanges: DeviceLists(changed: (response["device_lists"] as? [String: [String]])?["changed"] ?? [],
                                      left: (response["device_lists"] as? [String: [String]])?["left"] ?? []),
            keyCounts: (response["device_one_time_keys_count"] as? [String: Int32]) ?? [:],
            unusedFallbackKeys: response["device_unused_fallback_key_types"] as? [String],
            nextBatchToken: response["next_batch"] as? String ?? "", decryptionSettings: decryption)
        return response
    }

    static func run(_ accounts: [Account], folder: URL) async throws {
        let a = accounts[0], b = accounts[1]
        let alice = try OlmMachine(userId: a.user, deviceId: a.device, path: folder.appendingPathComponent("a").path, passphrase: UUID().uuidString)
        let bob = try OlmMachine(userId: b.user, deviceId: b.device, path: folder.appendingPathComponent("b").path, passphrase: UUID().uuidString)
        for (machine, account) in [(alice, a), (bob, b)] {
            for request in try machine.outgoingRequests() { try await dispatch(request, machine: machine, account: account) }
        }
        print("PASS device-key upload")
        let created = try await http("POST", "/createRoom", ["preset": "private_chat", "invite": [b.user],
            "initial_state": [["type": "m.room.encryption", "state_key": "", "content": ["algorithm": "m.megolm.v1.aes-sha2"]]]], a)
        guard let room = created["room_id"] as? String else { throw CheckError.contract }
        _ = try await http("POST", "/join/" + escape(room), [:], b)
        var since = (try await sync(b, machine: bob, since: nil))["next_batch"] as? String
        for (machine, account) in [(alice, a), (bob, b)] {
            try machine.updateTrackedUsers(users: [a.user, b.user])
            for request in try machine.outgoingRequests() { try await dispatch(request, machine: machine, account: account) }
        }
        print("PASS keys/query")
        if let request = try alice.getMissingSessions(users: [b.user]) {
            try await dispatch(request, machine: alice, account: a)
        } else { throw CheckError.contract }
        print("PASS keys/claim")
        let settings = EncryptionSettings(algorithm: .megolmV1AesSha2, rotationPeriod: 604800, rotationPeriodMsgs: 100,
            historyVisibility: .shared, onlyAllowTrustedDevices: false, errorOnVerifiedUserProblem: false)
        let shares = try alice.shareRoomKey(roomId: room, users: [a.user, b.user], settings: settings)
        guard !shares.isEmpty else { throw CheckError.contract }
        for request in shares { try await dispatch(request, machine: alice, account: a) }
        let keySync = try await sync(b, machine: bob, since: since)
        since = keySync["next_batch"] as? String
        print("PASS encrypted to-device room-key delivery")
        let ciphertext = try alice.encrypt(roomId: room, eventType: "m.room.message",
                                           content: encoded(["msgtype": "m.text", "body": "bonjour"]))
        guard !ciphertext.contains("bonjour") else { throw CheckError.contract }
        let sent = try await http("PUT", "/rooms/\(escape(room))/send/m.room.encrypted/\(UUID().uuidString)", object(ciphertext), a)
        guard let eventId = sent["event_id"] as? String else { throw CheckError.contract }
        // Fetch the actual persisted event, not a locally reconstructed ciphertext.
        let event = try await http("GET", "/rooms/\(escape(room))/event/\(escape(eventId))", nil, b)
        guard event["type"] as? String == "m.room.encrypted" else { throw CheckError.contract }
        let decrypted = try bob.decryptRoomEvent(event: encoded(event), roomId: room,
            handleVerificationEvents: false, strictShields: true, decryptionSettings: decryption)
        let clear = try object(decrypted.clearEvent)
        guard (clear["content"] as? [String: Any])?["body"] as? String == "bonjour" else { throw CheckError.contract }
        print("PASS persisted m.room.encrypted decrypted by recipient")
        for account in accounts { _ = try await http("POST", "/rooms/\(escape(room))/leave", [:], account) }
    }

    static func main() async {
        var accounts: [Account] = []
        var passed = false
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("mood-o1-" + UUID().uuidString)
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true,
                                                   attributes: [.posixPermissions: 0o700])
            let registration = try String(contentsOf: FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("mood-server/registration_token"), encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines)
            accounts.append(try await register("alice", registration: registration))
            accounts.append(try await register("bob", registration: registration))
            try await run(accounts, folder: folder)
            passed = true
        } catch { print("FAIL live crypto check (details suppressed to protect credentials)") }
        // Cleanup is awaited even after a failed check. No tokens or payloads are printed.
        for account in accounts {
            do {
                let challenge = try await http("POST", "/account/deactivate", [:], account, allowChallenge: true)
                var auth: [String: Any] = ["type": "m.login.password", "identifier": ["type": "m.id.user", "user": account.user], "password": account.password]
                if let session = challenge["session"] {
                    auth["session"] = session
                    _ = try await http("POST", "/account/deactivate", ["auth": auth, "erase": true], account)
                }
                print("PASS disposable account deactivated")
            } catch { passed = false; print("FAIL disposable account cleanup; manual intervention required") }
        }
        try? FileManager.default.removeItem(at: folder)
        exit(passed ? 0 : 1)
    }
}
