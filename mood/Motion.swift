import SwiftUI

private struct MoodReduceMotionKey: EnvironmentKey {
    static let defaultValue = false
}

/// A visible-only ringing indicator with no retained repeat-forever animation.
struct MoodRingingPulse: View {
    @Environment(\.moodReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: reduceMotion)) { context in
            let phase = context.date.timeIntervalSinceReferenceDate
                .truncatingRemainder(dividingBy: 1.2) / 1.2
            Circle()
                .stroke(MoodTheme.textSecondary.opacity(0.15), lineWidth: 2)
                .scaleEffect(reduceMotion ? 1 : 1 + 0.35 * phase)
                .opacity(reduceMotion ? 1 : 1 - phase)
        }
        .accessibilityHidden(true)
    }
}

extension EnvironmentValues {
    var moodReduceMotion: Bool {
        get { self[MoodReduceMotionKey.self] }
        set { self[MoodReduceMotionKey.self] = newValue }
    }
}

enum MoodMotion {
    static let reduceMotionPreferenceKey = "reduce_motion"

    /// Immediate feedback for hover and pressed states.
    static let hover = Animation.easeOut(duration: 0.12)

    /// Anchored menus and compact non-blocking surfaces.
    static let popover = Animation.easeOut(duration: 0.16)

    /// Short, non-bouncing state changes and occasional screen transitions.
    static let feedback = Animation.easeOut(duration: 0.16)
    static let screen = Animation.easeOut(duration: 0.24)

    /// Trailing panels keep a critically damped, interruptible response.
    static let panel = Animation.spring(response: 0.30, dampingFraction: 1.0)
}

/// Shared desktop press feedback. SwiftUI updates `isPressed` on pointer-down,
/// so controls react before their action is committed on pointer-up.
struct MoodPressButtonStyle: ButtonStyle {
    @Environment(\.moodReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.97 : 1)
            .opacity(configuration.isPressed ? 0.82 : 1)
            .animation(
                reduceMotion ? nil : .easeOut(duration: 0.08),
                value: configuration.isPressed
            )
    }
}
