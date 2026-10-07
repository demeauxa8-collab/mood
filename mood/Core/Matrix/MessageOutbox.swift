import Foundation
import Network

// MARK: - Outgoing Message

struct OutgoingMessage: Codable {
    let txnId: String
    let roomId: String
    let body: String
    let replyToEventId: String?
    let threadRootEventId: String?
    let createdAt: Date
}

// MARK: - Message Outbox (file d'attente persistée, FIFO)

@MainActor
final class MessageOutbox {
    private(set) var pending: [OutgoingMessage] = []
    private static let storageKey = "mood.outbox"

    init() {
        if let data = UserDefaults.standard.data(forKey: Self.storageKey),
           let decoded = try? JSONDecoder().decode([OutgoingMessage].self, from: data) {
            pending = decoded.sorted { $0.createdAt < $1.createdAt }
        }
    }

    func enqueue(_ message: OutgoingMessage) {
        guard !pending.contains(where: { $0.txnId == message.txnId }) else { return }
        pending.append(message)
        persist()
    }

    func remove(txnId: String) {
        pending.removeAll { $0.txnId == txnId }
        persist()
    }

    func removeAll() {
        pending = []
        persist()
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(pending) else { return }
        UserDefaults.standard.set(data, forKey: Self.storageKey)
    }
}

// MARK: - Network Reachability

@MainActor
final class NetworkReachability {
    private let monitor = NWPathMonitor()
    private(set) var isConnected = true
    var onReconnect: (() -> Void)?

    init() {
        monitor.pathUpdateHandler = { [weak self] path in
            let connected = path.status == .satisfied
            Task { @MainActor in
                guard let self else { return }
                let wasConnected = self.isConnected
                self.isConnected = connected
                if connected && !wasConnected {
                    self.onReconnect?()
                }
            }
        }
        monitor.start(queue: DispatchQueue(label: "mood.reachability"))
    }

    deinit {
        monitor.cancel()
    }
}
