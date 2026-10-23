import SwiftUI

// MARK: - Chat view glue

extension View {
    /// What a chat view needs around its header search: Cmd+F focuses the field, Esc closes the results,
    /// Discord's filter suggestions drop down under the field, and the search is forgotten when `resetKey` changes
    /// (another server or DM).
    func messageSearchSupport(
        model: MessageSearchModel,
        scope: SearchScope,
        isOpen: Bool,
        focus: FocusState<Bool>.Binding,
        resetKey: UUID,
        onClose: @escaping () -> Void
    ) -> some View {
        modifier(MessageSearchSupport(
            model: model,
            scope: scope,
            isOpen: isOpen,
            focus: focus,
            resetKey: resetKey,
            onClose: onClose
        ))
    }
}

private struct MessageSearchSupport: ViewModifier {
    @Environment(\.layoutMode) private var layoutMode
    let model: MessageSearchModel
    let scope: SearchScope
    let isOpen: Bool
    var focus: FocusState<Bool>.Binding
    let resetKey: UUID
    let onClose: () -> Void
    @State private var isHoveringSuggestions = false

    func body(content: Content) -> some View {
        content
            .background {
                if layoutMode == .regular {
                    Button { focus.wrappedValue = true } label: { EmptyView() }
                        .keyboardShortcut("f", modifiers: .command)
                    if isOpen {
                        Button(action: onClose) { EmptyView() }
                            .keyboardShortcut(.cancelAction)
                    }
                }
            }
            .overlay(alignment: .topTrailing) {
                if layoutMode == .regular, focus.wrappedValue || isHoveringSuggestions {
                    SearchSuggestions(model: model, scope: scope, focus: focus)
                        .onHover { isHoveringSuggestions = $0 }
                        .padding(.top, LayoutMetrics.desktopHeaderHeight - 6 * LayoutMetrics.scale)
                        .padding(.trailing, 12 * LayoutMetrics.scale)
                }
            }
            .onChange(of: model.query) { _, _ in isHoveringSuggestions = false }
            .onChange(of: resetKey) { _, _ in
                focus.wrappedValue = false
                isHoveringSuggestions = false
                if isOpen || !model.query.isEmpty { onClose() }
            }
    }
}

// MARK: - Filter suggestions

/// The dropdown under Discord's search field: filters to start with ("De :", "Dans :"), then people or channels.
private struct SearchSuggestions: View {
    @Environment(MatrixStore.self) private var matrixStore
    let model: MessageSearchModel
    let scope: SearchScope
    var focus: FocusState<Bool>.Binding

    private enum Mode {
        case filters
        case people(String)
        case channels(String)
    }

    private var token: String {
        model.query.split(separator: " ", omittingEmptySubsequences: false).last.map(String.init) ?? ""
    }

    private var hasChannelFilter: Bool { !scope.channels.isEmpty }

    private var mode: Mode? {
        if let value = remainder(of: token, prefixes: SearchQueryParser.senderPrefixes) { return .people(value) }
        if hasChannelFilter, let value = remainder(of: token, prefixes: SearchQueryParser.channelPrefixes) { return .channels(value) }
        let lowered = token.lowercased()
        if lowered.isEmpty || "de:".hasPrefix(lowered) || (hasChannelFilter && "dans:".hasPrefix(lowered)) { return .filters }
        return nil
    }

    private var people: [MoodUser] {
        guard case .people(let value) = mode else { return [] }
        let wanted = value.lowercased()
        let all = scope.members(me: matrixStore.currentUser)
        let matches = wanted.isEmpty ? all : all.filter {
            $0.username.lowercased().contains(wanted) || $0.displayName.lowercased().contains(wanted)
        }
        return Array(matches.prefix(6))
    }

    private var channels: [Channel] {
        guard case .channels(let value) = mode else { return [] }
        let wanted = SearchQueryParser.squashed(value)
        let all = scope.channels
        let matches = wanted.isEmpty ? all : all.filter { SearchQueryParser.squashed($0.name).contains(wanted) }
        return Array(matches.prefix(6))
    }

    var body: some View {
        if let mode {
            VStack(alignment: .leading, spacing: 2 * LayoutMetrics.scale) {
                switch mode {
                case .filters:
                    sectionTitle("FILTRES DE RECHERCHE")
                    SuggestionRow(title: "De :", detail: "un utilisateur") { insert("de:") }
                    if hasChannelFilter {
                        SuggestionRow(title: "Dans :", detail: "un salon") { insert("dans:") }
                    }
                case .people:
                    sectionTitle("UTILISATEURS")
                    if people.isEmpty { emptyRow("Aucun utilisateur trouvé") }
                    ForEach(people) { user in
                        SuggestionRow(title: user.displayName, detail: "@\(user.username)", leading: {
                            AvatarGlyph(user: user)
                                .font(.mood(12))
                                .frame(width: 22 * LayoutMetrics.scale, height: 22 * LayoutMetrics.scale)
                                .background(MoodTheme.glassBg)
                                .clipShape(Circle())
                        }) { insert(SearchQueryParser.token(for: user) + " ") }
                    }
                case .channels:
                    sectionTitle("SALONS")
                    if channels.isEmpty { emptyRow("Aucun salon trouvé") }
                    ForEach(channels) { channel in
                        SuggestionRow(title: channel.name, detail: "", leading: {
                            Image(systemName: channel.icon)
                                .font(.mood(13, weight: .semibold))
                                .foregroundStyle(MoodTheme.textSecondary)
                                .frame(width: 22 * LayoutMetrics.scale)
                        }) { insert(SearchQueryParser.token(for: channel) + " ") }
                    }
                }
            }
            .padding(8 * LayoutMetrics.scale)
            .frame(width: 300 * LayoutMetrics.scale, alignment: .leading)
            .background(MoodTheme.serverMenuBackground)
            .clipShape(RoundedRectangle(cornerRadius: 8 * LayoutMetrics.scale, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 8 * LayoutMetrics.scale, style: .continuous)
                    .strokeBorder(MoodTheme.serverMenuBorder, lineWidth: 1 * LayoutMetrics.scale)
            }
            .popoverElevation()
        }
    }

    private func sectionTitle(_ text: String) -> some View {
        Text(text)
            .font(.mood(11, weight: .semibold))
            .tracking(0.4)
            .foregroundStyle(MoodTheme.textSecondary)
            .padding(.horizontal, 8 * LayoutMetrics.scale)
            .padding(.vertical, 4 * LayoutMetrics.scale)
    }

    private func emptyRow(_ text: String) -> some View {
        Text(text)
            .font(.mood(13))
            .foregroundStyle(MoodTheme.textMuted)
            .padding(.horizontal, 8 * LayoutMetrics.scale)
            .padding(.vertical, 6 * LayoutMetrics.scale)
    }

    private func remainder(of token: String, prefixes: [String]) -> String? {
        let lowered = token.lowercased()
        guard let prefix = prefixes.first(where: { lowered.hasPrefix($0) }) else { return nil }
        return String(token.dropFirst(prefix.count)).trimmingCharacters(in: CharacterSet(charactersIn: "@#"))
    }

    /// Replaces the word being typed, keeping the rest of the query.
    private func insert(_ text: String) {
        var words = model.query.split(separator: " ", omittingEmptySubsequences: false).map(String.init)
        if words.isEmpty { words = [""] }
        words[words.count - 1] = text
        model.query = words.joined(separator: " ")
        focus.wrappedValue = true
    }
}

private struct SuggestionRow<Leading: View>: View {
    let title: String
    let detail: String
    @ViewBuilder var leading: Leading
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8 * LayoutMetrics.scale) {
                leading
                Text(title)
                    .font(.mood(14, weight: .semibold))
                    .foregroundStyle(MoodTheme.textPrimary)
                    .lineLimit(1)
                if !detail.isEmpty {
                    Text(detail)
                        .font(.mood(13))
                        .foregroundStyle(MoodTheme.textMuted)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 8 * LayoutMetrics.scale)
            .padding(.vertical, 6 * LayoutMetrics.scale)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(isHovered ? MoodTheme.serverMenuHover : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 4 * LayoutMetrics.scale, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}

extension SuggestionRow where Leading == EmptyView {
    init(title: String, detail: String, action: @escaping () -> Void) {
        self.init(title: title, detail: detail, leading: { EmptyView() }, action: action)
    }
}

// MARK: - Jump to a message

extension View {
    /// Scrolls to the message a search result or mention asked for (`MatrixStore.jumpTarget`) as soon as it
    /// is in `messages`; if it never loads, the channel is simply left where it is.
    func jumpToRequestedMessage(roomId: String?, messages: [ChatMessage], proxy: ScrollViewProxy) -> some View {
        modifier(JumpToMessage(roomId: roomId, messages: messages, proxy: proxy))
    }
}

private struct JumpToMessage: ViewModifier {
    @Environment(MatrixStore.self) private var matrixStore
    let roomId: String?
    let messages: [ChatMessage]
    let proxy: ScrollViewProxy

    private struct Key: Equatable {
        var nonce: UUID?
        var roomId: String?
        var count: Int
    }

    func body(content: Content) -> some View {
        content.task(id: Key(nonce: matrixStore.jumpTarget?.nonce, roomId: roomId, count: messages.count)) {
            guard let target = matrixStore.jumpTarget,
                  target.roomId == roomId,
                  let message = messages.first(where: { $0.eventId == target.eventId }) else { return }
            // After a channel switch the lazy stack needs a beat before it can scroll to a row.
            try? await Task.sleep(for: .milliseconds(80))
            guard !Task.isCancelled else { return }
            proxy.scrollTo(message.id, anchor: .center)
            matrixStore.jumpTarget = nil
        }
    }
}
