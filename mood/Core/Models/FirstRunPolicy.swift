import Foundation
import Observation

/// Presentation decisions only. Unknown or incomplete history must never claim to be its beginning.
enum FirstRunPolicy {
    static func showsBeginning(knownStart: Bool, loading: Bool) -> Bool {
        knownStart && !loading
    }

    static func hasReachedBeginning(hasMoreHistory: Bool?, hasPaginationCursor: Bool,
                                    conversationComplete: Bool, loading: Bool) -> Bool {
        showsBeginning(knownStart: (hasMoreHistory == false && hasPaginationCursor) || conversationComplete,
                       loading: loading)
    }

    static func canEditChannel(userLevel: Int, stateDefault: Int?, nameLevel: Int?, topicLevel: Int?) -> Bool {
        let required = stateDefault ?? 50
        return userLevel >= max(nameLevel ?? required, topicLevel ?? required)
    }

    static func showsChecklist(isFirstTextChannel: Bool, canManage: Bool, knownStart: Bool,
                               hasMessages: Bool, started: Bool, finished: Bool) -> Bool {
        isFirstTextChannel && canManage && knownStart && !finished && (!hasMessages || started)
    }

    enum FriendsState: Equatable { case empty, noResults, offline, populated }
    static func confirmedFirstMessage(isOwn: Bool, isSystem: Bool, accepted: Bool) -> Bool {
        isOwn && !isSystem && accepted
    }
    static func friendsState(total: Int, visible: Int, query: String) -> FriendsState {
        if !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && visible == 0 { return .noResults }
        if total == 0 { return .empty }
        return visible == 0 ? .offline : .populated
    }

    /// A public Mood handle is optional; never expose an internal Matrix identifier as a fallback.
    static func publicUsername(_ value: String?) -> String? {
        guard let value, !value.contains(":"),
              !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return value
    }
}

enum ServerWelcomeStep: String, Codable, CaseIterable {
    case invite, icon, message, otherDevice
}

/// Account + canonical server ID, rather than transient UI UUIDs or editable names.
struct ServerWelcomeScope: Codable, Hashable {
    let account: String
    let server: String
}

@Observable @MainActor
final class ServerWelcomeProgress {
    static let shared = ServerWelcomeProgress(defaults: .standard)
    private struct Entry: Codable {
        let scope: ServerWelcomeScope
        var steps: Set<ServerWelcomeStep> = []
    }
    private var entries: [Entry]
    private let defaults: UserDefaults?
    private static let key = "Mood.serverWelcome.v1"

    /// nil is deliberately memory-only, including visual previews and logic tests.
    init(defaults: UserDefaults? = nil) {
        self.defaults = defaults
        entries = defaults?.data(forKey: Self.key).flatMap { try? JSONDecoder().decode([Entry].self, from: $0) } ?? []
    }

    func started(_ scope: ServerWelcomeScope) -> Bool { entries.contains { $0.scope == scope } }
    func completed(_ step: ServerWelcomeStep, in scope: ServerWelcomeScope) -> Bool {
        entries.first { $0.scope == scope }?.steps.contains(step) == true
    }
    func finished(_ scope: ServerWelcomeScope) -> Bool {
        ServerWelcomeStep.allCases.allSatisfy { completed($0, in: scope) }
    }
    func begin(_ scope: ServerWelcomeScope) {
        guard !started(scope) else { return }
        entries.append(Entry(scope: scope))
        persist()
    }
    func complete(_ step: ServerWelcomeStep, in scope: ServerWelcomeScope) {
        begin(scope)
        guard let index = entries.firstIndex(where: { $0.scope == scope }), !entries[index].steps.contains(step) else { return }
        entries[index].steps.insert(step)
        persist()
    }
    private func persist() {
        guard let data = try? JSONEncoder().encode(entries) else { return }
        defaults?.set(data, forKey: Self.key)
    }
}
