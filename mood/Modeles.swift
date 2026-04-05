import SwiftUI

// MARK: - User

struct MoodUser: Identifiable, Hashable {
    let id: UUID
    let username: String
    let displayName: String
    let avatarEmoji: String
    let roleColor: Color
    let status: UserStatus
    let bio: String
    let joinedDate: Date
    let badges: [String]
    let activity: UserActivity?

    struct UserActivity {
        let type: ActivityType
        let name: String

        enum ActivityType: String {
            case playing = "Joue à"
            case listening = "Écoute"
            case watching = "Regarde"
            case streaming = "Streame"
        }
    }

    enum UserStatus: String {
        case online, offline
    }

    var statusColor: Color {
        switch status {
        case .online: return MoodTheme.onlineGreen
        case .offline: return MoodTheme.mentionBadge
        }
    }

    func hash(into hasher: inout Hasher) { hasher.combine(id) }
    static func == (lhs: MoodUser, rhs: MoodUser) -> Bool { lhs.id == rhs.id }
}

// MARK: - Server Role

enum ServerRole: String {
    case owner = "Propriétaire"
    case admin = "Administrateur"
    case moderator = "Modérateur"
    case member = "Membre"

    var icon: String {
        switch self {
        case .owner: return "crown.fill"
        case .admin: return "shield.checkered"
        case .moderator: return "shield.fill"
        case .member: return ""
        }
    }

    var color: Color {
        switch self {
        case .owner: return .yellow
        case .admin: return .red
        case .moderator: return Color(red: 0.2, green: 0.6, blue: 1.0)
        case .member: return .clear
        }
    }

    var priority: Int {
        switch self {
        case .owner: return 0
        case .admin: return 1
        case .moderator: return 2
        case .member: return 3
        }
    }
}

// MARK: - Server

struct MoodServer: Identifiable, Hashable {
    let id: UUID
    let name: String
    let iconEmoji: String
    let categories: [ChannelCategory]
    let members: [MoodUser]
    let memberRoles: [UUID: ServerRole]
    let hasUnread: Bool
    let mentionCount: Int

    func roleFor(_ user: MoodUser) -> ServerRole {
        memberRoles[user.id] ?? .member
    }

    func hash(into hasher: inout Hasher) { hasher.combine(id) }
    static func == (lhs: MoodServer, rhs: MoodServer) -> Bool { lhs.id == rhs.id }
}

// MARK: - Channel Category

struct ChannelCategory: Identifiable, Hashable {
    let id: UUID
    let name: String
    let channels: [Channel]

    func hash(into hasher: inout Hasher) { hasher.combine(id) }
    static func == (lhs: ChannelCategory, rhs: ChannelCategory) -> Bool { lhs.id == rhs.id }
}

// MARK: - Channel

struct Channel: Identifiable, Hashable {
    let id: UUID
    let name: String
    let type: ChannelType
    let topic: String
    let unreadCount: Int
    let isE2E: Bool

    enum ChannelType: String {
        case text, voice, announcement
    }

    var icon: String {
        switch type {
        case .text: return "number"
        case .voice: return "speaker.wave.2"
        case .announcement: return "megaphone"
        }
    }

    func hash(into hasher: inout Hasher) { hasher.combine(id) }
    static func == (lhs: Channel, rhs: Channel) -> Bool { lhs.id == rhs.id }
}

// MARK: - Reaction

struct MessageReaction: Identifiable, Hashable {
    let id: UUID
    let emoji: String
    var count: Int
    var hasReacted: Bool // current user reacted
}

// MARK: - Message Attachment

struct MessageAttachment: Identifiable {
    let id: UUID
    let type: AttachmentType
    let name: String
    let previewEmoji: String // placeholder pour l'image

    enum AttachmentType {
        case image, file
    }
}

// MARK: - Message

struct ChatMessage: Identifiable {
    let id: UUID
    let sender: MoodUser
    let content: String
    let timestamp: Date
    let isGrouped: Bool
    var reactions: [MessageReaction]
    var replyTo: ReplyRef?
    var attachments: [MessageAttachment]
    var isPinned: Bool
    var threadInfo: ThreadInfo?
    var isEdited: Bool
    var linkEmbed: LinkEmbed?
    var isSystemMessage: Bool
    var systemType: SystemMessageType?

    init(id: UUID, sender: MoodUser, content: String, timestamp: Date, isGrouped: Bool,
         reactions: [MessageReaction] = [], replyTo: ReplyRef? = nil,
         attachments: [MessageAttachment] = [], isPinned: Bool = false,
         threadInfo: ThreadInfo? = nil, isEdited: Bool = false,
         linkEmbed: LinkEmbed? = nil, isSystemMessage: Bool = false,
         systemType: SystemMessageType? = nil) {
        self.id = id
        self.sender = sender
        self.content = content
        self.timestamp = timestamp
        self.isGrouped = isGrouped
        self.reactions = reactions
        self.replyTo = replyTo
        self.attachments = attachments
        self.isPinned = isPinned
        self.threadInfo = threadInfo
        self.isEdited = isEdited
        self.linkEmbed = linkEmbed
        self.isSystemMessage = isSystemMessage
        self.systemType = systemType
    }
}

// MARK: - Reply Reference

struct ReplyRef {
    let sender: MoodUser
    let content: String
}

// MARK: - Thread Info

struct ThreadInfo {
    let replyCount: Int
    let lastReplier: MoodUser
    let lastReplyDate: Date
}

// MARK: - Link Embed

struct LinkEmbed {
    let siteName: String
    let title: String
    let description: String
    let color: Color
    let imageEmoji: String? // placeholder
}

// MARK: - System Message Type

enum SystemMessageType {
    case userJoined
    case messagePinned
    case serverBoosted
}

// MARK: - DM Conversation

struct DMConversation: Identifiable, Hashable {
    let id: UUID
    let participant: MoodUser
    let lastMessage: String
    let lastMessageDate: Date
    let unreadCount: Int

    func hash(into hasher: inout Hasher) { hasher.combine(id) }
    static func == (lhs: DMConversation, rhs: DMConversation) -> Bool { lhs.id == rhs.id }
}

// MARK: - Mock Data

enum MockData {

    static let currentUser = MoodUser(
        id: UUID(), username: "augustin", displayName: "Augustin",
        avatarEmoji: "🌊", roleColor: .blue, status: .online,
        bio: "Building the future of private communication.",
        joinedDate: Calendar.current.date(byAdding: .month, value: -6, to: Date())!,
        badges: ["Early Adopter", "E2E Advocate"],
        activity: nil
    )

    static let testUser = MoodUser(id: UUID(), username: "test", displayName: "Test", avatarEmoji: "🧪", roleColor: .cyan, status: .online, bio: "Utilisateur de test pour les appels", joinedDate: Date(), badges: [], activity: nil)

    static let users: [MoodUser] = [
        testUser,
        MoodUser(id: UUID(), username: "clara", displayName: "Clara", avatarEmoji: "🌸", roleColor: .purple, status: .online, bio: "Designer & cat person", joinedDate: Date(), badges: ["Early Adopter"], activity: MoodUser.UserActivity(type: .playing, name: "Figma")),
        MoodUser(id: UUID(), username: "maxime", displayName: "Maxime", avatarEmoji: "⚡", roleColor: .orange, status: .online, bio: "Full-stack dev", joinedDate: Date(), badges: [], activity: MoodUser.UserActivity(type: .listening, name: "Spotify")),
        MoodUser(id: UUID(), username: "lea", displayName: "Léa", avatarEmoji: "🎨", roleColor: .pink, status: .online, bio: "Illustrator", joinedDate: Date(), badges: ["Creator"], activity: nil),
        MoodUser(id: UUID(), username: "thomas", displayName: "Thomas", avatarEmoji: "🎵", roleColor: .green, status: .offline, bio: "Music producer", joinedDate: Date(), badges: [], activity: nil),
        MoodUser(id: UUID(), username: "sophie", displayName: "Sophie", avatarEmoji: "📚", roleColor: .red, status: .offline, bio: "Book lover & writer", joinedDate: Date(), badges: ["Moderator"], activity: MoodUser.UserActivity(type: .watching, name: "YouTube")),
    ]

    static let servers: [MoodServer] = [
        MoodServer(
            id: UUID(), name: "Design Club", iconEmoji: "🎨",
            categories: [
                ChannelCategory(id: UUID(), name: "TEXT CHANNELS", channels: [
                    Channel(id: UUID(), name: "general", type: .text, topic: "General design discussion", unreadCount: 3, isE2E: true),
                    Channel(id: UUID(), name: "showcase", type: .text, topic: "Share your latest work", unreadCount: 0, isE2E: true),
                    Channel(id: UUID(), name: "feedback", type: .text, topic: "Get feedback on your designs", unreadCount: 1, isE2E: true),
                    Channel(id: UUID(), name: "resources", type: .text, topic: "Tools, plugins, and assets", unreadCount: 0, isE2E: true),
                ]),
                ChannelCategory(id: UUID(), name: "VOICE CHANNELS", channels: [
                    Channel(id: UUID(), name: "lounge", type: .voice, topic: "", unreadCount: 0, isE2E: true),
                    Channel(id: UUID(), name: "co-design", type: .voice, topic: "", unreadCount: 0, isE2E: true),
                ]),
                ChannelCategory(id: UUID(), name: "INFO", channels: [
                    Channel(id: UUID(), name: "announcements", type: .announcement, topic: "Server news and updates", unreadCount: 0, isE2E: true),
                    Channel(id: UUID(), name: "rules", type: .text, topic: "Community guidelines", unreadCount: 0, isE2E: true),
                ]),
            ],
            members: Array(users.prefix(4)) + [currentUser],
            memberRoles: [
                currentUser.id: .owner,
                users[1].id: .admin,
                users[2].id: .moderator,
            ],
            hasUnread: true, mentionCount: 2
        ),
        MoodServer(
            id: UUID(), name: "Swift Devs", iconEmoji: "🧑‍💻",
            categories: [
                ChannelCategory(id: UUID(), name: "GENERAL", channels: [
                    Channel(id: UUID(), name: "general", type: .text, topic: "Swift & iOS discussion", unreadCount: 12, isE2E: true),
                    Channel(id: UUID(), name: "introductions", type: .text, topic: "Say hello!", unreadCount: 0, isE2E: true),
                ]),
                ChannelCategory(id: UUID(), name: "HELP", channels: [
                    Channel(id: UUID(), name: "swiftui-help", type: .text, topic: "Get help with SwiftUI", unreadCount: 5, isE2E: true),
                    Channel(id: UUID(), name: "uikit-help", type: .text, topic: "UIKit questions", unreadCount: 0, isE2E: true),
                    Channel(id: UUID(), name: "server-side", type: .text, topic: "Vapor, Hummingbird, etc.", unreadCount: 1, isE2E: true),
                ]),
                ChannelCategory(id: UUID(), name: "COMMUNITY", channels: [
                    Channel(id: UUID(), name: "showcase", type: .text, topic: "Show off your apps", unreadCount: 0, isE2E: true),
                    Channel(id: UUID(), name: "jobs", type: .text, topic: "iOS job postings", unreadCount: 3, isE2E: true),
                ]),
                ChannelCategory(id: UUID(), name: "VOICE", channels: [
                    Channel(id: UUID(), name: "pair-coding", type: .voice, topic: "", unreadCount: 0, isE2E: true),
                    Channel(id: UUID(), name: "talks", type: .voice, topic: "", unreadCount: 0, isE2E: true),
                ]),
            ],
            members: users + [currentUser],
            memberRoles: [
                currentUser.id: .moderator,
                users[2].id: .admin,
                users[5].id: .owner,
            ],
            hasUnread: true, mentionCount: 5
        ),
        MoodServer(
            id: UUID(), name: "Music Lab", iconEmoji: "🎵",
            categories: [
                ChannelCategory(id: UUID(), name: "CHAT", channels: [
                    Channel(id: UUID(), name: "general", type: .text, topic: "Music talk", unreadCount: 0, isE2E: true),
                    Channel(id: UUID(), name: "beats", type: .text, topic: "Share your beats", unreadCount: 2, isE2E: true),
                    Channel(id: UUID(), name: "production", type: .text, topic: "Production tips", unreadCount: 0, isE2E: true),
                ]),
                ChannelCategory(id: UUID(), name: "LISTEN", channels: [
                    Channel(id: UUID(), name: "studio", type: .voice, topic: "", unreadCount: 0, isE2E: true),
                ]),
            ],
            members: [users[3], users[2], currentUser],
            memberRoles: [
                currentUser.id: .owner,
                users[3].id: .moderator,
            ],
            hasUnread: true, mentionCount: 0
        ),
        MoodServer(
            id: UUID(), name: "Startup Café", iconEmoji: "🚀",
            categories: [
                ChannelCategory(id: UUID(), name: "GENERAL", channels: [
                    Channel(id: UUID(), name: "general", type: .text, topic: "Startup chat", unreadCount: 7, isE2E: true),
                    Channel(id: UUID(), name: "launches", type: .text, topic: "Ship it!", unreadCount: 1, isE2E: true),
                    Channel(id: UUID(), name: "funding", type: .text, topic: "Fundraising discussion", unreadCount: 0, isE2E: true),
                ]),
                ChannelCategory(id: UUID(), name: "VOICE", channels: [
                    Channel(id: UUID(), name: "coworking", type: .voice, topic: "", unreadCount: 0, isE2E: true),
                ]),
                ChannelCategory(id: UUID(), name: "NEWS", channels: [
                    Channel(id: UUID(), name: "announcements", type: .announcement, topic: "Big news only", unreadCount: 2, isE2E: true),
                ]),
            ],
            members: [users[1], users[4], currentUser],
            memberRoles: [
                users[1].id: .owner,
                currentUser.id: .admin,
            ],
            hasUnread: true, mentionCount: 1
        ),
        MoodServer(
            id: UUID(), name: "Book Club", iconEmoji: "📖",
            categories: [
                ChannelCategory(id: UUID(), name: "READING", channels: [
                    Channel(id: UUID(), name: "general", type: .text, topic: "All things books", unreadCount: 0, isE2E: true),
                    Channel(id: UUID(), name: "this-month", type: .text, topic: "February: Project Hail Mary", unreadCount: 4, isE2E: true),
                    Channel(id: UUID(), name: "recommendations", type: .text, topic: "What should we read next?", unreadCount: 0, isE2E: true),
                ]),
                ChannelCategory(id: UUID(), name: "VOICE", channels: [
                    Channel(id: UUID(), name: "discussion", type: .voice, topic: "", unreadCount: 0, isE2E: true),
                ]),
            ],
            members: [users[4], users[0], currentUser],
            memberRoles: [
                users[4].id: .owner,
                currentUser.id: .moderator,
            ],
            hasUnread: false, mentionCount: 0
        ),
    ]

    // Utilisateurs connectés en vocal
    static var voiceUsers: [UUID: [MoodUser]] {
        // On assigne des users à certains voice channels
        let allChannels = servers.flatMap { $0.categories.flatMap { $0.channels } }
        var dict: [UUID: [MoodUser]] = [:]
        for ch in allChannels where ch.type == .voice {
            // Premier voice channel : 2 users connectés
            if dict.isEmpty {
                dict[ch.id] = [users[0], users[1]]
            }
        }
        return dict
    }

    static func messages(for channel: Channel) -> [ChatMessage] {
        let cal = Calendar.current
        let now = Date()
        let u = users
        let me = currentUser
        return [
            ChatMessage(id: UUID(), sender: u[0], content: "Hey everyone! Just pushed a new design iteration", timestamp: cal.date(byAdding: .minute, value: -58, to: now)!, isGrouped: false,
                reactions: [
                    MessageReaction(id: UUID(), emoji: "🔥", count: 3, hasReacted: true),
                    MessageReaction(id: UUID(), emoji: "👀", count: 1, hasReacted: false),
                ]),
            ChatMessage(id: UUID(), sender: u[0], content: "Let me know what you think of the new layout", timestamp: cal.date(byAdding: .minute, value: -57, to: now)!, isGrouped: true),
            ChatMessage(id: UUID(), sender: u[1], content: "Looks great! Love the spacing on the new cards.", timestamp: cal.date(byAdding: .minute, value: -52, to: now)!, isGrouped: false,
                reactions: [
                    MessageReaction(id: UUID(), emoji: "💯", count: 2, hasReacted: false),
                ],
                replyTo: ReplyRef(sender: u[0], content: "Hey everyone! Just pushed a new design iteration"),
                isEdited: true),
            ChatMessage(id: UUID(), sender: me, content: "Nice work Clara. The typography is perfect.", timestamp: cal.date(byAdding: .minute, value: -48, to: now)!, isGrouped: false, isPinned: true),
            ChatMessage(id: UUID(), sender: u[2], content: "Léa a rejoint le serveur — bienvenue ! 🎉", timestamp: cal.date(byAdding: .minute, value: -45, to: now)!, isGrouped: false, isSystemMessage: true, systemType: .userJoined),
            ChatMessage(id: UUID(), sender: u[2], content: "The color palette feels very calm. Really fits the Mood brand.", timestamp: cal.date(byAdding: .minute, value: -40, to: now)!, isGrouped: false,
                attachments: [
                    MessageAttachment(id: UUID(), type: .image, name: "palette.png", previewEmoji: "🎨")
                ]),
            ChatMessage(id: UUID(), sender: u[0], content: "Thanks! I was going for that \"breathable\" feeling.", timestamp: cal.date(byAdding: .minute, value: -35, to: now)!, isGrouped: false,
                reactions: [
                    MessageReaction(id: UUID(), emoji: "❤️", count: 4, hasReacted: true),
                    MessageReaction(id: UUID(), emoji: "✨", count: 2, hasReacted: false),
                ]),
            ChatMessage(id: UUID(), sender: u[0], content: "Like the opposite of cramped Discord sidebars lol", timestamp: cal.date(byAdding: .minute, value: -34, to: now)!, isGrouped: true),
            ChatMessage(id: UUID(), sender: u[3], content: "Can we add a way to share audio snippets in channels?", timestamp: cal.date(byAdding: .minute, value: -28, to: now)!, isGrouped: false,
                threadInfo: ThreadInfo(replyCount: 4, lastReplier: u[1], lastReplyDate: cal.date(byAdding: .minute, value: -20, to: now)!)),
            ChatMessage(id: UUID(), sender: me, content: "That's on the roadmap! Audio messages + voice channels coming soon.", timestamp: cal.date(byAdding: .minute, value: -22, to: now)!, isGrouped: false,
                replyTo: ReplyRef(sender: u[3], content: "Can we add a way to share audio snippets in channels?"),
                isPinned: true),
            ChatMessage(id: UUID(), sender: u[4], content: "Love that everything is E2E encrypted by default. That's the way it should be.", timestamp: cal.date(byAdding: .minute, value: -15, to: now)!, isGrouped: false,
                reactions: [
                    MessageReaction(id: UUID(), emoji: "🔒", count: 5, hasReacted: true),
                    MessageReaction(id: UUID(), emoji: "💪", count: 3, hasReacted: false),
                    MessageReaction(id: UUID(), emoji: "🙌", count: 2, hasReacted: false),
                ],
                threadInfo: ThreadInfo(replyCount: 7, lastReplier: u[0], lastReplyDate: cal.date(byAdding: .minute, value: -5, to: now)!)),
            ChatMessage(id: UUID(), sender: u[1], content: "Agreed. Privacy-first is the move. Check this out: https://matrix.org", timestamp: cal.date(byAdding: .minute, value: -10, to: now)!, isGrouped: false,
                linkEmbed: LinkEmbed(siteName: "matrix.org", title: "Matrix — An open network for secure, decentralized communication", description: "Matrix is an open standard for interoperable, decentralised, real-time communication.", color: MoodTheme.brandAccent, imageEmoji: "🌐")),
            ChatMessage(id: UUID(), sender: u[1], content: "No more wondering who's reading your messages", timestamp: cal.date(byAdding: .minute, value: -9, to: now)!, isGrouped: true),
            ChatMessage(id: UUID(), sender: u[0], content: "Shipping the updated mockups tonight. Stay tuned!", timestamp: cal.date(byAdding: .minute, value: -3, to: now)!, isGrouped: false,
                reactions: [
                    MessageReaction(id: UUID(), emoji: "🚀", count: 4, hasReacted: true),
                ],
                attachments: [
                    MessageAttachment(id: UUID(), type: .file, name: "mockups_v3.fig", previewEmoji: "📎")
                ]),
        ]
    }

    static func dmMessages(for conversation: DMConversation) -> [ChatMessage] {
        let cal = Calendar.current
        let now = Date()
        let other = conversation.participant
        let me = currentUser
        return [
            ChatMessage(id: UUID(), sender: other, content: "Hey ! Tu es dispo ?", timestamp: cal.date(byAdding: .minute, value: -45, to: now)!, isGrouped: false),
            ChatMessage(id: UUID(), sender: me, content: "Oui, qu'est-ce qu'il y a ?", timestamp: cal.date(byAdding: .minute, value: -42, to: now)!, isGrouped: false),
            ChatMessage(id: UUID(), sender: other, content: "Je voulais te montrer un truc, regarde ça", timestamp: cal.date(byAdding: .minute, value: -38, to: now)!, isGrouped: false),
            ChatMessage(id: UUID(), sender: other, content: "C'est le nouveau design que j'ai fait", timestamp: cal.date(byAdding: .minute, value: -37, to: now)!, isGrouped: true),
            ChatMessage(id: UUID(), sender: me, content: "Ah c'est super clean ! J'adore le style", timestamp: cal.date(byAdding: .minute, value: -30, to: now)!, isGrouped: false,
                reactions: [
                    MessageReaction(id: UUID(), emoji: "🔥", count: 1, hasReacted: false),
                ]),
            ChatMessage(id: UUID(), sender: other, content: "Merci ! On en reparle demain ?", timestamp: cal.date(byAdding: .minute, value: -25, to: now)!, isGrouped: false),
            ChatMessage(id: UUID(), sender: me, content: "Parfait, à demain 👋", timestamp: cal.date(byAdding: .minute, value: -20, to: now)!, isGrouped: false),
        ]
    }

    static var dmConversations: [DMConversation] {
        [
            DMConversation(id: UUID(), participant: users[0], lastMessage: "The new designs are ready!", lastMessageDate: Date().addingTimeInterval(-300), unreadCount: 2),
            DMConversation(id: UUID(), participant: users[1], lastMessage: "Can you review my PR?", lastMessageDate: Date().addingTimeInterval(-3600), unreadCount: 0),
            DMConversation(id: UUID(), participant: users[2], lastMessage: "Here's the illustration", lastMessageDate: Date().addingTimeInterval(-7200), unreadCount: 1),
            DMConversation(id: UUID(), participant: users[3], lastMessage: "Check out this beat!", lastMessageDate: Date().addingTimeInterval(-86400), unreadCount: 0),
            DMConversation(id: UUID(), participant: users[4], lastMessage: "Finished the chapter review", lastMessageDate: Date().addingTimeInterval(-172800), unreadCount: 0),
        ]
    }
}

// MARK: - Role Badge View

struct RoleBadge: View {
    let role: ServerRole
    var size: CGFloat = 14

    var body: some View {
        if role != .member {
            Image(systemName: role.icon)
                .font(.system(size: size, weight: .semibold))
                .foregroundStyle(role.color)
                .help(role.rawValue)
        }
    }
}

// MARK: - Date Formatting

extension Date {
    var relativeFormatted: String {
        let interval = Date().timeIntervalSince(self)
        if interval < 60 { return "now" }
        else if interval < 3600 { return "\(Int(interval / 60))m ago" }
        else if interval < 86400 { return "\(Int(interval / 3600))h ago" }
        else { return "\(Int(interval / 86400))d ago" }
    }

    var timeFormatted: String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f.string(from: self)
    }

    var messageTimestamp: String {
        let f = DateFormatter()
        f.dateFormat = "dd/MM/yyyy HH:mm"
        return f.string(from: self)
    }

    var dateSeparator: String {
        let cal = Calendar.current
        if cal.isDateInToday(self) {
            return "Aujourd'hui"
        } else if cal.isDateInYesterday(self) {
            return "Hier"
        } else {
            let f = DateFormatter()
            f.dateFormat = "d MMMM yyyy"
            f.locale = Locale(identifier: "fr_FR")
            return f.string(from: self)
        }
    }

    func isSameDay(as other: Date) -> Bool {
        Calendar.current.isDate(self, inSameDayAs: other)
    }
}

