import SwiftUI

// MARK: - Inbox

/// Discord's inbox (the tray in the title bar): recent mentions, and everything that is still unread.
struct InboxPopover: View {
    @Environment(MatrixStore.self) private var matrixStore
    @Environment(\.dismiss) private var dismiss
    let servers: [MoodServer]
    let conversations: [DMConversation]
    let onOpenChannel: (Channel, MoodServer) -> Void
    let onOpenConversation: (DMConversation) -> Void
    let onMarkAllRead: () -> Void

    private enum Tab: Hashable { case mentions, unread }
    @State private var tab: Tab = .mentions

    // MARK: Data

    private struct UnreadChannel: Identifiable {
        let channel: Channel
        let server: MoodServer
        var id: UUID { channel.id }
    }

    /// Channels with unread messages, the ones that mention me first.
    private var unreadChannels: [UnreadChannel] {
        let all = servers.flatMap { server in
            server.categories.flatMap(\.channels)
                .filter { $0.unreadCount > 0 || $0.mentionCount > 0 }
                .map { UnreadChannel(channel: $0, server: server) }
        }
        return all.filter { $0.channel.mentionCount > 0 } + all.filter { $0.channel.mentionCount == 0 }
    }

    private var unreadConversations: [DMConversation] {
        conversations.filter { $0.unreadCount > 0 }
    }

    private var unreadTotal: Int { unreadChannels.count + unreadConversations.count }
    private var hasUnreadMentions: Bool { matrixStore.inboxMentions.contains { !$0.isRead } }

    // MARK: Layout

    var body: some View {
        VStack(spacing: 0) {
            header

            Rectangle().fill(MoodTheme.divider).frame(height: 1)

            switch tab {
            case .mentions: mentionsContent
            case .unread: unreadContent
            }
        }
        .frame(width: 420 * LayoutMetrics.scale, height: 560 * LayoutMetrics.scale)
        .background(MoodTheme.serverMenuBackground)
        .task { await matrixStore.refreshInbox() }
        // New mentions arrive through sync; marking things read flips the mentions' read state server-side.
        .onChange(of: refreshSignature) { _, _ in
            Task { await matrixStore.refreshInbox() }
        }
    }

    private var refreshSignature: [Int] {
        [servers.reduce(0) { $0 + $1.mentionCount }, unreadTotal]
    }

    private var header: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8 * LayoutMetrics.scale) {
                Image(systemName: "tray.full.fill")
                    .font(.mood(16, weight: .semibold))
                    .foregroundStyle(MoodTheme.textSecondary)

                Text("Boîte de réception")
                    .font(.mood(16, weight: .bold))
                    .foregroundStyle(MoodTheme.textPrimary)

                Spacer(minLength: 0)

                if tab == .unread && unreadTotal > 0 {
                    Button {
                        onMarkAllRead()
                    } label: {
                        Text("Tout marquer comme lu")
                            .font(.mood(13, weight: .semibold))
                            .foregroundStyle(MoodTheme.brandBlue)
                    }
                    .buttonStyle(.plain)
                    .help("Marquer tous les salons et messages privés comme lus")
                }
            }
            .padding(.horizontal, 16 * LayoutMetrics.scale)
            .frame(height: 48 * LayoutMetrics.scale)

            HStack(spacing: 8 * LayoutMetrics.scale) {
                InboxTabButton(title: "Mentions", badge: hasUnreadMentions ? .dot : .none, isSelected: tab == .mentions) {
                    tab = .mentions
                }
                InboxTabButton(title: "Non lus", badge: unreadTotal > 0 ? .count(unreadTotal) : .none, isSelected: tab == .unread) {
                    tab = .unread
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12 * LayoutMetrics.scale)
            .padding(.bottom, 10 * LayoutMetrics.scale)
        }
    }

    // MARK: Mentions

    @ViewBuilder
    private var mentionsContent: some View {
        let mentions = matrixStore.inboxMentions
        if !mentions.isEmpty {
            ScrollView(showsIndicators: false) {
                LazyVStack(spacing: 2 * LayoutMetrics.scale) {
                    ForEach(mentions) { mention in
                        InboxMentionRow(mention: mention) { open(mention) }
                    }
                }
                .padding(8 * LayoutMetrics.scale)
            }
        } else {
            switch matrixStore.inboxState {
            case .loading:
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            case .idle where matrixStore.userId != nil:
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            case .failed(let message):
                InboxEmptyState(icon: "exclamationmark.triangle", title: "Impossible de charger les mentions", subtitle: message) {
                    Button("Réessayer") { Task { await matrixStore.refreshInbox() } }
                        .buttonStyle(.plain)
                        .font(.mood(13, weight: .semibold))
                        .foregroundStyle(MoodTheme.brandBlue)
                }
            case .idle, .loaded:
                InboxEmptyState(icon: "checkmark.circle", title: "Tu es à jour !", subtitle: "Personne ne t'a mentionné récemment.")
            }
        }
    }

    private func open(_ mention: InboxMention) {
        matrixStore.requestJump(roomId: mention.roomId, eventId: mention.id)
        dismiss()
        switch mention.destination {
        case .channel(let channel, let server): onOpenChannel(channel, server)
        case .dm(let conversation): onOpenConversation(conversation)
        }
    }

    // MARK: Unread

    @ViewBuilder
    private var unreadContent: some View {
        if unreadTotal == 0 {
            InboxEmptyState(icon: "checkmark.circle", title: "Tu es à jour !", subtitle: "Tous tes salons et messages privés sont lus.")
        } else {
            ScrollView(showsIndicators: false) {
                LazyVStack(spacing: 2 * LayoutMetrics.scale) {
                    ForEach(unreadConversations) { conversation in
                        InboxRow(
                            leading: {
                                AvatarGlyph(user: conversation.participant)
                                    .font(.mood(16))
                                    .frame(width: 36 * LayoutMetrics.scale, height: 36 * LayoutMetrics.scale)
                                    .background(MoodTheme.glassBg)
                                    .clipShape(Circle())
                            },
                            title: conversation.participant.displayName,
                            subtitle: conversation.lastMessage.isEmpty ? "Message privé" : conversation.lastMessage,
                            badge: .mentions(conversation.unreadCount)
                        ) {
                            dismiss()
                            onOpenConversation(conversation)
                        }
                    }

                    ForEach(unreadChannels) { item in
                        InboxRow(
                            leading: { InboxServerIcon(server: item.server) },
                            title: "# \(item.channel.name)",
                            subtitle: item.server.name,
                            badge: item.channel.mentionCount > 0 ? .mentions(item.channel.mentionCount) : .unread
                        ) {
                            dismiss()
                            onOpenChannel(item.channel, item.server)
                        }
                    }
                }
                .padding(8 * LayoutMetrics.scale)
            }
        }
    }
}

// MARK: - Pieces

private struct InboxTabButton: View {
    enum Badge: Equatable {
        case none, dot
        case count(Int)
    }

    let title: String
    let badge: Badge
    let isSelected: Bool
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6 * LayoutMetrics.scale) {
                Text(title)
                    .font(.mood(14, weight: .semibold))

                switch badge {
                case .none:
                    EmptyView()
                case .dot:
                    Circle()
                        .fill(MoodTheme.mentionBadge)
                        .frame(width: 8 * LayoutMetrics.scale, height: 8 * LayoutMetrics.scale)
                case .count(let count):
                    Text("\(count)")
                        .font(.mood(11, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 5 * LayoutMetrics.scale)
                        .frame(minWidth: 16 * LayoutMetrics.scale, minHeight: 16 * LayoutMetrics.scale)
                        .background(MoodTheme.mentionBadge)
                        .clipShape(Capsule())
                }
            }
            .foregroundStyle(isSelected ? MoodTheme.textPrimary : MoodTheme.textSecondary)
            .padding(.horizontal, 12 * LayoutMetrics.scale)
            .padding(.vertical, 6 * LayoutMetrics.scale)
            .background(isSelected ? MoodTheme.serverMenuHover : (isHovered ? MoodTheme.hoverBg : Color.clear))
            .clipShape(RoundedRectangle(cornerRadius: 6 * LayoutMetrics.scale, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(MoodMotion.hover) { isHovered = hovering }
        }
    }
}

private struct InboxMentionRow: View {
    let mention: InboxMention
    let action: () -> Void
    @State private var isHovered = false

    private static let relative: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = Locale(identifier: "fr_FR")
        formatter.unitsStyle = .short
        return formatter
    }()

    private var location: String {
        switch mention.destination {
        case .channel(let channel, let server): return "# \(channel.name) · \(server.name)"
        case .dm: return "Message privé"
        }
    }

    var body: some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 12 * LayoutMetrics.scale) {
                AvatarGlyph(user: mention.sender)
                    .font(.mood(16))
                    .frame(width: 36 * LayoutMetrics.scale, height: 36 * LayoutMetrics.scale)
                    .background(MoodTheme.glassBg)
                    .clipShape(Circle())

                VStack(alignment: .leading, spacing: 2 * LayoutMetrics.scale) {
                    HStack(alignment: .firstTextBaseline, spacing: 8 * LayoutMetrics.scale) {
                        Text(mention.sender.displayName)
                            .font(.mood(14, weight: .semibold))
                            .foregroundStyle(mention.sender.roleColor)
                            .lineLimit(1)

                        Spacer(minLength: 0)

                        Text(Self.relative.localizedString(for: mention.timestamp, relativeTo: Date()))
                            .font(.mood(12))
                            .foregroundStyle(MoodTheme.textMuted)
                            .lineLimit(1)
                    }

                    Text(location)
                        .font(.mood(12))
                        .foregroundStyle(MoodTheme.textSecondary)
                        .lineLimit(1)

                    Text(mention.text)
                        .font(.mood(13))
                        .foregroundStyle(MoodTheme.textSupporting)
                        .lineLimit(3)
                        .multilineTextAlignment(.leading)
                        .padding(.top, 2 * LayoutMetrics.scale)
                }

                if !mention.isRead {
                    Circle()
                        .fill(MoodTheme.mentionBadge)
                        .frame(width: 8 * LayoutMetrics.scale, height: 8 * LayoutMetrics.scale)
                        .padding(.top, 6 * LayoutMetrics.scale)
                }
            }
            .padding(10 * LayoutMetrics.scale)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(isHovered ? MoodTheme.serverMenuHover : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 8 * LayoutMetrics.scale, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(MoodMotion.hover) { isHovered = hovering }
        }
    }
}

private struct InboxRow<Leading: View>: View {
    enum Badge {
        case mentions(Int)
        case unread
    }

    @ViewBuilder var leading: Leading
    let title: String
    let subtitle: String
    let badge: Badge
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12 * LayoutMetrics.scale) {
                leading

                VStack(alignment: .leading, spacing: 2 * LayoutMetrics.scale) {
                    Text(title)
                        .font(.mood(14, weight: .semibold))
                        .foregroundStyle(MoodTheme.textPrimary)
                        .lineLimit(1)
                    Text(subtitle)
                        .font(.mood(12))
                        .foregroundStyle(MoodTheme.textSecondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 0)

                switch badge {
                case .mentions(let count):
                    Text("\(count)")
                        .font(.mood(11, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 5 * LayoutMetrics.scale)
                        .frame(minWidth: 16 * LayoutMetrics.scale, minHeight: 16 * LayoutMetrics.scale)
                        .background(MoodTheme.mentionBadge)
                        .clipShape(Capsule())
                case .unread:
                    Circle()
                        .fill(MoodTheme.textPrimary)
                        .frame(width: 8 * LayoutMetrics.scale, height: 8 * LayoutMetrics.scale)
                }
            }
            .padding(10 * LayoutMetrics.scale)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(isHovered ? MoodTheme.serverMenuHover : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 8 * LayoutMetrics.scale, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(MoodMotion.hover) { isHovered = hovering }
        }
    }
}

private struct InboxServerIcon: View {
    let server: MoodServer

    var body: some View {
        Group {
            if let url = server.iconURL {
                AsyncImage(url: url) { phase in
                    if case .success(let image) = phase {
                        image.resizable().scaledToFill()
                    } else {
                        Text(server.iconEmoji)
                    }
                }
            } else {
                Text(server.iconEmoji)
            }
        }
        .font(.mood(18))
        .frame(width: 36 * LayoutMetrics.scale, height: 36 * LayoutMetrics.scale)
        .background(MoodTheme.serverIconBg)
        .clipShape(RoundedRectangle(cornerRadius: 10 * LayoutMetrics.scale, style: .continuous))
    }
}

private struct InboxEmptyState<Action: View>: View {
    let icon: String
    let title: String
    let subtitle: String
    @ViewBuilder var action: Action

    var body: some View {
        VStack(spacing: 10 * LayoutMetrics.scale) {
            Image(systemName: icon)
                .font(.mood(40))
                .foregroundStyle(MoodTheme.textMuted)

            Text(title)
                .font(.mood(17, weight: .bold))
                .foregroundStyle(MoodTheme.textPrimary)
                .multilineTextAlignment(.center)

            Text(subtitle)
                .font(.mood(13))
                .foregroundStyle(MoodTheme.textSecondary)
                .multilineTextAlignment(.center)

            action
        }
        .padding(.horizontal, 32 * LayoutMetrics.scale)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

extension InboxEmptyState where Action == EmptyView {
    init(icon: String, title: String, subtitle: String) {
        self.init(icon: icon, title: title, subtitle: subtitle) { EmptyView() }
    }
}
