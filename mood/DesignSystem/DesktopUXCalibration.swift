import SwiftUI
import UIKit
import CoreText

/// Native desktop reference tokens. Only the isolated Catalyst UI uses them.
enum DesktopUXPalette {
    static var popup: Color { MoodTheme.shared.theme == .dark ? Color(hex: "252529") : MoodTheme.popupBg }
    static var input: Color { MoodTheme.shared.theme == .dark ? Color(hex: "202024") : MoodTheme.glassBg }
    static var highlighted: Color { MoodTheme.shared.theme == .dark ? Color(hex: "3e3e44") : MoodTheme.hoverBg }
    static var settingsSidebar: Color { MoodTheme.shared.theme == .dark ? Color(hex: "1a1a1e") : MoodTheme.channelList }
    static var settingsContent: Color { MoodTheme.shared.theme == .dark ? Color(hex: "202024") : MoodTheme.chatBackground }
    static var settingsSelected: Color { MoodTheme.shared.theme == .dark ? Color(hex: "323236") : MoodTheme.selectedBg }
    static var addInput: Color { MoodTheme.shared.theme == .dark ? Color(hex: "16161a") : MoodTheme.glassBg }
}

enum DesktopNavigationTarget: Hashable {
    case friends
    case server(UUID)
    case channel(server: UUID, channel: UUID)
    case directMessage(UUID)
}

struct DesktopNavigationEntry: Identifiable, Equatable {
    let id: DesktopNavigationTarget
    let name: String
    let detail: String
    let icon: String
    let kind: Character
}

enum DesktopNavigationIndex {
    static func friendsTabs(hasOnlineFriends: Bool) -> [FriendsPlaceholderView.FriendsTab] {
        hasOnlineFriends ? [.online, .all, .pending] : [.all, .pending]
    }

    static func entries(servers: [MoodServer], conversations: [DMConversation]) -> [DesktopNavigationEntry] {
        var entries = [DesktopNavigationEntry(id: .friends, name: "Amis", detail: "Messages privés", icon: "figure.wave", kind: "@")]
        for server in servers {
            entries.append(DesktopNavigationEntry(id: .server(server.id), name: server.name,
                detail: "Serveur", icon: "bubble.left.and.bubble.right.fill", kind: "*"))
            for channel in server.categories.flatMap(\.channels) {
                // Selecting a voice result navigates to its UI; it never joins a call.
                entries.append(DesktopNavigationEntry(id: .channel(server: server.id, channel: channel.id),
                    name: channel.name, detail: server.name, icon: channel.icon, kind: channel.type == .voice ? "!" : "#"))
            }
        }
        entries += conversations.map {
            DesktopNavigationEntry(id: .directMessage($0.id), name: $0.participant.displayName,
                detail: "Message privé", icon: "person.fill", kind: "@")
        }
        return entries
    }

    static func filter(_ entries: [DesktopNavigationEntry], query: String) -> [DesktopNavigationEntry] {
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let prefix = text.first.flatMap { "@#!*".contains($0) ? $0 : nil }
        let needle = prefix == nil ? text : String(text.dropFirst()).trimmingCharacters(in: .whitespaces)
        return entries.filter { entry in
            let matchesKind = prefix.map { entry.kind == $0 } ?? (entry.kind != "*")
            let matchesText = needle.isEmpty || entry.name.localizedCaseInsensitiveContains(needle)
                || entry.detail.localizedCaseInsensitiveContains(needle)
            return matchesKind && matchesText
        }
    }

    static func selection(in entries: [DesktopNavigationEntry], current: DesktopNavigationTarget?, delta: Int) -> DesktopNavigationTarget? {
        guard !entries.isEmpty else { return nil }
        let index = entries.firstIndex { $0.id == current } ?? 0
        return entries[min(entries.count - 1, max(0, index + delta))].id
    }
}

/// Catalyst text editing gets arrow events before SwiftUI onKeyPress. Register
/// commands on the actual first responder instead; ordinary editing stays native.
private final class NavigationTextField: UITextField {
    var onMove: (Int) -> Void = { _ in }
    var onOpen: () -> Void = {}
    var onEscape: () -> Void = {}
    private var focusedOnce = false

    override var keyCommands: [UIKeyCommand]? {
        let commands = [
            UIKeyCommand(input: UIKeyCommand.inputDownArrow, modifierFlags: [], action: #selector(nextResult)),
            UIKeyCommand(input: UIKeyCommand.inputUpArrow, modifierFlags: [], action: #selector(previousResult)),
            UIKeyCommand(input: "\t", modifierFlags: [], action: #selector(keepSearchFocus)),
            UIKeyCommand(input: "\t", modifierFlags: [.shift], action: #selector(keepSearchFocus)),
            UIKeyCommand(input: "\r", modifierFlags: [], action: #selector(openResult)),
            UIKeyCommand(input: UIKeyCommand.inputEscape, modifierFlags: [], action: #selector(closeSwitcher))
        ]
        commands.forEach { $0.wantsPriorityOverSystemBehavior = true }
        return (super.keyCommands ?? []) + commands
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window != nil, !focusedOnce {
            focusedOnce = true
            DispatchQueue.main.async { [weak self] in self?.becomeFirstResponder() }
        }
    }
    @objc private func nextResult() { onMove(1) }
    @objc private func previousResult() { onMove(-1) }
    // Discord's Tab does not change the selected result. Until the help-link
    // focus path is implemented, keep the editor active rather than strand keys.
    @objc private func keepSearchFocus() { becomeFirstResponder() }
    @objc private func openResult() { onOpen() }
    @objc private func closeSwitcher() { onEscape() }
}

private struct DesktopNavigationInput: UIViewRepresentable {
    @Binding var text: String
    let onMove: (Int) -> Void
    let onOpen: () -> Void
    let onEscape: () -> Void

    final class Coordinator: NSObject, UITextFieldDelegate {
        var owner: DesktopNavigationInput
        init(_ owner: DesktopNavigationInput) { self.owner = owner }
        @objc func changed(_ field: UITextField) { owner.text = field.text ?? "" }
        func textFieldShouldReturn(_ textField: UITextField) -> Bool {
            owner.onOpen()
            return false
        }
    }
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeUIView(context: Context) -> NavigationTextField {
        let field = NavigationTextField()
        let font = DesktopFriendsTypography.ctFont(22, weight: .regular)
        field.font = UIFont(name: CTFontCopyPostScriptName(font) as String, size: 22)
        field.textColor = UIColor(MoodTheme.textPrimary)
        field.attributedPlaceholder = NSAttributedString(string: "Où désires-tu aller ?", attributes: [
            .foregroundColor: UIColor.clear, .font: field.font as Any
        ])
        field.autocorrectionType = .no
        field.autocapitalizationType = .none
        field.spellCheckingType = .no
        field.returnKeyType = .go
        field.accessibilityLabel = "Navigation rapide"
        field.delegate = context.coordinator
        field.addTarget(context.coordinator, action: #selector(Coordinator.changed(_:)), for: .editingChanged)
        field.setContentHuggingPriority(.defaultLow, for: .horizontal)
        field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        updateUIView(field, context: context)
        return field
    }
    func updateUIView(_ field: NavigationTextField, context: Context) {
        context.coordinator.owner = self
        if field.text != text { field.text = text }
        field.onMove = onMove
        field.onOpen = onOpen
        field.onEscape = onEscape
    }
}

/// One full-window modal owner: sidebar click and Cmd-K share this same view.
struct DesktopQuickSwitcher: View {
    let items: [QuickSwitcherItem]
    @Binding var isPresented: Bool
    var onSelect: (DesktopNavigationTarget) -> Void
    @State private var query = ""
    @State private var selected: DesktopNavigationTarget?

    private var results: [DesktopNavigationEntry] {
        QuickSwitcherSearch.rows(for: query, items: items, recents: QuickSwitcherRecents.load()).map { row in
            let item = row.item
            let target: DesktopNavigationTarget
            switch item.destination {
            case .channel(let server, let channel): target = .channel(server: server, channel: channel)
            case .conversation(let id): target = .directMessage(id)
            case .server(let id): target = .server(id)
            }
            let kind: Character = switch item.kind {
            case .textChannel: "#"
            case .voiceChannel: "!"
            case .conversation: "@"
            case .server: "*"
            }
            return DesktopNavigationEntry(id: target, name: item.title, detail: item.detail, icon: item.channelIcon, kind: kind)
        }
    }
    private var active: DesktopNavigationTarget? { selected ?? results.first?.id }

    private func move(_ delta: Int) {
        selected = DesktopNavigationIndex.selection(in: results, current: active, delta: delta)
    }

    private func open(_ target: DesktopNavigationTarget?) {
        guard isPresented, let target else { return }
        isPresented = false
        onSelect(target)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            DesktopNavigationInput(text: $query, onMove: move,
                onOpen: { open(active) }, onEscape: { isPresented = false })
                .overlay(alignment: .leading) {
                    if query.isEmpty {
                        CalibratedDesktopText(value: "Où désires-tu aller ?", size: 22,
                            color: DesktopFriendsPalette.placeholder, glyphBackground: DesktopUXPalette.input)
                            .offset(x: 1, y: -2)
                            .allowsHitTesting(false).accessibilityHidden(true)
                    }
                }
                .padding(.horizontal, 12)
                .frame(height: 70)
                .background(DesktopUXPalette.input)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(DesktopFriendsPalette.outline, lineWidth: 1))
                .padding(20)

            CalibratedDesktopText(value: query.isEmpty ? "SALONS ET MESSAGES PRIVÉS" : "RÉSULTATS", size: 12, weight: .bold,
                color: MoodTheme.textSupporting, glyphBackground: DesktopUXPalette.popup)
                .padding(.horizontal, 30)
                .padding(.top, 8)
                .padding(.bottom, 6)

            ScrollViewReader { scroll in
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(results) { entry in
                            Button { open(entry.id) } label: {
                                HStack(spacing: 10) {
                                    CalibratedDesktopSymbol(name: entry.icon, size: 18)
                                        .foregroundStyle(MoodTheme.textSupporting)
                                        .frame(width: 20)
                                    CalibratedDesktopText(value: entry.name, size: 16, weight: .medium,
                                        glyphBackground: active == entry.id ? DesktopUXPalette.highlighted : DesktopUXPalette.popup)
                                        .lineLimit(1)
                                    Spacer(minLength: 12)
                                    CalibratedDesktopText(value: entry.detail, size: 14, color: DesktopFriendsPalette.placeholder,
                                        glyphBackground: active == entry.id ? DesktopUXPalette.highlighted : DesktopUXPalette.popup)
                                        .lineLimit(1)
                                }
                                .padding(.horizontal, 10)
                                .frame(height: 34)
                                .background(active == entry.id ? DesktopUXPalette.highlighted : DesktopUXPalette.popup)
                                .clipShape(RoundedRectangle(cornerRadius: 4))
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("\(entry.name), \(entry.detail)")
                            .accessibilityAddTraits(active == entry.id ? .isSelected : [])
                            .onHover { if $0 { selected = entry.id } }
                            .id(entry.id)
                        }
                        if results.isEmpty {
                            CalibratedDesktopText(value: "Aucun résultat", size: 16, color: MoodTheme.textSecondary,
                                glyphBackground: DesktopUXPalette.popup)
                                .padding(24)
                        }
                    }
                    .padding(.horizontal, 20)
                }
                .frame(height: 200)
                .onChange(of: selected) { _, target in
                    if let target { scroll.scrollTo(target, anchor: .center) }
                }
            }
            HStack(spacing: 4) {
                CalibratedDesktopText(value: "CONSEIL DE PRO :", size: 12, weight: .bold, color: MoodTheme.onlineGreen,
                    glyphBackground: DesktopUXPalette.popup)
                CalibratedDesktopText(value: "@ MP   # salons   ! vocal   * serveurs   ↑ ↓ sélectionner   Entrée ouvrir", size: 12,
                    color: MoodTheme.textSupporting, glyphBackground: DesktopUXPalette.popup)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 20)
        }
        .padding(1)
        .frame(width: 680)
        .background(DesktopUXPalette.popup)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(DesktopFriendsPalette.outline, lineWidth: 1))
        .onChange(of: query) { _, _ in selected = nil }
    }
}

/// Read-only profile column. Contents are Mood data, not copied Discord account data.
struct DesktopDMProfilePanel: View {
    @Environment(AuthState.self) private var authState
    let user: MoodUser
    var onOpenProfile: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        ZStack(alignment: .bottomLeading) {
                            user.roleColor.opacity(0.2).frame(height: 105)
                                .clipShape(UnevenRoundedRectangle(topLeadingRadius: 7, topTrailingRadius: 7, style: .circular))
                                .padding(.horizontal, 2).padding(.top, 2)
                            ZStack(alignment: .bottomTrailing) {
                                AvatarGlyph(user: user).font(.mood(44))
                                    .frame(width: 80, height: 80)
                                    .background(MoodTheme.inputBg).clipShape(Circle())
                                    .overlay(Circle().strokeBorder(MoodTheme.inputBg, lineWidth: 6))
                                StatusIndicator(status: user.status, size: 16, borderColor: MoodTheme.inputBg)
                            }
                            .padding(.leading, 18).offset(y: 32)
                        }
                        VStack(alignment: .leading, spacing: 4) {
                            CalibratedDesktopText(value: user.displayName, size: 20, weight: .bold,
                                glyphBackground: MoodTheme.inputBg)
                            CalibratedDesktopText(value: user.username, size: 14,
                                glyphBackground: MoodTheme.inputBg)
                            if !user.bio.isEmpty {
                                Text(user.bio).desktopFriendsFont(14).foregroundStyle(MoodTheme.textPrimary)
                                    .fixedSize(horizontal: false, vertical: true).padding(.top, 24)
                            }
                            CalibratedDesktopText(value: "Membre depuis", size: 12, weight: .semibold,
                                glyphBackground: MoodTheme.inputBg).padding(.top, 24)
                            Text(authState.isDemoMode ? user.joinedDate.formatted(.dateTime.day().month(.wide).year().locale(Locale(identifier: "fr_FR"))) : "Non renseigné")
                                .desktopFriendsFont(14)
                                .foregroundStyle(MoodTheme.textPrimary).padding(.top, 4)
                        }
                        .padding(.horizontal, 18).padding(.top, 44).padding(.bottom, 24)
                    }
                }
                Button(action: onOpenProfile) {
                    CalibratedDesktopText(value: "Voir le profil complet", size: DesktopSurfaceMetrics.profileButtonFontSize, weight: .medium,
                        glyphBackground: DesktopSurfacePalette.profileButtonFill)
                        .offset(y: DesktopSurfaceMetrics.profileButtonTextOffset)
                        .frame(maxWidth: .infinity).frame(height: 40)
                        .background(DesktopSurfacePalette.profileButtonFill)
                        .modifier(DesktopRoundedSurface(radius: 8, border: DesktopSurfacePalette.profileButton))
                }
                .buttonStyle(.plain).padding(.horizontal, 18).padding(.bottom, 18)
            }
            .padding(1)
            .background(MoodTheme.inputBg)
            .modifier(DesktopRoundedSurface(radius: DesktopSurfaceMetrics.profileRadius, border: DesktopSurfacePalette.profileBorder))
            .padding(.top, 7).padding(.horizontal, DesktopSurfaceMetrics.profileInset).padding(.bottom, 7)
            .frame(width: DesktopSurfaceMetrics.profileColumnWidth)
        }
    }
}

/// Desktop-only font fallback for legacy controls not yet raster-calibrated.
/// Existing iOS/iPad system fonts and monospaced controls remain unchanged.
extension Font {
    static func desktopReferenceSystem(size: CGFloat, weight: Font.Weight = .regular, design: Font.Design = .default) -> Font {
        #if targetEnvironment(macCatalyst)
        if design == .default { return DesktopFriendsTypography.font(size, weight: weight) }
        #endif
        return .system(size: size, weight: weight, design: design)
    }
}
