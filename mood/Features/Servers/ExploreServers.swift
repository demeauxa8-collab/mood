import SwiftUI

// MARK: - Explore Servers View
// The compass on the server rail: the public room directory of the user's homeserver
// (`POST /publicRooms`), searchable, with a real "Rejoindre".

struct ExploreServersView: View {
    @Environment(MatrixStore.self) private var matrixStore
    /// Opens a joined room (its server or channel). ContentView waits for sync when it is not there yet.
    var onOpenRoom: (UUID) -> Void = { _ in }

    @State private var searchText = ""
    @State private var rooms: [MatrixPublicRoom] = []
    @State private var status: Status = .loading
    @State private var isRefreshing = false
    @State private var joinStates: [String: JoinState] = [:]

    private enum Status: Equatable {
        case loading
        case ready
        case failed(String)
        case noAccount
    }

    private enum JoinState {
        case joining, joined, failed
    }

    private var trimmedSearch: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        VStack(spacing: 0) {
            header

            Rectangle().fill(MoodTheme.divider).frame(height: 1 * LayoutMetrics.scale)

            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(MoodTheme.chatBackground)
        // Restarted on every keystroke: the previous request is cancelled and the new one waits 300 ms.
        .task(id: searchText) { await reload() }
    }

    // MARK: Header

    private var header: some View {
        VStack(spacing: 18 * LayoutMetrics.scale) {
            VStack(spacing: 8 * LayoutMetrics.scale) {
                Text("Découvrir des communautés")
                    .font(.mood(24, weight: .bold))
                    .foregroundStyle(MoodTheme.textPrimary)

                Text("Les salons publics référencés sur ton serveur Matrix.")
                    .font(.mood(14))
                    .foregroundStyle(MoodTheme.textSecondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 500 * LayoutMetrics.scale)
            }

            HStack(spacing: 10 * LayoutMetrics.scale) {
                Image(systemName: "magnifyingglass")
                    .font(.mood(14))
                    .foregroundStyle(MoodTheme.textMuted)
                    .accessibilityHidden(true)

                TextField("Explorer des communautés", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(.mood(14))
                    .foregroundStyle(MoodTheme.textPrimary)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .accessibilityLabel("Rechercher un salon public")

                if isRefreshing {
                    ProgressView()
                        .controlSize(.small)
                } else if !searchText.isEmpty {
                    Button { searchText = "" } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.mood(13))
                            .foregroundStyle(MoodTheme.textMuted)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Effacer la recherche")
                }
            }
            .padding(.horizontal, 14 * LayoutMetrics.scale)
            .frame(height: 44 * LayoutMetrics.scale)
            .background(MoodTheme.dmSearchBackground)
            .clipShape(RoundedRectangle(cornerRadius: 10 * LayoutMetrics.scale, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 10 * LayoutMetrics.scale, style: .continuous)
                    .strokeBorder(MoodTheme.dmSearchBorder, lineWidth: 1)
            )
            .frame(maxWidth: 540 * LayoutMetrics.scale)
        }
        .padding(.horizontal, 24 * LayoutMetrics.scale)
        .padding(.top, 36 * LayoutMetrics.scale)
        .padding(.bottom, 24 * LayoutMetrics.scale)
        .frame(maxWidth: .infinity)
    }

    // MARK: Content

    @ViewBuilder
    private var content: some View {
        switch status {
        case .loading:
            VStack(spacing: 12 * LayoutMetrics.scale) {
                ProgressView()
                Text("Chargement des salons publics…")
                    .font(.mood(13))
                    .foregroundStyle(MoodTheme.textSecondary)
            }
        case .noAccount:
            message(
                icon: "person.crop.circle.badge.questionmark",
                title: "Connecte-toi pour explorer",
                detail: "Le répertoire public se lit depuis ton compte Matrix. Le mode démo n'y a pas accès."
            )
        case .failed(let reason):
            message(
                icon: "wifi.exclamationmark",
                title: "Impossible de charger les salons",
                detail: reason,
                actionTitle: "Réessayer"
            ) {
                Task { await reload() }
            }
        case .ready where rooms.isEmpty:
            if trimmedSearch.isEmpty {
                message(
                    icon: "safari",
                    title: "Aucun salon public",
                    detail: "Ton serveur Matrix n'en référence aucun pour l'instant. Rejoins un serveur avec un lien d'invitation depuis le bouton + de la barre latérale."
                )
            } else {
                message(
                    icon: "magnifyingglass",
                    title: "Aucun résultat",
                    detail: "Aucun salon public ne correspond à « \(trimmedSearch) »."
                )
            }
        case .ready:
            ScrollView {
                VStack(alignment: .leading, spacing: 14 * LayoutMetrics.scale) {
                    Text(sectionTitle)
                        .font(.mood(12, weight: .bold))
                        .foregroundStyle(MoodTheme.textSubtle)
                        .accessibilityAddTraits(.isHeader)

                    LazyVGrid(
                        columns: [GridItem(.adaptive(minimum: 300 * LayoutMetrics.scale, maximum: 440 * LayoutMetrics.scale), spacing: 16 * LayoutMetrics.scale, alignment: .top)],
                        spacing: 16 * LayoutMetrics.scale
                    ) {
                        ForEach(rooms, id: \.roomId) { room in
                            ExploreRoomCard(
                                room: room,
                                avatarURL: matrixStore.resolveMediaURL(room.avatarUrl, width: 96, height: 96),
                                state: state(for: room),
                                onJoin: { join(room) },
                                onOpen: { onOpenRoom(matrixStore.stableUUID(from: room.roomId)) }
                            )
                        }
                    }
                }
                .frame(maxWidth: 1180 * LayoutMetrics.scale)
                .padding(.horizontal, 24 * LayoutMetrics.scale)
                .padding(.vertical, 24 * LayoutMetrics.scale)
                .frame(maxWidth: .infinity)
            }
        }
    }

    private var sectionTitle: String {
        let count = rooms.count
        let noun = count > 1 ? "salons" : "salon"
        return trimmedSearch.isEmpty
            ? "SALONS PUBLICS · \(count)"
            : "\(count) \(noun) pour « \(trimmedSearch.uppercased()) »"
    }

    private func message(
        icon: String,
        title: String,
        detail: String,
        actionTitle: String? = nil,
        action: (() -> Void)? = nil
    ) -> some View {
        VStack(spacing: 10 * LayoutMetrics.scale) {
            Image(systemName: icon)
                .font(.mood(40))
                .foregroundStyle(MoodTheme.textMuted)
                .padding(.bottom, 4 * LayoutMetrics.scale)
                .accessibilityHidden(true)

            Text(title)
                .font(.mood(18, weight: .semibold))
                .foregroundStyle(MoodTheme.textPrimary)

            Text(detail)
                .font(.mood(13))
                .foregroundStyle(MoodTheme.textSecondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 380 * LayoutMetrics.scale)

            if let actionTitle, let action {
                ExploreActionButton(title: actionTitle, style: .primary, action: action)
                    .padding(.top, 6 * LayoutMetrics.scale)
            }
        }
        .padding(24 * LayoutMetrics.scale)
    }

    // MARK: Loading and joining

    private func reload() async {
        guard matrixStore.userId != nil else {
            status = .noAccount
            isRefreshing = false
            return
        }
        let term = trimmedSearch
        if !term.isEmpty {
            // Debounce: `.task(id:)` cancels this sleep as soon as the next character arrives.
            try? await Task.sleep(for: .milliseconds(300))
            if Task.isCancelled { return }
        }

        if rooms.isEmpty { status = .loading }
        isRefreshing = true
        do {
            let found = try await matrixStore.loadPublicRooms(limit: 50, filter: term.isEmpty ? nil : term)
            if Task.isCancelled { return }
            // A joined space only becomes a server once one of its rooms is joined, so only rooms are offered.
            rooms = found.filter { $0.roomType != "m.space" }
            status = .ready
        } catch {
            if Task.isCancelled { return }
            status = .failed(error.localizedDescription)
        }
        isRefreshing = false
    }

    private func state(for room: MatrixPublicRoom) -> ExploreRoomCard.Availability {
        if joinStates[room.roomId] == .joining { return .joining }
        if joinStates[room.roomId] == .joined || matrixStore.hasJoined(roomId: room.roomId) { return .joined }
        if joinStates[room.roomId] == .failed { return .failed }
        return .available
    }

    private func join(_ room: MatrixPublicRoom) {
        guard joinStates[room.roomId] != .joining else { return }
        joinStates[room.roomId] = .joining
        let reference = room.canonicalAlias ?? room.roomId
        Task {
            if let joinedID = await matrixStore.joinServer(fromInvite: reference) {
                joinStates[room.roomId] = .joined
                onOpenRoom(joinedID)
            } else {
                joinStates[room.roomId] = .failed
            }
        }
    }
}

// MARK: - Room card

private struct ExploreRoomCard: View {
    enum Availability { case available, joining, joined, failed }

    let room: MatrixPublicRoom
    let avatarURL: URL?
    let state: Availability
    let onJoin: () -> Void
    let onOpen: () -> Void

    private var title: String {
        let name = room.name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return name.isEmpty ? (room.canonicalAlias ?? room.roomId) : name
    }

    private var memberLabel: String {
        let count = room.numJoinedMembers ?? 0
        return "\(count.formatted()) \(count > 1 ? "membres" : "membre")"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12 * LayoutMetrics.scale) {
            HStack(spacing: 12 * LayoutMetrics.scale) {
                avatar

                VStack(alignment: .leading, spacing: 2 * LayoutMetrics.scale) {
                    Text(title)
                        .font(.mood(16, weight: .bold))
                        .foregroundStyle(MoodTheme.textPrimary)
                        .lineLimit(1)

                    if let alias = room.canonicalAlias, alias != title {
                        Text(alias)
                            .font(.mood(12))
                            .foregroundStyle(MoodTheme.textMuted)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
            }

            Text(topicText)
                .font(.mood(13))
                .foregroundStyle(room.topic?.isEmpty == false ? MoodTheme.textSecondary : MoodTheme.textMuted)
                .lineLimit(3)
                .frame(maxWidth: .infinity, minHeight: 52 * LayoutMetrics.scale, alignment: .topLeading)

            HStack(spacing: 8 * LayoutMetrics.scale) {
                Image(systemName: "person.2.fill")
                    .font(.mood(11))
                    .foregroundStyle(MoodTheme.textMuted)
                    .accessibilityHidden(true)
                Text(memberLabel)
                    .font(.mood(12, weight: .medium))
                    .foregroundStyle(MoodTheme.textSecondary)

                Spacer(minLength: 8 * LayoutMetrics.scale)

                action
            }
        }
        .padding(16 * LayoutMetrics.scale)
        .background(MoodTheme.glassBg)
        .clipShape(RoundedRectangle(cornerRadius: 12 * LayoutMetrics.scale, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12 * LayoutMetrics.scale, style: .continuous)
                .strokeBorder(MoodTheme.glassBorder, lineWidth: 1)
        )
        .accessibilityElement(children: .contain)
    }

    private var topicText: String {
        if let topic = room.topic?.trimmingCharacters(in: .whitespacesAndNewlines), !topic.isEmpty { return topic }
        return "Pas de description."
    }

    private var avatar: some View {
        Group {
            if let avatarURL {
                AsyncImage(url: avatarURL) { phase in
                    if case .success(let image) = phase {
                        image.resizable().scaledToFill()
                    } else {
                        initial
                    }
                }
            } else {
                initial
            }
        }
        .frame(width: 48 * LayoutMetrics.scale, height: 48 * LayoutMetrics.scale)
        .background(MoodTheme.serverIconBg)
        .clipShape(RoundedRectangle(cornerRadius: 14 * LayoutMetrics.scale, style: .continuous))
        .accessibilityHidden(true)
    }

    private var initial: some View {
        Text(String(title.first(where: { $0.isLetter || $0.isNumber }) ?? "#").uppercased())
            .font(.mood(20, weight: .bold))
            .foregroundStyle(MoodTheme.textPrimary)
    }

    @ViewBuilder
    private var action: some View {
        switch state {
        case .available:
            ExploreActionButton(title: "Rejoindre", style: .primary, action: onJoin)
        case .failed:
            ExploreActionButton(title: "Réessayer", style: .primary, action: onJoin)
        case .joining:
            ExploreActionButton(title: "Connexion…", style: .secondary, isBusy: true) {}
        case .joined:
            ExploreActionButton(title: "Ouvrir", style: .secondary, action: onOpen)
        }
    }
}

// MARK: - Button

private struct ExploreActionButton: View {
    enum Style { case primary, secondary }

    let title: String
    let style: Style
    var isBusy = false
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6 * LayoutMetrics.scale) {
                if isBusy {
                    ProgressView().controlSize(.small)
                }
                Text(title)
                    .font(.mood(13, weight: .semibold))
            }
            .foregroundStyle(style == .primary ? Color.white : MoodTheme.textPrimary)
            .padding(.horizontal, 14 * LayoutMetrics.scale)
            .frame(height: 32 * LayoutMetrics.scale)
            .background(background)
            .clipShape(RoundedRectangle(cornerRadius: 8 * LayoutMetrics.scale, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isBusy)
        .onHover { hovering in
            withAnimation(MoodMotion.hover) { isHovered = hovering }
        }
    }

    private var background: Color {
        switch style {
        case .primary: MoodTheme.brandAccent.opacity(isHovered ? 0.85 : 1)
        case .secondary: isHovered ? MoodTheme.serverMenuHover : MoodTheme.serverMenuTagBackground
        }
    }
}
