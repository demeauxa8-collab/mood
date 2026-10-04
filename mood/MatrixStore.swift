import SwiftUI
import CryptoKit
import UniformTypeIdentifiers

// MARK: - Matrix Store

@Observable
@MainActor
class MatrixStore {

    // MARK: - Public State

    var currentUser: MoodUser?
    var servers: [MoodServer] = []
    var dmConversations: [DMConversation] = []
    var messagesByRoom: [String: [ChatMessage]] = [:]

    var isLoading = false
    var errorMessage: String?

    // Typing indicators: roomId -> [displayName]
    var typingUsersByRoom: [String: [String]] = [:]

    // Presence: userId -> (presence, statusMsg, lastActive)
    var presenceByUser: [String: UserPresenceInfo] = [:]

    // Pending invitations
    var pendingInvites: [PendingInvite] = []

    // Pagination: true si on peut encore charger de l'historique pour la room
    var hasMoreHistory: [String: Bool] = [:]

    struct UserPresenceInfo {
        let presence: String // "online", "offline", "unavailable"
        let statusMsg: String?
        let lastActiveAgo: Int64?
        let currentlyActive: Bool
    }

    struct PendingInvite: Identifiable {
        let id: String // roomId
        let roomName: String
        let inviter: String
    }

    // MARK: - Internal State

    let client: MatrixClient
    private var syncToken: String?
    private var syncTask: Task<Void, Never>?
    private var syncGeneration = 0
    private(set) var userId: String?
    private var directRoomIds: Set<String> = []

    private static let syncTokenKey = "mood.syncToken"
    private static let encryptedPlaceholderBody = "🔒 Message chiffré — pas encore pris en charge"
    private static let maxSendAttempts = 3

    // Outbox (file hors-ligne)
    private let outbox: MessageOutbox
    private let reachability: NetworkReachability
    private var flushTask: Task<Void, Never>?
    private var failedOutgoing: [String: OutgoingMessage] = [:] // txnId -> message pour retry manuel

    // Pagination
    private var backPaginationTokens: [String: String] = [:] // roomId -> token /messages
    private var paginatingRooms: Set<String> = []

    // Stable IDs: cache SHA256 + map inverse pour roomId(for:) en O(1)
    private var stableIdCache: [String: UUID] = [:]
    private var stableIdReverse: [UUID: String] = [:]

    // Raw event tracking for reactions/edits/redactions
    private var reactionEvents: [String: [(emoji: String, sender: String, eventId: String)]] = [:] // targetEventId -> reactions
    private var redactedEventIds: Set<String> = []
    private var latestEventIdByRoom: [String: String] = [:]
    /// First unread message when the room was opened — where Discord draws its "NOUVEAU" line.
    private(set) var newMessagesDivider: [String: String] = [:]
    private var latestUnreadEventIdByRoom: [String: String] = [:]
    private var readThroughUnreadEventIdByRoom: [String: String] = [:]
    private var pendingReadReceipts: [String: String] = [:]
    private var isSendingReadReceipts = false

    // Room metadata
    struct MatrixRoom {
        let roomId: String
        var name: String
        var topic: String
        var isDirect: Bool
        var members: [String: String] // userId -> displayName
        var memberAvatars: [String: String] // userId -> mxc URL
        var unreadCount: Int
        var mentionCount: Int
        var isEncrypted: Bool
        var roomType: String? // nil for normal, "m.space" for spaces
        var spaceChildren: [String] // roomIds of children (for spaces)
        var avatarUrl: String? // room avatar mxc URL
        var heroes: [String] // m.heroes du sync, fallback DM quand les membres ne sont pas résolus
        var pinnedEventIds: [String] = [] // m.room.pinned_events
    }

    private var rooms: [MatrixRoom] = []

    // MARK: - Init

    init(homeserver: String = "matrix.org") {
        self.client = MatrixClient(homeserver: homeserver)
        self.outbox = MessageOutbox()
        self.reachability = NetworkReachability()
        self.reachability.onReconnect = { [weak self] in
            self?.flushOutbox()
        }
    }

    // MARK: - Auth

    func login(username: String, password: String, homeserver: String) async throws {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        client.setHomeserver(homeserver)

        let response = try await client.login(username: username, password: password)
        self.userId = response.userId

        saveCredentials(token: response.accessToken, userId: response.userId, homeserver: homeserver)
        syncToken = nil
        UserDefaults.standard.removeObject(forKey: Self.syncTokenKey)
        await buildCurrentUser(userId: response.userId)
        startSyncLoop()
    }

    func register(username: String, password: String, homeserver: String) async throws {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        client.setHomeserver(homeserver)

        let response = try await client.register(username: username, password: password)
        self.userId = response.userId

        saveCredentials(token: response.accessToken, userId: response.userId, homeserver: homeserver)
        syncToken = nil
        UserDefaults.standard.removeObject(forKey: Self.syncTokenKey)
        await buildCurrentUser(userId: response.userId)
        startSyncLoop()
    }

    func loginWithSSOToken(_ token: String, homeserver: String) async throws {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        client.setHomeserver(homeserver)

        let response = try await client.loginWithToken(token)
        self.userId = response.userId

        saveCredentials(token: response.accessToken, userId: response.userId, homeserver: homeserver)
        syncToken = nil
        UserDefaults.standard.removeObject(forKey: Self.syncTokenKey)
        await buildCurrentUser(userId: response.userId)
        startSyncLoop()
    }

    func ssoRedirectURL(idpId: String, homeserver: String, redirectURL: String) -> URL? {
        client.setHomeserver(homeserver)
        return client.ssoRedirectURL(idpId: idpId, redirectURL: redirectURL)
    }

    func logout() {
        let clientRef = client
        Task { try? await clientRef.logout() } // best effort
        syncTask?.cancel()
        syncTask = nil
        syncGeneration += 1
        flushTask?.cancel()
        flushTask = nil
        syncToken = nil
        userId = nil
        currentUser = nil
        rooms = []
        servers = []
        dmConversations = []
        messagesByRoom = [:]
        directRoomIds = []
        typingUsersByRoom = [:]
        presenceByUser = [:]
        pendingInvites = []
        reactionEvents = [:]
        redactedEventIds = []
        latestEventIdByRoom = [:]
        latestUnreadEventIdByRoom = [:]
        readThroughUnreadEventIdByRoom = [:]
        pendingReadReceipts = [:]
        isSendingReadReceipts = false
        backPaginationTokens = [:]
        hasMoreHistory = [:]
        paginatingRooms = []
        failedOutgoing = [:]
        outbox.removeAll()
        UserDefaults.standard.removeObject(forKey: Self.syncTokenKey)
        clearCredentials()
    }

    func restoreSession() async -> Bool {
        guard let token = KeychainHelper.load(key: "access_token"),
              let storedUserId = KeychainHelper.load(key: "user_id"),
              let homeserver = KeychainHelper.load(key: "homeserver")
        else {
            // Migration from UserDefaults
            if let token = UserDefaults.standard.string(forKey: "matrix_access_token"),
               let userId = UserDefaults.standard.string(forKey: "matrix_user_id"),
               let homeserver = UserDefaults.standard.string(forKey: "matrix_homeserver") {
                saveCredentials(token: token, userId: userId, homeserver: homeserver)
                UserDefaults.standard.removeObject(forKey: "matrix_access_token")
                UserDefaults.standard.removeObject(forKey: "matrix_user_id")
                UserDefaults.standard.removeObject(forKey: "matrix_homeserver")
                return await restoreSession()
            }
            return false
        }

        client.setHomeserver(homeserver)
        client.setAccessToken(token)

        do {
            self.userId = try await client.whoami()
        } catch let error as MatrixClient.MatrixError where error.isUnknownToken {
            clearCredentials()
            UserDefaults.standard.removeObject(forKey: Self.syncTokenKey)
            return false
        } catch {
            // Erreur réseau : hors ligne ≠ déconnecté, on garde la session
            self.userId = storedUserId
        }

        syncToken = UserDefaults.standard.string(forKey: Self.syncTokenKey)
        restoreOutboxEchoes()
        Task { await buildCurrentUser(userId: self.userId ?? storedUserId) }
        startSyncLoop()
        flushOutbox()
        return true
    }

    // MARK: - Sync Loop

    private func startSyncLoop() {
        syncTask?.cancel()
        syncGeneration += 1
        let generation = syncGeneration

        syncTask = Task { [weak self] in
            guard let self else { return }

            var backoff: Double = 1
            var isFirstSync = true

            while !Task.isCancelled && generation == self.syncGeneration {
                do {
                    let response = try await self.client.sync(since: self.syncToken, timeout: isFirstSync ? 0 : 30000)
                    guard !Task.isCancelled, generation == self.syncGeneration else { return }

                    self.processSyncResponse(response)
                    self.syncToken = response.nextBatch
                    UserDefaults.standard.set(response.nextBatch, forKey: Self.syncTokenKey)
                    backoff = 1
                    await self.retryPendingReadReceipts()

                    if isFirstSync {
                        isFirstSync = false
                        if let userId = self.userId {
                            try? await self.client.setPresence(userId: userId, presence: "online")
                        }
                        guard !Task.isCancelled, generation == self.syncGeneration else { return }
                        self.flushOutbox()
                    }
                } catch {
                    guard !Task.isCancelled, generation == self.syncGeneration else { return }
                    if (error as? MatrixClient.MatrixError)?.isUnknownToken == true {
                        self.handleSessionExpired()
                        return
                    }
                    let jitter = Double.random(in: 0...(backoff * 0.25))
                    try? await Task.sleep(for: .seconds(backoff + jitter))
                    guard !Task.isCancelled, generation == self.syncGeneration else { return }
                    backoff = min(backoff * 2, 60)
                }
            }
        }
    }

    private func handleSessionExpired() {
        logout()
        errorMessage = "Session expirée, reconnecte-toi"
    }

    // MARK: - Process Sync Response

    private func processSyncResponse(_ response: MatrixSyncResponse) {
        // Account data (m.direct)
        if let accountEvents = response.accountData?.events {
            for event in accountEvents where event.type == "m.direct" {
                if let content = event.content {
                    var dmIds = Set<String>()
                    for (_, roomList) in content {
                        if let arr = roomList.arrayValue {
                            for item in arr {
                                if let roomId = item.stringValue {
                                    dmIds.insert(roomId)
                                }
                            }
                        }
                    }
                    directRoomIds = dmIds
                }
            }
        }

        // Presence
        if let presenceEvents = response.presence?.events {
            for event in presenceEvents where event.type == "m.presence" {
                guard let sender = event.sender else { continue }
                let presence = event.content?["presence"]?.stringValue ?? "offline"
                let statusMsg = event.content?["status_msg"]?.stringValue
                let lastActive = event.content?["last_active_ago"]?.intValue.map(Int64.init)
                let currentlyActive = event.content?["currently_active"]?.boolValue ?? false

                presenceByUser[sender] = UserPresenceInfo(
                    presence: presence,
                    statusMsg: statusMsg,
                    lastActiveAgo: lastActive,
                    currentlyActive: currentlyActive
                )
            }
        }

        // Invited rooms
        if let invitedRooms = response.rooms?.invite {
            for (roomId, inviteData) in invitedRooms {
                var roomName = roomId
                var inviter = ""
                if let events = inviteData.inviteState?.events {
                    for event in events {
                        if event.type == "m.room.name", let name = event.content?["name"]?.stringValue {
                            roomName = name
                        }
                        if event.type == "m.room.member", event.stateKey == userId,
                           let sender = event.sender {
                            inviter = sender
                        }
                    }
                }
                if !pendingInvites.contains(where: { $0.id == roomId }) {
                    pendingInvites.append(PendingInvite(id: roomId, roomName: roomName, inviter: inviter))
                }
            }
        }

        // Left rooms — remove from pending invites
        if let leftRooms = response.rooms?.leave {
            for roomId in leftRooms.keys {
                pendingInvites.removeAll { $0.id == roomId }
            }
        }

        // Joined rooms
        guard let joinedRooms = response.rooms?.join else {
            rebuildUIModels()
            return
        }

        for (roomId, roomData) in joinedRooms {
            var room = rooms.first(where: { $0.roomId == roomId }) ?? MatrixRoom(
                roomId: roomId, name: roomId, topic: "", isDirect: directRoomIds.contains(roomId),
                members: [:], memberAvatars: [:], unreadCount: 0, mentionCount: 0,
                isEncrypted: false, roomType: nil, spaceChildren: [], avatarUrl: nil, heroes: []
            )

            room.isDirect = directRoomIds.contains(roomId)

            if let heroes = roomData.summary?.mHeroes, !heroes.isEmpty {
                room.heroes = heroes
            }

            // Remove from pending invites once joined
            pendingInvites.removeAll { $0.id == roomId }

            // State events
            if let stateEvents = roomData.state?.events {
                for event in stateEvents {
                    processStateEvent(event, room: &room)
                }
            }

            // Pagination : prev_batch du sync = point de départ, limited = trou à combler
            if let timeline = roomData.timeline {
                let hadMessages = !(messagesByRoom[roomId]?.isEmpty ?? true)
                if let prevBatch = timeline.prevBatch, backPaginationTokens[roomId] == nil {
                    backPaginationTokens[roomId] = prevBatch
                    hasMoreHistory[roomId] = true
                } else if timeline.limited == true, hadMessages, let prevBatch = timeline.prevBatch {
                    let generation = syncGeneration
                    Task { [weak self] in
                        await self?.fillGap(roomId: roomId, from: prevBatch, generation: generation)
                    }
                }
            }

            // Timeline events
            if let timelineEvents = roomData.timeline?.events {
                for event in timelineEvents {
                    if event.stateKey != nil {
                        processStateEvent(event, room: &room)
                    }
                    processTimelineEvent(event, roomId: roomId)
                }
            }

            // Ephemeral events (typing, receipts)
            if let ephemeralEvents = roomData.ephemeral?.events {
                for event in ephemeralEvents {
                    processEphemeralEvent(event, roomId: roomId, room: room)
                }
            }

            // Unread counts
            if let notifs = roomData.unreadNotifications {
                if let readEventId = readThroughUnreadEventIdByRoom[roomId],
                   readEventId == latestUnreadEventIdByRoom[roomId] {
                    room.unreadCount = 0
                    room.mentionCount = 0
                } else {
                    readThroughUnreadEventIdByRoom.removeValue(forKey: roomId)
                    room.unreadCount = notifs.notificationCount ?? 0
                    room.mentionCount = notifs.highlightCount ?? 0
                }
            }

            // Fallback room name from members
            if room.name == roomId || room.name.isEmpty {
                let otherMembers = room.members.filter { $0.key != userId }
                if !otherMembers.isEmpty {
                    room.name = otherMembers.values.sorted().joined(separator: ", ")
                }
            }

            if let idx = rooms.firstIndex(where: { $0.roomId == roomId }) {
                rooms[idx] = room
            } else {
                rooms.append(room)
            }
        }

        rebuildUIModels()
    }

    private func processStateEvent(_ event: MatrixEvent, room: inout MatrixRoom) {
        switch event.type {
        case "m.room.name":
            if let name = event.content?["name"]?.stringValue, !name.isEmpty {
                room.name = name
            }
        case "m.room.topic":
            if let topic = event.content?["topic"]?.stringValue {
                room.topic = topic
            }
        case "m.room.avatar":
            if let url = event.content?["url"]?.stringValue {
                room.avatarUrl = url
            }
        case "m.room.member":
            if let membership = event.content?["membership"]?.stringValue,
               let memberUserId = event.stateKey {
                if membership == "join" {
                    let displayName = event.content?["displayname"]?.stringValue ?? extractLocalpart(memberUserId)
                    room.members[memberUserId] = displayName
                    if let avatarUrl = event.content?["avatar_url"]?.stringValue {
                        room.memberAvatars[memberUserId] = avatarUrl
                    }
                } else if membership == "leave" || membership == "ban" {
                    room.members.removeValue(forKey: memberUserId)
                    room.memberAvatars.removeValue(forKey: memberUserId)
                }
            }
        case "m.room.canonical_alias":
            if room.name == room.roomId,
               let alias = event.content?["alias"]?.stringValue, !alias.isEmpty {
                let cleaned = alias.split(separator: ":").first.map { String($0).replacingOccurrences(of: "#", with: "") } ?? alias
                room.name = cleaned
            }
        case "m.room.encryption":
            room.isEncrypted = true
        case "m.room.pinned_events":
            room.pinnedEventIds = event.content?["pinned"]?.arrayValue?.compactMap(\.stringValue) ?? []
        case "m.room.create":
            if let roomType = event.content?["type"]?.stringValue {
                room.roomType = roomType
            }
        case "m.space.child":
            if let childRoomId = event.stateKey {
                let via = event.content?["via"]?.arrayValue
                if via != nil && !(via?.isEmpty ?? true) {
                    if !room.spaceChildren.contains(childRoomId) {
                        room.spaceChildren.append(childRoomId)
                    }
                } else {
                    room.spaceChildren.removeAll { $0 == childRoomId }
                }
            }
        default:
            break
        }
    }

    private func processTimelineEvent(_ event: MatrixEvent, roomId: String) {
        guard let eventId = event.eventId else { return }
        latestEventIdByRoom[roomId] = eventId
        if isUnreadRelevant(event) {
            latestUnreadEventIdByRoom[roomId] = eventId
        }

        // Redaction
        if event.type == "m.room.redaction" {
            guard let redactedId = event.redacts else { return }
            redactedEventIds.insert(redactedId)
            if let idx = messageIndex(roomId: roomId, eventId: redactedId) {
                messagesByRoom[roomId]?.remove(at: idx)
            }
            reactionEvents.removeValue(forKey: redactedId)
            return
        }

        // Reaction
        if event.type == "m.reaction" {
            if let relatesTo = event.content?["m.relates_to"]?.dictValue,
               let targetEventId = relatesTo["event_id"]?.stringValue,
               !redactedEventIds.contains(targetEventId),
               let key = relatesTo["key"]?.stringValue,
               let sender = event.sender {
                if reactionEvents[targetEventId] == nil {
                    reactionEvents[targetEventId] = []
                }
                reactionEvents[targetEventId]?.append((emoji: key, sender: sender, eventId: eventId))

                // Update existing message reactions
                updateMessageReactions(roomId: roomId, targetEventId: targetEventId)
            }
            return
        }

        guard event.type == "m.room.message" || event.type == "m.room.encrypted" else { return }

        // Edit (m.replace)
        if event.type == "m.room.message",
           let relatesTo = event.content?["m.relates_to"]?.dictValue,
           relatesTo["rel_type"]?.stringValue == "m.replace",
           let targetEventId = relatesTo["event_id"]?.stringValue {
            let newContent = event.content?["m.new_content"]?.dictValue
            let newBody = newContent?["body"]?.stringValue ?? event.content?["body"]?.stringValue ?? ""

            if let idx = messageIndex(roomId: roomId, eventId: targetEventId) {
                let original = messagesByRoom[roomId]![idx]
                messagesByRoom[roomId]![idx] = ChatMessage(
                    id: original.id, sender: original.sender, content: newBody,
                    timestamp: original.timestamp, isGrouped: original.isGrouped,
                    reactions: original.reactions, replyTo: original.replyTo,
                    attachments: original.attachments, isPinned: original.isPinned,
                    threadInfo: original.threadInfo, isEdited: true,
                    linkEmbed: original.linkEmbed,
                    isSystemMessage: original.isSystemMessage, systemType: original.systemType,
                    sendState: original.sendState, eventId: original.eventId, txnId: original.txnId
                )
            }
            return
        }

        // Écho serveur d'un envoi local : remplace le message local au lieu de dupliquer
        if let txn = event.transactionId,
           let idx = messagesByRoom[roomId]?.firstIndex(where: { $0.txnId == txn }) {
            let localId = messagesByRoom[roomId]![idx].id
            messagesByRoom[roomId]?.remove(at: idx)
            failedOutgoing.removeValue(forKey: txn)
            outbox.remove(txnId: txn)
            if let message = makeMessage(from: event, roomId: roomId, overrideId: localId) {
                insertSorted(message, roomId: roomId)
            }
            return
        }

        // Déjà connu (eventId)
        if messageIndex(roomId: roomId, eventId: eventId) != nil { return }

        guard let message = makeMessage(from: event, roomId: roomId) else { return }
        insertSorted(message, roomId: roomId)
    }

    // Construit un ChatMessage depuis un event timeline (placeholder pour le chiffré, nil pour les edits)
    private func makeMessage(from event: MatrixEvent, roomId: String, overrideId: UUID? = nil) -> ChatMessage? {
        switch event.type {
        case "m.room.message":
            if let relatesTo = event.content?["m.relates_to"]?.dictValue,
               relatesTo["rel_type"]?.stringValue == "m.replace" {
                return nil
            }
            return convertToChatMessage(event, roomId: roomId, overrideId: overrideId)
        case "m.room.encrypted":
            return convertToChatMessage(event, roomId: roomId, overrideId: overrideId, overrideBody: Self.encryptedPlaceholderBody)
        default:
            return nil
        }
    }

    private func messageIndex(roomId: String, eventId: String) -> Int? {
        guard let list = messagesByRoom[roomId] else { return nil }
        let stableId = stableUUID(from: eventId)
        return list.firstIndex(where: { $0.id == stableId || $0.eventId == eventId })
    }

    private func insertSorted(_ message: ChatMessage, roomId: String) {
        var list = messagesByRoom[roomId] ?? []
        var idx = list.endIndex
        while idx > list.startIndex && list[idx - 1].timestamp > message.timestamp {
            idx -= 1
        }
        list.insert(message, at: idx)
        messagesByRoom[roomId] = list
    }

    private func isUnreadRelevant(_ event: MatrixEvent) -> Bool {
        guard event.stateKey == nil else { return false }

        if event.type == "m.room.message",
           let relatesTo = event.content?["m.relates_to"]?.dictValue,
           relatesTo["rel_type"]?.stringValue == "m.replace" {
            return false
        }

        switch event.type {
        case "m.reaction", "m.room.redaction", "m.receipt", "m.typing":
            return false
        default:
            return true
        }
    }

    private func processEphemeralEvent(_ event: MatrixEvent, roomId: String, room: MatrixRoom) {
        if event.type == "m.typing" {
            if let userIds = event.content?["user_ids"]?.arrayValue {
                let typingNames = userIds.compactMap { $0.stringValue }
                    .filter { $0 != userId }
                    .compactMap { uid -> String? in
                        room.members[uid] ?? extractLocalpart(uid)
                    }
                typingUsersByRoom[roomId] = typingNames
            }
        }

        if event.type == "m.receipt" {
            // Receipts come as: { "$eventId": { "m.read": { "@user:server": { "ts": 123 } } } }
            // We don't need to store these in detail for now,
            // but we could track last-read event per user if needed
        }
    }

    private func updateMessageReactions(roomId: String, targetEventId: String) {
        guard let reactions = reactionEvents[targetEventId],
              let idx = messageIndex(roomId: roomId, eventId: targetEventId)
        else { return }

        // Group reactions by emoji
        var grouped: [String: (count: Int, hasReacted: Bool)] = [:]
        for reaction in reactions {
            let existing = grouped[reaction.emoji] ?? (count: 0, hasReacted: false)
            grouped[reaction.emoji] = (
                count: existing.count + 1,
                hasReacted: existing.hasReacted || reaction.sender == userId
            )
        }

        let messageReactions = grouped.map { emoji, info in
            MessageReaction(
                id: stableUUID(from: "\(targetEventId)_\(emoji)"),
                emoji: emoji,
                count: info.count,
                hasReacted: info.hasReacted
            )
        }.sorted { $0.emoji < $1.emoji }

        let original = messagesByRoom[roomId]![idx]
        messagesByRoom[roomId]![idx] = ChatMessage(
            id: original.id, sender: original.sender, content: original.content,
            timestamp: original.timestamp, isGrouped: original.isGrouped,
            reactions: messageReactions, replyTo: original.replyTo,
            attachments: original.attachments, isPinned: original.isPinned,
            threadInfo: original.threadInfo, isEdited: original.isEdited,
            linkEmbed: original.linkEmbed,
            isSystemMessage: original.isSystemMessage, systemType: original.systemType,
            sendState: original.sendState, eventId: original.eventId, txnId: original.txnId
        )
    }

    // MARK: - Convert to UI Models

    private func convertToChatMessage(_ event: MatrixEvent, roomId: String, overrideId: UUID? = nil, overrideBody: String? = nil) -> ChatMessage {
        let senderUserId = event.sender ?? "unknown"
        let room = rooms.first(where: { $0.roomId == roomId })
        let displayName = room?.members[senderUserId] ?? extractLocalpart(senderUserId)
        let body = overrideBody ?? event.content?["body"]?.stringValue ?? ""
        let msgtype = overrideBody != nil ? "m.text" : (event.content?["msgtype"]?.stringValue ?? "m.text")
        let timestamp = Date(timeIntervalSince1970: TimeInterval(event.originServerTs ?? 0) / 1000)
        let eventId = event.eventId ?? UUID().uuidString

        let sender = makeUser(senderUserId, displayName: displayName, avatarMxc: room?.memberAvatars[senderUserId])

        // Parse reply
        var replyTo: ReplyRef?
        if let relatesTo = event.content?["m.relates_to"]?.dictValue,
           let inReplyTo = relatesTo["m.in_reply_to"]?.dictValue,
           let replyEventId = inReplyTo["event_id"]?.stringValue {
            // Find the original message
            if let idx = messageIndex(roomId: roomId, eventId: replyEventId) {
                let original = messagesByRoom[roomId]![idx]
                replyTo = ReplyRef(sender: original.sender, content: original.content)
            }
        }

        // Parse thread info
        var threadRootId: String?
        if let relatesTo = event.content?["m.relates_to"]?.dictValue,
           let relType = relatesTo["rel_type"]?.stringValue, relType == "m.thread",
           let rootId = relatesTo["event_id"]?.stringValue {
            threadRootId = rootId
        }

        // Parse attachments
        var attachments: [MessageAttachment] = []
        if msgtype == "m.image" || msgtype == "m.file" || msgtype == "m.video" || msgtype == "m.audio" {
            let isImage = msgtype == "m.image"
            let fileName = event.content?["body"]?.stringValue ?? (isImage ? "image" : "fichier")
            let mxc = event.content?["url"]?.stringValue
            let size = event.content?["info"]?.dictValue?["size"]?.intValue
            attachments.append(MessageAttachment(
                id: stableUUID(from: "\(eventId)_att"),
                type: isImage ? .image : .file,
                name: fileName,
                previewEmoji: isImage ? "🖼️" : "📎",
                url: resolveMediaURL(mxc),
                thumbnailURL: isImage ? resolveMediaURL(mxc, width: 800, height: 600) : nil,
                size: size
            ))
        }

        // System messages
        var isSystem = false
        var systemType: SystemMessageType?
        // Matrix doesn't have "system message" as a msgtype, but we can detect membership changes
        // These are handled separately via state events

        // Build reactions from stored data
        var reactions: [MessageReaction] = []
        if let stored = reactionEvents[eventId] {
            var grouped: [String: (count: Int, hasReacted: Bool)] = [:]
            for reaction in stored {
                let existing = grouped[reaction.emoji] ?? (count: 0, hasReacted: false)
                grouped[reaction.emoji] = (count: existing.count + 1, hasReacted: existing.hasReacted || reaction.sender == userId)
            }
            reactions = grouped.map { emoji, info in
                MessageReaction(id: stableUUID(from: "\(eventId)_\(emoji)"), emoji: emoji, count: info.count, hasReacted: info.hasReacted)
            }.sorted { $0.emoji < $1.emoji }
        }

        var message = ChatMessage(
            id: overrideId ?? stableUUID(from: eventId),
            sender: sender,
            content: attachments.isEmpty ? body : "",
            timestamp: timestamp,
            isGrouped: false,
            reactions: reactions,
            replyTo: replyTo,
            attachments: attachments,
            isSystemMessage: isSystem,
            systemType: systemType,
            sendState: .sent,
            eventId: event.eventId,
            txnId: event.transactionId
        )
        message.isOwn = senderUserId == userId
        return message
    }

    /// Single place that turns a Matrix user into a UI user (real avatar, presence, Matrix id).
    func makeUser(_ matrixUserId: String, displayName: String? = nil, avatarMxc: String? = nil,
                  fallbackStatus: MoodUser.UserStatus = .offline) -> MoodUser {
        let presenceInfo = presenceByUser[matrixUserId]
        let status: MoodUser.UserStatus
        switch presenceInfo?.presence {
        case "online": status = .online
        case "unavailable": status = .idle
        case "offline": status = .offline
        default: status = presenceInfo?.currentlyActive == true ? .online : fallbackStatus
        }
        return MoodUser(
            id: stableUUID(from: matrixUserId),
            username: extractLocalpart(matrixUserId),
            displayName: displayName ?? extractLocalpart(matrixUserId),
            avatarEmoji: emojiForUser(matrixUserId),
            roleColor: colorForUser(matrixUserId),
            status: status,
            bio: presenceInfo?.statusMsg ?? "",
            joinedDate: Date(),
            badges: [],
            activity: nil,
            matrixId: matrixUserId,
            avatarURL: resolveMediaURL(avatarMxc, width: 96, height: 96)
        )
    }

    private func rebuildUIModels() {
        // Separate spaces, group rooms, and DM rooms
        let spaceRooms = rooms.filter { $0.roomType == "m.space" }
        let dmRooms = rooms.filter { $0.isDirect && $0.roomType != "m.space" }
        let normalRooms = rooms.filter { !$0.isDirect && $0.roomType != "m.space" }

        // Build servers from spaces
        var builtServers: [MoodServer] = []

        for space in spaceRooms {
            let childRoomIds = Set(space.spaceChildren)
            let childRooms = rooms.filter { childRoomIds.contains($0.roomId) && !$0.isDirect }

            let channels = childRooms.map { room in
                Channel(
                    id: stableUUID(from: room.roomId),
                    name: room.name,
                    type: .text,
                    topic: room.topic,
                    unreadCount: room.unreadCount,
                    mentionCount: room.mentionCount,
                    isE2E: room.isEncrypted,
                    latestEventId: latestEventIdByRoom[room.roomId],
                    unreadEventId: latestUnreadEventIdByRoom[room.roomId]
                )
            }

            if !channels.isEmpty {
                let server = MoodServer(
                    id: stableUUID(from: space.roomId),
                    name: space.name,
                    iconEmoji: emojiForUser(space.roomId),
                    categories: [
                        ChannelCategory(
                            id: stableUUID(from: "\(space.roomId)-cat"),
                            name: "SALONS TEXTUELS",
                            channels: channels
                        )
                    ],
                    members: [],
                    memberRoles: [:],
                    hasUnread: childRooms.contains(where: { $0.unreadCount > 0 }),
                    mentionCount: childRooms.reduce(0) { $0 + $1.mentionCount }
                )
                builtServers.append(server)
            }
        }

        // Rooms not in any space → fallback "Matrix" server
        let roomsInSpaces = Set(spaceRooms.flatMap { $0.spaceChildren })
        let orphanRooms = normalRooms.filter { !roomsInSpaces.contains($0.roomId) }

        if !orphanRooms.isEmpty {
            let channels = orphanRooms.map { room in
                Channel(
                    id: stableUUID(from: room.roomId),
                    name: room.name,
                    type: .text,
                    topic: room.topic,
                    unreadCount: room.unreadCount,
                    mentionCount: room.mentionCount,
                    isE2E: room.isEncrypted,
                    latestEventId: latestEventIdByRoom[room.roomId],
                    unreadEventId: latestUnreadEventIdByRoom[room.roomId]
                )
            }

            let server = MoodServer(
                id: stableUUID(from: "matrix-all-rooms"),
                name: "Matrix",
                iconEmoji: "🌐",
                categories: [
                    ChannelCategory(
                        id: stableUUID(from: "matrix-rooms-cat"),
                        name: "SALONS",
                        channels: channels
                    )
                ],
                members: [],
                memberRoles: [:],
                hasUnread: orphanRooms.contains(where: { $0.unreadCount > 0 }),
                mentionCount: orphanRooms.reduce(0) { $0 + $1.mentionCount }
            )
            builtServers.append(server)
        }

        self.servers = builtServers

        // DMs — pas de suppression silencieuse : fallback heroes puis nom de room
        self.dmConversations = dmRooms.map { room in
            let otherUserId = room.members.keys.first(where: { $0 != self.userId })
                ?? room.heroes.first(where: { $0 != self.userId })

            let displayName: String
            if let otherUserId {
                displayName = room.members[otherUserId] ?? extractLocalpart(otherUserId)
            } else if !room.name.isEmpty && room.name != room.roomId {
                displayName = room.name
            } else {
                displayName = "Conversation"
            }

            let lastMsg = messagesByRoom[room.roomId]?.last
            let lastMessage = lastMsg?.content ?? ""
            let lastDate = lastMsg?.timestamp ?? Date()

            let avatarMxc = otherUserId.flatMap { room.memberAvatars[$0] }
            let participant = makeUser(otherUserId ?? room.roomId, displayName: displayName, avatarMxc: avatarMxc ?? room.avatarUrl)

            return DMConversation(
                id: stableUUID(from: room.roomId),
                participant: participant,
                lastMessage: lastMessage,
                lastMessageDate: lastDate,
                unreadCount: room.unreadCount,
                latestEventId: latestEventIdByRoom[room.roomId],
                unreadEventId: latestUnreadEventIdByRoom[room.roomId]
            )
        }.sorted { $0.lastMessageDate > $1.lastMessageDate }
    }

    // MARK: - Public Actions

    // Écho local immédiat + envoi via la file hors-ligne : jamais bloquant pour l'UI
    func clearNewMessagesDivider(roomId: String) {
        newMessagesDivider.removeValue(forKey: roomId)
    }

    /// Called when the user leaves a channel or DM (UI ids are stable hashes of room ids).
    func clearNewMessagesDivider(forConversationID id: UUID) {
        if let roomId = stableIdReverse[id] { clearNewMessagesDivider(roomId: roomId) }
    }

    func sendMessage(roomId: String, text: String, replyToEventId: String? = nil, threadRootEventId: String? = nil) async {
        clearNewMessagesDivider(roomId: roomId)
        let txnId = UUID().uuidString
        let echo = makeLocalEcho(roomId: roomId, body: text, txnId: txnId, replyToEventId: replyToEventId)
        insertSorted(echo, roomId: roomId)
        rebuildUIModels()

        outbox.enqueue(OutgoingMessage(
            txnId: txnId, roomId: roomId, body: text,
            replyToEventId: replyToEventId, threadRootEventId: threadRootEventId,
            createdAt: Date()
        ))
        flushOutbox()
    }

    func retryMessage(_ localId: UUID, roomId: String) {
        guard var list = messagesByRoom[roomId],
              let idx = list.firstIndex(where: { $0.id == localId }),
              list[idx].sendState == .failed,
              let txnId = list[idx].txnId
        else { return }

        list[idx].sendState = .sending
        messagesByRoom[roomId] = list

        let item = failedOutgoing.removeValue(forKey: txnId) ?? OutgoingMessage(
            txnId: txnId, roomId: roomId, body: list[idx].content,
            replyToEventId: nil, threadRootEventId: nil, createdAt: list[idx].timestamp
        )
        outbox.enqueue(item)
        flushOutbox()
    }

    // MARK: - Outbox

    private enum DeliveryResult {
        case sent, failed, offline, sessionExpired
    }

    private func flushOutbox() {
        guard flushTask == nil, userId != nil, !outbox.pending.isEmpty else { return }
        flushTask = Task { [weak self] in
            guard let self else { return }
            await self.processOutbox()
            self.flushTask = nil
            // Un message enfilé pendant la fin du flush ne doit pas rester bloqué
            if self.userId != nil, !self.outbox.pending.isEmpty, self.reachability.isConnected {
                self.flushOutbox()
            }
        }
    }

    private func processOutbox() async {
        while let item = outbox.pending.first {
            guard !Task.isCancelled, reachability.isConnected, userId != nil else { return }
            let result = await deliver(item)
            guard !Task.isCancelled else { return }

            switch result {
            case .sent:
                outbox.remove(txnId: item.txnId)
                rebuildUIModels()
            case .failed:
                outbox.remove(txnId: item.txnId)
                failedOutgoing[item.txnId] = item
                setSendState(.failed, txnId: item.txnId, roomId: item.roomId)
            case .offline:
                return
            case .sessionExpired:
                handleSessionExpired()
                return
            }
        }
    }

    private func deliver(_ item: OutgoingMessage) async -> DeliveryResult {
        var attempt = 0
        while attempt < Self.maxSendAttempts {
            do {
                let response = try await client.sendMessage(
                    roomId: item.roomId, body: item.body,
                    replyToEventId: item.replyToEventId,
                    threadRootEventId: item.threadRootEventId,
                    txnId: item.txnId
                )
                confirmEcho(txnId: item.txnId, roomId: item.roomId, eventId: response.eventId)
                return .sent
            } catch {
                if (error as? MatrixClient.MatrixError)?.isUnknownToken == true { return .sessionExpired }
                if !reachability.isConnected { return .offline }
                attempt += 1
                guard let delay = retryDelay(for: error, attempt: attempt) else { return .failed }
                try? await Task.sleep(for: .seconds(delay))
                if Task.isCancelled { return .offline }
            }
        }
        return .failed
    }

    private func retryDelay(for error: Error, attempt: Int) -> TimeInterval? {
        guard attempt < Self.maxSendAttempts else { return nil }
        if case .httpError(let statusCode, _, _, let retryAfterMs)? = error as? MatrixClient.MatrixError {
            if statusCode == 429 {
                return retryAfterMs.map { TimeInterval($0) / 1000 } ?? pow(2, Double(attempt))
            }
            if (400..<500).contains(statusCode) { return nil } // erreur définitive, inutile de réessayer
        }
        return pow(2, Double(attempt))
    }

    private func confirmEcho(txnId: String, roomId: String, eventId: String) {
        guard var list = messagesByRoom[roomId],
              let idx = list.firstIndex(where: { $0.txnId == txnId }),
              list[idx].eventId == nil
        else { return }
        let msg = list[idx]
        list[idx] = ChatMessage(
            id: msg.id, sender: msg.sender, content: msg.content, timestamp: msg.timestamp,
            isGrouped: msg.isGrouped, reactions: msg.reactions, replyTo: msg.replyTo,
            attachments: msg.attachments, isPinned: msg.isPinned, threadInfo: msg.threadInfo,
            isEdited: msg.isEdited, linkEmbed: msg.linkEmbed,
            isSystemMessage: msg.isSystemMessage, systemType: msg.systemType,
            sendState: .sent, eventId: eventId, txnId: msg.txnId
        )
        messagesByRoom[roomId] = list
    }

    private func setSendState(_ state: MessageSendState, txnId: String, roomId: String) {
        guard var list = messagesByRoom[roomId],
              let idx = list.firstIndex(where: { $0.txnId == txnId }) else { return }
        list[idx].sendState = state
        messagesByRoom[roomId] = list
    }

    private func makeLocalEcho(roomId: String, body: String, txnId: String, replyToEventId: String?, createdAt: Date = Date()) -> ChatMessage {
        let sender = currentUser ?? MoodUser(
            id: stableUUID(from: userId ?? "me"),
            username: userId.map(extractLocalpart) ?? "moi",
            displayName: userId.map(extractLocalpart) ?? "Moi",
            avatarEmoji: "👤", roleColor: .blue, status: .online,
            bio: "", joinedDate: Date(), badges: [], activity: nil
        )
        var replyTo: ReplyRef?
        if let replyToEventId, let idx = messageIndex(roomId: roomId, eventId: replyToEventId) {
            let original = messagesByRoom[roomId]![idx]
            replyTo = ReplyRef(sender: original.sender, content: original.content)
        }
        return ChatMessage(
            id: stableUUID(from: txnId), sender: sender, content: body,
            timestamp: createdAt, isGrouped: false, replyTo: replyTo,
            sendState: .sending, eventId: nil, txnId: txnId
        )
    }

    // Recrée les échos locaux des messages encore en file au démarrage
    private func restoreOutboxEchoes() {
        for item in outbox.pending {
            let exists = messagesByRoom[item.roomId]?.contains(where: { $0.txnId == item.txnId }) ?? false
            guard !exists else { continue }
            let echo = makeLocalEcho(roomId: item.roomId, body: item.body, txnId: item.txnId,
                                     replyToEventId: item.replyToEventId, createdAt: item.createdAt)
            insertSorted(echo, roomId: item.roomId)
        }
    }

    func editMessage(roomId: String, eventId: String, newBody: String) async {
        do {
            try await client.editMessage(roomId: roomId, eventId: eventId, newBody: newBody)
        } catch {
            self.errorMessage = "Modification échouée : \(error.localizedDescription)"
        }
    }

    func deleteMessage(roomId: String, eventId: String) async {
        do {
            try await client.redactEvent(roomId: roomId, eventId: eventId)
        } catch {
            self.errorMessage = "Suppression échouée : \(error.localizedDescription)"
        }
    }

    func sendReaction(roomId: String, eventId: String, emoji: String) async {
        do {
            try await client.sendReaction(roomId: roomId, eventId: eventId, emoji: emoji)
        } catch {
            self.errorMessage = "Réaction échouée : \(error.localizedDescription)"
        }
    }

    /// Clicking a reaction chip: adds my reaction, or removes it if I already reacted.
    func toggleReaction(roomId: String, eventId: String, emoji: String) async {
        if let mine = reactionEvents[eventId]?.first(where: { $0.emoji == emoji && $0.sender == userId }) {
            do {
                try await client.redactEvent(roomId: roomId, eventId: mine.eventId)
            } catch {
                errorMessage = "Impossible de retirer la réaction : \(error.localizedDescription)"
            }
        } else {
            await sendReaction(roomId: roomId, eventId: eventId, emoji: emoji)
        }
    }

    func togglePin(roomId: String, eventId: String) async {
        guard let index = rooms.firstIndex(where: { $0.roomId == roomId }) else { return }
        var pinned = rooms[index].pinnedEventIds
        if let existing = pinned.firstIndex(of: eventId) {
            pinned.remove(at: existing)
        } else {
            pinned.append(eventId)
        }
        do {
            try await client.setPinnedEvents(roomId: roomId, eventIds: pinned)
            rooms[index].pinnedEventIds = pinned
        } catch {
            errorMessage = "Épinglage impossible (droits insuffisants ?) : \(error.localizedDescription)"
        }
    }

    /// Shareable link to a message, the Matrix equivalent of Discord's "Copier le lien du message".
    func permalink(roomId: String, eventId: String) -> String {
        "https://matrix.to/#/\(roomId)/\(eventId)"
    }

    func setTyping(roomId: String, typing: Bool) async {
        guard let userId else { return }
        try? await client.sendTyping(roomId: roomId, userId: userId, typing: typing)
    }

    func markDMAsRead(_ conversation: DMConversation) {
        guard let roomId = roomId(for: conversation) else { return }
        let eventId = conversation.latestEventId ?? latestEventIdByRoom[roomId]
        let unreadEventId = conversation.unreadEventId ?? latestUnreadEventIdByRoom[roomId]
        markRoomAsRead(roomId: roomId, eventId: eventId, unreadEventId: unreadEventId)
    }

    func markChannelAsRead(_ channel: Channel) {
        guard let roomId = roomId(for: channel) else { return }
        let eventId = channel.latestEventId ?? latestEventIdByRoom[roomId]
        let unreadEventId = channel.unreadEventId ?? latestUnreadEventIdByRoom[roomId]
        markRoomAsRead(roomId: roomId, eventId: eventId, unreadEventId: unreadEventId)
    }

    private func markRoomAsRead(roomId: String, eventId: String?, unreadEventId: String?) {
        guard let roomIndex = rooms.firstIndex(where: { $0.roomId == roomId }) else { return }

        let unread = rooms[roomIndex].unreadCount
        if unread > 0, newMessagesDivider[roomId] == nil {
            let confirmed = (messagesByRoom[roomId] ?? []).filter { $0.eventId != nil }
            if unread <= confirmed.count {
                newMessagesDivider[roomId] = confirmed[confirmed.count - unread].eventId
            }
        }

        rooms[roomIndex].unreadCount = 0
        rooms[roomIndex].mentionCount = 0

        if let unreadEventId {
            readThroughUnreadEventIdByRoom[roomId] = unreadEventId
        }

        if let eventId {
            pendingReadReceipts[roomId] = eventId
        }

        rebuildUIModels()

        if eventId != nil {
            Task { await retryPendingReadReceipts() }
        }
    }

    private func retryPendingReadReceipts() async {
        guard !isSendingReadReceipts, !pendingReadReceipts.isEmpty else { return }
        isSendingReadReceipts = true
        defer { isSendingReadReceipts = false }

        let receiptsToSend = pendingReadReceipts
        for (roomId, eventId) in receiptsToSend {
            do {
                try await client.sendReadReceipt(roomId: roomId, eventId: eventId)
                try await client.setReadMarker(roomId: roomId, fullyRead: eventId, read: eventId)
                if pendingReadReceipts[roomId] == eventId {
                    pendingReadReceipts.removeValue(forKey: roomId)
                }
            } catch {
                // Keep the receipt queued; the next successful sync retries it.
            }
        }
    }

    /// Marks a room read up to `eventId` (or the latest known event) and queues the receipt.
    func markAsRead(roomId: String, eventId: String? = nil) {
        let target = eventId
            ?? latestEventIdByRoom[roomId]
            ?? messagesByRoom[roomId]?.last(where: { $0.eventId != nil })?.eventId
        markRoomAsRead(roomId: roomId, eventId: target, unreadEventId: latestUnreadEventIdByRoom[roomId])
    }

    func isRoomEncrypted(_ roomId: String) -> Bool {
        rooms.first(where: { $0.roomId == roomId })?.isEncrypted ?? false
    }

    func setPresenceStatus(presence: String, statusMsg: String? = nil) async {
        guard let userId else { return }
        try? await client.setPresence(userId: userId, presence: presence, statusMsg: statusMsg)
    }

    func uploadAndSendImage(roomId: String, imageData: Data, filename: String) async {
        do {
            let upload = try await client.uploadMedia(data: imageData, filename: filename, contentType: "image/jpeg")
            try await client.sendImage(roomId: roomId, mxcUrl: upload.contentUri, body: filename, info: [
                "mimetype": "image/jpeg",
                "size": imageData.count
            ])
        } catch {
            self.errorMessage = "Envoi d'image échoué : \(error.localizedDescription)"
        }
    }

    func uploadAndSendFile(roomId: String, fileData: Data, filename: String, contentType: String) async {
        do {
            let upload = try await client.uploadMedia(data: fileData, filename: filename, contentType: contentType)
            try await client.sendFile(roomId: roomId, mxcUrl: upload.contentUri, body: filename, info: [
                "mimetype": contentType,
                "size": fileData.count
            ])
        } catch {
            self.errorMessage = "Envoi de fichier échoué : \(error.localizedDescription)"
        }
    }

    func createRoom(name: String, topic: String = "", isPublic: Bool = false, inviteUserIds: [String] = []) async -> String? {
        do {
            let preset = isPublic ? "public_chat" : "private_chat"
            let response = try await client.createRoom(name: name, topic: topic, inviteUserIds: inviteUserIds, preset: preset)
            return response.roomId
        } catch {
            self.errorMessage = "Création du salon échouée : \(error.localizedDescription)"
            return nil
        }
    }

    func createSpace(name: String, topic: String = "") async -> String? {
        do {
            let response = try await client.createRoom(
                name: name, topic: topic, preset: "private_chat",
                roomType: "m.space",
                initialState: [
                    ["type": "m.room.history_visibility", "state_key": "", "content": ["history_visibility": "shared"]]
                ]
            )
            return response.roomId
        } catch {
            self.errorMessage = "Création de l'espace échouée : \(error.localizedDescription)"
            return nil
        }
    }

    /// Uploads a file picked from the composer's "+" menu; images are sent as m.image.
    func sendAttachment(roomId: String, fileURL: URL) async {
        let didAccess = fileURL.startAccessingSecurityScopedResource()
        defer { if didAccess { fileURL.stopAccessingSecurityScopedResource() } }
        let data: Data
        do {
            data = try Data(contentsOf: fileURL)
        } catch {
            errorMessage = "Impossible de lire \(fileURL.lastPathComponent) : \(error.localizedDescription)"
            return
        }
        let type = UTType(filenameExtension: fileURL.pathExtension) ?? .data
        if type.conforms(to: .image) {
            await uploadAndSendImage(roomId: roomId, imageData: data, filename: fileURL.lastPathComponent)
        } else {
            await uploadAndSendFile(
                roomId: roomId, fileData: data, filename: fileURL.lastPathComponent,
                contentType: type.preferredMIMEType ?? "application/octet-stream"
            )
        }
    }

    /// Discord's "Créer mon serveur": a space plus a first #général channel inside it
    /// (a space with no channel is not shown in the rail). Returns the server's UI id.
    func createServer(name: String, isPublic: Bool) async -> UUID? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let spaceId = await createSpace(name: trimmed) else { return nil }
        guard let channelId = await createRoom(name: "général", isPublic: isPublic) else { return nil }
        do {
            try await client.addSpaceChild(spaceRoomId: spaceId, childRoomId: channelId)
        } catch {
            errorMessage = "Le salon #général n'a pas pu être ajouté au serveur : \(error.localizedDescription)"
            return nil
        }
        return stableUUID(from: spaceId)
    }

    /// Joins from whatever the user pasted: a matrix.to link, a #alias:server or a !roomId:server.
    /// Returns the joined room's UI id (server id when it is a space).
    func joinServer(fromInvite invite: String) async -> UUID? {
        guard let reference = Self.roomReference(fromInvite: invite) else {
            errorMessage = "Lien d'invitation invalide. Exemple : https://matrix.to/#/#salon:serveur.org"
            return nil
        }
        do {
            let response = try await client.joinRoom(reference)
            return stableUUID(from: response.roomId)
        } catch {
            errorMessage = "Impossible de rejoindre : \(error.localizedDescription)"
            return nil
        }
    }

    /// "clara" → "@clara:<my homeserver>", "@clara:matrix.org" unchanged, nil if unusable.
    func matrixUserId(from input: String) -> String? {
        var text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !text.contains(" ") else { return nil }
        if !text.hasPrefix("@") { text = "@" + text }
        if !text.contains(":") {
            guard let domain = userId?.split(separator: ":", maxSplits: 1).last else { return nil }
            text += ":\(domain)"
        }
        return text
    }

    static func roomReference(fromInvite invite: String) -> String? {
        var text = invite.trimmingCharacters(in: .whitespacesAndNewlines)
        if let range = text.range(of: "matrix.to/#/") {
            text = String(text[range.upperBound...])
        }
        if let query = text.firstIndex(of: "?") {
            text = String(text[..<query])
        }
        text = text.removingPercentEncoding ?? text
        guard let first = text.first, first == "#" || first == "!",
              text.contains(":"), !text.contains(" ") else { return nil }
        return text
    }

    func createDM(userId targetUserId: String) async -> String? {
        // Dédup : room direct existante avec exactement ce user
        if let existing = existingDirectRoomId(with: targetUserId) {
            return existing
        }
        if let userId,
           let map = try? await client.getDirectRooms(userId: userId),
           let candidates = map[targetUserId],
           let existing = candidates.first(where: { candidate in rooms.contains { $0.roomId == candidate } }) {
            directRoomIds.insert(existing)
            return existing
        }

        do {
            let response = try await client.createRoom(isDirect: true, inviteUserIds: [targetUserId], preset: "trusted_private_chat")
            directRoomIds.insert(response.roomId)
            await registerDirectRoom(response.roomId, with: targetUserId)
            return response.roomId
        } catch {
            self.errorMessage = "Création du DM échouée : \(error.localizedDescription)"
            return nil
        }
    }

    // Retourne l'id de la DMConversation (existante ou créée), nil si échec
    func openOrCreateDM(with userId: String) async -> UUID? {
        guard let roomId = await createDM(userId: userId) else { return nil }
        if !rooms.contains(where: { $0.roomId == roomId }) {
            var members = [userId: extractLocalpart(userId)]
            if let me = self.userId {
                members[me] = currentUser?.displayName ?? extractLocalpart(me)
            }
            rooms.append(MatrixRoom(
                roomId: roomId, name: extractLocalpart(userId), topic: "", isDirect: true,
                members: members, memberAvatars: [:], unreadCount: 0, mentionCount: 0,
                isEncrypted: false, roomType: nil, spaceChildren: [], avatarUrl: nil, heroes: []
            ))
        }
        rebuildUIModels()
        return stableUUID(from: roomId)
    }

    private func existingDirectRoomId(with targetUserId: String) -> String? {
        rooms.first(where: { room in
            guard room.isDirect, room.roomType != "m.space" else { return false }
            let others = Set(room.members.keys.filter { $0 != userId })
            return others == [targetUserId]
        })?.roomId
    }

    // Merge dans m.direct (account data) pour que les autres clients voient le DM
    private func registerDirectRoom(_ roomId: String, with targetUserId: String) async {
        guard let userId else { return }
        var map = (try? await client.getDirectRooms(userId: userId)) ?? [:]
        var list = map[targetUserId] ?? []
        guard !list.contains(roomId) else { return }
        list.append(roomId)
        map[targetUserId] = list
        try? await client.setDirectRooms(userId: userId, directMap: map)
    }

    func joinRoom(_ roomIdOrAlias: String) async -> Bool {
        do {
            _ = try await client.joinRoom(roomIdOrAlias)
            return true
        } catch {
            self.errorMessage = "Impossible de rejoindre : \(error.localizedDescription)"
            return false
        }
    }

    func leaveRoom(_ roomId: String) async {
        do {
            try await client.leaveRoom(roomId)
            rooms.removeAll { $0.roomId == roomId }
            messagesByRoom.removeValue(forKey: roomId)
            backPaginationTokens.removeValue(forKey: roomId)
            hasMoreHistory.removeValue(forKey: roomId)
            rebuildUIModels()
        } catch {
            self.errorMessage = "Impossible de quitter : \(error.localizedDescription)"
        }
    }

    func inviteUser(roomId: String, userId targetUserId: String) async {
        do {
            try await client.inviteUser(roomId: roomId, userId: targetUserId)
        } catch {
            self.errorMessage = "Invitation échouée : \(error.localizedDescription)"
        }
    }

    func kickUser(roomId: String, userId targetUserId: String, reason: String? = nil) async {
        do {
            try await client.kickUser(roomId: roomId, userId: targetUserId, reason: reason)
        } catch {
            self.errorMessage = "Exclusion échouée : \(error.localizedDescription)"
        }
    }

    func banUser(roomId: String, userId targetUserId: String, reason: String? = nil) async {
        do {
            try await client.banUser(roomId: roomId, userId: targetUserId, reason: reason)
        } catch {
            self.errorMessage = "Bannissement échoué : \(error.localizedDescription)"
        }
    }

    func acceptInvite(roomId: String) async {
        if await joinRoom(roomId) {
            pendingInvites.removeAll { $0.id == roomId }
        }
    }

    func rejectInvite(roomId: String) async {
        await leaveRoom(roomId)
        pendingInvites.removeAll { $0.id == roomId }
    }

    func fetchProfile(userId targetUserId: String) async -> (displayName: String?, avatarUrl: URL?) {
        do {
            let profile = try await client.getProfile(userId: targetUserId)
            let avatarURL = profile.avatarUrl.flatMap { client.resolveMediaURL($0) }
            return (profile.displayname, avatarURL)
        } catch {
            return (nil, nil)
        }
    }

    func updateDisplayName(_ name: String) async {
        guard let userId else { return }
        try? await client.setDisplayName(userId: userId, displayName: name)
    }

    func updateAvatar(imageData: Data, filename: String) async {
        guard let userId else { return }
        do {
            let upload = try await client.uploadMedia(data: imageData, filename: filename, contentType: "image/jpeg")
            try await client.setAvatarUrl(userId: userId, avatarUrl: upload.contentUri)
        } catch {
            self.errorMessage = "Mise à jour de l'avatar échouée : \(error.localizedDescription)"
        }
    }

    func searchUsers(query: String) async -> [MatrixUserResult] {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return [] }
        do {
            let response = try await client.searchUsers(term: trimmed)
            return response.results ?? []
        } catch {
            return []
        }
    }

    func fetchPublicRooms(limit: Int = 50, filter: String? = nil) async -> [MatrixPublicRoom] {
        do {
            let response = try await client.getPublicRooms(limit: limit, filter: filter)
            return response.chunk ?? []
        } catch {
            return []
        }
    }

    func addRoomToSpace(spaceRoomId: String, childRoomId: String) async {
        try? await client.addSpaceChild(spaceRoomId: spaceRoomId, childRoomId: childRoomId)
    }

    func removeRoomFromSpace(spaceRoomId: String, childRoomId: String) async {
        try? await client.removeSpaceChild(spaceRoomId: spaceRoomId, childRoomId: childRoomId)
    }

    func unbanUser(roomId: String, userId targetUserId: String) async {
        do {
            try await client.unbanUser(roomId: roomId, userId: targetUserId)
        } catch {
            self.errorMessage = "Débannissement échoué : \(error.localizedDescription)"
        }
    }

    func setRoomName(roomId: String, name: String) async {
        do {
            try await client.setRoomName(roomId: roomId, name: name)
        } catch {
            self.errorMessage = "Renommage échoué : \(error.localizedDescription)"
        }
    }

    func setRoomTopic(roomId: String, topic: String) async {
        do {
            try await client.setRoomTopic(roomId: roomId, topic: topic)
        } catch {
            self.errorMessage = "Modification du sujet échouée : \(error.localizedDescription)"
        }
    }

    func loadMoreMessages(roomId: String) async {
        guard hasMoreHistory[roomId] ?? true, !paginatingRooms.contains(roomId) else { return }
        guard let token = backPaginationTokens[roomId] else {
            hasMoreHistory[roomId] = false
            return
        }
        paginatingRooms.insert(roomId)
        defer { paginatingRooms.remove(roomId) }

        do {
            let response = try await client.roomMessages(roomId: roomId, from: token, limit: 50)
            let events = response.chunk ?? []
            for event in events {
                insertHistoricalEvent(event, roomId: roomId)
            }
            if let end = response.end, !events.isEmpty {
                backPaginationTokens[roomId] = end
                hasMoreHistory[roomId] = true
            } else {
                hasMoreHistory[roomId] = false
            }
            rebuildUIModels()
        } catch {
            self.errorMessage = "Chargement de l'historique échoué : \(error.localizedDescription)"
        }
    }

    // Comble un trou de timeline (sync limited) en remontant depuis prev_batch
    private func fillGap(roomId: String, from token: String, generation: Int) async {
        guard let response = try? await client.roomMessages(roomId: roomId, from: token, limit: 100) else { return }
        guard generation == syncGeneration else { return }
        var insertedAny = false
        for event in response.chunk ?? [] {
            if let eventId = event.eventId, messageIndex(roomId: roomId, eventId: eventId) != nil {
                break // trou comblé, on a rejoint l'historique connu
            }
            if insertHistoricalEvent(event, roomId: roomId) {
                insertedAny = true
            }
        }
        if insertedAny { rebuildUIModels() }
    }

    @discardableResult
    private func insertHistoricalEvent(_ event: MatrixEvent, roomId: String) -> Bool {
        guard let eventId = event.eventId,
              !redactedEventIds.contains(eventId),
              messageIndex(roomId: roomId, eventId: eventId) == nil,
              let message = makeMessage(from: event, roomId: roomId)
        else { return false }
        insertSorted(message, roomId: roomId)
        return true
    }

    // MARK: - Media URL Resolution

    func resolveMediaURL(_ mxcUrl: String?, width: Int? = nil, height: Int? = nil) -> URL? {
        guard let mxcUrl else { return nil }
        return client.resolveMediaURL(mxcUrl, width: width, height: height)
    }

    // MARK: - Mapping Helpers

    func roomId(for server: MoodServer) -> String? {
        stableIdReverse[server.id]
    }

    func markServerAsRead(_ server: MoodServer) {
        for channel in server.categories.flatMap(\.channels) where channel.unreadCount > 0 || channel.mentionCount > 0 {
            markChannelAsRead(channel)
        }
    }

    /// Discord's "Quitter le serveur": leave every channel of the space, then the space.
    func leaveServer(_ server: MoodServer) async {
        for channel in server.categories.flatMap(\.channels) {
            if let roomId = roomId(for: channel) { await leaveRoom(roomId) }
        }
        if let spaceId = roomId(for: server) { await leaveRoom(spaceId) }
    }

    func roomId(for channel: Channel) -> String? {
        stableIdReverse[channel.id]
    }

    func roomId(for dm: DMConversation) -> String? {
        stableIdReverse[dm.id]
    }

    func messages(for channel: Channel) -> [ChatMessage] {
        guard let roomId = roomId(for: channel) else { return [] }
        return timeline(roomId: roomId)
    }

    func messages(forDM dm: DMConversation) -> [ChatMessage] {
        guard let roomId = roomId(for: dm) else { return [] }
        return timeline(roomId: roomId)
    }

    /// Pins live in room state and can change from any device, so they are applied at read time.
    private func timeline(roomId: String) -> [ChatMessage] {
        let pinned = Set(rooms.first(where: { $0.roomId == roomId })?.pinnedEventIds ?? [])
        var messages = computeGrouping(messagesByRoom[roomId] ?? [])
        if !pinned.isEmpty {
            for index in messages.indices {
                messages[index].isPinned = messages[index].eventId.map(pinned.contains) ?? false
            }
        }
        return messages
    }

    func typingUsers(for channel: Channel) -> [String] {
        guard let roomId = roomId(for: channel) else { return [] }
        return typingUsersByRoom[roomId] ?? []
    }

    func typingUsers(forDM dm: DMConversation) -> [String] {
        guard let roomId = roomId(for: dm) else { return [] }
        return typingUsersByRoom[roomId] ?? []
    }

    private func computeGrouping(_ messages: [ChatMessage]) -> [ChatMessage] {
        var result = messages
        for i in result.indices {
            if i > 0
                && result[i].sender.id == result[i - 1].sender.id
                && result[i].timestamp.timeIntervalSince(result[i - 1].timestamp) < 300 {
                result[i] = ChatMessage(
                    id: result[i].id, sender: result[i].sender,
                    content: result[i].content, timestamp: result[i].timestamp,
                    isGrouped: true, reactions: result[i].reactions,
                    replyTo: result[i].replyTo, attachments: result[i].attachments,
                    isPinned: result[i].isPinned, threadInfo: result[i].threadInfo,
                    isEdited: result[i].isEdited, linkEmbed: result[i].linkEmbed,
                    isSystemMessage: result[i].isSystemMessage, systemType: result[i].systemType,
                    sendState: result[i].sendState, eventId: result[i].eventId, txnId: result[i].txnId
                )
            }
        }
        return result
    }

    // MARK: - Build Current User from Profile

    private func buildCurrentUser(userId: String) async {
        var displayName = extractLocalpart(userId)
        var avatarMxc: String?

        // Try to fetch real profile
        if let profile = try? await client.getProfile(userId: userId) {
            if let name = profile.displayname, !name.isEmpty {
                displayName = name
            }
            avatarMxc = profile.avatarUrl
        }

        // Sync starts by setting presence "online", so that is our status until told otherwise.
        self.currentUser = makeUser(userId, displayName: displayName, avatarMxc: avatarMxc, fallbackStatus: .online)
    }

    // MARK: - Credential Storage (Keychain)

    private func saveCredentials(token: String, userId: String, homeserver: String) {
        KeychainHelper.save(key: "access_token", value: token)
        KeychainHelper.save(key: "user_id", value: userId)
        KeychainHelper.save(key: "homeserver", value: homeserver)
    }

    private func clearCredentials() {
        KeychainHelper.delete(key: "access_token")
        KeychainHelper.delete(key: "user_id")
        KeychainHelper.delete(key: "homeserver")
    }

    // MARK: - Utility

    private func extractLocalpart(_ userId: String) -> String {
        let cleaned = userId.hasPrefix("@") ? String(userId.dropFirst()) : userId
        return cleaned.split(separator: ":").first.map(String.init) ?? userId
    }

    func stableUUID(from string: String) -> UUID {
        if let cached = stableIdCache[string] { return cached }
        var bytes = [UInt8](SHA256.hash(data: Data(string.utf8)).prefix(16))
        bytes[6] = (bytes[6] & 0x0F) | 0x40
        bytes[8] = (bytes[8] & 0x3F) | 0x80
        let uuid = UUID(uuid: (bytes[0], bytes[1], bytes[2], bytes[3],
                               bytes[4], bytes[5], bytes[6], bytes[7],
                               bytes[8], bytes[9], bytes[10], bytes[11],
                               bytes[12], bytes[13], bytes[14], bytes[15]))
        stableIdCache[string] = uuid
        stableIdReverse[uuid] = string
        return uuid
    }

    private func emojiForUser(_ userId: String) -> String {
        let emojis = ["🌊", "🌸", "⚡", "🎨", "🎵", "📚", "🚀", "💎", "🔥", "🌿", "🦋", "🌙", "⭐", "🍀", "🎯"]
        let hash = userId.unicodeScalars.reduce(0) { $0 &+ Int($1.value) }
        return emojis[abs(hash) % emojis.count]
    }

    private func colorForUser(_ userId: String) -> Color {
        let colors: [Color] = [.blue, .purple, .orange, .pink, .green, .red, .cyan, .yellow, .mint, .indigo]
        let hash = userId.unicodeScalars.reduce(0) { $0 &+ Int($1.value) }
        return colors[abs(hash) % colors.count]
    }
}
