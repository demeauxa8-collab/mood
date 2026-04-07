import SwiftUI
import UIKit

// MARK: - Chat Area

struct ChatArea: View {
    @Environment(MatrixStore.self) private var matrixStore
    @Environment(\.layoutMode) private var layoutMode
    let channel: Channel
    let server: MoodServer
    @Binding var showProfilePopup: Bool
    @Binding var profileUser: MoodUser?
    @State private var messageText = ""
    @State private var showMemberList = false
    @State private var showSearch = false
    @State private var showPinnedMessages = false
    @State private var showThreadPanel = false
    @State private var activeThread: ChatMessage?
    @State private var replyingTo: ChatMessage?

    private var messages: [ChatMessage] {
        let storeMessages = matrixStore.messages(for: channel)
        return storeMessages.isEmpty ? MockData.messages(for: channel) : storeMessages
    }

    var body: some View {
        if channel.type == .voice {
            VoiceChannelLobby(channel: channel, server: server)
        } else {
            textChannelContent
        }
    }

    @ViewBuilder
    private var textChannelContent: some View {
        VStack(spacing: 0) {
            // Masquer ChannelHeader sur compact (NavigationStack fournit le titre)
            if layoutMode == .regular {
                ChannelHeader(
                    channel: channel,
                    showMemberList: $showMemberList,
                    showSearch: $showSearch,
                    showPinnedMessages: $showPinnedMessages
                )

                Rectangle().fill(MoodTheme.divider).frame(height: 1)
            }

            HStack(spacing: 0) {
                VStack(spacing: 0) {
                    // Search panel
                    if showSearch {
                        SearchPanel(showSearch: $showSearch)
                    }

                    // Pinned messages panel
                    if showPinnedMessages {
                        PinnedMessagesPanel(
                            messages: messages.filter { $0.isPinned },
                            server: server,
                            showPanel: $showPinnedMessages
                        )
                    }

                    MessageList(
                        messages: messages,
                        channel: channel,
                        server: server,
                        showProfilePopup: $showProfilePopup,
                        profileUser: $profileUser,
                        replyingTo: $replyingTo,
                        activeThread: $activeThread,
                        showThreadPanel: $showThreadPanel
                    )

                    MessageInputBar(
                        text: $messageText,
                        channelName: channel.name,
                        isE2E: channel.isE2E,
                        replyingTo: $replyingTo,
                        onSend: {
                            let trimmed = messageText.trimmingCharacters(in: .whitespacesAndNewlines)
                            guard !trimmed.isEmpty else { return }
                            let text = trimmed
                            messageText = ""
                            Task {
                                if let roomId = matrixStore.roomId(for: channel) {
                                    await matrixStore.sendMessage(roomId: roomId, text: text)
                                }
                            }
                        }
                    )
                }

                // Panels inline sur desktop uniquement
                if layoutMode == .regular {
                    if showThreadPanel, let thread = activeThread {
                        Rectangle().fill(MoodTheme.divider).frame(width: 1)

                        ThreadPanel(
                            message: thread,
                            server: server,
                            showPanel: $showThreadPanel
                        )
                        .frame(width: LayoutMetrics.threadPanelWidth)
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                    } else if showMemberList {
                        Rectangle().fill(MoodTheme.divider).frame(width: 1)

                        MemberListPanel(
                            members: server.members,
                            server: server,
                            showProfilePopup: $showProfilePopup,
                            profileUser: $profileUser
                        )
                        .frame(width: LayoutMetrics.memberListWidth)
                    }
                }
            }
        }
        .background(MoodTheme.chatBackground)
        // Sheets pour les panels sur compact
        .sheet(isPresented: Binding(
            get: { layoutMode == .compact && showThreadPanel && activeThread != nil },
            set: { if !$0 { showThreadPanel = false } }
        )) {
            if let thread = activeThread {
                NavigationStack {
                    ThreadPanel(
                        message: thread,
                        server: server,
                        showPanel: $showThreadPanel
                    )
                    .navigationTitle("Fil de discussion")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button("Fermer") { showThreadPanel = false }
                        }
                    }
                }
                .presentationDetents([.medium, .large])
            }
        }
        .sheet(isPresented: Binding(
            get: { layoutMode == .compact && showMemberList },
            set: { if !$0 { showMemberList = false } }
        )) {
            NavigationStack {
                MemberListPanel(
                    members: server.members,
                    server: server,
                    showProfilePopup: $showProfilePopup,
                    profileUser: $profileUser
                )
                .navigationTitle("Membres")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Fermer") { showMemberList = false }
                    }
                }
            }
            .presentationDetents([.medium, .large])
        }
    }
}

// MARK: - Channel Header

struct ChannelHeader: View {
    let channel: Channel
    @Binding var showMemberList: Bool
    @Binding var showSearch: Bool
    @Binding var showPinnedMessages: Bool
    @State private var showNotifAlert = false

    var body: some View {
        HStack(spacing: 10 * LayoutMetrics.scale) {
            Image(systemName: channel.icon)
                .font(.mood(16))
                .foregroundStyle(MoodTheme.textPrimary)

            Text(channel.name)
                .font(.mood(15, weight: .bold))
                .foregroundStyle(MoodTheme.textPrimary)

            if channel.isE2E {
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
            }

            if !channel.topic.isEmpty {
                Rectangle().fill(MoodTheme.divider).frame(width: 1, height: 16 * LayoutMetrics.scale)

                Text(channel.topic)
                    .font(.mood(13))
                    .foregroundStyle(MoodTheme.textMuted)
                    .lineLimit(1)
            }

            Spacer()

            HStack(spacing: 6 * LayoutMetrics.scale) {
                HeaderButton(icon: "bell") { showNotifAlert = true }
                    .help("Paramètres de notification")
                    .alert("Notifications", isPresented: $showNotifAlert) {
                        Button("OK", role: .cancel) {}
                    } message: {
                        Text("Les paramètres de notification seront disponibles dans une prochaine version.")
                    }

                Button {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        showPinnedMessages.toggle()
                    }
                } label: {
                    Image(systemName: "pin")
                        .font(.mood(16))
                        .foregroundStyle(MoodTheme.textPrimary)
                        .frame(width: 30 * LayoutMetrics.scale, height: 30 * LayoutMetrics.scale)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Messages épinglés")

                Button {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        showMemberList.toggle()
                    }
                } label: {
                    Image(systemName: "person.2")
                        .font(.mood(16))
                        .foregroundStyle(MoodTheme.textPrimary)
                        .frame(width: 30 * LayoutMetrics.scale, height: 30 * LayoutMetrics.scale)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Liste des membres")

                // Recherche
                Button {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        showSearch.toggle()
                    }
                } label: {
                    Image(systemName: "magnifyingglass")
                        .font(.mood(16))
                        .foregroundStyle(MoodTheme.textPrimary)
                        .frame(width: 30 * LayoutMetrics.scale, height: 30 * LayoutMetrics.scale)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Rechercher")
            }
        }
        .padding(.horizontal, 16 * LayoutMetrics.scale)
        .padding(.vertical, 10 * LayoutMetrics.scale)
        .background(MoodTheme.chatBackground)
    }
}

struct HeaderButton: View {
    let icon: String
    var action: () -> Void = {}

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.mood(16))
                .foregroundStyle(MoodTheme.textPrimary)
                .frame(width: 30 * LayoutMetrics.scale, height: 30 * LayoutMetrics.scale)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Message List

struct MessageList: View {
    let messages: [ChatMessage]
    let channel: Channel
    let server: MoodServer
    @Binding var showProfilePopup: Bool
    @Binding var profileUser: MoodUser?
    @Binding var replyingTo: ChatMessage?
    @Binding var activeThread: ChatMessage?
    @Binding var showThreadPanel: Bool
    @State private var isAtBottom = true

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            ScrollView {
                ScrollViewReader { proxy in
                    LazyVStack(spacing: 0) {
                        // Welcome
                        VStack(alignment: .leading, spacing: 10 * LayoutMetrics.scale) {
                            ZStack {
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .fill(MoodTheme.brandAccent.opacity(0.12))
                                    .frame(width: 56 * LayoutMetrics.scale, height: 56 * LayoutMetrics.scale)
                                Image(systemName: channel.icon)
                                    .font(.mood(26))
                                    .foregroundStyle(MoodTheme.brandAccent)
                            }

                            Text("Bienvenue dans #\(channel.name)")
                                .font(.mood(22, weight: .bold))
                                .foregroundStyle(MoodTheme.textPrimary)

                            HStack(spacing: 6) {
                                Text("C'est le début du channel.")
                                    .foregroundStyle(MoodTheme.textSecondary)
                                if channel.isE2E {
                                    HStack(spacing: 3) {
                                        Image(systemName: "lock.fill")
                                            .font(.mood(9))
                                        Text("Chiffrement E2E")
                                    }
                                    .foregroundStyle(MoodTheme.onlineGreen)
                                }
                            }
                            .font(.mood(13))
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 16 * LayoutMetrics.scale)
                        .padding(.top, 24 * LayoutMetrics.scale)
                        .padding(.bottom, 16 * LayoutMetrics.scale)

                        Rectangle()
                            .fill(MoodTheme.divider)
                            .frame(height: 1)
                            .padding(.horizontal, 16)
                            .padding(.bottom, 6)

                        ForEach(Array(messages.enumerated()), id: \.element.id) { index, message in
                            // Date separator
                            if index == 0 || !Calendar.current.isDate(message.timestamp, inSameDayAs: messages[index - 1].timestamp) {
                                DateSeparator(date: message.timestamp)
                            }

                            // Séparateur NOUVEAU (avant les 3 derniers messages)
                            if index == messages.count - 3 {
                                NewMessagesSeparator()
                            }

                            if message.isSystemMessage {
                                SystemMessageRow(message: message)
                                    .id(message.id)
                            } else {
                                MessageRow(message: message, server: server, onReply: {
                                    replyingTo = message
                                }, onThread: {
                                    activeThread = message
                                    withAnimation(.easeInOut(duration: 0.2)) {
                                        showThreadPanel = true
                                    }
                                }) {
                                    profileUser = message.sender
                                    showProfilePopup = true
                                }
                                .id(message.id)
                            }
                        }

                        // Anchor at bottom
                        Color.clear.frame(height: 1).id("bottom")
                    }
                    .onAppear {
                        proxy.scrollTo("bottom", anchor: .bottom)
                    }
                }
            }
            .scrollDismissesKeyboard(.interactively)

            // Scroll to bottom button
            if !isAtBottom {
                Button {
                    isAtBottom = true
                } label: {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(MoodTheme.textPrimary)
                        .frame(width: 36, height: 36)
                        .background(MoodTheme.channelList)
                        .clipShape(Circle())
                        .overlay(Circle().stroke(MoodTheme.glassBorder, lineWidth: 0.5))
                        .shadow(color: .black.opacity(0.3), radius: 4, y: 2)
                }
                .buttonStyle(.plain)
                .padding(16)
                .transition(.scale.combined(with: .opacity))
                .help("Aller en bas")
            }
        }
    }
}

// MARK: - Message Row

struct MessageRow: View {
    let message: ChatMessage
    let server: MoodServer?
    var onReply: (() -> Void)?
    var onThread: (() -> Void)?
    let onAvatarTap: () -> Void
    @State private var isHovered = false
    @State private var showReactionPicker = false
    @State private var copiedMessage = false
    @State private var showPinnedFeedback = false
    @State private var showEllipsisMenu = false
    @State private var showDeleteConfirm = false
    @State private var showMarkedUnread = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Reply reference
            if let reply = message.replyTo {
                HStack(spacing: 6 * LayoutMetrics.scale) {
                    RoundedRectangle(cornerRadius: 1)
                        .fill(MoodTheme.textMuted.opacity(0.4))
                        .frame(width: 2, height: 12 * LayoutMetrics.scale)
                        .padding(.leading, 52 * LayoutMetrics.scale)

                    Text(reply.sender.avatarEmoji)
                        .font(.mood(9))
                        .frame(width: 16 * LayoutMetrics.scale, height: 16 * LayoutMetrics.scale)
                        .background(MoodTheme.glassBg)
                        .clipShape(Circle())

                    Text(reply.sender.displayName)
                        .font(.mood(12, weight: .semibold))
                        .foregroundStyle(reply.sender.roleColor)

                    Text(reply.content)
                        .font(.mood(12))
                        .foregroundStyle(MoodTheme.textMuted)
                        .lineLimit(1)
                }
                .padding(.bottom, 4)
            }

            HStack(alignment: .top, spacing: 14 * LayoutMetrics.scale) {
                if message.isGrouped {
                    Text(message.timestamp.timeFormatted)
                        .font(.mood(10))
                        .foregroundStyle(MoodTheme.textMuted)
                        .frame(width: 38 * LayoutMetrics.scale, alignment: .center)
                        .opacity(isHovered ? 1 : 0)
                } else {
                    Button(action: onAvatarTap) {
                        Text(message.sender.avatarEmoji)
                            .font(.mood(20))
                            .frame(width: 40 * LayoutMetrics.scale, height: 40 * LayoutMetrics.scale)
                            .background(MoodTheme.glassBg)
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                }

                VStack(alignment: .leading, spacing: 4) {
                    if !message.isGrouped {
                        HStack(spacing: 8 * LayoutMetrics.scale) {
                            Button(action: onAvatarTap) {
                                HStack(spacing: 4) {
                                    Text(message.sender.displayName)
                                        .font(.mood(14, weight: .semibold))
                                        .foregroundStyle(message.sender.roleColor)
                                    RoleBadge(role: server?.roleFor(message.sender) ?? .member, size: 12 * LayoutMetrics.scale)
                                }
                            }
                            .buttonStyle(.plain)

                            Text(message.timestamp.messageTimestamp)
                                .font(.mood(11))
                                .foregroundStyle(MoodTheme.textMuted)

                            if message.isPinned {
                                Image(systemName: "pin.fill")
                                    .font(.mood(9))
                                    .foregroundStyle(MoodTheme.textMuted.opacity(0.5))
                            }
                        }
                    }

                    HStack(spacing: 0) {
                        MarkdownText(text: message.content)
                            .font(.mood(14))
                            .foregroundStyle(MoodTheme.textPrimary)
                            .textSelection(.enabled)

                        if message.isEdited {
                            Text(" (modifié)")
                                .font(.mood(11))
                                .foregroundStyle(MoodTheme.textMuted)
                        }
                    }

                    // Attachments
                    ForEach(message.attachments) { att in
                        if att.type == .image {
                            HStack(spacing: 8) {
                                Text(att.previewEmoji)
                                    .font(.mood(28))
                                    .frame(width: 200 * LayoutMetrics.scale, height: 120 * LayoutMetrics.scale)
                                    .background(MoodTheme.glassBg)
                                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                                            .stroke(MoodTheme.glassBorder, lineWidth: 0.5)
                                    )
                            }
                        } else {
                            HStack(spacing: 8) {
                                Image(systemName: "doc.fill")
                                    .font(.mood(16))
                                    .foregroundStyle(MoodTheme.brandAccent)
                                Text(att.name)
                                    .font(.mood(13))
                                    .foregroundStyle(MoodTheme.brandBlue)
                                    .underline()
                                Image(systemName: "arrow.down.circle")
                                    .font(.mood(13))
                                    .foregroundStyle(MoodTheme.textMuted)
                            }
                            .padding(10 * LayoutMetrics.scale)
                            .background(MoodTheme.glassBg)
                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .stroke(MoodTheme.glassBorder, lineWidth: 0.5)
                            )
                        }
                    }

                    // Link embed
                    if let embed = message.linkEmbed {
                        HStack(spacing: 0) {
                            RoundedRectangle(cornerRadius: 2)
                                .fill(embed.color)
                                .frame(width: 4)

                            VStack(alignment: .leading, spacing: 4) {
                                Text(embed.siteName)
                                    .font(.mood(11))
                                    .foregroundStyle(MoodTheme.textSecondary)

                                Text(embed.title)
                                    .font(.mood(13, weight: .semibold))
                                    .foregroundStyle(MoodTheme.brandBlue)

                                Text(embed.description)
                                    .font(.mood(12))
                                    .foregroundStyle(MoodTheme.textSecondary)
                                    .lineLimit(2)

                                if let emoji = embed.imageEmoji {
                                    Text(emoji)
                                        .font(.mood(22))
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .frame(height: 60 * LayoutMetrics.scale)
                                        .background(MoodTheme.glassBg)
                                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                                }
                            }
                            .padding(10 * LayoutMetrics.scale)
                        }
                        .frame(maxWidth: 400 * LayoutMetrics.scale, alignment: .leading)
                        .background(MoodTheme.glassBg)
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .stroke(MoodTheme.glassBorder, lineWidth: 0.5)
                        )
                        .padding(.top, 4)
                    }

                    // Thread indicator
                    if let thread = message.threadInfo {
                        Button { onThread?() } label: {
                            HStack(spacing: 6 * LayoutMetrics.scale) {
                                Text(thread.lastReplier.avatarEmoji)
                                    .font(.mood(10))
                                    .frame(width: 20 * LayoutMetrics.scale, height: 20 * LayoutMetrics.scale)
                                    .background(MoodTheme.glassBg)
                                    .clipShape(Circle())

                                Text("\(thread.replyCount) réponses")
                                    .font(.mood(12, weight: .semibold))
                                    .foregroundStyle(MoodTheme.brandBlue)

                                Text(thread.lastReplyDate.relativeFormatted)
                                    .font(.mood(11))
                                    .foregroundStyle(MoodTheme.textMuted)

                                Image(systemName: "chevron.right")
                                    .font(.mood(9, weight: .semibold))
                                    .foregroundStyle(MoodTheme.textMuted)
                            }
                            .padding(.horizontal, 8 * LayoutMetrics.scale)
                            .padding(.vertical, 5 * LayoutMetrics.scale)
                            .background(MoodTheme.glassBg.opacity(0.6))
                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        }
                        .buttonStyle(.plain)
                        .padding(.top, 4)
                    }

                    // Reactions
                    if !message.reactions.isEmpty {
                        HStack(spacing: 4 * LayoutMetrics.scale) {
                            ForEach(message.reactions) { reaction in
                                HStack(spacing: 4 * LayoutMetrics.scale) {
                                    Text(reaction.emoji)
                                        .font(.mood(13))
                                    Text("\(reaction.count)")
                                        .font(.mood(12, weight: .medium))
                                        .foregroundStyle(reaction.hasReacted ? MoodTheme.brandAccent : MoodTheme.textSecondary)
                                }
                                .padding(.horizontal, 8 * LayoutMetrics.scale)
                                .padding(.vertical, 4 * LayoutMetrics.scale)
                                .background(reaction.hasReacted ? MoodTheme.brandAccent.opacity(0.15) : MoodTheme.glassBg)
                                .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                                        .stroke(reaction.hasReacted ? MoodTheme.brandAccent.opacity(0.4) : MoodTheme.glassBorder, lineWidth: 0.5)
                                )
                            }

                            // Bouton ajouter réaction
                            Button { showReactionPicker = true } label: {
                                Image(systemName: "plus")
                                    .font(.mood(10))
                                    .foregroundStyle(MoodTheme.textPrimary)
                                    .frame(width: 26 * LayoutMetrics.scale, height: 26 * LayoutMetrics.scale)
                                    .background(MoodTheme.glassBg)
                                    .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                                            .stroke(MoodTheme.glassBorder, lineWidth: 0.5)
                                    )
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.top, 2)
                    }
                }

                Spacer()

                // Actions hover
                if isHovered {
                    HStack(spacing: 1) {
                        ActionButton(icon: "face.smiling", action: { showReactionPicker = true })
                            .help("Ajouter une réaction")
                            .popover(isPresented: $showReactionPicker, arrowEdge: .top) {
                                EmojiPicker(isPresented: $showReactionPicker) { emoji in
                                    showReactionPicker = false
                                }
                            }
                        ActionButton(icon: "arrowshape.turn.up.left", action: { onReply?() })
                            .help("Répondre")
                        ActionButton(icon: "text.bubble", action: { onThread?() })
                            .help("Créer un fil")
                        ActionButton(icon: showPinnedFeedback ? "pin.fill" : "pin", action: {
                            withAnimation(.easeInOut(duration: 0.2)) { showPinnedFeedback = true }
                            DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                                withAnimation { showPinnedFeedback = false }
                            }
                        })
                            .help(message.isPinned ? "Désépingler" : "Épingler")
                        ActionButton(icon: "ellipsis", action: { showEllipsisMenu = true })
                            .help("Plus")
                            .popover(isPresented: $showEllipsisMenu, arrowEdge: .top) {
                                VStack(spacing: 2) {
                                    Button {
                                        showEllipsisMenu = false
                                        UIPasteboard.general.string = message.content
                                        copiedMessage = true
                                        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { copiedMessage = false }
                                    } label: {
                                        Label("Copier le texte", systemImage: "doc.on.doc")
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                    }
                                    .buttonStyle(.plain)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 6)

                                    Button {
                                        showEllipsisMenu = false
                                        UIPasteboard.general.string = "mood://message/\(message.id.uuidString)"
                                    } label: {
                                        Label("Copier le lien", systemImage: "link")
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                    }
                                    .buttonStyle(.plain)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 6)

                                    Divider()

                                    Button {
                                        showEllipsisMenu = false
                                        showDeleteConfirm = true
                                    } label: {
                                        Label("Supprimer", systemImage: "trash")
                                            .foregroundStyle(.red)
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                    }
                                    .buttonStyle(.plain)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 6)
                                }
                                .padding(.vertical, 6)
                                .frame(width: 200 * LayoutMetrics.scale)
                                .font(.mood(13))
                                .foregroundStyle(MoodTheme.textPrimary)
                            }
                    }
                    .padding(3)
                    .background(MoodTheme.channelList)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(MoodTheme.glassBorder, lineWidth: 0.5)
                    )
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, message.isGrouped ? 1 : 5)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(isHovered ? MoodTheme.messageHover : Color.clear)
        )
        .padding(.horizontal, 4)
        .onHover { hovering in isHovered = hovering }
        .contextMenu {
            Button { onReply?() } label: { Label("Répondre", systemImage: "arrowshape.turn.up.left") }
            Button { onThread?() } label: { Label("Créer un fil", systemImage: "text.bubble") }
            Button { showReactionPicker = true } label: { Label("Ajouter une réaction", systemImage: "face.smiling") }
            Button {
                withAnimation(.easeInOut(duration: 0.2)) { showPinnedFeedback = true }
                DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                    withAnimation { showPinnedFeedback = false }
                }
            } label: { Label(message.isPinned ? "Désépingler" : "Épingler le message", systemImage: message.isPinned ? "pin.slash" : "pin") }
            Divider()
            Button {
                withAnimation(.easeInOut(duration: 0.2)) { showMarkedUnread = true }
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                    withAnimation { showMarkedUnread = false }
                }
            } label: { Label("Marquer comme non lu", systemImage: "circle.fill") }
            Button {
                UIPasteboard.general.string = message.content
                copiedMessage = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) { copiedMessage = false }
            } label: { Label("Copier le texte", systemImage: "doc.on.doc") }
            Button {
                UIPasteboard.general.string = "mood://message/\(message.id.uuidString)"
            } label: { Label("Copier le lien du message", systemImage: "link") }
            Divider()
            Button(role: .destructive) { showDeleteConfirm = true } label: { Label("Supprimer le message", systemImage: "trash") }
        }
        .alert("Supprimer le message", isPresented: $showDeleteConfirm) {
            Button("Annuler", role: .cancel) {}
            Button("Supprimer", role: .destructive) {}
        } message: {
            Text("Es-tu sûr de vouloir supprimer ce message ? Cette action est irréversible.")
        }
    }
}

struct ActionButton: View {
    let icon: String
    var action: (() -> Void)?

    var body: some View {
        Button { action?() } label: {
            Image(systemName: icon)
                .font(.mood(14))
                .foregroundStyle(MoodTheme.textPrimary)
                .frame(width: 28 * LayoutMetrics.scale, height: 28 * LayoutMetrics.scale)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Member List Panel

struct MemberListPanel: View {
    let members: [MoodUser]
    let server: MoodServer
    @Binding var showProfilePopup: Bool
    @Binding var profileUser: MoodUser?

    // Group by server role hierarchy
    private var ownerMembers: [MoodUser] {
        members.filter { server.roleFor($0) == .owner && $0.status != .offline }
    }

    private var adminMembers: [MoodUser] {
        members.filter { server.roleFor($0) == .admin && $0.status != .offline }
    }

    private var modMembers: [MoodUser] {
        members.filter { server.roleFor($0) == .moderator && $0.status != .offline }
    }

    private var onlineMembers: [MoodUser] {
        members.filter { server.roleFor($0) == .member && $0.status != .offline }
    }

    private var offlineMembers: [MoodUser] {
        members.filter { $0.status == .offline }
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 2) {
                if !ownerMembers.isEmpty {
                    MemberSection(title: "PROPRIÉTAIRE — \(ownerMembers.count)", members: ownerMembers, server: server) { user in
                        profileUser = user
                        showProfilePopup = true
                    }
                }

                if !adminMembers.isEmpty {
                    MemberSection(title: "ADMIN — \(adminMembers.count)", members: adminMembers, server: server) { user in
                        profileUser = user
                        showProfilePopup = true
                    }
                }

                if !modMembers.isEmpty {
                    MemberSection(title: "MODÉRATEUR — \(modMembers.count)", members: modMembers, server: server) { user in
                        profileUser = user
                        showProfilePopup = true
                    }
                }

                if !onlineMembers.isEmpty {
                    MemberSection(title: "EN LIGNE — \(onlineMembers.count)", members: onlineMembers, server: server) { user in
                        profileUser = user
                        showProfilePopup = true
                    }
                }

                if !offlineMembers.isEmpty {
                    MemberSection(title: "HORS LIGNE — \(offlineMembers.count)", members: offlineMembers, server: server) { user in
                        profileUser = user
                        showProfilePopup = true
                    }
                }
            }
            .padding(.top, 16 * LayoutMetrics.scale)
            .padding(.bottom, 12 * LayoutMetrics.scale)
        }
        .background(MoodTheme.memberList)
    }
}

struct MemberSection: View {
    let title: String
    let members: [MoodUser]
    let server: MoodServer
    let onTap: (MoodUser) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.mood(11, weight: .semibold))
                .tracking(0.4)
                .foregroundStyle(MoodTheme.textSecondary)
                .padding(.horizontal, 16 * LayoutMetrics.scale)
                .padding(.top, 16 * LayoutMetrics.scale)
                .padding(.bottom, 4)

            ForEach(members) { member in
                MemberRow(member: member, role: server.roleFor(member), onTap: { onTap(member) })
            }
        }
    }
}

struct MemberRow: View {
    let member: MoodUser
    let role: ServerRole
    let onTap: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 10 * LayoutMetrics.scale) {
                ZStack(alignment: .bottomTrailing) {
                    Text(member.avatarEmoji)
                        .font(.mood(14))
                        .frame(width: 32 * LayoutMetrics.scale, height: 32 * LayoutMetrics.scale)
                        .background(MoodTheme.glassBg)
                        .clipShape(Circle())
                        .opacity(member.status == .offline ? 0.4 : 1)

                    StatusIndicator(status: member.status, size: 8 * LayoutMetrics.scale, borderColor: MoodTheme.memberList)
                        .offset(x: 2, y: 2)
                }

                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 4) {
                        Text(member.displayName)
                            .font(.mood(13))
                            .foregroundStyle(member.status == .offline ? MoodTheme.textMuted : member.roleColor)
                        RoleBadge(role: role, size: 11 * LayoutMetrics.scale)
                    }

                    if let activity = member.activity {
                        Text("\(activity.type.rawValue) \(activity.name)")
                            .font(.mood(11))
                            .foregroundStyle(MoodTheme.textMuted)
                            .lineLimit(1)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 10 * LayoutMetrics.scale)
            .padding(.vertical, 5 * LayoutMetrics.scale)
            .background(isHovered ? MoodTheme.hoverBg : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
            .padding(.horizontal, 8)
        }
        .buttonStyle(.plain)
        .onHover { hovering in isHovered = hovering }
    }
}

// MARK: - Search Panel

struct SearchPanel: View {
    @Binding var showSearch: Bool
    @State private var searchText = ""

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8 * LayoutMetrics.scale) {
                Image(systemName: "magnifyingglass")
                    .font(.mood(13))
                    .foregroundStyle(MoodTheme.textMuted)

                TextField("Rechercher dans ce channel...", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(.mood(13))
                    .foregroundStyle(MoodTheme.textPrimary)

                Button {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        showSearch = false
                    }
                } label: {
                    Image(systemName: "xmark")
                        .font(.mood(11))
                        .foregroundStyle(MoodTheme.textPrimary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 12 * LayoutMetrics.scale)
            .padding(.vertical, 8 * LayoutMetrics.scale)
            .background(MoodTheme.glassBg)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(MoodTheme.glassBorder, lineWidth: 0.5)
            )

            // Filter chips
            HStack(spacing: 6) {
                SearchFilterChip(label: "de:", icon: "person")
                SearchFilterChip(label: "contient:", icon: "photo")
                SearchFilterChip(label: "avant:", icon: "calendar")
                SearchFilterChip(label: "après:", icon: "calendar")
                Spacer()
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(MoodTheme.chatBackground)
        .overlay(
            Rectangle().fill(MoodTheme.divider).frame(height: 1), alignment: .bottom
        )
    }
}

struct SearchFilterChip: View {
    let label: String
    let icon: String
    @State private var isHovered = false
    @State private var isActive = false

    var body: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.15)) { isActive.toggle() }
        } label: {
            HStack(spacing: 4 * LayoutMetrics.scale) {
                Image(systemName: icon)
                    .font(.mood(10))
                Text(label)
                    .font(.mood(11))
            }
            .foregroundStyle(isActive ? MoodTheme.brandAccent : MoodTheme.textSecondary)
            .padding(.horizontal, 8 * LayoutMetrics.scale)
            .padding(.vertical, 4 * LayoutMetrics.scale)
            .background(isActive ? MoodTheme.brandAccent.opacity(0.15) : (isHovered ? MoodTheme.hoverBg : MoodTheme.glassBg))
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(isActive ? MoodTheme.brandAccent.opacity(0.4) : Color.clear, lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering in isHovered = hovering }
    }
}

// MARK: - Markdown Text Renderer

struct MarkdownText: View {
    let text: String

    var body: some View {
        Text(parseMarkdown(text))
    }

    private func parseMarkdown(_ input: String) -> AttributedString {
        var result = AttributedString()
        var remaining = input[input.startIndex...]

        while !remaining.isEmpty {
            // Code block inline `code`
            if remaining.hasPrefix("`"), let end = remaining.dropFirst().firstIndex(of: "`") {
                let code = remaining[remaining.index(after: remaining.startIndex)...remaining.index(before: end)]
                var attr = AttributedString(" \(code) ")
                attr.font = .system(size: 13 * LayoutMetrics.scale, design: .monospaced)
                attr.foregroundColor = MoodTheme.textSecondary
                result += attr
                remaining = remaining[remaining.index(after: end)...]
            }
            // Bold **text**
            else if remaining.hasPrefix("**"), let end = remaining.dropFirst(2).range(of: "**") {
                let bold = remaining[remaining.index(remaining.startIndex, offsetBy: 2)..<end.lowerBound]
                var attr = AttributedString(String(bold))
                attr.font = .system(size: 14 * LayoutMetrics.scale, weight: .bold)
                result += attr
                remaining = remaining[end.upperBound...]
            }
            // Italic *text*
            else if remaining.hasPrefix("*"), let end = remaining.dropFirst().firstIndex(of: "*") {
                let italic = remaining[remaining.index(after: remaining.startIndex)..<end]
                var attr = AttributedString(String(italic))
                attr.font = .system(size: 14 * LayoutMetrics.scale).italic()
                result += attr
                remaining = remaining[remaining.index(after: end)...]
            }
            // ~~strikethrough~~
            else if remaining.hasPrefix("~~"), let end = remaining.dropFirst(2).range(of: "~~") {
                let strike = remaining[remaining.index(remaining.startIndex, offsetBy: 2)..<end.lowerBound]
                var attr = AttributedString(String(strike))
                attr.strikethroughStyle = .single
                result += attr
                remaining = remaining[end.upperBound...]
            }
            // @mention
            else if remaining.hasPrefix("@") {
                let after = remaining.dropFirst()
                let mention = after.prefix(while: { $0.isLetter || $0.isNumber || $0 == "_" })
                if !mention.isEmpty {
                    var attr = AttributedString("@\(mention)")
                    attr.foregroundColor = MoodTheme.brandBlue
                    attr.font = .system(size: 14 * LayoutMetrics.scale, weight: .bold)
                    result += attr
                    remaining = after.dropFirst(mention.count)
                } else {
                    result += AttributedString("@")
                    remaining = after
                }
            }
            // #channel
            else if remaining.hasPrefix("#") {
                let after = remaining.dropFirst()
                let channel = after.prefix(while: { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" })
                if !channel.isEmpty {
                    var attr = AttributedString("#\(channel)")
                    attr.foregroundColor = MoodTheme.brandBlue
                    result += attr
                    remaining = after.dropFirst(channel.count)
                } else {
                    result += AttributedString("#")
                    remaining = after
                }
            }
            // Normal character
            else {
                let nextSpecial = remaining.dropFirst().firstIndex(where: { "*`~@#".contains($0) }) ?? remaining.endIndex
                let plain = remaining[remaining.startIndex..<nextSpecial]
                result += AttributedString(String(plain))
                remaining = remaining[nextSpecial...]
            }
        }

        return result
    }
}

// MARK: - Date Separator

struct DateSeparator: View {
    let date: Date

    var body: some View {
        HStack(spacing: 10) {
            Rectangle()
                .fill(MoodTheme.divider)
                .frame(height: 1)

            Text(date.dateSeparator)
                .font(.mood(11, weight: .semibold))
                .foregroundStyle(MoodTheme.textMuted)
                .fixedSize()

            Rectangle()
                .fill(MoodTheme.divider)
                .frame(height: 1)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }
}

// MARK: - Pinned Messages Panel

struct PinnedMessagesPanel: View {
    let messages: [ChatMessage]
    let server: MoodServer?
    @Binding var showPanel: Bool

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: "pin.fill")
                    .font(.mood(12))
                    .foregroundStyle(MoodTheme.brandAccent)
                Text("Messages épinglés")
                    .font(.mood(13, weight: .semibold))
                    .foregroundStyle(MoodTheme.textPrimary)
                Spacer()
                Button {
                    withAnimation(.easeInOut(duration: 0.15)) { showPanel = false }
                } label: {
                    Image(systemName: "xmark")
                        .font(.mood(11))
                        .foregroundStyle(MoodTheme.textPrimary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16 * LayoutMetrics.scale)
            .padding(.vertical, 10 * LayoutMetrics.scale)

            Rectangle().fill(MoodTheme.divider).frame(height: 1)

            if messages.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "pin.slash")
                        .font(.mood(28))
                        .foregroundStyle(MoodTheme.textPrimary)
                    Text("Aucun message épinglé")
                        .font(.mood(13))
                        .foregroundStyle(MoodTheme.textSecondary)
                }
                .padding(.vertical, 24 * LayoutMetrics.scale)
            } else {
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 8) {
                        ForEach(messages) { msg in
                            HStack(alignment: .top, spacing: 10 * LayoutMetrics.scale) {
                                Text(msg.sender.avatarEmoji)
                                    .font(.mood(12))
                                    .frame(width: 28 * LayoutMetrics.scale, height: 28 * LayoutMetrics.scale)
                                    .background(MoodTheme.glassBg)
                                    .clipShape(Circle())

                                VStack(alignment: .leading, spacing: 3) {
                                    HStack(spacing: 6 * LayoutMetrics.scale) {
                                        Text(msg.sender.displayName)
                                            .font(.mood(12, weight: .semibold))
                                            .foregroundStyle(msg.sender.roleColor)
                                        RoleBadge(role: server?.roleFor(msg.sender) ?? .member, size: 10 * LayoutMetrics.scale)
                                        Text(msg.timestamp.timeFormatted)
                                            .font(.mood(10))
                                            .foregroundStyle(MoodTheme.textMuted)
                                    }
                                    Text(msg.content)
                                        .font(.mood(12))
                                        .foregroundStyle(MoodTheme.textPrimary)
                                        .lineLimit(3)
                                }
                                Spacer()
                            }
                            .padding(10 * LayoutMetrics.scale)
                            .background(MoodTheme.glassBg)
                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        }
                    }
                    .padding(12)
                }
                .frame(maxHeight: 250)
            }
        }
        .background(MoodTheme.chatBackground)
        .overlay(Rectangle().fill(MoodTheme.divider).frame(height: 1), alignment: .bottom)
    }
}

// MARK: - Thread Panel

struct ThreadPanel: View {
    let message: ChatMessage
    let server: MoodServer?
    @Binding var showPanel: Bool
    @State private var threadText = ""
    @State private var showThreadEmojiPicker = false

    private var mockReplies: [ChatMessage] {
        let cal = Calendar.current
        let now = Date()
        let users = MockData.users
        return [
            ChatMessage(id: UUID(), sender: users[1], content: "Bonne idée ! On devrait implémenter ça rapidement.", timestamp: cal.date(byAdding: .minute, value: -18, to: now)!, isGrouped: false),
            ChatMessage(id: UUID(), sender: users[0], content: "J'ai commencé un prototype, je partage ça bientôt.", timestamp: cal.date(byAdding: .minute, value: -14, to: now)!, isGrouped: false),
            ChatMessage(id: UUID(), sender: users[2], content: "Super, j'ai hâte de voir ça !", timestamp: cal.date(byAdding: .minute, value: -8, to: now)!, isGrouped: false),
        ]
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Fil de discussion")
                    .font(.mood(14, weight: .bold))
                    .foregroundStyle(MoodTheme.textPrimary)

                Spacer()

                Button {
                    withAnimation(.easeInOut(duration: 0.2)) { showPanel = false }
                } label: {
                    Image(systemName: "xmark")
                        .font(.mood(12))
                        .foregroundStyle(MoodTheme.textPrimary)
                        .frame(width: 28 * LayoutMetrics.scale, height: 28 * LayoutMetrics.scale)
                        .background(MoodTheme.glassBg)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                .buttonStyle(.plain)
                .help("Fermer le fil")
            }
            .padding(.horizontal, 14 * LayoutMetrics.scale)
            .padding(.vertical, 12 * LayoutMetrics.scale)

            Rectangle().fill(MoodTheme.divider).frame(height: 1)

            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    // Original message
                    HStack(alignment: .top, spacing: 10 * LayoutMetrics.scale) {
                        Text(message.sender.avatarEmoji)
                            .font(.mood(20))
                            .frame(width: 36 * LayoutMetrics.scale, height: 36 * LayoutMetrics.scale)
                            .background(MoodTheme.glassBg)
                            .clipShape(Circle())

                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: 6 * LayoutMetrics.scale) {
                                Text(message.sender.displayName)
                                    .font(.mood(13, weight: .semibold))
                                    .foregroundStyle(message.sender.roleColor)
                                RoleBadge(role: server?.roleFor(message.sender) ?? .member, size: 11 * LayoutMetrics.scale)
                                Text(message.timestamp.messageTimestamp)
                                    .font(.mood(11))
                                    .foregroundStyle(MoodTheme.textMuted)
                            }
                            Text(message.content)
                                .font(.mood(13))
                                .foregroundStyle(MoodTheme.textPrimary)
                        }
                    }
                    .padding(14 * LayoutMetrics.scale)

                    // Reply count
                    HStack(spacing: 8) {
                        Rectangle().fill(MoodTheme.divider).frame(height: 1)
                        Text("\(message.threadInfo?.replyCount ?? mockReplies.count) réponses")
                            .font(.mood(11, weight: .semibold))
                            .foregroundStyle(MoodTheme.textSecondary)
                            .fixedSize()
                        Rectangle().fill(MoodTheme.divider).frame(height: 1)
                    }
                    .padding(.horizontal, 14 * LayoutMetrics.scale)
                    .padding(.vertical, 6)

                    // Replies
                    ForEach(mockReplies) { reply in
                        HStack(alignment: .top, spacing: 10 * LayoutMetrics.scale) {
                            Text(reply.sender.avatarEmoji)
                                .font(.mood(12))
                                .frame(width: 30 * LayoutMetrics.scale, height: 30 * LayoutMetrics.scale)
                                .background(MoodTheme.glassBg)
                                .clipShape(Circle())

                            VStack(alignment: .leading, spacing: 3) {
                                HStack(spacing: 6 * LayoutMetrics.scale) {
                                    Text(reply.sender.displayName)
                                        .font(.mood(12, weight: .semibold))
                                        .foregroundStyle(reply.sender.roleColor)
                                    RoleBadge(role: server?.roleFor(reply.sender) ?? .member, size: 10 * LayoutMetrics.scale)
                                    Text(reply.timestamp.timeFormatted)
                                        .font(.mood(10))
                                        .foregroundStyle(MoodTheme.textMuted)
                                }
                                Text(reply.content)
                                    .font(.mood(13))
                                    .foregroundStyle(MoodTheme.textPrimary)
                            }
                            Spacer()
                        }
                        .padding(.horizontal, 14 * LayoutMetrics.scale)
                        .padding(.vertical, 5 * LayoutMetrics.scale)
                    }
                }
            }

            Spacer(minLength: 0)

            // Thread input
            HStack(spacing: 8 * LayoutMetrics.scale) {
                TextField("Répondre au fil...", text: $threadText)
                    .textFieldStyle(.plain)
                    .font(.mood(13))
                    .foregroundStyle(MoodTheme.textPrimary)

                Button { showThreadEmojiPicker = true } label: {
                    Image(systemName: "face.smiling")
                        .font(.mood(14))
                        .foregroundStyle(MoodTheme.textPrimary)
                }
                .buttonStyle(.plain)
                .popover(isPresented: $showThreadEmojiPicker, arrowEdge: .top) {
                    EmojiPicker(isPresented: $showThreadEmojiPicker) { emoji in
                        threadText += emoji
                        showThreadEmojiPicker = false
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(MoodTheme.glassBg)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(MoodTheme.glassBorder, lineWidth: 0.5)
            )
            .padding(12)
        }
        .background(MoodTheme.chatBackground)
    }
}

// MARK: - Status Indicator Shape

struct StatusIndicator: View {
    let status: MoodUser.UserStatus
    let size: CGFloat
    let borderColor: Color

    init(status: MoodUser.UserStatus, size: CGFloat = 12, borderColor: Color = MoodTheme.chatBackground) {
        self.status = status
        self.size = size
        self.borderColor = borderColor
    }

    var body: some View {
        ZStack {
            // Border
            Circle()
                .fill(borderColor)
                .frame(width: size + 4, height: size + 4)

            // Simple: green = online, red = offline
            Circle()
                .fill(status == .offline ? MoodTheme.mentionBadge : MoodTheme.onlineGreen)
                .frame(width: size, height: size)
        }
    }
}

// MARK: - New Messages Separator

struct NewMessagesSeparator: View {
    var body: some View {
        HStack(spacing: 8) {
            Rectangle()
                .fill(MoodTheme.mentionBadge)
                .frame(height: 1)

            Text("NOUVEAU")
                .font(.mood(10, weight: .bold))
                .foregroundStyle(MoodTheme.mentionBadge)

            Rectangle()
                .fill(MoodTheme.mentionBadge)
                .frame(height: 1)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
    }
}

// MARK: - System Message Row

struct SystemMessageRow: View {
    let message: ChatMessage

    private var icon: String {
        switch message.systemType {
        case .userJoined: return "arrow.right.circle.fill"
        case .messagePinned: return "pin.circle.fill"
        case .serverBoosted: return "sparkles"
        case .none: return "info.circle"
        }
    }

    private var color: Color {
        switch message.systemType {
        case .userJoined: return MoodTheme.onlineGreen
        case .messagePinned: return MoodTheme.brandAccent
        case .serverBoosted: return Color(hex: "e879f9")
        case .none: return MoodTheme.textMuted
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8 * LayoutMetrics.scale) {
                Image(systemName: icon)
                    .font(.mood(12, weight: .bold))
                    .foregroundStyle(color)
                    .frame(width: 38 * LayoutMetrics.scale, alignment: .center)

                Text(message.content)
                    .font(.mood(13))
                    .foregroundStyle(MoodTheme.textSecondary)

                Text(message.timestamp.timeFormatted)
                    .font(.mood(11))
                    .foregroundStyle(MoodTheme.textMuted)
            }

            // "Fais coucou !" button for user joins (like Discord)
            if message.systemType == .userJoined {
                Button {
                    // TODO: envoyer "👋" dans le channel
                } label: {
                    HStack(spacing: 6 * LayoutMetrics.scale) {
                        Text("👋")
                            .font(.mood(12))
                        Text("Fais coucou !")
                            .font(.mood(12, weight: .medium))
                            .foregroundStyle(MoodTheme.textPrimary)
                    }
                    .padding(.horizontal, 12 * LayoutMetrics.scale)
                    .padding(.vertical, 6 * LayoutMetrics.scale)
                    .background(MoodTheme.glassBg)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                .buttonStyle(.plain)
                .padding(.leading, 46 * LayoutMetrics.scale)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 4)
    }
}

#Preview {
    ChatArea(
        channel: MockData.servers[0].categories[0].channels[0],
        server: MockData.servers[0],
        showProfilePopup: .constant(false),
        profileUser: .constant(nil)
    )
    .environment(MatrixStore())
    .preferredColorScheme(.dark)
}
