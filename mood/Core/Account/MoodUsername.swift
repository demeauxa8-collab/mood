import Foundation

/// Discord-style Mood username (`profiles.username`): 2–32 characters of a–z, 0–9, `_` and `.`,
/// no "..". It is how people find each other: the Matrix directory hides users who share no room.
enum MoodUsername {
    /// "@Augustin " → "augustin"; nil when the text cannot be a username (a full `@x:server` id included).
    static func normalized(_ input: String) -> String? {
        var text = input.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if text.hasPrefix("@") { text.removeFirst() }
        return isValid(text) ? text : nil
    }

    static func isValid(_ text: String) -> Bool {
        guard (2...32).contains(text.count), !text.contains("..") else { return false }
        return text.allSatisfy { ("a"..."z").contains($0) || ("0"..."9").contains($0) || $0 == "_" || $0 == "." }
    }
    static let rule = "2 à 32 caractères : lettres minuscules, chiffres, _ et . ; pas de points consécutifs."

    static func updateError(status: Int, code: String?) -> String? {
        if status == 409 || code == "23505" { return "Ce nom d'utilisateur est déjà pris" }
        if code == "23514" { return rule }
        return nil
    }

}
