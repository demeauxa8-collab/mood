import Foundation

enum AccountStatusStorage {
    static func load(userId: String, defaults: UserDefaults = .standard) -> (MoodUser.UserStatus, String?) {
        let key = "mood.status.\(userId)"
        let status = defaults.string(forKey: key).flatMap(MoodUser.UserStatus.init(rawValue:)) ?? .online
        return (status, defaults.string(forKey: key + ".message"))
    }

    static func save(status: MoodUser.UserStatus, message: String?, userId: String, defaults: UserDefaults = .standard) {
        let key = "mood.status.\(userId)"
        defaults.set(status.rawValue, forKey: key)
        defaults.set(message, forKey: key + ".message")
    }
}
