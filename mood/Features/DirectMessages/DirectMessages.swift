import SwiftUI

// MARK: - DM List Column

struct DMListView: View {
    @Environment(MatrixStore.self) private var matrixStore
    let conversations: [DMConversation]
    @Binding var selectedDM: DMConversation?
    @Binding var showSettings: Bool
    /// Opens the desktop quick switcher overlay hosted by ContentView.
    var onOpenQuickSwitcher: () -> Void = {}
    @State private var showComingSoon = false
    @State private var showNewMessage = false

    var body: some View {
        VStack(spacing: 0) {
            // Barre de recherche
            Button(action: onOpenQuickSwitcher) {
                HStack(spacing: 0) {
                    Spacer(minLength: 0)
                    Text("Recherche ou lance une conversation")
                        .font(.mood(13))
                    Spacer(minLength: 0)
                }
                .foregroundStyle(MoodTheme.textPrimary)
                .padding(.horizontal, 10 * LayoutMetrics.scale)
                .frame(height: 32 * LayoutMetrics.scale)
                .background(MoodTheme.dmSearchBackground)
                .clipShape(RoundedRectangle(cornerRadius: 8 * LayoutMetrics.scale, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 8 * LayoutMetrics.scale, style: .continuous)
                        .strokeBorder(MoodTheme.dmSearchBorder, lineWidth: 1 * LayoutMetrics.scale)
                }
            }
            .buttonStyle(.plain)
            .padding(.leading, 9 * LayoutMetrics.scale)
            .padding(.trailing, 8 * LayoutMetrics.scale)
            .frame(height: LayoutMetrics.desktopHeaderHeight)

            Rectangle()
                .fill(MoodTheme.divider)
                .frame(height: 1 * LayoutMetrics.scale)
                .offset(y: 0.25 * LayoutMetrics.scale)

            ScrollView(showsIndicators: false) {
                VStack(spacing: 2 * LayoutMetrics.scale) {
                    SidebarNavItem(icon: "figure.wave", label: "Amis", iconSize: 17, isSelected: selectedDM == nil) {
                        selectedDM = nil
                    }

                    SidebarNavItem(icon: "circle.hexagongrid.fill", label: "Nitro", isSelected: false) { showComingSoon = true }

                    SidebarNavItem(icon: "bag.fill", label: "Boutique", badgeText: "NOUVEAU", isSelected: false) { showComingSoon = true }

                    SidebarNavItem(icon: "flag.fill", label: "Quêtes", isSelected: false) { showComingSoon = true }

                    Rectangle()
                        .fill(MoodTheme.workspaceBorder)
                        .frame(height: 1 * LayoutMetrics.scale)
                        .padding(.leading, 9 * LayoutMetrics.scale)
                        .padding(.trailing, 8 * LayoutMetrics.scale)
                        .padding(.top, 11 * LayoutMetrics.scale)
                        .padding(.bottom, 6 * LayoutMetrics.scale)

                    // Header messages privés
                    HStack {
                        Text("Messages privés")
                            .font(.mood(12, weight: .medium))
                            .foregroundStyle(MoodTheme.textSubtle)

                        Spacer()

                        Button { showNewMessage = true } label: {
                            Image(systemName: "plus")
                                .font(.mood(12))
                                .foregroundStyle(MoodTheme.textPrimary)
                        }
                        .buttonStyle(.plain)
                        .help("Nouveau message")
                    }
                    .padding(.horizontal, 16 * LayoutMetrics.scale)
                    .padding(.top, 7 * LayoutMetrics.scale)
                    .padding(.bottom, 4 * LayoutMetrics.scale)

                    if conversations.isEmpty {
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
        .alert("Bientôt disponible", isPresented: $showComingSoon) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Cette fonctionnalité arrive dans une prochaine version de Mood.")
        }
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
                Image(systemName: icon)
                    .font(.mood(iconSize))
                    .frame(width: 20 * LayoutMetrics.scale)

                Text(label)
                    .font(.mood(15, weight: .medium))

                Spacer()

                if let badgeText {
                    Text(badgeText)
                        .font(.mood(11, weight: .bold))
                        .foregroundStyle(Color(hex: "34343a"))
                        .padding(.horizontal, 10 * LayoutMetrics.scale)
                        .frame(height: 16 * LayoutMetrics.scale)
                        .background(MoodTheme.textPrimary)
                        .clipShape(Capsule())
                }
            }
            .foregroundStyle(isSelected ? MoodTheme.textPrimary : MoodTheme.textSecondary)
            .padding(.horizontal, 10.5 * LayoutMetrics.scale)
            .frame(height: 38 * LayoutMetrics.scale)
            .background(
                isSelected ? MoodTheme.selectedBg :
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
    @Environment(MatrixStore.self) private var matrixStore
    let conversation: DMConversation
    let isSelected: Bool
    let action: () -> Void
    @State private var isHovered = false
    @State private var isMuted = false
    @State private var showProfile = false
    @State private var showCallAlert = false
    @State private var showClosedFeedback = false

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
                    Text(conversation.participant.displayName)
                        .font(.mood(14, weight: .medium))
                        .foregroundStyle(conversation.unreadCount > 0 ? MoodTheme.textPrimary : MoodTheme.textSecondary)

                    Text(conversation.participant.status.publicLabel)
                        .font(.mood(11))
                        .foregroundStyle(MoodTheme.textMuted)
                }

                Spacer()

                if conversation.unreadCount > 0 {
                    Text("\(conversation.unreadCount)")
                        .font(.mood(10, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6 * LayoutMetrics.scale)
                        .padding(.vertical, 2 * LayoutMetrics.scale)
                        .background(MoodTheme.mentionBadge)
                        .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                }

                if isHovered {
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) { showClosedFeedback = true }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                            withAnimation { showClosedFeedback = false }
                        }
                    } label: {
                        Image(systemName: showClosedFeedback ? "checkmark" : "xmark")
                            .font(.mood(9))
                            .foregroundStyle(MoodTheme.textPrimary)
                    }
                    .buttonStyle(.plain)
                    .help("Fermer la conversation")
                }
            }
            .padding(.horizontal, 10 * LayoutMetrics.scale)
            .padding(.vertical, 8 * LayoutMetrics.scale)
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
            if matrixStore.callsAvailable {
                Button { showCallAlert = true } label: { Label("Appel vocal", systemImage: "phone") }
                Button { showCallAlert = true } label: { Label("Appel vidéo", systemImage: "video") }
                Divider()
            }
            Button { isMuted.toggle() } label: { Label(isMuted ? "Rétablir les notifications" : "Rendre muet", systemImage: isMuted ? "bell" : "bell.slash") }
            Button(role: .destructive) {
                withAnimation(.easeInOut(duration: 0.2)) { showClosedFeedback = true }
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                    withAnimation { showClosedFeedback = false }
                }
            } label: { Label("Fermer la conversation", systemImage: "xmark") }
        }
        .popover(isPresented: $showProfile, arrowEdge: .trailing) {
            UserProfilePopup(user: conversation.participant)
                .adaptiveFrame(width: 320, height: 400, mode: .regular)
        }
        .alert("Appel", isPresented: $showCallAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Les appels seront disponibles dans une prochaine version.")
        }
    }
}

// MARK: - DM Chat Area

struct DMChatArea: View {
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
                        .font(.mood(15, weight: .bold))
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
                            showInlineProfile.toggle()
                        }
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

                Rectangle().fill(MoodTheme.divider).frame(height: 1)
            }

            HStack(spacing: 0) {
                VStack(spacing: 0) {
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
                                VStack(spacing: 10 * LayoutMetrics.scale) {
                                    AvatarGlyph(user: conversation.participant)
                                        .font(.mood(50))
                                        .frame(width: 80 * LayoutMetrics.scale, height: 80 * LayoutMetrics.scale)
                                        .background(MoodTheme.glassBg)
                                        .clipShape(Circle())

                                    Text(conversation.participant.displayName)
                                        .font(.mood(20, weight: .bold))
                                        .foregroundStyle(MoodTheme.textPrimary)

                                    Text("@\(conversation.participant.username)")
                                        .font(.mood(13))
                                        .foregroundStyle(MoodTheme.textSecondary)
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 28 * LayoutMetrics.scale)

                                Rectangle()
                                    .fill(MoodTheme.divider)
                                    .frame(height: 1)
                                    .padding(.horizontal, 16)
                                    .padding(.bottom, 6)

                                if hasMoreHistory, let roomId {
                                    LoadMoreHistoryButton(roomId: roomId)
                                }

                                if messages.isEmpty {
                                    Text("Aucun message pour l'instant. Dis bonjour 👋")
                                        .font(.mood(13))
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
                        typingUsers: roomId.flatMap { matrixStore.typingUsersByRoom[$0] } ?? [],
                        isDisabled: isEncrypted,
                        replyingTo: $replyingTo,
                        onSend: sendCurrentMessage,
                        onAttachFile: attach
                    )
                }

                if showSearch, layoutMode == .regular {
                    Rectangle().fill(MoodTheme.divider).frame(width: 1)

                    SearchPanel(
                        model: search,
                        scope: .dm(conversation),
                        onClose: closeSearch,
                        onOpen: openSearchResult
                    )
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
                matrixStore.errorMessage = "Impossible d'envoyer : cette conversation n'est pas reliée à une room Matrix."
            }
            return
        }
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
