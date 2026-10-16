import Foundation
import Testing
@testable import mood

private final class PasswordResetProtocol: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        var bodyData = request.httpBody ?? Data()
        if let stream = request.httpBodyStream {
            stream.open(); defer { stream.close() }
            var buffer = [UInt8](repeating: 0, count: 1024)
            while stream.hasBytesAvailable {
                let count = stream.read(&buffer, maxLength: buffer.count)
                if count <= 0 { break }
                bodyData.append(contentsOf: buffer.prefix(count))
            }
        }
        let body = (try? JSONSerialization.jsonObject(with: bodyData)) as? [String: String] ?? [:]
        var valid = request.value(forHTTPHeaderField: "apikey") == "synthetic-public-key"
        let user = #"{"id":"00000000-0000-0000-0000-000000000001","email":"demo@example.invalid"}"#
        var payload = "{}"
        var status = 200
        switch request.url?.path {
        case "/auth/v1/recover":
            valid = valid && request.httpMethod == "POST" && body == ["email": "demo@example.invalid"]
                && URLComponents(url: request.url!, resolvingAgainstBaseURL: true)?.queryItems?.first?.value == "mood://auth-callback"
                && request.value(forHTTPHeaderField: "Authorization") == nil
        case "/auth/v1/verify":
            valid = valid && request.httpMethod == "POST" && body["email"] == "demo@example.invalid"
                && body["token"] == "123456" && ["signup", "recovery"].contains(body["type"] ?? "") && body.count == 3
            if body["token"] == "000000" {
                status = 403; valid = true
            }
            payload = "{\"access_token\":\"synthetic-access\",\"refresh_token\":\"synthetic-refresh\",\"expires_in\":3600,\"user\":\(user)}"
        case "/auth/v1/user":
            valid = valid && request.httpMethod == "PUT" && body == ["password": "synthetic-password"]
                && request.value(forHTTPHeaderField: "Authorization") == "Bearer synthetic-access"
            payload = user
        default: valid = false
        }
        if status == 403 { payload = #"{"error_code":"otp_expired","msg":"Token has expired or is invalid"}"# }
        let response = HTTPURLResponse(url: request.url!, statusCode: valid ? status : 400, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(payload.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

@MainActor
struct PasswordResetTests {
    private func makeClient() throws -> SupabaseAuthClient {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [PasswordResetProtocol.self]
        return try #require(SupabaseAuthClient(info: ["MoodSupabaseURL": "https://mood.invalid", "MoodSupabaseAnonKey": "synthetic-public-key"],
            urlSession: URLSession(configuration: config), persistsSession: false))
    }

    @Test func recoveryRequestAndPasswordUpdate() async throws {
        let client = try makeClient()
        try await client.requestPasswordRecovery(email: "demo@example.invalid")
        let session = try await client.verifyEmailCode(email: "demo@example.invalid", token: "123456", type: .recovery)
        #expect(try await client.restoreSession() == nil)
        let updated = try await client.resetPassword("synthetic-password", recoverySession: session)
        #expect(updated.user.email == "demo@example.invalid")
        #expect(updated.accessToken == session.accessToken)
    }

    @Test func signupVerificationRequest() async throws {
        let session = try await makeClient().verifyEmailCode(email: "demo@example.invalid", token: "123456", type: .signup)
        #expect(session.accessToken == "synthetic-access")
    }

    @Test func invalidCodeMapsHTTPErrorAndDoesNotSignIn() async throws {
        let store = AccountStore(client: try makeClient())
        store.beginPasswordRecovery()
        try await store.sendRecoveryCode(email: "demo@example.invalid")
        do {
            try await store.finishPasswordRecovery(code: "000000", password: "synthetic-password", confirmation: "synthetic-password")
            Issue.record("Expired code unexpectedly accepted")
        } catch { #expect(error.localizedDescription.contains("invalide ou expiré")) }
        #expect(!store.isSignedIn)
        #expect(!store.isLoading)
        #expect(store.isRecoveringPassword)
        try await store.finishPasswordRecovery(code: "123456", password: "synthetic-password", confirmation: "synthetic-password")
        #expect(store.isSignedIn)
        #expect(!store.isRecoveringPassword)
        #expect(!store.matrixReady)
    }

    @Test func validation() {
        #expect(AccountValidation.isValidEmailCode("012345"))
        for value in ["", "12345", "1234567", "123 45", "abcdef", "１２３４５６", "123456\n"] {
            #expect(!AccountValidation.isValidEmailCode(value))
        }
        #expect(!AccountValidation.isValidPassword("1234567"))
        #expect(AccountValidation.isValidPassword("12345678"))
    }

    @Test func frenchErrors() {
        #expect(SupabaseAuthClient.frenchMessage(for: "", code: "otp_expired").contains("invalide ou expiré"))
        #expect(SupabaseAuthClient.frenchMessage(for: "", status: 429).contains("Trop de tentatives"))
        #expect(SupabaseAuthClient.frenchMessage(for: "", code: "weak_password").contains("8 caractères"))
        #expect(SupabaseAuthClient.frenchMessage(for: "", code: "same_password").contains("différent"))
        #expect(SupabaseAuthClient.frenchMessage(for: "", code: "bad_jwt").contains("expiré"))
        #expect(SupabaseAuthClient.frenchMessage(for: "Invalid OTP").contains("invalide"))
    }

    @Test func recoveryCallbackRouting() throws {
        #expect(SupabaseAuthClient.isRecoveryCallback(try #require(URL(string: "mood://auth-callback#type=recovery&access_token=synthetic"))))
        #expect(!SupabaseAuthClient.isRecoveryCallback(try #require(URL(string: "mood://auth-callback#type=signup"))))
        #expect(!SupabaseAuthClient.isRecoveryCallback(try #require(URL(string: "https://example.invalid/#type=recovery"))))
    }
}
