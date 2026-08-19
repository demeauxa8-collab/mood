import SwiftUI

// MARK: - Layout Mode

enum LayoutMode {
    case compact   // iPhone
    case regular   // Mac / iPad
}

// MARK: - Layout Metrics
// Mac Catalyst renders UIKit/SwiftUI geometry at roughly 0.7707× in
// "Optimized for Mac" mode. The values below are measured Discord screen
// points, so the Catalyst build compensates once at the design-system boundary.

enum LayoutMetrics {
    #if targetEnvironment(macCatalyst)
    static let scale: CGFloat = 1.298
    #else
    static let scale: CGFloat = 1.0
    #endif

    // Desktop geometry — Discord reference captured at Retina 2×.
    static let desktopTitleBarHeight: CGFloat = 33 * scale
    static let workspaceCornerRadius: CGFloat = 12 * scale

    // Server rail
    static let serverBarWidth: CGFloat = 72 * scale
    static let serverIconSize: CGFloat = 40 * scale
    static let serverIconCornerRadius: CGFloat = 12 * scale
    static let serverPillOffset: CGFloat = -17 * scale
    static let serverSeparatorWidth: CGFloat = 32 * scale

    // Channel / DM list
    static let channelListWidth: CGFloat = 303 * scale
    static let desktopHeaderHeight: CGFloat = 48 * scale

    // Floating user panel spans the rail and the channel list in Discord desktop.
    static let userPanelWidth: CGFloat = 359 * scale
    static let userPanelHeight: CGFloat = 58 * scale
    static let userPanelInset: CGFloat = 8 * scale

    // Bottom composer aligns exactly with the floating user panel.
    static let composerHeight: CGFloat = 58 * scale
    static let composerHorizontalInset: CGFloat = 8 * scale
    static let composerBottomInset: CGFloat = 8 * scale

    // Side panels
    static let memberListWidth: CGFloat = 240 * scale
    static let threadPanelWidth: CGFloat = 360 * scale
    // Discord's right column is 360 pt including its 1 pt leading divider.
    static let friendsActivityPanelWidth: CGFloat = 359 * scale

    // Bottom padding to leave room for user status panel at bottom of channel list
    static let channelBottomPadding: CGFloat = userPanelHeight + 18 * scale
}

// MARK: - Scaled Font helper
// Use Font.mood() instead of Font.system() for auto-scaling on Mac Catalyst.

extension Font {
    static func mood(_ size: CGFloat, weight: Weight = .regular, design: Design = .default) -> Font {
        .system(size: size * LayoutMetrics.scale, weight: weight, design: design)
    }
}

// MARK: - Environment Key

struct LayoutModeKey: EnvironmentKey {
    static let defaultValue: LayoutMode = .regular
}

extension EnvironmentValues {
    var layoutMode: LayoutMode {
        get { self[LayoutModeKey.self] }
        set { self[LayoutModeKey.self] = newValue }
    }
}

// MARK: - Adaptive Frame Modifier

extension View {
    /// Applique un frame fixe sur regular, rien sur compact.
    @ViewBuilder
    func adaptiveFrame(width: CGFloat? = nil, height: CGFloat? = nil, mode: LayoutMode) -> some View {
        if mode == .regular {
            self.frame(width: width, height: height)
        } else {
            self
        }
    }

    /// Applique minWidth/minHeight sur regular, rien sur compact.
    @ViewBuilder
    func adaptiveMinFrame(minWidth: CGFloat? = nil, minHeight: CGFloat? = nil, mode: LayoutMode) -> some View {
        if mode == .regular {
            self.frame(minWidth: minWidth, minHeight: minHeight)
        } else {
            self
        }
    }
}
