import SwiftUI

struct ExtendedProfileEditor: View {
    @Environment(\.layoutMode) private var layoutMode
    @Environment(MatrixStore.self) private var store
    @State private var draft = ExtendedProfile()
    @State private var saving = false
    @State private var feedback: String?
    @State private var didSave = false

    var body: some View {
        if layoutMode == .compact { mobileBody } else { desktopBody }
    }

    private func feedbackNotice(_ message: String) -> some View {
        let retry: (() -> Void)? = didSave ? nil : { save() }
        return MoodNotice(title: didSave ? "Profil enregistré" : "Le profil n’a pas été enregistré", detail: message,
            symbol: didSave ? "checkmark.circle" : "exclamationmark.circle",
            actionTitle: didSave ? nil : "Réessayer", action: retry, busy: saving)
    }

    private func save() {
        guard !saving else { return }
        saving = true
        feedback = nil
        Task {
            didSave = await store.updateExtendedProfile(draft)
            feedback = didSave ? "Tes changements sont enregistrés." : "Tes saisies sont conservées. Vérifie ta connexion, puis réessaie."
            saving = false
        }
    }

    private var mobileBody: some View {
        VStack(alignment: .leading, spacing: LayoutMetrics.mobile(16)) {
            if store.supportsExtendedAccountProfile || ProcessInfo.processInfo.arguments.contains("-uiPreview") {
                Text("À PROPOS DE MOI").font(.mood(12, weight: .semibold)).foregroundStyle(MoodTheme.textSecondary)
                TextField("Ta bio", text: $draft.bio, axis: .vertical).lineLimit(3...8).font(.mood(16))
                Text("PRONOMS").font(.mood(12, weight: .semibold)).foregroundStyle(MoodTheme.textSecondary)
                TextField("Tes pronoms", text: $draft.pronouns).font(.mood(16)).frame(minHeight: LayoutMetrics.mobile(44))
                Button(saving ? "Enregistrement…" : "Enregistrer la bio") { save() }.buttonStyle(MobilePrimaryButtonStyle()).disabled(saving || store.userId == nil)
                if let feedback { feedbackNotice(feedback) }
            }
        }.padding(.vertical, LayoutMetrics.mobile(8))
            .task {
                if let id = store.userId { await store.loadExtendedProfile(userId: id); draft = store.extendedProfiles[id] ?? ExtendedProfile() }
            }
    }

    private var desktopBody: some View {
        VStack(alignment: .leading, spacing: LayoutMetrics.mobile(12)) {
            if store.supportsExtendedAccountProfile || ProcessInfo.processInfo.arguments.contains("-uiPreview") {
            SettingsSection(title: "À PROPOS DE MOI") {
                TextField("Ta bio", text: $draft.bio, axis: .vertical).lineLimit(2...4)
            }
            SettingsSection(title: "PRONOMS") { TextField("Tes pronoms", text: $draft.pronouns) }
            Button("Enregistrer la bio et les pronoms") { save() }.disabled(saving || store.userId == nil)
            if let feedback { feedbackNotice(feedback) }
            }
        }
        .font(.mood(14)).foregroundStyle(MoodTheme.textPrimary)
        .textFieldStyle(.roundedBorder)
        .task {
            if let id = store.userId {
                await store.loadExtendedProfile(userId: id)
                draft = store.extendedProfiles[id] ?? ExtendedProfile()
            }
        }
    }
}
