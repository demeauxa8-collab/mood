import Foundation
import Testing
@testable import mood

@Suite(.serialized) @MainActor
struct PremiumRecoveryTests {
    private func defaults() -> UserDefaults { UserDefaults(suiteName: "PremiumTests.\(UUID())")! }
    private func temporaryFile() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("premium-\(UUID())/outbox.json")
    }
    private func store(box: MessageOutbox, network: NetworkReachability, creation: CreationRecovery? = nil) -> MatrixStore {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [PremiumRecoveryProtocol.self]
        let client = MatrixClient(homeserver: "https://premium.invalid", conversationSession: URLSession(configuration: config))
        client.setAccessToken("synthetic-premium-test-value")
        let store = MatrixStore(client: client, outbox: box, reachability: network,
                                creationRecovery: creation ?? CreationRecovery(defaults: defaults()))
        store.preparePremiumTransportTestSession()
        return store
    }
    private func eventually(_ check: () -> Bool) async -> Bool {
        for _ in 0..<200 {
            if check() { return true }
            try? await Task.sleep(for: .milliseconds(10))
        }
        return check()
    }

    @Test func networkAndServiceFailuresStayDistinctAndSessionWins() {
        #expect(ConversationConnection.resolve(networkAvailable: false, service: .connected) == .offline)
        #expect(ConversationConnection.resolve(networkAvailable: true, service: .serverUnavailable) == .serverUnavailable)
        #expect(ConversationConnection.resolve(networkAvailable: false, service: .sessionExpired) == .sessionExpired)
        #expect(ConversationConnection.resolve(networkAvailable: true, service: .connecting) == .connecting)
        #expect(ConversationRecovery.waitingLabel(1) == "1 message en attente")
        #expect(ConversationRecovery.waitingLabel(2) == "2 messages en attente")
    }

    @Test func connectionCapsuleExplainsTheQueueWithoutClaimingDelivery() {
        #expect(ConversationConnection.offline.capsuleLabel(waiting: 0) == "Hors ligne · tu peux continuer à écrire")
        #expect(ConversationConnection.offline.capsuleLabel(waiting: 1) == "Hors ligne · 1 message partira au retour du réseau")
        #expect(ConversationConnection.offline.capsuleLabel(waiting: 2) == "Hors ligne · 2 messages partiront au retour du réseau")
        #expect(ConversationConnection.serverUnavailable.capsuleLabel(waiting: 2) == "Mood injoignable · 2 messages partiront au retour du service")
        #expect(ConversationConnection.sessionExpired.capsuleLabel(waiting: 2) == "Ta session a expiré")
        #expect(ConversationConnection.connecting.capsuleLabel(waiting: 2) == "Connexion en cours…")
    }

    @Test func undoTimebarClampsToTheRealFiveSecondDeadline() {
        let now = Date(timeIntervalSince1970: 1_000)
        let deletion = DeferredMessageDeletion(roomID: "room", eventID: "event", now: now)
        #expect(deletion.remainingFraction(at: now.addingTimeInterval(-1)) == 1)
        #expect(deletion.remainingFraction(at: now) == 1)
        #expect(deletion.remainingFraction(at: now.addingTimeInterval(2.5)) == 0.5)
        #expect(deletion.remainingFraction(at: now.addingTimeInterval(5)) == 0)
        #expect(deletion.remainingFraction(at: now.addingTimeInterval(8)) == 0)
    }

    @Test func interruptionMidSendKeepsQueueAndReconnectDeliversInOrderWithStableTransaction() async {
        PremiumRecoveryProtocol.reset(firstStatus: -1)
        let box = MessageOutbox(fileURL: nil, defaults: defaults())
        let network = NetworkReachability(monitoring: false)
        let store = store(box: box, network: network)
        await store.sendMessage(roomId: "!r:example.invalid", text: "Premier")
        #expect(await eventually { store.connection == .serverUnavailable })
        #expect(box.pending.count == 1)
        network.update(isConnected: false)
        #expect(store.connection == .offline)
        await store.sendMessage(roomId: "!r:example.invalid", text: "Deuxième")
        #expect(store.pendingMessageCount == 2)
        #expect(store.pendingMessageCount(roomID: "!other:example.invalid") == 0)
        network.update(isConnected: true)
        #expect(await eventually { box.pending.isEmpty })
        let sent = store.messagesByRoom["!r:example.invalid"] ?? []
        #expect(sent.count == 2)
        #expect(sent.allSatisfy { $0.sendState == .sent })
        #expect(store.recoveredDeliveryCount == 2)
        let requests = PremiumRecoveryProtocol.sendTransactions
        #expect(requests.count == 3)
        #expect(requests[0] == requests[1])
        #expect(requests[1] != requests[2])
        store.logout()
    }

    @Test func rejectedMessageCanRetryOnceWithSameIDAndCanBeDiscarded() async throws {
        PremiumRecoveryProtocol.reset(firstStatus: 403)
        let box = MessageOutbox(fileURL: nil, defaults: defaults())
        let store = store(box: box, network: NetworkReachability(monitoring: false))
        let room = "!r:example.invalid"
        await store.sendMessage(roomId: room, text: "À reprendre")
        #expect(await eventually { store.messagesByRoom[room]?.first?.sendState == .failed })
        let message = try #require(store.messagesByRoom[room]?.first)
        #expect(box.failed.count == 1)
        store.retryMessage(message.id, roomId: room)
        store.retryMessage(message.id, roomId: room) // a double tap never enqueues a duplicate
        #expect(await eventually { store.messagesByRoom[room]?.first?.sendState == .sent })
        #expect(box.failed.isEmpty)
        #expect(Set(PremiumRecoveryProtocol.sendTransactions).count == 1)
        #expect(store.messagesByRoom[room]?.first?.id == message.id)
        store.logout()
        let offlineBox = MessageOutbox(fileURL: nil, defaults: defaults())
        let offline = self.store(box: offlineBox, network: NetworkReachability(monitoring: false, initiallyConnected: false))
        await offline.sendMessage(roomId: room, text: "À supprimer")
        let queued = try #require(offline.messagesByRoom[room]?.first)
        offline.discardUnsentMessage(queued.id, roomId: room)
        #expect(offline.pendingMessageCount == 0)
        #expect(offline.messagesByRoom[room]?.isEmpty == true)
        offline.logout()
    }

    @Test func expiredSessionPreservesPendingMessageAndCachedHistory() async throws {
        PremiumRecoveryProtocol.reset(firstStatus: 401)
        let box = MessageOutbox(fileURL: nil, defaults: defaults())
        let store = store(box: box, network: NetworkReachability(monitoring: false))
        let room = "!r:example.invalid"
        await store.sendMessage(roomId: room, text: "Je reste ici")
        #expect(await eventually { store.connection == .sessionExpired })
        #expect(store.userId != nil)
        #expect(store.pendingMessageCount == 1)
        #expect(store.messagesByRoom[room]?.first?.content == "Je reste ici")
        store.retryConnection()
        #expect(store.connection == .sessionExpired)
        #expect(PremiumRecoveryProtocol.sendTransactions.count == 1)
        store.logout()
    }

    @Test func failedAttachmentsSurviveRelaunchAndAreIsolatedByAccount() throws {
        let file = temporaryFile()
        defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
        let settings = defaults()
        let box = MessageOutbox(fileURL: file, defaults: settings)
        box.adopt(ownerID: "alice")
        let attachment = OutgoingAttachment(kind: .audio, fileName: "Vocal.m4a", localFile: "vocal.m4a", mimeType: "audio/mp4", size: 4)
        let url = try #require(box.localURL(for: attachment.localFile))
        try Data([0, 1, 2, 3]).write(to: url)
        let item = OutgoingMessage(txnId: "same", roomId: "room", body: "Vocal.m4a", replyToEventId: nil, threadRootEventId: nil, createdAt: Date(), attachment: attachment)
        box.enqueue(item)
        box.retainFailed(item)
        let restored = MessageOutbox(fileURL: file, defaults: settings)
        #expect(restored.pending.isEmpty)
        #expect(restored.failed == [item])
        #expect(FileManager.default.fileExists(atPath: url.path))
        restored.retryFailed(item)
        restored.retryFailed(item)
        #expect(restored.pending == [item])
        #expect(restored.failed.isEmpty)
        restored.adopt(ownerID: "bob")
        #expect(restored.pending.isEmpty)
        #expect(!FileManager.default.fileExists(atPath: url.path))
    }

    @Test func oversizedPhotoDoesNotPartiallySendTextAndOfflineVoiceKeepsItsWaveform() async throws {
        let file = temporaryFile()
        let folder = file.deletingLastPathComponent()
        defer { try? FileManager.default.removeItem(at: folder) }
        let box = MessageOutbox(fileURL: file, defaults: defaults())
        let store = store(box: box, network: NetworkReachability(monitoring: false, initiallyConnected: false))
        let photo = folder.appendingPathComponent("too-large.jpg")
        FileManager.default.createFile(atPath: photo.path, contents: Data())
        let handle = try FileHandle(forWritingTo: photo)
        try handle.truncate(atOffset: UInt64(MediaUploadLimits.maxBytes + 1))
        try handle.close()
        let sent = await store.sendAttachments(roomId: "room", urls: [photo], text: "Garde mon texte")
        #expect(!sent)
        #expect(box.pending.isEmpty)
        #expect(store.messagesByRoom["room"]?.isEmpty ?? true)
        #expect(store.errorMessage?.contains("limite") == true)
        let voice = folder.appendingPathComponent("voice.m4a")
        try Data([0, 1, 2, 3]).write(to: voice)
        await store.sendVoice(roomId: "room", fileURL: voice, waveform: [-1, 8, 2048], duration: 300)
        let queued = try #require(box.pending.first)
        #expect(queued.attachment?.voiceWaveform == [0, 8, 1024])
        #expect(queued.attachment?.duration == 300)
        #expect(store.pendingMessageCount == 1)
        #expect(store.connection == .offline)
        store.logout()
    }

    @Test func serviceErrorsNeverExposeRawTechnicalPayloads() {
        let raw = "internal-detail-not-for-display"
        for status in [400, 401, 403, 404, 413, 429, 500, 502, 503] {
            let error = MatrixClient.MatrixError.httpError(statusCode: status, errcode: nil, message: raw, retryAfterMs: nil)
            #expect(!error.localizedDescription.contains(raw))
        }
        let expired = MatrixClient.MatrixError.httpError(statusCode: 401, errcode: "M_UNKNOWN_TOKEN", message: raw, retryAfterMs: nil)
        #expect(expired.localizedDescription.contains("Reconnecte-toi"))
    }

    @Test func partialServerAndChannelCreationResumeAfterRelaunchWithoutCreatingDuplicates() async throws {
        PremiumRecoveryProtocol.resetCreationFailure()
        let preferences = defaults()
        let recovery = CreationRecovery(defaults: preferences)
        let box = MessageOutbox(fileURL: nil, defaults: defaults())
        let first = store(box: box, network: NetworkReachability(monitoring: false), creation: recovery)
        #expect(await first.createServer(name: "Les amis", isPublic: true) == nil)
        #expect(PremiumRecoveryProtocol.createdRoomCount == 2)
        let identity = CreationIdentity(kind: .server, arguments: ["Les amis", "true"])
        #expect(recovery.remoteID(for: identity, owner: "@premium-test:example.invalid") != nil)
        #expect(recovery.remoteID(for: identity, owner: "another-account") == nil)
        #expect(recovery.remoteID(for: CreationIdentity(kind: .server, arguments: ["Les amis", "false"]), owner: "@premium-test:example.invalid") == nil)
        let restored = CreationRecovery(defaults: preferences)
        let second = store(box: MessageOutbox(fileURL: nil, defaults: defaults()), network: NetworkReachability(monitoring: false), creation: restored)
        #expect(await second.createServer(name: "Les amis", isPublic: true) != nil)
        #expect(PremiumRecoveryProtocol.createdRoomCount == 2) // same space and child, only their link retried
        #expect(restored.remoteID(for: identity, owner: "@premium-test:example.invalid") == nil)
        first.logout()
        second.logout()
    }

    @Test func deletionWaitsFiveSecondsUndoCancelsRequestAndFailureRestoresMessage() async throws {
        PremiumRecoveryProtocol.reset(firstStatus: 403)
        let box = MessageOutbox(fileURL: nil, defaults: defaults())
        let store = store(box: box, network: NetworkReachability(monitoring: false))
        let room = "!r:example.invalid", event = "$message"
        let message = ChatMessage(id: UUID(), sender: MockData.currentUser, content: "À garder", timestamp: Date(), isGrouped: false, eventId: event)
        store.messagesByRoom[room] = [message]
        store.scheduleMessageDeletion(roomID: room, eventID: event)
        let deletion = try #require(store.pendingDeletions.first)
        #expect(deletion.deadline.timeIntervalSinceNow > 4.8)
        await store.commitMessageDeletion(deletion, now: deletion.deadline.addingTimeInterval(-0.001))
        #expect(PremiumRecoveryProtocol.redactionCount == 0)
        #expect(store.isDeletionPending(message, roomID: room))
        store.undoMessageDeletion(deletion.id)
        await store.commitMessageDeletion(deletion, now: deletion.deadline)
        #expect(PremiumRecoveryProtocol.redactionCount == 0)
        #expect(!store.isDeletionPending(message, roomID: room))
        store.scheduleMessageDeletion(roomID: room, eventID: event)
        let retry = try #require(store.pendingDeletions.first)
        await store.commitMessageDeletion(retry, now: retry.deadline)
        #expect(PremiumRecoveryProtocol.redactionCount == 1)
        #expect(store.deletionFailure != nil)
        #expect(store.messagesByRoom[room]?.first?.content == "À garder")
        #expect(!store.isDeletionPending(message, roomID: room))
        store.scheduleMessageDeletion(roomID: room, eventID: event)
        let final = try #require(store.pendingDeletions.first)
        await store.commitMessageDeletion(final, now: final.deadline)
        await store.commitMessageDeletion(final, now: final.deadline) // stale timer is harmless
        #expect(PremiumRecoveryProtocol.redactionCount == 2)
        #expect(store.messagesByRoom[room]?.isEmpty == true)
        store.logout()
    }
}

/// Intercepts every request. A typo cannot fall through to the network or a real Mood service.
private final class PremiumRecoveryProtocol: URLProtocol, @unchecked Sendable {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var firstStatus = 200
    nonisolated(unsafe) private static var sends: [String] = []
    nonisolated(unsafe) private static var redactions = 0
    nonisolated(unsafe) private static var creationMode = false
    nonisolated(unsafe) private static var createdRooms = 0
    nonisolated(unsafe) private static var childLinks = 0
    static func reset(firstStatus: Int) { lock.withLock { self.firstStatus = firstStatus; sends = []; redactions = 0; creationMode = false } }
    static func resetCreationFailure() { lock.withLock { creationMode = true; createdRooms = 0; childLinks = 0 } }
    static var createdRoomCount: Int { lock.withLock { createdRooms } }
    static var sendTransactions: [String] { lock.withLock { sends } }
    static var redactionCount: Int { lock.withLock { redactions } }
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        guard request.url?.host == "premium.invalid", let url = request.url else {
            client?.urlProtocol(self, didFailWithError: URLError(.unsupportedURL)); return
        }
        let path = url.path
        let creationReply: (Int, String)? = Self.lock.withLock {
            guard Self.creationMode else { return nil }
            if path.hasSuffix("/createRoom") {
                Self.createdRooms += 1
                return (200, "{\"room_id\":\"!created-\(Self.createdRooms):example.invalid\"}")
            }
            if path.contains("/state/") && path.contains("m.space.child") {
                Self.childLinks += 1
                return Self.childLinks == 1 ? (403, #"{"errcode":"M_FORBIDDEN","error":"link refused"}"#) : (200, "{}")
            }
            if request.httpMethod == "GET" && path.hasSuffix("/state") { return (200, "[]") }
            return (200, "{}")
        }
        if let (status, body) = creationReply {
            respond(url: url, status: status, body: body)
            return
        }
        let status = Self.lock.withLock {
            if path.contains("/send/") {
                Self.sends.append(url.lastPathComponent)
                return Self.sends.count == 1 ? Self.firstStatus : 200
            }
            if path.contains("/redact/") {
                Self.redactions += 1
                return Self.redactions == 1 ? Self.firstStatus : 200
            }
            return 503
        }
        if status == -1 { client?.urlProtocol(self, didFailWithError: URLError(.networkConnectionLost)); return }
        let body = status == 200 ? #"{"event_id":"$accepted"}"# : (status == 401 ? #"{"errcode":"M_UNKNOWN_TOKEN","error":"expired"}"# : #"{"errcode":"M_FORBIDDEN","error":"refused"}"#)
        respond(url: url, status: status, body: body)
    }
    private func respond(url: URL, status: Int, body: String) {
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: nil)!, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
