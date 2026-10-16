import Foundation

nonisolated enum AttachmentSelectionPolicy {
    static let limit = 10
    static func appending(_ incoming: [URL], to current: [URL]) -> [URL] {
        var result = current
        for url in incoming where !result.contains(url) && result.count < limit { result.append(url) }
        return result
    }
}

nonisolated struct ComposerDraft: Codable, Equatable {
    var text: String
    var replyEventID: String?
}

/// Keys include the account and stable room id, never the room's display name.
@MainActor
final class ComposerDrafts {
    static let shared = ComposerDrafts()
    private let defaults: UserDefaults
    init(defaults: UserDefaults = .standard) { self.defaults = defaults }
    private func key(account: String, room: String) -> String {
        "mood.composer.n2." + Data((account + "\u{0}" + room).utf8).base64EncodedString()
    }
    func load(account: String, room: String) -> ComposerDraft? {
        guard let data = defaults.data(forKey: key(account: account, room: room)) else { return nil }
        return try? JSONDecoder().decode(ComposerDraft.self, from: data)
    }
    func save(_ draft: ComposerDraft, account: String, room: String) {
        let name = key(account: account, room: room)
        if draft.text.isEmpty && draft.replyEventID == nil { defaults.removeObject(forKey: name) }
        else if let data = try? JSONEncoder().encode(draft) { defaults.set(data, forKey: name) }
    }
}

nonisolated enum VoiceWaveform {
    static func normalized(_ powers: [Float], bins: Int = 64) -> [Int] {
        guard bins > 0, !powers.isEmpty else { return [] }
        let count = min(bins, powers.count)
        return (0..<count).map { index in
            let start = index * powers.count / count
            let end = max(start + 1, (index + 1) * powers.count / count)
            let peak = powers[start..<end].filter(\.isFinite).max() ?? -160
            return min(1024, max(0, Int(pow(10, Double(peak) / 20) * 1024)))
        }
    }
}

nonisolated struct MediaLinkPreview: Decodable, Equatable, Sendable {
    var title: String?
    var description: String?
    var image: String?
    enum CodingKeys: String, CodingKey {
        case title = "og:title", description = "og:description", image = "og:image"
    }
    static func firstURL(in text: String) -> URL? {
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue),
              let match = detector.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let url = match.url, ["https", "http"].contains(url.scheme?.lowercased() ?? "") else { return nil }
        return url
    }
}
