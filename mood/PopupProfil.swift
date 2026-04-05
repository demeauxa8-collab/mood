import SwiftUI

// MARK: - User Profile Popup (Discord-style card)

struct UserProfilePopup: View {
    let user: MoodUser
    var server: MoodServer? = nil
    var onDismiss: (() -> Void)? = nil
    @State private var messageText = ""
    @State private var showMoreMenu = false

    var body: some View {
        VStack(spacing: 0) {
            // Banner
            ZStack(alignment: .topTrailing) {
                RoundedRectangle(cornerRadius: 0)
                    .fill(
                        LinearGradient(
                            colors: [user.roleColor, user.roleColor.opacity(0.7)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(height: 60)

                // More button (...)
                Button { showMoreMenu.toggle() } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.white.opacity(0.8))
                        .frame(width: 32, height: 32)
                        .background(.black.opacity(0.3))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .padding(8)
            }

            VStack(alignment: .leading, spacing: 0) {
                // Avatar overlapping banner
                HStack(alignment: .top) {
                    ZStack(alignment: .bottomTrailing) {
                        Text(user.avatarEmoji)
                            .font(.system(size: 36))
                            .frame(width: 68, height: 68)
                            .background(MoodTheme.popupBg)
                            .clipShape(Circle())
                            .overlay(
                                Circle()
                                    .stroke(MoodTheme.popupBg, lineWidth: 5)
                            )

                        StatusIndicator(status: user.status, size: 14, borderColor: MoodTheme.popupBg)
                            .offset(x: 2, y: 2)
                    }
                    .offset(y: -30)

                    Spacer()
                }
                .padding(.horizontal, 14)

                // Name + badge + tag
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(user.displayName)
                            .font(.system(size: 18, weight: .bold))
                            .foregroundStyle(MoodTheme.textPrimary)

                        if let server, server.roleFor(user) != .member {
                            RoleBadge(role: server.roleFor(user), size: 14)
                        }
                    }

                    Text("@\(user.username)")
                        .font(.system(size: 13))
                        .foregroundStyle(MoodTheme.textSecondary)
                }
                .padding(.horizontal, 14)
                .offset(y: -18)

                // Divider
                Rectangle().fill(MoodTheme.divider).frame(height: 1)
                    .padding(.horizontal, 14)
                    .padding(.top, -8)

                // Sections
                VStack(alignment: .leading, spacing: 10) {
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

                    // Roles
                    if let server {
                        let role = server.roleFor(user)
                        if role != .member {
                            ProfileCardSection(title: "RÔLES") {
                                HStack(spacing: 6) {
                                    Circle()
                                        .fill(role.color)
                                        .frame(width: 10, height: 10)
                                    Text(role.rawValue)
                                        .font(.system(size: 12, weight: .medium))
                                        .foregroundStyle(MoodTheme.textPrimary)
                                }
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(MoodTheme.glassBg)
                                .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
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
                .padding(.top, 4)

                Spacer(minLength: 8)

                // Message input at bottom (like Discord)
                HStack(spacing: 8) {
                    TextField("Envoyer un message à @\(user.username)", text: $messageText)
                        .textFieldStyle(.plain)
                        .font(.system(size: 13))
                        .foregroundStyle(MoodTheme.textPrimary)

                    if !messageText.isEmpty {
                        Button {
                            messageText = ""
                            onDismiss?()
                        } label: {
                            Image(systemName: "paperplane.fill")
                                .font(.system(size: 12))
                                .foregroundStyle(MoodTheme.brandAccent)
                        }
                        .buttonStyle(.plain)
                    } else {
                        Button {} label: {
                            Image(systemName: "face.smiling")
                                .font(.system(size: 14))
                                .foregroundStyle(MoodTheme.textMuted)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(MoodTheme.glassBg)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .padding(.horizontal, 14)
                .padding(.bottom, 14)
            }
        }
        .background(MoodTheme.popupBg)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
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

// MARK: - Legacy wrapper (keep ProfileSection for other uses)

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
    UserProfilePopup(user: MockData.users[1], server: MockData.servers[0])
        .frame(width: 300)
        .preferredColorScheme(.dark)
}
