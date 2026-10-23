import SwiftUI

struct ContentView: View {
    @Environment(MatrixStore.self) private var matrixStore
    @Environment(AuthState.self) private var authState
    @Environment(\.layoutMode) private var layoutMode
    @State private var selectedServer: MoodServer?
    @State private var selectedChannel: Channel?
    @State private var showDMs = true
    @State private var desktopFriendsTab: FriendsPlaceholderView.FriendsTab = .online
    @State private var selectedDM: DMConversation?
    @State private var showProfilePopup = false
    @State private var profileUser: MoodUser?
    @State private var showSettings = false
    @State private var showQuickSwitcher = false
    @State private var showCreateServer = false
    /// Server just created or joined; opened as soon as the next sync delivers it.
    @State private var pendingServerID: UUID?
    @State private var showExplore = false
    @State private var callingUser: MoodUser?
    @State private var mockServers = MockData.servers
    @State private var mockConversations = MockData.dmConversations

    // Données de démonstration uniquement lorsqu'aucune session Matrix n'est active.
    private var servers: [MoodServer] {
        matrixStore.userId == nil && authState.isDemoMode ? mockServers : matrixStore.servers
    }
    private var sourceConversations: [DMConversation] {
        matrixStore.userId == nil && authState.isDemoMode ? mockConversations : matrixStore.dmConversations
    }
    private var conversations: [DMConversation] {
        sourceConversations
    }
    private var activeServer: MoodServer? {
        guard let selectedServer else { return nil }
        return servers.first(where: { $0.id == selectedServer.id })
    }
    private var activeChannel: Channel? {
        guard let selectedChannel else { return nil }
        return activeServer?.channel(withID: selectedChannel.id)
    }
    private var selectedDMBinding: Binding<DMConversation?> {
        Binding(
            get: { selectedDM },
            set: { conversation in
                if let conversation {
                    openDM(conversation)
                } else {
                    selectedDM = nil
                }
            }
        )
    }
    private var selectedChannelBinding: Binding<Channel?> {
        Binding(
            get: { activeChannel },
            set: { channel in
                if let channel {
                    openChannel(channel)
                } else {
                    selectedChannel = nil
                }
            }
        )
    }
    private var selectedDMUnreadSignature: String {
        guard let selectedDM,
              let conversation = conversations.first(where: { $0.id == selectedDM.id })
        else { return "none" }

        return "\(conversation.id.uuidString)|\(conversation.unreadCount)|\(conversation.unreadEventId ?? "")"
    }
    private var selectedChannelUnreadSignature: String {
        guard let channel = activeChannel else { return "none" }
        return "\(channel.id.uuidString)|\(channel.unreadCount)|\(channel.mentionCount)|\(channel.unreadEventId ?? "")"
    }

    var body: some View {
        ZStack {
            if layoutMode == .regular {
                desktopLayout
            } else {
                compactLayout
            }
        }
        .background(MoodTheme.chatBackground)
        .preferredColorScheme(.dark)
        .safeAreaInset(edge: .top, spacing: 0) {
            if layoutMode == .regular, activeChannel == nil, selectedDM == nil { ConversationRecoveryNotices() }
        }
        .overlay {
            if showProfilePopup, let user = profileUser {
                ZStack {
                    // Dim background
                    Color.black.opacity(0.4)
                        .ignoresSafeArea()
                        .onTapGesture {
                            showProfilePopup = false
                        }

                    UserProfilePopup(
                        user: user,
                        server: selectedServer,
                        onDismiss: { showProfilePopup = false },
                        onOpenConversation: openConversation(withID:)
                    )
                        .frame(width: 320)
                        .popoverElevation()
                }
                .transition(.opacity)
            }
        }
        .animation(MoodMotion.popover, value: showProfilePopup)
        .sheet(isPresented: Binding(get: { showSettings && !calibrateDesktop }, set: { showSettings = $0 })) {
            AccountSettingsView(isPresented: $showSettings, authState: authState)
                .environment(matrixStore)
                .environment(\.layoutMode, layoutMode)
                .preferredColorScheme(layoutMode == .regular ? .dark : (MoodTheme.shared.theme == .light ? .light : .dark))
        }
        .overlay {
            if showSettings && calibrateDesktop {
                GeometryReader { geometry in
                    ZStack {
                        Color.black.opacity(0.75).ignoresSafeArea()
                            .onTapGesture { showSettings = false }
                        AccountSettingsView(isPresented: $showSettings, authState: authState)
                            .frame(width: min(1400, geometry.size.width - 64), height: max(420, geometry.size.height - 144))
                            .environment(\.desktopFriendsCalibration, true)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    .frame(width: geometry.size.width, height: geometry.size.height)
                }
                .ignoresSafeArea()
            }
        }
        .overlay {
            // Appel vocal
            if let user = callingUser {
                VoiceCallView(
                    participant: user,
                    onEnd: {
                        callingUser = nil
                    }
                )
            }
        }
        .background {
            if layoutMode == .regular {
                Button {
                    guard !calibrateDesktop || !showSettings else { return }
                    withAnimation(MoodMotion.popover) { showQuickSwitcher.toggle() }
                } label: { EmptyView() }
                    .keyboardShortcut("k", modifiers: .command)
            }
        }
        .onAppear {
            // Mode -uiPreview : ouvre directement un serveur pour montrer la vue channel
            if ProcessInfo.processInfo.arguments.contains("-uiPreview"), let first = servers.first {
                showDMs = false
                selectedServer = first
                selectedChannel = first.categories.first?.channels.first
            }
            if selectedServer == nil, !showDMs, let first = servers.first {
                selectedServer = first
                selectedChannel = first.categories.first?.channels.first
            }
        }
        .onChange(of: showDMs) { _, newValue in
            if newValue { showExplore = false }
        }
        .onChange(of: selectedServer?.id) { _, newValue in
            if newValue != nil { showExplore = false }
        }
        .onChange(of: selectedChannel?.id) { oldValue, _ in
            if let oldValue { matrixStore.clearNewMessagesDivider(forConversationID: oldValue) }
        }
        .onChange(of: selectedDM?.id) { oldValue, _ in
            if let oldValue { matrixStore.clearNewMessagesDivider(forConversationID: oldValue) }
        }
        .onChange(of: matrixStore.servers) { _, newServers in
            if let pendingServerID, openJoinedRoom(withID: pendingServerID) {
                self.pendingServerID = nil
            } else if selectedServer == nil, let first = newServers.first {
                selectedServer = first
                selectedChannel = first.categories.first?.channels.first
            }
        }
        // Notifications: tell the store which room is on screen, and open the one a tapped banner points to.
        .onAppear { matrixStore.setOpenRoom(visibleRoomId) }
        .onChange(of: visibleRoomId) { _, roomId in
            if layoutMode == .regular { matrixStore.setOpenRoom(roomId) }
        }
        .onChange(of: matrixStore.roomOpenRequest) { _, _ in openRequestedRoom() }
        .onChange(of: matrixStore.dmConversations.map(\.id)) { _, _ in openRequestedRoom() }
        .onChange(of: matrixStore.servers) { _, _ in openRequestedRoom() }
        .onChange(of: selectedDMUnreadSignature) { _, _ in
            guard layoutMode == .regular,
                  showDMs,
                  !showExplore,
                  let selectedDM,
                  let conversation = conversations.first(where: { $0.id == selectedDM.id }),
                  conversation.unreadCount > 0
            else { return }

            self.selectedDM = markConversationRead(conversation)
        }
        .onChange(of: selectedChannelUnreadSignature) { _, _ in
            guard layoutMode == .regular,
                  !showDMs,
                  !showExplore,
                  activeServer != nil,
                  let channel = activeChannel,
                  channel.unreadCount > 0 || channel.mentionCount > 0
            else { return }
            selectedChannel = markChannelRead(channel)
        }
    }

    // MARK: - Desktop Layout — Figma "UI visé pour mood"

    private var calibrateFriends: Bool {
        #if targetEnvironment(macCatalyst)
        showDMs && selectedDM == nil && !showExplore
        #else
        false
        #endif
    }

    private var calibrateDesktop: Bool {
        #if targetEnvironment(macCatalyst)
        true
        #else
        false
        #endif
    }

    @ViewBuilder
    private var desktopLayout: some View {
        VStack(spacing: 0) {
            DesktopTitleBar(
                title: desktopWindowTitle,
                symbol: showDMs ? "person.2.fill" : "bubble.left.and.bubble.right.fill",
                onBack: desktopBack,
                servers: servers,
                conversations: conversations,
                onOpenChannel: openChannel(_:in:),
                onOpenConversation: openInboxConversation(_:),
                onMarkAllRead: markAllInboxRead
            )

            HStack(spacing: 0) {
                // Layer 0 — Server bar (darkest, base)
                ServerSidebarView(
                    servers: servers,
                    selectedServer: $selectedServer,
                    showDMs: $showDMs,
                    selectedChannel: selectedChannelBinding,
                    showCreateServer: $showCreateServer,
                    showExplore: $showExplore,
                    dmUnreadCount: conversations.reduce(0) { $0 + $1.unreadCount }
                )
                .frame(width: LayoutMetrics.serverBarWidth)

                HStack(spacing: 0) {
                    if !showExplore {
                        Group {
                            if showDMs {
                                DMListView(
                                    conversations: conversations,
                                    selectedDM: selectedDMBinding,
                                    showSettings: $showSettings,
                                    onShowMessageRequests: {
                                        selectedDM = nil
                                        desktopFriendsTab = .pending
                                    },
                                    onShowFriends: {
                                        desktopFriendsTab = .online
                                    },
                                    onOpenQuickSwitcher: { showQuickSwitcher = true }
                                )
                            } else if let server = activeServer {
                                ChannelListColumn(
                                    server: server,
                                    selectedChannel: selectedChannelBinding,
                                    showSettings: $showSettings
                                )
                            }
                        }
                        .frame(width: calibrateFriends ? DesktopFriendsPalette.sidebarWidth : LayoutMetrics.channelListWidth)
                        .frame(maxHeight: .infinity)
                        .background(MoodTheme.channelList)
                    }

                    desktopMainContent
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .clipShape(
                    UnevenRoundedRectangle(
                        topLeadingRadius: LayoutMetrics.workspaceCornerRadius,
                        bottomLeadingRadius: 0,
                        bottomTrailingRadius: 0,
                        topTrailingRadius: 0,
                        style: calibrateDesktop ? .circular : .continuous
                    )
                )
                .overlay(alignment: .top) {
                    if calibrateDesktop {
                        DesktopWorkspaceOutline()
                    } else {
                      UnevenRoundedRectangle(
                        topLeadingRadius: LayoutMetrics.workspaceCornerRadius,
                        bottomLeadingRadius: 0,
                        bottomTrailingRadius: 0,
                        topTrailingRadius: 0,
                        style: .continuous
                    )
                    .strokeBorder(MoodTheme.workspaceBorder, lineWidth: 1 * LayoutMetrics.scale)
                    .allowsHitTesting(false)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(MoodTheme.windowBackground)
        .onChange(of: selectedChannel?.id) { _, id in
            if let id { QuickSwitcherRecents.record(key: QuickSwitcherDestination.key(channel: id)) }
        }
        .onChange(of: selectedDM?.id) { _, id in
            if let id { QuickSwitcherRecents.record(key: QuickSwitcherDestination.key(conversation: id)) }
        }
        .overlay(alignment: .bottomLeading) {
            UserStatusPanel(showSettings: $showSettings)
                .frame(width: calibrateFriends ? DesktopFriendsPalette.userPanelWidth : LayoutMetrics.userPanelWidth)
                .padding(.leading, LayoutMetrics.userPanelInset)
                .padding(.bottom, LayoutMetrics.composerBottomInset)
        }
        .ignoresSafeArea()
        .accessibilityHidden(calibrateDesktop && (showQuickSwitcher || showSettings))
        .overlay {
            if showCreateServer {
                ZStack {
                    Color.black.opacity(0.5)
                        .ignoresSafeArea()
                        .onTapGesture { showCreateServer = false }
                    CreateServerModal(isPresented: $showCreateServer, onOpenServer: openServer(withID:))
                }
                .transition(.opacity)
            }
        }
        .overlay {
            if showQuickSwitcher {
                ZStack {
                    Color.black.opacity(calibrateDesktop ? 0.75 : 0.5)
                        .ignoresSafeArea()
                        .onTapGesture { showQuickSwitcher = false }
                    if calibrateDesktop {
                        DesktopQuickSwitcher(items: QuickSwitcherSearch.items(servers: servers, conversations: conversations),
                            isPresented: $showQuickSwitcher, onSelect: navigateDesktop)
                            .offset(y: -floor(LayoutMetrics.desktopTitleBarHeight / 2))
                    } else {
                        QuickSwitcher(isPresented: $showQuickSwitcher, servers: servers,
                            conversations: conversations, onSelect: openQuickSwitcherDestination)
                            .padding(.top, 120 * LayoutMetrics.scale)
                    }
                }
                .transition(.opacity)
            }
        }
        .environment(\.desktopFriendsCalibration, calibrateDesktop)
    }

    private var desktopWindowTitle: String {
        if showExplore { return "Explorer les serveurs" }
        if showDMs {
            return selectedDM?.participant.displayName ?? "Amis"
        }
        return selectedServer?.name ?? "Mood"
    }

    private func desktopBack() {
        if showExplore {
            showExplore = false
            showDMs = true
        } else if selectedDM != nil {
            selectedDM = nil
        } else if !showDMs {
            showDMs = true
            selectedServer = nil
            selectedChannel = nil
        }
    }

    /// Navigates to a quick-switcher result: a channel of a server, a DM, or a server's first channel.
    private func openQuickSwitcherDestination(_ destination: QuickSwitcherDestination) {
        showExplore = false
        switch destination {
        case .channel(let serverID, let channelID):
            guard let server = servers.first(where: { $0.id == serverID }),
                  let channel = server.channel(withID: channelID) else { return }
            showDMs = false
            selectedDM = nil
            selectedServer = server
            openChannel(channel)
        case .conversation(let id):
            openConversation(withID: id)
        case .server(let id):
            openServer(withID: id)
        }
    }

    @ViewBuilder
    private var desktopMainContent: some View {
        if showExplore {
            ExploreServersView(onOpenRoom: { id in
                if !openJoinedRoom(withID: id) { pendingServerID = id }
            })
        } else if showDMs {
            if let dm = selectedDM {
                DMChatArea(
                    conversation: dm,
                    showProfilePopup: $showProfilePopup,
                    profileUser: $profileUser,
                    onBack: {
                        selectedDM = nil
                    }
                )
            } else if conversations.isEmpty && desktopFriendsTab == .online && matrixStore.pendingInvites.isEmpty {
                Group {
                    if matrixStore.userId != nil && matrixStore.connection != .connected {
                        ConversationCacheEmptyState()
                    } else {
                        OnboardingHomeEmptyState(onAddFriends: { desktopFriendsTab = .add })
                    }
                }.padding(LayoutMetrics.mobile(24))
            } else {
                FriendsPlaceholderView(
                    selectedTab: $desktopFriendsTab,
                    onOpenDM: { user in
                        let conversation = conversations.first(where: { $0.participant.id == user.id })
                            ?? DMConversation(
                                id: UUID(),
                                participant: user,
                                lastMessage: "",
                                lastMessageDate: Date(),
                                unreadCount: 0
                            )
                        openDM(conversation)
                    },
                    onOpenConversation: { id in
                        showDMs = true
                        if let conversation = conversations.first(where: { $0.id == id }) {
                            openDM(conversation)
                        }
                    },
                    onShowProfile: { user in
                        profileUser = user
                        showProfilePopup = true
                    },
                    onCall: { user in
                        callingUser = user
                    }
                )
            }
        } else if let channel = activeChannel, let server = activeServer {
            ChatArea(
                channel: channel,
                server: server,
                showProfilePopup: $showProfilePopup,
                profileUser: $profileUser,
                onOpenChannel: openChannel(_:)
            )
        } else {
            EmptyStateView()
        }
    }

    // MARK: - Compact Layout (iPhone)

    private var compactLayout: some View {
        MobileRootView(
            servers: servers,
            conversations: conversations,
            matrixStore: matrixStore,
            authState: authState,
            showSettings: $showSettings,
            showCreateServer: $showCreateServer,
            mockServers: $mockServers,
            mockConversations: $mockConversations
        )
    }

    /// The Matrix room on screen in the desktop layout (the iPhone layout reports its own).
    private var visibleRoomId: String? {
        guard layoutMode == .regular, matrixStore.userId != nil, !showExplore else { return nil }
        if showDMs { return selectedDM.flatMap { matrixStore.roomId(for: $0) } }
        return activeChannel.flatMap { matrixStore.roomId(for: $0) }
    }

    /// A tapped notification asked for a room: open it as soon as sync knows it.
    private func openRequestedRoom() {
        guard layoutMode == .regular, let destination = matrixStore.consumeRoomOpenRequest() else { return }
        showSettings = false
        showQuickSwitcher = false
        showExplore = false
        switch destination {
        case .channel(let channel, let server): openChannel(channel, in: server)
        case .dm(let conversation): openInboxConversation(conversation)
        }
    }

    private func openConversation(withID id: UUID) {
        showDMs = true
        if let conversation = conversations.first(where: { $0.id == id }) { openDM(conversation) }
    }

    private func navigateDesktop(_ target: DesktopNavigationTarget) {
        switch target {
        case .friends:
            showDMs = true
            showExplore = false
            selectedDM = nil
            desktopFriendsTab = .online
        case .directMessage(let id):
            showExplore = false
            openConversation(withID: id)
        case .server(let id):
            selectedDM = nil
            showExplore = false
            openServer(withID: id)
        case .channel(let serverID, let channelID):
            guard let server = servers.first(where: { $0.id == serverID }),
                  let channel = server.channel(withID: channelID) else { return }
            showDMs = false
            showExplore = false
            selectedDM = nil
            selectedServer = server
            openChannel(channel)
        }
    }

    private func openServer(withID id: UUID) {
        if let server = servers.first(where: { $0.id == id }) { openServer(server) }
        else { pendingServerID = id }
    }

    /// Opens a just-joined room: its server when it is a space, else its channel inside whichever server lists it
    /// (a plain room lands in the "Matrix" server). False while sync has not delivered it yet.
    @discardableResult
    private func openJoinedRoom(withID id: UUID) -> Bool {
        if let server = servers.first(where: { $0.id == id }) {
            openServer(server)
            return true
        }
        if let server = servers.first(where: { $0.channel(withID: id) != nil }),
           let channel = server.channel(withID: id) {
            showDMs = false
            showExplore = false
            selectedDM = nil
            selectedServer = server
            openChannel(channel)
            return true
        }
        return false
    }

    private func openServer(_ server: MoodServer) {
        showDMs = false
        showExplore = false
        selectedDM = nil
        selectedServer = server
        if let channel = server.categories.first?.channels.first { openChannel(channel) }
    }

    private func openDM(_ conversation: DMConversation) {
        selectedDM = markConversationRead(conversation)
    }

    @discardableResult
    private func markConversationRead(_ conversation: DMConversation) -> DMConversation {
        guard conversation.unreadCount > 0 else { return conversation }
        let readConversation = conversation.withUnreadCount(0)
        if matrixStore.userId == nil {
            if let index = mockConversations.firstIndex(where: { $0.id == conversation.id }) { mockConversations[index] = readConversation }
        } else { matrixStore.markDMAsRead(conversation) }
        return readConversation
    }

    private func openChannel(_ channel: Channel) {
        selectedChannel = markChannelRead(channel)
    }

    // MARK: Inbox (desktop title bar)

    /// Opens a channel from anywhere: switches to its server first.
    private func openChannel(_ channel: Channel, in server: MoodServer) {
        showDMs = false
        showExplore = false
        selectedDM = nil
        selectedServer = server
        openChannel(channel)
    }

    private func openInboxConversation(_ conversation: DMConversation) {
        showExplore = false
        showDMs = true
        openDM(conversation)
    }

    private func markAllInboxRead() {
        for server in servers {
            for channel in server.categories.flatMap(\.channels) where channel.unreadCount > 0 || channel.mentionCount > 0 {
                markChannelRead(channel)
            }
        }
        for conversation in conversations where conversation.unreadCount > 0 {
            markConversationRead(conversation)
        }
    }

    @discardableResult
    private func markChannelRead(_ channel: Channel) -> Channel {
        guard channel.unreadCount > 0 || channel.mentionCount > 0 else { return channel }
        let readChannel = channel.markingAsRead()
        if matrixStore.userId == nil {
            if let index = mockServers.firstIndex(where: { $0.channel(withID: channel.id) != nil }) {
                mockServers[index] = mockServers[index].markingChannelAsRead(channel.id)
            }
        } else { matrixStore.markChannelAsRead(channel) }
        if let server = servers.first(where: { $0.channel(withID: channel.id) != nil }) { selectedServer = server }
        return readChannel
    }

}

// MARK: - Error Banner (toast global, lit matrixStore.errorMessage)

struct ErrorBanner: View {
    let message: String
    var onRetry: (() -> Void)? = nil
    let onDismiss: () -> Void

    var body: some View {
        MoodNotice(title: "L’action n’a pas abouti", detail: message,
            actionTitle: onRetry == nil ? nil : "Réessayer", action: onRetry,
            secondaryTitle: "Fermer", secondaryAction: onDismiss)
    }

}

// MARK: - Empty State

struct EmptyStateView: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "number")
                .font(.system(size: 44))
                .foregroundStyle(MoodTheme.textMuted)
            Text("Sélectionne un channel")
                .font(.subheadline)
                .foregroundStyle(MoodTheme.textMuted)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(MoodTheme.chatBackground)
    }
}

// MARK: - Friends View

struct FriendsPlaceholderView: View {
    enum FriendsTab: String, CaseIterable {
        case online = "En ligne"
        case all = "Tous"
        case pending = "En attente"
        case blocked = "Bloqués"
        case add = "Ajouter"
    }

    @Environment(MatrixStore.self) private var matrixStore
    @Environment(AuthState.self) private var authState
    @Environment(\.desktopFriendsCalibration) private var calibrated

    @Binding var selectedTab: FriendsTab

    /// Demo data only without a session; otherwise the people you have a DM with.
    private var friends: [MoodUser] {
        matrixStore.userId == nil && authState.isDemoMode ? MockData.users : matrixStore.friends
    }
    var onOpenDM: ((MoodUser) -> Void)?
    var onOpenConversation: ((UUID) -> Void)?
    var onShowProfile: ((MoodUser) -> Void)?
    var onCall: ((MoodUser) -> Void)?
    @State private var searchText = ""
    @State private var showAddFriend = false

    var filteredFriends: [MoodUser] {
        if searchText.isEmpty { return friends }
        return friends.filter { $0.displayName.localizedCaseInsensitiveContains(searchText) || $0.username.localizedCaseInsensitiveContains(searchText) }
    }

    var onlineFriends: [MoodUser] {
        filteredFriends.filter { !$0.status.isOfflineLike }
    }

    private var hasOnlineFriends: Bool { friends.contains { !$0.status.isOfflineLike } }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: (calibrated ? 12 : 13) * LayoutMetrics.scale) {
                Button {
                    selectedTab = calibrated && !hasOnlineFriends ? .all : .online
                } label: {
                    HStack(spacing: 8 * LayoutMetrics.scale) {
                        CalibratedDesktopSymbol(name: "figure.wave", size: calibrated ? 16 : 17, weight: .semibold)
                            .foregroundStyle(calibrated ? MoodTheme.textSubtle : MoodTheme.textPrimary)
                        CalibratedDesktopText(value: "Amis", size: calibrated ? 16 : 15, weight: calibrated ? .medium : .semibold,
                                              glyphBackground: calibrated ? MoodTheme.chatBackground : nil)
                    }
                    .foregroundStyle(MoodTheme.textPrimary)
                }
                .buttonStyle(.plain)

                Circle()
                    .fill(MoodTheme.textMuted.opacity(0.55))
                    .frame(width: 4 * LayoutMetrics.scale, height: 4 * LayoutMetrics.scale)

                HStack(spacing: (calibrated ? 16 : 19) * LayoutMetrics.scale) {
                    ForEach(calibrated ? DesktopNavigationIndex.friendsTabs(hasOnlineFriends: hasOnlineFriends)
                        : FriendsTab.allCases.filter { $0 != .add }, id: \.self) { tab in
                        FriendsTabButton(tab: tab, isSelected: selectedTab == tab) {
                            selectedTab = tab
                        }
                    }

                    Button {
                        if calibrated { selectedTab = .add }
                        else { showAddFriend = true }
                    } label: {
                        CalibratedDesktopText(value: "Ajouter", size: 16, weight: calibrated ? .medium : .regular,
                            color: selectedTab == .add ? MoodTheme.brandAccent : .white,
                            glyphBackground: calibrated && selectedTab != .add ? MoodTheme.brandAccent : nil)
                            .frame(width: 76 * LayoutMetrics.scale, height: 32 * LayoutMetrics.scale)
                            .background(selectedTab == .add ? MoodTheme.brandAccent.opacity(0.15) : MoodTheme.brandAccent)
                            .clipShape(RoundedRectangle(cornerRadius: 8 * LayoutMetrics.scale, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }

                Spacer()

                DesktopIconButton(
                    icon: "person.badge.plus",
                    help: "Nouveau groupe privé"
                )
            }
            .padding(.leading, 24 * LayoutMetrics.scale)
            .padding(.trailing, 18 * LayoutMetrics.scale)
            .frame(height: calibrated ? DesktopFriendsPalette.headerHeight : LayoutMetrics.desktopHeaderHeight)

            if calibrated {
                DesktopFriendsRule()
            } else {
                Rectangle().fill(MoodTheme.divider)
                    .frame(height: LayoutMetrics.scale).offset(y: 0.25 * LayoutMetrics.scale)
            }

            HStack(spacing: 0) {
                VStack(spacing: 0) {
                    if selectedTab == .all || (calibrated && selectedTab != .add) {
                        HStack(spacing: (calibrated ? 9 : 8) * LayoutMetrics.scale) {
                            CalibratedDesktopSymbol(name: "magnifyingglass", size: calibrated ? 18 : 16, weight: .medium)
                                .foregroundStyle(MoodTheme.textPrimary)

                            TextField(
                                "",
                                text: $searchText,
                                prompt: Text(calibrated ? "" : "Rechercher")
                                    .foregroundColor(calibrated ? MoodTheme.textSecondary : MoodTheme.friendsSearchPlaceholder)
                            )
                                .textFieldStyle(.plain)
                                .desktopFriendsFont(16)
                                .foregroundStyle(MoodTheme.textPrimary)
                                .accessibilityLabel("Rechercher")
                                .overlay(alignment: .leading) {
                                    if calibrated && searchText.isEmpty {
                                        CalibratedDesktopText(value: "Rechercher", size: 16,
                                            color: DesktopFriendsPalette.placeholder,
                                            glyphBackground: DesktopFriendsPalette.search)
                                            .allowsHitTesting(false)
                                            .accessibilityHidden(true)
                                    }
                                }

                            if !searchText.isEmpty {
                                Button { searchText = "" } label: {
                                    CalibratedDesktopSymbol(name: "xmark.circle.fill", size: 12)
                                        .foregroundStyle(MoodTheme.textPrimary)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, 12 * LayoutMetrics.scale)
                        .frame(height: 40 * LayoutMetrics.scale)
                        .background(calibrated ? DesktopFriendsPalette.search : MoodTheme.headerSearchBackground)
                        .clipShape(RoundedRectangle(cornerRadius: 8 * LayoutMetrics.scale, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: 8 * LayoutMetrics.scale, style: .continuous)
                                .strokeBorder(calibrated ? DesktopFriendsPalette.outline : MoodTheme.headerSearchBorder, lineWidth: 1 * LayoutMetrics.scale)
                        }
                        .padding(.leading, 24 * LayoutMetrics.scale)
                        .padding(.trailing, 16 * LayoutMetrics.scale)
                        .padding(.top, 12 * LayoutMetrics.scale)
                        .padding(.bottom, 20 * LayoutMetrics.scale)
                    }

                    ScrollView(showsIndicators: false) {
                        VStack(alignment: .leading, spacing: 0) {
                            friendsContent
                        }
                        .padding(.bottom, 20 * LayoutMetrics.scale)
                    }
                }

                if calibrated {
                    DesktopFriendsRule(vertical: true)
                } else {
                    Rectangle().fill(MoodTheme.divider)
                        .frame(width: LayoutMetrics.scale).offset(x: 0.25 * LayoutMetrics.scale)
                }

                FriendsActivityPanel()
                    .frame(width: LayoutMetrics.friendsActivityPanelWidth)
            }
        }
        .background(MoodTheme.chatBackground)
        .onAppear {
            if calibrated && !hasOnlineFriends && selectedTab == .online { selectedTab = .all }
        }
        .onChange(of: hasOnlineFriends) { _, present in
            if calibrated && !present && selectedTab == .online { selectedTab = .all }
        }
        .overlay {
            if showAddFriend {
                ZStack {
                    Color.black.opacity(0.5)
                        .ignoresSafeArea()
                        .onTapGesture { showAddFriend = false }

                    AddFriendModal(isPresented: $showAddFriend, onOpenConversation: { id in onOpenConversation?(id) })
                }
                .transition(.opacity)
            }
        }
    }

    @ViewBuilder
    private var friendsContent: some View {
        switch selectedTab {
        case .online:
            friendSection(title: "EN LIGNE", users: onlineFriends)
        case .all:
            allFriendsSection
        case .pending:
            pendingSection
        case .blocked:
            blockedSection
        case .add:
            AddFriendModal(isPresented: $showAddFriend, onOpenConversation: { id in onOpenConversation?(id) }, inline: calibrated)
        }
    }

    @ViewBuilder
    private var pendingSection: some View {
        let visibleInvites = matrixStore.pendingInvites.filter {
            !calibrated || searchText.isEmpty || $0.roomName.localizedCaseInsensitiveContains(searchText)
                || $0.inviter.localizedCaseInsensitiveContains(searchText)
        }
        if matrixStore.pendingInvites.isEmpty {
            friendsEmptyState(icon: "person.crop.circle.badge.clock", title: "Aucune invitation en attente", subtitle: "Les invitations à discuter ou à rejoindre un serveur apparaîtront ici.")
        } else if visibleInvites.isEmpty {
            friendsEmptyState(icon: "magnifyingglass", title: "Aucun résultat", subtitle: "Essaie avec un autre nom.")
        } else {
            friendsListTitle("En attente — \(visibleInvites.count)")
            ForEach(visibleInvites) { invite in
                PendingInviteRow(invite: invite)
            }
        }
    }

    @ViewBuilder
    private var blockedSection: some View {
        if matrixStore.blockedUsers.isEmpty {
            friendsEmptyState(icon: "nosign", title: "Personne n'est bloqué", subtitle: "Tu ne verras plus les messages des personnes que tu bloques.")
        } else {
            friendsListTitle("Bloqués — \(matrixStore.blockedUsers.count)")
            ForEach(matrixStore.blockedUsers) { user in
                BlockedUserRow(user: user)
            }
        }
    }

    private func friendsListTitle(_ title: String) -> some View {
        CalibratedDesktopText(value: title, size: 14, weight: calibrated ? .medium : .semibold,
            color: Color(hex: "efeff1"), glyphBackground: calibrated ? MoodTheme.chatBackground : nil)
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: 38 * LayoutMetrics.scale)
            .padding(.leading, 24 * LayoutMetrics.scale)
            .padding(.top, 12 * LayoutMetrics.scale)
    }

    @ViewBuilder
    private var allFriendsSection: some View {
        if FirstRunPolicy.friendsState(total: friends.count, visible: filteredFriends.count, query: searchText) == .empty {
            FriendsFirstRunState { showAddFriend = true }
        } else if filteredFriends.isEmpty {
            friendsEmptyState(
                icon: "magnifyingglass",
                title: "Aucun résultat",
                subtitle: "Essaie avec un autre nom."
            )
        } else {
            CalibratedDesktopText(value: "Tous les amis - \(filteredFriends.count)", size: 14,
                weight: calibrated ? .medium : .semibold, color: DesktopFriendsPalette.sidebarPrimary,
                glyphBackground: calibrated ? MoodTheme.chatBackground : nil)
                .frame(maxWidth: .infinity, alignment: .leading)
                .frame(height: 38 * LayoutMetrics.scale)
                .padding(.leading, 24 * LayoutMetrics.scale)
                .offset(y: -3 * LayoutMetrics.scale)

            ForEach(filteredFriends) { friend in
                AllFriendRow(
                    user: friend,
                    onMessage: { onOpenDM?(friend) },
                    onShowProfile: { onShowProfile?(friend) },
                    onCall: { onCall?(friend) }
                )
            }
        }
    }

    @ViewBuilder
    private func friendSection(title: String, users: [MoodUser]) -> some View {
        if FirstRunPolicy.friendsState(total: friends.count, visible: users.count, query: searchText) == .empty {
            FriendsFirstRunState { showAddFriend = true }
        } else if users.isEmpty {
            friendsEmptyState(
                icon: searchText.isEmpty ? "person.2.slash" : "magnifyingglass",
                title: searchText.isEmpty ? "Personne ici pour le moment" : "Aucun résultat",
                subtitle: searchText.isEmpty ? "Ajoute des amis pour commencer à discuter." : "Essaie avec un autre nom."
            )
        } else {
            CalibratedDesktopText(value: "\(calibrated ? "En ligne" : title) — \(users.count)", size: calibrated ? 14 : 11,
                                  weight: calibrated ? .medium : .semibold,
                                  color: calibrated ? DesktopFriendsPalette.sidebarPrimary : MoodTheme.textSecondary,
                                  glyphBackground: calibrated ? MoodTheme.chatBackground : nil)
                .offset(y: calibrated ? -1 : 0)
                .padding(.horizontal, (calibrated ? 24 : 20) * LayoutMetrics.scale)
                .padding(.top, (calibrated ? 4 : 8) * LayoutMetrics.scale)
                .padding(.bottom, (calibrated ? 16 : 8) * LayoutMetrics.scale)

            ForEach(users) { friend in
                if calibrated {
                    AllFriendRow(user: friend, onMessage: { onOpenDM?(friend) },
                                 onShowProfile: { onShowProfile?(friend) }, onCall: { onCall?(friend) })
                } else {
                    FriendRow(user: friend, onMessage: { onOpenDM?(friend) }, onCall: { onCall?(friend) })
                }
            }
        }
    }

    private func friendsEmptyState(icon: String, title: String, subtitle: String) -> some View {
        VStack(spacing: 9 * LayoutMetrics.scale) {
            Image(systemName: icon)
                .font(.mood(32, weight: .medium))
                .foregroundStyle(MoodTheme.textMuted)
            Text(title)
                .font(.mood(15, weight: .semibold))
                .foregroundStyle(MoodTheme.textPrimary)
            Text(subtitle)
                .font(.mood(13))
                .foregroundStyle(MoodTheme.textMuted)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 70 * LayoutMetrics.scale)
    }
}

struct FriendsActivityPanel: View {
    @Environment(\.desktopFriendsCalibration) private var calibrated
    var body: some View {
        VStack(alignment: .leading, spacing: 9.5 * LayoutMetrics.scale) {
            CalibratedDesktopText(value: "En ligne", size: 20, weight: calibrated ? .semibold : .bold,
                                  glyphBackground: calibrated ? MoodTheme.chatBackground : nil)

            VStack(spacing: 8 * LayoutMetrics.scale) {
                Text("Tout est calme... pour le moment.")
                    .desktopFriendsFont(15, weight: .bold)
                    .foregroundStyle(MoodTheme.textPrimary)
                    .multilineTextAlignment(.center)

                Text("Quand un ami commencera une activité, comme jouer à un jeu ou passer du temps sur le chat vocal, ce sera affiché ici !")
                    .desktopFriendsFont(13)
                    .foregroundStyle(MoodTheme.textSupporting)
                    .multilineTextAlignment(.center)
                    .lineSpacing(1 * LayoutMetrics.scale)
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 16 * LayoutMetrics.scale)
            .padding(.top, 17 * LayoutMetrics.scale)
            .padding(.bottom, 19 * LayoutMetrics.scale)
            .background(calibrated ? DesktopFriendsPalette.panel : MoodTheme.glassBg)
            .clipShape(RoundedRectangle(cornerRadius: 8 * LayoutMetrics.scale, style: .continuous))

            Spacer()
        }
        .padding(.horizontal, 16 * LayoutMetrics.scale)
        .padding(.top, (calibrated ? 12.5 : 13.5) * LayoutMetrics.scale)
        .background(MoodTheme.chatBackground)
    }
}

struct FriendsTabButton: View {
    @Environment(\.desktopFriendsCalibration) private var calibrated
    let tab: FriendsPlaceholderView.FriendsTab
    let isSelected: Bool
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            CalibratedDesktopText(value: tab.rawValue, size: calibrated ? 16 : 15, weight: .medium,
                                  color: isSelected ? MoodTheme.textPrimary : calibrated ? MoodTheme.textSupporting : MoodTheme.textSecondary,
                                  glyphBackground: calibrated ? (isSelected ? DesktopFriendsPalette.selectedTab : isHovered ? MoodTheme.hoverBg : MoodTheme.chatBackground) : nil)
                .padding(.horizontal, (calibrated ? 12 : 10) * LayoutMetrics.scale)
                .frame(height: 32 * LayoutMetrics.scale)
                .background(isSelected ? (calibrated ? DesktopFriendsPalette.selectedTab : MoodTheme.selectedBg) : isHovered ? MoodTheme.hoverBg : Color.clear)
                .clipShape(RoundedRectangle(cornerRadius: 6 * LayoutMetrics.scale, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.12)) { isHovered = hovering }
        }
    }
}

// MARK: - Add Friend Modal

/// Matrix has no friend requests: "adding a friend" opens a DM with them,
/// which sends them an invite — the closest honest equivalent.
struct AddFriendModal: View {
    @Environment(\.layoutMode) private var layoutMode
    @Environment(MatrixStore.self) private var matrixStore
    @Binding var isPresented: Bool
    var onOpenConversation: (UUID) -> Void = { _ in }
    var inline = false
    @State private var username = ""
    @State private var isWorking = false
    @State private var failure: String?
    @State private var results: [MatrixUserResult] = []

    private func send() {
        guard !isWorking else { return }
        isWorking = true
        failure = nil
        Task {
            results = await matrixStore.searchMoodUsername(username)
                .filter { $0.userId != matrixStore.userId }
            isWorking = false
            if results.isEmpty { failure = matrixStore.errorMessage ?? "Personne ne possède ce nom d’utilisateur Mood." }
        }
    }

    private func open(_ user: MatrixUserResult) {
        isWorking = true
        Task {
            if let id = await matrixStore.openOrCreateDM(with: user.userId) {
                isPresented = false
                onOpenConversation(id)
            } else { failure = matrixStore.errorMessage ?? "Impossible d’ouvrir le MP." }
            isWorking = false
        }
    }

    private var directoryResults: some View {
        VStack(alignment: .leading, spacing: LayoutMetrics.mobile(8)) {
            ForEach(results, id: \.userId) { result in
                Button { open(result) } label: {
                    Text(result.displayName ?? "Utilisateur Mood").font(.mood(14))
                        .foregroundStyle(MoodTheme.textPrimary)
                }.disabled(isWorking)
            }
        }
    }

    var body: some View {
        if inline { inlineContent } else { modalContent }
    }

    private var inlineContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            CalibratedDesktopText(value: "Ajouter", size: 20, weight: .semibold, glyphBackground: MoodTheme.chatBackground)
            Text("Tu peux ajouter des amis avec leur nom d’utilisateur Mood")
                .desktopFriendsFont(16).foregroundStyle(DesktopFriendsPalette.sidebarPrimary)
            HStack(spacing: 12) {
                TextField("Nom d’utilisateur", text: $username)
                    .textFieldStyle(.plain).desktopFriendsFont(16)
                    .foregroundStyle(MoodTheme.textPrimary)
                    .accessibilityLabel("Nom d’utilisateur")
                    .autocorrectionDisabled().textInputAutocapitalization(.never)
                    .onSubmit { if !username.trimmingCharacters(in: .whitespaces).isEmpty { send() } }
                Button(action: send) {
                    HStack(spacing: 6) {
                        if isWorking { ProgressView().controlSize(.small).tint(.white) }
                        CalibratedDesktopText(value: "Rechercher", size: 14, weight: .medium)
                    }
                    .padding(.horizontal, 12).frame(height: 32)
                    .background(MoodTheme.brandAccent).clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
                .disabled(username.trimmingCharacters(in: .whitespaces).isEmpty || isWorking)
                .opacity(username.trimmingCharacters(in: .whitespaces).isEmpty ? 0.5 : 1)
            }
            .padding(12).frame(minHeight: 58)
            .background(DesktopUXPalette.addInput).clipShape(RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(DesktopFriendsPalette.outline, lineWidth: 1))
            directoryResults
            if let failure {
                Text(failure).desktopFriendsFont(14).foregroundStyle(MoodTheme.mentionBadge)
            }
        }
        .padding(.horizontal, 30).padding(.top, 24)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var modalContent: some View {
        VStack(spacing: 16) {
            HStack {
                Text("Ajouter un ami")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(MoodTheme.textPrimary)
                Spacer()
                Button { isPresented = false } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 12))
                        .foregroundStyle(MoodTheme.textPrimary)
                        .frame(width: 28, height: 28)
                        .background(MoodTheme.glassBg)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                .buttonStyle(.plain)
            }

            Text("Tu peux ajouter des amis avec leur nom d’utilisateur Mood")
                .font(.system(size: 13))
                .foregroundStyle(MoodTheme.textSecondary)

            HStack {
                TextField("Nom d’utilisateur", text: $username)
                    .onSubmit(send)
                    .textFieldStyle(.plain)
                    .font(.system(size: 14))
                    .foregroundStyle(MoodTheme.textPrimary)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(MoodTheme.glassBg)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(MoodTheme.glassBorder, lineWidth: 0.5)
                    )

                Button(action: send) {
                    HStack(spacing: 6) {
                        if isWorking {
                            ProgressView().controlSize(.small).tint(.white)
                        }
                        Text("Rechercher")
                            .font(.system(size: 13, weight: .semibold))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(username.isEmpty ? MoodTheme.brandAccent.opacity(0.4) : MoodTheme.brandAccent)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled(username.isEmpty)
            }

            directoryResults
            if let failure {
                Text(failure)
                    .font(.system(size: 12))
                    .foregroundStyle(MoodTheme.mentionBadge)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(24)
        .adaptiveFrame(width: 440, mode: layoutMode)
        .background(MoodTheme.popupBg)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(MoodTheme.glassBorder, lineWidth: 0.5)
        )
        .popoverElevation()
    }
}

// MARK: - Friend Row

struct FriendRow: View {
    @Environment(MatrixStore.self) private var matrixStore
    let user: MoodUser
    var onMessage: () -> Void = {}
    var onCall: () -> Void = {}
    @State private var isHovered = false
    @State private var showVideoCallAlert = false
    @State private var showRemoveConfirm = false
    @State private var showBlockConfirm = false

    var body: some View {
        HStack(spacing: 14 * LayoutMetrics.scale) {
            // Avatar circle + status
            ZStack(alignment: .bottomTrailing) {
                AvatarGlyph(user: user)
                    .font(.mood(21))
                    .frame(width: 40 * LayoutMetrics.scale, height: 40 * LayoutMetrics.scale)
                    .background(MoodTheme.glassBg)
                    .clipShape(Circle())
                    .opacity(user.status.isOfflineLike ? 0.5 : 1)

                StatusIndicator(status: user.status, size: 10 * LayoutMetrics.scale, borderColor: MoodTheme.chatBackground)
                    .offset(x: 3 * LayoutMetrics.scale, y: 3 * LayoutMetrics.scale)
            }

            // Nom + status
            VStack(alignment: .leading, spacing: 2 * LayoutMetrics.scale) {
                Text(user.displayName)
                    .font(.mood(14, weight: .semibold))
                    .foregroundStyle(user.status.isOfflineLike ? MoodTheme.textMuted : MoodTheme.textPrimary)

                Text(user.status.publicLabel)
                    .font(.mood(12))
                    .foregroundStyle(MoodTheme.textSecondary)
            }

            Spacer()

            // Actions
            HStack(spacing: 6 * LayoutMetrics.scale) {
                FriendActionButton(icon: "bubble.left.fill", action: onMessage)
                    .help("Envoyer un message")
                if matrixStore.callsAvailable {
                    FriendActionButton(icon: "phone.fill", action: onCall)
                        .help("Appel vocal")
                }
            }
        }
        .padding(.horizontal, 18 * LayoutMetrics.scale)
        .frame(height: 58 * LayoutMetrics.scale)
        .background(
            RoundedRectangle(cornerRadius: 10 * LayoutMetrics.scale, style: .continuous)
                .fill(isHovered ? MoodTheme.hoverBg : Color.clear)
        )
        .padding(.horizontal, 8 * LayoutMetrics.scale)
        .contentShape(Rectangle())
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.12)) { isHovered = hovering }
        }
        .contextMenu {
            Button { onMessage() } label: { Label("Envoyer un message", systemImage: "bubble.left") }
            if matrixStore.callsAvailable {
                Button { onCall() } label: { Label("Appel vocal", systemImage: "phone") }
                Button { showVideoCallAlert = true } label: { Label("Appel vidéo", systemImage: "video") }
            }
            Divider()
            Button(role: .destructive) { showRemoveConfirm = true } label: { Label("Retirer l'ami", systemImage: "person.badge.minus") }
            Button(role: .destructive) { showBlockConfirm = true } label: { Label("Bloquer", systemImage: "nosign") }
        }
        .alert("Appel vidéo", isPresented: $showVideoCallAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Les appels vidéo seront disponibles dans une prochaine version.")
        }
        .alert("Retirer l'ami", isPresented: $showRemoveConfirm) {
            Button("Annuler", role: .cancel) {}
            Button("Retirer", role: .destructive) {
                if let id = user.matrixId { Task { await matrixStore.removeFriend(id) } }
            }
        } message: {
            Text("Es-tu sûr de vouloir retirer \(user.displayName) de ta liste d'amis ?")
        }
        .alert("Bloquer", isPresented: $showBlockConfirm) {
            Button("Annuler", role: .cancel) {}
            Button("Bloquer", role: .destructive) {
                if let id = user.matrixId { Task { await matrixStore.setBlocked(id, blocked: true) } }
            }
        } message: {
            Text("Es-tu sûr de vouloir bloquer \(user.displayName) ?")
        }
    }
}

/// Discord-style unified row used only by the desktop `Tous` tab.
/// The online tab intentionally keeps `FriendRow`, whose call shortcut and
/// denser layout were already calibrated separately.
struct AllFriendRow: View {
    @Environment(MatrixStore.self) private var matrixStore
    @Environment(\.desktopFriendsCalibration) private var calibrated
    let user: MoodUser
    var onMessage: () -> Void = {}
    var onShowProfile: () -> Void = {}
    var onCall: () -> Void = {}

    @State private var isHovered = false
    @State private var showVideoCallAlert = false
    @State private var showRemoveConfirm = false
    @State private var showBlockConfirm = false

    private var subtitle: String {
        if !user.status.isOfflineLike, let activity = user.activity {
            return "\(activity.type.rawValue) \(activity.name)"
        }
        return user.status.publicLabel
    }

    private var rowBackground: Color {
        isHovered ? MoodTheme.friendRowHover : Color.clear
    }

    private var presenceBackground: Color {
        isHovered ? MoodTheme.friendRowHover : MoodTheme.chatBackground
    }

    var body: some View {
        VStack(spacing: 0) {
            DesktopFriendsRule(color: calibrated ? DesktopFriendsPalette.rule : MoodTheme.friendRowSeparator)
                .padding(.leading, (calibrated ? 24 : 30) * LayoutMetrics.scale)
                .padding(.trailing, 36 * LayoutMetrics.scale)

            HStack(spacing: 12 * LayoutMetrics.scale) {
                Button(action: onShowProfile) {
                    ZStack(alignment: .bottomTrailing) {
                        AvatarGlyph(user: user)
                            .font(.mood(18))
                            .frame(width: 32 * LayoutMetrics.scale, height: 32 * LayoutMetrics.scale)
                            .background(MoodTheme.glassBg)
                            .clipShape(Circle())

                        FriendPresenceIndicator(
                            status: user.status,
                            background: presenceBackground
                        )
                    }
                }
                .buttonStyle(.plain)
                .help("Afficher le profil de \(user.displayName)")

                Button(action: onShowProfile) {
                    VStack(alignment: .leading, spacing: 0) {
                        CalibratedDesktopText(value: user.displayName, size: 16, weight: .semibold)
                            .lineLimit(1)

                        CalibratedDesktopText(value: subtitle, size: calibrated ? 14 : 15, color: MoodTheme.textSecondary)
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                HStack(spacing: 10 * LayoutMetrics.scale) {
                    AllFriendActionButton(
                        icon: "bubble.left.fill",
                        help: "Envoyer un message",
                        showsSurface: isHovered,
                        action: onMessage
                    )

                    Menu {
                        Button { onMessage() } label: {
                            Label("Envoyer un message", systemImage: "bubble.left")
                        }
                        if matrixStore.callsAvailable {
                            Button { onCall() } label: {
                                Label("Appel vocal", systemImage: "phone")
                            }
                            Button { showVideoCallAlert = true } label: {
                                Label("Appel vidéo", systemImage: "video")
                            }
                        }
                        Divider()
                        Button(role: .destructive) { showRemoveConfirm = true } label: {
                            Label("Retirer l'ami", systemImage: "person.badge.minus")
                        }
                        Button(role: .destructive) { showBlockConfirm = true } label: {
                            Label("Bloquer", systemImage: "nosign")
                        }
                    } label: {
                        Group {
                            if calibrated {
                                DesktopFriendsIcon(name: "ellipsis", size: 24)
                            } else {
                                Image(systemName: "ellipsis").font(.mood(17, weight: .bold)).rotationEffect(.degrees(90))
                            }
                        }
                            .foregroundStyle(MoodTheme.textSupporting)
                            .frame(width: 36 * LayoutMetrics.scale, height: 36 * LayoutMetrics.scale)
                            .background(isHovered ? MoodTheme.serverBar : Color.clear)
                            .clipShape(Circle())
                            .contentShape(Circle())
                    }
                    .menuIndicator(.hidden)
                    .buttonStyle(.plain)
                    .help("Plus")
                }
            }
            .padding(.leading, 24 * LayoutMetrics.scale)
            .padding(.trailing, 36 * LayoutMetrics.scale)
            .frame(height: 61 * LayoutMetrics.scale)
        }
        .frame(height: 62 * LayoutMetrics.scale)
        .background {
            RoundedRectangle(cornerRadius: 8 * LayoutMetrics.scale, style: .continuous)
                .fill(rowBackground)
                .padding(.leading, 14 * LayoutMetrics.scale)
                .padding(.trailing, 26 * LayoutMetrics.scale)
        }
        .contentShape(Rectangle())
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.1)) { isHovered = hovering }
        }
        .contextMenu {
            Button { onMessage() } label: { Label("Envoyer un message", systemImage: "bubble.left") }
            if matrixStore.callsAvailable {
                Button { onCall() } label: { Label("Appel vocal", systemImage: "phone") }
                Button { showVideoCallAlert = true } label: { Label("Appel vidéo", systemImage: "video") }
            }
            Divider()
            Button(role: .destructive) { showRemoveConfirm = true } label: { Label("Retirer l'ami", systemImage: "person.badge.minus") }
            Button(role: .destructive) { showBlockConfirm = true } label: { Label("Bloquer", systemImage: "nosign") }
        }
        .alert("Appel vidéo", isPresented: $showVideoCallAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Les appels vidéo seront disponibles dans une prochaine version.")
        }
        .alert("Retirer l'ami", isPresented: $showRemoveConfirm) {
            Button("Annuler", role: .cancel) {}
            Button("Retirer", role: .destructive) {
                if let id = user.matrixId { Task { await matrixStore.removeFriend(id) } }
            }
        } message: {
            Text("Es-tu sûr de vouloir retirer \(user.displayName) de ta liste d'amis ?")
        }
        .alert("Bloquer", isPresented: $showBlockConfirm) {
            Button("Annuler", role: .cancel) {}
            Button("Bloquer", role: .destructive) {
                if let id = user.matrixId { Task { await matrixStore.setBlocked(id, blocked: true) } }
            }
        } message: {
            Text("Es-tu sûr de vouloir bloquer \(user.displayName) ?")
        }
    }
}

private struct FriendPresenceIndicator: View {
    let status: MoodUser.UserStatus
    let background: Color

    var body: some View {
        StatusIndicator(
            status: status,
            size: 10 * LayoutMetrics.scale,
            borderColor: background
        )
        .offset(x: 2 * LayoutMetrics.scale, y: 2 * LayoutMetrics.scale)
    }
}

private struct AllFriendActionButton: View {
    let icon: String
    let help: String
    let showsSurface: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            CalibratedDesktopSymbol(name: icon, size: 16, calibratedSize: 20, weight: .semibold)
                .foregroundStyle(MoodTheme.textSupporting)
                .frame(width: 36 * LayoutMetrics.scale, height: 36 * LayoutMetrics.scale)
                .background(showsSurface ? MoodTheme.serverBar : Color.clear)
                .clipShape(Circle())
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(help)
        .accessibilityLabel(help)
    }
}

// MARK: - Inbox Panel

struct FriendActionButton: View {
    let icon: String
    var action: () -> Void = {}

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.mood(16))
                .foregroundStyle(MoodTheme.textPrimary)
                .frame(width: 30 * LayoutMetrics.scale, height: 30 * LayoutMetrics.scale)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    ContentView()
        .environment(MatrixStore())
        .environment(AuthState())
}

// MARK: - Pending Invite Row

struct PendingInviteRow: View {
    @Environment(MatrixStore.self) private var matrixStore
    let invite: MatrixStore.PendingInvite
    @State private var isHovered = false
    @State private var working = false

    var body: some View {
        HStack(spacing: 12 * LayoutMetrics.scale) {
            Image(systemName: "envelope.fill")
                .font(.mood(16))
                .foregroundStyle(MoodTheme.textSecondary)
                .frame(width: 36 * LayoutMetrics.scale, height: 36 * LayoutMetrics.scale)
                .background(MoodTheme.serverIconBg)
                .clipShape(Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text(invite.isDirect ? (invite.inviterName ?? invite.inviter) : invite.roomName)
                    .font(.mood(15, weight: .semibold))
                    .foregroundStyle(MoodTheme.textPrimary)
                    .lineLimit(1)
                Text(invite.isDirect ? "Veut discuter avec toi" : "Invitation de \(invite.inviterName ?? invite.inviter)")
                    .font(.mood(13))
                    .foregroundStyle(MoodTheme.textSecondary)
                    .lineLimit(1)
            }
            Spacer()
            RoundIconButton(icon: "checkmark", tint: MoodTheme.onlineGreen, help: "Accepter") {
                working = true
                Task { await matrixStore.acceptInvite(roomId: invite.id); working = false }
            }
            RoundIconButton(icon: "xmark", tint: MoodTheme.mentionBadge, help: "Refuser") {
                working = true
                Task { await matrixStore.rejectInvite(roomId: invite.id); working = false }
            }
        }
        .disabled(working || matrixStore.userId == nil)
        .padding(.horizontal, 12 * LayoutMetrics.scale)
        .frame(height: 62 * LayoutMetrics.scale)
        .background(isHovered ? MoodTheme.hoverBg : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 8 * LayoutMetrics.scale, style: .continuous))
        .padding(.horizontal, 12 * LayoutMetrics.scale)
        .onHover { isHovered = $0 }
    }
}

// MARK: - Blocked User Row

struct BlockedUserRow: View {
    @Environment(MatrixStore.self) private var matrixStore
    let user: MoodUser
    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 12 * LayoutMetrics.scale) {
            AvatarGlyph(user: user)
                .font(.mood(18))
                .frame(width: 36 * LayoutMetrics.scale, height: 36 * LayoutMetrics.scale)
                .background(MoodTheme.serverIconBg)
                .clipShape(Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text(user.displayName)
                    .font(.mood(15, weight: .semibold))
                    .foregroundStyle(MoodTheme.textPrimary)
                Text("Bloqué")
                    .font(.mood(13))
                    .foregroundStyle(MoodTheme.textSecondary)
            }
            Spacer()
            RoundIconButton(icon: "person.fill.xmark", tint: MoodTheme.mentionBadge, help: "Débloquer") {
                if let id = user.matrixId { Task { await matrixStore.setBlocked(id, blocked: false) } }
            }
        }
        .padding(.horizontal, 12 * LayoutMetrics.scale)
        .frame(height: 62 * LayoutMetrics.scale)
        .background(isHovered ? MoodTheme.hoverBg : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 8 * LayoutMetrics.scale, style: .continuous))
        .padding(.horizontal, 12 * LayoutMetrics.scale)
        .onHover { isHovered = $0 }
    }
}

/// Discord's circular row action (accept, decline, message, unblock).
struct RoundIconButton: View {
    let icon: String
    var tint: Color = MoodTheme.textSecondary
    let help: String
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.mood(14, weight: .semibold))
                .foregroundStyle(isHovered ? tint : MoodTheme.textSecondary)
                .frame(width: 36 * LayoutMetrics.scale, height: 36 * LayoutMetrics.scale)
                .background(MoodTheme.serverBar)
                .clipShape(Circle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in withAnimation(MoodMotion.hover) { isHovered = hovering } }
        .help(help)
        .accessibilityLabel(help)
    }
}
