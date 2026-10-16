import SwiftUI

/// Explicitly disconnected visual fixtures, reachable only with -uiPreview -conversationPreview <screen>.
@MainActor
enum ConversationPreview {
    static var screen: String? {
        let args = ProcessInfo.processInfo.arguments
        guard args.contains("-uiPreview"), let index = args.firstIndex(of: "-conversationPreview"), args.indices.contains(index + 1) else { return nil }
        return args[index + 1]
    }
    static let room = "!n1-preview:mood.local"
    static let root = ChatMessage(id: UUID(uuidString: "00000000-0000-0000-0000-000000000101")!, sender: MockData.users[0],
        content: "On organise la soirée de vendredi ici ?", timestamp: Date(timeIntervalSince1970: 1792062000), isGrouped: false, eventId: "$n1-root")
    static let replies = [
        ChatMessage(id: UUID(uuidString: "00000000-0000-0000-0000-000000000102")!, sender: MockData.users[1], content: "Oui, rendez-vous à 20 h !", timestamp: Date(timeIntervalSince1970: 1792062060), isGrouped: false, eventId: "$n1-reply-1"),
        ChatMessage(id: UUID(uuidString: "00000000-0000-0000-0000-000000000103")!, sender: MockData.currentUser, content: "Parfait, je serai là.", timestamp: Date(timeIntervalSince1970: 1792062120), isGrouped: false, isEdited: true, eventId: "$n1-reply-2")
    ]
}

struct ConversationPreviewScreen: View {
    let screen: String
    @State private var store = MatrixStore()
    @State private var panel = true
    @State private var selectedRoot: ChatMessage?

    var body: some View {
        NavigationStack {
            Group {
                switch screen {
                case "thread": ThreadPanel(message: ConversationPreview.root, roomId: ConversationPreview.room, server: MockData.servers[0], showPanel: $panel)
                case "forward": ConversationForwardPicker(message: ConversationPreview.root, onClose: {})
                case "directory": ConversationThreadDirectory(roomId: ConversationPreview.room, onOpen: { selectedRoot = $0 }, onClose: {})
                case "search":
                    ConversationSearchScreen(roomId: ConversationPreview.room, server: MockData.servers[0], onClose: {})
                default:
                    ScrollView {
                        VStack(spacing: 8 * LayoutMetrics.scale) {
                            ForEach(store.conversationThreads(roomId: ConversationPreview.room)) { message in
                                MessageRow(message: message, server: MockData.servers[0], roomId: ConversationPreview.room, onReply: nil, onThread: { selectedRoot = message }, onAvatarTap: {})
                            }
                            SystemMessageRow(message: ChatMessage(id: UUID(), sender: MockData.users[1], content: "Léa a rejoint la conversation.", timestamp: ConversationPreview.root.timestamp.addingTimeInterval(30), isGrouped: false, isSystemMessage: true))
                            MessageRow(message: ChatMessage(id: UUID(), sender: MockData.currentUser,
                                content: "Je prépare aussi la liste des jeux.", timestamp: ConversationPreview.root.timestamp.addingTimeInterval(180),
                                isGrouped: false, isEdited: true), server: MockData.servers[0], onReply: nil, onThread: nil, onAvatarTap: {})
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(MoodTheme.chatBackground).foregroundStyle(MoodTheme.textPrimary)
            .navigationTitle("Démo · \(screen)").navigationBarTitleDisplayMode(.inline)
            .navigationDestination(isPresented: Binding(get: { selectedRoot != nil }, set: { if !$0 { selectedRoot = nil } })) {
                ThreadPanel(message: selectedRoot ?? ConversationPreview.root, roomId: ConversationPreview.room, server: MockData.servers[0], showPanel: $panel)
            }
        }
        .environment(store).environment(AuthState()).environment(\.layoutMode, .compact)
        .task { store.prepareConversationPreview() }
    }
}
