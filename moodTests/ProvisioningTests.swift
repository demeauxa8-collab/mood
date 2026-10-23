import Foundation
import Testing
@testable import mood

@MainActor
struct ProvisioningTests {
    @Test func decodeContract() throws {
        // Deliberately synthetic credentials; never contacts an online service.
        let data = Data(#"{"homeserver":"https://mood.invalid:8443","user_id":"@m123456789abc:mood.local","access_token":"synthetic-test-value","device_id":"MOOD123456789ABC","created":true}"#.utf8)
        let session = try JSONDecoder().decode(MoodMatrixSession.self, from: data)
        #expect(session.homeserver == "https://mood.invalid:8443")
        #expect(session.userId == "@m123456789abc:mood.local")
        #expect(session.deviceId == "MOOD123456789ABC")
        #expect(session.created)
    }

    @Test func rejectIncompleteContract() {
        #expect(throws: DecodingError.self) {
            _ = try JSONDecoder().decode(MoodMatrixSession.self, from: Data(#"{"created":false}"#.utf8))
        }
    }

    @Test func safeFrenchErrors() {
        #expect(MoodProvisioningError.http(401).errorDescription == "Ta session Mood a expiré. Reconnecte-toi.")
        #expect(MoodProvisioningError.http(503).errorDescription == "Le serveur Mood est injoignable")
        #expect(MoodProvisioningError.http(500).errorDescription == "Impossible de connecter ton compte Mood. Réessaie dans un instant.")
    }

    @Test func stableDeviceAndIndependentInstall() throws {
        let suite = "MoodProvisioningTests." + UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let first = MoodDevice.identifier(defaults: defaults)
        #expect(first.count == 16)
        #expect(first.hasPrefix("MOOD"))
        #expect(first.dropFirst(4).allSatisfy { $0.isHexDigit })
        #expect(MoodDevice.identifier(defaults: defaults) == first)
        defaults.removeObject(forKey: "mood.matrix.device_id")
        #expect(MoodDevice.identifier(defaults: defaults) != first)
    }
}

private final class ProvisioningProtocol: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let valid = request.url?.path == "/functions/v1/matrix-session"
            && request.httpMethod == "POST"
            && request.value(forHTTPHeaderField: "Authorization") == "Bearer synthetic-test-value"
        let response = HTTPURLResponse(url: request.url!, statusCode: valid ? 200 : 500, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(#"{"homeserver":"https://mood.invalid:8443","user_id":"@m123456789abc:mood.local","access_token":"synthetic-test-value","device_id":"MOOD123456789ABC","created":false}"#.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

extension ProvisioningTests {
    @Test func simulatedFunctionRequest() async throws {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [ProvisioningProtocol.self]
        let client = try #require(SupabaseAuthClient(info: ["MoodSupabaseURL": "https://mood.invalid", "MoodSupabaseAnonKey": "synthetic-public-key"], urlSession: URLSession(configuration: config), initialSession: SupabaseSession(accessToken: "synthetic-test-value", refreshToken: "synthetic-refresh", expiresIn: 3600, user: SupabaseUser(id: UUID(), email: nil, userMetadata: nil))))
        // Seed only the client's in-memory session; avoid persisting test credentials.
        let result = try await client.matrixSession(deviceId: "MOOD123456789ABC", deviceName: "Mood · Mac")
        #expect(!result.created)
        #expect(result.deviceId == "MOOD123456789ABC")
    }
}
