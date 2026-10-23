import SwiftUI

/// Compact-only settings. All changes use the store's existing public preferences/actions.
struct MobilePreferencesView: View {
    @Environment(MatrixStore.self) private var store
    let tab: AccountSettingsView.SettingsTab
    let onSignOut: () -> Void
    @State private var confirmSignOut = false

    private var preferences: AccountPreferences { store.preferences }

    var body: some View {
        List {
            switch tab {
            case .appearance: appearance
            case .privacy: privacy
            case .notifications: notifications
            case .appAuth: devices
            case .encryption:
                Section {
                    Text("Pas encore de chiffrement de bout en bout").font(.mood(16, weight: .semibold))
                    Text("Tes messages sont protégés pendant le transfert. Le serveur Mood peut encore les lire.")
                        .font(.mood(15)).foregroundStyle(MoodTheme.textSecondary)
                }.listRowBackground(MoodTheme.inputBg)
            default: EmptyView()
            }
        }.mobileGroupedList()
            .task {
                guard !ProcessInfo.processInfo.arguments.contains("-uiPreview") else { return }
                store.refreshPreferencesIfNeeded()
                if tab == .appAuth { await store.refreshDevices() }
                if tab == .notifications { await store.refreshNotificationAuthorization() }
            }
            .confirmationDialog("Se déconnecter de cet appareil ?", isPresented: $confirmSignOut, titleVisibility: .visible) {
                Button("Se déconnecter", role: .destructive, action: onSignOut)
                Button("Annuler", role: .cancel) {}
            } message: { Text("Les messages non envoyés de cet appareil seront perdus.") }
    }

    private var appearance: some View {
        Group {
            Section("Thème") {
                ForEach([AppTheme.dark, .amoled, .light], id: \.self) { theme in
                    Button { MoodTheme.shared.theme = theme } label: {
                        HStack {
                            Text(theme == .dark ? "Sombre" : (theme == .amoled ? "AMOLED" : "Clair"))
                            Spacer()
                            if MoodTheme.shared.theme == theme { Image(systemName: "checkmark").foregroundStyle(MoodTheme.brandAccent) }
                        }.foregroundStyle(MoodTheme.textPrimary)
                    }.buttonStyle(.plain)
                }
            }.listRowBackground(MoodTheme.inputBg)
            Section("Couleur d’accent") {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: LayoutMetrics.mobile(44)))], spacing: LayoutMetrics.mobile(12)) {
                    ForEach(AccentColor.allCases, id: \.self) { accent in
                        Button { MoodTheme.shared.accent = accent } label: {
                            Circle().fill(accent.color).frame(width: LayoutMetrics.mobile(32), height: LayoutMetrics.mobile(32))
                                .overlay { if MoodTheme.shared.accent == accent { Image(systemName: "checkmark").foregroundStyle(MoodTheme.mobileIndicator) } }
                                .frame(width: LayoutMetrics.mobile(44), height: LayoutMetrics.mobile(44))
                        }.buttonStyle(.plain).accessibilityLabel(accent.rawValue)
                            .accessibilityAddTraits(MoodTheme.shared.accent == accent ? .isSelected : [])
                    }
                }.padding(.vertical, LayoutMetrics.mobile(8))
            }.listRowBackground(MoodTheme.inputBg)
        }
    }

    private var privacy: some View {
        Section {
            Toggle(isOn: Binding(get: { preferences.sendsReadReceipts }, set: { value in store.updatePreferences { $0.sendsReadReceipts = value } })) {
                settingLabel("Confirmations de lecture", "Les autres voient quand tu as lu un message.")
            }
            Toggle(isOn: Binding(get: { preferences.sendsTypingIndicator }, set: { value in store.updatePreferences { $0.sendsTypingIndicator = value } })) {
                settingLabel("Indicateur de frappe", "Les autres voient quand tu écris.")
            }
            Text("Ces choix sont enregistrés pour ce compte, sur cet appareil.").font(.mood(14)).foregroundStyle(MoodTheme.textSecondary)
        }.listRowBackground(MoodTheme.inputBg)
    }

    private var notifications: some View {
        Group {
            Section {
                Toggle(isOn: Binding(get: { preferences.notificationsEnabled }, set: { value in Task { await store.setNotificationsEnabled(value) } })) {
                    settingLabel("Notifications", "Pour les nouvelles conversations et les messages non lus.")
                }
                if store.notificationAuthorization == .denied {
                    Text("Autorise les notifications dans les réglages iPhone, puis réactive cette option.").font(.mood(14)).foregroundStyle(MoodTheme.mentionBadge)
                }
                Toggle("Sons", isOn: Binding(get: { preferences.soundsEnabled }, set: { value in store.updatePreferences { $0.soundsEnabled = value } }))
                Toggle("Pastille sur l’icône", isOn: Binding(get: { preferences.badgeEnabled }, set: { value in Task { await store.setBadgeEnabled(value) } }))
            }.listRowBackground(MoodTheme.inputBg)
            Section("Salons en sourdine") {
                if store.mutedRoomIds.isEmpty {
                    Text("Appui long sur un salon ou une conversation, puis « Rendre muet ».").font(.mood(15)).foregroundStyle(MoodTheme.textSecondary)
                }
                ForEach(store.mutedRoomIds.sorted(), id: \.self) { roomID in
                    if let destination = store.destination(forRoomId: roomID) {
                        VStack(alignment: .leading, spacing: LayoutMetrics.mobile(8)) {
                            Text(destination.title).fixedSize(horizontal: false, vertical: true)
                            Button("Rétablir le son") { Task { await store.setMuted(false, roomId: roomID) } }.frame(minHeight: LayoutMetrics.mobile(44))
                        }
                    }
                }
            }.listRowBackground(MoodTheme.inputBg)
            Section {
                Text("Les notifications arrivent lorsque Mood est ouvert. Quand l’app est fermée, aucune notification n’est encore envoyée.").font(.mood(14)).foregroundStyle(MoodTheme.textSecondary)
            }.listRowBackground(MoodTheme.inputBg)
        }
    }

    @ViewBuilder private var devices: some View {
        Section("Appareils connectés") {
            if store.userId == nil {
                Text("Connecte-toi pour voir tes appareils.").foregroundStyle(MoodTheme.textSecondary)
            } else if store.devices.isEmpty {
                switch store.devicesState {
                case .idle, .loading: ProgressView("Chargement…")
                case .loaded: Text("Aucun appareil à afficher.")
                case .failed:
                    Text("Impossible de charger les appareils.").foregroundStyle(MoodTheme.mentionBadge)
                    Button("Réessayer") { Task { await store.refreshDevices() } }
                }
            } else {
                ForEach(store.devices) { device in
                    VStack(alignment: .leading, spacing: LayoutMetrics.mobile(8)) {
                        Label(device.title, systemImage: "iphone").font(.mood(16, weight: .semibold))
                        if device.deviceId == store.currentDeviceId {
                            Text("Cet appareil · actif").font(.mood(14)).foregroundStyle(MoodTheme.textSecondary)
                            Button("Se déconnecter", role: .destructive) { confirmSignOut = true }.foregroundStyle(MoodTheme.mentionBadge)
                        } else {
                            Text("Pour le déconnecter, ouvre Mood sur cet appareil.").font(.mood(14)).foregroundStyle(MoodTheme.textSecondary)
                        }
                    }.padding(.vertical, LayoutMetrics.mobile(8))
                }
            }
        }.listRowBackground(MoodTheme.inputBg)
    }

    private func settingLabel(_ title: String, _ detail: String) -> some View {
        VStack(alignment: .leading, spacing: LayoutMetrics.mobile(4)) {
            Text(title).font(.mood(16))
            Text(detail).font(.mood(14)).foregroundStyle(MoodTheme.textSecondary).fixedSize(horizontal: false, vertical: true)
        }.padding(.vertical, LayoutMetrics.mobile(4))
    }
}
