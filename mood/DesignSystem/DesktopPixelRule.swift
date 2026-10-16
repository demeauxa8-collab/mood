import SwiftUI

enum DesktopPixelMetrics {
    static var legacyHeaderOffset: CGFloat {
        #if targetEnvironment(macCatalyst)
        0
        #else
        0.25 * LayoutMetrics.scale
        #endif
    }

    static func thickness(displayScale: CGFloat) -> CGFloat {
        guard displayScale.isFinite, displayScale > 0 else { return 1 }
        return 1 / displayScale
    }
}

/// A single filled physical-pixel strip. Platform menus keep their own Divider.
/// iPhone/iPad retain the original one-point layout and rendering behavior.
struct DesktopPixelRule: View {
    @Environment(\.displayScale) private var displayScale
    var vertical = false
    var color: Color = MoodTheme.divider

    private var thickness: CGFloat {
        #if targetEnvironment(macCatalyst)
        DesktopPixelMetrics.thickness(displayScale: displayScale)
        #else
        1
        #endif
    }

    var body: some View {
        Rectangle()
            .fill(color, style: FillStyle(antialiased: !isDesktop))
            .frame(width: vertical ? thickness : nil,
                   height: vertical ? nil : thickness)
            .accessibilityHidden(true)
    }

    private var isDesktop: Bool {
        #if targetEnvironment(macCatalyst)
        true
        #else
        false
        #endif
    }
}
