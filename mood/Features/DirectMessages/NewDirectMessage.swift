import SwiftUI

// MARK: - New DM Sheet
// Recherche d'utilisateurs Matrix (debounce 300 ms) puis ouverture/création du DM.

struct NewDMSheet: View {
    @Environment(MatrixStore.self) private var matrixStore
    @Environment(\.dismiss) private var dismiss
    /// Appelé avec l'id de la DMConversation (existante ou créée) après ouverture.
    var onOpen: (UUID) -> Void

    @State private var query = ""
    @State private var results: [MatrixUserResult] = []
    @State private var isSearching = false
    @State private var openingUserId: String?
    @State private var searchTask: Task<Void, Never>?
    @FocusState private var searchFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            header

            searchField

            Rectangle().fill(MoodTheme.divider).frame(height: 1)

            resultsList
        }
        .background(MoodTheme.channelList)
        .onAppear { searchFocused = true }
        .onChange(of: query) { _, newValue in
            scheduleSearch(newValue)
        }
        .onDisappear { searchTask?.cancel() }
    }

    // MARK: - Subviews

    private var header: some View {
        HStack {
            Text("Nouveau message")
                .font(.mood(16, weight: .bold))
                .foregroundStyle(MoodTheme.textPrimary)

            Spacer()

            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.mood(12))
                    .foregroundStyle(MoodTheme.textPrimary)
                    .frame(width: 28 * LayoutMetrics.scale, height: 28 * LayoutMetrics.scale)
                    .background(MoodTheme.glassBg)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16 * LayoutMetrics.scale)
        .padding(.vertical, 14 * LayoutMetrics.scale)
    }

    private var searchField: some View {
        HStack(spacing: 8 * LayoutMetrics.scale) {
            Image(systemName: "magnifyingglass")
                .font(.mood(13))
                .foregroundStyle(MoodTheme.textMuted)

            TextField("Nom ou identifiant (ex. @alice:matrix.org)", text: $query)
                .textFieldStyle(.plain)
                .font(.mood(13))
                .foregroundStyle(MoodTheme.textPrimary)
                .focused($searchFocused)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)

            if isSearching {
                ProgressView()
                    .scaleEffect(0.6)
                    .frame(width: 16, height: 16)
            } else if !query.isEmpty {
                Button { query = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.mood(12))
                        .foregroundStyle(MoodTheme.textMuted)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12 * LayoutMetrics.scale)
        .padding(.vertical, 10 * LayoutMetrics.scale)
        .background(MoodTheme.glassBg)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(MoodTheme.glassBorder, lineWidth: 0.5)
        )
        .padding(.horizontal, 16 * LayoutMetrics.scale)
        .padding(.bottom, 12 * LayoutMetrics.scale)
    }

    @ViewBuilder
    private var resultsList: some View {
        if results.isEmpty {
            VStack(spacing: 8 * LayoutMetrics.scale) {
                Image(systemName: query.isEmpty ? "person.crop.circle.badge.plus" : "magnifyingglass")
                    .font(.mood(28))
                    .foregroundStyle(MoodTheme.textMuted)

                Text(emptyStateText)
                    .font(.mood(13))
                    .foregroundStyle(MoodTheme.textSecondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(24)
        } else {
            ScrollView(showsIndicators: false) {
                LazyVStack(spacing: 2) {
                    ForEach(results, id: \.userId) { user in
                        UserResultRow(
                            user: user,
                            isOpening: openingUserId == user.userId
                        ) {
                            openDM(with: user.userId)
                        }
                    }
                }
                .padding(8)
            }
        }
    }

    private var emptyStateText: String {
        if query.trimmingCharacters(in: .whitespaces).count < 2 {
            return "Cherche quelqu'un pour lancer une conversation."
        }
        return isSearching ? "Recherche en cours…" : "Aucun utilisateur trouvé pour \"\(query)\"."
    }

    // MARK: - Actions

    private func scheduleSearch(_ rawQuery: String) {
        searchTask?.cancel()
        let trimmed = rawQuery.trimmingCharacters(in: .whitespaces)
        guard trimmed.count >= 2 else {
            results = []
            isSearching = false
            return
        }
        searchTask = Task {
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            isSearching = true
            let found = await matrixStore.searchUsers(query: trimmed)
            guard !Task.isCancelled else { return }
            results = found
            isSearching = false
        }
    }

    private func openDM(with userId: String) {
        guard openingUserId == nil else { return }
        openingUserId = userId
        Task {
            if let conversationId = await matrixStore.openOrCreateDM(with: userId) {
                onOpen(conversationId)
                dismiss()
            } else {
                // L'erreur est affichée par le bandeau global (matrixStore.errorMessage)
                openingUserId = nil
            }
        }
    }
}

// MARK: - User Result Row

private struct UserResultRow: View {
    @Environment(MatrixStore.self) private var matrixStore
    let user: MatrixUserResult
    let isOpening: Bool
    let onTap: () -> Void
    @State private var isHovered = false

    private var displayName: String {
        if let name = user.displayName, !name.isEmpty { return name }
        return String(user.userId.dropFirst().prefix(while: { $0 != ":" }))
    }

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 10 * LayoutMetrics.scale) {
                avatar

                VStack(alignment: .leading, spacing: 2) {
                    Text(displayName)
                        .font(.mood(14, weight: .medium))
                        .foregroundStyle(MoodTheme.textPrimary)

                    Text(user.userId)
                        .font(.mood(11))
                        .foregroundStyle(MoodTheme.textMuted)
                        .lineLimit(1)
                }

                Spacer()

                if isOpening {
                    ProgressView()
                        .scaleEffect(0.6)
                        .frame(width: 16, height: 16)
                } else {
                    Image(systemName: "bubble.left")
                        .font(.mood(13))
                        .foregroundStyle(MoodTheme.textMuted)
                }
            }
            .padding(.horizontal, 10 * LayoutMetrics.scale)
            .padding(.vertical, 8 * LayoutMetrics.scale)
            .background(isHovered ? MoodTheme.hoverBg : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isOpening)
        .onHover { hovering in isHovered = hovering }
    }

    @ViewBuilder
    private var avatar: some View {
        let size = 36 * LayoutMetrics.scale
        if let url = matrixStore.resolveMediaURL(user.avatarUrl, width: 72, height: 72) {
            AsyncImage(url: url) { image in
                image.resizable().scaledToFill()
            } placeholder: {
                initialAvatar
            }
            .frame(width: size, height: size)
            .clipShape(Circle())
        } else {
            initialAvatar
                .frame(width: size, height: size)
        }
    }

    private var initialAvatar: some View {
        ZStack {
            Circle().fill(MoodTheme.glassBg)
            Text(String(displayName.prefix(1)).uppercased())
                .font(.mood(15, weight: .semibold))
                .foregroundStyle(MoodTheme.textSecondary)
        }
    }
}

#Preview {
    NewDMSheet { _ in }
        .environment(MatrixStore())
        .frame(width: 420, height: 520)
        .preferredColorScheme(.dark)
}
