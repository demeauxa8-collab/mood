import SwiftUI

struct MobileMemberList: View {
    let members: [MoodUser]
    let server: MoodServer
    @State private var query = ""
    @State private var selectedUser: MoodUser?

    private var filtered: [MoodUser] {
        members.filter { query.isEmpty || $0.displayName.localizedCaseInsensitiveContains(query) }
    }
    var body: some View {
        List {
            if filtered.isEmpty {
                Section { Text(query.isEmpty ? "Aucun membre" : "Aucun membre trouvé").foregroundStyle(MoodTheme.textSecondary) }
                    .listRowBackground(MoodTheme.inputBg)
            }
            ForEach([ServerRole.owner, .admin, .moderator, .member], id: \.self) { role in
                let people = filtered.filter { server.roleFor($0) == role }
                if !people.isEmpty {
                    Section(role.rawValue.uppercased()) {
                        ForEach(people) { user in
                            Button { selectedUser = user } label: {
                                HStack(spacing: LayoutMetrics.mobile(12)) {
                                    AvatarGlyph(user: user).font(.mood(22))
                                        .frame(width: LayoutMetrics.mobile(44), height: LayoutMetrics.mobile(44))
                                        .background(MoodTheme.mobileSurface, in: Circle())
                                    VStack(alignment: .leading, spacing: LayoutMetrics.mobile(3)) {
                                        Text(user.displayName).font(.mood(16, weight: .semibold))
                                            .fixedSize(horizontal: false, vertical: true)
                                        Text(user.status.rawValue).font(.mood(14)).foregroundStyle(MoodTheme.textSecondary)
                                    }
                                    Spacer(minLength: 0)
                                    Image(systemName: "chevron.right").font(.mood(13)).foregroundStyle(MoodTheme.textMuted)
                                }.foregroundStyle(MoodTheme.textPrimary)
                            }.buttonStyle(.plain)
                        }
                    }.listRowBackground(MoodTheme.inputBg)
                }
            }
        }.mobileGroupedList().searchable(text: $query, prompt: "Rechercher un membre")
            .sheet(item: $selectedUser) { user in
                MobileUserProfileSheet(user: user, server: server)
                    .presentationDetents([.large]).presentationDragIndicator(.visible)
                    .presentationBackground(MoodTheme.mobileSurface)
            }
    }
}
