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
                    // UI preview mode opens directly on the deterministic mock data.
                    if ProcessInfo.processInfo.arguments.contains("-uiPreview") {
                        authState.isLoggedIn = true
                    } else if await matrixStore.restoreSession() {
                        authState.isLoggedIn = true
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
            } else {
                AuthContainer(authState: authState, matrixStore: matrixStore)
                    .environment(\.layoutMode, layoutMode)
            }

            if showSplash {
                SplashScreen()
            }
        }
        .preferredColorScheme(MoodTheme.shared.theme == .light ? .light : .dark)
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
