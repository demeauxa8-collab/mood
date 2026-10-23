import SwiftUI

struct AccountCredentialsView: View {
    @Environment(\.layoutMode) private var layoutMode
    @Environment(AccountStore.self) private var accountStore
    @State private var email = ""
    @State private var password = ""
    @State private var confirmation = ""
    @State private var nonce = ""
    @State private var busy = false
    @State private var feedback: String?

    var body: some View {
        if layoutMode == .compact { mobileBody } else { desktopBody }
    }

    private var mobileBody: some View {
        List {
            Section("Adresse e-mail") {
                TextField("Nouvelle adresse", text: $email).textContentType(.emailAddress).keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
                Text("Un lien de confirmation sera envoyé. Ton adresse actuelle reste active jusqu’à la confirmation.")
                    .font(.mood(14)).foregroundStyle(MoodTheme.textSecondary)
                Button("Changer l’e-mail") { update(isPassword: false) }
                    .disabled(busy || !AccountValidation.isValidEmail(email))
            }.listRowBackground(MoodTheme.inputBg)
            Section("Mot de passe") {
                Text("8 caractères minimum").font(.mood(14)).foregroundStyle(MoodTheme.textSecondary)
                SecureField("Nouveau mot de passe", text: $password).textContentType(.newPassword)
                SecureField("Confirmer", text: $confirmation).textContentType(.newPassword)
                Button("Changer le mot de passe") { update(isPassword: true) }
                    .disabled(busy || !AccountValidation.isValidPassword(password) || password != confirmation)
            }.listRowBackground(MoodTheme.inputBg)
            Section("Vérification") {
                Button("Recevoir un code par e-mail") {
                    Task {
                        busy = true
                        defer { busy = false }
                        do { try await accountStore.requestReauthentication(); feedback = "Consulte tes e-mails, puis saisis le code reçu." }
                        catch { feedback = "Impossible d’envoyer le code. Reconnecte-toi et réessaie." }
                    }
                }.disabled(busy)
                SecureField("Code reçu", text: $nonce).textContentType(.oneTimeCode)
            }.listRowBackground(MoodTheme.inputBg)
            if let feedback { Section { Text(feedback).font(.mood(14)).foregroundStyle(MoodTheme.textSecondary) }.listRowBackground(MoodTheme.inputBg) }
            if busy { Section { ProgressView("Enregistrement…") }.listRowBackground(MoodTheme.inputBg) }
        }.mobileGroupedList()
    }

    private var desktopBody: some View {
        VStack(alignment: .leading, spacing: LayoutMetrics.mobile(12)) {
            Text("Compte Mood").font(.mood(16, weight: .semibold))
            TextField("Nouvelle adresse e-mail", text: $email)
                .textInputAutocapitalization(.never).autocorrectionDisabled()
            Button("Changer l’e-mail") { update(isPassword: false) }
                .disabled(busy || !AccountValidation.isValidEmail(email))
            Text("Un lien de confirmation sera envoyé. L’adresse actuelle reste affichée tant que le changement n’est pas confirmé.")
                .font(.mood(12)).foregroundStyle(MoodTheme.textSecondary)
            SecureField("Nouveau mot de passe (8 caractères minimum)", text: $password)
            SecureField("Confirmer le mot de passe", text: $confirmation)
            Button("Changer le mot de passe") { update(isPassword: true) }
                .disabled(busy || !AccountValidation.isValidPassword(password) || password != confirmation)
            Button("Recevoir un code de vérification") {
                Task {
                    busy = true
                    defer { busy = false }
                    do {
                        try await accountStore.requestReauthentication()
                        feedback = "Consulte tes e-mails, puis saisis le code reçu ci-dessous."
                    } catch { feedback = "Impossible d’envoyer le code. Reconnecte-toi à Mood et réessaie." }
                }
            }.disabled(busy)
            SecureField("Code de vérification (si demandé)", text: $nonce)
            if let feedback { Text(feedback).font(.mood(13)).foregroundStyle(MoodTheme.textSecondary) }
            if busy { ProgressView() }
        }
        .font(.mood(14)).foregroundStyle(MoodTheme.textPrimary)
        .textFieldStyle(.roundedBorder)
        .padding(LayoutMetrics.mobile(16))
    }

    private func update(isPassword: Bool) {
        busy = true
        feedback = nil
        Task {
            defer { busy = false }
            do {
                try await accountStore.updateCredentials(email: isPassword ? nil : email.trimmingCharacters(in: .whitespacesAndNewlines),
                                                         password: isPassword ? password : nil,
                                                         nonce: nonce.isEmpty ? nil : nonce)
                feedback = isPassword ? "Mot de passe modifié." : "Demande envoyée : confirme le changement dans les e-mails reçus."
                password = ""
                confirmation = ""
                nonce = ""
            } catch {
                feedback = "Modification refusée. Vérifie ta connexion et les champs. Si Mood demande une vérification, reçois un code ou reconnecte-toi avant de réessayer."
            }
        }
    }
}
