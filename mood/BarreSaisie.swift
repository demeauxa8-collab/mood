import SwiftUI

struct MessageInputBar: View {
    @Binding var text: String
    let channelName: String
    let isE2E: Bool
    var typingUsers: [String] = []
    @Binding var replyingTo: ChatMessage?
    var onSend: (() -> Void)?
    @State private var showEmojiPicker = false
    @State private var showGIFPicker = false
    @State private var showAttachMenu = false
    @State private var showAttachAlert = false

    init(text: Binding<String>, channelName: String, isE2E: Bool, typingUsers: [String] = [], replyingTo: Binding<ChatMessage?> = .constant(nil), onSend: (() -> Void)? = nil) {
        self._text = text
        self.channelName = channelName
        self.isE2E = isE2E
        self.typingUsers = typingUsers
        self._replyingTo = replyingTo
        self.onSend = onSend
    }

    var body: some View {
        VStack(spacing: 0) {
            // Typing indicator
            if !typingUsers.isEmpty {
                HStack(spacing: 6 * LayoutMetrics.scale) {
                    TypingDots()
                    Text(typingText)
                        .font(.mood(12))
                        .foregroundStyle(MoodTheme.textSecondary)
                    Spacer()
                }
                .padding(.horizontal, 20 * LayoutMetrics.scale)
                .padding(.bottom, 4)
            }

            // Reply bar
            if let reply = replyingTo {
                HStack(spacing: 8 * LayoutMetrics.scale) {
                    Image(systemName: "arrowshape.turn.up.left.fill")
                        .font(.mood(10))
                        .foregroundStyle(MoodTheme.brandAccent)

                    Text("Répondre à")
                        .font(.mood(12))
                        .foregroundStyle(MoodTheme.textSecondary)

                    Text(reply.sender.displayName)
                        .font(.mood(12, weight: .semibold))
                        .foregroundStyle(reply.sender.roleColor)

                    Text("— \(reply.content)")
                        .font(.mood(12))
                        .foregroundStyle(MoodTheme.textMuted)
                        .lineLimit(1)

                    Spacer()

                    Button {
                        withAnimation(.easeInOut(duration: 0.12)) { replyingTo = nil }
                    } label: {
                        Image(systemName: "xmark")
                            .font(.mood(10))
                            .foregroundStyle(MoodTheme.textPrimary)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 16 * LayoutMetrics.scale)
                .padding(.vertical, 8 * LayoutMetrics.scale)
                .background(MoodTheme.glassBg)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            HStack(spacing: 0) {
                // Bouton +
                Button { showAttachMenu.toggle() } label: {
                    Image(systemName: "plus")
                        .font(.mood(16, weight: .medium))
                        .foregroundStyle(MoodTheme.textPrimary)
                        .frame(width: 30 * LayoutMetrics.scale, height: 30 * LayoutMetrics.scale)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.leading, 8 * LayoutMetrics.scale)
                .padding(.trailing, 10 * LayoutMetrics.scale)
                .help("Joindre un fichier")
                .popover(isPresented: $showAttachMenu, arrowEdge: .top) {
                    VStack(spacing: 2) {
                        AttachMenuItem(icon: "doc", label: "Importer un fichier", color: MoodTheme.brandAccent) {
                            showAttachMenu = false
                            showAttachAlert = true
                        }
                        AttachMenuItem(icon: "photo", label: "Importer une photo", color: MoodTheme.onlineGreen) {
                            showAttachMenu = false
                            showAttachAlert = true
                        }
                        AttachMenuItem(icon: "text.bubble", label: "Créer un fil", color: MoodTheme.brandBlue) {
                            showAttachMenu = false
                            showAttachAlert = true
                        }
                    }
                    .padding(8)
                    .frame(width: 220)
                    .background(MoodTheme.channelList)
                }
                .alert("Bientôt disponible", isPresented: $showAttachAlert) {
                    Button("OK", role: .cancel) {}
                } message: {
                    Text("L'envoi de fichiers sera disponible dans une prochaine version.")
                }

                // Champ texte
                HStack(spacing: 6 * LayoutMetrics.scale) {
                    if isE2E {
                        Image(systemName: "lock.fill")
                            .font(.mood(9))
                            .foregroundStyle(MoodTheme.brandAccent.opacity(0.4))
                    }

                    TextField("Envoyer un message dans #\(channelName)", text: $text)
                        .textFieldStyle(.plain)
                        .font(.mood(14))
                        .foregroundStyle(MoodTheme.textPrimary)
                        .onSubmit { onSend?() }
                }

                // Boutons droite
                HStack(spacing: 4 * LayoutMetrics.scale) {
                    InputBarButton(icon: "gift")
                        .help("Envoyer un cadeau")

                    Button {
                        showGIFPicker.toggle()
                        showEmojiPicker = false
                    } label: {
                        Text("GIF")
                            .font(.mood(10, weight: .bold))
                            .foregroundStyle(MoodTheme.textPrimary)
                            .frame(width: 30 * LayoutMetrics.scale, height: 30 * LayoutMetrics.scale)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help("GIF")
                    .popover(isPresented: $showGIFPicker, arrowEdge: .bottom) {
                        GIFPicker(isPresented: $showGIFPicker)
                    }

                    Button {
                        showEmojiPicker.toggle()
                        showGIFPicker = false
                    } label: {
                        Image(systemName: "face.smiling")
                            .font(.mood(16))
                            .foregroundStyle(MoodTheme.textPrimary)
                            .frame(width: 30 * LayoutMetrics.scale, height: 30 * LayoutMetrics.scale)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help("Emoji")
                    .popover(isPresented: $showEmojiPicker, arrowEdge: .bottom) {
                        EmojiPicker(isPresented: $showEmojiPicker) { emoji in
                            text += emoji
                        }
                    }
                }
                .fixedSize()
                .padding(.trailing, 8 * LayoutMetrics.scale)
            }
            .padding(.vertical, 6 * LayoutMetrics.scale)
            .background(MoodTheme.glassBg)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .padding(.horizontal, 16 * LayoutMetrics.scale)
            .padding(.bottom, 20 * LayoutMetrics.scale)
            .padding(.top, 4)
        }
        .background(MoodTheme.chatBackground)
    }

    private var typingText: String {
        switch typingUsers.count {
        case 1: return "\(typingUsers[0]) est en train d'écrire..."
        case 2: return "\(typingUsers[0]) et \(typingUsers[1]) sont en train d'écrire..."
        default: return "Plusieurs personnes sont en train d'écrire..."
        }
    }
}

// MARK: - Typing Dots Animation

struct TypingDots: View {
    @State private var phase = 0

    var body: some View {
        HStack(spacing: 3) {
            ForEach(0..<3) { i in
                Circle()
                    .fill(MoodTheme.textSecondary)
                    .frame(width: 5, height: 5)
                    .offset(y: phase == i ? -3 : 0)
            }
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 0.4).repeatForever(autoreverses: true)) {
                phase = 1
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                withAnimation(.easeInOut(duration: 0.4).repeatForever(autoreverses: true)) {
                    phase = 2
                }
            }
        }
    }
}

struct InputBarButton: View {
    let icon: String
    @State private var showAlert = false

    var body: some View {
        Button { showAlert = true } label: {
            Image(systemName: icon)
                .font(.mood(16))
                .foregroundStyle(MoodTheme.textPrimary)
                .frame(width: 30 * LayoutMetrics.scale, height: 30 * LayoutMetrics.scale)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .alert("Bientôt disponible", isPresented: $showAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Cette fonctionnalité arrive dans une prochaine version.")
        }
    }
}

struct AttachMenuItem: View {
    let icon: String
    let label: String
    let color: Color
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 14))
                    .foregroundStyle(color)
                    .frame(width: 20)
                Text(label)
                    .font(.system(size: 13))
                    .foregroundStyle(isHovered ? .white : MoodTheme.textPrimary)
                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(isHovered ? MoodTheme.brandAccent : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { hovering in isHovered = hovering }
    }
}

// MARK: - Emoji Picker

struct EmojiPicker: View {
    @Environment(\.layoutMode) private var layoutMode
    @Binding var isPresented: Bool
    let onSelect: (String) -> Void

    @State private var searchText = ""
    @State private var selectedCategory = "Fréquents"

    private let categories: [(name: String, icon: String, emojis: [String])] = [
        ("Fréquents", "clock", ["😂", "❤️", "🔥", "👍", "😭", "🙏", "😍", "✨", "🎉", "💀", "👀", "🤔", "💯", "🥺", "😊", "🫡"]),
        ("Smileys", "face.smiling", ["😀", "😃", "😄", "😁", "😅", "😂", "🤣", "🥲", "😊", "😇", "🙂", "😉", "😌", "😍", "🥰", "😘", "😋", "😛", "😜", "🤪", "🤨", "🧐", "🤓", "😎", "🤩", "🥳", "😏", "😒", "😞", "😔", "😟", "😕", "🙁", "😣", "😖", "😫", "😩", "🥺", "😢", "😭", "😤", "😠", "😡", "🤬", "🤯", "😳", "🥵"]),
        ("Personnes", "person.fill", ["👋", "🤚", "🖐️", "✋", "🖖", "👌", "🤌", "🤏", "✌️", "🤞", "🤟", "🤘", "🤙", "👈", "👉", "👆", "🖕", "👇", "👍", "👎", "✊", "👊", "🤛", "🤜", "👏", "🙌", "🫶", "👐", "🤲", "🙏"]),
        ("Nature", "leaf", ["🐶", "🐱", "🐭", "🐹", "🐰", "🦊", "🐻", "🐼", "🐨", "🐯", "🦁", "🐮", "🐷", "🐸", "🐵", "🌸", "🌹", "🌺", "🌻", "🌼", "🌷", "🌱", "🌿", "☘️", "🍀", "🍁", "🍂", "🍃", "🌍"]),
        ("Nourriture", "fork.knife", ["🍎", "🍐", "🍊", "🍋", "🍌", "🍉", "🍇", "🍓", "🫐", "🍈", "🍒", "🍑", "🥭", "🍍", "🥥", "🥝", "🍅", "🍕", "🍔", "🍟", "🌭", "🍿", "🧁", "🍩", "🍪", "🎂", "☕", "🍷", "🍺"]),
        ("Activités", "gamecontroller", ["⚽", "🏀", "🏈", "⚾", "🥎", "🎾", "🏐", "🏉", "🥏", "🎱", "🏓", "🏸", "🏒", "🎯", "🪀", "🎮", "🕹️", "🎲", "🎭", "🎨", "🎬", "🎤", "🎧", "🎼", "🎹", "🥁", "🎷", "🎺"]),
        ("Objets", "lightbulb", ["💡", "🔦", "🕯️", "💰", "💎", "🔧", "🔨", "⚙️", "🔗", "💻", "🖥️", "⌨️", "🖱️", "📱", "☎️", "📷", "🎥", "📺", "📻", "⏰", "📧", "💌", "📦", "🔑", "🗝️", "🔒", "🔓", "❤️", "🧡", "💛", "💚", "💙", "💜", "🖤", "🤍"]),
        ("Symboles", "star", ["❤️", "🧡", "💛", "💚", "💙", "💜", "🖤", "🤍", "❤️‍🔥", "💔", "💯", "💢", "💥", "💫", "⭐", "🌟", "✨", "⚡", "🔥", "💧", "🌊", "✅", "❌", "⚠️", "🚫", "♻️", "🔴", "🟢", "🔵", "🟡"]),
    ]

    // Map emoji → searchable French keywords
    private static let emojiKeywords: [String: [String]] = [
        "😂": ["rire", "mdr", "lol"], "❤️": ["coeur", "amour", "love"], "🔥": ["feu", "fire", "hot"],
        "👍": ["pouce", "ok", "bien"], "😭": ["pleurer", "triste", "sad"], "🙏": ["prier", "merci", "svp"],
        "😍": ["amour", "love", "coeur"], "✨": ["etoile", "briller", "star"], "🎉": ["fete", "celebration"],
        "💀": ["mort", "dead", "skull"], "👀": ["yeux", "regarder", "voir"], "🤔": ["penser", "reflechir", "hmm"],
        "💯": ["cent", "parfait", "100"], "🥺": ["triste", "pitie", "please"], "😊": ["sourire", "heureux", "happy"],
        "🫡": ["salut", "respect", "soldat"], "👋": ["salut", "coucou", "hello", "bonjour"],
        "😀": ["sourire", "happy"], "😎": ["cool", "lunettes", "soleil"], "🥳": ["fete", "anniversaire"],
        "😢": ["triste", "pleurer"], "😡": ["colere", "enerve", "angry"], "🤣": ["mdr", "rire", "lol"],
        "💪": ["fort", "muscle", "strong"], "🎮": ["jeu", "gaming", "manette"], "💻": ["ordi", "code", "dev"],
        "☕": ["cafe", "coffee"], "🍕": ["pizza"], "🎵": ["musique", "music", "son"],
        "⚡": ["eclair", "rapide", "energie"], "🌊": ["vague", "mer", "ocean"], "🌸": ["fleur", "cerisier"],
    ]

    var filteredEmojis: [String] {
        if searchText.isEmpty { return [] }
        let query = searchText.lowercased()
            .folding(options: .diacriticInsensitive, locale: .current)
        return categories.flatMap { $0.emojis }.filter { emoji in
            if let keywords = Self.emojiKeywords[emoji] {
                return keywords.contains { $0.contains(query) }
            }
            return false
        }
    }

    var currentCategory: (name: String, icon: String, emojis: [String]) {
        categories.first { $0.name == selectedCategory } ?? categories[0]
    }

    var body: some View {
        VStack(spacing: 0) {
            // Search
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 12))
                    .foregroundStyle(MoodTheme.textMuted)
                TextField("Rechercher un emoji", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                    .foregroundStyle(MoodTheme.textPrimary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(MoodTheme.glassBg)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .padding(10)

            // Category tabs
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 4) {
                    ForEach(categories, id: \.name) { cat in
                        Button {
                            selectedCategory = cat.name
                        } label: {
                            Image(systemName: cat.icon)
                                .font(.system(size: 13))
                                .foregroundStyle(MoodTheme.textPrimary)
                                .frame(width: 30, height: 28)
                                .background(selectedCategory == cat.name ? MoodTheme.selectedBg : Color.clear)
                                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                        }
                        .buttonStyle(.plain)
                        .help(cat.name)
                    }
                }
                .padding(.horizontal, 10)
            }
            .padding(.bottom, 6)

            Rectangle().fill(MoodTheme.divider).frame(height: 1)

            // Emoji grid
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(searchText.isEmpty ? currentCategory.name.uppercased() : "RÉSULTATS")
                        .font(.system(size: 11, weight: .bold))
                        .tracking(0.4)
                        .foregroundStyle(MoodTheme.textSecondary)
                        .padding(.horizontal, 4)
                        .padding(.top, 8)

                    let emojisToShow = searchText.isEmpty ? currentCategory.emojis : filteredEmojis

                    if !searchText.isEmpty && emojisToShow.isEmpty {
                        Text("Aucun emoji trouvé")
                            .font(.system(size: 13))
                            .foregroundStyle(MoodTheme.textMuted)
                            .frame(maxWidth: .infinity)
                            .padding(.top, 20)
                    }

                    LazyVGrid(columns: Array(repeating: GridItem(.fixed(34), spacing: 2), count: 8), spacing: 2) {
                        ForEach(emojisToShow, id: \.self) { emoji in
                            Button {
                                onSelect(emoji)
                                isPresented = false
                            } label: {
                                Text(emoji)
                                    .font(.system(size: 22))
                                    .frame(width: 34, height: 34)
                                    .background(Color.clear)
                                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding(.horizontal, 10)
                .padding(.bottom, 10)
            }
        }
        .adaptiveFrame(width: 310, height: 360, mode: layoutMode)
        .background(MoodTheme.channelList)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(MoodTheme.glassBorder, lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.4), radius: 12, y: 4)
    }
}

// MARK: - GIF Picker

struct GIFPicker: View {
    @Environment(\.layoutMode) private var layoutMode
    @Binding var isPresented: Bool
    @State private var searchText = ""

    // GIF placeholders
    private let trendingGIFs: [(String, String)] = [
        ("😂", "Rire"), ("🎉", "Fête"), ("👏", "Applaudir"), ("🔥", "Feu"),
        ("💃", "Danse"), ("😍", "Amour"), ("🤣", "MDR"), ("👋", "Salut"),
        ("😎", "Cool"), ("🥳", "Célébration"), ("🤦", "Facepalm"), ("💪", "Fort"),
        ("😴", "Dormir"), ("🏃", "Courir"), ("🤝", "Deal"), ("🙈", "Oh non"),
    ]

    var body: some View {
        VStack(spacing: 0) {
            // Search
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 12))
                    .foregroundStyle(MoodTheme.textMuted)
                TextField("Rechercher un GIF", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                    .foregroundStyle(MoodTheme.textPrimary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(MoodTheme.glassBg)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .padding(10)

            // Trending label
            HStack {
                Text("TENDANCES")
                    .font(.system(size: 11, weight: .bold))
                    .tracking(0.4)
                    .foregroundStyle(MoodTheme.textSecondary)
                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 6)

            Rectangle().fill(MoodTheme.divider).frame(height: 1)

            // GIF grid
            ScrollView(showsIndicators: false) {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 6) {
                    ForEach(trendingGIFs, id: \.1) { emoji, label in
                        Button {
                            isPresented = false
                        } label: {
                            VStack(spacing: 4) {
                                Text(emoji)
                                    .font(.system(size: 32))
                                    .frame(maxWidth: .infinity)
                                    .frame(height: 80)
                                    .background(MoodTheme.glassBg)
                                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

                                Text(label)
                                    .font(.system(size: 10))
                                    .foregroundStyle(MoodTheme.textMuted)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(10)
            }

            // Powered by
            HStack {
                Text("Propulsé par Tenor")
                    .font(.system(size: 10))
                    .foregroundStyle(MoodTheme.textMuted)
            }
            .padding(.vertical, 6)
        }
        .adaptiveFrame(width: 310, height: 380, mode: layoutMode)
        .background(MoodTheme.channelList)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(MoodTheme.glassBorder, lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.4), radius: 12, y: 4)
    }
}

// MARK: - Quick Switcher

struct QuickSwitcher: View {
    @Environment(\.layoutMode) private var layoutMode
    @Binding var isPresented: Bool
    @State private var searchText = ""

    private var results: [(icon: String, name: String, detail: String)] {
        let all: [(icon: String, name: String, detail: String)] = [
            ("number", "general", "Design Club"),
            ("number", "showcase", "Design Club"),
            ("number", "feedback", "Design Club"),
            ("number", "general", "Swift Devs"),
            ("number", "swiftui-help", "Swift Devs"),
            ("speaker.wave.2", "lounge", "Design Club"),
            ("person.fill", "Clara", "Message privé"),
            ("person.fill", "Maxime", "Message privé"),
            ("person.fill", "Léa", "Message privé"),
        ]
        if searchText.isEmpty { return all }
        return all.filter { $0.name.localizedCaseInsensitiveContains(searchText) || $0.detail.localizedCaseInsensitiveContains(searchText) }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Search field
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 14))
                    .foregroundStyle(MoodTheme.textMuted)
                TextField("Où aller ?", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 15))
                    .foregroundStyle(MoodTheme.textPrimary)
            }
            .padding(14)
            .background(MoodTheme.glassBg)

            Rectangle().fill(MoodTheme.divider).frame(height: 1)

            // Results
            ScrollView(showsIndicators: false) {
                VStack(spacing: 2) {
                    ForEach(Array(results.enumerated()), id: \.offset) { _, result in
                        HStack(spacing: 10) {
                            Image(systemName: result.icon)
                                .font(.system(size: 13))
                                .foregroundStyle(MoodTheme.textMuted)
                                .frame(width: 20)
                            Text(result.name)
                                .font(.system(size: 14))
                                .foregroundStyle(MoodTheme.textPrimary)
                            Spacer()
                            Text(result.detail)
                                .font(.system(size: 12))
                                .foregroundStyle(MoodTheme.textMuted)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(MoodTheme.hoverBg)
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                    }
                }
                .padding(8)
            }
            .frame(maxHeight: 300)

            Rectangle().fill(MoodTheme.divider).frame(height: 1)

            HStack(spacing: 4) {
                Text("astuce :")
                    .font(.system(size: 11))
                    .foregroundStyle(MoodTheme.textMuted)
                Text("⌘K")
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundStyle(MoodTheme.textSecondary)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(MoodTheme.glassBg)
                    .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                Text("pour ouvrir rapidement")
                    .font(.system(size: 11))
                    .foregroundStyle(MoodTheme.textMuted)
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .adaptiveFrame(width: 520, mode: layoutMode)
        .background(MoodTheme.channelList)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(MoodTheme.glassBorder, lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.5), radius: 20, y: 8)
    }
}

#Preview {
    VStack {
        Spacer()
        MessageInputBar(text: .constant(""), channelName: "general", isE2E: true)
    }
    .background(MoodTheme.chatBackground)
    .preferredColorScheme(.dark)
}
