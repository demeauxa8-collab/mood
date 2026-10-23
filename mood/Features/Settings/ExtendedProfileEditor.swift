import SwiftUI

struct ExtendedProfileEditor: View {
    @Environment(\.layoutMode) private var layoutMode
    @Environment(MatrixStore.self) private var store
    @State private var draft = ExtendedProfile()
    @State private var saving = false
    @State private var feedback: String?

    var body: some View {
        if layoutMode == .compact { mobileBody } else { desktopBody }
    }

    private var mobileBody: some View {
        VStack(alignment: .leading, spacing: LayoutMetrics.mobile(16)) {
            if store.supportsExtendedAccountProfile || ProcessInfo.processInfo.arguments.contains("-uiPreview") {
                Text("À PROPOS DE MOI").font(.mood(12, weight: .semibold)).foregroundStyle(MoodTheme.textSecondary)
                TextField("Ta bio", text: $draft.bio, axis: .vertical).lineLimit(3...8).font(.mood(16))
                Text("PRONOMS").font(.mood(12, weight: .semibold)).foregroundStyle(MoodTheme.textSecondary)
                TextField("Tes pronoms", text: $draft.pronouns).font(.mood(16)).frame(minHeight: LayoutMetrics.mobile(44))
                Button(saving ? "Enregistrement…" : "Enregistrer la bio") {
                    Task {
                        saving = true
                        let success = await store.updateExtendedProfile(draft)
                        feedback = success ? "Profil enregistré." : store.errorMessage
                        saving = false
                    }
                }.buttonStyle(MobilePrimaryButtonStyle()).disabled(saving || store.userId == nil)
                if let feedback { Text(feedback).font(.mood(14)).foregroundStyle(MoodTheme.textSecondary) }
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
            Button("Enregistrer la bio et les pronoms") {
                Task {
                    saving = true
                    let success = await store.updateExtendedProfile(draft)
                    feedback = success ? "Profil enregistré." : store.errorMessage
                    saving = false
                }
            }.disabled(saving || store.userId == nil)
            if let feedback { Text(feedback).font(.mood(12)).foregroundStyle(MoodTheme.textSecondary) }
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
