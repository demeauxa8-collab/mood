import SwiftUI

// MARK: - Destination

/// Where a quick-switcher row leads. ContentView owns navigation and resolves it.
enum QuickSwitcherDestination: Hashable {
    case channel(serverID: UUID, channelID: UUID)
    case conversation(UUID)
    case server(UUID)

    /// Stable key shared by result rows and the persisted recents.
    var key: String {
        switch self {
        case .channel(_, let channelID): Self.key(channel: channelID)
        case .conversation(let id): Self.key(conversation: id)
        case .server(let id): "server:\(id.uuidString)"
        }
    }

    static func key(channel id: UUID) -> String { "channel:\(id.uuidString)" }
    static func key(conversation id: UUID) -> String { "dm:\(id.uuidString)" }
}

// MARK: - Recents

/// Last destinations the user actually visited, newest first (ids are stable Matrix-derived UUIDs).
enum QuickSwitcherRecents {
    private static let storageKey = "quick_switcher_recents"
    private static let limit = 12

    static func load() -> [String] {
        UserDefaults.standard.stringArray(forKey: storageKey) ?? []
    }

    static func record(key: String) {
        var list = load()
        list.removeAll { $0 == key }
        list.insert(key, at: 0)
        UserDefaults.standard.set(Array(list.prefix(limit)), forKey: storageKey)
    }
}

// MARK: - Items

struct QuickSwitcherItem: Identifiable {
    enum Kind { case textChannel, voiceChannel, conversation, server }

    let destination: QuickSwitcherDestination
    let kind: Kind
    let title: String
    /// Right-aligned context: the server for a channel, "@username" for a DM, "Serveur" for a server.
    let detail: String
    var channelIcon: String = "number"
    var user: MoodUser?
    var server: MoodServer?
    var unreadCount = 0
    var mentionCount = 0
    var lastActivity: Date?

    var id: String { destination.key }
    var hasUnread: Bool { unreadCount > 0 || mentionCount > 0 }
}

/// One visible row; `header` is set on the first row of each section of the empty-query list.
struct QuickSwitcherRow: Identifiable {
    let item: QuickSwitcherItem
    var header: String?
    var id: String { item.id }
}

// MARK: - Search (pure logic)

enum QuickSwitcherSearch {
    /// Discord's narrowing prefixes: `#` text channels, `!` voice channels, `@` people, `*` servers.
    enum Scope {
        case all, textChannels, voiceChannels, conversations, servers

        func includes(_ kind: QuickSwitcherItem.Kind) -> Bool {
            switch self {
            case .all: true
            case .textChannels: kind == .textChannel
            case .voiceChannels: kind == .voiceChannel
            case .conversations: kind == .conversation
            case .servers: kind == .server
            }
        }
    }

    static let maxResults = 50

    // MARK: Building the index

    static func items(servers: [MoodServer], conversations: [DMConversation]) -> [QuickSwitcherItem] {
        var items: [QuickSwitcherItem] = []
        for server in servers {
            for channel in server.categories.flatMap(\.channels) {
                items.append(QuickSwitcherItem(
                    destination: .channel(serverID: server.id, channelID: channel.id),
                    kind: channel.type == .voice ? .voiceChannel : .textChannel,
                    title: channel.name,
                    detail: server.name,
                    channelIcon: channel.icon,
                    unreadCount: channel.unreadCount,
                    mentionCount: channel.mentionCount
                ))
            }
            items.append(QuickSwitcherItem(
                destination: .server(server.id),
                kind: .server,
                title: server.name,
                detail: "Serveur",
                server: server,
                mentionCount: server.mentionCount
            ))
        }
        for conversation in conversations {
            items.append(QuickSwitcherItem(
                destination: .conversation(conversation.id),
                kind: .conversation,
                title: conversation.participant.displayName,
                detail: "@\(conversation.participant.username)",
                user: conversation.participant,
                unreadCount: conversation.unreadCount,
                lastActivity: conversation.lastMessageDate
            ))
        }
        return items
    }

    // MARK: Querying

    static func rows(for query: String, items: [QuickSwitcherItem], recents: [String]) -> [QuickSwitcherRow] {
        let (scope, text) = parse(query)
        let scoped = items.filter { scope.includes($0.kind) }
        let tokens = normalized(text).split(whereSeparator: \.isWhitespace).map(String.init)

        if tokens.isEmpty {
            // Nothing typed: where the user probably wants to go, unread and recent first.
            return scope == .all
                ? sectionedDefaults(scoped, recents: recents)
                : defaultOrder(scoped, recents: recents).map { QuickSwitcherRow(item: $0) }
        }

        let ranked: [(item: QuickSwitcherItem, score: Int)] = scoped.compactMap { item in
            guard let base = matchScore(tokens: tokens, item: item) else { return nil }
            return (item, base + bonus(for: item, recents: recents))
        }
        let sorted = ranked.sorted { lhs, rhs in
            if lhs.score != rhs.score { return lhs.score > rhs.score }
            if lhs.item.title.count != rhs.item.title.count { return lhs.item.title.count < rhs.item.title.count }
            return lhs.item.title.localizedStandardCompare(rhs.item.title) == .orderedAscending
        }
        return sorted.prefix(maxResults).map { QuickSwitcherRow(item: $0.item) }
    }

    static func parse(_ query: String) -> (scope: Scope, text: String) {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard let first = trimmed.first else { return (.all, "") }
        let rest = String(trimmed.dropFirst())
        switch first {
        case "#": return (.textChannels, rest)
        case "!": return (.voiceChannels, rest)
        case "@": return (.conversations, rest)
        case "*": return (.servers, rest)
        default: return (.all, trimmed)
        }
    }

    // MARK: Scoring

    /// Case- and accent-insensitive form used for every comparison.
    static func normalized(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
    }

    /// Every token must hit the title, or (at half weight) the detail; nil when one misses.
    static func matchScore(tokens: [String], item: QuickSwitcherItem) -> Int? {
        let title = normalized(item.title)
        let detail = normalized(item.detail)
        var total = 0
        for token in tokens {
            let best = max(score(token, in: title), score(token, in: detail) / 2)
            if best == 0 { return nil }
            total += best
        }
        return total
    }

    /// 100 exact, 80 prefix, 60 word prefix, 40 substring, 15 loose subsequence ("gnrl" finds "general").
    static func score(_ token: String, in text: String) -> Int {
        guard !token.isEmpty, !text.isEmpty else { return 0 }
        if text == token { return 100 }
        if text.hasPrefix(token) { return 80 }
        let words = text.split(whereSeparator: { !$0.isLetter && !$0.isNumber })
        if words.contains(where: { $0.hasPrefix(token) }) { return 60 }
        if text.contains(token) { return 40 }
        if token.count >= 3, isSubsequence(token, of: text) { return 15 }
        return 0
    }

    private static func isSubsequence(_ token: String, of text: String) -> Bool {
        var remaining = text.makeIterator()
        return token.allSatisfy { character in
            while let next = remaining.next() {
                if next == character { return true }
            }
            return false
        }
    }

    /// Small tie-breaker, kept below the gap between two match tiers (20) so it never beats a better match.
    private static func bonus(for item: QuickSwitcherItem, recents: [String]) -> Int {
        var bonus = 0
        if let rank = recents.firstIndex(of: item.id) { bonus += max(0, 6 - rank) }
        if item.mentionCount > 0 { bonus += 4 } else if item.unreadCount > 0 { bonus += 2 }
        return bonus
    }

    // MARK: Empty query

    private static func defaultOrder(_ items: [QuickSwitcherItem], recents: [String]) -> [QuickSwitcherItem] {
        func rank(_ item: QuickSwitcherItem) -> Int { recents.firstIndex(of: item.id) ?? Int.max }
        return items.sorted { lhs, rhs in
            if (lhs.mentionCount > 0) != (rhs.mentionCount > 0) { return lhs.mentionCount > 0 }
            if lhs.hasUnread != rhs.hasUnread { return lhs.hasUnread }
            if rank(lhs) != rank(rhs) { return rank(lhs) < rank(rhs) }
            if let l = lhs.lastActivity, let r = rhs.lastActivity, l != r { return l > r }
            return false
        }
    }

    private static func sectionedDefaults(_ items: [QuickSwitcherItem], recents: [String]) -> [QuickSwitcherRow] {
        var used = Set<String>()
        var rows: [QuickSwitcherRow] = []

        func add(_ title: String, _ candidates: [QuickSwitcherItem], limit: Int) {
            let fresh = candidates.filter { !used.contains($0.id) }.prefix(limit)
            for (index, item) in fresh.enumerated() {
                used.insert(item.id)
                rows.append(QuickSwitcherRow(item: item, header: index == 0 ? title : nil))
            }
        }

        let byKey = Dictionary(items.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        add("Récents", recents.compactMap { byKey[$0] }, limit: 5)

        let unread = items
            .filter { $0.kind != .server && $0.hasUnread }
            .sorted { ($0.mentionCount, $0.unreadCount) > ($1.mentionCount, $1.unreadCount) }
        add("Non lus", unread, limit: 6)

        let conversations = items
            .filter { $0.kind == .conversation }
            .sorted { ($0.lastActivity ?? .distantPast) > ($1.lastActivity ?? .distantPast) }
        add("Messages privés", conversations, limit: 5)

        add("Salons", items.filter { $0.kind == .textChannel || $0.kind == .voiceChannel }, limit: 12)
        add("Serveurs", items.filter { $0.kind == .server }, limit: 8)
        return rows
    }
}

// MARK: - View

struct QuickSwitcher: View {
    @Environment(\.layoutMode) private var layoutMode
    @Binding var isPresented: Bool
    /// Real servers and DMs from the Matrix store, or the demo lists when there is no session.
    let servers: [MoodServer]
    let conversations: [DMConversation]
    /// Called with the chosen destination; the switcher closes itself right after.
    var onSelect: (QuickSwitcherDestination) -> Void

    @State private var query = ""
    @State private var selection = 0
    @State private var recents = QuickSwitcherRecents.load()
    @State private var lastKeyboardMove = Date.distantPast
    @FocusState private var fieldFocused: Bool

    private var rows: [QuickSwitcherRow] {
        QuickSwitcherSearch.rows(
            for: query,
            items: QuickSwitcherSearch.items(servers: servers, conversations: conversations),
            recents: recents
        )
    }

    var body: some View {
        let rows = rows
        let selected = min(selection, max(rows.count - 1, 0))

        VStack(spacing: 0) {
            searchField
                .padding(.horizontal, 16 * LayoutMetrics.scale)
                .padding(.top, 16 * LayoutMetrics.scale)
                .padding(.bottom, 12 * LayoutMetrics.scale)

            Rectangle().fill(MoodTheme.serverMenuSeparator).frame(height: 1 * LayoutMetrics.scale)

            if rows.isEmpty {
                emptyState
            } else {
                resultsList(rows, selected: selected)
            }

            Rectangle().fill(MoodTheme.serverMenuSeparator).frame(height: 1 * LayoutMetrics.scale)

            footer
        }
        .adaptiveFrame(width: 540 * LayoutMetrics.scale, mode: layoutMode)
        .background(MoodTheme.serverMenuBackground)
        .clipShape(RoundedRectangle(cornerRadius: 12 * LayoutMetrics.scale, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12 * LayoutMetrics.scale, style: .continuous)
                .stroke(MoodTheme.serverMenuBorder, lineWidth: 1)
        )
        .popoverElevation()
        .onKeyPress(.upArrow) { moveSelection(by: -1, count: rows.count); return .handled }
        .onKeyPress(.downArrow) { moveSelection(by: 1, count: rows.count); return .handled }
        .onKeyPress(.escape) { close(); return .handled }
        .background {
            // Esc also works when focus has left the field (clicked on the dim area, etc.).
            Button { close() } label: { EmptyView() }
                .keyboardShortcut(.cancelAction)
                .accessibilityHidden(true)
        }
        .onChange(of: query) { _, _ in selection = 0 }
        .task { fieldFocused = true }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Sélecteur rapide")
    }

    // MARK: Pieces

    private var searchField: some View {
        HStack(spacing: 10 * LayoutMetrics.scale) {
            TextField("Où veux-tu aller ?", text: $query)
                .textFieldStyle(.plain)
                .font(.mood(16))
                .foregroundStyle(MoodTheme.textPrimary)
                .focused($fieldFocused)
                .submitLabel(.go)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .onSubmit { openSelected() }
                .accessibilityLabel("Rechercher un salon, un message privé ou un serveur")

            if !query.isEmpty {
                Button { query = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.mood(14))
                        .foregroundStyle(MoodTheme.textMuted)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Effacer la recherche")
            } else {
                Image(systemName: "magnifyingglass")
                    .font(.mood(14))
                    .foregroundStyle(MoodTheme.textMuted)
                    .accessibilityHidden(true)
            }
        }
        .padding(.horizontal, 12 * LayoutMetrics.scale)
        .frame(height: 44 * LayoutMetrics.scale)
        .background(MoodTheme.dmSearchBackground)
        .clipShape(RoundedRectangle(cornerRadius: 8 * LayoutMetrics.scale, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8 * LayoutMetrics.scale, style: .continuous)
                .strokeBorder(MoodTheme.dmSearchBorder, lineWidth: 1)
        )
    }

    private func resultsList(_ rows: [QuickSwitcherRow], selected: Int) -> some View {
        ScrollViewReader { proxy in
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 2 * LayoutMetrics.scale) {
                    ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                        VStack(alignment: .leading, spacing: 0) {
                            if let header = row.header {
                                Text(header.uppercased())
                                    .font(.mood(11, weight: .bold))
                                    .foregroundStyle(MoodTheme.textSubtle)
                                    .padding(.horizontal, 10 * LayoutMetrics.scale)
                                    .padding(.top, index == 0 ? 2 * LayoutMetrics.scale : 10 * LayoutMetrics.scale)
                                    .padding(.bottom, 4 * LayoutMetrics.scale)
                                    .accessibilityAddTraits(.isHeader)
                            }
                            QuickSwitcherRowView(item: row.item, isSelected: index == selected) {
                                open(row.item)
                            } onHover: {
                                // Ignore the pointer while keys scroll content under it, or selection fights the arrows.
                                guard Date().timeIntervalSince(lastKeyboardMove) > 0.4 else { return }
                                selection = index
                            }
                        }
                        .id(row.id)
                    }
                }
                .padding(8 * LayoutMetrics.scale)
            }
            .frame(maxHeight: 360 * LayoutMetrics.scale)
            .onChange(of: selection) { _, newValue in
                guard rows.indices.contains(newValue) else { return }
                proxy.scrollTo(rows[newValue].id)
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 6 * LayoutMetrics.scale) {
            Text("Aucun résultat")
                .font(.mood(15, weight: .semibold))
                .foregroundStyle(MoodTheme.textPrimary)
            Text("Rien ne correspond à « \(query.trimmingCharacters(in: .whitespaces)) ».")
                .font(.mood(13))
                .foregroundStyle(MoodTheme.textSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 32 * LayoutMetrics.scale)
        .padding(.horizontal, 16 * LayoutMetrics.scale)
    }

    private var footer: some View {
        HStack(spacing: 14 * LayoutMetrics.scale) {
            hint("↑↓", "naviguer")
            hint("↵", "ouvrir")
            hint("esc", "fermer")
            Spacer(minLength: 8)
            Text("# salons  @ messages  * serveurs")
                .font(.mood(11))
                .foregroundStyle(MoodTheme.textMuted)
                .lineLimit(1)
        }
        .padding(.horizontal, 16 * LayoutMetrics.scale)
        .padding(.vertical, 9 * LayoutMetrics.scale)
        .accessibilityHidden(true)
    }

    private func hint(_ keys: String, _ label: String) -> some View {
        HStack(spacing: 5 * LayoutMetrics.scale) {
            Text(keys)
                .font(.mood(10, weight: .semibold, design: .monospaced))
                .foregroundStyle(MoodTheme.textSecondary)
                .padding(.horizontal, 5 * LayoutMetrics.scale)
                .padding(.vertical, 2 * LayoutMetrics.scale)
                .background(MoodTheme.serverMenuTagBackground)
                .clipShape(RoundedRectangle(cornerRadius: 4 * LayoutMetrics.scale, style: .continuous))
            Text(label)
                .font(.mood(11))
                .foregroundStyle(MoodTheme.textMuted)
        }
    }

    // MARK: Actions

    private func moveSelection(by delta: Int, count: Int) {
        guard count > 0 else { return }
        lastKeyboardMove = Date()
        let current = min(selection, count - 1)
        selection = (current + delta + count) % count
    }

    private func openSelected() {
        let rows = rows
        guard !rows.isEmpty else { return }
        open(rows[min(selection, rows.count - 1)].item)
    }

    private func open(_ item: QuickSwitcherItem) {
        QuickSwitcherRecents.record(key: item.id)
        isPresented = false
        onSelect(item.destination)
    }

    private func close() {
        isPresented = false
    }
}

// MARK: - Row

private struct QuickSwitcherRowView: View {
    let item: QuickSwitcherItem
    let isSelected: Bool
    let action: () -> Void
    let onHover: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10 * LayoutMetrics.scale) {
                glyph
                    .frame(width: 24 * LayoutMetrics.scale, height: 24 * LayoutMetrics.scale)

                Text(item.title)
                    .font(.mood(15, weight: item.hasUnread ? .bold : .semibold))
                    .foregroundStyle(MoodTheme.textPrimary)
                    .lineLimit(1)

                Spacer(minLength: 12 * LayoutMetrics.scale)

                if item.mentionCount > 0 {
                    Text("\(item.mentionCount)")
                        .font(.mood(11, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 5 * LayoutMetrics.scale)
                        .padding(.vertical, 1 * LayoutMetrics.scale)
                        .background(MoodTheme.mentionBadge)
                        .clipShape(Capsule())
                } else if item.unreadCount > 0 {
                    Circle()
                        .fill(MoodTheme.textPrimary)
                        .frame(width: 7 * LayoutMetrics.scale, height: 7 * LayoutMetrics.scale)
                }

                Text(item.detail)
                    .font(.mood(13))
                    .foregroundStyle(isSelected ? MoodTheme.textSupporting : MoodTheme.textMuted)
                    .lineLimit(1)
            }
            .padding(.horizontal, 10 * LayoutMetrics.scale)
            .frame(height: 40 * LayoutMetrics.scale)
            .background(isSelected ? MoodTheme.serverMenuHover : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 6 * LayoutMetrics.scale, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            if hovering { onHover() }
        }
        .accessibilityLabel(accessibilityLabel)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    @ViewBuilder
    private var glyph: some View {
        switch item.kind {
        case .textChannel, .voiceChannel:
            Image(systemName: item.channelIcon)
                .font(.mood(15, weight: .medium))
                .foregroundStyle(MoodTheme.textSecondary)
        case .conversation:
            if let user = item.user {
                AvatarGlyph(user: user)
                    .font(.mood(14))
                    .frame(width: 24 * LayoutMetrics.scale, height: 24 * LayoutMetrics.scale)
                    .background(MoodTheme.glassBg)
                    .clipShape(Circle())
            }
        case .server:
            Group {
                if let url = item.server?.iconURL {
                    AsyncImage(url: url) { phase in
                        if case .success(let image) = phase {
                            image.resizable().scaledToFill()
                        } else {
                            Text(item.server?.iconEmoji ?? "").font(.mood(13))
                        }
                    }
                } else {
                    Text(item.server?.iconEmoji ?? "").font(.mood(13))
                }
            }
            .frame(width: 24 * LayoutMetrics.scale, height: 24 * LayoutMetrics.scale)
            .background(MoodTheme.serverIconBg)
            .clipShape(RoundedRectangle(cornerRadius: 7 * LayoutMetrics.scale, style: .continuous))
        }
    }

    private var accessibilityLabel: String {
        switch item.kind {
        case .textChannel, .voiceChannel: "#\(item.title), \(item.detail)"
        case .conversation: "Message privé avec \(item.title)"
        case .server: "Serveur \(item.title)"
        }
    }
}
