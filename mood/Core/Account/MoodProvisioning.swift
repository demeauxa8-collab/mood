import Foundation

struct MoodMatrixSession: Decodable, Sendable {
    let homeserver: String
    let userId: String
    let accessToken: String
    let deviceId: String
    let created: Bool
    enum CodingKeys: String, CodingKey {
        case homeserver, created
        case userId = "user_id", accessToken = "access_token", deviceId = "device_id"
    }
}

enum MoodProvisioningError: LocalizedError, Equatable {
    case http(Int)
    var errorDescription: String? {
        switch self {
        case .http(401): "Ta session Mood a expiré. Reconnecte-toi."
        case .http(503): "Le serveur Mood est injoignable"
        default: "Impossible de connecter ton compte Mood. Réessaie dans un instant."
        }
    }
}

enum MoodDevice {
    static func identifier(defaults: UserDefaults = .standard) -> String {
        let key = "mood.matrix.device_id"
        if let saved = defaults.string(forKey: key), saved.count == 16, saved.hasPrefix("MOOD") { return saved }
        let value = "MOOD" + UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(12).uppercased()
        defaults.set(value, forKey: key)
        return value
    }
    static var name: String {
        #if targetEnvironment(macCatalyst)
        "Mood · Mac"
        #else
        "Mood · iPhone"
        #endif
    }
}
