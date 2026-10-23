import Foundation

/// Pure protocol decisions shared by the conversation UI and its tests.
enum ConversationPolicy {
    static func threadRoot(_ event: MatrixEvent) -> String? {
        let relation = event.content?["m.relates_to"]?.dictValue
        guard relation?["rel_type"]?.stringValue == "m.thread" else { return nil }
        guard let root = relation?["event_id"]?.stringValue, root.hasPrefix("$"), root != event.eventId else { return nil }
        return root
    }

    static func link(room: String, event: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_.~"))
        return "mood://message/\(room.addingPercentEncoding(withAllowedCharacters: allowed)!)/\(event.addingPercentEncoding(withAllowedCharacters: allowed)!)"
    }

    static func target(_ url: URL) -> (room: String, event: String)? {
        guard url.scheme == "mood", url.host == "message", url.query == nil, url.fragment == nil else { return nil }
        let parts = URLComponents(url: url, resolvingAgainstBaseURL: false)?.percentEncodedPath.split(separator: "/").compactMap { String($0).removingPercentEncoding } ?? []
        guard parts.count == 2, parts[0].hasPrefix("!"), parts[1].hasPrefix("$"),
              !parts.contains(where: { $0.contains(where: { $0.isWhitespace || $0.isNewline }) }) else { return nil }
        return (parts[0], parts[1])
    }

    static func markedUnread(_ events: [MatrixEvent]) -> Bool? {
        let canonical = events.last { $0.type == "m.marked_unread" }
        let legacy = events.last { $0.type == "com.famedly.marked_unread" }
        return (canonical ?? legacy)?.content?["unread"]?.boolValue
    }

    static func forwardedText(_ message: ChatMessage) -> String? {
        guard !message.isSystemMessage, !message.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              message.attachments.isEmpty else { return nil }
        return "Transféré · \(message.sender.displayName)\n\(message.content)"
    }

    static func canGroup(_ previous: ChatMessage, _ message: ChatMessage) -> Bool {
        !previous.isSystemMessage && !message.isSystemMessage && message.replyTo == nil
            && previous.sender.id == message.sender.id
            && Calendar.current.isDate(previous.timestamp, inSameDayAs: message.timestamp)
            && (0..<300).contains(message.timestamp.timeIntervalSince(previous.timestamp))
    }

    static func systemText(_ event: MatrixEvent, actor: String, member: String) -> String? {
        switch event.type {
        case "m.room.member":
            switch event.content?["membership"]?.stringValue {
            case "join":
                if let previous = event.unsigned?.previousContent, previous["membership"]?.stringValue == "join" {
                    return previous["displayname"]?.stringValue != event.content?["displayname"]?.stringValue
                        ? "\(member) a changé de nom." : nil
                }
                return "\(member) a rejoint la conversation."
            case "leave": return "\(member) a quitté la conversation."
            case "ban": return "\(member) a été exclu de la conversation."
            default: return nil
            }
        case "m.room.name": return "\(actor) a renommé la conversation : \(event.content?["name"]?.stringValue ?? "sans nom")."
        case "m.room.topic": return "\(actor) a changé le sujet : \(event.content?["topic"]?.stringValue ?? "aucun sujet")."
        case "m.room.avatar": return "\(actor) a changé l’icône de la conversation."
        case "m.room.pinned_events":
            let old = Set(event.unsigned?.previousContent?["pinned"]?.arrayValue?.compactMap(\.stringValue) ?? [])
            let new = Set(event.content?["pinned"]?.arrayValue?.compactMap(\.stringValue) ?? [])
            return new.subtracting(old).isEmpty ? "\(actor) a retiré une épingle." : "\(actor) a épinglé un message."
        default: return nil
        }
    }
}
