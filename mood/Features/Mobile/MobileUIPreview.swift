import SwiftUI

/// Deterministic, account-free entry points for the iPhone visual audit.
/// Only enabled by the explicit -uiPreview launch argument.
@Observable @MainActor
final class MobileUIPreviewRoute {
    static let shared = MobileUIPreviewRoute()
    var screen: String?
}

enum MobileUIPreview {
    static var screen: String? {
        let args = ProcessInfo.processInfo.arguments
        guard args.contains("-uiPreview") else { return nil }
        if let screen = MobileUIPreviewRoute.shared.screen { return screen }
        guard let index = args.firstIndex(of: "-uiPreviewScreen"),
              args.indices.contains(index + 1) else { return nil }
        return args[index + 1]
    }
    static let sheets: Set<String> = FirstRunPreview.screens.union(["server-settings", "create-channel", "edit-channel", "invite", "members", "pins", "pins-empty", "thread", "search", "emoji", "attachments", "username", "group-dm", "create-server-form", "server-overview", "server-roles", "server-members", "server-invites", "server-bans", "account-credentials", "discord-import", "profile-long", "members-empty", "attachment-draft", "video", "audio", "create-channel-error", "create-channel-loading", "search-error", "search-loading", "search-results", "new-dm-results"])
}

struct MobileUIPreviewSheet: View {
    let screen: String
    @Binding var presented: Bool
    @Environment(AccountStore.self) private var accountStore
    @Environment(MatrixStore.self) private var store
    @State private var search = MessageSearchModel()
    private var server: MoodServer { MockData.servers[0] }
    private var channel: Channel { server.categories.flatMap(\.channels).first { $0.type == .text }! }
    private var message: ChatMessage { MockData.messages(for: channel)[0] }

    var body: some View {
        Group {
            switch screen {
            case let route where FirstRunPreview.screens.contains(route): FirstRunPreviewScreen(screen: route)
            case "server-settings", "server-overview", "server-roles", "server-members", "server-invites", "server-bans": ServerSettingsView(server: server, isPresented: $presented)
            case "create-channel", "create-channel-error", "create-channel-loading": CreateChannelModal(server: server, isPresented: $presented)
            case "edit-channel": ChannelSettingsView(channel: channel, server: server, isPresented: $presented)
            case "invite": ServerInviteModal(server: server, isPresented: $presented)
            case "members", "members-empty":
                NavigationStack {
                    MemberListPanel(members: screen == "members-empty" ? [] : server.members, server: server, showProfilePopup: .constant(false), profileUser: .constant(nil))
                        .navigationTitle("Membres").navigationBarTitleDisplayMode(.inline)
                }
            case "pins", "pins-empty": PinnedMessagesPanel(messages: screen == "pins" ? [message] : [], server: server, showPanel: $presented)
            case "thread":
                NavigationStack {
                    ThreadPanel(message: message, server: server, showPanel: $presented)
                        .navigationTitle("Fil de discussion").navigationBarTitleDisplayMode(.inline)
                }
            case "search", "search-error", "search-loading", "search-results": SearchPanel(model: search, scope: .server(server), onClose: { presented = false }, onOpen: { _ in })
            case "emoji": MobileEmojiPicker { _ in }
            case "attachments": MediaAttachmentPicker { _ in }
            case "username": UsernameEditor()
            case "group-dm", "new-dm-results": NewDMSheet { _ in }
            case "create-server-form": CreateServerModal(isPresented: $presented)
            case "account-credentials":
                NavigationStack { AccountCredentialsView().disabled(true).navigationTitle("Identifiants").navigationBarTitleDisplayMode(.inline) }
            case "discord-import": DiscordGuildImporter(accountStore: accountStore, matrixStore: store)
            case "profile-long":
                MobileUserProfileSheet(user: MoodUser(id: MockData.users[1].id, username: "camille", displayName: "Camille et un nom de profil très long sur plusieurs lignes", avatarEmoji: "🌸", roleColor: MoodTheme.brandAccent, status: .online, bio: "Une description de profil longue pour vérifier que le contenu reste lisible sur un écran de téléphone, sans être coupé.", joinedDate: Date(), badges: [], activity: nil), server: server)
            case "video", "audio":
                if let url = Bundle.main.url(forResource: screen == "video" ? "n2-clip" : "n2-tone", withExtension: screen == "video" ? "mp4" : "m4a") {
                    NavigationStack { PlayableMedia(url: url, name: screen == "video" ? "Un souvenir.mp4" : "Message vocal.m4a", autoplay: true).navigationTitle(screen == "video" ? "Vidéo" : "Message vocal").navigationBarTitleDisplayMode(.inline) }
                }
            case "attachment-draft":
                NavigationStack {
                    AttachmentDraftPreview(url: URL(fileURLWithPath: "/tmp/Une pièce jointe avec un nom très long et lisible sur plusieurs lignes.txt"), onCancel: { presented = false }, onSend: { presented = false })
                        .padding(LayoutMetrics.mobile(16))
                        .frame(maxHeight: .infinity, alignment: .top)
                        .background(MoodTheme.mobileSurface)
                        .navigationTitle("Pièce jointe").navigationBarTitleDisplayMode(.inline)
                }
            default: EmptyView()
            }
        }
        .environment(\.layoutMode, .compact)
        .onAppear { search.prepareMobileUIPreview() }
    }
}
