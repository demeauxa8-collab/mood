import Foundation
import ImageIO
import Testing
import UIKit
@testable import mood

/// Every request is intercepted; unexpected routes fail instead of reaching a service.
private final class OnboardingAuthProtocol: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let user = #"{"id":"00000000-0000-0000-0000-000000000001","email":"demo@example.invalid"}"#
        let body = (request.httpBody ?? request.httpBodyStream.flatMap { stream -> Data? in
            stream.open(); defer { stream.close() }
            var data = Data()
            var buffer = [UInt8](repeating: 0, count: 1024)
            while stream.hasBytesAvailable {
                let count = stream.read(&buffer, maxLength: buffer.count)
                guard count > 0 else { break }
                data.append(contentsOf: buffer.prefix(count))
            }
            return data
        }).flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] } ?? [:]
        var status = 200
        let payload: String
        switch request.url?.path {
        case "/auth/v1/signup":
            if request.url?.host == "signup-rejected.invalid" {
                status = 400; payload = #"{"msg":"User already registered"}"#
            } else { payload = user }
        case "/auth/v1/verify":
            if body["token"] as? String != "123456" {
                status = 403; payload = #"{"error_code":"otp_expired","msg":"Token has expired"}"#
            } else {
                payload = "{\"access_token\":\"synthetic\",\"refresh_token\":\"synthetic\",\"expires_in\":3600,\"user\":\(user)}"
            }
        case "/rest/v1/profiles":
            if request.httpMethod == "PATCH", let name = body["username"] as? String, name.hasPrefix("collision_") {
                status = name == "collision_409" ? 409 : 400
                payload = name == "collision_409" ? "{}" : #"{"code":"23505","message":"duplicate key"}"#
            } else {
                payload = #"[{"id":"00000000-0000-0000-0000-000000000001","username":"demo","matrix_user_id":"@self:mood.invalid"}]"#
            }
        case "/rest/v1/rpc/find_user_by_username":
            guard request.value(forHTTPHeaderField: "Authorization") == "Bearer synthetic",
                  body["p_username"] as? String != nil else {
                client?.urlProtocol(self, didFailWithError: URLError(.userAuthenticationRequired)); return
            }
            switch request.url?.host {
            case "offline.invalid":
                client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet)); return
            case "taken.invalid": payload = #"[{"matrix_user_id":"@someone:mood.invalid"}]"#
            case "own.invalid": payload = #"[{"matrix_user_id":"@self:mood.invalid"}]"#
            default: payload = "[]"
            }
        case "/auth/v1/resend":
            if request.url?.host == "rate-limited.invalid" {
                status = 429; payload = #"{"error_code":"over_email_send_rate_limit","msg":"Too many requests"}"#
            } else { payload = "{}" }
        case "/auth/v1/logout": payload = "{}"
        default:
            client?.urlProtocol(self, didFailWithError: URLError(.unsupportedURL))
            return
        }
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(payload.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

@MainActor
struct OnboardingStoreTests {
    private func client(host: String = "mood.invalid") throws -> SupabaseAuthClient {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [OnboardingAuthProtocol.self]
        return try #require(SupabaseAuthClient(
            info: ["MoodSupabaseURL": "https://\(host)", "MoodSupabaseAnonKey": "synthetic-public-key"],
            urlSession: URLSession(configuration: config), persistsSession: false
        ))
    }

    @Test func otpSignupAndConfirmationAfterStoreRecreation() async throws {
        let client = try client()
        let account = AccountStore(client: client)
        try await account.registerForOnboarding(email: "demo@example.invalid", password: "synthetic-password")
        #expect(!account.isSignedIn && account.pendingConfirmationEmail == "demo@example.invalid")
        let restored = AccountStore(client: client)
        try await restored.confirmSignup(code: "123456", email: "demo@example.invalid")
        #expect(restored.isSignedIn && !restored.matrixReady && restored.pendingConfirmationEmail == nil)
        #expect(restored.session?.user.id.uuidString == "00000000-0000-0000-0000-000000000001")
    }

    @Test func liveAdapterRequiresAuthenticationForUsernameLookup() async throws {
        let account = AccountStore(client: try client())
        let actions = OnboardingAdapter(services: .live(account: account, matrix: MatrixStore()))
        do {
            _ = try await actions.checkUsername("demo")
            Issue.record("Unauthenticated lookup unexpectedly accepted")
        } catch AccountError.notConfigured {
            #expect(!account.isSignedIn && account.pendingConfirmationEmail == nil)
        }
    }

    @Test func liveSignupConfirmsSessionBeforeChoosingUsername() async throws {
        let suite = "onboarding-store-tests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let account = AccountStore(client: try client())
        let actions = OnboardingAdapter(services: .live(account: account, matrix: MatrixStore()))
        let model = OnboardingModel(actions: actions, defaults: defaults)
        model.go(.email); model.email = "demo@example.invalid"; await model.submit()
        model.password = "synthetic-password"; await model.submit()
        #expect(model.step == .confirmation && !account.isSignedIn)
        model.code = "123456"; await model.submit()
        #expect(account.isSignedIn && model.accountID == account.session?.user.id.uuidString)
        #expect(model.step == .displayName && model.code.isEmpty && model.password.isEmpty)
        await model.skip(); #expect(model.step == .username)
        model.username = "alex"; await model.checkUsername(); await model.submit()
        #expect(model.step == .trust && model.networkError == nil)
    }

    @Test(arguments: ["collision_409", "collision_23505"])
    func liveUsernameConflictStaysUnderFieldAndCanRetry(_ name: String) async throws {
        let suite = "onboarding-conflict-tests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let account = AccountStore(client: try client())
        try await account.confirmSignup(code: "123456", email: "demo@example.invalid")
        let model = OnboardingModel(actions: OnboardingAdapter(services: .live(account: account, matrix: MatrixStore())),
                                    defaults: defaults, userID: account.session?.user.id.uuidString)
        model.username = name; await model.checkUsername()
        #expect(model.usernameAvailability == true)
        await model.submit()
        #expect(model.step == .username && model.usernameAvailability == false)
        #expect(model.fieldError == "Ce nom d'utilisateur est déjà pris." && model.networkError == nil)
        #expect(account.isSignedIn)
        model.username = "another"; await model.checkUsername(); await model.submit()
        #expect(model.step == .trust)
    }

    @Test(arguments: ["taken.invalid", "own.invalid", "mood.invalid"])
    func authenticatedLookupUsesServerAndAllowsOwnName(_ host: String) async throws {
        let account = AccountStore(client: try client(host: host))
        try await account.confirmSignup(code: "123456", email: "demo@example.invalid")
        let actions = OnboardingAdapter(services: .live(account: account, matrix: MatrixStore()))
        let available = try await actions.checkUsername("demo")
        #expect(available == (host != "taken.invalid"))
    }

    @Test func lookupNetworkFailureIsNotAnAvailableUsername() async throws {
        let account = AccountStore(client: try client(host: "offline.invalid"))
        try await account.confirmSignup(code: "123456", email: "demo@example.invalid")
        let actions = OnboardingAdapter(services: .live(account: account, matrix: MatrixStore()))
        do {
            _ = try await actions.checkUsername("demo")
            Issue.record("Offline lookup unexpectedly succeeded")
        } catch { #expect((error as? URLError)?.code == .notConnectedToInternet) }
    }

    @Test func incorrectCodeAndResendLimitsPropagateWithoutSession() async throws {
        let account = AccountStore(client: try client(host: "rate-limited.invalid"))
        let actions = OnboardingAdapter(services: .live(account: account, matrix: MatrixStore()))
        try await actions.register(email: "demo@example.invalid", password: "synthetic-password")
        do {
            _ = try await actions.confirmCode("000000")
            Issue.record("Incorrect code unexpectedly accepted")
        } catch { #expect(error.localizedDescription.contains("invalide ou expiré")) }
        #expect(!account.isSignedIn)
        do {
            try await actions.resendCode()
            Issue.record("Rate limited resend unexpectedly succeeded")
        } catch { #expect(error.localizedDescription.contains("Trop de tentatives")) }
    }

    @Test func signupPreservesExistingAccountErrorMessage() async throws {
        let account = AccountStore(client: try client(host: "signup-rejected.invalid"))
        let actions = OnboardingAdapter(services: .live(account: account, matrix: MatrixStore()))
        do {
            try await actions.register(email: "demo@example.invalid", password: "synthetic-password")
            Issue.record("Rejected signup unexpectedly accepted")
        } catch { #expect(error.localizedDescription == "Un compte existe déjà avec cette adresse : connecte-toi.") }
        #expect(!account.isSignedIn)
    }

    @Test func avatarRejectsInvalidAndOversizedBytes() {
        #expect(throws: (any Error).self) { try OnboardingAvatar.photo(Data([1, 2, 3])) }
        #expect(throws: (any Error).self) { try OnboardingAvatar.photo(Data(count: OnboardingAvatar.maximumInputBytes + 1)) }
        #expect(throws: (any Error).self) { try OnboardingAvatar.emoji("not an emoji") }
    }

    @Test func avatarBoundsPixelsAndReencodesToJPEG() throws {
        let input = UIGraphicsImageRenderer(size: CGSize(width: 1800, height: 900)).pngData { context in
            UIColor.red.setFill(); context.fill(CGRect(x: 0, y: 0, width: 1800, height: 900))
        }
        let data = try OnboardingAvatar.photo(input)
        let source = try #require(CGImageSourceCreateWithData(data as CFData, nil))
        #expect((CGImageSourceGetType(source) as String?) == "public.jpeg")
        let properties = try #require(CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any])
        #expect((properties[kCGImagePropertyPixelWidth as String] as? Int) == 512)
        #expect(properties[kCGImagePropertyGPSDictionary as String] == nil)
        for emoji in OnboardingAvatar.emojis {
            let png = try OnboardingAvatar.emoji(emoji)
            let image = try #require(UIImage(data: png))
            #expect(image.size == CGSize(width: 256, height: 256))
        }
    }
}
