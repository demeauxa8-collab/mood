import SwiftUI

struct MobileServerRail: View {
    let servers: [MoodServer]
    let selectedServer: MoodServer?
    let showingDMs: Bool
    let dmUnreadCount: Int
    let onDMs: () -> Void
    let onSelect: (MoodServer) -> Void
    let onCreate: () -> Void
    let onExplore: () -> Void

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: LayoutMetrics.mobile(12)) {
                railButton(selected: showingDMs, unread: dmUnreadCount > 0, mentionCount: dmUnreadCount, action: onDMs) {
                    Image(systemName: "bubble.left.fill").font(.mood(23)).foregroundStyle(MoodTheme.mobileIndicator).frame(width: LayoutMetrics.mobile(48), height: LayoutMetrics.mobile(48))
                        .background(showingDMs ? MoodTheme.brandBlue : MoodTheme.serverIconBg, in: RoundedRectangle(cornerRadius: LayoutMetrics.mobile(16), style: .continuous))
                }.accessibilityLabel("Messages privés")
                Rectangle().fill(MoodTheme.divider).frame(width: LayoutMetrics.mobile(32), height: LayoutMetrics.mobile(1))
                ForEach(servers) { server in
                    railButton(
                        selected: selectedServer?.id == server.id,
                        unread: server.hasUnread,
                        mentionCount: server.mentionCount,
                        action: { onSelect(server) }
                    ) {
                        ZStack {
                            if let url = server.iconURL {
                                AuthenticatedImage(url: url) { phase in
                                    if let image = phase.image { image.resizable().scaledToFill() } else { Text(server.iconEmoji).font(.mood(23)) }
                                }
                            } else { Text(server.iconEmoji).font(.mood(23)) }
                        }
                        .frame(width: LayoutMetrics.mobile(48), height: LayoutMetrics.mobile(48))
                        .background(MoodTheme.serverIconBg, in: RoundedRectangle(cornerRadius: LayoutMetrics.mobile(16), style: .continuous))
                        .clipShape(RoundedRectangle(cornerRadius: LayoutMetrics.mobile(16), style: .continuous))
                    }.accessibilityLabel(server.name)
                }
                Rectangle().fill(MoodTheme.divider).frame(width: LayoutMetrics.mobile(32), height: LayoutMetrics.mobile(1))
                railButton(selected: false, unread: false, mentionCount: 0, action: onCreate) {
                    Image(systemName: "plus").font(.mood(21, weight: .medium)).foregroundStyle(MoodTheme.onlineGreen)
                        .frame(width: LayoutMetrics.mobile(48), height: LayoutMetrics.mobile(48)).background(MoodTheme.serverIconBg, in: RoundedRectangle(cornerRadius: LayoutMetrics.mobile(16), style: .continuous))
                }
                railButton(selected: false, unread: false, mentionCount: 0, action: onExplore) {
                    Image(systemName: "safari").font(.mood(21)).foregroundStyle(MoodTheme.onlineGreen)
                        .frame(width: LayoutMetrics.mobile(48), height: LayoutMetrics.mobile(48)).background(MoodTheme.serverIconBg, in: RoundedRectangle(cornerRadius: LayoutMetrics.mobile(16), style: .continuous))
                }
            }
            .padding(.top, LayoutMetrics.mobile(8))
            .padding(.bottom, LayoutMetrics.mobile(62))
            .frame(maxWidth: .infinity)
        }
    }

    private func railButton<Label: View>(selected: Bool, unread: Bool, mentionCount: Int, action: @escaping () -> Void, @ViewBuilder label: () -> Label) -> some View {
        Button(action: action) {
            ZStack(alignment: .leading) {
                Capsule().fill(MoodTheme.mobileIndicator).frame(width: LayoutMetrics.mobile(4), height: LayoutMetrics.mobile(selected ? 38 : (unread ? 8 : 0))).offset(x: LayoutMetrics.mobile(-11))
                label()
                    .overlay(alignment: .bottomTrailing) {
                        if mentionCount > 0 {
                            Text(mentionCount > 99 ? "99+" : "\(mentionCount)")
                                .font(.mood(9, weight: .bold)).foregroundStyle(MoodTheme.mobileIndicator)
                                .padding(.horizontal, LayoutMetrics.mobile(4)).frame(minWidth: LayoutMetrics.mobile(17), minHeight: LayoutMetrics.mobile(16))
                                .background(MoodTheme.mentionBadge, in: Capsule())
                                .overlay(Capsule().stroke(MoodTheme.serverBar, lineWidth: LayoutMetrics.mobile(2)))
                                .offset(x: LayoutMetrics.mobile(5), y: LayoutMetrics.mobile(4))
                        }
                    }
            }
            .frame(width: LayoutMetrics.mobile(56), height: LayoutMetrics.mobile(50))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
