import SwiftUI

/// Floating mobile controls only; opaque content and desktop retain their styling.
extension View {
    @ViewBuilder
    func mobileGlass(cornerRadius: CGFloat = LayoutMetrics.mobile(24)) -> some View {
        if #available(iOS 26.0, *) {
            self.glassEffect(.regular, in: .rect(cornerRadius: cornerRadius))
        } else {
            self.background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous).stroke(MoodTheme.glassBorder, lineWidth: LayoutMetrics.mobile(0.5)))
        }
    }

    @ViewBuilder
    func mobileGlassCapsule() -> some View {
        if #available(iOS 26.0, *) {
            self.glassEffect(.regular, in: .capsule)
        } else {
            self.background(.ultraThinMaterial, in: Capsule())
                .overlay(Capsule().stroke(MoodTheme.glassBorder, lineWidth: LayoutMetrics.mobile(0.5)))
        }
    }
}

struct MobileGlassGroup<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        if #available(iOS 26.0, *) {
            GlassEffectContainer(spacing: LayoutMetrics.mobile(12), content: content)
        } else {
            content()
        }
    }
}
