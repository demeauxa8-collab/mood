import Foundation
import Testing
@testable import mood

@MainActor
struct MessagingServerTests {
    @Test func invitationsAcceptAllSupportedFormsAndRejectUnrelatedLinks() {
        for value in ["ABCD2345", "abcd2345", " mood://invite/abcd2345 ", "#abcd2345:mood.local", "https://matrix.to/#/%23abcd2345%3Amood.local?via=mood.local"] {
            #expect(MoodInvite.reference(value) == "#abcd2345:mood.local")
        }
        for value in ["https://evil.example/matrix.to/#/#abcd2345:mood.local", "mood://auth-callback/abcd2345", "abc", "#:mood.local", "#room:", "abcd 234", "https://example.org"] {
            #expect(MoodInvite.reference(value) == nil)
        }
        #expect(MoodInvite.reference("!room:mood.local") == "!room:mood.local")
        for _ in 0..<100 {
            let code = MoodInvite.makeCode()
            #expect(code.count == 8)
            #expect(MoodInvite.reference(code) == "#\(code):mood.local")
        }
    }

    @Test func restrictedMembershipIsScopedToOnlyTheParentSpace() throws {
        let rule = MessagingServerPolicy.restricted(spaceId: "!parent:mood.local")
        let data = try JSONSerialization.data(withJSONObject: rule)
        let decoded = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(decoded["join_rule"] as? String == "restricted")
        let allow = try #require(decoded["allow"] as? [[String: String]])
        #expect(allow == [["type": "m.room_membership", "room_id": "!parent:mood.local"]])
    }

    @Test func numericChannelOrderSurvivesLexicalMatrixSorting() {
        let positions = [100, 2, 10, 0, 1]
        #expect(positions.sorted { MessagingServerPolicy.order($0) < MessagingServerPolicy.order($1) } == [0, 1, 2, 10, 100])
    }

    @Test func mentionsUseUnambiguousIdsAndIgnoreEmailOrCompletedTokens() {
        let members = [MentionCandidate(userId: "@alice:mood.local", displayName: "Alice Martin"), MentionCandidate(userId: "@alix:mood.local", displayName: "Alix")]
        #expect(MessagingServerPolicy.mentions("Salut @ali", members: members).count == 2)
        #expect(MessagingServerPolicy.completing("Salut @ali", with: members[0]) == "Salut @alice:mood.local ")
        #expect(MessagingServerPolicy.mentions("alice@example.org", members: members).isEmpty)
        #expect(MessagingServerPolicy.mentions("@alice ", members: members).isEmpty)
        #expect(MessagingServerPolicy.mentions("", members: members).isEmpty)
        let result = MessageFormatter.format(MessagingServerPolicy.completing("Salut @ali", with: members[0]), members: members)
        #expect(result.mentionedUserIds == ["@alice:mood.local"])
    }

    @Test func upArrowNeverEditsAnAttachmentOrAnotherPersonsMessage() {
        var own = MockData.messages(for: MockData.servers[0].categories[0].channels[0])[0]
        own.isOwn = true
        own = own.replacing(eventId: "$own")
        var other = own
        other.isOwn = false
        #expect(MessagingServerPolicy.lastEditable([own, other], draft: "") == own.id)
        #expect(MessagingServerPolicy.lastEditable([own], draft: "unsent draft") == nil)
        let file = MessageAttachment(id: UUID(), type: .file, name: "a.txt", previewEmoji: "📎")
        #expect(MessagingServerPolicy.lastEditable([own.replacing(attachments: [file])], draft: "") == nil)
    }

    @Test func roleLevelsKeepModeratorsBelowAdministrators() {
        #expect(MessagingServerPolicy.roleLevel(.owner) == 100)
        #expect(MessagingServerPolicy.roleLevel(.admin) > MessagingServerPolicy.roleLevel(.moderator))
        #expect(MessagingServerPolicy.roleLevel(.member) == 0)
    }
}
