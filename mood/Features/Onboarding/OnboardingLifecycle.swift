import Foundation

/// Upgrade exemption is decided once, after session restoration, before showing a new flow.
@MainActor
enum OnboardingLifecycle {
    static let migrationKey = "mood.onboarding.migrated.v1"

    static func bootstrap(restoredAccountID: String?, restoredEmail: String? = nil, defaults: UserDefaults = .standard) {
        if let id = restoredAccountID {
            OnboardingModel.recoverConfirmation(for: id, email: restoredEmail, defaults: defaults)
        }
        guard !defaults.bool(forKey: migrationKey) else { return }
        if let id = restoredAccountID,
           defaults.data(forKey: OnboardingModel.progressKey(for: id)) == nil {
            defaults.set(true, forKey: OnboardingModel.completionKey(for: id))
        }
        defaults.set(true, forKey: migrationKey)
    }
}
