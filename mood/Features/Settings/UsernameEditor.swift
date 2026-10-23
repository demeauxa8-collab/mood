import SwiftUI

struct UsernameEditor: View {
    @Environment(\.layoutMode) private var layoutMode
    @Environment(AccountStore.self) private var accountStore
    @Environment(\.dismiss) private var dismiss
    @State private var username = ""
    @State private var failure: String?
    @State private var saving = false

    var body: some View {
        if layoutMode == .compact { mobileBody } else { desktopBody }
    }

    private var mobileBody: some View {
        MobileSheet(title: "Nom d’utilisateur", onClose: { dismiss() }) {
            List {
                Section("Nom d’utilisateur") {
                    TextField("Ton nom d’utilisateur", text: $username)
                        .textInputAutocapitalization(.never).autocorrectionDisabled().font(.mood(16))
                    Text(MoodUsername.rule).font(.mood(14)).foregroundStyle(MoodTheme.textSecondary)
                }.listRowBackground(MoodTheme.inputBg)
                if let failure { Section { MoodNotice(title: "L’action n’a pas abouti", detail: failure, secondaryTitle: "Fermer", secondaryAction: { self.failure = nil }) }.listRowBackground(MoodTheme.inputBg) }
            }.mobileGroupedList()
                .toolbar { ToolbarItem(placement: .confirmationAction) {
                    Button(saving ? "Enregistrement…" : "Enregistrer") {
                        saving = true; failure = nil
                        Task {
                            do { try await accountStore.setUsername(username); dismiss() }
                            catch { failure = error.localizedDescription }
                            saving = false
                        }
                    }.font(.mood(17, weight: .semibold)).disabled(saving || !accountStore.isSignedIn)
                } }
        }
        .onAppear { username = accountStore.profile?.username ?? (ProcessInfo.processInfo.arguments.contains("-uiPreview") ? "augustin" : "") }
    }

    private var desktopBody: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: LayoutMetrics.mobile(16)) {
                TextField("Nom d’utilisateur", text: $username)
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
                    .font(.mood(16)).textFieldStyle(.roundedBorder)
                Text(MoodUsername.rule).font(.mood(13)).foregroundStyle(MoodTheme.textSecondary)
                if let failure { MoodNotice(title: "L’action n’a pas abouti", detail: failure, secondaryTitle: "Fermer", secondaryAction: { self.failure = nil }) }
                Button(saving ? "Enregistrement…" : "Enregistrer") {
                    saving = true
                    failure = nil
                    Task {
                        do { try await accountStore.setUsername(username); dismiss() }
                        catch { failure = error.localizedDescription }
                        saving = false
                    }
                }.font(.mood(15)).buttonStyle(.borderedProminent)
                    .disabled(saving || !accountStore.isSignedIn)
                Spacer()
            }
            .padding(LayoutMetrics.mobile(20)).background(MoodTheme.chatBackground)
            .navigationTitle("Nom d’utilisateur")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Annuler") { dismiss() } } }
        }
        .onAppear { username = accountStore.profile?.username ?? (ProcessInfo.processInfo.arguments.contains("-uiPreview") ? "augustin" : "") }
    }
}
