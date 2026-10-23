import SwiftUI

// MARK: - New DM Sheet
// Recherche d'utilisateurs Matrix (debounce 300 ms) puis ouverture/création du DM.

struct NewDMSheet: View {
    @Environment(\.layoutMode) private var layoutMode
    @Environment(MatrixStore.self) private var matrixStore
    @Environment(\.dismiss) private var dismiss
    /// Appelé avec l'id de la DMConversation (existante ou créée) après ouverture.
    var onOpen: (UUID) -> Void

    @State private var groupMode = ProcessInfo.processInfo.arguments.contains("-uiPreview") && (ProcessInfo.processInfo.arguments.contains("-uiPreviewGroup") || MobileUIPreview.screen == "group-dm")
    @State private var groupName = ""
    @State private var selectedUsers: [String: String] = [:]
    @State private var query = ""
    @State private var results: [MatrixUserResult] = MobileUIPreview.screen == "new-dm-results"
        ? [MatrixUserResult(userId: "@camille:example.invalid", displayName: "Camille avec un nom de profil très long sur plusieurs lignes", avatarUrl: nil)] : []
    @State private var isSearching = false
    @State private var openingUserId: String?
    @State private var searchTask: Task<Void, Never>?
    @FocusState private var searchFocused: Bool

    var body: some View {
        Group { if layoutMode == .compact { mobileBody } else { desktopBody } }
            .onAppear { searchFocused = !ProcessInfo.processInfo.arguments.contains("-uiPreview") }
            .onChange(of: query) { _, value in if layoutMode == .compact { scheduleSearch(value) } }
            .onDisappear { searchTask?.cancel() }
    }

    private var mobileBody: some View {
        MobileSheet(title: "Nouveau message", onClose: { dismiss() }) {
            List {
                Section {
                    Toggle("Message de groupe", isOn: $groupMode)
                    if groupMode {
                        TextField("Nom du groupe", text: $groupName, axis: .vertical).lineLimit(1...3)
                        if !selectedUsers.isEmpty {
                            Text(selectedUsers.values.sorted().joined(separator: ", ")).font(.mood(14)).foregroundStyle(MoodTheme.textSecondary)
                        }
                    }
                    TextField("Nom d’utilisateur", text: $query).focused($searchFocused)
                        .autocorrectionDisabled().textInputAutocapitalization(.never)
                }.listRowBackground(MoodTheme.inputBg)
                Section("Amis") {
                    if isSearching { ProgressView("Recherche…") }
                    else if results.isEmpty { Text(emptyStateText).font(.mood(15)).foregroundStyle(MoodTheme.textSecondary).fixedSize(horizontal: false, vertical: true) }
                    ForEach(results, id: \.userId) { user in
                        HStack {
                            UserResultRow(user: user, isOpening: openingUserId == user.userId) {
                                if groupMode {
                                    if selectedUsers[user.userId] != nil { selectedUsers.removeValue(forKey: user.userId) }
                                    else { selectedUsers[user.userId] = user.displayName ?? String(user.userId.dropFirst().prefix(while: { $0 != ":" })) }
                                } else { openDM(with: user.userId) }
                            }
                            if groupMode { Image(systemName: selectedUsers[user.userId] == nil ? "circle" : "checkmark.circle.fill").foregroundStyle(MoodTheme.brandAccent) }
                        }
                    }
                }.listRowBackground(MoodTheme.inputBg)
                if let error = matrixStore.errorMessage { Section { Text(error).foregroundStyle(MoodTheme.mentionBadge) }.listRowBackground(MoodTheme.inputBg) }
                if groupMode {
                    Section {
                        Button(openingUserId == "group" ? "Création…" : "Créer le groupe") {
                            openingUserId = "group"
                            Task {
                                if let id = await matrixStore.createGroupDM(name: groupName, invitees: Array(selectedUsers.keys)) { onOpen(id); dismiss() }
                                openingUserId = nil
                            }
                        }.buttonStyle(MobilePrimaryButtonStyle())
                            .disabled(selectedUsers.count < 2 || groupName.trimmingCharacters(in: .whitespaces).isEmpty || openingUserId != nil)
                    }.listRowBackground(MoodTheme.mobileSurface).listRowInsets(EdgeInsets())
                }
            }.mobileGroupedList()
        }
    }

    private var desktopBody: some View {
        VStack(spacing: 0) {
            header

            Toggle("MP de groupe", isOn: $groupMode).font(.mood(14)).padding(LayoutMetrics.mobile(12))
            if groupMode {
                TextField("Nom du groupe", text: $groupName).font(.mood(14)).padding(LayoutMetrics.mobile(12))
                Text(selectedUsers.values.sorted().joined(separator: ", ")).font(.mood(12)).foregroundStyle(MoodTheme.textSecondary)
                Button("Créer le groupe") {
                    openingUserId = "group"
                    Task {
                        if let id = await matrixStore.createGroupDM(name: groupName, invitees: Array(selectedUsers.keys)) {
                            onOpen(id); dismiss()
                        }
                        openingUserId = nil
                    }
                }.disabled(selectedUsers.count < 2 || groupName.trimmingCharacters(in: .whitespaces).isEmpty || openingUserId != nil)
            }
            if let error = matrixStore.errorMessage {
                Text(error).font(.mood(12)).foregroundStyle(MoodTheme.mentionBadge).padding(LayoutMetrics.mobile(12))
            }
            searchField

            DesktopPixelRule()

            resultsList
        }
        .background(MoodTheme.channelList)
        .onAppear { searchFocused = !ProcessInfo.processInfo.arguments.contains("-uiPreview") }
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

            TextField("Nom d’utilisateur", text: $query)
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
                            if groupMode {
                                if selectedUsers[user.userId] != nil { selectedUsers.removeValue(forKey: user.userId) }
                                else { selectedUsers[user.userId] = user.displayName ?? user.userId }
                            } else { openDM(with: user.userId) }
                        }
                    }
                }
                .padding(8)
            }
        }
    }

    private var emptyStateText: String {
        if query.trimmingCharacters(in: .whitespaces).count < 2 {
            return "Tu peux ajouter des amis avec leur nom d’utilisateur Mood"
        }
        return isSearching ? "Recherche en cours…" : "Personne ne possède ce nom d’utilisateur Mood : \"\(query)\"."
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
            let found = await matrixStore.searchMoodUsername(trimmed)
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
    @Environment(\.layoutMode) private var layoutMode
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

                    if layoutMode == .regular { Text(user.userId)
                        .font(.mood(11))
                        .foregroundStyle(MoodTheme.textMuted)
                        .lineLimit(1) }
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
            .frame(minHeight: layoutMode == .compact ? LayoutMetrics.mobile(44) : nil)
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
            AuthenticatedImage(url: url) { phase in
                if let image = phase.image {
                    image.resizable().scaledToFill()
                } else {
                    initialAvatar
                }
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
