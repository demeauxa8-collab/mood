import Foundation

// MARK: - Where a room lives in the UI

/// A Matrix room seen through Discord's eyes: a channel of a server, or a DM.
enum RoomDestination {
    case channel(Channel, MoodServer)
    case dm(DMConversation)

    /// "général" for a channel, the other person's name for a DM.
    var title: String {
        switch self {
        case .channel(let channel, _): return channel.name
        case .dm(let conversation): return conversation.participant.displayName
        }
    }

    var serverName: String? {
        if case .channel(_, let server) = self { return server.name }
        return nil
    }
}

// MARK: - Message search

/// What a header search covers: every channel of the current server, or the current DM.
enum SearchScope {
    case server(MoodServer)
    case dm(DMConversation)

    /// Channels the "dans:" filter can target; none in a DM.
    var channels: [Channel] {
        switch self {
        case .server(let server): return server.categories.flatMap(\.channels)
        case .dm: return []
        }
    }

    /// People the "de:" filter can target.
    func members(me: MoodUser?) -> [MoodUser] {
        switch self {
        case .server(let server): return server.members
        case .dm(let conversation): return [conversation.participant] + [me].compactMap { $0 }
        }
    }

    var placeholderName: String {
        switch self {
        case .server(let server): return server.name
        case .dm(let conversation): return conversation.participant.displayName
        }
    }
}

struct SearchHit: Identifiable {
    var id: String { eventId }
    let eventId: String
    let roomId: String
    let message: ChatMessage
    let destination: RoomDestination
}

struct SearchPage {
    var hits: [SearchHit]
    /// Approximate total across all pages, as reported by the homeserver.
    var total: Int?
    var nextBatch: String?
    /// Words the server matched, for highlighting.
    var highlights: [String]
    /// Encrypted channels left out because the homeserver cannot read them.
    var skippedEncryptedRooms: Int
    /// Every room in scope is encrypted: nothing can be searched.
    var isUnavailable: Bool

    static let unavailable = SearchPage(hits: [], total: 0, nextBatch: nil, highlights: [], skippedEncryptedRooms: 0, isUnavailable: true)
}

// MARK: - Jump to a message

/// Set when the user picks a search result or a mention: the open channel scrolls to the message
/// once it is on screen, then clears this.
struct JumpTarget: Equatable {
    let roomId: String
    let eventId: String
    let nonce = UUID()
}

// MARK: - Inbox

struct InboxMention: Identifiable {
    let id: String // event id
    let roomId: String
    let sender: MoodUser
    let text: String
    let timestamp: Date
    let isRead: Bool
    let destination: RoomDestination
}

// MARK: - Query parsing ("de:clara dans:général salut")

/// Discord-style filters typed straight into the search field. Pure logic, no UI.
struct SearchQueryParser {
    struct Result {
        /// What is sent as `search_term`, filters removed.
        var term: String
        var senders: [MoodUser]
        var channels: [Channel]

        var hasFilters: Bool { !senders.isEmpty || !channels.isEmpty }
    }

    static let senderPrefixes = ["de:", "from:"]
    static let channelPrefixes = ["dans:", "in:"]

    static func parse(_ raw: String, members: [MoodUser], channels: [Channel]) -> Result {
        var termWords: [String] = []
        var senders: [MoodUser] = []
        var chosenChannels: [Channel] = []

        for word in raw.split(whereSeparator: \.isWhitespace).map(String.init) {
            if let value = value(of: word, prefixes: senderPrefixes),
               let member = member(matching: value, in: members) {
                if !senders.contains(member) { senders.append(member) }
            } else if let value = value(of: word, prefixes: channelPrefixes),
                      let channel = channel(matching: value, in: channels) {
                if !chosenChannels.contains(channel) { chosenChannels.append(channel) }
            } else {
                termWords.append(word)
            }
        }
        return Result(term: termWords.joined(separator: " "), senders: senders, channels: chosenChannels)
    }

    /// "de:@clara" -> "clara"; nil when the word is not a filter or its value is empty.
    static func value(of word: String, prefixes: [String]) -> String? {
        let lowered = word.lowercased()
        guard let prefix = prefixes.first(where: { lowered.hasPrefix($0) }) else { return nil }
        var value = String(word.dropFirst(prefix.count))
        while let first = value.first, first == "@" || first == "#" { value.removeFirst() }
        return value.isEmpty ? nil : value
    }

    static func member(matching value: String, in members: [MoodUser]) -> MoodUser? {
        let wanted = value.lowercased()
        if let exact = members.first(where: { $0.username.lowercased() == wanted || squashed($0.displayName) == wanted }) {
            return exact
        }
        let partial = members.filter { $0.username.lowercased().hasPrefix(wanted) || squashed($0.displayName).hasPrefix(wanted) }
        return partial.count == 1 ? partial[0] : nil
    }

    static func channel(matching value: String, in channels: [Channel]) -> Channel? {
        let wanted = squashed(value)
        if let exact = channels.first(where: { squashed($0.name) == wanted }) { return exact }
        let partial = channels.filter { squashed($0.name).hasPrefix(wanted) }
        return partial.count == 1 ? partial[0] : nil
    }

    /// The text inserted when a suggestion is picked: one word, so it survives tokenizing.
    static func token(for channel: Channel) -> String { "dans:" + squashed(channel.name) }
    static func token(for member: MoodUser) -> String { "de:" + member.username }

    /// Lowercased, spaces turned into dashes: "Général Chat" -> "général-chat".
    static func squashed(_ name: String) -> String {
        name.lowercased().split(whereSeparator: \.isWhitespace).joined(separator: "-")
    }
}
