import SwiftUI

// MARK: - Layout Mode

enum LayoutMode {
    case compact   // iPhone
    case regular   // Mac / iPad
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
