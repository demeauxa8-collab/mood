import SwiftUI

private struct FirstRunFont: ViewModifier {
    @ScaledMetric private var size: CGFloat
    let weight: Font.Weight
    init(size: CGFloat, weight: Font.Weight) {
        _size = ScaledMetric(wrappedValue: size, relativeTo: .body)
        self.weight = weight
    }
    func body(content: Content) -> some View { content.font(.mood(size, weight: weight)) }
}

extension View {
    func firstRunFont(_ size: CGFloat, weight: Font.Weight = .regular) -> some View {
        modifier(FirstRunFont(size: size, weight: weight))
    }
}

/// Shared by the two conversation surfaces; actions remain owned by their existing hosts.
struct FirstRunChannelBeginning: View {
    @Environment(MatrixStore.self) private var store
    let channel: Channel
    let server: MoodServer
    let messages: [ChatMessage]
    let onInvite: () -> Void
    let onSettings: () -> Void
    let onEdit: () -> Void
    let onCompose: () -> Void
    var previewNewServer = false
    @State private var progress: ServerWelcomeProgress

    init(channel: Channel, server: MoodServer, messages: [ChatMessage], onInvite: @escaping () -> Void,
         onSettings: @escaping () -> Void, onEdit: @escaping () -> Void, onCompose: @escaping () -> Void,
         previewNewServer: Bool = false) {
        self.channel = channel
        self.server = server
        self.messages = messages
        self.onInvite = onInvite
        self.onSettings = onSettings
        self.onEdit = onEdit
        self.onCompose = onCompose
        self.previewNewServer = previewNewServer
        _progress = State(initialValue: previewNewServer || FirstRunPreview.enabled ? ServerWelcomeProgress() : .shared)
    }

    private var liveServer: MoodServer { store.servers.first { $0.id == server.id } ?? server }
    private var scope: ServerWelcomeScope? {
        store.firstRunScope(for: server) ?? (previewNewServer ? ServerWelcomeScope(account: "preview", server: "preview") : nil)
    }
    private var showChecklist: Bool {
        guard let scope else { return false }
        return FirstRunPolicy.showsChecklist(
            isFirstTextChannel: server.categories.flatMap(\.channels).first { $0.type == .text }?.id == channel.id,
            canManage: previewNewServer || store.myPowerLevel(in: server) >= 50,
            knownStart: true, hasMessages: messages.contains { !$0.isSystemMessage },
            started: progress.started(scope), finished: progress.finished(scope))
    }
    private var sentFirstMessage: Bool {
        messages.contains { FirstRunPolicy.confirmedFirstMessage(isOwn: $0.isOwn, isSystem: $0.isSystemMessage, accepted: $0.sendState == .sent) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: LayoutMetrics.mobile(24)) {
            if showChecklist, let scope {
                ServerWelcomeChecklist(server: liveServer, scope: scope, progress: progress,
                    onInvite: onInvite, onSettings: onSettings, onCompose: onCompose)
            }
            ChannelBeginningState(name: channel.name,
                onEdit: store.firstRunCanEditChannel(channel) ? onEdit : nil)
        }
        .padding(.horizontal, LayoutMetrics.mobile(16))
        .padding(.vertical, LayoutMetrics.mobile(24))
        .task(id: scope) {
            if showChecklist, let scope { progress.begin(scope) }
            recordCompletedSteps()
        }
        .onChange(of: liveServer.iconURL) { _, _ in recordCompletedSteps() }
        .onChange(of: liveServer.members.count) { _, _ in recordCompletedSteps() }
        .onChange(of: sentFirstMessage) { _, _ in recordCompletedSteps() }
    }

    private func recordCompletedSteps() {
        guard let scope, progress.started(scope) else { return }
        if liveServer.iconURL != nil { progress.complete(.icon, in: scope) }
        if liveServer.members.contains(where: { $0.matrixId != nil && $0.matrixId != store.userId }) {
            progress.complete(.invite, in: scope)
        }
        if sentFirstMessage { progress.complete(.message, in: scope) }
    }
}

struct ChannelBeginningState: View {
    let name: String
    var onEdit: (() -> Void)?
    var body: some View {
        VStack(alignment: .leading, spacing: LayoutMetrics.mobile(10)) {
            Image(systemName: "number").font(.mood(34, weight: .bold))
                .frame(width: LayoutMetrics.mobile(68), height: LayoutMetrics.mobile(68))
                .background(MoodTheme.inputBg, in: Circle()).accessibilityHidden(true)
            Text("Bienvenue dans #\(name) !").firstRunFont(28, weight: .bold).accessibilityAddTraits(.isHeader)
            Text("C'est le début du salon #\(name).").firstRunFont(15).foregroundStyle(MoodTheme.textSecondary)
            if let onEdit {
                Button(action: onEdit) { Label("Modifier le salon", systemImage: "pencil").firstRunFont(14) }
                    .buttonStyle(.plain).foregroundStyle(MoodTheme.brandAccent)
                    .frame(minHeight: LayoutMetrics.mobile(44))
            }
        }
        .foregroundStyle(MoodTheme.textPrimary)
        .frame(maxWidth: .infinity, alignment: .leading)
        .fixedSize(horizontal: false, vertical: true)
    }
}

struct DirectMessageBeginningState: View {
    @Environment(\.layoutMode) private var layoutMode
    let user: MoodUser
    let username: String?
    var onBlock: (() -> Void)? = nil
    var supportsOfflineDelivery = true
    var body: some View {
        VStack(alignment: .leading, spacing: LayoutMetrics.mobile(10)) {
            AvatarGlyph(user: user).font(.mood(46))
                .frame(width: LayoutMetrics.mobile(80), height: LayoutMetrics.mobile(80))
                .background(MoodTheme.glassBg, in: Circle()).accessibilityHidden(true)
            Text(user.displayName).firstRunFont(32, weight: .bold).accessibilityAddTraits(.isHeader)
            if let username = FirstRunPolicy.publicUsername(username) {
                Text(username).firstRunFont(20).foregroundStyle(MoodTheme.textSecondary)
            }
            Text("C'est le début de ton historique de messages privés avec \(user.displayName).")
                .firstRunFont(16).foregroundStyle(MoodTheme.textSecondary)
            if let onBlock {
                Button("Bloquer", action: onBlock).firstRunFont(14)
                    .buttonStyle(.plain).foregroundStyle(MoodTheme.textSecondary)
                    .frame(minHeight: LayoutMetrics.mobile(44))
            }
            if supportsOfflineDelivery {
                Text("Tes messages partent même sans réseau : ils attendent et s'envoient au retour.")
                    .firstRunFont(13).foregroundStyle(MoodTheme.textMuted)
            }
        }
        .foregroundStyle(MoodTheme.textPrimary)
        .frame(maxWidth: .infinity, alignment: .leading)
        .fixedSize(horizontal: false, vertical: true)
        .padding(.horizontal, LayoutMetrics.mobile(16))
        .padding(.top, LayoutMetrics.mobile(layoutMode == .regular ? 60 : 24))
        .padding(.bottom, LayoutMetrics.mobile(24))
    }
}

struct FriendsFirstRunState: View {
    let onAddFriend: () -> Void
    var body: some View {
        VStack(spacing: LayoutMetrics.mobile(14)) {
            MoodInfinitySymbol(size: LayoutMetrics.mobile(42))
                .frame(width: LayoutMetrics.mobile(88), height: LayoutMetrics.mobile(88))
                .background(MoodTheme.inputBg, in: Circle()).accessibilityHidden(true)
            Text("Tu n'as pas encore d'amis sur Mood.")
                .firstRunFont(18, weight: .semibold).accessibilityAddTraits(.isHeader)
            Button("Ajouter un ami", action: onAddFriend)
                .firstRunFont(15, weight: .semibold)
                .padding(.horizontal, LayoutMetrics.mobile(18))
                .frame(minHeight: LayoutMetrics.mobile(44))
                .background(MoodTheme.brandAccent, in: Capsule())
                .foregroundStyle(MoodTheme.mobileIndicator)
                .buttonStyle(.plain)
            Text("Recherche son nom d'utilisateur.").firstRunFont(14).foregroundStyle(MoodTheme.textSecondary)
        }
        .foregroundStyle(MoodTheme.textPrimary).multilineTextAlignment(.center)
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity).padding(LayoutMetrics.mobile(24))
    }
}

/// Unknown history is a loading/retry state, never an empty conversation presented as a fact.
struct FirstRunHistoryPlaceholder: View {
    @Environment(MatrixStore.self) private var store
    let roomID: String
    var body: some View {
        Group {
            if store.conversationLoading.contains(roomID) {
                ProgressView("Chargement des messages…")
            } else {
                Button("Charger les messages") {
                    Task { await store.loadConversationHistory(roomId: roomID) }
                }.buttonStyle(.plain).frame(minHeight: LayoutMetrics.mobile(44))
            }
        }
        .firstRunFont(14).foregroundStyle(MoodTheme.textSecondary)
        .frame(maxWidth: .infinity).padding(LayoutMetrics.mobile(24))
    }
}
