import SwiftUI
import UIKit
import GameController
import UniformTypeIdentifiers

struct MessageInputBar: View {
    @Environment(\.desktopFriendsCalibration) private var calibrated
    @Binding var text: String
    let channelName: String
    let isE2E: Bool
    var isDirectMessage = false
    var typingUsers: [String] = []
    // Bloque la saisie (ex. room E2EE non supportée — ne pas envoyer du clair)
    var isDisabled: Bool = false
    @Binding var replyingTo: ChatMessage?
    var mentionMembers: [MentionCandidate] = []
    var focusRequest: UUID?
    var onSend: (() -> Void)?
    var onAttachFile: ((URL) -> Void)?
    @State private var attachmentError: String?
    @State private var showEmojiPicker = false
    @State private var showGIFPicker = false
    @State private var showAttachMenu = false
    @State private var importedTypes: [UTType]?
    @FocusState private var composerFocused: Bool

    init(text: Binding<String>, channelName: String, isE2E: Bool, isDirectMessage: Bool = false, typingUsers: [String] = [], isDisabled: Bool = false, replyingTo: Binding<ChatMessage?> = .constant(nil), onSend: (() -> Void)? = nil, onAttachFile: ((URL) -> Void)? = nil, mentionMembers: [MentionCandidate] = [], focusRequest: UUID? = nil) {
        self._text = text
        self.channelName = channelName
        self.isE2E = isE2E
        self.isDirectMessage = isDirectMessage
        self.typingUsers = typingUsers
        self.isDisabled = isDisabled
        self._replyingTo = replyingTo
        self.onSend = onSend
        self.onAttachFile = onAttachFile
        self.mentionMembers = mentionMembers
        self.focusRequest = focusRequest
    }

    var body: some View {
        VStack(spacing: 0) {
            if let attachmentError {
                Text(attachmentError).font(.mood(12)).foregroundStyle(MoodTheme.mentionBadge)
            }
            let matches = MessagingServerPolicy.mentions(text, members: mentionMembers)
            if !matches.isEmpty {
                VStack(alignment: .leading, spacing: 4 * LayoutMetrics.scale) {
                    ForEach(matches, id: \.userId) { member in
                        Button {
                            if let at = text.lastIndex(of: "@") { text = String(text[..<at]) + "@" + member.displayName + " " }
                        } label: {
                            Text("@\(member.displayName)")
                                .font(.mood(13)).foregroundStyle(MoodTheme.textPrimary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }.buttonStyle(.plain)
                    }
                }.padding(8 * LayoutMetrics.scale).background(MoodTheme.popupBg)
            }
            // Typing indicator
            if !typingUsers.isEmpty {
                HStack(spacing: 6 * LayoutMetrics.scale) {
                    TypingDots()
                    Text(typingText)
                        .font(.mood(12))
                        .foregroundStyle(MoodTheme.textSecondary)
                    Spacer()
                }
                .padding(.horizontal, 20 * LayoutMetrics.scale)
                .padding(.bottom, 4)
            }

            // Reply bar
            if let reply = replyingTo {
                HStack(spacing: 8 * LayoutMetrics.scale) {
                    Image(systemName: "arrowshape.turn.up.left.fill")
                        .font(.mood(10))
                        .foregroundStyle(MoodTheme.brandAccent)

                    Text("Répondre à")
                        .font(.mood(12))
                        .foregroundStyle(MoodTheme.textSecondary)

                    Text(reply.sender.displayName)
                        .font(.mood(12, weight: .semibold))
                        .foregroundStyle(reply.sender.roleColor)

                    Text("— \(reply.content)")
                        .font(.mood(12))
                        .foregroundStyle(MoodTheme.textMuted)
                        .lineLimit(1)

                    Spacer()

                    Button {
                        replyingTo = nil
                    } label: {
                        Image(systemName: "xmark")
                            .font(.mood(10))
                            .foregroundStyle(MoodTheme.textPrimary)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 16 * LayoutMetrics.scale)
                .padding(.vertical, 8 * LayoutMetrics.scale)
                .background(MoodTheme.glassBg)
            }

            HStack(spacing: 0) {
                // Bouton +
                Button { showAttachMenu.toggle() } label: {
                    CalibratedDesktopSymbol(name: calibrated ? "desktop.attach" : "plus", size: 16, calibratedSize: 24, weight: .medium)
                        .foregroundStyle(calibrated ? MoodTheme.textSupporting : MoodTheme.textPrimary)
                        .frame(width: 30 * LayoutMetrics.scale, height: 30 * LayoutMetrics.scale)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.leading, 8 * LayoutMetrics.scale)
                .padding(.trailing, 10 * LayoutMetrics.scale)
                .help("Joindre un fichier")
                .popover(isPresented: $showAttachMenu, arrowEdge: .top) {
                    VStack(spacing: 2) {
                        AttachMenuItem(icon: "doc", label: "Importer un fichier", color: MoodTheme.brandAccent) {
                            showAttachMenu = false
                            importedTypes = [.item]
                        }
                        AttachMenuItem(icon: "photo", label: "Importer une photo", color: MoodTheme.onlineGreen) {
                            showAttachMenu = false
                            importedTypes = [.image, .movie]
                        }
                    }
                    .padding(8)
                    .frame(width: 220)
                    .background(MoodTheme.channelList)
                }
                .fileImporter(
                    isPresented: Binding(get: { importedTypes != nil }, set: { if !$0 { importedTypes = nil } }),
                    allowedContentTypes: importedTypes ?? [.item]
                ) { result in
                    switch result {
                    case .success(let url): attachmentError = nil; onAttachFile?(url)
                    case .failure: attachmentError = "Impossible d’importer le fichier. Réessaie."
                    }
                }
                .disabled(isDisabled || onAttachFile == nil)

                // Champ texte
                HStack(spacing: 6 * LayoutMetrics.scale) {

                    TextField(
                        "",
                        text: $text,
                        prompt: Text(isDisabled ? "Saisie désactivée (conversation chiffrée)" : isDirectMessage ? "Envoyer un message à @\(channelName)" : "Envoyer un message dans #\(channelName)")
                            .foregroundStyle(MoodTheme.textMuted),
                        axis: .vertical
                    )
                        .textFieldStyle(.plain)
                        .focused($composerFocused)
                        .onChange(of: focusRequest) { _, _ in composerFocused = true }
                        .desktopFriendsFont(calibrated ? 16 : 15)
                        .foregroundStyle(MoodTheme.textPrimary)
                        .disabled(isDisabled)
                        .lineLimit(1...5)
                        .onKeyPress(.return, phases: .down) { press in
                            guard !isDisabled else { return .handled }
                            if press.modifiers.contains(.shift) { text += "\n" } else { onSend?() }
                            return .handled
                        }
                        .onSubmit {
                            guard !isDisabled else { return }
                            onSend?()
                        }
                        .onChange(of: text) { old, new in
                            // Mac Catalyst: the multi-line field's text view takes Return before
                            // onKeyPress sees it and inserts a line break, so nothing was sent. A
                            // plain Return that added exactly one line break sends instead.
                            guard !isDisabled, MessageReturnKey.isPlainReturn(old: old, new: new),
                                  !MessageReturnKey.isShiftHeld else { return }
                            text = old
                            onSend?()
                        }
                        .onKeyPress(.escape) {
                            guard replyingTo != nil else { return .ignored }
                            replyingTo = nil
                            return .handled
                        }
                }

                // Boutons droite
                HStack(spacing: 4 * LayoutMetrics.scale) {
                    if onAttachFile != nil {
                        PasteButton(supportedContentTypes: [.image]) { providers in
                            for provider in providers {
                                provider.loadObject(ofClass: UIImage.self) { object, _ in
                                    guard let image = object as? UIImage else { return }
                                    Task { @MainActor in pasteImage(image) }
                                }
                            }
                        }.labelStyle(.iconOnly).tint(MoodTheme.brandAccent).disabled(isDisabled)
                    }
                    // Discord shows what is left near the limit, in red once over.
                    if let remaining = MessageLengthPolicy.remaining(for: text) {
                        Text("\(remaining)")
                            .font(.mood(12, weight: .medium))
                            .monospacedDigit()
                            .foregroundStyle(remaining < 0 ? MoodTheme.mentionBadge : MoodTheme.textMuted)
                            .padding(.trailing, 4 * LayoutMetrics.scale)
                            .accessibilityLabel(remaining < 0
                                ? "\(-remaining) caractères de trop"
                                : "\(remaining) caractères restants")
                    }

                    Button {
                        showEmojiPicker.toggle()
                        showGIFPicker = false
                    } label: {
                        CalibratedDesktopSymbol(name: "face.smiling", size: 16, calibratedSize: 24)
                            .foregroundStyle(calibrated ? MoodTheme.textSupporting : MoodTheme.textPrimary)
                            .frame(width: 30 * LayoutMetrics.scale, height: 30 * LayoutMetrics.scale)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help("Emoji")
                    .disabled(isDisabled)
                    .popover(isPresented: $showEmojiPicker, arrowEdge: .bottom) {
                        EmojiPicker(isPresented: $showEmojiPicker) { emoji in
                            text += emoji
                        }
                    }


                }
                .fixedSize()
                .padding(.trailing, 8 * LayoutMetrics.scale)
            }
            .frame(minHeight: LayoutMetrics.composerHeight)
            .background(MoodTheme.inputBg)
            .desktopRoundedSurface(calibrated: calibrated, radius: DesktopSurfaceMetrics.composerRadius * LayoutMetrics.scale,
                border: DesktopSurfacePalette.composerBorder(focused: composerFocused), legacyBorder: MoodTheme.composerBorder)
            .opacity(isDisabled ? 0.5 : 1)
            .padding(.horizontal, LayoutMetrics.composerHorizontalInset)
            .padding(.bottom, LayoutMetrics.composerBottomInset)
        }
        .background(MoodTheme.chatBackground)
        .dropDestination(for: URL.self) { urls, _ in
            guard !isDisabled, let onAttachFile else { return false }
            for url in urls { onAttachFile(url) }
            return !urls.isEmpty
        }
        .onDrop(of: [UTType.image], isTargeted: nil) { providers in
            guard !isDisabled, onAttachFile != nil else { return false }
            for provider in providers {
                provider.loadObject(ofClass: UIImage.self) { object, _ in
                    guard let image = object as? UIImage else { return }
                    Task { @MainActor in pasteImage(image) }
                }
            }
            return !providers.isEmpty
        }
        .onKeyPress(characters: CharacterSet(charactersIn: "v"), phases: .down) { press in
            guard press.modifiers.contains(.command), !isDisabled,
                  let image = UIPasteboard.general.image else { return .ignored }
            pasteImage(image)
            return .handled
        }
    }

    private func pasteImage(_ image: UIImage) {
        guard let onAttachFile, let data = image.pngData() else { return }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".png")
        do { try data.write(to: url); attachmentError = nil; onAttachFile(url) }
        catch { attachmentError = "Impossible de coller cette image." }
    }

    private var typingText: String {
        switch typingUsers.count {
        case 1: return "\(typingUsers[0]) est en train d'écrire..."
        case 2: return "\(typingUsers[0]) et \(typingUsers[1]) sont en train d'écrire..."
        default: return "Plusieurs personnes sont en train d'écrire..."
        }
    }
}

private extension View {
    @ViewBuilder
    func desktopComposerFocus(calibrated: Bool, focus: FocusState<Bool>.Binding) -> some View {
        if calibrated { focused(focus) } else { self }
    }
}

// MARK: - Typing Dots Animation

/// Discord's typing indicator: three dots pulsing in sequence while someone types.
struct TypingDots: View {
    var body: some View {
        HStack(spacing: 3 * LayoutMetrics.scale) {
            ForEach(0..<3) { _ in
                Circle().fill(MoodTheme.textSecondary)
                    .frame(width: 5 * LayoutMetrics.scale, height: 5 * LayoutMetrics.scale)
            }
        }
    }
}

struct AttachMenuItem: View {
    let icon: String
    let label: String
    let color: Color
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 14))
                    .foregroundStyle(color)
                    .frame(width: 20)
                Text(label)
                    .font(.system(size: 13))
                    .foregroundStyle(isHovered ? .white : MoodTheme.textPrimary)
                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(isHovered ? MoodTheme.brandAccent : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { hovering in isHovered = hovering }
    }
}

// MARK: - Emoji Picker

struct EmojiPicker: View {
    @Environment(\.layoutMode) private var layoutMode
    @Binding var isPresented: Bool
    let onSelect: (String) -> Void

    var body: some View {
        MediaEmojiPicker { emoji in
            onSelect(emoji)
            isPresented = false
        }
    }
}

// MARK: - GIF Picker

struct GIFPicker: View {
    @Environment(\.layoutMode) private var layoutMode
    @Binding var isPresented: Bool
    @State private var searchText = ""

    // GIF placeholders
    private let trendingGIFs: [(String, String)] = [
        ("😂", "Rire"), ("🎉", "Fête"), ("👏", "Applaudir"), ("🔥", "Feu"),
        ("💃", "Danse"), ("😍", "Amour"), ("🤣", "MDR"), ("👋", "Salut"),
        ("😎", "Cool"), ("🥳", "Célébration"), ("🤦", "Facepalm"), ("💪", "Fort"),
        ("😴", "Dormir"), ("🏃", "Courir"), ("🤝", "Deal"), ("🙈", "Oh non"),
    ]

    var body: some View {
        VStack(spacing: 0) {
            // Search
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 12))
                    .foregroundStyle(MoodTheme.textMuted)
                TextField("Rechercher un GIF", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                    .foregroundStyle(MoodTheme.textPrimary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(MoodTheme.glassBg)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .padding(10)

            // Trending label
            HStack {
                Text("TENDANCES")
                    .font(.system(size: 11, weight: .bold))
                    .tracking(0.4)
                    .foregroundStyle(MoodTheme.textSecondary)
                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 6)

            DesktopPixelRule()

            // GIF grid
            ScrollView(showsIndicators: false) {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 6) {
                    ForEach(trendingGIFs, id: \.1) { emoji, label in
                        Button {
                            isPresented = false
                        } label: {
                            VStack(spacing: 4) {
                                Text(emoji)
                                    .font(.system(size: 32))
                                    .frame(maxWidth: .infinity)
                                    .frame(height: 80)
                                    .background(MoodTheme.glassBg)
                                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

                                Text(label)
                                    .font(.system(size: 10))
                                    .foregroundStyle(MoodTheme.textMuted)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(10)
            }

            // Powered by
            HStack {
                Text("Propulsé par Tenor")
                    .font(.system(size: 10))
                    .foregroundStyle(MoodTheme.textMuted)
            }
            .padding(.vertical, 6)
        }
        .adaptiveFrame(width: 310, height: 380, mode: layoutMode)
        .background(MoodTheme.channelList)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(MoodTheme.glassBorder, lineWidth: 0.5)
        )
        .popoverElevation()
    }
}

#Preview {
    VStack {
        Spacer()
        MessageInputBar(text: .constant(""), channelName: "general", isE2E: true)
    }
    .background(MoodTheme.chatBackground)
    .preferredColorScheme(.dark)
}

/// Return-to-send for the desktop composer (Discord: Return sends, Shift+Return breaks the line).
enum MessageReturnKey {
    /// One character more, and that character is a line break.
    static func isPlainReturn(old: String, new: String) -> Bool {
        new.count == old.count + 1
            && new.reduce(0) { $0 + ($1 == "\n" ? 1 : 0) } == old.reduce(0) { $0 + ($1 == "\n" ? 1 : 0) } + 1
    }

    static var isShiftHeld: Bool {
        guard let keyboard = GCKeyboard.coalesced?.keyboardInput else { return false }
        return keyboard.button(forKeyCode: .leftShift)?.isPressed == true
            || keyboard.button(forKeyCode: .rightShift)?.isPressed == true
    }
}
