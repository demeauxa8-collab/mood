import Foundation

// MARK: - API Response Types

struct MatrixLoginResponse: Codable, Sendable {
    let accessToken: String
    let userId: String
    let deviceId: String
    let homeServer: String?

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case userId = "user_id"
        case deviceId = "device_id"
        case homeServer = "home_server"
    }
}

struct MatrixRegisterResponse: Codable, Sendable {
    let accessToken: String?
    let userId: String?
    let deviceId: String?
    let session: String?
    let flows: [MatrixAuthFlow]?

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case userId = "user_id"
        case deviceId = "device_id"
        case session, flows
    }
}

struct MatrixAuthFlow: Codable, Sendable {
    let stages: [String]?
}

struct MatrixSyncResponse: Codable, Sendable {
    let nextBatch: String
    let rooms: SyncRooms?
    let accountData: AccountData?
    let presence: SyncPresence?

    enum CodingKeys: String, CodingKey {
        case nextBatch = "next_batch"
        case rooms
        case accountData = "account_data"
        case presence
    }
}

struct SyncPresence: Codable, Sendable {
    let events: [MatrixEvent]?
}

struct AccountData: Codable, Sendable {
    let events: [MatrixEvent]?
}

struct SyncRooms: Codable, Sendable {
    let join: [String: JoinedRoom]?
    let invite: [String: InvitedRoom]?
    let leave: [String: LeavingRoom]?
}

struct JoinedRoom: Codable, Sendable {
    let timeline: RoomTimeline?
    let state: RoomState?
    let summary: RoomSummary?
    let unreadNotifications: UnreadNotifications?
    /// Per-thread counts (filter `unread_thread_notifications`); `unread_notifications` then excludes them.
    let unreadThreadNotifications: [String: UnreadNotifications]?
    let accountData: AccountData?
    let ephemeral: RoomEphemeral?

    enum CodingKeys: String, CodingKey {
        case timeline, state, summary, ephemeral
        case unreadNotifications = "unread_notifications"
        case unreadThreadNotifications = "unread_thread_notifications"
        case accountData = "account_data"
    }
}

struct RoomEphemeral: Codable, Sendable {
    let events: [MatrixEvent]?
}

struct RoomTimeline: Codable, Sendable {
    let events: [MatrixEvent]?
    let limited: Bool?
    let prevBatch: String?

    enum CodingKeys: String, CodingKey {
        case events, limited
        case prevBatch = "prev_batch"
    }
}

struct RoomState: Codable, Sendable {
    let events: [MatrixEvent]?
}

struct MatrixEvent: Codable, Sendable {
    let type: String
    let eventId: String?
    let sender: String?
    let originServerTs: Int64?
    let content: [String: AnyCodable]?
    let stateKey: String?
    let unsigned: MatrixUnsigned?
    let redacts: String?

    var transactionId: String? { unsigned?.transactionId }

    enum CodingKeys: String, CodingKey {
        case type
        case eventId = "event_id"
        case sender
        case originServerTs = "origin_server_ts"
        case content
        case stateKey = "state_key"
        case unsigned
        case redacts
    }
}

struct MatrixUnsigned: Codable, Sendable {
    let age: Int64?
    let transactionId: String?
    /// Present on events that were deleted: their content has been stripped by the server.
    let redactedBecause: AnyCodable?
    var previousContent: [String: AnyCodable]? = nil
    var relations: [String: AnyCodable]? = nil

    enum CodingKeys: String, CodingKey {
        case age
        case transactionId = "transaction_id"
        case redactedBecause = "redacted_because"
        case previousContent = "prev_content"
        case relations = "m.relations"
    }
}

struct RoomSummary: Codable, Sendable {
    let mHeroes: [String]?
    let mJoinedMemberCount: Int?
    let mInvitedMemberCount: Int?

    enum CodingKeys: String, CodingKey {
        case mHeroes = "m.heroes"
        case mJoinedMemberCount = "m.joined_member_count"
        case mInvitedMemberCount = "m.invited_member_count"
    }
}

struct UnreadNotifications: Codable, Sendable {
    let highlightCount: Int?
    let notificationCount: Int?

    enum CodingKeys: String, CodingKey {
        case highlightCount = "highlight_count"
        case notificationCount = "notification_count"
    }
}

struct InvitedRoom: Codable, Sendable {
    let inviteState: RoomState?
    enum CodingKeys: String, CodingKey {
        case inviteState = "invite_state"
    }
}

struct LeavingRoom: Codable, Sendable {}

struct MatrixMessagesResponse: Codable, Sendable {
    let chunk: [MatrixEvent]?
    let start: String?
    let end: String?
    /// Member events of the chunk's senders (lazy-loading filter).
    let state: [MatrixEvent]?
}

struct MatrixErrorResponse: Codable, Sendable {
    let errcode: String?
    let error: String?
    let retryAfterMs: Int?

    enum CodingKeys: String, CodingKey {
        case errcode, error
        case retryAfterMs = "retry_after_ms"
    }
}

struct MatrixProfileResponse: Codable, Sendable {
    let displayname: String?
    let avatarUrl: String?

    enum CodingKeys: String, CodingKey {
        case displayname
        case avatarUrl = "avatar_url"
    }
}

struct MatrixCreateRoomResponse: Codable, Sendable {
    let roomId: String
    enum CodingKeys: String, CodingKey { case roomId = "room_id" }
}

struct MatrixUploadResponse: Codable, Sendable {
    let contentUri: String
    enum CodingKeys: String, CodingKey { case contentUri = "content_uri" }
}

struct MatrixJoinResponse: Codable, Sendable {
    let roomId: String
    enum CodingKeys: String, CodingKey { case roomId = "room_id" }
}

struct MatrixPresenceResponse: Codable, Sendable {
    let presence: String?
    let lastActiveAgo: Int64?
    let statusMsg: String?
    let currentlyActive: Bool?

    enum CodingKeys: String, CodingKey {
        case presence
        case lastActiveAgo = "last_active_ago"
        case statusMsg = "status_msg"
        case currentlyActive = "currently_active"
    }
}

struct MatrixUserSearchResponse: Codable, Sendable {
    let results: [MatrixUserResult]?
    let limited: Bool?
}

struct MatrixUserResult: Codable, Sendable {
    let userId: String
    let displayName: String?
    let avatarUrl: String?

    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
        case displayName = "display_name"
        case avatarUrl = "avatar_url"
    }
}

struct MatrixPublicRoomsResponse: Codable, Sendable {
    let chunk: [MatrixPublicRoom]?
    let nextBatch: String?
    let totalRoomCountEstimate: Int?

    enum CodingKeys: String, CodingKey {
        case chunk
        case nextBatch = "next_batch"
        case totalRoomCountEstimate = "total_room_count_estimate"
    }
}

struct MatrixPublicRoom: Codable, Sendable {
    let roomId: String
    let name: String?
    let topic: String?
    let numJoinedMembers: Int?
    let avatarUrl: String?
    let canonicalAlias: String?
    /// "m.space" for spaces, absent for ordinary rooms.
    let roomType: String?

    enum CodingKeys: String, CodingKey {
        case roomId = "room_id"
        case name, topic
        case numJoinedMembers = "num_joined_members"
        case avatarUrl = "avatar_url"
        case canonicalAlias = "canonical_alias"
        case roomType = "room_type"
    }
}

struct MatrixMembersResponse: Codable, Sendable {
    let chunk: [MatrixEvent]?
}

struct MatrixSendResponse: Codable, Sendable {
    let eventId: String
    enum CodingKeys: String, CodingKey { case eventId = "event_id" }
}

struct MatrixWhoamiResponse: Codable, Sendable {
    let userId: String
    let deviceId: String?

    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
        case deviceId = "device_id"
    }
}

// MARK: - AnyCodable

struct AnyCodable: Codable, @unchecked Sendable {
    let value: Any

    init(_ value: Any) { self.value = value }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let str = try? container.decode(String.self) { value = str }
        else if let int = try? container.decode(Int.self) { value = int }
        else if let double = try? container.decode(Double.self) { value = double }
        else if let bool = try? container.decode(Bool.self) { value = bool }
        else if let dict = try? container.decode([String: AnyCodable].self) { value = dict }
        else if let arr = try? container.decode([AnyCodable].self) { value = arr }
        else { value = NSNull() }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        if let str = value as? String { try container.encode(str) }
        else if let int = value as? Int { try container.encode(int) }
        else if let double = value as? Double { try container.encode(double) }
        else if let bool = value as? Bool { try container.encode(bool) }
        else if let dict = value as? [String: AnyCodable] { try container.encode(dict) }
        else if let arr = value as? [AnyCodable] { try container.encode(arr) }
        else { try container.encodeNil() }
    }

    var stringValue: String? { value as? String }
    var intValue: Int? { value as? Int }
    var boolValue: Bool? { value as? Bool }
    var dictValue: [String: AnyCodable]? { value as? [String: AnyCodable] }
    var arrayValue: [AnyCodable]? { value as? [AnyCodable] }

    /// Back to plain JSON (for re-sending a state event we received).
    var jsonObject: Any {
        if let dict = value as? [String: AnyCodable] { return dict.mapValues(\.jsonObject) }
        if let array = value as? [AnyCodable] { return array.map(\.jsonObject) }
        return value
    }
}

// MARK: - MatrixClient

@MainActor
class MatrixClient {
    private let session: URLSession
    // Mirrored for MediaLoader, which fetches authenticated media off the main actor.
    private var homeserverURL: URL {
        didSet { MediaCredentials.shared.setHomeserver(homeserverURL) }
    }
    private var accessToken: String? {
        didSet { MediaCredentials.shared.setToken(accessToken) }
    }

    enum MatrixError: LocalizedError {
        case invalidURL
        case httpError(statusCode: Int, errcode: String?, message: String, retryAfterMs: Int?)
        case decodingError(Error)
        case notAuthenticated
        case networkError(Error)
        case registrationIncomplete(session: String, flows: [MatrixAuthFlow])

        var errcode: String? {
            if case .httpError(_, let errcode, _, _) = self { return errcode }
            return nil
        }

        var isUnknownToken: Bool { errcode == "M_UNKNOWN_TOKEN" }

        var errorDescription: String? {
            switch self {
            case .invalidURL: return "URL invalide"
            case .httpError(let code, _, let msg, _): return "Erreur \(code) : \(msg)"
            case .decodingError(let err): return "Erreur de décodage : \(err.localizedDescription)"
            case .notAuthenticated: return "Non authentifié"
            case .networkError(let err): return "Erreur réseau : \(err.localizedDescription)"
            case .registrationIncomplete: return "Inscription en cours (étapes supplémentaires requises)"
            }
        }
    }

    init(homeserver: String = "matrix.org") {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 60
        self.session = URLSession(configuration: config)
        self.homeserverURL = Self.normalizedHomeserverURL(from: homeserver)
    }

    func setHomeserver(_ homeserver: String) {
        self.homeserverURL = Self.normalizedHomeserverURL(from: homeserver)
    }

    func setAccessToken(_ token: String) {
        self.accessToken = token
    }

    var currentHomeserverURL: URL { homeserverURL }

    private static let fallbackHomeserverURL = URL(string: "https://matrix.org")!

    private static func normalizedHomeserverURL(from input: String) -> URL {
        var host = input.trimmingCharacters(in: .whitespacesAndNewlines)
        for scheme in ["https://", "http://"] where host.lowercased().hasPrefix(scheme) {
            host = String(host.dropFirst(scheme.count))
        }
        if let slash = host.firstIndex(of: "/") {
            host = String(host[..<slash])
        }
        host = host.lowercased()
        guard !host.isEmpty, let url = URL(string: "https://\(host)"), url.host != nil else {
            return Self.fallbackHomeserverURL
        }
        return url
    }

    // MARK: - Login

    func login(username: String, password: String) async throws -> MatrixLoginResponse {
        let body: [String: Any] = [
            "type": "m.login.password",
            "identifier": ["type": "m.id.user", "user": username],
            "password": password
        ]
        return try await post("/_matrix/client/v3/login", body: body, authenticated: false)
    }

    // MARK: - Login with Token (SSO)

    func loginWithToken(_ token: String) async throws -> MatrixLoginResponse {
        let body: [String: Any] = [
            "type": "m.login.token",
            "token": token
        ]
        return try await post("/_matrix/client/v3/login", body: body, authenticated: false)
    }

    // MARK: - SSO Redirect URL

    func ssoRedirectURL(idpId: String, redirectURL: String) -> URL? {
        let path = "/_matrix/client/v3/login/sso/redirect/\(pathEscape(idpId))"
        return try? buildURL(encodedPath: path, query: [URLQueryItem(name: "redirectUrl", value: redirectURL)])
    }

    // MARK: - Get SSO Providers

    struct SSOProvider: Sendable {
        let id: String
        let name: String
    }

    func getSSOProviders() async throws -> [SSOProvider] {
        let url = try buildURL(encodedPath: "/_matrix/client/v3/login")
        let (data, response) = try await performRequest(URLRequest(url: url))
        try validateResponse(response, data: data)

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let flows = json["flows"] as? [[String: Any]] else { return [] }

        for flow in flows {
            if let type = flow["type"] as? String, type == "m.login.sso",
               let providers = flow["identity_providers"] as? [[String: Any]] {
                return providers.compactMap { provider in
                    guard let id = provider["id"] as? String,
                          let name = provider["name"] as? String else { return nil }
                    return SSOProvider(id: id, name: name)
                }
            }
        }
        return []
    }

    // MARK: - Register

    func register(username: String, password: String, uiaaSession: String? = nil) async throws -> MatrixLoginResponse {
        var body: [String: Any] = [
            "username": username,
            "password": password,
            "inhibit_login": false
        ]

        if let uiaaSession {
            body["auth"] = [
                "type": "m.login.dummy",
                "session": uiaaSession
            ] as [String: Any]
        }

        let url = try buildURL(encodedPath: "/_matrix/client/v3/register")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await performRequest(request)

        // 401 = UIAA flow. Un seul retry m.login.dummy ; tout autre stage (recaptcha, terms…) est impossible in-app.
        if let httpResp = response as? HTTPURLResponse, httpResp.statusCode == 401 {
            let regResp: MatrixRegisterResponse = try decodeResponse(data)
            let hasDummyOnlyFlow = (regResp.flows ?? []).contains { $0.stages == ["m.login.dummy"] }
            if uiaaSession == nil, hasDummyOnlyFlow, let sess = regResp.session {
                return try await register(username: username, password: password, uiaaSession: sess)
            }
            throw MatrixError.httpError(
                statusCode: 401,
                errcode: nil,
                message: "Ce serveur exige une inscription via son site web (captcha ou conditions d'utilisation).",
                retryAfterMs: nil
            )
        }

        try validateResponse(response, data: data)
        let regResp: MatrixRegisterResponse = try decodeResponse(data)

        guard let token = regResp.accessToken, let userId = regResp.userId, let deviceId = regResp.deviceId else {
            throw MatrixError.httpError(statusCode: 400, errcode: nil, message: "Réponse d'inscription incomplète", retryAfterMs: nil)
        }

        self.accessToken = token
        return MatrixLoginResponse(
            accessToken: token,
            userId: userId,
            deviceId: deviceId,
            homeServer: nil
        )
    }

    // MARK: - Whoami

    func whoami() async throws -> String {
        let response: MatrixWhoamiResponse = try await get("/_matrix/client/v3/account/whoami")
        return response.userId
    }

    // MARK: - Logout

    func logout() async throws {
        try await postNoResponse("/_matrix/client/v3/logout", body: [:])
        accessToken = nil
    }

    // MARK: - Sync

    func sync(since: String? = nil, timeout: Int = 30000) async throws -> MatrixSyncResponse {
        guard let token = accessToken else { throw MatrixError.notAuthenticated }

        var queryItems = [URLQueryItem(name: "timeout", value: String(timeout)),
                          URLQueryItem(name: "set_presence", value: accountSyncPresence)]
        if let since {
            queryItems.append(URLQueryItem(name: "since", value: since))
        }
        queryItems.append(URLQueryItem(name: "filter", value: Self.syncFilterJSON))

        let url = try buildURL(encodedPath: "/_matrix/client/v3/sync", query: queryItems)
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = TimeInterval(timeout / 1000 + 30)

        let (data, response) = try await performRequest(request)
        try validateResponse(response, data: data)
        return try decodeResponse(data)
    }

    // MARK: - Send Message

    /// Text message with its HTML (`formatted_body`) and intentional mentions (`m.mentions`).
    @discardableResult
    func sendMessage(roomId: String, body: String, replyToEventId: String? = nil, threadRootEventId: String? = nil, txnId: String? = nil,
                     formattedBody: String? = nil, mentionUserIds: [String] = [], mentionsRoom: Bool = false) async throws -> MatrixSendResponse {
        let content = MatrixMessageContent.text(
            body: body, formattedBody: formattedBody, mentionUserIds: mentionUserIds, mentionsRoom: mentionsRoom,
            replyToEventId: replyToEventId, threadRootEventId: threadRootEventId
        )
        return try await sendRoomMessage(roomId: roomId, content: content, txnId: txnId ?? UUID().uuidString)
    }

    // MARK: - Edit Message

    @discardableResult
    func editMessage(roomId: String, eventId: String, newBody: String, formattedBody: String? = nil,
                     mentionUserIds: [String] = [], mentionsRoom: Bool = false,
                     previousMentionUserIds: [String] = []) async throws -> MatrixSendResponse {
        let content = MatrixMessageContent.edit(
            eventId: eventId, body: newBody, formattedBody: formattedBody, mentionUserIds: mentionUserIds,
            mentionsRoom: mentionsRoom, previousMentionUserIds: previousMentionUserIds
        )
        return try await sendRoomMessage(roomId: roomId, content: content, txnId: UUID().uuidString)
    }

    // MARK: - Redact (Delete) Event

    @discardableResult
    func redactEvent(roomId: String, eventId: String, reason: String? = nil) async throws -> MatrixSendResponse {
        let txnId = UUID().uuidString
        let path = "/_matrix/client/v3/rooms/\(pathEscape(roomId))/redact/\(pathEscape(eventId))/\(pathEscape(txnId))"

        var body: [String: Any] = [:]
        if let reason { body["reason"] = reason }

        return try await putJSON(path, body: body)
    }

    // MARK: - Send Reaction

    @discardableResult
    func sendReaction(roomId: String, eventId: String, emoji: String) async throws -> MatrixSendResponse {
        let txnId = UUID().uuidString
        let path = "/_matrix/client/v3/rooms/\(pathEscape(roomId))/send/m.reaction/\(pathEscape(txnId))"

        let content: [String: Any] = [
            "m.relates_to": [
                "rel_type": "m.annotation",
                "event_id": eventId,
                "key": emoji
            ]
        ]

        return try await putJSON(path, body: content)
    }

    // MARK: - Typing Indicator

    func sendTyping(roomId: String, userId: String, typing: Bool, timeout: Int = 30000) async throws {
        let path = "/_matrix/client/v3/rooms/\(pathEscape(roomId))/typing/\(pathEscape(userId))"

        var body: [String: Any] = ["typing": typing]
        if typing { body["timeout"] = timeout }

        try await putJSONNoResponse(path, body: body)
    }

    // MARK: - Read Receipt

    func sendReadReceipt(roomId: String, eventId: String) async throws {
        let path = "/_matrix/client/v3/rooms/\(pathEscape(roomId))/receipt/m.read/\(pathEscape(eventId))"
        try await postNoResponse(path, body: [:])
    }

    // MARK: - Read Markers (fully read)

    func setReadMarker(roomId: String, fullyRead: String, read: String? = nil) async throws {
        let path = "/_matrix/client/v3/rooms/\(pathEscape(roomId))/read_markers"

        var body: [String: Any] = ["m.fully_read": fullyRead]
        if let read { body["m.read"] = read }

        try await postNoResponse(path, body: body)
    }

    // MARK: - Presence

    func setPresence(userId: String, presence: String, statusMsg: String? = nil) async throws {
        let path = "/_matrix/client/v3/presence/\(pathEscape(userId))/status"

        var body: [String: Any] = ["presence": presence]
        if let statusMsg { body["status_msg"] = statusMsg }

        try await putJSONNoResponse(path, body: body)
    }

    func getPresence(userId: String) async throws -> MatrixPresenceResponse {
        return try await get("/_matrix/client/v3/presence/\(pathEscape(userId))/status")
    }

    // MARK: - Media Upload

    func uploadMedia(data: Data, filename: String, contentType: String) async throws -> MatrixUploadResponse {
        guard let token = accessToken else { throw MatrixError.notAuthenticated }

        let url = try buildURL(
            encodedPath: "/_matrix/media/v3/upload",
            query: [URLQueryItem(name: "filename", value: filename)]
        )
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(contentType, forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.httpBody = data

        let (responseData, response) = try await performRequest(request)
        try validateResponse(response, data: responseData)
        return try decodeResponse(responseData)
    }

    // MARK: - Resolve mxc:// URL

    /// mxc://server/mediaId → the authenticated v1 route (`/_matrix/client/v1/media/download|thumbnail/…`).
    /// These URLs need the Bearer token: load them through `MediaLoader` / `AuthenticatedImage`,
    /// which also falls back to the legacy v3 route on servers without v1 media.
    func resolveMediaURL(_ mxcUrl: String, width: Int? = nil, height: Int? = nil, method: String = "crop") -> URL? {
        if let width, let height {
            return MatrixMediaEndpoint.thumbnailURL(for: mxcUrl, homeserver: homeserverURL, width: width, height: height, method: method)
        }
        return MatrixMediaEndpoint.downloadURL(for: mxcUrl, homeserver: homeserverURL)
    }

    // MARK: - Create Room

    func createRoom(
        name: String? = nil,
        topic: String? = nil,
        isDirect: Bool = false,
        inviteUserIds: [String] = [],
        preset: String? = nil,
        roomType: String? = nil,
        initialState: [[String: Any]]? = nil
    ) async throws -> MatrixCreateRoomResponse {
        var body: [String: Any] = [:]
        if let name { body["name"] = name }
        if let topic { body["topic"] = topic }
        if isDirect { body["is_direct"] = true }
        if !inviteUserIds.isEmpty { body["invite"] = inviteUserIds }
        if let preset { body["preset"] = preset }
        if let roomType {
            body["creation_content"] = ["type": roomType]
        }
        if let initialState { body["initial_state"] = initialState }

        return try await post("/_matrix/client/v3/createRoom", body: body)
    }

    // MARK: - Join Room

    func joinRoom(_ roomIdOrAlias: String) async throws -> MatrixJoinResponse {
        return try await post("/_matrix/client/v3/join/\(pathEscape(roomIdOrAlias))", body: [:])
    }

    // MARK: - Invite User

    func inviteUser(roomId: String, userId: String) async throws {
        try await postNoResponse("/_matrix/client/v3/rooms/\(pathEscape(roomId))/invite", body: ["user_id": userId])
    }

    // MARK: - Leave Room

    func leaveRoom(_ roomId: String) async throws {
        try await postNoResponse("/_matrix/client/v3/rooms/\(pathEscape(roomId))/leave", body: [:])
    }

    // MARK: - Kick User

    func kickUser(roomId: String, userId: String, reason: String? = nil) async throws {
        var body: [String: Any] = ["user_id": userId]
        if let reason { body["reason"] = reason }
        try await postNoResponse("/_matrix/client/v3/rooms/\(pathEscape(roomId))/kick", body: body)
    }

    // MARK: - Ban User

    func banUser(roomId: String, userId: String, reason: String? = nil) async throws {
        var body: [String: Any] = ["user_id": userId]
        if let reason { body["reason"] = reason }
        try await postNoResponse("/_matrix/client/v3/rooms/\(pathEscape(roomId))/ban", body: body)
    }

    // MARK: - Unban User

    func unbanUser(roomId: String, userId: String) async throws {
        try await postNoResponse("/_matrix/client/v3/rooms/\(pathEscape(roomId))/unban", body: ["user_id": userId])
    }

    // MARK: - Profile

    func getProfile(userId: String) async throws -> MatrixProfileResponse {
        return try await get("/_matrix/client/v3/profile/\(pathEscape(userId))")
    }

    func setDisplayName(userId: String, displayName: String) async throws {
        try await putJSONNoResponse("/_matrix/client/v3/profile/\(pathEscape(userId))/displayname", body: ["displayname": displayName])
    }

    func setAvatarUrl(userId: String, avatarUrl: String) async throws {
        try await putJSONNoResponse("/_matrix/client/v3/profile/\(pathEscape(userId))/avatar_url", body: ["avatar_url": avatarUrl])
    }

    // MARK: - Direct Rooms (m.direct account data)

    func getDirectRooms(userId: String) async throws -> [String: [String]] {
        let path = "/_matrix/client/v3/user/\(pathEscape(userId))/account_data/m.direct"
        do {
            return try await get(path)
        } catch MatrixError.httpError(let statusCode, _, _, _) where statusCode == 404 {
            return [:]
        }
    }

    func setIgnoredUsers(userId: String, ignored: [String]) async throws {
        let path = "/_matrix/client/v3/user/\(pathEscape(userId))/account_data/m.ignored_user_list"
        let users = Dictionary(uniqueKeysWithValues: ignored.map { ($0, [String: Any]()) })
        try await putJSONNoResponse(path, body: ["ignored_users": users])
    }

    func setDirectRooms(userId: String, directMap: [String: [String]]) async throws {
        let path = "/_matrix/client/v3/user/\(pathEscape(userId))/account_data/m.direct"
        try await putJSONNoResponse(path, body: directMap)
    }

    // MARK: - User Directory Search

    func searchUsers(term: String, limit: Int = 20) async throws -> MatrixUserSearchResponse {
        let body: [String: Any] = ["search_term": term, "limit": limit]
        return try await post("/_matrix/client/v3/user_directory/search", body: body)
    }

    // MARK: - Public Rooms

    func getPublicRooms(limit: Int = 50, since: String? = nil, filter: String? = nil) async throws -> MatrixPublicRoomsResponse {
        var body: [String: Any] = ["limit": limit]
        if let since { body["since"] = since }
        if let filter { body["filter"] = ["generic_search_term": filter] }
        return try await post("/_matrix/client/v3/publicRooms", body: body)
    }

    // MARK: - Room Members

    func getRoomMembers(roomId: String) async throws -> MatrixMembersResponse {
        return try await get("/_matrix/client/v3/rooms/\(pathEscape(roomId))/members")
    }

    // MARK: - Room Messages (history)

    func roomMessages(roomId: String, from: String? = nil, limit: Int = 50, direction: String = "b") async throws -> MatrixMessagesResponse {
        guard let token = accessToken else { throw MatrixError.notAuthenticated }

        var queryItems = [
            URLQueryItem(name: "dir", value: direction),
            URLQueryItem(name: "limit", value: String(limit)),
            // Sync lazy-loads members: ask for the senders of this page in `state`.
            URLQueryItem(name: "filter", value: #"{"lazy_load_members":true}"#)
        ]
        if let from { queryItems.append(URLQueryItem(name: "from", value: from)) }

        let url = try buildURL(encodedPath: "/_matrix/client/v3/rooms/\(pathEscape(roomId))/messages", query: queryItems)
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await performRequest(request)
        try validateResponse(response, data: data)
        return try decodeResponse(data)
    }

    // MARK: - Room State

    func getRoomState(roomId: String) async throws -> [MatrixEvent] {
        return try await get("/_matrix/client/v3/rooms/\(pathEscape(roomId))/state")
    }

    // MARK: - Set Room Name / Topic

    func setRoomName(roomId: String, name: String) async throws {
        try await putJSONNoResponse("/_matrix/client/v3/rooms/\(pathEscape(roomId))/state/m.room.name", body: ["name": name])
    }

    func setStateEvent(roomId: String, type: String, stateKey: String = "", content: [String: Any]) async throws {
        try await putJSONNoResponse("/_matrix/client/v3/rooms/\(pathEscape(roomId))/state/\(pathEscape(type))/\(pathEscape(stateKey))", body: content)
    }

    func setPinnedEvents(roomId: String, eventIds: [String]) async throws {
        try await putJSONNoResponse("/_matrix/client/v3/rooms/\(pathEscape(roomId))/state/m.room.pinned_events", body: ["pinned": eventIds])
    }

    func setRoomTopic(roomId: String, topic: String) async throws {
        try await putJSONNoResponse("/_matrix/client/v3/rooms/\(pathEscape(roomId))/state/m.room.topic", body: ["topic": topic])
    }

    // MARK: - Space Children

    func addSpaceChild(spaceRoomId: String, childRoomId: String, order: String? = nil) async throws {
        let path = "/_matrix/client/v3/rooms/\(pathEscape(spaceRoomId))/state/m.space.child/\(pathEscape(childRoomId))"

        var body: [String: Any] = ["via": [homeserverURL.host ?? ""]]
        if let order { body["order"] = order }

        try await putJSONNoResponse(path, body: body)
    }

    func removeSpaceChild(spaceRoomId: String, childRoomId: String) async throws {
        let path = "/_matrix/client/v3/rooms/\(pathEscape(spaceRoomId))/state/m.space.child/\(pathEscape(childRoomId))"
        try await putJSONNoResponse(path, body: [:])
    }

    // MARK: - URL Building

    // Dynamic path segments are percent-encoded ONCE here; buildURL uses percentEncodedPath
    // so nothing re-escapes the % (appendingPathComponent would, turning %23 into %2523).
    private static let pathComponentAllowed: CharacterSet = {
        var set = CharacterSet.urlPathAllowed
        set.remove(charactersIn: "/")
        return set
    }()

    private func pathEscape(_ component: String) -> String {
        component.addingPercentEncoding(withAllowedCharacters: Self.pathComponentAllowed) ?? component
    }

    private func buildURL(encodedPath: String, query: [URLQueryItem]? = nil) throws -> URL {
        guard var components = URLComponents(url: homeserverURL, resolvingAgainstBaseURL: false) else {
            throw MatrixError.invalidURL
        }
        components.percentEncodedPath = encodedPath
        if let query { components.queryItems = query }
        guard let url = components.url else { throw MatrixError.invalidURL }
        return url
    }

    // MARK: - Generic HTTP Helpers

    /// Every JSON call goes through here. A 429 is retried after the server's `retry_after_ms`
    /// (or `Retry-After`), up to `maxRateLimitRetries` times; then the 429 reaches the caller.
    private func performRequest(_ request: URLRequest) async throws -> (Data, URLResponse) {
        var retries = 0
        while true {
            let result: (Data, URLResponse)
            do {
                result = try await session.data(for: request)
            } catch let error as MatrixError {
                throw error
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                throw MatrixError.networkError(error)
            }
            guard let http = result.1 as? HTTPURLResponse, retries < Self.maxRateLimitRetries,
                  let delay = MatrixRateLimit.retryAfter(statusCode: http.statusCode, headers: http.allHeaderFields, body: result.0),
                  delay <= MatrixRateLimit.maxHonouredDelay else { return result }
            retries += 1
            try await Task.sleep(for: .seconds(delay))
        }
    }

    private func decodeResponse<T: Decodable>(_ data: Data) throws -> T {
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw MatrixError.decodingError(error)
        }
    }

    private func get<T: Decodable>(_ path: String) async throws -> T {
        guard let token = accessToken else { throw MatrixError.notAuthenticated }

        let url = try buildURL(encodedPath: path)
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await performRequest(request)
        try validateResponse(response, data: data)
        return try decodeResponse(data)
    }

    private func post<T: Decodable>(_ path: String, body: [String: Any], authenticated: Bool = true) async throws -> T {
        let url = try buildURL(encodedPath: path)
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if authenticated {
            guard let token = accessToken else { throw MatrixError.notAuthenticated }
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await performRequest(request)
        try validateResponse(response, data: data)
        return try decodeResponse(data)
    }

    private func postNoResponse(_ path: String, body: [String: Any]) async throws {
        guard let token = accessToken else { throw MatrixError.notAuthenticated }

        let url = try buildURL(encodedPath: path)
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await performRequest(request)
        try validateResponse(response, data: data)
    }

    @discardableResult
    private func putJSON<T: Decodable>(_ path: String, body: [String: Any]) async throws -> T {
        guard let token = accessToken else { throw MatrixError.notAuthenticated }

        let url = try buildURL(encodedPath: path)
        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await performRequest(request)
        try validateResponse(response, data: data)
        return try decodeResponse(data)
    }

    private func putJSONNoResponse(_ path: String, body: [String: Any]) async throws {
        guard let token = accessToken else { throw MatrixError.notAuthenticated }

        let url = try buildURL(encodedPath: path)
        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await performRequest(request)
        try validateResponse(response, data: data)
    }

    private func validateResponse(_ response: URLResponse, data: Data) throws {
        guard let httpResponse = response as? HTTPURLResponse else { return }
        guard (200...299).contains(httpResponse.statusCode) else {
            if let errorResponse = try? JSONDecoder().decode(MatrixErrorResponse.self, from: data) {
                throw MatrixError.httpError(
                    statusCode: httpResponse.statusCode,
                    errcode: errorResponse.errcode,
                    message: errorResponse.error ?? "Erreur inconnue",
                    retryAfterMs: errorResponse.retryAfterMs
                )
            }
            throw MatrixError.httpError(statusCode: httpResponse.statusCode, errcode: nil, message: "Erreur inconnue", retryAfterMs: nil)
        }
    }

    // MARK: - Search & Inbox

    /// Server-side full-text search (`POST /search`), newest messages first.
    /// Encrypted rooms are not indexed by the homeserver, so callers should leave them out of `roomIds`.
    func search(
        term: String,
        roomIds: [String],
        senderIds: [String] = [],
        nextBatch: String? = nil,
        limit: Int = 25
    ) async throws -> MatrixSearchResponse {
        guard let token = accessToken else { throw MatrixError.notAuthenticated }

        var filter: [String: Any] = ["limit": limit]
        if !roomIds.isEmpty { filter["rooms"] = roomIds }
        if !senderIds.isEmpty { filter["senders"] = senderIds }

        let body: [String: Any] = [
            "search_categories": [
                "room_events": [
                    "search_term": term,
                    "filter": filter,
                    "order_by": "recent",
                    "event_context": ["before_limit": 0, "after_limit": 0]
                ] as [String: Any]
            ]
        ]

        var query: [URLQueryItem]?
        if let nextBatch { query = [URLQueryItem(name: "next_batch", value: nextBatch)] }

        let url = try buildURL(encodedPath: "/_matrix/client/v3/search", query: query)
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await performRequest(request)
        try validateResponse(response, data: data)
        return try decodeResponse(data)
    }

    /// Events that notified this account (`GET /notifications`); `only: "highlight"` keeps mentions and replies.
    func notifications(from: String? = nil, limit: Int = 30, only: String? = nil) async throws -> MatrixNotificationsResponse {
        guard let token = accessToken else { throw MatrixError.notAuthenticated }

        var query = [URLQueryItem(name: "limit", value: String(limit))]
        if let from { query.append(URLQueryItem(name: "from", value: from)) }
        if let only { query.append(URLQueryItem(name: "only", value: only)) }

        let url = try buildURL(encodedPath: "/_matrix/client/v3/notifications", query: query)
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await performRequest(request)
        try validateResponse(response, data: data)
        return try decodeResponse(data)
    }

    // MARK: - Notifications & push rules

    /// `GET /pushrules/` as plain JSON, to read which rooms are muted.
    func getPushRules() async throws -> Any {
        let rules: AnyCodable = try await get(PushRules.allRulesPath)
        return rules.jsonObject
    }

    /// Mute = a `room` push rule with no actions. Idempotent on the server.
    func muteRoom(_ roomId: String) async throws {
        try await putJSONNoResponse(PushRules.roomRulePath(roomId: roomId), body: ["actions": [Any]()])
    }

    /// Unmute = delete the room rule, and the override rule other clients may have created.
    /// A rule that does not exist is not an error.
    func unmuteRoom(_ roomId: String) async throws {
        try await deleteIgnoringNotFound(PushRules.roomRulePath(roomId: roomId))
        try await deleteIgnoringNotFound(PushRules.overrideRulePath(roomId: roomId))
    }

    /// `GET /devices`: the sessions of this account.
    func getDevices() async throws -> [MatrixDevice] {
        let response: MatrixDevicesResponse = try await get("/_matrix/client/v3/devices")
        return response.devices ?? []
    }

    /// The device id of the access token in use (`/account/whoami`).
    func currentDeviceId() async throws -> String? {
        let response: MatrixWhoamiResponse = try await get("/_matrix/client/v3/account/whoami")
        return response.deviceId
    }

    /// Read receipt only this account's own devices can see (`m.read.private`).
    func sendPrivateReadReceipt(roomId: String, eventId: String) async throws {
        let path = "/_matrix/client/v3/rooms/\(pathEscape(roomId))/receipt/m.read.private/\(pathEscape(eventId))"
        try await postNoResponse(path, body: [:])
    }

    /// Moves the "fully read" marker without publishing a public read receipt.
    func setPrivateReadMarker(roomId: String, fullyRead: String) async throws {
        let path = "/_matrix/client/v3/rooms/\(pathEscape(roomId))/read_markers"
        try await postNoResponse(path, body: ["m.fully_read": fullyRead, "m.read.private": fullyRead])
    }

    private func deleteIgnoringNotFound(_ path: String) async throws {
        guard let token = accessToken else { throw MatrixError.notAuthenticated }

        let url = try buildURL(encodedPath: path)
        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await performRequest(request)
        do {
            try validateResponse(response, data: data)
        } catch let error as MatrixError {
            if case .httpError(let status, let errcode, _, _) = error, status == 404 || errcode == "M_NOT_FOUND" { return }
            throw error
        }
    }

    // MARK: - Messaging pipeline

    /// Sync filter: 30 timeline events per room (the disk cache holds older ones), members lazy-loaded,
    /// per-thread unread counts. Presence stays on (federation is off, so it is all local).
    static let syncFilterJSON = #"{"room":{"timeline":{"limit":30,"unread_thread_notifications":true},"state":{"lazy_load_members":true}},"presence":{"types":["m.presence"]}}"#
    static let maxRateLimitRetries = 3

    /// `PUT /rooms/{roomId}/send/m.room.message/{txnId}` — the txnId makes a retry idempotent.
    @discardableResult
    func sendRoomMessage(roomId: String, content: [String: Any], txnId: String) async throws -> MatrixSendResponse {
        let path = "/_matrix/client/v3/rooms/\(pathEscape(roomId))/send/m.room.message/\(pathEscape(txnId))"
        return try await putJSON(path, body: content)
    }

    /// Streams a file to `POST /_matrix/media/v3/upload` with progress (0…1). Cancelling the calling
    /// task cancels the upload. A 429 is retried after `retry_after_ms`.
    func uploadMedia(fileURL: URL, filename: String, contentType: String,
                     progress: (@Sendable (Double) -> Void)? = nil) async throws -> MatrixUploadResponse {
        guard let token = accessToken else { throw MatrixError.notAuthenticated }
        let url = try buildURL(
            encodedPath: "/_matrix/media/v3/upload",
            query: [URLQueryItem(name: "filename", value: filename)]
        )
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(contentType, forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 300

        var retries = 0
        while true {
            let delegate = progress.map(UploadProgressDelegate.init)
            let data: Data
            let response: URLResponse
            do {
                (data, response) = try await session.upload(for: request, fromFile: fileURL, delegate: delegate)
            } catch let error as URLError where error.code == .cancelled {
                throw CancellationError()
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                throw MatrixError.networkError(error)
            }
            if let http = response as? HTTPURLResponse, retries < Self.maxRateLimitRetries,
               let delay = MatrixRateLimit.retryAfter(statusCode: http.statusCode, headers: http.allHeaderFields, body: data),
               delay <= MatrixRateLimit.maxHonouredDelay {
                retries += 1
                try await Task.sleep(for: .seconds(delay))
                continue
            }
            try validateResponse(response, data: data)
            return try decodeResponse(data)
        }
    }

    /// The server's upload limit (`m.upload.size`), v1 route first then legacy v3; nil if unknown.
    func mediaUploadLimit() async -> Int? {
        for path in ["/_matrix/client/v1/media/config", "/_matrix/media/v3/config"] {
            if let config: MatrixMediaConfigResponse = try? await get(path) {
                return config.uploadSize
            }
        }
        return nil
    }

    /// Errors that mean "the server is not reachable right now" (offline, Funnel or Studio down):
    /// the message stays queued instead of being marked as failed.
    static func isTransient(_ error: Error) -> Bool {
        switch error {
        case MatrixError.networkError(let underlying):
            guard let urlError = underlying as? URLError else { return true }
            let transient: Set<URLError.Code> = [
                .notConnectedToInternet, .networkConnectionLost, .cannotConnectToHost, .cannotFindHost,
                .timedOut, .dnsLookupFailed, .internationalRoamingOff, .dataNotAllowed, .callIsActive,
                .secureConnectionFailed, .resourceUnavailable
            ]
            return transient.contains(urlError.code)
        case MatrixError.httpError(let statusCode, _, _, _):
            return [502, 503, 504].contains(statusCode)
        default:
            return false
        }
    }
    // MARK: - Account features

    private var accountSyncPresence = "online"

    func setSyncPresence(_ presence: String) { accountSyncPresence = presence }

    func supportsExtendedProfiles() async throws -> Bool {
        let response: AccountServerVersions = try await get("/_matrix/client/versions")
        return response.supportsExtendedProfiles
    }

    func getExtendedProfile(userId: String) async throws -> ExtendedProfile {
        let fields: [String: AnyCodable] = try await get("/_matrix/client/v3/profile/\(pathEscape(userId))")
        return ExtendedProfile(bio: fields["mood.bio"]?.stringValue ?? "",
                               pronouns: fields["mood.pronouns"]?.stringValue ?? "")
    }

    func setProfileText(userId: String, field: String, value: String) async throws {
        try await putJSONNoResponse("/_matrix/client/v3/profile/\(pathEscape(userId))/\(pathEscape(field))", body: [field: value])
    }

    // MARK: - Messaging & servers UI

    func createMessagingAlias(_ alias: String, roomId: String) async throws {
        try await putJSONNoResponse("/_matrix/client/v3/directory/room/\(pathEscape(alias))", body: ["room_id": roomId])
    }

    func createMessagingChannel(spaceId: String, name: String, topic: String, isPrivate: Bool, powerLevels: [String: Any]) async throws -> MatrixCreateRoomResponse {
        let rules: [String: Any] = isPrivate ? ["join_rule": "invite"] : MessagingServerPolicy.restricted(spaceId: spaceId)
        return try await post("/_matrix/client/v3/createRoom", body: [
            "name": name, "topic": topic, "preset": "private_chat", "room_version": "10",
            "power_level_content_override": powerLevels,
            "initial_state": [
                ["type": "m.room.join_rules", "state_key": "", "content": rules],
                ["type": "m.room.history_visibility", "state_key": "", "content": ["history_visibility": "shared"]],
                ["type": "m.space.parent", "state_key": spaceId, "content": ["via": ["mood.local"], "canonical": true]]
            ]
        ])
    }

    func messagingContext(roomId: String, eventId: String) async throws -> MessagingContext {
        try await get("/_matrix/client/v3/rooms/\(pathEscape(roomId))/context/\(pathEscape(eventId))")
    }

    // MARK: - Finish basics

    /// Filter membership events, then retain our own; paging avoids years of chat messages.
    func directMembershipHistory(roomId: String, userId: String) async throws -> [MatrixEvent] {
        var from: String?
        var seen: Set<String> = []
        var evidence: [MatrixEvent] = []
        while !Task.isCancelled {
            let filter = try JSONSerialization.data(withJSONObject: ["types": ["m.room.member"]])
            var query = [URLQueryItem(name: "dir", value: "b"), URLQueryItem(name: "limit", value: "100"),
                         URLQueryItem(name: "filter", value: String(decoding: filter, as: UTF8.self))]
            if let from { query.append(URLQueryItem(name: "from", value: from)) }
            guard let token = accessToken else { throw MatrixError.notAuthenticated }
            let url = try buildURL(encodedPath: "/_matrix/client/v3/rooms/\(pathEscape(roomId))/messages", query: query)
            var request = URLRequest(url: url)
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            let (data, response) = try await performRequest(request)
            try validateResponse(response, data: data)
            let page: MatrixMessagesResponse = try decodeResponse(data)
            evidence += (page.chunk ?? []).filter { $0.stateKey == userId }
            if evidence.contains(where: { $0.content?["is_direct"]?.boolValue == true }) { return evidence }
            guard let next = page.end, next != from, seen.insert(next).inserted else { break }
            from = next
        }
        return evidence
    }

    // MARK: - Media & composer (N2)

    func mediaEvent(roomId: String, eventId: String) async throws -> MatrixEvent {
        try await get("/_matrix/client/v3/rooms/\(pathEscape(roomId))/event/\(pathEscape(eventId))")
    }


    func mediaLinkPreview(_ target: URL) async throws -> MediaLinkPreview {
        let url = try buildURL(encodedPath: "/_matrix/client/v1/media/preview_url",
                               query: [URLQueryItem(name: "url", value: target.absoluteString)])
        var request = URLRequest(url: url)
        request.timeoutInterval = 18
        if let accessToken { request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization") }
        let (data, response) = try await performRequest(request)
        try validateResponse(response, data: data)
        return try JSONDecoder().decode(MediaLinkPreview.self, from: data)
    }

    // MARK: - Conversation (N1)

    /// Injectable transport for deterministic contract tests; production uses the standard initializer.
    init(homeserver: String, conversationSession: URLSession) {
        self.session = conversationSession
        self.homeserverURL = Self.normalizedHomeserverURL(from: homeserver)
    }

    func conversationThreads(roomId: String, from: String? = nil) async throws -> ConversationThreadPage {
        guard let token = accessToken else { throw MatrixError.notAuthenticated }
        var query = [URLQueryItem(name: "include", value: "all"), URLQueryItem(name: "limit", value: "100")]
        if let from { query.append(URLQueryItem(name: "from", value: from)) }
        let url = try buildURL(encodedPath: "/_matrix/client/v1/rooms/\(pathEscape(roomId))/threads", query: query)
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await performRequest(request)
        try validateResponse(response, data: data)
        return try decodeResponse(data)
    }

    func conversationMarkedUnread(userId: String, roomId: String, unread: Bool, legacy: Bool = false) async throws {
        let type = legacy ? "com.famedly.marked_unread" : "m.marked_unread"
        try await putJSONNoResponse("/_matrix/client/v3/user/\(pathEscape(userId))/rooms/\(pathEscape(roomId))/account_data/\(type)", body: ["unread": unread])
    }

    func conversationThreadRead(roomId: String, root: String, eventId: String, isPrivate: Bool) async throws {
        let receipt = isPrivate ? "m.read.private" : "m.read"
        try await postNoResponse("/_matrix/client/v3/rooms/\(pathEscape(roomId))/receipt/\(receipt)/\(pathEscape(eventId))", body: ["thread_id": root])
    }

}


struct MessagingContext: Decodable {
    let event: MatrixEvent?
    let eventsBefore: [MatrixEvent]?
    let eventsAfter: [MatrixEvent]?
    let state: [MatrixEvent]?
    enum CodingKeys: String, CodingKey {
        case event, state
        case eventsBefore = "events_before", eventsAfter = "events_after"
    }
}

struct ConversationThreadPage: Decodable {
    let chunk: [MatrixEvent]
    let nextBatch: String?
    enum CodingKeys: String, CodingKey { case chunk; case nextBatch = "next_batch" }
}
