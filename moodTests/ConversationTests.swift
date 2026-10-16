import Foundation
import Testing
@testable import mood

@MainActor
struct ConversationTests {
    private func event(_ json: String) throws -> MatrixEvent {
        try JSONDecoder().decode(MatrixEvent.self, from: Data(json.utf8))
    }

    @Test func threadRelationsNeverConfuseOrdinaryRepliesOrEdits() throws {
        let thread = try event(#"{"type":"m.room.message","content":{"m.relates_to":{"rel_type":"m.thread","event_id":"$root","m.in_reply_to":{"event_id":"$previous"}}}}"#)
        #expect(ConversationPolicy.threadRoot(thread) == "$root")
        for relation in [#"{"m.in_reply_to":{"event_id":"$root"}}"#, #"{"rel_type":"m.replace","event_id":"$root"}"#] {
            let other = try event("{\"type\":\"m.room.message\",\"content\":{\"m.relates_to\":\(relation)}}")
            #expect(ConversationPolicy.threadRoot(other) == nil)
        }
    }

    @Test func messageLinksRoundTripReservedCharactersAndRejectOtherActions() throws {
        let room = "!room/a:b.example"
        let id = "$event/#?+%"
        let url = try #require(URL(string: ConversationPolicy.link(room: room, event: id)))
        #expect(ConversationPolicy.target(url)?.room == room)
        #expect(ConversationPolicy.target(url)?.event == id)
        for value in ["https://example.org/message/!r/$e", "mood://auth-callback/!r/$e", "mood://message/!r", "mood://message/!r/$e/extra", "mood://message/!r/$e?token=x", "mood://message/@r/$e"] {
            #expect(ConversationPolicy.target(try #require(URL(string: value))) == nil)
        }
    }

    @Test func forwardingCopiesVisibleTextWithoutBorrowingTheOriginalIdentity() throws {
        let source = MockData.messages(for: MockData.servers[0].categories[0].channels[0])[0]
        let text = try #require(ConversationPolicy.forwardedText(source))
        #expect(text == "Transféré · \(source.sender.displayName)\n\(source.content)")
        var file = source
        file.attachments = [MessageAttachment(id: UUID(), type: .file, name: "private.txt", previewEmoji: "")]
        #expect(ConversationPolicy.forwardedText(file) == nil)
        var system = source
        system.isSystemMessage = true
        #expect(ConversationPolicy.forwardedText(system) == nil)
        #expect(ConversationPolicy.forwardedText(source.replacing(content: "  ")) == nil)
    }

    @Test func groupingBreaksAtMidnightAtSystemLinesAndAtReplies() {
        let user = MockData.users[0]
        let midnight = Calendar.current.startOfDay(for: Date())
        let a = ChatMessage(id: UUID(), sender: user, content: "a", timestamp: midnight.addingTimeInterval(-10), isGrouped: false)
        let b = ChatMessage(id: UUID(), sender: user, content: "b", timestamp: midnight.addingTimeInterval(10), isGrouped: false)
        #expect(!ConversationPolicy.canGroup(a,b))
        let c = ChatMessage(id: UUID(), sender: user, content: "c", timestamp: midnight.addingTimeInterval(20), isGrouped: false)
        #expect(ConversationPolicy.canGroup(b,c))
        var system = b
        system.isSystemMessage = true
        #expect(!ConversationPolicy.canGroup(system,c))
        var reply = c
        reply.replyTo = ReplyRef(sender: user, content: "b")
        #expect(!ConversationPolicy.canGroup(b,reply))
    }

    @Test func systemEventsDescribeActualChangesWithoutProtocolJargon() throws {
        let joined = try event(#"{"type":"m.room.member","content":{"membership":"join"}}"#)
        #expect(ConversationPolicy.systemText(joined, actor: "Alice", member: "Bob") == "Bob a rejoint la conversation.")
        let renamed = try event(#"{"type":"m.room.member","content":{"membership":"join","displayname":"Bob"},"unsigned":{"prev_content":{"membership":"join","displayname":"Bobby"}}}"#)
        #expect(ConversationPolicy.systemText(renamed, actor: "Bob", member: "Bob") == "Bob a changé de nom.")
        let pinned = try event(#"{"type":"m.room.pinned_events","content":{"pinned":["$a"]},"unsigned":{"prev_content":{"pinned":[]}}}"#)
        #expect(ConversationPolicy.systemText(pinned, actor: "Alice", member: "Bob") == "Alice a épinglé un message.")
    }

    @Test func threadPageDecodesCursorAndRoomAccountDataPreservesUnread() throws {
        let page = try JSONDecoder().decode(ConversationThreadPage.self, from: Data(#"{"chunk":[],"next_batch":"cursor/+"}"#.utf8))
        #expect(page.nextBatch == "cursor/+")
        let sync = try JSONDecoder().decode(JoinedRoom.self, from: Data(#"{"account_data":{"events":[{"type":"m.marked_unread","content":{"unread":true}}]},"unread_thread_notifications":{"$root":{"notification_count":3}}}"#.utf8))
        #expect(sync.accountData?.events?.first?.content?["unread"]?.boolValue == true)
        #expect(sync.unreadThreadNotifications?["$root"]?.notificationCount == 3)
    }

    @Test func searchFiltersUseResolvedMembersAndChannels() {
        let server = MockData.servers[0]
        let channel = server.categories[0].channels[0]
        let user = server.members[0]
        let parsed = SearchQueryParser.parse("dans:#\(channel.name) de:\(user.username) aiguille", members: server.members, channels: server.categories.flatMap(\.channels))
        #expect(parsed.term == "aiguille")
        #expect(parsed.channels.map(\.id) == [channel.id])
        #expect(parsed.senders.map(\.id) == [user.id])
    }
}

@MainActor
struct ConversationTransportTests {
    @Test func unreadStableFlagWinsLegacyAndFalseDoesNotMeanMissing() throws {
        func flag(_ type: String, _ value: Bool) throws -> MatrixEvent {
            try JSONDecoder().decode(MatrixEvent.self, from: JSONSerialization.data(withJSONObject: ["type":type,"content":["unread":value]]))
        }
        let legacy = try flag("com.famedly.marked_unread", true)
        let stable = try flag("m.marked_unread", false)
        #expect(ConversationPolicy.markedUnread([legacy]) == true)
        #expect(ConversationPolicy.markedUnread([stable,legacy]) == false)
        #expect(ConversationPolicy.markedUnread([]) == nil)
    }

    @Test func encodedThreadCursorUnreadAndReceiptUseAuthenticatedContracts() async throws {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [ConversationProtocol.self]
        let client = MatrixClient(homeserver: "https://conversation.invalid", conversationSession: URLSession(configuration: config))
        client.setAccessToken("synthetic-n1-value")
        let page = try await client.conversationThreads(roomId: "!r/x:local", from: "cursor/+?&")
        #expect(page.chunk.isEmpty)
        try await client.conversationMarkedUnread(userId: "@user:local", roomId: "!r/x:local", unread: true)
        try await client.conversationThreadRead(roomId: "!r/x:local", root: "$root", eventId: "$reply", isPrivate: true)
    }
}

private final class ConversationProtocol: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let components = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)!
        var valid = request.url?.host == "conversation.invalid" && request.value(forHTTPHeaderField: "Authorization") == "Bearer synthetic-n1-value"
        let path = components.percentEncodedPath
        var body = #"{}"#
        if path.hasSuffix("/threads") {
            valid = valid && request.httpMethod == "GET" && path.contains("%2F")
                && components.queryItems?.first(where: { $0.name == "from" })?.value == "cursor/+?&"
            body = #"{"chunk":[]}"#
        } else {
            var data = request.httpBody ?? Data()
            if let stream = request.httpBodyStream {
                stream.open(); defer { stream.close() }
                var bytes = [UInt8](repeating: 0, count: 2048)
                while stream.hasBytesAvailable {
                    let count = stream.read(&bytes, maxLength: bytes.count)
                    if count <= 0 { break }; data.append(contentsOf: bytes.prefix(count))
                }
            }
            let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
            if path.hasSuffix("/m.marked_unread") { valid = valid && request.httpMethod == "PUT" && json?["unread"] as? Bool == true }
            else { valid = valid && request.httpMethod == "POST" && path.contains("/receipt/m.read.private/") && json?["thread_id"] as? String == "$root" }
        }
        let response = HTTPURLResponse(url: request.url!, statusCode: valid ? 200 : 400, httpVersion: nil, headerFields: nil)!
        self.client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        self.client?.urlProtocol(self, didLoad: Data(body.utf8))
        self.client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
