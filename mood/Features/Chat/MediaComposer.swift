import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// Room-scoped composer. Hosts supply only their room id and existing reply binding.
/// No session restoration, login or account provisioning is performed here.
struct MediaComposer: View {
    @Environment(MatrixStore.self) private var store
    let roomID: String
    let channelName: String
    var disabled = false
    @Binding var text: String
    @Binding var replyingTo: ChatMessage?
    var members: [MentionCandidate] = []
    var typingUsers: [String] = []
    var focusRequest: UUID? = nil
    @FocusState private var composerFocused: Bool
    @State private var files: [URL] = []
    @State private var microphoneDenied = false
    @State private var error: String?
    @State private var sending = false
    @State private var picking = false
    @State private var emoji = false
    @State private var loadedKey: String?
    @State private var replyEventID: String?
    @State private var restoredText: String?
    @State private var savedText = ""
    @State private var active = false
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.layoutMode) private var layoutMode

    private var account: String { store.userId ?? "demo" }
    private var key: String { account + "\u{0}" + roomID }
    var body: some View {
        VStack(alignment: .leading, spacing: 8 * LayoutMetrics.scale) {
            if !typingUsers.isEmpty {
                Text(typingUsers.joined(separator: ", ") + " est en train d’écrire…")
                    .font(.mood(11)).foregroundStyle(MoodTheme.textMuted)
            }
            if microphoneDenied { MoodPermissionNotice(permission: .microphone) }
            if let error {
                MoodNotice(title: "L’envoi attend ton aide", detail: error,
                    actionTitle: "Choisir un fichier", action: { picking = true },
                    secondaryTitle: "Fermer", secondaryAction: { self.error = nil })
            }
            if sending { ProgressView("Préparation de ton message…").font(.mood(13)) }
            if !files.isEmpty {
                ScrollView(.horizontal) {
                    HStack {
                        ForEach(files, id: \.self) { url in
                            AttachmentDraftPreview(url: url, onCancel: { files.removeAll { $0 == url } }, onSend: send, showsSendButton: false)
                                .frame(width: 260 * LayoutMetrics.scale)
                        }
                    }
                }
            }
            if let reply = replyingTo {
                HStack {
                    Text("Répondre à " + reply.sender.displayName).font(.mood(12))
                    Button("Annuler") { replyingTo = nil; replyEventID = nil; persist() }.font(.mood(12))
                }.foregroundStyle(MoodTheme.textSecondary)
            } else if replyEventID != nil {
                HStack {
                    Text("Réponse conservée").font(.mood(12))
                    Button("Annuler") { replyEventID = nil; persist() }.font(.mood(12))
                }.foregroundStyle(MoodTheme.textSecondary)
            }
            ForEach(MessagingServerPolicy.mentions(text, members: members), id: \.userId) { member in
                Button("@" + member.displayName) {
                    // Keep the readable name in the editor. The formatter resolves display names.
                    if let at = text.lastIndex(of: "@") { text = String(text[..<at]) + "@" + member.displayName + " " }
                }.font(.mood(13)).foregroundStyle(MoodTheme.textPrimary)
            }
            if picking && layoutMode == .regular { MediaAttachmentPicker(onFiles: append) }
            inputBar
        }
        .sheet(isPresented: Binding(get: { picking && layoutMode == .compact }, set: { picking = $0 })) {
            MediaAttachmentPicker { urls in append(urls); picking = false }.environment(\.layoutMode, .compact)
        }
        .opacity(disabled ? 0.5 : 1)
        .onChange(of: replyingTo?.eventId) { old, value in
            if let value { replyEventID = value; persist() }
            else if old != nil, old == replyEventID, active { replyEventID = nil; persist() }
        }
        .onChange(of: key, initial: true) { old, _ in
            if let loadedKey, loadedKey == old { persistSnapshot() }
            files = []
            let draft = ComposerDrafts.shared.load(account: account, room: roomID)
            restoredText = draft?.text ?? ""
            text = restoredText ?? ""
            savedText = text
            replyEventID = draft?.replyEventID
            replyingTo = nil
            loadedKey = key
        }
        .onAppear {
            active = true
            let args = ProcessInfo.processInfo.arguments
            if args.contains("-uiPreview"), args.contains("-composerPreview"), files.isEmpty {
                files = [("n2-animation", "gif"), ("n2-clip", "mp4")].compactMap {
                    Bundle.main.url(forResource: $0.0, withExtension: $0.1)
                }
            }
        }
        .onDisappear { active = false; persistSnapshot() }
        .onChange(of: scenePhase) { _, phase in if phase != .active { persist() } }
        .dropDestination(for: URL.self) { urls, _ in guard !disabled, !sending else { return false }; append(urls); return !urls.isEmpty }
        .onKeyPress(characters: CharacterSet(charactersIn: "v"), phases: .down) { press in
            guard press.modifiers.contains(.command), !disabled, !sending, let image = UIPasteboard.general.image, let data = image.pngData() else { return .ignored }
            let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".png")
            do { try data.write(to: url); append([url]) } catch { self.error = "Impossible de coller cette image." }
            return .handled
        }
    }
    private func append(_ incoming: [URL]) {
        let next = AttachmentSelectionPolicy.appending(incoming, to: files)
        if files.count + incoming.filter({ !files.contains($0) }).count > AttachmentSelectionPolicy.limit { error = "10 pièces jointes maximum par envoi." }
        files = next
    }
    private func persist(key target: String? = nil) {
        guard loadedKey != nil, active else { return }
        savedText = text
        let components = (target ?? key).split(separator: "\u{0}", maxSplits: 1, omittingEmptySubsequences: false)
        guard components.count == 2 else { return }
        ComposerDrafts.shared.save(ComposerDraft(text: text, replyEventID: replyEventID), account: String(components[0]), room: String(components[1]))
    }
    private func persistSnapshot() {
        guard let loadedKey else { return }
        let components = loadedKey.split(separator: "\u{0}", maxSplits: 1, omittingEmptySubsequences: false)
        guard components.count == 2 else { return }
        ComposerDrafts.shared.save(ComposerDraft(text: savedText, replyEventID: replyEventID), account: String(components[0]), room: String(components[1]))
    }
    private var hasContent: Bool { !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !files.isEmpty }
    private var micAvailable: Bool { Bundle.main.object(forInfoDictionaryKey: "NSMicrophoneUsageDescription") != nil }

    private var placeholder: String {
        if disabled { return "Saisie désactivée" }
        guard layoutMode == .compact else { return "Message dans " + channelName }
        // Short enough to fit next to +, emoji and mic on a 390 pt iPhone.
        return channelName.hasPrefix("#") ? "Message dans " + channelName : "Message à @" + channelName
    }

    private var textField: some View {
        TextField(placeholder, text: $text, axis: .vertical)
            .textFieldStyle(.plain).lineLimit(1...5)
            .focused($composerFocused)
            .onChange(of: focusRequest) { _, _ in composerFocused = true }
            .onSubmit(send)
            .onKeyPress(.return, phases: .down) { press in
                if press.modifiers.contains(.shift) { text += "\n" } else { send() }
                return .handled
            }
            .onChange(of: text) { old, new in
                if restoredText == new { restoredText = nil; return }
                if MessageReturnKey.isPlainReturn(old: old, new: new), !MessageReturnKey.isShiftHeld {
                    text = old; send()
                } else { persist() }
            }
    }

    @ViewBuilder private var counter: some View {
        if let remaining = MessageLengthPolicy.remaining(for: text) {
            Text("\(remaining)").font(.mood(12, weight: .medium)).monospacedDigit()
                .foregroundStyle(remaining < 0 ? MoodTheme.mentionBadge : MoodTheme.textMuted)
                .accessibilityLabel(remaining < 0 ? "\(-remaining) caractères de trop" : "\(remaining) caractères restants")
        }
    }

    private var voiceButton: some View {
        VoiceRecorderButton(onRecorded: { url, waveform, duration in
            microphoneDenied = false
            Task { await store.sendVoice(roomId: roomID, fileURL: url, waveform: waveform, duration: duration) }
        }, onPermissionDenied: { microphoneDenied = true }, onFailure: { error = $0 })
    }

    /// iPhone: the original Liquid Glass capsule (+, field, emoji, send arrow when there is something to
    /// send, otherwise the mic like Discord). Elsewhere: the flat bar.
    @ViewBuilder private var inputBar: some View {
        if layoutMode == .compact {
            MobileGlassGroup {
                HStack(spacing: LayoutMetrics.mobile(10)) {
                    Button { picking.toggle() } label: { Image(systemName: "plus").font(.mood(23)).frame(minWidth: LayoutMetrics.mobile(44), minHeight: LayoutMetrics.mobile(44)) }
                        .accessibilityLabel("Joindre des médias")
                    textField.font(.mood(16))
                    counter
                    Button { emoji.toggle() } label: { Image(systemName: "face.smiling.fill").font(.mood(23)).frame(minWidth: LayoutMetrics.mobile(44), minHeight: LayoutMetrics.mobile(44)) }
                        .accessibilityLabel("Émoji")
                        .sheet(isPresented: $emoji) { MobileEmojiPicker { text += $0; emoji = false } }
                    if hasContent {
                        Button(action: send) {
                            Image(systemName: "arrow.up.circle.fill").font(.mood(26)).foregroundStyle(MoodTheme.brandAccent).frame(minWidth: LayoutMetrics.mobile(44), minHeight: LayoutMetrics.mobile(44))
                        }
                        .accessibilityLabel("Envoyer")
                    } else if micAvailable {
                        voiceButton
                    }
                }
                .buttonStyle(.plain).foregroundStyle(MoodTheme.textPrimary)
                .padding(.horizontal, LayoutMetrics.mobile(8)).padding(.vertical, LayoutMetrics.mobile(6))
                .mobileGlassCapsule()
            }
            .disabled(disabled || sending)
        } else {
            HStack(spacing: 10 * LayoutMetrics.scale) {
                Button { picking.toggle() } label: { Image(systemName: "plus") }.accessibilityLabel("Joindre des médias")
                textField.font(.mood(15))
                counter
                Button { emoji.toggle() } label: { Image(systemName: "face.smiling") }.accessibilityLabel("Emoji")
                    .popover(isPresented: $emoji) { MediaEmojiPicker { text += $0; emoji = false } }
                if micAvailable { voiceButton }
                Button(action: send) { Image(systemName: "paperplane.fill") }.accessibilityLabel("Envoyer")
                    .disabled(!hasContent)
            }.foregroundStyle(MoodTheme.textPrimary)
                .padding(12 * LayoutMetrics.scale).background(MoodTheme.inputBg, in: RoundedRectangle(cornerRadius: 8 * LayoutMetrics.scale))
                .disabled(disabled || sending)
        }
    }

    private func send() {
        guard !disabled, !sending, store.validateOutgoingText(text), !files.isEmpty || !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        sending = true
        error = nil
        let urls = files, body = text, reply = replyingTo?.eventId ?? replyEventID, room = roomID, owner = account
        Task { @MainActor in
            let success = await store.sendAttachments(roomId: room, urls: urls, text: body, replyToEventId: reply)
            // Preparation errors retain the selection for correction. Already queued items use the outbox's retry controls.
            if success {
                ComposerDrafts.shared.save(ComposerDraft(text: "", replyEventID: nil), account: owner, room: room)
            }
            if success, active, roomID == room, account == owner { text = ""; files = []; replyingTo = nil; replyEventID = nil; persist() }
            if !success { error = store.errorMessage ?? "Impossible d’envoyer les médias." }
            sending = false
        }
    }
}
