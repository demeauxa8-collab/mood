import SwiftUI

enum FirstRunPreview {
    static var enabled: Bool { ProcessInfo.processInfo.arguments.contains("-uiPreview") }
    static let screens: Set<String> = ["first-run-server", "first-run-channel", "first-run-dm", "first-run-friends",
        "first-run-notifications", "first-run-search", "first-run-server-long", "first-run-dm-long", "first-run-large-text"]
}

/// Isolated fixtures only: no session restore, login, sync, or real identifiers.
struct FirstRunPreviewScreen: View {
    @Environment(\.dismiss) private var dismiss
    let screen: String
    @State private var store = MatrixStore()
    @State private var search = MessageSearchModel()
    @State private var showInvite = false
    @State private var showSettings = false
    @State private var showEdit = false
    @State private var showAddFriend = false
    @State private var text = ""
    @State private var reply: ChatMessage?
    @State private var focusRequest: UUID?
    private var server: MoodServer {
        let base = MockData.servers[0]
        return MoodServer(id: base.id,
            name: screen.hasSuffix("long") ? "Les amis de Camille et notre très longue aventure du week-end" : "Les amis",
            iconEmoji: base.iconEmoji,
            categories: [ChannelCategory(id: base.categories[0].id, name: "Salons texte", channels: [channel])],
            members: [], memberRoles: [:], hasUnread: false, mentionCount: 0)
    }
    private var channel: Channel {
        Channel(id: MockData.servers[0].categories[0].channels[0].id, name: "général", type: .text,
            topic: "", unreadCount: 0, isE2E: false)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollView {
                    content
                }
                if screen.contains("server") || screen == "first-run-channel" || screen == "first-run-large-text" {
                    MediaComposer(roomID: "first-run-preview", channelName: "#général", text: $text, replyingTo: $reply,
                        focusRequest: focusRequest)
                        .padding(LayoutMetrics.mobile(12))
                }
            }
            .navigationTitle("Aperçu Mood").navigationBarTitleDisplayMode(.inline)
            .background(MoodTheme.chatBackground)
            .sheet(isPresented: $showInvite) { ServerInviteModal(server: server, isPresented: $showInvite) }
            .sheet(isPresented: $showSettings) { ServerSettingsView(server: server, isPresented: $showSettings) }
            .sheet(isPresented: $showEdit) { ChannelSettingsView(channel: channel, server: server, isPresented: $showEdit) }
            .sheet(isPresented: $showAddFriend) { NewDMSheet { _ in } }
        }
        .environment(store)
        .onAppear { search.prepareMobileUIPreview() }
        .dynamicTypeSize(screen == "first-run-large-text" ? .accessibility3 : .large)
    }

    @ViewBuilder private var content: some View {
        switch screen {
        case "first-run-server", "first-run-server-long", "first-run-large-text":
            FirstRunChannelBeginning(channel: channel, server: server, messages: [],
                onInvite: { showInvite = true }, onSettings: { showSettings = true },
                onEdit: { showEdit = true }, onCompose: { focusRequest = UUID() }, previewNewServer: true)
        case "first-run-channel":
            ChannelBeginningState(name: "général", onEdit: { showEdit = true }).padding(LayoutMetrics.mobile(16))
        case "first-run-dm", "first-run-dm-long":
            DirectMessageBeginningState(user: screen.hasSuffix("long") ? longUser : MockData.users[0], username: "camille")
        case "first-run-friends": FriendsFirstRunState { showAddFriend = true }
        case "first-run-notifications":
            MobileNotificationsView(servers: [], conversations: [], onOpenDM: { _ in }, store: store, onOpen: { _ in })
                .frame(minHeight: LayoutMetrics.mobile(400))
        case "first-run-search":
            SearchPanel(model: search, scope: .server(server), onClose: { dismiss() }, onOpen: { _ in })
                .frame(minHeight: LayoutMetrics.mobile(360))
        default: EmptyView()
        }
    }

    private var longUser: MoodUser {
        MoodUser(id: MockData.users[0].id, username: "camille", displayName: "Camille et un très long nom d'affichage qui reste lisible sur plusieurs lignes",
            avatarEmoji: "🌸", roleColor: MoodTheme.brandAccent, status: .offline, bio: "", joinedDate: Date(), badges: [], activity: nil)
    }
}

#Preview("First server") {
    FirstRunPreviewScreen(screen: "first-run-server")
        .environment(AccountStore()).environment(AuthState()).environment(\.layoutMode, .compact)
}

#Preview("First server desktop") {
    FirstRunPreviewScreen(screen: "first-run-server")
        .environment(AccountStore()).environment(AuthState()).environment(\.layoutMode, .regular)
}
