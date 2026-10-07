import SwiftUI
import UIKit

// MARK: - Server Sidebar

struct ServerSidebarView: View {
    @Environment(MatrixStore.self) private var matrixStore
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
                VStack(spacing: 8 * LayoutMetrics.scale) {
                    // Home / DMs — Logo Mood (deux points)
                    Button {
                        showDMs = true
                        selectedServer = nil
                    } label: {
                        ZStack(alignment: .bottomTrailing) {
                            ZStack {
                                MoodLogoDots(dotSize: 9 * LayoutMetrics.scale, spacing: 5 * LayoutMetrics.scale)
                            }
                            .frame(width: LayoutMetrics.serverIconSize, height: LayoutMetrics.serverIconSize)
                            .background(
                                showDMs ? MoodTheme.brandAccent :
                                MoodTheme.serverIconBg
                            )
                            .clipShape(
                                RoundedRectangle(
                                    cornerRadius: LayoutMetrics.serverIconCornerRadius,
                                    style: .continuous
                                )
                            )

                            // Badge mentions DMs
                            if dmUnreadCount > 0 {
                                Text("\(dmUnreadCount)")
                                    .font(.mood(10, weight: .bold))
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 5 * LayoutMetrics.scale)
                                    .padding(.vertical, 2 * LayoutMetrics.scale)
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
                                .frame(width: 4 * LayoutMetrics.scale, height: 40 * LayoutMetrics.scale)
                                .offset(x: LayoutMetrics.serverPillOffset)
                        }
                    }

                    // Séparateur
                    RoundedRectangle(cornerRadius: 0.5 * LayoutMetrics.scale)
                        .fill(MoodTheme.workspaceBorder)
                        .frame(width: LayoutMetrics.serverSeparatorWidth, height: 1 * LayoutMetrics.scale)

                    // Serveurs
                    ForEach(servers) { server in
                        SidebarIcon(
                            emoji: server.iconEmoji,
                            imageURL: server.iconURL,
                            isSelected: !showDMs && selectedServer?.id == server.id,
                            hasUnread: server.hasUnread,
                            mentionCount: server.mentionCount,
                            onMarkRead: { matrixStore.markServerAsRead(server) },
                            onLeave: {
                                if selectedServer?.id == server.id {
                                    selectedServer = nil
                                    selectedChannel = nil
                                    showDMs = true
                                }
                                Task { await matrixStore.leaveServer(server) }
                            }
                        ) {
                            selectedServer = server
                            showDMs = false
                            selectedChannel = server.categories.first?.channels.first
                        }
                        .help(server.name)
                    }

                    // Séparateur
                    RoundedRectangle(cornerRadius: 0.5 * LayoutMetrics.scale)
                        .fill(MoodTheme.workspaceBorder)
                        .frame(width: LayoutMetrics.serverSeparatorWidth, height: 1 * LayoutMetrics.scale)

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

                    SidebarIcon(
                        systemIcon: "arrow.down.to.line",
                        isSelected: false,
                        hasUnread: false,
                        mentionCount: 0,
                        iconColor: MoodTheme.textSecondary
                    ) {}
                    .help("Télécharger l'application")
                }
                .padding(.bottom, 12 * LayoutMetrics.scale)
                .padding(.horizontal, 15 * LayoutMetrics.scale)
            }

            Spacer()
        }
        .padding(.bottom, LayoutMetrics.channelBottomPadding)
        .frame(width: LayoutMetrics.serverBarWidth)
        .background(MoodTheme.serverBar)
    }
}

// MARK: - Sidebar Icon (carré arrondi / squircle)

struct SidebarIcon: View {
    var emoji: String?
    var imageURL: URL?
    var systemIcon: String?
    let isSelected: Bool
    let hasUnread: Bool
    let mentionCount: Int
    var iconColor: Color = MoodTheme.textPrimary
    /// Server-only actions; the context menu is hidden for rail buttons (add, explore…).
    var onMarkRead: (() -> Void)?
    var onLeave: (() -> Void)?
    let action: () -> Void

    @State private var isHovered = false
    @State private var isMuted = false
    @State private var showComingSoon = false
    @State private var showLeaveConfirm = false
    @State private var hideMutedChannels = false

    // Discord's 2025 rail keeps every icon a rounded square; only the pill changes.
    private let cornerRadius: CGFloat = LayoutMetrics.serverIconCornerRadius

    var body: some View {
        Button(action: action) {
            ZStack(alignment: .bottomTrailing) {
                Group {
                    if let imageURL {
                        AsyncImage(url: imageURL) { image in
                            image.resizable().scaledToFill()
                        } placeholder: {
                            Text(emoji ?? "")
                                .font(.mood(20))
                        }
                    } else if let emoji = emoji {
                        Text(emoji)
                            .font(.mood(20))
                    } else if let icon = systemIcon {
                        Image(systemName: icon)
                            .font(.mood(20, weight: .medium))
                            .foregroundStyle(isHovered ? .white : iconColor)
                    }
                }
                .frame(width: LayoutMetrics.serverIconSize, height: LayoutMetrics.serverIconSize)
                .background(
                    isSelected ? MoodTheme.brandAccent :
                    isHovered ? MoodTheme.brandAccent :
                    MoodTheme.serverIconBg
                )
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                .animation(MoodMotion.hover, value: isSelected)
                .animation(MoodMotion.hover, value: isHovered)

                // Badge mentions
                if mentionCount > 0 {
                    Text("\(mentionCount)")
                        .font(.mood(10, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 5 * LayoutMetrics.scale)
                        .padding(.vertical, 2 * LayoutMetrics.scale)
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
        .onHover { hovering in
            withAnimation(MoodMotion.hover) { isHovered = hovering }
        }
        // Pill indicator gauche
        .overlay(alignment: .leading) {
            if hasUnread || isSelected || isHovered {
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(MoodTheme.textPrimary)
                    .frame(width: 4 * LayoutMetrics.scale, height: (isSelected ? 40 : (isHovered ? 20 : 8)) * LayoutMetrics.scale)
                    .offset(x: LayoutMetrics.serverPillOffset)
                    .animation(.easeInOut(duration: 0.2), value: isSelected)
                    .animation(.easeInOut(duration: 0.2), value: isHovered)
            }
        }
        .contextMenu {
            if onLeave != nil {
                Button { onMarkRead?() } label: { Label("Marquer comme lu", systemImage: "checkmark.circle") }
                    .disabled(!hasUnread && mentionCount == 0)
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
        }
        .alert("Bientôt disponible", isPresented: $showComingSoon) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Cette fonctionnalité arrive dans une prochaine version de Mood.")
        }
        .alert("Quitter le serveur", isPresented: $showLeaveConfirm) {
            Button("Annuler", role: .cancel) {}
            Button("Quitter", role: .destructive) { onLeave?() }
        } message: {
            Text("Es-tu sûr de vouloir quitter ce serveur ?")
        }
    }
}

// MARK: - Server Folder

// MARK: - Create Server Modal

struct CreateServerModal: View {
    @Environment(\.layoutMode) private var layoutMode
    @Environment(MatrixStore.self) private var matrixStore
    @Binding var isPresented: Bool
    /// Called with the new or joined server's id so the caller can open it.
    var onOpenServer: (UUID) -> Void = { _ in }
    @State private var step = 0 // 0 = choice, 1 = create, 2 = join
    @State private var serverName = ""
    @State private var inviteLink = ""
    @State private var selectedTemplate = ""
    @State private var isPublic = false
    @State private var isWorking = false
    @State private var failure: String?

    private var defaultServerName: String {
        "Serveur de \(matrixStore.currentUser?.displayName ?? "moi")"
    }

    private func createServer() {
        guard !isWorking else { return }
        isWorking = true
        failure = nil
        let name = serverName.trimmingCharacters(in: .whitespaces).isEmpty ? defaultServerName : serverName
        Task {
            let serverId = await matrixStore.createServer(name: name, isPublic: isPublic)
            isWorking = false
            if let serverId {
                isPresented = false
                onOpenServer(serverId)
            } else {
                failure = matrixStore.errorMessage ?? "La création du serveur a échoué."
            }
        }
    }

    private func joinServer() {
        guard !isWorking else { return }
        isWorking = true
        failure = nil
        Task {
            let serverId = await matrixStore.joinServer(fromInvite: inviteLink)
            isWorking = false
            if let serverId {
                isPresented = false
                onOpenServer(serverId)
            } else {
                failure = matrixStore.errorMessage ?? "Impossible de rejoindre ce serveur."
            }
        }
    }

    @ViewBuilder
    private var failureText: some View {
        if let failure {
            Text(failure)
                .font(.system(size: 12))
                .foregroundStyle(MoodTheme.mentionBadge)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

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

                        TextField(defaultServerName, text: $serverName)
                            .onAppear { if serverName.isEmpty { serverName = defaultServerName } }
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
                                isPublic = false
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
                                isPublic = true
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

                    failureText

                    Button(action: createServer) {
                        HStack(spacing: 6) {
                            if isWorking {
                                ProgressView().controlSize(.small).tint(.white)
                            }
                            Text("Créer")
                                .font(.system(size: 14, weight: .semibold))
                        }
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(MoodTheme.brandAccent)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .keyboardShortcut(.defaultAction)
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

                        TextField("https://matrix.to/#/#salon:matrix.org", text: $inviteLink)
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

                    failureText

                    Button(action: joinServer) {
                        HStack(spacing: 6) {
                            if isWorking {
                                ProgressView().controlSize(.small).tint(.white)
                            }
                            Text("Rejoindre le serveur")
                                .font(.system(size: 14, weight: .semibold))
                        }
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(MoodTheme.brandAccent)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .disabled(inviteLink.trimmingCharacters(in: .whitespaces).isEmpty)
                    .opacity(inviteLink.trimmingCharacters(in: .whitespaces).isEmpty ? 0.5 : 1)
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
        .popoverElevation()
    }
}

// MARK: - Invite Modal

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
