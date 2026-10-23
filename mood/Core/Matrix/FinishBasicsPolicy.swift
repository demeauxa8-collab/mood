import Foundation

/// Pure decisions shared by startup repair, the cached inbox and regression tests.
enum FinishBasicsPolicy {
    static func directPeer(me: String, members: [MatrixEvent], evidence: [MatrixEvent], isSpace: Bool) -> String? {
        guard !isSpace else { return nil }
        let joined = Set(members.compactMap { event in
            event.type == "m.room.member" && event.content?["membership"]?.stringValue == "join" ? event.stateKey : nil
        })
        guard joined.count == 2, joined.contains(me) else { return nil }
        let hasFlag = evidence.contains { event in
            guard event.content?["is_direct"]?.boolValue == true else { return false }
            if event.type == "m.room.create" { return true }
            guard event.type == "m.room.member" else { return false }
            return event.content?["membership"]?.stringValue == "join"
                || (event.stateKey == me && event.content?["membership"]?.stringValue == "invite")
        }
        return hasFlag ? joined.subtracting([me]).first : nil
    }

    static func isMention(_ event: MatrixEvent, me: String, names: [String], ignored: Set<String>) -> Bool {
        guard event.type == "m.room.message", let sender = event.sender, sender != me,
              !ignored.contains(sender), !MatrixStore.isRedactedEvent(event),
              MatrixStore.replacedEventId(of: event) == nil else { return false }
        if let mentions = event.content?["m.mentions"]?.dictValue {
            if mentions["room"]?.boolValue == true { return true }
            if mentions["user_ids"]?.arrayValue?.contains(where: { $0.stringValue == me }) == true { return true }
            // An explicit empty mentions object suppresses legacy name matching (notably replies).
            return false
        }
        let body = MatrixStore.plainBody(of: event)
        return ([me, "@room"] + names.filter { !$0.isEmpty }).contains { name in
            let pattern = "(?<![\\p{L}\\p{N}_])" + NSRegularExpression.escapedPattern(for: name) + "(?![\\p{L}\\p{N}_])"
            return body.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil
        }
    }
    static func effectiveMessages(_ events: [MatrixEvent]) -> [MatrixEvent] {
        let deleted = Set(events.compactMap { $0.type == "m.room.redaction" ? ($0.redacts ?? $0.content?["redacts"]?.stringValue) : nil })
        var edits: [String: MatrixEvent] = [:]
        for event in events {
            guard let target = MatrixStore.replacedEventId(of: event),
                  let id = event.eventId, !deleted.contains(id), !MatrixStore.isRedactedEvent(event) else { continue }
            if (event.originServerTs ?? 0) >= (edits[target]?.originServerTs ?? 0) { edits[target] = event }
        }
        return events.compactMap { event in
            guard event.type == "m.room.message", MatrixStore.replacedEventId(of: event) == nil,
                  let id = event.eventId, !deleted.contains(id), !MatrixStore.isRedactedEvent(event) else { return nil }
            guard let edit = edits[id], edit.sender == event.sender,
                  let content = edit.content?["m.new_content"]?.dictValue else { return event }
            return MatrixEvent(type: event.type, eventId: id, sender: event.sender, originServerTs: event.originServerTs,
                               content: content, stateKey: event.stateKey, unsigned: event.unsigned, redacts: event.redacts)
        }
    }

}
