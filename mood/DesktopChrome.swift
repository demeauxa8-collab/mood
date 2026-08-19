import SwiftUI

// MARK: - Discord desktop chrome

/// The global strip introduced by Discord's refreshed desktop UI. Keeping it
/// outside the workspace lets the server rail and rounded content surface
/// follow the measured Discord desktop chrome independently.
struct DesktopTitleBar: View {
    let title: String
    var symbol: String = "bubble.left.and.bubble.right.fill"
    var onBack: () -> Void = {}
    var onForward: () -> Void = {}

    @State private var inboxHovered = false
    @State private var helpHovered = false
    @State private var backHovered = false
    @State private var forwardHovered = false

    var body: some View {
        ZStack {
            HStack(spacing: 0) {
                HStack(spacing: -4 * LayoutMetrics.scale) {
                    titleButton(
                        icon: "arrow.left",
                        help: "Retour",
                        isHovered: $backHovered,
                        action: onBack
                    )

                    titleButton(
                        icon: "arrow.right",
                        help: "Suivant",
                        isHovered: $forwardHovered,
                        isEnabled: false,
                        action: onForward
                    )
                }
                .padding(.leading, 82 * LayoutMetrics.scale)

                Spacer()

                HStack(spacing: 8 * LayoutMetrics.scale) {
                    titleButton(
                        icon: "tray.full.fill",
                        help: "Boîte de réception",
                        isHovered: $inboxHovered,
                        action: {}
                    )

                    titleButton(
                        icon: "questionmark.circle.fill",
                        help: "Aide",
                        isHovered: $helpHovered,
                        action: {}
                    )
                }
                .padding(.trailing, 14 * LayoutMetrics.scale)
            }

            HStack(spacing: 7 * LayoutMetrics.scale) {
                Image(systemName: symbol)
                    .font(.mood(10, weight: .bold))
                    .foregroundStyle(MoodTheme.brandAccent)

                Text(title)
                    .font(.mood(12, weight: .semibold))
                    .foregroundStyle(MoodTheme.textPrimary)
                    .lineLimit(1)
            }
            .padding(.horizontal, 12 * LayoutMetrics.scale)
            .frame(height: 26 * LayoutMetrics.scale)
            .contentShape(Rectangle())
        }
        .frame(height: LayoutMetrics.desktopTitleBarHeight)
        .background(MoodTheme.titleBar)
    }

    private func titleButton(
        icon: String,
        help: String,
        isHovered: Binding<Bool>,
        isEnabled: Bool = true,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.mood(13, weight: .semibold))
                .foregroundStyle(isHovered.wrappedValue ? MoodTheme.textPrimary : MoodTheme.textSecondary)
                .frame(width: 28 * LayoutMetrics.scale, height: 28 * LayoutMetrics.scale)
                .background(isHovered.wrappedValue ? MoodTheme.hoverBg : Color.clear)
                .clipShape(RoundedRectangle(cornerRadius: 7 * LayoutMetrics.scale, style: .continuous))
        }
        .buttonStyle(.plain)
        .opacity(isEnabled ? 1 : 0.42)
        .disabled(!isEnabled)
        .onHover { isHovered.wrappedValue = $0 }
        .help(help)
    }
}

/// Consistent desktop hover feedback used by compact icon-only actions.
struct DesktopIconButton: View {
    let icon: String
    let help: String
    var badge: Bool = false
    var action: () -> Void = {}

    @State private var isHovered = false
    @State private var isPressed = false

    var body: some View {
        Button {
            withAnimation(.easeOut(duration: 0.09)) { isPressed = true }
            action()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.09) {
                withAnimation(.easeOut(duration: 0.09)) { isPressed = false }
            }
        } label: {
            ZStack(alignment: .topTrailing) {
                Image(systemName: icon)
                    .font(.mood(15, weight: .semibold))
                    .foregroundStyle(isHovered ? MoodTheme.textPrimary : MoodTheme.textSecondary)
                    .frame(width: 32 * LayoutMetrics.scale, height: 32 * LayoutMetrics.scale)
                    .background(isHovered ? MoodTheme.hoverBg : Color.clear)
                    .clipShape(RoundedRectangle(cornerRadius: 8 * LayoutMetrics.scale, style: .continuous))

                if badge {
                    Circle()
                        .fill(MoodTheme.mentionBadge)
                        .frame(width: 7 * LayoutMetrics.scale, height: 7 * LayoutMetrics.scale)
                        .overlay(Circle().stroke(MoodTheme.chatBackground, lineWidth: 1.5 * LayoutMetrics.scale))
                        .offset(x: -2 * LayoutMetrics.scale, y: 2 * LayoutMetrics.scale)
                }
            }
            .scaleEffect(isPressed ? 0.92 : 1)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.12)) { isHovered = hovering }
        }
        .help(help)
    }
}
