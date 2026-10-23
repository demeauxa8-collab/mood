import Foundation
import SwiftUI

/// Explicit review route; it never restores a session or calls a live store.
enum OnboardingPreview {
    static var enabled: Bool { ProcessInfo.processInfo.arguments.contains("-onboardingPreview") }

    @MainActor
    static func makeModel(step override: OnboardingStep? = nil) -> OnboardingModel {
        let arguments = ProcessInfo.processInfo.arguments
        let suite = "mood.onboarding.preview.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        let actions = ReviewActions()
        actions.taken = arguments.contains("-onboardingTaken")
        actions.unavailable = arguments.contains("-onboardingOffline")
        var step = override ?? .welcome
        if override == nil, let index = arguments.firstIndex(of: "-onboardingStep"), arguments.indices.contains(index + 1),
           let requested = OnboardingStep(rawValue: arguments[index + 1]) { step = requested }
        let signedInSteps: [OnboardingStep] = [.displayName, .username, .trust, .server, .notifications, .friends, .avatar]
        let model = OnboardingModel(actions: actions, defaults: defaults,
                                    userID: signedInSteps.contains(step) ? "onboarding-review" : nil)
        if arguments.contains("-onboardingFilled") {
            model.email = "demo@example.invalid"
            model.username = "demo_user"
            model.displayName = "Alex"
            model.friendUsername = "friend"
            model.serverName = "Les amis"
            model.inviteCode = "democode"
        }
        model.go(step)
        // Navigation clears transient credentials; supply only synthetic review values afterwards.
        if arguments.contains("-onboardingFilled") {
            if [.account, .signIn].contains(step) { model.password = "example-password" }
            if step == .confirmation { model.code = "123456" }
        }
        if arguments.contains("-onboardingLongText") {
            model.displayName = "Alex et ses amis à travers le monde"
            model.username = String(repeating: "a", count: 32)
            model.serverName = "Le rendez-vous des amis après les cours"
        }
        return model
    }

    @MainActor
    private final class ReviewActions: OnboardingActions {
        var taken = false
        var unavailable = false
        func perform() async throws {
            try await Task.sleep(for: .milliseconds(120))
            if unavailable { throw OnboardingError.network }
        }
        func resumeConfirmation(email: String) {}
        func register(email: String, password: String) async throws { try await perform() }
        func confirmCode(_ code: String) async throws -> String {
            try await perform()
            guard code == "123456" else { throw OnboardingError.invalidCode }
            return "onboarding-review"
        }
        func resendCode() async throws { try await perform() }
        func login(email: String, password: String) async throws -> String { try await perform(); return "onboarding-review" }
        func resetPassword(email: String) async throws { try await perform() }
        func checkUsername(_ username: String) async throws -> Bool { try await perform(); return !taken }
        func setUsername(_ username: String) async throws {
            try await perform()
            if taken { throw OnboardingError.usernameTaken }
        }
        func setDisplayName(_ name: String) async throws { try await perform() }
        func setAvatar(_ data: Data) async throws { try await perform() }
        func setAvatarEmoji(_ emoji: String) async throws { try await perform() }
        func searchUser(username: String) async throws -> MoodUser? { try await perform(); return MockData.users.first }
        func addFriend(_ user: MoodUser) async throws { try await perform() }
        func openDM(with user: MoodUser) async throws { try await perform() }
        func joinServer(code: String) async throws { try await perform() }
        func createServer(name: String, template: OnboardingTemplate) async throws { try await perform() }
        func requestNotifications() async throws { try await perform() }
        func finish() async throws { try await perform() }
    }
}

struct OnboardingReviewScreen: View {
    @State private var model = OnboardingPreview.makeModel()
    @State private var showsEmptyHome = ProcessInfo.processInfo.arguments.contains("-onboardingHomeEmpty")
    let mode: LayoutMode
    var body: some View {
        Group {
            if showsEmptyHome || model.didFinish {
                OnboardingHomeEmptyState(onAddFriends: {
                    showsEmptyHome = false
                    model = OnboardingPreview.makeModel(step: .friends)
                })
            } else {
                OnboardingView(model: model, mode: mode)
            }
        }
        .environment(\.dynamicTypeSize, ProcessInfo.processInfo.arguments.contains("-onboardingLargeText") ? .accessibility3 : .large)
    }
}
