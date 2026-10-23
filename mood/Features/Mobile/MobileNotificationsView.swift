import SwiftUI

struct MobileNotificationsView: View {
    let servers: [MoodServer]
    let conversations: [DMConversation]
    let onOpenDM: (DMConversation) -> Void
    let store: MatrixStore
    let onOpen: (Channel) -> Void

    private var mentionedChannels: [(server: MoodServer, channel: Channel)] {
        servers.flatMap { server in
            server.categories.flatMap(\.channels).filter { $0.mentionCount > 0 || $0.unreadCount > 0 }.map { (server, $0) }
        }
    }

    var body: some View {
        VStack(spacing: LayoutMetrics.mobile(0)) {
            Text("Notifications").font(.mood(17, weight: .bold)).foregroundStyle(MoodTheme.textPrimary)
                .frame(maxWidth: .infinity).frame(height: LayoutMetrics.mobile(48)).background(MoodTheme.serverBar)
            Rectangle().fill(MoodTheme.divider).frame(height: LayoutMetrics.mobile(1))
            if store.inboxMentions.isEmpty && mentionedChannels.isEmpty && conversations.allSatisfy({ $0.unreadCount == 0 }) && store.userId != nil && store.connection != .connected {
                ConversationCacheEmptyState().frame(maxHeight: .infinity)
            } else if store.inboxMentions.isEmpty && mentionedChannels.isEmpty && conversations.allSatisfy({ $0.unreadCount == 0 }) {
                VStack(spacing: LayoutMetrics.mobile(12)) {
                    Image(systemName: "bell.slash").font(.mood(36)).foregroundStyle(MoodTheme.textMuted)
                    Text("Rien de nouveau").font(.mood(17, weight: .semibold)).foregroundStyle(MoodTheme.textPrimary)
                }.frame(maxWidth: .infinity, maxHeight: .infinity).background(MoodTheme.mobileSurface)
            } else {
                ScrollView {
                    LazyVStack(spacing: LayoutMetrics.mobile(10)) {
                        if !store.inboxMentions.isEmpty {
                            Text("Mentions").font(.mood(16, weight: .semibold)).foregroundStyle(MoodTheme.textPrimary)
                            ForEach(store.inboxMentions) { mention in
                                Button {
                                    store.requestJump(roomId: mention.roomId, eventId: mention.id)
                                    switch mention.destination {
                                    case .channel(let channel, _): onOpen(channel)
                                    case .dm(let dm): onOpenDM(dm)
                                    }
                                } label: {
                                    VStack(alignment: .leading, spacing: LayoutMetrics.mobile(5)) {
                                        Text(mention.sender.displayName).font(.mood(14, weight: .semibold))
                                        Text(mention.text).font(.mood(14)).lineLimit(3)
                                    }.foregroundStyle(MoodTheme.textPrimary)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .padding(LayoutMetrics.mobile(14))
                                }.buttonStyle(.plain)
                                    .background(MoodTheme.inputBg, in: RoundedRectangle(cornerRadius: LayoutMetrics.mobile(16)))
                            }
                        }
                        ForEach(conversations.filter { $0.unreadCount > 0 }) { conversation in
                            Button { onOpenDM(conversation) } label: {
                                MobileDMRow(conversation: conversation)
                            }.buttonStyle(.plain)
                                .background(MoodTheme.inputBg, in: RoundedRectangle(cornerRadius: LayoutMetrics.mobile(16), style: .continuous))
                        }
                        ForEach(mentionedChannels, id: \.channel.id) { entry in
                            Button { onOpen(entry.channel) } label: {
                                HStack(alignment: .top, spacing: LayoutMetrics.mobile(11)) {
                                    Text(entry.server.iconEmoji).font(.mood(18)).frame(width: LayoutMetrics.mobile(38), height: LayoutMetrics.mobile(38))
                                        .background(MoodTheme.glassBg, in: RoundedRectangle(cornerRadius: LayoutMetrics.mobile(14), style: .continuous))
                                    VStack(alignment: .leading, spacing: LayoutMetrics.mobile(5)) {
                                        HStack(spacing: LayoutMetrics.mobile(4)) {
                                            Text(entry.server.name).font(.mood(14, weight: .semibold)).foregroundStyle(MoodTheme.textPrimary)
                                            Text("· #\(entry.channel.name)").font(.mood(12)).foregroundStyle(MoodTheme.brandAccent)
                                            Spacer(minLength: 2)
                                            Text("\(max(entry.channel.mentionCount, entry.channel.unreadCount))").font(.mood(10, weight: .bold)).foregroundStyle(MoodTheme.mobileIndicator)
                                                .padding(.horizontal, LayoutMetrics.mobile(5)).padding(.vertical, LayoutMetrics.mobile(2)).background(MoodTheme.mentionBadge, in: Capsule())
                                        }
                                        Text(latestMessage(in: entry.channel)?.content ?? "Des messages non lus dans ce salon.")
                                            .font(.mood(14)).foregroundStyle(MoodTheme.textSecondary).lineLimit(2)
                                        if let latest = latestMessage(in: entry.channel) {
                                            Text(latest.sender.displayName + " · " + latest.timestamp.formatted(date: .omitted, time: .shortened))
                                                .font(.mood(11)).foregroundStyle(MoodTheme.textMuted)
                                        }
                                    }
                                }
                                .padding(.horizontal, LayoutMetrics.mobile(14)).padding(.vertical, LayoutMetrics.mobile(12)).contentShape(Rectangle())
                            }.buttonStyle(.plain)
                                .background(MoodTheme.inputBg, in: RoundedRectangle(cornerRadius: LayoutMetrics.mobile(16), style: .continuous))
                        }
                    }.padding(.horizontal, LayoutMetrics.mobile(16)).padding(.top, LayoutMetrics.mobile(16)).padding(.bottom, LayoutMetrics.mobile(100))
                }.background(MoodTheme.mobileSurface)
            }
        }
        .task { await store.refreshInbox() }
    }

    private func latestMessage(in channel: Channel) -> ChatMessage? {
        store.messages(for: channel).last
    }
}
