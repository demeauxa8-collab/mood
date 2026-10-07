import SwiftUI

// MARK: - Search model

/// State of one header search: the typed query, the current results, paging.
/// One instance per chat view; it forgets everything when the scope (server or DM) changes.
@Observable
@MainActor
final class MessageSearchModel {
    enum Phase: Equatable {
        case idle
        case loading
        case loaded
        /// Enter pressed with nothing to look for (empty field, or filters only).
        case needsTerm
        /// Every room in scope is encrypted: the homeserver cannot search them.
        case unavailable
        case failed(String)
    }

    var query = ""
    private(set) var phase: Phase = .idle
    private(set) var hits: [SearchHit] = []
    private(set) var nextBatch: String?
    private(set) var isLoadingMore = false
    private(set) var loadMoreError: String?
    private(set) var skippedEncryptedRooms = 0
    private(set) var highlightWords: [String] = []

    @ObservationIgnored private var total: Int?
    @ObservationIgnored private var request: Request?
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var generation = 0

    private struct Request {
        var term: String
        var channels: [Channel]
        var senders: [MoodUser]
    }

    /// Exact once every page is loaded, the homeserver's estimate before that.
    var resultCount: Int {
        nextBatch == nil ? hits.count : max(total ?? hits.count, hits.count)
    }

    /// Runs the typed query (Enter). "de:" and "dans:" words become real filters.
    func submit(store: MatrixStore, scope: SearchScope) {
        let parsed = SearchQueryParser.parse(
            query,
            members: scope.members(me: store.currentUser),
            channels: scope.channels
        )
        cancel()
        hits = []
        nextBatch = nil
        total = nil
        skippedEncryptedRooms = 0
        loadMoreError = nil

        guard !parsed.term.isEmpty else {
            phase = .needsTerm
            return
        }
        request = Request(term: parsed.term, channels: parsed.channels, senders: parsed.senders)
        highlightWords = Self.words(in: parsed.term)
        phase = .loading
        fetch(store: store, scope: scope, replacing: true)
    }

    func loadMore(store: MatrixStore, scope: SearchScope) {
        guard phase == .loaded, nextBatch != nil, !isLoadingMore else { return }
        isLoadingMore = true
        loadMoreError = nil
        fetch(store: store, scope: scope, replacing: false)
    }

    /// Forgets the query and its results (Esc, the clear button, a change of server or DM).
    func reset() {
        cancel()
        query = ""
        hits = []
        nextBatch = nil
        total = nil
        skippedEncryptedRooms = 0
        loadMoreError = nil
        highlightWords = []
        request = nil
        phase = .idle
    }

    private func cancel() {
        task?.cancel()
        task = nil
        generation += 1
        isLoadingMore = false
    }

    private func fetch(store: MatrixStore, scope: SearchScope, replacing: Bool) {
        guard let request else { return }
        let current = generation
        let token = replacing ? nil : nextBatch
        task = Task {
            do {
                let page = try await store.searchMessages(
                    term: request.term,
                    scope: scope,
                    channels: request.channels,
                    senders: request.senders,
                    nextBatch: token
                )
                guard current == generation else { return }
                apply(page, replacing: replacing)
            } catch {
                guard current == generation else { return }
                isLoadingMore = false
                if replacing {
                    phase = .failed(error.localizedDescription)
                } else {
                    loadMoreError = error.localizedDescription
                }
            }
        }
    }

    private func apply(_ page: SearchPage, replacing: Bool) {
        isLoadingMore = false
        if page.isUnavailable {
            hits = []
            phase = .unavailable
            return
        }
        if replacing {
            hits = page.hits
        } else {
            let known = Set(hits.map(\.id))
            hits += page.hits.filter { !known.contains($0.id) }
        }
        nextBatch = page.nextBatch
        total = page.total
        skippedEncryptedRooms = page.skippedEncryptedRooms
        for word in page.highlights.map({ $0.lowercased() }) where !highlightWords.contains(word) {
            highlightWords.append(word)
        }
        phase = .loaded
    }

    private static func words(in term: String) -> [String] {
        term.split(whereSeparator: { $0.isWhitespace || $0 == "\"" }).map { String($0).lowercased() }
    }
}

// MARK: - Results panel

/// Discord's right-hand search results: "N résultats", newest first, one card per message.
struct SearchPanel: View {
    @Environment(MatrixStore.self) private var matrixStore
    let model: MessageSearchModel
    let scope: SearchScope
    let onClose: () -> Void
    let onOpen: (SearchHit) -> Void

    static let width: CGFloat = 400 * LayoutMetrics.scale

    private var showsChannelNames: Bool {
        if case .server = scope { return true }
        return false
    }

    private var title: String {
        switch model.phase {
        case .loaded:
            let count = model.resultCount
            return count == 1 ? "1 résultat" : "\(count) résultats"
        case .loading: return "Recherche…"
        case .idle, .needsTerm, .unavailable, .failed: return "Recherche"
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8 * LayoutMetrics.scale) {
                Text(title)
                    .font(.mood(14, weight: .semibold))
                    .foregroundStyle(MoodTheme.textPrimary)
                    .lineLimit(1)

                Spacer(minLength: 0)

                HeaderButton(icon: "xmark", action: onClose)
                    .help("Fermer la recherche (Échap)")
            }
            .padding(.leading, 16 * LayoutMetrics.scale)
            .padding(.trailing, 8 * LayoutMetrics.scale)
            .frame(height: 44 * LayoutMetrics.scale)

            Rectangle().fill(MoodTheme.divider).frame(height: 1)

            content
        }
        .frame(width: Self.width)
        .frame(maxHeight: .infinity)
        .background(MoodTheme.memberList)
    }

    @ViewBuilder
    private var content: some View {
        switch model.phase {
        case .idle:
            SearchStateMessage(icon: "magnifyingglass", title: "Rechercher dans \(scope.placeholderName)", subtitle: "Écris un mot puis appuie sur Entrée.")
        case .loading:
            ProgressView()
                .controlSize(.regular)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .needsTerm:
            SearchStateMessage(
                icon: "text.magnifyingglass",
                title: "Que cherches-tu ?",
                subtitle: "Ajoute un mot à ta recherche. Tu peux le combiner avec de:nom ou dans:salon."
            )
        case .unavailable:
            SearchStateMessage(
                icon: "magnifyingglass",
                title: "La recherche n'est pas disponible dans les salons chiffrés",
                subtitle: "Le serveur ne peut pas lire leurs messages."
            )
        case .failed(let message):
            SearchStateMessage(icon: "exclamationmark.triangle", title: "La recherche a échoué", subtitle: message) {
                Button("Réessayer") { model.submit(store: matrixStore, scope: scope) }
                    .buttonStyle(SearchActionButtonStyle())
            }
        case .loaded:
            if model.hits.isEmpty && model.nextBatch == nil {
                SearchStateMessage(
                    icon: "magnifyingglass",
                    title: "Aucun résultat",
                    subtitle: "Essaie avec d'autres mots-clés."
                )
            } else {
                results
            }
        }
    }

    private var results: some View {
        ScrollView(showsIndicators: false) {
            LazyVStack(alignment: .leading, spacing: 12 * LayoutMetrics.scale) {
                ForEach(model.hits) { hit in
                    SearchResultCard(
                        hit: hit,
                        words: model.highlightWords,
                        showsChannelName: showsChannelNames,
                        onOpen: { onOpen(hit) }
                    )
                }

                if model.skippedEncryptedRooms > 0 {
                    Text(model.skippedEncryptedRooms == 1
                         ? "1 salon chiffré n'est pas inclus : la recherche n'y est pas disponible."
                         : "\(model.skippedEncryptedRooms) salons chiffrés ne sont pas inclus : la recherche n'y est pas disponible.")
                        .font(.mood(12))
                        .foregroundStyle(MoodTheme.textMuted)
                        .padding(.horizontal, 4 * LayoutMetrics.scale)
                }

                if model.nextBatch != nil {
                    loadMoreButton
                }
            }
            .padding(12 * LayoutMetrics.scale)
        }
    }

    private var loadMoreButton: some View {
        VStack(spacing: 6 * LayoutMetrics.scale) {
            Button {
                model.loadMore(store: matrixStore, scope: scope)
            } label: {
                HStack(spacing: 6 * LayoutMetrics.scale) {
                    if model.isLoadingMore { ProgressView().controlSize(.small) }
                    Text("Charger plus")
                }
            }
            .buttonStyle(SearchActionButtonStyle())
            .disabled(model.isLoadingMore)

            if let error = model.loadMoreError {
                Text(error)
                    .font(.mood(12))
                    .foregroundStyle(MoodTheme.mentionBadge)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 4 * LayoutMetrics.scale)
    }
}

// MARK: - Result card

private struct SearchResultCard: View {
    let hit: SearchHit
    let words: [String]
    let showsChannelName: Bool
    let onOpen: () -> Void
    @State private var isHovered = false

    private var message: ChatMessage { hit.message }

    private var channelLabel: String? {
        guard showsChannelName, case .channel(let channel, _) = hit.destination else { return nil }
        return channel.name
    }

    private var text: AttributedString {
        let body = message.content.isEmpty ? message.attachments.map(\.name).joined(separator: ", ") : message.content
        return Self.highlighted(body, words: words)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6 * LayoutMetrics.scale) {
            if let channelLabel {
                HStack(spacing: 4 * LayoutMetrics.scale) {
                    Image(systemName: "number")
                        .font(.mood(11, weight: .bold))
                    Text(channelLabel)
                        .font(.mood(12, weight: .semibold))
                        .lineLimit(1)
                }
                .foregroundStyle(MoodTheme.textSecondary)
                .padding(.horizontal, 4 * LayoutMetrics.scale)
            }

            Button(action: onOpen) {
                HStack(alignment: .top, spacing: 12 * LayoutMetrics.scale) {
                    AvatarGlyph(user: message.sender)
                        .font(.mood(18))
                        .frame(width: 40 * LayoutMetrics.scale, height: 40 * LayoutMetrics.scale)
                        .background(MoodTheme.glassBg)
                        .clipShape(Circle())

                    VStack(alignment: .leading, spacing: 3 * LayoutMetrics.scale) {
                        HStack(alignment: .firstTextBaseline, spacing: 8 * LayoutMetrics.scale) {
                            Text(message.sender.displayName)
                                .font(.mood(15, weight: .semibold))
                                .foregroundStyle(message.sender.roleColor)
                                .lineLimit(1)
                            Text(message.timestamp.messageTimestamp)
                                .font(.mood(12))
                                .foregroundStyle(MoodTheme.textMuted)
                                .lineLimit(1)
                        }

                        Text(text)
                            .font(.mood(14))
                            .foregroundStyle(MoodTheme.textPrimary)
                            .lineLimit(8)
                            .multilineTextAlignment(.leading)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(12 * LayoutMetrics.scale)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(isHovered ? MoodTheme.hoverBg : MoodTheme.chatBackground)
                .overlay(alignment: .topTrailing) {
                    if isHovered {
                        Text("Aller")
                            .font(.mood(12, weight: .semibold))
                            .foregroundStyle(MoodTheme.textPrimary)
                            .padding(.horizontal, 8 * LayoutMetrics.scale)
                            .padding(.vertical, 3 * LayoutMetrics.scale)
                            .background(MoodTheme.serverMenuHover)
                            .clipShape(RoundedRectangle(cornerRadius: 4 * LayoutMetrics.scale, style: .continuous))
                            .padding(8 * LayoutMetrics.scale)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 8 * LayoutMetrics.scale, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 8 * LayoutMetrics.scale, style: .continuous)
                        .strokeBorder(MoodTheme.divider, lineWidth: 1 * LayoutMetrics.scale)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .onHover { hovering in
                withAnimation(MoodMotion.hover) { isHovered = hovering }
            }
        }
    }

    /// Bold + tinted background on every occurrence of a searched word.
    static func highlighted(_ text: String, words: [String]) -> AttributedString {
        var result = AttributedString(text)
        for word in words where !word.isEmpty {
            var cursor = result.startIndex
            while cursor < result.endIndex,
                  let range = result[cursor...].range(of: word, options: [.caseInsensitive, .diacriticInsensitive]) {
                result[range].font = .mood(14, weight: .bold)
                result[range].backgroundColor = MoodTheme.brandAccent.opacity(0.28)
                cursor = range.upperBound
            }
        }
        return result
    }
}

// MARK: - Shared bits

private struct SearchStateMessage<Action: View>: View {
    let icon: String
    let title: String
    let subtitle: String
    @ViewBuilder var action: Action

    var body: some View {
        VStack(spacing: 10 * LayoutMetrics.scale) {
            Image(systemName: icon)
                .font(.mood(32))
                .foregroundStyle(MoodTheme.textMuted)

            Text(title)
                .font(.mood(15, weight: .semibold))
                .foregroundStyle(MoodTheme.textPrimary)
                .multilineTextAlignment(.center)

            Text(subtitle)
                .font(.mood(13))
                .foregroundStyle(MoodTheme.textSecondary)
                .multilineTextAlignment(.center)

            action
        }
        .padding(.horizontal, 28 * LayoutMetrics.scale)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

extension SearchStateMessage where Action == EmptyView {
    init(icon: String, title: String, subtitle: String) {
        self.init(icon: icon, title: title, subtitle: subtitle) { EmptyView() }
    }
}

private struct SearchActionButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.mood(13, weight: .semibold))
            .foregroundStyle(MoodTheme.textPrimary)
            .padding(.horizontal, 14 * LayoutMetrics.scale)
            .padding(.vertical, 7 * LayoutMetrics.scale)
            .background(configuration.isPressed ? MoodTheme.serverMenuHover : MoodTheme.serverMenuBackground)
            .clipShape(RoundedRectangle(cornerRadius: 6 * LayoutMetrics.scale, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 6 * LayoutMetrics.scale, style: .continuous)
                    .strokeBorder(MoodTheme.serverMenuBorder, lineWidth: 1 * LayoutMetrics.scale)
            }
    }
}
