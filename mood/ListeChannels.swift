import SwiftUI
import UIKit

// MARK: - Channel List Column

struct ChannelListColumn: View {
    let server: MoodServer
    @Binding var selectedChannel: Channel?
    @Binding var showSettings: Bool
    @State private var showServerMenu = false
    @State private var showInviteModal = false
    @State private var showAllChannels = true
    @State private var hideMutedChannels = false

    var body: some View {
        VStack(spacing: 0) {
            // Header serveur
            HStack(spacing: 0) {
                Button {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        showServerMenu.toggle()
                    }
                } label: {
                    HStack(spacing: 8 * LayoutMetrics.scale) {
                        Text(server.name)
                            .font(.mood(15, weight: .bold))
                            .foregroundStyle(MoodTheme.textPrimary)
                            .lineLimit(1)

                        Image(systemName: showServerMenu ? "chevron.up" : "chevron.down")
                            .font(.mood(10, weight: .semibold))
                            .foregroundStyle(MoodTheme.textPrimary)

                        Spacer(minLength: 0)
                    }
                    .padding(.leading, 16 * LayoutMetrics.scale)
                    .frame(height: LayoutMetrics.desktopHeaderHeight)
                }
                .buttonStyle(.plain)

                Button {
                    showInviteModal = true
                } label: {
                    Image(systemName: "person.badge.plus")
                        .font(.mood(17, weight: .semibold))
                        .foregroundStyle(MoodTheme.textPrimary)
                        .frame(width: 48 * LayoutMetrics.scale, height: LayoutMetrics.desktopHeaderHeight)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Inviter sur le serveur")
            }

            Rectangle()
                .fill(MoodTheme.divider)
                .frame(height: 1)

            // Channels
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 2) {
                    ServerQuickLinks()
                        .padding(.top, 10 * LayoutMetrics.scale)
                        .padding(.bottom, 10 * LayoutMetrics.scale)

                    Rectangle()
                        .fill(MoodTheme.divider)
                        .frame(height: 1)
                        .padding(.horizontal, 14 * LayoutMetrics.scale)
                        .padding(.bottom, 10 * LayoutMetrics.scale)

                    ForEach(server.categories) { category in
                        CategorySection(
                            category: category,
                            server: server,
                            selectedChannel: $selectedChannel
                        )
                    }
                }
                .padding(.top, 10 * LayoutMetrics.scale)
                .padding(.bottom, LayoutMetrics.channelBottomPadding)
            }

            Spacer(minLength: 0)

            // Voice connected panel
            VoiceConnectedPanel()
                .padding(.bottom, LayoutMetrics.channelBottomPadding)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(MoodTheme.channelList)
        .overlay(alignment: .top) {
            if showServerMenu {
                ServerSettingsMenu(
                    server: server,
                    showAllChannels: $showAllChannels,
                    hideMutedChannels: $hideMutedChannels
                ) {
                    withAnimation(.easeOut(duration: 0.14)) { showServerMenu = false }
                    showInviteModal = true
                }
                .padding(.top, 53 * LayoutMetrics.scale)
                .transition(
                    .opacity.combined(
                        with: .scale(scale: 0.985, anchor: .top)
                    )
                )
                .zIndex(100)
            }
        }
        .sheet(isPresented: $showInviteModal) {
            InviteModal(isPresented: $showInviteModal, serverName: server.name)
        }
        .onChange(of: server.id) { _, _ in
            showServerMenu = false
        }
    }
}

// MARK: - Discord-like Server Shortcuts

struct ServerQuickLinks: View {
    var body: some View {
        VStack(spacing: 2) {
            ServerQuickLinkRow(icon: "calendar.badge.plus", label: "Événements")
            ServerQuickLinkRow(icon: "diamond.fill", label: "Boosts de serveur")
        }
    }
}

struct ServerQuickLinkRow: View {
    let icon: String
    let label: String
    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 12 * LayoutMetrics.scale) {
            Image(systemName: icon)
                .font(.mood(16))
                .foregroundStyle(MoodTheme.textSecondary)
                .frame(width: 20 * LayoutMetrics.scale)

            Text(label)
                .font(.mood(14, weight: .medium))
                .foregroundStyle(MoodTheme.textSecondary)

            Spacer()
        }
        .padding(.horizontal, 12 * LayoutMetrics.scale)
        .padding(.top, 7 * LayoutMetrics.scale)
        .padding(.bottom, 9 * LayoutMetrics.scale)
        .background(isHovered ? MoodTheme.hoverBg : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
        .padding(.horizontal, 8)
        .contentShape(Rectangle())
        .onHover { hovering in isHovered = hovering }
    }
}

// MARK: - Server Settings Menu

struct ServerSettingsMenu: View {
    let server: MoodServer
    @Binding var showAllChannels: Bool
    @Binding var hideMutedChannels: Bool
    let onInvite: () -> Void
    @State private var showComingSoon = false
    @State private var showLeaveConfirm = false
    @State private var copiedServerID = false

    private var serverTag: String {
        let letters = server.name
            .filter { $0.isLetter || $0.isNumber }
            .prefix(3)
        return String(letters).uppercased()
    }

    var body: some View {
        VStack(spacing: 0) {
            ServerMenuItem(icon: "hexagon", label: "Boosts de serveur") {
                showComingSoon = true
            }

            ServerTagMenuItem(tag: serverTag) {
                showComingSoon = true
            }

            ServerMenuDivider()

            ServerMenuItem(icon: "person.badge.plus", label: "Inviter sur le serveur") {
                onInvite()
            }
            ServerMenuItem(icon: "square.grid.2x2", label: "Répertoire d’applications") {
                showComingSoon = true
            }

            ServerMenuDivider()

            ServerMenuItem(icon: "eye", label: "Montrer tous les salons", isChecked: showAllChannels) {
                showAllChannels.toggle()
            }
            ServerMenuItem(icon: "bell.fill", label: "Paramètres de notification") {
                showComingSoon = true
            }
            ServerMenuItem(icon: "shield", label: "Paramètres de confidentialité") {
                showComingSoon = true
            }

            ServerMenuDivider()

            ServerMenuItem(icon: "pencil", label: "Modifier le profil par serveur") {
                showComingSoon = true
            }
            ServerMenuItem(
                icon: hideMutedChannels ? "eye" : "eye.slash",
                label: "Masquer les salons muets",
                isChecked: hideMutedChannels
            ) {
                hideMutedChannels.toggle()
            }

            ServerMenuDivider()

            ServerMenuItem(
                icon: "rectangle.portrait.and.arrow.right",
                label: "Quitter le serveur",
                color: MoodTheme.serverMenuDanger,
                iconColor: MoodTheme.serverMenuDanger
            ) {
                showLeaveConfirm = true
            }

            ServerMenuDivider()

            ServerMenuItem(
                icon: copiedServerID ? "checkmark.square.fill" : "",
                label: copiedServerID ? "Identifiant copié" : "Copier l’identifiant du serveur",
                leadingBadge: copiedServerID ? nil : "ID"
            ) {
                UIPasteboard.general.string = server.id.uuidString
                copiedServerID = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                    copiedServerID = false
                }
            }
        }
        .padding(.vertical, 8 * LayoutMetrics.scale)
        .frame(width: 220 * LayoutMetrics.scale)
        .background(MoodTheme.serverMenuBackground)
        .clipShape(RoundedRectangle(cornerRadius: 8 * LayoutMetrics.scale, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8 * LayoutMetrics.scale, style: .continuous)
                .strokeBorder(MoodTheme.serverMenuBorder, lineWidth: 1 * LayoutMetrics.scale)
        }
        .shadow(color: .black.opacity(0.48), radius: 14 * LayoutMetrics.scale, y: 7 * LayoutMetrics.scale)
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
    var color: Color = MoodTheme.textPrimary
    var iconColor: Color = MoodTheme.textSupporting
    var isChecked: Bool? = nil
    var leadingBadge: String? = nil
    var action: () -> Void = {}
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8 * LayoutMetrics.scale) {
                Group {
                    if let leadingBadge {
                        Text(leadingBadge)
                            .font(.mood(9, weight: .bold))
                            .foregroundStyle(MoodTheme.serverMenuBackground)
                            .frame(width: 16 * LayoutMetrics.scale, height: 16 * LayoutMetrics.scale)
                            .background(MoodTheme.textSupporting)
                            .clipShape(RoundedRectangle(cornerRadius: 2 * LayoutMetrics.scale, style: .continuous))
                    } else {
                        Image(systemName: icon)
                            .font(.mood(16, weight: .medium))
                            .foregroundStyle(isHovered ? .white : iconColor)
                    }
                }
                .frame(width: 20 * LayoutMetrics.scale)

                Text(label)
                    .font(.mood(14, weight: .medium))
                    .foregroundStyle(isHovered ? .white : color)
                    .lineLimit(1)
                    .truncationMode(.tail)

                Spacer(minLength: 4 * LayoutMetrics.scale)

                if let isChecked {
                    ServerMenuCheckbox(isChecked: isChecked)
                }
            }
            .padding(.horizontal, 10.5 * LayoutMetrics.scale)
            .frame(height: 36 * LayoutMetrics.scale)
            .background(isHovered ? MoodTheme.serverMenuHover : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
            .padding(.horizontal, 6 * LayoutMetrics.scale)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.1)) {
                isHovered = hovering
            }
        }
    }
}

struct ServerTagMenuItem: View {
    let tag: String
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8 * LayoutMetrics.scale) {
                HStack(spacing: 3 * LayoutMetrics.scale) {
                    Image(systemName: "bolt.fill")
                        .font(.mood(10, weight: .bold))
                    Text(tag)
                        .font(.mood(12, weight: .semibold))
                        .lineLimit(1)
                }
                .foregroundStyle(MoodTheme.textSupporting)
                .padding(.horizontal, 6 * LayoutMetrics.scale)
                .frame(height: 16 * LayoutMetrics.scale)
                .background(MoodTheme.serverMenuTagBackground)
                .clipShape(RoundedRectangle(cornerRadius: 4 * LayoutMetrics.scale, style: .continuous))

                Text("Tag du serveur")
                    .font(.mood(14, weight: .medium))
                    .foregroundStyle(isHovered ? .white : MoodTheme.textPrimary)
                    .lineLimit(1)

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10.5 * LayoutMetrics.scale)
            .frame(height: 36 * LayoutMetrics.scale)
            .background(isHovered ? MoodTheme.serverMenuHover : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
            .padding(.horizontal, 6 * LayoutMetrics.scale)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.1)) {
                isHovered = hovering
            }
        }
    }
}

struct ServerMenuCheckbox: View {
    let isChecked: Bool

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 4 * LayoutMetrics.scale, style: .continuous)
                .fill(isChecked ? MoodTheme.brandAccent : MoodTheme.serverMenuCheckboxBackground)
                .overlay {
                    if !isChecked {
                        RoundedRectangle(cornerRadius: 4 * LayoutMetrics.scale, style: .continuous)
                            .strokeBorder(MoodTheme.serverMenuCheckboxBorder, lineWidth: 1 * LayoutMetrics.scale)
                    }
                }

            if isChecked {
                Image(systemName: "checkmark")
                    .font(.mood(12, weight: .bold))
                    .foregroundStyle(.white)
            }
        }
        .frame(width: 20 * LayoutMetrics.scale, height: 20 * LayoutMetrics.scale)
        .animation(.easeInOut(duration: 0.12), value: isChecked)
    }
}

struct ServerMenuDivider: View {
    var body: some View {
        Rectangle()
            .fill(MoodTheme.serverMenuSeparator)
            .frame(height: 1 * LayoutMetrics.scale)
            .padding(.horizontal, 9 * LayoutMetrics.scale)
            .padding(.vertical, 8 * LayoutMetrics.scale)
    }
}

// MARK: - Category Section

struct CategorySection: View {
    let category: ChannelCategory
    let server: MoodServer
    @Binding var selectedChannel: Channel?
    @State private var isExpanded = true

    private var categoryTitle: String {
        let channels = category.channels
        if !channels.isEmpty && channels.allSatisfy({ $0.type == .voice }) {
            return "SALONS VOCAUX"
        }
        if channels.contains(where: { $0.type == .text || $0.type == .announcement }) {
            return "SALONS TEXTUELS"
        }
        return category.name.uppercased()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Button {
                withAnimation(.easeInOut(duration: 0.12)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(spacing: 4 * LayoutMetrics.scale) {
                    Image(systemName: "chevron.right")
                        .font(.mood(8, weight: .bold))
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))

                    Text(categoryTitle)
                        .font(.mood(11, weight: .semibold))
                        .tracking(0.5)

                    Spacer()

                    Image(systemName: "plus")
                        .font(.mood(11))
                        .opacity(0.5)
                }
                .foregroundStyle(MoodTheme.textSecondary)
                .padding(.horizontal, 14 * LayoutMetrics.scale)
                .padding(.vertical, 6 * LayoutMetrics.scale)
                .padding(.top, 16 * LayoutMetrics.scale)
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
                                    HStack(spacing: 8 * LayoutMetrics.scale) {
                                        Text(user.avatarEmoji)
                                            .font(.mood(12))
                                            .frame(width: 24 * LayoutMetrics.scale, height: 24 * LayoutMetrics.scale)
                                            .background(MoodTheme.glassBg)
                                            .clipShape(Circle())

                                        Text(user.displayName)
                                            .font(.mood(13))
                                            .foregroundStyle(MoodTheme.textSecondary)
                                            .lineLimit(1)

                                        Spacer()

                                        // Live badge (like Discord "EN DIRECT")
                                        if user.activity != nil {
                                            Text("EN DIRECT")
                                                .font(.mood(9, weight: .bold))
                                                .foregroundStyle(.white)
                                                .padding(.horizontal, 5 * LayoutMetrics.scale)
                                                .padding(.vertical, 2 * LayoutMetrics.scale)
                                                .background(MoodTheme.mentionBadge)
                                                .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
                                        }

                                        Image(systemName: "mic.fill")
                                            .font(.mood(9))
                                            .foregroundStyle(MoodTheme.textMuted)
                                    }
                                    .padding(.horizontal, 10 * LayoutMetrics.scale)
                                    .padding(.vertical, 3 * LayoutMetrics.scale)
                                }
                            }
                            .padding(.leading, 32 * LayoutMetrics.scale)
                            .padding(.horizontal, 8 * LayoutMetrics.scale)
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

    private var unreadBadgeCount: Int { max(channel.unreadCount, channel.mentionCount) }
    private var isUnread: Bool { unreadBadgeCount > 0 }

    var body: some View {
        HStack(spacing: 8 * LayoutMetrics.scale) {
            Image(systemName: channel.icon)
                .font(.mood(15))
                .foregroundStyle(isUnread ? MoodTheme.textPrimary : MoodTheme.textSecondary)
                .frame(width: 20 * LayoutMetrics.scale)

            Text(channel.name)
                .font(.mood(15))
                .fontWeight(isUnread ? .semibold : .regular)
                .foregroundStyle(isUnread ? MoodTheme.textPrimary : MoodTheme.textSecondary)
                .lineLimit(1)

            if channel.isE2E {
                Image(systemName: "lock.fill")
                    .font(.mood(7))
                    .foregroundStyle(MoodTheme.textMuted.opacity(0.4))
            }

            Spacer()

            if isSelected || isHovered {
                HStack(spacing: 5 * LayoutMetrics.scale) {
                    Image(systemName: "person.badge.plus")
                        .font(.mood(13, weight: .semibold))
                        .foregroundStyle(MoodTheme.textPrimary)
                        .frame(width: 16 * LayoutMetrics.scale)

                    Image(systemName: "gearshape.fill")
                        .font(.mood(13, weight: .semibold))
                        .foregroundStyle(MoodTheme.textPrimary)
                        .frame(width: 16 * LayoutMetrics.scale)
                }
            } else if isUnread {
                Text("\(unreadBadgeCount)")
                    .font(.mood(10, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 5 * LayoutMetrics.scale)
                    .padding(.vertical, 2 * LayoutMetrics.scale)
                    .background(MoodTheme.mentionBadge)
                    .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
            }
        }
        .padding(.horizontal, 8 * LayoutMetrics.scale)
        .frame(height: 32 * LayoutMetrics.scale)
        .background(
            isSelected && isUnread ? MoodTheme.channelSelectedBg :
            isHovered ? MoodTheme.hoverBg :
            Color.clear
        )
        .clipShape(RoundedRectangle(cornerRadius: 8 * LayoutMetrics.scale, style: .continuous))
        .padding(.horizontal, 8 * LayoutMetrics.scale)
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
    // The panel only appears after a real voice join. Starting disconnected
    // matches Discord's normal text-channel state and avoids a phantom call.
    @State private var isConnected = false

    var body: some View {
        if isConnected {
            VStack(spacing: 4 * LayoutMetrics.scale) {
                // Ligne 1 : Voix connectée + signal + timer
                HStack(spacing: 6 * LayoutMetrics.scale) {
                    Circle()
                        .fill(MoodTheme.onlineGreen)
                        .frame(width: 8 * LayoutMetrics.scale, height: 8 * LayoutMetrics.scale)

                    Text("Voix connectée")
                        .font(.mood(12, weight: .semibold))
                        .foregroundStyle(MoodTheme.onlineGreen)

                    Spacer()

                    // Timer
                    Text(formattedDuration)
                        .font(.mood(11, weight: .medium, design: .monospaced))
                        .foregroundStyle(MoodTheme.textSupporting)

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
                HStack(spacing: 6 * LayoutMetrics.scale) {
                    Image(systemName: "speaker.wave.2")
                        .font(.mood(10))
                        .foregroundStyle(MoodTheme.textSecondary)

                    Text("lounge / Design Club")
                        .font(.mood(11))
                        .foregroundStyle(MoodTheme.textSecondary)
                        .lineLimit(1)

                    Spacer()

                    if isScreenSharing {
                        Text("Partage")
                            .font(.mood(9, weight: .semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 6 * LayoutMetrics.scale)
                            .padding(.vertical, 2 * LayoutMetrics.scale)
                            .background(MoodTheme.brandAccent)
                            .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                    }

                    if isCameraOn {
                        Text("Caméra")
                            .font(.mood(9, weight: .semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 6 * LayoutMetrics.scale)
                            .padding(.vertical, 2 * LayoutMetrics.scale)
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
            .padding(.horizontal, 10 * LayoutMetrics.scale)
            .padding(.vertical, 8 * LayoutMetrics.scale)
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
                .font(.mood(13))
                .foregroundStyle(fgColor)
                .frame(width: 32 * LayoutMetrics.scale, height: 32 * LayoutMetrics.scale)
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
        VStack(alignment: .leading, spacing: 8) {
            // Status picker popup
            if showStatusPicker {
                StatusPickerMenu(showPicker: $showStatusPicker)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .padding(.leading, 2)
            }

            HStack(spacing: 8 * LayoutMetrics.scale) {
                // Avatar circle (clickable for status)
                Button {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        showStatusPicker.toggle()
                    }
                } label: {
                    ZStack(alignment: .bottomTrailing) {
                        Text(user.avatarEmoji)
                            .font(.mood(18))
                            .frame(width: 32 * LayoutMetrics.scale, height: 32 * LayoutMetrics.scale)
                            .background(MoodTheme.hoverBg)
                            .clipShape(Circle())

                        StatusIndicator(status: user.status, size: 8 * LayoutMetrics.scale, borderColor: MoodTheme.inputBg)
                            .offset(x: 2, y: 2)
                    }
                }
                .buttonStyle(.plain)
                .help("Changer le statut")

                VStack(alignment: .leading, spacing: 1) {
                    Text(user.displayName)
                        .font(.mood(14, weight: .semibold))
                        .foregroundStyle(MoodTheme.textPrimary)
                        .lineLimit(1)
                    Text(user.status.rawValue)
                        .font(.mood(12))
                        .foregroundStyle(MoodTheme.textSupporting)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                HStack(spacing: 8 * LayoutMetrics.scale) {
                    HStack(spacing: 1 * LayoutMetrics.scale) {
                        UserPanelControl(
                            icon: isMicMuted ? "mic.slash.fill" : "mic.fill",
                            isActive: isMicMuted,
                            isDestructive: isMicMuted,
                            help: "Micro"
                        ) { isMicMuted.toggle() }

                        UserPanelControl(
                            icon: "chevron.down",
                            compact: true,
                            isActive: isMicMuted,
                            isDestructive: isMicMuted,
                            help: "Périphériques d’entrée"
                        ) {}
                    }

                    HStack(spacing: 1 * LayoutMetrics.scale) {
                        UserPanelControl(
                            icon: isDeafened ? "speaker.slash.fill" : "headphones",
                            isActive: isDeafened,
                            isDestructive: isDeafened,
                            help: "Casque"
                        ) {
                            isDeafened.toggle()
                            if isDeafened { isMicMuted = true }
                        }

                        UserPanelControl(
                            icon: "chevron.down",
                            compact: true,
                            isActive: isDeafened,
                            isDestructive: isDeafened,
                            help: "Périphériques de sortie"
                        ) {}
                    }

                    UserPanelControl(icon: "gearshape.fill", help: "Paramètres utilisateur") {
                        showSettings = true
                    }
                }
            }
            .padding(.leading, 12 * LayoutMetrics.scale)
            .padding(.trailing, 13 * LayoutMetrics.scale)
            .frame(height: LayoutMetrics.userPanelHeight)
            .background(MoodTheme.glassBg)
            .clipShape(RoundedRectangle(cornerRadius: 8 * LayoutMetrics.scale, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 8 * LayoutMetrics.scale, style: .continuous)
                    .strokeBorder(MoodTheme.glassBorder, lineWidth: 1 * LayoutMetrics.scale)
            }
            .shadow(color: .black.opacity(0.28), radius: 12, y: 5)
        }
        .frame(width: LayoutMetrics.userPanelWidth, alignment: .bottomLeading)
        .zIndex(10)
    }
}

struct UserPanelControl: View {
    let icon: String
    var compact = false
    var isActive = false
    var isDestructive = false
    let help: String
    let action: () -> Void
    @State private var isHovered = false

    private var foreground: Color {
        if isDestructive { return Color(hex: "da3e44") }
        if isActive { return MoodTheme.textPrimary }
        return MoodTheme.textSupporting
    }

    private var background: Color {
        if isDestructive {
            return isHovered ? Color(hex: "432b2f") : Color(hex: "372327")
        }
        if isActive {
            return MoodTheme.selectedBg
        }
        return isHovered ? MoodTheme.hoverBg : Color.clear
    }

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.mood(compact ? 10 : 14, weight: .semibold))
                .foregroundStyle(foreground)
                .frame(width: (compact ? 16 : 32) * LayoutMetrics.scale, height: 32 * LayoutMetrics.scale)
                .background(background)
                .clipShape(RoundedRectangle(cornerRadius: 6 * LayoutMetrics.scale, style: .continuous))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in isHovered = hovering }
        .help(help)
    }
}

// MARK: - Status Picker Menu

struct StatusPickerMenu: View {
    @Binding var showPicker: Bool
    @State private var showCustomStatus = false

    private let statuses: [(status: MoodUser.UserStatus, label: String, description: String)] = [
        (.online, "En ligne", ""),
        (.idle, "Inactif", ""),
        (.dnd, "Ne pas déranger", "Tu ne recevras pas de notifications"),
        (.invisible, "Invisible", "Tu apparaîtras hors ligne"),
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
                    .font(.mood(13, weight: .medium))
                    .foregroundStyle(isMuted ? MoodTheme.mentionBadge : MoodTheme.textSecondary)
                    .animation(.easeInOut(duration: 0.15), value: isMuted)

                AnimatedSlash(progress: slashProgress)
                    .stroke(MoodTheme.mentionBadge, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                    .frame(width: 18 * LayoutMetrics.scale, height: 18 * LayoutMetrics.scale)
            }
            .frame(width: 32 * LayoutMetrics.scale, height: 32 * LayoutMetrics.scale)
            .background(isMuted ? MoodTheme.mentionBadge.opacity(0.18) : (isHovered ? MoodTheme.hoverBg : Color.clear))
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
