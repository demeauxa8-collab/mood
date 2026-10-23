import Foundation

// MARK: - Per-account preferences

/// What Mood tells the user (notifications) and what it tells other people (receipts, typing).
/// Stored per Matrix account in `UserDefaults`, so two accounts on one device keep their own choices.
struct AccountPreferences: Codable, Equatable {
    /// Local notifications for new messages. Off until the user turns it on, which is also when the
    /// system permission is requested.
    var notificationsEnabled = false
    var soundsEnabled = true
    /// Red badge on the app icon (mentions + unread DMs).
    var badgeEnabled = true
    /// Off: the read receipt is sent as `m.read.private`, so only this account's own devices see it.
    var sendsReadReceipts = true
    /// Off: the "est en train d'écrire…" indicator is never sent.
    var sendsTypingIndicator = true

    init() {}

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        notificationsEnabled = try container.decodeIfPresent(Bool.self, forKey: .notificationsEnabled) ?? false
        soundsEnabled = try container.decodeIfPresent(Bool.self, forKey: .soundsEnabled) ?? true
        badgeEnabled = try container.decodeIfPresent(Bool.self, forKey: .badgeEnabled) ?? true
        sendsReadReceipts = try container.decodeIfPresent(Bool.self, forKey: .sendsReadReceipts) ?? true
        sendsTypingIndicator = try container.decodeIfPresent(Bool.self, forKey: .sendsTypingIndicator) ?? true
    }

    static func storageKey(for userId: String) -> String { "mood.preferences.\(userId)" }

    static func load(userId: String, defaults: UserDefaults = .standard) -> AccountPreferences {
        guard let data = defaults.data(forKey: storageKey(for: userId)),
              let stored = try? JSONDecoder().decode(AccountPreferences.self, from: data) else {
            return AccountPreferences()
        }
        return stored
    }

    func save(userId: String, defaults: UserDefaults = .standard) {
        guard let data = try? JSONEncoder().encode(self) else { return }
        defaults.set(data, forKey: Self.storageKey(for: userId))
    }
}

// MARK: - What a notification says

/// A new message that might deserve a notification, already resolved to display strings.
struct NotificationCandidate: Equatable {
    let eventId: String
    let roomId: String
    let senderId: String
    let senderName: String
    /// Channel name; ignored for DMs.
    let roomName: String
    let isDirect: Bool
    let body: String
    let timestamp: Date

    /// "Clara" in a DM, "Clara · #général" in a server channel.
    var title: String {
        guard !isDirect, !roomName.isEmpty else { return senderName }
        return "\(senderName) · #\(roomName)"
    }

    static let previewLimit = 180

    /// The body, trimmed and shortened so a long message does not fill the banner.
    var preview: String {
        let text = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return "Nouveau message" }
        guard text.count > Self.previewLimit else { return text }
        return String(text.prefix(Self.previewLimit)).trimmingCharacters(in: .whitespaces) + "…"
    }

    /// Text shown for an event: the body of a text message, a short label for media.
    /// `nil` for events that never notify (edits, unknown types).
    static func previewText(eventType: String, msgtype: String?, body: String?, isEdit: Bool) -> String? {
        guard !isEdit else { return nil }
        switch eventType {
        case "m.room.encrypted":
            return "Nouveau message chiffré"
        case "m.room.message":
            let text = body ?? ""
            switch msgtype ?? "m.text" {
            case "m.text", "m.notice": return text
            case "m.emote": return text.isEmpty ? nil : "* \(text)"
            case "m.image": return "Image"
            case "m.video": return "Vidéo"
            case "m.audio": return "Message audio"
            case "m.file": return text.isEmpty ? "Fichier" : "Fichier : \(text)"
            default: return text.isEmpty ? nil : text
            }
        default:
            return nil
        }
    }
}

// MARK: - Should it notify?

/// Everything the decision depends on, so the rule is testable without a network or a notification center.
struct NotificationContext {
    var myUserId: String?
    var preferences: AccountPreferences
    var isDoNotDisturb = false
    var ignoredUserIds: Set<String>
    var mutedRoomIds: Set<String>
    /// Room currently on screen, if any.
    var openRoomId: String?
    var isAppActive: Bool
    /// Events already notified or already seen in a replay.
    var seenEventIds: Set<String>
    var now: Date

    /// Older messages are catch-up after a long offline period, not news.
    static let maxAge: TimeInterval = 15 * 60
    /// A burst (reconnect after sleep) shows the newest few, not fifty banners.
    static let maxPerSync = 5
}

enum NotificationDecision {

    static func shouldNotify(_ candidate: NotificationCandidate, in context: NotificationContext) -> Bool {
        guard !context.isDoNotDisturb else { return false }
        guard context.preferences.notificationsEnabled else { return false }
        guard let me = context.myUserId, candidate.senderId != me else { return false }
        guard !context.ignoredUserIds.contains(candidate.senderId) else { return false }
        guard !context.mutedRoomIds.contains(candidate.roomId) else { return false }
        guard !context.seenEventIds.contains(candidate.eventId) else { return false }
        // Reading the room right now: the message is already in front of the user.
        guard !(context.isAppActive && context.openRoomId == candidate.roomId) else { return false }
        guard context.now.timeIntervalSince(candidate.timestamp) <= NotificationContext.maxAge else { return false }
        return true
    }

    /// The candidates of one sync that should notify, oldest first, at most `NotificationContext.maxPerSync`
    /// (the newest ones when there are more).
    static func select(_ candidates: [NotificationCandidate], in context: NotificationContext) -> [NotificationCandidate] {
        let eligible = candidates
            .filter { shouldNotify($0, in: context) }
            .sorted { $0.timestamp < $1.timestamp }
        return Array(eligible.suffix(NotificationContext.maxPerSync))
    }
}

// MARK: - Seen events

/// Bounded memory of event ids, so a message returned twice by the server (cache replay, then sync,
/// then gap filling) notifies at most once.
struct RecentEventSet {
    private var order: [String] = []
    private var members: Set<String> = []
    let capacity: Int

    init(capacity: Int = 2000) { self.capacity = max(capacity, 4) }

    var ids: Set<String> { members }

    func contains(_ id: String) -> Bool { members.contains(id) }

    /// Returns false when the id was already there.
    @discardableResult
    mutating func insert(_ id: String) -> Bool {
        guard members.insert(id).inserted else { return false }
        order.append(id)
        if order.count > capacity {
            let overflow = order.count - capacity + capacity / 4
            for old in order.prefix(overflow) { members.remove(old) }
            order.removeFirst(overflow)
        }
        return true
    }

    mutating func removeAll() {
        order = []
        members = []
    }
}

// MARK: - App icon badge

/// What the unread counters of one room contribute to the badge.
struct BadgeRoom: Equatable {
    var isDirect: Bool
    var isSpace = false
    var unreadCount: Int
    var mentionCount: Int
    var isMuted = false
}

enum BadgeCalculator {
    /// Mentions in channels + every unread message in DMs, like Discord's icon badge.
    /// Muted rooms and spaces do not count.
    static func count(_ rooms: [BadgeRoom]) -> Int {
        rooms.reduce(0) { total, room in
            guard !room.isMuted, !room.isSpace else { return total }
            if room.isDirect { return total + max(room.unreadCount, room.mentionCount) }
            return total + room.mentionCount
        }
    }
}
