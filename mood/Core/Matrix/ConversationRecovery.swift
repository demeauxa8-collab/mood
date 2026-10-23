import Foundation

/// A reachable network is not proof that the conversation service is reachable.
nonisolated enum ConversationConnection: Equatable, Sendable {
    case connected, connecting, offline, serverUnavailable, sessionExpired

    static func resolve(networkAvailable: Bool, service: Self) -> Self {
        if service == .sessionExpired { return .sessionExpired }
        return networkAvailable ? service : .offline
    }

    var title: String {
        switch self {
        case .connected: "Connexion rétablie"
        case .connecting: "Connexion en cours…"
        case .offline: "Hors ligne"
        case .serverUnavailable: "Mood est injoignable"
        case .sessionExpired: "Ta session a expiré"
        }
    }

    func capsuleLabel(waiting count: Int) -> String {
        switch self {
        case .offline, .serverUnavailable:
            let prefix = self == .offline ? "Hors ligne" : "Mood injoignable"
            if count == 0 { return "\(prefix) · tu peux continuer à écrire" }
            let messages = count == 1 ? "1 message partira" : "\(count) messages partiront"
            return "\(prefix) · \(messages) au retour du \(self == .offline ? "réseau" : "service")"
        default: return title
        }
    }

    var detail: String {
        switch self {
        case .connected: "Tes messages ont été envoyés."
        case .connecting: "Tes conversations restent disponibles pendant la connexion."
        case .offline: "Tes messages partent dès que le réseau revient."
        case .serverUnavailable: "Tu peux lire les conversations déjà chargées et écrire. Tes messages attendent ici ; les nouveaux arriveront au retour de Mood."
        case .sessionExpired: "Tes conversations et tes messages en attente restent ici. Reconnecte-toi pour reprendre les envois et recevoir la suite."
        }
    }
}

enum ConversationRecovery {
    static func waitingLabel(_ count: Int) -> String {
        count == 1 ? "1 message en attente" : "\(count) messages en attente"
    }

    static func sentLabel(_ count: Int) -> String {
        count == 1 ? "Ton message a été envoyé." : "Tes \(count) messages ont été envoyés."
    }
}

/// One cancellable deadline per message. Tokens prevent an old timer from committing a newer action.
nonisolated struct DeferredMessageDeletion: Identifiable, Equatable, Sendable {
    static let gracePeriod: TimeInterval = 5
    let id: UUID
    let roomID: String
    let eventID: String
    let deadline: Date

    init(roomID: String, eventID: String, now: Date = Date()) {
        id = UUID()
        self.roomID = roomID
        self.eventID = eventID
        deadline = now.addingTimeInterval(Self.gracePeriod)
    }

    func isDue(at date: Date) -> Bool { date >= deadline }

    func remainingFraction(at date: Date) -> Double {
        min(1, max(0, deadline.timeIntervalSince(date) / Self.gracePeriod))
    }
}

nonisolated struct CreationIdentity: Codable, Hashable {
    enum Kind: String, Codable { case server, channel }
    let kind: Kind
    let arguments: [String]
}

/// Remember only the remote resources already created, so later setup failures can be resumed.
/// No credentials, passwords or message content are stored here.
@MainActor final class CreationRecovery {
    private struct Checkpoint: Codable {
        let identity: CreationIdentity
        let remoteID: String
    }
    private let defaults: UserDefaults
    init(defaults: UserDefaults = .standard) { self.defaults = defaults }
    private func key(_ owner: String) -> String { "mood.creationRecovery.\(owner)" }
    private func checkpoints(owner: String) -> [Checkpoint] {
        guard let data = defaults.data(forKey: key(owner)) else { return [] }
        return (try? JSONDecoder().decode([Checkpoint].self, from: data)) ?? []
    }
    func remoteID(for identity: CreationIdentity, owner: String) -> String? {
        checkpoints(owner: owner).first { $0.identity == identity }?.remoteID
    }
    func record(_ remoteID: String, for identity: CreationIdentity, owner: String) {
        var entries = checkpoints(owner: owner).filter { $0.identity != identity }
        entries.append(Checkpoint(identity: identity, remoteID: remoteID))
        if let data = try? JSONEncoder().encode(entries) { defaults.set(data, forKey: key(owner)) }
    }
    func finish(_ identity: CreationIdentity, owner: String) {
        let entries = checkpoints(owner: owner).filter { $0.identity != identity }
        if entries.isEmpty { clear(owner: owner) }
        else if let data = try? JSONEncoder().encode(entries) { defaults.set(data, forKey: key(owner)) }
    }
    func clear(owner: String) { defaults.removeObject(forKey: key(owner)) }
}
