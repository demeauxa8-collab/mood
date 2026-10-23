import SwiftUI

// MARK: - Layout Mode

enum LayoutMode {
    case compact   // iPhone
    case regular   // Mac / iPad
}

// MARK: - Layout Metrics
// The desktop target uses the native Mac idiom (UIDeviceFamily 6), rendered 1:1.
// The old iPad idiom downscaled to 77%, causing ringing around glyphs and rules.
// Measurements below are now physical screen points; do not compensate twice.

enum LayoutMetrics {
    #if targetEnvironment(macCatalyst)
    static let scale: CGFloat = 1.0
    #else
    static let scale: CGFloat = 1.0
    #endif

    static let accountButtonHeight: CGFloat = 48 * scale
    static let accountCornerRadius: CGFloat = 10 * scale
    static let discordLogoSize: CGFloat = 22 * scale

    /// Mobile geometry uses the same design-system scaling boundary.
    static func mobile(_ value: CGFloat) -> CGFloat { value * scale }

    // Desktop geometry — Discord reference captured at Retina 2×.
    static let desktopTitleBarHeight: CGFloat = 33 * scale
    static let workspaceCornerRadius: CGFloat = 12 * scale

    static let onboardingCardWidth: CGFloat = 480 * scale

    // Server rail
    static let serverBarWidth: CGFloat = 72 * scale
    static let serverIconSize: CGFloat = 40 * scale
    static let serverIconCornerRadius: CGFloat = 12 * scale
    static let serverPillOffset: CGFloat = -17 * scale
    static let serverSeparatorWidth: CGFloat = 32 * scale

    // Channel / DM list
    #if targetEnvironment(macCatalyst)
    static let channelListWidth: CGFloat = 285 * scale
    static let desktopHeaderHeight: CGFloat = 49 * scale
    #else
    static let channelListWidth: CGFloat = 303 * scale
    static let desktopHeaderHeight: CGFloat = 48 * scale
    #endif

    // Floating user panel spans the rail and the channel list in Discord desktop.
    #if targetEnvironment(macCatalyst)
    static let userPanelWidth: CGFloat = 341 * scale
    #else
    static let userPanelWidth: CGFloat = 359 * scale
    #endif
    static let userPanelHeight: CGFloat = 58 * scale
    static let userPanelInset: CGFloat = 8 * scale

    // Bottom composer aligns exactly with the floating user panel.
    static let composerHeight: CGFloat = 58 * scale
    static let composerHorizontalInset: CGFloat = 8 * scale
    static let composerBottomInset: CGFloat = 8 * scale

    // Side panels
    #if targetEnvironment(macCatalyst)
    static let memberListWidth: CGFloat = 264 * scale
    #else
    static let memberListWidth: CGFloat = 240 * scale
    #endif
    static let threadPanelWidth: CGFloat = 360 * scale
    // Measured Friends column is 420 pixels including its leading rule.
    #if targetEnvironment(macCatalyst)
    static let friendsActivityPanelWidth: CGFloat = 419 * scale
    #else
    static let friendsActivityPanelWidth: CGFloat = 359 * scale
    #endif

    // Bottom padding to leave room for user status panel at bottom of channel list
    static let channelBottomPadding: CGFloat = userPanelHeight + 18 * scale
}

// MARK: - Scaled Font helper
// Use Font.mood() instead of Font.system() for auto-scaling on Mac Catalyst.

extension Font {
    static func mood(_ size: CGFloat, weight: Weight = .regular, design: Design = .default) -> Font {
        #if targetEnvironment(macCatalyst)
        if design == .default {
            return DesktopFriendsTypography.font(size, weight: weight)
        }
        #endif
        return .system(size: size * LayoutMetrics.scale, weight: weight, design: design)
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
