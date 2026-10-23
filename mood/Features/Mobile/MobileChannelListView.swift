import SwiftUI

struct MobileChannelListView: View {
    @Environment(MatrixStore.self) private var store
    let server: MoodServer
    let selectedChannel: Channel?
    let onOpen: (Channel) -> Void
    @State private var search = ""
    @State private var showServerSettings = false
    @State private var showInvite = false
    @State private var showCreateChannel = false
    @State private var editingChannel: Channel?
    @State private var collapsedCategories: Set<UUID> = []

    var body: some View {
        VStack(spacing: LayoutMetrics.mobile(0)) {
            ScrollView(showsIndicators: false) {
                LazyVStack(alignment: .leading, spacing: LayoutMetrics.mobile(2)) {
                    VStack(alignment: .leading, spacing: LayoutMetrics.mobile(14)) {
                        ZStack {
                            MoodTheme.brandAccent.opacity(0.28)
                            if let url = server.iconURL {
                                AuthenticatedImage(url: url) { phase in
                                    if let image = phase.image { image.resizable().scaledToFit() } else { Text(server.iconEmoji).font(.mood(52)) }
                                }
                            } else { Text(server.iconEmoji).font(.mood(52)) }
                        }.frame(height: LayoutMetrics.mobile(112))
                            .clipShape(UnevenRoundedRectangle(topLeadingRadius: LayoutMetrics.mobile(24), topTrailingRadius: LayoutMetrics.mobile(24), style: .continuous))
                        Menu {
                            Button("Inviter") { showInvite = true }
                            Button("Paramètres du serveur") { showServerSettings = true }
                            if store.myPowerLevel(in: server) >= 50 { Button("Créer un salon") { showCreateChannel = true } }
                            Button("Marquer comme lu") { store.markServerAsRead(server) }
                        } label: {
                            HStack {
                                Text(server.name).font(.mood(22, weight: .bold)).fixedSize(horizontal: false, vertical: true)
                                Image(systemName: "chevron.right").font(.mood(12))
                                Spacer()
                            }.foregroundStyle(MoodTheme.textPrimary)
                        }.buttonStyle(.plain).padding(.horizontal, LayoutMetrics.mobile(16))
                        Text("\(server.members.count) membres · Communauté")
                            .font(.mood(14)).foregroundStyle(MoodTheme.textMuted).padding(.horizontal, LayoutMetrics.mobile(16))
                        HStack {
                            Image(systemName: "magnifyingglass")
                            TextField("Rechercher", text: $search).textFieldStyle(.plain)
                        }.font(.mood(15)).foregroundStyle(MoodTheme.textSecondary)
                            .padding(LayoutMetrics.mobile(12)).background(MoodTheme.inputBg, in: Capsule())
                            .padding(.horizontal, LayoutMetrics.mobile(16))
                        Rectangle().fill(MoodTheme.divider).frame(height: LayoutMetrics.mobile(1)).padding(.horizontal, LayoutMetrics.mobile(16))
                    }
                    ForEach(server.categories.filter { $0.channels.contains { $0.type != .voice } }) { category in
                        Button { toggle(category) } label: {
                            HStack(spacing: LayoutMetrics.mobile(6)) {
                                Text(category.displayTitle).font(.mood(14, weight: .medium))
                                Image(systemName: collapsedCategories.contains(category.id) ? "chevron.right" : "chevron.down").font(.mood(11))
                                Spacer()
                            }
                            .foregroundStyle(MoodTheme.textMuted)
                            .padding(.horizontal, LayoutMetrics.mobile(14)).padding(.top, LayoutMetrics.mobile(16)).padding(.bottom, LayoutMetrics.mobile(5))
                        }.buttonStyle(.plain)

                        if !collapsedCategories.contains(category.id) {
                            ForEach(category.channels.filter { $0.type != .voice && (search.isEmpty || $0.name.localizedCaseInsensitiveContains(search)) }) { channel in
                                let unread = max(channel.unreadCount, channel.mentionCount)
                                Button { onOpen(channel) } label: {
                                    HStack(spacing: LayoutMetrics.mobile(9)) {
                                        Image(systemName: channel.type == .text ? "number" : channel.icon)
                                            .font(.mood(16, weight: .medium)).foregroundStyle(unread > 0 ? MoodTheme.textPrimary : MoodTheme.textMuted)
                                            .frame(width: LayoutMetrics.mobile(18))
                                        Text(channel.name).font(.mood(17, weight: unread > 0 ? .bold : .medium))
                                            .foregroundStyle(unread > 0 ? MoodTheme.textPrimary : MoodTheme.textSecondary).fixedSize(horizontal: false, vertical: true)
                                        Spacer(minLength: 4)
                                        if channel.mentionCount > 0 {
                                            Text("\(channel.mentionCount)").font(.mood(10, weight: .bold)).foregroundStyle(MoodTheme.mobileIndicator)
                                                .padding(.horizontal, LayoutMetrics.mobile(5)).padding(.vertical, LayoutMetrics.mobile(2)).background(MoodTheme.mentionBadge, in: Capsule())
                                        } else if unread > 0 {
                                            Circle().fill(MoodTheme.mobileIndicator).frame(width: LayoutMetrics.mobile(7), height: LayoutMetrics.mobile(7))
                                        }
                                    }
                                    .opacity(store.isMuted(channel) && selectedChannel?.id != channel.id ? 0.45 : 1)
                                    .padding(.horizontal, LayoutMetrics.mobile(12)).frame(minHeight: LayoutMetrics.mobile(44))
                                    .background(selectedChannel?.id == channel.id ? MoodTheme.hoverBg : .clear, in: RoundedRectangle(cornerRadius: LayoutMetrics.mobile(14), style: .continuous))
                                    .contentShape(Rectangle())
                                }.buttonStyle(.plain).padding(.horizontal, LayoutMetrics.mobile(7))
                                .contextMenu {
                                    if store.myPowerLevel(in: server) >= 50 { Button("Modifier le salon") { editingChannel = channel } }
                                    if store.userId != nil {
                                        let muted = store.isMuted(channel)
                                        Button { Task { await store.setMuted(!muted, channel: channel) } } label: {
                                            Label(muted ? "Rétablir le son" : "Rendre muet", systemImage: muted ? "bell" : "bell.slash")
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
                .padding(.bottom, LayoutMetrics.mobile(90))
            }
        }
        .background(MoodTheme.channelList)
        .task {
            guard ProcessInfo.processInfo.arguments.contains("-uiPreview"), store.userId == nil else { return }
            if MessagingPreview.kind == "settings" { showServerSettings = true }
            if MessagingPreview.kind == "invite" { showInvite = true }
            if MessagingPreview.kind == "create-channel" { showCreateChannel = true }
        }
        .sheet(isPresented: $showServerSettings) { ServerSettingsView(server: server, isPresented: $showServerSettings).environment(store).environment(\.layoutMode, .compact) }
        .sheet(isPresented: $showInvite) { ServerInviteModal(server: server, isPresented: $showInvite).environment(store).environment(\.layoutMode, .compact) }
        .sheet(isPresented: $showCreateChannel) { CreateChannelModal(server: server, isPresented: $showCreateChannel).environment(store).environment(\.layoutMode, .compact) }
        .sheet(item: $editingChannel) { channel in
            ChannelSettingsView(channel: channel, server: server, isPresented: Binding(get: { editingChannel != nil }, set: { if !$0 { editingChannel = nil } }))
                .environment(store).environment(\.layoutMode, .compact)
        }
    }

    private func toggle(_ category: ChannelCategory) {
        if collapsedCategories.contains(category.id) { collapsedCategories.remove(category.id) }
        else { collapsedCategories.insert(category.id) }
    }
}
