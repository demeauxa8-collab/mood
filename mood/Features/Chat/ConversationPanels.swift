import SwiftUI

struct ThreadPanel: View {
    @Environment(MatrixStore.self) private var store
    let message: ChatMessage
    var roomId: String? = nil
    let server: MoodServer?
    @Binding var showPanel: Bool
    @Environment(\.layoutMode) private var layoutMode
    @State private var text = ""

    /// iPhone pushes the thread in a navigation stack: the system bar carries the title and back button.
    private var compact: Bool { layoutMode == .compact }
    private var cannotSend: Bool { text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || roomId == nil || store.userId == nil }
    private var replyCount: String { replies.count > 1 ? "\(replies.count) réponses" : "\(replies.count) réponse" }

    private var replies: [ChatMessage] {
        guard let roomId, let root = message.eventId else { return [] }
        return store.conversationReplies(roomId: roomId, root: root)
    }

    var body: some View {
        VStack(spacing: 0) {
            if !compact {
                HStack {
                    Text("Fil de discussion").font(.mood(15, weight: .bold))
                    Spacer()
                    Button("Fermer") { showPanel = false }
                }.padding(12 * LayoutMetrics.scale)
                DesktopPixelRule()
            }
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12 * LayoutMetrics.scale) {
                        threadRow(message)
                        Text(replyCount).font(.mood(compact ? 14 : 12)).foregroundStyle(MoodTheme.textMuted)
                        if let roomId, !store.conversationHistoryComplete.contains(roomId) {
                            Button("Charger les réponses plus anciennes") { Task { await store.loadConversationHistory(roomId: roomId) } }
                                .disabled(store.conversationLoading.contains(roomId))
                        }
                        ForEach(replies) { reply in
                            threadRow(reply).id(reply.id)
                            if reply.sendState == .failed, let roomId {
                                Button("Réessayer") { store.retryMessage(reply.id, roomId: roomId) }
                            }
                        }
                    }.padding(compact ? LayoutMetrics.mobile(16) : 12 * LayoutMetrics.scale)
                }
                .task(id: store.conversationThreadJump) {
                    guard let jump = store.conversationThreadJump, jump.roomId == roomId,
                          let reply = replies.first(where: { $0.eventId == jump.eventId }) else { return }
                    try? await Task.sleep(for: .milliseconds(100))
                    guard !Task.isCancelled else { return }
                    proxy.scrollTo(reply.id, anchor: .center)
                    store.conversationThreadJump = nil
                }
                .onChange(of: replies.last?.id) { _, id in if let id { proxy.scrollTo(id, anchor: .bottom) } }
            }
            if compact {
                // Same Liquid Glass capsule as the channel composer, with its violet send arrow.
                MobileGlassGroup {
                    HStack(spacing: LayoutMetrics.mobile(10)) {
                        TextField("Répondre au fil", text: $text)
                            .textFieldStyle(.plain).font(.mood(16))
                            .onSubmit(send)
                            .submitLabel(.send)
                        Button(action: send) {
                            Image(systemName: "arrow.up.circle.fill").font(.mood(26)).foregroundStyle(MoodTheme.brandAccent)
                                .frame(minWidth: LayoutMetrics.mobile(44), minHeight: LayoutMetrics.mobile(44))
                        }
                        .accessibilityLabel("Envoyer")
                        .disabled(cannotSend).opacity(cannotSend ? 0.4 : 1)
                    }
                    .buttonStyle(.plain).foregroundStyle(MoodTheme.textPrimary)
                    .padding(.leading, LayoutMetrics.mobile(16)).padding(.trailing, LayoutMetrics.mobile(6))
                    .padding(.vertical, LayoutMetrics.mobile(6))
                    .mobileGlassCapsule()
                }
                .padding(.horizontal, LayoutMetrics.mobile(16)).padding(.bottom, LayoutMetrics.mobile(8))
            } else {
                HStack {
                    TextField("Répondre au fil", text: $text)
                        .textFieldStyle(.plain)
                        .onSubmit(send)
                        .submitLabel(.send)
                    Button("Envoyer", action: send)
                        .disabled(cannotSend)
                }
                .font(.mood(14)).padding(12 * LayoutMetrics.scale)
                .background(MoodTheme.inputBg)
            }
        }
        .foregroundStyle(MoodTheme.textPrimary)
        .background(MoodTheme.chatBackground)
        .task(id: message.eventId) {
            guard let roomId else { return }
            await store.loadConversationHistory(roomId: roomId)
            if let root = message.eventId { await store.readConversationThread(roomId: roomId, root: root) }
        }
        .onChange(of: replies.last?.eventId) { _, _ in
            guard let roomId, let root = message.eventId else { return }
            Task { await store.readConversationThread(roomId: roomId, root: root) }
        }
    }

    private func threadRow(_ message: ChatMessage) -> some View {
        VStack(alignment: .leading, spacing: 4 * LayoutMetrics.scale) {
            HStack {
                Text(message.sender.displayName).font(.mood(compact ? 16 : 13, weight: .semibold))
                Text(message.timestamp.messageTimestamp).font(.mood(compact ? 12 : 10)).foregroundStyle(MoodTheme.textMuted)
            }
            Text(message.content + (message.isEdited ? " (modifié)" : "")).font(.mood(compact ? 16 : 14)).textSelection(.enabled)
            if message.sendState == .sending { Text("Envoi en cours…").font(.mood(compact ? 13 : 11)).foregroundStyle(MoodTheme.textMuted) }
        }
    }

    private func send() {
        guard let roomId, let root = message.eventId, store.userId != nil else { return }
        let body = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty, store.validateOutgoingText(body) else { return }
        text = ""
        Task { await store.sendMessage(roomId: roomId, text: body, replyToEventId: root, threadRootEventId: root) }
    }
}

struct ConversationThreadDirectory: View {
    @Environment(MatrixStore.self) private var store
    let roomId: String?
    let onOpen: (ChatMessage) -> Void
    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12 * LayoutMetrics.scale) {
            HStack { Text("Fils du salon").font(.mood(18, weight: .bold)); Spacer(); Button("Fermer", action: onClose) }
            ScrollView {
                VStack(alignment: .leading, spacing: 12 * LayoutMetrics.scale) {
                    if let roomId {
                        let roots = store.conversationThreads(roomId: roomId)
                        if roots.isEmpty { Text("Aucun fil dans l’historique chargé.").font(.mood(14)) }
                        ForEach(roots) { root in
                            Button { onOpen(root) } label: {
                                VStack(alignment: .leading, spacing: 4 * LayoutMetrics.scale) {
                                    Text(root.content).lineLimit(2)
                                    Text("\(root.threadInfo?.replyCount ?? 0) réponses").foregroundStyle(MoodTheme.textMuted)
                                    if let id = root.eventId, (store.conversationThreadUnread[roomId]?[id] ?? 0) > 0 { Text("Non lu").foregroundStyle(MoodTheme.brandBlue) }
                                }.font(.mood(14)).frame(maxWidth: .infinity, alignment: .leading)
                            }.buttonStyle(.plain)
                        }
                        if !store.conversationHistoryComplete.contains(roomId) {
                            Button("Charger les fils plus anciens") { Task { await store.loadConversationHistory(roomId: roomId) } }
                                .disabled(store.conversationLoading.contains(roomId))
                        }
                    } else { Text("Les fils seront disponibles dans une conversation connectée.").font(.mood(14)) }
                }
            }
        }
        .padding(16 * LayoutMetrics.scale)
        .frame(maxWidth: 460 * LayoutMetrics.scale, maxHeight: 500 * LayoutMetrics.scale)
        .background(MoodTheme.channelList)
        .foregroundStyle(MoodTheme.textPrimary)
        .clipShape(RoundedRectangle(cornerRadius: 12 * LayoutMetrics.scale))
        .padding(16 * LayoutMetrics.scale)
        .task { if let roomId { await store.loadConversationHistory(roomId: roomId) } }
    }
}

struct ConversationForwardPicker: View {
    @Environment(MatrixStore.self) private var store
    let message: ChatMessage
    let onClose: () -> Void
    @State private var query = ""
    @State private var sending = false
    @State private var failure = false

    private var destinations: [(id: String, title: String)] {
        let channels = store.servers.flatMap { server in
            server.categories.flatMap(\.channels).compactMap { channel -> (id: String, title: String)? in
                guard let id = store.roomId(for: channel), !store.isRoomEncrypted(id) else { return nil }
                return (id, "\(server.name) · #\(channel.name)")
            }
        }
        let dms = store.dmConversations.compactMap { dm -> (id: String, title: String)? in
            guard let id = store.roomId(for: dm), !store.isRoomEncrypted(id) else { return nil }
            return (id, dm.participant.displayName)
        }
        return (channels + dms).filter { query.isEmpty || $0.title.localizedCaseInsensitiveContains(query) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12 * LayoutMetrics.scale) {
            HStack { Text("Transférer le message").font(.mood(18, weight: .bold)); Spacer(); Button("Fermer", action: onClose).disabled(sending) }
            Text(message.content).font(.mood(13)).lineLimit(3).foregroundStyle(MoodTheme.textMuted)
            TextField("Rechercher un salon ou un message privé", text: $query).textFieldStyle(.roundedBorder).font(.mood(14))
            if failure { Text("Le transfert a échoué. Réessaie.").font(.mood(13)).foregroundStyle(MoodTheme.mentionBadge) }
            ScrollView {
                VStack(alignment: .leading, spacing: 12 * LayoutMetrics.scale) {
                    if destinations.isEmpty { Text("Aucune conversation trouvée.").font(.mood(14)) }
                    ForEach(destinations, id: \.id) { destination in
                        Button {
                            sending = true
                            Task {
                                let success = await store.forwardConversationMessage(message, to: destination.id)
                                sending = false
                                failure = !success
                                if success { onClose() }
                            }
                        } label: { Text(destination.title).font(.mood(14)).frame(maxWidth: .infinity, alignment: .leading) }
                        .disabled(sending || store.userId == nil)
                    }
                }
            }
            if sending { ProgressView("Transfert en cours…").font(.mood(12)) }
        }
        .padding(16 * LayoutMetrics.scale)
        .frame(maxWidth: 460 * LayoutMetrics.scale, maxHeight: 500 * LayoutMetrics.scale)
        .foregroundStyle(MoodTheme.textPrimary).background(MoodTheme.channelList)
        .clipShape(RoundedRectangle(cornerRadius: 12 * LayoutMetrics.scale))
        .padding(16 * LayoutMetrics.scale)
    }
}

struct ConversationMobileSearch: View {
    let model: MessageSearchModel
    let onOpen: (SearchHit) -> Void
    let onRetry: () -> Void
    let onMore: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16 * LayoutMetrics.scale) {
                switch model.phase {
                case .idle: Text("Recherche par mot, de:nom ou dans:salon.")
                case .loading: ProgressView("Recherche en cours…")
                case .needsTerm: Text("Ajoute un mot à rechercher.")
                case .unavailable: Text("La recherche n’est pas disponible dans ces conversations.")
                case .failed: Text("La recherche a échoué."); Button("Réessayer", action: onRetry)
                case .loaded:
                    Text("\(model.resultCount) résultats").foregroundStyle(MoodTheme.textMuted)
                    ForEach(model.hits) { hit in
                        Button { onOpen(hit) } label: {
                            VStack(alignment: .leading, spacing: 4 * LayoutMetrics.scale) {
                                Text("\(hit.destination.title) · \(hit.message.sender.displayName)").font(.mood(12, weight: .semibold))
                                Text(hit.message.content).font(.mood(14))
                                Text(hit.message.timestamp.messageTimestamp).font(.mood(11)).foregroundStyle(MoodTheme.textMuted)
                            }.frame(maxWidth: .infinity, alignment: .leading)
                        }.buttonStyle(.plain)
                    }
                    if model.nextBatch != nil { Button("Plus de résultats", action: onMore).disabled(model.isLoadingMore) }
                    if model.loadMoreError != nil { Text("La suite n’a pas pu être chargée. Réessaie.") }
                }
            }.font(.mood(14)).padding(16 * LayoutMetrics.scale).frame(maxWidth: .infinity, alignment: .leading)
        }
        .foregroundStyle(MoodTheme.textPrimary).background(MoodTheme.chatBackground)
    }
}

/// Mobile entry point available from the shared message menu, without modifying the N2 composer.
struct ConversationSearchScreen: View {
    @Environment(MatrixStore.self) private var store
    let roomId: String
    let server: MoodServer?
    let onClose: () -> Void
    @State private var model = MessageSearchModel()
    @State private var roomOnly = true

    private var scope: SearchScope? {
        if let server { return .server(server) }
        if case .dm(let dm) = store.destination(forRoomId: roomId) { return .dm(dm) }
        return nil
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if server != nil {
                    Picker("Rechercher dans", selection: $roomOnly) {
                        Text("Ce salon").tag(true)
                        Text("Ce serveur").tag(false)
                    }.pickerStyle(.segmented).padding(12 * LayoutMetrics.scale)
                }
                HStack {
                    TextField("Mot, de:nom, dans:salon", text: $model.query).onSubmit(submit)
                    Button("Chercher", action: submit)
                }.font(.mood(14)).padding(12 * LayoutMetrics.scale)
                ConversationMobileSearch(model: model, onOpen: { hit in
                    store.openConversationSearchResult(hit)
                    onClose()
                }, onRetry: submit, onMore: { if let scope { model.loadMore(store: store, scope: scope) } })
            }
            .background(MoodTheme.chatBackground).foregroundStyle(MoodTheme.textPrimary)
            .navigationTitle("Recherche").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Fermer", action: onClose) } }
        }
    }

    private func submit() {
        guard let scope else { return }
        let typedQuery = model.query
        if roomOnly, case .channel(let channel, _) = store.destination(forRoomId: roomId),
           !model.query.contains("dans:") && !model.query.contains("in:") {
            model.query = SearchQueryParser.token(for: channel) + " " + typedQuery
        }
        model.submit(store: store, scope: scope)
        model.query = typedQuery
    }
}
