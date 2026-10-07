import Foundation

// MARK: - POST /_matrix/client/v3/search

struct MatrixSearchResponse: Decodable, Sendable {
    let searchCategories: SearchCategories

    struct SearchCategories: Decodable, Sendable {
        let roomEvents: MatrixSearchRoomEvents?

        enum CodingKeys: String, CodingKey { case roomEvents = "room_events" }
    }

    enum CodingKeys: String, CodingKey { case searchCategories = "search_categories" }
}

struct MatrixSearchRoomEvents: Decodable, Sendable {
    /// Approximate number of matches across every page.
    let count: Int?
    /// Pass back as `next_batch` to get the following page; nil on the last one.
    let nextBatch: String?
    let results: [MatrixSearchResult]?
    /// Words the server matched, used to highlight them in the results.
    let highlights: [String]?

    enum CodingKeys: String, CodingKey {
        case count, results, highlights
        case nextBatch = "next_batch"
    }
}

struct MatrixSearchResult: Decodable, Sendable {
    let rank: Double?
    let result: MatrixEvent
    /// `room_id` of the matched event; `MatrixEvent` does not carry it, search results need it.
    let roomId: String?

    private enum CodingKeys: String, CodingKey { case rank, result }
    private enum EventKeys: String, CodingKey { case roomId = "room_id" }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        rank = try container.decodeIfPresent(Double.self, forKey: .rank)
        result = try container.decode(MatrixEvent.self, forKey: .result)
        roomId = try container.nestedContainer(keyedBy: EventKeys.self, forKey: .result)
            .decodeIfPresent(String.self, forKey: .roomId)
    }
}

// MARK: - GET /_matrix/client/v3/notifications

struct MatrixNotificationsResponse: Decodable, Sendable {
    let nextToken: String?
    let notifications: [MatrixNotification]

    enum CodingKeys: String, CodingKey {
        case nextToken = "next_token"
        case notifications
    }
}

struct MatrixNotification: Decodable, Sendable {
    let event: MatrixEvent
    let roomId: String
    let read: Bool
    let ts: Int64?

    enum CodingKeys: String, CodingKey {
        case event, read, ts
        case roomId = "room_id"
    }
}
