import Foundation
import Testing
#if canImport(mood)
@testable import mood
#else
@testable import FirstRunLogic
#endif

@MainActor
struct FirstRunTests {
    @Test func onlyKnownLoadedHistoryHasABeginning() {
        for known in [true, false] {
            for loading in [true, false] {
                #expect(FirstRunPolicy.showsBeginning(knownStart: known, loading: loading) == (known && !loading))
            }
        }
    }

    @Test func checklistDoesNotAppearOnAnExistingOrUnmanagedChannel() {
        #expect(FirstRunPolicy.showsChecklist(isFirstTextChannel: true, canManage: true, knownStart: true,
            hasMessages: false, started: false, finished: false))
        for (first, manage, known, messages, started, finished) in [
            (false, true, true, false, false, false), (true, false, true, false, false, false),
            (true, true, false, false, false, false), (true, true, true, true, false, false),
            (true, true, true, false, true, true)
        ] {
            #expect(!FirstRunPolicy.showsChecklist(isFirstTextChannel: first, canManage: manage, knownStart: known,
                hasMessages: messages, started: started, finished: finished))
        }
    }

    @Test func missingPaginationCursorIsNotProofOfTheBeginning() {
        #expect(!FirstRunPolicy.hasReachedBeginning(hasMoreHistory: nil, hasPaginationCursor: false, conversationComplete: false, loading: false))
        #expect(!FirstRunPolicy.hasReachedBeginning(hasMoreHistory: false, hasPaginationCursor: false, conversationComplete: false, loading: false))
        #expect(!FirstRunPolicy.hasReachedBeginning(hasMoreHistory: true, hasPaginationCursor: true, conversationComplete: false, loading: false))
        #expect(FirstRunPolicy.hasReachedBeginning(hasMoreHistory: false, hasPaginationCursor: true, conversationComplete: false, loading: false))
        #expect(FirstRunPolicy.hasReachedBeginning(hasMoreHistory: true, hasPaginationCursor: true, conversationComplete: true, loading: false))
        #expect(!FirstRunPolicy.hasReachedBeginning(hasMoreHistory: false, hasPaginationCursor: true, conversationComplete: true, loading: true))
    }

    @Test func channelEditingRequiresBothNameAndTopicPermissions() {
        #expect(!FirstRunPolicy.canEditChannel(userLevel: 0, stateDefault: nil, nameLevel: nil, topicLevel: nil))
        #expect(FirstRunPolicy.canEditChannel(userLevel: 50, stateDefault: nil, nameLevel: nil, topicLevel: nil))
        #expect(!FirstRunPolicy.canEditChannel(userLevel: 50, stateDefault: nil, nameLevel: 10, topicLevel: 100))
        #expect(FirstRunPolicy.canEditChannel(userLevel: 100, stateDefault: nil, nameLevel: 10, topicLevel: 100))
        #expect(FirstRunPolicy.canEditChannel(userLevel: 0, stateDefault: 0, nameLevel: nil, topicLevel: nil))
    }

    @Test func startedChecklistRemainsAfterFirstMessageUntilFinished() {
        #expect(FirstRunPolicy.showsChecklist(isFirstTextChannel: true, canManage: true, knownStart: true,
            hasMessages: true, started: true, finished: false))
    }

    @Test func friendsEmptySearchAndOfflineAreDifferentStates() {
        #expect(FirstRunPolicy.friendsState(total: 0, visible: 0, query: "") == .empty)
        #expect(FirstRunPolicy.friendsState(total: 0, visible: 0, query: "  ") == .empty)
        #expect(FirstRunPolicy.friendsState(total: 5, visible: 0, query: "Camille") == .noResults)
        #expect(FirstRunPolicy.friendsState(total: 0, visible: 0, query: "Camille") == .noResults)
        #expect(FirstRunPolicy.friendsState(total: 5, visible: 0, query: "") == .offline)
        #expect(FirstRunPolicy.friendsState(total: 5, visible: 1, query: "Camille") == .populated)
    }

    @Test func queuedFailedPeerAndSystemMessagesNeverCompleteTheMessageStep() {
        #expect(FirstRunPolicy.confirmedFirstMessage(isOwn: true, isSystem: false, accepted: true))
        #expect(!FirstRunPolicy.confirmedFirstMessage(isOwn: true, isSystem: false, accepted: false))
        #expect(!FirstRunPolicy.confirmedFirstMessage(isOwn: false, isSystem: false, accepted: true))
        #expect(!FirstRunPolicy.confirmedFirstMessage(isOwn: true, isSystem: true, accepted: true))
    }

    @Test func absentPublicUsernameNeverFallsBackToTechnicalIdentifier() {
        #expect(FirstRunPolicy.publicUsername(nil) == nil)
        #expect(FirstRunPolicy.publicUsername(" ") == nil)
        #expect(FirstRunPolicy.publicUsername("@m123456:mood.local") == nil)
        #expect(FirstRunPolicy.publicUsername("m123456:mood.local") == nil)
        #expect(FirstRunPolicy.publicUsername("marie") == "marie")
        #expect(FirstRunPolicy.publicUsername("@marie") == "@marie")
    }

    @Test func beginNeverCompletesAStepAndCompletingIsIdempotent() {
        let model = ServerWelcomeProgress()
        let scope = ServerWelcomeScope(account: "test-a", server: "test-server")
        #expect(!model.started(scope))
        model.begin(scope)
        model.begin(scope)
        #expect(model.started(scope))
        for step in ServerWelcomeStep.allCases { #expect(!model.completed(step, in: scope)) }
        model.complete(.message, in: scope)
        model.complete(.message, in: scope)
        #expect(model.completed(.message, in: scope))
        #expect(!model.completed(.invite, in: scope))
        #expect(!model.finished(scope))
    }

    @Test func completionIsIsolatedByAccountAndCanonicalServer() {
        let model = ServerWelcomeProgress()
        let scope = ServerWelcomeScope(account: "test-a", server: "test-server")
        model.complete(.invite, in: scope)
        for other in [ServerWelcomeScope(account: "test-b", server: "test-server"),
                      ServerWelcomeScope(account: "test-a", server: "another-server")] {
            #expect(!model.started(other))
            #expect(!model.completed(.invite, in: other))
        }
    }

    @Test func allFourStepsAreRequired() {
        let model = ServerWelcomeProgress()
        let scope = ServerWelcomeScope(account: "test-a", server: "test-server")
        for step in ServerWelcomeStep.allCases.dropLast() { model.complete(step, in: scope) }
        #expect(!model.finished(scope))
        model.complete(.otherDevice, in: scope)
        #expect(model.finished(scope))
    }

    @Test func persistenceSurvivesRelaunchAndMalformedDataIsIgnored() throws {
        let suite = "MoodFirstRunTests-" + UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let scope = ServerWelcomeScope(account: "test-a", server: "test-server")
        ServerWelcomeProgress(defaults: defaults).complete(.icon, in: scope)
        let restored = ServerWelcomeProgress(defaults: defaults)
        #expect(restored.started(scope))
        #expect(restored.completed(.icon, in: scope))
        #expect(!restored.completed(.otherDevice, in: scope))
        defaults.set(Data("invalid".utf8), forKey: "Mood.serverWelcome.v1")
        #expect(!ServerWelcomeProgress(defaults: defaults).started(scope))
    }

    @Test func previewsAreMemoryOnly() {
        let scope = ServerWelcomeScope(account: "preview", server: "preview")
        ServerWelcomeProgress().complete(.invite, in: scope)
        #expect(!ServerWelcomeProgress().started(scope))
    }
}
