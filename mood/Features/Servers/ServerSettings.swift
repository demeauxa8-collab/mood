import SwiftUI
import UIKit
import UniformTypeIdentifiers

// MARK: - Shared field style

private struct SettingsTextField: View {
    let placeholder: String
    @Binding var text: String
    var axis: Axis = .horizontal

    var body: some View {
        TextField(placeholder, text: $text, axis: axis)
            .textFieldStyle(.plain)
            .font(.system(size: 14))
            .foregroundStyle(MoodTheme.textPrimary)
            .lineLimit(axis == .vertical ? 3...6 : 1...1)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(MoodTheme.serverBar)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

// MARK: - Create Channel

/// Discord's "Créer un salon" modal: type, name, private toggle.
struct CreateChannelModal: View {
    @Environment(MatrixStore.self) private var matrixStore
    let server: MoodServer
    @Binding var isPresented: Bool
    var onCreated: (UUID) -> Void = { _ in }
    @State private var name = ""
    @State private var topic = ""
    @State private var isPrivate = false
    @State private var isWorking = false
    @State private var failure: String?

    private var cleanedName: String {
        name.trimmingCharacters(in: .whitespaces).lowercased().replacingOccurrences(of: " ", with: "-")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Créer un salon")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(MoodTheme.textPrimary)
                    Text("dans \(server.name)")
                        .font(.system(size: 12))
                        .foregroundStyle(MoodTheme.textSecondary)
                }
                Spacer()
                Button { isPresented = false } label: {
                    Image(systemName: "xmark").font(.system(size: 14)).foregroundStyle(MoodTheme.textSecondary)
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.cancelAction)
            }

            SettingsSection(title: "TYPE DE SALON") {
                HStack(spacing: 12) {
                    Image(systemName: "number").font(.system(size: 20)).foregroundStyle(MoodTheme.textSecondary)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Texte").font(.system(size: 15, weight: .medium)).foregroundStyle(MoodTheme.textPrimary)
                        Text("Envoie des messages, des images, des GIF, des emojis, des avis et des blagues")
                            .font(.system(size: 12)).foregroundStyle(MoodTheme.textSecondary)
                    }
                    Spacer()
                    Image(systemName: "largecircle.fill.circle").foregroundStyle(MoodTheme.textPrimary)
                }
                .padding(12)
                .background(MoodTheme.selectedBg)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }

            SettingsSection(title: "NOM DU SALON") {
                HStack(spacing: 6) {
                    Image(systemName: "number").foregroundStyle(MoodTheme.textSecondary)
                    TextField("nouveau-salon", text: $name)
                        .textFieldStyle(.plain)
                        .font(.system(size: 14))
                        .foregroundStyle(MoodTheme.textPrimary)
                        .onSubmit(create)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(MoodTheme.serverBar)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }

            SettingsSection(title: "SUJET (FACULTATIF)") {
                SettingsTextField(placeholder: "De quoi parle ce salon ?", text: $topic)
            }

            Toggle(isOn: $isPrivate) {
                VStack(alignment: .leading, spacing: 2) {
                    Label("Salon privé", systemImage: "lock").font(.system(size: 15, weight: .medium))
                    Text("Seules les personnes invitées pourront rejoindre ce salon.")
                        .font(.system(size: 12)).foregroundStyle(MoodTheme.textSecondary)
                }
            }
            .tint(MoodTheme.onlineGreen)
            .foregroundStyle(MoodTheme.textPrimary)

            if let failure {
                Text(failure).font(.system(size: 12)).foregroundStyle(MoodTheme.mentionBadge)
            }

            HStack {
                Spacer()
                Button("Annuler") { isPresented = false }
                    .buttonStyle(.plain)
                    .foregroundStyle(MoodTheme.textPrimary)
                Button(action: create) {
                    HStack(spacing: 6) {
                        if isWorking { ProgressView().controlSize(.small).tint(.white) }
                        Text("Créer un salon").font(.system(size: 14, weight: .semibold))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 9)
                    .background(MoodTheme.brandAccent.opacity(cleanedName.isEmpty ? 0.5 : 1))
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled(cleanedName.isEmpty)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 460)
        .background(MoodTheme.popupBg)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .popoverElevation()
    }

    private func create() {
        guard !cleanedName.isEmpty, !isWorking else { return }
        isWorking = true
        failure = nil
        Task {
            let channelId = await matrixStore.createChannel(in: server, name: cleanedName, topic: topic, isPrivate: isPrivate)
            isWorking = false
            if let channelId {
                isPresented = false
                onCreated(channelId)
            } else {
                failure = matrixStore.errorMessage ?? "La création du salon a échoué."
            }
        }
    }
}

// MARK: - Server Settings

/// Discord's full-screen server settings, mapped onto the Matrix space.
struct ServerSettingsView: View {
    @Environment(MatrixStore.self) private var matrixStore
    let server: MoodServer
    @Binding var isPresented: Bool
    var onLeft: () -> Void = {}
    @State private var tab: Tab = .overview

    /// Discord's settings sidebar, limited to what a Matrix space can actually do.
    enum Tab: String, CaseIterable {
        case overview = "Profil du serveur"
        case roles = "Rôles"
        case members = "Membres"
        case invites = "Invitations"
        case bans = "Bannissements"

        var section: String? {
            switch self {
            case .overview: return nil
            case .roles: return "PERSONNES"
            case .bans: return "MODÉRATION"
            default: return nil
            }
        }

        var needsModeration: Bool { self == .roles || self == .bans }
    }

    private var canModerate: Bool { matrixStore.myPowerLevel(in: server) >= 50 }
    /// Re-read from the store so edits (name, icon, roles) show up immediately.
    private var liveServer: MoodServer { matrixStore.servers.first { $0.id == server.id } ?? server }

    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 2) {
                Text(server.name.uppercased())
                    .font(.system(size: 11, weight: .semibold))
                    .tracking(0.4)
                    .foregroundStyle(MoodTheme.textSecondary)
                    .lineLimit(1)
                    .padding(.horizontal, 10)
                    .padding(.bottom, 6)
                ForEach(Tab.allCases, id: \.self) { item in
                    if let section = item.section {
                        Text(section)
                            .font(.system(size: 11, weight: .semibold))
                            .tracking(0.4)
                            .foregroundStyle(MoodTheme.textSecondary)
                            .padding(.horizontal, 10)
                            .padding(.top, 14)
                            .padding(.bottom, 4)
                    }
                    if !item.needsModeration || canModerate {
                        Button { tab = item } label: {
                            Text(item.rawValue)
                                .font(.system(size: 15, weight: tab == item ? .semibold : .regular))
                                .foregroundStyle(tab == item ? MoodTheme.textPrimary : MoodTheme.textSecondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(tab == item ? MoodTheme.selectedBg : Color.clear)
                                .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }
                }
                Rectangle().fill(MoodTheme.divider).frame(height: 1).padding(.vertical, 8)
                LeaveServerButton(server: server) {
                    isPresented = false
                    onLeft()
                }
                Spacer()
            }
            .padding(.top, 60)
            .padding(.horizontal, 12)
            .frame(width: 232)
            .background(MoodTheme.channelList)

            ScrollView {
                Group {
                    switch tab {
                    case .overview: ServerOverviewPane(server: liveServer, canEdit: canModerate)
                    case .roles: ServerRolesPane(server: liveServer)
                    case .members: ServerMembersPane(server: liveServer, canModerate: canModerate)
                    case .invites: ServerInvitesPane(server: liveServer)
                    case .bans: ServerBansPane(server: liveServer)
                    }
                }
                .frame(maxWidth: 740, alignment: .leading)
                .padding(.horizontal, 40)
                .padding(.top, 60)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(MoodTheme.chatBackground)
            .overlay(alignment: .topTrailing) {
                Button { isPresented = false } label: {
                    VStack(spacing: 4) {
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .semibold))
                            .frame(width: 34, height: 34)
                            .overlay(Circle().stroke(MoodTheme.textSecondary, lineWidth: 2))
                        Text("ÉCHAP").font(.system(size: 11, weight: .semibold))
                    }
                    .foregroundStyle(MoodTheme.textSecondary)
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.cancelAction)
                .padding(24)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct ServerOverviewPane: View {
    @Environment(MatrixStore.self) private var matrixStore
    let server: MoodServer
    let canEdit: Bool
    @State private var name = ""
    @State private var topic = ""
    @State private var isSaving = false
    @State private var isPickingIcon = false

    private var hasChanges: Bool {
        name.trimmingCharacters(in: .whitespaces) != server.name || topic != matrixStore.topic(of: server)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Profil du serveur")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(MoodTheme.textPrimary)
                Text("Personnalise l'apparence de ton serveur dans les liens d'invitation.")
                    .font(.system(size: 14))
                    .foregroundStyle(MoodTheme.textSecondary)
            }

            SettingsSection(title: "ICÔNE") {
                HStack(spacing: 16) {
                    SidebarIcon(emoji: server.iconEmoji, imageURL: server.iconURL, isSelected: true, hasUnread: false, mentionCount: 0) {}
                        .allowsHitTesting(false)
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Nous recommandons une image d'au moins 512x512.")
                            .font(.system(size: 13))
                            .foregroundStyle(MoodTheme.textSecondary)
                        Button("Changer l'icône du serveur") { isPickingIcon = true }
                            .buttonStyle(.plain)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(MoodTheme.brandAccent)
                            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                            .disabled(!canEdit)
                    }
                }
            }
            .fileImporter(isPresented: $isPickingIcon, allowedContentTypes: [.image]) { result in
                guard case .success(let url) = result else { return }
                let didAccess = url.startAccessingSecurityScopedResource()
                defer { if didAccess { url.stopAccessingSecurityScopedResource() } }
                guard let data = try? Data(contentsOf: url) else { return }
                Task { await matrixStore.updateServerIcon(server, imageData: data, filename: url.lastPathComponent) }
            }

            SettingsSection(title: "NOM DU SERVEUR") {
                SettingsTextField(placeholder: "Nom du serveur", text: $name).disabled(!canEdit)
            }
            SettingsSection(title: "DESCRIPTION") {
                SettingsTextField(placeholder: "Présente ton serveur", text: $topic, axis: .vertical).disabled(!canEdit)
            }
            if !canEdit {
                Text("Seuls les modérateurs et les administrateurs peuvent modifier ce serveur.")
                    .font(.system(size: 13))
                    .foregroundStyle(MoodTheme.textSecondary)
            }
        }
        .safeAreaInset(edge: .bottom) {
            if hasChanges {
                UnsavedChangesBar(isSaving: isSaving, onReset: reset, onSave: save).padding(.top, 20)
            }
        }
        .onAppear(perform: reset)
    }

    private func reset() {
        name = server.name
        topic = matrixStore.topic(of: server)
    }

    private func save() {
        let newName = name.trimmingCharacters(in: .whitespaces)
        guard !newName.isEmpty, !isSaving else { return }
        isSaving = true
        Task {
            await matrixStore.updateServer(server, name: newName, topic: topic)
            isSaving = false
        }
    }
}

private struct ServerMembersPane: View {
    @Environment(MatrixStore.self) private var matrixStore
    let server: MoodServer
    let canModerate: Bool
    @State private var search = ""
    @State private var pendingAction: (user: MoodUser, ban: Bool)?

    private var members: [MoodUser] {
        let current = server.members
        guard !search.isEmpty else { return current }
        return current.filter { $0.displayName.localizedCaseInsensitiveContains(search) || ($0.matrixId ?? "").localizedCaseInsensitiveContains(search) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Membres du serveur")
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(MoodTheme.textPrimary)
            SettingsTextField(placeholder: "Rechercher des membres", text: $search)
            Text("\(members.count) MEMBRES")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(MoodTheme.textSecondary)
            ForEach(members) { member in
                HStack(spacing: 12) {
                    AvatarGlyph(user: member)
                        .font(.system(size: 18))
                        .frame(width: 36, height: 36)
                        .background(MoodTheme.serverIconBg)
                        .clipShape(Circle())
                    VStack(alignment: .leading, spacing: 2) {
                        Text(member.displayName).font(.system(size: 15, weight: .medium)).foregroundStyle(MoodTheme.textPrimary)
                        Text(member.matrixId ?? member.username).font(.system(size: 12)).foregroundStyle(MoodTheme.textMuted)
                    }
                    Spacer()
                    Text(server.roleFor(member).rawValue)
                        .font(.system(size: 12))
                        .foregroundStyle(MoodTheme.textSecondary)
                    if canModerate, member.matrixId != matrixStore.userId, server.roleFor(member) != .owner {
                        Menu {
                            Menu("Rôle") {
                                ForEach([ServerRole.admin, .moderator, .member], id: \.self) { role in
                                    Button {
                                        Task { await matrixStore.setRole(role, for: member, in: server) }
                                    } label: {
                                        if server.roleFor(member) == role { Label(role.rawValue, systemImage: "checkmark") } else { Text(role.rawValue) }
                                    }
                                }
                            }
                            Divider()
                            Button("Expulser \(member.displayName)", role: .destructive) { pendingAction = (member, false) }
                            Button("Bannir \(member.displayName)", role: .destructive) { pendingAction = (member, true) }
                        } label: {
                            Image(systemName: "ellipsis").foregroundStyle(MoodTheme.textSecondary).frame(width: 28, height: 28)
                        }
                        .menuStyle(.borderlessButton)
                        .fixedSize()
                    }
                }
                .padding(.vertical, 6)
                Rectangle().fill(MoodTheme.divider).frame(height: 1)
            }
        }
        .alert(
            pendingAction.map { $0.ban ? "Bannir \($0.user.displayName)" : "Expulser \($0.user.displayName)" } ?? "",
            isPresented: Binding(get: { pendingAction != nil }, set: { if !$0 { pendingAction = nil } })
        ) {
            Button("Annuler", role: .cancel) {}
            Button(pendingAction?.ban == true ? "Bannir" : "Expulser", role: .destructive) {
                guard let action = pendingAction else { return }
                Task {
                    if action.ban {
                        await matrixStore.banFromServer(server, user: action.user)
                    } else {
                        await matrixStore.kickFromServer(server, user: action.user)
                    }
                }
            }
        } message: {
            Text(pendingAction?.ban == true
                 ? "Cette personne sera retirée de tous les salons du serveur et ne pourra plus revenir."
                 : "Cette personne sera retirée de tous les salons du serveur. Elle pourra revenir si elle est réinvitée.")
        }
    }
}

/// Matrix has no named roles: Discord-style roles map onto power levels.
private struct ServerRolesPane: View {
    let server: MoodServer

    private let roles: [(role: ServerRole, level: String, detail: String)] = [
        (.owner, "100", "A créé le serveur. Tous les droits."),
        (.admin, "100", "Peut tout modifier : salons, rôles, membres."),
        (.moderator, "50", "Peut expulser, bannir et épingler des messages."),
        (.member, "0", "@everyone — tout le monde dans le serveur."),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Rôles")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(MoodTheme.textPrimary)
                Text("Attribue un rôle depuis l'onglet Membres. Les rôles correspondent aux niveaux de pouvoir Matrix.")
                    .font(.system(size: 14))
                    .foregroundStyle(MoodTheme.textSecondary)
            }
            HStack {
                Text("RÔLES — \(roles.count)").frame(maxWidth: .infinity, alignment: .leading)
                Text("MEMBRES").frame(width: 90, alignment: .trailing)
            }
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(MoodTheme.textSecondary)
            ForEach(roles, id: \.role) { item in
                HStack(spacing: 12) {
                    Image(systemName: item.role.icon)
                        .foregroundStyle(item.role.color)
                        .frame(width: 24)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.role == .member ? "@everyone" : item.role.rawValue)
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(MoodTheme.textPrimary)
                        Text(item.detail)
                            .font(.system(size: 12))
                            .foregroundStyle(MoodTheme.textMuted)
                    }
                    Spacer()
                    Text("\(server.members.filter { server.roleFor($0) == item.role }.count)")
                        .font(.system(size: 14))
                        .foregroundStyle(MoodTheme.textSecondary)
                        .frame(width: 90, alignment: .trailing)
                }
                .padding(.vertical, 8)
                Rectangle().fill(MoodTheme.divider).frame(height: 1)
            }
        }
    }
}

private struct ServerInvitesPane: View {
    @Environment(MatrixStore.self) private var matrixStore
    let server: MoodServer

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Invitations")
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(MoodTheme.textPrimary)
            Text("Partage ce lien : il ouvre le serveur dans n'importe quelle appli Matrix, dont Mood. Il n'expire pas.")
                .font(.system(size: 14))
                .foregroundStyle(MoodTheme.textSecondary)
            if let link = matrixStore.inviteLink(for: server) {
                CopyField(value: link)
            }
        }
    }
}

private struct ServerBansPane: View {
    @Environment(MatrixStore.self) private var matrixStore
    let server: MoodServer

    var body: some View {
        let banned = matrixStore.bannedUsers(in: server)
        VStack(alignment: .leading, spacing: 16) {
            Text("Bannissements")
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(MoodTheme.textPrimary)
            if banned.isEmpty {
                Text("Personne n'est banni de ce serveur.")
                    .font(.system(size: 14))
                    .foregroundStyle(MoodTheme.textSecondary)
            }
            ForEach(banned) { user in
                HStack {
                    Text(user.displayName).font(.system(size: 15, weight: .medium)).foregroundStyle(MoodTheme.textPrimary)
                    Text(user.matrixId ?? "").font(.system(size: 12)).foregroundStyle(MoodTheme.textMuted)
                    Spacer()
                    Button("Révoquer le bannissement") {
                        Task { await matrixStore.unbanFromServer(server, user: user) }
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(MoodTheme.mentionBadge)
                }
                .padding(.vertical, 6)
                Rectangle().fill(MoodTheme.divider).frame(height: 1)
            }
        }
    }
}

private struct LeaveServerButton: View {
    @Environment(MatrixStore.self) private var matrixStore
    let server: MoodServer
    let onLeft: () -> Void
    @State private var confirm = false

    var body: some View {
        Button { confirm = true } label: {
            Label("Quitter le serveur", systemImage: "rectangle.portrait.and.arrow.right")
                .font(.system(size: 15))
                .foregroundStyle(MoodTheme.mentionBadge)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
        }
        .buttonStyle(.plain)
        .alert("Quitter « \(server.name) »", isPresented: $confirm) {
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

// MARK: - Channel Settings

struct ChannelSettingsView: View {
    @Environment(MatrixStore.self) private var matrixStore
    let channel: Channel
    let server: MoodServer
    @Binding var isPresented: Bool
    var onDeleted: () -> Void = {}
    @State private var name = ""
    @State private var topic = ""
    @State private var isSaving = false
    @State private var confirmDelete = false

    private var hasChanges: Bool { name != channel.name || topic != channel.topic }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Text("# \(channel.name)")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(MoodTheme.textPrimary)
                Spacer()
                Button { isPresented = false } label: {
                    Image(systemName: "xmark").font(.system(size: 14)).foregroundStyle(MoodTheme.textSecondary)
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.cancelAction)
            }
            SettingsSection(title: "NOM DU SALON") { SettingsTextField(placeholder: "nom-du-salon", text: $name) }
            SettingsSection(title: "SUJET DU SALON") {
                SettingsTextField(placeholder: "Dis à tout le monde comment utiliser ce salon", text: $topic, axis: .vertical)
            }
            Button(role: .destructive) { confirmDelete = true } label: {
                Label("Supprimer le salon", systemImage: "trash").foregroundStyle(MoodTheme.mentionBadge)
            }
            .buttonStyle(.plain)

            if hasChanges {
                UnsavedChangesBar(isSaving: isSaving, onReset: reset, onSave: save)
            }
        }
        .padding(20)
        .frame(width: 520)
        .background(MoodTheme.popupBg)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .popoverElevation()
        .onAppear(perform: reset)
        .alert("Supprimer #\(channel.name)", isPresented: $confirmDelete) {
            Button("Annuler", role: .cancel) {}
            Button("Supprimer le salon", role: .destructive) {
                isPresented = false
                onDeleted()
                Task { await matrixStore.deleteChannel(channel, from: server) }
            }
        } message: {
            Text("Le salon sera retiré du serveur et tu le quitteras. Matrix ne permet pas d'effacer l'historique pour les autres membres.")
        }
    }

    private func reset() {
        name = channel.name
        topic = channel.topic
    }

    private func save() {
        guard !name.trimmingCharacters(in: .whitespaces).isEmpty, !isSaving else { return }
        isSaving = true
        Task {
            await matrixStore.updateChannel(channel, name: name, topic: topic)
            isSaving = false
        }
    }
}

// MARK: - Copy Field

/// Read-only value with Discord's "Copier" button (turns into "Copié" for 2 s).
struct CopyField: View {
    let value: String
    @State private var copied = false

    var body: some View {
        HStack {
            Text(value)
                .font(.system(size: 14))
                .foregroundStyle(MoodTheme.textPrimary)
                .lineLimit(1)
                .truncationMode(.middle)
                .textSelection(.enabled)
            Spacer()
            Button {
                UIPasteboard.general.string = value
                copied = true
                Task {
                    try? await Task.sleep(for: .seconds(2))
                    copied = false
                }
            } label: {
                Text(copied ? "Copié" : "Copier")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 76)
                    .padding(.vertical, 7)
                    .background(copied ? MoodTheme.onlineGreen : MoodTheme.brandAccent)
                    .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
            }
            .buttonStyle(.plain)
        }
        .padding(.leading, 12)
        .padding(.trailing, 4)
        .padding(.vertical, 4)
        .background(MoodTheme.serverBar)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

// MARK: - Invite Modal

/// Discord's "Inviter des amis dans <serveur>": search people, invite them, or copy the link.
struct ServerInviteModal: View {
    @Environment(MatrixStore.self) private var matrixStore
    let server: MoodServer
    @Binding var isPresented: Bool
    @State private var query = ""
    @State private var results: [MatrixUserResult] = []
    @State private var invited: Set<String> = []
    @State private var searchTask: Task<Void, Never>?

    /// Before typing, suggest the people you already talk to — like Discord's friends list.
    private var suggestions: [(id: String, name: String)] {
        if !query.isEmpty {
            return results.map { ($0.userId, $0.displayName ?? $0.userId) }
        }
        let memberIds = Set(server.members.compactMap(\.matrixId))
        return matrixStore.friends.compactMap { user in
            guard let id = user.matrixId, !memberIds.contains(id) else { return nil }
            return (id, user.displayName)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Inviter des amis dans \(server.name)")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(MoodTheme.textPrimary)
                Spacer()
                Button { isPresented = false } label: {
                    Image(systemName: "xmark").font(.system(size: 14)).foregroundStyle(MoodTheme.textSecondary)
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.cancelAction)
            }

            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(MoodTheme.textSecondary)
                TextField("Rechercher des amis ou un identifiant (@nom:serveur)", text: $query)
                    .textFieldStyle(.plain)
                    .font(.system(size: 14))
                    .foregroundStyle(MoodTheme.textPrimary)
                    .onChange(of: query) { _, newValue in search(newValue) }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(MoodTheme.serverBar)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

            ScrollView {
                VStack(spacing: 2) {
                    if suggestions.isEmpty {
                        Text(query.isEmpty ? "Tes contacts apparaîtront ici." : "Aucun résultat pour « \(query) ».")
                            .font(.system(size: 13))
                            .foregroundStyle(MoodTheme.textSecondary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 20)
                    }
                    ForEach(suggestions, id: \.id) { person in
                        HStack(spacing: 10) {
                            AvatarGlyph(user: matrixStore.makeUser(person.id, displayName: person.name))
                                .font(.system(size: 14))
                                .frame(width: 32, height: 32)
                                .background(MoodTheme.serverIconBg)
                                .clipShape(Circle())
                            VStack(alignment: .leading, spacing: 1) {
                                Text(person.name).font(.system(size: 14, weight: .medium)).foregroundStyle(MoodTheme.textPrimary)
                                Text(person.id).font(.system(size: 11)).foregroundStyle(MoodTheme.textMuted)
                            }
                            Spacer()
                            let isInvited = invited.contains(person.id)
                            Button(isInvited ? "Invité" : "Inviter") {
                                invited.insert(person.id)
                                Task { await matrixStore.inviteToServer(server, matrixUserId: person.id) }
                            }
                            .buttonStyle(.plain)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(isInvited ? MoodTheme.textSecondary : .white)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 6)
                            .background(isInvited ? Color.clear : MoodTheme.onlineGreen)
                            .overlay(RoundedRectangle(cornerRadius: 4).stroke(isInvited ? MoodTheme.divider : .clear))
                            .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                            .disabled(isInvited)
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
            .frame(height: 220)

            Rectangle().fill(MoodTheme.divider).frame(height: 1)

            VStack(alignment: .leading, spacing: 6) {
                Text("OU ENVOIE UN LIEN D'INVITATION À UN AMI")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(MoodTheme.textSecondary)
                if let link = matrixStore.inviteLink(for: server) {
                    CopyField(value: link)
                }
                Text("Ton lien d'invitation n'expire pas.")
                    .font(.system(size: 11))
                    .foregroundStyle(MoodTheme.textMuted)
            }
        }
        .padding(18)
        .frame(width: 460)
        .background(MoodTheme.popupBg)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .popoverElevation()
    }

    private func search(_ text: String) {
        searchTask?.cancel()
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard trimmed.count >= 2 else { results = []; return }
        searchTask = Task {
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            var found = await matrixStore.searchUsers(query: trimmed)
            // A full Matrix id can always be invited, even when the directory does not list it.
            if let typed = matrixStore.matrixUserId(from: trimmed), trimmed.contains(":"),
               !found.contains(where: { $0.userId == typed }) {
                found.insert(MatrixUserResult(userId: typed, displayName: nil, avatarUrl: nil), at: 0)
            }
            guard !Task.isCancelled else { return }
            results = found
        }
    }
}

// MARK: - Modal Backdrop

extension View {
    /// Centers a Discord modal over a dimmed window; clicking outside dismisses it.
    func modalOverlay<Modal: View>(isPresented: Binding<Bool>, @ViewBuilder modal: () -> Modal) -> some View {
        overlay {
            if isPresented.wrappedValue {
                ZStack {
                    Color.black.opacity(0.7)
                        .ignoresSafeArea()
                        .onTapGesture { isPresented.wrappedValue = false }
                    modal()
                }
                .transition(.opacity)
            }
        }
        .animation(MoodMotion.popover, value: isPresented.wrappedValue)
    }
}

// MARK: - Server Actions Router

/// Lets the chat area trigger modals owned by the channel column
/// (welcome checklist, "Modifier le salon"), without threading bindings through every view.
@Observable
final class ServerActions {
    enum Action: Equatable {
        case invite
        case openSettings
        case editChannel(UUID)
    }

    var pending: Action?
}

// MARK: - Server Welcome

/// Discord's checklist in the first channel of a brand-new server.
struct ServerWelcomeChecklist: View {
    @Environment(ServerActions.self) private var actions
    let server: MoodServer

    var body: some View {
        VStack(spacing: 16 * LayoutMetrics.scale) {
            VStack(spacing: 6 * LayoutMetrics.scale) {
                Text("Bienvenue sur\n\(server.name)")
                    .font(.mood(28, weight: .bold))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(MoodTheme.textPrimary)
                Text("Voici ton tout nouveau serveur. Quelques étapes pour bien démarrer :")
                    .font(.mood(14))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(MoodTheme.textSecondary)
            }
            VStack(spacing: 8 * LayoutMetrics.scale) {
                WelcomeStep(icon: "person.2.fill", tint: MoodTheme.brandBlue, label: "Invite tes amis") {
                    actions.pending = .invite
                }
                WelcomeStep(icon: "paintbrush.pointed.fill", tint: MoodTheme.onlineGreen, label: "Personnalise ton serveur avec une icône",
                            isDone: server.iconURL != nil) {
                    actions.pending = .openSettings
                }
                WelcomeStep(icon: "paperplane.fill", tint: MoodTheme.brandAccent, label: "Envoie ton premier message", isDone: false) {}
                    .allowsHitTesting(false)
            }
        }
        .frame(maxWidth: 440)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 32 * LayoutMetrics.scale)
    }
}

private struct WelcomeStep: View {
    let icon: String
    let tint: Color
    let label: String
    var isDone = false
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12 * LayoutMetrics.scale) {
                Image(systemName: icon)
                    .font(.mood(18))
                    .foregroundStyle(tint)
                    .frame(width: 28 * LayoutMetrics.scale)
                Text(label)
                    .font(.mood(15, weight: .semibold))
                    .foregroundStyle(isDone ? MoodTheme.textSecondary : MoodTheme.textPrimary)
                Spacer()
                Image(systemName: isDone ? "checkmark.circle.fill" : "chevron.right")
                    .font(.mood(isDone ? 18 : 13, weight: .semibold))
                    .foregroundStyle(isDone ? MoodTheme.onlineGreen : MoodTheme.textSecondary)
            }
            .padding(.horizontal, 16 * LayoutMetrics.scale)
            .frame(height: 56 * LayoutMetrics.scale)
            .background(isHovered ? MoodTheme.hoverBg : MoodTheme.serverBar)
            .clipShape(RoundedRectangle(cornerRadius: 8 * LayoutMetrics.scale, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { hovering in withAnimation(MoodMotion.hover) { isHovered = hovering } }
    }
}
