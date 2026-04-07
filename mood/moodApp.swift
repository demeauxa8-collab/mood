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

    var body: some Scene {
        WindowGroup {
            RootView(showSplash: $showSplash, authState: authState, matrixStore: matrixStore)
                .task {
                    if matrixStore.restoreSession() {
                        authState.isLoggedIn = true
                    }
                }
        }
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
        windowScene.titlebar?.titleVisibility = .hidden
        windowScene.titlebar?.toolbarStyle = .unifiedCompact
        windowScene.sizeRestrictions?.minimumSize = CGSize(width: 1200, height: 720)
    }
}
#endif

// MARK: - Root View (reads horizontalSizeClass)

struct RootView: View {
    @Binding var showSplash: Bool
    var authState: AuthState
    var matrixStore: MatrixStore
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    private var layoutMode: LayoutMode {
        horizontalSizeClass == .compact ? .compact : .regular
    }

    var body: some View {
        ZStack {
            if authState.isLoggedIn {
                ContentView()
                    .environment(matrixStore)
                    .environment(authState)
                    .environment(\.layoutMode, layoutMode)
                    .transition(.opacity)
            } else {
                AuthContainer(authState: authState, matrixStore: matrixStore)
                    .environment(\.layoutMode, layoutMode)
                    .transition(.opacity)
            }

            if showSplash {
                SplashScreen {
                    withAnimation(.easeOut(duration: 0.5)) {
                        showSplash = false
                    }
                }
                .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.3), value: authState.isLoggedIn)
        .ignoresSafeArea(layoutMode == .regular ? .all : [])
        .preferredColorScheme(MoodTheme.shared.theme == .light ? .light : .dark)
    }
}

// MARK: - Splash Screen
// Deux points → deviennent deux "o" → se rapprochent et fusionnent en ∞ → "m" et "d" arrivent

struct SplashScreen: View {
    let onFinish: () -> Void

    // Phase 1 : deux points apparaissent (écartés)
    @State private var dotsVisible = false
    // Phase 2 : les points se rapprochent
    @State private var dotsClose = false
    // Phase 3 : les points deviennent le ∞
    @State private var becomeInfinity = false
    // Phase 4 : "m" et "d" apparaissent
    @State private var showM = false
    @State private var showD = false
    // Glow
    @State private var glowOn = false

    private var dotsSpacing: CGFloat {
        dotsClose ? 4 : 30
    }

    var body: some View {
        ZStack {
            MoodTheme.serverBar.ignoresSafeArea()

            // Glow subtil
            Circle()
                .fill(
                    RadialGradient(
                        colors: [MoodTheme.brandAccent.opacity(0.2), Color.clear],
                        center: .center,
                        startRadius: 0,
                        endRadius: 120
                    )
                )
                .frame(width: 240, height: 240)
                .blur(radius: 40)
                .opacity(glowOn ? 1 : 0)

            // Le logo assemblé
            HStack(spacing: 0) {
                // "m"
                Text("m")
                    .font(.system(size: 52, weight: .bold, design: .rounded))
                    .foregroundStyle(MoodTheme.textPrimary)
                    .opacity(showM ? 1 : 0)
                    .offset(x: showM ? 0 : 15)

                // Les deux points qui deviennent un ∞
                ZStack {
                    // Points initiaux (se rapprochent puis disparaissent)
                    HStack(spacing: dotsSpacing) {
                        Circle()
                            .fill(MoodTheme.brandAccent)
                            .frame(width: 12, height: 12)

                        Circle()
                            .fill(MoodTheme.brandBlue)
                            .frame(width: 12, height: 12)
                    }
                    .opacity(becomeInfinity ? 0 : 1)
                    .scaleEffect(becomeInfinity ? 0.3 : 1)

                    // Le symbole ∞ (apparaît quand les points fusionnent)
                    MoodInfinitySymbol(size: 52)
                        .opacity(becomeInfinity ? 1 : 0)
                        .scaleEffect(becomeInfinity ? 1 : 0.2)
                        .offset(y: 2)
                }

                // "d"
                Text("d")
                    .font(.system(size: 52, weight: .bold, design: .rounded))
                    .foregroundStyle(MoodTheme.textPrimary)
                    .opacity(showD ? 1 : 0)
                    .offset(x: showD ? 0 : -15)
            }
            .opacity(dotsVisible ? 1 : 0)
            .scaleEffect(dotsVisible ? 1 : 0.5)
        }
        .onAppear { runAnimation() }
    }

    private func runAnimation() {
        // 1. Les deux points apparaissent (écartés)
        withAnimation(.spring(response: 0.5, dampingFraction: 0.7)) {
            dotsVisible = true
            glowOn = true
        }

        // 2. Les points se rapprochent
        withAnimation(.spring(response: 0.6, dampingFraction: 0.7).delay(0.6)) {
            dotsClose = true
        }

        // 3. Les points se transforment en ∞
        withAnimation(.spring(response: 0.6, dampingFraction: 0.65).delay(1.2)) {
            becomeInfinity = true
        }

        // 4. "m" glisse depuis la gauche
        withAnimation(.spring(response: 0.5, dampingFraction: 0.7).delay(1.9)) {
            showM = true
        }

        // 5. "d" glisse depuis la droite
        withAnimation(.spring(response: 0.5, dampingFraction: 0.7).delay(2.1)) {
            showD = true
        }

        // 6. Fondu vers l'app
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
            onFinish()
        }
    }
}

