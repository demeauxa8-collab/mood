import SwiftUI

struct MobileProfileView: View {
    @Environment(AccountStore.self) private var accountStore
    @State private var showCustomStatus = false
    @State private var confirmSignOut = false
    let user: MoodUser?
    let status: MoodUser.UserStatus
    let statusMessage: String?
    @Binding var showStatusPicker: Bool
    @Binding var showSettings: Bool
    let authState: AuthState
    let store: MatrixStore

    var body: some View {
        ScrollView {
            VStack(spacing: LayoutMetrics.mobile(0)) {
                ZStack(alignment: .bottomLeading) {
                    MoodTheme.brandAccent.opacity(0.28)
                        .frame(height: LayoutMetrics.mobile(150))
                    if let user {
                        AvatarGlyph(user: user).font(.mood(42)).frame(width: LayoutMetrics.mobile(84), height: LayoutMetrics.mobile(84))
                            .background(MoodTheme.mobileSurface, in: RoundedRectangle(cornerRadius: LayoutMetrics.mobile(28), style: .continuous)).clipShape(RoundedRectangle(cornerRadius: LayoutMetrics.mobile(28), style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: LayoutMetrics.mobile(28), style: .continuous).stroke(MoodTheme.mobileSurface, lineWidth: LayoutMetrics.mobile(5)))
                            .overlay(alignment: .bottomTrailing) {
                                StatusIndicator(status: status, size: LayoutMetrics.mobile(18), borderColor: MoodTheme.mobileSurface).offset(x: LayoutMetrics.mobile(2), y: LayoutMetrics.mobile(2))
                            }
                            .padding(.leading, LayoutMetrics.mobile(16)).offset(y: LayoutMetrics.mobile(40))
                    }
                }
                .padding(.bottom, LayoutMetrics.mobile(42))

                VStack(alignment: .leading, spacing: LayoutMetrics.mobile(5)) {
                    Text(user?.displayName ?? "Mon profil").font(.mood(21, weight: .bold)).foregroundStyle(MoodTheme.textPrimary)
                    if let user, let username = accountStore.moodUsername(for: user, currentUserId: store.userId) {
                        Text(username).font(.mood(14)).foregroundStyle(MoodTheme.textSecondary)
                    }
                    if let statusMessage, !statusMessage.isEmpty {
                        Text(statusMessage).font(.mood(13)).foregroundStyle(MoodTheme.textMuted).padding(.top, LayoutMetrics.mobile(3))
                    }
                }.frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, LayoutMetrics.mobile(16))

                VStack(spacing: LayoutMetrics.mobile(0)) {
                    profileRow(icon: "circle.fill", color: statusColor, title: status.rawValue, detail: "Modifier le statut") {
                        showStatusPicker = true
                    }
                    profileRow(icon: "text.bubble", color: MoodTheme.textSecondary, title: "Statut personnalisé") {
                        showCustomStatus = true
                    }
                    profileRow(icon: "gearshape.fill", color: MoodTheme.textSecondary, title: "Réglages") {
                        showSettings = true
                    }
                    if authState.isLoggedIn {
                        profileRow(icon: "rectangle.portrait.and.arrow.right", color: MoodTheme.mentionBadge, title: "Déconnexion", destructive: true) {
                            confirmSignOut = true
                        }
                    }
                }
                .background(MoodTheme.inputBg, in: RoundedRectangle(cornerRadius: LayoutMetrics.mobile(16), style: .continuous))
                .padding(.top, LayoutMetrics.mobile(24))
                .padding(.horizontal, LayoutMetrics.mobile(16))
            }
            .padding(.bottom, LayoutMetrics.mobile(100))
        }
        .background(MoodTheme.mobileSurface)
        .onAppear {
            if MobileUIPreview.screen == "custom-status" { showCustomStatus = true }
        }
        .sheet(isPresented: $showCustomStatus) {
            MobileCustomStatusSheet(isPresented: $showCustomStatus).environment(store)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
                .presentationBackground(MoodTheme.mobileSurface)
        }
        .confirmationDialog("Se déconnecter de Mood ?", isPresented: $confirmSignOut, titleVisibility: .visible) {
            Button("Se déconnecter", role: .destructive) {
                Task { await accountStore.signOut(); store.logout(); authState.isLoggedIn = false }
            }
            Button("Annuler", role: .cancel) {}
        } message: { Text("Les messages non envoyés sur cet appareil seront perdus.") }
        .confirmationDialog("Ton statut", isPresented: $showStatusPicker, titleVisibility: .visible) {
            Button("En ligne") { setStatus(.online) }
            Button("Inactif") { setStatus(.idle) }
            Button("Ne pas déranger") { setStatus(.dnd) }
            Button("Invisible") { setStatus(.invisible) }
            Button("Annuler", role: .cancel) { }
        }
    }

    private var statusColor: Color {
        switch status {
        case .online: MoodTheme.onlineGreen
        case .idle: MoodTheme.statusIdle
        case .dnd: MoodTheme.mentionBadge
        case .invisible, .offline: MoodTheme.statusOffline
        }
    }

    private func setStatus(_ newStatus: MoodUser.UserStatus) {
        Task { await store.setMyStatus(newStatus, message: store.myStatusMessage) }
    }

    private func profileRow(icon: String, color: Color, title: String, detail: String? = nil, destructive: Bool = false, action: @escaping () -> Void) -> some View {
        VStack(spacing: LayoutMetrics.mobile(0)) {
        Button(action: action) {
            HStack(spacing: LayoutMetrics.mobile(12)) {
                Image(systemName: icon).font(.mood(17, weight: .medium)).foregroundStyle(color).frame(width: LayoutMetrics.mobile(26))
                VStack(alignment: .leading, spacing: LayoutMetrics.mobile(2)) {
                    Text(title).font(.mood(15, weight: .medium)).foregroundStyle(destructive ? color : MoodTheme.textPrimary)
                    if let detail { Text(detail).font(.mood(12)).foregroundStyle(MoodTheme.textMuted) }
                }
                Spacer()
                Image(systemName: "chevron.right").font(.mood(11, weight: .semibold)).foregroundStyle(MoodTheme.textMuted)
            }
            .padding(.horizontal, LayoutMetrics.mobile(12)).frame(minHeight: LayoutMetrics.mobile(54)).contentShape(Rectangle())
        }.buttonStyle(.plain)
        Rectangle().fill(MoodTheme.divider).frame(height: LayoutMetrics.mobile(0.5)).padding(.leading, LayoutMetrics.mobile(50))
        }
    }
}
