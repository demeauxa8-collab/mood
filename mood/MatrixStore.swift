import SwiftUI

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
    private(set) var userId: String?
    private var directRoomIds: Set<String> = []

    // Raw event tracking for reactions/edits/redactions
    private var reactionEvents: [String: [(emoji: String, sender: String, eventId: String)]] = [:] // targetEventId -> reactions
    private var redactedEventIds: Set<String> = []

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
    }

    private var rooms: [MatrixRoom] = []

    // MARK: - Init

    init(homeserver: String = "matrix.org") {
        self.client = MatrixClient(homeserver: homeserver)
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
        await buildCurrentUser(userId: response.userId)
        startSyncLoop()
    }

    func ssoRedirectURL(idpId: String, homeserver: String, redirectURL: String) -> URL? {
        client.setHomeserver(homeserver)
        return client.ssoRedirectURL(idpId: idpId, redirectURL: redirectURL)
    }

    func logout() {
        syncTask?.cancel()
        syncTask = nil
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
        eventIdsByRoom = [:]
        clearCredentials()
    }

    func restoreSession() -> Bool {
        guard let token = KeychainHelper.load(key: "access_token"),
              let userId = KeychainHelper.load(key: "user_id"),
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
                return restoreSession()
            }
            return false
        }

        self.userId = userId
        client.setHomeserver(homeserver)
        client.setAccessToken(token)

        Task { await buildCurrentUser(userId: userId) }
        startSyncLoop()
        return true
    }

    // MARK: - Sync Loop

    private func startSyncLoop() {
        syncTask?.cancel()
        syncTask = Task { [weak self] in
            guard let self else { return }

            // Initial sync
            do {
                let response = try await client.sync(since: nil, timeout: 0)
                self.processSyncResponse(response)
                self.syncToken = response.nextBatch
            } catch {
                if !Task.isCancelled {
                    self.errorMessage = "Sync initiale échouée : \(error.localizedDescription)"
                }
            }

            // Set online presence
            if let userId = self.userId {
                try? await client.setPresence(userId: userId, presence: "online")
            }

            // Long-poll loop
            while !Task.isCancelled {
                do {
                    let response = try await client.sync(since: self.syncToken, timeout: 30000)
                    self.processSyncResponse(response)
                    self.syncToken = response.nextBatch
                } catch {
                    if !Task.isCancelled {
                        try? await Task.sleep(for: .seconds(5))
                    }
                }
            }
        }
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
                isEncrypted: false, roomType: nil, spaceChildren: [], avatarUrl: nil
            )

            room.isDirect = directRoomIds.contains(roomId)

            // Remove from pending invites once joined
            pendingInvites.removeAll { $0.id == roomId }

            // State events
            if let stateEvents = roomData.state?.events {
                for event in stateEvents {
                    processStateEvent(event, room: &room)
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
                room.unreadCount = notifs.notificationCount ?? 0
                room.mentionCount = notifs.highlightCount ?? 0
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

        // Redaction
        if event.type == "m.room.redaction" {
            guard let redactedId = event.redacts else { return }
            redactedEventIds.insert(redactedId)
            // Remove the message from the store
            if let idx = messagesByRoom[roomId]?.firstIndex(where: { stableUUID(from: redactedId) == $0.id }) {
                messagesByRoom[roomId]?.remove(at: idx)
            }
            // Remove associated reactions
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

        // Regular message or edit
        if event.type == "m.room.message" {
            // Check for edit (m.replace)
            if let relatesTo = event.content?["m.relates_to"]?.dictValue,
               let relType = relatesTo["rel_type"]?.stringValue,
               relType == "m.replace",
               let targetEventId = relatesTo["event_id"]?.stringValue {
                // Update the original message content
                let newContent = event.content?["m.new_content"]?.dictValue
                let newBody = newContent?["body"]?.stringValue ?? event.content?["body"]?.stringValue ?? ""

                if let idx = messagesByRoom[roomId]?.firstIndex(where: { stableUUID(from: targetEventId) == $0.id }) {
                    let original = messagesByRoom[roomId]![idx]
                    messagesByRoom[roomId]![idx] = ChatMessage(
                        id: original.id, sender: original.sender, content: newBody,
                        timestamp: original.timestamp, isGrouped: original.isGrouped,
                        reactions: original.reactions, replyTo: original.replyTo,
                        attachments: original.attachments, isPinned: original.isPinned,
                        threadInfo: original.threadInfo, isEdited: true,
                        linkEmbed: original.linkEmbed,
                        isSystemMessage: original.isSystemMessage, systemType: original.systemType
                    )
                }
                return
            }

            // Check if already added
            if messagesByRoom[roomId]?.contains(where: { stableUUID(from: eventId) == $0.id }) == true {
                return
            }

            let chatMessage = convertToChatMessage(event, roomId: roomId)
            if messagesByRoom[roomId] == nil { messagesByRoom[roomId] = [] }
            messagesByRoom[roomId]!.append(chatMessage)
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
              let idx = messagesByRoom[roomId]?.firstIndex(where: { stableUUID(from: targetEventId) == $0.id })
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
            isSystemMessage: original.isSystemMessage, systemType: original.systemType
        )
    }

    // MARK: - Convert to UI Models

    private func convertToChatMessage(_ event: MatrixEvent, roomId: String) -> ChatMessage {
        let senderUserId = event.sender ?? "unknown"
        let room = rooms.first(where: { $0.roomId == roomId })
        let displayName = room?.members[senderUserId] ?? extractLocalpart(senderUserId)
        let body = event.content?["body"]?.stringValue ?? ""
        let msgtype = event.content?["msgtype"]?.stringValue ?? "m.text"
        let timestamp = Date(timeIntervalSince1970: TimeInterval(event.originServerTs ?? 0) / 1000)
        let eventId = event.eventId ?? UUID().uuidString

        // Determine avatar
        let avatarMxc = room?.memberAvatars[senderUserId]
        let avatarEmoji = avatarMxc != nil ? "👤" : emojiForUser(senderUserId)

        // Determine presence-based status
        let presenceInfo = presenceByUser[senderUserId]
        let status: MoodUser.UserStatus = (presenceInfo?.presence == "online" || presenceInfo?.currentlyActive == true) ? .online : .offline

        let sender = MoodUser(
            id: stableUUID(from: senderUserId),
            username: extractLocalpart(senderUserId),
            displayName: displayName,
            avatarEmoji: avatarEmoji,
            roleColor: colorForUser(senderUserId),
            status: status,
            bio: "",
            joinedDate: Date(),
            badges: [],
            activity: nil
        )

        // Parse reply
        var replyTo: ReplyRef?
        if let relatesTo = event.content?["m.relates_to"]?.dictValue,
           let inReplyTo = relatesTo["m.in_reply_to"]?.dictValue,
           let replyEventId = inReplyTo["event_id"]?.stringValue {
            // Find the original message
            if let original = messagesByRoom[roomId]?.first(where: { stableUUID(from: replyEventId) == $0.id }) {
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
        if msgtype == "m.image" {
            let fileName = event.content?["body"]?.stringValue ?? "image"
            attachments.append(MessageAttachment(id: stableUUID(from: "\(eventId)_att"), type: .image, name: fileName, previewEmoji: "🖼️"))
        } else if msgtype == "m.file" {
            let fileName = event.content?["body"]?.stringValue ?? "file"
            attachments.append(MessageAttachment(id: stableUUID(from: "\(eventId)_att"), type: .file, name: fileName, previewEmoji: "📎"))
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

        return ChatMessage(
            id: stableUUID(from: eventId),
            sender: sender,
            content: body,
            timestamp: timestamp,
            isGrouped: false,
            reactions: reactions,
            replyTo: replyTo,
            attachments: attachments,
            isSystemMessage: isSystem,
            systemType: systemType
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
                    isE2E: room.isEncrypted
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
                            name: "SALONS",
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
                    isE2E: room.isEncrypted
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

        // DMs
        self.dmConversations = dmRooms.compactMap { room in
            guard let otherUserId = room.members.keys.first(where: { $0 != self.userId }) else { return nil }
            let displayName = room.members[otherUserId] ?? extractLocalpart(otherUserId)
            let lastMsg = messagesByRoom[room.roomId]?.last
            let lastMessage = lastMsg?.content ?? ""
            let lastDate = lastMsg?.timestamp ?? Date()

            let presence = presenceByUser[otherUserId]
            let status: MoodUser.UserStatus = (presence?.presence == "online" || presence?.currentlyActive == true) ? .online : .offline

            let avatarMxc = room.memberAvatars[otherUserId]

            let participant = MoodUser(
                id: stableUUID(from: otherUserId),
                username: extractLocalpart(otherUserId),
                displayName: displayName,
                avatarEmoji: avatarMxc != nil ? "👤" : emojiForUser(otherUserId),
                roleColor: colorForUser(otherUserId),
                status: status,
                bio: "",
                joinedDate: Date(),
                badges: [],
                activity: nil
            )

            return DMConversation(
                id: stableUUID(from: room.roomId),
                participant: participant,
                lastMessage: lastMessage,
                lastMessageDate: lastDate,
                unreadCount: room.unreadCount
            )
        }.sorted { $0.lastMessageDate > $1.lastMessageDate }
    }

    // MARK: - Public Actions

    func sendMessage(roomId: String, text: String, replyToEventId: String? = nil, threadRootEventId: String? = nil) async {
        do {
            try await client.sendMessage(roomId: roomId, body: text, replyToEventId: replyToEventId, threadRootEventId: threadRootEventId)
        } catch {
            self.errorMessage = "Envoi échoué : \(error.localizedDescription)"
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

    func setTyping(roomId: String, typing: Bool) async {
        guard let userId else { return }
        try? await client.sendTyping(roomId: roomId, userId: userId, typing: typing)
    }

    func markAsRead(roomId: String, eventId: String) async {
        try? await client.sendReadReceipt(roomId: roomId, eventId: eventId)
        try? await client.setReadMarker(roomId: roomId, fullyRead: eventId, read: eventId)
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

    func createDM(userId targetUserId: String) async -> String? {
        do {
            let response = try await client.createRoom(isDirect: true, inviteUserIds: [targetUserId], preset: "trusted_private_chat")

            // Mark as direct in account data
            // The sync loop will pick this up
            return response.roomId
        } catch {
            self.errorMessage = "Création du DM échouée : \(error.localizedDescription)"
            return nil
        }
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

    func searchUsers(term: String) async -> [MatrixUserResult] {
        do {
            let response = try await client.searchUsers(term: term)
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
        do {
            let existing = messagesByRoom[roomId] ?? []
            let firstEventId = existing.first.map { "\($0.id)" }
            let response = try await client.roomMessages(roomId: roomId, from: firstEventId, limit: 50)
            if let events = response.chunk {
                for event in events.reversed() where event.type == "m.room.message" {
                    let msg = convertToChatMessage(event, roomId: roomId)
                    if !(messagesByRoom[roomId]?.contains(where: { $0.id == msg.id }) ?? false) {
                        if messagesByRoom[roomId] == nil { messagesByRoom[roomId] = [] }
                        messagesByRoom[roomId]!.insert(msg, at: 0)
                    }
                }
            }
        } catch {
            self.errorMessage = "Chargement de l'historique échoué : \(error.localizedDescription)"
        }
    }

    // MARK: - Media URL Resolution

    func resolveMediaURL(_ mxcUrl: String?, width: Int? = nil, height: Int? = nil) -> URL? {
        guard let mxcUrl else { return nil }
        return client.resolveMediaURL(mxcUrl, width: width, height: height)
    }

    // MARK: - Mapping Helpers

    func roomId(for channel: Channel) -> String? {
        rooms.first(where: { stableUUID(from: $0.roomId) == channel.id })?.roomId
    }

    func roomId(for dm: DMConversation) -> String? {
        rooms.first(where: { stableUUID(from: $0.roomId) == dm.id })?.roomId
    }

    func messages(for channel: Channel) -> [ChatMessage] {
        guard let roomId = roomId(for: channel) else { return [] }
        return computeGrouping(messagesByRoom[roomId] ?? [])
    }

    func messages(forDM dm: DMConversation) -> [ChatMessage] {
        guard let roomId = roomId(for: dm) else { return [] }
        return computeGrouping(messagesByRoom[roomId] ?? [])
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
                    isSystemMessage: result[i].isSystemMessage, systemType: result[i].systemType
                )
            }
        }
        return result
    }

    // MARK: - Build Current User from Profile

    private func buildCurrentUser(userId: String) async {
        var displayName = extractLocalpart(userId)
        var avatarEmoji = emojiForUser(userId)

        // Try to fetch real profile
        if let profile = try? await client.getProfile(userId: userId) {
            if let name = profile.displayname, !name.isEmpty {
                displayName = name
            }
            if profile.avatarUrl != nil {
                avatarEmoji = "👤"
            }
        }

        self.currentUser = MoodUser(
            id: stableUUID(from: userId),
            username: extractLocalpart(userId),
            displayName: displayName,
            avatarEmoji: avatarEmoji,
            roleColor: .blue,
            status: .online,
            bio: "",
            joinedDate: Date(),
            badges: [],
            activity: nil
        )
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
        var hash = [UInt8](repeating: 0, count: 16)
        let bytes = Array(string.utf8)
        for (i, byte) in bytes.enumerated() {
            hash[i % 16] ^= byte &+ UInt8(truncatingIfNeeded: i)
        }
        hash[6] = (hash[6] & 0x0F) | 0x40
        hash[8] = (hash[8] & 0x3F) | 0x80
        return UUID(uuid: (hash[0], hash[1], hash[2], hash[3],
                           hash[4], hash[5], hash[6], hash[7],
                           hash[8], hash[9], hash[10], hash[11],
                           hash[12], hash[13], hash[14], hash[15]))
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
