import Foundation

/// Visual fixtures are reachable only through the account-free developer preview.
enum MessagingPreview {
    static var kind: String? {
        let args = ProcessInfo.processInfo.arguments
        guard args.contains("-uiPreview"), let index = args.firstIndex(of: "-messagingPreview"), args.indices.contains(index + 1) else { return nil }
        return args[index + 1]
    }
    static let members = [
        MentionCandidate(userId: "@alice:mood.local", displayName: "Alice"),
        MentionCandidate(userId: "@alix:mood.local", displayName: "Alix")
    ]
}
