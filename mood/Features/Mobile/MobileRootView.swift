import SwiftUI

enum MobileTab: Hashable {
    case home, notifications, profile
}

struct MobileRootView: View {
    let servers: [MoodServer]
    let conversations: [DMConversation]
    let matrixStore: MatrixStore
    let authState: AuthState
    @Binding var showSettings: Bool
    @Binding var showCreateServer: Bool
    @Binding var mockServers: [MoodServer]
    @Binding var mockConversations: [DMConversation]

    @State private var tab: MobileTab = .home
    @State private var selectedServer: MoodServer?
    @State private var selectedChannel: Channel?
    @State private var selectedDM: DMConversation?
    @State private var showingDMs = true
    @State private var chat: MobileDestination?
    @State private var showExplore = false
    @State private var pendingServerID: UUID?
    @State private var showMembers = false
    @State private var showStatusPicker = false
    @State private var previewAuditSheet = false
    @State private var previewAccountComposer = false
    @State private var previewProfilePopup = false

    private var mentionCount: Int {
        servers.flatMap { $0.categories.flatMap(\.channels) }.reduce(0) { $0 + $1.mentionCount }
    }

    private var currentServer: MoodServer? {
        servers.first { $0.id == selectedServer?.id }
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            Group {
                switch tab {
                case .home:
                    home
                case .notifications:
                    MobileNotificationsView(servers: servers, conversations: conversations, onOpenDM: openDM, store: matrixStore) { channel in openChannel(channel) }
                case .profile:
                    MobileProfileView(
                        user: matrixStore.currentUser ?? (authState.isDemoMode && matrixStore.userId == nil ? MockData.currentUser : nil),
                        status: matrixStore.myStatus,
                        statusMessage: matrixStore.myStatusMessage,
                        showStatusPicker: $showStatusPicker,
                        showSettings: $showSettings,
                        authState: authState,
                        store: matrixStore
                    )
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .accessibilityHidden(chat != nil)
            .allowsHitTesting(chat == nil)

            tabBar
                .accessibilityHidden(chat != nil)
                .allowsHitTesting(chat == nil)

            if let chat {
                MobileChatScreen(
                    destination: chat,
                    store: matrixStore,
                    authState: authState,
                    showMembers: $showMembers,
                    onBack: closeChat
                )
                .simultaneousGesture(DragGesture().onEnded { value in
                    if value.startLocation.x < 28 && value.translation.width > 80 && abs(value.translation.height) < 100 { closeChat() }
                })
                .transition(.move(edge: .trailing))
                .zIndex(2)
            }
        }
        .background(MoodTheme.channelList)

        
        .sheet(isPresented: $showMembers) {
            if case .channel(_, let server) = chat {
                MobileSheet(title: "Membres", onClose: { showMembers = false }) {
                    MobileMemberList(members: server.members, server: server)
                }
            }
        }
        .sheet(isPresented: $showCreateServer) {
            CreateServerModal(isPresented: $showCreateServer, onOpenServer: { id in
                pendingServerID = id
                if let server = servers.first(where: { $0.id == id }) { selectServer(server); pendingServerID = nil }
            })
            .environment(matrixStore)
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
            .presentationBackground(MoodTheme.mobileSurface)
        }
        .sheet(isPresented: $previewAuditSheet) {
            MobileUIPreviewSheet(screen: MobileUIPreview.screen ?? "", presented: $previewAuditSheet)
                .environment(matrixStore)
        }
        .sheet(isPresented: $previewAccountComposer) {
            NewDMSheet { _ in }.environment(matrixStore)
        }
        .sheet(isPresented: $previewProfilePopup) {
            MobileUserProfileSheet(user: ProcessInfo.processInfo.arguments.contains("-finishBasicsPreview") ? MockData.currentUser : MockData.users[1], server: MockData.servers[0]).environment(matrixStore)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
                .presentationBackground(MoodTheme.mobileSurface)
        }
        .sheet(isPresented: $showExplore) {
            MobileExploreView(store: matrixStore)
        }
        .task {
            guard authState.isDemoMode, matrixStore.userId == nil,
                  ProcessInfo.processInfo.arguments.contains("-uiPreview") else { return }
            guard let screen = MobileUIPreview.screen else { return }
            if MobileUIPreview.sheets.contains(screen) { previewAuditSheet = true; return }
            switch screen {
            case "create-server", "join-server": showCreateServer = true
            case "server": if let first = servers.first { selectServer(first) }
            case "chat": if let first = servers.first, let channel = first.categories.flatMap(\.channels).first(where: { $0.type == .text }) { openChannel(channel, server: first) }
            case "explore": showExplore = true
            case "notifications": tab = .notifications
            case "profile", "custom-status": tab = .profile
            case "settings", "appearance", "privacy", "devices", "notification-settings", "encryption", "account", "profile-settings", "account-credentials": tab = .profile; showSettings = true
            case "new-dm": previewAccountComposer = true
            case "profile-popup": previewProfilePopup = true
            default: break
            }
        }
        // Notifications: report the open room, and open the one a tapped banner points to.
        .onChange(of: chat) { _, newValue in matrixStore.setOpenRoom(roomId(of: newValue)) }
        .onChange(of: matrixStore.roomOpenRequest) { _, _ in openRequestedRoom() }
        .onChange(of: conversations.map(\.id)) { _, _ in openRequestedRoom() }
        .onChange(of: servers) { _, _ in openRequestedRoom() }
        .onChange(of: servers) { _, newValue in
            if let pendingServerID, let joined = newValue.first(where: { $0.id == pendingServerID }) {
                selectServer(joined)
                self.pendingServerID = nil
            }
            if let selectedServer, let updated = newValue.first(where: { $0.id == selectedServer.id }) {
                self.selectedServer = updated
                if let selectedChannel { self.selectedChannel = updated.channel(withID: selectedChannel.id) }
            }
        }
    }

    private var home: some View {
        HStack(spacing: LayoutMetrics.mobile(0)) {
            MobileServerRail(
                servers: servers,
                selectedServer: selectedServer,
                showingDMs: showingDMs,
                dmUnreadCount: conversations.reduce(0) { $0 + $1.unreadCount } + matrixStore.pendingInvites.count,
                onDMs: { showingDMs = true; selectedServer = nil },
                onSelect: { server in selectServer(server) },
                onCreate: { showCreateServer = true },
                onExplore: { showExplore = true }
            )
            .frame(width: LayoutMetrics.mobile(72))
            .background(MoodTheme.serverBar)

            if showingDMs {
                MobileDMListView(conversations: conversations) { conversation in
                    openDM(conversation)
                }
            } else if let server = currentServer {
                MobileChannelListView(server: server, selectedChannel: selectedChannel) { channel in
                    openChannel(channel, server: server)
                }
            } else {
                ContentUnavailableView("Aucun serveur", systemImage: "rectangle.stack", description: Text("Rejoins ou crée un serveur pour commencer."))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(MoodTheme.channelList)
            }
        }

    }

    private var tabBar: some View {
        MobileGlassGroup {
            HStack(spacing: LayoutMetrics.mobile(12)) {
                Button { tab = tab == .profile ? .home : .profile } label: {
                    HStack(spacing: LayoutMetrics.mobile(12)) {
                        if let user = matrixStore.currentUser ?? (authState.isDemoMode && matrixStore.userId == nil ? MockData.currentUser : nil) {
                            AvatarGlyph(user: user).font(.mood(26))
                                .frame(width: LayoutMetrics.mobile(48), height: LayoutMetrics.mobile(48))
                                .background(MoodTheme.inputBg, in: RoundedRectangle(cornerRadius: LayoutMetrics.mobile(18), style: .continuous)).clipShape(RoundedRectangle(cornerRadius: LayoutMetrics.mobile(18), style: .continuous))
                                .overlay(alignment: .bottomTrailing) {
                                    Circle().fill(statusColor).frame(width: LayoutMetrics.mobile(13), height: LayoutMetrics.mobile(13))
                                }
                            VStack(alignment: .leading, spacing: LayoutMetrics.mobile(3)) {
                                HStack {
                                    Text(user.displayName).font(.mood(17, weight: .semibold))
                                    Image(systemName: tab == .home ? "chevron.down" : "chevron.left").font(.mood(11))
                                }
                                Text(tab == .home ? matrixStore.myStatus.rawValue : "Retour à l’accueil")
                                    .font(.mood(12)).foregroundStyle(MoodTheme.textMuted)
                            }
                        } else { Label("Mon profil", systemImage: "person.crop.circle") }
                        Spacer(minLength: 0)
                    }.foregroundStyle(MoodTheme.textPrimary)
                }.buttonStyle(.plain).accessibilityLabel(tab == .home ? "Toi" : "Accueil")
                if !matrixStore.pendingInvites.isEmpty {
                    Button {
                        tab = .home; showingDMs = true; selectedServer = nil
                    } label: {
                        Text("\(matrixStore.pendingInvites.count)").font(.mood(12, weight: .bold))
                            .foregroundStyle(MoodTheme.mobileIndicator)
                            .padding(LayoutMetrics.mobile(8)).background(MoodTheme.mentionBadge, in: Circle())
                    }.buttonStyle(.plain).accessibilityLabel("Invitations reçues : \(matrixStore.pendingInvites.count)")
                }
                Button { tab = tab == .notifications ? .home : .notifications } label: {
                    Image(systemName: "bell.fill").font(.mood(20))
                        .foregroundStyle(MoodTheme.textPrimary)
                        .frame(width: LayoutMetrics.mobile(44), height: LayoutMetrics.mobile(44))
                        .mobileGlass(cornerRadius: LayoutMetrics.mobile(14))
                        .overlay(alignment: .topTrailing) {
                            if mentionCount > 0 {
                                Text("\(mentionCount)").font(.mood(10, weight: .bold))
                                    .padding(LayoutMetrics.mobile(4)).background(MoodTheme.mentionBadge, in: Circle())
                            }
                        }
                }.buttonStyle(.plain).accessibilityLabel("Notifications")
            }
            .padding(LayoutMetrics.mobile(10))
            .mobileGlassCapsule()
        }
        .padding(.horizontal, LayoutMetrics.mobile(12)).padding(.bottom, LayoutMetrics.mobile(8))
        .zIndex(1)
    }

    private var statusColor: Color {
        switch matrixStore.myStatus {
        case .online: MoodTheme.onlineGreen
        case .idle: MoodTheme.statusIdle
        case .dnd: MoodTheme.mentionBadge
        case .invisible, .offline: MoodTheme.statusOffline
        }
    }

    private func openDM(_ conversation: DMConversation) {
        selectedDM = conversation
        chat = .dm(conversation)
        if authState.isDemoMode && matrixStore.userId == nil {
            if let index = mockConversations.firstIndex(where: { $0.id == conversation.id }) {
                mockConversations[index] = conversation.withUnreadCount(0)
            }
        } else { matrixStore.markDMAsRead(conversation) }
    }

    private func roomId(of destination: MobileDestination?) -> String? {
        switch destination {
        case .channel(let channel, _)?: matrixStore.roomId(for: channel)
        case .dm(let conversation)?: matrixStore.roomId(for: conversation)
        case nil: nil
        }
    }

    /// A tapped notification asked for a room: open it as soon as sync knows it.
    private func openRequestedRoom() {
        guard let destination = matrixStore.consumeRoomOpenRequest() else { return }
        tab = .home
        showSettings = false
        switch destination {
        case .channel(let channel, let server): openChannel(channel, server: server)
        case .dm(let conversation): showingDMs = true; openDM(conversation)
        }
    }

    private func closeChat() {
        if let selectedChannel { matrixStore.clearNewMessagesDivider(forConversationID: selectedChannel.id) }
        if let selectedDM { matrixStore.clearNewMessagesDivider(forConversationID: selectedDM.id) }
        chat = nil
    }

    private func selectServer(_ server: MoodServer, openFirstChannel: Bool = false) {
        selectedServer = server
        showingDMs = false
        if openFirstChannel, let channel = server.categories.first?.channels.first { openChannel(channel, server: server) }
    }

    private func openChannel(_ channel: Channel, server: MoodServer? = nil) {
        let owner = server ?? servers.first(where: { $0.channel(withID: channel.id) != nil })
        guard let owner else { return }
        selectedServer = owner
        selectedChannel = channel
        showingDMs = false
        chat = .channel(channel, owner)
        if channel.unreadCount > 0 || channel.mentionCount > 0 {
            if authState.isDemoMode && matrixStore.userId == nil {
                if let index = mockServers.firstIndex(where: { $0.channel(withID: channel.id) != nil }) {
                    mockServers[index] = mockServers[index].markingChannelAsRead(channel.id)
                }
            } else { matrixStore.markChannelAsRead(channel) }
        }
    }
}
