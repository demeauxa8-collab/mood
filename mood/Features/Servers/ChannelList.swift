import SwiftUI
import UIKit

// MARK: - Channel List Column

struct ChannelListColumn: View {
    @Environment(ServerActions.self) private var serverActions
    let server: MoodServer
    @Binding var selectedChannel: Channel?
    @Binding var showSettings: Bool
    @State private var showServerMenu = false
    @State private var showInviteModal = false
    @State private var showCreateChannel = false
    @State private var showServerSettings = false
    @State private var editingChannel: Channel?
    @State private var pendingChannelID: UUID?

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
                    ForEach(server.categories) { category in
                        CategorySection(
                            category: category,
                            server: server,
                            selectedChannel: $selectedChannel,
                            onCreateChannel: { showCreateChannel = true },
                            onEditChannel: { editingChannel = $0 },
                            onInvite: { showInviteModal = true }
                        )
                    }
                }
                .padding(.top, 10 * LayoutMetrics.scale)
                .padding(.bottom, LayoutMetrics.channelBottomPadding)
            }

            Spacer(minLength: 0)

        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(MoodTheme.channelList)
        .overlay(alignment: .top) {
            if showServerMenu {
                ServerSettingsMenu(
                    server: server,
                    onInvite: { showServerMenu = false; showInviteModal = true },
                    onOpenSettings: { showServerMenu = false; showServerSettings = true },
                    onCreateChannel: { showServerMenu = false; showCreateChannel = true },
                    onLeft: { showServerMenu = false; selectedChannel = nil }
                )
                .padding(.top, 53 * LayoutMetrics.scale)
                .transition(
                    .opacity.combined(
                        with: .scale(scale: 0.985, anchor: .top)
                    )
                )
                .zIndex(100)
            }
        }
        .modalOverlay(isPresented: $showInviteModal) {
            ServerInviteModal(server: server, isPresented: $showInviteModal)
        }
        .modalOverlay(isPresented: $showCreateChannel) {
            CreateChannelModal(server: server, isPresented: $showCreateChannel) { channelId in
                pendingChannelID = channelId
            }
        }
        .modalOverlay(isPresented: Binding(get: { editingChannel != nil }, set: { if !$0 { editingChannel = nil } })) {
            if let channel = editingChannel {
                ChannelSettingsView(
                    channel: channel,
                    server: server,
                    isPresented: Binding(get: { editingChannel != nil }, set: { if !$0 { editingChannel = nil } }),
                    onDeleted: { if selectedChannel?.id == channel.id { selectedChannel = nil } }
                )
            }
        }
        .fullScreenCover(isPresented: $showServerSettings) {
            ServerSettingsView(server: server, isPresented: $showServerSettings) {
                selectedChannel = nil
            }
        }
        .onChange(of: serverActions.pending) { _, action in
            guard let action else { return }
            serverActions.pending = nil
            switch action {
            case .invite: showInviteModal = true
            case .openSettings: showServerSettings = true
            case .editChannel(let id): editingChannel = server.channel(withID: id)
            }
        }
        .onChange(of: server.categories.flatMap(\.channels).map(\.id)) { _, channelIDs in
            // Open a freshly created channel as soon as the sync delivers it.
            guard let pendingChannelID, channelIDs.contains(pendingChannelID) else { return }
            selectedChannel = server.channel(withID: pendingChannelID)
            self.pendingChannelID = nil
        }
        .onChange(of: server.id) { _, _ in
            showServerMenu = false
        }
    }
}


// MARK: - Server Settings Menu

struct ServerSettingsMenu: View {
    @Environment(MatrixStore.self) private var matrixStore
    let server: MoodServer
    let onInvite: () -> Void
    let onOpenSettings: () -> Void
    let onCreateChannel: () -> Void
    let onLeft: () -> Void
    @State private var showLeaveConfirm = false
    @State private var copiedServerID = false

    private var canManage: Bool { matrixStore.myPowerLevel(in: server) >= 50 }

    var body: some View {
        VStack(spacing: 0) {
            ServerMenuItem(icon: "person.badge.plus", label: "Inviter sur le serveur", color: MoodTheme.brandBlue, iconColor: MoodTheme.brandBlue) {
                onInvite()
            }

            ServerMenuDivider()

            ServerMenuItem(icon: "gearshape.fill", label: "Paramètres du serveur") {
                onOpenSettings()
            }
            if canManage {
                ServerMenuItem(icon: "plus.circle.fill", label: "Créer un salon") {
                    onCreateChannel()
                }
            }
            ServerMenuItem(icon: "checkmark.circle", label: "Marquer comme lu") {
                matrixStore.markServerAsRead(server)
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
                UIPasteboard.general.string = matrixStore.roomId(for: server) ?? server.id.uuidString
                copiedServerID = true
                Task {
                    try? await Task.sleep(for: .seconds(1.5))
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
        .popoverElevation()
        .alert("Quitter « \(server.name) »", isPresented: $showLeaveConfirm) {
            Button("Annuler", role: .cancel) {}
            Button("Quitter le serveur", role: .destructive) {
                onLeft()
                Task { await matrixStore.leaveServer(server) }
            }
        } message: {
            Text("Tu ne pourras plus revenir sans être réinvité.")
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
    var onCreateChannel: (() -> Void)?
    var onEditChannel: ((Channel) -> Void)?
    var onInvite: (() -> Void)?
    @State private var isExpanded = true

    /// Discord 2025 writes categories in sentence case ("Salons textuels ⌄").
    private var categoryTitle: String {
        let channels = category.channels
        if !channels.isEmpty && channels.allSatisfy({ $0.type == .voice }) {
            return "Salons vocaux"
        }
        if category.name.uppercased() == "SALONS TEXTUELS" || category.name.uppercased() == "SALONS" {
            return "Salons textuels"
        }
        return category.name.prefix(1).uppercased() + category.name.dropFirst().lowercased()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Button {
                withAnimation(.easeInOut(duration: 0.12)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(spacing: 4 * LayoutMetrics.scale) {
                    Text(categoryTitle)
                        .font(.mood(13, weight: .medium))

                    Image(systemName: "chevron.down")
                        .font(.mood(8, weight: .bold))
                        .rotationEffect(.degrees(isExpanded ? 0 : -90))

                    Spacer()
                }
                .foregroundStyle(MoodTheme.textSecondary)
                .padding(.horizontal, 14 * LayoutMetrics.scale)
                .padding(.vertical, 6 * LayoutMetrics.scale)
                .padding(.top, 16 * LayoutMetrics.scale)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .overlay(alignment: .bottomTrailing) {
                if let onCreateChannel {
                    Button(action: onCreateChannel) {
                        Image(systemName: "plus")
                            .font(.mood(13))
                            .foregroundStyle(MoodTheme.textSecondary)
                            .frame(width: 24 * LayoutMetrics.scale, height: 24 * LayoutMetrics.scale)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .padding(.trailing, 10 * LayoutMetrics.scale)
                    .help("Créer un salon")
                }
            }

            if isExpanded {
                ForEach(category.channels) { channel in
                    VStack(spacing: 0) {
                        ChannelRow(
                            channel: channel,
                            isSelected: selectedChannel?.id == channel.id,
                            onEdit: onEditChannel.map { edit in { edit(channel) } },
                            onInvite: onInvite
                        )
                        .onTapGesture {
                            selectedChannel = channel
                        }

                        // Voice channel: show connected users
                        if channel.type == .voice, let users = MockData.voiceUsers[channel.id], !users.isEmpty {
                            VStack(spacing: 2) {
                                ForEach(users) { user in
                                    HStack(spacing: 8 * LayoutMetrics.scale) {
                                        AvatarGlyph(user: user)
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
    @Environment(MatrixStore.self) private var matrixStore
    let channel: Channel
    let isSelected: Bool
    var onEdit: (() -> Void)?
    var onInvite: (() -> Void)?
    @State private var isHovered = false

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

            Spacer()

            if isSelected || isHovered {
                HStack(spacing: 5 * LayoutMetrics.scale) {
                    if let onInvite {
                        Button(action: onInvite) {
                            Image(systemName: "person.badge.plus")
                                .font(.mood(13, weight: .semibold))
                                .foregroundStyle(MoodTheme.textPrimary)
                                .frame(width: 16 * LayoutMetrics.scale)
                        }
                        .buttonStyle(.plain)
                        .help("Créer une invitation")
                    }
                    if let onEdit {
                        Button(action: onEdit) {
                            Image(systemName: "gearshape.fill")
                                .font(.mood(13, weight: .semibold))
                                .foregroundStyle(MoodTheme.textPrimary)
                                .frame(width: 16 * LayoutMetrics.scale)
                        }
                        .buttonStyle(.plain)
                        .help("Modifier le salon")
                    }
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
            Button { matrixStore.markChannelAsRead(channel) } label: { Label("Marquer comme lu", systemImage: "checkmark.circle") }
                .disabled(channel.unreadCount == 0 && channel.mentionCount == 0)
            if let onInvite {
                Divider()
                Button(action: onInvite) { Label("Inviter des gens", systemImage: "person.badge.plus") }
            }
            if let onEdit {
                Button(action: onEdit) { Label("Modifier le salon", systemImage: "gearshape") }
            }
            Divider()
            Button {
                UIPasteboard.general.string = matrixStore.roomId(for: channel) ?? channel.id.uuidString
            } label: { Label("Copier l'identifiant du salon", systemImage: "doc.on.doc") }
        }
    }
}

// MARK: - Voice Connected Panel

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
                    .transition(.opacity)
                    .padding(.leading, 2)
            }

            HStack(spacing: 6 * LayoutMetrics.scale) {
                Button {
                    withAnimation(MoodMotion.popover) {
                        showStatusPicker.toggle()
                    }
                } label: {
                    ZStack(alignment: .bottomTrailing) {
                        AvatarGlyph(user: user)
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

                VStack(alignment: .leading, spacing: 0) {
                    Text(user.displayName)
                        .font(.mood(14, weight: .semibold))
                        .foregroundStyle(MoodTheme.textPrimary)
                        .lineLimit(1)
                    Text(user.bio.isEmpty ? user.status.rawValue : user.bio)
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
    @Environment(MatrixStore.self) private var matrixStore
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
                    showPicker = false
                    Task { await matrixStore.setMyStatus(item.status, message: matrixStore.myStatusMessage) }
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

// MARK: - Custom Status Editor

struct CustomStatusEditor: View {
    @Environment(MatrixStore.self) private var matrixStore
    @Binding var isPresented: Bool
    @State private var statusText = ""
    @State private var selectedEmoji = "😀"
    @State private var selectedDuration = "Ne pas effacer"

    private let quickEmojis = ["😀", "😴", "🤒", "🏠", "🎮", "📚", "💻", "🎵"]
    private let durations = ["Ne pas effacer", "30 minutes", "1 heure", "4 heures", "Aujourd'hui"]

    private var clearAfter: TimeInterval? {
        switch selectedDuration {
        case "30 minutes": return 30 * 60
        case "1 heure": return 3600
        case "4 heures": return 4 * 3600
        case "Aujourd'hui":
            let midnight = Calendar.current.startOfDay(for: Date()).addingTimeInterval(86_400)
            return midnight.timeIntervalSinceNow
        default: return nil
        }
    }

    private func saveStatus() {
        let text = statusText.trimmingCharacters(in: .whitespaces)
        let message = text.isEmpty ? nil : "\(selectedEmoji) \(text)"
        let store = matrixStore
        let delay = clearAfter
        Task {
            await store.setMyStatus(store.myStatus, message: message)
            // Cleared while the app is running; Matrix has no server-side expiry for status_msg.
            if let delay, let message {
                try? await Task.sleep(for: .seconds(delay))
                if store.myStatusMessage == message { await store.setMyStatus(store.myStatus, message: nil) }
            }
        }
    }

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
                    Task { await matrixStore.setMyStatus(matrixStore.myStatus, message: nil) }
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
                    saveStatus()
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
    .environment(ServerActions())
    .preferredColorScheme(.dark)
}
