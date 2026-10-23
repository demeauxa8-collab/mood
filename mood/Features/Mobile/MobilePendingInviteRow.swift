import SwiftUI

struct MobilePendingInviteRow: View {
    @Environment(MatrixStore.self) private var store
    let invite: MatrixStore.PendingInvite
    @State private var working = false

    var body: some View {
        VStack(alignment: .leading, spacing: LayoutMetrics.mobile(10)) {
            Text(invite.isDirect ? (invite.inviterName ?? "Utilisateur Mood") : invite.roomName)
                .font(.mood(15, weight: .semibold)).foregroundStyle(MoodTheme.textPrimary)
            Text(invite.isDirect ? "Veut discuter avec toi" : "Invitation de \(invite.inviterName ?? "un membre")")
                .font(.mood(13)).foregroundStyle(MoodTheme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: LayoutMetrics.mobile(12)) {
                Button("Accepter") { respond(accept: true) }
                    .foregroundStyle(MoodTheme.onlineGreen)
                Button("Refuser") { respond(accept: false) }
                    .foregroundStyle(MoodTheme.mentionBadge)
                if working { ProgressView().controlSize(.small) }
            }
            .font(.mood(15, weight: .semibold)).buttonStyle(.bordered).controlSize(.large).buttonBorderShape(.capsule)
            .disabled(working || store.userId == nil)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(LayoutMetrics.mobile(12))
        .background(MoodTheme.inputBg, in: RoundedRectangle(cornerRadius: LayoutMetrics.mobile(16)))
        .padding(.horizontal, LayoutMetrics.mobile(16))
        .padding(.bottom, LayoutMetrics.mobile(6))
    }

    private func respond(accept: Bool) {
        working = true
        Task {
            if accept { await store.acceptInvite(roomId: invite.id) }
            else { await store.rejectInvite(roomId: invite.id) }
            working = false
        }
    }
}
