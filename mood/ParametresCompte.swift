import SwiftUI

// MARK: - Account Settings View

struct AccountSettingsView: View {
    @Environment(MatrixStore.self) private var matrixStore
    @Environment(\.layoutMode) private var layoutMode
    @Binding var isPresented: Bool
    var authState: AuthState?
    @State private var selectedTab: SettingsTab = .myAccount

    // Catégories façon Discord
    enum SettingsCategory: String {
        case user = "PARAMÈTRES UTILISATEUR"
        case app = "PARAMÈTRES DE L'APP"
        case activity = "PARAMÈTRES D'ACTIVITÉ"
    }

    enum SettingsTab: String, CaseIterable {
        // Paramètres utilisateur
        case myAccount = "Mon compte"
        case profile = "Profil"
        case privacy = "Confidentialité & sécurité"
        case appAuth = "Appareils autorisés"
        // Paramètres de l'app
        case appearance = "Apparence"
        case accessibility = "Accessibilité"
        case voiceVideo = "Voix & Vidéo"
        case notifications = "Notifications"
        case keybinds = "Raccourcis clavier"
        case language = "Langue"
        // Paramètres d'activité
        case activityStatus = "Statut d'activité"
        case encryption = "Chiffrement"

        var icon: String {
            switch self {
            case .myAccount: return "person.circle"
            case .profile: return "person.text.rectangle"
            case .privacy: return "lock.shield"
            case .appAuth: return "checkmark.shield"
            case .appearance: return "paintbrush"
            case .accessibility: return "accessibility"
            case .voiceVideo: return "mic"
            case .notifications: return "bell"
            case .keybinds: return "keyboard"
            case .language: return "globe"
            case .activityStatus: return "circle.fill"
            case .encryption: return "key"
            }
        }

        var category: SettingsCategory {
            switch self {
            case .myAccount, .profile, .privacy, .appAuth:
                return .user
            case .appearance, .accessibility, .voiceVideo, .notifications, .keybinds, .language:
                return .app
            case .activityStatus, .encryption:
                return .activity
            }
        }
    }

    // Onglets groupés par catégorie
    private var tabsByCategory: [(SettingsCategory, [SettingsTab])] {
        let categories: [SettingsCategory] = [.user, .app, .activity]
        return categories.map { cat in
            (cat, SettingsTab.allCases.filter { $0.category == cat })
        }
    }

    var body: some View {
        if layoutMode == .regular {
            desktopSettingsLayout
        } else {
            compactSettingsLayout
        }
    }

    private var desktopSettingsLayout: some View {
        HStack(spacing: 0) {
            // Sidebar
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(tabsByCategory, id: \.0.rawValue) { category, tabs in
                        Text(category.rawValue)
                            .font(.system(size: 11, weight: .semibold))
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

                        Rectangle()
                            .fill(MoodTheme.divider)
                            .frame(height: 1)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 4)
                    }

                    Spacer().frame(height: 8)

                    // Déconnexion
                    Button {
                        matrixStore.logout()
                        if let authState {
                            withAnimation { authState.isLoggedIn = false }
                        }
                        isPresented = false
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "rectangle.portrait.and.arrow.right")
                                .font(.system(size: 13))
                            Text("Déconnexion")
                                .font(.system(size: 13))
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

            Rectangle().fill(MoodTheme.divider).frame(width: 1)

            // Content
            VStack(spacing: 0) {
                // Top bar with close
                HStack {
                    Text(selectedTab.rawValue)
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(MoodTheme.textPrimary)

                    Spacer()

                    Button {
                        isPresented = false
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 20))
                            .foregroundStyle(MoodTheme.textPrimary)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 16)

                Rectangle().fill(MoodTheme.divider).frame(height: 1)

                // Tab content
                ScrollView(showsIndicators: false) {
                    switch selectedTab {
                    case .myAccount:
                        MyAccountContent(selectedTab: $selectedTab)
                    case .profile:
                        ProfileContent()
                    case .privacy:
                        PrivacyContent()
                    case .appAuth:
                        AuthorizedDevicesContent()
                    case .appearance:
                        AppearanceContent()
                    case .accessibility:
                        AccessibilityContent()
                    case .voiceVideo:
                        VoiceVideoContent()
                    case .notifications:
                        NotificationsContent()
                    case .keybinds:
                        KeybindsContent()
                    case .language:
                        LanguageContent()
                    case .activityStatus:
                        ActivityStatusContent()
                    case .encryption:
                        EncryptionContent()
                    }
                }
            }
            .background(MoodTheme.chatBackground)
        }
        .frame(minWidth: 700, minHeight: 500)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var compactSettingsLayout: some View {
        NavigationStack {
            List {
                ForEach(tabsByCategory, id: \.0.rawValue) { category, tabs in
                    Section(category.rawValue) {
                        ForEach(tabs, id: \.self) { tab in
                            NavigationLink(value: tab) {
                                Label(tab.rawValue, systemImage: tab.icon)
                                    .font(.system(size: 15))
                            }
                        }
                    }
                }

                Section {
                    Button {
                        matrixStore.logout()
                        if let authState {
                            withAnimation { authState.isLoggedIn = false }
                        }
                        isPresented = false
                    } label: {
                        Label("Déconnexion", systemImage: "rectangle.portrait.and.arrow.right")
                            .font(.system(size: 15))
                            .foregroundStyle(MoodTheme.mentionBadge)
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(MoodTheme.channelList)
            .navigationTitle("Paramètres")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Fermer") { isPresented = false }
                }
            }
            .navigationDestination(for: SettingsTab.self) { tab in
                ScrollView(showsIndicators: false) {
                    settingsContent(for: tab)
                }
                .background(MoodTheme.chatBackground)
                .navigationTitle(tab.rawValue)
                .navigationBarTitleDisplayMode(.inline)
            }
        }
    }

    @ViewBuilder
    private func settingsContent(for tab: SettingsTab) -> some View {
        switch tab {
        case .myAccount:
            MyAccountContent(selectedTab: $selectedTab)
        case .profile:
            ProfileContent()
        case .privacy:
            PrivacyContent()
        case .appAuth:
            AuthorizedDevicesContent()
        case .appearance:
            AppearanceContent()
        case .accessibility:
            AccessibilityContent()
        case .voiceVideo:
            VoiceVideoContent()
        case .notifications:
            NotificationsContent()
        case .keybinds:
            KeybindsContent()
        case .language:
            LanguageContent()
        case .activityStatus:
            ActivityStatusContent()
        case .encryption:
            EncryptionContent()
        }
    }
}

// MARK: - Sidebar Item

struct SettingsSidebarItem: View {
    let tab: AccountSettingsView.SettingsTab
    let isSelected: Bool
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: tab.icon)
                    .font(.system(size: 13))
                    .frame(width: 18)
                Text(tab.rawValue)
                    .font(.system(size: 13))
                Spacer()
            }
            .foregroundStyle(MoodTheme.textPrimary)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                isSelected ? MoodTheme.selectedBg :
                isHovered ? MoodTheme.hoverBg : Color.clear
            )
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            .padding(.horizontal, 8)
        }
        .buttonStyle(.plain)
        .onHover { hovering in isHovered = hovering }
    }
}

// MARK: - My Account

struct MyAccountContent: View {
    @Environment(MatrixStore.self) private var matrixStore
    @Binding var selectedTab: AccountSettingsView.SettingsTab
    @State private var showDeleteConfirm = false
    private var user: MoodUser { matrixStore.currentUser ?? MockData.currentUser }

    var body: some View {
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
                        Text(user.avatarEmoji)
                            .font(.system(size: 34))
                            .frame(width: 70, height: 70)
                            .background(MoodTheme.glassBg)
                            .clipShape(Circle())
                            .overlay(
                                Circle()
                                    .stroke(MoodTheme.chatBackground, lineWidth: 4)
                            )
                            .offset(y: -20)

                        Circle()
                            .fill(MoodTheme.onlineGreen)
                            .frame(width: 16, height: 16)
                            .overlay(Circle().stroke(MoodTheme.chatBackground, lineWidth: 3))
                            .offset(x: 2, y: -18)
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        Text(user.displayName)
                            .font(.system(size: 18, weight: .bold))
                            .foregroundStyle(MoodTheme.textPrimary)

                        Text("@\(user.username)")
                            .font(.system(size: 13))
                            .foregroundStyle(MoodTheme.textSecondary)
                    }
                    .offset(y: -10)

                    Spacer()

                    Button { selectedTab = .profile } label: {
                        Text("Modifier le profil")
                            .font(.system(size: 12, weight: .semibold))
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
            SettingsSection(title: "NOM D'UTILISATEUR") {
                SettingsField(value: user.username, buttonLabel: "Modifier")
            }

            SettingsSection(title: "EMAIL") {
                SettingsField(value: "\(user.username)@mood.chat", buttonLabel: "Modifier")
            }

            SettingsSection(title: "HOMESERVER") {
                SettingsField(value: "matrix.mood.chat", buttonLabel: nil)
            }

            SettingsSection(title: "MOT DE PASSE") {
                SettingsField(value: "••••••••••", buttonLabel: "Modifier")
            }

            // Danger zone
            VStack(alignment: .leading, spacing: 10) {
                Text("ZONE DANGEREUSE")
                    .font(.system(size: 11, weight: .semibold))
                    .tracking(0.4)
                    .foregroundStyle(MoodTheme.mentionBadge)

                Button {
                    showDeleteConfirm = true
                } label: {
                    Text("Supprimer le compte")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(MoodTheme.mentionBadge)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                .buttonStyle(.plain)
                .alert("Supprimer le compte", isPresented: $showDeleteConfirm) {
                    Button("Annuler", role: .cancel) {}
                    Button("Supprimer", role: .destructive) {
                        matrixStore.logout()
                    }
                } message: {
                    Text("Cette action est irréversible. Toutes tes données seront supprimées.")
                }
            }
            .padding(.top, 10)
        }
        .padding(24)
    }
}

// MARK: - Profile Content

struct ProfileContent: View {
    @Environment(MatrixStore.self) private var matrixStore
    @State private var bio = ""
    @State private var displayName = ""
    @State private var showSaved = false
    @State private var showAvatarInfo = false
    private var user: MoodUser { matrixStore.currentUser ?? MockData.currentUser }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            SettingsSection(title: "NOM D'AFFICHAGE") {
                HStack {
                    TextField("Nom d'affichage", text: $displayName)
                        .textFieldStyle(.plain)
                        .font(.system(size: 14))
                        .foregroundStyle(MoodTheme.textPrimary)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(MoodTheme.glassBg)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .stroke(MoodTheme.glassBorder, lineWidth: 0.5)
                        )
                }
            }

            SettingsSection(title: "BIO") {
                TextEditor(text: $bio)
                    .font(.system(size: 14))
                    .foregroundStyle(MoodTheme.textPrimary)
                    .scrollContentBackground(.hidden)
                    .frame(height: 80)
                    .padding(10)
                    .background(MoodTheme.glassBg)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(MoodTheme.glassBorder, lineWidth: 0.5)
                    )
            }

            SettingsSection(title: "AVATAR") {
                HStack(spacing: 14) {
                    Text(user.avatarEmoji)
                        .font(.system(size: 30))
                        .frame(width: 60, height: 60)
                        .background(MoodTheme.glassBg)
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

                    Button {
                        showAvatarInfo = true
                    } label: {
                        Text("Changer l'avatar")
                            .font(.system(size: 13, weight: .semibold))
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
                    .alert("Changer l'avatar", isPresented: $showAvatarInfo) {
                        Button("OK", role: .cancel) {}
                    } message: {
                        Text("L'import d'images sera disponible dans une prochaine version.")
                    }
                }
            }

            SettingsSection(title: "BADGES") {
                HStack(spacing: 8) {
                    ForEach(user.badges, id: \.self) { badge in
                        Text(badge)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(MoodTheme.brandAccent)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(MoodTheme.brandAccent.opacity(0.12))
                            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                    }
                }
            }

            Spacer()

            Button {
                withAnimation(.easeInOut(duration: 0.2)) { showSaved = true }
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                    withAnimation { showSaved = false }
                }
            } label: {
                HStack(spacing: 6) {
                    if showSaved {
                        Image(systemName: "checkmark")
                            .font(.system(size: 12, weight: .bold))
                    }
                    Text(showSaved ? "Sauvegardé !" : "Sauvegarder")
                        .font(.system(size: 14, weight: .semibold))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 20)
                .padding(.vertical, 10)
                .background(showSaved ? MoodTheme.onlineGreen : MoodTheme.brandAccent)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .animation(.easeInOut(duration: 0.2), value: showSaved)
            }
            .buttonStyle(.plain)
        }
        .padding(24)
        .onAppear {
            bio = user.bio
            displayName = user.displayName
        }
    }
}

// MARK: - Privacy Content

struct PrivacyContent: View {
    @State private var readReceipts = true
    @State private var typingIndicators = true
    @State private var onlineStatus = true
    @State private var dmFromEveryone = false

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            SettingsToggle(title: "Confirmations de lecture", subtitle: "Les autres voient quand tu as lu un message", isOn: $readReceipts)
            SettingsToggle(title: "Indicateur de frappe", subtitle: "Les autres voient quand tu es en train d'écrire", isOn: $typingIndicators)
            SettingsToggle(title: "Statut en ligne", subtitle: "Montre ton statut de connexion aux autres", isOn: $onlineStatus)
            SettingsToggle(title: "Autoriser les DMs de tout le monde", subtitle: "Permettre à n'importe quel utilisateur de t'envoyer un message", isOn: $dmFromEveryone)

            Rectangle().fill(MoodTheme.divider).frame(height: 1).padding(.vertical, 4)

            VStack(alignment: .leading, spacing: 6) {
                Text("SESSIONS ACTIVES")
                    .font(.system(size: 11, weight: .semibold))
                    .tracking(0.4)
                    .foregroundStyle(MoodTheme.textSecondary)

                HStack(spacing: 12) {
                    Image(systemName: "laptopcomputer")
                        .font(.system(size: 18))
                        .foregroundStyle(MoodTheme.onlineGreen)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("macOS — Cette session")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(MoodTheme.textPrimary)
                        Text("Dernière activité : maintenant")
                            .font(.system(size: 12))
                            .foregroundStyle(MoodTheme.textSecondary)
                    }

                    Spacer()

                    HStack(spacing: 4) {
                        Circle().fill(MoodTheme.onlineGreen).frame(width: 6, height: 6)
                        Text("Vérifié")
                            .font(.system(size: 11))
                            .foregroundStyle(MoodTheme.onlineGreen)
                    }
                }
                .padding(12)
                .background(MoodTheme.glassBg)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(MoodTheme.glassBorder, lineWidth: 0.5)
                )
            }
        }
        .padding(24)
    }
}

// MARK: - Authorized Devices

struct AuthorizedDevicesContent: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Les appareils et applications autorisés à accéder à ton compte.")
                .font(.system(size: 14))
                .foregroundStyle(MoodTheme.textSecondary)

            HStack(spacing: 12) {
                Image(systemName: "laptopcomputer")
                    .font(.system(size: 20))
                    .foregroundStyle(MoodTheme.onlineGreen)
                    .frame(width: 40, height: 40)
                    .background(MoodTheme.glassBg)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

                VStack(alignment: .leading, spacing: 2) {
                    Text("Mood pour macOS")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(MoodTheme.textPrimary)
                    Text("Session active — accès complet")
                        .font(.system(size: 12))
                        .foregroundStyle(MoodTheme.textSecondary)
                }

                Spacer()

                Text("Actif")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(MoodTheme.onlineGreen)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(MoodTheme.onlineGreen.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            }
            .padding(14)
            .background(MoodTheme.glassBg)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(MoodTheme.glassBorder, lineWidth: 0.5)
            )
        }
        .padding(24)
    }
}

// MARK: - Notifications Content

struct NotificationsContent: View {
    @State private var enableAll = true
    @State private var mentions = true
    @State private var dms = true
    @State private var sounds = true

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            SettingsToggle(title: "Activer les notifications", subtitle: "Recevoir toutes les notifications", isOn: $enableAll)
            SettingsToggle(title: "Mentions", subtitle: "Notifier quand quelqu'un te mentionne", isOn: $mentions)
            SettingsToggle(title: "Messages privés", subtitle: "Notifier pour les nouveaux DMs", isOn: $dms)
            SettingsToggle(title: "Sons", subtitle: "Jouer un son pour les notifications", isOn: $sounds)
        }
        .padding(24)
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

            Rectangle().fill(MoodTheme.divider).frame(height: 1).padding(.vertical, 4)

            SettingsSection(title: "TAILLE DU TEXTE") {
                HStack(spacing: 16) {
                    Text("Aa")
                        .font(.system(size: 12))
                        .foregroundStyle(MoodTheme.textSecondary)

                    RoundedRectangle(cornerRadius: 2)
                        .fill(MoodTheme.glassBg)
                        .frame(height: 4)
                        .overlay(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 2)
                                .fill(MoodTheme.brandAccent)
                                .frame(width: 80, height: 4)
                        }

                    Text("Aa")
                        .font(.system(size: 18))
                        .foregroundStyle(MoodTheme.textSecondary)
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

// MARK: - Accessibility Content

struct AccessibilityContent: View {
    @State private var reduceMotion = false
    @State private var highContrast = false
    @State private var largerText = false

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            SettingsToggle(title: "Réduire les animations", subtitle: "Minimise les animations et transitions", isOn: $reduceMotion)
            SettingsToggle(title: "Contraste élevé", subtitle: "Augmente le contraste des bordures et séparateurs", isOn: $highContrast)
            SettingsToggle(title: "Texte plus grand", subtitle: "Augmente la taille de la police de base", isOn: $largerText)
        }
        .padding(24)
    }
}

// MARK: - Voice & Video Content

struct VoiceVideoContent: View {
    @State private var noiseReduction = true
    @State private var echoCancellation = true
    @State private var autoGain = true

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            SettingsSection(title: "ENTRÉE AUDIO") {
                HStack {
                    Text("Microphone par défaut")
                        .font(.system(size: 14))
                        .foregroundStyle(MoodTheme.textPrimary)
                    Spacer()
                    Text("Défaut du système")
                        .font(.system(size: 13))
                        .foregroundStyle(MoodTheme.textSecondary)
                }
                .padding(12)
                .background(MoodTheme.glassBg)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(MoodTheme.glassBorder, lineWidth: 0.5)
                )
            }

            SettingsSection(title: "SORTIE AUDIO") {
                HStack {
                    Text("Haut-parleur par défaut")
                        .font(.system(size: 14))
                        .foregroundStyle(MoodTheme.textPrimary)
                    Spacer()
                    Text("Défaut du système")
                        .font(.system(size: 13))
                        .foregroundStyle(MoodTheme.textSecondary)
                }
                .padding(12)
                .background(MoodTheme.glassBg)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(MoodTheme.glassBorder, lineWidth: 0.5)
                )
            }

            Rectangle().fill(MoodTheme.divider).frame(height: 1).padding(.vertical, 4)

            SettingsToggle(title: "Réduction du bruit", subtitle: "Supprime les bruits de fond pendant les appels", isOn: $noiseReduction)
            SettingsToggle(title: "Annulation d'écho", subtitle: "Empêche l'écho de tes haut-parleurs", isOn: $echoCancellation)
            SettingsToggle(title: "Contrôle automatique du gain", subtitle: "Ajuste automatiquement le volume du microphone", isOn: $autoGain)
        }
        .padding(24)
    }
}

// MARK: - Keybinds Content

struct KeybindsContent: View {
    private let shortcuts: [(String, String)] = [
        ("Rechercher", "⌘ F"),
        ("Paramètres", "⌘ ,"),
        ("Basculer sourdine", "⌘ ⇧ M"),
        ("Basculer sourdine vidéo", "⌘ ⇧ V"),
        ("Naviguer entre serveurs", "⌘ ↑/↓"),
        ("Naviguer entre channels", "⌥ ↑/↓"),
        ("Marquer comme lu", "⌘ ⇧ R"),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(shortcuts, id: \.0) { name, shortcut in
                HStack {
                    Text(name)
                        .font(.system(size: 14))
                        .foregroundStyle(MoodTheme.textPrimary)

                    Spacer()

                    Text(shortcut)
                        .font(.system(size: 12, weight: .medium, design: .monospaced))
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

// MARK: - Language Content

struct LanguageContent: View {
    @State private var selectedLanguage = "Français"
    private let languages = ["Français", "English", "Español", "Deutsch", "Italiano", "Português", "日本語", "한국어"]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Choisis la langue de l'application.")
                .font(.system(size: 14))
                .foregroundStyle(MoodTheme.textSecondary)
                .padding(.bottom, 4)

            ForEach(languages, id: \.self) { lang in
                Button {
                    selectedLanguage = lang
                } label: {
                    HStack {
                        Text(lang)
                            .font(.system(size: 14))
                            .foregroundStyle(MoodTheme.textPrimary)

                        Spacer()

                        if selectedLanguage == lang {
                            Image(systemName: "checkmark")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundStyle(MoodTheme.brandAccent)
                        }
                    }
                    .padding(12)
                    .background(selectedLanguage == lang ? MoodTheme.selectedBg : MoodTheme.glassBg)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(selectedLanguage == lang ? MoodTheme.brandAccent.opacity(0.5) : MoodTheme.glassBorder, lineWidth: 0.5)
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(24)
    }
}

// MARK: - Activity Status Content

struct ActivityStatusContent: View {
    @State private var showActivity = true
    @State private var showCurrentApp = false

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            SettingsToggle(title: "Afficher l'activité en cours", subtitle: "Les autres peuvent voir à quoi tu joues ou travailles", isOn: $showActivity)
            SettingsToggle(title: "Afficher l'application active", subtitle: "Montre l'application que tu utilises actuellement", isOn: $showCurrentApp)

            Rectangle().fill(MoodTheme.divider).frame(height: 1).padding(.vertical, 4)

            SettingsSection(title: "STATUT PERSONNALISÉ") {
                HStack(spacing: 10) {
                    Text("😊")
                        .font(.system(size: 20))
                        .frame(width: 36, height: 36)
                        .background(MoodTheme.glassBg)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .stroke(MoodTheme.glassBorder, lineWidth: 0.5)
                        )

                    Text("Définir un statut personnalisé...")
                        .font(.system(size: 14))
                        .foregroundStyle(MoodTheme.textMuted)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .background(MoodTheme.glassBg)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .stroke(MoodTheme.glassBorder, lineWidth: 0.5)
                        )
                }
            }
        }
        .padding(24)
    }
}

// MARK: - Encryption Content

struct EncryptionContent: View {
    @State private var showRecoveryAlert = false

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            // E2E status
            HStack(spacing: 12) {
                Image(systemName: "lock.shield.fill")
                    .font(.system(size: 24))
                    .foregroundStyle(MoodTheme.onlineGreen)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Chiffrement de bout en bout activé")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(MoodTheme.textPrimary)
                    Text("Tes messages sont protégés par le protocole Matrix Megolm")
                        .font(.system(size: 13))
                        .foregroundStyle(MoodTheme.textSecondary)
                }
            }
            .padding(16)
            .background(MoodTheme.onlineGreen.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(MoodTheme.onlineGreen.opacity(0.2), lineWidth: 0.5)
            )

            SettingsSection(title: "CLÉ DE RÉCUPÉRATION") {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Ta clé de récupération te permet de restaurer tes messages chiffrés si tu perds l'accès à toutes tes sessions.")
                        .font(.system(size: 13))
                        .foregroundStyle(MoodTheme.textSecondary)

                    Button {
                        showRecoveryAlert = true
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "key")
                                .font(.system(size: 12))
                            Text("Configurer la clé de récupération")
                                .font(.system(size: 13, weight: .semibold))
                        }
                        .foregroundStyle(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(MoodTheme.brandAccent)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .alert("Clé de récupération", isPresented: $showRecoveryAlert) {
                        Button("OK", role: .cancel) {}
                    } message: {
                        Text("La génération de clé de récupération sera disponible dans une prochaine version.")
                    }
                }
            }

            SettingsSection(title: "VÉRIFICATION CROISÉE") {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Vérifie tes autres appareils pour garantir que personne n'usurpe ton identité.")
                        .font(.system(size: 13))
                        .foregroundStyle(MoodTheme.textSecondary)

                    HStack(spacing: 12) {
                        Image(systemName: "laptopcomputer")
                            .font(.system(size: 16))
                            .foregroundStyle(MoodTheme.onlineGreen)

                        VStack(alignment: .leading, spacing: 1) {
                            Text("macOS")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(MoodTheme.textPrimary)
                            Text("ABCD EFGH IJKL MNOP")
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(MoodTheme.textMuted)
                        }

                        Spacer()

                        HStack(spacing: 4) {
                            Image(systemName: "checkmark.shield.fill")
                                .font(.system(size: 11))
                            Text("Vérifié")
                                .font(.system(size: 11, weight: .medium))
                        }
                        .foregroundStyle(MoodTheme.onlineGreen)
                    }
                    .padding(12)
                    .background(MoodTheme.glassBg)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
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
                .font(.system(size: 11, weight: .semibold))
                .tracking(0.4)
                .foregroundStyle(MoodTheme.textSecondary)

            content
        }
    }
}

struct SettingsField: View {
    let value: String
    let buttonLabel: String?
    @State private var showFieldAlert = false

    var body: some View {
        HStack {
            Text(value)
                .font(.system(size: 14))
                .foregroundStyle(MoodTheme.textPrimary)

            Spacer()

            if let label = buttonLabel {
                Button { showFieldAlert = true } label: {
                    Text(label)
                        .font(.system(size: 12, weight: .semibold))
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
                .alert("Modification", isPresented: $showFieldAlert) {
                    Button("OK", role: .cancel) {}
                } message: {
                    Text("Cette fonctionnalité sera disponible dans une prochaine version.")
                }
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
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(MoodTheme.textPrimary)
                Text(subtitle)
                    .font(.system(size: 12))
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
                    .font(.system(size: 12))
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
                        .font(.system(size: 12, weight: .bold))
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
