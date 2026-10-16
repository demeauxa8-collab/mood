import SwiftUI

/// Explicit launch-only previews never restore credentials or contact a service.
enum AccountAuthPreview {
    static var isTesting: Bool { NSClassFromString("XCTestCase") != nil || ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil }
    static var enabled: Bool { ProcessInfo.processInfo.arguments.contains("-authPreview") }
    static var screen: String { ProcessInfo.processInfo.arguments.last ?? "login" }
}

struct EmailCodeField: View {
    @Binding var code: String
    var body: some View {
        AuthField(icon: "number", placeholder: "Code à 6 chiffres", text: $code)
            .keyboardType(.numberPad).textContentType(.oneTimeCode)
            .textInputAutocapitalization(.never).autocorrectionDisabled()
    }
}

struct PasswordRecoveryView: View {
    @Environment(AccountStore.self) private var accountStore
    var authState: AuthState
    @State private var email = ""
    @State private var code = ""
    @State private var password = ""
    @State private var confirmation = ""
    @State private var message: String?
    @State private var notice: String?

    private var readyForPassword: Bool { accountStore.recoveryEmail != nil || accountStore.hasRecoverySession }
    private var valid: Bool {
        readyForPassword
        ? (accountStore.hasRecoverySession || AccountValidation.isValidEmailCode(code)) && AccountValidation.isValidPassword(password) && password == confirmation
        : AccountValidation.isValidEmail(email)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: LayoutMetrics.mobile(16)) {
                Text(readyForPassword ? "Nouveau mot de passe" : "Mot de passe oublié ?")
                    .font(.mood(24, weight: .bold)).foregroundStyle(MoodTheme.textPrimary)
                Text(readyForPassword
                     ? (accountStore.hasRecoverySession ? "Ton lien est confirmé. Choisis ton nouveau mot de passe." : "Entre le code reçu par e-mail, puis choisis ton nouveau mot de passe.")
                     : "Entre ton adresse e-mail pour recevoir un code de récupération.")
                    .font(.mood(14)).foregroundStyle(MoodTheme.textSecondary)
                if readyForPassword {
                    if !accountStore.hasRecoverySession { EmailCodeField(code: $code) }
                    passwordField("Nouveau mot de passe", text: $password)
                    passwordField("Confirmer le mot de passe", text: $confirmation)
                    Text("Au moins 8 caractères.").font(.mood(12)).foregroundStyle(MoodTheme.textMuted)
                } else {
                    AuthField(icon: "envelope", placeholder: "Adresse e-mail", text: $email)
                        .keyboardType(.emailAddress).textContentType(.emailAddress)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                }
                if let message = message ?? accountStore.errorMessage {
                    Text(message).font(.mood(13)).foregroundStyle(MoodTheme.mentionBadge)
                }
                if let notice { Text(notice).font(.mood(13)).foregroundStyle(MoodTheme.textSecondary) }
                Button(accountStore.isLoading ? "Envoi…" : readyForPassword ? "Changer le mot de passe" : "Envoyer le code") {
                    Task {
                        message = nil; notice = nil
                        do {
                            if readyForPassword {
                                try await accountStore.finishPasswordRecovery(code: code, password: password, confirmation: confirmation)
                                password = ""; confirmation = ""; code = ""
                                authState.currentScreen = .login
                                authState.isLoggedIn = accountStore.isSignedIn
                            } else {
                                try await accountStore.sendRecoveryCode(email: email)
                                notice = "Si un compte existe, un e-mail de récupération a été demandé."
                            }
                        } catch { message = error.localizedDescription }
                    }
                }
                .font(.mood(14, weight: .semibold)).foregroundStyle(MoodTheme.textPrimary)
                .frame(maxWidth: .infinity).frame(height: LayoutMetrics.accountButtonHeight)
                .background(MoodTheme.brandAccent)
                .clipShape(RoundedRectangle(cornerRadius: LayoutMetrics.accountCornerRadius))
                .buttonStyle(.plain).disabled(!valid || accountStore.isLoading)
                if let address = accountStore.recoveryEmail, !accountStore.hasRecoverySession {
                    Button("Renvoyer le code") {
                        Task {
                            message = nil
                            do { try await accountStore.sendRecoveryCode(email: address); notice = "Un nouvel e-mail a été demandé." }
                            catch { message = error.localizedDescription }
                        }
                    }.disabled(accountStore.isLoading)
                }
                Button("Retour à la connexion") {
                    password = ""; confirmation = ""; code = ""
                    accountStore.cancelPasswordRecovery()
                    authState.currentScreen = .login
                }.disabled(accountStore.isLoading)
            }
            .buttonStyle(.plain).foregroundStyle(MoodTheme.brandBlue)
            .frame(maxWidth: LayoutMetrics.mobile(360))
            .padding(LayoutMetrics.mobile(24)).padding(.top, LayoutMetrics.mobile(60))
            .frame(maxWidth: .infinity)
        }
        .background(MoodTheme.serverBar.ignoresSafeArea())
        .onDisappear { password = ""; confirmation = ""; code = "" }
    }

    private func passwordField(_ title: String, text: Binding<String>) -> some View {
        SecureField(title, text: text).textContentType(.newPassword)
            .textFieldStyle(.plain).font(.mood(14)).foregroundStyle(MoodTheme.textPrimary)
            .padding(LayoutMetrics.mobile(14)).background(MoodTheme.glassBg)
            .clipShape(RoundedRectangle(cornerRadius: LayoutMetrics.accountCornerRadius))
    }
}
