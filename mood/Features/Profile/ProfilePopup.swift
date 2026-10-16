import SwiftUI

// MARK: - User Profile Popup (Discord-style card)

struct UserProfilePopup: View {
    @Environment(AccountStore.self) private var accountStore
    @Environment(MatrixStore.self) private var matrixStore
    @Environment(\.dismiss) private var dismiss
    let user: MoodUser
    var server: MoodServer? = nil
    var onDismiss: (() -> Void)? = nil
    /// Opens the DM once a message was sent from the card.
    var onOpenConversation: ((UUID) -> Void)? = nil
    @State private var messageText = ""

    private var liveUser: MoodUser { matrixStore.resolvedAccountUser(user) }

    private var canMessage: Bool {
        user.matrixId?.hasPrefix("@") == true && user.matrixId != matrixStore.userId
            && !matrixStore.ignoredUserIds.contains(user.matrixId ?? "")
    }

    private func sendMessage() {
        let text = messageText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, let matrixId = user.matrixId else { return }
        Task {
            if let conversationId = await matrixStore.sendDirectMessage(to: matrixId, text: text) {
                messageText = ""
                if let onDismiss { onDismiss() } else { dismiss() }
                if let onOpenConversation { onOpenConversation(conversationId) }
                else { matrixStore.openAccountConversation(conversationId) }
            }
        }
    }

    private let bannerHeight: CGFloat = 60
    private let avatarSize: CGFloat = 76
    private let avatarBorder: CGFloat = 6
    private let avatarOverlap: CGFloat = 38

    private var mutualServers: [MoodServer] {
        matrixStore.userId == nil
            ? MockData.servers.filter { s in s.members.contains(where: { $0.id == user.id }) }
            : matrixStore.mutualServers(with: user)
    }

    var body: some View {
        VStack(spacing: 0) {
            // Banner + Avatar overlay zone
            ZStack(alignment: .bottomLeading) {
                // Banner
                RoundedRectangle(cornerRadius: 0)
                    .fill(
                        LinearGradient(
                            colors: [user.roleColor, user.roleColor.opacity(0.6)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(height: bannerHeight)


                // Avatar straddling the banner
                ZStack(alignment: .bottomTrailing) {
                    AvatarGlyph(user: liveUser)
                        .font(.system(size: 36))
                        .frame(width: avatarSize, height: avatarSize)
                        .background(MoodTheme.popupBg)
                        .clipShape(Circle())
                        .overlay(
                            Circle()
                                .stroke(MoodTheme.popupBg, lineWidth: avatarBorder)
                        )

                    StatusIndicator(status: liveUser.status, size: 14, borderColor: MoodTheme.popupBg)
                        .offset(x: 0, y: -2)
                }
                .padding(.leading, 14)
                .offset(y: avatarOverlap)
            }

            // Content below avatar
            VStack(alignment: .leading, spacing: 0) {
                // Name + badges
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(liveUser.displayName)
                            .font(.system(size: 18, weight: .bold))
                            .foregroundStyle(MoodTheme.textPrimary)

                        if user.isBot {
                            BotBadge()
                        }

                        if let server, server.roleFor(user) != .member {
                            RoleBadge(role: server.roleFor(user), size: 14)
                        }
                    }

                    // Username#discriminator + dev badge
                    HStack(spacing: 4) {
                        if let username = accountStore.moodUsername(for: liveUser, currentUserId: matrixStore.userId) {
                            Text(username).font(.mood(13)).foregroundStyle(MoodTheme.textSecondary)
                        }

                        if user.isBot {
                            Text("{/}")
                                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                                .foregroundStyle(MoodTheme.textMuted)
                        }
                    }
                }
                .padding(.horizontal, 14)
                .padding(.top, avatarOverlap + 8)

                // Separator
                DesktopPixelRule()
                    .padding(.horizontal, 14)
                    .padding(.top, 12)

                // Info sections
                VStack(alignment: .leading, spacing: 12) {
                    if let id = user.matrixId, let profile = matrixStore.extendedProfiles[id] {
                        if !profile.pronouns.isEmpty {
                            Text(profile.pronouns).font(.mood(13)).foregroundStyle(MoodTheme.textSecondary)
                        }
                        if !profile.bio.isEmpty {
                            ProfileCardSection(title: "À PROPOS") {
                                Text(profile.bio).font(.mood(13)).foregroundStyle(MoodTheme.textPrimary)
                            }
                        }
                    }
                    // About
                    if !liveUser.bio.isEmpty {
                        ProfileCardSection(title: "STATUT") {
                            Text(liveUser.bio)
                                .font(.system(size: 13))
                                .foregroundStyle(MoodTheme.textPrimary)
                        }
                    }

                    // Mutual servers
                    if !mutualServers.isEmpty {
                        ProfileCardSection(title: "\(mutualServers.count) SERVEUR\(mutualServers.count > 1 ? "S" : "") EN COMMUN") {
                            HStack(spacing: 6) {
                                ForEach(mutualServers.prefix(5)) { s in
                                    Text(s.iconEmoji)
                                        .font(.system(size: 14))
                                        .frame(width: 28, height: 28)
                                        .background(MoodTheme.glassBg)
                                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                                        .help(s.name)
                                }
                                if mutualServers.count > 5 {
                                    Text("+\(mutualServers.count - 5)")
                                        .font(.system(size: 11, weight: .medium))
                                        .foregroundStyle(MoodTheme.textSecondary)
                                        .frame(width: 28, height: 28)
                                        .background(MoodTheme.glassBg)
                                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                                }
                            }
                        }
                    }

                    // Roles
                    if let server {
                        let role = server.roleFor(user)
                        if role != .member {
                            ProfileCardSection(title: "RÔLES") {
                                HStack(spacing: 6) {
                                    HStack(spacing: 6) {
                                        Circle()
                                            .fill(role.color)
                                            .frame(width: 10, height: 10)
                                        Text(role.rawValue)
                                            .font(.system(size: 12, weight: .medium))
                                            .foregroundStyle(MoodTheme.textPrimary)
                                    }
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 5)
                                    .background(MoodTheme.glassBg)
                                    .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))


                                }
                            }
                        }
                    }

                    // Badges
                    if !user.badges.isEmpty {
                        ProfileCardSection(title: "BADGES") {
                            HStack(spacing: 6) {
                                ForEach(user.badges, id: \.self) { badge in
                                    Text(badge)
                                        .font(.system(size: 11, weight: .medium))
                                        .foregroundStyle(MoodTheme.brandAccent)
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 4)
                                        .background(MoodTheme.brandAccent.opacity(0.10))
                                        .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, 14)
                .padding(.top, 12)

                if canMessage {
                    Button("Envoyer un message") {
                        Task {
                            if let id = user.matrixId, let conversation = await matrixStore.openOrCreateDM(with: id) {
                                if let onDismiss { onDismiss() } else { dismiss() }
                                if let onOpenConversation { onOpenConversation(conversation) }
                                else { matrixStore.openAccountConversation(conversation) }
                            }
                        }
                    }.font(.mood(14)).buttonStyle(.bordered)
                    .padding(LayoutMetrics.mobile(14))
                }

                if let error = matrixStore.errorMessage {
                    Text(error).font(.mood(12)).foregroundStyle(MoodTheme.mentionBadge)
                        .padding(LayoutMetrics.mobile(14))
                }
                // Message input at bottom
                HStack(spacing: 8) {
                    TextField("Envoyer un message à \(liveUser.displayName)", text: $messageText)
                        .textFieldStyle(.plain)
                        .font(.system(size: 13))
                        .foregroundStyle(MoodTheme.textPrimary)
                        .onSubmit(sendMessage)
                        .disabled(!canMessage)

                    if !messageText.isEmpty {
                        Button(action: sendMessage) {
                            Image(systemName: "paperplane.fill")
                                .font(.system(size: 12))
                                .foregroundStyle(MoodTheme.brandAccent)
                        }
                        .buttonStyle(.plain)
                    } else {
                        Image(systemName: "face.smiling")
                            .font(.system(size: 14))
                            .foregroundStyle(MoodTheme.textMuted)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(MoodTheme.glassBg)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .padding(.horizontal, 14)
                .padding(.top, 14)
                .padding(.bottom, 14)
            }
        }
        .task {
            if let id = user.matrixId, matrixStore.userId != nil, id.hasPrefix("@") {
                await matrixStore.loadExtendedProfile(userId: id)
            }
        }
        .background(MoodTheme.popupBg)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

// MARK: - Bot Badge

struct BotBadge: View {
    var body: some View {
        Text("APP")
            .font(.system(size: 9, weight: .bold))
            .foregroundStyle(.white)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(MoodTheme.onlineGreen)
            .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
    }
}

// MARK: - Profile Card Section

struct ProfileCardSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 11, weight: .bold))
                .tracking(0.4)
                .foregroundStyle(MoodTheme.textSecondary)
            content
        }
    }
}

// MARK: - Legacy ProfileSection (used elsewhere)

#Preview {
    ZStack {
        MoodTheme.chatBackground.ignoresSafeArea()
        UserProfilePopup(user: MockData.users[1], server: MockData.servers[0])
            .frame(width: 320)
            .shadow(color: .black.opacity(0.5), radius: 20, y: 8)
    }
    .preferredColorScheme(.dark)
}
