import Foundation

// MARK: - Mentions

/// A room member that `@name` in the composer can refer to.
nonisolated struct MentionCandidate: Equatable, Sendable {
    let userId: String
    let displayName: String

    var localpart: String {
        let trimmed = userId.hasPrefix("@") ? String(userId.dropFirst()) : userId
        return trimmed.split(separator: ":", maxSplits: 1).first.map(String.init) ?? trimmed
    }
}

/// What the composer text becomes on the wire.
nonisolated struct FormattedMessage: Equatable, Sendable {
    /// Plain fallback: the markdown as typed (Mood and Element render it).
    let body: String
    /// `org.matrix.custom.html`, nil when the text has no formatting and no mention.
    let formattedBody: String?
    /// `m.mentions.user_ids`: members named with @, in order, never the sender.
    let mentionedUserIds: [String]
    /// `@room` / `@everyone` / `@here`.
    let mentionsRoom: Bool
}

// MARK: - Markdown → HTML

/// Discord's markdown subset turned into Matrix HTML: **gras**, *italique* / _italique_, __souligné__,
/// ~~barré~~, ||spoiler||, `code`, ```blocs```, > citations, [liens](https://…) and bare URLs.
/// Everything else is escaped, so the output is safe for any client's HTML sanitizer.
nonisolated enum MessageFormatter {
    static let htmlFormat = "org.matrix.custom.html"

    static func format(_ text: String, members: [MentionCandidate] = [], selfUserId: String? = nil) -> FormattedMessage {
        var renderer = MarkdownHTMLRenderer(members: members, selfUserId: selfUserId)
        let html = renderer.render(text)
        return FormattedMessage(
            body: text,
            formattedBody: renderer.didFormat ? html : nil,
            mentionedUserIds: renderer.mentioned,
            mentionsRoom: renderer.mentionsRoom
        )
    }

    /// HTML for `text`, nil when it is plain.
    static func html(fromMarkdown text: String) -> String? {
        format(text).formattedBody
    }

    static func escape(_ text: String) -> String {
        var out = ""
        out.reserveCapacity(text.count)
        for character in text { out += escape(character) }
        return out
    }

    static func escape(_ character: Character) -> String {
        switch character {
        case "&": "&amp;"
        case "<": "&lt;"
        case ">": "&gt;"
        case "\"": "&quot;"
        case "'": "&#39;"
        default: String(character)
        }
    }
}

nonisolated private struct MarkdownHTMLRenderer {
    let members: [MentionCandidate]
    let selfUserId: String?
    private(set) var didFormat = false
    private(set) var mentioned: [String] = []
    private(set) var mentionsRoom = false

    init(members: [MentionCandidate], selfUserId: String?) {
        self.members = members
        self.selfUserId = selfUserId
    }

    private static let escapable: Set<Character> = ["\\", "*", "_", "`", "~", "|", ">", "[", "]", "(", ")", "#", "@"]
    private static let pairs: [(delimiter: [Character], open: String, close: String)] = [
        (Array("**"), "<strong>", "</strong>"),
        (Array("__"), "<u>", "</u>"),
        (Array("~~"), "<del>", "</del>"),
        (Array("||"), "<span data-mx-spoiler>", "</span>"),
    ]
    private static let roomMentions = ["@room", "@everyone", "@here"]

    // MARK: Blocks

    mutating func render(_ text: String) -> String {
        let lines = text.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n")
        var output = ""
        var paragraph: [String] = []
        var index = 0

        while index < lines.count {
            let line = lines[index]

            if let fence = Self.codeFence(in: lines, at: index) {
                output += flush(&paragraph)
                let language = fence.language.map { " class=\"language-\(MessageFormatter.escape($0))\"" } ?? ""
                output += "<pre><code\(language)>\(MessageFormatter.escape(fence.code))</code></pre>"
                didFormat = true
                index = fence.next
                continue
            }

            // Discord's ">>> " quotes the whole rest of the message.
            if line.hasPrefix(">>> ") || line == ">>>" {
                output += flush(&paragraph)
                let rest = [String(line.dropFirst(min(4, line.count)))] + lines[(index + 1)...]
                output += "<blockquote>\(inline(rest.joined(separator: "\n")))</blockquote>"
                didFormat = true
                return output
            }

            if line.hasPrefix("> ") || line == ">" {
                output += flush(&paragraph)
                var quoted: [String] = []
                while index < lines.count, lines[index].hasPrefix("> ") || lines[index] == ">" {
                    quoted.append(lines[index] == ">" ? "" : String(lines[index].dropFirst(2)))
                    index += 1
                }
                output += "<blockquote>\(inline(quoted.joined(separator: "\n")))</blockquote>"
                didFormat = true
                continue
            }

            paragraph.append(line)
            index += 1
        }
        output += flush(&paragraph)
        return output
    }

    private mutating func flush(_ paragraph: inout [String]) -> String {
        defer { paragraph = [] }
        // Blank lines next to a block would only add stray <br>s.
        var lines = paragraph
        while lines.first?.trimmingCharacters(in: .whitespaces).isEmpty == true { lines.removeFirst() }
        while lines.last?.trimmingCharacters(in: .whitespaces).isEmpty == true { lines.removeLast() }
        guard !lines.isEmpty else { return "" }
        return inline(lines.joined(separator: "\n"))
    }

    private static func codeFence(in lines: [String], at start: Int) -> (language: String?, code: String, next: Int)? {
        let line = lines[start]
        guard line.hasPrefix("```") else { return nil }
        let afterOpen = line.dropFirst(3)

        // ```one line```
        if afterOpen.count > 3, afterOpen.hasSuffix("```") {
            return (nil, String(afterOpen.dropLast(3)), start + 1)
        }

        let info = afterOpen.trimmingCharacters(in: .whitespaces)
        var language: String?
        var codeLines: [String] = []
        if !info.isEmpty {
            if info.allSatisfy({ $0.isLetter || $0.isNumber || "+#-_.".contains($0) }) {
                language = info
            } else {
                codeLines.append(String(afterOpen))
            }
        }

        var index = start + 1
        while index < lines.count {
            let current = lines[index]
            if current.trimmingCharacters(in: .whitespaces) == "```" {
                return (language, codeLines.joined(separator: "\n"), index + 1)
            }
            if current.hasSuffix("```") {
                codeLines.append(String(current.dropLast(3)))
                return (language, codeLines.joined(separator: "\n"), index + 1)
            }
            codeLines.append(current)
            index += 1
        }
        return nil // never closed: shown as typed
    }

    // MARK: Inline

    private mutating func inline(_ text: String) -> String {
        let characters = Array(text)
        return inline(characters, characters.startIndex, characters.endIndex)
    }

    private mutating func inline(_ c: [Character], _ start: Int, _ end: Int) -> String {
        var out = ""
        var i = start

        scan: while i < end {
            let ch = c[i]

            if ch == "\\", i + 1 < end, Self.escapable.contains(c[i + 1]) {
                out += MessageFormatter.escape(c[i + 1])
                i += 2
                continue
            }

            if ch == "\n" {
                out += "<br>"
                i += 1
                continue
            }

            if ch == "`" {
                var run = 0
                while i + run < end, c[i + run] == "`" { run += 1 }
                if let close = Self.closingBackticks(c, run: run, from: i + run, end: end) {
                    let code = String(c[(i + run)..<close])
                    out += "<code>\(MessageFormatter.escape(code).replacingOccurrences(of: "\n", with: "<br>"))</code>"
                    didFormat = true
                    i = close + run
                } else {
                    out += String(repeating: "`", count: run)
                    i += run
                }
                continue
            }

            if ch == "[", let link = Self.maskedLink(c, at: i, end: end) {
                out += "<a href=\"\(MessageFormatter.escape(link.url))\">\(inline(c, link.textStart, link.textEnd))</a>"
                didFormat = true
                i = link.next
                continue
            }

            if ch == "h" || ch == "H", Self.isWordStart(c, i), let link = Self.autolink(c, at: i, end: end) {
                out += "<a href=\"\(MessageFormatter.escape(link.url))\">\(MessageFormatter.escape(link.url))</a>"
                didFormat = true
                i = link.next
                continue
            }

            if ch == "@", let mention = mention(c, at: i, end: end) {
                out += mention.html
                i = mention.next
                continue
            }

            for pair in Self.pairs where Self.hasPrefix(c, pair.delimiter, at: i, end: end) {
                let contentStart = i + pair.delimiter.count
                guard var close = Self.find(pair.delimiter, in: c, from: contentStart, end: end),
                      close > contentStart,
                      !String(c[contentStart..<close]).trimmingCharacters(in: .whitespaces).isEmpty else { continue }
                // "***x***": the closing ** is the end of the star run.
                while close + pair.delimiter.count < end, c[close + pair.delimiter.count] == pair.delimiter[0] { close += 1 }
                out += pair.open + inline(c, contentStart, close) + pair.close
                didFormat = true
                i = close + pair.delimiter.count
                continue scan
            }

            if ch == "*", let close = Self.closingStar(c, from: i, end: end) {
                out += "<em>\(inline(c, i + 1, close))</em>"
                didFormat = true
                i = close + 1
                continue
            }

            if ch == "_", let close = Self.closingUnderscore(c, from: i, end: end) {
                out += "<em>\(inline(c, i + 1, close))</em>"
                didFormat = true
                i = close + 1
                continue
            }

            out += MessageFormatter.escape(ch)
            i += 1
        }
        return out
    }

    // MARK: Mentions

    private mutating func mention(_ c: [Character], at i: Int, end: Int) -> (html: String, next: Int)? {
        // "alice@example.org" is an e-mail address, not a mention.
        if i > 0, c[i - 1].isLetter || c[i - 1].isNumber || c[i - 1] == "_" || c[i - 1] == "." { return nil }

        for keyword in Self.roomMentions {
            let length = keyword.count
            if i + length <= end, String(c[i..<(i + length)]) == keyword, Self.isBoundary(c, i + length, end: end) {
                mentionsRoom = true
                return (MessageFormatter.escape(keyword), i + length)
            }
        }

        var best: (member: MentionCandidate, length: Int)?
        for member in members {
            for form in [member.userId, "@" + member.displayName, "@" + member.localpart] where form.count > 1 {
                let length = form.count
                guard length > best?.length ?? 0, i + length <= end,
                      String(c[i..<(i + length)]).compare(form, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame,
                      Self.isBoundary(c, i + length, end: end) else { continue }
                best = (member, length)
            }
        }
        guard let best else { return nil }

        let userId = best.member.userId
        if userId != selfUserId, !mentioned.contains(userId) { mentioned.append(userId) }
        didFormat = true
        let pill = "<a href=\"https://matrix.to/#/\(MessageFormatter.escape(userId))\">\(MessageFormatter.escape(best.member.displayName))</a>"
        return (pill, i + best.length)
    }

    // MARK: Scanning helpers

    private static func isBoundary(_ c: [Character], _ index: Int, end: Int) -> Bool {
        guard index < end else { return true }
        let next = c[index]
        return !(next.isLetter || next.isNumber || next == "_")
    }

    private static func isWordStart(_ c: [Character], _ index: Int) -> Bool {
        index == 0 || c[index - 1].isWhitespace || "(<".contains(c[index - 1])
    }

    private static func hasPrefix(_ c: [Character], _ delimiter: [Character], at index: Int, end: Int) -> Bool {
        guard index + delimiter.count <= end else { return false }
        return Array(c[index..<(index + delimiter.count)]) == delimiter
    }

    private static func find(_ delimiter: [Character], in c: [Character], from start: Int, end: Int) -> Int? {
        var index = start
        while index + delimiter.count <= end {
            if c[index] == "\\" { index += 2; continue }
            if hasPrefix(c, delimiter, at: index, end: end) { return index }
            index += 1
        }
        return nil
    }

    private static func closingBackticks(_ c: [Character], run: Int, from start: Int, end: Int) -> Int? {
        var index = start
        while index < end {
            guard c[index] == "`" else { index += 1; continue }
            var length = 0
            while index + length < end, c[index + length] == "`" { length += 1 }
            if length == run, index > start { return index }
            index += length
        }
        return nil
    }

    /// `*x*`: no space right inside the stars ("2 * 3 * 4" stays as typed).
    private static func closingStar(_ c: [Character], from i: Int, end: Int) -> Int? {
        guard i + 1 < end, !c[i + 1].isWhitespace, c[i + 1] != "*" else { return nil }
        var index = i + 2
        while index < end {
            if c[index] == "\\" { index += 2; continue }
            if c[index] == "*", !c[index - 1].isWhitespace { return index }
            index += 1
        }
        return nil
    }

    /// `_x_` only at word edges, so snake_case_names are left alone.
    private static func closingUnderscore(_ c: [Character], from i: Int, end: Int) -> Int? {
        if i > 0, c[i - 1].isLetter || c[i - 1].isNumber { return nil }
        guard i + 1 < end, !c[i + 1].isWhitespace, c[i + 1] != "_" else { return nil }
        var index = i + 2
        while index < end {
            if c[index] == "\\" { index += 2; continue }
            if c[index] == "_", !c[index - 1].isWhitespace,
               index + 1 >= end || !(c[index + 1].isLetter || c[index + 1].isNumber) {
                return index
            }
            index += 1
        }
        return nil
    }

    private static func maskedLink(_ c: [Character], at i: Int, end: Int) -> (url: String, textStart: Int, textEnd: Int, next: Int)? {
        guard let closeBracket = c[(i + 1)..<end].firstIndex(of: "]"), closeBracket > i + 1,
              closeBracket + 1 < end, c[closeBracket + 1] == "(",
              let closeParen = c[(closeBracket + 2)..<end].firstIndex(of: ")") else { return nil }
        let url = String(c[(closeBracket + 2)..<closeParen]).trimmingCharacters(in: .whitespaces)
        guard isAllowedLink(url), !url.contains(" ") else { return nil }
        return (url, i + 1, closeBracket, closeParen + 1)
    }

    private static func autolink(_ c: [Character], at i: Int, end: Int) -> (url: String, next: Int)? {
        var index = i
        while index < end, !c[index].isWhitespace, c[index] != "<", c[index] != ">" { index += 1 }
        var candidate = String(c[i..<index])
        // Trailing punctuation belongs to the sentence, and an unbalanced ")" to the parenthesis.
        while let last = candidate.last, ".,;:!?\"'".contains(last) || (last == ")" && !candidate.contains("(")) {
            candidate.removeLast()
        }
        let lower = candidate.lowercased()
        guard lower.hasPrefix("https://") || lower.hasPrefix("http://"),
              let schemeEnd = candidate.range(of: "://"), candidate[schemeEnd.upperBound...].count > 0 else { return nil }
        return (candidate, i + candidate.count)
    }

    private static func isAllowedLink(_ url: String) -> Bool {
        let lower = url.lowercased()
        return lower.hasPrefix("https://") || lower.hasPrefix("http://") || lower.hasPrefix("mailto:")
    }
}

// MARK: - Length limit

/// 4 000 characters per message; the composer shows what is left past 3 500 (Discord does the same).
nonisolated enum MessageLengthPolicy {
    static let maxCharacters = 4000
    static let counterThreshold = 3500

    static func isTooLong(_ text: String) -> Bool {
        text.count > maxCharacters
    }

    /// Characters left (negative once over), nil while the counter stays hidden.
    static func remaining(for text: String) -> Int? {
        let count = text.count
        return count > counterThreshold ? maxCharacters - count : nil
    }

    static func tooLongMessage(for text: String) -> String {
        "Ton message fait \(text.count.formatted()) caractères : la limite est de \(maxCharacters.formatted()). Raccourcis-le ou envoie-le en plusieurs fois."
    }
}

// MARK: - Event content

/// The JSON content of the `m.room.message` events Mood sends.
nonisolated enum MatrixMessageContent {
    /// Always present (even empty): it opts the event into intentional mentions,
    /// so a display name merely appearing in the text no longer pings anyone.
    static func mentions(userIds: [String], room: Bool) -> [String: Any] {
        var mentions: [String: Any] = ["user_ids": userIds]
        if room { mentions["room"] = true }
        return mentions
    }

    static func relation(replyToEventId: String?, threadRootEventId: String?) -> [String: Any]? {
        var relatesTo: [String: Any] = [:]
        if let threadRootEventId {
            relatesTo["rel_type"] = "m.thread"
            relatesTo["event_id"] = threadRootEventId
            relatesTo["is_falling_back"] = replyToEventId == nil
            relatesTo["m.in_reply_to"] = ["event_id": replyToEventId ?? threadRootEventId]
        } else if let replyToEventId {
            relatesTo["m.in_reply_to"] = ["event_id": replyToEventId]
        }
        return relatesTo.isEmpty ? nil : relatesTo
    }

    static func text(body: String, formattedBody: String?, mentionUserIds: [String], mentionsRoom: Bool,
                     replyToEventId: String? = nil, threadRootEventId: String? = nil) -> [String: Any] {
        var content: [String: Any] = [
            "msgtype": "m.text",
            "body": body,
            "m.mentions": mentions(userIds: mentionUserIds, room: mentionsRoom)
        ]
        if let formattedBody {
            content["format"] = MessageFormatter.htmlFormat
            content["formatted_body"] = formattedBody
        }
        if let relatesTo = relation(replyToEventId: replyToEventId, threadRootEventId: threadRootEventId) {
            content["m.relates_to"] = relatesTo
        }
        return content
    }

    static func media(msgtype: String, body: String, contentURI: String, info: [String: Any]) -> [String: Any] {
        [
            "msgtype": msgtype,
            "body": body,
            "filename": body,
            "url": contentURI,
            "info": info,
            "m.mentions": mentions(userIds: [], room: false)
        ]
    }

    /// `m.replace` edit. The top-level `m.mentions` only names people the edit adds,
    /// so fixing a typo does not ping everyone again.
    static func edit(eventId: String, body: String, formattedBody: String?, mentionUserIds: [String],
                     mentionsRoom: Bool, previousMentionUserIds: [String]) -> [String: Any] {
        var newContent: [String: Any] = [
            "msgtype": "m.text",
            "body": body,
            "m.mentions": mentions(userIds: mentionUserIds, room: mentionsRoom)
        ]
        var content: [String: Any] = [
            "msgtype": "m.text",
            "body": "* \(body)",
            "m.mentions": mentions(userIds: mentionUserIds.filter { !previousMentionUserIds.contains($0) }, room: false),
            "m.relates_to": ["rel_type": "m.replace", "event_id": eventId]
        ]
        if let formattedBody {
            newContent["format"] = MessageFormatter.htmlFormat
            newContent["formatted_body"] = formattedBody
            content["format"] = MessageFormatter.htmlFormat
            content["formatted_body"] = "* \(formattedBody)"
        }
        content["m.new_content"] = newContent
        return content
    }
}
