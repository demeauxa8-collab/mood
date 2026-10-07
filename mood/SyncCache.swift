import Foundation
import CryptoKit

/// On-disk snapshot of the last sync, so the app opens on its rooms and recent
/// messages instantly instead of an empty screen while the first sync runs.
/// The server stays the source of truth: a full sync always follows a restore.
struct SyncSnapshot: Codable {
    static let currentVersion = 1

    var version = SyncSnapshot.currentVersion
    var savedAt = Date()
    var rooms: [MatrixStore.MatrixRoom]
    /// Most recent raw timeline events per room, replayed through the normal pipeline.
    var timelines: [String: [MatrixEvent]]
    var directRoomIds: [String]
    var ignoredUserIds: [String]
}

/// One file per account in Application Support, protected while the device is locked.
struct SyncCache {
    static let eventsPerRoom = 150

    private let fileURL: URL

    init?(userId: String) {
        guard let support = try? FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true
        ) else { return nil }
        let folder = support.appendingPathComponent("Mood", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        // Hash the Matrix id so the file name does not reveal the account.
        let digest = SHA256.hash(data: Data(userId.utf8)).prefix(8).map { String(format: "%02x", $0) }.joined()
        fileURL = folder.appendingPathComponent("sync-\(digest).json")
    }

    func load() -> SyncSnapshot? {
        guard let data = try? Data(contentsOf: fileURL),
              let snapshot = try? JSONDecoder().decode(SyncSnapshot.self, from: data),
              snapshot.version == SyncSnapshot.currentVersion
        else { return nil }
        return snapshot
    }

    /// Encodes on the caller, writes off the main thread.
    func save(_ snapshot: SyncSnapshot) {
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        let url = fileURL
        Task.detached(priority: .utility) {
            try? data.write(to: url, options: [.atomic, .completeFileProtection])
        }
    }

    func delete() {
        try? FileManager.default.removeItem(at: fileURL)
    }
}
