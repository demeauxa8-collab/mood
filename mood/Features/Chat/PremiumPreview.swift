import SwiftUI
import Foundation

/// Account-free fault injection. No credential restoration, live token or server modification.
enum PremiumPreview {
    static var screen: String? {
        guard let screen = MobileUIPreview.screen, screen.hasPrefix("premium-") else { return nil }
        return String(screen.dropFirst("premium-".count))
    }
    static var showsNotice: Bool {
        ["permission", "microphone", "photos", "notifications", "large-photo"].contains(screen ?? "")
    }
    static let roomID = "!premium-preview:example.invalid"
}

struct PremiumPreviewScreen: View {
    let screen: String
    @State private var store: MatrixStore
    @State private var account: AccountStore
    @State private var auth = AuthState()
    @State private var members = false

    init(screen: String) {
        self.screen = screen
        let defaults = UserDefaults(suiteName: "Mood.PremiumPreview")!
        let store = MatrixStore(outbox: MessageOutbox(fileURL: nil, defaults: defaults),
                                reachability: NetworkReachability(monitoring: false))
        store.preparePremiumPreview(screen: screen)
        _store = State(initialValue: store)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [PremiumPreviewTransport.self]
        let client = SupabaseAuthClient(info: ["MoodSupabaseURL": "https://premium-preview.invalid",
            "MoodSupabaseAnonKey": "preview-placeholder"], urlSession: URLSession(configuration: configuration), persistsSession: false)!
        _account = State(initialValue: AccountStore(client: client))
    }

    private var server: MoodServer { MockData.servers[0] }
    private var channel: Channel { server.categories.flatMap(\.channels).first { $0.type == .text }! }

    var body: some View {
        MobileChatScreen(destination: .channel(channel, server), store: store, authState: auth,
            showMembers: $members, onBack: { MobileUIPreviewRoute.shared.screen = "chat" })
            .environment(store).environment(account).environment(auth).environment(\.layoutMode, .compact)
            .preferredColorScheme(.dark)
            .task {
                guard screen == "recovered" else { return }
                try? await Task.sleep(for: .seconds(2))
                guard !Task.isCancelled else { return }
                store.resumePremiumPreview()
            }
    }
}

/// Fault fixtures use the same permission/media recovery controls as the shipping composer.
struct PremiumPreviewNotices: View {
    @State private var picking = false
    private var screen: String? { PremiumPreview.screen }
    var body: some View {
        Group {
            if screen == "permission" || screen == "microphone" { MoodPermissionNotice(permission: .microphone) }
            if screen == "photos" { MoodPermissionNotice(permission: .photos, alternative: { picking = true }) }
            if screen == "notifications" { MoodPermissionNotice(permission: .notifications) }
            if screen == "large-photo" {
                MoodNotice(title: "Cette photo est trop lourde", detail: "Elle dépasse la limite de 25 Mo. Choisis une photo plus petite ; ton texte est conservé.", actionTitle: "Choisir un fichier", action: { picking = true })
            }
        }
        .sheet(isPresented: $picking) { MediaAttachmentPicker { _ in picking = false }.environment(\.layoutMode, .compact) }
    }
}

/// The account-free login sheet shows the Mood form, while every request stays local.
private final class PremiumPreviewTransport: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() { client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet)) }
    override func stopLoading() {}
}
