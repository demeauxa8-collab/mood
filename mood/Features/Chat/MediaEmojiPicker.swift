import SwiftUI

nonisolated struct CatalogEmoji: Codable, Equatable, Sendable {
    let emoji: String
    let category: String
    let keywords: String
}

nonisolated enum MediaEmojiCatalog {
    static let entries: [CatalogEmoji] = {
        guard let url = Bundle.main.url(forResource: "EmojiCatalog", withExtension: "json"),
              let data = try? Data(contentsOf: url), let entries = try? JSONDecoder().decode([CatalogEmoji].self, from: data) else { return [] }
        return entries
    }()
    static func matching(_ query: String, in entries: [CatalogEmoji] = entries) -> [CatalogEmoji] {
        let query = query.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "fr"))
        return entries.filter {
            $0.emoji.contains(query) || ($0.keywords + " " + $0.category).folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "fr")).contains(query)
        }
    }
    static func recording(_ emoji: String, in recent: [String]) -> [String] {
        [emoji] + recent.filter { $0 != emoji }.prefix(31)
    }
}

/// Shared by composer and reaction pickers. Skin tones are complete Unicode entries with French names.
struct MediaEmojiPicker: View {
    @Environment(\.layoutMode) private var layoutMode
    @Environment(\.dismiss) private var dismiss
    let onSelect: (String) -> Void
    @State private var query = ""
    @State private var category = "Récents"
    @AppStorage("mood.emoji.recents.n2") private var recentJSON = "[]"
    private var recent: [String] { (try? JSONDecoder().decode([String].self, from: Data(recentJSON.utf8))) ?? [] }
    private var categories: [String] {
        ["Récents"] + MediaEmojiCatalog.entries.reduce(into: [String]()) { if !$0.contains($1.category) { $0.append($1.category) } }
    }
    private var emojis: [String] {
        if !query.isEmpty { return MediaEmojiCatalog.matching(query).map(\.emoji) }
        if category == "Récents" { return recent.isEmpty ? ["😂", "❤️", "🔥", "👍", "🙏", "😊"] : recent }
        return MediaEmojiCatalog.entries.filter { $0.category == category }.map(\.emoji)
    }
    var body: some View {
        if layoutMode == .compact { mobileBody } else { desktopBody }
    }
    private var mobileBody: some View {
        MobileSheet(title: "Emoji", onClose: { dismiss() }) {
            VStack(alignment: .leading, spacing: LayoutMetrics.mobile(12)) {
                TextField("Rechercher un emoji", text: $query).font(.mood(16))
                    .padding(LayoutMetrics.mobile(12)).background(MoodTheme.inputBg, in: Capsule())
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: LayoutMetrics.mobile(8)) {
                        ForEach(categories, id: \.self) { name in
                            Button { category = name; query = "" } label: {
                                Text(name).font(.mood(14, weight: .semibold))
                                    .padding(.horizontal, LayoutMetrics.mobile(16)).frame(minHeight: LayoutMetrics.mobile(44))
                                    .background(category == name ? MoodTheme.brandAccent : MoodTheme.inputBg, in: Capsule())
                                    .foregroundStyle(category == name ? MoodTheme.mobileIndicator : MoodTheme.textPrimary)
                            }.buttonStyle(.plain)
                        }
                    }
                }
                Text((query.isEmpty ? category : "Résultats").uppercased()).font(.mood(12, weight: .semibold)).foregroundStyle(MoodTheme.textSecondary)
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: LayoutMetrics.mobile(44)))], spacing: LayoutMetrics.mobile(8)) {
                        ForEach(emojis, id: \.self) { emoji in
                            Button {
                                let values = MediaEmojiCatalog.recording(emoji, in: recent)
                                if let data = try? JSONEncoder().encode(values), let value = String(data: data, encoding: .utf8) { recentJSON = value }
                                onSelect(emoji); dismiss()
                            } label: { Text(emoji).font(.mood(28)).frame(minWidth: LayoutMetrics.mobile(44), minHeight: LayoutMetrics.mobile(44)) }
                                .buttonStyle(.plain)
                        }
                    }
                    if emojis.isEmpty { ContentUnavailableView("Aucun emoji", systemImage: "face.smiling", description: Text("Essaie un autre mot.")) }
                }
            }.padding(LayoutMetrics.mobile(16)).background(MoodTheme.mobileSurface)
        }
    }
    private var desktopBody: some View {
        VStack(alignment: .leading, spacing: 10 * LayoutMetrics.scale) {
            TextField("", text: $query, prompt: Text("Rechercher un emoji").foregroundStyle(MoodTheme.textMuted))
                .textFieldStyle(.plain).font(.mood(14)).foregroundStyle(MoodTheme.textPrimary)
                .padding(10 * LayoutMetrics.scale)
                .background(MoodTheme.inputBg, in: RoundedRectangle(cornerRadius: 6 * LayoutMetrics.scale))
            ScrollView(.horizontal) {
                HStack {
                    ForEach(categories, id: \.self) { name in
                        Button(name) { category = name; query = "" }
                            .font(.mood(12)).foregroundStyle(category == name ? MoodTheme.brandAccent : MoodTheme.textSecondary)
                    }
                }
            }
            Text(query.isEmpty ? category : "Résultats").font(.mood(12, weight: .semibold)).foregroundStyle(MoodTheme.textMuted)
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 36 * LayoutMetrics.scale))], spacing: 4 * LayoutMetrics.scale) {
                    ForEach(emojis, id: \.self) { emoji in
                        Button {
                            let values = MediaEmojiCatalog.recording(emoji, in: recent)
                            if let data = try? JSONEncoder().encode(values), let string = String(data: data, encoding: .utf8) { recentJSON = string }
                            onSelect(emoji)
                        } label: { Text(emoji).font(.mood(26)).frame(minWidth: 36 * LayoutMetrics.scale, minHeight: 38 * LayoutMetrics.scale) }
                        .buttonStyle(.plain)
                    }
                }
                if emojis.isEmpty { Text("Aucun emoji trouvé").font(.mood(13)).foregroundStyle(MoodTheme.textMuted) }
            }
        }.padding(12 * LayoutMetrics.scale).frame(minWidth: 280 * LayoutMetrics.scale, maxWidth: 420 * LayoutMetrics.scale)
            .frame(height: 340 * LayoutMetrics.scale).background(MoodTheme.popupBg)
    }
}
