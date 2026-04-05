import SwiftUI
import AuthenticationServices
import UIKit

// MARK: - Auth State

@Observable
class AuthState {
    var isLoggedIn = false
    var currentScreen: AuthScreen = .login

    enum AuthScreen {
        case login, signup
    }
}

// MARK: - Login View

struct LoginView: View {
    @Environment(\.layoutMode) private var layoutMode
    @Bindable var authState: AuthState
    var matrixStore: MatrixStore
    @State private var homeserver = "matrix.org"
    @State private var username = ""
    @State private var password = ""
    @State private var showPassword = false
    @State private var isLoading = false
    @State private var showAdvanced = false
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

            // Subtle glow
            Circle()
                .fill(
                    RadialGradient(
                        colors: [MoodTheme.brandAccent.opacity(0.12), Color.clear],
                        center: .center,
                        startRadius: 0,
                        endRadius: 250
                    )
                )
                .frame(width: 500, height: 500)
                .blur(radius: 80)
                .offset(y: -100)

            if layoutMode == .regular {
                desktopLoginContent
            } else {
                compactLoginContent
            }
        }
    }

    // MARK: - Desktop Login
    private var desktopLoginContent: some View {
        VStack(spacing: 0) {
            Spacer()
            loginLogo
            loginForm
                .frame(width: formWidth)
                .padding(.bottom, 24)
            loginErrorMessage
                .frame(width: formWidth, alignment: .leading)
            loginButton
                .frame(width: formWidth)
                .padding(.bottom, 16)
            loginForgotPassword
            loginSeparator
                .frame(width: formWidth)
            loginSSO
            loginSignupLink
            Spacer()
            loginSkip
            loginBranding
        }
    }

    // MARK: - Compact Login
    private var compactLoginContent: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 16) {
                loginLogo
                    .padding(.top, 60)

                loginForm

                loginErrorMessage

                loginButton

                loginForgotPassword

                loginSeparator

                loginSSO

                loginSignupLink

                Spacer(minLength: 40)

                loginSkip
                loginBranding
            }
            .padding(.horizontal, 32)
        }
        .scrollDismissesKeyboard(.interactively)
        .safeAreaPadding(.horizontal, 24)
        .background(Color.clear)
    }

    // MARK: - Login Subviews

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
            .font(.system(size: fontSize, weight: .bold, design: .rounded))

            Text("Connexion à ton compte")
                .font(.system(size: layoutMode == .compact ? 13 : 15))
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
                    .font(.system(size: isCompact ? 12 : 14))
                    .foregroundStyle(MoodTheme.textMuted)
                    .frame(width: 18)

                if showPassword {
                    TextField("Mot de passe", text: $password)
                        .textFieldStyle(.plain)
                        .font(.system(size: fieldFont))
                        .foregroundStyle(MoodTheme.textPrimary)
                } else {
                    SecureField("Mot de passe", text: $password)
                        .textFieldStyle(.plain)
                        .font(.system(size: fieldFont))
                        .foregroundStyle(MoodTheme.textPrimary)
                }

                Button {
                    showPassword.toggle()
                } label: {
                    Image(systemName: showPassword ? "eye.slash" : "eye")
                        .font(.system(size: isCompact ? 12 : 13))
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
                        .font(.system(size: isCompact ? 11 : 12))
                    Image(systemName: showAdvanced ? "chevron.up" : "chevron.down")
                        .font(.system(size: 9, weight: .semibold))
                }
                .foregroundStyle(MoodTheme.textMuted)
            }
            .buttonStyle(.plain)
        }
    }

    @ViewBuilder
    private var loginErrorMessage: some View {
        if let error = errorMessage {
            Text(error)
                .font(.system(size: 12))
                .foregroundStyle(MoodTheme.mentionBadge)
                .multilineTextAlignment(.leading)
                .padding(.bottom, layoutMode == .compact ? 0 : 8)
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
                    withAnimation(.easeOut(duration: 0.3)) {
                        authState.isLoggedIn = true
                    }
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
                        .font(.system(size: layoutMode == .compact ? 13 : 14, weight: .semibold))
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
                .font(.system(size: layoutMode == .compact ? 12 : 13))
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
            Rectangle().fill(MoodTheme.divider).frame(height: 1)
            Text("ou")
                .font(.system(size: layoutMode == .compact ? 11 : 12))
                .foregroundStyle(MoodTheme.textMuted)
            Rectangle().fill(MoodTheme.divider).frame(height: 1)
        }
        .padding(.bottom, layoutMode == .compact ? 0 : 20)
    }

    private var loginSSO: some View {
        HStack(spacing: layoutMode == .compact ? 10 : 12) {
            SSOButton(icon: "apple.logo", label: "Apple") { showSSOAlert = true }
            SSOButton(customIcon: "G", label: "Google") {
                startGoogleSSO()
            }
        }
        .padding(.bottom, layoutMode == .compact ? 0 : 32)
        .alert("Connexion SSO", isPresented: $showSSOAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("La connexion Apple sera disponible dans une prochaine version.")
        }
    }

    private var loginSignupLink: some View {
        HStack(spacing: 4) {
            Text("Pas encore de compte ?")
                .font(.system(size: layoutMode == .compact ? 12 : 13))
                .foregroundStyle(MoodTheme.textSecondary)
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    authState.currentScreen = .signup
                }
            } label: {
                Text("Créer un compte")
                    .font(.system(size: layoutMode == .compact ? 12 : 13, weight: .semibold))
                    .foregroundStyle(MoodTheme.brandBlue)
            }
            .buttonStyle(.plain)
        }
        .padding(.bottom, 16)
    }

    private var loginSkip: some View {
        Button {
            withAnimation(.easeOut(duration: 0.3)) {
                authState.isLoggedIn = true
            }
        } label: {
            Text("Passer →")
                .font(.system(size: layoutMode == .compact ? 12 : 13, weight: .medium))
                .foregroundStyle(MoodTheme.textMuted)
        }
        .buttonStyle(.plain)
        .padding(.bottom, 8)
    }

    private var loginBranding: some View {
        HStack(spacing: 6) {
            Text("Propulsé par")
                .font(.system(size: layoutMode == .compact ? 10 : 11))
                .foregroundStyle(MoodTheme.textMuted)
            Text("[matrix]")
                .font(.system(size: layoutMode == .compact ? 10 : 11, weight: .bold, design: .monospaced))
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
                    withAnimation(.easeOut(duration: 0.3)) {
                        authState.isLoggedIn = true
                    }
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

    private var passwordsMatch: Bool {
        !password.isEmpty && password == confirmPassword
    }

    private var formValid: Bool {
        !username.isEmpty && !email.isEmpty && passwordsMatch
    }

    private var formWidth: CGFloat { 320 }

    var body: some View {
        ZStack {
            MoodTheme.serverBar.ignoresSafeArea()

            Circle()
                .fill(
                    RadialGradient(
                        colors: [MoodTheme.brandBlue.opacity(0.12), Color.clear],
                        center: .center,
                        startRadius: 0,
                        endRadius: 250
                    )
                )
                .frame(width: 500, height: 500)
                .blur(radius: 80)
                .offset(y: -100)

            if layoutMode == .regular {
                desktopSignupContent
            } else {
                compactSignupContent
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
                signupSkip
                signupBranding
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

                signupSkip
                signupBranding
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
            .font(.system(size: fontSize, weight: .bold, design: .rounded))

            Text("Créer ton compte")
                .font(.system(size: layoutMode == .compact ? 13 : 15))
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

            AuthField(icon: "face.smiling", placeholder: "Nom d'affichage", text: $displayName)
            AuthField(icon: "person", placeholder: "Nom d'utilisateur", text: $username)
            AuthField(icon: "envelope", placeholder: "Email", text: $email)

            // Password
            HStack(spacing: 8) {
                Image(systemName: "lock")
                    .font(.system(size: isCompact ? 12 : 14))
                    .foregroundStyle(MoodTheme.textMuted)
                    .frame(width: 18)

                if showPassword {
                    TextField("Mot de passe", text: $password)
                        .textFieldStyle(.plain)
                        .font(.system(size: fieldFont))
                        .foregroundStyle(MoodTheme.textPrimary)
                } else {
                    SecureField("Mot de passe", text: $password)
                        .textFieldStyle(.plain)
                        .font(.system(size: fieldFont))
                        .foregroundStyle(MoodTheme.textPrimary)
                }

                Button { showPassword.toggle() } label: {
                    Image(systemName: showPassword ? "eye.slash" : "eye")
                        .font(.system(size: isCompact ? 12 : 13))
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
                    .font(.system(size: isCompact ? 12 : 14))
                    .foregroundStyle(MoodTheme.textMuted)
                    .frame(width: 18)

                SecureField("Confirmer le mot de passe", text: $confirmPassword)
                    .textFieldStyle(.plain)
                    .font(.system(size: fieldFont))
                    .foregroundStyle(MoodTheme.textPrimary)

                if !confirmPassword.isEmpty {
                    Image(systemName: passwordsMatch ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .font(.system(size: isCompact ? 12 : 13))
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
                        .font(.system(size: isCompact ? 11 : 12))
                    Image(systemName: showAdvanced ? "chevron.up" : "chevron.down")
                        .font(.system(size: 9, weight: .semibold))
                }
                .foregroundStyle(MoodTheme.textMuted)
            }
            .buttonStyle(.plain)
        }
    }

    @ViewBuilder
    private var signupErrorMessage: some View {
        if let error = errorMessage {
            Text(error)
                .font(.system(size: 12))
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
                    try await matrixStore.login(
                        username: username,
                        password: password,
                        homeserver: homeserver
                    )
                    isLoading = false
                    withAnimation(.easeOut(duration: 0.3)) {
                        authState.isLoggedIn = true
                    }
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
                        .font(.system(size: layoutMode == .compact ? 13 : 14, weight: .semibold))
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
        .disabled(!formValid)
        .opacity(formValid ? 1 : 0.5)
    }

    private var signupLoginLink: some View {
        HStack(spacing: 4) {
            Text("Déjà un compte ?")
                .font(.system(size: layoutMode == .compact ? 12 : 13))
                .foregroundStyle(MoodTheme.textSecondary)
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    authState.currentScreen = .login
                }
            } label: {
                Text("Se connecter")
                    .font(.system(size: layoutMode == .compact ? 12 : 13, weight: .semibold))
                    .foregroundStyle(MoodTheme.brandBlue)
            }
            .buttonStyle(.plain)
        }
        .padding(.bottom, layoutMode == .compact ? 0 : 16)
    }

    private var signupSkip: some View {
        Button {
            withAnimation(.easeOut(duration: 0.3)) {
                authState.isLoggedIn = true
            }
        } label: {
            Text("Passer →")
                .font(.system(size: layoutMode == .compact ? 12 : 13, weight: .medium))
                .foregroundStyle(MoodTheme.textMuted)
        }
        .buttonStyle(.plain)
        .padding(.bottom, 8)
    }

    private var signupBranding: some View {
        HStack(spacing: 6) {
            Text("Propulsé par")
                .font(.system(size: layoutMode == .compact ? 10 : 11))
                .foregroundStyle(MoodTheme.textMuted)
            Text("[matrix]")
                .font(.system(size: layoutMode == .compact ? 10 : 11, weight: .bold, design: .monospaced))
                .foregroundStyle(MoodTheme.textSecondary)
        }
        .padding(.bottom, 20)
    }
}

// MARK: - Auth Container

struct AuthContainer: View {
    @Bindable var authState: AuthState
    var matrixStore: MatrixStore

    var body: some View {
        ZStack {
            switch authState.currentScreen {
            case .login:
                LoginView(authState: authState, matrixStore: matrixStore)
                    .transition(.move(edge: .leading).combined(with: .opacity))
            case .signup:
                SignupView(authState: authState, matrixStore: matrixStore)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.25), value: authState.currentScreen)
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
                .font(.system(size: iconSize))
                .foregroundStyle(MoodTheme.textMuted)
                .frame(width: 18)

            TextField(placeholder, text: $text)
                .textFieldStyle(.plain)
                .font(.system(size: fontSize))
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
                        .font(.system(size: iconFont))
                } else if let customIcon {
                    Text(customIcon)
                        .font(.system(size: iconFont, weight: .bold, design: .rounded))
                }
                Text(label)
                    .font(.system(size: labelFont, weight: .medium))
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
        .preferredColorScheme(.dark)
}

#Preview("Signup") {
    SignupView(authState: AuthState(), matrixStore: MatrixStore())
        .frame(width: 500, height: 800)
        .preferredColorScheme(.dark)
}
