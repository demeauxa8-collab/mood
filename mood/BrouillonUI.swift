import SwiftUI

// Brouillon UI basé sur la frame Figma "Mood - UI Discord Calage".
// Reproduit en SwiftUI : barre serveurs, channels, chat, membres.

// MARK: - Modèle minimal

private struct BServer: Identifiable { let id = UUID(); let label: String; let color: Color; let selected: Bool }
private struct BChannel: Identifiable { let id = UUID(); let name: String; let voice: Bool; let unread: Int; let selected: Bool }
private struct BCategory: Identifiable { let id = UUID(); let title: String; let channels: [BChannel] }
private struct BMessage: Identifiable { let id = UUID(); let author: String; let color: Color; let initial: String; let time: String; let text: String; let reactions: [BReaction]; let compact: Bool }
private struct BReaction: Identifiable { let id = UUID(); let emoji: String; let count: Int; let mine: Bool }
private struct BMember: Identifiable { let id = UUID(); let name: String; let initial: String; let color: Color; let presence: Presence
    enum Presence { case online, idle, dnd, offline } }

// MARK: - Vue brouillon

struct BrouillonUI: View {
    private let servers: [BServer] = [
        .init(label: "M",  color: Color(hex: "6e56cf"), selected: true),
        .init(label: "DV", color: Color(hex: "5865f2"), selected: false),
        .init(label: "★",  color: Color(hex: "eb459e"), selected: false),
        .init(label: "GG", color: Color(hex: "57f287"), selected: false),
        .init(label: "JS", color: Color(hex: "fee75c"), selected: false),
        .init(label: "RP", color: Color(hex: "ed4245"), selected: false)
    ]

    private let categories: [BCategory] = [
        .init(title: "INFORMATION", channels: [
            .init(name: "annonces", voice: false, unread: 0, selected: false),
            .init(name: "règles",   voice: false, unread: 0, selected: false)
        ]),
        .init(title: "DISCUSSION", channels: [
            .init(name: "général", voice: false, unread: 0,  selected: true),
            .init(name: "dev",     voice: false, unread: 3,  selected: false),
            .init(name: "design",  voice: false, unread: 0,  selected: false),
            .init(name: "memes",   voice: false, unread: 12, selected: false)
        ]),
        .init(title: "VOCAL", channels: [
            .init(name: "Salon vocal", voice: true, unread: 0, selected: false),
            .init(name: "Stand-up",    voice: true, unread: 0, selected: false)
        ])
    ]

    private let messages: [BMessage] = [
        .init(author: "léo", color: Color(hex: "5865f2"), initial: "L", time: "aujourd'hui à 09:12",
              text: "Salut tout le monde, j'ai poussé le brouillon de l'UI sur la branche claude/connect-figma-0fOzY 🎨",
              reactions: [], compact: false),
        .init(author: "léo", color: Color(hex: "5865f2"), initial: "L", time: "09:12",
              text: "Le calage suit la frame Figma \"Mood — UI Discord Calage\"",
              reactions: [], compact: true),
        .init(author: "manon", color: Color(hex: "eb459e"), initial: "M", time: "aujourd'hui à 09:18",
              text: "Top, j'ouvre la PR. Faut juste remplacer les carrés rouges par les icônes serveurs.",
              reactions: [.init(emoji: "👍", count: 2, mine: true), .init(emoji: "🔥", count: 1, mine: false)],
              compact: false),
        .init(author: "tom", color: Color(hex: "23a55a"), initial: "T", time: "aujourd'hui à 09:24",
              text: "@adm tu peux ajouter la liste des membres à droite stp ? Sinon LGTM 👌",
              reactions: [], compact: false),
        .init(author: "adm", color: Color(hex: "6e56cf"), initial: "A", time: "aujourd'hui à 09:31",
              text: "Fait. La col 4 est là, 240px, avec online/offline et statuts.",
              reactions: [], compact: false)
    ]

    private let online: [BMember] = [
        .init(name: "adm",   initial: "A", color: Color(hex: "6e56cf"), presence: .online),
        .init(name: "léo",   initial: "L", color: Color(hex: "5865f2"), presence: .online),
        .init(name: "manon", initial: "M", color: Color(hex: "eb459e"), presence: .dnd),
        .init(name: "jules", initial: "J", color: Color(hex: "fee75c"), presence: .idle)
    ]
    private let offline: [BMember] = [
        .init(name: "tom",  initial: "T", color: Color(hex: "4f545c"), presence: .offline),
        .init(name: "nora", initial: "N", color: Color(hex: "4f545c"), presence: .offline),
        .init(name: "sami", initial: "S", color: Color(hex: "4f545c"), presence: .offline)
    ]

    var body: some View {
        HStack(spacing: 0) {
            serverBar
            channelColumn
            chatColumn
            memberColumn
        }
        .background(Color.black.ignoresSafeArea())
        .preferredColorScheme(.dark)
    }

    // MARK: - Server bar

    private var serverBar: some View {
        VStack(spacing: 8) {
            ForEach(Array(servers.enumerated()), id: \.element.id) { idx, s in
                serverIcon(s)
                if idx == 0 {
                    Rectangle().fill(MoodTheme.divider)
                        .frame(width: 32, height: 2).cornerRadius(1)
                        .padding(.vertical, 4)
                }
            }
            addServerIcon
            Spacer()
        }
        .padding(.top, 12)
        .frame(width: 72)
        .frame(maxHeight: .infinity)
        .background(MoodTheme.serverBar)
    }

    private func serverIcon(_ s: BServer) -> some View {
        HStack(spacing: 0) {
            Rectangle()
                .fill(.white)
                .frame(width: 4, height: s.selected ? 40 : 0)
                .clipShape(.rect(topLeadingRadius: 0, bottomLeadingRadius: 0,
                                 bottomTrailingRadius: 2, topTrailingRadius: 2))
                .animation(.spring(duration: 0.2), value: s.selected)

            Spacer(minLength: 0)

            RoundedRectangle(cornerRadius: s.selected ? 14 : 24, style: .continuous)
                .fill(s.color)
                .frame(width: 48, height: 48)
                .overlay(
                    Text(s.label)
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(textOn(s.color))
                )

            Spacer(minLength: 0)
        }
        .frame(width: 72, height: 48)
    }

    private var addServerIcon: some View {
        RoundedRectangle(cornerRadius: 24, style: .continuous)
            .fill(MoodTheme.serverIconBg)
            .frame(width: 48, height: 48)
            .overlay(
                Text("+")
                    .font(.system(size: 26, weight: .light))
                    .foregroundStyle(MoodTheme.onlineGreen)
            )
    }

    private func textOn(_ bg: Color) -> Color {
        // Texte foncé sur fond clair (jaune/vert vif)
        bg == Color(hex: "fee75c") || bg == Color(hex: "57f287") ? .black : .white
    }

    // MARK: - Channel column

    private var channelColumn: some View {
        VStack(spacing: 0) {
            // Header serveur
            HStack {
                Text("Mood — Équipe")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(MoodTheme.textPrimary)
                Spacer()
                Image(systemName: "chevron.down")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(MoodTheme.textSecondary)
            }
            .padding(.horizontal, 16)
            .frame(height: 48)
            .frame(maxWidth: .infinity)
            .overlay(Rectangle().fill(Color(hex: "1e1f22")).frame(height: 1), alignment: .bottom)

            // Liste channels
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(categories) { cat in
                        categoryHeader(cat.title)
                        ForEach(cat.channels) { channelRow($0) }
                    }
                    Spacer(minLength: 12)
                }
                .padding(.horizontal, 8)
            }
            .frame(maxHeight: .infinity)

            // Profil bar
            profileBar
        }
        .frame(width: 240)
        .background(MoodTheme.channelList)
    }

    private func categoryHeader(_ title: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: "chevron.down")
                .font(.system(size: 9, weight: .bold))
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .tracking(0.4)
            Spacer()
        }
        .foregroundStyle(MoodTheme.textSecondary)
        .padding(.horizontal, 8)
        .padding(.top, 16)
        .padding(.bottom, 4)
    }

    private func channelRow(_ c: BChannel) -> some View {
        HStack(spacing: 6) {
            Image(systemName: c.voice ? "speaker.wave.2.fill" : "number")
                .font(.system(size: 14))
                .foregroundStyle(c.selected ? MoodTheme.textPrimary : MoodTheme.textMuted)
                .frame(width: 20)
            Text(c.name)
                .font(.system(size: 14))
                .foregroundStyle(c.selected ? MoodTheme.textPrimary : MoodTheme.textSecondary)
            Spacer()
            if c.unread > 0 {
                Text("\(c.unread)")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 1)
                    .background(MoodTheme.mentionBadge, in: Capsule())
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(c.selected ? MoodTheme.selectedBg : .clear, in: RoundedRectangle(cornerRadius: 4))
    }

    private var profileBar: some View {
        HStack(spacing: 8) {
            ZStack(alignment: .bottomTrailing) {
                Circle().fill(Color(hex: "6e56cf")).frame(width: 32, height: 32)
                    .overlay(Text("A").font(.system(size: 13, weight: .bold)).foregroundStyle(.white))
                Circle().fill(MoodTheme.onlineGreen).frame(width: 10, height: 10)
                    .overlay(Circle().stroke(MoodTheme.inputBg, lineWidth: 3))
                    .offset(x: 2, y: 2)
            }
            VStack(alignment: .leading, spacing: 0) {
                Text("adm").font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(MoodTheme.textPrimary)
                Text("@adm:matrix.org").font(.system(size: 11))
                    .foregroundStyle(MoodTheme.textSecondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            ForEach(["mic.fill", "headphones", "gearshape.fill"], id: \.self) { icon in
                Image(systemName: icon)
                    .font(.system(size: 14))
                    .foregroundStyle(MoodTheme.textSecondary)
                    .frame(width: 28, height: 28)
            }
        }
        .padding(.horizontal, 8)
        .frame(height: 56)
        .background(MoodTheme.inputBg)
    }

    // MARK: - Chat column

    private var chatColumn: some View {
        VStack(spacing: 0) {
            chatHeader
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    dayDivider("19 mai 2026")
                    ForEach(messages) { messageRow($0) }
                }
                .padding(.bottom, 16)
            }
            .frame(maxHeight: .infinity)
            inputBar
        }
        .background(MoodTheme.chatBackground)
    }

    private var chatHeader: some View {
        HStack(spacing: 12) {
            Text("#").font(.system(size: 22, weight: .regular))
                .foregroundStyle(MoodTheme.textSecondary)
            Text("général").font(.system(size: 15, weight: .semibold))
                .foregroundStyle(MoodTheme.textPrimary)
            Rectangle().fill(MoodTheme.divider).frame(width: 1, height: 22)
            Text("Discussions générales de l'équipe Mood")
                .font(.system(size: 13)).foregroundStyle(MoodTheme.textSecondary)
            Spacer()
            HStack(spacing: 16) {
                ForEach(["bubble.left.and.bubble.right", "bell.fill", "pin.fill", "person.2.fill"], id: \.self) {
                    Image(systemName: $0).font(.system(size: 16))
                        .foregroundStyle(MoodTheme.textSecondary)
                }
            }
            HStack {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 11)).foregroundStyle(MoodTheme.textMuted)
                Text("Rechercher").font(.system(size: 12)).foregroundStyle(MoodTheme.textMuted)
            }
            .padding(.horizontal, 8).padding(.vertical, 4)
            .background(MoodTheme.serverBar, in: RoundedRectangle(cornerRadius: 4))
        }
        .padding(.horizontal, 16)
        .frame(height: 48)
        .overlay(Rectangle().fill(Color(hex: "1e1f22")).frame(height: 1), alignment: .bottom)
    }

    private func dayDivider(_ label: String) -> some View {
        HStack(spacing: 8) {
            Rectangle().fill(MoodTheme.divider).frame(height: 1)
            Text(label).font(.system(size: 12)).foregroundStyle(MoodTheme.textSecondary)
            Rectangle().fill(MoodTheme.divider).frame(height: 1)
        }
        .padding(.horizontal, 16)
        .padding(.top, 16)
    }

    private func messageRow(_ m: BMessage) -> some View {
        HStack(alignment: .top, spacing: 16) {
            if m.compact {
                Text(m.time)
                    .font(.system(size: 10))
                    .foregroundStyle(MoodTheme.textMuted)
                    .frame(width: 40, alignment: .trailing)
            } else {
                Circle().fill(m.color).frame(width: 40, height: 40)
                    .overlay(Text(m.initial).font(.system(size: 16, weight: .bold))
                        .foregroundStyle(textOn(m.color)))
            }
            VStack(alignment: .leading, spacing: 4) {
                if !m.compact {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(m.author)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(m.color)
                        Text(m.time)
                            .font(.system(size: 11))
                            .foregroundStyle(MoodTheme.textSecondary)
                    }
                }
                Text(m.text)
                    .font(.system(size: 15))
                    .foregroundStyle(MoodTheme.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                if !m.reactions.isEmpty {
                    HStack(spacing: 4) {
                        ForEach(m.reactions) { reactionPill($0) }
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
    }

    private func reactionPill(_ r: BReaction) -> some View {
        HStack(spacing: 4) {
            Text(r.emoji).font(.system(size: 12))
            Text("\(r.count)").font(.system(size: 12, weight: .semibold))
                .foregroundStyle(r.mine ? MoodTheme.textPrimary : MoodTheme.textSecondary)
        }
        .padding(.horizontal, 8).padding(.vertical, 2)
        .background(r.mine ? MoodTheme.brandAccent.opacity(0.15) : MoodTheme.serverBar,
                    in: Capsule())
        .overlay(Capsule().stroke(r.mine ? MoodTheme.brandAccent : MoodTheme.divider, lineWidth: 1))
    }

    private var inputBar: some View {
        HStack(spacing: 16) {
            Text("+").font(.system(size: 22, weight: .regular))
                .foregroundStyle(MoodTheme.textSecondary)
            Text("Envoyer un message dans #général")
                .font(.system(size: 14))
                .foregroundStyle(MoodTheme.textMuted)
            Spacer()
            HStack(spacing: 16) {
                Image(systemName: "gift.fill")
                Text("GIF").font(.system(size: 12, weight: .bold))
                Image(systemName: "face.smiling")
            }
            .foregroundStyle(MoodTheme.textSecondary)
        }
        .padding(.horizontal, 16)
        .frame(height: 44)
        .background(MoodTheme.inputBg, in: RoundedRectangle(cornerRadius: 8))
        .padding(.horizontal, 16)
        .padding(.bottom, 24)
    }

    // MARK: - Member column

    private var memberColumn: some View {
        VStack(alignment: .leading, spacing: 0) {
            memberCategory("EN LIGNE — \(online.count)")
            ForEach(online) { memberRow($0) }
            memberCategory("HORS LIGNE — \(offline.count)")
            ForEach(offline) { memberRow($0) }
            Spacer()
        }
        .padding(.top, 16)
        .frame(width: 240)
        .background(MoodTheme.memberList)
    }

    private func memberCategory(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 11, weight: .semibold))
            .tracking(0.4)
            .foregroundStyle(MoodTheme.textSecondary)
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .padding(.bottom, 4)
    }

    private func memberRow(_ m: BMember) -> some View {
        HStack(spacing: 12) {
            ZStack(alignment: .bottomTrailing) {
                Circle().fill(m.color).frame(width: 32, height: 32)
                    .overlay(Text(m.initial).font(.system(size: 13, weight: .bold))
                        .foregroundStyle(textOn(m.color)))
                if let c = presenceColor(m.presence) {
                    Circle().fill(c).frame(width: 10, height: 10)
                        .overlay(Circle().stroke(MoodTheme.memberList, lineWidth: 3))
                        .offset(x: 2, y: 2)
                }
            }
            Text(m.name)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(m.presence == .offline ? MoodTheme.textMuted : MoodTheme.textPrimary)
            Spacer()
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .padding(.horizontal, 8)
    }

    private func presenceColor(_ p: BMember.Presence) -> Color? {
        switch p {
        case .online:  return MoodTheme.onlineGreen
        case .idle:    return Color(hex: "f0b232")
        case .dnd:     return Color(hex: "da373c")
        case .offline: return nil
        }
    }
}

#Preview {
    BrouillonUI()
        .frame(width: 1440, height: 900)
}
