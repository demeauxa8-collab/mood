import SwiftUI
import UniformTypeIdentifiers

// MARK: - Account Settings View

struct AccountSettingsView: View {
    @Environment(MatrixStore.self) private var matrixStore
    @Environment(AccountStore.self) private var accountStore
    @Environment(\.layoutMode) private var layoutMode
    @Environment(\.desktopFriendsCalibration) private var calibrated
    @Binding var isPresented: Bool
    var authState: AuthState?
    @State private var selectedTab: SettingsTab = {
        let args = ProcessInfo.processInfo.arguments
        return args.contains("-uiPreview") && args.contains("profile-settings") ? .profile : .myAccount
    }()
    @State private var compactPath: [SettingsTab] = {
        let args = [MobileUIPreview.screen ?? ""]
        guard ProcessInfo.processInfo.arguments.contains("-uiPreview") else { return [] }
        if args.contains("profile-settings") { return [.profile] }
        for (name, tab) in [("appearance", SettingsTab.appearance), ("privacy", .privacy), ("devices", .appAuth), ("notification-settings", .notifications), ("encryption", .encryption)] {
            if args.contains(name) { return [tab] }
        }
        if args.contains("account") || args.contains("account-credentials") { return [.myAccount] }
        return []
    }()
    @State private var sidebarQuery = ""
    @State private var confirmCompactSignOut = false

    private var desktopTitle: String { selectedTab == .myAccount ? "Compte" : selectedTab.rawValue }

    // Catégories façon Discord
    enum SettingsCategory: String {
        case user = "PARAMÈTRES UTILISATEUR"
        case app = "PARAMÈTRES DE L'APP"
        case security = "CONFIDENTIALITÉ ET SÉCURITÉ"

        /// Header of the group in the desktop (calibrated) sidebar.
        var calibratedTitle: String {
            switch self {
            case .user: return "Compte"
            case .app: return "Expérience"
            case .security: return "Sécurité"
            }
        }
    }

    enum SettingsTab: String, CaseIterable {
        // Paramètres utilisateur
        case myAccount = "Mon compte"
        case profile = "Profil"
        // Paramètres de l'app
        case appearance = "Apparence"
        case keybinds = "Raccourcis clavier"
        case notifications = "Notifications"
        // Confidentialité et sécurité
        case privacy = "Confidentialité & sécurité"
        case appAuth = "Appareils autorisés"
        case encryption = "Chiffrement"

        var icon: String {
            switch self {
            case .myAccount: return "person.circle"
            case .profile: return "person.text.rectangle"
            case .appearance: return "paintbrush"
            case .keybinds: return "keyboard"
            case .notifications: return "bell"
            case .privacy: return "lock.shield"
            case .appAuth: return "checkmark.shield"
            case .encryption: return "key"
            }
        }

        var category: SettingsCategory {
            switch self {
            case .myAccount, .profile:
                return .user
            case .appearance, .keybinds, .notifications:
                return .app
            case .privacy, .appAuth, .encryption:
                return .security
            }
        }
    }

    // Onglets groupés par catégorie
    private var tabsByCategory: [(SettingsCategory, [SettingsTab])] {
        let categories: [SettingsCategory] = [.user, .app, .security]
        return categories.map { cat in
            (cat, SettingsTab.allCases.filter { $0.category == cat })
        }
    }

    var body: some View {
        if calibrated {
            calibratedSettingsLayout
        } else if layoutMode == .regular {
            desktopSettingsLayout
        } else {
            compactSettingsLayout
        }
    }

    private var calibratedSettingsLayout: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                let user = matrixStore.me
                Button { selectedTab = .profile } label: {
                    HStack(spacing: 12) {
                        AvatarGlyph(user: user).font(.mood(24))
                            .frame(width: 48, height: 48)
                            .background(MoodTheme.glassBg).clipShape(Circle())
                        VStack(alignment: .leading, spacing: 4) {
                            CalibratedDesktopText(value: user.displayName, size: 16, weight: .semibold,
                                glyphBackground: DesktopUXPalette.settingsSidebar)
                            CalibratedDesktopText(value: "Modifier le profil", size: 14, color: MoodTheme.textSecondary,
                                glyphBackground: DesktopUXPalette.settingsSidebar)
                        }
                    }
                }
                .buttonStyle(.plain)
                .padding(.leading, 26).padding(.trailing, 24).padding(.top, 24).padding(.bottom, 16)

                HStack(spacing: 11) {
                    CalibratedDesktopSymbol(name: "magnifyingglass", size: 16)
                        .foregroundStyle(MoodTheme.textSupporting)
                    TextField("", text: $sidebarQuery, prompt: Text("Rechercher").foregroundStyle(.clear))
                        .textFieldStyle(.plain).desktopFriendsFont(16)
                        .foregroundStyle(MoodTheme.textPrimary)
                        .accessibilityLabel("Rechercher dans les paramètres")
                        .overlay(alignment: .leading) {
                            if sidebarQuery.isEmpty {
                                CalibratedDesktopText(value: "Rechercher", size: 16, color: DesktopFriendsPalette.placeholder,
                                    glyphBackground: DesktopUXPalette.addInput)
                                    .offset(y: 1)
                                    .allowsHitTesting(false).accessibilityHidden(true)
                            }
                        }
                }
                .padding(.horizontal, 12).frame(height: 40)
                .background(DesktopUXPalette.addInput)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(DesktopFriendsPalette.outline, lineWidth: 1))
                .padding(.leading, 17).padding(.trailing, 16).padding(.bottom, 12)

                ScrollView {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(tabsByCategory, id: \.0.rawValue) { category, tabs in
                            let filtered = tabs.filter { sidebarQuery.isEmpty || $0.rawValue.localizedCaseInsensitiveContains(sidebarQuery)
                                || ($0 == .myAccount && "Compte".localizedCaseInsensitiveContains(sidebarQuery)) }
                            if !filtered.isEmpty {
                                if category != .user {
                                    DesktopPixelRule().padding(.vertical, 12)
                                    CalibratedDesktopText(value: category.calibratedTitle, size: 14,
                                        color: MoodTheme.textSecondary, glyphBackground: DesktopUXPalette.settingsSidebar)
                                        .padding(.horizontal, 8).padding(.bottom, 8)
                                }
                                ForEach(filtered, id: \.self) { tab in
                                    SettingsSidebarItem(tab: tab, isSelected: selectedTab == tab) { selectedTab = tab }
                                }
                            }
                        }
                    }
                    // Déconnexion
                    Button {
                        Task { await accountStore.signOut() }
                        matrixStore.logout()
                        if let authState {
                            authState.isLoggedIn = false
                        }
                        isPresented = false
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "rectangle.portrait.and.arrow.right")
                                .font(.desktopReferenceSystem(size: 13))
                            Text("Déconnexion")
                                .font(.desktopReferenceSystem(size: 13))
                        }
                        .foregroundStyle(MoodTheme.mentionBadge)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                    }
                    .buttonStyle(.plain)
                    .padding(.bottom, 16)
                    .padding(.leading, 17).padding(.trailing, 16)
                }
            }
            .frame(width: 253)
            .background(DesktopUXPalette.settingsSidebar)

            VStack(spacing: 0) {
                HStack {
                    CalibratedDesktopText(value: desktopTitle, size: 16, weight: .medium,
                        color: DesktopFriendsPalette.sidebarPrimary, glyphBackground: DesktopUXPalette.settingsContent)
                    Spacer()
                    Button { isPresented = false } label: {
                        Image(systemName: "xmark").font(.desktopReferenceSystem(size: 14))
                            .foregroundStyle(MoodTheme.textSupporting)
                            .frame(width: 24, height: 24).contentShape(Rectangle())
                    }
                    .buttonStyle(.plain).help("Fermer les paramètres")
                    .keyboardShortcut(.escape, modifiers: [])
                }
                .padding(.leading, 17).padding(.trailing, 16).frame(height: 49)
                DesktopPixelRule(color: DesktopFriendsPalette.rule)
                ScrollView {
                    settingsContent(for: selectedTab)
                        .frame(maxWidth: 744, alignment: .leading)
                        .padding(.top, 40)
                        .frame(maxWidth: .infinity, alignment: .center)
                }
            }
            .background(DesktopUXPalette.settingsContent)
        }
    }

    private var desktopSettingsLayout: some View {
        HStack(spacing: 0) {
            // Sidebar
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(tabsByCategory, id: \.0.rawValue) { category, tabs in
                        Text(category.rawValue)
                            .font(.desktopReferenceSystem(size: 11, weight: .semibold))
                            .tracking(0.4)
                            .foregroundStyle(MoodTheme.textPrimary)
                            .padding(.horizontal, 12)
                            .padding(.top, 16)
                            .padding(.bottom, 4)

                        ForEach(tabs, id: \.self) { tab in
                            SettingsSidebarItem(
                                tab: tab,
                                isSelected: selectedTab == tab
                            ) {
                                selectedTab = tab
                            }
                        }

                        DesktopPixelRule()
                            .padding(.horizontal, 12)
                            .padding(.vertical, 4)
                    }

                    Spacer().frame(height: 8)

                    // Déconnexion
                    Button {
                        Task { await accountStore.signOut() }
                        matrixStore.logout()
                        if let authState {
                            authState.isLoggedIn = false
                        }
                        isPresented = false
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "rectangle.portrait.and.arrow.right")
                                .font(.desktopReferenceSystem(size: 13))
                            Text("Déconnexion")
                                .font(.desktopReferenceSystem(size: 13))
                        }
                        .foregroundStyle(MoodTheme.mentionBadge)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                    }
                    .buttonStyle(.plain)
                    .padding(.bottom, 16)
                }
            }
            .frame(width: 200)
            .background(MoodTheme.channelList)

            DesktopPixelRule(vertical: true)

            // Content
            VStack(spacing: 0) {
                // Top bar with close
                HStack {
                    Text(selectedTab.rawValue)
                        .font(.desktopReferenceSystem(size: 18, weight: .bold))
                        .foregroundStyle(MoodTheme.textPrimary)

                    Spacer()

                    Button {
                        isPresented = false
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.desktopReferenceSystem(size: 20))
                            .foregroundStyle(MoodTheme.textPrimary)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 16)

                DesktopPixelRule()

                // Tab content
                ScrollView(showsIndicators: false) {
                    settingsContent(for: selectedTab)
                }
            }
            .background(MoodTheme.chatBackground)
        }
        .frame(minWidth: 700, minHeight: 500)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var compactSettingsLayout: some View {
        NavigationStack(path: $compactPath) {
            List {
                ForEach(tabsByCategory, id: \.0.rawValue) { category, tabs in
                    Section(category.rawValue) {
                        ForEach(tabs.filter { $0 != .keybinds }, id: \.self) { tab in
                            NavigationLink(value: tab) {
                                Label(tab == .privacy ? "Confidentialité" : tab.rawValue, systemImage: tab.icon).font(.mood(16))
                            }
                        }
                    }.listRowBackground(MoodTheme.inputBg)
                }
                Section {
                    Button("Déconnexion", role: .destructive) { confirmCompactSignOut = true }
                        .foregroundStyle(MoodTheme.mentionBadge)
                }.listRowBackground(MoodTheme.inputBg)
            }.mobileGroupedList()
                .navigationTitle("Paramètres").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .cancellationAction) { MobileCloseButton { isPresented = false } } }
                .navigationDestination(for: SettingsTab.self) { tab in
                    Group {
                        if tab == .myAccount || tab == .profile { settingsContent(for: tab) }
                        else { MobilePreferencesView(tab: tab, onSignOut: signOut) }
                    }
                    .navigationTitle(tab == .privacy ? "Confidentialité" : (tab == .appAuth ? "Appareils" : tab.rawValue))
                    .navigationBarTitleDisplayMode(.inline)
                }
        }
        .tint(MoodTheme.brandAccent)
        .presentationDetents([.large]).presentationDragIndicator(.visible)
        .presentationBackground(MoodTheme.mobileSurface)
        .confirmationDialog("Se déconnecter de Mood ?", isPresented: $confirmCompactSignOut, titleVisibility: .visible) {
            Button("Se déconnecter", role: .destructive, action: signOut)
            Button("Annuler", role: .cancel) {}
        } message: { Text("Les messages non envoyés sur cet appareil seront perdus.") }
    }

    @ViewBuilder
    private func settingsContent(for tab: SettingsTab) -> some View {
        switch tab {
        case .myAccount:
            MyAccountContent(selectedTab: Binding(
                get: { selectedTab },
                set: { value in
                    selectedTab = value
                    if layoutMode != .regular, !calibrated, compactPath.last != value {
                        compactPath.append(value)
                    }
                }
            ))
        case .profile:
            ProfileContent()
        case .privacy:
            PrivacyContent()
        case .appAuth:
            AuthorizedDevicesContent(onSignOut: signOut)
        case .appearance:
            AppearanceContent()
        case .notifications:
            NotificationsContent()
        case .keybinds:
            KeybindsContent()
        case .encryption:
            EncryptionContent()
        }
    }

    /// Same sequence as the "Déconnexion" buttons, for the "Se déconnecter de cet appareil" row.
    private func signOut() {
        Task { await accountStore.signOut() }
        matrixStore.logout()
        if let authState {
            authState.isLoggedIn = false
        }
        isPresented = false
    }
}

// MARK: - Sidebar Item

struct SettingsSidebarItem: View {
    @Environment(\.desktopFriendsCalibration) private var calibrated
    let tab: AccountSettingsView.SettingsTab
    let isSelected: Bool
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: tab.icon)
                    .font(.desktopReferenceSystem(size: 13))
                    .frame(width: 18)
                CalibratedDesktopText(value: calibrated && tab == .myAccount ? "Compte" : tab.rawValue,
                    size: calibrated ? 16 : 13, weight: calibrated ? .medium : .regular,
                    color: isSelected ? MoodTheme.textPrimary : MoodTheme.textSecondary,
                    glyphBackground: calibrated ? (isSelected ? DesktopUXPalette.settingsSelected : isHovered ? MoodTheme.hoverBg : DesktopUXPalette.settingsSidebar) : nil)
                Spacer()
            }
            .foregroundStyle(MoodTheme.textPrimary)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                isSelected ? (calibrated ? DesktopUXPalette.settingsSelected : MoodTheme.selectedBg) :
                isHovered ? MoodTheme.hoverBg : Color.clear
            )
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            .padding(.horizontal, calibrated ? 0 : 8)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityRemoveTraits(isSelected ? [] : .isSelected)
        .onHover { hovering in isHovered = hovering }
    }
}

// MARK: - My Account

struct MyAccountContent: View {
    @Environment(\.layoutMode) private var layoutMode
    @Environment(MatrixStore.self) private var matrixStore
    @Environment(AccountStore.self) private var accountStore
    @Environment(\.desktopFriendsCalibration) private var calibrated
    @Binding var selectedTab: AccountSettingsView.SettingsTab
    @State private var showDeleteConfirm = false
    @State private var showGuildImporter = false
    @State private var accountError: String?
    @State private var isSyncingDiscord = false
    @State private var showUsernameEditor = ProcessInfo.processInfo.arguments.contains("-uiPreview") && ProcessInfo.processInfo.arguments.contains("-uiPreviewUsernameEditor")
    @State private var showAdvancedMatrix = false
    @State private var advancedAuthState = AuthState()
    private var user: MoodUser { matrixStore.me }

    var body: some View {
        Group {
            if layoutMode == .compact { mobileAccountContent } else if calibrated { calibratedAccountContent } else { legacyAccountContent }
        }
        .safeAreaInset(edge: .bottom) {
            if layoutMode == .regular { DisclosureGroup("Avancé") {
                Button("Utiliser un autre compte Matrix") { showAdvancedMatrix = true }
                    .font(.mood(14)).foregroundStyle(MoodTheme.brandBlue)
            }
            .font(.mood(14)).padding(LayoutMetrics.mobile(16)) }
        }
        .sheet(isPresented: $showAdvancedMatrix) {
            MatrixAccountLinkView(authState: advancedAuthState, matrixStore: matrixStore)
                .environment(accountStore)
        }
        .sheet(isPresented: $showUsernameEditor) { UsernameEditor() }
        .task {
            guard !ProcessInfo.processInfo.arguments.contains("-uiPreview") else { return }
            await accountStore.loadProviders()
            if accountStore.discordEnabled { await accountStore.loadDiscordIdentity() }
        }
    }

    private var mobileAccountContent: some View {
        List {
            Section {
                HStack(spacing: LayoutMetrics.mobile(16)) {
                    AvatarGlyph(user: user).font(.mood(32))
                        .frame(width: LayoutMetrics.mobile(64), height: LayoutMetrics.mobile(64))
                        .background(MoodTheme.mobileSurface, in: Circle())
                    VStack(alignment: .leading, spacing: LayoutMetrics.mobile(4)) {
                        Text(user.displayName).font(.mood(20, weight: .semibold)).fixedSize(horizontal: false, vertical: true)
                        if let name = accountStore.moodUsername(for: user, currentUserId: matrixStore.userId) {
                            Text(name).font(.mood(15)).foregroundStyle(MoodTheme.textSecondary)
                        }
                    }
                }.padding(.vertical, LayoutMetrics.mobile(8))
                Button("Modifier mon profil") { selectedTab = .profile }.frame(minHeight: LayoutMetrics.mobile(44))
                Button("Modifier mon nom d’utilisateur") { showUsernameEditor = true }.frame(minHeight: LayoutMetrics.mobile(44))
            }.listRowBackground(MoodTheme.inputBg)
            Section("Adresse e-mail") {
                Text(accountStore.email ?? "Mode démonstration").font(.mood(16)).textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }.listRowBackground(MoodTheme.inputBg)
            if accountStore.isSignedIn || MobileUIPreview.screen == "account-credentials" {
                Section {
                    NavigationLink("E-mail et mot de passe") {
                        AccountCredentialsView().disabled(!accountStore.isSignedIn)
                            .navigationTitle("Identifiants").navigationBarTitleDisplayMode(.inline)
                    }
                }.listRowBackground(MoodTheme.inputBg)
            }
            if accountStore.isSignedIn && accountStore.discordEnabled {
                Section("Discord") { discordAccountContent }.listRowBackground(MoodTheme.inputBg)
            }
        }.mobileGroupedList()
    }

    private var calibratedAccountContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            accountHeading("Infos du compte")
            accountRow("Nom du profil", value: user.displayName, buttonLabel: "Profil", action: { selectedTab = .profile })
            accountRow("Nom d’utilisateur", value: accountStore.moodUsername(for: user, currentUserId: matrixStore.userId) ?? "Non défini", action: { showUsernameEditor = true })
            accountRow("Nom d’affichage", value: user.displayName, action: { selectedTab = .profile })
            DesktopPixelRule(color: DesktopFriendsPalette.rule).padding(.vertical, 36)
            accountHeading("Compte Mood")
            accountRow("Email", value: accountStore.email ?? "Compte Mood non connecté")
            discordAccountContent
            accountCredentialsContent
            DesktopPixelRule(color: DesktopFriendsPalette.rule).padding(.vertical, 36)
            Text("Gère les informations de ton compte Mood.")
                .desktopFriendsFont(14).foregroundStyle(MoodTheme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(24)
        .offset(y: -2)
    }

    @ViewBuilder
    private var accountCredentialsContent: some View {
        if accountStore.isSignedIn || (ProcessInfo.processInfo.arguments.contains("-uiPreview") && ProcessInfo.processInfo.arguments.contains("account-credentials")) {
            AccountCredentialsView().disabled(!accountStore.isSignedIn)
        }
    }

    @ViewBuilder
    private var discordAccountContent: some View {
            if accountStore.isSignedIn && accountStore.discordEnabled {
                SettingsSection(title: "DISCORD") {
                    HStack(spacing: 12) {
                        if let url = accountStore.discord?.avatarURL ?? accountStore.profile?.discordAvatarURL.flatMap(URL.init(string:)) { AsyncImage(url: url) { $0.resizable().scaledToFill() } placeholder: { Circle().fill(MoodTheme.glassBg) }.frame(width: 42, height: 42).clipShape(Circle()) }
                        VStack(alignment: .leading, spacing: 3) {
                            Text(accountStore.discord?.displayName ?? accountStore.profile?.discordUsername ?? "Non relié").font(.system(size: 14, weight: .semibold)).foregroundStyle(MoodTheme.textPrimary)
                            Text(accountStore.discord?.username ?? "Connecte-toi avec Discord pour synchroniser").font(.system(size: 12)).foregroundStyle(MoodTheme.textSecondary)
                        }
                        Spacer()
                        Button("Synchroniser") { Task { isSyncingDiscord = true; do { try await accountStore.synchronizeDiscord() } catch { accountError = error.localizedDescription }; isSyncingDiscord = false } }.buttonStyle(.bordered).disabled(isSyncingDiscord)
                    }
                    Button("Délier Discord") { Task { do { try await accountStore.unlinkDiscord() } catch { accountError = error.localizedDescription } } }.disabled(accountStore.profile?.discordId == nil)
                    HStack {
                        Button("Importer mes serveurs Discord") { Task { do { try await accountStore.refreshGuilds(); showGuildImporter = true } catch { accountError = error.localizedDescription } } }.buttonStyle(.bordered)
                        Button("Utiliser mon profil Discord") { Task { await applyDiscordProfile() } }.buttonStyle(.bordered).disabled(accountStore.discord == nil)
                    }
                    if let accountError { Text(accountError).font(.system(size: 12)).foregroundStyle(MoodTheme.mentionBadge) }
                }
                .sheet(isPresented: $showGuildImporter) { DiscordGuildImporter(accountStore: accountStore, matrixStore: matrixStore) }
            }


    }

    private func accountHeading(_ title: String) -> some View {
        CalibratedDesktopText(value: title, size: 24, weight: .regular,
            glyphBackground: DesktopUXPalette.settingsContent)
            .padding(.bottom, 16)
    }

    private func accountRow(_ label: String, value: String, buttonLabel: String = "Modifier", action: (() -> Void)? = nil) -> some View {
        HStack(spacing: 16) {
            CalibratedDesktopText(value: label, size: 16, weight: .medium,
                glyphBackground: DesktopUXPalette.settingsContent)
            Spacer(minLength: 16)
            CalibratedDesktopText(value: value, size: 16, weight: .medium, color: MoodTheme.textSupporting,
                glyphBackground: DesktopUXPalette.settingsContent)
                .lineLimit(1)
            if let action {
                Button(action: action) {
                    CalibratedDesktopText(value: buttonLabel, size: 14, weight: .medium,
                        glyphBackground: DesktopUXPalette.settingsSelected)
                        .frame(width: 100, height: 40)
                        .background(DesktopUXPalette.settingsSelected)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(buttonLabel) \(label.lowercased())")
            }
        }
        .frame(height: 72)
    }

    private var legacyAccountContent: some View {
        VStack(alignment: .leading, spacing: 20) {
            // User card
            VStack(spacing: 0) {
                // Banner
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [MoodTheme.brandAccent, MoodTheme.brandBlue],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(height: 80)

                HStack(spacing: 14) {
                    // Avatar
                    ZStack(alignment: .bottomTrailing) {
                        AvatarGlyph(user: user)
                            .font(.desktopReferenceSystem(size: 34))
                            .frame(width: 70, height: 70)
                            .background(MoodTheme.glassBg)
                            .clipShape(Circle())
                            .overlay(
                                Circle()
                                    .stroke(MoodTheme.chatBackground, lineWidth: 4)
                            )
                            .offset(y: -20)

                        StatusIndicator(status: user.status, size: 16, borderColor: MoodTheme.chatBackground)
                            .offset(x: 2, y: -18)
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        Text(user.displayName)
                            .font(.desktopReferenceSystem(size: 18, weight: .bold))
                            .foregroundStyle(MoodTheme.textPrimary)

                        Text(user.displayName)
                            .font(.desktopReferenceSystem(size: 13))
                            .foregroundStyle(MoodTheme.textSecondary)
                    }
                    .offset(y: -10)

                    Spacer()

                    Button { selectedTab = .profile } label: {
                        Text("Modifier le profil")
                            .font(.desktopReferenceSystem(size: 12, weight: .semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 7)
                            .background(MoodTheme.brandAccent)
                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .offset(y: -10)
                }
                .padding(.horizontal, 16)
            }
            .background(MoodTheme.glassBg)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(MoodTheme.glassBorder, lineWidth: 0.5)
            )

            // Fields
            SettingsSection(title: "NOM DU PROFIL") {
                SettingsField(value: user.displayName, buttonLabel: nil)
            }

            SettingsSection(title: "EMAIL") {
                SettingsField(value: accountStore.email ?? "Compte Mood non connecté", buttonLabel: nil)
            }

            SettingsSection(title: "NOM D’UTILISATEUR") {
                HStack {
                    Text(accountStore.moodUsername(for: user, currentUserId: matrixStore.userId) ?? "Non défini")
                        .font(.mood(14)).foregroundStyle(MoodTheme.textPrimary)
                    Spacer()
                    Button("Modifier") { showUsernameEditor = true }.font(.mood(14))
                }
            }

            discordAccountContent
            accountCredentialsContent
        }
        .padding(24)
    }

    private func applyDiscordProfile() async {
        do { try await accountStore.applyDiscordProfile(matrixStore: matrixStore) }
        catch { accountError = error.localizedDescription }
    }
}

struct DiscordGuildImporter: View {
    @Environment(\.layoutMode) private var layoutMode
    @Environment(\.dismiss) private var dismiss
    var accountStore: AccountStore
    var matrixStore: MatrixStore
    @State private var selected: Set<String> = []
    @State private var importing = false
    @State private var errorMessage: String?
    var body: some View {
        if layoutMode == .compact { mobileBody } else { desktopBody }
    }
    private var mobileBody: some View {
        MobileSheet(title: "Importer de Discord", onClose: { dismiss() }) {
            List {
                Section {
                    Text("Mood importe le nom et l’icône des serveurs, sans leurs messages.").font(.mood(15)).foregroundStyle(MoodTheme.textSecondary)
                }.listRowBackground(MoodTheme.inputBg)
                Section("Serveurs") {
                    if accountStore.guilds.isEmpty { Text("Aucun serveur à importer.").foregroundStyle(MoodTheme.textSecondary) }
                    ForEach(accountStore.guilds) { guild in
                        Button {
                            if selected.contains(guild.id) { selected.remove(guild.id) } else { selected.insert(guild.id) }
                        } label: {
                            HStack {
                                Text(guild.name).fixedSize(horizontal: false, vertical: true)
                                Spacer()
                                if accountStore.importedGuildIds.contains(guild.id) { Text("Déjà importé").font(.mood(14)).foregroundStyle(MoodTheme.textSecondary) }
                                else { Image(systemName: selected.contains(guild.id) ? "checkmark.circle.fill" : "circle").foregroundStyle(MoodTheme.brandAccent) }
                            }.foregroundStyle(MoodTheme.textPrimary).frame(minHeight: LayoutMetrics.mobile(44))
                        }.buttonStyle(.plain).disabled(importing || accountStore.importedGuildIds.contains(guild.id))
                    }
                }.listRowBackground(MoodTheme.inputBg)
                if let errorMessage { Section { Text(errorMessage).foregroundStyle(MoodTheme.mentionBadge) }.listRowBackground(MoodTheme.inputBg) }
                Section {
                    Button(importing ? "Importation…" : "Importer (\(selected.count))") { Task { await importSelected() } }
                        .buttonStyle(MobilePrimaryButtonStyle()).disabled(selected.isEmpty || importing)
                }.listRowBackground(MoodTheme.mobileSurface).listRowInsets(EdgeInsets())
            }.mobileGroupedList()
        }.interactiveDismissDisabled(importing)
    }
    private var desktopBody: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Importer mes serveurs Discord").font(.system(size: 20, weight: .bold))
            Text("Mood importe uniquement le nom et l’icône des serveurs.").font(.system(size: 13)).foregroundStyle(MoodTheme.textSecondary)
            List(accountStore.guilds) { guild in
                Button { if selected.contains(guild.id) { selected.remove(guild.id) } else { selected.insert(guild.id) } } label: {
                    HStack(spacing: 10) {
                        if let url = guild.iconURL { AsyncImage(url: url) { $0.resizable().scaledToFill() } placeholder: { Circle().fill(MoodTheme.glassBg) }.frame(width: 34, height: 34).clipShape(Circle()) }
                        else { Image(systemName: "person.3.fill").frame(width: 34, height: 34).background(MoodTheme.glassBg).clipShape(Circle()) }
                        Text(guild.name).foregroundStyle(MoodTheme.textPrimary)
                        if accountStore.importedGuildIds.contains(guild.id) { Text("Déjà importé").font(.mood(11)).foregroundStyle(MoodTheme.textMuted) }
                        Spacer()
                        Image(systemName: selected.contains(guild.id) ? "checkmark.circle.fill" : "circle").foregroundStyle(selected.contains(guild.id) ? MoodTheme.brandBlue : MoodTheme.textMuted)
                    }
                }.buttonStyle(.plain).disabled(importing || accountStore.importedGuildIds.contains(guild.id))
            }
            if let errorMessage { Text(errorMessage).font(.system(size: 12)).foregroundStyle(MoodTheme.mentionBadge) }
            HStack { Button("Annuler") { dismiss() }.disabled(importing); Spacer(); Button(importing ? "Importation…" : "Importer (\(selected.count))") { Task { await importSelected() } }.disabled(selected.isEmpty || importing) }
        }.padding(20).frame(maxWidth: 560, minHeight: 480).background(MoodTheme.chatBackground)
    }
    private func importSelected() async {
        importing = true; errorMessage = nil
        for guild in accountStore.guilds where selected.contains(guild.id) && !accountStore.importedGuildIds.contains(guild.id) {
            do { try await accountStore.importGuild(guild, matrixStore: matrixStore); selected.remove(guild.id) }
            catch { errorMessage = error.localizedDescription; break }
        }
        importing = false
        if errorMessage == nil { dismiss() }
    }
}

// MARK: - Profile Content

struct ProfileContent: View {
    @Environment(\.layoutMode) private var layoutMode
    @Environment(MatrixStore.self) private var matrixStore
    @State private var displayName = ""
    @State private var savedDisplayName = ""
    @State private var isPickingAvatar = false
    @State private var isSaving = false
    @State private var saveError: String?
    private var user: MoodUser { matrixStore.me }

    private var hasChanges: Bool {
        displayName.trimmingCharacters(in: .whitespaces) != savedDisplayName
    }

    var body: some View {
        if layoutMode == .compact { mobileBody } else { desktopBody }
    }

    private var mobileBody: some View {
        List {
            Section("Nom d’affichage") {
                TextField("Ton nom", text: $displayName, axis: .vertical).lineLimit(1...3)
                if let saveError { MoodNotice(title: "Le profil n’a pas été enregistré", detail: saveError, secondaryTitle: "Fermer", secondaryAction: { self.saveError = nil }) }
            }.listRowBackground(MoodTheme.inputBg)
            Section("Avatar") {
                HStack(spacing: LayoutMetrics.mobile(16)) {
                    AvatarGlyph(user: user).font(.mood(30))
                        .frame(width: LayoutMetrics.mobile(64), height: LayoutMetrics.mobile(64))
                        .background(MoodTheme.mobileSurface, in: Circle())
                    Button("Changer l’avatar") { isPickingAvatar = true }.frame(minHeight: LayoutMetrics.mobile(44))
                }
            }.listRowBackground(MoodTheme.inputBg)
            if hasChanges {
                Section {
                    Button(isSaving ? "Enregistrement…" : "Enregistrer le nom", action: save)
                        .buttonStyle(MobilePrimaryButtonStyle()).disabled(isSaving || displayName.trimmingCharacters(in: .whitespaces).isEmpty)
                    Button("Réinitialiser") { displayName = savedDisplayName }.frame(minHeight: LayoutMetrics.mobile(44))
                }.listRowBackground(MoodTheme.mobileSurface)
            }
            Section { ExtendedProfileEditor() }.listRowBackground(MoodTheme.inputBg)
            if !user.badges.isEmpty {
                Section("Badges") { ForEach(user.badges, id: \.self) { Text($0).foregroundStyle(MoodTheme.brandAccent) } }.listRowBackground(MoodTheme.inputBg)
            }
        }.mobileGroupedList()
        .onAppear { displayName = user.displayName; savedDisplayName = user.displayName }
        .fileImporter(isPresented: $isPickingAvatar, allowedContentTypes: [.image]) { result in
            guard case .success(let url) = result else { return }
            Task { await uploadAvatar(from: url) }
        }
    }

    private var desktopBody: some View {
        VStack(alignment: .leading, spacing: 20) {
            SettingsSection(title: "NOM D'AFFICHAGE") {
                TextField("Nom d'affichage", text: $displayName)
                    .textFieldStyle(.plain)
                    .font(.desktopReferenceSystem(size: 14))
                    .foregroundStyle(MoodTheme.textPrimary)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(MoodTheme.glassBg)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(MoodTheme.glassBorder, lineWidth: 0.5)
                    )
                if let saveError {
                    MoodNotice(title: "Le profil n’a pas été enregistré", detail: saveError, secondaryTitle: "Fermer", secondaryAction: { self.saveError = nil })
                }
            }

            SettingsSection(title: "AVATAR") {
                HStack(spacing: 14) {
                    AvatarGlyph(user: user)
                        .font(.desktopReferenceSystem(size: 30))
                        .frame(width: 60, height: 60)
                        .background(MoodTheme.glassBg)
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

                    Button {
                        isPickingAvatar = true
                    } label: {
                        Text("Changer l'avatar")
                            .font(.desktopReferenceSystem(size: 13, weight: .semibold))
                            .foregroundStyle(MoodTheme.brandBlue)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(MoodTheme.glassBg)
                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .stroke(MoodTheme.glassBorder, lineWidth: 0.5)
                            )
                    }
                    .buttonStyle(.plain)
                    .fileImporter(isPresented: $isPickingAvatar, allowedContentTypes: [.image]) { result in
                        guard case .success(let url) = result else { return }
                        Task { await uploadAvatar(from: url) }
                    }
                }
            }

            ExtendedProfileEditor()

            SettingsSection(title: "BADGES") {
                HStack(spacing: 8) {
                    ForEach(user.badges, id: \.self) { badge in
                        Text(badge)
                            .font(.desktopReferenceSystem(size: 12, weight: .medium))
                            .foregroundStyle(MoodTheme.brandAccent)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(MoodTheme.brandAccent.opacity(0.12))
                            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                    }
                }
            }

            Spacer()
        }
        .padding(24)
        .safeAreaInset(edge: .bottom) {
            if hasChanges {
                UnsavedChangesBar(isSaving: isSaving, onReset: { displayName = savedDisplayName }, onSave: save)
                    .padding(.horizontal, 24)
                    .padding(.bottom, 16)
                    .transition(.opacity)
            }
        }
        .animation(MoodMotion.popover, value: hasChanges)
        .onAppear {
            displayName = user.displayName
            savedDisplayName = user.displayName
        }
    }

    private func save() {
        let name = displayName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty, !isSaving else { return }
        isSaving = true
        saveError = nil
        Task {
            let saved = await matrixStore.updateDisplayName(name)
            isSaving = false
            if saved {
                savedDisplayName = name
                displayName = name
            } else {
                saveError = matrixStore.errorMessage ?? "Impossible de changer le nom."
            }
        }
    }

    private func uploadAvatar(from url: URL) async {
        let didAccess = url.startAccessingSecurityScopedResource()
        defer { if didAccess { url.stopAccessingSecurityScopedResource() } }
        saveError = nil
        guard let data = try? Data(contentsOf: url) else {
            saveError = "Impossible de lire l'image \(url.lastPathComponent)."
            return
        }
        if !(await matrixStore.updateAvatar(imageData: data, filename: url.lastPathComponent)) {
            saveError = matrixStore.errorMessage ?? "Mise à jour de l'avatar échouée."
        }
    }
}

// MARK: - Privacy Content

/// What other people can see about you. Both switches change what Mood sends to the server.
struct PrivacyContent: View {
    @Environment(MatrixStore.self) private var matrixStore

    private var readReceipts: Binding<Bool> {
        Binding(get: { matrixStore.preferences.sendsReadReceipts },
                set: { value in matrixStore.updatePreferences { $0.sendsReadReceipts = value } })
    }

    private var typingIndicator: Binding<Bool> {
        Binding(get: { matrixStore.preferences.sendsTypingIndicator },
                set: { value in matrixStore.updatePreferences { $0.sendsTypingIndicator = value } })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            SettingsToggle(title: "Confirmations de lecture",
                           subtitle: "Les autres voient quand tu as lu un message. Désactivé, ta lecture reste privée.",
                           isOn: readReceipts)
            SettingsToggle(title: "Indicateur de frappe",
                           subtitle: "Les autres voient quand tu es en train d’écrire. Désactivé, il n’est jamais envoyé.",
                           isOn: typingIndicator)
            Text("Ces choix sont enregistrés pour ce compte, sur cet appareil.")
                .font(.desktopReferenceSystem(size: 12))
                .foregroundStyle(MoodTheme.textSecondary)
        }
        .padding(24)
        .task { matrixStore.refreshPreferencesIfNeeded() }
    }
}

// MARK: - Authorized Devices

/// The sessions of this account. Signing another one out needs the account password, which Mood manages
/// itself and the user never sees, so only the current device can be signed out from here.
struct AuthorizedDevicesContent: View {
    @Environment(MatrixStore.self) private var matrixStore
    var onSignOut: () -> Void
    @State private var confirmSignOut = false

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Les appareils connectés à ton compte.")
                .font(.desktopReferenceSystem(size: 14))
                .foregroundStyle(MoodTheme.textSecondary)

            if matrixStore.userId == nil {
                note("Connecte-toi pour voir tes appareils.")
            } else if matrixStore.devices.isEmpty {
                switch matrixStore.devicesState {
                case .failed(let message):
                    VStack(alignment: .leading, spacing: 10) {
                        note("Impossible de charger les appareils : \(message)")
                        Button("Réessayer") { Task { await matrixStore.refreshDevices() } }
                            .buttonStyle(.bordered)
                    }
                case .loaded:
                    note("Aucun appareil à afficher.")
                case .idle, .loading:
                    ProgressView().frame(maxWidth: .infinity, alignment: .leading)
                }
            } else {
                ForEach(matrixStore.devices) { device in
                    deviceRow(device)
                }
                if matrixStore.devices.contains(where: { $0.deviceId != matrixStore.currentDeviceId }) {
                    note("Pour déconnecter un autre appareil, ouvre Mood dessus et déconnecte-toi depuis ses paramètres.")
                }
            }
        }
        .padding(24)
        .task { await matrixStore.refreshDevices() }
        .confirmationDialog("Se déconnecter de cet appareil ?", isPresented: $confirmSignOut, titleVisibility: .visible) {
            Button("Se déconnecter", role: .destructive, action: onSignOut)
            Button("Annuler", role: .cancel) {}
        } message: {
            Text("Les messages non envoyés de cet appareil seront perdus.")
        }
    }

    private func note(_ text: String) -> some View {
        Text(text)
            .font(.desktopReferenceSystem(size: 12))
            .foregroundStyle(MoodTheme.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func symbol(for device: MatrixDevice) -> String {
        let name = device.title.lowercased()
        if name.contains("iphone") { return "iphone" }
        if name.contains("ipad") { return "ipad" }
        if name.contains("mac") { return "laptopcomputer" }
        return "desktopcomputer"
    }

    private func lastSeen(_ device: MatrixDevice) -> String {
        guard let date = device.lastSeenDate else { return "Dernière activité inconnue" }
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = Locale(identifier: "fr_FR")
        formatter.unitsStyle = .full
        return "Dernière activité : " + formatter.localizedString(for: date, relativeTo: Date())
    }

    private func deviceRow(_ device: MatrixDevice) -> some View {
        let isCurrent = device.deviceId == matrixStore.currentDeviceId
        return HStack(spacing: 12) {
            Image(systemName: symbol(for: device))
                .font(.desktopReferenceSystem(size: 20))
                .foregroundStyle(isCurrent ? MoodTheme.onlineGreen : MoodTheme.textSecondary)
                .frame(width: 40, height: 40)
                .background(MoodTheme.glassBg)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text(device.title)
                    .font(.desktopReferenceSystem(size: 14, weight: .medium))
                    .foregroundStyle(MoodTheme.textPrimary)
                Text(isCurrent ? "Cet appareil · actif" : lastSeen(device))
                    .font(.desktopReferenceSystem(size: 12))
                    .foregroundStyle(MoodTheme.textSecondary)
            }

            Spacer()

            if isCurrent {
                Button { confirmSignOut = true } label: {
                    Text("Se déconnecter")
                        .font(.desktopReferenceSystem(size: 12, weight: .semibold))
                        .foregroundStyle(MoodTheme.mentionBadge)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(MoodTheme.mentionBadge.opacity(0.12))
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(14)
        .background(MoodTheme.glassBg)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(MoodTheme.glassBorder, lineWidth: 0.5)
        )
    }
}

// MARK: - Notifications Content

struct NotificationsContent: View {
    @Environment(MatrixStore.self) private var matrixStore

    private var enabled: Binding<Bool> {
        Binding(get: { matrixStore.preferences.notificationsEnabled },
                set: { value in Task { await matrixStore.setNotificationsEnabled(value) } })
    }

    private var sounds: Binding<Bool> {
        Binding(get: { matrixStore.preferences.soundsEnabled },
                set: { value in matrixStore.updatePreferences { $0.soundsEnabled = value } })
    }

    private var badge: Binding<Bool> {
        Binding(get: { matrixStore.preferences.badgeEnabled },
                set: { value in Task { await matrixStore.setBadgeEnabled(value) } })
    }

    /// Muted rooms Mood can show, with where they live.
    private var mutedRooms: [(roomId: String, title: String)] {
        matrixStore.mutedRoomIds.compactMap { roomId in
            guard let destination = matrixStore.destination(forRoomId: roomId) else { return nil }
            let title = destination.serverName.map { "#\(destination.title) · \($0)" } ?? destination.title
            return (roomId, title)
        }
        .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            SettingsToggle(title: "Activer les notifications",
                           subtitle: "Une bannière à chaque nouveau message, sauf dans la conversation que tu regardes.",
                           isOn: enabled)
            if matrixStore.notificationAuthorization == .denied {
                MoodPermissionNotice(permission: .notifications)
            }
            SettingsToggle(title: "Sons", subtitle: "Jouer un son avec chaque notification.", isOn: sounds)
            SettingsToggle(title: "Pastille sur l’icône",
                           subtitle: "Affiche le nombre de mentions et de messages privés non lus.",
                           isOn: badge)

            DesktopPixelRule().padding(.vertical, 4)

            SettingsSection(title: "SALONS EN SOURDINE") {
                if mutedRooms.isEmpty {
                    Text("Aucun. Clic droit sur un salon ou une conversation, puis « Rendre muet ».")
                        .font(.desktopReferenceSystem(size: 13))
                        .foregroundStyle(MoodTheme.textSecondary)
                } else {
                    VStack(spacing: 8) {
                        ForEach(mutedRooms, id: \.roomId) { room in
                            HStack {
                                Text(room.title)
                                    .font(.desktopReferenceSystem(size: 14))
                                    .foregroundStyle(MoodTheme.textPrimary)
                                    .lineLimit(1)
                                Spacer()
                                Button("Rétablir le son") {
                                    Task { await matrixStore.setMuted(false, roomId: room.roomId) }
                                }
                                .buttonStyle(.bordered)
                            }
                            .padding(12)
                            .background(MoodTheme.glassBg)
                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        }
                    }
                }
            }

            Text("Les notifications arrivent tant que Mood est ouvert, au premier plan ou en arrière-plan. Mood fermé, rien n’est envoyé pour l’instant.")
                .font(.desktopReferenceSystem(size: 12))
                .foregroundStyle(MoodTheme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(24)
        .task {
            matrixStore.refreshPreferencesIfNeeded()
            await matrixStore.refreshNotificationAuthorization()
        }
    }
}

// MARK: - Appearance Content (thèmes fonctionnels)

struct AppearanceContent: View {
    private var themeManager: ThemeManager { MoodTheme.shared }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            SettingsSection(title: "THÈME") {
                HStack(spacing: 12) {
                    ThemeCard(
                        name: "Sombre",
                        colors: [Color(hex: "000000"), Color(hex: "0a0a0a")],
                        isSelected: themeManager.theme == .dark
                    ) {
                        themeManager.theme = .dark
                    }
                    ThemeCard(
                        name: "AMOLED",
                        colors: [.black, Color(hex: "050505")],
                        isSelected: themeManager.theme == .amoled
                    ) {
                        themeManager.theme = .amoled
                    }
                    ThemeCard(
                        name: "Clair",
                        colors: [Color(hex: "f0f0f0"), Color(hex: "e5e5e5")],
                        isSelected: themeManager.theme == .light
                    ) {
                        themeManager.theme = .light
                    }
                }
            }

            SettingsSection(title: "COULEUR D'ACCENT") {
                HStack(spacing: 10) {
                    ForEach(AccentColor.allCases, id: \.self) { accent in
                        AccentDot(
                            color: accent.color,
                            isSelected: themeManager.accent == accent
                        ) {
                            themeManager.accent = accent
                        }
                    }
                }
            }
        }
        .padding(24)
    }
}

// MARK: - Keybinds Content

struct KeybindsContent: View {
    private let shortcuts: [(String, String)] = [
        ("Sélecteur rapide", "⌘ K"),
        ("Rechercher dans la conversation", "⌘ F"),
        ("Fermer la recherche ou la fenêtre", "Échap"),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(shortcuts, id: \.0) { name, shortcut in
                HStack {
                    Text(name)
                        .font(.desktopReferenceSystem(size: 14))
                        .foregroundStyle(MoodTheme.textPrimary)

                    Spacer()

                    Text(shortcut)
                        .font(.desktopReferenceSystem(size: 12, weight: .medium, design: .monospaced))
                        .foregroundStyle(MoodTheme.textSecondary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(MoodTheme.glassBg)
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .stroke(MoodTheme.glassBorder, lineWidth: 0.5)
                        )
                }
                .padding(12)
                .background(MoodTheme.glassBg)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(MoodTheme.glassBorder, lineWidth: 0.5)
                )
            }
        }
        .padding(24)
    }
}

// MARK: - Encryption Content

/// There is no end-to-end encryption in Mood yet: this page says so instead of showing keys that do not exist.
struct EncryptionContent: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "info.circle.fill")
                    .font(.desktopReferenceSystem(size: 22))
                    .foregroundStyle(MoodTheme.textSecondary)

                VStack(alignment: .leading, spacing: 4) {
                    Text("Pas encore de chiffrement de bout en bout")
                        .font(.desktopReferenceSystem(size: 15, weight: .semibold))
                        .foregroundStyle(MoodTheme.textPrimary)
                    Text("Tes messages sont protégés pendant le transfert, mais le serveur de Mood peut les lire. Le chiffrement de bout en bout est prévu, pas encore disponible.")
                        .font(.desktopReferenceSystem(size: 13))
                        .foregroundStyle(MoodTheme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(16)
            .background(MoodTheme.glassBg)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(MoodTheme.glassBorder, lineWidth: 0.5)
            )

            SettingsSection(title: "CE QUE ÇA CHANGE") {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Il n’y a donc ni clé de récupération ni vérification d’appareil : elles n’ont de sens qu’avec ce chiffrement.")
                    Text("Un salon chiffré créé depuis une autre application s’affiche comme « message chiffré » : Mood ne sait pas encore le lire.")
                }
                .font(.desktopReferenceSystem(size: 13))
                .foregroundStyle(MoodTheme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(24)
    }
}

// MARK: - Reusable Components

struct SettingsSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.desktopReferenceSystem(size: 11, weight: .semibold))
                .tracking(0.4)
                .foregroundStyle(MoodTheme.textSecondary)

            content
        }
    }
}

struct SettingsField: View {
    let value: String
    let buttonLabel: String?
    /// The button only exists when it has something to do.
    var action: (() -> Void)?

    var body: some View {
        HStack {
            Text(value)
                .font(.desktopReferenceSystem(size: 14))
                .foregroundStyle(MoodTheme.textPrimary)

            Spacer()

            if let label = buttonLabel, let action {
                Button(action: action) {
                    Text(label)
                        .font(.desktopReferenceSystem(size: 12, weight: .semibold))
                        .foregroundStyle(MoodTheme.brandBlue)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(MoodTheme.glassBg)
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .stroke(MoodTheme.glassBorder, lineWidth: 0.5)
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(12)
        .background(MoodTheme.glassBg)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(MoodTheme.glassBorder, lineWidth: 0.5)
        )
    }
}

struct SettingsToggle: View {
    let title: String
    let subtitle: String
    @Binding var isOn: Bool

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.desktopReferenceSystem(size: 14, weight: .medium))
                    .foregroundStyle(MoodTheme.textPrimary)
                Text(subtitle)
                    .font(.desktopReferenceSystem(size: 12))
                    .foregroundStyle(MoodTheme.textSecondary)
            }

            Spacer()

            Toggle("", isOn: $isOn)
                .toggleStyle(.switch)
                .tint(MoodTheme.brandAccent)
        }
        .padding(12)
        .background(MoodTheme.glassBg)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(MoodTheme.glassBorder, lineWidth: 0.5)
        )
    }
}

struct ThemeCard: View {
    let name: String
    let colors: [Color]
    let isSelected: Bool
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(
                        LinearGradient(colors: colors, startPoint: .top, endPoint: .bottom)
                    )
                    .frame(width: 80, height: 55)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(isSelected ? MoodTheme.brandAccent : MoodTheme.glassBorder, lineWidth: isSelected ? 2 : 0.5)
                    )

                Text(name)
                    .font(.desktopReferenceSystem(size: 12))
                    .foregroundStyle(isSelected ? MoodTheme.brandAccent : MoodTheme.textSecondary)
            }
        }
        .buttonStyle(.plain)
    }
}

struct AccentDot: View {
    let color: Color
    let isSelected: Bool
    var action: () -> Void = {}

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(color)
                    .frame(width: 30, height: 30)

                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.desktopReferenceSystem(size: 12, weight: .bold))
                        .foregroundStyle(.white)
                }
            }
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    AccountSettingsView(isPresented: .constant(true))
        .environment(MatrixStore())
        .frame(width: 700, height: 500)
        .preferredColorScheme(.dark)
}

// MARK: - Unsaved Changes Bar
// Discord's bottom bar: appears only when a settings page has unsaved edits.

struct UnsavedChangesBar: View {
    let isSaving: Bool
    let onReset: () -> Void
    let onSave: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Text("Attention, tu as des modifications non enregistrées !")
                .font(.desktopReferenceSystem(size: 14, weight: .medium))
                .foregroundStyle(MoodTheme.textPrimary)
            Spacer()
            Button("Réinitialiser", action: onReset)
                .buttonStyle(.plain)
                .font(.desktopReferenceSystem(size: 14, weight: .medium))
                .foregroundStyle(MoodTheme.textPrimary)
            Button(action: onSave) {
                HStack(spacing: 6) {
                    if isSaving { ProgressView().controlSize(.small).tint(.white) }
                    Text("Enregistrer les modifications")
                        .font(.desktopReferenceSystem(size: 14, weight: .semibold))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(MoodTheme.onlineGreen)
                .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.defaultAction)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(MoodTheme.serverBar)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .popoverElevation()
    }
}
