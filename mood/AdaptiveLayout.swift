import SwiftUI

// MARK: - Layout Mode

enum LayoutMode {
    case compact   // iPhone
    case regular   // Mac / iPad
}

// MARK: - Mac Catalyst Layout Metrics
// Mac Catalyst scales the entire UI by 0.77x. To match Discord desktop dimensions,
// we compensate with a 1.28x factor (≈ 1/0.77) on Catalyst only.

enum LayoutMetrics {
    #if targetEnvironment(macCatalyst)
    static let scale: CGFloat = 1.28
    #else
    static let scale: CGFloat = 1.0
    #endif

    // Server bar
    static let serverBarWidth: CGFloat = 72 * scale
    static let serverIconSize: CGFloat = 48 * scale
    static let serverIconCornerRadius: CGFloat = 13 * scale
    static let serverPillOffset: CGFloat = -12 * scale
    static let serverSeparatorWidth: CGFloat = 32 * scale

    // Channel / DM list
    static let channelListWidth: CGFloat = 240 * scale

    // Carte principale (coin arrondi haut-gauche) + bande de titre
    static let cardCornerRadius: CGFloat = 18 * scale
    static let titleBarInset: CGFloat = 28 * scale

    // Headers (hauteur unifiée pour un trait fin continu sur toute la largeur)
    static let headerHeight: CGFloat = 38 * scale

    // Dock bas (pilules flottantes : panneau utilisateur + barre de saisie)
    static let dockMargin: CGFloat = 8 * scale
    static let dockCornerRadius: CGFloat = 11 * scale
    // Hauteur visible des pilules (utilisateur et saisie alignées)
    static let dockPillHeight: CGFloat = 52 * scale
    // Hauteur réservée en bas du rail + panneau pour la pilule utilisateur flottante
    static let dockReserve: CGFloat = 66 * scale

    // Side panels
    static let memberListWidth: CGFloat = 240 * scale
    static let threadPanelWidth: CGFloat = 340 * scale

    // Combined widths
    static var userPanelWidth: CGFloat { serverBarWidth + channelListWidth }

    // Bottom padding
    static let channelBottomPadding: CGFloat = 0
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
