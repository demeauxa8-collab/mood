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
    /// My chosen status; Matrix presence cannot express "Ne pas déranger", so it is kept here.
    private(set) var myStatus: MoodUser.UserStatus = .online
    private(set) var myStatusMessage: String?
    private var currentAvatarMxc: String?
    /// m.direct: room → the person of a 1:1 DM (the reliable source of a DM's peer).
    private var directPeerByRoom: [String: String] = [:]
    /// Profiles of DM peers whose member event the lazy-loaded sync did not bring.
    private var peerProfiles: [String: MatrixProfileResponse] = [:]
    private var peerProfileRequests: Set<String> = []
    /// The 1:1 DM shown for each person when two exist (both sides started one).
    private var shownDirectRoomByPeer: [String: String] = [:]
    /// m.ignored_user_list — Discord's "Bloqués".
    private(set) var ignoredUserIds: Set<String> = []

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
        /// `is_direct` on my invite: a DM, to file under m.direct once accepted.
        var isDirect = false
        /// The inviter's display name, fetched after the invite arrives.
        var inviterName: String?
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

    // Outbox (file hors-ligne) — per-room delivery lanes live in "Messaging pipeline" below
    private let outbox: MessageOutbox
    private let reachability: NetworkReachability
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
    struct MatrixRoom: Codable {
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
        var powerLevels: [String: Int] = [:] // m.room.power_levels users
        var powerLevelsContent: [String: AnyCodable] = [:] // full event, re-sent when a role changes
        var creator: String? // sender of m.room.create
        var bannedUsers: [String: String] = [:] // userId -> display name
    }

    private var rooms: [MatrixRoom] = []

    // MARK: - Disk cache
    private var syncCache: SyncCache?
    /// Raw timeline events kept for the disk cache (last `SyncCache.eventsPerRoom` per room).
    private var cachedTimelines: [String: [MatrixEvent]] = [:]
    private var cacheSaveTask: Task<Void, Never>?
    /// After restoring from cache, rooms absent from the first full sync were left meanwhile.
    private var pruneUnseenRoomsOnNextSync = false

    // MARK: - Init

    init(homeserver: String = "matrix.org") {
        self.client = MatrixClient(homeserver: homeserver)
        self.outbox = MessageOutbox()
        self.reachability = NetworkReachability()
        self.reachability.onReconnect = { [weak self] in
            self?.flushOutbox()
        }
        configureNotifications()
    }

    // MARK: - Auth

    /// Password login (manual Matrix account). The token login below does the session switch, so a
    /// password login gets the same handling: token handed to the client, old session cleared, sync restarted.
    func login(username: String, password: String, homeserver: String) async throws {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        let response = try await MatrixClient(homeserver: homeserver).login(username: username, password: password)
        try await login(accessToken: response.accessToken, userId: response.userId,
                        homeserver: homeserver, deviceId: response.deviceId)
    }

    func login(accessToken: String, userId: String, homeserver: String, deviceId: String) async throws {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        // Validate before replacing the active session or its persisted credentials.
        let verifier = MatrixClient(homeserver: homeserver)
        verifier.setAccessToken(accessToken)
        guard try await verifier.whoami() == userId else { throw AccountError.invalidResponse }
        if let previous = self.userId, previous != userId { clearLocalSession() }
        syncTask?.cancel()
        syncGeneration += 1
        client.setHomeserver(homeserver)
        client.setAccessToken(accessToken)
        self.userId = userId
        saveCredentials(token: accessToken, userId: userId, homeserver: homeserver)
        UserDefaults.standard.set(deviceId, forKey: "mood.matrix.active_device_id")
        syncToken = nil
        UserDefaults.standard.removeObject(forKey: Self.syncTokenKey)
        restoreFromCache(userId: userId)
        restoreOutboxEchoes()
        await buildCurrentUser(userId: userId)
        startSyncLoop()
        flushOutbox()
    }

    func register(username: String, password: String, homeserver: String) async throws {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        let response = try await MatrixClient(homeserver: homeserver).register(username: username, password: password)
        try await login(accessToken: response.accessToken, userId: response.userId,
                        homeserver: homeserver, deviceId: response.deviceId)
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
        clearLocalSession()
    }

    private func clearLocalSession() {
        syncTask?.cancel()
        syncTask = nil
        syncGeneration += 1
        resetMessagingPipeline()
        resetMessagingServersUI()
        resetFinishBasics()
        resetConversation()
        syncToken = nil
        userId = nil
        currentUser = nil
        rooms = []
        servers = []
        dmConversations = []
        messagesByRoom = [:]
        directRoomIds = []
        directPeerByRoom = [:]
        peerProfiles = [:]
        peerProfileRequests = []
        shownDirectRoomByPeer = [:]
        groupDirectRoomIds = []
        pendingDirectRooms.values.forEach { $0.cancel() }
        pendingDirectRooms = [:]
        typingUsersByRoom = [:]
        presenceByUser = [:]
        pendingInvites = []
        ignoredUserIds = []
        myStatus = .online
        myStatusMessage = nil
        currentAvatarMxc = nil
        supportsExtendedAccountProfile = false
        client.setSyncPresence("online")
        extendedProfiles = [:]
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
        cacheSaveTask?.cancel()
        syncCache?.delete()
        syncCache = nil
        cachedTimelines = [:]
        clearCredentials()
        resetNotificationState()
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

        // Show the cached rooms and messages right away, then let a full sync
        // (no `since`) bring the truth: an incremental sync would only return rooms that
        // changed meanwhile, and nothing else survives a relaunch.
        syncToken = nil
        UserDefaults.standard.removeObject(forKey: Self.syncTokenKey)
        restoreFromCache(userId: self.userId ?? storedUserId)
        restoreOutboxEchoes()
        Task { await buildCurrentUser(userId: self.userId ?? storedUserId) }
        startSyncLoop()
        flushOutbox()
        return true
    }

    // MARK: - Disk Cache

    private func restoreFromCache(userId: String) {
        syncCache = SyncCache(userId: userId)
        guard let snapshot = syncCache?.load() else { return }
        rooms = snapshot.rooms
        directRoomIds = Set(snapshot.directRoomIds)
        ignoredUserIds = Set(snapshot.ignoredUserIds)
        cachedTimelines = snapshot.timelines
        for (roomId, events) in snapshot.timelines {
            for event in events {
                processTimelineEvent(event, roomId: roomId)
            }
        }
        pruneUnseenRoomsOnNextSync = true
        rebuildUIModels()
    }

    private func rememberForCache(_ events: [MatrixEvent], roomId: String) {
        var list = cachedTimelines[roomId] ?? []
        let known = Set(list.compactMap(\.eventId))
        list.append(contentsOf: events.filter { $0.eventId.map { !known.contains($0) } ?? false })
        if list.count > SyncCache.eventsPerRoom {
            list.removeFirst(list.count - SyncCache.eventsPerRoom)
        }
        cachedTimelines[roomId] = list
    }

    /// Debounced: a burst of syncs (catch-up after being offline) writes the file once.
    private func scheduleCacheSave() {
        cacheSaveTask?.cancel()
        cacheSaveTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2))
            guard let self, !Task.isCancelled else { return }
            if self.syncCache == nil, let userId = self.userId {
                self.syncCache = SyncCache(userId: userId) // first session after login
            }
            guard let syncCache = self.syncCache else { return }
            syncCache.save(SyncSnapshot(
                rooms: self.rooms,
                timelines: self.cachedTimelines,
                directRoomIds: Array(self.directRoomIds),
                ignoredUserIds: Array(self.ignoredUserIds)
            ))
        }
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
                    self.handleSyncForNotifications(response, isInitialSync: self.syncToken == nil)
                    self.syncToken = response.nextBatch
                    self.scheduleCacheSave()
                    backoff = 1
                    // A sync that went through means the server is back: send what waited.
                    self.flushOutbox()
                    await self.retryPendingReadReceipts()

                    if isFirstSync {
                        isFirstSync = false
                        if self.userId != nil {
                            await self.setPresenceStatus(presence: Self.matrixPresence(for: self.myStatus), statusMsg: self.myStatusMessage)
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
            for event in accountEvents where event.type == "m.ignored_user_list" {
                ignoredUserIds = Set(event.content?["ignored_users"]?.dictValue?.keys.map { $0 } ?? [])
            }
            for event in accountEvents where event.type == "m.direct" {
                if let content = event.content {
                    var dmIds = Set<String>()
                    var peerCounts: [String: Int] = [:]
                    var peers: [String: String] = [:]
                    for (peer, roomList) in content {
                        if let arr = roomList.arrayValue {
                            for item in arr {
                                if let roomId = item.stringValue {
                                    dmIds.insert(roomId)
                                    peerCounts[roomId, default: 0] += 1
                                    peers[roomId] = peer
                                }
                            }
                        }
                    }
                    directRoomIds = dmIds
                    directPeerByRoom = peers.filter { peerCounts[$0.key] == 1 && $0.value != userId }
                    // Rooms already shown move to (or out of) the DM list right away.
                    for index in rooms.indices { rooms[index].isDirect = dmIds.contains(rooms[index].roomId) }
                    groupDirectRoomIds = Set(peerCounts.filter { $0.value > 1 }.keys)
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
                var isDirect = false
                var memberNames: [String: String] = [:]
                if let events = inviteData.inviteState?.events {
                    for event in events {
                        if event.type == "m.room.name", let name = event.content?["name"]?.stringValue {
                            roomName = name
                        }
                        if event.type == "m.room.member", let member = event.stateKey,
                           let name = event.content?["displayname"]?.stringValue {
                            memberNames[member] = name
                        }
                        if event.type == "m.room.member", event.stateKey == userId,
                           let sender = event.sender {
                            inviter = sender
                            isDirect = event.content?["is_direct"]?.boolValue ?? false
                        }
                    }
                }
                if !pendingInvites.contains(where: { $0.id == roomId }) {
                    pendingInvites.append(PendingInvite(id: roomId, roomName: roomName, inviter: inviter,
                                                        isDirect: isDirect, inviterName: memberNames[inviter]))
                    if memberNames[inviter] == nil, !inviter.isEmpty {
                        Task { [weak self] in
                            guard let self, let name = await self.fetchProfile(userId: inviter).displayName,
                                  let index = self.pendingInvites.firstIndex(where: { $0.id == roomId }) else { return }
                            self.pendingInvites[index].inviterName = name
                        }
                    }
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
        if pruneUnseenRoomsOnNextSync {
            pruneUnseenRoomsOnNextSync = false
            let joined = Set(response.rooms?.join?.keys.map { $0 } ?? [])
            for roomId in rooms.map(\.roomId) where !joined.contains(roomId) {
                directRoomIds.remove(roomId)
            rooms.removeAll { $0.roomId == roomId }
                messagesByRoom.removeValue(forKey: roomId)
                cachedTimelines.removeValue(forKey: roomId)
            }
        }
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

            // Pagination : prev_batch du sync = point de départ, limited = trou à combler.
            // A gap exists when the oldest event of a limited timeline is unknown — including on the
            // first full sync after a cache restore, so edits and deletions made meanwhile still arrive.
            if let timeline = roomData.timeline {
                let hadMessages = !(messagesByRoom[roomId]?.isEmpty ?? true)
                let oldestNewEventId = timeline.events?.first?.eventId
                let hasGap = timeline.limited == true && hadMessages
                    && oldestNewEventId.map { !isKnownEvent($0, roomId: roomId) } == true
                // A room just joined (an accepted DM, a channel) comes as a limited timeline holding
                // only my join: the messages sent before it must be fetched, or the first DM is lost.
                let bringsMessages = timeline.events?.contains { $0.type == "m.room.message" || $0.type == "m.sticker" } ?? false
                let joinedWithoutHistory = timeline.limited == true && !hadMessages && !bringsMessages
                    && room.roomType != "m.space"
                if let prevBatch = timeline.prevBatch, backPaginationTokens[roomId] == nil {
                    backPaginationTokens[roomId] = prevBatch
                    hasMoreHistory[roomId] = true
                }
                if hasGap || joinedWithoutHistory, let prevBatch = timeline.prevBatch {
                    let generation = syncGeneration
                    Task { [weak self] in
                        await self?.fillGap(roomId: roomId, from: prevBatch, generation: generation)
                    }
                }
            }

            applyConversationSync(roomId: roomId, data: roomData)

            // Timeline events
            if let timelineEvents = roomData.timeline?.events {
                for event in timelineEvents {
                    if event.stateKey != nil {
                        processStateEvent(event, room: &room)
                    }
                    processTimelineEvent(event, roomId: roomId)
                }
                rememberForCache(timelineEvents, roomId: roomId)
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
                    // With unread_thread_notifications the room count leaves threads out: add them back,
                    // a channel badge counts every unread message like Discord.
                    let threads = roomData.unreadThreadNotifications?.values.map { $0 } ?? []
                    room.unreadCount = (notifs.notificationCount ?? 0) + threads.reduce(0) { $0 + ($1.notificationCount ?? 0) }
                    room.mentionCount = (notifs.highlightCount ?? 0) + threads.reduce(0) { $0 + ($1.highlightCount ?? 0) }
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
        conversationHasSynced = true
        if let url = pendingConversationLink {
            pendingConversationLink = nil
            openConversationLink(url)
        }
        scheduleDirectRepair()
        for space in rooms where space.roomType == "m.space" {
            Task { await joinServerChannels(space.roomId) }
        }
    }

    private func processStateEvent(_ event: MatrixEvent, room: inout MatrixRoom) {
        rememberDirectEvidence(event, roomId: room.roomId)
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
                if membership == "ban" {
                    room.bannedUsers[memberUserId] = event.content?["displayname"]?.stringValue ?? extractLocalpart(memberUserId)
                } else {
                    room.bannedUsers.removeValue(forKey: memberUserId)
                }
            }
        case "m.room.join_rules":
            messagingJoinRules[room.roomId] = event.content?["join_rule"]?.stringValue
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
            room.creator = event.content?["creator"]?.stringValue ?? event.sender
        case "m.room.power_levels":
            var levels: [String: Int] = [:]
            for (user, level) in event.content?["users"]?.dictValue ?? [:] {
                levels[user] = level.intValue ?? 0
            }
            room.powerLevels = levels
            room.powerLevelsContent = event.content ?? [:]
        case "m.space.child":
            if let childRoomId = event.stateKey {
                messagingChannelOrders[room.roomId, default: [:]][childRoomId] = event.content?["order"]?.stringValue
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
            guard let redactedId = event.redacts ?? event.content?["redacts"]?.stringValue else { return }
            applyRedaction(of: redactedId, roomId: roomId)
            return
        }

        // Reaction
        if event.type == "m.reaction" {
            recordReaction(event, eventId: eventId, roomId: roomId)
            return
        }

        if event.stateKey != nil, let system = conversationSystemMessage(event, roomId: roomId),
           messageIndex(roomId: roomId, eventId: eventId) == nil {
            insertSorted(system, roomId: roomId)
            return
        }
        guard event.type == "m.room.message" || event.type == "m.room.encrypted" else { return }

        // Already deleted (the server sends it with its content stripped): Discord shows nothing.
        if Self.isRedactedEvent(event) {
            redactedEventIds.insert(eventId)
            if let idx = messageIndex(roomId: roomId, eventId: eventId) {
                messagesByRoom[roomId]?.remove(at: idx)
            }
            return
        }

        // Edit (m.replace)
        if event.type == "m.room.message", Self.replacedEventId(of: event) != nil {
            recordEdit(event, eventId: eventId, roomId: roomId)
            return
        }

        if let root = ConversationPolicy.threadRoot(event), messageIndex(roomId: roomId, eventId: eventId) == nil,
           let count = conversationSummaries[root] {
            conversationSummaries[root] = count + 1
        }

        // Écho serveur d'un envoi local : remplace le message local au lieu de dupliquer
        if let txn = event.transactionId,
           let idx = messagesByRoom[roomId]?.firstIndex(where: { $0.txnId == txn }) {
            let localId = messagesByRoom[roomId]![idx].id
            messagesByRoom[roomId]?.remove(at: idx)
            if let failed = failedOutgoing.removeValue(forKey: txn) { outbox.deleteFiles(of: failed) }
            outbox.remove(txnId: txn)
            uploadProgress.removeValue(forKey: txn)
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
        if let root = ConversationPolicy.threadRoot(event), let id = event.eventId { conversationRoots[id] = root }
        if event.stateKey != nil { return conversationSystemMessage(event, roomId: roomId) }
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
            for (eventId, payload) in event.content ?? [:] {
                for reader in payload.dictValue?["m.read"]?.dictValue?.keys ?? Dictionary<String, AnyCodable>().keys {
                    messagingReceipts[roomId, default: [:]][reader] = eventId
                }
            }
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

        messagesByRoom[roomId]![idx].reactions = messageReactions
    }

    // MARK: - Convert to UI Models

    private func convertToChatMessage(_ event: MatrixEvent, roomId: String, overrideId: UUID? = nil, overrideBody: String? = nil) -> ChatMessage {
        let senderUserId = event.sender ?? "unknown"
        let room = rooms.first(where: { $0.roomId == roomId })
        // Lazy-loaded members often lack the sender: use (and fetch once) its profile instead of the id.
        let displayName = room?.members[senderUserId] ?? peerProfiles[senderUserId]?.displayname ?? extractLocalpart(senderUserId)
        if room?.members[senderUserId] == nil, senderUserId.hasPrefix("@") { loadPeerProfile(senderUserId) }
        let body = overrideBody ?? event.content?["body"]?.stringValue ?? ""
        let msgtype = overrideBody != nil ? "m.text" : (event.content?["msgtype"]?.stringValue ?? "m.text")
        let timestamp = Date(timeIntervalSince1970: TimeInterval(event.originServerTs ?? 0) / 1000)
        let eventId = event.eventId ?? UUID().uuidString

        let sender = makeUser(senderUserId, displayName: displayName,
                              avatarMxc: room?.memberAvatars[senderUserId] ?? peerProfiles[senderUserId]?.avatarUrl)

        // Parse reply
        var replyTo: ReplyRef?
        if let relatesTo = event.content?["m.relates_to"]?.dictValue,
           let inReplyTo = relatesTo["m.in_reply_to"]?.dictValue,
           let replyEventId = inReplyTo["event_id"]?.stringValue {
            // Find the original message
            if let idx = messageIndex(roomId: roomId, eventId: replyEventId) {
                let original = messagesByRoom[roomId]![idx]
                replyTo = ReplyRef(sender: original.sender, content: original.content, eventId: replyEventId)
            } else {
                replyTo = ReplyRef(sender: makeUser("unknown", displayName: "Message cité"), content: "Voir le message", eventId: replyEventId)
            }
        }

        // Parse attachments
        var attachments: [MessageAttachment] = []
        if msgtype == "m.image" || msgtype == "m.file" || msgtype == "m.video" || msgtype == "m.audio" {
            let isImage = msgtype == "m.image"
            let fileName = event.content?["filename"]?.stringValue ?? event.content?["body"]?.stringValue ?? (isImage ? "image" : "fichier")
            let mxc = event.content?["url"]?.stringValue
            let info = event.content?["info"]?.dictValue
            let width = info?["w"]?.intValue
            let height = info?["h"]?.intValue
            attachments.append(MessageAttachment(
                id: stableUUID(from: "\(eventId)_att"),
                type: isImage ? .image : .file,
                name: fileName,
                previewEmoji: isImage ? "🖼️" : "📎",
                url: resolveMediaURL(mxc),
                thumbnailURL: isImage ? previewURL(mxc: mxc, thumbnailMxc: info?["thumbnail_url"]?.stringValue, width: width, height: height) : nil,
                size: info?["size"]?.intValue,
                width: width,
                height: height
            ))
        }

        // An edit can arrive before its original (history is read newest first).
        var editedBody: String?
        if let edit = latestEdits[eventId], edit.sender == senderUserId {
            editedBody = edit.body
        }

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
            content: attachments.isEmpty ? (editedBody ?? body) : "",
            timestamp: timestamp,
            isGrouped: false,
            reactions: reactions,
            replyTo: replyTo,
            attachments: attachments,
            isEdited: editedBody != nil,
            isSystemMessage: false,
            sendState: .sent,
            eventId: event.eventId,
            txnId: event.transactionId
        )
        message.isOwn = senderUserId == userId
        return message
    }

    /// Everyone in the space or one of its channels, with Discord-style roles from power levels.
    private func members(of space: MatrixRoom, channels: [MatrixRoom]) -> (users: [MoodUser], roles: [UUID: ServerRole]) {
        var names: [String: String] = [:]
        var avatars: [String: String] = [:]
        for room in [space] + channels {
            names.merge(room.members) { current, _ in current }
            avatars.merge(room.memberAvatars) { current, _ in current }
        }
        var roles: [UUID: ServerRole] = [:]
        let users = names.map { matrixUserId, displayName -> MoodUser in
            let user = makeUser(matrixUserId, displayName: displayName, avatarMxc: avatars[matrixUserId],
                                fallbackStatus: matrixUserId == userId ? .online : .offline)
            let level = space.powerLevels[matrixUserId] ?? 0
            if matrixUserId == space.creator {
                roles[user.id] = .owner
            } else if level >= 75 {
                roles[user.id] = .admin
            } else if level >= 50 {
                roles[user.id] = .moderator
            }
            return user
        }.sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
        return (users, roles)
    }

    /// The signed-in user for display. While the profile loads, show the Matrix id rather than
    /// demo data; demo data only exists without a session (developer -uiPreview launches).
    var me: MoodUser {
        if let currentUser { return currentUser }
        if let userId { return makeUser(userId, fallbackStatus: myStatus) }
        return MockData.currentUser
    }

    /// Single place that turns a Matrix user into a UI user (real avatar, presence, Matrix id).
    func makeUser(_ matrixUserId: String, displayName: String? = nil, avatarMxc: String? = nil,
                  fallbackStatus: MoodUser.UserStatus = .offline) -> MoodUser {
        let presenceInfo = presenceByUser[matrixUserId]
        let status: MoodUser.UserStatus
        let isMe = matrixUserId == userId
        switch isMe ? nil : presenceInfo?.presence {
        case nil where isMe: status = myStatus
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
            bio: (isMe ? myStatusMessage : presenceInfo?.statusMsg) ?? "",
            joinedDate: Date(),
            badges: [],
            activity: nil,
            matrixId: matrixUserId,
            avatarURL: resolveMediaURL(avatarMxc, width: 96, height: 96)
        )
    }

    private func rebuildUIModels() {
        filterBlockedAccountMessages()
        // Separate spaces, group rooms, and DM rooms
        let spaceRooms = rooms.filter { $0.roomType == "m.space" }
        let dmRooms = rooms.filter { $0.isDirect && $0.roomType != "m.space" }
        let normalRooms = rooms.filter { !$0.isDirect && $0.roomType != "m.space" }

        // Build servers from spaces
        var builtServers: [MoodServer] = []

        for space in spaceRooms {
            let childRoomIds = Set(space.spaceChildren)
            let childRooms = rooms.filter { childRoomIds.contains($0.roomId) && !$0.isDirect }.sorted {
                let left = messagingChannelOrders[space.roomId]?[$0.roomId] ?? "~"
                let right = messagingChannelOrders[space.roomId]?[$1.roomId] ?? "~"
                return left == right ? $0.roomId < $1.roomId : left < right
            }

            let channels = childRooms.map { room in
                Channel(
                    id: stableUUID(from: room.roomId),
                    name: room.name,
                    type: .text,
                    topic: room.topic,
                    unreadCount: max(room.unreadCount, conversationMarkedRooms.contains(room.roomId) ? 1 : 0),
                    mentionCount: room.mentionCount,
                    isE2E: room.isEncrypted,
                    latestEventId: latestEventIdByRoom[room.roomId],
                    unreadEventId: latestUnreadEventIdByRoom[room.roomId]
                )
            }

            if space.roomType == "m.space" {
                let serverMembers = members(of: space, channels: childRooms)
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
                    members: serverMembers.users,
                    memberRoles: serverMembers.roles,
                    hasUnread: childRooms.contains(where: { $0.unreadCount > 0 }),
                    mentionCount: childRooms.reduce(0) { $0 + $1.mentionCount },
                    iconURL: resolveMediaURL(space.avatarUrl, width: 96, height: 96)
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
                    unreadCount: max(room.unreadCount, conversationMarkedRooms.contains(room.roomId) ? 1 : 0),
                    mentionCount: room.mentionCount,
                    isE2E: room.isEncrypted,
                    latestEventId: latestEventIdByRoom[room.roomId],
                    unreadEventId: latestUnreadEventIdByRoom[room.roomId]
                )
            }

            let server = MoodServer(
                id: stableUUID(from: "matrix-all-rooms"),
                name: "Salons",
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
        self.dmConversations = dedupedDirectRooms(dmRooms).map { room in
            let isGroup = isGroupDirectRoom(room)
            let otherUserId = directPeer(of: room)

            let displayName: String
            if isGroup {
                displayName = room.name == room.roomId ? "Groupe privé" : room.name
            } else if let otherUserId {
                displayName = room.members[otherUserId] ?? peerProfiles[otherUserId]?.displayname ?? extractLocalpart(otherUserId)
                if room.members[otherUserId] == nil { loadPeerProfile(otherUserId) }
            } else if !room.name.isEmpty && room.name != room.roomId {
                displayName = room.name
            } else {
                displayName = "Conversation"
            }

            let lastMsg = messagesByRoom[room.roomId]?.last
            let lastMessage = lastMsg?.content ?? ""
            let lastDate = lastMsg?.timestamp ?? Date()

            let avatarMxc = otherUserId.flatMap { room.memberAvatars[$0] ?? peerProfiles[$0]?.avatarUrl }
            let participant = makeUser(isGroup ? room.roomId : (otherUserId ?? room.roomId), displayName: displayName, avatarMxc: avatarMxc ?? room.avatarUrl)

            return DMConversation(
                id: stableUUID(from: room.roomId),
                participant: participant,
                lastMessage: lastMessage,
                lastMessageDate: lastDate,
                unreadCount: max(room.unreadCount, conversationMarkedRooms.contains(room.roomId) ? 1 : 0),
                latestEventId: latestEventIdByRoom[room.roomId],
                unreadEventId: latestUnreadEventIdByRoom[room.roomId]
            )
        }.sorted { $0.lastMessageDate > $1.lastMessageDate }
        rebuildLocalMentions()
    }

    // MARK: - Public Actions

    // Écho local immédiat + envoi via la file hors-ligne : jamais bloquant pour l'UI
    // MARK: - Friends (Matrix has no friend graph: friends are the people you have a DM with)

    var friends: [MoodUser] {
        var seen = Set<UUID>()
        return dmConversations.map(\.participant).filter { user in
            guard let matrixId = user.matrixId, matrixId.hasPrefix("@"), !ignoredUserIds.contains(matrixId) else { return false }
            return seen.insert(user.id).inserted
        }
    }

    var blockedUsers: [MoodUser] {
        ignoredUserIds.sorted().map { id in
            let room = rooms.first { $0.members[id] != nil }
            return makeUser(id, displayName: room?.members[id], avatarMxc: room?.memberAvatars[id])
        }
    }

    func setBlocked(_ matrixUserId: String, blocked: Bool) async {
        guard let userId else { return }
        var ignored = ignoredUserIds
        if blocked { ignored.insert(matrixUserId) } else { ignored.remove(matrixUserId) }
        do {
            try await client.setIgnoredUsers(userId: userId, ignored: Array(ignored))
            ignoredUserIds = ignored
            for roomId in messagesByRoom.keys {
                messagesByRoom[roomId]?.removeAll { $0.sender.matrixId.map(ignored.contains) ?? false }
            }
            rebuildUIModels()
            scheduleCacheSave()
        } catch {
            errorMessage = "Impossible de modifier la liste des bloqués : \(error.localizedDescription)"
        }
    }

    /// Servers (spaces) where this user is also a member — the profile card's "serveurs en commun".
    func mutualServers(with user: MoodUser) -> [MoodServer] {
        servers.filter { server in server.members.contains { $0.id == user.id } }
    }

    /// The profile card's "Envoyer un message à @x": opens (or creates) the DM and sends there.
    func sendDirectMessage(to matrixUserId: String, text: String) async -> UUID? {
        guard let conversationId = await openOrCreateDM(with: matrixUserId),
              let roomId = stableIdReverse[conversationId] else { return nil }
        await sendMessage(roomId: roomId, text: text)
        return conversationId
    }

    /// Discord's "Retirer l'ami": leave the DM room with them.
    func removeFriend(_ matrixUserId: String) async {
        guard let roomId = existingDirectRoomId(with: matrixUserId) else { return }
        await leaveRoom(roomId)
    }

    func clearNewMessagesDivider(roomId: String) {
        newMessagesDivider.removeValue(forKey: roomId)
    }

    /// Called when the user leaves a channel or DM (UI ids are stable hashes of room ids).
    func clearNewMessagesDivider(forConversationID id: UUID) {
        if let roomId = stableIdReverse[id] { clearNewMessagesDivider(roomId: roomId) }
    }

    func sendMessage(roomId: String, text: String, replyToEventId: String? = nil, threadRootEventId: String? = nil) async {
        guard validateOutgoingText(text) else { return }
        clearNewMessagesDivider(roomId: roomId)
        let txnId = UUID().uuidString
        let formatted = formatOutgoing(text, roomId: roomId)
        var mentions = formatted.mentionedUserIds
        // Like Discord, a reply pings the author of the message it answers.
        if let replyToEventId, let author = senderId(ofEventId: replyToEventId, roomId: roomId),
           author != userId, !mentions.contains(author) {
            mentions.append(author)
        }
        let echo = makeLocalEcho(roomId: roomId, body: text, txnId: txnId, replyToEventId: replyToEventId)
        if let threadRootEventId { conversationRoots[txnId] = threadRootEventId }
        insertSorted(echo, roomId: roomId)
        rebuildUIModels()

        outbox.enqueue(OutgoingMessage(
            txnId: txnId, roomId: roomId, body: text,
            replyToEventId: replyToEventId, threadRootEventId: threadRootEventId,
            createdAt: Date(),
            formattedBody: formatted.formattedBody,
            mentionUserIds: mentions,
            mentionsRoom: formatted.mentionsRoom
        ))
        flushOutbox()
    }

    func retryMessage(_ localId: UUID, roomId: String) {
        guard var list = messagesByRoom[roomId],
              let idx = list.firstIndex(where: { $0.id == localId }),
              list[idx].sendState == .failed,
              let txnId = list[idx].txnId
        else { return }

        let item: OutgoingMessage
        if let failed = failedOutgoing.removeValue(forKey: txnId) {
            item = failed
        } else {
            guard !list[idx].content.isEmpty else { return } // an attachment needs its queued copy
            item = OutgoingMessage(
                txnId: txnId, roomId: roomId, body: list[idx].content,
                replyToEventId: nil, threadRootEventId: nil, createdAt: list[idx].timestamp
            )
        }
        list[idx].sendState = .sending
        messagesByRoom[roomId] = list
        outbox.enqueue(item)
        flushOutbox()
    }

    // MARK: - Outbox

    private enum DeliveryResult {
        /// `failed` carries a message for the banner when the reason is worth explaining.
        case sent, failed(String?), unreachable, sessionExpired, cancelled
    }

    /// Starts a delivery lane for every room with something queued (rooms already running are left alone).
    private func flushOutbox() {
        guard userId != nil, reachability.isConnected else { return }
        for roomId in outbox.roomIds where outboxLanes[roomId] == nil {
            startOutboxLane(roomId: roomId)
        }
    }

    private func startOutboxLane(roomId: String) {
        let laneId = UUID()
        outboxLanes[roomId] = OutboxLane(id: laneId, task: Task { [weak self] in
            await self?.runOutboxLane(roomId: roomId, laneId: laneId)
        })
    }

    /// Sends one room's queue strictly in order. Offline or server unreachable: the lane stops and
    /// the message waits (the next sync, reconnection or retry timer restarts it). A message the
    /// server rejects is marked failed and the lane moves on.
    private func runOutboxLane(roomId: String, laneId: UUID) async {
        defer {
            if outboxLanes[roomId]?.id == laneId { outboxLanes[roomId] = nil }
        }
        while let item = outbox.next(in: roomId) {
            guard !Task.isCancelled, reachability.isConnected, userId != nil else { return }
            let result = await deliver(item)
            guard !Task.isCancelled else { return }

            switch result {
            case .sent:
                outboxRetryDelay = Self.outboxRetryBaseDelay
                outbox.remove(txnId: item.txnId)
                rebuildUIModels()
            case .failed(let reason):
                let latest = outbox.message(txnId: item.txnId) ?? item // keeps an upload already done
                outbox.remove(txnId: item.txnId, deleteFiles: false)
                failedOutgoing[item.txnId] = latest
                uploadProgress.removeValue(forKey: item.txnId)
                setSendState(.failed, txnId: item.txnId, roomId: item.roomId)
                if let reason { errorMessage = reason }
            case .unreachable:
                scheduleOutboxRetry()
                return
            case .cancelled:
                return
            case .sessionExpired:
                handleSessionExpired()
                return
            }
        }
    }

    private func deliver(_ queued: OutgoingMessage) async -> DeliveryResult {
        var item = queued
        var attempt = 0
        while true {
            do {
                let eventId: String
                if item.attachment != nil {
                    item = try await uploadAttachment(of: item)
                    try Task.checkCancellation()
                    guard let attachment = item.attachment, attachment.contentURI != nil else { return .failed(nil) }
                    eventId = try await client.sendRoomMessage(
                        roomId: item.roomId,
                        content: attachment.eventContent(),
                        txnId: item.txnId
                    ).eventId
                } else {
                    eventId = try await client.sendMessage(
                        roomId: item.roomId, body: item.body,
                        replyToEventId: item.replyToEventId,
                        threadRootEventId: item.threadRootEventId,
                        txnId: item.txnId,
                        formattedBody: item.formattedBody,
                        mentionUserIds: item.mentionUserIds ?? [],
                        mentionsRoom: item.mentionsRoom ?? false
                    ).eventId
                }
                confirmEcho(txnId: item.txnId, roomId: item.roomId, eventId: eventId, attachment: item.attachment)
                return .sent
            } catch {
                if error is CancellationError || Task.isCancelled { return .cancelled }
                let matrixError = error as? MatrixClient.MatrixError
                if matrixError?.isUnknownToken == true { return .sessionExpired }
                if !reachability.isConnected || MatrixClient.isTransient(error) { return .unreachable }
                if case .httpError(413, _, _, _)? = matrixError {
                    return .failed("Le serveur refuse ce fichier : il dépasse sa taille maximale.")
                }
                attempt += 1
                guard let delay = retryDelay(for: error, attempt: attempt) else { return .failed(nil) }
                try? await Task.sleep(for: .seconds(delay))
                if Task.isCancelled { return .cancelled }
            }
        }
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

    private func confirmEcho(txnId: String, roomId: String, eventId: String, attachment: OutgoingAttachment? = nil) {
        uploadProgress.removeValue(forKey: txnId)
        guard var list = messagesByRoom[roomId],
              let idx = list.firstIndex(where: { $0.txnId == txnId }),
              list[idx].eventId == nil
        else { return }
        // Point the echo at the uploaded copy (already in the media cache): the outbox file goes away.
        let attachments = attachment.flatMap { remoteAttachment($0, txnId: txnId) }.map { [$0] } ?? list[idx].attachments
        if let root = conversationRoots[txnId] {
            conversationRoots[eventId] = root
            if let count = conversationSummaries[root] { conversationSummaries[root] = count + 1 }
        }
        list[idx] = list[idx].replacing(attachments: attachments, sendState: .sent, eventId: eventId)
        messagesByRoom[roomId] = list
    }

    private func setSendState(_ state: MessageSendState, txnId: String, roomId: String) {
        guard var list = messagesByRoom[roomId],
              let idx = list.firstIndex(where: { $0.txnId == txnId }) else { return }
        list[idx].sendState = state
        messagesByRoom[roomId] = list
    }

    private func makeLocalEcho(roomId: String, body: String, txnId: String, replyToEventId: String?,
                               createdAt: Date = Date(), attachment: OutgoingAttachment? = nil) -> ChatMessage {
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
            replyTo = ReplyRef(sender: original.sender, content: original.content, eventId: replyToEventId)
        }
        var echo = ChatMessage(
            id: stableUUID(from: txnId), sender: sender, content: attachment == nil ? body : "",
            timestamp: createdAt, isGrouped: false, replyTo: replyTo,
            attachments: attachment.map { [localAttachment($0, txnId: txnId)] } ?? [],
            sendState: .sending, eventId: nil, txnId: txnId
        )
        echo.isOwn = true
        return echo
    }

    // Recrée les échos locaux des messages encore en file au démarrage
    private func restoreOutboxEchoes() {
        for item in outbox.pending {
            let exists = messagesByRoom[item.roomId]?.contains(where: { $0.txnId == item.txnId }) ?? false
            guard !exists else { continue }
            let echo = makeLocalEcho(roomId: item.roomId, body: item.body, txnId: item.txnId,
                                     replyToEventId: item.replyToEventId, createdAt: item.createdAt,
                                     attachment: item.attachment)
            if let root = item.threadRootEventId { conversationRoots[item.txnId] = root }
            insertSorted(echo, roomId: item.roomId)
            // A queued attachment shows its upload card (0 % while it waits), with its ✕.
            if item.attachment != nil, uploadProgress[item.txnId] == nil { uploadProgress[item.txnId] = 0 }
        }
    }

    func editMessage(roomId: String, eventId: String, newBody: String) async {
        guard validateOutgoingText(newBody) else { return }
        let formatted = formatOutgoing(newBody, roomId: roomId)
        let previous = messageIndex(roomId: roomId, eventId: eventId)
            .map { formatOutgoing(messagesByRoom[roomId]![$0].content, roomId: roomId).mentionedUserIds } ?? []
        do {
            try await client.editMessage(
                roomId: roomId, eventId: eventId, newBody: newBody,
                formattedBody: formatted.formattedBody, mentionUserIds: formatted.mentionedUserIds,
                mentionsRoom: formatted.mentionsRoom, previousMentionUserIds: previous
            )
            if let index = messageIndex(roomId: roomId, eventId: eventId) {
                let original = messagesByRoom[roomId]![index]
                messagesByRoom[roomId]![index] = original.replacing(content: newBody, isEdited: true)
            }
            rebuildUIModels()
        } catch {
            self.errorMessage = "Modification échouée : \(error.localizedDescription)"
        }
    }

    func deleteMessage(roomId: String, eventId: String) async {
        do {
            try await client.redactEvent(roomId: roomId, eventId: eventId)
            applyRedaction(of: eventId, roomId: roomId)
            rebuildUIModels()
        } catch {
            self.errorMessage = "Suppression échouée : \(error.localizedDescription)"
        }
    }

    func sendReaction(roomId: String, eventId: String, emoji: String) async {
        do {
            let response = try await client.sendReaction(roomId: roomId, eventId: eventId, emoji: emoji)
            if let userId {
                recordReaction(MatrixEvent(type: "m.reaction", eventId: response.eventId, sender: userId, originServerTs: nil,
                    content: ["m.relates_to": AnyCodable(["event_id": AnyCodable(eventId), "key": AnyCodable(emoji)])],
                    stateKey: nil, unsigned: nil, redacts: nil), eventId: response.eventId, roomId: roomId)
            }
            rebuildUIModels()
        } catch {
            self.errorMessage = "Réaction échouée : \(error.localizedDescription)"
        }
    }

    /// Clicking a reaction chip: adds my reaction, or removes it if I already reacted.
    func toggleReaction(roomId: String, eventId: String, emoji: String) async {
        if let mine = reactionEvents[eventId]?.first(where: { $0.emoji == emoji && $0.sender == userId }) {
            do {
                try await client.redactEvent(roomId: roomId, eventId: mine.eventId)
                applyRedaction(of: mine.eventId, roomId: roomId)
                rebuildUIModels()
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
        ConversationPolicy.link(room: roomId, event: eventId)
    }

    func setTyping(roomId: String, typing: Bool) async {
        guard let userId else { return }
        refreshPreferencesIfNeeded()
        guard preferences.sendsTypingIndicator else { return }
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
        guard !conversationHeldUnread.contains(roomId),
              let roomIndex = rooms.firstIndex(where: { $0.roomId == roomId }) else { return }
        clearConversationUnread(roomId: roomId)

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
        updateAppBadge()

        if eventId != nil {
            Task { await retryPendingReadReceipts() }
        }
    }

    private func retryPendingReadReceipts() async {
        guard !isSendingReadReceipts, !pendingReadReceipts.isEmpty else { return }
        isSendingReadReceipts = true
        defer { isSendingReadReceipts = false }

        refreshPreferencesIfNeeded()
        let receiptsToSend = pendingReadReceipts
        for (roomId, eventId) in receiptsToSend {
            do {
                if preferences.sendsReadReceipts {
                    try await client.sendReadReceipt(roomId: roomId, eventId: eventId)
                    try await client.setReadMarker(roomId: roomId, fullyRead: eventId, read: eventId)
                } else {
                    // Receipts off: the server still learns where we are (for unread counts), the others do not.
                    try await client.sendPrivateReadReceipt(roomId: roomId, eventId: eventId)
                    try await client.setPrivateReadMarker(roomId: roomId, fullyRead: eventId)
                }
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

    static func matrixPresence(for status: MoodUser.UserStatus) -> String {
        switch status {
        case .idle: return "unavailable"
        case .invisible, .offline: return "offline"
        default: return "online"
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

    /// A file picked from the composer's "+" menu: copied into the outbox (images resized, HEIC → JPEG,
    /// thumbnail made), shown at once with an upload bar, then uploaded and sent in the room's order.
    /// Over 25 Mo (or the server's own limit) it is refused with a clear message.
    func sendAttachment(roomId: String, fileURL: URL) async {
        guard let folder = outbox.filesDirectory else {
            errorMessage = "Impossible de préparer l'envoi : stockage local indisponible."
            return
        }
        let didAccess = fileURL.startAccessingSecurityScopedResource()
        defer { if didAccess { fileURL.stopAccessingSecurityScopedResource() } }

        let txnId = UUID().uuidString
        let attachment: OutgoingAttachment
        do {
            let limit = effectiveUploadLimit()
            attachment = try await MediaPreparation.prepare(sourceURL: fileURL, txnId: txnId, folder: folder, limit: limit)
        } catch {
            errorMessage = error.localizedDescription
            return
        }
        guard userId != nil else { return } // logged out while preparing

        clearNewMessagesDivider(roomId: roomId)
        let message = OutgoingMessage(
            txnId: txnId, roomId: roomId, body: attachment.fileName,
            replyToEventId: nil, threadRootEventId: nil, createdAt: Date(),
            attachment: attachment
        )
        insertSorted(makeLocalEcho(roomId: roomId, body: message.body, txnId: txnId, replyToEventId: nil,
                                   createdAt: message.createdAt, attachment: attachment), roomId: roomId)
        uploadProgress[txnId] = 0
        rebuildUIModels()
        outbox.enqueue(message)
        flushOutbox()
    }

    /// Discord's "Créer mon serveur": a space plus a first #général channel inside it
    /// (a space with no channel is not shown in the rail). Returns the server's UI id.
    func createServer(name: String, isPublic: Bool) async -> UUID? {
        await createMessagingServer(name: name, isPublic: isPublic)
    }

    /// Joins from whatever the user pasted: a matrix.to link, a #alias:server or a !roomId:server.
    /// Returns the joined room's UI id (server id when it is a space).
    func joinServer(fromInvite invite: String) async -> UUID? {
        guard let reference = Self.roomReference(fromInvite: invite) else {
            errorMessage = "Invitation invalide. Utilise un code Mood, un lien mood://invite/… ou un alias."
            return nil
        }
        do {
            let response = try await client.joinRoom(reference)
            await refreshMessagingRoom(response.roomId)
            await joinServerChannels(response.roomId)
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
        MoodInvite.reference(invite)
    }

    private func performCreateDM(userId targetUserId: String) async -> String? {
        // Dédup : room direct existante avec exactement ce user
        if let existing = existingDirectRoomId(with: targetUserId) {
            return existing
        }
        if let userId,
           let map = try? await client.getDirectRooms(userId: userId),
           let candidates = map[targetUserId],
           let existing = candidates.first(where: { candidate in rooms.contains {
               $0.roomId == candidate && !groupDirectRoomIds.contains(candidate) && AccountValidation.canReuseDirectRoom(members: Set($0.members.keys), me: userId, target: targetUserId)
           } }) {
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
        if let shown = shownDirectRoomByPeer[targetUserId], rooms.contains(where: { $0.roomId == shown }) { return shown }
        return rooms.first(where: { room in
            guard room.isDirect, room.roomType != "m.space", !groupDirectRoomIds.contains(room.roomId) else { return false }
            return AccountValidation.canReuseDirectRoom(members: Set(room.members.keys), me: userId ?? "", target: targetUserId)
        })?.roomId
    }

    private func isGroupDirectRoom(_ room: MatrixRoom) -> Bool {
        groupDirectRoomIds.contains(room.roomId) || Set(room.members.keys).subtracting([userId ?? ""]).count > 1
    }

    /// The other person of a 1:1 DM: m.direct first, then joined members, then heroes — never me.
    private func directPeer(of room: MatrixRoom) -> String? {
        let me = userId
        if !isGroupDirectRoom(room), let peer = directPeerByRoom[room.roomId], peer != me { return peer }
        return room.members.keys.sorted().first(where: { $0 != me }) ?? room.heroes.first(where: { $0 != me })
    }

    /// One conversation per person, like Discord: when two 1:1 DMs exist with the same peer (both
    /// sides started one), the one with the latest message is shown and reused.
    private func dedupedDirectRooms(_ dmRooms: [MatrixRoom]) -> [MatrixRoom] {
        var best: [String: MatrixRoom] = [:]
        var kept: [MatrixRoom] = []
        func lastActivity(_ room: MatrixRoom) -> Date { messagesByRoom[room.roomId]?.last?.timestamp ?? .distantPast }
        for room in dmRooms {
            guard !isGroupDirectRoom(room), let peer = directPeer(of: room) else { kept.append(room); continue }
            if let current = best[peer], lastActivity(current) >= lastActivity(room) { continue }
            best[peer] = room
        }
        shownDirectRoomByPeer = best.mapValues(\.roomId)
        return kept + best.values
    }

    /// Fetches once the profile of a DM peer missing from the lazy-loaded members, then redraws.
    private func loadPeerProfile(_ peerId: String) {
        guard peerProfiles[peerId] == nil, !peerProfileRequests.contains(peerId) else { return }
        peerProfileRequests.insert(peerId)
        Task { [weak self] in
            guard let self, let profile = try? await self.client.getProfile(userId: peerId) else { return }
            self.peerProfiles[peerId] = profile
            // Messages already shown with the bare id get the real name and avatar.
            let user = self.makeUser(peerId, displayName: profile.displayname ?? self.extractLocalpart(peerId),
                                     avatarMxc: profile.avatarUrl)
            for (roomId, list) in self.messagesByRoom where list.contains(where: { $0.sender.matrixId == peerId }) {
                guard self.rooms.first(where: { $0.roomId == roomId })?.members[peerId] == nil else { continue }
                self.messagesByRoom[roomId] = list.map { $0.sender.matrixId == peerId ? $0.replacing(sender: user) : $0 }
            }
            self.rebuildUIModels()
        }
    }

    // Merge dans m.direct (account data) pour que les autres clients voient le DM
    @discardableResult
    private func registerDirectRoom(_ roomId: String, with targetUserId: String) async -> Bool {
        guard let userId else { return false }
        do {
            var map = try await client.getDirectRooms(userId: userId)
            var list = map[targetUserId] ?? []
            if !list.contains(roomId) { list.append(roomId) }
            map[targetUserId] = list
            try await client.setDirectRooms(userId: userId, directMap: map)
            return true
        } catch {
            errorMessage = "MP ouvert, mais sa sauvegarde a échoué. Réessaie quand la connexion revient."
            return false
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
            await refreshMessagingRoom(roomId)
        } catch {
            self.errorMessage = "Exclusion échouée : \(error.localizedDescription)"
        }
    }

    func banUser(roomId: String, userId targetUserId: String, reason: String? = nil) async {
        do {
            try await client.banUser(roomId: roomId, userId: targetUserId, reason: reason)
            await refreshMessagingRoom(roomId)
        } catch {
            self.errorMessage = "Bannissement échoué : \(error.localizedDescription)"
        }
    }

    /// Joins; a DM invite is also filed under m.direct, so it shows in my DMs (the inviter only
    /// writes their own m.direct) with the messages already sent.
    func acceptInvite(roomId: String) async {
        guard userId != nil else { return }
        let invite = pendingInvites.first { $0.id == roomId }
        guard await joinRoom(roomId) else { return }
        pendingInvites.removeAll { $0.id == roomId }
        if let invite, invite.isDirect, !invite.inviter.isEmpty {
            directRoomIds.insert(roomId)
            if let index = rooms.firstIndex(where: { $0.roomId == roomId }) { rooms[index].isDirect = true }
            await registerDirectRoom(roomId, with: invite.inviter)
        }
    }

    func rejectInvite(roomId: String) async {
        guard userId != nil else { return }
        do {
            try await client.leaveRoom(roomId)
            pendingInvites.removeAll { $0.id == roomId }
        } catch { errorMessage = "Impossible de refuser l’invitation. Réessaie." }
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

    /// Sets the global display name and shows it at once; the server echoes it to every room later.
    @discardableResult
    func updateDisplayName(_ name: String) async -> Bool {
        guard let userId else { return false }
        do {
            try await client.setDisplayName(userId: userId, displayName: name)
            currentUser = makeUser(userId, displayName: name, avatarMxc: currentAvatarMxc)
            refreshOwnRoomProfile(name: name, avatar: currentAvatarMxc)
            return true
        } catch {
            errorMessage = "Impossible de changer le nom : \(error.localizedDescription)"
            return false
        }
    }

    @discardableResult
    func updateAvatar(imageData: Data, filename: String) async -> Bool {
        guard let userId else { return false }
        do {
            let contentType = MediaPreparation.imageMimeType(of: imageData) ?? "image/jpeg"
            let upload = try await client.uploadMedia(data: imageData, filename: filename, contentType: contentType)
            try await client.setAvatarUrl(userId: userId, avatarUrl: upload.contentUri)
            currentAvatarMxc = upload.contentUri
            currentUser = makeUser(userId, displayName: currentUser?.displayName ?? extractLocalpart(userId),
                                   avatarMxc: upload.contentUri)
            refreshOwnRoomProfile(name: currentUser?.displayName ?? "", avatar: upload.contentUri)
            return true
        } catch {
            self.errorMessage = "Mise à jour de l'avatar échouée : \(error.localizedDescription)"
            return false
        }
    }

    /// Mood username → Matrix id (Supabase), set by the app. The Matrix directory only returns people
    /// who share a room with us or sit in a public room, so a new user is found by username only.
    var usernameLookup: (@MainActor (String) async throws -> String?)?

    func searchUsers(query: String) async -> [MatrixUserResult] {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return [] }
        errorMessage = nil
        var results: [MatrixUserResult] = []
        if let handle = MoodUsername.normalized(trimmed), let lookup = usernameLookup,
           let matrixId = try? await lookup(handle), matrixId != userId {
            let profile = try? await client.getProfile(userId: matrixId)
            results.append(MatrixUserResult(userId: matrixId, displayName: profile?.displayname ?? handle,
                                            avatarUrl: profile?.avatarUrl))
        }
        do {
            let response = try await client.searchUsers(term: trimmed)
            results += (response.results ?? []).filter { found in !results.contains { $0.userId == found.userId } }
        } catch {
            if results.isEmpty { errorMessage = "Recherche impossible. Vérifie ta connexion et réessaie." }
        }
        return results.filter { AccountValidation.isVisiblePeer($0.userId, me: userId, blocked: ignoredUserIds) }
    }

    func fetchPublicRooms(limit: Int = 50, filter: String? = nil) async -> [MatrixPublicRoom] {
        (try? await loadPublicRooms(limit: limit, filter: filter)) ?? []
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
            await refreshMessagingRoom(roomId)
        } catch {
            self.errorMessage = "Débannissement échoué : \(error.localizedDescription)"
        }
    }

    func setRoomName(roomId: String, name: String) async {
        do {
            try await client.setRoomName(roomId: roomId, name: name)
            await refreshMessagingRoom(roomId)
        } catch {
            self.errorMessage = "Renommage échoué : \(error.localizedDescription)"
        }
    }

    func setRoomTopic(roomId: String, topic: String) async {
        do {
            try await client.setRoomTopic(roomId: roomId, topic: topic)
            await refreshMessagingRoom(roomId)
        } catch {
            self.errorMessage = "Modification du sujet échouée : \(error.localizedDescription)"
        }
    }

    func loadMoreMessages(roomId: String) async {
        guard hasMoreHistory[roomId] ?? true, !paginatingRooms.contains(roomId) else { return }
        guard var token = backPaginationTokens[roomId] else {
            hasMoreHistory[roomId] = false
            return
        }
        paginatingRooms.insert(roomId)
        defer { paginatingRooms.remove(roomId) }

        do {
            // After a cache restore the first pages can be messages we already show: keep going
            // (a few pages at most) until something new appears, so the scroll-up never looks stuck.
            for _ in 0..<Self.maxHistoryPagesPerLoad {
                let response = try await client.roomMessages(roomId: roomId, from: token, limit: 50)
                let events = response.chunk ?? []
                let insertedAny = applyHistoryPage(response, roomId: roomId, stopAtKnownEvent: false).insertedAny
                guard let end = response.end, !events.isEmpty else {
                    hasMoreHistory[roomId] = false
                    break
                }
                backPaginationTokens[roomId] = end
                hasMoreHistory[roomId] = true
                token = end
                if insertedAny { break }
            }
            rebuildUIModels()
        } catch {
            self.errorMessage = "Chargement de l'historique échoué : \(error.localizedDescription)"
        }
    }

    // Comble un trou de timeline (sync limited) en remontant depuis prev_batch, page après page,
    // jusqu'à rejoindre un événement connu (cache ou sync précédente).
    private func fillGap(roomId: String, from token: String, generation: Int) async {
        var from = token
        var changed = false
        for _ in 0..<Self.maxGapPages {
            guard let response = try? await client.roomMessages(roomId: roomId, from: from, limit: 100),
                  generation == syncGeneration else { break }
            let page = applyHistoryPage(response, roomId: roomId, stopAtKnownEvent: true)
            changed = changed || page.insertedAny || page.changedExisting
            guard !page.reachedKnownEvent, let end = response.end, !(response.chunk ?? []).isEmpty else { break }
            from = end
        }
        if changed { rebuildUIModels() }
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

    func resolveMediaURL(_ mxcUrl: String?, width: Int? = nil, height: Int? = nil, method: String = "crop") -> URL? {
        guard let mxcUrl else { return nil }
        return client.resolveMediaURL(mxcUrl, width: width, height: height, method: method)
    }

    // MARK: - Mapping Helpers

    func roomId(for server: MoodServer) -> String? {
        stableIdReverse[server.id]
    }

    // MARK: - Server & channel management (Discord server settings on top of Matrix spaces)

    private func room(_ roomId: String?) -> MatrixRoom? {
        guard let roomId else { return nil }
        return rooms.first { $0.roomId == roomId }
    }

    func topic(of server: MoodServer) -> String {
        room(roomId(for: server))?.topic ?? ""
    }

    /// My power level in the space: 100 admin, 50 moderator, 0 member.
    func myPowerLevel(in server: MoodServer) -> Int {
        guard let space = room(roomId(for: server)), let userId else { return 0 }
        return space.powerLevels[userId] ?? space.powerLevelsContent["users_default"]?.intValue ?? 0
    }

    func bannedUsers(in server: MoodServer) -> [MoodUser] {
        let spaceId = roomId(for: server)
        let channelIds = server.categories.flatMap(\.channels).compactMap { roomId(for: $0) }
        var banned: [String: String] = [:]
        for room in rooms where room.roomId == spaceId || channelIds.contains(room.roomId) {
            banned.merge(room.bannedUsers) { current, _ in current }
        }
        return banned.sorted { $0.value < $1.value }.map { makeUser($0.key, displayName: $0.value) }
    }

    private func serverRoomIds(_ server: MoodServer) -> [String] {
        server.categories.flatMap(\.channels).compactMap { roomId(for: $0) } + [roomId(for: server)].compactMap { $0 }
    }

    /// Discord's "Créer un salon": a room added as a child of the space.
    func createChannel(in server: MoodServer, name: String, topic: String = "", isPrivate: Bool) async -> UUID? {
        guard let spaceId = roomId(for: server) else { return nil }
        return await createMessagingChannel(spaceId: spaceId, name: name, topic: topic, isPrivate: isPrivate)
    }

    /// Matrix cannot delete a room: remove it from the space, then leave it.
    func deleteChannel(_ channel: Channel, from server: MoodServer) async -> Bool {
        guard let channelId = roomId(for: channel), let spaceId = roomId(for: server) else { return false }
        do {
            try await client.removeSpaceChild(spaceRoomId: spaceId, childRoomId: channelId)
            await refreshMessagingRoom(spaceId)
            await leaveRoom(channelId)
            return room(channelId) == nil
        } catch { errorMessage = "Le salon n’a pas été retiré : \(error.localizedDescription)"; return false }
    }

    func updateServer(_ server: MoodServer, name: String, topic: String) async {
        guard let spaceId = roomId(for: server) else { return }
        if name != server.name { await setRoomName(roomId: spaceId, name: name) }
        if topic != self.topic(of: server) { await setRoomTopic(roomId: spaceId, topic: topic) }
    }

    func updateChannel(_ channel: Channel, name: String, topic: String) async {
        guard let channelId = roomId(for: channel) else { return }
        if name != channel.name { await setRoomName(roomId: channelId, name: name) }
        if topic != channel.topic { await setRoomTopic(roomId: channelId, topic: topic) }
    }

    /// Kicking or banning from a Discord server means every room of the space.
    func kickFromServer(_ server: MoodServer, user: MoodUser) async {
        guard let target = user.matrixId else { return }
        for roomId in serverRoomIds(server) { await kickUser(roomId: roomId, userId: target) }
    }

    func banFromServer(_ server: MoodServer, user: MoodUser) async {
        guard let target = user.matrixId else { return }
        for roomId in serverRoomIds(server) { await banUser(roomId: roomId, userId: target) }
    }

    func unbanFromServer(_ server: MoodServer, user: MoodUser) async {
        guard let target = user.matrixId else { return }
        for roomId in serverRoomIds(server) where room(roomId)?.bannedUsers[target] != nil {
            await unbanUser(roomId: roomId, userId: target)
        }
    }

    /// Discord role ↔ Matrix power level, applied to the space and every channel.
    func setRole(_ role: ServerRole, for user: MoodUser, in server: MoodServer) async {
        guard let target = user.matrixId else { return }
        let level = MessagingServerPolicy.roleLevel(role)
        for roomId in serverRoomIds(server) {
            guard let index = rooms.firstIndex(where: { $0.roomId == roomId }) else { continue }
            var content = rooms[index].powerLevelsContent.mapValues(\.jsonObject)
            var users = content["users"] as? [String: Any] ?? [:]
            users[target] = level
            content["users"] = users
            do {
                try await client.setStateEvent(roomId: roomId, type: "m.room.power_levels", content: content)
                rooms[index].powerLevels[target] = level
                rooms[index].powerLevelsContent["users"] = AnyCodable(users.mapValues { AnyCodable($0) })
            } catch {
                errorMessage = "Impossible de changer le rôle (droits insuffisants ?) : \(error.localizedDescription)"
                return
            }
        }
        rebuildUIModels()
    }

    func updateServerIcon(_ server: MoodServer, imageData: Data, filename: String) async {
        guard let spaceId = roomId(for: server) else { return }
        do {
            let contentType = MediaPreparation.imageMimeType(of: imageData) ?? "image/jpeg"
            let upload = try await client.uploadMedia(data: imageData, filename: filename, contentType: contentType)
            try await client.setStateEvent(roomId: spaceId, type: "m.room.avatar", content: ["url": upload.contentUri])
            await refreshMessagingRoom(spaceId)
        } catch {
            errorMessage = "Impossible de changer l'icône : \(error.localizedDescription)"
        }
    }

    /// Shareable invite link for the server (a matrix.to link to the space).
    func inviteLink(for server: MoodServer) -> String? {
        roomId(for: server).flatMap { messagingInvites[$0] }.map { "mood://invite/\($0)" }
    }

    func inviteToServer(_ server: MoodServer, matrixUserId: String) async -> Bool {
        guard let spaceId = roomId(for: server) else { return false }
        do {
            try await client.inviteUser(roomId: spaceId, userId: matrixUserId)
            return true
        } catch {
            errorMessage = "Invitation échouée : \(error.localizedDescription)"
            return false
        }
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
        var messages = computeGrouping((messagesByRoom[roomId] ?? []).filter { conversationRoot(of: $0) == nil })
        for index in messages.indices {
            messages[index].threadInfo = nil
            if let id = messages[index].eventId {
                let replies = conversationReplies(roomId: roomId, root: id)
                if let last = replies.last {
                    messages[index].threadInfo = ThreadInfo(replyCount: max(conversationSummaries[id] ?? 0, replies.count), lastReplier: last.sender, lastReplyDate: last.timestamp)
                }
            }
        }
        do {
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
            if i > 0 && ConversationPolicy.canGroup(result[i - 1], result[i]) {
                result[i] = result[i].replacing(isGrouped: true) // keeps isOwn: grouped messages stay editable
            }
        }
        return result
    }

    // MARK: - Build Current User from Profile

    private func buildCurrentUser(userId: String) async {
        var displayName = extractLocalpart(userId)
        var avatarMxc: String?

        defer { currentAvatarMxc = avatarMxc }
        // Try to fetch real profile
        if let profile = try? await client.getProfile(userId: userId) {
            if let name = profile.displayname, !name.isEmpty {
                displayName = name
            }
            avatarMxc = profile.avatarUrl
        }

        restoreAccountStatus(userId: userId)
        self.currentUser = makeUser(userId, displayName: displayName, avatarMxc: avatarMxc, fallbackStatus: .online)
        rebuildLocalMentions()
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

    // MARK: - Quick Switcher & Explore

    /// Calls and video are simulated (Calls.swift): only the demo, without a Matrix session, may show them.
    var callsAvailable: Bool { userId == nil }

    /// Throwing twin of `fetchPublicRooms`, so Explore can tell "nothing found" from "request failed".
    func loadPublicRooms(limit: Int = 50, filter: String? = nil) async throws -> [MatrixPublicRoom] {
        let response = try await client.getPublicRooms(limit: limit, filter: filter)
        return response.chunk ?? []
    }

    /// True once sync has delivered the room as joined (Explore then offers "Ouvrir" instead of "Rejoindre").
    func hasJoined(roomId: String) -> Bool {
        rooms.contains { $0.roomId == roomId }
    }

    // MARK: - Search & Inbox

    enum InboxLoadState: Equatable {
        case idle, loading, loaded
        case failed(String)
    }

    /// Set by a search result or a mention: the channel scrolls to this message once it is loaded.
    var jumpTarget: JumpTarget?
    /// Recent mentions and replies (`GET /notifications?only=highlight`), newest first.
    private(set) var inboxMentions: [InboxMention] = []
    private(set) var inboxState: InboxLoadState = .idle

    /// The channel or DM a Matrix room is shown as, nil for rooms the UI does not list (left, invited).
    func destination(forRoomId roomId: String) -> RoomDestination? {
        let id = stableUUID(from: roomId)
        for server in servers {
            if let channel = server.channel(withID: id) { return .channel(channel, server) }
        }
        if let conversation = dmConversations.first(where: { $0.id == id }) { return .dm(conversation) }
        return nil
    }

    /// Asks the open channel to scroll to `eventId`. Dropped after a few seconds if the message never loads,
    /// so a stale request cannot hijack the scroll position later.
    func requestJump(roomId: String, eventId: String) {
        if let root = conversationRoots[eventId] {
            guard root != eventId, conversationRoots[root] == nil else {
                errorMessage = "Ce fil n’est pas accessible."
                return
            }
            if messageIndex(roomId: roomId, eventId: root) == nil {
                Task {
                    await loadMessagingContext(roomId: roomId, eventId: root)
                    if messageIndex(roomId: roomId, eventId: root) != nil { requestJump(roomId: roomId, eventId: eventId) }
                }
                return
            }
            conversationThreadJump = JumpTarget(roomId: roomId, eventId: eventId)
            requestJump(roomId: roomId, eventId: root)
            return
        }
        if messageIndex(roomId: roomId, eventId: eventId) == nil {
            Task {
                await loadMessagingContext(roomId: roomId, eventId: eventId)
                if messageIndex(roomId: roomId, eventId: eventId) != nil { requestJump(roomId: roomId, eventId: eventId) }
            }
            return
        }
        let target = JumpTarget(roomId: roomId, eventId: eventId)
        jumpTarget = target
        Task {
            try? await Task.sleep(for: .seconds(5))
            if jumpTarget == target { jumpTarget = nil }
        }
    }

    /// One page of server-side message search. `channels` / `senders` narrow it (Discord's "dans:" / "de:").
    /// Encrypted rooms cannot be searched by the homeserver: they are skipped and counted.
    func searchMessages(
        term: String,
        scope: SearchScope,
        channels: [Channel] = [],
        senders: [MoodUser] = [],
        nextBatch: String? = nil
    ) async throws -> SearchPage {
        let roomIds: [String]
        switch scope {
        case .server(let server):
            let pool = channels.isEmpty ? server.categories.flatMap(\.channels) : channels
            roomIds = pool.compactMap { roomId(for: $0) }
        case .dm(let conversation):
            roomIds = [roomId(for: conversation)].compactMap { $0 }
        }

        let searchable = roomIds.filter { !isRoomEncrypted($0) }
        let skipped = roomIds.count - searchable.count
        guard !roomIds.isEmpty else {
            return SearchPage(hits: [], total: 0, nextBatch: nil, highlights: [], skippedEncryptedRooms: 0, isUnavailable: false)
        }
        guard !searchable.isEmpty else { return .unavailable }

        let response = try await client.search(
            term: term,
            roomIds: searchable,
            senderIds: senders.compactMap(\.matrixId),
            nextBatch: nextBatch
        )
        let events = response.searchCategories.roomEvents
        let hits = (events?.results ?? []).compactMap { result -> SearchHit? in
            guard let roomId = result.roomId else { return nil }
            return makeSearchHit(result.result, roomId: roomId)
        }
        return SearchPage(
            hits: hits,
            total: events?.count,
            nextBatch: events?.nextBatch,
            highlights: events?.highlights ?? [],
            skippedEncryptedRooms: skipped,
            isUnavailable: false
        )
    }

    private func makeSearchHit(_ event: MatrixEvent, roomId: String) -> SearchHit? {
        guard let eventId = event.eventId,
              !redactedEventIds.contains(eventId),
              let destination = destination(forRoomId: roomId) else { return nil }
        if let sender = event.sender, ignoredUserIds.contains(sender) { return nil }

        // Prefer the copy already in the timeline: it carries edits and reactions.
        let message: ChatMessage
        if let index = messageIndex(roomId: roomId, eventId: eventId), let loaded = messagesByRoom[roomId]?[index] {
            message = loaded
        } else if let made = makeMessage(from: event, roomId: roomId) {
            message = made
        } else {
            return nil
        }
        return SearchHit(eventId: eventId, roomId: roomId, message: message, destination: destination)
    }

    /// Refreshes the inbox's Mentions tab.
    func refreshInbox() async {
        guard userId != nil else { return }
        rebuildLocalMentions()
        guard !notificationsUnavailable else { return }
        let generation = syncGeneration
        do {
            let response = try await client.notifications(limit: 50, only: "highlight")
            guard generation == syncGeneration else { return }
            serverInboxMentions = response.notifications.compactMap(makeInboxMention)
            rebuildLocalMentions()
        } catch {
            guard generation == syncGeneration else { return }
            if case MatrixClient.MatrixError.httpError(let status, let code, _, _) = error,
               status == 404 || code == "M_UNRECOGNIZED" { notificationsUnavailable = true }
            // Cached mentions remain usable even during an outage or on servers without /notifications.
            rebuildLocalMentions()
        }
    }

    private func makeInboxMention(_ item: MatrixNotification) -> InboxMention? {
        let event = item.event
        guard event.type == "m.room.message",
              let eventId = event.eventId,
              let senderId = event.sender,
              senderId != userId,
              !ignoredUserIds.contains(senderId),
              let destination = destination(forRoomId: item.roomId) else { return nil }

        let source = room(item.roomId)
        let sender = makeUser(senderId, displayName: source?.members[senderId], avatarMxc: source?.memberAvatars[senderId])
        let timestamp = Date(timeIntervalSince1970: TimeInterval(event.originServerTs ?? item.ts ?? 0) / 1000)
        return InboxMention(
            id: eventId,
            roomId: item.roomId,
            sender: sender,
            text: Self.plainBody(of: event),
            timestamp: timestamp,
            isRead: item.read,
            destination: destination
        )
    }

    /// The message text without the legacy reply fallback ("> <@user> quoted line" + blank line).
    static func plainBody(of event: MatrixEvent) -> String {
        var body = event.content?["m.new_content"]?.dictValue?["body"]?.stringValue
            ?? event.content?["body"]?.stringValue
            ?? ""
        if body.hasPrefix("> "), let split = body.range(of: "\n\n") {
            body = String(body[split.upperBound...])
        }
        return body.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Notifications & push rules

    /// Per-account switches (notifications, receipts, typing) of the signed-in account.
    private(set) var preferences = AccountPreferences()
    /// Rooms muted through Matrix push rules, so every device of the account agrees.
    private(set) var mutedRoomIds: Set<String> = []
    private(set) var notificationAuthorization: NotificationAuthorizationState = .unknown
    /// A room a tapped notification asked to open; the visible layout consumes it once the room is known.
    private(set) var roomOpenRequest: RoomOpenRequest?
    /// Sessions of this account (`GET /devices`), this device first.
    private(set) var devices: [MatrixDevice] = []
    private(set) var currentDeviceId: String?
    private(set) var devicesState: InboxLoadState = .idle

    struct RoomOpenRequest: Equatable, Identifiable {
        let id = UUID()
        let roomId: String
    }

    @ObservationIgnored private var preferencesOwner: String?
    @ObservationIgnored private var seenEventIds = RecentEventSet()
    @ObservationIgnored private var openRoomId: String?
    @ObservationIgnored private var lastBadgeCount: Int?
    @ObservationIgnored private let notificationService = NotificationService.shared

    private func configureNotifications() {
        notificationService.onOpenRoom = { [weak self] roomId in self?.requestOpenRoom(roomId) }
    }

    private func resetNotificationState() {
        mutedRoomIds = []
        devices = []
        currentDeviceId = nil
        devicesState = .idle
        roomOpenRequest = nil
        seenEventIds.removeAll()
        openRoomId = nil
        preferencesOwner = nil
        preferences = AccountPreferences()
        lastBadgeCount = nil
        notificationService.setBadge(0)
        notificationService.removeAllDelivered()
    }

    // MARK: Preferences

    /// Loads the signed-in account's preferences the first time they are needed (and after an account switch).
    func refreshPreferencesIfNeeded() {
        guard let userId, preferencesOwner != userId else { return }
        preferencesOwner = userId
        preferences = AccountPreferences.load(userId: userId)
    }

    func updatePreferences(_ change: (inout AccountPreferences) -> Void) {
        refreshPreferencesIfNeeded()
        var updated = preferences
        change(&updated)
        guard updated != preferences else { return }
        preferences = updated
        if let userId { updated.save(userId: userId) }
        updateAppBadge()
    }

    func refreshNotificationAuthorization() async {
        notificationAuthorization = await notificationService.authorizationState()
    }

    /// Turning notifications on is the moment the system permission is requested.
    /// The switch stays off when the user (or an earlier answer) refuses.
    func setNotificationsEnabled(_ enabled: Bool) async {
        if !enabled {
            updatePreferences { $0.notificationsEnabled = false }
            notificationService.removeAllDelivered()
            return
        }
        let granted = await notificationService.requestAuthorization()
        // A refused or failed request (for instance an unsigned build) both read as "not allowed" to the user.
        notificationAuthorization = granted ? .authorized : .denied
        updatePreferences { $0.notificationsEnabled = granted }
    }

    /// The badge needs the same permission as banners.
    func setBadgeEnabled(_ enabled: Bool) async {
        if enabled, notificationAuthorization != .authorized {
            let granted = await notificationService.requestAuthorization()
            notificationAuthorization = granted ? .authorized : .denied
        }
        updatePreferences { $0.badgeEnabled = enabled }
    }

    // MARK: Sync-driven notifications

    /// Runs after each sync response has been applied to the rooms.
    /// The first response of a loop is a full dump (cache replay plus the last messages of every room):
    /// none of it is news, so it only fills the "already seen" memory.
    private func handleSyncForNotifications(_ response: MatrixSyncResponse, isInitialSync: Bool) {
        refreshPreferencesIfNeeded()
        applyPushRules(fromAccountData: response.accountData?.events)
        if isInitialSync {
            // The store that syncs owns taps on notifications (SwiftUI may build and drop spare stores at launch).
            configureNotifications()
            for roomData in (response.rooms?.join ?? [:]).values {
                for eventId in (roomData.timeline?.events ?? []).compactMap(\.eventId) { seenEventIds.insert(eventId) }
            }
            Task { await loadPushRules() }
        } else {
            postNotifications(for: response)
        }
        updateAppBadge()
    }

    private func postNotifications(for response: MatrixSyncResponse) {
        guard let joined = response.rooms?.join else { return }

        var candidates: [NotificationCandidate] = []
        for (roomId, roomData) in joined {
            guard let room = rooms.first(where: { $0.roomId == roomId }), room.roomType != "m.space" else { continue }
            for event in roomData.timeline?.events ?? [] {
                if let candidate = notificationCandidate(for: event, in: room) { candidates.append(candidate) }
            }
        }
        guard !candidates.isEmpty else { return }

        let context = NotificationContext(
            myUserId: userId,
            preferences: preferences,
            isDoNotDisturb: myStatus == .dnd,
            ignoredUserIds: ignoredUserIds,
            mutedRoomIds: mutedRoomIds,
            openRoomId: openRoomId,
            isAppActive: notificationService.isAppActive,
            seenEventIds: seenEventIds.ids,
            now: Date()
        )
        let selected = NotificationDecision.select(candidates, in: context)
        for candidate in candidates { seenEventIds.insert(candidate.eventId) }
        for candidate in selected {
            notificationService.post(candidate, playSound: preferences.soundsEnabled)
        }
    }

    private func notificationCandidate(for event: MatrixEvent, in room: MatrixRoom) -> NotificationCandidate? {
        guard event.stateKey == nil,
              let eventId = event.eventId,
              !redactedEventIds.contains(eventId),
              let sender = event.sender else { return nil }

        let relation = event.content?["m.relates_to"]?.dictValue?["rel_type"]?.stringValue
        guard let text = NotificationCandidate.previewText(
            eventType: event.type,
            msgtype: event.content?["msgtype"]?.stringValue,
            body: Self.plainBody(of: event),
            isEdit: relation == "m.replace"
        ), !text.isEmpty else { return nil }

        return NotificationCandidate(
            eventId: eventId,
            roomId: room.roomId,
            senderId: sender,
            senderName: room.members[sender] ?? extractLocalpart(sender),
            roomName: room.name,
            isDirect: room.isDirect,
            body: text,
            timestamp: Date(timeIntervalSince1970: TimeInterval(event.originServerTs ?? 0) / 1000)
        )
    }

    // MARK: Badge

    /// Mentions + unread DMs on the app icon.
    var appBadgeCount: Int {
        BadgeCalculator.count(rooms.map {
            BadgeRoom(
                isDirect: $0.isDirect,
                isSpace: $0.roomType == "m.space",
                unreadCount: $0.unreadCount,
                mentionCount: $0.mentionCount,
                isMuted: mutedRoomIds.contains($0.roomId)
            )
        })
    }

    private func updateAppBadge() {
        guard userId != nil else { return }
        refreshPreferencesIfNeeded()
        let target = preferences.badgeEnabled ? appBadgeCount : 0
        guard target != lastBadgeCount else { return }
        lastBadgeCount = target
        notificationService.setBadge(target)
    }

    // MARK: Open room & tap to open

    /// The layout tells which room is on screen, so its own messages do not notify while the app is in front.
    func setOpenRoom(_ roomId: String?) {
        if openRoomId != roomId, let previous = openRoomId { conversationHeldUnread.remove(previous) }
        openRoomId = roomId
        if let roomId { notificationService.removeDelivered(roomId: roomId) }
    }

    private func requestOpenRoom(_ roomId: String) {
        let request = RoomOpenRequest(roomId: roomId)
        roomOpenRequest = request
        Task { [weak self] in
            // A launch from a notification may beat the first sync; give up after a minute so a stale request cannot hijack navigation.
            try? await Task.sleep(for: .seconds(60))
            if self?.roomOpenRequest == request { self?.roomOpenRequest = nil }
        }
    }

    /// The destination of a pending tap-to-open once sync has delivered the room; nil leaves the request pending.
    func consumeRoomOpenRequest() -> RoomDestination? {
        guard let request = roomOpenRequest, let destination = destination(forRoomId: request.roomId) else { return nil }
        roomOpenRequest = nil
        return destination
    }

    // MARK: Mute (push rules)

    func isMuted(roomId: String) -> Bool { mutedRoomIds.contains(roomId) }

    func isMuted(_ channel: Channel) -> Bool {
        roomId(for: channel).map(mutedRoomIds.contains) ?? false
    }

    func isMuted(_ conversation: DMConversation) -> Bool {
        roomId(for: conversation).map(mutedRoomIds.contains) ?? false
    }

    func setMuted(_ muted: Bool, channel: Channel) async {
        guard let roomId = roomId(for: channel) else { return }
        await setMuted(muted, roomId: roomId)
    }

    func setMuted(_ muted: Bool, conversation: DMConversation) async {
        guard let roomId = roomId(for: conversation) else { return }
        await setMuted(muted, roomId: roomId)
    }

    /// Shows the new state at once, then tells the server; goes back if the server refuses.
    func setMuted(_ muted: Bool, roomId: String) async {
        guard userId != nil, mutedRoomIds.contains(roomId) != muted else { return }
        let previous = mutedRoomIds
        if muted { mutedRoomIds.insert(roomId) } else { mutedRoomIds.remove(roomId) }
        updateAppBadge()
        do {
            if muted { try await client.muteRoom(roomId) } else { try await client.unmuteRoom(roomId) }
        } catch {
            mutedRoomIds = previous
            updateAppBadge()
            errorMessage = muted
                ? "Impossible de rendre ce salon muet : \(error.localizedDescription)"
                : "Impossible de rétablir le son : \(error.localizedDescription)"
        }
    }

    private func applyPushRules(fromAccountData events: [MatrixEvent]?) {
        guard let event = events?.last(where: { $0.type == "m.push_rules" }) else { return }
        mutedRoomIds = PushRules.mutedRoomIds(in: event.content?.mapValues(\.jsonObject))
    }

    /// `GET /pushrules/` at startup; later changes (this or another device) arrive as `m.push_rules` account data.
    private func loadPushRules() async {
        guard userId != nil, let rules = try? await client.getPushRules() else { return }
        mutedRoomIds = PushRules.mutedRoomIds(in: rules)
        updateAppBadge()
    }

    // MARK: Devices

    func refreshDevices() async {
        guard userId != nil else { return }
        if devices.isEmpty { devicesState = .loading }
        do {
            let list = try await client.getDevices()
            if let id = try? await client.currentDeviceId() { currentDeviceId = id }
            devices = DeviceList.ordered(list, currentDeviceId: currentDeviceId)
            devicesState = .loaded
        } catch {
            devicesState = .failed(error.localizedDescription)
        }
    }

    // MARK: - Messaging pipeline

    struct OutboxLane {
        let id: UUID
        let task: Task<Void, Never>
    }

    struct EditRecord {
        let sender: String
        let body: String
        let timestamp: Int64
    }

    private struct HistoryPageResult {
        var insertedAny = false
        var changedExisting = false
        var reachedKnownEvent = false
    }

    private static let outboxRetryBaseDelay: TimeInterval = 5
    private static let outboxRetryMaxDelay: TimeInterval = 120
    private static let maxGapPages = 5
    private static let maxHistoryPagesPerLoad = 4

    /// Upload progress (0…1) of attachments being sent, by transaction id.
    private(set) var uploadProgress: [String: Double] = [:]
    /// One delivery task per room with queued messages.
    @ObservationIgnored private var outboxLanes: [String: OutboxLane] = [:]
    @ObservationIgnored private var outboxRetryTask: Task<Void, Never>?
    @ObservationIgnored private var outboxRetryDelay: TimeInterval = 5
    /// The server's `m.upload.size`, fetched once per session in the background.
    @ObservationIgnored private var serverUploadLimit: Int?
    @ObservationIgnored private var serverUploadLimitTask: Task<Void, Never>?
    /// Newest edit per message, kept so an edit read before its original (history) still applies.
    @ObservationIgnored private var latestEdits: [String: EditRecord] = [:]
    /// Reaction event → the message it reacts to, so removing a reaction finds its message.
    @ObservationIgnored private var reactionTargets: [String: String] = [:]

    /// Logout: stops every lane and timer, forgets per-session state, wipes cached media.
    private func resetMessagingPipeline() {
        for lane in outboxLanes.values { lane.task.cancel() }
        outboxLanes = [:]
        outboxRetryTask?.cancel()
        outboxRetryTask = nil
        outboxRetryDelay = Self.outboxRetryBaseDelay
        serverUploadLimitTask?.cancel()
        serverUploadLimitTask = nil
        serverUploadLimit = nil
        uploadProgress = [:]
        latestEdits = [:]
        reactionTargets = [:]
        Task { await MediaLoader.shared.purge() }
    }

    /// Server unreachable while the network is up (Studio or Funnel down): try again later,
    /// 5 s then doubling up to 2 min. A successful sync or a reconnection also restarts the lanes.
    private func scheduleOutboxRetry() {
        guard outboxRetryTask == nil else { return }
        let delay = outboxRetryDelay
        outboxRetryDelay = min(outboxRetryDelay * 2, Self.outboxRetryMaxDelay)
        outboxRetryTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard let self, !Task.isCancelled else { return }
            self.outboxRetryTask = nil
            self.flushOutbox()
        }
    }

    // MARK: Composer

    /// False (and the banner explains why) when the text is over 4 000 characters.
    @discardableResult
    func validateOutgoingText(_ text: String) -> Bool {
        guard MessageLengthPolicy.isTooLong(text) else { return true }
        errorMessage = MessageLengthPolicy.tooLongMessage(for: text)
        return false
    }

    private func formatOutgoing(_ text: String, roomId: String) -> FormattedMessage {
        MessageFormatter.format(text, members: mentionCandidates(roomId: roomId), selfUserId: userId)
    }

    /// Who `@name` can mean in this room: its members, plus the members of its server (space).
    private func mentionCandidates(roomId: String) -> [MentionCandidate] {
        var names = room(roomId)?.members ?? [:]
        for space in rooms where space.roomType == "m.space" && space.spaceChildren.contains(roomId) {
            names.merge(space.members) { current, _ in current }
        }
        return names.map { MentionCandidate(userId: $0.key, displayName: $0.value) }.sorted { $0.userId < $1.userId }
    }

    private func senderId(ofEventId eventId: String, roomId: String) -> String? {
        messageIndex(roomId: roomId, eventId: eventId).flatMap { messagesByRoom[roomId]?[$0].sender.matrixId }
    }

    // MARK: Attachments

    /// Upload progress of an attachment still being sent, nil otherwise.
    func uploadProgress(for message: ChatMessage) -> Double? {
        guard message.sendState == .sending, let txnId = message.txnId else { return nil }
        return uploadProgress[txnId]
    }

    /// The ✕ on an upload, or "Supprimer" on a message that failed: drops the local message,
    /// its queued copy and files. A running upload is cancelled.
    func discardUnsentMessage(_ localId: UUID, roomId: String) {
        guard let message = messagesByRoom[roomId]?.first(where: { $0.id == localId }),
              message.eventId == nil, let txnId = message.txnId else { return }
        if outbox.message(txnId: txnId) != nil {
            if outbox.next(in: roomId)?.txnId == txnId, let lane = outboxLanes.removeValue(forKey: roomId) {
                lane.task.cancel() // it may be uploading this very file
            }
            outbox.remove(txnId: txnId)
        }
        if let failed = failedOutgoing.removeValue(forKey: txnId) { outbox.deleteFiles(of: failed) }
        uploadProgress.removeValue(forKey: txnId)
        messagesByRoom[roomId]?.removeAll { $0.id == localId }
        rebuildUIModels()
        flushOutbox()
    }

    /// Authenticated download to a temporary file (Quick Look, share sheet). Nil and a banner on failure.
    func downloadAttachment(_ attachment: MessageAttachment) async -> URL? {
        guard let url = attachment.url else { return nil }
        do {
            return try await MediaLoader.shared.temporaryFile(for: url, fileName: attachment.name)
        } catch {
            errorMessage = "Impossible de télécharger \(attachment.name) : \(error.localizedDescription)"
            return nil
        }
    }

    /// 25 Mo, or less if the server says so (asked in the background, never blocking a send).
    private func effectiveUploadLimit() -> Int {
        if serverUploadLimit == nil, serverUploadLimitTask == nil, userId != nil {
            serverUploadLimitTask = Task { [weak self] in
                guard let self else { return }
                let limit = await self.client.mediaUploadLimit()
                guard !Task.isCancelled else { return }
                self.serverUploadLimit = limit
                self.serverUploadLimitTask = nil
            }
        }
        guard let server = serverUploadLimit, server > 0 else { return MediaUploadLimits.maxBytes }
        return min(MediaUploadLimits.maxBytes, server)
    }

    /// Uploads the file then its thumbnail; each content URI is saved in the outbox as soon as it
    /// exists, so a retry or a relaunch resumes instead of uploading again.
    private func uploadAttachment(of queued: OutgoingMessage) async throws -> OutgoingMessage {
        guard var attachment = queued.attachment else { return queued }
        var item = queued
        let txnId = item.txnId

        if attachment.contentURI == nil {
            guard let fileURL = outbox.localURL(for: attachment.localFile) else {
                throw MediaPreparation.PreparationError.unreadable(attachment.fileName)
            }
            if uploadProgress[txnId] == nil { uploadProgress[txnId] = 0 }
            let response = try await client.uploadMedia(
                fileURL: fileURL, filename: attachment.fileName, contentType: attachment.mimeType,
                progress: { [weak self] value in
                    Task { @MainActor in self?.reportUploadProgress(txnId: txnId, value) }
                }
            )
            attachment.contentURI = response.contentUri
            item.attachment = attachment
            outbox.update(item)
            if let remote = resolveMediaURL(response.contentUri) {
                await MediaLoader.shared.store(fileAt: fileURL, for: remote)
            }
        }

        if let thumbnailFile = attachment.thumbnailFile, attachment.thumbnailContentURI == nil,
           let thumbnailURL = outbox.localURL(for: thumbnailFile) {
            // Optional: without it other clients ask the server for a thumbnail.
            do {
                let response = try await client.uploadMedia(
                    fileURL: thumbnailURL, filename: "thumbnail-\(attachment.fileName)",
                    contentType: attachment.thumbnailMimeType ?? "image/jpeg"
                )
                attachment.thumbnailContentURI = response.contentUri
                item.attachment = attachment
                outbox.update(item)
                if let remote = resolveMediaURL(response.contentUri) {
                    await MediaLoader.shared.store(fileAt: thumbnailURL, for: remote)
                }
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                if MatrixClient.isTransient(error) || !reachability.isConnected { throw error }
            }
        }
        uploadProgress[txnId] = 1
        return item
    }

    private func reportUploadProgress(txnId: String, _ value: Double) {
        guard let current = uploadProgress[txnId], value > current else { return }
        uploadProgress[txnId] = value
    }

    /// The echo of a queued attachment, shown from the outbox copy.
    private func localAttachment(_ attachment: OutgoingAttachment, txnId: String) -> MessageAttachment {
        let file = outbox.localURL(for: attachment.localFile)
        let isImage = attachment.kind == .image
        return MessageAttachment(
            id: stableUUID(from: "\(txnId)_att"),
            type: isImage ? .image : .file,
            name: attachment.fileName,
            previewEmoji: isImage ? "🖼️" : "📎",
            url: file,
            thumbnailURL: isImage ? (attachment.thumbnailFile.flatMap { outbox.localURL(for: $0) } ?? file) : nil,
            size: attachment.size,
            width: attachment.width,
            height: attachment.height
        )
    }

    /// The same attachment once uploaded (its bytes were put in the media cache).
    private func remoteAttachment(_ attachment: OutgoingAttachment, txnId: String) -> MessageAttachment? {
        guard let contentURI = attachment.contentURI else { return nil }
        let isImage = attachment.kind == .image
        return MessageAttachment(
            id: stableUUID(from: "\(txnId)_att"),
            type: isImage ? .image : .file,
            name: attachment.fileName,
            previewEmoji: isImage ? "🖼️" : "📎",
            url: resolveMediaURL(contentURI),
            thumbnailURL: isImage ? previewURL(mxc: contentURI, thumbnailMxc: attachment.thumbnailContentURI,
                                              width: attachment.width, height: attachment.height) : nil,
            size: attachment.size,
            width: attachment.width,
            height: attachment.height
        )
    }

    /// Message preview: the sender's thumbnail, else the original when it is small, else a server
    /// thumbnail that keeps the aspect ratio ("scale", not the avatar "crop").
    private func previewURL(mxc: String?, thumbnailMxc: String?, width: Int?, height: Int?) -> URL? {
        if let thumbnailMxc, let url = resolveMediaURL(thumbnailMxc) { return url }
        if let width, let height, ImageUploadPlan.thumbnailSize(width: width, height: height) == nil {
            return resolveMediaURL(mxc)
        }
        return resolveMediaURL(mxc, width: ImageUploadPlan.thumbnailBox.width, height: ImageUploadPlan.thumbnailBox.height, method: "scale")
    }

    // MARK: Reception (edits, reactions, redactions, history)

    static func isRedactedEvent(_ event: MatrixEvent) -> Bool {
        if event.unsigned?.redactedBecause != nil { return true }
        guard event.type == "m.room.message" || event.type == "m.room.encrypted" else { return false }
        return event.content?.isEmpty ?? true
    }

    static func replacedEventId(of event: MatrixEvent) -> String? {
        guard let relatesTo = event.content?["m.relates_to"]?.dictValue,
              relatesTo["rel_type"]?.stringValue == "m.replace" else { return nil }
        return relatesTo["event_id"]?.stringValue
    }

    private func isKnownEvent(_ eventId: String, roomId: String) -> Bool {
        messageIndex(roomId: roomId, eventId: eventId) != nil
            || redactedEventIds.contains(eventId)
            || cachedTimelines[roomId]?.contains(where: { $0.eventId == eventId }) == true
    }

    private func applyRedaction(of redactedId: String, roomId: String) {
        if !redactedEventIds.contains(redactedId), let root = conversationRoots[redactedId], let count = conversationSummaries[root] {
            conversationSummaries[root] = max(0, count - 1)
        }
        redactedEventIds.insert(redactedId)
        if let idx = messageIndex(roomId: roomId, eventId: redactedId) {
            messagesByRoom[roomId]?.remove(at: idx)
        }
        reactionEvents.removeValue(forKey: redactedId)
        latestEdits.removeValue(forKey: redactedId)
        // Removing a reaction is a redaction of the reaction event: take it off its message.
        if let target = reactionTargets.removeValue(forKey: redactedId) {
            reactionEvents[target]?.removeAll { $0.eventId == redactedId }
            updateMessageReactions(roomId: roomId, targetEventId: target)
        }
    }

    private func recordReaction(_ event: MatrixEvent, eventId: String, roomId: String) {
        guard let relatesTo = event.content?["m.relates_to"]?.dictValue,
              let targetEventId = relatesTo["event_id"]?.stringValue,
              !redactedEventIds.contains(targetEventId),
              !redactedEventIds.contains(eventId), // already removed (history is read newest first)
              let key = relatesTo["key"]?.stringValue,
              let sender = event.sender else { return }
        // The same reaction can arrive twice (cache replay, then full sync).
        guard reactionEvents[targetEventId]?.contains(where: { $0.eventId == eventId }) != true else { return }
        reactionEvents[targetEventId, default: []].append((emoji: key, sender: sender, eventId: eventId))
        reactionTargets[eventId] = targetEventId
        updateMessageReactions(roomId: roomId, targetEventId: targetEventId)
    }

    private func recordEdit(_ event: MatrixEvent, eventId: String, roomId: String) {
        guard let targetEventId = Self.replacedEventId(of: event), let sender = event.sender else { return }
        let newContent = event.content?["m.new_content"]?.dictValue
        let newBody = newContent?["body"]?.stringValue ?? event.content?["body"]?.stringValue ?? ""
        let timestamp = event.originServerTs ?? 0
        if let current = latestEdits[targetEventId], current.timestamp > timestamp { return } // older edit
        latestEdits[targetEventId] = EditRecord(sender: sender, body: newBody, timestamp: timestamp)

        guard let idx = messageIndex(roomId: roomId, eventId: targetEventId) else { return }
        let original = messagesByRoom[roomId]![idx]
        // Anyone can send an m.replace: only the author's edits count. Attachments keep their card.
        guard original.sender.matrixId == sender, original.attachments.isEmpty else { return }
        messagesByRoom[roomId]![idx] = original.replacing(content: newBody, isEdited: true)
    }

    /// One `/messages` page (newest first): members first, then events oldest → newest so edits,
    /// reactions and deletions meet their message. With `stopAtKnownEvent` the page is cut at the
    /// first event already shown (the gap is closed there).
    private func applyHistoryPage(_ response: MatrixMessagesResponse, roomId: String, stopAtKnownEvent: Bool) -> HistoryPageResult {
        applyMemberState(response.state ?? [], roomId: roomId)
        var events = response.chunk ?? []
        var result = HistoryPageResult()
        if stopAtKnownEvent,
           let firstKnown = events.firstIndex(where: { $0.eventId.map { isKnownEvent($0, roomId: roomId) } ?? false }) {
            events = Array(events[..<firstKnown])
            result.reachedKnownEvent = true
        }
        for event in events.reversed() {
            guard let eventId = event.eventId else { continue }
            switch event.type {
            case "m.room.redaction":
                if let redacted = event.redacts {
                    applyRedaction(of: redacted, roomId: roomId)
                    result.changedExisting = true
                }
            case "m.reaction":
                recordReaction(event, eventId: eventId, roomId: roomId)
                result.changedExisting = true
            case "m.room.message" where Self.replacedEventId(of: event) != nil:
                recordEdit(event, eventId: eventId, roomId: roomId)
                result.changedExisting = true
            default:
                if Self.isRedactedEvent(event) {
                    redactedEventIds.insert(eventId)
                } else if insertHistoricalEvent(event, roomId: roomId) {
                    result.insertedAny = true
                }
            }
        }
        return result
    }

    /// Sync lazy-loads members, so senders of old messages can be unknown: take their names from
    /// the page's member events (never overriding what sync said).
    private func applyMemberState(_ events: [MatrixEvent], roomId: String) {
        guard !events.isEmpty, let index = rooms.firstIndex(where: { $0.roomId == roomId }) else { return }
        var room = rooms[index]
        for event in events where event.type == "m.room.member" {
            guard let member = event.stateKey, room.members[member] == nil,
                  event.content?["membership"]?.stringValue == "join" else { continue }
            processStateEvent(event, room: &room)
        }
        rooms[index] = room
    }
    // MARK: - Account features

    private func restoreAccountStatus(userId: String) {
        (myStatus, myStatusMessage) = AccountStatusStorage.load(userId: userId)
        client.setSyncPresence(Self.matrixPresence(for: myStatus))
    }

    @discardableResult
    func setMyStatus(_ status: MoodUser.UserStatus, message: String? = nil) async -> Bool {
        guard let userId else { errorMessage = "Connecte-toi pour modifier ton statut."; return false }
        let trimmed = message?.trimmingCharacters(in: .whitespacesAndNewlines)
        let newMessage = trimmed?.isEmpty == false ? trimmed : nil
        do {
            try await client.setPresence(userId: userId, presence: Self.matrixPresence(for: status), statusMsg: newMessage)
            myStatus = status
            client.setSyncPresence(Self.matrixPresence(for: status))
            myStatusMessage = newMessage
            AccountStatusStorage.save(status: status, message: newMessage, userId: userId)
            currentUser = makeUser(userId, displayName: currentUser?.displayName, avatarMxc: currentAvatarMxc)
            rebuildUIModels()
            return true
        } catch { errorMessage = "Impossible de modifier le statut. Vérifie ta connexion et réessaie."; return false }
    }

    func setPresenceStatus(presence: String, statusMsg: String? = nil) async {
        guard let userId else { return }
        do { try await client.setPresence(userId: userId, presence: presence, statusMsg: statusMsg) }
        catch { errorMessage = "Impossible de publier ta présence. Vérifie ta connexion." }
    }

    private func refreshOwnRoomProfile(name: String, avatar: String?) {
        guard let userId else { return }
        for index in rooms.indices where rooms[index].members[userId] != nil {
            rooms[index].members[userId] = name
            rooms[index].memberAvatars[userId] = avatar
        }
        rebuildUIModels()
    }

    func resolvedAccountUser(_ user: MoodUser) -> MoodUser {
        guard let id = user.matrixId else { return user }
        if id == userId { return currentUser ?? user }
        let room = rooms.first { $0.members[id] != nil }
        return makeUser(id, displayName: room?.members[id] ?? user.displayName,
                        avatarMxc: room?.memberAvatars[id])
    }

    func createGroupDM(name: String, invitees: [String]) async -> UUID? {
        guard let me = userId else { errorMessage = "Connecte-toi pour créer un groupe."; return nil }
        let invited = Array(Set(invitees).subtracting([me])).sorted()
        guard invited.count >= 2, !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            errorMessage = "Choisis un nom et au moins deux personnes."; return nil
        }
        do {
            let response = try await client.createRoom(name: name, isDirect: true,
                                                       inviteUserIds: invited, preset: "private_chat")
            // Keep every invited peer in m.direct, so groups survive the next sync and relaunch.
            var map = try await client.getDirectRooms(userId: me)
            for peer in invited { map[peer, default: []].append(response.roomId) }
            try await client.setDirectRooms(userId: me, directMap: map)
            directRoomIds.insert(response.roomId)
            groupDirectRoomIds.insert(response.roomId)
            var members = Dictionary(uniqueKeysWithValues: invited.map { ($0, extractLocalpart($0)) })
            members[me] = currentUser?.displayName ?? extractLocalpart(me)
            rooms.append(MatrixRoom(roomId: response.roomId, name: name, topic: "", isDirect: true,
                                    members: members, memberAvatars: [:], unreadCount: 0, mentionCount: 0,
                                    isEncrypted: false, roomType: nil, spaceChildren: [], avatarUrl: nil, heroes: invited))
            rebuildUIModels()
            scheduleCacheSave()
            return stableUUID(from: response.roomId)
        } catch { errorMessage = "Impossible de créer le groupe. Vérifie ta connexion et réessaie."; return nil }
    }

    func isGroupDM(_ conversation: DMConversation) -> Bool {
        guard let id = roomId(for: conversation), let room = rooms.first(where: { $0.roomId == id }) else { return false }
        return groupDirectRoomIds.contains(id) || Set(room.members.keys).subtracting([userId ?? ""]).count > 1
    }

    private(set) var supportsExtendedAccountProfile = false
    private(set) var extendedProfiles: [String: ExtendedProfile] = [:]

    func loadExtendedProfile(userId: String) async {
        do {
            supportsExtendedAccountProfile = try await client.supportsExtendedProfiles()
            guard supportsExtendedAccountProfile else { return }
            extendedProfiles[userId] = try await client.getExtendedProfile(userId: userId)
        }
        catch { errorMessage = "Impossible de charger le profil. Vérifie ta connexion." }
    }

    func updateExtendedProfile(_ profile: ExtendedProfile) async -> Bool {
        guard let userId else { errorMessage = "Connecte-toi pour modifier ton profil."; return false }
        do {
            try await client.setProfileText(userId: userId, field: "mood.bio", value: profile.bio)
            // Reflect each successful field even if the next request fails.
            extendedProfiles[userId, default: ExtendedProfile()].bio = profile.bio
            try await client.setProfileText(userId: userId, field: "mood.pronouns", value: profile.pronouns)
            extendedProfiles[userId, default: ExtendedProfile()].pronouns = profile.pronouns
            return true
        } catch { errorMessage = "Impossible d’enregistrer tout le profil. Réessaie."; return false }
    }

    private var groupDirectRoomIds: Set<String> = []
    private var pendingDirectRooms: [String: Task<String?, Never>] = [:]

    func createDM(userId targetUserId: String) async -> String? {
        guard AccountValidation.isVisiblePeer(targetUserId, me: userId, blocked: ignoredUserIds) else {
            errorMessage = "Choisis une autre personne non bloquée."; return nil
        }
        if let pending = pendingDirectRooms[targetUserId] { return await pending.value }
        let pending = Task { await self.performCreateDM(userId: targetUserId) }
        pendingDirectRooms[targetUserId] = pending
        defer { pendingDirectRooms.removeValue(forKey: targetUserId) }
        return await pending.value
    }

    private func filterBlockedAccountMessages() {
        guard !ignoredUserIds.isEmpty else { return }
        for roomId in Array(messagesByRoom.keys) {
            messagesByRoom[roomId]?.removeAll { $0.sender.matrixId.map(ignoredUserIds.contains) ?? false }
        }
    }

    func openAccountConversation(_ id: UUID) {
        if let roomId = stableIdReverse[id] { requestOpenRoom(roomId) }
    }

    // MARK: - Messaging & servers UI

    private var messagingReceipts: [String: [String: String]] = [:]

    func messagingReaders(roomId: String, eventId: String) -> [String] {
        let list = messagesByRoom[roomId] ?? []
        guard let target = list.firstIndex(where: { $0.eventId == eventId }) else { return [] }
        return (messagingReceipts[roomId] ?? [:]).compactMap { reader, readEvent in
            guard reader != userId, let index = list.firstIndex(where: { $0.eventId == readEvent }), index >= target else { return nil }
            return room(roomId)?.members[reader] ?? extractLocalpart(reader)
        }.sorted()
    }

    private var generatingMessagingInvites: Set<String> = []
    private var messagingInvites: [String: String] = [:]
    private var messagingChannelOrders: [String: [String: String]] = [:]
    private var messagingJoinRules: [String: String] = [:]
    private var joiningMessagingSpaces: Set<String> = []
    var pendingMessagingInvite: String?

    func prepareMessagingInvite(for server: MoodServer) async {
        guard let id = roomId(for: server), messagingInvites[id] == nil, !generatingMessagingInvites.contains(id) else { return }
        generatingMessagingInvites.insert(id)
        defer { generatingMessagingInvites.remove(id) }
        do {
            let code = MoodInvite.makeCode()
            try await client.createMessagingAlias("#\(code):mood.local", roomId: id)
            // A code must be usable by someone who was not already invited.
            try await client.setStateEvent(roomId: id, type: "m.room.join_rules", content: ["join_rule": "public"])
            messagingInvites[id] = code
        } catch { errorMessage = "Impossible de créer l'invitation : \(error.localizedDescription)" }
    }

    private func refreshMessagingRoom(_ id: String) async {
        guard userId != nil else { return }
        let generation = syncGeneration
        do {
            let state = try await client.getRoomState(roomId: id)
            guard generation == syncGeneration, userId != nil else { return }
            var updated = room(id) ?? MatrixRoom(roomId: id, name: id, topic: "", isDirect: false,
                members: [:], memberAvatars: [:], unreadCount: 0, mentionCount: 0,
                isEncrypted: false, roomType: nil, spaceChildren: [], avatarUrl: nil, heroes: [])
            for event in state { processStateEvent(event, room: &updated) }
            if let index = rooms.firstIndex(where: { $0.roomId == id }) { rooms[index] = updated }
            else { rooms.append(updated) }
            rebuildUIModels()
        } catch { errorMessage = "Actualisation du salon impossible : \(error.localizedDescription)" }
    }

    private func createMessagingServer(name: String, isPublic: Bool) async -> UUID? {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, let id = await createSpace(name: name) else { return nil }
        if isPublic {
            do { try await client.setStateEvent(roomId: id, type: "m.room.join_rules", content: ["join_rule": "public"]) }
            catch { errorMessage = "Le serveur a été créé, mais sa visibilité publique n’a pas pu être appliquée."; return nil }
        }
        await refreshMessagingRoom(id)
        guard await createMessagingChannel(spaceId: id, name: "général", topic: "", isPrivate: false) != nil else { return nil }
        return stableUUID(from: id)
    }

    private func createMessagingChannel(spaceId: String, name: String, topic: String, isPrivate: Bool) async -> UUID? {
        do {
            let id = try await client.createMessagingChannel(spaceId: spaceId, name: name, topic: topic, isPrivate: isPrivate,
                powerLevels: room(spaceId)?.powerLevelsContent.mapValues(\.jsonObject) ?? [:]).roomId
            try await client.setStateEvent(roomId: spaceId, type: "m.space.child", stateKey: id,
                content: ["via": ["mood.local"], "order": MessagingServerPolicy.order(room(spaceId)?.spaceChildren.count ?? 0)])
            await refreshMessagingRoom(id)
            await refreshMessagingRoom(spaceId)
            return stableUUID(from: id)
        } catch { errorMessage = "Création du salon échouée : \(error.localizedDescription)"; return nil }
    }

    func joinServerChannels(_ spaceId: String) async {
        guard !joiningMessagingSpaces.contains(spaceId), let space = room(spaceId), space.roomType == "m.space" else { return }
        joiningMessagingSpaces.insert(spaceId)
        defer { joiningMessagingSpaces.remove(spaceId) }
        for child in space.spaceChildren where room(child) == nil {
            do {
                _ = try await client.joinRoom(child)
                await refreshMessagingRoom(child)
            } catch {
                // Private rooms stay hidden. Restricted rooms are retried on the next sync.
            }
        }
    }

    /// Explicit owner repair: invitations remain private unless the owner chooses this action.
    func repairMessagingAccess(_ server: MoodServer) async {
        guard myPowerLevel(in: server) == 100, let spaceId = roomId(for: server) else { return }
        for child in room(spaceId)?.spaceChildren ?? [] {
            do {
                try await client.setStateEvent(roomId: child, type: "m.room.join_rules", content: MessagingServerPolicy.restricted(spaceId: spaceId))
            } catch { errorMessage = "Accès non réparé pour un salon : \(error.localizedDescription)"; return }
        }
    }

    func moveMessagingChannel(_ channel: Channel, in server: MoodServer, offset: Int) async {
        guard let spaceId = roomId(for: server), let id = roomId(for: channel) else { return }
        var ids = server.categories.flatMap(\.channels).compactMap { roomId(for: $0) }
        guard let index = ids.firstIndex(of: id), ids.indices.contains(index + offset) else { return }
        ids.swapAt(index, index + offset)
        do {
            for (position, child) in ids.enumerated() {
                try await client.setStateEvent(roomId: spaceId, type: "m.space.child", stateKey: child,
                    content: ["via": ["mood.local"], "order": MessagingServerPolicy.order(position)])
            }
            await refreshMessagingRoom(spaceId)
        } catch { errorMessage = "Ordre des salons non enregistré : \(error.localizedDescription)" }
    }

    private func resetMessagingServersUI() {
        generatingMessagingInvites = []
        messagingInvites = [:]
        messagingChannelOrders = [:]
        messagingJoinRules = [:]
        messagingReceipts = [:]
        joiningMessagingSpaces = []
        pendingMessagingInvite = nil
    }

    private func loadMessagingContext(roomId: String, eventId: String) async {
        do {
            let response = try await client.messagingContext(roomId: roomId, eventId: eventId)
            applyMemberState(response.state ?? [], roomId: roomId)
            let events = (response.eventsBefore ?? []) + [response.event].compactMap { $0 } + (response.eventsAfter ?? [])
            for event in events.sorted(by: { ($0.originServerTs ?? 0) < ($1.originServerTs ?? 0) }) {
                _ = insertHistoricalEvent(event, roomId: roomId)
            }
            rebuildUIModels()
        } catch { errorMessage = "Ce message n’a pas pu être chargé : \(error.localizedDescription)" }
    }

    func loadMessagingPins(roomId: String) async {
        for eventId in room(roomId)?.pinnedEventIds ?? [] where messageIndex(roomId: roomId, eventId: eventId) == nil {
            await loadMessagingContext(roomId: roomId, eventId: eventId)
        }
    }

    // MARK: - Finish basics

    var ownMoodUsername: (@MainActor () -> String?)?
    private var notificationsUnavailable = false
    private var serverInboxMentions: [InboxMention] = []
    private var directEvidence: [String: [MatrixEvent]] = [:]
    private var checkedDirectRooms: Set<String> = []
    private var directRepairTask: Task<Void, Never>?

    private func resetFinishBasics() {
        directRepairTask?.cancel()
        directRepairTask = nil
        checkedDirectRooms = []
        directEvidence = [:]
        notificationsUnavailable = false
        serverInboxMentions = []
        inboxMentions = []
        inboxState = .idle
    }

    private func rememberDirectEvidence(_ event: MatrixEvent, roomId: String) {
        guard event.content?["is_direct"]?.boolValue == true else { return }
        directEvidence[roomId, default: []].append(event)
    }

    /// Lazy-loaded sync members cannot establish a two-person room: use the complete state first.
    private func scheduleDirectRepair() {
        guard directRepairTask == nil, let me = userId else { return }
        let candidates = rooms.filter { !$0.isDirect && $0.roomType != "m.space" && !checkedDirectRooms.contains($0.roomId) }
        guard !candidates.isEmpty else { return }
        let generation = syncGeneration
        directRepairTask = Task { [weak self] in
            guard let self else { return }
            defer { if generation == self.syncGeneration { self.directRepairTask = nil } }
            for candidate in candidates {
                guard !Task.isCancelled, generation == self.syncGeneration else { return }
                do {
                    let state = try await self.client.getRoomState(roomId: candidate.roomId)
                    guard generation == self.syncGeneration else { return }
                    let joined = state.filter { $0.type == "m.room.member" && $0.content?["membership"]?.stringValue == "join" }
                    var evidence = state + (self.directEvidence[candidate.roomId] ?? [])
                    if joined.count == 2, joined.contains(where: { $0.stateKey == me }),
                       FinishBasicsPolicy.directPeer(me: me, members: state, evidence: evidence, isSpace: false) == nil {
                        // The recipient's old invitation may carry the only is_direct flag.
                        evidence += try await self.client.directMembershipHistory(roomId: candidate.roomId, userId: me)
                    }
                    guard !Task.isCancelled, generation == self.syncGeneration,
                          self.rooms.contains(where: { $0.roomId == candidate.roomId }) else { continue }
                    let isSpace = state.contains { $0.type == "m.room.create" && $0.content?["type"]?.stringValue == "m.space" }
                    if let peer = FinishBasicsPolicy.directPeer(me: me, members: state, evidence: evidence, isSpace: isSpace) {
                        guard await self.registerDirectRoom(candidate.roomId, with: peer) else { continue }
                        guard generation == self.syncGeneration,
                              let index = self.rooms.firstIndex(where: { $0.roomId == candidate.roomId }) else { return }
                        self.directRoomIds.insert(candidate.roomId)
                        var updated = self.rooms[index]
                        updated.isDirect = true
                        for event in state { self.processStateEvent(event, room: &updated) }
                        self.rooms[index] = updated
                        self.rebuildUIModels()
                        self.scheduleCacheSave()
                    }
                    self.checkedDirectRooms.insert(candidate.roomId)
                } catch {
                    // Retry after a later sync; never classify a room from incomplete data.
                }
            }
        }
    }

    private func rebuildLocalMentions() {
        guard let me = userId else { return }
        let names = [currentUser?.displayName, ownMoodUsername?()].compactMap { $0 }
        var mentions: [String: InboxMention] = [:]
        for (roomId, events) in cachedTimelines {
            for event in FinishBasicsPolicy.effectiveMessages(events) where FinishBasicsPolicy.isMention(event, me: me, names: names, ignored: ignoredUserIds) {
                guard let eventId = event.eventId, !redactedEventIds.contains(eventId),
                      let destination = destination(forRoomId: roomId), let sender = event.sender else { continue }
                let source = room(roomId)
                let read = source?.mentionCount == 0 || readThroughUnreadEventIdByRoom[roomId] != nil
                let entry = InboxMention(id: eventId, roomId: roomId,
                    sender: makeUser(sender, displayName: source?.members[sender], avatarMxc: source?.memberAvatars[sender]),
                    text: messageIndex(roomId: roomId, eventId: eventId).flatMap { messagesByRoom[roomId]?[$0].content } ?? Self.plainBody(of: event),
                    timestamp: Date(timeIntervalSince1970: Double(event.originServerTs ?? 0) / 1000),
                    isRead: read, destination: destination)
                mentions[eventId] = entry
            }
        }
        let cachedMessageIds = Set(cachedTimelines.values.flatMap { $0 }.filter { $0.type == "m.room.message" }.compactMap(\.eventId))
        for entry in serverInboxMentions where !cachedMessageIds.contains(entry.id) && mentions[entry.id] == nil && !redactedEventIds.contains(entry.id)
            && !ignoredUserIds.contains(entry.sender.matrixId ?? "") && destination(forRoomId: entry.roomId) != nil {
            mentions[entry.id] = entry
        }
        inboxMentions = mentions.values.sorted { $0.timestamp > $1.timestamp }
        inboxState = .loaded
    }

    /// Deterministic, disconnected fixtures for this brief's simulator captures.
    func loadFinishBasicsPreview() {
        guard userId == nil, ProcessInfo.processInfo.arguments.contains("-uiPreview"),
              ProcessInfo.processInfo.arguments.contains("-finishBasicsPreview") else { return }
        pendingInvites = [
            PendingInvite(id: "!preview-dm:mood.local", roomName: "Clara", inviter: "@preview-clara:mood.local", isDirect: true, inviterName: "Clara"),
            PendingInvite(id: "!preview-space:mood.local", roomName: "Les amis", inviter: "@preview-leo:mood.local", inviterName: "Léo")
        ]
        if let server = MockData.servers.first, let channel = server.categories.flatMap(\.channels).first {
            inboxMentions = [InboxMention(id: "$preview-mention", roomId: "!preview-channel:mood.local", sender: MockData.users[1],
                text: "@augustin Tu viens discuter avec nous ?", timestamp: Date(timeIntervalSince1970: 1791982800),
                isRead: false, destination: .channel(channel, server))]
            inboxState = .loaded
        }
    }

    /// Friend addition is an exact handle lookup, with no directory match for a different person.
    func searchMoodUsername(_ input: String) async -> [MatrixUserResult] {
        errorMessage = nil
        guard let username = MoodUsername.normalized(input) else {
            errorMessage = MoodUsername.rule
            return []
        }
        guard userId != nil, let lookup = usernameLookup else {
            errorMessage = "Connecte-toi à Mood pour rechercher un ami."
            return []
        }
        do {
            guard let id = try await lookup(username),
                  AccountValidation.isVisiblePeer(id, me: userId, blocked: ignoredUserIds) else { return [] }
            let profile = try? await client.getProfile(userId: id)
            return [MatrixUserResult(userId: id, displayName: profile?.displayname ?? username, avatarUrl: profile?.avatarUrl)]
        } catch {
            errorMessage = "Recherche impossible. Vérifie ta connexion et réessaie."
            return []
        }
    }

    // MARK: - Conversation (N1)

    private var pendingConversationLink: URL?
    private var conversationHasSynced = false
    var conversationThreadJump: JumpTarget?
    private var conversationRoots: [String: String] = [:]
    private var conversationHeldUnread: Set<String> = []
    private var conversationSummaries: [String: Int] = [:]
    private(set) var conversationMarkedRooms: Set<String> = []
    private var conversationLegacyRooms: Set<String> = []
    private(set) var conversationThreadUnread: [String: [String: Int]] = [:]
    private var conversationHistoryCursor: [String: String] = [:]
    private(set) var conversationHistoryComplete: Set<String> = []
    private(set) var conversationLoading: Set<String> = []
    private var conversationThreadCursors: [String: String] = [:]
    private var conversationUnavailableThreads: Set<String> = []

    func conversationJumpRoot(roomId: String) -> ChatMessage? {
        guard let jump = conversationThreadJump, jump.roomId == roomId, let root = conversationRoots[jump.eventId] else { return nil }
        return (messagesByRoom[roomId] ?? []).first { $0.eventId == root }
    }

    func prepareConversationPreview() {
        guard userId == nil, ConversationPreview.screen != nil else { return }
        let id = ConversationPreview.room
        messagesByRoom[id] = [ConversationPreview.root] + ConversationPreview.replies
        for reply in ConversationPreview.replies { if let event = reply.eventId { conversationRoots[event] = "$n1-root" } }
        conversationHistoryComplete.insert(id)
        conversationThreadUnread[id] = ["$n1-root": 2]
        servers = MockData.servers
        dmConversations = MockData.dmConversations
        for server in servers {
            for channel in server.categories.flatMap(\.channels) { stableIdReverse[channel.id] = "!preview-" + channel.id.uuidString + ":mood.local" }
        }
        for dm in dmConversations { stableIdReverse[dm.id] = "!preview-" + dm.id.uuidString + ":mood.local" }
    }

    func conversationStartsDay(_ message: ChatMessage, roomId: String) -> Bool {
        let visible = (messagesByRoom[roomId] ?? []).filter { conversationRoot(of: $0) == nil }
        guard let index = visible.firstIndex(where: { $0.id == message.id }) else { return false }
        return index == 0 || !Calendar.current.isDate(visible[index - 1].timestamp, inSameDayAs: message.timestamp)
    }

    private func resetConversation() {
        pendingConversationLink = nil
        conversationHasSynced = false
        conversationThreadJump = nil
        conversationRoots = [:]
        conversationHeldUnread = []
        conversationSummaries = [:]
        conversationMarkedRooms = []
        conversationLegacyRooms = []
        conversationThreadUnread = [:]
        conversationHistoryCursor = [:]
        conversationHistoryComplete = []
        conversationLoading = []
        conversationThreadCursors = [:]
        conversationUnavailableThreads = []
    }

    private func applyConversationSync(roomId: String, data: JoinedRoom) {
        let flags = (data.accountData?.events ?? []).filter { ["m.marked_unread", "com.famedly.marked_unread"].contains($0.type) }
        if flags.contains(where: { $0.type == "com.famedly.marked_unread" }) { conversationLegacyRooms.insert(roomId) }
        if let unread = ConversationPolicy.markedUnread(flags) {
            if unread { conversationMarkedRooms.insert(roomId) }
            else { conversationMarkedRooms.remove(roomId) }
        }
        if let threads = data.unreadThreadNotifications {
            conversationThreadUnread[roomId] = threads.mapValues { $0.notificationCount ?? 0 }
        }
    }

    func setConversationUnread(roomId: String, unread: Bool) async {
        guard let me = userId else { return }
        let generation = syncGeneration
        do {
            try await client.conversationMarkedUnread(userId: me, roomId: roomId, unread: unread)
            // Clear the legacy flag too if another client has used it.
            if conversationLegacyRooms.contains(roomId) {
                try await client.conversationMarkedUnread(userId: me, roomId: roomId, unread: unread, legacy: true)
            }
            guard generation == syncGeneration else { return }
            if unread { conversationMarkedRooms.insert(roomId); if openRoomId == roomId { conversationHeldUnread.insert(roomId) } }
            else { conversationMarkedRooms.remove(roomId) }
            rebuildUIModels()
        } catch { if generation == syncGeneration { errorMessage = "Impossible de modifier le statut non lu. Réessaie." } }
    }

    private func clearConversationUnread(roomId: String) {
        guard conversationMarkedRooms.contains(roomId) else { return }
        Task { await setConversationUnread(roomId: roomId, unread: false) }
    }

    private func conversationRoot(of message: ChatMessage) -> String? {
        message.eventId.flatMap { conversationRoots[$0] } ?? message.txnId.flatMap { conversationRoots[$0] }
    }

    func conversationReplies(roomId: String, root: String) -> [ChatMessage] {
        computeGrouping((messagesByRoom[roomId] ?? []).filter { conversationRoot(of: $0) == root })
    }

    func conversationThreads(roomId: String) -> [ChatMessage] {
        timeline(roomId: roomId).filter { $0.threadInfo != nil }.sorted { ($0.threadInfo?.lastReplyDate ?? $0.timestamp) > ($1.threadInfo?.lastReplyDate ?? $1.timestamp) }
    }

    /// One bounded page per invocation, with explicit "older" action; never claim a complete history early.
    func loadConversationHistory(roomId: String) async {
        guard userId != nil, !conversationLoading.contains(roomId), !conversationHistoryComplete.contains(roomId) else { return }
        let generation = syncGeneration
        conversationLoading.insert(roomId)
        defer { if generation == syncGeneration { conversationLoading.remove(roomId) } }
        do {
            if !conversationUnavailableThreads.contains(roomId) {
                do {
                    let roots = try await client.conversationThreads(roomId: roomId, from: conversationThreadCursors[roomId])
                    guard generation == syncGeneration else { return }
                    for event in roots.chunk {
                        _ = insertHistoricalEvent(event, roomId: roomId)
                        if let id = event.eventId, let summary = event.unsigned?.relations?["m.thread"]?.dictValue {
                            conversationSummaries[id] = summary["count"]?.intValue
                            if let latest = summary["latest_event"],
                               let raw = try? JSONEncoder().encode(latest),
                               let reply = try? JSONDecoder().decode(MatrixEvent.self, from: raw) {
                                processConversationHistory(reply, roomId: roomId)
                            }
                        }
                    }
                    conversationThreadCursors[roomId] = roots.nextBatch
                } catch let error as MatrixClient.MatrixError {
                    if case .httpError(let status, let code, _, _) = error, status == 404 || code == "M_UNRECOGNIZED" { conversationUnavailableThreads.insert(roomId) }
                    else { throw error }
                }
            }
            let previous = conversationHistoryCursor[roomId]
            let page = try await client.roomMessages(roomId: roomId, from: previous, limit: 100)
            guard generation == syncGeneration else { return }
            for event in (page.chunk ?? []).reversed() {
                processConversationHistory(event, roomId: roomId)
            }
            conversationHistoryCursor[roomId] = page.end
            if page.chunk?.isEmpty != false || page.end == nil || page.end == previous { conversationHistoryComplete.insert(roomId) }
            // Thread roots can predate this page; context retrieves them without /relations.
            let missing = Set((page.chunk ?? []).compactMap(ConversationPolicy.threadRoot)).filter { messageIndex(roomId: roomId, eventId: $0) == nil }
            for root in missing { await loadMessagingContext(roomId: roomId, eventId: root) }
            rebuildUIModels()
        } catch { if generation == syncGeneration { errorMessage = "Impossible de charger les fils. Réessaie." } }
    }

    private func processConversationHistory(_ event: MatrixEvent, roomId: String) {
        if event.type == "m.room.redaction", let id = event.redacts ?? event.content?["redacts"]?.stringValue { applyRedaction(of: id, roomId: roomId); return }
        if event.type == "m.room.message", let id = event.eventId, Self.replacedEventId(of: event) != nil { recordEdit(event, eventId: id, roomId: roomId); return }
        _ = insertHistoricalEvent(event, roomId: roomId)
    }

    func readConversationThread(roomId: String, root: String) async {
        guard userId != nil, let last = conversationReplies(roomId: roomId, root: root).last?.eventId else { return }
        do {
            try await client.conversationThreadRead(roomId: roomId, root: root, eventId: last, isPrivate: !preferences.sendsReadReceipts)
            conversationThreadUnread[roomId]?[root] = 0
        } catch { errorMessage = "Impossible de marquer ce fil comme lu. Réessaie." }
    }

    func forwardConversationMessage(_ message: ChatMessage, to roomId: String) async -> Bool {
        guard userId != nil, !isRoomEncrypted(roomId), let text = ConversationPolicy.forwardedText(message), validateOutgoingText(text) else { return false }
        let generation = syncGeneration
        do {
            let sent = try await client.sendMessage(roomId: roomId, body: text)
            guard generation == syncGeneration else { return false }
            // Only update after server acceptance. The sync will deduplicate the event ID.
            let event = MatrixEvent(type: "m.room.message", eventId: sent.eventId, sender: userId,
                originServerTs: Int64(Date().timeIntervalSince1970 * 1000), content: ["msgtype": AnyCodable("m.text"), "body": AnyCodable(text)], stateKey: nil, unsigned: nil, redacts: nil)
            processTimelineEvent(event, roomId: roomId)
            rebuildUIModels()
            return true
        } catch { errorMessage = "Le message n’a pas été transféré. Vérifie ta connexion et réessaie."; return false }
    }

    func openConversationSearchResult(_ hit: SearchHit) {
        requestOpenRoom(hit.roomId)
        requestJump(roomId: hit.roomId, eventId: hit.eventId)
    }

    func openConversationLink(_ url: URL) {
        guard let target = ConversationPolicy.target(url) else { return }
        guard userId != nil, conversationHasSynced else {
            pendingConversationLink = url
            return
        }
        guard destination(forRoomId: target.room) != nil else {
            errorMessage = "Cette conversation n’est pas accessible. Ouvre Mood et réessaie après la connexion."
            return
        }
        requestOpenRoom(target.room)
        requestJump(roomId: target.room, eventId: target.event)
    }

    private func conversationSystemMessage(_ event: MatrixEvent, roomId: String) -> ChatMessage? {
        guard !Self.isRedactedEvent(event), let id = event.eventId else { return nil }
        let source = room(roomId)
        func name(_ id: String?) -> String {
            guard let id else { return "Quelqu’un" }
            return source?.members[id] ?? (id == event.stateKey ? event.content?["displayname"]?.stringValue : nil) ?? "Quelqu’un"
        }
        guard let text = ConversationPolicy.systemText(event, actor: name(event.sender), member: name(event.stateKey)) else { return nil }
        return ChatMessage(id: stableUUID(from: id), sender: makeUser(event.sender ?? "unknown", displayName: name(event.sender)), content: text,
            timestamp: Date(timeIntervalSince1970: Double(event.originServerTs ?? 0) / 1000), isGrouped: false, isSystemMessage: true, eventId: id)
    }

    // MARK: - Media & composer (N2)

    func mediaVoiceWaveform(roomId: String, eventId: String) async -> [Int] {
        guard let event = try? await client.mediaEvent(roomId: roomId, eventId: eventId),
              event.content?["org.matrix.msc3245.voice"] != nil,
              let audio = event.content?["org.matrix.msc1767.audio"]?.dictValue,
              let values = audio["waveform"]?.arrayValue else { return [] }
        return values.prefix(1024).compactMap(\.intValue).map { min(1024, max(0, $0)) }
    }


    func sendVoice(roomId: String, fileURL: URL, waveform: [Int], duration: Int) async {
        guard let folder = outbox.filesDirectory, let owner = userId, !isRoomEncrypted(roomId) else { return }
        let txnId = UUID().uuidString
        do {
            var attachment = try await MediaPreparation.prepare(sourceURL: fileURL, txnId: txnId, folder: folder, limit: effectiveUploadLimit())
            guard userId == owner, !isRoomEncrypted(roomId) else {
                for name in attachment.localFiles { try? FileManager.default.removeItem(at: folder.appendingPathComponent(name)) }
                return
            }
            attachment.voiceWaveform = Array(waveform.prefix(1024)).map { min(1024, max(0, $0)) }
            attachment.duration = max(0, duration)
            let message = OutgoingMessage(txnId: txnId, roomId: roomId, body: attachment.fileName,
                                          replyToEventId: nil, threadRootEventId: nil, createdAt: Date(), attachment: attachment)
            insertSorted(makeLocalEcho(roomId: roomId, body: message.body, txnId: txnId, replyToEventId: nil,
                                       createdAt: message.createdAt, attachment: attachment), roomId: roomId)
            uploadProgress[txnId] = 0
            outbox.enqueue(message)
            rebuildUIModels()
            flushOutbox()
        } catch { errorMessage = error.localizedDescription }
    }

    private var n2PreviewCache: [URL: MediaLinkPreview] {
        get { N2PreviewCache.shared.values }
        set { N2PreviewCache.shared.values = newValue }
    }

    func mediaLinkPreview(_ url: URL) async -> MediaLinkPreview? {
        if let cached = n2PreviewCache[url] { return cached }
        do {
            let preview = try await client.mediaLinkPreview(url)
            if n2PreviewCache.count >= 100 { n2PreviewCache.removeAll() }
            n2PreviewCache[url] = preview
            return preview
        } catch { return nil } // Embeds are optional; never block sending or the timeline.
    }

    @discardableResult
    func sendAttachments(roomId: String, urls: [URL], text: String = "", replyToEventId: String? = nil) async -> Bool {
        guard urls.count <= AttachmentSelectionPolicy.limit else {
            errorMessage = "Tu peux joindre au maximum 10 fichiers."
            return false
        }
        guard let owner = userId, !isRoomEncrypted(roomId), validateOutgoingText(text),
              let folder = outbox.filesDirectory else {
            errorMessage = "Impossible d’envoyer dans cette conversation."
            return false
        }
        var prepared: [OutgoingMessage] = []
        do {
            // Prepare the entire selection first. A bad tenth file must not send the first nine twice
            // when the user fixes it and retries. No network upload starts until all copies exist.
            for url in urls {
                let access = url.startAccessingSecurityScopedResource()
                defer { if access { url.stopAccessingSecurityScopedResource() } }
                let txnId = UUID().uuidString
                let attachment = try await MediaPreparation.prepare(sourceURL: url, txnId: txnId, folder: folder, limit: effectiveUploadLimit())
                prepared.append(OutgoingMessage(txnId: txnId, roomId: roomId, body: attachment.fileName,
                                               replyToEventId: nil, threadRootEventId: nil, createdAt: Date(), attachment: attachment))
            }
            guard userId == owner, !isRoomEncrypted(roomId) else { throw CancellationError() }
            if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                await sendMessage(roomId: roomId, text: text, replyToEventId: replyToEventId)
            }
            for message in prepared {
                insertSorted(makeLocalEcho(roomId: roomId, body: message.body, txnId: message.txnId, replyToEventId: nil,
                                           createdAt: message.createdAt, attachment: message.attachment), roomId: roomId)
                uploadProgress[message.txnId] = 0
                outbox.enqueue(message)
            }
            clearNewMessagesDivider(roomId: roomId)
            rebuildUIModels()
            flushOutbox()
            return true
        } catch {
            for message in prepared { outbox.deleteFiles(of: message) }
            errorMessage = error is CancellationError ? "Envoi annulé : la conversation ou la session a changé." : error.localizedDescription
            return false
        }
    }

}

@MainActor
private final class N2PreviewCache {
    static let shared = N2PreviewCache()
    var values: [URL: MediaLinkPreview] = [:]
}
