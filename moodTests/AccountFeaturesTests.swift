import Foundation
import Testing
@testable import mood

@MainActor
struct AccountFeaturesTests {
    @Test func restoresStatusSeparatelyForEachAccount() throws {
        let suite = "MoodJStatus." + UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        AccountStatusStorage.save(status: .invisible, message: "Focus", userId: "@one:x", defaults: defaults)
        let restored = AccountStatusStorage.load(userId: "@one:x", defaults: defaults)
        #expect(restored.0 == .invisible)
        #expect(restored.1 == "Focus")
        #expect(AccountStatusStorage.load(userId: "@two:x", defaults: defaults).0 == .online)
        AccountStatusStorage.save(status: .dnd, message: nil, userId: "@one:x", defaults: defaults)
        #expect(AccountStatusStorage.load(userId: "@one:x", defaults: defaults).1 == nil)
    }

    @Test func validatesEmail() {
        #expect(AccountValidation.isValidEmail("clara@example.org"))
        for invalid in ["", "clara", "@example.org", "clara@", "clara @example.org", "clara@example.", "a@@b.fr"] {
            #expect(!AccountValidation.isValidEmail(invalid))
        }
    }

    @Test func filtersBlockedPeersAndSelf() {
        #expect(AccountValidation.isVisiblePeer("@peer:x", me: "@me:x", blocked: []))
        #expect(!AccountValidation.isVisiblePeer("@peer:x", me: "@me:x", blocked: ["@peer:x"]))
        #expect(!AccountValidation.isVisiblePeer("@me:x", me: "@me:x", blocked: []))
        #expect(!AccountValidation.isVisiblePeer("!group:x", me: "@me:x", blocked: []))
    }

    @Test func gatesExtendedProfileByAdvertisedVersion() throws {
        let older = try JSONDecoder().decode(AccountServerVersions.self, from: Data(#"{"versions":["v1.15"]}"#.utf8))
        #expect(!older.supportsExtendedProfiles)
        let supported = try JSONDecoder().decode(AccountServerVersions.self, from: Data(#"{"versions":["v1.16","v1.18"]}"#.utf8))
        #expect(supported.supportsExtendedProfiles)
        let unstable = try JSONDecoder().decode(AccountServerVersions.self, from: Data(#"{"versions":[],"unstable_features":{"uk.tcpip.msc4133":true}}"#.utf8))
        #expect(unstable.supportsExtendedProfiles)
    }

    @Test func validatesPasswordLength() {
        #expect(!AccountValidation.isValidPassword("short"))
        #expect(AccountValidation.isValidPassword("synthetic-password"))
    }

    @Test func neverReuseAGroupForOnePeer() {
        #expect(AccountValidation.canReuseDirectRoom(members: ["@me:x", "@peer:x"], me: "@me:x", target: "@peer:x"))
        #expect(!AccountValidation.canReuseDirectRoom(members: ["@me:x", "@peer:x", "@other:x"], me: "@me:x", target: "@peer:x"))
        #expect(!AccountValidation.canReuseDirectRoom(members: ["@me:x"], me: "@me:x", target: "@peer:x"))
    }

    @Test func doNotDisturbAndBlockingSuppressBanners() {
        let candidate = NotificationCandidate(eventId: "$new", roomId: "!dm:x", senderId: "@peer:x",
                                              senderName: "Peer", roomName: "DM", isDirect: true,
                                              body: "Hello", timestamp: Date())
        var preferences = AccountPreferences()
        preferences.notificationsEnabled = true
        var context = NotificationContext(myUserId: "@me:x", preferences: preferences, ignoredUserIds: [],
                                          mutedRoomIds: [], openRoomId: nil, isAppActive: false,
                                          seenEventIds: [], now: Date())
        #expect(NotificationDecision.shouldNotify(candidate, in: context))
        context.isDoNotDisturb = true
        #expect(!NotificationDecision.shouldNotify(candidate, in: context))
        context.isDoNotDisturb = false
        context.ignoredUserIds.insert("@peer:x")
        #expect(!NotificationDecision.shouldNotify(candidate, in: context))
    }

    @Test func statusFailureDoesNotClaimSuccessWithoutSession() async {
        let store = MatrixStore()
        await store.setMyStatus(.dnd, message: "Focus")
        #expect(store.myStatus == .online)
        #expect(store.myStatusMessage == nil)
        #expect(store.errorMessage != nil)
    }

    @Test func simulatedPasswordEmailAndReauthenticationRequests() async throws {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [AccountFeaturesProtocol.self]
        let client = try #require(SupabaseAuthClient(
            info: ["MoodSupabaseURL": "https://account.invalid", "MoodSupabaseAnonKey": "synthetic-public-key"],
            urlSession: URLSession(configuration: config),
            initialSession: SupabaseSession(accessToken: "synthetic-token", refreshToken: "synthetic-refresh", expiresIn: 3600,
                                            user: SupabaseUser(id: UUID(), email: "old@example.org", userMetadata: nil))))
        let user = try await client.updateAccount(password: "synthetic-password", nonce: "synthetic-nonce")
        #expect(user.email == "old@example.org")
        let pendingEmail = try await client.updateAccount(email: "new@example.org")
        #expect(pendingEmail.email == "old@example.org")
        try await client.requestReauthentication()
    }
}

private final class AccountFeaturesProtocol: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        var body = request.httpBody
        if body == nil, let stream = request.httpBodyStream {
            stream.open()
            defer { stream.close() }
            var bytes = [UInt8](repeating: 0, count: 1024)
            var data = Data()
            while stream.hasBytesAvailable {
                let count = stream.read(&bytes, maxLength: bytes.count)
                if count <= 0 { break }
                data.append(contentsOf: bytes.prefix(count))
            }
            body = data
        }
        let json = body.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: String] }
        let validBody = json == ["password": "synthetic-password", "nonce": "synthetic-nonce"]
            || json == ["email": "new@example.org"]
        let valid = request.url?.host == "account.invalid"
            && request.value(forHTTPHeaderField: "Authorization") == "Bearer synthetic-token"
            && ((request.url?.path == "/auth/v1/user" && request.httpMethod == "PUT" && validBody)
                || (request.url?.path == "/auth/v1/reauthenticate" && request.httpMethod == "GET"))
        let response = HTTPURLResponse(url: request.url!, statusCode: valid ? 200 : 400, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(#"{"id":"00000000-0000-0000-0000-000000000001","email":"old@example.org"}"#.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
