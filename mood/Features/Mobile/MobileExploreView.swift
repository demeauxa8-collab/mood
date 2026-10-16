import SwiftUI

/// Browses the signed-in homeserver's public Matrix room directory.
struct MobileExploreView: View {
    let store: MatrixStore
    @Environment(\.dismiss) private var dismiss
    @State private var search = ""
    @State private var rooms: [MatrixPublicRoom] = []
    @State private var loading = false
    @State private var joining: String?
    @State private var failure: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: LayoutMetrics.mobile(12)) {
                    if loading { ProgressView().frame(maxWidth: .infinity) }
                    if let failure {
                        Text(failure).font(.mood(15)).foregroundStyle(MoodTheme.mentionBadge).mobileCard()
                        Button("Réessayer") { Task { await load() } }.buttonStyle(MobilePrimaryButtonStyle())
                    }
                    if !loading && failure == nil && rooms.isEmpty {
                        ContentUnavailableView("Aucune communauté", systemImage: "safari", description: Text("Recherche une communauté publique sur Mood."))
                    }
                    ForEach(rooms, id: \.roomId) { room in
                        Button {
                            joining = room.roomId
                            Task {
                                if await store.joinRoom(room.roomId) { dismiss() }
                                joining = nil
                            }
                        } label: {
                            VStack(alignment: .leading, spacing: LayoutMetrics.mobile(5)) {
                                Text(room.name ?? "Communauté").font(.mood(16, weight: .semibold)).foregroundStyle(MoodTheme.textPrimary)
                                if let topic = room.topic { Text(topic).font(.mood(13)).foregroundStyle(MoodTheme.textSecondary) .fixedSize(horizontal: false, vertical: true) }
                                Text(joining == room.roomId ? "Connexion…" : "Rejoindre").font(.mood(13, weight: .semibold)).foregroundStyle(MoodTheme.brandAccent)
                            }.frame(maxWidth: .infinity, alignment: .leading).padding(LayoutMetrics.mobile(12))
                                .background(MoodTheme.inputBg, in: RoundedRectangle(cornerRadius: LayoutMetrics.mobile(16), style: .continuous))
                        }.buttonStyle(.plain).disabled(joining != nil)
                    }
                }.padding(LayoutMetrics.mobile(16))
            }
            .background(MoodTheme.mobileSurface)
            .navigationTitle("Explorer")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $search, prompt: "Rechercher")
            .onSubmit(of: .search) { Task { await load() } }
            .toolbar { ToolbarItem(placement: .cancellationAction) { MobileCloseButton { dismiss() } } }
            .task { await load() }
        }
        .presentationDetents([.large]).presentationDragIndicator(.visible)
        .presentationBackground(MoodTheme.mobileSurface)
    }

    private func load() async {
        loading = true
        failure = nil
        rooms = await store.fetchPublicRooms(filter: search.isEmpty ? nil : search)
        failure = store.errorMessage
        loading = false
    }
}
