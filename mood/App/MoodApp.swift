//
//  moodApp.swift
//  mood
//
//  Created by Augustin  on 27/02/2026.
//

import SwiftUI

@main
struct moodApp: App {
    #if targetEnvironment(macCatalyst)
    @UIApplicationDelegateAdaptor(MacAppDelegate.self) var appDelegate
    #endif
    @State private var showSplash = true
    @State private var authState = AuthState()
    @State private var matrixStore = MatrixStore()
    @State private var accountStore = AccountStore()

    var body: some Scene {
        WindowGroup {
            RootView(showSplash: $showSplash, authState: authState, matrixStore: matrixStore, accountStore: accountStore)
                .id(MobileUIPreviewRoute.shared.screen)
                .onOpenURL { url in
                    guard ProcessInfo.processInfo.arguments.contains("-uiPreview"),
                          url.scheme == "mood", url.host == "ui-preview" else { return }
                    MobileUIPreviewRoute.shared.screen = url.lastPathComponent
                }
                .task {
                    matrixStore.ownMoodUsername = { [accountStore] in accountStore.profile?.username }
                    matrixStore.usernameLookup = { [accountStore] name in
                        guard let client = accountStore.client, accountStore.isSignedIn else { throw AccountError.notConfigured }
                        return try await client.findUser(username: name)
                    }
                    // UI preview mode opens directly on the deterministic mock data.
                    if OnboardingPreview.enabled {
                        // The isolated onboarding review never restores credentials or contacts a service.
                    } else if AccountAuthPreview.enabled {
                        accountStore.prepareAuthPreview()
                        authState.currentScreen = AccountAuthPreview.screen == "signup" ? .signup : .login
                    } else if AccountAuthPreview.isTesting {
                        // Hosted tests must never restore credentials or contact live services.
                    } else if ProcessInfo.processInfo.arguments.contains("-uiPreview") {
                        matrixStore.loadFinishBasicsPreview()
                        authState.isDemoMode = true
                        authState.isLoggedIn = true
                    } else if await accountStore.restore() {
                        OnboardingLifecycle.bootstrap(restoredAccountID: accountStore.session?.user.id.uuidString,
                                                      restoredEmail: accountStore.session?.user.email)
                        authState.isLoggedIn = true
                    } else if !accountStore.isConfigured {
                        if await matrixStore.restoreSession() {
                            OnboardingLifecycle.bootstrap(restoredAccountID: matrixStore.userId)
                            authState.isLoggedIn = true
                        }
                    }
                    if !OnboardingPreview.enabled && !AccountAuthPreview.isTesting && !AccountAuthPreview.enabled && !ProcessInfo.processInfo.arguments.contains("-uiPreview") {
                        OnboardingLifecycle.bootstrap(restoredAccountID: nil)
                    }
                    // The splash only covers session restore — no fixed delay.
                    showSplash = false
                }
        }
        .defaultSize(width: 1600, height: 1000)
    }
}

// MARK: - Mac Catalyst Window Configuration

#if targetEnvironment(macCatalyst)
class MacAppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     configurationForConnecting connectingSceneSession: UISceneSession,
                     options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        let config = UISceneConfiguration(name: nil, sessionRole: connectingSceneSession.role)
        config.delegateClass = MacSceneDelegate.self
        return config
    }
}

class MacSceneDelegate: NSObject, UIWindowSceneDelegate {
    func scene(_ scene: UIScene, willConnectTo session: UISceneSession,
               options connectionOptions: UIScene.ConnectionOptions) {
        guard let windowScene = scene as? UIWindowScene else { return }
        if let titlebar = windowScene.titlebar {
            titlebar.titleVisibility = .hidden
            titlebar.toolbar = nil
            titlebar.separatorStyle = .none
        }
        windowScene.sizeRestrictions?.minimumSize = CGSize(width: 1200, height: 720)
    }
}
#endif

// MARK: - Root View (reads horizontalSizeClass)

struct RootView: View {
    @Binding var showSplash: Bool
    var authState: AuthState
    var matrixStore: MatrixStore
    @Bindable var accountStore: AccountStore
    @State private var onboarding: OnboardingModel?
    @State private var serverActions = ServerActions()
    @State private var modalHost = WindowModalHost()
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    private var layoutMode: LayoutMode {
        horizontalSizeClass == .compact ? .compact : .regular
    }

    var body: some View {
        ZStack {
            if OnboardingPreview.enabled {
                OnboardingReviewScreen(mode: layoutMode)
            } else if let screen = PremiumPreview.screen {
                PremiumPreviewScreen(screen: screen)
            } else if let screen = ConversationPreview.screen {
                ConversationPreviewScreen(screen: screen)
            } else if accountStore.isRecoveringPassword {
                PasswordRecoveryView(authState: authState)
                    .environment(accountStore).environment(\.layoutMode, layoutMode)
                    .disabled(AccountAuthPreview.enabled)
            } else if let onboarding, !onboarding.didFinish {
                OnboardingView(model: onboarding, mode: layoutMode)
            } else if authState.isLoggedIn && accountStore.isSignedIn && !accountStore.matrixReady && matrixStore.userId == nil {
                MoodConnectionView(accountStore: accountStore, matrixStore: matrixStore, authState: authState)
                    .environment(accountStore)
                    .environment(\.layoutMode, layoutMode)
            } else if authState.isLoggedIn {
                ContentView()
                    .windowModalHost(modalHost)
                    .environment(serverActions)
                    .environment(matrixStore)
                    .environment(authState)
                    .environment(accountStore)
                    .environment(\.layoutMode, layoutMode)
                    .sheet(isPresented: $accountStore.showGuildImporter) {
                        DiscordGuildImporter(accountStore: accountStore, matrixStore: matrixStore)
                    }
            } else {
                AuthContainer(authState: authState, matrixStore: matrixStore)
                    .environment(accountStore)
                    .environment(\.layoutMode, layoutMode)
            }

            if showSplash {
                SplashScreen()
            }
        }
        .onChange(of: onboarding?.didFinish) { _, finished in
            if finished == true { authState.isLoggedIn = accountStore.isSignedIn }
        }
        .task(id: showSplash) {
            guard !showSplash else { return }
            configureOnboarding()
        }
        .onChange(of: accountStore.session?.user.id) { oldID, newID in
            if oldID != nil, oldID != newID {
                OnboardingModel.discardProgress(for: oldID?.uuidString)
                onboarding = nil
            }
            // Sign-in/OTP actions adopt their account themselves; do not replace a busy model.
            if newID != nil, let onboarding, onboarding.accountID == nil, onboarding.step == .confirmation {
                Task { await onboarding.acceptConfirmedSession() }
                return
            }
            if onboarding?.isBusy != true { configureOnboarding() }
        }
        .alert("Rejoindre ce serveur ?", isPresented: Binding(
            get: { matrixStore.pendingMessagingInvite != nil },
            set: { if !$0 { matrixStore.pendingMessagingInvite = nil } }
        )) {
            Button("Annuler", role: .cancel) { matrixStore.pendingMessagingInvite = nil }
            Button("Rejoindre") {
                guard let invite = matrixStore.pendingMessagingInvite else { return }
                matrixStore.pendingMessagingInvite = nil
                Task { _ = await matrixStore.joinServer(fromInvite: invite) }
            }
        }
        .onOpenURL { url in
            guard !OnboardingPreview.enabled else { return }
            if ConversationPolicy.target(url) != nil {
                matrixStore.openConversationLink(url)
                return
            }
            if url.scheme == "mood", url.host == "invite", MoodInvite.reference(url.absoluteString) != nil {
                matrixStore.pendingMessagingInvite = url.absoluteString
                return
            }
            guard url.scheme == "mood", url.host == "auth-callback" else { return }
            Task {
                await accountStore.completeEmailCallback(url)
                if accountStore.isSignedIn, let onboarding, onboarding.accountID == nil {
                    await onboarding.acceptConfirmedSession()
                } else {
                    authState.isLoggedIn = accountStore.isSignedIn
                }
            }
        }
        .preferredColorScheme(MoodTheme.shared.theme == .light ? .light : .dark)
    }

    private func configureOnboarding() {
        guard !showSplash, !OnboardingPreview.enabled, !AccountAuthPreview.isTesting, !AccountAuthPreview.enabled,
              ConversationPreview.screen == nil, !authState.isDemoMode,
              !ProcessInfo.processInfo.arguments.contains("-uiPreview") else { return }
        // Keep a legacy Matrix-only session usable when the Mood account service is absent.
        if authState.isLoggedIn && !accountStore.isSignedIn && matrixStore.userId != nil { return }
        let id = accountStore.session?.user.id.uuidString
        if let id, OnboardingModel.isComplete(for: id) { onboarding = nil; return }
        if let onboarding, onboarding.accountID == id { return }
        let actions = OnboardingAdapter(services: .live(account: accountStore, matrix: matrixStore))
        onboarding = OnboardingModel(actions: actions, userID: id)
    }

}

// MARK: - Splash Screen
// Deux points → deviennent deux "o" → se rapprochent et fusionnent en ∞ → "m" et "d" arrivent

// MARK: - Splash Screen
// Static logo shown only while the stored session is being restored,
// like Discord's loading screen.

struct SplashScreen: View {
    var body: some View {
        ZStack {
            MoodTheme.serverBar.ignoresSafeArea()
            MoodInfinityLogo(size: 52)
        }
    }
}

struct MoodConnectionView: View {
    @Bindable var accountStore: AccountStore
    var matrixStore: MatrixStore
    var authState: AuthState
    var body: some View {
        VStack(spacing: LayoutMetrics.mobile(16)) {
            if let error = accountStore.provisioningError {
                Text(error).font(.mood(16)).foregroundStyle(MoodTheme.textPrimary)
                Button("Réessayer") { Task { await accountStore.connectMood(matrixStore: matrixStore) } }
                Button("Déconnexion") {
                    Task { await accountStore.signOut(); matrixStore.logout(); authState.isLoggedIn = false }
                }
            } else {
                ProgressView()
                Text("Connexion à Mood…").font(.mood(16)).foregroundStyle(MoodTheme.textPrimary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(MoodTheme.serverBar)
        .task { await accountStore.connectMood(matrixStore: matrixStore) }
    }
}
