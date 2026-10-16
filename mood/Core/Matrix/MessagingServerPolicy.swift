import Foundation

nonisolated enum MoodInvite {
    static let alphabet = Array("abcdefghjkmnpqrstuvwxyz23456789")
    static func makeCode() -> String { String((0..<8).map { _ in alphabet.randomElement()! }) }
    static func reference(_ input: String) -> String? {
        var text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        if let url = URL(string: text), url.scheme == "mood", url.host == "invite" {
            text = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        } else if text.hasPrefix("https://matrix.to/#/") {
            text = String(text.dropFirst("https://matrix.to/#/".count)).components(separatedBy: "?")[0]
        }
        text = text.removingPercentEncoding ?? text
        if text.count == 8, text.lowercased().allSatisfy({ alphabet.contains($0) }) { return "#\(text.lowercased()):mood.local" }
        guard text.first == "#" || text.first == "!", text.contains(":"),
              !text.contains(where: { $0.isWhitespace }), !text.contains("/") else { return nil }
        let parts = text.dropFirst().split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
        guard parts.count == 2, !parts[0].isEmpty, !parts[1].isEmpty else { return nil }
        return text
    }
}

nonisolated enum MessagingServerPolicy {
    static func restricted(spaceId: String) -> [String: Any] {
        ["join_rule": "restricted", "allow": [["type": "m.room_membership", "room_id": spaceId]]]
    }
    static func roleLevel(_ role: ServerRole) -> Int {
        switch role { case .owner: 100; case .admin: 75; case .moderator: 50; case .member: 0 }
    }
    static func lastEditable(_ messages: [ChatMessage], draft: String) -> UUID? {
        guard draft.isEmpty else { return nil }
        return messages.last { $0.isOwn && $0.eventId != nil && $0.attachments.isEmpty && !$0.isSystemMessage }?.id
    }
    static func order(_ index: Int) -> String { String(format: "%08d", max(0, index)) }
    static func mentionQuery(_ text: String) -> String? {
        guard let token = text.split(whereSeparator: { $0.isWhitespace }).last,
              token.first == "@", text.last?.isWhitespace == false else { return nil }
        return String(token.dropFirst())
    }
    static func mentions(_ text: String, members: [MentionCandidate]) -> [MentionCandidate] {
        guard let query = mentionQuery(text) else { return [] }
        return Array(members.filter { query.isEmpty || $0.displayName.localizedCaseInsensitiveContains(query) || $0.localpart.localizedCaseInsensitiveContains(query) }.sorted { $0.userId < $1.userId }.prefix(8))
    }
    static func completing(_ text: String, with member: MentionCandidate) -> String {
        guard let at = text.lastIndex(of: "@"), mentionQuery(text) != nil else { return text }
        return String(text[..<at]) + member.userId + " "
    }
}
