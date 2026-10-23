import SwiftUI

struct MobileDMListView: View {
    let conversations: [DMConversation]
    let onOpen: (DMConversation) -> Void
    @State private var search = ""
    @State private var showNewDM = false
    @State private var showSearch = false
    @Environment(MatrixStore.self) private var store

    private var filtered: [DMConversation] {
        guard !search.isEmpty else { return conversations }
        return conversations.filter { $0.participant.displayName.localizedCaseInsensitiveContains(search) }
    }

    var body: some View {
        VStack(spacing: LayoutMetrics.mobile(0)) {
            Text("Messages").font(.mood(23, weight: .bold))
                .foregroundStyle(MoodTheme.textPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, LayoutMetrics.mobile(16)).padding(.top, LayoutMetrics.mobile(20))
            MobileGlassGroup {
                HStack(spacing: LayoutMetrics.mobile(8)) {
                    Button { showSearch.toggle() } label: {
                        Image(systemName: "magnifyingglass").frame(width: LayoutMetrics.mobile(44), height: LayoutMetrics.mobile(44))
                    }.mobileGlassCapsule().accessibilityLabel("Rechercher")
                    Button { showNewDM = true } label: {
                        Label("Ajouter des amis", systemImage: "person.badge.plus")
                            .font(.mood(14, weight: .medium)).frame(maxWidth: .infinity).frame(height: LayoutMetrics.mobile(44))
                    }.mobileGlassCapsule()
                    Button { showNewDM = true } label: {
                        Image(systemName: "plus").frame(width: LayoutMetrics.mobile(44), height: LayoutMetrics.mobile(44))
                    }.mobileGlassCapsule().accessibilityLabel("Nouveau message")
                }.buttonStyle(.plain).foregroundStyle(MoodTheme.textPrimary)
            }.padding(.horizontal, LayoutMetrics.mobile(16)).padding(.vertical, LayoutMetrics.mobile(14))
            if showSearch {
                TextField("Rechercher", text: $search).textFieldStyle(.plain).font(.mood(15))
                    .padding(LayoutMetrics.mobile(12)).background(MoodTheme.inputBg, in: Capsule())
                    .padding(.horizontal, LayoutMetrics.mobile(16))
            }
            ScrollView {
                LazyVStack(spacing: LayoutMetrics.mobile(2)) {
                    if !store.pendingInvites.isEmpty {
                        Text("Invitations · \(store.pendingInvites.count)").font(.mood(15, weight: .semibold))
                            .foregroundStyle(MoodTheme.textPrimary).padding(LayoutMetrics.mobile(12))
                        ForEach(store.pendingInvites) { invite in MobilePendingInviteRow(invite: invite) }
                    }
                    if let error = store.errorMessage {
                        Text(error).font(.mood(13)).foregroundStyle(MoodTheme.mentionBadge)
                            .padding(LayoutMetrics.mobile(12))
                    }
                    if filtered.isEmpty {
                        ContentUnavailableView("Aucune conversation", systemImage: "bubble.left.and.bubble.right")
                            .padding(.top, LayoutMetrics.mobile(50))
                    }

                    ForEach(filtered) { conversation in
                        Button { onOpen(conversation) } label: { MobileDMRow(conversation: conversation) }
                            .buttonStyle(.plain)
                            .background(MoodTheme.channelList, in: RoundedRectangle(cornerRadius: LayoutMetrics.mobile(14), style: .continuous))
                            .contextMenu {
                                if store.userId != nil {
                                    let muted = store.isMuted(conversation)
                                    Button { Task { await store.setMuted(!muted, conversation: conversation) } } label: {
                                        Label(muted ? "Rétablir le son" : "Rendre muet", systemImage: muted ? "bell" : "bell.slash")
                                    }
                                }
                            }
                    }
                }
                .padding(.bottom, LayoutMetrics.mobile(90))
            }
        }
        .background(MoodTheme.channelList)
        .sheet(isPresented: $showNewDM) {
            NewDMSheet { id in
                if let dm = store.dmConversations.first(where: { $0.id == id }) { onOpen(dm) }
            }.environment(store).presentationDetents([.large])
        }
    }
}

struct MobileDMRow: View {
    @Environment(MatrixStore.self) private var store
    let conversation: DMConversation

    private var relativeTime: String {
        let minutes = max(0, Int(Date().timeIntervalSince(conversation.lastMessageDate) / 60))
        if minutes < 1 { return "maint." }
        if minutes < 60 { return "\(minutes)m" }
        if minutes < 1440 { return "\(minutes / 60)h" }
        return "\(minutes / 1440)j"
    }

    var body: some View {
        HStack(spacing: LayoutMetrics.mobile(11)) {
            ZStack(alignment: .bottomTrailing) {
                AvatarGlyph(user: conversation.participant).font(.mood(19))
                    .frame(width: LayoutMetrics.mobile(42), height: LayoutMetrics.mobile(42)).background(MoodTheme.glassBg).clipShape(RoundedRectangle(cornerRadius: LayoutMetrics.mobile(16), style: .continuous))
                StatusIndicator(status: conversation.participant.status, size: LayoutMetrics.mobile(10), borderColor: MoodTheme.channelList).offset(x: LayoutMetrics.mobile(2), y: LayoutMetrics.mobile(2))
            }
            VStack(alignment: .leading, spacing: LayoutMetrics.mobile(3)) {
                Text(conversation.participant.displayName).font(.mood(15, weight: conversation.unreadCount > 0 ? .semibold : .medium))
                    .foregroundStyle(MoodTheme.textPrimary).fixedSize(horizontal: false, vertical: true)
                Text(conversation.lastMessage.isEmpty ? "Démarrer une conversation" : conversation.lastMessage)
                    .font(.mood(13)).foregroundStyle(MoodTheme.textMuted).lineLimit(1)
            }
            Spacer(minLength: 4)
            VStack(alignment: .trailing, spacing: LayoutMetrics.mobile(5)) {
                Text(relativeTime).font(.mood(10)).foregroundStyle(MoodTheme.textMuted)
                if conversation.unreadCount > 0 {
                    Text("\(conversation.unreadCount)").font(.mood(10, weight: .bold)).foregroundStyle(MoodTheme.mobileIndicator)
                        .padding(.horizontal, LayoutMetrics.mobile(5)).padding(.vertical, LayoutMetrics.mobile(2)).background(MoodTheme.mentionBadge, in: Capsule())
                }
            }
        }
        .opacity(store.isMuted(conversation) ? 0.45 : 1) // muted conversations are dimmed, like Discord
        .padding(.horizontal, LayoutMetrics.mobile(13)).frame(minHeight: LayoutMetrics.mobile(70)).contentShape(Rectangle())
    }
}
