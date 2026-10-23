import SwiftUI

// MARK: - DM List Column

struct DMListView: View {
    @Environment(MatrixStore.self) private var matrixStore
    @Environment(\.desktopFriendsCalibration) private var calibrated
    let conversations: [DMConversation]
    @Binding var selectedDM: DMConversation?
    @Binding var showSettings: Bool
    var onShowMessageRequests: () -> Void = {}
    var onShowFriends: () -> Void = {}
    var onOpenQuickSwitcher: () -> Void = {}
    @State private var showNewMessage = false

    var body: some View {
        VStack(spacing: 0) {
            // Barre de recherche
            Button {
                onOpenQuickSwitcher()
            } label: {
                HStack(spacing: 0) {
                    Spacer(minLength: 0)
                    CalibratedDesktopText(value: "Recherche ou lance une conversation", size: calibrated ? 14 : 13, weight: calibrated ? .medium : .regular,
                                          glyphBackground: calibrated ? DesktopFriendsPalette.sidebarSearch : nil)
                    Spacer(minLength: 0)
                }
                .foregroundStyle(MoodTheme.textPrimary)
                .padding(.horizontal, 10 * LayoutMetrics.scale)
                .frame(height: 32 * LayoutMetrics.scale)
                .background(calibrated ? DesktopFriendsPalette.sidebarSearch : MoodTheme.dmSearchBackground)
                .clipShape(RoundedRectangle(cornerRadius: 8 * LayoutMetrics.scale, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 8 * LayoutMetrics.scale, style: .continuous)
                        .strokeBorder(calibrated ? DesktopFriendsPalette.rule : MoodTheme.dmSearchBorder, lineWidth: 1 * LayoutMetrics.scale)
                }
            }
            .buttonStyle(.plain)
            .padding(.leading, 9 * LayoutMetrics.scale)
            .padding(.trailing, 8 * LayoutMetrics.scale)
            .frame(height: calibrated ? DesktopFriendsPalette.headerHeight : LayoutMetrics.desktopHeaderHeight)

            if calibrated {
                DesktopFriendsRule(color: DesktopFriendsPalette.sidebarSearch)
            } else {
                Rectangle().fill(MoodTheme.divider)
                    .frame(height: LayoutMetrics.scale).offset(y: 0.25 * LayoutMetrics.scale)
            }

            ScrollView(showsIndicators: false) {
                VStack(spacing: 2 * LayoutMetrics.scale) {
                    SidebarNavItem(icon: "figure.wave", label: "Amis", iconSize: 17, isSelected: selectedDM == nil) {
                        selectedDM = nil
                        onShowFriends()
                    }

                    if calibrated {
                        SidebarNavItem(icon: "envelope.fill", label: "Demandes de message", isSelected: false,
                                       action: onShowMessageRequests)
                    }




                    DesktopFriendsRule(color: calibrated ? DesktopFriendsPalette.sidebarSearch : MoodTheme.workspaceBorder)
                        .padding(.leading, 9 * LayoutMetrics.scale)
                        .padding(.trailing, 8 * LayoutMetrics.scale)
                        .padding(.top, 11 * LayoutMetrics.scale)
                        .padding(.bottom, 6 * LayoutMetrics.scale)

                    // Header messages privés
                    HStack {
                        CalibratedDesktopText(value: "Messages privés", size: calibrated ? 14 : 12, weight: .medium,
                                              color: calibrated ? DesktopFriendsPalette.hint : MoodTheme.textSubtle,
                                              glyphBackground: calibrated ? MoodTheme.channelList : nil)
                            .offset(x: calibrated ? 1 : 0, y: calibrated ? -1 : 0)

                        Spacer()

                        Button { showNewMessage = true } label: {
                            CalibratedDesktopSymbol(name: "plus", size: 12)
                                .foregroundStyle(MoodTheme.textPrimary)
                        }
                        .buttonStyle(.plain)
                        .help("Nouveau message")
                    }
                    .padding(.horizontal, 16 * LayoutMetrics.scale)
                    .padding(.top, (calibrated ? 5 : 7) * LayoutMetrics.scale)
                    .padding(.bottom, (calibrated ? 3 : 4) * LayoutMetrics.scale)

                    if conversations.isEmpty && matrixStore.userId != nil && matrixStore.connection != .connected {
                        ConversationCacheEmptyState()
                    } else if conversations.isEmpty {
                        VStack(spacing: 8 * LayoutMetrics.scale) {
                            Image(systemName: "bubble.left.and.bubble.right")
                                .font(.mood(24))
                                .foregroundStyle(MoodTheme.textMuted)
                            Text("Aucune conversation")
                                .font(.mood(13, weight: .medium))
                                .foregroundStyle(MoodTheme.textSecondary)
                            Text("Appuie sur + pour lancer un message")
                                .font(.mood(11))
                                .foregroundStyle(MoodTheme.textMuted)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 24 * LayoutMetrics.scale)
                    }

                    ForEach(conversations) { convo in
                        DMRow(
                            conversation: convo,
                            isSelected: selectedDM?.id == convo.id
                        ) {
                            selectedDM = convo
                        }
                    }
                }
                .padding(.top, 9 * LayoutMetrics.scale)
            }

            Spacer(minLength: 0)
        }
        .padding(.bottom, LayoutMetrics.channelBottomPadding)
        .background(MoodTheme.channelList)
        .sheet(isPresented: $showNewMessage) {
            NewDMSheet { conversationId in
                if let convo = matrixStore.dmConversations.first(where: { $0.id == conversationId }) {
                    selectedDM = convo
                }
            }
            .environment(matrixStore)
            .presentationDetents([.medium, .large])
        }
    }
}

// MARK: - Sidebar Nav Item

struct SidebarNavItem: View {
    @Environment(\.desktopFriendsCalibration) private var calibrated
    let icon: String
    let label: String
    var badgeText: String? = nil
    var iconSize: CGFloat = 15
    let isSelected: Bool
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 9 * LayoutMetrics.scale) {
                CalibratedDesktopSymbol(name: icon, size: iconSize, calibratedSize: 20)
                    .frame(width: 20 * LayoutMetrics.scale)

                CalibratedDesktopText(value: label, size: calibrated ? 16 : 15, weight: .medium,
                                      color: isSelected ? (calibrated ? DesktopFriendsPalette.sidebarPrimary : MoodTheme.textPrimary) : MoodTheme.textSecondary,
                                      glyphBackground: calibrated ? (isSelected ? DesktopFriendsPalette.selected : isHovered ? MoodTheme.hoverBg : MoodTheme.channelList) : nil)
                    .offset(y: calibrated ? -1 : 0)

                Spacer()

                if let badgeText {
                    CalibratedDesktopText(value: badgeText, size: 11, weight: .bold, color: Color(hex: "34343a"))
                        .padding(.horizontal, 10 * LayoutMetrics.scale)
                        .frame(height: 16 * LayoutMetrics.scale)
                        .background(MoodTheme.textPrimary)
                        .clipShape(Capsule())
                }
            }
            .foregroundStyle(isSelected ? MoodTheme.textPrimary : MoodTheme.textSecondary)
            .padding(.horizontal, (calibrated ? 11 : 10.5) * LayoutMetrics.scale)
            .frame(height: 38 * LayoutMetrics.scale)
            .background(
                isSelected ? (calibrated ? DesktopFriendsPalette.selected : MoodTheme.selectedBg) :
                isHovered ? MoodTheme.hoverBg :
                Color.clear
            )
            .clipShape(RoundedRectangle(cornerRadius: 8 * LayoutMetrics.scale, style: .continuous))
            .padding(.leading, 9 * LayoutMetrics.scale)
            .padding(.trailing, 8 * LayoutMetrics.scale)
        }
        .buttonStyle(.plain)
        .onHover { hovering in isHovered = hovering }
    }
}

// MARK: - DM Row

struct DMRow: View {
    @Environment(\.desktopFriendsCalibration) private var calibrated
    let conversation: DMConversation
    let isSelected: Bool
    let action: () -> Void
    @Environment(MatrixStore.self) private var matrixStore
    @State private var isHovered = false
    @State private var showProfile = false

    private var isMuted: Bool { matrixStore.isMuted(conversation) }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12 * LayoutMetrics.scale) {
                // Avatar circle + status
                ZStack(alignment: .bottomTrailing) {
                    AvatarGlyph(user: conversation.participant)
                        .font(.mood(20))
                        .frame(width: 32 * LayoutMetrics.scale, height: 32 * LayoutMetrics.scale)
                        .background(MoodTheme.glassBg)
                        .clipShape(Circle())

                    StatusIndicator(status: conversation.participant.status, size: 10 * LayoutMetrics.scale, borderColor: MoodTheme.channelList)
                        .offset(x: 2, y: 2)
                }

                VStack(alignment: .leading, spacing: 2) {
                    CalibratedDesktopText(value: conversation.participant.displayName, size: calibrated ? 16 : 14, weight: .medium,
                                          color: conversation.unreadCount > 0 ? MoodTheme.textPrimary : MoodTheme.textSecondary)

                    CalibratedDesktopText(value: conversation.participant.status.publicLabel, size: calibrated ? 12 : 11, color: MoodTheme.textMuted)
                }

                Spacer()

                if conversation.unreadCount > 0 {
                    Text("\(conversation.unreadCount)")
                        .desktopFriendsFont(10, weight: .bold)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6 * LayoutMetrics.scale)
                        .padding(.vertical, 2 * LayoutMetrics.scale)
                        .background(MoodTheme.mentionBadge)
                        .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                }

            }
            .opacity(isMuted && !isSelected ? 0.45 : 1) // Discord dims muted conversations
            .padding(.horizontal, 10 * LayoutMetrics.scale)
            .padding(.vertical, calibrated ? 0 : 8 * LayoutMetrics.scale)
            .frame(height: calibrated ? 42 * LayoutMetrics.scale : nil)
            .background(
                isSelected && conversation.unreadCount > 0 ? MoodTheme.selectedBg :
                isHovered ? MoodTheme.hoverBg :
                Color.clear
            )
            .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
            .padding(.horizontal, 8)
        }
        .buttonStyle(.plain)
        .onHover { hovering in isHovered = hovering }
        .contextMenu {
            Button { showProfile = true } label: { Label("Voir le profil", systemImage: "person.crop.circle") }
            if matrixStore.userId != nil {
                if matrixStore.isGroupDM(conversation), let roomId = matrixStore.roomId(for: conversation) {
                    Button("Quitter le groupe", role: .destructive) { Task { await matrixStore.leaveRoom(roomId) } }
                }
                Button { Task { await matrixStore.setMuted(!isMuted, conversation: conversation) } } label: {
                    Label(isMuted ? "Rétablir le son" : "Rendre muet", systemImage: isMuted ? "bell" : "bell.slash")
                }
            }
        }
        .popover(isPresented: $showProfile, arrowEdge: .trailing) {
            UserProfilePopup(user: conversation.participant)
                .adaptiveFrame(width: 320, height: 400, mode: .regular)
        }

    }
}

// MARK: - DM Chat Area

struct DMChatArea: View {
    @Environment(AccountStore.self) private var accountStore
    @Environment(\.desktopFriendsCalibration) private var calibrated
    @State private var showDesktopProfile = true
    @Environment(MatrixStore.self) private var matrixStore
    @Environment(AuthState.self) private var authState
    @Environment(\.layoutMode) private var layoutMode
    let conversation: DMConversation
    @Binding var showProfilePopup: Bool
    @Binding var profileUser: MoodUser?
    var onBack: (() -> Void)?
    @State private var messageText = ""
    @State private var replyingTo: ChatMessage?
    @State private var activeCall: CallType?
    @State private var showPinnedMessages = false
    @State private var showSearch = false
    @State private var search = MessageSearchModel()
    @FocusState private var searchFocused: Bool
    @State private var showInlineProfile = false
    @State private var typingTask: Task<Void, Never>?
    @State private var isTyping = false
    @State private var showFirstRunBlock = false

    private var messages: [ChatMessage] {
        let storeMessages = matrixStore.messages(forDM: conversation)
        if storeMessages.isEmpty && authState.isDemoMode {
            return MockData.dmMessages(for: conversation)
        }
        return storeMessages
    }

    private func attach(_ url: URL) {
        guard let roomId else { return }
        Task { await matrixStore.sendAttachment(roomId: roomId, fileURL: url) }
    }

    private var roomId: String? {
        matrixStore.roomId(for: conversation)
    }

    private var isEncrypted: Bool {
        guard let roomId else { return false }
        return matrixStore.isRoomEncrypted(roomId)
    }

    private var hasMoreHistory: Bool {
        guard let roomId else { return false }
        return matrixStore.hasMoreHistory[roomId] == true
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header DM — masqué sur compact (NavigationStack fournit le titre)
            if layoutMode == .regular {
                HStack(spacing: 10 * LayoutMetrics.scale) {
                    AvatarGlyph(user: conversation.participant)
                        .font(.mood(14))
                        .frame(width: 30 * LayoutMetrics.scale, height: 30 * LayoutMetrics.scale)
                        .background(MoodTheme.glassBg)
                        .clipShape(Circle())

                    Text(conversation.participant.displayName)
                        .desktopFriendsFont(calibrated ? 16 : 15, weight: calibrated ? .medium : .bold)
                        .foregroundStyle(MoodTheme.textPrimary)
                        .lineLimit(1)

                    Spacer()

                    HStack(spacing: 6 * LayoutMetrics.scale) {
                        // Calls are simulated: demo only, never in a real Matrix session.
                        if matrixStore.callsAvailable {
                            HeaderButton(icon: "phone.fill") {
                                activeCall = .voice
                            }
                            .help("Appel vocal")
                            HeaderButton(icon: "video.fill") {
                                activeCall = .video
                            }
                            .help("Appel vidéo")
                        }
                        HeaderButton(icon: "pin") {
                            showPinnedMessages.toggle()
                        }
                        .help("Messages épinglés")

                        HeaderButton(icon: "person.crop.circle") {
                            if calibrated { showDesktopProfile.toggle() } else { showInlineProfile.toggle() }
                        }
                        .help(calibrated && showDesktopProfile ? "Masquer le profil" : "Afficher le profil")
                        .popover(isPresented: $showInlineProfile, arrowEdge: .top) {
                            UserProfilePopup(user: conversation.participant)
                                .adaptiveFrame(width: 320, height: 400, mode: layoutMode)
                        }

                        HeaderSearchField(
                            text: $search.query,
                            isActive: showSearch,
                            focus: $searchFocused,
                            onSubmit: runSearch,
                            onClear: closeSearch
                        )
                        .padding(.leading, 4 * LayoutMetrics.scale)
                    }
                }
                .padding(.horizontal, 16 * LayoutMetrics.scale)
                .frame(height: LayoutMetrics.desktopHeaderHeight)

                DesktopPixelRule()
            }

            HStack(spacing: 0) {
                VStack(spacing: 0) {
                    ConversationRecoveryNotices()
                    // Pinned messages panel
                    if showPinnedMessages {
                        PinnedMessagesPanel(
                            messages: messages.filter { $0.isPinned },
                            server: nil,
                            showPanel: $showPinnedMessages
                        )
                    }

                    // Messages
                    ScrollView {
                        ScrollViewReader { proxy in
                            LazyVStack(spacing: 0) {
                                if hasMoreHistory, !matrixStore.firstRunHistoryStart(roomId: roomId), let roomId {
                                    LoadMoreHistoryButton(roomId: roomId)
                                } else if matrixStore.firstRunHistoryStart(roomId: roomId) || (roomId == nil && authState.isDemoMode) {
                                    DirectMessageBeginningState(user: conversation.participant,
                                        username: authState.isDemoMode && matrixStore.userId == nil ? conversation.participant.username
                                            : accountStore.moodUsername(for: conversation.participant, currentUserId: matrixStore.userId),
                                        onBlock: matrixStore.firstRunCanBlock(conversation) ? { showFirstRunBlock = true } : nil,
                                        supportsOfflineDelivery: !isEncrypted)
                                    DesktopPixelRule().padding(.horizontal, 16 * LayoutMetrics.scale)
                                }

                                if messages.isEmpty, let roomId, !matrixStore.firstRunHistoryStart(roomId: roomId) {
                                    FirstRunHistoryPlaceholder(roomID: roomId)
                                } else if messages.isEmpty {
                                    Text("Aucun message pour l'instant. Dis bonjour 👋")
                                        .desktopFriendsFont(calibrated ? 16 : 13)
                                        .foregroundStyle(MoodTheme.textSecondary)
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 24 * LayoutMetrics.scale)
                                }

                                ForEach(messages) { message in
                                    MessageRow(message: message, server: nil, roomId: roomId, onReply: { replyingTo = message }) {
                                        profileUser = message.sender
                                        showProfilePopup = true
                                    }
                                    .id(message.id)
                                }
                            }
                            .onAppear {
                                if let lastID = messages.last?.id {
                                    proxy.scrollTo(lastID, anchor: .bottom)
                                }
                            }
                            .onChange(of: messages.count) { _, _ in
                                if let lastID = messages.last?.id {
                                    proxy.scrollTo(lastID, anchor: .bottom)
                                }
                            }
                            .jumpToRequestedMessage(roomId: roomId, messages: messages, proxy: proxy)
                        }
                    }
                    .scrollDismissesKeyboard(.interactively)

                    if isEncrypted {
                        EncryptedRoomNotice()
                    }

                    MessageInputBar(
                        text: $messageText,
                        channelName: conversation.participant.displayName,
                        isE2E: isEncrypted,
                        isDirectMessage: calibrated,
                        typingUsers: roomId.flatMap { matrixStore.typingUsersByRoom[$0] } ?? [],
                        isDisabled: isEncrypted,
                        replyingTo: $replyingTo,
                        onSend: sendCurrentMessage,
                        onAttachFile: attach
                    ).messageUndoAccessory()
                }

                if showSearch, layoutMode == .regular {
                    DesktopPixelRule(vertical: true)

                    SearchPanel(
                        model: search,
                        scope: .dm(conversation),
                        onClose: closeSearch,
                        onOpen: openSearchResult
                    )
                }
                if calibrated && showDesktopProfile {
                    DesktopDMProfilePanel(user: conversation.participant) {
                        profileUser = conversation.participant
                        showProfilePopup = true
                    }
                }
            }
        }
        .background(MoodTheme.chatBackground)
        .messageSearchSupport(
            model: search,
            scope: .dm(conversation),
            isOpen: showSearch,
            focus: $searchFocused,
            resetKey: conversation.id,
            onClose: closeSearch
        )
        .task(id: roomId) { if let roomId { await matrixStore.loadConversationHistory(roomId: roomId) } }
        .alert("Bloquer cette personne ?", isPresented: $showFirstRunBlock) {
            Button("Annuler", role: .cancel) {}
            Button("Bloquer", role: .destructive) {
                if let id = conversation.participant.matrixId { Task { await matrixStore.setBlocked(id, blocked: true) } }
            }
        } message: { Text("Tu ne verras plus ses messages.") }
        .onAppear { markConversationAsRead() }
        .onChange(of: conversation.id) { _, _ in markConversationAsRead() }
        .onChange(of: messageText) { _, newValue in
            guard !newValue.isEmpty else { return }
            scheduleTypingNotification()
        }
        .onDisappear { stopTyping() }
        .overlay {
            if let call = activeCall {
                Group {
                    switch call {
                    case .voice:
                        VoiceCallView(participant: conversation.participant) {
                            activeCall = nil
                        }
                    case .video:
                        VideoCallView(participant: conversation.participant) {
                            activeCall = nil
                        }
                    }
                }
                .transition(.opacity)
            }
        }
    }

    private func sendCurrentMessage() {
        let trimmed = messageText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        guard let roomId else {
            if authState.isDemoMode {
                messageText = ""
            } else {
                matrixStore.errorMessage = "Impossible d'envoyer : cette conversation n’est pas encore disponible."
            }
            return
        }
        guard matrixStore.validateOutgoingText(trimmed) else { return } // over 4 000: keep the text
        stopTyping()
        let text = trimmed
        let replyToEventId = replyingTo?.eventId
        Task {
            await matrixStore.sendMessage(roomId: roomId, text: text, replyToEventId: replyToEventId)
        }
        messageText = ""
        replyingTo = nil
    }

    private func markConversationAsRead() {
        guard let roomId else { return }
        matrixStore.markAsRead(roomId: roomId)
    }

    // MARK: Search

    private func runSearch() {
        showSearch = true
        search.submit(store: matrixStore, scope: .dm(conversation))
    }

    private func closeSearch() {
        showSearch = false
        searchFocused = false
        search.reset()
    }

    /// Every result lives in this conversation: scroll to the message.
    private func openSearchResult(_ hit: SearchHit) {
        matrixStore.requestJump(roomId: hit.roomId, eventId: hit.eventId)
    }

    private func scheduleTypingNotification() {
        guard let roomId else { return }
        if !isTyping {
            isTyping = true
            Task { await matrixStore.setTyping(roomId: roomId, typing: true) }
        }
        typingTask?.cancel()
        typingTask = Task {
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }
            isTyping = false
            await matrixStore.setTyping(roomId: roomId, typing: false)
        }
    }

    private func stopTyping() {
        typingTask?.cancel()
        typingTask = nil
        guard isTyping, let roomId else {
            isTyping = false
            return
        }
        isTyping = false
        Task { await matrixStore.setTyping(roomId: roomId, typing: false) }
    }
}

#Preview {
    DMListView(
        conversations: MockData.dmConversations,
        selectedDM: .constant(nil),
        showSettings: .constant(false)
    )
    .frame(width: 240, height: 700)
    .environment(MatrixStore())
    .preferredColorScheme(.dark)
}
