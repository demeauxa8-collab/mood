import Foundation
import Testing
@testable import mood

@MainActor
struct FinishBasicsTests {
    private func event(_ json: String) throws -> MatrixEvent {
        try JSONDecoder().decode(MatrixEvent.self, from: Data(json.utf8))
    }

    @Test func usernameValidationAndConflictMessages() {
        #expect(MoodUsername.isValid("augustin.2"))
        for value in ["a", "UPPER", "a b", "a:b", "a..b", String(repeating: "a", count: 33)] {
            #expect(!MoodUsername.isValid(value))
        }
        #expect(MoodUsername.updateError(status: 409, code: nil) == "Ce nom d'utilisateur est déjà pris")
        #expect(MoodUsername.updateError(status: 400, code: "23505") == "Ce nom d'utilisateur est déjà pris")
        #expect(MoodUsername.updateError(status: 400, code: "23514") == MoodUsername.rule)
        #expect(MoodUsername.updateError(status: 500, code: nil) == nil)
    }

    @Test func rejectsInvalidUsernameBeforeRequest() async {
        let store = AccountStore()
        do { try await store.setUsername("Invalid Handle"); Issue.record("Must reject before networking") }
        catch { #expect(error.localizedDescription == MoodUsername.rule) }
    }

    @Test func directRepairRequiresTwoJoinedMembersAndEvidence() throws {
        let me = try event(#"{"type":"m.room.member","state_key":"@me:x","content":{"membership":"join"}}"#)
        let peer = try event(#"{"type":"m.room.member","state_key":"@peer:x","content":{"membership":"join","is_direct":true}}"#)
        let third = try event(#"{"type":"m.room.member","state_key":"@third:x","content":{"membership":"join"}}"#)
        #expect(FinishBasicsPolicy.directPeer(me: "@me:x", members: [me, peer], evidence: [peer], isSpace: false) == "@peer:x")
        #expect(FinishBasicsPolicy.directPeer(me: "@me:x", members: [me, peer], evidence: [], isSpace: false) == nil)
        #expect(FinishBasicsPolicy.directPeer(me: "@me:x", members: [me, peer, third], evidence: [peer], isSpace: false) == nil)
        #expect(FinishBasicsPolicy.directPeer(me: "@me:x", members: [peer], evidence: [peer], isSpace: false) == nil)
        #expect(FinishBasicsPolicy.directPeer(me: "@me:x", members: [me, peer], evidence: [peer], isSpace: true) == nil)
    }

    @Test func directRepairUsesOwnOldInvitation() throws {
        let members = try [event(#"{"type":"m.room.member","state_key":"@me:x","content":{"membership":"join"}}"#),
                           event(#"{"type":"m.room.member","state_key":"@peer:x","content":{"membership":"join"}}"#)]
        let invite = try event(#"{"type":"m.room.member","state_key":"@me:x","content":{"membership":"invite","is_direct":true}}"#)
        let otherInvite = try event(#"{"type":"m.room.member","state_key":"@other:x","content":{"membership":"invite","is_direct":true}}"#)
        #expect(FinishBasicsPolicy.directPeer(me: "@me:x", members: members, evidence: [invite], isSpace: false) == "@peer:x")
        #expect(FinishBasicsPolicy.directPeer(me: "@me:x", members: members, evidence: [otherInvite], isSpace: false) == nil)
    }

    @Test func structuredAndLegacyMentions() throws {
        for body in [#"{"body":"Hello","m.mentions":{"user_ids":["@me:x"]}}"#,
                     #"{"body":"Hello","m.mentions":{"room":true}}"#,
                     #"{"body":"Salut @room !"}"#, #"{"body":"Salut Augustin !"}"#] {
            let message = try event("{\"type\":\"m.room.message\",\"sender\":\"@peer:x\",\"content\":\(body)}")
            #expect(FinishBasicsPolicy.isMention(message, me: "@me:x", names: ["Augustin"], ignored: []))
            #expect(!FinishBasicsPolicy.isMention(message, me: "@me:x", names: ["Augustin"], ignored: ["@peer:x"]))
        }
        for json in [#"{"type":"m.room.message","sender":"@me:x","content":{"body":"@room"}}"#,
                     #"{"type":"m.room.message","sender":"@peer:x","content":{"body":"Augustine"}}"#,
                     #"{"type":"m.room.message","sender":"@peer:x","content":{"body":"@room","m.mentions":{}}}"#,
                     #"{"type":"m.room.message","sender":"@peer:x","content":{"body":"> <@me:x> Augustin\n\nBonjour"}}"#,
                     #"{"type":"m.room.message","sender":"@peer:x","content":{"body":"@room"},"unsigned":{"redacted_because":{}}}"#] {
            #expect(!FinishBasicsPolicy.isMention(try event(json), me: "@me:x", names: ["Augustin"], ignored: []))
        }
    }
}

extension FinishBasicsTests {
    @Test func editsAndRedactionsChangeMentionClassification() throws {
        let original = try event(#"{"type":"m.room.message","event_id":"$one","sender":"@peer:x","origin_server_ts":1,"content":{"body":"@room"}}"#)
        let edit = try event(#"{"type":"m.room.message","event_id":"$edit","sender":"@peer:x","origin_server_ts":2,"content":{"body":"* Hello","m.relates_to":{"rel_type":"m.replace","event_id":"$one"},"m.new_content":{"body":"Hello","m.mentions":{}}}}"#)
        let effective = FinishBasicsPolicy.effectiveMessages([original, edit])
        #expect(effective.count == 1)
        #expect(!FinishBasicsPolicy.isMention(try #require(effective.first), me: "@me:x", names: [], ignored: []))
        let redaction = try event(#"{"type":"m.room.redaction","event_id":"$redact","sender":"@peer:x","redacts":"$one","content":{}}"#)
        #expect(FinishBasicsPolicy.effectiveMessages([original, redaction]).isEmpty)
        // The same raw events survive a cache encode/decode round trip.
        let restored = try JSONDecoder().decode([MatrixEvent].self, from: JSONEncoder().encode([original, edit]))
        #expect(!FinishBasicsPolicy.isMention(try #require(FinishBasicsPolicy.effectiveMessages(restored).first), me: "@me:x", names: [], ignored: []))
    }

    @Test func syntheticUsernamePatchAndConflict() async throws {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [UsernameProtocol.self]
        let client = try #require(SupabaseAuthClient(info: ["MoodSupabaseURL": "https://mood.invalid", "MoodSupabaseAnonKey": "synthetic-public-key"],
            urlSession: URLSession(configuration: config),
            initialSession: SupabaseSession(accessToken: "synthetic-test-value", refreshToken: "synthetic-refresh", expiresIn: 3600,
                user: SupabaseUser(id: UUID(), email: nil, userMetadata: nil)), persistsSession: false))
        try await client.setUsername("available")
        do { try await client.setUsername("taken"); Issue.record("Conflict must throw") }
        catch AccountError.usernameTaken {
            #expect(AccountError.usernameTaken.localizedDescription == "Ce nom d'utilisateur est déjà pris.")
        } catch {
            Issue.record("Expected a typed username conflict, received: \(error)")
        }
    }
}

/// Intercepts every request; .invalid and synthetic values can never reach a live account.
private final class UsernameProtocol: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let profile = #"[{"id":"00000000-0000-0000-0000-000000000001","username":"available"}]"#
        var status = 200
        var body = profile
        if request.httpMethod == "PATCH" {
            let data: Data
            if let payload = request.httpBody { data = payload }
            else if let stream = request.httpBodyStream {
                stream.open(); defer { stream.close() }
                var payload = Data()
                var buffer = [UInt8](repeating: 0, count: 512)
                while stream.hasBytesAvailable {
                    let count = stream.read(&buffer, maxLength: buffer.count)
                    if count <= 0 { break }
                    payload.append(contentsOf: buffer.prefix(count))
                }
                data = payload
            } else { data = Data() }
            let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: String]
            let valid = json?.count == 1 && json?["username"] != nil
                && request.url?.query == "id=eq.00000000-0000-0000-0000-000000000001"
                && request.value(forHTTPHeaderField: "Prefer") == "return=representation"
                && request.value(forHTTPHeaderField: "Authorization") == "Bearer synthetic-test-value"
            if !valid { status = 400; body = #"{"message":"Invalid patch"}"# }
            else if json?["username"] == "taken" { status = 409; body = #"{"code":"23505","message":"duplicate"}"# }
        }
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
