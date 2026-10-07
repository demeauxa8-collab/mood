//
//  moodTests.swift
//  moodTests
//
//  Pure logic only: no network, no homeserver.
//

import Foundation
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
