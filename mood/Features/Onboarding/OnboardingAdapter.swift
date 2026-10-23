import Foundation

/// Narrow service boundary: tests replace these operations without sessions, keychain or network.
@MainActor
struct OnboardingServices {
    var checkUsername: (String) async throws -> Bool
    var register: (String, String) async throws -> Void
    var confirm: (String, String) async throws -> String
    var resend: (String) async throws -> Void
    var login: (String, String) async throws -> String
    var resetPassword: (String) async throws -> Void
    var setUsername: (String) async throws -> Void
    var setDisplayName: (String) async throws -> Void
    var setAvatar: (Data) async throws -> Void
    var setAvatarEmoji: (String) async throws -> Void
    var searchUser: (String) async throws -> MoodUser?
    var addFriend: (MoodUser) async throws -> Void
    var openDM: (MoodUser) async throws -> Void
    var joinServer: (String) async throws -> Void
    var createServer: (String, OnboardingTemplate) async throws -> Void
    var requestNotifications: () async throws -> Void
    var finish: () async throws -> Void
}

@MainActor
final class OnboardingAdapter: OnboardingActions {
    private let services: OnboardingServices
    private var pendingEmail = ""

    init(services: OnboardingServices) { self.services = services }

    func resumeConfirmation(email: String) {
        pendingEmail = email
    }

    func register(email: String, password: String) async throws {
        try await services.register(email, password)
        resumeConfirmation(email: email)
    }

    func confirmCode(_ code: String) async throws -> String {
        try await services.confirm(code, pendingEmail)
    }

    func resendCode() async throws { try await services.resend(pendingEmail) }
    func login(email: String, password: String) async throws -> String { try await services.login(email, password) }
    func resetPassword(email: String) async throws { try await services.resetPassword(email) }
    func checkUsername(_ username: String) async throws -> Bool { try await services.checkUsername(username) }
    func setUsername(_ username: String) async throws { try await services.setUsername(username) }
    func setDisplayName(_ name: String) async throws { try await services.setDisplayName(name) }
    func setAvatar(_ data: Data) async throws { try await services.setAvatar(data) }
    func setAvatarEmoji(_ emoji: String) async throws { try await services.setAvatarEmoji(emoji) }
    func searchUser(username: String) async throws -> MoodUser? { try await services.searchUser(username) }
    func addFriend(_ user: MoodUser) async throws { try await services.addFriend(user) }
    func openDM(with user: MoodUser) async throws { try await services.openDM(user) }
    func joinServer(code: String) async throws { try await services.joinServer(code) }
    func createServer(name: String, template: OnboardingTemplate) async throws { try await services.createServer(name, template) }
    func requestNotifications() async throws { try await services.requestNotifications() }
    func finish() async throws { try await services.finish() }
}
