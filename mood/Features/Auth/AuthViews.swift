import SwiftUI
import AuthenticationServices
import UIKit

// MARK: - Auth State

@Observable
class AuthState {
    var isLoggedIn = false
    // Developer-only demo data: true only when launched with -uiPreview (never reachable from the UI).
    var isDemoMode: Bool = false
    var currentScreen: AuthScreen = .login

    enum AuthScreen {
        case login, signup, matrixLink
    }
}

// MARK: - Login View

struct LoginView: View {
    @Environment(AccountStore.self) private var accountStore
    @Environment(\.layoutMode) private var layoutMode
    @Bindable var authState: AuthState
    var matrixStore: MatrixStore
    @State private var homeserver = "matrix.org"
    @State private var username = ""
    @State private var password = ""
    @State private var showPassword = false
    @State private var isLoading = false
    @State private var showAdvanced = false
    @State private var showMatrixLogin = false
    @State private var errorMessage: String?
    @State private var showForgotPassword = false
    @State private var showSSOAlert = false
    @State private var isSSOLoading = false
    @State private var ssoSession: ASWebAuthenticationSession?
    @State private var ssoContextProvider: SSOContextProvider?

    // Custom URL scheme for SSO callback
    private let ssoCallbackScheme = "moodapp"
    private let ssoCallbackURL = "moodapp://sso/callback"

    private var formWidth: CGFloat { 320 }

    var body: some View {
        ZStack {
            // Background
            MoodTheme.serverBar.ignoresSafeArea()


            if layoutMode == .regular {
                desktopLoginContent
            } else {
                compactLoginContent
            }
        }
        .task { if !AccountAuthPreview.enabled && !AccountAuthPreview.isTesting { await accountStore.loadProviders() } }
    }

    // MARK: - Desktop Login
    private var desktopLoginContent: some View {
        VStack(spacing: 0) {
            Spacer()
            loginLogo
            if accountStore.isConfigured && !showMatrixLogin {
                if accountStore.discordEnabled { discordLoginButton.frame(width: formWidth).padding(.bottom, 18) }
                accountLoginForm.frame(width: formWidth).padding(.bottom, 18)
            } else {
                loginForm.frame(width: formWidth).padding(.bottom, 24)
            }
            loginErrorMessage
                .frame(width: formWidth, alignment: .leading)
            if accountStore.isConfigured && !showMatrixLogin {
                Button { Task { await performMoodLogin(discord: false) } } label: {
                    Text(accountStore.isLoading ? "Connexion…" : "Se connecter avec une adresse e-mail")
                        .font(.mood( 14, weight: .semibold)).foregroundStyle(.white)
                        .frame(maxWidth: .infinity).frame(height: 48).background(MoodTheme.brandAccent)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }.buttonStyle(.plain).frame(width: formWidth).disabled(username.isEmpty || password.isEmpty || accountStore.isLoading)
            } else { loginButton.frame(width: formWidth) }
            if !accountStore.isConfigured || showMatrixLogin { loginForgotPassword }
            loginSeparator
                .frame(width: formWidth)
            loginSignupLink
            Spacer()
            if !accountStore.isConfigured { loginBranding }
        }
    }

    // MARK: - Compact Login
    private var compactLoginContent: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 16) {
                loginLogo
                    .padding(.top, 60)

                if accountStore.isConfigured && !showMatrixLogin {
                    if accountStore.discordEnabled { discordLoginButton }
                    accountLoginForm
                } else { loginForm }

                loginErrorMessage

                if accountStore.isConfigured && !showMatrixLogin {
                    Button { Task { await performMoodLogin(discord: false) } } label: {
                        Text(accountStore.isLoading ? "Connexion…" : "Se connecter avec une adresse e-mail")
                            .font(.mood( 13, weight: .semibold)).foregroundStyle(.white).frame(maxWidth: .infinity).frame(height: 42)
                            .background(MoodTheme.brandAccent).clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }.buttonStyle(.plain).disabled(username.isEmpty || password.isEmpty || accountStore.isLoading)
                } else { loginButton }

                if !accountStore.isConfigured || showMatrixLogin { loginForgotPassword }

                loginSeparator


                loginSignupLink

                Spacer(minLength: 40)

                if !accountStore.isConfigured { loginBranding }
            }
            .padding(.horizontal, 32)
        }
        .scrollDismissesKeyboard(.interactively)
        .safeAreaPadding(.horizontal, 24)
        .background(Color.clear)
    }

    // MARK: - Login Subviews

    private var discordLoginButton: some View {
        Button { Task { await performMoodLogin(discord: true) } } label: {
            Label { Text("Se connecter avec Discord") } icon: {
                Image("DiscordLogo").resizable().scaledToFit()
                    .frame(width: LayoutMetrics.discordLogoSize, height: LayoutMetrics.discordLogoSize)
            }
            .font(.mood(14, weight: .semibold)).foregroundStyle(MoodTheme.textPrimary)
            .frame(maxWidth: .infinity).frame(height: LayoutMetrics.accountButtonHeight)
            .background(MoodTheme.brandBlue)
            .clipShape(RoundedRectangle(cornerRadius: LayoutMetrics.accountCornerRadius))
        }.buttonStyle(.plain).disabled(accountStore.isLoading)
    }

    private var accountLoginForm: some View {
        VStack(spacing: 12) {
            AuthField(icon: "envelope", placeholder: "Adresse e-mail", text: $username)
            SecureField("Mot de passe", text: $password)
                .textFieldStyle(.plain).font(.mood( 14)).foregroundStyle(MoodTheme.textPrimary)
                .padding(14).background(MoodTheme.glassBg).clipShape(RoundedRectangle(cornerRadius: 10))
            Button("Mot de passe oublié ?") { accountStore.beginPasswordRecovery() }
                .font(.mood(13)).foregroundStyle(MoodTheme.brandBlue)
                .buttonStyle(.plain).disabled(accountStore.isLoading)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func performMoodLogin(discord: Bool) async {
        errorMessage = nil
        do {
            if discord { try await accountStore.signInWithDiscord() }
            else { try await accountStore.signIn(email: username, password: password) }
            authState.isLoggedIn = true
        } catch { errorMessage = error.localizedDescription }
    }

    private var loginLogo: some View {
        let fontSize: CGFloat = layoutMode == .compact ? 34 : 44
        return VStack(spacing: 6) {
            HStack(spacing: 0) {
                Text("m")
                    .foregroundStyle(MoodTheme.textPrimary)
                MoodInfinitySymbol(size: fontSize)
                    .offset(y: fontSize * 0.04)
                Text("d")
                    .foregroundStyle(MoodTheme.textPrimary)
            }
            .font(.mood( fontSize, weight: .bold, design: .rounded))

            Text("Connexion à ton compte")
                .font(.mood( layoutMode == .compact ? 13 : 15))
                .foregroundStyle(MoodTheme.textSecondary)
        }
        .padding(.bottom, layoutMode == .compact ? 0 : 32)
    }

    private var loginForm: some View {
        let isCompact = layoutMode == .compact
        let fieldFont: CGFloat = isCompact ? 13 : 14
        let fieldPadH: CGFloat = isCompact ? 12 : 14
        let fieldPadV: CGFloat = isCompact ? 10 : 12

        return VStack(spacing: isCompact ? 12 : 16) {
            if showAdvanced {
                AuthField(
                    icon: "server.rack",
                    placeholder: "Homeserver",
                    text: $homeserver
                )
            }

            AuthField(
                icon: "person",
                placeholder: "Nom d'utilisateur ou email",
                text: $username
            )

            // Password field
            HStack(spacing: 8) {
                Image(systemName: "lock")
                    .font(.mood( isCompact ? 12 : 14))
                    .foregroundStyle(MoodTheme.textMuted)
                    .frame(width: 18)

                if showPassword {
                    TextField("Mot de passe", text: $password)
                        .textFieldStyle(.plain)
                        .font(.mood( fieldFont))
                        .foregroundStyle(MoodTheme.textPrimary)
                } else {
                    SecureField("Mot de passe", text: $password)
                        .textFieldStyle(.plain)
                        .font(.mood( fieldFont))
                        .foregroundStyle(MoodTheme.textPrimary)
                }

                Button {
                    showPassword.toggle()
                } label: {
                    Image(systemName: showPassword ? "eye.slash" : "eye")
                        .font(.mood( isCompact ? 12 : 13))
                        .foregroundStyle(MoodTheme.textMuted)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, fieldPadH)
            .padding(.vertical, fieldPadV)
            .background(MoodTheme.glassBg)
            .clipShape(RoundedRectangle(cornerRadius: layoutMode == .compact ? 14 : 10, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: layoutMode == .compact ? 14 : 10, style: .continuous)
                    .stroke(MoodTheme.glassBorder, lineWidth: 0.5)
            )

            // Advanced toggle
            Button {
                withAnimation(.easeInOut(duration: 0.15)) {
                    showAdvanced.toggle()
                }
            } label: {
                HStack(spacing: 4) {
                    Text("Homeserver avancé")
                        .font(.mood( isCompact ? 11 : 12))
                    Image(systemName: showAdvanced ? "chevron.up" : "chevron.down")
                        .font(.mood( 9, weight: .semibold))
                }
                .foregroundStyle(MoodTheme.textMuted)
            }
            .buttonStyle(.plain)
        }
    }

    @ViewBuilder
    private var loginErrorMessage: some View {
        if let error = errorMessage ?? accountStore.errorMessage {
            MoodNotice(title: "La connexion n’a pas abouti", detail: error,
                secondaryTitle: "Fermer", secondaryAction: { errorMessage = nil; accountStore.errorMessage = nil })
        }
    }

    private var loginButton: some View {
        Button {
            isLoading = true
            errorMessage = nil
            Task {
                do {
                    try await matrixStore.login(
                        username: username,
                        password: password,
                        homeserver: homeserver
                    )
                    isLoading = false
                    authState.isLoggedIn = true
                } catch {
                    isLoading = false
                    errorMessage = error.localizedDescription
                }
            }
        } label: {
            ZStack {
                if isLoading {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .scaleEffect(0.7)
                        .tint(.white)
                } else {
                    Text("Se connecter")
                        .font(.mood( layoutMode == .compact ? 13 : 14, weight: .semibold))
                }
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .frame(height: layoutMode == .compact ? 42 : 48)
            .background(MoodTheme.brandAccent)
            .clipShape(RoundedRectangle(cornerRadius: layoutMode == .compact ? 14 : 12, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(username.isEmpty || password.isEmpty)
        .opacity(username.isEmpty || password.isEmpty ? 0.5 : 1)
    }

    private var loginForgotPassword: some View {
        Button {
            showForgotPassword = true
        } label: {
            Text("Mot de passe oublié ?")
                .font(.mood( layoutMode == .compact ? 12 : 13))
                .foregroundStyle(MoodTheme.brandBlue)
        }
        .buttonStyle(.plain)
        .padding(.bottom, layoutMode == .compact ? 0 : 32)
        .alert("Mot de passe oublié", isPresented: $showForgotPassword) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Contacte l'administrateur de ton homeserver pour réinitialiser ton mot de passe.")
        }
    }

    private var loginSeparator: some View {
        HStack(spacing: 12) {
            DesktopPixelRule()
            Text("ou")
                .font(.mood( layoutMode == .compact ? 11 : 12))
                .foregroundStyle(MoodTheme.textMuted)
            DesktopPixelRule()
        }
        .padding(.bottom, layoutMode == .compact ? 0 : 20)
    }


    private var loginSignupLink: some View {
        HStack(spacing: 4) {
            Text("Pas encore de compte ?")
                .font(.mood( layoutMode == .compact ? 12 : 13))
                .foregroundStyle(MoodTheme.textSecondary)
            Button {
                authState.currentScreen = .signup
            } label: {
                Text("Créer un compte")
                    .font(.mood( layoutMode == .compact ? 12 : 13, weight: .semibold))
                    .foregroundStyle(MoodTheme.brandBlue)
            }
            .buttonStyle(.plain)
        }
        .padding(.bottom, 16)
    }

    private var loginBranding: some View {
        HStack(spacing: 6) {
            Text("Propulsé par")
                .font(.mood( layoutMode == .compact ? 10 : 11))
                .foregroundStyle(MoodTheme.textMuted)
            Text("[matrix]")
                .font(.mood( layoutMode == .compact ? 10 : 11, weight: .bold, design: .monospaced))
                .foregroundStyle(MoodTheme.textSecondary)
        }
        .padding(.bottom, 20)
    }

    private func startGoogleSSO() {
        isSSOLoading = true
        errorMessage = nil

        // Google's SSO provider ID on matrix.org
        let googleIdpId = "oidc-google"
        guard let ssoURL = matrixStore.ssoRedirectURL(
            idpId: googleIdpId,
            homeserver: homeserver,
            redirectURL: ssoCallbackURL
        ) else {
            errorMessage = "Impossible de construire l'URL SSO"
            isSSOLoading = false
            return
        }

        let contextProvider = SSOContextProvider()
        ssoContextProvider = contextProvider

        let session = ASWebAuthenticationSession(
            url: ssoURL,
            callbackURLScheme: ssoCallbackScheme
        ) { callbackURL, error in
            isSSOLoading = false

            if let error {
                if (error as NSError).code == ASWebAuthenticationSessionError.canceledLogin.rawValue {
                    return // User cancelled
                }
                errorMessage = error.localizedDescription
                return
            }

            guard let callbackURL,
                  let components = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false),
                  let loginToken = components.queryItems?.first(where: { $0.name == "loginToken" })?.value
            else {
                errorMessage = "Pas de token reçu du serveur"
                return
            }

            Task {
                do {
                    try await matrixStore.loginWithSSOToken(loginToken, homeserver: homeserver)
                    authState.isLoggedIn = true
                } catch {
                    errorMessage = error.localizedDescription
                }
            }
        }

        session.prefersEphemeralWebBrowserSession = false
        session.presentationContextProvider = contextProvider
        ssoSession = session
        session.start()
    }
}

// MARK: - SSO Context Provider

private class SSOContextProvider: NSObject, ASWebAuthenticationPresentationContextProviding {
    @MainActor
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        if let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let window = scene.windows.first {
            return window
        }
        return ASPresentationAnchor()
    }
}

// MARK: - Signup View

struct SignupView: View {
    @Environment(AccountStore.self) private var accountStore
    @Environment(\.layoutMode) private var layoutMode
    @Bindable var authState: AuthState
    var matrixStore: MatrixStore
    @State private var homeserver = "matrix.org"
    @State private var displayName = ""
    @State private var username = ""
    @State private var email = ""
    @State private var password = ""
    @State private var confirmPassword = ""
    @State private var showPassword = false
    @State private var isLoading = false
    @State private var showAdvanced = false
    @State private var errorMessage: String?
    @State private var isCheckingConfirmation = false
    @State private var confirmationCode = ""
    @State private var confirmationNotice: String?

    private var passwordsMatch: Bool {
        !password.isEmpty && password == confirmPassword
    }

    private var formValid: Bool {
        (accountStore.isConfigured || !username.isEmpty) && !email.isEmpty && passwordsMatch
    }

    private var formWidth: CGFloat { 320 }

    var body: some View {
        ZStack {
            MoodTheme.serverBar.ignoresSafeArea()


            if let pending = accountStore.pendingConfirmationEmail {
                confirmationPanel(pending)
                    .frame(maxWidth: formWidth)
                    .padding(.horizontal, 32)
            } else if layoutMode == .regular {
                desktopSignupContent
            } else {
                compactSignupContent
            }
        }
        .onChange(of: accountStore.isSignedIn) { _, signedIn in
            // The e-mail was confirmed (automatic watch or "J'ai confirmé").
            guard signedIn, !authState.isLoggedIn else { return }
            authState.currentScreen = .login
            authState.isLoggedIn = true
        }
    }

    // MARK: - E-mail confirmation

    private func confirmationPanel(_ email: String) -> some View {
        VStack(spacing: 14) {
            Image(systemName: "envelope.badge")
                .font(.mood(34))
                .foregroundStyle(MoodTheme.brandAccent)
            Text("Vérifie ta boîte mail")
                .font(.mood(20, weight: .bold))
                .foregroundStyle(MoodTheme.textPrimary)
            Text("Entre le code reçu à \(email), ou ouvre le lien sur n’importe quel appareil.")
                .font(.mood(13))
                .foregroundStyle(MoodTheme.textSecondary)
                .multilineTextAlignment(.center)
            EmailCodeField(code: $confirmationCode)
            Button("Confirmer le code") {
                Task {
                    do { try await accountStore.confirmSignup(code: confirmationCode) }
                    catch { accountStore.errorMessage = error.localizedDescription }
                }
            }.buttonStyle(.plain).font(.mood(14, weight: .semibold))
                .foregroundStyle(MoodTheme.brandBlue)
                .disabled(!AccountValidation.isValidEmailCode(confirmationCode) || accountStore.isLoading)
            if let confirmationNotice {
                Text(confirmationNotice).font(.mood(12)).foregroundStyle(MoodTheme.textSecondary)
            }
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("En attente de confirmation…")
                    .font(.mood(12))
                    .foregroundStyle(MoodTheme.textMuted)
            }
            Button {
                Task {
                    isCheckingConfirmation = true
                    await accountStore.completeConfirmedSignUp(manual: true)
                    isCheckingConfirmation = false
                }
            } label: {
                Text(isCheckingConfirmation ? "Vérification…" : "J'ai confirmé mon e-mail")
                    .font(.mood(14, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 42)
                    .background(MoodTheme.brandAccent)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(isCheckingConfirmation || accountStore.isLoading)
            HStack(spacing: 18) {
                Button("Renvoyer le code") { Task { await accountStore.resendConfirmation(); if accountStore.errorMessage == nil { confirmationNotice = "Un nouvel e-mail a été demandé." } } }
                Button("Changer d'adresse") { accountStore.cancelPendingConfirmation() }
            }
            .disabled(accountStore.isLoading)
            .font(.mood(12, weight: .medium))
            .foregroundStyle(MoodTheme.brandBlue)
            .buttonStyle(.plain)
            if let message = accountStore.errorMessage {
                Text(message)
                    .font(.mood(12))
                    .foregroundStyle(MoodTheme.mentionBadge)
                    .multilineTextAlignment(.center)
            }
        }
    }

    // MARK: - Desktop Signup
    private var desktopSignupContent: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 0) {
                Spacer(minLength: 60)
                signupLogo
                signupForm
                    .frame(width: formWidth)
                    .padding(.bottom, 24)
                signupErrorMessage
                    .frame(width: formWidth, alignment: .leading)
                signupButton
                    .frame(width: formWidth)
                    .padding(.bottom, 24)
                signupLoginLink
                Spacer(minLength: 40)
                if !accountStore.isConfigured { signupBranding }
                Spacer(minLength: 40)
            }
            .frame(minHeight: UIScreen.main.bounds.height)
        }
    }

    // MARK: - Compact Signup
    private var compactSignupContent: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 16) {
                signupLogo
                    .padding(.top, 40)

                signupForm

                signupErrorMessage

                signupButton

                signupLoginLink
                    .padding(.top, 4)

                Spacer(minLength: 30)

                if !accountStore.isConfigured { signupBranding }
            }
            .padding(.horizontal, 32)
        }
        .scrollDismissesKeyboard(.interactively)
        .safeAreaPadding(.horizontal, 24)
        .background(Color.clear)
    }

    // MARK: - Signup Subviews

    private var signupLogo: some View {
        let fontSize: CGFloat = layoutMode == .compact ? 34 : 44
        return VStack(spacing: 6) {
            HStack(spacing: 0) {
                Text("m")
                    .foregroundStyle(MoodTheme.textPrimary)
                MoodInfinitySymbol(size: fontSize)
                    .offset(y: fontSize * 0.04)
                Text("d")
                    .foregroundStyle(MoodTheme.textPrimary)
            }
            .font(.mood( fontSize, weight: .bold, design: .rounded))

            Text("Créer ton compte")
                .font(.mood( layoutMode == .compact ? 13 : 15))
                .foregroundStyle(MoodTheme.textSecondary)
        }
        .padding(.bottom, layoutMode == .compact ? 0 : 32)
    }

    private var signupForm: some View {
        let isCompact = layoutMode == .compact
        let fieldFont: CGFloat = isCompact ? 13 : 14
        let fieldPadH: CGFloat = isCompact ? 12 : 14
        let fieldPadV: CGFloat = isCompact ? 10 : 12

        return VStack(spacing: isCompact ? 10 : 14) {
            if showAdvanced {
                AuthField(icon: "server.rack", placeholder: "Homeserver", text: $homeserver)
            }

            if !accountStore.isConfigured {
                AuthField(icon: "face.smiling", placeholder: "Nom d'affichage", text: $displayName)
                AuthField(icon: "person", placeholder: "Nom d'utilisateur", text: $username)
            }
            AuthField(icon: "envelope", placeholder: "Email", text: $email)

            // Password
            HStack(spacing: 8) {
                Image(systemName: "lock")
                    .font(.mood( isCompact ? 12 : 14))
                    .foregroundStyle(MoodTheme.textMuted)
                    .frame(width: 18)

                if showPassword {
                    TextField("Mot de passe", text: $password)
                        .textFieldStyle(.plain)
                        .font(.mood( fieldFont))
                        .foregroundStyle(MoodTheme.textPrimary)
                } else {
                    SecureField("Mot de passe", text: $password)
                        .textFieldStyle(.plain)
                        .font(.mood( fieldFont))
                        .foregroundStyle(MoodTheme.textPrimary)
                }

                Button { showPassword.toggle() } label: {
                    Image(systemName: showPassword ? "eye.slash" : "eye")
                        .font(.mood( isCompact ? 12 : 13))
                        .foregroundStyle(MoodTheme.textMuted)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, fieldPadH)
            .padding(.vertical, fieldPadV)
            .background(MoodTheme.glassBg)
            .clipShape(RoundedRectangle(cornerRadius: layoutMode == .compact ? 14 : 10, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: layoutMode == .compact ? 14 : 10, style: .continuous)
                    .stroke(MoodTheme.glassBorder, lineWidth: 0.5)
            )

            // Confirm password
            HStack(spacing: 8) {
                Image(systemName: "lock.rotation")
                    .font(.mood( isCompact ? 12 : 14))
                    .foregroundStyle(MoodTheme.textMuted)
                    .frame(width: 18)

                SecureField("Confirmer le mot de passe", text: $confirmPassword)
                    .textFieldStyle(.plain)
                    .font(.mood( fieldFont))
                    .foregroundStyle(MoodTheme.textPrimary)

                if !confirmPassword.isEmpty {
                    Image(systemName: passwordsMatch ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .font(.mood( isCompact ? 12 : 13))
                        .foregroundStyle(passwordsMatch ? MoodTheme.onlineGreen : MoodTheme.mentionBadge)
                }
            }
            .padding(.horizontal, fieldPadH)
            .padding(.vertical, fieldPadV)
            .background(MoodTheme.glassBg)
            .clipShape(RoundedRectangle(cornerRadius: layoutMode == .compact ? 14 : 10, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: layoutMode == .compact ? 14 : 10, style: .continuous)
                    .stroke(MoodTheme.glassBorder, lineWidth: 0.5)
            )

            Button {
                withAnimation(.easeInOut(duration: 0.15)) {
                    showAdvanced.toggle()
                }
            } label: {
                HStack(spacing: 4) {
                    Text("Homeserver avancé")
                        .font(.mood( isCompact ? 11 : 12))
                    Image(systemName: showAdvanced ? "chevron.up" : "chevron.down")
                        .font(.mood( 9, weight: .semibold))
                }
                .foregroundStyle(MoodTheme.textMuted)
            }
            .buttonStyle(.plain)
        }
    }

    @ViewBuilder
    private var signupErrorMessage: some View {
        if let error = errorMessage ?? accountStore.errorMessage {
            Text(error)
                .font(.mood( 12))
                .foregroundStyle(MoodTheme.mentionBadge)
                .multilineTextAlignment(.leading)
                .padding(.bottom, 8)
        }
    }

    private var signupButton: some View {
        Button {
            isLoading = true
            errorMessage = nil
            Task {
                do {
                    if accountStore.isConfigured {
                        try await accountStore.signUp(email: email, password: password)
                        // Without a session the address still needs confirming: the panel takes over.
                        if accountStore.isSignedIn {
                            authState.currentScreen = .login
                            authState.isLoggedIn = true
                        }
                    } else {
                        try await matrixStore.register(username: username, password: password, homeserver: homeserver)
                        let name = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
                        if !name.isEmpty { await matrixStore.updateDisplayName(name) }
                        authState.isLoggedIn = true
                    }
                    isLoading = false
                } catch {
                    isLoading = false
                    errorMessage = error.localizedDescription
                }
            }
        } label: {
            ZStack {
                if isLoading {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .scaleEffect(0.7)
                        .tint(.white)
                } else {
                    Text("Créer mon compte")
                        .font(.mood( layoutMode == .compact ? 13 : 14, weight: .semibold))
                }
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .frame(height: layoutMode == .compact ? 40 : 44)
            .background(
                LinearGradient(
                    colors: [MoodTheme.brandAccent, MoodTheme.brandBlue],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .clipShape(RoundedRectangle(cornerRadius: layoutMode == .compact ? 14 : 10, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(!formValid || isLoading)
        .opacity(formValid ? 1 : 0.5)
    }

    private var signupLoginLink: some View {
        HStack(spacing: 4) {
            Text("Déjà un compte ?")
                .font(.mood( layoutMode == .compact ? 12 : 13))
                .foregroundStyle(MoodTheme.textSecondary)
            Button {
                authState.currentScreen = .login
            } label: {
                Text("Se connecter")
                    .font(.mood( layoutMode == .compact ? 12 : 13, weight: .semibold))
                    .foregroundStyle(MoodTheme.brandBlue)
            }
            .buttonStyle(.plain)
        }
        .padding(.bottom, layoutMode == .compact ? 0 : 16)
    }

    private var signupBranding: some View {
        HStack(spacing: 6) {
            Text("Propulsé par")
                .font(.mood( layoutMode == .compact ? 10 : 11))
                .foregroundStyle(MoodTheme.textMuted)
            Text("[matrix]")
                .font(.mood( layoutMode == .compact ? 10 : 11, weight: .bold, design: .monospaced))
                .foregroundStyle(MoodTheme.textSecondary)
        }
        .padding(.bottom, 20)
    }
}

// MARK: - Auth Container

struct AuthContainer: View {
    @Environment(AccountStore.self) private var accountStore
    @Bindable var authState: AuthState
    var matrixStore: MatrixStore

    var body: some View {
        ZStack {
            if accountStore.isRecoveringPassword {
                PasswordRecoveryView(authState: authState)
            } else {
                switch authState.currentScreen {
                case .login: LoginView(authState: authState, matrixStore: matrixStore)
                case .signup: SignupView(authState: authState, matrixStore: matrixStore)
                case .matrixLink: MatrixAccountLinkView(authState: authState, matrixStore: matrixStore)
                }
            }
        }.disabled(AccountAuthPreview.enabled)
    }
}

struct MatrixAccountLinkView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AccountStore.self) private var accountStore
    @Bindable var authState: AuthState
    var matrixStore: MatrixStore
    @State private var homeserver = "matrix.org"
    @State private var username = ""
    @State private var password = ""
    @State private var errorMessage: String?
    @State private var isLoading = false

    var body: some View {
        VStack(spacing: 16) {
            Text("Utiliser un autre compte Matrix").font(.mood( 24, weight: .bold)).foregroundStyle(MoodTheme.textPrimary)
            Text("Ton compte Mood utilise Matrix pour les messages.").font(.mood( 14)).foregroundStyle(MoodTheme.textSecondary)
            AuthField(icon: "server.rack", placeholder: "Homeserver", text: $homeserver)
            AuthField(icon: "person", placeholder: "Nom d'utilisateur Matrix", text: $username)
            SecureField("Mot de passe Matrix", text: $password).padding(14).background(MoodTheme.glassBg).clipShape(RoundedRectangle(cornerRadius: 10))
            if let errorMessage = errorMessage ?? accountStore.errorMessage { Text(errorMessage).foregroundStyle(MoodTheme.mentionBadge).font(.mood(12)) }
            Button { Task { await link() } } label: {
                Text(isLoading ? "Connexion…" : "Relier mon compte Matrix").foregroundStyle(.white).frame(maxWidth: .infinity).frame(height: 46).background(MoodTheme.brandAccent).clipShape(RoundedRectangle(cornerRadius: 10))
            }.buttonStyle(.plain).disabled(isLoading || username.isEmpty || password.isEmpty)
            Button("Fermer") { dismiss() }.disabled(isLoading)
        }.padding(32).frame(maxWidth: 400).background(MoodTheme.serverBar.ignoresSafeArea())
        .onAppear {
            homeserver = accountStore.profile?.matrixHomeserver ?? "matrix.org"
            username = accountStore.profile?.matrixUserId ?? ""
        }
    }

    private func link() async {
        isLoading = true; errorMessage = nil
        do {
            try await matrixStore.login(username: username, password: password, homeserver: homeserver)
            guard let matrixId = matrixStore.userId else { throw AccountError.invalidResponse }
            _ = matrixId
            accountStore.matrixReady = true
            dismiss()
            authState.isLoggedIn = true
        } catch { errorMessage = error.localizedDescription }
        isLoading = false
    }
}

// MARK: - Reusable Components

struct AuthField: View {
    let icon: String
    let placeholder: String
    @Binding var text: String
    @Environment(\.layoutMode) private var layoutMode

    private var fontSize: CGFloat { layoutMode == .compact ? 13 : 14 }
    private var iconSize: CGFloat { layoutMode == .compact ? 12 : 14 }
    private var hPad: CGFloat { layoutMode == .compact ? 12 : 14 }
    private var vPad: CGFloat { layoutMode == .compact ? 10 : 12 }

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.mood( iconSize))
                .foregroundStyle(MoodTheme.textMuted)
                .frame(width: 18)

            TextField(placeholder, text: $text)
                .textFieldStyle(.plain)
                .font(.mood( fontSize))
                .foregroundStyle(MoodTheme.textPrimary)
        }
        .padding(.horizontal, hPad)
        .padding(.vertical, vPad)
        .background(MoodTheme.glassBg)
        .clipShape(RoundedRectangle(cornerRadius: layoutMode == .compact ? 14 : 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: layoutMode == .compact ? 14 : 10, style: .continuous)
                .stroke(MoodTheme.glassBorder, lineWidth: 0.5)
        )
    }
}

struct SSOButton: View {
    var icon: String? = nil
    var customIcon: String? = nil
    let label: String
    var action: () -> Void = {}
    @State private var isHovered = false
    @Environment(\.layoutMode) private var layoutMode

    private var iconFont: CGFloat { layoutMode == .compact ? 13 : 15 }
    private var labelFont: CGFloat { layoutMode == .compact ? 12 : 13 }
    private var btnHeight: CGFloat { layoutMode == .compact ? 38 : 42 }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let icon {
                    Image(systemName: icon)
                        .font(.mood( iconFont))
                } else if let customIcon {
                    Text(customIcon)
                        .font(.mood( iconFont, weight: .bold, design: .rounded))
                }
                Text(label)
                    .font(.mood( labelFont, weight: .medium))
            }
            .foregroundStyle(MoodTheme.textPrimary)
            .frame(maxWidth: .infinity)
            .frame(height: btnHeight)
            .background(isHovered ? MoodTheme.glassHighlight : MoodTheme.glassBg)
            .clipShape(RoundedRectangle(cornerRadius: layoutMode == .compact ? 14 : 10, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: layoutMode == .compact ? 14 : 10, style: .continuous)
                    .stroke(MoodTheme.glassBorder, lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering in isHovered = hovering }
    }
}

#Preview("Login") {
    LoginView(authState: AuthState(), matrixStore: MatrixStore())
        .frame(width: 500, height: 700)
        .environment(AccountStore())
        .preferredColorScheme(.dark)
}

#Preview("Signup") {
    SignupView(authState: AuthState(), matrixStore: MatrixStore())
        .frame(width: 500, height: 800)
        .environment(AccountStore())
        .preferredColorScheme(.dark)
}
