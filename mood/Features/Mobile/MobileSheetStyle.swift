import SwiftUI

/// Opaque content with native navigation; Liquid Glass is supplied by the system toolbar.
struct MobileSheet<Content: View>: View {
    let title: String
    /// Set on a sub-step: the leading button becomes a back chevron, like a pushed screen.
    var onBack: (() -> Void)? = nil
    let onClose: () -> Void
    @ViewBuilder let content: () -> Content

    var body: some View {
        NavigationStack {
            content()
                .navigationTitle(title)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        if let onBack { MobileBackButton(action: onBack) } else { MobileCloseButton(action: onClose) }
                    }
                }
        }
        .tint(MoodTheme.brandAccent)
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .presentationBackground(MoodTheme.mobileSurface)
    }
}

struct MobileCloseButton: View {
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Image(systemName: "xmark").font(.mood(17, weight: .semibold))
                .frame(minWidth: LayoutMetrics.mobile(44), minHeight: LayoutMetrics.mobile(44))
        }.accessibilityLabel("Fermer")
            .foregroundStyle(MoodTheme.textPrimary)
    }
}

struct MobileBackButton: View {
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Image(systemName: "chevron.left").font(.mood(17, weight: .semibold))
                .frame(minWidth: LayoutMetrics.mobile(44), minHeight: LayoutMetrics.mobile(44))
        }.accessibilityLabel("Retour")
            .foregroundStyle(MoodTheme.textPrimary)
    }
}

struct MobilePrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var enabled
    var secondary = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.mood(16, weight: .semibold))
            .foregroundStyle(secondary ? MoodTheme.textPrimary : MoodTheme.mobileIndicator)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity, minHeight: LayoutMetrics.mobile(50))
            .padding(.horizontal, LayoutMetrics.mobile(16))
            .background(secondary ? MoodTheme.inputBg : MoodTheme.brandAccent, in: Capsule())
            .opacity(enabled ? (configuration.isPressed ? 0.8 : 1) : 0.45)
    }
}

extension View {
    func mobileGroupedList() -> some View {
        self.listStyle(.insetGrouped)
            .contentMargins(.horizontal, LayoutMetrics.mobile(16), for: .scrollContent)
            .scrollContentBackground(.hidden)
            .background(MoodTheme.mobileSurface)
            .font(.mood(16))
            .foregroundStyle(MoodTheme.textPrimary)
            .tint(MoodTheme.brandAccent)
            .environment(\.defaultMinListRowHeight, LayoutMetrics.mobile(44))
            .scrollDismissesKeyboard(.interactively)
    }

    func mobileCard() -> some View {
        self.padding(LayoutMetrics.mobile(16))
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(MoodTheme.inputBg, in: RoundedRectangle(cornerRadius: LayoutMetrics.mobile(16)))
    }
}
