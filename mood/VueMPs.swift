import SwiftUI

// MARK: - DM List Column

struct DMListView: View {
    let conversations: [DMConversation]
    @Binding var selectedDM: DMConversation?
    @Binding var showSettings: Bool
    @State private var showComingSoon = false
    @State private var showQuickSwitcher = false

    var body: some View {
        VStack(spacing: 0) {
            // Barre de recherche
            Button { showQuickSwitcher = true } label: {
                HStack {
                    Image(systemName: "magnifyingglass")
                        .font(.mood(11))
                    Text("Recherche ou lance une conversation")
                        .font(.mood(12))
                    Spacer()
                }
                .foregroundStyle(MoodTheme.textPrimary)
                .padding(.horizontal, 10 * LayoutMetrics.scale)
                .padding(.vertical, 8 * LayoutMetrics.scale)
                .background(MoodTheme.glassBg)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 12 * LayoutMetrics.scale)
            .padding(.vertical, 12 * LayoutMetrics.scale)

            Rectangle().fill(MoodTheme.divider).frame(height: 1)

            ScrollView(showsIndicators: false) {
                VStack(spacing: 2) {
                    SidebarNavItem(icon: "person.2.fill", label: "Amis", isSelected: selectedDM == nil) {
                        selectedDM = nil
                    }

                    SidebarNavItem(icon: "bag.fill", label: "Boutique", isSelected: false) { showComingSoon = true }

                    SidebarNavItem(icon: "flag.fill", label: "Quêtes", isSelected: false) { showComingSoon = true }

                    // Header messages privés
                    HStack {
                        Text("MESSAGES PRIVÉS")
                            .font(.mood(11, weight: .semibold))
                            .tracking(0.4)
                            .foregroundStyle(MoodTheme.textSecondary)

                        Spacer()

                        Button { showComingSoon = true } label: {
                            Image(systemName: "plus")
                                .font(.mood(11))
                                .foregroundStyle(MoodTheme.textPrimary)
                        }
                        .buttonStyle(.plain)
                        .help("Nouveau message")
                    }
                    .padding(.horizontal, 16 * LayoutMetrics.scale)
                    .padding(.top, 16 * LayoutMetrics.scale)
                    .padding(.bottom, 4)

                    ForEach(conversations) { convo in
                        DMRow(
                            conversation: convo,
                            isSelected: selectedDM?.id == convo.id
                        ) {
                            selectedDM = convo
                        }
                    }
                }
            }

            Spacer(minLength: 0)
        }
        .padding(.bottom, LayoutMetrics.channelBottomPadding)
        .background(MoodTheme.channelList)
        .alert("Bientôt disponible", isPresented: $showComingSoon) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Cette fonctionnalité arrive dans une prochaine version de Mood.")
        }
        .sheet(isPresented: $showQuickSwitcher) {
            QuickSwitcher(isPresented: $showQuickSwitcher)
                .presentationDetents([.medium])
        }
    }
}

// MARK: - Sidebar Nav Item

struct SidebarNavItem: View {
    let icon: String
    let label: String
    let isSelected: Bool
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12 * LayoutMetrics.scale) {
                Image(systemName: icon)
                    .font(.mood(15))
                    .frame(width: 20 * LayoutMetrics.scale)

                Text(label)
                    .font(.mood(14, weight: .medium))

                Spacer()
            }
            .foregroundStyle(isSelected ? MoodTheme.textPrimary : MoodTheme.textSecondary)
            .padding(.horizontal, 12 * LayoutMetrics.scale)
            .padding(.vertical, 8 * LayoutMetrics.scale)
            .background(
                isSelected ? MoodTheme.selectedBg :
                isHovered ? MoodTheme.hoverBg :
                Color.clear
            )
            .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
            .padding(.horizontal, 8)
        }
        .buttonStyle(.plain)
        .onHover { hovering in isHovered = hovering }
    }
}

// MARK: - DM Row

struct DMRow: View {
    let conversation: DMConversation
    let isSelected: Bool
    let action: () -> Void
    @State private var isHovered = false
    @State private var isMuted = false
    @State private var showProfile = false
    @State private var showCallAlert = false
    @State private var showClosedFeedback = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12 * LayoutMetrics.scale) {
                // Avatar circle + status
                ZStack(alignment: .bottomTrailing) {
                    Text(conversation.participant.avatarEmoji)
                        .font(.mood(20))
                        .frame(width: 32 * LayoutMetrics.scale, height: 32 * LayoutMetrics.scale)
                        .background(MoodTheme.glassBg)
                        .clipShape(Circle())

                    StatusIndicator(status: conversation.participant.status, size: 10 * LayoutMetrics.scale, borderColor: MoodTheme.channelList)
                        .offset(x: 2, y: 2)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(conversation.participant.displayName)
                        .font(.mood(14, weight: .medium))
                        .foregroundStyle(isSelected || conversation.unreadCount > 0 ? MoodTheme.textPrimary : MoodTheme.textSecondary)

                    Text(conversation.participant.status.rawValue.capitalized)
                        .font(.mood(11))
                        .foregroundStyle(MoodTheme.textMuted)
                }

                Spacer()

                if conversation.unreadCount > 0 {
                    Text("\(conversation.unreadCount)")
                        .font(.mood(10, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6 * LayoutMetrics.scale)
                        .padding(.vertical, 2 * LayoutMetrics.scale)
                        .background(MoodTheme.mentionBadge)
                        .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                }

                if isHovered {
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) { showClosedFeedback = true }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                            withAnimation { showClosedFeedback = false }
                        }
                    } label: {
                        Image(systemName: showClosedFeedback ? "checkmark" : "xmark")
                            .font(.mood(9))
                            .foregroundStyle(MoodTheme.textPrimary)
                    }
                    .buttonStyle(.plain)
                    .help("Fermer la conversation")
                }
            }
            .padding(.horizontal, 10 * LayoutMetrics.scale)
            .padding(.vertical, 8 * LayoutMetrics.scale)
            .background(
                isSelected ? MoodTheme.selectedBg :
                isHovered ? MoodTheme.hoverBg :
                Color.clear
            )
            .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
            .padding(.horizontal, 8)
        }
        .buttonStyle(.plain)
        .onHover { hovering in isHovered = hovering }
        .contextMenu {
            Button { showProfile = true } label: { Label("Voir le profil", systemImage: "person.crop.circle") }
            Button { showCallAlert = true } label: { Label("Appel vocal", systemImage: "phone") }
            Button { showCallAlert = true } label: { Label("Appel vidéo", systemImage: "video") }
            Divider()
            Button { isMuted.toggle() } label: { Label(isMuted ? "Rétablir les notifications" : "Rendre muet", systemImage: isMuted ? "bell" : "bell.slash") }
            Button(role: .destructive) {
                withAnimation(.easeInOut(duration: 0.2)) { showClosedFeedback = true }
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                    withAnimation { showClosedFeedback = false }
                }
            } label: { Label("Fermer la conversation", systemImage: "xmark") }
        }
        .popover(isPresented: $showProfile, arrowEdge: .trailing) {
            UserProfilePopup(user: conversation.participant)
                .adaptiveFrame(width: 320, height: 400, mode: .regular)
        }
        .alert("Appel", isPresented: $showCallAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Les appels seront disponibles dans une prochaine version.")
        }
    }
}

// MARK: - DM Chat Area

struct DMChatArea: View {
    @Environment(MatrixStore.self) private var matrixStore
    @Environment(\.layoutMode) private var layoutMode
    let conversation: DMConversation
    @Binding var showProfilePopup: Bool
    @Binding var profileUser: MoodUser?
    var onBack: (() -> Void)?
    @State private var messageText = ""
    @State private var activeCall: CallType?
    @State private var showPinnedMessages = false
    @State private var showSearch = false
    @State private var showInlineProfile = false

    private var messages: [ChatMessage] {
        let storeMessages = matrixStore.messages(forDM: conversation)
        return storeMessages.isEmpty ? MockData.dmMessages(for: conversation) : storeMessages
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header DM — masqué sur compact (NavigationStack fournit le titre)
            if layoutMode == .regular {
                HStack(spacing: 10 * LayoutMetrics.scale) {
                    Button { onBack?() } label: {
                        Image(systemName: "chevron.left")
                            .font(.mood(16, weight: .medium))
                            .foregroundStyle(MoodTheme.textPrimary)
                            .frame(width: 30 * LayoutMetrics.scale, height: 30 * LayoutMetrics.scale)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help("Retour aux amis")

                    Text(conversation.participant.avatarEmoji)
                        .font(.mood(14))
                        .frame(width: 28 * LayoutMetrics.scale, height: 28 * LayoutMetrics.scale)
                        .background(MoodTheme.glassBg)
                        .clipShape(Circle())

                    Text(conversation.participant.displayName)
                        .font(.mood(15, weight: .bold))
                        .foregroundStyle(MoodTheme.textPrimary)

                    HStack(spacing: 3) {
                        Image(systemName: "lock.fill")
                            .font(.mood(8))
                        Text("E2E")
                            .font(.mood(10, weight: .semibold))
                    }
                    .foregroundStyle(MoodTheme.onlineGreen)
                    .padding(.horizontal, 8 * LayoutMetrics.scale)
                    .padding(.vertical, 3 * LayoutMetrics.scale)
                    .background(MoodTheme.onlineGreen.opacity(0.10))
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))

                    Spacer()

                    HStack(spacing: 6 * LayoutMetrics.scale) {
                        HeaderButton(icon: "phone") {
                            activeCall = .voice
                        }
                        .help("Appel vocal")
                        HeaderButton(icon: "video") {
                            activeCall = .video
                        }
                        .help("Appel vidéo")
                        HeaderButton(icon: "pin") {
                            withAnimation(.easeInOut(duration: 0.15)) {
                                showPinnedMessages.toggle()
                                showSearch = false
                            }
                        }
                        .help("Messages épinglés")

                        Button {
                            showInlineProfile.toggle()
                        } label: {
                            Image(systemName: "person.crop.circle")
                                .font(.mood(16))
                                .foregroundStyle(MoodTheme.textPrimary)
                                .frame(width: 30 * LayoutMetrics.scale, height: 30 * LayoutMetrics.scale)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .popover(isPresented: $showInlineProfile, arrowEdge: .top) {
                            UserProfilePopup(user: conversation.participant)
                                .adaptiveFrame(width: 320, height: 400, mode: layoutMode)
                        }

                        HeaderButton(icon: "magnifyingglass") {
                            withAnimation(.easeInOut(duration: 0.15)) {
                                showSearch.toggle()
                                showPinnedMessages = false
                            }
                        }
                        .help("Rechercher")
                    }
                }
                .padding(.horizontal, 16 * LayoutMetrics.scale)
                .padding(.vertical, 10 * LayoutMetrics.scale)

                Rectangle().fill(MoodTheme.divider).frame(height: 1)
            }

            // Search panel
            if showSearch {
                SearchPanel(showSearch: $showSearch)
            }

            // Pinned messages panel
            if showPinnedMessages {
                PinnedMessagesPanel(
                    messages: messages.filter { $0.isPinned },
                    server: nil,
                    showPanel: $showPinnedMessages
                )
            }

            // Messages
            ScrollView {
                ScrollViewReader { proxy in
                    LazyVStack(spacing: 0) {
                        VStack(spacing: 10 * LayoutMetrics.scale) {
                            Text(conversation.participant.avatarEmoji)
                                .font(.mood(50))
                                .frame(width: 80 * LayoutMetrics.scale, height: 80 * LayoutMetrics.scale)
                                .background(MoodTheme.glassBg)
                                .clipShape(Circle())

                            Text(conversation.participant.displayName)
                                .font(.mood(20, weight: .bold))
                                .foregroundStyle(MoodTheme.textPrimary)

                            Text("@\(conversation.participant.username)")
                                .font(.mood(13))
                                .foregroundStyle(MoodTheme.textSecondary)

                            HStack(spacing: 4) {
                                Image(systemName: "lock.fill")
                                    .font(.mood(9))
                                Text("Conversation chiffrée de bout en bout")
                                    .font(.mood(12))
                            }
                            .foregroundStyle(MoodTheme.onlineGreen)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 28 * LayoutMetrics.scale)

                        Rectangle()
                            .fill(MoodTheme.divider)
                            .frame(height: 1)
                            .padding(.horizontal, 16)
                            .padding(.bottom, 6)

                        ForEach(messages) { message in
                            MessageRow(message: message, server: nil) {
                                profileUser = message.sender
                                showProfilePopup = true
                            }
                            .id(message.id)
                        }
                    }
                    .onAppear {
                        if let lastID = messages.last?.id {
                            proxy.scrollTo(lastID, anchor: .bottom)
                        }
                    }
                }
            }
            .scrollDismissesKeyboard(.interactively)

            MessageInputBar(
                text: $messageText,
                channelName: conversation.participant.displayName,
                isE2E: true,
                onSend: {
                    let trimmed = messageText.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !trimmed.isEmpty else { return }
                    let text = trimmed
                    messageText = ""
                    Task {
                        if let roomId = matrixStore.roomId(for: conversation) {
                            await matrixStore.sendMessage(roomId: roomId, text: text)
                        }
                    }
                }
            )
        }
        .background(MoodTheme.chatBackground)
        .overlay {
            if let call = activeCall {
                Group {
                    switch call {
                    case .voice:
                        VoiceCallView(participant: conversation.participant) {
                            withAnimation(.easeInOut(duration: 0.2)) { activeCall = nil }
                        }
                    case .video:
                        VideoCallView(participant: conversation.participant) {
                            withAnimation(.easeInOut(duration: 0.2)) { activeCall = nil }
                        }
                    case .screenShare:
                        ScreenShareView(participant: conversation.participant) {
                            withAnimation(.easeInOut(duration: 0.2)) { activeCall = nil }
                        }
                    }
                }
                .transition(.opacity.combined(with: .scale(scale: 0.95)))
            }
        }
    }
}

#Preview {
    DMListView(
        conversations: MockData.dmConversations,
        selectedDM: .constant(nil),
        showSettings: .constant(false)
    )
    .frame(width: 240, height: 700)
    .environment(MatrixStore())
    .preferredColorScheme(.dark)
}
