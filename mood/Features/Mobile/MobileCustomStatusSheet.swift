import SwiftUI

/// Discord iOS "Définir un statut personnalisé": a native sheet with Annuler / Enregistrer in the bar,
/// the emoji + text field, quick emojis, "Effacer après" as a checked list and a red "Effacer le statut".
/// The desktop keeps its compact `CustomStatusEditor` popover.
struct MobileCustomStatusSheet: View {
    @Environment(MatrixStore.self) private var matrixStore
    @Binding var isPresented: Bool
    @State private var statusText = ""
    @State private var selectedEmoji = "😀"
    @State private var clearAfter: ClearAfter = .never
    @State private var saving = false
    @State private var failure: String?
    @FocusState private var fieldFocused: Bool

    private let quickEmojis = ["😀", "😴", "🤒", "🏠", "🎮", "📚", "💻", "🎵"]

    enum ClearAfter: String, CaseIterable, Identifiable {
        case never = "Ne pas effacer", minutes30 = "30 minutes", hour1 = "1 heure", hours4 = "4 heures", today = "Aujourd'hui"
        var id: String { rawValue }

        var interval: TimeInterval? {
            switch self {
            case .never: return nil
            case .minutes30: return 30 * 60
            case .hour1: return 3600
            case .hours4: return 4 * 3600
            case .today: return Calendar.current.startOfDay(for: Date()).addingTimeInterval(86_400).timeIntervalSinceNow
            }
        }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack(spacing: LayoutMetrics.mobile(12)) {
                        Text(selectedEmoji)
                            .font(.mood(22))
                            .frame(width: LayoutMetrics.mobile(40), height: LayoutMetrics.mobile(40))
                            .background(MoodTheme.selectedBg, in: Circle())
                            .accessibilityLabel("Emoji du statut")
                        TextField("Quel est ton mood ?", text: $statusText)
                            .font(.mood(16))
                            .foregroundStyle(MoodTheme.textPrimary)
                            .focused($fieldFocused)
                            .submitLabel(.done)
                            .onSubmit(save)
                        if !statusText.isEmpty {
                            Button { statusText = "" } label: {
                                Image(systemName: "xmark.circle.fill").foregroundStyle(MoodTheme.textMuted)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Effacer le texte")
                        }
                    }
                    .padding(.vertical, LayoutMetrics.mobile(4))

                    // The eight quick emojis share the row's width: none hidden, 44pt-tall targets.
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 4), spacing: LayoutMetrics.mobile(4)) {
                        ForEach(quickEmojis, id: \.self) { emoji in
                            Button { selectedEmoji = emoji } label: {
                                Text(emoji)
                                    .font(.mood(22))
                                    .frame(maxWidth: .infinity, minHeight: LayoutMetrics.mobile(44))
                                    .background(selectedEmoji == emoji ? MoodTheme.selectedBg : Color.clear, in: Circle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .listRowBackground(MoodTheme.inputBg)

                Section {
                    ForEach(ClearAfter.allCases) { option in
                        Button { clearAfter = option } label: {
                            HStack {
                                Text(option.rawValue).font(.mood(16)).foregroundStyle(MoodTheme.textPrimary)
                                Spacer()
                                if clearAfter == option {
                                    Image(systemName: "checkmark").font(.mood(15, weight: .semibold)).foregroundStyle(MoodTheme.brandAccent)
                                }
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                } header: {
                    Text("EFFACER APRÈS").font(.mood(12, weight: .semibold)).foregroundStyle(MoodTheme.textSecondary)
                }
                .listRowBackground(MoodTheme.inputBg)

                if matrixStore.myStatusMessage != nil {
                    Section {
                        Button(role: .destructive) { clear() } label: {
                            Text("Effacer le statut").font(.mood(16)).foregroundStyle(MoodTheme.mentionBadge)
                        }
                    } footer: {
                        if let failure { Text(failure).foregroundStyle(MoodTheme.mentionBadge) }
                    }
                    .listRowBackground(MoodTheme.inputBg)
                } else if let failure {
                    Section { } footer: { Text(failure).foregroundStyle(MoodTheme.mentionBadge) }
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(MoodTheme.mobileSurface)
            .navigationTitle("Ton statut")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { isPresented = false } label: { Image(systemName: "xmark") }
                        .accessibilityLabel("Annuler")
                }
                ToolbarItem(placement: .confirmationAction) {
                    if saving {
                        ProgressView()
                    } else {
                        Button("Enregistrer", action: save).fontWeight(.semibold)
                    }
                }
            }
            .disabled(saving)
        }
        .onAppear(perform: loadCurrent)
    }

    /// "🎮 En game" → emoji 🎮 + text "En game".
    private func loadCurrent() {
        guard let message = matrixStore.myStatusMessage, !message.isEmpty else { return }
        if let first = message.first, first.unicodeScalars.first?.properties.isEmojiPresentation == true {
            selectedEmoji = String(first)
            statusText = String(message.dropFirst()).trimmingCharacters(in: .whitespaces)
        } else {
            statusText = message
        }
    }

    private func save() {
        let text = statusText.trimmingCharacters(in: .whitespaces)
        let message = text.isEmpty ? nil : "\(selectedEmoji) \(text)"
        let store = matrixStore
        let delay = clearAfter.interval
        saving = true
        failure = nil
        Task {
            guard await store.setMyStatus(store.myStatus, message: message) else {
                failure = store.errorMessage ?? "Impossible d'enregistrer le statut."
                saving = false
                return
            }
            saving = false
            isPresented = false
            // Cleared while the app is running; Matrix has no server-side expiry for status_msg.
            if let delay, let message {
                try? await Task.sleep(for: .seconds(delay))
                if store.myStatusMessage == message { await store.setMyStatus(store.myStatus, message: nil) }
            }
        }
    }

    private func clear() {
        saving = true
        failure = nil
        Task {
            if await matrixStore.setMyStatus(matrixStore.myStatus, message: nil) {
                isPresented = false
            } else {
                failure = matrixStore.errorMessage ?? "Impossible d'effacer le statut."
            }
            saving = false
        }
    }
}
