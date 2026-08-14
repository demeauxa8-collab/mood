import SwiftUI

struct ContentView: View {
    @Environment(MatrixStore.self) private var matrixStore
    @Environment(AuthState.self) private var authState
    @Environment(\.layoutMode) private var layoutMode
    @State private var selectedServer: MoodServer?
    @State private var selectedChannel: Channel?
    @State private var showDMs = true
    @State private var selectedDM: DMConversation?
    @State private var showProfilePopup = false
    @State private var profileUser: MoodUser?
    @State private var showSettings = false
    @State private var showQuickSwitcher = false
    @State private var showCreateServer = false
    @State private var showExplore = false
    @State private var callingUser: MoodUser?
    @State private var selectedTab: CompactTab = .servers
    @State private var mockServers = MockData.servers
    @State private var mockConversations = MockData.dmConversations

    // Données de démonstration uniquement lorsqu'aucune session Matrix n'est active.
    private var servers: [MoodServer] {
        matrixStore.userId == nil ? mockServers : matrixStore.servers
    }
    private var sourceConversations: [DMConversation] {
        matrixStore.userId == nil ? mockConversations : matrixStore.dmConversations
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
                    withAnimation(.snappy(duration: 0.2)) {
                        selectedDM = nil
                    }
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
        .overlay {
            if showProfilePopup, let user = profileUser {
                ZStack {
                    // Dim background
                    Color.black.opacity(0.4)
                        .ignoresSafeArea()
                        .onTapGesture {
                            withAnimation(.easeOut(duration: 0.15)) {
                                showProfilePopup = false
                            }
                        }

                    UserProfilePopup(user: user, server: selectedServer, onDismiss: {
                            withAnimation(.easeOut(duration: 0.15)) { showProfilePopup = false }
                        })
                        .frame(width: 320)
                        .shadow(color: .black.opacity(0.5), radius: 20, y: 8)
                        .transition(.opacity.combined(with: .scale(scale: 0.95)))
                }
                .animation(.easeOut(duration: 0.15), value: showProfilePopup)
            }
        }
        .sheet(isPresented: $showSettings) {
            AccountSettingsView(isPresented: $showSettings, authState: authState)
                .environment(matrixStore)
                .environment(\.layoutMode, layoutMode)
                .preferredColorScheme(.dark)
        }
        .sheet(isPresented: Binding(
            get: { layoutMode == .compact && showCreateServer },
            set: { showCreateServer = $0 }
        )) {
            CreateServerModal(isPresented: $showCreateServer)
                .environment(matrixStore)
                .environment(\.layoutMode, layoutMode)
                .presentationDetents(layoutMode == .compact ? [.large] : [.medium])
        }
        .overlay {
            // Appel vocal
            if let user = callingUser {
                VoiceCallView(
                    participant: user,
                    onEnd: {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            callingUser = nil
                        }
                    }
                )
                .transition(.opacity.combined(with: .scale(scale: 0.95)))
            }
        }
        .background {
            if layoutMode == .regular {
                Button { withAnimation(.easeOut(duration: 0.15)) { showQuickSwitcher.toggle() } } label: { EmptyView() }
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
        .onChange(of: matrixStore.servers) { _, newServers in
            if selectedServer == nil, let first = newServers.first {
                selectedServer = first
                selectedChannel = first.categories.first?.channels.first
            }
        }
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

    @ViewBuilder
    private var desktopLayout: some View {
        VStack(spacing: 0) {
            DesktopTitleBar(
                title: desktopWindowTitle,
                symbol: showDMs ? "person.2.fill" : "bubble.left.and.bubble.right.fill",
                onBack: desktopBack
            )

            HStack(spacing: 0) {
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
                                    showSettings: $showSettings
                                )
                            } else if let server = activeServer {
                                ChannelListColumn(
                                    server: server,
                                    selectedChannel: selectedChannelBinding,
                                    showSettings: $showSettings
                                )
                            }
                        }
                        .frame(width: LayoutMetrics.channelListWidth)
                        .frame(maxHeight: .infinity)
                        .background(MoodTheme.channelList)
                        .transition(.move(edge: .leading).combined(with: .opacity))
                    }

                    desktopMainContent
                        .transition(.opacity.combined(with: .scale(scale: 0.995)))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .clipShape(
                    UnevenRoundedRectangle(
                        topLeadingRadius: LayoutMetrics.workspaceCornerRadius,
                        bottomLeadingRadius: 0,
                        bottomTrailingRadius: 0,
                        topTrailingRadius: 0,
                        style: .continuous
                    )
                )
                .overlay(alignment: .top) {
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
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(MoodTheme.windowBackground)
        .overlay(alignment: .bottomLeading) {
            UserStatusPanel(showSettings: $showSettings)
                .frame(width: LayoutMetrics.userPanelWidth)
                .padding(.leading, LayoutMetrics.userPanelInset)
                .padding(.bottom, LayoutMetrics.composerBottomInset)
        }
        .ignoresSafeArea()
        .animation(.snappy(duration: 0.24), value: showDMs)
        .animation(.snappy(duration: 0.22), value: selectedServer?.id)
        .animation(.snappy(duration: 0.20), value: selectedChannel?.id)
        .animation(.snappy(duration: 0.20), value: selectedDM?.id)
        .overlay {
            if showCreateServer {
                ZStack {
                    Color.black.opacity(0.5)
                        .ignoresSafeArea()
                        .onTapGesture { showCreateServer = false }
                    CreateServerModal(isPresented: $showCreateServer)
                }
                .transition(.opacity)
            }
        }
        .overlay {
            if showQuickSwitcher {
                ZStack {
                    Color.black.opacity(0.5)
                        .ignoresSafeArea()
                        .onTapGesture { showQuickSwitcher = false }
                    QuickSwitcher(isPresented: $showQuickSwitcher)
                        .padding(.bottom, 100)
                }
                .transition(.opacity)
            }
        }
    }

    private var desktopWindowTitle: String {
        if showExplore { return "Explorer les serveurs" }
        if showDMs {
            return selectedDM?.participant.displayName ?? "Amis"
        }
        return selectedServer?.name ?? "Mood"
    }

    private func desktopBack() {
        withAnimation(.snappy(duration: 0.2)) {
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
    }

    @ViewBuilder
    private var desktopMainContent: some View {
        if showExplore {
            ExploreServersView()
        } else if showDMs {
            if let dm = selectedDM {
                DMChatArea(
                    conversation: dm,
                    showProfilePopup: $showProfilePopup,
                    profileUser: $profileUser,
                    onBack: {
                        withAnimation(.snappy(duration: 0.2)) { selectedDM = nil }
                    }
                )
            } else {
                FriendsPlaceholderView(
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
                    onShowProfile: { user in
                        profileUser = user
                        showProfilePopup = true
                    },
                    onCall: { user in
                        withAnimation(.snappy(duration: 0.25)) { callingUser = user }
                    }
                )
            }
        } else if let channel = activeChannel, let server = activeServer {
            ChatArea(
                channel: channel,
                server: server,
                showProfilePopup: $showProfilePopup,
                profileUser: $profileUser
            )
        } else {
            EmptyStateView()
        }
    }

    // MARK: - Compact Layout (iPhone)

    enum CompactTab: Hashable {
        case servers, messages, notifications, profile
    }

    @ViewBuilder
    private var compactLayout: some View {
        TabView(selection: $selectedTab) {
            // Onglet Serveurs
            NavigationStack {
                CompactServerListView(
                    servers: servers,
                    showCreateServer: $showCreateServer,
                    showProfilePopup: $showProfilePopup,
                    profileUser: $profileUser,
                    onReadChannel: { channel in
                        _ = markChannelRead(channel)
                    }
                )
            }
            .tabItem {
                Image(systemName: "rectangle.stack.fill")
                Text("Serveurs")
            }
            .tag(CompactTab.servers)

            // Onglet Messages (DMs)
            NavigationStack {
                CompactDMListView(
                    conversations: conversations,
                    showProfilePopup: $showProfilePopup,
                    profileUser: $profileUser,
                    callingUser: $callingUser,
                    onReadConversation: { conversation in
                        _ = markConversationRead(conversation)
                    }
                )
            }
            .tabItem {
                Image(systemName: "bubble.left.and.bubble.right.fill")
                Text("Messages")
            }
            .tag(CompactTab.messages)
            .badge(conversations.reduce(0) { $0 + $1.unreadCount })

            // Onglet Notifications
            NavigationStack {
                CompactNotificationsView()
            }
            .tabItem {
                Image(systemName: "at")
                Text("Mentions")
            }
            .tag(CompactTab.notifications)
            .badge(3)

            // Onglet Toi
            NavigationStack {
                CompactProfileView(
                    showSettings: $showSettings,
                    authState: authState,
                    matrixStore: matrixStore
                )
            }
            .tabItem {
                Image(systemName: "person.fill")
                Text("Toi")
            }
            .tag(CompactTab.profile)
        }
        .tint(MoodTheme.textPrimary)
        .toolbarBackground(MoodTheme.serverBar, for: .tabBar)
        .toolbarBackground(.visible, for: .tabBar)
    }

    private func openDM(_ conversation: DMConversation) {
        let readConversation = markConversationRead(conversation)
        withAnimation(.snappy(duration: 0.2)) {
            selectedDM = readConversation
        }
    }

    @discardableResult
    private func markConversationRead(_ conversation: DMConversation) -> DMConversation {
        guard conversation.unreadCount > 0 else { return conversation }

        let readConversation = conversation.withUnreadCount(0)

        if matrixStore.userId == nil {
            if let index = mockConversations.firstIndex(where: { $0.id == conversation.id }) {
                mockConversations[index] = readConversation
            }
        } else {
            matrixStore.markDMAsRead(conversation)
        }

        return readConversation
    }

    private func openChannel(_ channel: Channel) {
        let readChannel = markChannelRead(channel)
        withAnimation(.snappy(duration: 0.2)) {
            selectedChannel = readChannel
        }
    }

    @discardableResult
    private func markChannelRead(_ channel: Channel) -> Channel {
        guard channel.unreadCount > 0 || channel.mentionCount > 0 else { return channel }

        let readChannel = channel.markingAsRead()

        if matrixStore.userId == nil {
            if let serverIndex = mockServers.firstIndex(where: { $0.channel(withID: channel.id) != nil }) {
                mockServers[serverIndex] = mockServers[serverIndex].markingChannelAsRead(channel.id)
            }
        } else {
            matrixStore.markChannelAsRead(channel)
        }

        if let refreshedServer = servers.first(where: { $0.channel(withID: channel.id) != nil }) {
            selectedServer = refreshedServer
        }

        return readChannel
    }
}

// MARK: - Compact Server List (iPhone)

struct CompactServerListView: View {
    let servers: [MoodServer]
    @Binding var showCreateServer: Bool
    @Binding var showProfilePopup: Bool
    @Binding var profileUser: MoodUser?
    let onReadChannel: (Channel) -> Void
    @State private var searchText = ""

    var filteredServers: [MoodServer] {
        if searchText.isEmpty { return servers }
        return servers.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                // Barre de recherche
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 14))
                        .foregroundStyle(MoodTheme.textMuted)
                    TextField("Rechercher un serveur", text: $searchText)
                        .font(.system(size: 14))
                        .foregroundStyle(MoodTheme.textPrimary)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(MoodTheme.inputBg)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .padding(.horizontal, 14)
                .padding(.top, 6)
                .padding(.bottom, 12)

                // Liste de serveurs style Discord
                // Chaque serveur = icône ronde + nom + badge, avec pill indicator à gauche
                LazyVStack(spacing: 4) {
                    ForEach(filteredServers) { server in
                        NavigationLink(value: server) {
                            HStack(spacing: 0) {
                                // Pill indicator (unread/mention)
                                RoundedRectangle(cornerRadius: 2)
                                    .fill(server.mentionCount > 0 || server.hasUnread ? MoodTheme.textPrimary : Color.clear)
                                    .frame(width: 4, height: server.mentionCount > 0 ? 32 : (server.hasUnread ? 8 : 0))
                                    .padding(.trailing, 8)

                                // Icône serveur ronde
                                ZStack(alignment: .bottomTrailing) {
                                    Text(server.iconEmoji)
                                        .font(.system(size: 22))
                                        .frame(width: 48, height: 48)
                                        .background(MoodTheme.glassBg)
                                        .clipShape(Circle())

                                    // Badge mentions
                                    if server.mentionCount > 0 {
                                        Text("\(server.mentionCount)")
                                            .font(.system(size: 9, weight: .bold))
                                            .foregroundStyle(.white)
                                            .padding(.horizontal, 4)
                                            .padding(.vertical, 1)
                                            .background(MoodTheme.mentionBadge)
                                            .clipShape(Capsule())
                                            .offset(x: 4, y: 4)
                                    }
                                }

                                // Nom du serveur
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(server.name)
                                        .font(.system(size: 15, weight: server.hasUnread || server.mentionCount > 0 ? .bold : .medium))
                                        .foregroundStyle(server.hasUnread || server.mentionCount > 0 ? MoodTheme.textPrimary : MoodTheme.textSecondary)
                                        .lineLimit(1)
                                }
                                .padding(.leading, 12)

                                Spacer()
                            }
                            .padding(.vertical, 4)
                            .padding(.horizontal, 2)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }

                    // Bouton "Créer un serveur"
                    Button { showCreateServer = true } label: {
                        HStack(spacing: 0) {
                            Color.clear.frame(width: 4).padding(.trailing, 8)
                            ZStack {
                                Circle()
                                    .fill(MoodTheme.glassBg)
                                    .frame(width: 48, height: 48)
                                Image(systemName: "plus")
                                    .font(.system(size: 20))
                                    .foregroundStyle(MoodTheme.onlineGreen)
                            }
                            Text("Ajouter un serveur")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundStyle(MoodTheme.textSecondary)
                                .padding(.leading, 12)
                            Spacer()
                        }
                        .padding(.vertical, 4)
                        .padding(.horizontal, 2)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .scrollDismissesKeyboard(.interactively)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                MoodInfinityLogo(size: 26)
            }
        }
        .navigationDestination(for: MoodServer.self) { server in
            let currentServer = servers.first(where: { $0.id == server.id }) ?? server
            CompactChannelListView(
                server: currentServer,
                showProfilePopup: $showProfilePopup,
                profileUser: $profileUser,
                onReadChannel: onReadChannel
            )
        }
        .background(MoodTheme.serverBar)
        .toolbarBackground(MoodTheme.serverBar, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
    }
}

// MARK: - Compact Channel List (iPhone)

struct CompactChannelListView: View {
    let server: MoodServer
    @Binding var showProfilePopup: Bool
    @Binding var profileUser: MoodUser?
    let onReadChannel: (Channel) -> Void

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(server.categories) { category in
                    // Catégorie header — style Discord (petit, majuscules, discret)
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.down")
                            .font(.system(size: 8, weight: .bold))
                        Text(category.name.uppercased())
                            .font(.system(size: 11, weight: .bold))
                            .tracking(0.5)
                    }
                    .foregroundStyle(MoodTheme.textMuted)
                    .padding(.horizontal, 14)
                    .padding(.top, 18)
                    .padding(.bottom, 4)

                    ForEach(category.channels) { channel in
                        let unreadBadgeCount = max(channel.unreadCount, channel.mentionCount)
                        NavigationLink(value: channel) {
                            HStack(spacing: 8) {
                                Image(systemName: channel.icon)
                                    .font(.system(size: 13))
                                    .foregroundStyle(unreadBadgeCount > 0 ? MoodTheme.textPrimary : MoodTheme.textSecondary)
                                    .frame(width: 18)

                                Text(channel.name)
                                    .font(.system(size: 15, weight: unreadBadgeCount > 0 ? .semibold : .regular))
                                    .foregroundStyle(unreadBadgeCount > 0 ? MoodTheme.textPrimary : MoodTheme.textSecondary)

                                Spacer()

                                if unreadBadgeCount > 0 {
                                    Text("\(unreadBadgeCount)")
                                        .font(.system(size: 10, weight: .bold))
                                        .foregroundStyle(.white)
                                        .padding(.horizontal, 5)
                                        .padding(.vertical, 2)
                                        .background(MoodTheme.mentionBadge)
                                        .clipShape(Capsule())
                                }
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 7)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                HStack(spacing: 8) {
                    Text(server.iconEmoji)
                        .font(.system(size: 16))
                    Text(server.name)
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(MoodTheme.textPrimary)
                }
            }
        }
        .navigationDestination(for: Channel.self) { channel in
            let currentChannel = server.channel(withID: channel.id) ?? channel
            CompactChatWrapper(
                channel: currentChannel,
                server: server,
                showProfilePopup: $showProfilePopup,
                profileUser: $profileUser
            )
            .task(id: "\(currentChannel.unreadEventId ?? "")|\(currentChannel.unreadCount)|\(currentChannel.mentionCount)") {
                if currentChannel.unreadCount > 0 || currentChannel.mentionCount > 0 {
                    onReadChannel(currentChannel)
                }
            }
        }
        .background(MoodTheme.channelList)
        .toolbarBackground(MoodTheme.serverBar, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
    }
}

// MARK: - Compact Chat Wrapper (iPhone)

struct CompactChatWrapper: View {
    let channel: Channel
    let server: MoodServer
    @Binding var showProfilePopup: Bool
    @Binding var profileUser: MoodUser?
    @State private var showMemberList = false

    var body: some View {
        ChatArea(
            channel: channel,
            server: server,
            showProfilePopup: $showProfilePopup,
            profileUser: $profileUser
        )
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                HStack(spacing: 6) {
                    Image(systemName: channel.icon)
                        .font(.system(size: 13))
                    Text(channel.name)
                        .font(.system(size: 16, weight: .semibold))
                }
                .foregroundStyle(MoodTheme.textPrimary)
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button { showMemberList = true } label: {
                    Image(systemName: "person.2")
                        .font(.system(size: 14))
                }
            }
        }
        .sheet(isPresented: $showMemberList) {
            NavigationStack {
                MemberListPanel(
                    members: server.members,
                    server: server,
                    showProfilePopup: $showProfilePopup,
                    profileUser: $profileUser
                )
                .navigationTitle("Membres")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Fermer") { showMemberList = false }
                    }
                }
            }
            .presentationDetents([.medium, .large])
        }
    }
}

// MARK: - Compact DM List (iPhone)

struct CompactDMListView: View {
    let conversations: [DMConversation]
    @Binding var showProfilePopup: Bool
    @Binding var profileUser: MoodUser?
    @Binding var callingUser: MoodUser?
    let onReadConversation: (DMConversation) -> Void
    @State private var searchText = ""

    var filteredConversations: [DMConversation] {
        if searchText.isEmpty { return conversations }
        return conversations.filter { $0.participant.displayName.localizedCaseInsensitiveContains(searchText) }
    }

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                // Recherche custom
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 14))
                        .foregroundStyle(MoodTheme.textMuted)
                    TextField("Rechercher", text: $searchText)
                        .font(.system(size: 14))
                        .foregroundStyle(MoodTheme.textPrimary)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(MoodTheme.inputBg)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .padding(.horizontal, 14)
                .padding(.top, 6)
                .padding(.bottom, 6)

                onlineFriendsCarousel

                Rectangle().fill(MoodTheme.divider).frame(height: 0.5)
                    .padding(.horizontal, 14)

                // Header section
                Text("MESSAGES DIRECTS")
                    .font(.system(size: 11, weight: .bold))
                    .tracking(0.5)
                    .foregroundStyle(MoodTheme.textMuted)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 14)
                    .padding(.top, 12)
                    .padding(.bottom, 4)

                conversationList
            }
        }
        .scrollDismissesKeyboard(.interactively)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text("Messages")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(MoodTheme.textPrimary)
            }
        }
        .navigationDestination(for: DMConversation.self) { convo in
            let currentConversation = conversations.first(where: { $0.id == convo.id }) ?? convo
            CompactDMChatWrapper(
                conversation: currentConversation,
                showProfilePopup: $showProfilePopup,
                profileUser: $profileUser
            )
            .task(id: "\(currentConversation.unreadEventId ?? "")|\(currentConversation.unreadCount)") {
                if currentConversation.unreadCount > 0 {
                    onReadConversation(currentConversation)
                }
            }
        }
        .background(MoodTheme.channelList)
        .toolbarBackground(MoodTheme.serverBar, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
    }

    private var onlineFriendsCarousel: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 16) {
                ForEach(MockData.users.filter { !$0.status.isOfflineLike }) { user in
                    VStack(spacing: 4) {
                        ZStack(alignment: .bottomTrailing) {
                            Text(user.avatarEmoji)
                                .font(.system(size: 18))
                                .frame(width: 44, height: 44)
                                .background(MoodTheme.glassBg)
                                .clipShape(Circle())
                            StatusIndicator(status: user.status, size: 10, borderColor: MoodTheme.channelList)
                                .offset(x: 2, y: 2)
                        }
                        Text(user.displayName)
                            .font(.system(size: 10))
                            .foregroundStyle(MoodTheme.textMuted)
                            .lineLimit(1)
                            .frame(width: 50)
                    }
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
        }
    }

    private var conversationList: some View {
        ForEach(filteredConversations) { convo in
            NavigationLink(value: convo) {
                CompactDMRow(conversation: convo)
            }
            .buttonStyle(.plain)
        }
    }
}

private struct CompactDMRow: View {
    let conversation: DMConversation

    var body: some View {
        HStack(spacing: 10) {
            ZStack(alignment: .bottomTrailing) {
                Text(conversation.participant.avatarEmoji)
                    .font(.system(size: 18))
                    .frame(width: 38, height: 38)
                    .background(MoodTheme.glassBg)
                    .clipShape(Circle())
                StatusIndicator(status: conversation.participant.status, size: 10, borderColor: MoodTheme.channelList)
                    .offset(x: 2, y: 2)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(conversation.participant.displayName)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(conversation.unreadCount > 0 ? MoodTheme.textPrimary : MoodTheme.textSecondary)
                Text(conversation.lastMessage)
                    .font(.system(size: 13))
                    .foregroundStyle(MoodTheme.textMuted)
                    .lineLimit(1)
            }

            Spacer()

            if conversation.unreadCount > 0 {
                Text("\(conversation.unreadCount)")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(MoodTheme.mentionBadge)
                    .clipShape(Capsule())
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 7)
        .contentShape(Rectangle())
    }
}

// MARK: - Compact DM Chat Wrapper (iPhone)

struct CompactDMChatWrapper: View {
    let conversation: DMConversation
    @Binding var showProfilePopup: Bool
    @Binding var profileUser: MoodUser?

    var body: some View {
        DMChatArea(
            conversation: conversation,
            showProfilePopup: $showProfilePopup,
            profileUser: $profileUser,
            onBack: nil
        )
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                HStack(spacing: 8) {
                    Text(conversation.participant.avatarEmoji)
                        .font(.system(size: 14))
                    Text(conversation.participant.displayName)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(MoodTheme.textPrimary)
                }
            }
        }
    }
}

// MARK: - Compact Notifications (iPhone)

struct CompactNotificationsView: View {
    private let mockMentions: [(user: String, emoji: String, channel: String, server: String, content: String, time: String)] = [
        ("Clara", "🌸", "#general", "Design Club", "Hey @Augustin tu peux review le design ?", "Il y a 2h"),
        ("Maxime", "⚡", "#swiftui-help", "Swift Devs", "@Augustin j'ai un bug bizarre avec les Bindings", "Il y a 5h"),
        ("Sophie", "📚", "#general", "Book Club", "C'est @Augustin qui avait recommandé ce livre non ?", "Hier"),
    ]

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(mockMentions, id: \.content) { mention in
                    HStack(alignment: .top, spacing: 10) {
                        Text(mention.emoji)
                            .font(.system(size: 16))
                            .frame(width: 36, height: 36)
                            .background(MoodTheme.glassBg)
                            .clipShape(Circle())

                        VStack(alignment: .leading, spacing: 3) {
                            HStack(spacing: 4) {
                                Text(mention.user)
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundStyle(MoodTheme.textPrimary)
                                Text(mention.channel)
                                    .font(.system(size: 12))
                                    .foregroundStyle(MoodTheme.brandAccent)
                                Text("· \(mention.server)")
                                    .font(.system(size: 12))
                                    .foregroundStyle(MoodTheme.textMuted)
                            }
                            Text(mention.content)
                                .font(.system(size: 14))
                                .foregroundStyle(MoodTheme.textSecondary)
                                .lineLimit(2)
                            Text(mention.time)
                                .font(.system(size: 11))
                                .foregroundStyle(MoodTheme.textMuted)
                        }
                        Spacer()
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                }
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text("Mentions")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(MoodTheme.textPrimary)
            }
        }
        .background(MoodTheme.channelList)
        .toolbarBackground(MoodTheme.serverBar, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
    }
}

// MARK: - Compact Profile (iPhone — "Toi")

struct CompactProfileView: View {
    @Binding var showSettings: Bool
    var authState: AuthState
    var matrixStore: MatrixStore
    private var user: MoodUser { matrixStore.currentUser ?? MockData.currentUser }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                // Bandeau profil style Discord
                ZStack(alignment: .bottom) {
                    // Banner gradient
                    LinearGradient(
                        colors: [MoodTheme.brandAccent.opacity(0.5), MoodTheme.channelList],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(height: 100)

                    // Avatar qui chevauche le banner
                    Text(user.avatarEmoji)
                        .font(.system(size: 36))
                        .frame(width: 72, height: 72)
                        .background(MoodTheme.channelList)
                        .clipShape(Circle())
                        .overlay(
                            Circle().stroke(MoodTheme.channelList, lineWidth: 4)
                        )
                        .overlay(alignment: .bottomTrailing) {
                            Circle()
                                .fill(MoodTheme.onlineGreen)
                                .frame(width: 16, height: 16)
                                .overlay(Circle().stroke(MoodTheme.channelList, lineWidth: 3))
                                .offset(x: 2, y: 2)
                        }
                        .offset(y: 36)
                }

                VStack(spacing: 4) {
                    Text(user.displayName)
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(MoodTheme.textPrimary)
                    Text("@\(user.username)")
                        .font(.system(size: 13))
                        .foregroundStyle(MoodTheme.textSecondary)
                }
                .padding(.top, 42)

                // Boutons d'action rapide (style Discord)
                HStack(spacing: 0) {
                    profileActionButton(icon: "pencil", label: "Modifier") {
                        showSettings = true
                    }
                    profileActionButton(icon: "face.smiling", label: "Statut") {}
                    profileActionButton(icon: "person.2.fill", label: "Amis") {}
                    profileActionButton(icon: "gearshape.fill", label: "Réglages") {
                        showSettings = true
                    }
                }
                .padding(.top, 20)
                .padding(.horizontal, 14)

                // Séparateur
                Rectangle().fill(MoodTheme.divider).frame(height: 0.5)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 16)

                // Déconnexion
                Button {
                    matrixStore.logout()
                    authState.isLoggedIn = false
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "rectangle.portrait.and.arrow.right")
                            .font(.system(size: 14))
                        Text("Déconnexion")
                            .font(.system(size: 14, weight: .medium))
                    }
                    .foregroundStyle(.red.opacity(0.8))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(Color.red.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .padding(.horizontal, 14)
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text("Toi")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(MoodTheme.textPrimary)
            }
        }
        .background(MoodTheme.channelList)
        .toolbarBackground(MoodTheme.serverBar, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
    }

    private func profileActionButton(icon: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 18))
                    .foregroundStyle(MoodTheme.textSecondary)
                    .frame(width: 40, height: 40)
                    .background(MoodTheme.glassBg)
                    .clipShape(Circle())
                Text(label)
                    .font(.system(size: 11))
                    .foregroundStyle(MoodTheme.textMuted)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
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
    }

    let friends = MockData.users
    var onOpenDM: ((MoodUser) -> Void)?
    var onShowProfile: ((MoodUser) -> Void)?
    var onCall: ((MoodUser) -> Void)?
    @State private var searchText = ""
    @State private var showAddFriend = false
    @State private var selectedTab: FriendsTab = .online

    var filteredFriends: [MoodUser] {
        if searchText.isEmpty { return friends }
        return friends.filter { $0.displayName.localizedCaseInsensitiveContains(searchText) || $0.username.localizedCaseInsensitiveContains(searchText) }
    }

    var onlineFriends: [MoodUser] {
        friends.filter { !$0.status.isOfflineLike }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 13 * LayoutMetrics.scale) {
                Button {
                    withAnimation(.easeOut(duration: 0.14)) { selectedTab = .online }
                } label: {
                    HStack(spacing: 8 * LayoutMetrics.scale) {
                        Image(systemName: "figure.wave")
                            .font(.mood(17, weight: .semibold))
                        Text("Amis")
                            .font(.mood(15, weight: .bold))
                    }
                    .foregroundStyle(MoodTheme.textPrimary)
                }
                .buttonStyle(.plain)

                Circle()
                    .fill(MoodTheme.textMuted.opacity(0.55))
                    .frame(width: 4 * LayoutMetrics.scale, height: 4 * LayoutMetrics.scale)

                HStack(spacing: 19 * LayoutMetrics.scale) {
                    ForEach([FriendsTab.all, FriendsTab.pending], id: \.self) { tab in
                        FriendsTabButton(tab: tab, isSelected: selectedTab == tab) {
                            withAnimation(.easeOut(duration: 0.14)) { selectedTab = tab }
                        }
                    }

                    Button { showAddFriend = true } label: {
                        Text("Ajouter")
                            .font(.mood(16, weight: .regular))
                            .foregroundStyle(.white)
                            .frame(width: 76 * LayoutMetrics.scale, height: 32 * LayoutMetrics.scale)
                            .background(MoodTheme.brandAccent)
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
            .frame(height: LayoutMetrics.desktopHeaderHeight)

            Rectangle()
                .fill(MoodTheme.divider)
                .frame(height: 1 * LayoutMetrics.scale)
                .offset(y: 0.25 * LayoutMetrics.scale)

            HStack(spacing: 0) {
                VStack(spacing: 0) {
                    if selectedTab == .all {
                        HStack(spacing: 8 * LayoutMetrics.scale) {
                            Image(systemName: "magnifyingglass")
                                .font(.mood(16, weight: .medium))
                                .foregroundStyle(MoodTheme.textPrimary)

                            TextField(
                                "",
                                text: $searchText,
                                prompt: Text("Rechercher")
                                    .foregroundColor(MoodTheme.friendsSearchPlaceholder)
                            )
                                .textFieldStyle(.plain)
                                .font(.mood(16))
                                .foregroundStyle(MoodTheme.textPrimary)

                            if !searchText.isEmpty {
                                Button { searchText = "" } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .font(.mood(12))
                                        .foregroundStyle(MoodTheme.textPrimary)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, 12 * LayoutMetrics.scale)
                        .frame(height: 40 * LayoutMetrics.scale)
                        .background(MoodTheme.headerSearchBackground)
                        .clipShape(RoundedRectangle(cornerRadius: 8 * LayoutMetrics.scale, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: 8 * LayoutMetrics.scale, style: .continuous)
                                .strokeBorder(MoodTheme.headerSearchBorder, lineWidth: 1 * LayoutMetrics.scale)
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

                Rectangle()
                    .fill(MoodTheme.divider)
                    .frame(width: 1 * LayoutMetrics.scale)
                    .offset(x: 0.25 * LayoutMetrics.scale)

                FriendsActivityPanel()
                    .frame(width: LayoutMetrics.friendsActivityPanelWidth)
            }
        }
        .background(MoodTheme.chatBackground)
        .overlay {
            if showAddFriend {
                ZStack {
                    Color.black.opacity(0.5)
                        .ignoresSafeArea()
                        .onTapGesture { showAddFriend = false }

                    AddFriendModal(isPresented: $showAddFriend)
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
            friendsEmptyState(icon: "person.crop.circle.badge.clock", title: "Aucune demande en attente", subtitle: "Les nouvelles demandes d'ami apparaîtront ici.")
        }
    }

    @ViewBuilder
    private var allFriendsSection: some View {
        if filteredFriends.isEmpty {
            friendsEmptyState(
                icon: "magnifyingglass",
                title: "Aucun résultat",
                subtitle: "Essaie avec un autre nom."
            )
        } else {
            Text("Tous les amis - \(filteredFriends.count)")
                .font(.mood(14, weight: .semibold))
                .foregroundStyle(Color(hex: "efeff1"))
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
        if users.isEmpty {
            friendsEmptyState(
                icon: searchText.isEmpty ? "person.2.slash" : "magnifyingglass",
                title: searchText.isEmpty ? "Personne ici pour le moment" : "Aucun résultat",
                subtitle: searchText.isEmpty ? "Ajoute des amis pour commencer à discuter." : "Essaie avec un autre nom."
            )
        } else {
            Text("\(title) — \(users.count)")
                .font(.mood(11, weight: .semibold))
                .tracking(0.35 * LayoutMetrics.scale)
                .foregroundStyle(MoodTheme.textSecondary)
                .padding(.horizontal, 20 * LayoutMetrics.scale)
                .padding(.top, 8 * LayoutMetrics.scale)
                .padding(.bottom, 8 * LayoutMetrics.scale)

            ForEach(users) { friend in
                FriendRow(
                    user: friend,
                    onMessage: { onOpenDM?(friend) },
                    onCall: { onCall?(friend) }
                )
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
    var body: some View {
        VStack(alignment: .leading, spacing: 9.5 * LayoutMetrics.scale) {
            Text("En ligne")
                .font(.mood(20, weight: .bold))
                .tracking(-0.65 * LayoutMetrics.scale)
                .foregroundStyle(MoodTheme.textPrimary)

            VStack(spacing: 8 * LayoutMetrics.scale) {
                Text("Tout est calme... pour le moment.")
                    .font(.mood(15, weight: .bold))
                    .foregroundStyle(MoodTheme.textPrimary)
                    .multilineTextAlignment(.center)

                Text("Quand un ami commencera une activité, comme jouer à un jeu ou passer du temps sur le chat vocal, ce sera affiché ici !")
                    .font(.mood(13))
                    .foregroundStyle(MoodTheme.textSupporting)
                    .multilineTextAlignment(.center)
                    .lineSpacing(1 * LayoutMetrics.scale)
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 16 * LayoutMetrics.scale)
            .padding(.top, 17 * LayoutMetrics.scale)
            .padding(.bottom, 19 * LayoutMetrics.scale)
            .background(MoodTheme.glassBg)
            .clipShape(RoundedRectangle(cornerRadius: 8 * LayoutMetrics.scale, style: .continuous))

            Spacer()
        }
        .padding(.horizontal, 16 * LayoutMetrics.scale)
        .padding(.top, 13.5 * LayoutMetrics.scale)
        .background(MoodTheme.chatBackground)
    }
}

struct FriendsTabButton: View {
    let tab: FriendsPlaceholderView.FriendsTab
    let isSelected: Bool
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Text(tab.rawValue)
                .font(.mood(15, weight: .medium))
                .foregroundStyle(isSelected ? MoodTheme.textPrimary : MoodTheme.textSecondary)
                .padding(.horizontal, 10 * LayoutMetrics.scale)
                .frame(height: 32 * LayoutMetrics.scale)
                .background(isSelected ? MoodTheme.selectedBg : isHovered ? MoodTheme.hoverBg : Color.clear)
                .clipShape(RoundedRectangle(cornerRadius: 6 * LayoutMetrics.scale, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.12)) { isHovered = hovering }
        }
    }
}

// MARK: - Add Friend Modal

struct AddFriendModal: View {
    @Environment(\.layoutMode) private var layoutMode
    @Binding var isPresented: Bool
    @State private var username = ""
    @State private var showSent = false

    var body: some View {
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

            Text("Tu peux ajouter des amis avec leur nom d'utilisateur Mood.")
                .font(.system(size: 13))
                .foregroundStyle(MoodTheme.textSecondary)

            HStack {
                TextField("Entre un nom d'utilisateur", text: $username)
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

                Button {
                    withAnimation(.easeInOut(duration: 0.2)) { showSent = true }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                        isPresented = false
                    }
                } label: {
                    HStack(spacing: 6) {
                        if showSent {
                            Image(systemName: "checkmark")
                                .font(.system(size: 11, weight: .bold))
                        }
                        Text(showSent ? "Envoyé !" : "Envoyer")
                            .font(.system(size: 13, weight: .semibold))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(showSent ? MoodTheme.onlineGreen : (username.isEmpty ? MoodTheme.brandAccent.opacity(0.4) : MoodTheme.brandAccent))
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .animation(.easeInOut(duration: 0.2), value: showSent)
                }
                .buttonStyle(.plain)
                .disabled(username.isEmpty || showSent)
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
        .shadow(color: .black.opacity(0.5), radius: 20, y: 8)
    }
}

// MARK: - Friend Row

struct FriendRow: View {
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
                Text(user.avatarEmoji)
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
                FriendActionButton(icon: "phone.fill", action: onCall)
                    .help("Appel vocal")
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
            Button { onCall() } label: { Label("Appel vocal", systemImage: "phone") }
            Button { showVideoCallAlert = true } label: { Label("Appel vidéo", systemImage: "video") }
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
            Button("Retirer", role: .destructive) {}
        } message: {
            Text("Es-tu sûr de vouloir retirer \(user.displayName) de ta liste d'amis ?")
        }
        .alert("Bloquer", isPresented: $showBlockConfirm) {
            Button("Annuler", role: .cancel) {}
            Button("Bloquer", role: .destructive) {}
        } message: {
            Text("Es-tu sûr de vouloir bloquer \(user.displayName) ?")
        }
    }
}

/// Discord-style unified row used only by the desktop `Tous` tab.
/// The online tab intentionally keeps `FriendRow`, whose call shortcut and
/// denser layout were already calibrated separately.
struct AllFriendRow: View {
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
            Rectangle()
                .fill(MoodTheme.friendRowSeparator)
                .frame(height: 1 * LayoutMetrics.scale)
                .padding(.leading, 30 * LayoutMetrics.scale)
                .padding(.trailing, 36 * LayoutMetrics.scale)

            HStack(spacing: 12 * LayoutMetrics.scale) {
                Button(action: onShowProfile) {
                    ZStack(alignment: .bottomTrailing) {
                        Text(user.avatarEmoji)
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
                        Text(user.displayName)
                            .font(.mood(16, weight: .semibold))
                            .foregroundStyle(MoodTheme.textPrimary)
                            .lineLimit(1)

                        Text(subtitle)
                            .font(.mood(15))
                            .foregroundStyle(MoodTheme.textSecondary)
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
                        Button { onCall() } label: {
                            Label("Appel vocal", systemImage: "phone")
                        }
                        Button { showVideoCallAlert = true } label: {
                            Label("Appel vidéo", systemImage: "video")
                        }
                        Divider()
                        Button(role: .destructive) { showRemoveConfirm = true } label: {
                            Label("Retirer l'ami", systemImage: "person.badge.minus")
                        }
                        Button(role: .destructive) { showBlockConfirm = true } label: {
                            Label("Bloquer", systemImage: "nosign")
                        }
                    } label: {
                        Image(systemName: "ellipsis")
                            .font(.mood(17, weight: .bold))
                            .rotationEffect(.degrees(90))
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
            Button { onCall() } label: { Label("Appel vocal", systemImage: "phone") }
            Button { showVideoCallAlert = true } label: { Label("Appel vidéo", systemImage: "video") }
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
            Button("Retirer", role: .destructive) {}
        } message: {
            Text("Es-tu sûr de vouloir retirer \(user.displayName) de ta liste d'amis ?")
        }
        .alert("Bloquer", isPresented: $showBlockConfirm) {
            Button("Annuler", role: .cancel) {}
            Button("Bloquer", role: .destructive) {}
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
            Image(systemName: icon)
                .font(.mood(16, weight: .semibold))
                .foregroundStyle(MoodTheme.textSupporting)
                .frame(width: 36 * LayoutMetrics.scale, height: 36 * LayoutMetrics.scale)
                .background(showsSurface ? MoodTheme.serverBar : Color.clear)
                .clipShape(Circle())
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(help)
    }
}

// MARK: - Inbox Panel

struct InboxPanel: View {
    @Environment(\.layoutMode) private var layoutMode
    @Binding var isPresented: Bool
    @State private var selectedTab = "Mentions"

    private let mockMentions: [(user: String, emoji: String, channel: String, server: String, content: String, time: String)] = [
        ("Clara", "🌸", "#general", "Design Club", "Hey @Augustin tu peux review le design ?", "Il y a 2h"),
        ("Maxime", "⚡", "#swiftui-help", "Swift Devs", "@Augustin j'ai un bug bizarre avec les Bindings", "Il y a 5h"),
        ("Sophie", "📚", "#general", "Book Club", "C'est @Augustin qui avait recommandé ce livre non ?", "Hier"),
    ]

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Boîte de réception")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(MoodTheme.textPrimary)
                Spacer()
                Button { isPresented = false } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 11))
                        .foregroundStyle(MoodTheme.textPrimary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            // Tabs
            HStack(spacing: 4) {
                ForEach(["Mentions", "Non lus"], id: \.self) { tab in
                    Button {
                        selectedTab = tab
                    } label: {
                        Text(tab)
                            .font(.system(size: 13, weight: selectedTab == tab ? .semibold : .regular))
                            .foregroundStyle(selectedTab == tab ? MoodTheme.textPrimary : MoodTheme.textSecondary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(selectedTab == tab ? MoodTheme.selectedBg : Color.clear)
                            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 8)

            Rectangle().fill(MoodTheme.divider).frame(height: 1)

            if selectedTab == "Mentions" {
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 2) {
                        ForEach(mockMentions, id: \.content) { mention in
                            HStack(alignment: .top, spacing: 10) {
                                Text(mention.emoji)
                                    .font(.system(size: 14))
                                    .frame(width: 32, height: 32)
                                    .background(MoodTheme.glassBg)
                                    .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))

                                VStack(alignment: .leading, spacing: 3) {
                                    HStack(spacing: 6) {
                                        Text(mention.user)
                                            .font(.system(size: 12, weight: .semibold))
                                            .foregroundStyle(MoodTheme.textPrimary)
                                        Text(mention.channel)
                                            .font(.system(size: 11))
                                            .foregroundStyle(MoodTheme.brandBlue)
                                        Text("·")
                                            .foregroundStyle(MoodTheme.textMuted)
                                        Text(mention.server)
                                            .font(.system(size: 11))
                                            .foregroundStyle(MoodTheme.textMuted)
                                    }
                                    Text(mention.content)
                                        .font(.system(size: 13))
                                        .foregroundStyle(MoodTheme.textSecondary)
                                        .lineLimit(2)
                                    Text(mention.time)
                                        .font(.system(size: 10))
                                        .foregroundStyle(MoodTheme.textMuted)
                                }
                                Spacer()
                            }
                            .padding(10)
                            .background(MoodTheme.hoverBg)
                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        }
                    }
                    .padding(10)
                }
            } else {
                VStack(spacing: 8) {
                    Image(systemName: "checkmark.circle")
                        .font(.system(size: 32))
                        .foregroundStyle(MoodTheme.textMuted)
                    Text("Tout est lu !")
                        .font(.system(size: 14))
                        .foregroundStyle(MoodTheme.textSecondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .adaptiveFrame(width: 400, height: 420, mode: layoutMode)
        .background(MoodTheme.popupBg)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(MoodTheme.glassBorder, lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.5), radius: 20, y: 8)
    }
}

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
