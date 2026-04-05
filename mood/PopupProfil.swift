import SwiftUI

// MARK: - User Profile Popup

struct UserProfilePopup: View {
    let user: MoodUser
    var server: MoodServer? = nil
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            // Bannière gradient
            RoundedRectangle(cornerRadius: 0)
                .fill(
                    LinearGradient(
                        colors: [user.roleColor, MoodTheme.brandAccent],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(height: 80)
                .overlay(alignment: .topTrailing) {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.7))
                            .frame(width: 28, height: 28)
                            .background(.white.opacity(0.15))
                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                            .padding(12)
                    }
                }

            VStack(alignment: .leading, spacing: 14) {
                // Avatar
                HStack {
                    ZStack(alignment: .bottomTrailing) {
                        Text(user.avatarEmoji)
                            .font(.system(size: 30))
                            .frame(width: 56, height: 56)
                            .background(MoodTheme.popupBg)
                            .clipShape(Circle())
                            .overlay(
                                Circle()
                                    .stroke(MoodTheme.popupBg, lineWidth: 4)
                            )

                        StatusIndicator(status: user.status, size: 12, borderColor: MoodTheme.popupBg)
                            .offset(x: 3, y: 3)
                    }
                    .offset(y: -18)

                    Spacer()

                    Button {
                        // Ouvre la conversation DM
                        dismiss()
                    } label: {
                        Image(systemName: "bubble.left.fill")
                            .font(.system(size: 13))
                            .foregroundStyle(.white)
                            .frame(width: 34, height: 34)
                            .background(MoodTheme.brandAccent)
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .help("Envoyer un message")
                }

                // Infos
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(user.displayName)
                            .font(.system(size: 20, weight: .bold))
                            .foregroundStyle(MoodTheme.textPrimary)
                        RoleBadge(role: server?.roleFor(user) ?? .member, size: 16)
                    }

                    Text("@\(user.username)")
                        .font(.system(size: 13))
                        .foregroundStyle(MoodTheme.textSecondary)

                    HStack(spacing: 4) {
                        Circle().fill(user.statusColor).frame(width: 7, height: 7)
                        Text(user.status.rawValue.capitalized)
                            .font(.system(size: 12))
                            .foregroundStyle(MoodTheme.textSecondary)
                    }
                    .padding(.top, 2)
                }
                .offset(y: -12)

                // Sections
                VStack(spacing: 8) {
                    ProfileSection(title: "À PROPOS") {
                        Text(user.bio)
                            .font(.system(size: 13))
                            .foregroundStyle(MoodTheme.textPrimary)
                    }

                    ProfileSection(title: "MEMBRE DEPUIS") {
                        Text(user.joinedDate, style: .date)
                            .font(.system(size: 13))
                            .foregroundStyle(MoodTheme.textPrimary)
                    }

                    if let server, server.roleFor(user) != .member {
                        let role = server.roleFor(user)
                        ProfileSection(title: "RÔLE") {
                            HStack(spacing: 6) {
                                Image(systemName: role.icon)
                                    .font(.system(size: 12))
                                    .foregroundStyle(role.color)
                                Text(role.rawValue)
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(role.color)
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(role.color.opacity(0.10))
                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        }
                    }

                    if !user.badges.isEmpty {
                        ProfileSection(title: "BADGES") {
                            HStack(spacing: 6) {
                                ForEach(user.badges, id: \.self) { badge in
                                    Text(badge)
                                        .font(.system(size: 11, weight: .medium))
                                        .foregroundStyle(MoodTheme.brandAccent)
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 5)
                                        .background(MoodTheme.brandAccent.opacity(0.10))
                                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                                }
                            }
                        }
                    }
                }
                .offset(y: -8)

                Spacer()
            }
            .padding(.horizontal, 16)
        }
        .background(MoodTheme.popupBg)
    }
}

// MARK: - Profile Section

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
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(MoodTheme.glassBorder, lineWidth: 0.5)
        )
    }
}

#Preview {
    UserProfilePopup(user: MockData.users[1], server: MockData.servers[0])
        .preferredColorScheme(.dark)
}
