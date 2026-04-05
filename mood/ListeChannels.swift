import SwiftUI
import UIKit

// MARK: - Channel List Column

struct ChannelListColumn: View {
    let server: MoodServer
    @Binding var selectedChannel: Channel?
    @Binding var showSettings: Bool
    @State private var showServerMenu = false

    var body: some View {
        VStack(spacing: 0) {
            // Header serveur
            Button {
                withAnimation(.easeInOut(duration: 0.15)) {
                    showServerMenu.toggle()
                }
            } label: {
                HStack {
                    Text(server.name)
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(MoodTheme.textPrimary)
                    Spacer()
                    Image(systemName: showServerMenu ? "xmark" : "chevron.down")
                        .font(.system(size: showServerMenu ? 11 : 10, weight: .semibold))
                        .foregroundStyle(MoodTheme.textPrimary)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
            }
            .buttonStyle(.plain)

            Rectangle()
                .fill(MoodTheme.divider)
                .frame(height: 1)

            // Server settings dropdown
            if showServerMenu {
                ServerSettingsMenu()
                    .transition(.move(edge: .top).combined(with: .opacity))
            }

            // Channels
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(server.categories) { category in
                        CategorySection(
                            category: category,
                            server: server,
                            selectedChannel: $selectedChannel
                        )
                    }
                }
                .padding(.top, 10)
                .padding(.bottom, 16)
            }

            Spacer(minLength: 0)

            // Voice connected panel
            VoiceConnectedPanel()

            UserStatusPanel(showSettings: $showSettings)
        }
        .background(MoodTheme.channelList)
    }
}

// MARK: - Server Settings Menu

struct ServerSettingsMenu: View {
    @State private var showInviteModal = false
    @State private var showComingSoon = false
    @State private var showLeaveConfirm = false
    @State private var hideMutedChannels = false

    var body: some View {
        VStack(spacing: 2) {
            ServerMenuItem(icon: "person.badge.plus", label: "Inviter des gens", color: MoodTheme.brandBlue) {
                showInviteModal = true
            }

            Rectangle().fill(MoodTheme.divider).frame(height: 1).padding(.horizontal, 8).padding(.vertical, 4)

            ServerMenuItem(icon: "gearshape", label: "Paramètres du serveur", color: MoodTheme.textSecondary) { showComingSoon = true }
            ServerMenuItem(icon: "folder", label: "Créer un channel", color: MoodTheme.textSecondary) { showComingSoon = true }
            ServerMenuItem(icon: "folder.badge.plus", label: "Créer une catégorie", color: MoodTheme.textSecondary) { showComingSoon = true }

            Rectangle().fill(MoodTheme.divider).frame(height: 1).padding(.horizontal, 8).padding(.vertical, 4)

            ServerMenuItem(icon: "bell", label: "Paramètres de notification", color: MoodTheme.textSecondary) { showComingSoon = true }
            ServerMenuItem(icon: "shield", label: "Confidentialité", color: MoodTheme.textSecondary) { showComingSoon = true }
            ServerMenuItem(icon: hideMutedChannels ? "eye" : "eye.slash", label: hideMutedChannels ? "Afficher les channels muets" : "Masquer les channels muets", color: MoodTheme.textSecondary) { hideMutedChannels.toggle() }

            Rectangle().fill(MoodTheme.divider).frame(height: 1).padding(.horizontal, 8).padding(.vertical, 4)

            ServerMenuItem(icon: "rectangle.portrait.and.arrow.right", label: "Quitter le serveur", color: .red) { showLeaveConfirm = true }
        }
        .padding(.vertical, 8)
        .background(MoodTheme.serverBar.opacity(0.95))
        .alert("Bientôt disponible", isPresented: $showComingSoon) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Cette fonctionnalité arrive dans une prochaine version de Mood.")
        }
        .alert("Quitter le serveur", isPresented: $showLeaveConfirm) {
            Button("Annuler", role: .cancel) {}
            Button("Quitter", role: .destructive) {}
        } message: {
            Text("Es-tu sûr de vouloir quitter ce serveur ?")
        }
    }
}

struct ServerMenuItem: View {
    let icon: String
    let label: String
    let color: Color
    var action: () -> Void = {}
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Text(label)
                    .font(.system(size: 13))
                    .foregroundStyle(isHovered ? .white : color)
                Spacer()
                Image(systemName: icon)
                    .font(.system(size: 12))
                    .foregroundStyle(isHovered ? .white : color)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(isHovered ? MoodTheme.brandAccent : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
            .padding(.horizontal, 8)
        }
        .buttonStyle(.plain)
        .onHover { hovering in isHovered = hovering }
    }
}

// MARK: - Category Section

struct CategorySection: View {
    let category: ChannelCategory
    let server: MoodServer
    @Binding var selectedChannel: Channel?
    @State private var isExpanded = true

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Button {
                withAnimation(.easeInOut(duration: 0.12)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 8, weight: .bold))
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))

                    Text(category.name)
                        .font(.system(size: 11, weight: .semibold))
                        .tracking(0.5)

                    Spacer()

                    Image(systemName: "plus")
                        .font(.system(size: 11))
                        .opacity(0.5)
                }
                .foregroundStyle(MoodTheme.textSecondary)
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
                .padding(.top, 16)
            }
            .buttonStyle(.plain)

            if isExpanded {
                ForEach(category.channels) { channel in
                    VStack(spacing: 0) {
                        ChannelRow(
                            channel: channel,
                            isSelected: selectedChannel?.id == channel.id
                        )
                        .onTapGesture {
                            selectedChannel = channel
                        }

                        // Voice channel: show connected users
                        if channel.type == .voice, let users = MockData.voiceUsers[channel.id], !users.isEmpty {
                            VStack(spacing: 2) {
                                ForEach(users) { user in
                                    HStack(spacing: 8) {
                                        Text(user.avatarEmoji)
                                            .font(.system(size: 12))
                                            .frame(width: 24, height: 24)
                                            .background(MoodTheme.glassBg)
                                            .clipShape(Circle())

                                        Text(user.displayName)
                                            .font(.system(size: 13))
                                            .foregroundStyle(MoodTheme.textSecondary)
                                            .lineLimit(1)

                                        Spacer()

                                        // Live badge (like Discord "EN DIRECT")
                                        if user.activity != nil {
                                            Text("EN DIRECT")
                                                .font(.system(size: 9, weight: .bold))
                                                .foregroundStyle(.white)
                                                .padding(.horizontal, 5)
                                                .padding(.vertical, 2)
                                                .background(MoodTheme.mentionBadge)
                                                .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
                                        }

                                        Image(systemName: "mic.fill")
                                            .font(.system(size: 9))
                                            .foregroundStyle(MoodTheme.textMuted)
                                    }
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 3)
                                }
                            }
                            .padding(.leading, 32)
                            .padding(.horizontal, 8)
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Channel Row

struct ChannelRow: View {
    let channel: Channel
    let isSelected: Bool
    @State private var isHovered = false
    @State private var isMuted = false
    @State private var markedAsRead = false
    @State private var showComingSoon = false
    @State private var showDeleteConfirm = false

    private var isUnread: Bool { channel.unreadCount > 0 }

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: channel.icon)
                .font(.system(size: 14))
                .foregroundStyle(isSelected ? MoodTheme.textPrimary : (isUnread ? MoodTheme.textPrimary : MoodTheme.textMuted))
                .frame(width: 20)

            Text(channel.name)
                .font(.system(size: 14))
                .fontWeight(isUnread ? .semibold : .regular)
                .foregroundStyle(isSelected ? MoodTheme.textPrimary : (isUnread ? MoodTheme.textPrimary : MoodTheme.textMuted))
                .lineLimit(1)

            if channel.isE2E {
                Image(systemName: "lock.fill")
                    .font(.system(size: 7))
                    .foregroundStyle(MoodTheme.textMuted.opacity(0.4))
            }

            Spacer()

            if channel.unreadCount > 0 && !isSelected {
                Text("\(channel.unreadCount)")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(MoodTheme.mentionBadge)
                    .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(
            isSelected ? MoodTheme.selectedBg :
            isHovered ? MoodTheme.hoverBg :
            Color.clear
        )
        .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
        .padding(.horizontal, 6)
        .contentShape(Rectangle())
        .onHover { hovering in isHovered = hovering }
        .contextMenu {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) { markedAsRead = true }
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                    withAnimation { markedAsRead = false }
                }
            } label: { Label(markedAsRead ? "Marqué !" : "Marquer comme lu", systemImage: markedAsRead ? "checkmark.circle.fill" : "checkmark.circle") }
            Divider()
            Button { showComingSoon = true } label: { Label("Modifier le channel", systemImage: "pencil") }
            Button { showComingSoon = true } label: { Label("Paramètres de notification", systemImage: "bell") }
            Button { isMuted.toggle() } label: { Label(isMuted ? "Rétablir le son" : "Rendre muet", systemImage: isMuted ? "bell" : "bell.slash") }
            Divider()
            Button { showComingSoon = true } label: { Label("Inviter des gens", systemImage: "person.badge.plus") }
            Button {
                UIPasteboard.general.string = channel.id.uuidString
            } label: { Label("Copier l'ID", systemImage: "doc.on.doc") }
            Divider()
            Button(role: .destructive) { showDeleteConfirm = true } label: { Label("Supprimer le channel", systemImage: "trash") }
        }
        .alert("Bientôt disponible", isPresented: $showComingSoon) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Cette fonctionnalité arrive dans une prochaine version de Mood.")
        }
        .alert("Supprimer le channel", isPresented: $showDeleteConfirm) {
            Button("Annuler", role: .cancel) {}
            Button("Supprimer", role: .destructive) {}
        } message: {
            Text("Es-tu sûr de vouloir supprimer #\(channel.name) ? Cette action est irréversible.")
        }
    }
}

// MARK: - Voice Connected Panel

struct VoiceConnectedPanel: View {
    @State private var callDuration: TimeInterval = 0
    @State private var timer: Timer?
    @State private var isScreenSharing = false
    @State private var isCameraOn = false
    @State private var isInActivity = false
    @State private var isConnected = true

    var body: some View {
        if isConnected {
            VStack(spacing: 4) {
                // Ligne 1 : Voix connectée + signal + timer
                HStack(spacing: 6) {
                    Circle()
                        .fill(MoodTheme.onlineGreen)
                        .frame(width: 8, height: 8)

                    Text("Voix connectée")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(MoodTheme.onlineGreen)

                    Spacer()

                    // Timer
                    Text(formattedDuration)
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundStyle(MoodTheme.textSecondary)

                    // Barres signal
                    HStack(spacing: 1.5) {
                        ForEach(0..<4) { i in
                            RoundedRectangle(cornerRadius: 1)
                                .fill(i < 3 ? MoodTheme.onlineGreen : MoodTheme.textMuted)
                                .frame(width: 3, height: CGFloat(4 + i * 3))
                        }
                    }
                }

                // Ligne 2 : Channel / Serveur + mode actif
                HStack(spacing: 6) {
                    Image(systemName: "speaker.wave.2")
                        .font(.system(size: 10))
                        .foregroundStyle(MoodTheme.textSecondary)

                    Text("lounge / Design Club")
                        .font(.system(size: 11))
                        .foregroundStyle(MoodTheme.textSecondary)
                        .lineLimit(1)

                    Spacer()

                    if isScreenSharing {
                        Text("Partage")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(MoodTheme.brandAccent)
                            .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                    }

                    if isCameraOn {
                        Text("Caméra")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(MoodTheme.onlineGreen)
                            .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                    }
                }
                .padding(.bottom, 4)

                // Ligne 3 : Boutons de contrôle
                HStack(spacing: 6) {
                    // Partage d'écran
                    VoicePanelButton(
                        icon: isScreenSharing ? "rectangle.on.rectangle.slash" : "rectangle.on.rectangle",
                        help: isScreenSharing ? "Arrêter le partage" : "Partager l'écran",
                        isActive: isScreenSharing
                    ) {
                        withAnimation(.easeInOut(duration: 0.15)) {
                            isScreenSharing.toggle()
                        }
                    }

                    // Caméra
                    VoicePanelButton(
                        icon: isCameraOn ? "video.fill" : "video",
                        help: isCameraOn ? "Couper la caméra" : "Activer la caméra",
                        isActive: isCameraOn
                    ) {
                        withAnimation(.easeInOut(duration: 0.15)) {
                            isCameraOn.toggle()
                        }
                    }

                    // Activité
                    VoicePanelButton(
                        icon: "sparkles",
                        help: "Activités",
                        isActive: isInActivity
                    ) {
                        withAnimation(.easeInOut(duration: 0.15)) {
                            isInActivity.toggle()
                        }
                    }

                    Spacer()

                    // Déconnecter
                    VoicePanelButton(
                        icon: "phone.down.fill",
                        help: "Déconnecter",
                        isDestructive: true
                    ) {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            timer?.invalidate()
                            isConnected = false
                        }
                    }
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(MoodTheme.channelList)
            .overlay(
                Rectangle().fill(MoodTheme.divider).frame(height: 1), alignment: .top
            )
            .overlay(
                Rectangle().fill(MoodTheme.divider).frame(height: 1), alignment: .bottom
            )
            .onAppear {
                timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
                    callDuration += 1
                }
            }
            .onDisappear {
                timer?.invalidate()
            }
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }

    private var formattedDuration: String {
        let m = Int(callDuration) / 60
        let s = Int(callDuration) % 60
        return String(format: "%d:%02d", m, s)
    }
}

struct VoicePanelButton: View {
    let icon: String
    let help: String
    var isActive: Bool = false
    var isDestructive: Bool = false
    let action: () -> Void
    @State private var isHovered = false

    private var bgColor: Color {
        if isDestructive {
            return isHovered ? Color(hex: "d83c3e") : Color(hex: "b5383a")
        }
        if isActive {
            return isHovered ? MoodTheme.brandAccent.opacity(0.8) : MoodTheme.brandAccent
        }
        return isHovered ? MoodTheme.glassHighlight : MoodTheme.glassBg
    }

    private var fgColor: Color {
        if isDestructive || isActive { return .white }
        return MoodTheme.textPrimary
    }

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 13))
                .foregroundStyle(fgColor)
                .frame(width: 32, height: 32)
                .background(bgColor)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .contentTransition(.symbolEffect(.replace))
        }
        .buttonStyle(.plain)
        .animation(.easeInOut(duration: 0.15), value: isDestructive)
        .animation(.easeInOut(duration: 0.15), value: isActive)
        .onHover { hovering in isHovered = hovering }
        .help(help)
    }
}

// MARK: - User Status Panel

struct UserStatusPanel: View {
    @Environment(MatrixStore.self) private var matrixStore
    @Binding var showSettings: Bool
    @State private var showStatusPicker = false
    @State private var isMicMuted = false
    @State private var isDeafened = false

    private var user: MoodUser { matrixStore.currentUser ?? MockData.currentUser }

    var body: some View {
        VStack(spacing: 0) {
            // Status picker popup
            if showStatusPicker {
                StatusPickerMenu(showPicker: $showStatusPicker)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            HStack(spacing: 8) {
                // Avatar circle (clickable for status)
                Button {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        showStatusPicker.toggle()
                    }
                } label: {
                    ZStack(alignment: .bottomTrailing) {
                        Text(user.avatarEmoji)
                            .font(.system(size: 18))
                            .frame(width: 32, height: 32)
                            .background(MoodTheme.glassBg)
                            .clipShape(Circle())

                        StatusIndicator(status: .online, size: 8, borderColor: MoodTheme.serverBar)
                            .offset(x: 2, y: 2)
                    }
                }
                .buttonStyle(.plain)
                .help("Changer le statut")

                VStack(alignment: .leading, spacing: 1) {
                    Text(user.displayName)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(MoodTheme.textPrimary)
                        .lineLimit(1)
                    Text("En ligne")
                        .font(.system(size: 11))
                        .foregroundStyle(MoodTheme.textSecondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                HStack(spacing: 4) {
                    StatusPanelIcon(isMuted: $isMicMuted, iconOn: "mic.fill", iconOff: "mic.slash.fill", tooltip: "Micro")
                    StatusPanelIcon(isMuted: $isDeafened, iconOn: "headphones", iconOff: "speaker.slash.fill", tooltip: "Casque")
                    Button {
                        showSettings = true
                    } label: {
                        Image(systemName: "gearshape.fill")
                            .font(.system(size: 13))
                            .foregroundStyle(MoodTheme.textSecondary)
                            .frame(width: 32, height: 32)
                            .background(Color.clear)
                            .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help("Paramètres utilisateur")
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
        }
        .background(MoodTheme.serverBar)
        .overlay(Rectangle().fill(MoodTheme.divider).frame(height: 1), alignment: .top)
    }
}

// MARK: - Status Picker Menu

struct StatusPickerMenu: View {
    @Binding var showPicker: Bool
    @State private var showCustomStatus = false

    private let statuses: [(status: MoodUser.UserStatus, label: String, description: String)] = [
        (.online, "En ligne", ""),
        (.offline, "Hors ligne", "Tu apparaîtras hors ligne"),
    ]

    var body: some View {
        VStack(spacing: 2) {
            // Custom status
            Button { showCustomStatus = true } label: {
                HStack(spacing: 8) {
                    Text("😀")
                        .font(.system(size: 14))
                    Text("Définir un statut personnalisé")
                        .font(.system(size: 13))
                        .foregroundStyle(MoodTheme.textSecondary)
                    Spacer()
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
            }
            .buttonStyle(.plain)
            .popover(isPresented: $showCustomStatus, arrowEdge: .top) {
                CustomStatusEditor(isPresented: $showCustomStatus)
            }

            Rectangle().fill(MoodTheme.divider).frame(height: 1).padding(.horizontal, 8).padding(.vertical, 4)

            ForEach(statuses, id: \.status) { item in
                Button {
                    withAnimation(.easeInOut(duration: 0.15)) { showPicker = false }
                } label: {
                    HStack(spacing: 10) {
                        StatusIndicator(status: item.status, size: 10, borderColor: MoodTheme.serverBar)

                        VStack(alignment: .leading, spacing: 1) {
                            Text(item.label)
                                .font(.system(size: 13))
                                .foregroundStyle(MoodTheme.textPrimary)
                            if !item.description.isEmpty {
                                Text(item.description)
                                    .font(.system(size: 11))
                                    .foregroundStyle(MoodTheme.textMuted)
                            }
                        }

                        Spacer()
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 8)
        .background(MoodTheme.serverBar.opacity(0.95))
        .overlay(Rectangle().fill(MoodTheme.divider).frame(height: 1), alignment: .bottom)
    }
}

struct StatusPanelIcon: View {
    @Binding var isMuted: Bool
    let iconOn: String
    let iconOff: String
    let tooltip: String
    @State private var isHovered = false
    @State private var slashProgress: CGFloat = 0

    var body: some View {
        Button {
            if isMuted {
                withAnimation(.easeIn(duration: 0.2)) { slashProgress = 0 }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { isMuted = false }
            } else {
                isMuted = true
                slashProgress = 0
                withAnimation(.easeOut(duration: 0.25)) { slashProgress = 1 }
            }
        } label: {
            ZStack {
                Image(systemName: iconOn)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(isMuted ? MoodTheme.mentionBadge : MoodTheme.textSecondary)
                    .animation(.easeInOut(duration: 0.15), value: isMuted)

                AnimatedSlash(progress: slashProgress)
                    .stroke(MoodTheme.mentionBadge, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                    .frame(width: 18, height: 18)
            }
            .frame(width: 32, height: 32)
            .background(isHovered ? MoodTheme.hoverBg : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in isHovered = hovering }
        .help(tooltip)
    }
}

struct MuteButton: View {
    @Binding var isMuted: Bool
    let iconOn: String
    let iconOff: String
    let tooltip: String
    @State private var slashProgress: CGFloat = 0

    var body: some View {
        Button {
            if isMuted {
                // Unmute : rétracte la barre puis change l'état
                withAnimation(.easeIn(duration: 0.2)) {
                    slashProgress = 0
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                    isMuted = false
                }
            } else {
                // Mute : change l'état puis trace la barre
                isMuted = true
                slashProgress = 0
                withAnimation(.easeOut(duration: 0.25)) {
                    slashProgress = 1
                }
            }
        } label: {
            ZStack {
                // Icône — toujours la même, change juste de couleur
                Image(systemName: iconOn)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(isMuted ? MoodTheme.mentionBadge : MoodTheme.textPrimary)
                    .animation(.easeInOut(duration: 0.15), value: isMuted)

                // Barre rouge diagonale qui se trace
                AnimatedSlash(progress: slashProgress)
                    .stroke(
                        MoodTheme.mentionBadge,
                        style: StrokeStyle(lineWidth: 2.5, lineCap: .round)
                    )
                    .frame(width: 20, height: 20)
            }
            .frame(width: 30, height: 30)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(tooltip)
    }
}

// MARK: - Custom Status Editor

struct CustomStatusEditor: View {
    @Binding var isPresented: Bool
    @State private var statusText = ""
    @State private var selectedEmoji = "😀"
    @State private var selectedDuration = "Ne pas effacer"

    private let quickEmojis = ["😀", "😴", "🤒", "🏠", "🎮", "📚", "💻", "🎵"]
    private let durations = ["Ne pas effacer", "30 minutes", "1 heure", "4 heures", "Aujourd'hui"]

    var body: some View {
        VStack(spacing: 12) {
            Text("Définir un statut personnalisé")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(MoodTheme.textPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)

            // Emoji + text input
            HStack(spacing: 8) {
                Text(selectedEmoji)
                    .font(.system(size: 20))
                    .frame(width: 36, height: 36)
                    .background(MoodTheme.glassBg)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

                TextField("Quel est ton mood ?", text: $statusText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                    .foregroundStyle(MoodTheme.textPrimary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(MoodTheme.glassBg)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(MoodTheme.glassBorder, lineWidth: 0.5)
                    )
            }

            // Quick emoji selector
            HStack(spacing: 6) {
                ForEach(quickEmojis, id: \.self) { emoji in
                    Button { selectedEmoji = emoji } label: {
                        Text(emoji)
                            .font(.system(size: 16))
                            .frame(width: 28, height: 28)
                            .background(selectedEmoji == emoji ? MoodTheme.selectedBg : Color.clear)
                            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }

            // Duration picker
            HStack {
                Text("Effacer après")
                    .font(.system(size: 12))
                    .foregroundStyle(MoodTheme.textSecondary)

                Picker("", selection: $selectedDuration) {
                    ForEach(durations, id: \.self) { duration in
                        Text(duration).tag(duration)
                    }
                }
                .labelsHidden()
                .frame(width: 140)
            }

            // Buttons
            HStack {
                Button {
                    statusText = ""
                    isPresented = false
                } label: {
                    Text("Effacer le statut")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(MoodTheme.textSecondary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(MoodTheme.glassBg)
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                }
                .buttonStyle(.plain)

                Spacer()

                Button {
                    isPresented = false
                } label: {
                    Text("Enregistrer")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 7)
                        .background(MoodTheme.brandAccent)
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(14)
        .frame(width: 300)
        .background(MoodTheme.channelList)
    }
}

struct AnimatedSlash: Shape {
    var progress: CGFloat

    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let start = CGPoint(x: rect.maxX - 2, y: rect.minY + 2)
        let end = CGPoint(x: rect.minX + 2, y: rect.maxY - 2)
        let current = CGPoint(
            x: start.x + (end.x - start.x) * progress,
            y: start.y + (end.y - start.y) * progress
        )
        path.move(to: start)
        path.addLine(to: current)
        return path
    }
}



#Preview {
    HStack(spacing: 0) {
        ChannelListColumn(
            server: MockData.servers[0],
            selectedChannel: .constant(MockData.servers[0].categories[0].channels[0]),
            showSettings: .constant(false)
        )
        .frame(width: 240)
    }
    .frame(height: 700)
    .environment(MatrixStore())
    .preferredColorScheme(.dark)
}
