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
    let accountData: AccountData?
    let ephemeral: RoomEphemeral?

    enum CodingKeys: String, CodingKey {
        case timeline, state, summary, ephemeral
        case unreadNotifications = "unread_notifications"
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

    enum CodingKeys: String, CodingKey {
        case age
        case transactionId = "transaction_id"
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
}

struct MatrixErrorResponse: Codable, Sendable {
    let errcode: String
    let error: String
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

    enum CodingKeys: String, CodingKey {
        case roomId = "room_id"
        case name, topic
        case numJoinedMembers = "num_joined_members"
        case avatarUrl = "avatar_url"
    }
}

struct MatrixMembersResponse: Codable, Sendable {
    let chunk: [MatrixEvent]?
}

struct MatrixSendResponse: Codable, Sendable {
    let eventId: String
    enum CodingKeys: String, CodingKey { case eventId = "event_id" }
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
}

// MARK: - MatrixClient

@MainActor
class MatrixClient {
    private let session: URLSession
    private var homeserverURL: URL
    private var accessToken: String?

    enum MatrixError: LocalizedError {
        case invalidURL
        case httpError(Int, String)
        case decodingError(Error)
        case notAuthenticated
        case networkError(Error)
        case registrationIncomplete(session: String, flows: [MatrixAuthFlow])

        var errorDescription: String? {
            switch self {
            case .invalidURL: return "URL invalide"
            case .httpError(let code, let msg): return "Erreur \(code) : \(msg)"
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
        self.homeserverURL = URL(string: "https://\(homeserver)")!
    }

    func setHomeserver(_ homeserver: String) {
        self.homeserverURL = URL(string: "https://\(homeserver)")!
    }

    func setAccessToken(_ token: String) {
        self.accessToken = token
    }

    var currentHomeserverURL: URL { homeserverURL }

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
        let encodedIdp = idpId.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? idpId
        let path = "/_matrix/client/v3/login/sso/redirect/\(encodedIdp)"
        var components = URLComponents(url: homeserverURL.appendingPathComponent(path), resolvingAgainstBaseURL: false)
        components?.queryItems = [URLQueryItem(name: "redirectUrl", value: redirectURL)]
        return components?.url
    }

    // MARK: - Get SSO Providers

    struct SSOProvider: Sendable {
        let id: String
        let name: String
    }

    func getSSOProviders() async throws -> [SSOProvider] {
        let url = homeserverURL.appendingPathComponent("/_matrix/client/v3/login")
        let (data, response) = try await session.data(for: URLRequest(url: url))
        try validateResponse(response, data: data)

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
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

        let url = homeserverURL.appendingPathComponent("/_matrix/client/v3/register")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await self.session.data(for: request)

        // 401 means UIAA flow — need to complete auth stages
        if let httpResp = response as? HTTPURLResponse, httpResp.statusCode == 401 {
            let regResp = try JSONDecoder().decode(MatrixRegisterResponse.self, from: data)
            if let sess = regResp.session {
                return try await register(username: username, password: password, uiaaSession: sess)
            }
            throw MatrixError.registrationIncomplete(session: "", flows: regResp.flows ?? [])
        }

        try validateResponse(response, data: data)
        let regResp = try JSONDecoder().decode(MatrixRegisterResponse.self, from: data)

        guard let token = regResp.accessToken, let userId = regResp.userId, let deviceId = regResp.deviceId else {
            throw MatrixError.httpError(400, "Réponse d'inscription incomplète")
        }

        self.accessToken = token
        return MatrixLoginResponse(
            accessToken: token,
            userId: userId,
            deviceId: deviceId,
            homeServer: nil
        )
    }

    // MARK: - Sync

    func sync(since: String? = nil, timeout: Int = 30000) async throws -> MatrixSyncResponse {
        guard let token = accessToken else { throw MatrixError.notAuthenticated }

        guard var components = URLComponents(url: homeserverURL.appendingPathComponent("/_matrix/client/v3/sync"), resolvingAgainstBaseURL: false) else {
            throw MatrixError.invalidURL
        }
        var queryItems = [URLQueryItem(name: "timeout", value: String(timeout))]
        if let since {
            queryItems.append(URLQueryItem(name: "since", value: since))
        }
        if since == nil {
            let filterJSON = #"{"room":{"timeline":{"limit":50},"state":{"lazy_load_members":true}},"presence":{"types":["m.presence"]}}"#
            queryItems.append(URLQueryItem(name: "filter", value: filterJSON))
        }
        components.queryItems = queryItems

        guard let url = components.url else { throw MatrixError.invalidURL }
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = TimeInterval(timeout / 1000 + 30)

        do {
            let (data, response) = try await session.data(for: request)
            try validateResponse(response, data: data)
            return try JSONDecoder().decode(MatrixSyncResponse.self, from: data)
        } catch let error as MatrixError { throw error }
        catch let error as DecodingError { throw MatrixError.decodingError(error) }
        catch { throw MatrixError.networkError(error) }
    }

    // MARK: - Send Message

    @discardableResult
    func sendMessage(roomId: String, body: String, replyToEventId: String? = nil, threadRootEventId: String? = nil) async throws -> MatrixSendResponse {
        guard let token = accessToken else { throw MatrixError.notAuthenticated }

        let txnId = UUID().uuidString
        let encodedRoomId = roomId.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? roomId
        let path = "/_matrix/client/v3/rooms/\(encodedRoomId)/send/m.room.message/\(txnId)"

        var content: [String: Any] = ["msgtype": "m.text", "body": body]

        // Build m.relates_to for replies and/or threads
        var relatesTo: [String: Any] = [:]
        if let threadRoot = threadRootEventId {
            relatesTo["rel_type"] = "m.thread"
            relatesTo["event_id"] = threadRoot
            relatesTo["is_falling_back"] = true
            if let replyTo = replyToEventId {
                relatesTo["m.in_reply_to"] = ["event_id": replyTo]
            }
        } else if let replyTo = replyToEventId {
            relatesTo["m.in_reply_to"] = ["event_id": replyTo]
        }
        if !relatesTo.isEmpty {
            content["m.relates_to"] = relatesTo
        }

        let url = homeserverURL.appendingPathComponent(path)
        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONSerialization.data(withJSONObject: content)

        let (data, response) = try await session.data(for: request)
        try validateResponse(response, data: data)
        return try JSONDecoder().decode(MatrixSendResponse.self, from: data)
    }

    // MARK: - Edit Message

    @discardableResult
    func editMessage(roomId: String, eventId: String, newBody: String) async throws -> MatrixSendResponse {
        let txnId = UUID().uuidString
        let encodedRoomId = roomId.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? roomId
        let path = "/_matrix/client/v3/rooms/\(encodedRoomId)/send/m.room.message/\(txnId)"

        let content: [String: Any] = [
            "msgtype": "m.text",
            "body": "* \(newBody)",
            "m.new_content": [
                "msgtype": "m.text",
                "body": newBody
            ],
            "m.relates_to": [
                "rel_type": "m.replace",
                "event_id": eventId
            ]
        ]

        return try await putJSON(path, body: content)
    }

    // MARK: - Redact (Delete) Event

    @discardableResult
    func redactEvent(roomId: String, eventId: String, reason: String? = nil) async throws -> MatrixSendResponse {
        let txnId = UUID().uuidString
        let encodedRoomId = roomId.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? roomId
        let encodedEventId = eventId.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? eventId
        let path = "/_matrix/client/v3/rooms/\(encodedRoomId)/redact/\(encodedEventId)/\(txnId)"

        var body: [String: Any] = [:]
        if let reason { body["reason"] = reason }

        return try await putJSON(path, body: body)
    }

    // MARK: - Send Reaction

    @discardableResult
    func sendReaction(roomId: String, eventId: String, emoji: String) async throws -> MatrixSendResponse {
        let txnId = UUID().uuidString
        let encodedRoomId = roomId.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? roomId
        let path = "/_matrix/client/v3/rooms/\(encodedRoomId)/send/m.reaction/\(txnId)"

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
        let encodedRoomId = roomId.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? roomId
        let encodedUserId = userId.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? userId
        let path = "/_matrix/client/v3/rooms/\(encodedRoomId)/typing/\(encodedUserId)"

        var body: [String: Any] = ["typing": typing]
        if typing { body["timeout"] = timeout }

        try await putJSONNoResponse(path, body: body)
    }

    // MARK: - Read Receipt

    func sendReadReceipt(roomId: String, eventId: String) async throws {
        let encodedRoomId = roomId.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? roomId
        let encodedEventId = eventId.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? eventId
        let path = "/_matrix/client/v3/rooms/\(encodedRoomId)/receipt/m.read/\(encodedEventId)"

        try await postNoResponse(path, body: [:])
    }

    // MARK: - Read Markers (fully read)

    func setReadMarker(roomId: String, fullyRead: String, read: String? = nil) async throws {
        let encodedRoomId = roomId.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? roomId
        let path = "/_matrix/client/v3/rooms/\(encodedRoomId)/read_markers"

        var body: [String: Any] = ["m.fully_read": fullyRead]
        if let read { body["m.read"] = read }

        try await postNoResponse(path, body: body)
    }

    // MARK: - Presence

    func setPresence(userId: String, presence: String, statusMsg: String? = nil) async throws {
        let encodedUserId = userId.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? userId
        let path = "/_matrix/client/v3/presence/\(encodedUserId)/status"

        var body: [String: Any] = ["presence": presence]
        if let statusMsg { body["status_msg"] = statusMsg }

        try await putJSONNoResponse(path, body: body)
    }

    func getPresence(userId: String) async throws -> MatrixPresenceResponse {
        let encodedUserId = userId.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? userId
        let path = "/_matrix/client/v3/presence/\(encodedUserId)/status"
        return try await get(path)
    }

    // MARK: - Media Upload

    func uploadMedia(data: Data, filename: String, contentType: String) async throws -> MatrixUploadResponse {
        guard let token = accessToken else { throw MatrixError.notAuthenticated }

        var components = URLComponents(url: homeserverURL.appendingPathComponent("/_matrix/media/v3/upload"), resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "filename", value: filename)]

        var request = URLRequest(url: components.url!)
        request.httpMethod = "POST"
        request.setValue(contentType, forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.httpBody = data

        let (responseData, response) = try await session.data(for: request)
        try validateResponse(response, data: responseData)
        return try JSONDecoder().decode(MatrixUploadResponse.self, from: responseData)
    }

    // MARK: - Send Image

    @discardableResult
    func sendImage(roomId: String, mxcUrl: String, body: String, info: [String: Any]? = nil) async throws -> MatrixSendResponse {
        let txnId = UUID().uuidString
        let encodedRoomId = roomId.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? roomId
        let path = "/_matrix/client/v3/rooms/\(encodedRoomId)/send/m.room.message/\(txnId)"

        var content: [String: Any] = [
            "msgtype": "m.image",
            "body": body,
            "url": mxcUrl
        ]
        if let info { content["info"] = info }

        return try await putJSON(path, body: content)
    }

    // MARK: - Send File

    @discardableResult
    func sendFile(roomId: String, mxcUrl: String, body: String, info: [String: Any]? = nil) async throws -> MatrixSendResponse {
        let txnId = UUID().uuidString
        let encodedRoomId = roomId.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? roomId
        let path = "/_matrix/client/v3/rooms/\(encodedRoomId)/send/m.room.message/\(txnId)"

        var content: [String: Any] = [
            "msgtype": "m.file",
            "body": body,
            "url": mxcUrl
        ]
        if let info { content["info"] = info }

        return try await putJSON(path, body: content)
    }

    // MARK: - Resolve mxc:// URL

    func resolveMediaURL(_ mxcUrl: String, width: Int? = nil, height: Int? = nil) -> URL? {
        // mxc://server/mediaId → https://homeserver/_matrix/media/v3/download/server/mediaId
        guard mxcUrl.hasPrefix("mxc://") else { return nil }
        let stripped = String(mxcUrl.dropFirst(6)) // "server/mediaId"

        if let width, let height {
            var components = URLComponents(url: homeserverURL, resolvingAgainstBaseURL: false)
            components?.path = "/_matrix/media/v3/thumbnail/\(stripped)"
            components?.queryItems = [
                URLQueryItem(name: "width", value: String(width)),
                URLQueryItem(name: "height", value: String(height)),
                URLQueryItem(name: "method", value: "crop")
            ]
            return components?.url
        }

        var components = URLComponents(url: homeserverURL, resolvingAgainstBaseURL: false)
        components?.path = "/_matrix/media/v3/download/\(stripped)"
        return components?.url
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
        let encoded = roomIdOrAlias.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? roomIdOrAlias
        return try await post("/_matrix/client/v3/join/\(encoded)", body: [:])
    }

    // MARK: - Invite User

    func inviteUser(roomId: String, userId: String) async throws {
        let encodedRoomId = roomId.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? roomId
        try await postNoResponse("/_matrix/client/v3/rooms/\(encodedRoomId)/invite", body: ["user_id": userId])
    }

    // MARK: - Leave Room

    func leaveRoom(_ roomId: String) async throws {
        let encoded = roomId.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? roomId
        try await postNoResponse("/_matrix/client/v3/rooms/\(encoded)/leave", body: [:])
    }

    // MARK: - Kick User

    func kickUser(roomId: String, userId: String, reason: String? = nil) async throws {
        let encoded = roomId.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? roomId
        var body: [String: Any] = ["user_id": userId]
        if let reason { body["reason"] = reason }
        try await postNoResponse("/_matrix/client/v3/rooms/\(encoded)/kick", body: body)
    }

    // MARK: - Ban User

    func banUser(roomId: String, userId: String, reason: String? = nil) async throws {
        let encoded = roomId.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? roomId
        var body: [String: Any] = ["user_id": userId]
        if let reason { body["reason"] = reason }
        try await postNoResponse("/_matrix/client/v3/rooms/\(encoded)/ban", body: body)
    }

    // MARK: - Unban User

    func unbanUser(roomId: String, userId: String) async throws {
        let encoded = roomId.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? roomId
        try await postNoResponse("/_matrix/client/v3/rooms/\(encoded)/unban", body: ["user_id": userId])
    }

    // MARK: - Profile

    func getProfile(userId: String) async throws -> MatrixProfileResponse {
        let encoded = userId.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? userId
        return try await get("/_matrix/client/v3/profile/\(encoded)")
    }

    func setDisplayName(userId: String, displayName: String) async throws {
        let encoded = userId.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? userId
        try await putJSONNoResponse("/_matrix/client/v3/profile/\(encoded)/displayname", body: ["displayname": displayName])
    }

    func setAvatarUrl(userId: String, avatarUrl: String) async throws {
        let encoded = userId.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? userId
        try await putJSONNoResponse("/_matrix/client/v3/profile/\(encoded)/avatar_url", body: ["avatar_url": avatarUrl])
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
        let encoded = roomId.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? roomId
        return try await get("/_matrix/client/v3/rooms/\(encoded)/members")
    }

    // MARK: - Room Messages (history)

    func roomMessages(roomId: String, from: String? = nil, limit: Int = 50, direction: String = "b") async throws -> MatrixMessagesResponse {
        guard let token = accessToken else { throw MatrixError.notAuthenticated }

        let encodedRoomId = roomId.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? roomId
        guard var components = URLComponents(url: homeserverURL.appendingPathComponent("/_matrix/client/v3/rooms/\(encodedRoomId)/messages"), resolvingAgainstBaseURL: false) else {
            throw MatrixError.invalidURL
        }
        var queryItems = [
            URLQueryItem(name: "dir", value: direction),
            URLQueryItem(name: "limit", value: String(limit))
        ]
        if let from { queryItems.append(URLQueryItem(name: "from", value: from)) }
        components.queryItems = queryItems

        guard let url = components.url else { throw MatrixError.invalidURL }
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await session.data(for: request)
        try validateResponse(response, data: data)
        return try JSONDecoder().decode(MatrixMessagesResponse.self, from: data)
    }

    // MARK: - Room State

    func getRoomState(roomId: String) async throws -> [MatrixEvent] {
        let encoded = roomId.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? roomId
        return try await get("/_matrix/client/v3/rooms/\(encoded)/state")
    }

    // MARK: - Set Room Name / Topic

    func setRoomName(roomId: String, name: String) async throws {
        let encoded = roomId.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? roomId
        try await putJSONNoResponse("/_matrix/client/v3/rooms/\(encoded)/state/m.room.name", body: ["name": name])
    }

    func setRoomTopic(roomId: String, topic: String) async throws {
        let encoded = roomId.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? roomId
        try await putJSONNoResponse("/_matrix/client/v3/rooms/\(encoded)/state/m.room.topic", body: ["topic": topic])
    }

    // MARK: - Space Children

    func addSpaceChild(spaceRoomId: String, childRoomId: String, order: String? = nil) async throws {
        let encodedSpace = spaceRoomId.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? spaceRoomId
        let encodedChild = childRoomId.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? childRoomId
        let path = "/_matrix/client/v3/rooms/\(encodedSpace)/state/m.space.child/\(encodedChild)"

        var body: [String: Any] = ["via": [homeserverURL.host ?? ""]]
        if let order { body["order"] = order }

        try await putJSONNoResponse(path, body: body)
    }

    func removeSpaceChild(spaceRoomId: String, childRoomId: String) async throws {
        let encodedSpace = spaceRoomId.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? spaceRoomId
        let encodedChild = childRoomId.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? childRoomId
        let path = "/_matrix/client/v3/rooms/\(encodedSpace)/state/m.space.child/\(encodedChild)"

        try await putJSONNoResponse(path, body: [:])
    }

    // MARK: - Generic HTTP Helpers

    private func get<T: Decodable>(_ path: String) async throws -> T {
        guard let token = accessToken else { throw MatrixError.notAuthenticated }

        let url = homeserverURL.appendingPathComponent(path)
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        do {
            let (data, response) = try await session.data(for: request)
            try validateResponse(response, data: data)
            return try JSONDecoder().decode(T.self, from: data)
        } catch let error as MatrixError { throw error }
        catch let error as DecodingError { throw MatrixError.decodingError(error) }
        catch { throw MatrixError.networkError(error) }
    }

    private func post<T: Decodable>(_ path: String, body: [String: Any], authenticated: Bool = true) async throws -> T {
        let url = homeserverURL.appendingPathComponent(path)
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if authenticated {
            guard let token = accessToken else { throw MatrixError.notAuthenticated }
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        do {
            let (data, response) = try await session.data(for: request)
            try validateResponse(response, data: data)
            return try JSONDecoder().decode(T.self, from: data)
        } catch let error as MatrixError { throw error }
        catch let error as DecodingError { throw MatrixError.decodingError(error) }
        catch { throw MatrixError.networkError(error) }
    }

    private func postNoResponse(_ path: String, body: [String: Any]) async throws {
        guard let token = accessToken else { throw MatrixError.notAuthenticated }

        let url = homeserverURL.appendingPathComponent(path)
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await session.data(for: request)
        try validateResponse(response, data: data)
    }

    @discardableResult
    private func putJSON<T: Decodable>(_ path: String, body: [String: Any]) async throws -> T {
        guard let token = accessToken else { throw MatrixError.notAuthenticated }

        let url = homeserverURL.appendingPathComponent(path)
        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        do {
            let (data, response) = try await session.data(for: request)
            try validateResponse(response, data: data)
            return try JSONDecoder().decode(T.self, from: data)
        } catch let error as MatrixError { throw error }
        catch let error as DecodingError { throw MatrixError.decodingError(error) }
        catch { throw MatrixError.networkError(error) }
    }

    private func putJSONNoResponse(_ path: String, body: [String: Any]) async throws {
        guard let token = accessToken else { throw MatrixError.notAuthenticated }

        let url = homeserverURL.appendingPathComponent(path)
        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await session.data(for: request)
        try validateResponse(response, data: data)
    }

    private func validateResponse(_ response: URLResponse, data: Data) throws {
        guard let httpResponse = response as? HTTPURLResponse else { return }
        guard (200...299).contains(httpResponse.statusCode) else {
            if let errorResponse = try? JSONDecoder().decode(MatrixErrorResponse.self, from: data) {
                throw MatrixError.httpError(httpResponse.statusCode, errorResponse.error)
            }
            throw MatrixError.httpError(httpResponse.statusCode, "Erreur inconnue")
        }
    }
}
