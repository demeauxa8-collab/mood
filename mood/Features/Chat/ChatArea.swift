import SwiftUI
import UIKit
import QuickLook

// MARK: - Chat Area

struct ChatArea: View {
    @Environment(MatrixStore.self) private var matrixStore
    @Environment(AuthState.self) private var authState
    @Environment(\.layoutMode) private var layoutMode
    let channel: Channel
    let server: MoodServer
    @Binding var showProfilePopup: Bool
    @Binding var profileUser: MoodUser?
    /// Opens another channel of the server (a search result that lives elsewhere); nil where search is unavailable.
    var onOpenChannel: ((Channel) -> Void)? = nil
    @State private var messageText = ""
    @State private var showMemberList = true
    @State private var showSearch = false
    @State private var search = MessageSearchModel()
    @FocusState private var searchFocused: Bool
    @State private var showPinnedMessages = false
    @State private var showThreadDirectory = false
    @State private var showThreadPanel = false
    @State private var activeThread: ChatMessage?
    @State private var replyingTo: ChatMessage?
    @State private var editRequest: UUID?
    @State private var typingTask: Task<Void, Never>?
    @State private var isTyping = false
    @State private var draftAttachment: URL?

    private var messages: [ChatMessage] {
        let storeMessages = matrixStore.messages(for: channel)
        if storeMessages.isEmpty && authState.isDemoMode {
            return MockData.messages(for: channel)
        }
        return storeMessages
    }

    private func attach(_ url: URL) {
        draftAttachment = url
    }

    private var roomId: String? {
        matrixStore.roomId(for: channel)
    }

    private var isEncrypted: Bool {
        guard let roomId else { return false }
        return matrixStore.isRoomEncrypted(roomId)
    }

    var body: some View {
        if channel.type == .voice {
            VoiceChannelLobby(channel: channel, server: server)
        } else {
            textChannelContent
        }
    }

    @ViewBuilder
    private var textChannelContent: some View {
        VStack(spacing: 0) {
            // Masquer ChannelHeader sur compact (NavigationStack fournit le titre)
            if layoutMode == .regular {
                ChannelHeader(
                    channel: channel,
                    showMemberList: $showMemberList,
                    searchText: $search.query,
                    isSearchActive: showSearch,
                    searchFocus: $searchFocused,
                    onSubmitSearch: runSearch,
                    onClearSearch: closeSearch,
                    showPinnedMessages: $showPinnedMessages
                )

                DesktopPixelRule()
                    .offset(y: DesktopPixelMetrics.legacyHeaderOffset)
            }

            HStack {
                Button { showThreadDirectory = true } label: { Label("Fils", systemImage: "bubble.left.and.bubble.right") }
                if let roomId, matrixStore.conversationMarkedRooms.contains(roomId) {
                    Label("Non lu", systemImage: "circle.fill").foregroundStyle(MoodTheme.brandBlue)
                }
                Spacer()
                Button {
                    search.query = "dans:#\(channel.name) "
                    showSearch = true
                    searchFocused = true
                } label: { Label("Dans ce salon", systemImage: "magnifyingglass") }
                if layoutMode == .compact {
                    Button { search.query = ""; showSearch = true } label: { Text("Serveur") }
                }
            }
            .font(.mood(12)).foregroundStyle(MoodTheme.textSecondary)
            .padding(.horizontal, 16 * LayoutMetrics.scale).padding(.vertical, 6 * LayoutMetrics.scale)

            HStack(spacing: 0) {
                VStack(spacing: 0) {
                    // Pinned messages panel
                    if showPinnedMessages {
                        PinnedMessagesPanel(
                            messages: messages.filter { $0.isPinned },
                            server: server,
                            showPanel: $showPinnedMessages,
                            onJump: { message in
                                if let roomId, let eventId = message.eventId { matrixStore.requestJump(roomId: roomId, eventId: eventId) }
                                showPinnedMessages = false
                            }
                        )
                    }

                    MessageList(
                        messages: messages,
                        channel: channel,
                        server: server,
                        roomId: roomId,
                        showProfilePopup: $showProfilePopup,
                        profileUser: $profileUser,
                        replyingTo: $replyingTo,
                        activeThread: $activeThread,
                        showThreadPanel: $showThreadPanel,
                        editRequest: $editRequest
                    )

                    if isEncrypted {
                        EncryptedRoomNotice()
                    }

                    if let url = draftAttachment {
                        AttachmentDraftPreview(url: url, onCancel: { draftAttachment = nil }, onSend: {
                            guard let roomId else { return }
                            draftAttachment = nil
                            Task { await matrixStore.sendAttachment(roomId: roomId, fileURL: url) }
                        })
                    }
                    MessageInputBar(
                        text: $messageText,
                        channelName: channel.name,
                        isE2E: isEncrypted,
                        typingUsers: roomId.flatMap { matrixStore.typingUsersByRoom[$0] } ?? [],
                        isDisabled: isEncrypted,
                        replyingTo: $replyingTo,
                        onSend: sendCurrentMessage,
                        onAttachFile: attach,
                        mentionMembers: server.members.compactMap { member in
                            member.matrixId.map { MentionCandidate(userId: $0, displayName: member.displayName) }
                        }
                    )
                    .onKeyPress(.upArrow) {
                        guard let id = MessagingServerPolicy.lastEditable(messages, draft: messageText) else { return .ignored }
                        editRequest = id
                        return .handled
                    }
                }

                // Panels inline sur desktop uniquement
                if layoutMode == .regular {
                    if showSearch {
                        DesktopPixelRule(vertical: true)

                        SearchPanel(
                            model: search,
                            scope: .server(server),
                            onClose: closeSearch,
                            onOpen: openSearchResult
                        )
                    } else if showThreadPanel, let thread = activeThread {
                        DesktopPixelRule(vertical: true)

                        ThreadPanel(
                            message: thread,
                            roomId: roomId,
                            server: server,
                            showPanel: $showThreadPanel
                        )
                        .frame(width: LayoutMetrics.threadPanelWidth)
                    } else if showMemberList {
                        DesktopPixelRule(vertical: true)

                        MemberListPanel(
                            members: server.members,
                            server: server,
                            showProfilePopup: $showProfilePopup,
                            profileUser: $profileUser
                        )
                        .frame(width: LayoutMetrics.memberListWidth)
                    }
                }
            }
        }
        .background(MoodTheme.chatBackground)
        .modalOverlay(isPresented: $showThreadDirectory) {
            ConversationThreadDirectory(roomId: roomId, onOpen: { message in
                activeThread = message
                showThreadDirectory = false
                showThreadPanel = true
            }, onClose: { showThreadDirectory = false })
        }
        .navigationDestination(isPresented: Binding(get: { layoutMode == .compact && showSearch }, set: { showSearch = $0 })) {
            VStack(spacing: 0) {
                HStack {
                    TextField("Rechercher dans le serveur", text: $search.query).onSubmit(runSearch)
                    Button("Chercher", action: runSearch)
                }
                .font(.mood(14)).padding(12 * LayoutMetrics.scale)
                ConversationMobileSearch(model: search, onOpen: { hit in
                    openSearchResult(hit)
                    showSearch = false
                }, onRetry: runSearch, onMore: { search.loadMore(store: matrixStore, scope: .server(server)) })
            }
            .background(MoodTheme.chatBackground)
            .navigationTitle("Recherche")
        }
        .messageSearchSupport(
            model: search,
            scope: .server(server),
            isOpen: showSearch,
            focus: $searchFocused,
            resetKey: server.id,
            onClose: closeSearch
        )
        .task(id: roomId) { if let roomId { await matrixStore.loadConversationHistory(roomId: roomId) } }
        .onChange(of: matrixStore.conversationThreadJump, initial: true) { _, _ in
            guard let roomId, let root = matrixStore.conversationJumpRoot(roomId: roomId) else { return }
            activeThread = root
            showThreadPanel = true
        }
        .task(id: showPinnedMessages) { if showPinnedMessages, let roomId { await matrixStore.loadMessagingPins(roomId: roomId) } }
        .onAppear { if layoutMode == .compact { showMemberList = false }; markChannelAsRead() }
        .onChange(of: channel.id) { _, _ in markChannelAsRead() }
        .onChange(of: messageText) { _, newValue in
            guard !newValue.isEmpty else { return }
            scheduleTypingNotification()
        }
        .onDisappear { stopTyping() }
        // Sheets pour les panels sur compact
        .navigationDestination(isPresented: Binding(
            get: { layoutMode == .compact && showThreadPanel && activeThread != nil },
            set: { if !$0 { showThreadPanel = false } }
        )) {
            if let thread = activeThread {
                    ThreadPanel(
                        message: thread,
                        roomId: roomId,
                        server: server,
                        showPanel: $showThreadPanel
                    )
                    .navigationTitle("Fil de discussion")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button("Fermer") { showThreadPanel = false }
                        }
                    }
            }
        }
        .sheet(isPresented: Binding(
            get: { layoutMode == .compact && showMemberList },
            set: { if !$0 { showMemberList = false } }
        )) {
            MobileSheet(title: "Membres", onClose: { showMemberList = false }) {
                MobileMemberList(members: server.members, server: server)
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
                matrixStore.errorMessage = "Impossible d'envoyer : ce salon n’est pas encore disponible."
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

    private func markChannelAsRead() {
        guard let roomId else { return }
        matrixStore.markAsRead(roomId: roomId)
    }

    // MARK: Search

    private func runSearch() {
        showSearch = true
        search.submit(store: matrixStore, scope: .server(server))
    }

    private func closeSearch() {
        showSearch = false
        searchFocused = false
        search.reset()
    }

    /// A result opens its channel when it is not the current one, then the channel scrolls to the message.
    private func openSearchResult(_ hit: SearchHit) {
        matrixStore.requestJump(roomId: hit.roomId, eventId: hit.eventId)
        if case .channel(let target, _) = hit.destination, target.id != channel.id {
            onOpenChannel?(target)
        }
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

// MARK: - Encrypted Room Notice

struct EncryptedRoomNotice: View {
    var body: some View {
        HStack(spacing: 8 * LayoutMetrics.scale) {
            Image(systemName: "lock.fill")
                .font(.mood(11))
            Text("Cette conversation est chiffrée — Mood ne prend pas encore en charge le chiffrement.")
                .font(.mood(12))
            Spacer()
        }
        .foregroundStyle(MoodTheme.mentionBadge)
        .padding(.horizontal, 12 * LayoutMetrics.scale)
        .padding(.vertical, 8 * LayoutMetrics.scale)
        .background(MoodTheme.mentionBadge.opacity(0.10))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .padding(.horizontal, 16 * LayoutMetrics.scale)
        .padding(.top, 6)
    }
}

// MARK: - Channel Header

struct ChannelHeader: View {
    @Environment(\.desktopFriendsCalibration) private var calibrated
    let channel: Channel
    @Binding var showMemberList: Bool
    @Binding var searchText: String
    let isSearchActive: Bool
    var searchFocus: FocusState<Bool>.Binding
    let onSubmitSearch: () -> Void
    let onClearSearch: () -> Void
    @Binding var showPinnedMessages: Bool
    @State private var showNotifAlert = false

    var body: some View {
        HStack(spacing: 10 * LayoutMetrics.scale) {
            CalibratedDesktopSymbol(name: channel.icon, size: 16)
                .foregroundStyle(calibrated ? MoodTheme.textSubtle : MoodTheme.textPrimary)

            CalibratedDesktopText(value: channel.name, size: calibrated ? 16 : 15,
                weight: calibrated ? .medium : .bold, glyphBackground: calibrated ? MoodTheme.chatBackground : nil)
                .lineLimit(1)
                .fixedSize()

            if !channel.topic.isEmpty {
                DesktopPixelRule(vertical: true).frame(height: 16 * LayoutMetrics.scale)

                Text(channel.topic)
                    .desktopFriendsFont(calibrated ? 14 : 13)
                    .foregroundStyle(MoodTheme.textMuted)
                    .lineLimit(1)
                    .layoutPriority(-1)
            }

            Spacer()

            HStack(spacing: 8 * LayoutMetrics.scale) {
                HeaderButton(icon: "pin.fill", isActive: showPinnedMessages) {
                    showPinnedMessages.toggle()
                }
                .help("Messages épinglés")

                HeaderButton(icon: "person.2.fill", isActive: showMemberList) {
                    showMemberList.toggle()
                }
                .help("Liste des membres")

                HeaderSearchField(
                    text: $searchText,
                    isActive: isSearchActive,
                    focus: searchFocus,
                    onSubmit: onSubmitSearch,
                    onClear: onClearSearch
                )
                .padding(.leading, 4 * LayoutMetrics.scale)
            }
        }
        .padding(.leading, 16 * LayoutMetrics.scale)
        .padding(.trailing, 12 * LayoutMetrics.scale)
        .frame(height: LayoutMetrics.desktopHeaderHeight)
        .background(MoodTheme.chatBackground)
    }
}

struct HeaderButton: View {
    @Environment(\.desktopFriendsCalibration) private var calibrated
    let icon: String
    var isActive = false
    var action: () -> Void = {}
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            CalibratedDesktopSymbol(name: calibrated && icon == "person.2.fill" ? "desktop.members" : icon,
                                    size: 16, calibratedSize: 24)
                .foregroundStyle(isHovered || isActive ? MoodTheme.textPrimary : MoodTheme.textSecondary)
                .frame(width: 32 * LayoutMetrics.scale, height: 32 * LayoutMetrics.scale)
                .background(isHovered ? MoodTheme.hoverBg : Color.clear)
                .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in isHovered = hovering }
    }
}

/// Discord's header search: a real text field. Enter runs the search, Esc clears it and closes the results.
struct HeaderSearchField: View {
    @Binding var text: String
    /// The results panel is open.
    let isActive: Bool
    var focus: FocusState<Bool>.Binding
    let onSubmit: () -> Void
    let onClear: () -> Void
    @State private var isHovered = false

    private var isHighlighted: Bool { isHovered || isActive || focus.wrappedValue }

    var body: some View {
        HStack(spacing: 8 * LayoutMetrics.scale) {
            TextField(
                "Rechercher",
                text: $text,
                prompt: Text("Rechercher").foregroundStyle(MoodTheme.textMuted)
            )
            .textFieldStyle(.plain)
            .font(.mood(15))
            .foregroundStyle(MoodTheme.textPrimary)
            .focused(focus)
            .submitLabel(.search)
            .autocorrectionDisabled()
            .textInputAutocapitalization(.never)
            .onSubmit(onSubmit)
            .onKeyPress(.escape) {
                onClear()
                return .handled
            }

            if isActive || !text.isEmpty {
                Button(action: onClear) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.mood(15, weight: .semibold))
                        .foregroundStyle(MoodTheme.textSecondary)
                }
                .buttonStyle(.plain)
                .help("Effacer la recherche")
            } else {
                Image(systemName: "magnifyingglass")
                    .font(.mood(15, weight: .semibold))
                    .foregroundStyle(MoodTheme.textMuted)
            }
        }
        .padding(.horizontal, 10 * LayoutMetrics.scale)
        // Discord shrinks the search box before it lets the channel title wrap.
        .frame(minWidth: 120 * LayoutMetrics.scale, maxWidth: 244 * LayoutMetrics.scale)
        .frame(height: 32 * LayoutMetrics.scale)
        .background(isHighlighted ? MoodTheme.inputBg : MoodTheme.headerSearchBackground)
        .clipShape(RoundedRectangle(cornerRadius: 8 * LayoutMetrics.scale, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8 * LayoutMetrics.scale, style: .continuous)
                .strokeBorder(
                    focus.wrappedValue || isActive ? MoodTheme.brandBlue.opacity(0.55) : MoodTheme.headerSearchBorder,
                    lineWidth: 1 * LayoutMetrics.scale
                )
        )
        .contentShape(Rectangle())
        .onTapGesture { focus.wrappedValue = true }
        .onHover { hovering in isHovered = hovering }
        .help("Rechercher (Cmd+F)")
    }
}

// MARK: - Message List

struct MessageList: View {
    @Environment(MatrixStore.self) private var matrixStore
    let messages: [ChatMessage]
    let channel: Channel
    let server: MoodServer
    var roomId: String? = nil
    @Binding var showProfilePopup: Bool
    @Binding var profileUser: MoodUser?
    @Binding var replyingTo: ChatMessage?
    @Binding var activeThread: ChatMessage?
    @Binding var showThreadPanel: Bool
    @Binding var editRequest: UUID?
    @Environment(ServerActions.self) private var serverActions
    @State private var isAtBottom = true
    @State private var visibleMessageIDs: Set<UUID> = []
    @State private var historyAnchor: UUID?

    /// Discord shows its setup checklist in the first channel of a new, still empty server.
    private var isFirstChannelOfServer: Bool {
        roomId != nil && server.categories.first?.channels.first?.id == channel.id
            && server.categories.flatMap(\.channels).count <= 1
    }

    private var dividerEventId: String? {
        roomId.flatMap { matrixStore.newMessagesDivider[$0] }
    }

    private var hasMoreHistory: Bool {
        guard let roomId else { return false }
        return matrixStore.hasMoreHistory[roomId] == true
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0) {
                    if hasMoreHistory, let roomId {
                        LoadMoreHistoryButton(roomId: roomId, onStart: {
                            historyAnchor = messages.first { visibleMessageIDs.contains($0.id) }?.id
                        }, onLoaded: {
                            if let historyAnchor {
                                Task { @MainActor in
                                    try? await Task.sleep(for: .milliseconds(80))
                                    proxy.scrollTo(historyAnchor, anchor: .top)
                                }
                            }
                        })
                    } else if messages.isEmpty, isFirstChannelOfServer {
                        ServerWelcomeChecklist(server: server)
                    } else {
                        // Welcome — uniquement au vrai début du channel
                        VStack(alignment: .leading, spacing: 10 * LayoutMetrics.scale) {
                            ZStack {
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .fill(MoodTheme.brandAccent.opacity(0.12))
                                    .frame(width: 56 * LayoutMetrics.scale, height: 56 * LayoutMetrics.scale)
                                Image(systemName: channel.icon)
                                    .font(.mood(26))
                                    .foregroundStyle(MoodTheme.brandAccent)
                            }

                            Text("Bienvenue dans #\(channel.name) !")
                                .font(.mood(28, weight: .bold))
                                .foregroundStyle(MoodTheme.textPrimary)

                            Text("C'est le début du salon #\(channel.name).")
                                .foregroundStyle(MoodTheme.textSecondary)
                                .font(.mood(15))

                            if roomId != nil {
                                Button {
                                    serverActions.pending = .editChannel(channel.id)
                                } label: {
                                    Label("Modifier le salon", systemImage: "pencil")
                                        .font(.mood(13, weight: .medium))
                                        .foregroundStyle(MoodTheme.textPrimary)
                                        .padding(.horizontal, 10 * LayoutMetrics.scale)
                                        .padding(.vertical, 6 * LayoutMetrics.scale)
                                        .background(MoodTheme.serverBar)
                                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 16 * LayoutMetrics.scale)
                        .padding(.top, 24 * LayoutMetrics.scale)
                        .padding(.bottom, 16 * LayoutMetrics.scale)
                    }

                    DesktopPixelRule()
                        .padding(.horizontal, 16)
                        .padding(.bottom, 6)

                    if messages.isEmpty {
                        Text("Aucun message pour l'instant. Dis bonjour 👋")
                            .font(.mood(13))
                            .foregroundStyle(MoodTheme.textSecondary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 24 * LayoutMetrics.scale)
                    }

                    ForEach(Array(messages.enumerated()), id: \.element.id) { index, message in
                        // Date separator
                        if index == 0 || !Calendar.current.isDate(message.timestamp, inSameDayAs: messages[index - 1].timestamp) {
                            DateSeparator(date: message.timestamp)
                        }

                        // Discord's red "NOUVEAU" line above the first message that was unread on arrival
                        if let dividerEventId, message.eventId == dividerEventId {
                            NewMessagesSeparator()
                        }

                        if message.isSystemMessage {
                            SystemMessageRow(message: message)
                                .id(message.id)
                                .onAppear { visibleMessageIDs.insert(message.id) }
                                .onDisappear { visibleMessageIDs.remove(message.id) }
                        } else {
                            MessageRow(message: message, server: server, roomId: roomId, editRequest: $editRequest, onReply: {
                                replyingTo = message
                            }, onThread: {
                                activeThread = message
                                showThreadPanel = true
                            }) {
                                profileUser = message.sender
                                showProfilePopup = true
                            }
                            .id(message.id)
                                .onAppear { visibleMessageIDs.insert(message.id) }
                                .onDisappear { visibleMessageIDs.remove(message.id) }
                        }
                    }

                    // Bottom anchor: tracks whether the newest message is on screen
                    Color.clear
                        .frame(height: 1)
                        .id("bottom")
                        .onAppear { isAtBottom = true }
                        .onDisappear { isAtBottom = false }
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .defaultScrollAnchor(.bottom)
            .onAppear { proxy.scrollTo("bottom", anchor: .bottom) }
            .onChange(of: messages.last?.id) { _, _ in
                // Like Discord: follow new messages only when already at the bottom,
                // or when the new message is mine.
                if isAtBottom || messages.last?.isOwn == true {
                    proxy.scrollTo("bottom", anchor: .bottom)
                    if let roomId { matrixStore.markAsRead(roomId: roomId) }
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if !isAtBottom {
                    JumpToPresentBar { proxy.scrollTo("bottom", anchor: .bottom) }
                        .transition(.opacity)
                }
            }
            .onChange(of: isAtBottom) { _, value in if value, let roomId { matrixStore.markAsRead(roomId: roomId) } }
            .animation(MoodMotion.popover, value: isAtBottom)
            .jumpToRequestedMessage(roomId: roomId, messages: messages, proxy: proxy)
        }
    }
}

/// Discord's "Tu consultes des messages plus anciens — Revenir au présent" bar.
struct JumpToPresentBar: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                Text("Tu consultes des messages plus anciens")
                    .font(.mood(13, weight: .medium))
                    .foregroundStyle(MoodTheme.textPrimary)
                Spacer()
                HStack(spacing: 4) {
                    Text("Revenir au présent")
                        .font(.mood(13, weight: .semibold))
                    Image(systemName: "arrow.down")
                        .font(.mood(11, weight: .bold))
                }
                .foregroundStyle(MoodTheme.textPrimary)
            }
            .padding(.horizontal, 12 * LayoutMetrics.scale)
            .padding(.vertical, 6 * LayoutMetrics.scale)
            .background(MoodTheme.brandBlue.opacity(0.85))
            .clipShape(UnevenRoundedRectangle(topLeadingRadius: 8, topTrailingRadius: 8, style: .continuous))
            .padding(.horizontal, 16 * LayoutMetrics.scale)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Message Row

struct MessageRow: View {
    @Environment(\.desktopFriendsCalibration) private var calibrated
    @Environment(MatrixStore.self) private var matrixStore
    let message: ChatMessage
    let server: MoodServer?
    var roomId: String? = nil
    /// Set by the composer's ↑ shortcut to the message that should enter edit mode.
    var editRequest: Binding<UUID?> = .constant(nil)
    var onReply: (() -> Void)?
    var onThread: (() -> Void)?
    let onAvatarTap: () -> Void
    @State private var isHovered = false
    @State private var showReactionPicker = false
    @State private var showEllipsisMenu = false
    @State private var showDeleteConfirm = false
    @State private var isEditing = false
    @State private var editText = ""
    @Environment(\.layoutMode) private var layoutMode
    @State private var showForward = false
    @State private var ownThreadRoot: ChatMessage?
    @State private var showOwnThread = false
    @State private var showOwnDirectory = false
    @State private var showOwnSearch = false

    /// Matrix ids needed by every action; nil for local echoes and demo data.
    private var target: (roomId: String, eventId: String)? {
        guard let roomId, let eventId = message.eventId else { return nil }
        return (roomId, eventId)
    }

    private func react(_ emoji: String) {
        guard let target else { return }
        Task { await matrixStore.toggleReaction(roomId: target.roomId, eventId: target.eventId, emoji: emoji) }
    }

    private func togglePin() {
        guard let target else { return }
        Task { await matrixStore.togglePin(roomId: target.roomId, eventId: target.eventId) }
    }

    private func copyLink() {
        guard let target else { return }
        UIPasteboard.general.string = matrixStore.permalink(roomId: target.roomId, eventId: target.eventId)
    }

    private func startEditing() {
        editText = message.content
        isEditing = true
    }

    private func saveEdit() {
        let newBody = editText.trimmingCharacters(in: .whitespacesAndNewlines)
        isEditing = false
        guard let target, !newBody.isEmpty, newBody != message.content else { return }
        Task { await matrixStore.editMessage(roomId: target.roomId, eventId: target.eventId, newBody: newBody) }
    }

    @ViewBuilder private var conversationActions: some View {
        if target != nil {
            if onThread != nil || roomId != nil {
                Button {
                    showEllipsisMenu = false
                    openThread()
                } label: { Label(message.threadInfo == nil ? "Créer un fil" : "Ouvrir le fil", systemImage: "bubble.left.and.bubble.right") }
            }
            if layoutMode == .compact {
                Button { showOwnDirectory = true } label: { Label("Fils du salon", systemImage: "bubble.left.and.bubble.right") }
                Button { showOwnSearch = true } label: { Label("Rechercher", systemImage: "magnifyingglass") }
            }
            if ConversationPolicy.forwardedText(message) != nil {
                Button { showEllipsisMenu = false; showForward = true } label: { Label("Transférer", systemImage: "arrowshape.turn.up.right") }
            }
            Button {
                guard let roomId else { return }
                showEllipsisMenu = false
                Task { await matrixStore.setConversationUnread(roomId: roomId, unread: true) }
            } label: { Label("Marquer comme non lu", systemImage: "envelope.badge") }
        }
    }

    private func openThread() {
        if let onThread { onThread() } else { showOwnThread = true }
    }

    var body: some View {
        VStack(spacing: 0) {
            if layoutMode == .compact, let roomId, matrixStore.conversationStartsDay(message, roomId: roomId) { DateSeparator(date: message.timestamp) }
            if message.isSystemMessage { SystemMessageRow(message: message) }
            else { messageContent }
        }

    }

    private var messageContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Reply reference
            if let reply = message.replyTo {
                HStack(spacing: 6 * LayoutMetrics.scale) {
                    RoundedRectangle(cornerRadius: 1)
                        .fill(MoodTheme.textMuted.opacity(0.4))
                        .frame(width: 2, height: 12 * LayoutMetrics.scale)
                        .padding(.leading, 52 * LayoutMetrics.scale)

                    AvatarGlyph(user: reply.sender)
                        .font(.mood(9))
                        .frame(width: 16 * LayoutMetrics.scale, height: 16 * LayoutMetrics.scale)
                        .background(MoodTheme.glassBg)
                        .clipShape(Circle())

                    Text(reply.sender.displayName)
                        .font(.mood(12, weight: .semibold))
                        .foregroundStyle(reply.sender.roleColor)

                    Text(reply.content)
                        .font(.mood(12))
                        .foregroundStyle(MoodTheme.textMuted)
                        .lineLimit(1)
                }
                .padding(.bottom, 4)
                .contentShape(Rectangle())
                .onTapGesture {
                    if let roomId, let eventId = reply.eventId { matrixStore.requestJump(roomId: roomId, eventId: eventId) }
                }
            }

            HStack(alignment: .top, spacing: 14 * LayoutMetrics.scale) {
                if message.isGrouped {
                    Text(message.timestamp.timeFormatted)
                        .font(.mood(10))
                        .foregroundStyle(MoodTheme.textMuted)
                        .frame(width: 38 * LayoutMetrics.scale, alignment: .center)
                        .opacity(isHovered ? 1 : 0)
                } else {
                    Button(action: onAvatarTap) {
                        AvatarGlyph(user: message.sender)
                            .font(.mood(20))
                            .frame(width: 40 * LayoutMetrics.scale, height: 40 * LayoutMetrics.scale)
                            .background(MoodTheme.glassBg)
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                }

                VStack(alignment: .leading, spacing: 4) {
                    if !message.isGrouped {
                        HStack(spacing: 8 * LayoutMetrics.scale) {
                            Button(action: onAvatarTap) {
                                HStack(spacing: 4) {
                                    Text(message.sender.displayName)
                                        .desktopFriendsFont(calibrated ? 16 : 14, weight: calibrated ? .medium : .semibold)
                                        .foregroundStyle(calibrated && server == nil ? MoodTheme.textPrimary : message.sender.roleColor)
                                    RoleBadge(role: server?.roleFor(message.sender) ?? .member, size: 12 * LayoutMetrics.scale)
                                }
                            }
                            .buttonStyle(.plain)

                            Text(message.timestamp.messageTimestamp)
                                .help(message.timestamp.formatted(date: .complete, time: .standard))
                                .desktopFriendsFont(calibrated ? 12 : 11)
                                .foregroundStyle(MoodTheme.textMuted)

                            if message.isPinned {
                                Image(systemName: "pin.fill")
                                    .font(.mood(9))
                                    .foregroundStyle(MoodTheme.textMuted.opacity(0.5))
                            }
                        }
                    }

                    if isEditing {
                        MessageEditor(text: $editText, onSave: saveEdit, onCancel: { isEditing = false })
                    } else if !message.content.isEmpty {
                    HStack(spacing: 0) {
                        MarkdownText(text: message.content)
                            .desktopFriendsFont(calibrated ? 16 : 14)
                            .foregroundStyle(MoodTheme.textPrimary)
                            .textSelection(.enabled)

                        if message.isEdited {
                            Text(" (modifié)")
                                .font(.mood(11))
                                .foregroundStyle(MoodTheme.textMuted)
                        }

                        if message.sendState == .sending {
                            ProgressView()
                                .scaleEffect(0.5)
                                .frame(width: 16 * LayoutMetrics.scale, height: 16 * LayoutMetrics.scale)
                                .padding(.leading, 6)
                        }
                    }
                    .opacity(message.sendState == .sending ? 0.55 : 1)
                    }

                    if message.sendState == .failed {
                        HStack(spacing: 6 * LayoutMetrics.scale) {
                            Image(systemName: "exclamationmark.circle.fill")
                                .font(.mood(11))
                                .foregroundStyle(MoodTheme.mentionBadge)

                            Text("Échec de l'envoi")
                                .font(.mood(11))
                                .foregroundStyle(MoodTheme.mentionBadge)

                            if let roomId {
                                Button {
                                    matrixStore.retryMessage(message.id, roomId: roomId)
                                } label: {
                                    Text("Réessayer")
                                        .font(.mood(11, weight: .semibold))
                                        .foregroundStyle(MoodTheme.brandBlue)
                                }
                                .buttonStyle(.plain)

                                Button {
                                    matrixStore.discardUnsentMessage(message.id, roomId: roomId)
                                } label: {
                                    Text("Supprimer")
                                        .font(.mood(11, weight: .semibold))
                                        .foregroundStyle(MoodTheme.mentionBadge)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.top, 2)
                    }

                    if let url = MediaLinkPreview.firstURL(in: message.content) {
                        MediaLinkPreviewCard(url: url)
                    }
                    // Attachments
                    ForEach(message.attachments) { att in
                        if let progress = matrixStore.uploadProgress(for: message), let roomId {
                            AttachmentUploadCard(name: att.name, size: att.size, progress: progress) {
                                matrixStore.discardUnsentMessage(message.id, roomId: roomId)
                            }
                        } else if let url = att.url, PlayableMedia.supports(att.name) {
                            PlayableMedia(url: url, name: att.name, roomID: roomId, eventID: message.eventId)
                        } else if att.type == .image, let thumbnail = att.name.lowercased().hasSuffix(".gif") ? att.url : (att.thumbnailURL ?? att.url) {
                            AttachmentImage(attachment: att, previewURL: thumbnail)
                        } else if att.type == .image {
                            HStack(spacing: 8) {
                                Text(att.previewEmoji)
                                    .font(.mood(28))
                                    .frame(width: 200 * LayoutMetrics.scale, height: 120 * LayoutMetrics.scale)
                                    .background(MoodTheme.glassBg)
                                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                                            .stroke(MoodTheme.glassBorder, lineWidth: 0.5)
                                    )
                            }
                        } else if att.url != nil {
                            AttachmentFileCard(attachment: att)
                        } else {
                            HStack(spacing: 8) {
                                Image(systemName: "doc.fill")
                                    .font(.mood(16))
                                    .foregroundStyle(MoodTheme.brandAccent)
                                Text(att.name)
                                    .font(.mood(13))
                                    .foregroundStyle(MoodTheme.brandBlue)
                                    .underline()
                                Image(systemName: "arrow.down.circle")
                                    .font(.mood(13))
                                    .foregroundStyle(MoodTheme.textMuted)
                            }
                            .padding(10 * LayoutMetrics.scale)
                            .background(MoodTheme.glassBg)
                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .stroke(MoodTheme.glassBorder, lineWidth: 0.5)
                            )
                        }
                    }

                    // Link embed
                    if let embed = message.linkEmbed {
                        HStack(spacing: 0) {
                            RoundedRectangle(cornerRadius: 2)
                                .fill(embed.color)
                                .frame(width: 4)

                            VStack(alignment: .leading, spacing: 4) {
                                Text(embed.siteName)
                                    .font(.mood(11))
                                    .foregroundStyle(MoodTheme.textSecondary)

                                Text(embed.title)
                                    .font(.mood(13, weight: .semibold))
                                    .foregroundStyle(MoodTheme.brandBlue)

                                Text(embed.description)
                                    .font(.mood(12))
                                    .foregroundStyle(MoodTheme.textSecondary)
                                    .lineLimit(2)

                                if let emoji = embed.imageEmoji {
                                    Text(emoji)
                                        .font(.mood(22))
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .frame(height: 60 * LayoutMetrics.scale)
                                        .background(MoodTheme.glassBg)
                                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                                }
                            }
                            .padding(10 * LayoutMetrics.scale)
                        }
                        .frame(maxWidth: 400 * LayoutMetrics.scale, alignment: .leading)
                        .background(MoodTheme.glassBg)
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .stroke(MoodTheme.glassBorder, lineWidth: 0.5)
                        )
                        .padding(.top, 4)
                    }


                    if let info = message.threadInfo {
                        Button { openThread() } label: {
                            VStack(alignment: .leading, spacing: 3 * LayoutMetrics.scale) {
                                Text("\(info.replyCount) réponses · \(info.lastReplier.displayName)")
                                    .font(.mood(12, weight: .semibold))
                                if let roomId, let id = message.eventId,
                                   let last = matrixStore.conversationReplies(roomId: roomId, root: id).last {
                                    Text(last.content).font(.mood(12)).lineLimit(1)
                                    if (matrixStore.conversationThreadUnread[roomId]?[id] ?? 0) > 0 {
                                        Text("Nouvelles réponses").font(.mood(11, weight: .bold))
                                    }
                                }
                            }
                            .foregroundStyle(MoodTheme.brandBlue)
                        }
                        .buttonStyle(.plain)
                    }

                    // Reactions
                    if !message.reactions.isEmpty {
                        HStack(spacing: 4 * LayoutMetrics.scale) {
                            ForEach(message.reactions) { reaction in
                                Button { react(reaction.emoji) } label: {
                                HStack(spacing: 4 * LayoutMetrics.scale) {
                                    Text(reaction.emoji)
                                        .font(.mood(13))
                                    Text("\(reaction.count)")
                                        .font(.mood(12, weight: .medium))
                                        .foregroundStyle(reaction.hasReacted ? MoodTheme.brandAccent : MoodTheme.textSecondary)
                                }
                                .padding(.horizontal, 8 * LayoutMetrics.scale)
                                .padding(.vertical, 4 * LayoutMetrics.scale)
                                .background(reaction.hasReacted ? MoodTheme.brandAccent.opacity(0.15) : MoodTheme.glassBg)
                                .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                                        .stroke(reaction.hasReacted ? MoodTheme.brandAccent.opacity(0.4) : MoodTheme.glassBorder, lineWidth: 0.5)
                                )
                                }
                                .buttonStyle(.plain)
                                .disabled(target == nil)
                            }

                            // Bouton ajouter réaction
                            Button { showReactionPicker = true } label: {
                                Image(systemName: "plus")
                                    .font(.mood(10))
                                    .foregroundStyle(MoodTheme.textPrimary)
                                    .frame(width: 26 * LayoutMetrics.scale, height: 26 * LayoutMetrics.scale)
                                    .background(MoodTheme.glassBg)
                                    .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                                            .stroke(MoodTheme.glassBorder, lineWidth: 0.5)
                                    )
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.top, 2)
                    }
                }

                Spacer()

                // Actions hover
                if isHovered {
                    HStack(spacing: 1) {
                        ActionButton(icon: "hand.thumbsup", action: { react("👍") }).help("Réaction rapide 👍")
                        ActionButton(icon: "face.smiling", action: { showReactionPicker = true })
                            .help("Ajouter une réaction")
                        if message.isOwn {
                            ActionButton(icon: "pencil", action: startEditing)
                                .help("Modifier")
                        } else {
                            ActionButton(icon: "arrowshape.turn.up.left", action: { onReply?() })
                                .help("Répondre")
                        }
                        ActionButton(icon: message.isPinned ? "pin.slash" : "pin", action: togglePin)
                            .help(message.isPinned ? "Désépingler" : "Épingler")
                        ActionButton(icon: "ellipsis", action: { showEllipsisMenu = true })
                            .help("Plus")
                            .popover(isPresented: $showEllipsisMenu, arrowEdge: .top) {
                                VStack(spacing: 2) {
                                    conversationActions
                                    Button {
                                        showEllipsisMenu = false
                                        onReply?()
                                    } label: {
                                        Label("Répondre", systemImage: "arrowshape.turn.up.left")
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                    }
                                    .buttonStyle(.plain)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 6)

                                    Button {
                                        showEllipsisMenu = false
                                        UIPasteboard.general.string = message.content
                                    } label: {
                                        Label("Copier le texte", systemImage: "doc.on.doc")
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                    }
                                    .buttonStyle(.plain)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 6)

                                    Button {
                                        showEllipsisMenu = false
                                        copyLink()
                                    } label: {
                                        Label("Copier le lien du message", systemImage: "link")
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                    }
                                    .buttonStyle(.plain)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 6)

                                    if message.isOwn {
                                    Divider()

                                    Button {
                                        showEllipsisMenu = false
                                        showDeleteConfirm = true
                                    } label: {
                                        Label("Supprimer le message", systemImage: "trash")
                                            .foregroundStyle(.red)
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                    }
                                    .buttonStyle(.plain)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 6)
                                    }
                                }
                                .padding(.vertical, 6)
                                .frame(width: 200 * LayoutMetrics.scale)
                                .font(.mood(13))
                                .foregroundStyle(MoodTheme.textPrimary)
                            }
                    }
                    .padding(3)
                    .background(MoodTheme.channelList)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(MoodTheme.glassBorder, lineWidth: 0.5)
                    )
                }
            }
            if message.isOwn, let roomId, let eventId = message.eventId {
                let readers = matrixStore.messagingReaders(roomId: roomId, eventId: eventId)
                if !readers.isEmpty {
                    Text("Lu par " + readers.joined(separator: ", "))
                        .font(.mood(10)).foregroundStyle(MoodTheme.textMuted)
                        .padding(.leading, 52 * LayoutMetrics.scale)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, message.isGrouped ? 1 : 5)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(isHovered ? MoodTheme.messageHover : Color.clear)
        )
        .padding(.horizontal, 4)
        .onHover { hovering in isHovered = hovering }
        .onChange(of: editRequest.wrappedValue, initial: true) { _, requested in
            guard requested == message.id else { return }
            editRequest.wrappedValue = nil
            startEditing()
        }
        .fullScreenCover(isPresented: $showOwnThread) {
            NavigationStack {
                ThreadPanel(message: ownThreadRoot ?? message, roomId: roomId, server: server, showPanel: $showOwnThread)
            }.environment(matrixStore).environment(\.layoutMode, .compact)
        }
        .fullScreenCover(isPresented: $showOwnSearch) {
            if let roomId {
                ConversationSearchScreen(roomId: roomId, server: server, onClose: { showOwnSearch = false })
                    .environment(matrixStore)
            }
        }
        .modalOverlay(isPresented: $showOwnDirectory) {
            ConversationThreadDirectory(roomId: roomId, onOpen: { root in
                showOwnDirectory = false
                ownThreadRoot = root
                showOwnThread = true
            }, onClose: { showOwnDirectory = false })
        }
        .modalOverlay(isPresented: $showForward) {
            ConversationForwardPicker(message: message, onClose: { showForward = false })
        }
        .popover(isPresented: $showReactionPicker) {
            EmojiPicker(isPresented: $showReactionPicker) { emoji in react(emoji) }
        }
        .contextMenu {
            conversationActions
            Button("Réaction rapide 👍") { react("👍") }
            Button { showReactionPicker = true } label: { Label("Ajouter une réaction", systemImage: "face.smiling") }
            if message.isOwn {
                Button(action: startEditing) { Label("Modifier le message", systemImage: "pencil") }
            }
            Button { onReply?() } label: { Label("Répondre", systemImage: "arrowshape.turn.up.left") }
            Divider()
            Button(action: togglePin) { Label(message.isPinned ? "Désépingler" : "Épingler le message", systemImage: message.isPinned ? "pin.slash" : "pin") }
            Button {
                UIPasteboard.general.string = message.content
            } label: { Label("Copier le texte", systemImage: "doc.on.doc") }
            Button(action: copyLink) { Label("Copier le lien du message", systemImage: "link") }
            if message.isOwn {
                Divider()
                Button(role: .destructive) { showDeleteConfirm = true } label: { Label("Supprimer le message", systemImage: "trash") }
            }
        }
        .alert("Supprimer le message", isPresented: $showDeleteConfirm) {
            Button("Annuler", role: .cancel) {}
            Button("Supprimer", role: .destructive) {
                guard let target else { return }
                Task { await matrixStore.deleteMessage(roomId: target.roomId, eventId: target.eventId) }
            }
        } message: {
            Text("Es-tu sûr de vouloir supprimer ce message ? Cette action est irréversible.")
        }
    }
}

// MARK: - Load More History Button

struct LoadMoreHistoryButton: View {
    @Environment(MatrixStore.self) private var matrixStore
    let roomId: String
    var onStart: (() -> Void)? = nil
    var onLoaded: (() -> Void)? = nil
    @State private var isLoading = false

    var body: some View {
        Button {
            guard !isLoading else { return }
            isLoading = true
            onStart?()
            Task {
                await matrixStore.loadMoreMessages(roomId: roomId)
                isLoading = false
                onLoaded?()
            }
        } label: {
            HStack(spacing: 6 * LayoutMetrics.scale) {
                if isLoading {
                    ProgressView()
                        .scaleEffect(0.5)
                        .frame(width: 14 * LayoutMetrics.scale, height: 14 * LayoutMetrics.scale)
                } else {
                    Image(systemName: "arrow.up.circle")
                        .font(.mood(12))
                }
                Text(isLoading ? "Chargement…" : "Charger les messages précédents")
                    .font(.mood(12, weight: .medium))
            }
            .foregroundStyle(MoodTheme.textSecondary)
            .padding(.horizontal, 12 * LayoutMetrics.scale)
            .padding(.vertical, 6 * LayoutMetrics.scale)
            .background(MoodTheme.glassBg)
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(isLoading)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12 * LayoutMetrics.scale)
    }
}

struct ActionButton: View {
    let icon: String
    var action: (() -> Void)?

    var body: some View {
        Button { action?() } label: {
            Image(systemName: icon)
                .font(.mood(14))
                .foregroundStyle(MoodTheme.textPrimary)
                .frame(width: 28 * LayoutMetrics.scale, height: 28 * LayoutMetrics.scale)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Member List Panel

struct MemberListPanel: View {
    @Environment(\.layoutMode) private var layoutMode
    @Environment(\.desktopFriendsCalibration) private var calibrated
    let members: [MoodUser]
    let server: MoodServer
    @Binding var showProfilePopup: Bool
    @Binding var profileUser: MoodUser?

    // Group by server role hierarchy
    private var ownerMembers: [MoodUser] {
        members.filter { server.roleFor($0) == .owner && !$0.status.isOfflineLike }
    }

    private var adminMembers: [MoodUser] {
        members.filter { server.roleFor($0) == .admin && !$0.status.isOfflineLike }
    }

    private var modMembers: [MoodUser] {
        members.filter { server.roleFor($0) == .moderator && !$0.status.isOfflineLike }
    }

    private var onlineMembers: [MoodUser] {
        members.filter { server.roleFor($0) == .member && !$0.status.isOfflineLike }
    }

    private var offlineMembers: [MoodUser] {
        members.filter { $0.status.isOfflineLike }
    }

    var body: some View {
        if layoutMode == .compact { MobileMemberList(members: members, server: server) } else { desktopBody }
    }

    private var desktopBody: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 2) {
                if !ownerMembers.isEmpty {
                    MemberSection(title: "PROPRIÉTAIRE — \(ownerMembers.count)", members: ownerMembers, server: server) { user in
                        profileUser = user
                        showProfilePopup = true
                    }
                }

                if !adminMembers.isEmpty {
                    MemberSection(title: "ADMIN — \(adminMembers.count)", members: adminMembers, server: server) { user in
                        profileUser = user
                        showProfilePopup = true
                    }
                }

                if !modMembers.isEmpty {
                    MemberSection(title: "MODÉRATEUR — \(modMembers.count)", members: modMembers, server: server) { user in
                        profileUser = user
                        showProfilePopup = true
                    }
                }

                if !onlineMembers.isEmpty {
                    MemberSection(title: "EN LIGNE — \(onlineMembers.count)", members: onlineMembers, server: server) { user in
                        profileUser = user
                        showProfilePopup = true
                    }
                }

                if !offlineMembers.isEmpty {
                    MemberSection(title: "HORS LIGNE — \(offlineMembers.count)", members: offlineMembers, server: server) { user in
                        profileUser = user
                        showProfilePopup = true
                    }
                }
            }
            .padding(.top, (calibrated ? 4 : 16) * LayoutMetrics.scale)
            .padding(.bottom, 12 * LayoutMetrics.scale)
        }
        .background(MoodTheme.memberList)
    }
}

struct MemberSection: View {
    @Environment(\.desktopFriendsCalibration) private var calibrated
    let title: String
    let members: [MoodUser]
    let server: MoodServer
    let onTap: (MoodUser) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            CalibratedDesktopText(value: calibrated ? String(title.prefix(1)) + title.dropFirst().lowercased() : title,
                size: calibrated ? 12 : 11, weight: calibrated ? .medium : .semibold,
                color: MoodTheme.textSecondary, glyphBackground: calibrated ? MoodTheme.memberList : nil)
                .tracking(calibrated ? 0 : 0.4)
                .padding(.horizontal, 16 * LayoutMetrics.scale)
                .padding(.top, 16 * LayoutMetrics.scale)
                .padding(.bottom, 4)

            ForEach(members) { member in
                MemberRow(member: member, role: server.roleFor(member), onTap: { onTap(member) })
            }
        }
    }
}

struct MemberRow: View {
    @Environment(\.desktopFriendsCalibration) private var calibrated
    let member: MoodUser
    let role: ServerRole
    let onTap: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 10 * LayoutMetrics.scale) {
                ZStack(alignment: .bottomTrailing) {
                    AvatarGlyph(user: member)
                        .font(.mood(14))
                        .frame(width: 32 * LayoutMetrics.scale, height: 32 * LayoutMetrics.scale)
                        .background(MoodTheme.glassBg)
                        .clipShape(Circle())
                        .opacity(member.status.isOfflineLike ? 0.4 : 1)

                    StatusIndicator(status: member.status, size: 8 * LayoutMetrics.scale, borderColor: MoodTheme.memberList)
                        .offset(x: 2, y: 2)
                }

                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 4) {
                        CalibratedDesktopText(value: member.displayName, size: calibrated ? 16 : 13,
                            weight: calibrated ? .medium : .regular,
                            color: member.status.isOfflineLike ? MoodTheme.textMuted : member.roleColor,
                            glyphBackground: calibrated ? (isHovered ? MoodTheme.hoverBg : MoodTheme.memberList) : nil)
                        RoleBadge(role: role, size: 11 * LayoutMetrics.scale)
                    }

                    if !member.status.isOfflineLike, let activity = member.activity {
                        Text("\(activity.type.rawValue) \(activity.name)")
                            .desktopFriendsFont(calibrated ? 12 : 11)
                            .foregroundStyle(MoodTheme.textMuted)
                            .lineLimit(1)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 10 * LayoutMetrics.scale)
            .padding(.vertical, 5 * LayoutMetrics.scale)
            .background(isHovered ? MoodTheme.hoverBg : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
            .padding(.horizontal, 8)
        }
        .buttonStyle(.plain)
        .onHover { hovering in isHovered = hovering }
    }
}

// MARK: - Markdown Text Renderer

struct MarkdownText: View {
    let text: String

    var body: some View {
        Text(parseMarkdown(text))
    }

    private func parseMarkdown(_ input: String) -> AttributedString {
        var result = AttributedString()
        var remaining = input[input.startIndex...]

        while !remaining.isEmpty {
            if remaining.hasPrefix("```"), let end = remaining.dropFirst(3).range(of: "```") {
                let code = remaining[remaining.index(remaining.startIndex, offsetBy: 3)..<end.lowerBound]
                var attr = AttributedString(String(code))
                attr.font = .mood(13, design: .monospaced)
                attr.foregroundColor = MoodTheme.textSecondary
                result += attr
                remaining = remaining[end.upperBound...]
            }
            else if remaining.hasPrefix("__"), let end = remaining.dropFirst(2).range(of: "__") {
                var attr = parseMarkdown(String(remaining[remaining.index(remaining.startIndex, offsetBy: 2)..<end.lowerBound]))
                attr.underlineStyle = .single
                result += attr
                remaining = remaining[end.upperBound...]
            }
            else if remaining.hasPrefix("_"), let end = remaining.dropFirst().firstIndex(of: "_") {
                var attr = parseMarkdown(String(remaining[remaining.index(after: remaining.startIndex)..<end]))
                attr.font = .mood(14).italic()
                result += attr
                remaining = remaining[remaining.index(after: end)...]
            }
            // Code block inline `code`
            else if remaining.hasPrefix("`"), let end = remaining.dropFirst().firstIndex(of: "`") {
                let code = remaining[remaining.index(after: remaining.startIndex)...remaining.index(before: end)]
                var attr = AttributedString(" \(code) ")
                attr.font = .mood(13, design: .monospaced)
                attr.foregroundColor = MoodTheme.textSecondary
                result += attr
                remaining = remaining[remaining.index(after: end)...]
            }
            // Bold **text**
            else if remaining.hasPrefix("**"), let end = remaining.dropFirst(2).range(of: "**") {
                let bold = remaining[remaining.index(remaining.startIndex, offsetBy: 2)..<end.lowerBound]
                var attr = AttributedString(String(bold))
                attr.font = .mood(14, weight: .bold)
                result += attr
                remaining = remaining[end.upperBound...]
            }
            // Italic *text*
            else if remaining.hasPrefix("*"), let end = remaining.dropFirst().firstIndex(of: "*") {
                let italic = remaining[remaining.index(after: remaining.startIndex)..<end]
                var attr = AttributedString(String(italic))
                attr.font = .mood(14).italic()
                result += attr
                remaining = remaining[remaining.index(after: end)...]
            }
            // ~~strikethrough~~
            else if remaining.hasPrefix("~~"), let end = remaining.dropFirst(2).range(of: "~~") {
                let strike = remaining[remaining.index(remaining.startIndex, offsetBy: 2)..<end.lowerBound]
                var attr = AttributedString(String(strike))
                attr.strikethroughStyle = .single
                result += attr
                remaining = remaining[end.upperBound...]
            }
            else if remaining.hasPrefix("["), let labelEnd = remaining.range(of: "]("),
                    let urlEnd = remaining[labelEnd.upperBound...].firstIndex(of: ")"),
                    let url = URL(string: String(remaining[labelEnd.upperBound..<urlEnd])),
                    ["https", "http", "mood"].contains(url.scheme?.lowercased() ?? "") {
                var attr = parseMarkdown(String(remaining[remaining.index(after: remaining.startIndex)..<labelEnd.lowerBound]))
                attr.link = url
                attr.foregroundColor = MoodTheme.brandBlue
                result += attr
                remaining = remaining[remaining.index(after: urlEnd)...]
            }
            // @mention
            else if remaining.hasPrefix("@") {
                let after = remaining.dropFirst()
                let mention = after.prefix(while: { $0.isLetter || $0.isNumber || $0 == "_" })
                if !mention.isEmpty {
                    var attr = AttributedString("@\(mention)")
                    attr.foregroundColor = MoodTheme.brandBlue
                    attr.font = .mood(14, weight: .bold)
                    result += attr
                    remaining = after.dropFirst(mention.count)
                } else {
                    result += AttributedString("@")
                    remaining = after
                }
            }
            // #channel
            else if remaining.hasPrefix("#") {
                let after = remaining.dropFirst()
                let channel = after.prefix(while: { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" })
                if !channel.isEmpty {
                    var attr = AttributedString("#\(channel)")
                    attr.foregroundColor = MoodTheme.brandBlue
                    result += attr
                    remaining = after.dropFirst(channel.count)
                } else {
                    result += AttributedString("#")
                    remaining = after
                }
            }
            // Normal character
            else {
                let nextSpecial = remaining.dropFirst().firstIndex(where: { "*`~@#_[".contains($0) }) ?? remaining.endIndex
                let plain = remaining[remaining.startIndex..<nextSpecial]
                result += AttributedString(String(plain))
                remaining = remaining[nextSpecial...]
            }
        }

        return result
    }
}

// MARK: - Date Separator

struct DateSeparator: View {
    let date: Date

    var body: some View {
        HStack(spacing: 10) {
            DesktopPixelRule()

            Text(date.dateSeparator)
                .font(.mood(11, weight: .semibold))
                .foregroundStyle(MoodTheme.textMuted)
                .fixedSize()

            DesktopPixelRule()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }
}

// MARK: - Pinned Messages Panel

struct PinnedMessagesPanel: View {
    @Environment(\.layoutMode) private var layoutMode
    let messages: [ChatMessage]
    let server: MoodServer?
    @Binding var showPanel: Bool
    var onJump: ((ChatMessage) -> Void)? = nil

    var body: some View {
        if layoutMode == .compact { mobileBody } else { desktopBody }
    }

    private var mobileBody: some View {
        MobileSheet(title: "Épingles", onClose: { showPanel = false }) {
            List {
                if messages.isEmpty {
                    Section {
                        ContentUnavailableView("Aucune épingle", systemImage: "pin.slash", description: Text("Les messages épinglés apparaîtront ici."))
                    }.listRowBackground(MoodTheme.inputBg)
                } else {
                    Section {
                        ForEach(messages) { message in
                            Button { onJump?(message) } label: {
                                VStack(alignment: .leading, spacing: LayoutMetrics.mobile(8)) {
                                    Text(message.sender.displayName).font(.mood(16, weight: .semibold))
                                    Text(message.content).font(.mood(16)).fixedSize(horizontal: false, vertical: true)
                                    Text(message.timestamp.messageTimestamp).font(.mood(13)).foregroundStyle(MoodTheme.textSecondary)
                                }.foregroundStyle(MoodTheme.textPrimary).padding(.vertical, LayoutMetrics.mobile(8))
                            }.buttonStyle(.plain).disabled(onJump == nil)
                        }
                    }.listRowBackground(MoodTheme.inputBg)
                }
            }.mobileGroupedList()
        }
    }

    private var desktopBody: some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: "pin.fill")
                    .font(.mood(12))
                    .foregroundStyle(MoodTheme.brandAccent)
                Text("Messages épinglés")
                    .font(.mood(13, weight: .semibold))
                    .foregroundStyle(MoodTheme.textPrimary)
                Spacer()
                Button {
                    showPanel = false
                } label: {
                    Image(systemName: "xmark")
                        .font(.mood(11))
                        .foregroundStyle(MoodTheme.textPrimary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16 * LayoutMetrics.scale)
            .padding(.vertical, 10 * LayoutMetrics.scale)

            DesktopPixelRule()

            if messages.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "pin.slash")
                        .font(.mood(28))
                        .foregroundStyle(MoodTheme.textPrimary)
                    Text("Aucun message épinglé")
                        .font(.mood(13))
                        .foregroundStyle(MoodTheme.textSecondary)
                }
                .padding(.vertical, 24 * LayoutMetrics.scale)
            } else {
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 8) {
                        ForEach(messages) { msg in
                            HStack(alignment: .top, spacing: 10 * LayoutMetrics.scale) {
                                AvatarGlyph(user: msg.sender)
                                    .font(.mood(12))
                                    .frame(width: 28 * LayoutMetrics.scale, height: 28 * LayoutMetrics.scale)
                                    .background(MoodTheme.glassBg)
                                    .clipShape(Circle())

                                VStack(alignment: .leading, spacing: 3) {
                                    HStack(spacing: 6 * LayoutMetrics.scale) {
                                        Text(msg.sender.displayName)
                                            .font(.mood(12, weight: .semibold))
                                            .foregroundStyle(msg.sender.roleColor)
                                        RoleBadge(role: server?.roleFor(msg.sender) ?? .member, size: 10 * LayoutMetrics.scale)
                                        Text(msg.timestamp.timeFormatted)
                                            .font(.mood(10))
                                            .foregroundStyle(MoodTheme.textMuted)
                                    }
                                    Text(msg.content)
                                        .font(.mood(12))
                                        .foregroundStyle(MoodTheme.textPrimary)
                                        .lineLimit(3)
                                }
                                Spacer()
                            }
                            .contentShape(Rectangle())
                            .onTapGesture { onJump?(msg) }
                            .padding(10 * LayoutMetrics.scale)
                            .background(MoodTheme.glassBg)
                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        }
                    }
                    .padding(12)
                }
                .frame(maxHeight: 250)
            }
        }
        .background(MoodTheme.chatBackground)
        .overlay(DesktopPixelRule(), alignment: .bottom)
    }
}

// MARK: - Thread Panel

// MARK: - Status Indicator Shape

struct StatusIndicator: View {
    let status: MoodUser.UserStatus
    let size: CGFloat
    let borderColor: Color

    init(status: MoodUser.UserStatus, size: CGFloat = 12, borderColor: Color = MoodTheme.chatBackground) {
        self.status = status
        self.size = size
        self.borderColor = borderColor
    }

    private var statusColor: Color {
        switch status {
        case .online: return MoodTheme.onlineGreen
        case .idle: return Color(hex: "f0b232")
        case .dnd: return MoodTheme.mentionBadge
        case .invisible, .offline: return Color(hex: "80848e")
        }
    }

    var body: some View {
        ZStack {
            // Border
            Circle()
                .fill(borderColor)
                .frame(width: size + 4, height: size + 4)

            switch status {
            case .online:
                Circle()
                    .fill(statusColor)
                    .frame(width: size, height: size)

            case .idle:
                // Croissant jaune (comme Discord)
                ZStack {
                    Circle()
                        .fill(statusColor)
                        .frame(width: size, height: size)
                    Circle()
                        .fill(borderColor)
                        .frame(width: size * 0.6, height: size * 0.6)
                        .offset(x: -size * 0.15, y: -size * 0.15)
                }

            case .dnd:
                // Cercle rouge avec trait blanc (comme Discord)
                ZStack {
                    Circle()
                        .fill(statusColor)
                        .frame(width: size, height: size)
                    RoundedRectangle(cornerRadius: 1)
                        .fill(borderColor)
                        .frame(width: size * 0.55, height: size * 0.2)
                }

            case .invisible, .offline:
                // Cercle gris creux (comme Discord)
                ZStack {
                    Circle()
                        .fill(statusColor)
                        .frame(width: size, height: size)
                    Circle()
                        .fill(borderColor)
                        .frame(width: size * 0.5, height: size * 0.5)
                }
            }
        }
    }
}

// MARK: - New Messages Separator

struct NewMessagesSeparator: View {
    var body: some View {
        HStack(spacing: 8) {
            Rectangle()
                .fill(MoodTheme.mentionBadge)
                .frame(height: 1)

            Text("NOUVEAU")
                .font(.mood(10, weight: .bold))
                .foregroundStyle(MoodTheme.mentionBadge)

            Rectangle()
                .fill(MoodTheme.mentionBadge)
                .frame(height: 1)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
    }
}

// MARK: - System Message Row

struct SystemMessageRow: View {
    let message: ChatMessage

    private var icon: String {
        switch message.systemType {
        case .userJoined: return "arrow.right.circle.fill"
        case .messagePinned: return "pin.circle.fill"
        case .serverBoosted: return "sparkles"
        case .none: return "info.circle"
        }
    }

    private var color: Color {
        switch message.systemType {
        case .userJoined: return MoodTheme.onlineGreen
        case .messagePinned: return MoodTheme.brandAccent
        case .serverBoosted: return MoodTheme.brandAccent
        case .none: return MoodTheme.textMuted
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8 * LayoutMetrics.scale) {
                Image(systemName: icon)
                    .font(.mood(12, weight: .bold))
                    .foregroundStyle(color)
                    .frame(width: 38 * LayoutMetrics.scale, alignment: .center)

                Text(message.content)
                    .font(.mood(13))
                    .foregroundStyle(MoodTheme.textSecondary)

                Text(message.timestamp.timeFormatted)
                    .font(.mood(11))
                    .foregroundStyle(MoodTheme.textMuted)
            }


        }
        .padding(.horizontal, 16)
        .padding(.vertical, 4)
    }
}

#Preview {
    ChatArea(
        channel: MockData.servers[0].categories[0].channels[0],
        server: MockData.servers[0],
        showProfilePopup: .constant(false),
        profileUser: .constant(nil)
    )
    .environment(MatrixStore())
    .environment(AuthState())
    .preferredColorScheme(.dark)
}

// MARK: - Inline Message Editor
// Discord: the message turns into a field — "échap pour annuler • entrée pour enregistrer".

struct MessageEditor: View {
    @Binding var text: String
    let onSave: () -> Void
    let onCancel: () -> Void
    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 4 * LayoutMetrics.scale) {
            TextField("", text: $text, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.mood(14))
                .foregroundStyle(MoodTheme.textPrimary)
                .focused($isFocused)
                .onSubmit(onSave)
                .onKeyPress(.escape) { onCancel(); return .handled }
                .padding(.horizontal, 12 * LayoutMetrics.scale)
                .padding(.vertical, 9 * LayoutMetrics.scale)
                .background(MoodTheme.inputBg)
                .clipShape(RoundedRectangle(cornerRadius: 8 * LayoutMetrics.scale, style: .continuous))

            HStack(spacing: 4) {
                Text("échap pour")
                Button("annuler", action: onCancel).buttonStyle(.plain).foregroundStyle(MoodTheme.brandBlue)
                Text("• entrée pour")
                Button("enregistrer", action: onSave).buttonStyle(.plain).foregroundStyle(MoodTheme.brandBlue)
            }
            .font(.mood(11))
            .foregroundStyle(MoodTheme.textMuted)
        }
        .onAppear { isFocused = true }
    }
}

// MARK: - Attachments

/// An image in a message: the preview keeps its size from `info` while it loads (no jump in the
/// list); a click downloads the original with the session token and opens it in Quick Look.
struct AttachmentImage: View {
    @Environment(MatrixStore.self) private var matrixStore
    let attachment: MessageAttachment
    let previewURL: URL
    @State private var quickLookURL: URL?
    @State private var isOpening = false

    /// Pixel size fitted in Discord's 400×300 box, never upscaled; nil when the event gave none.
    private var displaySize: CGSize? {
        guard let width = attachment.width, let height = attachment.height, width > 0, height > 0 else { return nil }
        let box = CGSize(width: 400 * LayoutMetrics.scale, height: 300 * LayoutMetrics.scale)
        let ratio = min(1, box.width / CGFloat(width), box.height / CGFloat(height))
        return CGSize(width: CGFloat(width) * ratio, height: CGFloat(height) * ratio)
    }

    var body: some View {
        AuthenticatedImage(url: previewURL) { phase in
            switch phase {
            case .success(let image):
                image.resizable().scaledToFit()
            case .failure:
                Label(attachment.name, systemImage: "photo")
                    .font(.mood(13))
                    .foregroundStyle(MoodTheme.textMuted)
                    .frame(width: 200 * LayoutMetrics.scale, height: 120 * LayoutMetrics.scale)
                    .background(MoodTheme.glassBg)
            case .empty:
                MoodTheme.glassBg
                    .frame(width: displaySize?.width ?? 320 * LayoutMetrics.scale,
                           height: displaySize?.height ?? 200 * LayoutMetrics.scale)
                    .overlay { ProgressView().controlSize(.small) }
            }
        }
        .frame(width: displaySize?.width, height: displaySize?.height)
        .frame(maxWidth: 400 * LayoutMetrics.scale, maxHeight: 300 * LayoutMetrics.scale, alignment: .leading)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            if isOpening { ProgressView().controlSize(.small) }
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: open)
        .help(attachment.name)
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel("Image \(attachment.name)")
        .quickLookPreview($quickLookURL)
    }

    private func open() {
        guard !isOpening else { return }
        // A message still being sent shows its local copy: nothing to download.
        if let url = attachment.url, url.isFileURL {
            quickLookURL = url
            return
        }
        isOpening = true
        Task {
            quickLookURL = await matrixStore.downloadAttachment(attachment)
            isOpening = false
        }
    }
}

/// A file in a message. Matrix media needs the session token, so a plain link cannot open it:
/// the card downloads it to a temporary file, then Quick Look opens it (with its share button).
struct AttachmentFileCard: View {
    @Environment(MatrixStore.self) private var matrixStore
    let attachment: MessageAttachment
    @State private var quickLookURL: URL?
    @State private var isDownloading = false

    var body: some View {
        Button(action: open) {
            HStack(spacing: 10 * LayoutMetrics.scale) {
                Image(systemName: "doc.fill")
                    .font(.mood(26))
                    .foregroundStyle(MoodTheme.brandBlue)
                VStack(alignment: .leading, spacing: 2) {
                    Text(attachment.name)
                        .font(.mood(14, weight: .medium))
                        .foregroundStyle(MoodTheme.brandBlue)
                        .lineLimit(1)
                    if let size = attachment.size {
                        Text(ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file))
                            .font(.mood(11))
                            .foregroundStyle(MoodTheme.textMuted)
                    }
                }
                Spacer(minLength: 16)
                if isDownloading {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Image(systemName: "arrow.down.to.line")
                        .font(.mood(16))
                        .foregroundStyle(MoodTheme.textSecondary)
                }
            }
            .padding(12 * LayoutMetrics.scale)
            .frame(maxWidth: 400 * LayoutMetrics.scale, alignment: .leading)
            .background(MoodTheme.glassBg)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(MoodTheme.glassBorder, lineWidth: 0.5)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isDownloading)
        .help("Télécharger \(attachment.name)")
        .quickLookPreview($quickLookURL)
    }

    private func open() {
        if let url = attachment.url, url.isFileURL {
            quickLookURL = url
            return
        }
        isDownloading = true
        Task {
            quickLookURL = await matrixStore.downloadAttachment(attachment)
            isDownloading = false
        }
    }
}

/// Discord's upload row: name, size, progress bar and ✕. Shown while an attachment waits or uploads.
struct AttachmentUploadCard: View {
    let name: String
    let size: Int?
    let progress: Double
    let onCancel: () -> Void

    var body: some View {
        HStack(spacing: 10 * LayoutMetrics.scale) {
            Image(systemName: "doc.fill")
                .font(.mood(26))
                .foregroundStyle(MoodTheme.textMuted)

            VStack(alignment: .leading, spacing: 6 * LayoutMetrics.scale) {
                HStack(spacing: 8 * LayoutMetrics.scale) {
                    Text(name)
                        .font(.mood(14, weight: .medium))
                        .foregroundStyle(MoodTheme.textPrimary)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    if let size {
                        Text(ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file))
                            .font(.mood(11))
                            .foregroundStyle(MoodTheme.textMuted)
                    }
                }
                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Capsule().fill(MoodTheme.textMuted.opacity(0.25))
                        Capsule().fill(MoodTheme.brandAccent)
                            .frame(width: proxy.size.width * min(max(progress, 0), 1))
                    }
                }
                .frame(height: 4 * LayoutMetrics.scale)
                .accessibilityElement()
                .accessibilityLabel("Envoi de \(name)")
                .accessibilityValue("\(Int((progress * 100).rounded())) %")
            }

            Button(action: onCancel) {
                Image(systemName: "xmark")
                    .font(.mood(13, weight: .semibold))
                    .foregroundStyle(MoodTheme.textSecondary)
                    .frame(width: 24 * LayoutMetrics.scale, height: 24 * LayoutMetrics.scale)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Annuler l'envoi")
            .accessibilityLabel("Annuler l'envoi de \(name)")
        }
        .padding(12 * LayoutMetrics.scale)
        .frame(maxWidth: 400 * LayoutMetrics.scale, alignment: .leading)
        .background(MoodTheme.glassBg)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(MoodTheme.glassBorder, lineWidth: 0.5)
        )
    }
}
