//
//  moodTests.swift
//  moodTests
//
//  Pure logic only: no network, no homeserver.
//

import Foundation
import SwiftUI
import Testing
@testable import mood

@MainActor
struct InviteParsingTests {

    @Test func matrixToLinkGivesTheAlias() {
        #expect(MatrixStore.roomReference(fromInvite: "https://matrix.to/#/#mood:matrix.org") == "#mood:matrix.org")
    }

    @Test func percentEncodedLinkIsDecoded() {
        #expect(MatrixStore.roomReference(fromInvite: "https://matrix.to/#/%23mood%3Amatrix.org?via=matrix.org") == "#mood:matrix.org")
    }

    @Test func rawRoomIdAndAliasAreAccepted() {
        #expect(MatrixStore.roomReference(fromInvite: "  !abc123:matrix.org ") == "!abc123:matrix.org")
        #expect(MatrixStore.roomReference(fromInvite: "#general:example.com") == "#general:example.com")
    }

    @Test func garbageIsRejected() {
        #expect(MatrixStore.roomReference(fromInvite: "https://mood.app/invite/abc") == nil)
        #expect(MatrixStore.roomReference(fromInvite: "#nohomeserver") == nil)
        #expect(MatrixStore.roomReference(fromInvite: "") == nil)
    }
}

@MainActor
struct UserIdTests {

    @Test func fullIdIsKept() {
        #expect(MatrixStore().matrixUserId(from: "@clara:matrix.org") == "@clara:matrix.org")
    }

    @Test func missingAtIsAdded() {
        #expect(MatrixStore().matrixUserId(from: "clara:matrix.org") == "@clara:matrix.org")
    }

    @Test func spacesAndEmptyAreRejected() {
        #expect(MatrixStore().matrixUserId(from: "clara dupont") == nil)
        #expect(MatrixStore().matrixUserId(from: "   ") == nil)
    }

    @Test func bareNameNeedsASignedInUser() {
        // No session: there is no homeserver to complete "clara" with.
        #expect(MatrixStore().matrixUserId(from: "clara") == nil)
    }

    @Test func presenceMapping() {
        #expect(MatrixStore.matrixPresence(for: .online) == "online")
        #expect(MatrixStore.matrixPresence(for: .idle) == "unavailable")
        #expect(MatrixStore.matrixPresence(for: .invisible) == "offline")
        #expect(MatrixStore.matrixPresence(for: .dnd) == "online")
    }
}

@MainActor
struct SyncCacheTests {

    @Test func snapshotRoundTrips() throws {
        let userId = "@test-\(UUID().uuidString):example.org"
        let cache = try #require(SyncCache(userId: userId))
        defer { cache.delete() }

        let room = MatrixStore.MatrixRoom(
            roomId: "!room:example.org", name: "général", topic: "Salut", isDirect: false,
            members: ["@a:example.org": "Alice"], memberAvatars: [:], unreadCount: 2, mentionCount: 1,
            isEncrypted: false, roomType: nil, spaceChildren: [], avatarUrl: nil, heroes: [],
            pinnedEventIds: ["$pinned"]
        )
        let event = try JSONDecoder().decode(MatrixEvent.self, from: Data("""
        {"type":"m.room.message","event_id":"$1","sender":"@a:example.org",
         "origin_server_ts":1700000000000,"content":{"msgtype":"m.text","body":"bonjour"}}
        """.utf8))

        let data = try JSONEncoder().encode(SyncSnapshot(
            rooms: [room], timelines: [room.roomId: [event]],
            directRoomIds: [], ignoredUserIds: ["@troll:example.org"]
        ))
        let decoded = try JSONDecoder().decode(SyncSnapshot.self, from: data)

        #expect(decoded.rooms.first?.name == "général")
        #expect(decoded.rooms.first?.pinnedEventIds == ["$pinned"])
        #expect(decoded.timelines[room.roomId]?.first?.content?["body"]?.stringValue == "bonjour")
        #expect(decoded.ignoredUserIds == ["@troll:example.org"])
    }

    @Test func cacheFileNameDoesNotLeakTheUserId() throws {
        // Two accounts get two different files, neither named after the account.
        let first = try #require(SyncCache(userId: "@alice:example.org"))
        let second = try #require(SyncCache(userId: "@bob:example.org"))
        let firstPath = String(describing: first)
        #expect(!firstPath.contains("alice"))
        #expect(String(describing: first) != String(describing: second))
    }
}

@MainActor
struct SupabaseAuthLogicTests {
    @Test func pkceUsesRFC7636S256Vector() {
        let pair = SupabaseAuthClient.pkcePair(verifier: "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk")
        #expect(pair.challenge == "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM")
    }

    @Test func authorizationURLContainsDiscordAndPKCEParameters() throws {
        let base = try #require(URL(string: "https://example.supabase.co"))
        let url = try #require(SupabaseAuthClient.authorizationURL(baseURL: base, challenge: "challenge"))
        let components = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))
        let items = Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).compactMap { item in item.value.map { (item.name, $0) } })
        #expect(components.path == "/auth/v1/authorize")
        #expect(items["provider"] == "discord")
        #expect(items["code_challenge_method"] == "s256")
        #expect(items["code_challenge"] == "challenge")
        #expect(items["scopes"] == "identify email guilds")
        #expect(items["redirect_to"] == "mood://auth-callback")
    }

    @Test func expiryThresholdIsSixtySeconds() {
        #expect(SupabaseAuthClient.shouldRefresh(expiresAt: 1_000, now: 941))
        #expect(!SupabaseAuthClient.shouldRefresh(expiresAt: 1_000, now: 939))
    }
}

@MainActor
struct AccountResponseTests {
    @Test func oauthSessionDecodesMixedMetadataAndProviderToken() throws {
        let data = Data("""
        {"access_token":"access","refresh_token":"refresh","expires_in":3600,
         "provider_token":"discord-token","user":{"id":"11111111-1111-1111-1111-111111111111",
         "email":"a@example.org","user_metadata":{"email_verified":true,"count":3,"name":"Alice","nested":{"value":null}}}}
        """.utf8)
        let session = try JSONDecoder().decode(SupabaseSession.self, from: data)
        #expect(session.providerToken == "discord-token")
        #expect(session.user.userMetadata?["email_verified"]?.boolValue == true)
        #expect(session.user.userMetadata?["name"]?.stringValue == "Alice")
    }

    @Test func optionalSupabaseConfigurationRejectsUnexpandedAndPlaceholderValues() {
        #expect(SupabaseAuthClient(info: [:]) == nil)
        #expect(SupabaseAuthClient(info: ["MoodSupabaseURL": "$(SUPABASE_URL)", "MoodSupabaseAnonKey": "key"]) == nil)
        #expect(SupabaseAuthClient(info: ["MoodSupabaseURL": "https://example.org", "MoodSupabaseAnonKey": "your-supabase-anon-key"]) == nil)
        #expect(SupabaseAuthClient(info: ["MoodSupabaseURL": "https://example.org", "MoodSupabaseAnonKey": "public-key"]) != nil)
    }

    @Test func randomPKCEVerifiersHaveRequiredLengthAndAlphabet() {
        let first = SupabaseAuthClient.pkcePair()
        let second = SupabaseAuthClient.pkcePair()
        #expect((43...128).contains(first.verifier.count))
        #expect(first.verifier.allSatisfy { $0.isLetter || $0.isNumber || "-_".contains($0) })
        #expect(first.verifier != second.verifier)
        #expect(first.challenge.count == 43)
    }

    @Test func refreshIncludesBoundaryAndExpiredTokens() {
        #expect(SupabaseAuthClient.shouldRefresh(expiresAt: 1_000, now: 940))
        #expect(SupabaseAuthClient.shouldRefresh(expiresAt: 1_000, now: 1_001))
    }

    @Test func discordIdentityAndProfileDecodeNullableFields() throws {
        let identity = try JSONDecoder().decode(DiscordIdentity.self, from: Data("""
        {"id":"123","username":"alice","global_name":null,"avatar":null,"banner":null,"accent_color":null}
        """.utf8))
        #expect(identity.displayName == "alice")
        #expect(identity.avatarURL == nil)
        let profile = try JSONDecoder().decode(AccountProfile.self, from: Data("""
        {"id":"11111111-1111-1111-1111-111111111111","matrix_user_id":"@alice:example.org","matrix_homeserver":"https://example.org","discord_id":null}
        """.utf8))
        #expect(profile.matrixUserId == "@alice:example.org")
        #expect(profile.discordId == nil)
    }
}

@MainActor
struct SearchQueryTests {

    private let clara = MoodUser(
        id: UUID(), username: "clara", displayName: "Clara Dupont", avatarEmoji: "🌸", roleColor: .purple,
        status: .online, bio: "", joinedDate: Date(), badges: [], activity: nil, matrixId: "@clara:example.org"
    )
    private let maxime = MoodUser(
        id: UUID(), username: "maxime", displayName: "Maxime", avatarEmoji: "⚡", roleColor: .orange,
        status: .online, bio: "", joinedDate: Date(), badges: [], activity: nil, matrixId: "@maxime:example.org"
    )
    private let general = Channel(id: UUID(), name: "Général Chat", type: .text, topic: "", unreadCount: 0, isE2E: false)
    private let design = Channel(id: UUID(), name: "design", type: .text, topic: "", unreadCount: 0, isE2E: false)

    private func parse(_ raw: String) -> SearchQueryParser.Result {
        SearchQueryParser.parse(raw, members: [clara, maxime], channels: [general, design])
    }

    @Test func plainWordsAreTheTerm() {
        let result = parse("  bonjour   le monde ")
        #expect(result.term == "bonjour le monde")
        #expect(!result.hasFilters)
    }

    @Test func senderAndChannelFiltersAreExtracted() {
        let result = parse("de:clara dans:design salut")
        #expect(result.term == "salut")
        #expect(result.senders == [clara])
        #expect(result.channels == [design])
    }

    @Test func filtersAcceptEnglishPrefixesAndSigils() {
        let result = parse("from:@maxime in:#design salut")
        #expect(result.senders == [maxime])
        #expect(result.channels == [design])
    }

    @Test func channelNamesWithSpacesAreDashed() {
        let result = parse("dans:général-chat salut")
        #expect(result.channels == [general])
        #expect(SearchQueryParser.token(for: general) == "dans:général-chat")
    }

    @Test func unknownFiltersStayInTheTerm() {
        let result = parse("de:inconnu salut")
        #expect(result.term == "de:inconnu salut")
        #expect(!result.hasFilters)
    }

    @Test func filterOnlyQueryHasNoTerm() {
        #expect(parse("de:clara").term.isEmpty)
    }

    @Test func replyFallbackIsStrippedFromNotificationText() throws {
        let event = try JSONDecoder().decode(MatrixEvent.self, from: Data("""
        {"type":"m.room.message","event_id":"$1","sender":"@a:example.org",
         "content":{"msgtype":"m.text","body":"> <@b:example.org> avant\\n\\nla vraie réponse"}}
        """.utf8))
        #expect(MatrixStore.plainBody(of: event) == "la vraie réponse")
    }

    @Test func searchResponseKeepsTheRoomIdOfEachResult() throws {
        let response = try JSONDecoder().decode(MatrixSearchResponse.self, from: Data("""
        {"search_categories":{"room_events":{"count":1,"next_batch":"abc","highlights":["salut"],
         "results":[{"rank":0.5,"result":{"type":"m.room.message","event_id":"$1","room_id":"!r:example.org",
         "sender":"@a:example.org","content":{"msgtype":"m.text","body":"salut"}}}]}}}
        """.utf8))
        let events = try #require(response.searchCategories.roomEvents)
        #expect(events.nextBatch == "abc")
        #expect(events.results?.first?.roomId == "!r:example.org")
        #expect(events.results?.first?.result.eventId == "$1")
    }
}

// MARK: - Notifications

@MainActor
struct NotificationDecisionTests {
    private let me = "@me:mood.local"
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func candidate(
        id: String = "$1",
        room: String = "!room:mood.local",
        sender: String = "@clara:mood.local",
        direct: Bool = true,
        age: TimeInterval = 5
    ) -> NotificationCandidate {
        NotificationCandidate(
            eventId: id, roomId: room, senderId: sender, senderName: "Clara", roomName: "général",
            isDirect: direct, body: "Salut", timestamp: now.addingTimeInterval(-age)
        )
    }

    private func context(
        enabled: Bool = true,
        ignored: Set<String> = [],
        muted: Set<String> = [],
        open: String? = nil,
        active: Bool = false,
        seen: Set<String> = []
    ) -> NotificationContext {
        var preferences = AccountPreferences()
        preferences.notificationsEnabled = enabled
        return NotificationContext(
            myUserId: me, preferences: preferences, ignoredUserIds: ignored, mutedRoomIds: muted,
            openRoomId: open, isAppActive: active, seenEventIds: seen, now: now
        )
    }

    @Test func aNewMessageFromSomeoneElseNotifies() {
        #expect(NotificationDecision.shouldNotify(candidate(), in: context()))
    }

    @Test func nothingNotifiesWhileNotificationsAreOff() {
        #expect(!NotificationDecision.shouldNotify(candidate(), in: context(enabled: false)))
    }

    @Test func myOwnMessagesNeverNotify() {
        #expect(!NotificationDecision.shouldNotify(candidate(sender: me), in: context()))
    }

    @Test func blockedUsersAreSilenced() {
        let blocked = candidate(sender: "@troll:mood.local")
        #expect(!NotificationDecision.shouldNotify(blocked, in: context(ignored: ["@troll:mood.local"])))
    }

    @Test func mutedRoomsAreSilenced() {
        #expect(!NotificationDecision.shouldNotify(candidate(), in: context(muted: ["!room:mood.local"])))
        #expect(NotificationDecision.shouldNotify(candidate(), in: context(muted: ["!other:mood.local"])))
    }

    @Test func theOpenRoomIsSilentOnlyWhileTheAppIsInFront() {
        let open = "!room:mood.local"
        #expect(!NotificationDecision.shouldNotify(candidate(), in: context(open: open, active: true)))
        // In the background the user is not looking at it.
        #expect(NotificationDecision.shouldNotify(candidate(), in: context(open: open, active: false)))
        // In front, but on another room.
        #expect(NotificationDecision.shouldNotify(candidate(), in: context(open: "!other:mood.local", active: true)))
    }

    @Test func eventsAlreadySeenDoNotNotifyAgain() {
        #expect(!NotificationDecision.shouldNotify(candidate(id: "$1"), in: context(seen: ["$1"])))
    }

    @Test func oldMessagesAreCatchUpNotNews() {
        let stale = candidate(age: NotificationContext.maxAge + 60)
        #expect(!NotificationDecision.shouldNotify(stale, in: context()))
        let recent = candidate(age: NotificationContext.maxAge - 60)
        #expect(NotificationDecision.shouldNotify(recent, in: context()))
    }

    @Test func aBurstKeepsTheNewestOnesOldestFirst() {
        let burst = (0..<9).map { candidate(id: "$\($0)", age: TimeInterval(100 - $0 * 10)) }
        let selected = NotificationDecision.select(burst.shuffled(), in: context())
        #expect(selected.count == NotificationContext.maxPerSync)
        #expect(selected.map(\.eventId) == ["$4", "$5", "$6", "$7", "$8"])
    }

    @Test func selectionDropsWhatIsNotEligible() {
        let list = [candidate(id: "$1"), candidate(id: "$2", sender: me), candidate(id: "$3", room: "!muted:mood.local")]
        let selected = NotificationDecision.select(list, in: context(muted: ["!muted:mood.local"]))
        #expect(selected.map(\.eventId) == ["$1"])
    }

    @Test func titleIsTheAuthorInADMAndAddsTheChannelInAServer() {
        #expect(candidate(direct: true).title == "Clara")
        #expect(candidate(direct: false).title == "Clara · #général")
    }

    @Test func longBodiesAreShortened() {
        let long = NotificationCandidate(
            eventId: "$1", roomId: "!r:x", senderId: "@a:x", senderName: "A", roomName: "", isDirect: true,
            body: String(repeating: "a", count: 500), timestamp: now
        )
        #expect(long.preview.count <= NotificationCandidate.previewLimit + 1)
        #expect(long.preview.hasSuffix("…"))
    }

    @Test func mediaGetsAShortLabelAndEditsNeverNotify() {
        #expect(NotificationCandidate.previewText(eventType: "m.room.message", msgtype: "m.text", body: "yo", isEdit: false) == "yo")
        #expect(NotificationCandidate.previewText(eventType: "m.room.message", msgtype: "m.image", body: "IMG_1.png", isEdit: false) == "Image")
        #expect(NotificationCandidate.previewText(eventType: "m.room.message", msgtype: "m.file", body: "cv.pdf", isEdit: false) == "Fichier : cv.pdf")
        #expect(NotificationCandidate.previewText(eventType: "m.room.message", msgtype: "m.text", body: "* yo", isEdit: true) == nil)
        #expect(NotificationCandidate.previewText(eventType: "m.reaction", msgtype: nil, body: nil, isEdit: false) == nil)
    }

    @Test func recentEventSetDedupesAndStaysBounded() {
        var seen = RecentEventSet(capacity: 8)
        let firstInsert = seen.insert("$a")
        let secondInsert = seen.insert("$a")
        #expect(firstInsert)
        #expect(!secondInsert)
        for index in 0..<40 { seen.insert("$e\(index)") }
        #expect(seen.ids.count <= 8)
        #expect(seen.contains("$e39"))
        #expect(!seen.contains("$a"))
        seen.removeAll()
        #expect(seen.ids.isEmpty)
    }
}

@MainActor
struct BadgeTests {

    @Test func dmsCountEveryUnreadMessageChannelsOnlyMentions() {
        let rooms = [
            BadgeRoom(isDirect: true, unreadCount: 3, mentionCount: 0),
            BadgeRoom(isDirect: false, unreadCount: 12, mentionCount: 2),
            BadgeRoom(isDirect: false, unreadCount: 7, mentionCount: 0),
        ]
        #expect(BadgeCalculator.count(rooms) == 5)
    }

    @Test func aDMNeverCountsLessThanItsMentions() {
        #expect(BadgeCalculator.count([BadgeRoom(isDirect: true, unreadCount: 0, mentionCount: 2)]) == 2)
    }

    @Test func mutedRoomsAndSpacesDoNotCount() {
        let rooms = [
            BadgeRoom(isDirect: true, unreadCount: 4, mentionCount: 0, isMuted: true),
            BadgeRoom(isDirect: false, isSpace: true, unreadCount: 9, mentionCount: 9),
            BadgeRoom(isDirect: false, unreadCount: 1, mentionCount: 1),
        ]
        #expect(BadgeCalculator.count(rooms) == 1)
    }

    @Test func noRoomsMeansNoBadge() {
        #expect(BadgeCalculator.count([]) == 0)
        #expect(MatrixStore().appBadgeCount == 0)
    }
}

@MainActor
struct PushRuleTests {

    private func json(_ text: String) throws -> Any {
        try JSONSerialization.jsonObject(with: Data(text.utf8))
    }

    @Test func roomRulePathEscapesTheRoomIdOnce() {
        #expect(PushRules.roomRulePath(roomId: "!abc:mood.local") == "/_matrix/client/v3/pushrules/global/room/!abc:mood.local")
        #expect(PushRules.roomRulePath(roomId: "!a/b#c:mood.local") == "/_matrix/client/v3/pushrules/global/room/!a%2Fb%23c:mood.local")
        #expect(PushRules.overrideRulePath(roomId: "!abc:mood.local") == "/_matrix/client/v3/pushrules/global/override/!abc:mood.local")
        #expect(PushRules.allRulesPath == "/_matrix/client/v3/pushrules/")
    }

    @Test func aRoomRuleWithNoActionsMutesTheRoom() throws {
        let rules = try json("""
        {"global":{"room":[
          {"rule_id":"!muted:mood.local","enabled":true,"default":false,"actions":[]},
          {"rule_id":"!loud:mood.local","enabled":true,"default":false,"actions":["notify"]},
          {"rule_id":"!off:mood.local","enabled":false,"default":false,"actions":[]}
        ]}}
        """)
        #expect(PushRules.mutedRoomIds(in: rules) == ["!muted:mood.local"])
    }

    @Test func theLegacyDontNotifyActionAlsoMutes() throws {
        let rules = try json(#"{"global":{"room":[{"rule_id":"!old:mood.local","actions":["dont_notify"]}]}}"#)
        #expect(PushRules.mutedRoomIds(in: rules) == ["!old:mood.local"])
    }

    @Test func anElementStyleOverrideRuleMutesToo() throws {
        let rules = try json("""
        {"global":{"override":[
          {"rule_id":"!el:mood.local","enabled":true,"actions":[],
           "conditions":[{"kind":"event_match","key":"room_id","pattern":"!el:mood.local"}]},
          {"rule_id":".m.rule.master","enabled":false,"actions":[],"conditions":[]},
          {"rule_id":"!other:mood.local","enabled":true,"actions":[],
           "conditions":[{"kind":"event_match","key":"room_id","pattern":"!different:mood.local"}]}
        ]}}
        """)
        #expect(PushRules.mutedRoomIds(in: rules) == ["!el:mood.local"])
    }

    @Test func missingOrBrokenRulesMuteNothing() throws {
        #expect(PushRules.mutedRoomIds(in: nil).isEmpty)
        #expect(PushRules.mutedRoomIds(in: try json("[]")).isEmpty)
        #expect(PushRules.mutedRoomIds(in: try json(#"{"global":{}}"#)).isEmpty)
        #expect(PushRules.mutedRoomIds(in: try json(#"{"global":{"room":[{"rule_id":"!x:y"}]}}"#)).isEmpty)
    }

    @Test func syncAccountDataCarriesTheSameRules() throws {
        let response = try JSONDecoder().decode(MatrixSyncResponse.self, from: Data("""
        {"next_batch":"s1","account_data":{"events":[
          {"type":"m.push_rules","content":{"global":{"room":[{"rule_id":"!quiet:mood.local","enabled":true,"actions":[]}]}}}
        ]}}
        """.utf8))
        let event = try #require(response.accountData?.events?.first)
        let rules = event.content?.mapValues(\.jsonObject)
        #expect(PushRules.mutedRoomIds(in: rules) == ["!quiet:mood.local"])
    }

    @Test func aStoreWithoutASessionTalksToNoOneWhenMuting() async {
        let store = MatrixStore()
        await store.setMuted(true, roomId: "!room:mood.local")
        #expect(!store.isMuted(roomId: "!room:mood.local"))
    }
}

@MainActor
struct AccountPreferencesTests {

    private func freshDefaults() -> UserDefaults {
        UserDefaults(suiteName: "mood.tests.\(UUID().uuidString)")!
    }

    @Test func defaultsAskForNothingAndShareNothingExtra() {
        let preferences = AccountPreferences()
        #expect(!preferences.notificationsEnabled)
        #expect(preferences.soundsEnabled)
        #expect(preferences.badgeEnabled)
        #expect(preferences.sendsReadReceipts)
        #expect(preferences.sendsTypingIndicator)
    }

    @Test func preferencesAreKeptPerAccount() {
        let defaults = freshDefaults()
        var clara = AccountPreferences()
        clara.notificationsEnabled = true
        clara.sendsReadReceipts = false
        clara.save(userId: "@clara:mood.local", defaults: defaults)

        #expect(AccountPreferences.load(userId: "@clara:mood.local", defaults: defaults) == clara)
        #expect(AccountPreferences.load(userId: "@paul:mood.local", defaults: defaults) == AccountPreferences())
    }

    @Test func storedPreferencesMissingNewKeysFallBackToDefaults() throws {
        let defaults = freshDefaults()
        defaults.set(Data(#"{"soundsEnabled":false}"#.utf8), forKey: AccountPreferences.storageKey(for: "@a:mood.local"))
        let loaded = AccountPreferences.load(userId: "@a:mood.local", defaults: defaults)
        #expect(!loaded.soundsEnabled)
        #expect(loaded.sendsTypingIndicator)
        #expect(!loaded.notificationsEnabled)
    }

    @Test func aStoreWithoutASessionKeepsChoicesInMemoryOnly() {
        let store = MatrixStore()
        store.updatePreferences { $0.sendsTypingIndicator = false }
        #expect(!store.preferences.sendsTypingIndicator)
    }
}

@MainActor
struct DeviceListTests {

    private func device(_ id: String, name: String? = nil, seen: Int64? = nil) -> MatrixDevice {
        MatrixDevice(deviceId: id, displayName: name, lastSeenIp: nil, lastSeenTs: seen)
    }

    @Test func thisDeviceComesFirstThenTheMostRecentlyActive() {
        let ordered = DeviceList.ordered(
            [device("OLD", seen: 100), device("NEW", seen: 900), device("ME", seen: 10), device("NEVER")],
            currentDeviceId: "ME"
        )
        #expect(ordered.map(\.deviceId) == ["ME", "NEW", "OLD", "NEVER"])
    }

    @Test func devicesDecodeFromTheServerResponse() throws {
        let response = try JSONDecoder().decode(MatrixDevicesResponse.self, from: Data("""
        {"devices":[{"device_id":"MOODMAC1","display_name":"Mood · Mac","last_seen_ip":"203.0.113.4","last_seen_ts":1800000000000},
                    {"device_id":"MOODPHONE"}]}
        """.utf8))
        let devices = try #require(response.devices)
        #expect(devices.count == 2)
        #expect(devices[0].title == "Mood · Mac")
        #expect(devices[0].lastSeenDate == Date(timeIntervalSince1970: 1_800_000_000))
        #expect(devices[1].title == "MOODPHONE")
        #expect(devices[1].lastSeenDate == nil)
    }
}

// MARK: - Messaging pipeline (track G)

@MainActor
struct MessageFormattingTests {

    private let clara = MentionCandidate(userId: "@clara:mood.local", displayName: "Clara Dupont")
    private let max = MentionCandidate(userId: "@max:mood.local", displayName: "Max")
    private let me = MentionCandidate(userId: "@me:mood.local", displayName: "Moi")

    @Test func plainTextHasNoFormattedBody() {
        let result = MessageFormatter.format("salut tout le monde")
        #expect(result.body == "salut tout le monde")
        #expect(result.formattedBody == nil)
        #expect(result.mentionedUserIds.isEmpty)
        #expect(!result.mentionsRoom)
    }

    @Test func inlineMarkdownBecomesHTML() {
        #expect(MessageFormatter.html(fromMarkdown: "**gras** *italique* ~~barré~~ `code`")
                == "<strong>gras</strong> <em>italique</em> <del>barré</del> <code>code</code>")
        #expect(MessageFormatter.html(fromMarkdown: "_doux_") == "<em>doux</em>")
        #expect(MessageFormatter.html(fromMarkdown: "__souligné__ ||secret||")
                == "<u>souligné</u> <span data-mx-spoiler>secret</span>")
    }

    @Test func codeBlockKeepsLanguageAndEscapes() {
        #expect(MessageFormatter.html(fromMarkdown: "```swift\nlet a = 1 < 2\n```")
                == "<pre><code class=\"language-swift\">let a = 1 &lt; 2</code></pre>")
        // Markdown inside a code block stays as typed.
        #expect(MessageFormatter.html(fromMarkdown: "```\n**pas gras**\n```") == "<pre><code>**pas gras**</code></pre>")
    }

    @Test func quotesAndLinks() {
        #expect(MessageFormatter.html(fromMarkdown: "> cité\nréponse") == "<blockquote>cité</blockquote>réponse")
        #expect(MessageFormatter.html(fromMarkdown: "[Mood](https://mood.app/a?b=1&c=2)")
                == "<a href=\"https://mood.app/a?b=1&amp;c=2\">Mood</a>")
        #expect(MessageFormatter.html(fromMarkdown: "va sur https://example.org/page.")
                == "va sur <a href=\"https://example.org/page\">https://example.org/page</a>.")
        // Only web links: no javascript: URL ever becomes a link.
        #expect(MessageFormatter.html(fromMarkdown: "[x](javascript:alert(1))") == nil)
    }

    @Test func htmlIsEscaped() {
        #expect(MessageFormatter.format("<script>alert('x')</script> **ok**").formattedBody
                == "&lt;script&gt;alert(&#39;x&#39;)&lt;/script&gt; <strong>ok</strong>")
        #expect(MessageFormatter.html(fromMarkdown: "a < b & c") == nil) // escaping alone needs no HTML
    }

    @Test func underscoresInsideWordsAndSpacedStarsStayLiteral() {
        #expect(MessageFormatter.html(fromMarkdown: "snake_case_name") == nil)
        #expect(MessageFormatter.html(fromMarkdown: "2 * 3 * 4") == nil)
        #expect(MessageFormatter.html(fromMarkdown: "\\*pas italique\\*") == nil)
    }

    @Test func mentionsBecomePillsAndUserIds() {
        let result = MessageFormatter.format("salut @Clara Dupont et @max !", members: [clara, max, me], selfUserId: me.userId)
        #expect(result.mentionedUserIds == ["@clara:mood.local", "@max:mood.local"])
        #expect(result.formattedBody == "salut <a href=\"https://matrix.to/#/@clara:mood.local\">Clara Dupont</a> et "
                + "<a href=\"https://matrix.to/#/@max:mood.local\">Max</a> !")
    }

    @Test func selfAndCodeMentionsDoNotPing() {
        let result = MessageFormatter.format("@Moi regarde `@max`", members: [max, me], selfUserId: me.userId)
        #expect(result.mentionedUserIds.isEmpty)
        #expect(MessageFormatter.format("@inconnu salut", members: [max]).mentionedUserIds.isEmpty)
    }

    @Test func roomMentionAndEmailAddresses() {
        let everyone = MessageFormatter.format("@everyone réunion")
        #expect(everyone.mentionsRoom)
        #expect(everyone.mentionedUserIds.isEmpty)
        #expect(MessageFormatter.format("écris à max@mood.local", members: [max]).mentionedUserIds.isEmpty)
    }

    @Test func textContentAlwaysCarriesMentions() {
        let plain = MatrixMessageContent.text(body: "salut", formattedBody: nil, mentionUserIds: [], mentionsRoom: false)
        #expect(plain["format"] == nil)
        #expect((plain["m.mentions"] as? [String: Any])?["user_ids"] as? [String] == [])

        let reply = MatrixMessageContent.text(body: "ok", formattedBody: "<strong>ok</strong>", mentionUserIds: ["@a:x"],
                                              mentionsRoom: true, replyToEventId: "$e")
        #expect(reply["format"] as? String == "org.matrix.custom.html")
        #expect(reply["formatted_body"] as? String == "<strong>ok</strong>")
        #expect(((reply["m.relates_to"] as? [String: Any])?["m.in_reply_to"] as? [String: Any])?["event_id"] as? String == "$e")
        #expect((reply["m.mentions"] as? [String: Any])?["room"] as? Bool == true)
    }

    @Test func editOnlyPingsNewlyMentionedPeople() {
        let content = MatrixMessageContent.edit(eventId: "$1", body: "salut @b", formattedBody: nil,
                                                mentionUserIds: ["@a:x", "@b:x"], mentionsRoom: false,
                                                previousMentionUserIds: ["@a:x"])
        #expect(content["body"] as? String == "* salut @b")
        #expect((content["m.mentions"] as? [String: Any])?["user_ids"] as? [String] == ["@b:x"])
        let newContent = content["m.new_content"] as? [String: Any]
        #expect(newContent?["body"] as? String == "salut @b")
        #expect((newContent?["m.mentions"] as? [String: Any])?["user_ids"] as? [String] == ["@a:x", "@b:x"])
        #expect((content["m.relates_to"] as? [String: Any])?["rel_type"] as? String == "m.replace")
    }
}

@MainActor
struct MessageLengthTests {

    @Test func counterAppearsPast3500() {
        #expect(MessageLengthPolicy.remaining(for: String(repeating: "a", count: 3500)) == nil)
        #expect(MessageLengthPolicy.remaining(for: String(repeating: "a", count: 3501)) == 499)
        #expect(MessageLengthPolicy.remaining(for: String(repeating: "a", count: 4010)) == -10)
    }

    @Test func limitIsFourThousandCharacters() {
        #expect(!MessageLengthPolicy.isTooLong(String(repeating: "é", count: 4000)))
        #expect(MessageLengthPolicy.isTooLong(String(repeating: "é", count: 4001)))
        // Characters, not bytes: an emoji with a skin tone counts once.
        #expect(!MessageLengthPolicy.isTooLong(String(repeating: "👍🏽", count: 4000)))
    }

    @Test func storeRefusesTooLongText() {
        let store = MatrixStore()
        #expect(!store.validateOutgoingText(String(repeating: "a", count: 4001)))
        #expect(store.errorMessage != nil)
        #expect(store.validateOutgoingText("ok"))
    }
}

@MainActor
struct OutboxTests {

    private func message(_ txnId: String, room: String, at seconds: TimeInterval) -> OutgoingMessage {
        OutgoingMessage(txnId: txnId, roomId: room, body: txnId, replyToEventId: nil, threadRootEventId: nil,
                        createdAt: Date(timeIntervalSince1970: seconds))
    }

    private func temporaryOutboxFile() throws -> URL {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("mood-outbox-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder.appendingPathComponent("outbox.json")
    }

    @Test func eachRoomKeepsItsOwnOrder() {
        var queue = OutboxQueue()
        queue.enqueue(message("a1", room: "!a", at: 1))
        queue.enqueue(message("b1", room: "!b", at: 2))
        queue.enqueue(message("a2", room: "!a", at: 3))
        #expect(queue.roomIds == ["!a", "!b"])
        #expect(queue.next(in: "!a")?.txnId == "a1")
        #expect(queue.next(in: "!b")?.txnId == "b1")
        queue.remove(txnId: "a1")
        #expect(queue.next(in: "!a")?.txnId == "a2")
        let queuedTwice = queue.enqueue(message("a2", room: "!a", at: 4))
        #expect(!queuedTwice) // a txnId is never queued twice
        #expect(queue.pending(in: "!a").count == 1)
    }

    @Test func updateKeepsThePosition() {
        var queue = OutboxQueue(messages: [message("a1", room: "!a", at: 1), message("a2", room: "!a", at: 2)])
        var first = message("a1", room: "!a", at: 1)
        first.formattedBody = "<em>a1</em>"
        queue.update(first)
        #expect(queue.next(in: "!a")?.formattedBody == "<em>a1</em>")
        #expect(queue.messages.map(\.txnId) == ["a1", "a2"])
    }

    @Test func attachmentRoundTripsThroughJSON() throws {
        var outgoing = message("t1", room: "!a", at: 10)
        outgoing.mentionUserIds = ["@clara:mood.local"]
        outgoing.attachment = OutgoingAttachment(
            kind: .image, fileName: "photo.jpg", localFile: "t1.jpg", mimeType: "image/jpeg", size: 1234,
            width: 2560, height: 1920, thumbnailFile: "t1-thumb.jpg", thumbnailMimeType: "image/jpeg",
            thumbnailSize: 99, thumbnailWidth: 800, thumbnailHeight: 600, contentURI: "mxc://mood.local/abc"
        )
        let data = try JSONEncoder().encode(OutboxQueue(messages: [outgoing]))
        let decoded = try JSONDecoder().decode(OutboxQueue.self, from: data)
        #expect(decoded.messages == [outgoing])
    }

    @Test func legacyPayloadWithoutNewFieldsStillDecodes() throws {
        let legacy = Data(#"[{"txnId":"old","roomId":"!a","body":"hors ligne","createdAt":0}]"#.utf8)
        let decoded = try JSONDecoder().decode([OutgoingMessage].self, from: legacy)
        #expect(decoded.first?.body == "hors ligne")
        #expect(decoded.first?.attachment == nil)
        #expect(decoded.first?.formattedBody == nil)
    }

    @Test func userDefaultsOutboxIsMigratedToTheFile() throws {
        let suiteName = "mood.tests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let legacy = [message("second", room: "!a", at: 20), message("first", room: "!a", at: 10)]
        defaults.set(try JSONEncoder().encode(legacy), forKey: MessageOutbox.legacyDefaultsKey)
        let file = try temporaryOutboxFile()
        defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }

        let outbox = MessageOutbox(fileURL: file, defaults: defaults)
        #expect(outbox.pending.map(\.txnId) == ["first", "second"])
        #expect(defaults.data(forKey: MessageOutbox.legacyDefaultsKey) == nil)
        #expect(FileManager.default.fileExists(atPath: file.path))

        // The next launch reads the file.
        let reopened = MessageOutbox(fileURL: file, defaults: defaults)
        #expect(reopened.pending.map(\.txnId) == ["first", "second"])
    }

    @Test func removingAMessageDeletesItsFilesUnlessKeptForRetry() throws {
        let suiteName = "mood.tests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let file = try temporaryOutboxFile()
        defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }

        let outbox = MessageOutbox(fileURL: file, defaults: defaults)
        let local = try #require(outbox.localURL(for: "t1.bin"))
        try Data("x".utf8).write(to: local)
        var queued = message("t1", room: "!a", at: 1)
        queued.attachment = OutgoingAttachment(kind: .file, fileName: "a.bin", localFile: "t1.bin",
                                               mimeType: "application/octet-stream", size: 1)
        outbox.enqueue(queued)
        outbox.remove(txnId: "t1", deleteFiles: false)
        #expect(FileManager.default.fileExists(atPath: local.path))
        outbox.enqueue(queued)
        outbox.remove(txnId: "t1")
        #expect(!FileManager.default.fileExists(atPath: local.path))
    }

    @Test func attachmentInfoCarriesSizeAndThumbnail() {
        let attachment = OutgoingAttachment(
            kind: .image, fileName: "p.jpg", localFile: "x.jpg", mimeType: "image/jpeg", size: 500,
            width: 2560, height: 1440, thumbnailFile: "x-thumb.jpg", thumbnailMimeType: "image/jpeg",
            thumbnailSize: 50, thumbnailWidth: 800, thumbnailHeight: 450,
            contentURI: "mxc://s/a", thumbnailContentURI: "mxc://s/t"
        )
        let info = attachment.info()
        #expect(info["w"] as? Int == 2560)
        #expect(info["h"] as? Int == 1440)
        #expect(info["size"] as? Int == 500)
        #expect(info["mimetype"] as? String == "image/jpeg")
        #expect(info["thumbnail_url"] as? String == "mxc://s/t")
        #expect((info["thumbnail_info"] as? [String: Any])?["w"] as? Int == 800)
        #expect(attachment.kind.msgtype == "m.image")
        #expect(OutgoingAttachment.Kind.video.msgtype == "m.video")
    }

    @Test func unreachableServerKeepsMessagesQueued() {
        #expect(MatrixClient.isTransient(MatrixClient.MatrixError.networkError(URLError(.cannotConnectToHost))))
        #expect(MatrixClient.isTransient(MatrixClient.MatrixError.httpError(statusCode: 502, errcode: nil, message: "", retryAfterMs: nil)))
        #expect(!MatrixClient.isTransient(MatrixClient.MatrixError.httpError(statusCode: 403, errcode: "M_FORBIDDEN", message: "", retryAfterMs: nil)))
        #expect(!MatrixClient.isTransient(MatrixClient.MatrixError.networkError(URLError(.badURL))))
    }

    @Test func retryAfterComesFromTheBodyThenTheHeader() {
        let body = Data(#"{"errcode":"M_LIMIT_EXCEEDED","retry_after_ms":1500}"#.utf8)
        #expect(MatrixRateLimit.retryAfter(statusCode: 429, headers: [:], body: body) == 1.5)
        #expect(MatrixRateLimit.retryAfter(statusCode: 429, headers: ["retry-after": "3"], body: Data()) == 3)
        #expect(MatrixRateLimit.retryAfter(statusCode: 429, headers: [:], body: nil) == nil)
        #expect(MatrixRateLimit.retryAfter(statusCode: 500, headers: ["Retry-After": "3"], body: body) == nil)
        #expect(MatrixRateLimit.errcode(in: body) == "M_LIMIT_EXCEEDED")
    }
}

@MainActor
struct MediaURLTests {

    private let homeserver = URL(string: "https://mac-studio.example.ts.net:8443")!

    @Test func downloadUsesTheAuthenticatedRoute() {
        #expect(MatrixMediaEndpoint.downloadURL(for: "mxc://mood.local/AbC_12-x", homeserver: homeserver)?.absoluteString
                == "https://mac-studio.example.ts.net:8443/_matrix/client/v1/media/download/mood.local/AbC_12-x")
        let client = MatrixClient(homeserver: "https://mood.example")
        #expect(client.resolveMediaURL("mxc://mood.local/abc")?.path == "/_matrix/client/v1/media/download/mood.local/abc")
    }

    @Test func thumbnailKeepsItsParameters() {
        #expect(MatrixMediaEndpoint.thumbnailURL(for: "mxc://mood.local/abc", homeserver: homeserver, width: 96, height: 96)?.absoluteString
                == "https://mac-studio.example.ts.net:8443/_matrix/client/v1/media/thumbnail/mood.local/abc?width=96&height=96&method=crop")
        #expect(MatrixMediaEndpoint.thumbnailURL(for: "mxc://mood.local/abc", homeserver: homeserver, width: 800, height: 600,
                                                 method: "scale")?.query == "width=800&height=600&method=scale")
    }

    @Test func legacyFallbackMapsToV3() throws {
        let v1 = try #require(URL(string: "https://hs.example/_matrix/client/v1/media/thumbnail/s/m?width=1&height=1&method=crop"))
        #expect(MatrixMediaEndpoint.legacyEquivalent(of: v1)?.absoluteString
                == "https://hs.example/_matrix/media/v3/thumbnail/s/m?width=1&height=1&method=crop")
        #expect(MatrixMediaEndpoint.legacyEquivalent(of: try #require(URL(string: "https://hs.example/other"))) == nil)
        #expect(MatrixMediaEndpoint.downloadURL(for: "mxc://s/m", homeserver: try #require(URL(string: "https://hs.example")),
                                                legacy: true)?.path == "/_matrix/media/v3/download/s/m")
    }

    @Test func fallbackOnlyWhenTheRouteIsUnknown() {
        #expect(MatrixMediaEndpoint.shouldFallBackToLegacy(statusCode: 404, errcode: "M_UNRECOGNIZED"))
        #expect(MatrixMediaEndpoint.shouldFallBackToLegacy(statusCode: 400, errcode: "M_UNRECOGNIZED"))
        #expect(MatrixMediaEndpoint.shouldFallBackToLegacy(statusCode: 405, errcode: nil))
        #expect(MatrixMediaEndpoint.shouldFallBackToLegacy(statusCode: 404, errcode: nil))
        #expect(!MatrixMediaEndpoint.shouldFallBackToLegacy(statusCode: 404, errcode: "M_NOT_FOUND"))
        #expect(!MatrixMediaEndpoint.shouldFallBackToLegacy(statusCode: 401, errcode: "M_MISSING_TOKEN"))
    }

    @Test func tokenOnlyGoesToTheHomeserver() throws {
        #expect(MatrixMediaEndpoint.shouldAuthorize(try #require(URL(string: "https://mac-studio.example.ts.net:8443/_matrix/client/v1/media/download/a/b")), homeserver: homeserver))
        #expect(!MatrixMediaEndpoint.shouldAuthorize(try #require(URL(string: "https://mac-studio.example.ts.net/x")), homeserver: homeserver))
        #expect(!MatrixMediaEndpoint.shouldAuthorize(try #require(URL(string: "https://cdn.example/x")), homeserver: homeserver))
        #expect(!MatrixMediaEndpoint.shouldAuthorize(try #require(URL(string: "http://mac-studio.example.ts.net:8443/x")), homeserver: homeserver))
        #expect(!MatrixMediaEndpoint.shouldAuthorize(homeserver, homeserver: nil))
    }

    @Test func malformedContentURIsAreRejected() {
        #expect(MatrixContentURI("mxc://mood.local/abc") == MatrixContentURI("mxc://mood.local/abc"))
        #expect(MatrixContentURI("mxc://mood.local/abc")?.mediaId == "abc")
        #expect(MatrixContentURI("mxc://mood.local/../secret") == nil)
        #expect(MatrixContentURI("mxc://mood.local/a?b") == nil)
        #expect(MatrixContentURI("https://mood.local/abc") == nil)
        #expect(MatrixContentURI("mxc://mood.local") == nil)
        #expect(MatrixContentURI("mxc:///abc") == nil)
    }

    @Test func downloadedFileNamesAreSafe() {
        #expect(MediaLoader.safeFileName("rapport.pdf") == "rapport.pdf")
        #expect(!MediaLoader.safeFileName("../../etc/passwd").contains("/"))
        #expect(MediaLoader.safeFileName("  ") == "fichier")
    }

    @Test func diskCacheEvictsLeastRecentlyUsedFirst() {
        let megabyte: Int64 = 1024 * 1024
        let entries = [
            MediaDiskCachePolicy.Entry(name: "old", size: 200 * megabyte, lastAccess: Date(timeIntervalSince1970: 1)),
            MediaDiskCachePolicy.Entry(name: "recent", size: 200 * megabyte, lastAccess: Date(timeIntervalSince1970: 3)),
            MediaDiskCachePolicy.Entry(name: "middle", size: 150 * megabyte, lastAccess: Date(timeIntervalSince1970: 2)),
        ]
        // 550 Mo > 500: drop the oldest until under 450.
        #expect(MediaDiskCachePolicy.evictions(entries) == ["old"])
        #expect(MediaDiskCachePolicy.evictions(Array(entries.prefix(2))).isEmpty)
    }

    @Test func uploadLimitIs25Megabytes() {
        #expect(MediaUploadLimits.maxBytes == 26_214_400)
        #expect(MediaUploadLimits.tooLargeMessage(size: 30 * 1024 * 1024).contains("25"))
    }
}

@MainActor
struct ImageResizeTests {

    @Test func largeJPEGIsScaledTo2560() {
        let plan = ImageUploadPlan.make(typeIdentifier: "public.jpeg", width: 4032, height: 3024)
        #expect(plan.output == .jpeg)
        #expect(plan.width == 2560 && plan.height == 1920)
    }

    @Test func heicIsAlwaysConvertedButNeverUpscaled() {
        let plan = ImageUploadPlan.make(typeIdentifier: "public.heic", width: 1200, height: 900)
        #expect(plan.output == .jpeg)
        #expect(plan.width == 1200 && plan.height == 900)
    }

    @Test func smallWebImagesAreKept() {
        #expect(ImageUploadPlan.make(typeIdentifier: "public.jpeg", width: 1920, height: 1080).output == .original)
        #expect(ImageUploadPlan.make(typeIdentifier: "public.png", width: 2560, height: 100, hasAlpha: true).output == .original)
    }

    @Test func transparentImagesStayPNG() {
        let plan = ImageUploadPlan.make(typeIdentifier: "public.png", width: 5120, height: 2560, hasAlpha: true)
        #expect(plan.output == .png)
        #expect(plan.width == 2560 && plan.height == 1280)
    }

    @Test func animationsAreNeverReencoded() {
        #expect(ImageUploadPlan.make(typeIdentifier: "com.compuserve.gif", width: 4000, height: 4000, isAnimated: true).output == .original)
    }

    @Test func exifRotationSwapsTheSize() {
        let plan = ImageUploadPlan.make(typeIdentifier: "public.heic", width: 4032, height: 3024, orientation: 6)
        #expect(plan.width == 1920 && plan.height == 2560)
    }

    @Test func thumbnailFitsIn800x600() {
        let landscape = ImageUploadPlan.thumbnailSize(width: 2560, height: 1920)
        #expect(landscape?.width == 800 && landscape?.height == 600)
        let tall = ImageUploadPlan.thumbnailSize(width: 1000, height: 2000)
        #expect(tall?.width == 300 && tall?.height == 600)
        #expect(ImageUploadPlan.thumbnailSize(width: 640, height: 480) == nil)
    }
}

@MainActor
struct ReceptionTests {

    @Test func syncFilterAsksFor30EventsLazyMembersAndThreadCounts() throws {
        let json = try #require(try JSONSerialization.jsonObject(with: Data(MatrixClient.syncFilterJSON.utf8)) as? [String: Any])
        let room = try #require(json["room"] as? [String: Any])
        let timeline = try #require(room["timeline"] as? [String: Any])
        #expect(timeline["limit"] as? Int == 30)
        #expect(timeline["unread_thread_notifications"] as? Bool == true)
        #expect((room["state"] as? [String: Any])?["lazy_load_members"] as? Bool == true)
    }

    @Test func threadUnreadCountsDecode() throws {
        let room = try JSONDecoder().decode(JoinedRoom.self, from: Data("""
        {"unread_notifications":{"notification_count":1,"highlight_count":0},
         "unread_thread_notifications":{"$root":{"notification_count":2,"highlight_count":1}}}
        """.utf8))
        #expect(room.unreadNotifications?.notificationCount == 1)
        #expect(room.unreadThreadNotifications?["$root"]?.highlightCount == 1)
    }

    @Test func redactedAndEditEventsAreRecognised() throws {
        let redacted = try JSONDecoder().decode(MatrixEvent.self, from: Data("""
        {"type":"m.room.message","event_id":"$1","sender":"@a:x","content":{},
         "unsigned":{"redacted_because":{"type":"m.room.redaction","redacts":"$1"}}}
        """.utf8))
        #expect(MatrixStore.isRedactedEvent(redacted))

        let edit = try JSONDecoder().decode(MatrixEvent.self, from: Data("""
        {"type":"m.room.message","event_id":"$2","sender":"@a:x",
         "content":{"body":"* new","m.new_content":{"body":"new"},"m.relates_to":{"rel_type":"m.replace","event_id":"$1"}}}
        """.utf8))
        #expect(!MatrixStore.isRedactedEvent(edit))
        #expect(MatrixStore.replacedEventId(of: edit) == "$1")
    }

    @Test func replacingAMessageKeepsOwnership() {
        let author = MoodUser(id: UUID(), username: "me", displayName: "Moi", avatarEmoji: "🌊", roleColor: .blue,
                              status: .online, bio: "", joinedDate: Date(), badges: [], activity: nil)
        var message = ChatMessage(id: UUID(), sender: author, content: "avant", timestamp: Date(), isGrouped: false)
        message.isOwn = true
        let edited = message.replacing(content: "après", isEdited: true)
        #expect(edited.isOwn)
        #expect(edited.content == "après")
        #expect(edited.isEdited)
        #expect(message.replacing(isGrouped: true).isOwn)
    }
}



// MARK: - Mood usernames

struct MoodUsernameTests {

    @Test func normalizesWhatPeopleType() {
        #expect(MoodUsername.normalized("  @Demeauxa8 ") == "demeauxa8")
        #expect(MoodUsername.normalized("jean.dupont") == "jean.dupont")
        #expect(MoodUsername.normalized("ok_2") == "ok_2")
    }

    @Test func rejectsWhatCannotBeAUsername() {
        #expect(MoodUsername.normalized("a") == nil)
        #expect(MoodUsername.normalized("two words") == nil)
        #expect(MoodUsername.normalized("jean..dupont") == nil)
        #expect(MoodUsername.normalized("@x:mood.local") == nil)
        #expect(MoodUsername.normalized(String(repeating: "a", count: 33)) == nil)
        #expect(MoodUsername.normalized("élise") == nil)
    }
}


// MARK: - Supabase messages

struct SupabaseMessageTests {

    @Test func commonAuthErrorsAreFrench() {
        #expect(SupabaseAuthClient.frenchMessage(for: "Email not confirmed").contains("pas encore confirmée"))
        #expect(SupabaseAuthClient.frenchMessage(for: "Invalid login credentials") == "E-mail ou mot de passe incorrect.")
        #expect(SupabaseAuthClient.frenchMessage(for: "email rate limit exceeded").hasPrefix("Trop de tentatives"))
        #expect(SupabaseAuthClient.frenchMessage(for: "Something else") == "Something else")
    }
}


// MARK: - Return to send

struct MessageReturnKeyTests {

    @Test func aReturnThatAddsOneLineBreakSends() {
        #expect(MessageReturnKey.isPlainReturn(old: "salut", new: "salut\n"))
        #expect(MessageReturnKey.isPlainReturn(old: "ab", new: "a\nb"))
    }

    @Test func otherEditsDoNotSend() {
        #expect(!MessageReturnKey.isPlainReturn(old: "salut", new: "salut!"))
        #expect(!MessageReturnKey.isPlainReturn(old: "", new: "a\nb"))
        #expect(!MessageReturnKey.isPlainReturn(old: "a\nb", new: "a\nb\nc\n"))
    }
}

