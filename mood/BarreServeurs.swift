import SwiftUI
import UIKit

// MARK: - Server Sidebar

struct ServerSidebarView: View {
    let servers: [MoodServer]
    @Binding var selectedServer: MoodServer?
    @Binding var showDMs: Bool
    @Binding var selectedChannel: Channel?
    @Binding var showCreateServer: Bool
    @Binding var showExplore: Bool
    var dmUnreadCount: Int = 0

    var body: some View {
        VStack(spacing: 0) {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 6) {
                    // Home / DMs — Logo Mood (deux points)
                    Button {
                        showDMs = true
                        selectedServer = nil
                    } label: {
                        ZStack(alignment: .bottomTrailing) {
                            ZStack {
                                MoodLogoDots(dotSize: 9, spacing: 5)
                            }
                            .frame(width: 48, height: 48)
                            .background(
                                showDMs ? MoodTheme.brandAccent :
                                MoodTheme.glassBg
                            )
                            .clipShape(RoundedRectangle(cornerRadius: showDMs ? 16 : 25, style: .continuous))
                            .animation(.easeInOut(duration: 0.2), value: showDMs)

                            // Badge mentions DMs
                            if dmUnreadCount > 0 {
                                Text("\(dmUnreadCount)")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 5)
                                    .padding(.vertical, 2)
                                    .background(MoodTheme.mentionBadge)
                                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                                            .stroke(MoodTheme.serverBar, lineWidth: 2.5)
                                    )
                                    .offset(x: 6, y: 6)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    .help("Messages privés")
                    // Pill indicator gauche
                    .overlay(alignment: .leading) {
                        if showDMs {
                            RoundedRectangle(cornerRadius: 3, style: .continuous)
                                .fill(MoodTheme.textPrimary)
                                .frame(width: 3, height: 36)
                                .offset(x: -12)
                        }
                    }

                    // Séparateur
                    RoundedRectangle(cornerRadius: 2)
                        .fill(MoodTheme.divider)
                        .frame(width: 32, height: 2)
                        .padding(.vertical, 4)

                    // Serveurs (premiers 3 individuels)
                    ForEach(servers.prefix(3)) { server in
                        SidebarIcon(
                            emoji: server.iconEmoji,
                            isSelected: !showDMs && selectedServer?.id == server.id,
                            hasUnread: server.hasUnread,
                            mentionCount: server.mentionCount
                        ) {
                            selectedServer = server
                            showDMs = false
                            selectedChannel = server.categories.first?.channels.first
                        }
                        .help(server.name)
                    }

                    // Dossier de serveurs (derniers 2)
                    ServerFolder(
                        servers: Array(servers.suffix(2)),
                        selectedServer: $selectedServer,
                        showDMs: $showDMs,
                        selectedChannel: $selectedChannel
                    )

                    // Séparateur
                    RoundedRectangle(cornerRadius: 2)
                        .fill(MoodTheme.divider)
                        .frame(width: 32, height: 2)
                        .padding(.vertical, 4)

                    // Ajouter
                    SidebarIcon(
                        systemIcon: "plus",
                        isSelected: false,
                        hasUnread: false,
                        mentionCount: 0,
                        iconColor: MoodTheme.onlineGreen
                    ) { showCreateServer = true }
                    .help("Ajouter un serveur")

                    // Explorer
                    SidebarIcon(
                        systemIcon: "safari",
                        isSelected: showExplore,
                        hasUnread: false,
                        mentionCount: 0,
                        iconColor: MoodTheme.onlineGreen
                    ) {
                        showExplore = true
                        showDMs = false
                        selectedServer = nil
                    }
                    .help("Explorer les serveurs")
                }
                .padding(.vertical, 12)
                .padding(.horizontal, 10)
            }

            Spacer()
        }
        .frame(width: 72)
        .background(MoodTheme.serverBar)
    }
}

// MARK: - Sidebar Icon (carré arrondi / squircle)

struct SidebarIcon: View {
    var emoji: String?
    var systemIcon: String?
    let isSelected: Bool
    let hasUnread: Bool
    let mentionCount: Int
    var iconColor: Color = MoodTheme.textPrimary
    let action: () -> Void

    @State private var isHovered = false
    @State private var isMuted = false
    @State private var showComingSoon = false
    @State private var showLeaveConfirm = false
    @State private var markedAsRead = false
    @State private var hideMutedChannels = false

    // Discord: cercle par défaut, squircle au hover/sélection
    private var cornerRadius: CGFloat {
        isSelected ? 16 : (isHovered ? 16 : 25)
    }

    var body: some View {
        Button(action: action) {
            ZStack(alignment: .bottomTrailing) {
                Group {
                    if let emoji = emoji {
                        Text(emoji)
                            .font(.title2)
                    } else if let icon = systemIcon {
                        Image(systemName: icon)
                            .font(.system(size: 20, weight: .medium))
                            .foregroundStyle(isHovered ? .white : iconColor)
                    }
                }
                .frame(width: 48, height: 48)
                .background(
                    isSelected ? MoodTheme.brandAccent :
                    isHovered ? MoodTheme.brandAccent.opacity(0.5) :
                    MoodTheme.glassBg
                )
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                .animation(.easeInOut(duration: 0.2), value: isSelected)
                .animation(.easeInOut(duration: 0.2), value: isHovered)

                // Badge mentions
                if mentionCount > 0 {
                    Text("\(mentionCount)")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(MoodTheme.mentionBadge)
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .stroke(MoodTheme.serverBar, lineWidth: 2.5)
                        )
                        .offset(x: 6, y: 6)
                }
            }
        }
        .buttonStyle(.plain)
        .onHover { hovering in isHovered = hovering }
        // Pill indicator gauche
        .overlay(alignment: .leading) {
            if hasUnread || isSelected {
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(MoodTheme.textPrimary)
                    .frame(width: 3, height: isSelected ? 36 : (isHovered ? 18 : 6))
                    .offset(x: -12)
                    .animation(.easeInOut(duration: 0.2), value: isSelected)
                    .animation(.easeInOut(duration: 0.2), value: isHovered)
            }
        }
        .contextMenu {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) { markedAsRead = true }
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                    withAnimation { markedAsRead = false }
                }
            } label: { Label(markedAsRead ? "Marqué !" : "Marquer comme lu", systemImage: markedAsRead ? "checkmark.circle.fill" : "checkmark.circle") }
            Divider()
            Button { showComingSoon = true } label: { Label("Inviter des gens", systemImage: "person.badge.plus") }
            Button { isMuted.toggle() } label: { Label(isMuted ? "Rétablir le son" : "Rendre muet", systemImage: isMuted ? "bell" : "bell.slash") }
            Button { showComingSoon = true } label: { Label("Paramètres de notification", systemImage: "bell") }
            Button { showComingSoon = true } label: { Label("Confidentialité", systemImage: "shield") }
            Divider()
            Button { showComingSoon = true } label: { Label("Modifier le profil serveur", systemImage: "pencil") }
            Button { hideMutedChannels.toggle() } label: { Label(hideMutedChannels ? "Afficher les channels muets" : "Masquer les channels muets", systemImage: hideMutedChannels ? "eye" : "eye.slash") }
            Divider()
            Button(role: .destructive) { showLeaveConfirm = true } label: { Label("Quitter le serveur", systemImage: "rectangle.portrait.and.arrow.right") }
        }
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

// MARK: - Server Folder

struct ServerFolder: View {
    let servers: [MoodServer]
    @Binding var selectedServer: MoodServer?
    @Binding var showDMs: Bool
    @Binding var selectedChannel: Channel?
    @State private var isExpanded = false
    @State private var isHovered = false

    private var totalMentions: Int {
        servers.reduce(0) { $0 + $1.mentionCount }
    }

    private var hasUnread: Bool {
        servers.contains { $0.hasUnread }
    }

    var body: some View {
        VStack(spacing: 4) {
            // Folder icon (collapsed) or expanded servers
            if isExpanded {
                VStack(spacing: 4) {
                    ForEach(servers) { server in
                        SidebarIcon(
                            emoji: server.iconEmoji,
                            isSelected: !showDMs && selectedServer?.id == server.id,
                            hasUnread: server.hasUnread,
                            mentionCount: server.mentionCount
                        ) {
                            selectedServer = server
                            showDMs = false
                            selectedChannel = server.categories.first?.channels.first
                        }
                    }
                }
                .padding(6)
                .background(MoodTheme.glassBg)
                .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                .onTapGesture {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isExpanded = false
                    }
                }
            } else {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isExpanded = true
                    }
                } label: {
                    ZStack(alignment: .bottomTrailing) {
                        // Mini 2x2 grid of server emojis
                        LazyVGrid(columns: [GridItem(.fixed(20)), GridItem(.fixed(20))], spacing: 3) {
                            ForEach(servers.prefix(4)) { server in
                                Text(server.iconEmoji)
                                    .font(.system(size: 12))
                            }
                        }
                        .frame(width: 48, height: 48)
                        .background(
                            isHovered ? MoodTheme.brandAccent.opacity(0.5) : MoodTheme.glassBg
                        )
                        .clipShape(RoundedRectangle(cornerRadius: isHovered ? 16 : 25, style: .continuous))
                        .animation(.easeInOut(duration: 0.2), value: isHovered)

                        if totalMentions > 0 {
                            Text("\(totalMentions)")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 2)
                                .background(MoodTheme.mentionBadge)
                                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                                        .stroke(MoodTheme.serverBar, lineWidth: 2.5)
                                )
                                .offset(x: 6, y: 6)
                        }
                    }
                }
                .buttonStyle(.plain)
                .onHover { hovering in isHovered = hovering }
                .overlay(alignment: .leading) {
                    if hasUnread {
                        RoundedRectangle(cornerRadius: 3, style: .continuous)
                            .fill(MoodTheme.textPrimary)
                            .frame(width: 3, height: isHovered ? 18 : 6)
                            .offset(x: -12)
                            .animation(.easeInOut(duration: 0.2), value: isHovered)
                    }
                }
            }
        }
    }
}

// MARK: - Create Server Modal

struct CreateServerModal: View {
    @Environment(\.layoutMode) private var layoutMode
    @Binding var isPresented: Bool
    @State private var step = 0 // 0 = choice, 1 = create, 2 = join
    @State private var serverName = ""
    @State private var inviteLink = ""
    @State private var selectedTemplate = ""
    @State private var isPublic = false
    @State private var showCreated = false
    @State private var showJoined = false

    let templates = [
        ("gamecontroller", "Gaming", Color.purple),
        ("graduationcap", "Études", Color.blue),
        ("music.note", "Musique", Color.pink),
        ("person.3", "Amis", Color.green),
        ("lightbulb", "Communauté", Color.orange),
        ("wrench.and.screwdriver", "Créateurs", Color.red),
    ]

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                if step > 0 {
                    Button {
                        withAnimation(.easeInOut(duration: 0.15)) { step = 0 }
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 12))
                            .foregroundStyle(MoodTheme.textPrimary)
                    }
                    .buttonStyle(.plain)
                }

                Spacer()

                Button {
                    isPresented = false
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 12))
                        .foregroundStyle(MoodTheme.textPrimary)
                        .frame(width: 28, height: 28)
                        .background(MoodTheme.glassBg)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)

            if step == 0 {
                // Choice screen
                VStack(spacing: 16) {
                    Text("Créer ou rejoindre\nun serveur")
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(MoodTheme.textPrimary)
                        .multilineTextAlignment(.center)

                    Text("Un serveur c'est ton espace avec tes amis. Crée le tien ou rejoins-en un.")
                        .font(.system(size: 13))
                        .foregroundStyle(MoodTheme.textSecondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 20)

                    VStack(spacing: 8) {
                        ModalButton(title: "Créer mon serveur", icon: "plus.circle.fill", color: MoodTheme.brandAccent) {
                            withAnimation(.easeInOut(duration: 0.15)) { step = 1 }
                        }

                        ModalButton(title: "Rejoindre un serveur", icon: "link.circle.fill", color: MoodTheme.brandBlue) {
                            withAnimation(.easeInOut(duration: 0.15)) { step = 2 }
                        }
                    }
                    .padding(.top, 8)
                }
                .padding(20)
            } else if step == 1 {
                // Create server
                VStack(spacing: 16) {
                    Text("Personnalise ton serveur")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(MoodTheme.textPrimary)

                    Text("Choisis un template pour commencer")
                        .font(.system(size: 13))
                        .foregroundStyle(MoodTheme.textSecondary)

                    // Templates
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                        ForEach(templates, id: \.1) { icon, name, color in
                            Button {
                                selectedTemplate = name
                            } label: {
                                HStack(spacing: 8) {
                                    Image(systemName: icon)
                                        .font(.system(size: 14))
                                        .foregroundStyle(color)
                                    Text(name)
                                        .font(.system(size: 13))
                                        .foregroundStyle(MoodTheme.textPrimary)
                                    Spacer()
                                }
                                .padding(10)
                                .background(selectedTemplate == name ? color.opacity(0.15) : MoodTheme.glassBg)
                                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                                        .stroke(selectedTemplate == name ? color.opacity(0.4) : MoodTheme.glassBorder, lineWidth: 0.5)
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    // Server name
                    VStack(alignment: .leading, spacing: 6) {
                        Text("NOM DU SERVEUR")
                            .font(.system(size: 11, weight: .bold))
                            .tracking(0.4)
                            .foregroundStyle(MoodTheme.textSecondary)

                        TextField("Mon super serveur", text: $serverName)
                            .textFieldStyle(.plain)
                            .font(.system(size: 14))
                            .foregroundStyle(MoodTheme.textPrimary)
                            .padding(10)
                            .background(MoodTheme.glassBg)
                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .stroke(MoodTheme.glassBorder, lineWidth: 0.5)
                            )
                    }

                    // Privé / Public
                    VStack(alignment: .leading, spacing: 6) {
                        Text("VISIBILITÉ")
                            .font(.system(size: 11, weight: .bold))
                            .tracking(0.4)
                            .foregroundStyle(MoodTheme.textSecondary)

                        HStack(spacing: 8) {
                            Button {
                                withAnimation(.easeInOut(duration: 0.15)) { isPublic = false }
                            } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: "lock.fill")
                                        .font(.system(size: 12))
                                    Text("Privé")
                                        .font(.system(size: 13, weight: .medium))
                                }
                                .foregroundStyle(!isPublic ? .white : MoodTheme.textSecondary)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 7)
                                .background(!isPublic ? MoodTheme.brandAccent : MoodTheme.glassBg)
                                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                                        .stroke(!isPublic ? Color.clear : MoodTheme.glassBorder, lineWidth: 0.5)
                                )
                            }
                            .buttonStyle(.plain)

                            Button {
                                withAnimation(.easeInOut(duration: 0.15)) { isPublic = true }
                            } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: "globe")
                                        .font(.system(size: 12))
                                    Text("Public")
                                        .font(.system(size: 13, weight: .medium))
                                }
                                .foregroundStyle(isPublic ? .white : MoodTheme.textSecondary)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 7)
                                .background(isPublic ? MoodTheme.brandAccent : MoodTheme.glassBg)
                                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                                        .stroke(isPublic ? Color.clear : MoodTheme.glassBorder, lineWidth: 0.5)
                                )
                            }
                            .buttonStyle(.plain)

                            Spacer()
                        }

                        Text(isPublic ? "Tout le monde peut trouver et rejoindre ce serveur." : "Seules les personnes invitées peuvent rejoindre.")
                            .font(.system(size: 11))
                            .foregroundStyle(MoodTheme.textSecondary)
                    }

                    Button {
                        showCreated = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                            isPresented = false
                        }
                    } label: {
                        HStack(spacing: 6) {
                            if showCreated {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 12, weight: .bold))
                            }
                            Text(showCreated ? "Serveur créé !" : "Créer")
                                .font(.system(size: 14, weight: .semibold))
                        }
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(showCreated ? MoodTheme.onlineGreen : MoodTheme.brandAccent)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .animation(.easeInOut(duration: 0.2), value: showCreated)
                    }
                    .buttonStyle(.plain)
                    .disabled(serverName.isEmpty)
                    .opacity(serverName.isEmpty && !showCreated ? 0.5 : 1)
                }
                .padding(20)
            } else {
                // Join server
                VStack(spacing: 16) {
                    Text("Rejoindre un serveur")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(MoodTheme.textPrimary)

                    Text("Entre un lien d'invitation pour rejoindre un serveur existant")
                        .font(.system(size: 13))
                        .foregroundStyle(MoodTheme.textSecondary)
                        .multilineTextAlignment(.center)

                    VStack(alignment: .leading, spacing: 6) {
                        Text("LIEN D'INVITATION")
                            .font(.system(size: 11, weight: .bold))
                            .tracking(0.4)
                            .foregroundStyle(MoodTheme.textSecondary)

                        TextField("https://mood.app/invite/abc123", text: $inviteLink)
                            .textFieldStyle(.plain)
                            .font(.system(size: 14))
                            .foregroundStyle(MoodTheme.textPrimary)
                            .padding(10)
                            .background(MoodTheme.glassBg)
                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .stroke(MoodTheme.glassBorder, lineWidth: 0.5)
                            )
                    }

                    Button {
                        showJoined = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                            isPresented = false
                        }
                    } label: {
                        HStack(spacing: 6) {
                            if showJoined {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 12, weight: .bold))
                            }
                            Text(showJoined ? "Rejoint !" : "Rejoindre le serveur")
                                .font(.system(size: 14, weight: .semibold))
                        }
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(showJoined ? MoodTheme.onlineGreen : MoodTheme.brandAccent)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .animation(.easeInOut(duration: 0.2), value: showJoined)
                    }
                    .buttonStyle(.plain)
                    .disabled(inviteLink.isEmpty)
                    .opacity(inviteLink.isEmpty && !showJoined ? 0.5 : 1)
                }
                .padding(20)
            }

            Spacer()
        }
        .adaptiveFrame(width: 400, height: step == 0 ? 320 : (step == 1 ? 520 : 440), mode: layoutMode)
        .background(MoodTheme.popupBg)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(MoodTheme.glassBorder, lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.5), radius: 20, y: 8)
    }
}

// MARK: - Invite Modal

struct InviteModal: View {
    @Environment(\.layoutMode) private var layoutMode
    @Binding var isPresented: Bool
    let serverName: String
    @State private var copied = false
    @State private var invitedUsers: Set<UUID> = []

    private let inviteLink = "https://mood.app/invite/aB3kD9z"

    var body: some View {
        VStack(spacing: 16) {
            HStack {
                Text("Inviter des amis dans \(serverName)")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(MoodTheme.textPrimary)
                Spacer()
                Button { isPresented = false } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 12))
                        .foregroundStyle(MoodTheme.textPrimary)
                }
                .buttonStyle(.plain)
            }

            // Search friends
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 12))
                    .foregroundStyle(MoodTheme.textMuted)
                Text("Rechercher un ami...")
                    .font(.system(size: 13))
                    .foregroundStyle(MoodTheme.textMuted)
                Spacer()
            }
            .padding(10)
            .background(MoodTheme.glassBg)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

            // Friend list for inviting
            VStack(spacing: 4) {
                ForEach(MockData.users.prefix(3)) { user in
                    HStack(spacing: 10) {
                        Text(user.avatarEmoji)
                            .font(.system(size: 14))
                            .frame(width: 32, height: 32)
                            .background(MoodTheme.glassBg)
                            .clipShape(Circle())
                        Text(user.displayName)
                            .font(.system(size: 13))
                            .foregroundStyle(MoodTheme.textPrimary)
                        Spacer()
                        Button {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                _ = invitedUsers.insert(user.id)
                            }
                        } label: {
                            Text(invitedUsers.contains(user.id) ? "Envoyé" : "Inviter")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 5)
                                .background(invitedUsers.contains(user.id) ? MoodTheme.onlineGreen : MoodTheme.brandAccent)
                                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                                .animation(.easeInOut(duration: 0.2), value: invitedUsers.contains(user.id))
                        }
                        .buttonStyle(.plain)
                        .disabled(invitedUsers.contains(user.id))
                    }
                    .padding(.vertical, 4)
                }
            }

            Rectangle().fill(MoodTheme.divider).frame(height: 1)

            // Invite link
            VStack(alignment: .leading, spacing: 6) {
                Text("OU ENVOIE UN LIEN D'INVITATION")
                    .font(.system(size: 11, weight: .bold))
                    .tracking(0.4)
                    .foregroundStyle(MoodTheme.textSecondary)

                HStack {
                    Text(inviteLink)
                        .font(.system(size: 13))
                        .foregroundStyle(MoodTheme.textPrimary)
                        .lineLimit(1)

                    Spacer()

                    Button {
                        UIPasteboard.general.string = inviteLink
                        copied = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { copied = false }
                    } label: {
                        Text(copied ? "Copié !" : "Copier")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 6)
                            .background(copied ? MoodTheme.onlineGreen : MoodTheme.brandAccent)
                            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
                .padding(10)
                .background(MoodTheme.glassBg)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

                HStack(spacing: 6) {
                    Image(systemName: "clock")
                        .font(.system(size: 10))
                    Text("Ce lien expire dans 7 jours")
                        .font(.system(size: 11))
                }
                .foregroundStyle(MoodTheme.textMuted)
            }
        }
        .padding(20)
        .adaptiveFrame(width: 420, mode: layoutMode)
        .background(MoodTheme.popupBg)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(MoodTheme.glassBorder, lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.5), radius: 20, y: 8)
    }
}

struct ModalButton: View {
    let title: String
    let icon: String
    let color: Color
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 18))
                    .foregroundStyle(color)
                Text(title)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(MoodTheme.textPrimary)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 11))
                    .foregroundStyle(MoodTheme.textPrimary)
            }
            .padding(14)
            .background(isHovered ? MoodTheme.hoverBg : MoodTheme.glassBg)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(MoodTheme.glassBorder, lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering in isHovered = hovering }
    }
}

// MARK: - Explore Servers View

struct ExploreServersView: View {
    @State private var searchText = ""
    @State private var selectedCategory = "Populaire"

    private let categories: [(icon: String, label: String, color: Color)] = [
        ("flame.fill", "Populaire", .orange),
        ("gamecontroller.fill", "Gaming", .purple),
        ("film.fill", "Divertissement", .pink),
        ("graduationcap.fill", "Éducation", .blue),
        ("music.note", "Musique", .red),
        ("atom", "Science & Tech", .cyan),
        ("paintbrush.fill", "Art & Créatif", .green),
        ("bitcoinsign.circle.fill", "Finance", .yellow),
    ]

    var body: some View {
        VStack(spacing: 0) {
            // Header
            VStack(spacing: 20) {
                VStack(spacing: 8) {
                    Text("Découvrir des communautés")
                        .font(.system(size: 24, weight: .bold))
                        .foregroundStyle(MoodTheme.textPrimary)

                    Text("Trouve ta communauté sur Mood — des gamers aux artistes, tout le monde a sa place.")
                        .font(.system(size: 14))
                        .foregroundStyle(MoodTheme.textSecondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 500)
                }

                // Barre de recherche
                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 14))
                        .foregroundStyle(MoodTheme.textMuted)

                    TextField("Explorer des communautés", text: $searchText)
                        .textFieldStyle(.plain)
                        .font(.system(size: 14))
                        .foregroundStyle(MoodTheme.textPrimary)

                    if !searchText.isEmpty {
                        Button { searchText = "" } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 13))
                                .foregroundStyle(MoodTheme.textPrimary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(MoodTheme.glassBg)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(MoodTheme.glassBorder, lineWidth: 0.5)
                )
                .frame(maxWidth: 540)
            }
            .padding(.top, 40)
            .padding(.bottom, 24)
            .frame(maxWidth: .infinity)
            .background(
                LinearGradient(
                    colors: [MoodTheme.brandAccent.opacity(0.12), Color.clear],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )

            Rectangle().fill(MoodTheme.divider).frame(height: 1)

            // Catégories
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(categories, id: \.label) { cat in
                        Button {
                            selectedCategory = cat.label
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: cat.icon)
                                    .font(.system(size: 12))
                                    .foregroundStyle(selectedCategory == cat.label ? .white : cat.color)
                                Text(cat.label)
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundStyle(selectedCategory == cat.label ? .white : MoodTheme.textSecondary)
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(selectedCategory == cat.label ? cat.color.opacity(0.8) : MoodTheme.glassBg)
                            .clipShape(Capsule())
                            .overlay(
                                Capsule()
                                    .stroke(selectedCategory == cat.label ? Color.clear : MoodTheme.glassBorder, lineWidth: 0.5)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 16)
            }

            Rectangle().fill(MoodTheme.divider).frame(height: 1)

            // Contenu — état vide
            ScrollView {
                VStack(spacing: 16) {
                    Spacer().frame(height: 60)

                    Image(systemName: "safari")
                        .font(.system(size: 48))
                        .foregroundStyle(MoodTheme.textMuted.opacity(0.5))

                    Text("Bientôt disponible")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(MoodTheme.textSecondary)

                    Text("Les serveurs publics apparaîtront ici.\nEn attendant, rejoins un serveur via un lien d'invitation.")
                        .font(.system(size: 13))
                        .foregroundStyle(MoodTheme.textMuted)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 340)

                    Spacer()
                }
                .frame(maxWidth: .infinity)
            }
        }
        .background(MoodTheme.chatBackground)
    }
}

#Preview {
    ServerSidebarView(
        servers: MockData.servers,
        selectedServer: .constant(MockData.servers.first),
        showDMs: .constant(false),
        selectedChannel: .constant(nil),
        showCreateServer: .constant(false),
        showExplore: .constant(false)
    )
    .frame(height: 700)
    .preferredColorScheme(.dark)
}
