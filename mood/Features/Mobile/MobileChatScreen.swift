import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct MobileChatScreen: View {
    let destination: MobileDestination
    let store: MatrixStore
    let authState: AuthState
    @Binding var showMembers: Bool
    let onBack: () -> Void
    @State private var text = ""
    @State private var previewMessages: [ChatMessage] = []
    @State private var showEmoji = false
    @State private var showImporter = false
    @State private var replyingTo: ChatMessage?
    @State private var editRequest: UUID?
    @State private var profileUser: MoodUser?
    @State private var thread: ChatMessage?
    @State private var showPins = false
    @State private var showConversationSearch = false
    @State private var showThreadDirectory = false
    @State private var isAtBottom = true
    @State private var draftAttachment: URL?
    @State private var visibleMessageIDs: Set<UUID> = []
    @State private var historyAnchor: UUID?

    private var name: String {
        switch destination {
        case .channel(let channel, _): demo && channel.name == "general" ? "général" : channel.name
        case .dm(let dm): dm.participant.displayName
        }
    }

    private var roomId: String? {
        switch destination {
        case .channel(let channel, _): store.roomId(for: channel)
        case .dm(let dm): store.roomId(for: dm)
        }
    }

    private var server: MoodServer? {
        if case .channel(_, let server) = destination { return server }
        return nil
    }

    private var encrypted: Bool { roomId.map { store.isRoomEncrypted($0) } ?? false }
    private var demo: Bool { authState.isDemoMode && store.userId == nil }
    private var messages: [ChatMessage] {
        switch destination {
        case .channel(let channel, _): demo ? previewMessages : store.messages(for: channel)
        case .dm(let dm): demo ? previewMessages : store.messages(forDM: dm)
        }
    }

    var body: some View {
        NavigationStack {
            conversationContent.toolbar(.hidden, for: .navigationBar)
        }
    }

    private var conversationContent: some View {
        VStack(spacing: LayoutMetrics.mobile(0)) {
            Rectangle().fill(MoodTheme.divider).frame(height: LayoutMetrics.mobile(0.5))
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: LayoutMetrics.mobile(8)) {
                        if let roomId, store.hasMoreHistory[roomId] == true {
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
                        }
                        ForEach(messages) { message in
                            if let roomId, store.newMessagesDivider[roomId] == message.eventId, message.eventId != nil {
                                NewMessagesSeparator()
                            }
                            MessageRow(message: message, server: server, roomId: roomId, editRequest: $editRequest,
                                       onReply: { replyingTo = message }, onThread: { thread = message },
                                       onAvatarTap: { profileUser = message.sender })
                                .id(message.id)
                                .onAppear { visibleMessageIDs.insert(message.id) }
                                .onDisappear { visibleMessageIDs.remove(message.id) }
                        }
                        Color.clear.frame(height: LayoutMetrics.mobile(1)).id("bottom")
                            .onAppear { isAtBottom = true }.onDisappear { isAtBottom = false }
                    }.padding(.top, LayoutMetrics.mobile(18))
                }
                .contentMargins(.bottom, LayoutMetrics.mobile(16), for: .scrollContent)
                .defaultScrollAnchor(.bottom)
                .scrollDismissesKeyboard(.interactively)
                .onAppear { proxy.scrollTo("bottom", anchor: .bottom) }
                 .onChange(of: messages.last?.id) { _, _ in
                    if isAtBottom || messages.last?.isOwn == true {
                        proxy.scrollTo("bottom", anchor: .bottom)
                        if let roomId { store.markAsRead(roomId: roomId) }
                    }
                }
                .safeAreaInset(edge: .bottom) {
                    if !isAtBottom { JumpToPresentBar { proxy.scrollTo("bottom", anchor: .bottom) } }
                }
                .jumpToRequestedMessage(roomId: roomId, messages: messages, proxy: proxy)
            }
            if let error = store.errorMessage {
                HStack {
                    Text(error).font(.mood(13))
                    Spacer()
                    Button("Fermer") { store.errorMessage = nil }.font(.mood(12))
                }.padding(LayoutMetrics.mobile(12)).foregroundStyle(MoodTheme.textPrimary)
                    .background(MoodTheme.inputBg)
            }
            if encrypted { EncryptedRoomNotice() }
            composer
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .safeAreaInset(edge: .top, spacing: 0) {
            header.fixedSize(horizontal: false, vertical: true).background(MoodTheme.chatBackground)
        }
        .background(MoodTheme.chatBackground)
        .environment(store).environment(authState).environment(\.layoutMode, .compact)
        .onAppear {
            if demo, previewMessages.isEmpty {
                switch destination {
                case .channel(let channel, _): previewMessages = MockData.messages(for: channel)
                case .dm(let dm): previewMessages = MockData.dmMessages(for: dm)
                }
            }
            if demo {
                let kind = MessagingPreview.kind
                if kind == "mentions" { text = "Salut @al" }
                if kind == "reply" { replyingTo = previewMessages.first }
                if kind == "edit", let index = previewMessages.indices.last {
                    previewMessages[index].isOwn = true
                    editRequest = previewMessages[index].id
                }
                if kind == "pins" { showPins = true }
                if kind == "attachment" {
                    let url = FileManager.default.temporaryDirectory.appendingPathComponent("exemple.txt")
                    try? Data("Pièce jointe de démonstration".utf8).write(to: url)
                    draftAttachment = url
                }
            }
            if let roomId { store.markAsRead(roomId: roomId) }
        }
        .task(id: showPins) { if showPins, let roomId { await store.loadMessagingPins(roomId: roomId) } }
        .onChange(of: isAtBottom) { _, value in if value, let roomId { store.markAsRead(roomId: roomId) } }
        .onChange(of: text) { _, value in
            guard let roomId, !encrypted else { return }
            Task { await store.setTyping(roomId: roomId, typing: !value.isEmpty) }
        }
        .onDisappear { if let roomId { Task { await store.setTyping(roomId: roomId, typing: false) } } }
        .sheet(isPresented: $showPins) {
            PinnedMessagesPanel(messages: messages.filter(\.isPinned), server: server, showPanel: $showPins, onJump: { message in
                showPins = false
                if let roomId, let eventId = message.eventId { store.requestJump(roomId: roomId, eventId: eventId) }
            }).environment(store).presentationDetents([.medium, .large])
        }
        .sheet(isPresented: $showEmoji) {
            MobileEmojiPicker { text += $0 }
                .presentationDetents([.medium, .large]).presentationDragIndicator(.visible)
        }
        .sheet(item: $profileUser) { user in
            MobileUserProfileSheet(user: user, server: server)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
                .presentationBackground(MoodTheme.mobileSurface)
        }
        .navigationDestination(isPresented: Binding(get: { thread != nil }, set: { if !$0 { thread = nil } })) {
            if let thread {
                ThreadPanel(message: thread, roomId: roomId, server: server,
                    showPanel: Binding(get: { self.thread != nil }, set: { if !$0 { self.thread = nil } }))
                    .environment(store)
                    .navigationTitle("Fil de discussion").navigationBarTitleDisplayMode(.inline)
                    .toolbar(.visible, for: .navigationBar)
            }
        }
        .navigationDestination(isPresented: $showConversationSearch) {
            if let roomId {
                ConversationSearchScreen(roomId: roomId, server: server, onClose: { showConversationSearch = false })
                    .environment(store)
            }
        }
        .sheet(isPresented: $showThreadDirectory) {
            ConversationThreadDirectory(roomId: roomId, onOpen: { root in
                showThreadDirectory = false
                thread = root
            }, onClose: { showThreadDirectory = false }).environment(store)
        }
        .onChange(of: store.conversationThreadJump, initial: true) { _, _ in
            if let roomId, let root = store.conversationJumpRoot(roomId: roomId) { thread = root }
        }

        .fileImporter(isPresented: $showImporter, allowedContentTypes: [.item]) { result in
            guard case .success(let url) = result else { return }
            draftAttachment = url
        }
    }

    private var header: some View {
        MobileGlassGroup {
            HStack(spacing: LayoutMetrics.mobile(4)) {
                Button(action: onBack) {
                    Image(systemName: "chevron.left").font(.mood(21))
                        .frame(width: LayoutMetrics.mobile(44), height: LayoutMetrics.mobile(44)).mobileGlassCapsule()
                }.buttonStyle(.plain).accessibilityLabel("Retour")
                Button {
                    if server != nil { showMembers = true }
                    else if case .dm(let dm) = destination { profileUser = dm.participant }
                } label: {
                    VStack(alignment: .leading, spacing: LayoutMetrics.mobile(4)) {
                        HStack(spacing: LayoutMetrics.mobile(7)) {
                            if server != nil { Image(systemName: "number").font(.mood(23)) }
                            Text(name).font(.mood(17, weight: .semibold)).fixedSize(horizontal: false, vertical: true)
                            Image(systemName: "chevron.right").font(.mood(12))
                        }
                        HStack(spacing: LayoutMetrics.mobile(5)) {
                            if server != nil {
                                Circle().fill(MoodTheme.onlineGreen).frame(width: LayoutMetrics.mobile(7), height: LayoutMetrics.mobile(7))
                            } else if case .dm(let dm) = destination {
                                StatusIndicator(status: dm.participant.status, size: LayoutMetrics.mobile(8))
                            }
                            if let server {
                                Text("En ligne - \(server.members.filter { $0.status == .online }.count)")
                            } else if case .dm(let dm) = destination { Text(dm.participant.status.rawValue) }
                        }.font(.mood(12)).foregroundStyle(MoodTheme.textMuted)
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }.buttonStyle(.plain)
                if roomId != nil, !encrypted {
                    Menu {
                        Button("Rechercher", systemImage: "magnifyingglass") { showConversationSearch = true }
                        Button("Fils du salon", systemImage: "bubble.left.and.bubble.right") { showThreadDirectory = true }
                    } label: { Image(systemName: "ellipsis").font(.mood(18)).frame(width: LayoutMetrics.mobile(44), height: LayoutMetrics.mobile(44)) }
                    .accessibilityLabel("Actions de conversation")
                }
                Button { showPins = true } label: { Image(systemName: "pin").font(.mood(18)).frame(width: LayoutMetrics.mobile(44), height: LayoutMetrics.mobile(44)) }
                    .accessibilityLabel("Messages épinglés")
            }.foregroundStyle(MoodTheme.textPrimary)
        }.padding(.horizontal, LayoutMetrics.mobile(12)).padding(.vertical, LayoutMetrics.mobile(12))
    }

    private var composerRoomKey: String {
        if let roomId { return roomId }
        switch destination {
        case .channel(let channel, _): return "demo-channel-" + channel.id.uuidString
        case .dm(let dm): return "demo-dm-" + dm.id.uuidString
        }
    }

    private var composer: some View {
        VStack(spacing: LayoutMetrics.mobile(8)) {
            if let roomId, let typing = store.typingUsersByRoom[roomId], !typing.isEmpty {
                Text(typing.joined(separator: ", ") + " est en train d’écrire…")
                    .font(.mood(11)).foregroundStyle(MoodTheme.textMuted)
            }
            if demo, let url = draftAttachment,
               ProcessInfo.processInfo.arguments.contains("-mediaPreview") {
                AttachmentDraftPreview(url: url, onCancel: { draftAttachment = nil }, onSend: {})
            }
            MediaComposer(
                roomID: composerRoomKey, channelName: server == nil ? name : "#" + name,
                disabled: encrypted || (roomId == nil && !demo),
                text: $text, replyingTo: $replyingTo,
                members: demo ? MessagingPreview.members : server?.members.compactMap { member in
                    member.matrixId.map { MentionCandidate(userId: $0, displayName: member.displayName) }
                } ?? []
            )
            .id((store.userId ?? "demo") + composerRoomKey)
            .onKeyPress(.upArrow) {
                guard let id = MessagingServerPolicy.lastEditable(messages, draft: text) else { return .ignored }
                editRequest = id; return .handled
            }
        }.padding(.horizontal, LayoutMetrics.mobile(12)).padding(.bottom, LayoutMetrics.mobile(8))
    }

    private func send() {
        let body = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let roomId, !body.isEmpty, !encrypted, store.validateOutgoingText(body) else { return }
        let reply = replyingTo?.eventId
        text = ""
        replyingTo = nil
        Task { await store.sendMessage(roomId: roomId, text: body, replyToEventId: reply) }
    }
}

enum MobileDestination: Equatable {
    case channel(Channel, MoodServer)
    case dm(DMConversation)

    static func == (lhs: Self, rhs: Self) -> Bool {
        switch (lhs, rhs) {
        case (.channel(let a, _), .channel(let b, _)): a.id == b.id
        case (.dm(let a), .dm(let b)): a.id == b.id
        default: false
        }
    }
}
