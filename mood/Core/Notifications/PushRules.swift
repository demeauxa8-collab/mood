import Foundation

// MARK: - Push rules (real mute)

/// Muting a room is a Matrix push rule: a `room` rule whose `actions` list is empty means "do not notify".
/// The server then stops counting that room's messages as notifications for every device of the account.
enum PushRules {

    static let allRulesPath = "/_matrix/client/v3/pushrules/"

    /// `PUT` (mute, body `{"actions":[]}`) / `DELETE` (unmute) target. The id is percent-encoded once.
    static func roomRulePath(roomId: String) -> String {
        "/_matrix/client/v3/pushrules/global/room/\(escape(roomId))"
    }

    /// Other clients (Element) mute with an `override` rule named after the room; unmuting removes it too.
    static func overrideRulePath(roomId: String) -> String {
        "/_matrix/client/v3/pushrules/global/override/\(escape(roomId))"
    }

    private static let pathAllowed: CharacterSet = {
        var set = CharacterSet.urlPathAllowed
        set.remove(charactersIn: "/")
        return set
    }()

    private static func escape(_ component: String) -> String {
        component.addingPercentEncoding(withAllowedCharacters: pathAllowed) ?? component
    }

    /// Rooms muted by the rule set returned by `GET /pushrules/` or by the `m.push_rules` account data
    /// (`{"global": {"override": [...], "room": [...], ...}}`).
    static func mutedRoomIds(in json: Any?) -> Set<String> {
        guard let root = json as? [String: Any],
              let global = root["global"] as? [String: Any] else { return [] }
        var muted = Set<String>()

        for rule in global["room"] as? [[String: Any]] ?? [] {
            guard let roomId = rule["rule_id"] as? String, isEnabled(rule), silencesNotifications(rule) else { continue }
            muted.insert(roomId)
        }

        // Element-style mute: an override rule matching `room_id` with no actions.
        for rule in global["override"] as? [[String: Any]] ?? [] {
            guard let roomId = rule["rule_id"] as? String, roomId.hasPrefix("!"),
                  isEnabled(rule), silencesNotifications(rule) else { continue }
            let conditions = rule["conditions"] as? [[String: Any]] ?? []
            let matchesRoom = conditions.contains {
                $0["kind"] as? String == "event_match"
                    && $0["key"] as? String == "room_id"
                    && $0["pattern"] as? String == roomId
            }
            if matchesRoom { muted.insert(roomId) }
        }
        return muted
    }

    private static func isEnabled(_ rule: [String: Any]) -> Bool {
        rule["enabled"] as? Bool ?? true
    }

    /// No actions, or only the legacy `dont_notify`.
    private static func silencesNotifications(_ rule: [String: Any]) -> Bool {
        guard let actions = rule["actions"] as? [Any] else { return false }
        return actions.allSatisfy { ($0 as? String) == "dont_notify" }
    }
}

// MARK: - Devices

/// One entry of `GET /devices`: a session of this account.
struct MatrixDevice: Codable, Identifiable, Equatable {
    let deviceId: String
    let displayName: String?
    let lastSeenIp: String?
    /// Milliseconds since 1970, nil when the server never saw the device.
    let lastSeenTs: Int64?

    var id: String { deviceId }

    var lastSeenDate: Date? {
        lastSeenTs.map { Date(timeIntervalSince1970: TimeInterval($0) / 1000) }
    }

    /// The name set by the app that opened the session, else its id.
    var title: String {
        guard let name = displayName?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty else { return deviceId }
        return name
    }

    enum CodingKeys: String, CodingKey {
        case deviceId = "device_id"
        case displayName = "display_name"
        case lastSeenIp = "last_seen_ip"
        case lastSeenTs = "last_seen_ts"
    }
}

struct MatrixDevicesResponse: Codable {
    let devices: [MatrixDevice]?
}

enum DeviceList {
    /// This device first, then the most recently active.
    static func ordered(_ devices: [MatrixDevice], currentDeviceId: String?) -> [MatrixDevice] {
        devices.sorted { lhs, rhs in
            if (lhs.deviceId == currentDeviceId) != (rhs.deviceId == currentDeviceId) {
                return lhs.deviceId == currentDeviceId
            }
            let left = lhs.lastSeenTs ?? 0
            let right = rhs.lastSeenTs ?? 0
            if left != right { return left > right }
            return lhs.deviceId < rhs.deviceId
        }
    }
}
