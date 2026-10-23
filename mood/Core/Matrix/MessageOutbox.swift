import Foundation
import Network
import Observation

// MARK: - Outgoing Message

nonisolated struct OutgoingMessage: Codable, Sendable, Equatable {
    let txnId: String
    let roomId: String
    let body: String
    let replyToEventId: String?
    let threadRootEventId: String?
    let createdAt: Date
    // Added with the file-based outbox; optional so the old UserDefaults payload still decodes.
    var formattedBody: String? = nil
    var mentionUserIds: [String]? = nil
    var mentionsRoom: Bool? = nil
    var attachment: OutgoingAttachment? = nil
}

/// A file waiting to be uploaded. The picked file is copied (and resized for images) into the
/// outbox folder at send time, so it survives the picker's security scope, a relaunch and offline time.
nonisolated struct OutgoingAttachment: Codable, Sendable, Equatable {
    enum Kind: String, Codable, Sendable {
        case image, video, audio, file

        var msgtype: String {
            switch self {
            case .image: "m.image"
            case .video: "m.video"
            case .audio: "m.audio"
            case .file: "m.file"
            }
        }
    }

    var kind: Kind
    /// Shown name and event `body`.
    var fileName: String
    /// File name inside the outbox folder.
    var localFile: String
    var mimeType: String
    var size: Int
    var duration: Int? = nil
    var voiceWaveform: [Int]? = nil
    var width: Int? = nil
    var height: Int? = nil
    var thumbnailFile: String? = nil
    var thumbnailMimeType: String? = nil
    var thumbnailSize: Int? = nil
    var thumbnailWidth: Int? = nil
    var thumbnailHeight: Int? = nil
    /// Set once uploaded, so a retry or a relaunch never uploads twice.
    var contentURI: String? = nil
    var thumbnailContentURI: String? = nil

    func eventContent() -> [String: Any] {
        var content = MatrixMessageContent.media(msgtype: kind.msgtype, body: fileName,
                                                 contentURI: contentURI ?? "", info: info())
        if let voiceWaveform {
            content["org.matrix.msc3245.voice"] = [String: String]()
            content["org.matrix.msc1767.audio"] = ["duration": duration ?? 0, "waveform": voiceWaveform] as [String: Any]
        }
        return content
    }

    var localFiles: [String] { [localFile] + [thumbnailFile].compactMap { $0 } }

    /// The event's `info`: w, h, size, mimetype and the thumbnail when there is one.
    func info() -> [String: Any] {
        var info: [String: Any] = ["mimetype": mimeType, "size": size]
        if let duration { info["duration"] = duration }
        if let width { info["w"] = width }
        if let height { info["h"] = height }
        if let thumbnailContentURI {
            info["thumbnail_url"] = thumbnailContentURI
            var thumbnailInfo: [String: Any] = [:]
            if let thumbnailMimeType { thumbnailInfo["mimetype"] = thumbnailMimeType }
            if let thumbnailSize { thumbnailInfo["size"] = thumbnailSize }
            if let thumbnailWidth { thumbnailInfo["w"] = thumbnailWidth }
            if let thumbnailHeight { thumbnailInfo["h"] = thumbnailHeight }
            info["thumbnail_info"] = thumbnailInfo
        }
        return info
    }
}

// MARK: - Queue (pure ordering)

/// FIFO per room: a room's next message waits for the previous one, rooms do not wait for each other
/// (a 25 Mo upload in one channel never holds a DM back).
nonisolated struct OutboxQueue: Codable, Equatable, Sendable {
    private(set) var messages: [OutgoingMessage] = []

    init(messages: [OutgoingMessage] = []) {
        self.messages = messages
    }

    var isEmpty: Bool { messages.isEmpty }

    /// Rooms with something to send, in the order their oldest message was queued.
    var roomIds: [String] {
        var seen = Set<String>()
        return messages.compactMap { seen.insert($0.roomId).inserted ? $0.roomId : nil }
    }

    func next(in roomId: String) -> OutgoingMessage? {
        messages.first { $0.roomId == roomId }
    }

    func message(txnId: String) -> OutgoingMessage? {
        messages.first { $0.txnId == txnId }
    }

    func pending(in roomId: String) -> [OutgoingMessage] {
        messages.filter { $0.roomId == roomId }
    }

    @discardableResult
    mutating func enqueue(_ message: OutgoingMessage) -> Bool {
        guard self.message(txnId: message.txnId) == nil else { return false }
        messages.append(message)
        return true
    }

    /// Replaces a message in place (upload progress saved), keeping its position.
    mutating func update(_ message: OutgoingMessage) {
        guard let index = messages.firstIndex(where: { $0.txnId == message.txnId }) else { return }
        messages[index] = message
    }

    @discardableResult
    mutating func remove(txnId: String) -> OutgoingMessage? {
        guard let index = messages.firstIndex(where: { $0.txnId == txnId }) else { return nil }
        return messages.remove(at: index)
    }

    mutating func removeAll() {
        messages = []
    }
}

// MARK: - Message Outbox (persisted queue)

/// `Application Support/Mood/outbox.json` (+ `outbox-files/` for attachments), written atomically
/// on every change. The previous UserDefaults storage is migrated once.
@MainActor
@Observable final class MessageOutbox {
    struct Snapshot: Codable {
        static let currentVersion = 1
        var version = Snapshot.currentVersion
        var queue: OutboxQueue
        var failed: [OutgoingMessage]? = nil
        var ownerID: String? = nil
    }

    static let legacyDefaultsKey = "mood.outbox"

    private(set) var queue = OutboxQueue()
    private(set) var failed: [OutgoingMessage] = []
    private(set) var ownerID: String?
    private let fileURL: URL?
    let filesDirectory: URL?

    var pending: [OutgoingMessage] { queue.messages }

    /// - Parameters:
    ///   - fileURL: where the queue lives; nil keeps it in memory only (no Application Support).
    ///   - defaults: holder of the pre-file outbox, migrated then cleared.
    init(fileURL: URL? = MessageOutbox.defaultFileURL(), defaults: UserDefaults = .standard) {
        self.fileURL = fileURL
        self.filesDirectory = fileURL.map {
            $0.deletingLastPathComponent().appendingPathComponent("\($0.deletingPathExtension().lastPathComponent)-files", isDirectory: true)
        }
        if let filesDirectory {
            try? FileManager.default.createDirectory(at: filesDirectory, withIntermediateDirectories: true)
        }

        if let fileURL, let data = try? Data(contentsOf: fileURL),
           let snapshot = try? JSONDecoder().decode(Snapshot.self, from: data),
           snapshot.version == Snapshot.currentVersion {
            queue = snapshot.queue
            failed = snapshot.failed ?? []
            ownerID = snapshot.ownerID
        }
        if let migrated = Self.migrateLegacy(from: defaults) {
            for message in migrated { queue.enqueue(message) }
            persist()
        }
        removeOrphanFiles()
    }

    nonisolated static func defaultFileURL() -> URL? {
        guard let support = try? FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true
        ) else { return nil }
        let folder = support.appendingPathComponent("Mood", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder.appendingPathComponent("outbox.json")
    }

    /// Messages left in UserDefaults by earlier versions, oldest first; the key is cleared.
    static func migrateLegacy(from defaults: UserDefaults) -> [OutgoingMessage]? {
        guard let data = defaults.data(forKey: legacyDefaultsKey) else { return nil }
        defaults.removeObject(forKey: legacyDefaultsKey)
        guard let decoded = try? JSONDecoder().decode([OutgoingMessage].self, from: data) else { return nil }
        return decoded.sorted { $0.createdAt < $1.createdAt }
    }

    // MARK: Queue

    /// A different account never inherits another person's pending messages or attachments.
    func adopt(ownerID: String) {
        if let previous = self.ownerID, previous != ownerID { removeAll() }
        self.ownerID = ownerID
        persist()
    }

    func next(in roomId: String) -> OutgoingMessage? { queue.next(in: roomId) }
    func message(txnId: String) -> OutgoingMessage? { queue.message(txnId: txnId) }
    var roomIds: [String] { queue.roomIds }

    func enqueue(_ message: OutgoingMessage) {
        guard queue.enqueue(message) else { return }
        persist()
    }

    func update(_ message: OutgoingMessage) {
        queue.update(message)
        persist()
    }

    /// - Parameter deleteFiles: false when the message moves to the failed list and may be retried.
    func remove(txnId: String, deleteFiles: Bool = true) {
        guard let removed = queue.remove(txnId: txnId) else { return }
        if deleteFiles { self.deleteFiles(of: removed) }
        persist()
    }

    func removeAll() {
        queue.removeAll()
        failed = []
        persist()
        if let filesDirectory {
            try? FileManager.default.removeItem(at: filesDirectory)
            try? FileManager.default.createDirectory(at: filesDirectory, withIntermediateDirectories: true)
        }
    }

    func retainFailed(_ message: OutgoingMessage) {
        queue.remove(txnId: message.txnId)
        failed.removeAll { $0.txnId == message.txnId }
        failed.append(message)
        persist()
    }

    func retryFailed(_ message: OutgoingMessage) {
        failed.removeAll { $0.txnId == message.txnId }
        queue.enqueue(message)
        persist()
    }

    func removeFailed(txnId: String, deleteFiles: Bool = false) {
        if deleteFiles, let item = failed.first(where: { $0.txnId == txnId }) { self.deleteFiles(of: item) }
        failed.removeAll { $0.txnId == txnId }
        persist()
    }

    // MARK: Attachment files

    func localURL(for fileName: String) -> URL? {
        filesDirectory?.appendingPathComponent(fileName, isDirectory: false)
    }

    func deleteFiles(of message: OutgoingMessage) {
        for name in message.attachment?.localFiles ?? [] {
            if let url = localURL(for: name) { try? FileManager.default.removeItem(at: url) }
        }
    }

    /// Files whose message is gone (sent, cancelled, or failed before a relaunch).
    private func removeOrphanFiles() {
        guard let filesDirectory,
              let names = try? FileManager.default.contentsOfDirectory(atPath: filesDirectory.path) else { return }
        let referenced = Set((queue.messages + failed).flatMap { $0.attachment?.localFiles ?? [] })
        for name in names where !referenced.contains(name) {
            try? FileManager.default.removeItem(at: filesDirectory.appendingPathComponent(name))
        }
    }

    // MARK: Persistence

    private func persist() {
        guard let fileURL, let data = try? JSONEncoder().encode(Snapshot(queue: queue, failed: failed, ownerID: ownerID)) else { return }
        // Synchronous and atomic: two quick sends must never be written out of order.
        // Readable before first unlock so a background flush can still use it.
        try? data.write(to: fileURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }
}

// MARK: - Network Reachability

@Observable @MainActor
final class NetworkReachability {
    private let monitor = NWPathMonitor()
    private(set) var isConnected = true
    var onReconnect: (() -> Void)?
    var onChange: ((Bool) -> Void)?

    init(monitoring: Bool = true, initiallyConnected: Bool = true) {
        isConnected = initiallyConnected
        guard monitoring else { return }
        monitor.pathUpdateHandler = { [weak self] path in
            let connected = path.status == .satisfied
            Task { @MainActor in
                self?.update(isConnected: connected)
            }
        }
        monitor.start(queue: DispatchQueue(label: "mood.reachability"))
    }

    /// Shared by NWPathMonitor and deterministic reachability tests.
    func update(isConnected connected: Bool) {
        let wasConnected = isConnected
        isConnected = connected
        onChange?(connected)
        if connected && !wasConnected { onReconnect?() }
    }

    deinit {
        monitor.cancel()
    }
}
