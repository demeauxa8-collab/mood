import SwiftUI

// MARK: - User Profile Popup (Discord-style card)

struct UserProfilePopup: View {
    let user: MoodUser
    var server: MoodServer? = nil
    var onDismiss: (() -> Void)? = nil
    @State private var messageText = ""

    private let bannerHeight: CGFloat = 60
    private let avatarSize: CGFloat = 76
    private let avatarBorder: CGFloat = 6
    private let avatarOverlap: CGFloat = 38

    // Compute mutual servers from MockData
    private var mutualServers: [MoodServer] {
        MockData.servers.filter { s in
            s.members.contains(where: { $0.id == user.id })
        }
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
                    .overlay(alignment: .topTrailing) {
                        Button { } label: {
                            Image(systemName: "ellipsis")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundStyle(.white.opacity(0.8))
                                .frame(width: 30, height: 30)
                                .background(.black.opacity(0.3))
                                .clipShape(Circle())
                        }
                        .buttonStyle(.plain)
                        .padding(8)
                    }

                // Avatar straddling the banner
                ZStack(alignment: .bottomTrailing) {
                    Text(user.avatarEmoji)
                        .font(.system(size: 36))
                        .frame(width: avatarSize, height: avatarSize)
                        .background(MoodTheme.popupBg)
                        .clipShape(Circle())
                        .overlay(
                            Circle()
                                .stroke(MoodTheme.popupBg, lineWidth: avatarBorder)
                        )

                    StatusIndicator(status: user.status, size: 14, borderColor: MoodTheme.popupBg)
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
                        Text(user.displayName)
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
                        Text(user.displayName + (user.discriminator.map { "#\($0)" } ?? ""))
                            .font(.system(size: 13))
                            .foregroundStyle(MoodTheme.textSecondary)

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
                Rectangle().fill(MoodTheme.divider).frame(height: 1)
                    .padding(.horizontal, 14)
                    .padding(.top, 12)

                // Info sections
                VStack(alignment: .leading, spacing: 12) {
                    // About
                    if !user.bio.isEmpty {
                        ProfileCardSection(title: "À PROPOS") {
                            Text(user.bio)
                                .font(.system(size: 13))
                                .foregroundStyle(MoodTheme.textPrimary)
                        }
                    }

                    // Member since
                    ProfileCardSection(title: "MEMBRE DEPUIS") {
                        HStack(spacing: 6) {
                            Image(systemName: "calendar")
                                .font(.system(size: 11))
                                .foregroundStyle(MoodTheme.textMuted)
                            Text(user.joinedDate, style: .date)
                                .font(.system(size: 12))
                                .foregroundStyle(MoodTheme.textSecondary)
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

                    // Add application button (for bots)
                    if user.isBot {
                        Button { } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "plus")
                                    .font(.system(size: 12, weight: .medium))
                                Text("Ajouter l'application")
                                    .font(.system(size: 13, weight: .medium))
                            }
                            .foregroundStyle(MoodTheme.textPrimary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(MoodTheme.glassBg)
                            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .stroke(MoodTheme.glassBorder, lineWidth: 1)
                            )
                        }
                        .buttonStyle(.plain)
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

                                    // "+" button to add role
                                    Button { } label: {
                                        Image(systemName: "plus")
                                            .font(.system(size: 10, weight: .medium))
                                            .foregroundStyle(MoodTheme.textSecondary)
                                            .frame(width: 26, height: 26)
                                            .background(MoodTheme.glassBg)
                                            .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                                    }
                                    .buttonStyle(.plain)
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

                // Message input at bottom
                HStack(spacing: 8) {
                    TextField("Envoyer un message à @\(user.username)", text: $messageText)
                        .textFieldStyle(.plain)
                        .font(.system(size: 13))
                        .foregroundStyle(MoodTheme.textPrimary)

                    if !messageText.isEmpty {
                        Button {
                            messageText = ""
                        } label: {
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

struct ProfileSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 11, weight: .bold))
                .tracking(0.4)
                .foregroundStyle(MoodTheme.textSecondary)
            content
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(MoodTheme.glassBg)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

#Preview {
    ZStack {
        MoodTheme.chatBackground.ignoresSafeArea()
        UserProfilePopup(user: MockData.users[1], server: MockData.servers[0])
            .frame(width: 320)
            .shadow(color: .black.opacity(0.5), radius: 20, y: 8)
    }
    .preferredColorScheme(.dark)
}
