import SwiftUI
import UIKit
import UniformTypeIdentifiers

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
                                    .desktopFriendsFont(10, weight: .bold)
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
    @State private var showLeaveConfirm = false

    // Discord's 2025 rail keeps every icon a rounded square; only the pill changes.
    private let cornerRadius: CGFloat = LayoutMetrics.serverIconCornerRadius

    var body: some View {
        Button(action: action) {
            ZStack(alignment: .bottomTrailing) {
                Group {
                    if let imageURL {
                        AuthenticatedImage(url: imageURL) { phase in
                            if let image = phase.image {
                                image.resizable().scaledToFill()
                            } else {
                                Text(emoji ?? "")
                                    .font(.mood(20))
                            }
                        }
                    } else if let emoji = emoji {
                        Text(emoji)
                            .font(.mood(20))
                    } else if let icon = systemIcon {
                        CalibratedDesktopSymbol(name: icon, size: 20, calibratedSize: 24, weight: .medium)
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
                        .desktopFriendsFont(10, weight: .bold)
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
                Button(role: .destructive) { showLeaveConfirm = true } label: { Label("Quitter le serveur", systemImage: "rectangle.portrait.and.arrow.right") }
            }
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
    @State private var pickingIcon = false
    @State private var iconData: Data?
    @State private var iconFilename = "icon.png"
    @State private var isPublic = false
    @State private var isWorking = false
    @State private var failure: String?

    private var defaultServerName: String {
        matrixStore.currentUser.map { "Serveur de \($0.displayName)" } ?? "Mon serveur"
    }

    private func createServer() {
        guard !isWorking else { return }
        isWorking = true
        failure = nil
        let name = serverName.trimmingCharacters(in: .whitespaces).isEmpty ? defaultServerName : serverName
        Task {
            let serverId = await matrixStore.createServer(name: name, isPublic: isPublic)
            defer { isWorking = false }
            if let serverId {
                if let iconData, let server = matrixStore.servers.first(where: { $0.id == serverId }) {
                    await matrixStore.updateServerIcon(server, imageData: iconData, filename: iconFilename)
                }
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
                .font(.mood(12))
                .foregroundStyle(MoodTheme.mentionBadge)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }


    var body: some View {
        if layoutMode == .compact { mobileBody } else { desktopBody }
    }

    private var mobileBody: some View {
        MobileSheet(title: step == 1 ? "Créer un serveur" : (step == 2 ? "Rejoindre un serveur" : "Un nouveau serveur"),
                    onBack: step > 0 ? { if !isWorking { step = 0 } } : nil,
                    onClose: { isPresented = false }) {
            List {
                if step == 0 {
                    Section {
                        Text("Un endroit pour retrouver tes amis.").font(.mood(16)).foregroundStyle(MoodTheme.textSecondary)
                        Button { step = 1 } label: {
                            Label { Text("Créer mon serveur") } icon: { Image(systemName: "plus.circle").frame(width: LayoutMetrics.mobile(30)) }
                        }
                        Button { step = 2 } label: {
                            Label { Text("Rejoindre un serveur") } icon: { Image(systemName: "person.3").frame(width: LayoutMetrics.mobile(30)) }
                        }
                    }.listRowBackground(MoodTheme.inputBg)
                } else if step == 1 {
                    Section("Icône") {
                        Button { pickingIcon = true } label: {
                            HStack(spacing: LayoutMetrics.mobile(16)) {
                                if let iconData, let image = UIImage(data: iconData) {
                                    Image(uiImage: image).resizable().scaledToFill()
                                        .frame(width: LayoutMetrics.mobile(56), height: LayoutMetrics.mobile(56)).clipShape(Circle())
                                } else { Image(systemName: "camera.fill").frame(width: LayoutMetrics.mobile(56), height: LayoutMetrics.mobile(56)).mobileGlassCapsule() }
                                Text("Choisir une image").fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }.listRowBackground(MoodTheme.inputBg)
                    Section("Nom du serveur") {
                        TextField(defaultServerName, text: $serverName, axis: .vertical).lineLimit(1...3)
                    }.listRowBackground(MoodTheme.inputBg)
                    Section {
                        Toggle("Communauté publique", isOn: $isPublic)
                        Text("Un serveur privé n’est accessible que sur invitation.").font(.mood(14)).foregroundStyle(MoodTheme.textSecondary)
                    }.listRowBackground(MoodTheme.inputBg)
                    Section {
                        Button(isWorking ? "Création…" : "Créer le serveur", action: createServer)
                            .buttonStyle(MobilePrimaryButtonStyle()).disabled(isWorking)
                    }.listRowBackground(MoodTheme.mobileSurface).listRowInsets(EdgeInsets())
                } else {
                    Section("Invitation") {
                        TextField("Code ou lien d’invitation", text: $inviteLink, axis: .vertical).lineLimit(2...4)
                            .autocorrectionDisabled().textInputAutocapitalization(.never)
                        Text("Demande un code ou un lien Mood à un ami.").font(.mood(14)).foregroundStyle(MoodTheme.textSecondary)
                    }.listRowBackground(MoodTheme.inputBg)
                    Section {
                        Button(isWorking ? "Connexion…" : "Rejoindre le serveur", action: joinServer)
                            .buttonStyle(MobilePrimaryButtonStyle()).disabled(isWorking || inviteLink.trimmingCharacters(in: .whitespaces).isEmpty)
                    }.listRowBackground(MoodTheme.mobileSurface).listRowInsets(EdgeInsets())
                }
                if let failure { Section { Text(failure).foregroundStyle(MoodTheme.mentionBadge) }.listRowBackground(MoodTheme.inputBg) }
            }.mobileGroupedList().disabled(isWorking)
        }
        .onAppear {
            if MobileUIPreview.screen == "join-server" { step = 2 }
            if MobileUIPreview.screen == "create-server-form" { step = 1 }
        }
        .fileImporter(isPresented: $pickingIcon, allowedContentTypes: [.image]) { result in
            guard case .success(let url) = result else { return }
            let access = url.startAccessingSecurityScopedResource()
            defer { if access { url.stopAccessingSecurityScopedResource() } }
            iconData = try? Data(contentsOf: url); iconFilename = url.lastPathComponent
        }
    }

    private var desktopBody: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                if step > 0 {
                    Button {
                        withAnimation(.easeInOut(duration: 0.15)) { step = 0 }
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(.mood(12))
                            .foregroundStyle(MoodTheme.textPrimary)
                    }
                    .buttonStyle(.plain)
                }

                Spacer()

                Button {
                    isPresented = false
                } label: {
                    Image(systemName: "xmark")
                        .font(.mood(12))
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
                        .font(.mood(22, weight: .bold))
                        .foregroundStyle(MoodTheme.textPrimary)
                        .multilineTextAlignment(.center)

                    Text("Un serveur c'est ton espace avec tes amis. Crée le tien ou rejoins-en un.")
                        .font(.mood(13))
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
                        .font(.mood(20, weight: .bold))
                        .foregroundStyle(MoodTheme.textPrimary)

                    Button("Choisir une icône (facultatif)") { pickingIcon = true }
                        .font(.mood(13)).foregroundStyle(MoodTheme.brandAccent)
                    if let iconData, let image = UIImage(data: iconData) {
                        Image(uiImage: image).resizable().scaledToFit()
                            .frame(width: LayoutMetrics.serverIconSize, height: LayoutMetrics.serverIconSize)
                    }

                    // Server name
                    VStack(alignment: .leading, spacing: 6) {
                        Text("NOM DU SERVEUR")
                            .font(.mood(11, weight: .bold))
                            .tracking(0.4)
                            .foregroundStyle(MoodTheme.textSecondary)

                        TextField(defaultServerName, text: $serverName)
                            .onAppear { if serverName.isEmpty { serverName = defaultServerName } }
                            .textFieldStyle(.plain)
                            .font(.mood(14))
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
                            .font(.mood(11, weight: .bold))
                            .tracking(0.4)
                            .foregroundStyle(MoodTheme.textSecondary)

                        HStack(spacing: 8) {
                            Button {
                                isPublic = false
                            } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: "person.2")
                                        .font(.mood(12))
                                    Text("Privé")
                                        .font(.mood(13, weight: .medium))
                                }
                                .foregroundStyle(!isPublic ? MoodTheme.mobileIndicator : MoodTheme.textSecondary)
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
                                        .font(.mood(12))
                                    Text("Public")
                                        .font(.mood(13, weight: .medium))
                                }
                                .foregroundStyle(isPublic ? MoodTheme.mobileIndicator : MoodTheme.textSecondary)
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
                            .font(.mood(11))
                            .foregroundStyle(MoodTheme.textSecondary)
                    }

                    failureText

                    Button(action: createServer) {
                        HStack(spacing: 6) {
                            if isWorking {
                                ProgressView().controlSize(.small).tint(.white)
                            }
                            Text("Créer")
                                .font(.mood(14, weight: .semibold))
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
                        .font(.mood(20, weight: .bold))
                        .foregroundStyle(MoodTheme.textPrimary)

                    Text("Entre un lien d'invitation pour rejoindre un serveur existant")
                        .font(.mood(13))
                        .foregroundStyle(MoodTheme.textSecondary)
                        .multilineTextAlignment(.center)

                    VStack(alignment: .leading, spacing: 6) {
                        Text("LIEN D'INVITATION")
                            .font(.mood(11, weight: .bold))
                            .tracking(0.4)
                            .foregroundStyle(MoodTheme.textSecondary)

                        TextField("Code Mood ou lien d’invitation", text: $inviteLink)
                            .textFieldStyle(.plain)
                            .font(.mood(14))
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
                                .font(.mood(14, weight: .semibold))
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
        .onAppear {
            guard matrixStore.userId == nil, ProcessInfo.processInfo.arguments.contains("-uiPreview") else { return }
            if MessagingPreview.kind == "create-server" { step = 1 }
            if MessagingPreview.kind == "join-server" { step = 2 }
        }
        .fileImporter(isPresented: $pickingIcon, allowedContentTypes: [.image]) { result in
            guard case .success(let url) = result else { return }
            let access = url.startAccessingSecurityScopedResource()
            defer { if access { url.stopAccessingSecurityScopedResource() } }
            do { iconData = try Data(contentsOf: url); iconFilename = url.lastPathComponent }
            catch { failure = "Impossible de lire cette image." }
        }
        .modifier(CreateServerChrome(layoutMode: layoutMode, height: step == 0 ? 320 : (step == 1 ? 520 : 440)))
    }
}

/// Desktop: Discord's floating card. iPhone: the modal sits in a sheet, so it fills it plainly
/// (a card inside the sheet left a grey band and a second set of corners).
private struct CreateServerChrome: ViewModifier {
    let layoutMode: LayoutMode
    let height: CGFloat

    func body(content: Content) -> some View {
        if layoutMode == .compact {
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .background(MoodTheme.mobileSurface)
        } else {
            content
                .frame(width: 400, height: height)
                .background(MoodTheme.popupBg)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(MoodTheme.glassBorder, lineWidth: 0.5)
                )
                .popoverElevation()
        }
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
