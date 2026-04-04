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

    // Fallback sur MockData si le store Matrix est vide
    private var servers: [MoodServer] {
        matrixStore.servers.isEmpty ? MockData.servers : matrixStore.servers
    }
    private var conversations: [DMConversation] {
        matrixStore.dmConversations.isEmpty ? MockData.dmConversations : matrixStore.dmConversations
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
        .sheet(isPresented: $showProfilePopup) {
            if let user = profileUser {
                UserProfilePopup(user: user, server: selectedServer)
                    .presentationDetents([.medium])
            }
        }
        .sheet(isPresented: $showSettings) {
            AccountSettingsView(isPresented: $showSettings, authState: authState)
                .preferredColorScheme(.dark)
        }
        .sheet(isPresented: $showCreateServer) {
            CreateServerModal(isPresented: $showCreateServer)
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
    }

    // MARK: - Desktop Layout (inchangé)

    @ViewBuilder
    private var desktopLayout: some View {
        ZStack {
            MoodTheme.subtleGlow.ignoresSafeArea()

            HStack(spacing: 0) {
                ServerSidebarView(
                    servers: servers,
                    selectedServer: $selectedServer,
                    showDMs: $showDMs,
                    selectedChannel: $selectedChannel,
                    showCreateServer: $showCreateServer,
                    showExplore: $showExplore,
                    dmUnreadCount: conversations.reduce(0) { $0 + $1.unreadCount }
                )

                if !showExplore {
                    Group {
                        if showDMs {
                            DMListView(
                                conversations: conversations,
                                selectedDM: $selectedDM,
                                showSettings: $showSettings
                            )
                        } else if let server = selectedServer {
                            ChannelListColumn(
                                server: server,
                                selectedChannel: $selectedChannel,
                                showSettings: $showSettings
                            )
                        }
                    }
                    .frame(width: 240)
                    .transition(.move(edge: .leading).combined(with: .opacity))
                }

                Group {
                    if showExplore {
                        ExploreServersView()
                    } else if showDMs {
                        if let dm = selectedDM {
                            DMChatArea(
                                conversation: dm,
                                showProfilePopup: $showProfilePopup,
                                profileUser: $profileUser,
                                onBack: {
                                    withAnimation(.easeInOut(duration: 0.2)) {
                                        selectedDM = nil
                                    }
                                }
                            )
                            .transition(.move(edge: .trailing).combined(with: .opacity))
                        } else {
                            FriendsPlaceholderView(
                                onOpenDM: { user in
                                    if let convo = conversations.first(where: { $0.participant.id == user.id }) {
                                        withAnimation(.easeInOut(duration: 0.2)) {
                                            selectedDM = convo
                                        }
                                    }
                                },
                                onShowProfile: { user in
                                    profileUser = user
                                    showProfilePopup = true
                                },
                                onCall: { user in
                                    withAnimation(.easeInOut(duration: 0.25)) {
                                        callingUser = user
                                    }
                                }
                            )
                            .transition(.opacity)
                        }
                    } else if let channel = selectedChannel {
                        ChatArea(
                            channel: channel,
                            server: selectedServer!,
                            showProfilePopup: $showProfilePopup,
                            profileUser: $profileUser
                        )
                    } else {
                        EmptyStateView()
                    }
                }
                .transition(.opacity)
            }
            .animation(.easeInOut(duration: 0.2), value: showDMs)
            .animation(.easeInOut(duration: 0.15), value: selectedServer?.id)
            .animation(.easeInOut(duration: 0.15), value: selectedChannel?.id)
            .animation(.easeInOut(duration: 0.15), value: selectedDM?.id)
        }
        .ignoresSafeArea()
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
                    profileUser: $profileUser
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
                    callingUser: $callingUser
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
}

// MARK: - Compact Server List (iPhone)

struct CompactServerListView: View {
    let servers: [MoodServer]
    @Binding var showCreateServer: Bool
    @Binding var showProfilePopup: Bool
    @Binding var profileUser: MoodUser?
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
            CompactChannelListView(
                server: server,
                showProfilePopup: $showProfilePopup,
                profileUser: $profileUser
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
                        NavigationLink(value: channel) {
                            HStack(spacing: 8) {
                                Image(systemName: channel.icon)
                                    .font(.system(size: 13))
                                    .foregroundStyle(channel.unreadCount > 0 ? MoodTheme.textPrimary : MoodTheme.textMuted)
                                    .frame(width: 18)

                                Text(channel.name)
                                    .font(.system(size: 15, weight: channel.unreadCount > 0 ? .semibold : .regular))
                                    .foregroundStyle(channel.unreadCount > 0 ? MoodTheme.textPrimary : MoodTheme.textSecondary)

                                Spacer()

                                if channel.unreadCount > 0 {
                                    Text("\(channel.unreadCount)")
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
            CompactChatWrapper(
                channel: channel,
                server: server,
                showProfilePopup: $showProfilePopup,
                profileUser: $profileUser
            )
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
            CompactDMChatWrapper(
                conversation: convo,
                showProfilePopup: $showProfilePopup,
                profileUser: $profileUser
            )
        }
        .background(MoodTheme.channelList)
        .toolbarBackground(MoodTheme.serverBar, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
    }

    private var onlineFriendsCarousel: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 16) {
                ForEach(MockData.users.filter { $0.status == .online }) { user in
                    VStack(spacing: 4) {
                        ZStack(alignment: .bottomTrailing) {
                            Text(user.avatarEmoji)
                                .font(.system(size: 18))
                                .frame(width: 44, height: 44)
                                .background(MoodTheme.glassBg)
                                .clipShape(Circle())
                            StatusIndicator(status: .online, size: 10, borderColor: MoodTheme.channelList)
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
    let friends = MockData.users
    var onOpenDM: ((MoodUser) -> Void)?
    var onShowProfile: ((MoodUser) -> Void)?
    var onCall: ((MoodUser) -> Void)?
    @State private var searchText = ""
    @State private var showAddFriend = false

    var filteredFriends: [MoodUser] {
        if searchText.isEmpty { return friends }
        return friends.filter { $0.displayName.localizedCaseInsensitiveContains(searchText) || $0.username.localizedCaseInsensitiveContains(searchText) }
    }

    var onlineFriends: [MoodUser] {
        filteredFriends.filter { $0.status != .offline }
    }

    var offlineFriends: [MoodUser] {
        filteredFriends.filter { $0.status == .offline }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Image(systemName: "person.2.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(MoodTheme.textPrimary)

                Text("Amis")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(MoodTheme.textPrimary)

                Spacer()

                Button { showAddFriend = true } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "plus")
                            .font(.system(size: 13, weight: .semibold))
                        Text("Ajouter")
                            .font(.system(size: 13, weight: .semibold))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(MoodTheme.brandAccent)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)

            // Barre de recherche
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 13))
                    .foregroundStyle(MoodTheme.textMuted)

                TextField("Rechercher un ami...", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                    .foregroundStyle(MoodTheme.textPrimary)

                if !searchText.isEmpty {
                    Button { searchText = "" } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 12))
                            .foregroundStyle(MoodTheme.textPrimary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(MoodTheme.glassBg)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .padding(.horizontal, 20)
            .padding(.vertical, 12)

            // Liste d'amis
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 4) {
                    if !onlineFriends.isEmpty {
                        Text("EN LIGNE — \(onlineFriends.count)")
                            .font(.system(size: 11, weight: .semibold))
                            .tracking(0.4)
                            .foregroundStyle(MoodTheme.textSecondary)
                            .padding(.horizontal, 20)
                            .padding(.top, 4)
                            .padding(.bottom, 6)

                        ForEach(onlineFriends) { friend in
                            FriendRow(user: friend, onMessage: { onOpenDM?(friend) }, onCall: { onCall?(friend) })
                        }
                    }

                    if !offlineFriends.isEmpty {
                        Text("HORS LIGNE — \(offlineFriends.count)")
                            .font(.system(size: 11, weight: .semibold))
                            .tracking(0.4)
                            .foregroundStyle(MoodTheme.textSecondary)
                            .padding(.horizontal, 20)
                            .padding(.top, 16)
                            .padding(.bottom, 6)

                        ForEach(offlineFriends) { friend in
                            FriendRow(user: friend, onMessage: { onOpenDM?(friend) }, onCall: { onCall?(friend) })
                        }
                    }

                    if onlineFriends.isEmpty && offlineFriends.isEmpty && !searchText.isEmpty {
                        VStack(spacing: 8) {
                            Image(systemName: "magnifyingglass")
                                .font(.system(size: 28))
                                .foregroundStyle(MoodTheme.textMuted)
                            Text("Aucun résultat pour \"\(searchText)\"")
                                .font(.system(size: 14))
                                .foregroundStyle(MoodTheme.textSecondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.top, 60)
                    }
                }
                .padding(.bottom, 20)
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
        HStack(spacing: 14) {
            // Avatar circle + status
            ZStack(alignment: .bottomTrailing) {
                Text(user.avatarEmoji)
                    .font(.system(size: 20))
                    .frame(width: 36, height: 36)
                    .background(MoodTheme.glassBg)
                    .clipShape(Circle())
                    .opacity(user.status == .offline ? 0.5 : 1)

                StatusIndicator(status: user.status, size: 10, borderColor: MoodTheme.chatBackground)
                    .offset(x: 3, y: 3)
            }

            // Nom + status
            VStack(alignment: .leading, spacing: 2) {
                Text(user.displayName)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(user.status == .offline ? MoodTheme.textMuted : MoodTheme.textPrimary)

                Text(user.status == .online ? "En ligne" : "Hors ligne")
                    .font(.system(size: 12))
                    .foregroundStyle(MoodTheme.textSecondary)
            }

            Spacer()

            // Actions
            HStack(spacing: 6) {
                FriendActionButton(icon: "bubble.left.fill", action: onMessage)
                    .help("Envoyer un message")
                FriendActionButton(icon: "phone.fill", action: onCall)
                    .help("Appel vocal")
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(isHovered ? MoodTheme.hoverBg : Color.clear)
        )
        .padding(.horizontal, 8)
        .contentShape(Rectangle())
        .onHover { hovering in isHovered = hovering }
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
                .font(.system(size: 16))
                .foregroundStyle(MoodTheme.textPrimary)
                .frame(width: 30, height: 30)
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
