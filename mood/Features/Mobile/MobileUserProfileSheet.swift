import SwiftUI

/// Discord iOS profile sheet: full-bleed banner, large avatar straddling it, name and Mood username,
/// one primary "Envoyer un message" action, then a single rounded card (about, status, mutual servers,
/// roles). The desktop keeps `UserProfilePopup`, its popover card.
struct MobileUserProfileSheet: View {
    @Environment(AccountStore.self) private var accountStore
    @Environment(MatrixStore.self) private var matrixStore
    @Environment(\.dismiss) private var dismiss
    let user: MoodUser
    var server: MoodServer? = nil
    @State private var opening = false

    private var liveUser: MoodUser { matrixStore.resolvedAccountUser(user) }
    private let bannerHeight = LayoutMetrics.mobile(110)
    private let avatarSize = LayoutMetrics.mobile(92)
    private let ring = LayoutMetrics.mobile(6)

    private var canMessage: Bool {
        user.matrixId?.hasPrefix("@") == true && user.matrixId != matrixStore.userId
            && !matrixStore.ignoredUserIds.contains(user.matrixId ?? "")
    }

    private var mutualServers: [MoodServer] {
        matrixStore.userId == nil
            ? MockData.servers.filter { s in s.members.contains(where: { $0.id == user.id }) }
            : matrixStore.mutualServers(with: user)
    }

    private var extended: (bio: String, pronouns: String)? {
        guard let id = user.matrixId, let profile = matrixStore.extendedProfiles[id] else { return nil }
        return (profile.bio, profile.pronouns)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                header
                identity
                if canMessage { messageButton }
                if let error = matrixStore.errorMessage {
                    Text(error).font(.mood(13)).foregroundStyle(MoodTheme.mentionBadge)
                        .padding(.horizontal, LayoutMetrics.mobile(16)).padding(.top, LayoutMetrics.mobile(8))
                }
                details
            }
            .padding(.bottom, LayoutMetrics.mobile(24))
        }
        .overlay(alignment: .topTrailing) {
            MobileCloseButton { dismiss() }.mobileGlassCapsule().padding(LayoutMetrics.mobile(12))
        }
        .scrollBounceBehavior(.basedOnSize)
        .background(MoodTheme.mobileSurface)
        .task {
            if let id = user.matrixId, matrixStore.userId != nil, id.hasPrefix("@") {
                await matrixStore.loadExtendedProfile(userId: id)
            }
        }
    }

    private var header: some View {
        ZStack(alignment: .bottomLeading) {
            LinearGradient(colors: [user.roleColor, user.roleColor.opacity(0.65)], startPoint: .topLeading, endPoint: .bottomTrailing)
                .frame(height: bannerHeight)
            ZStack(alignment: .bottomTrailing) {
                AvatarGlyph(user: liveUser)
                    .font(.mood(40))
                    .frame(width: avatarSize, height: avatarSize)
                    .background(MoodTheme.inputBg)
                    .clipShape(Circle())
                    .overlay(Circle().stroke(MoodTheme.mobileSurface, lineWidth: ring))
                StatusIndicator(status: liveUser.status, size: LayoutMetrics.mobile(20), borderColor: MoodTheme.mobileSurface)
                    .offset(x: -LayoutMetrics.mobile(2), y: -LayoutMetrics.mobile(2))
            }
            .padding(.leading, LayoutMetrics.mobile(16))
            .offset(y: avatarSize / 2)
        }
        .padding(.bottom, avatarSize / 2)
    }

    private var identity: some View {
        VStack(alignment: .leading, spacing: LayoutMetrics.mobile(2)) {
            HStack(spacing: LayoutMetrics.mobile(6)) {
                Text(liveUser.displayName).font(.mood(24, weight: .bold)).foregroundStyle(MoodTheme.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                if user.isBot { BotBadge() }
                if let server, server.roleFor(user) != .member { RoleBadge(role: server.roleFor(user), size: 16) }
            }
            if let username = accountStore.moodUsername(for: liveUser, currentUserId: matrixStore.userId) {
                Text(username).font(.mood(15)).foregroundStyle(MoodTheme.textSecondary)
            }
            if let pronouns = extended?.pronouns, !pronouns.isEmpty {
                Text(pronouns).font(.mood(14)).foregroundStyle(MoodTheme.textMuted)
            }
        }
        .padding(.horizontal, LayoutMetrics.mobile(16))
        .padding(.top, LayoutMetrics.mobile(12))
    }

    private var messageButton: some View {
        Button {
            guard let id = user.matrixId, !opening else { return }
            opening = true
            Task {
                if let conversation = await matrixStore.openOrCreateDM(with: id) {
                    dismiss()
                    matrixStore.openAccountConversation(conversation)
                }
                opening = false
            }
        } label: {
            HStack(spacing: LayoutMetrics.mobile(8)) {
                if opening { ProgressView().tint(.white) } else { Image(systemName: "bubble.left.fill") }
                Text("Envoyer un message")
            }
            .font(.mood(16, weight: .semibold))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, minHeight: LayoutMetrics.mobile(50))
            .background(MoodTheme.brandAccent, in: Capsule())
        }
        .buttonStyle(.plain)
        .disabled(opening)
        .padding(.horizontal, LayoutMetrics.mobile(16))
        .padding(.top, LayoutMetrics.mobile(16))
    }

    @ViewBuilder private var details: some View {
        let bio = extended?.bio ?? ""
        let rows = !bio.isEmpty || !liveUser.bio.isEmpty || !mutualServers.isEmpty
            || (server.map { $0.roleFor(user) != .member } ?? false)
        if rows {
            VStack(alignment: .leading, spacing: LayoutMetrics.mobile(16)) {
                if !bio.isEmpty { section("À propos de moi") { Text(bio).font(.mood(15)).foregroundStyle(MoodTheme.textPrimary) } }
                if !liveUser.bio.isEmpty { section("Statut") { Text(liveUser.bio).font(.mood(15)).foregroundStyle(MoodTheme.textPrimary) } }
                if !mutualServers.isEmpty {
                    section("\(mutualServers.count) serveur\(mutualServers.count > 1 ? "s" : "") en commun") {
                        HStack(spacing: LayoutMetrics.mobile(8)) {
                            ForEach(mutualServers.prefix(6)) { s in
                                Text(s.iconEmoji).font(.mood(18))
                                    .frame(width: LayoutMetrics.mobile(40), height: LayoutMetrics.mobile(40))
                                    .background(MoodTheme.serverIconBg, in: RoundedRectangle(cornerRadius: LayoutMetrics.mobile(12), style: .continuous))
                                    .accessibilityLabel(s.name)
                            }
                            if mutualServers.count > 6 {
                                Text("+\(mutualServers.count - 6)").font(.mood(13, weight: .semibold)).foregroundStyle(MoodTheme.textSecondary)
                            }
                        }
                    }
                }
                if let server, server.roleFor(user) != .member {
                    let role = server.roleFor(user)
                    section("Rôles") {
                        HStack(spacing: LayoutMetrics.mobile(6)) {
                            Circle().fill(role.color).frame(width: LayoutMetrics.mobile(10), height: LayoutMetrics.mobile(10))
                            Text(role.rawValue).font(.mood(14, weight: .medium)).foregroundStyle(MoodTheme.textPrimary)
                        }
                        .padding(.horizontal, LayoutMetrics.mobile(10)).padding(.vertical, LayoutMetrics.mobile(6))
                        .background(MoodTheme.serverIconBg, in: Capsule())
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(LayoutMetrics.mobile(16))
            .background(MoodTheme.inputBg, in: RoundedRectangle(cornerRadius: LayoutMetrics.mobile(16), style: .continuous))
            .padding(.horizontal, LayoutMetrics.mobile(16))
            .padding(.top, LayoutMetrics.mobile(16))
        }
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: LayoutMetrics.mobile(8)) {
            Text(title.uppercased()).font(.mood(12, weight: .bold)).foregroundStyle(MoodTheme.textSecondary)
            content()
        }
    }
}
