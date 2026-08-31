//
//  moodTests.swift
//  moodTests
//
//  Created by Augustin  on 27/02/2026.
//

import Foundation
import SwiftUI
import Testing
@testable import mood

struct moodTests {

    @Test func markingChannelAsReadClearsChannelAndRecomputesServerBadges() {
        let mentionedChannel = Channel(
            id: UUID(),
            name: "general",
            type: .text,
            topic: "General",
            unreadCount: 4,
            mentionCount: 2,
            isE2E: true
        )
        let unreadChannel = Channel(
            id: UUID(),
            name: "showcase",
            type: .text,
            topic: "Showcase",
            unreadCount: 1,
            isE2E: true
        )
        let server = MoodServer(
            id: UUID(),
            name: "Design Club",
            iconEmoji: "🎨",
            categories: [
                ChannelCategory(
                    id: UUID(),
                    name: "TEXT CHANNELS",
                    channels: [mentionedChannel, unreadChannel]
                )
            ],
            members: [],
            memberRoles: [:],
            hasUnread: true,
            mentionCount: 2
        )

        let partiallyReadServer = server.markingChannelAsRead(mentionedChannel.id)
        let readMentionedChannel = partiallyReadServer.channel(withID: mentionedChannel.id)

        #expect(readMentionedChannel?.unreadCount == 0)
        #expect(readMentionedChannel?.mentionCount == 0)
        #expect(partiallyReadServer.hasUnread)
        #expect(partiallyReadServer.mentionCount == 0)

        let fullyReadServer = partiallyReadServer.markingChannelAsRead(unreadChannel.id)
        #expect(fullyReadServer.channel(withID: unreadChannel.id)?.unreadCount == 0)
        #expect(fullyReadServer.hasUnread == false)
        #expect(fullyReadServer.mentionCount == 0)
    }

    @Test func markingDirectMessageAsReadClearsOnlyItsCounter() {
        let user = MoodUser(
            id: UUID(),
            username: "Clara",
            displayName: "Clara",
            avatarEmoji: "🌸",
            roleColor: .pink,
            status: .online,
            bio: "",
            joinedDate: Date(),
            badges: [],
            activity: nil
        )
        let conversation = DMConversation(
            id: UUID(),
            participant: user,
            lastMessage: "Hello",
            lastMessageDate: Date(),
            unreadCount: 3
        )

        let readConversation = conversation.withUnreadCount(0)

        #expect(readConversation.id == conversation.id)
        #expect(readConversation.unreadCount == 0)
        #expect(readConversation.lastMessage == conversation.lastMessage)
    }

}
