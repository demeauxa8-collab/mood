import Foundation

enum AccountValidation {
    static func isValidEmail(_ value: String) -> Bool {
        let parts = value.split(separator: "@", omittingEmptySubsequences: false)
        guard parts.count == 2, !parts[0].isEmpty, !value.contains(where: { $0.isWhitespace }),
              parts[1].contains("."), !parts[1].hasPrefix("."), !parts[1].hasSuffix(".") else { return false }
        return true
    }

    static func isValidEmailCode(_ value: String) -> Bool {
        value.utf8.count == 6 && value.utf8.allSatisfy { (48...57).contains($0) }
    }

    static func isValidPassword(_ value: String) -> Bool { value.count >= 8 }

    static func isVisiblePeer(_ id: String, me: String?, blocked: Set<String>) -> Bool {
        id.hasPrefix("@") && id != me && !blocked.contains(id)
    }

    static func canReuseDirectRoom(members: Set<String>, me: String, target: String) -> Bool {
        members.subtracting([me]) == [target]
    }
}
