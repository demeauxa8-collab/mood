import Foundation
import Testing
#if canImport(mood)
@testable import mood
#else
@testable import OnboardingHarness
#endif

@MainActor
private final class OnboardingFixture {
    let defaults: UserDefaults
    let suite = "onboarding-tests.\(UUID().uuidString)"
    var events: [String] = []
    var loginEmail: String?
    var available = true
    var failure: String?
    var usernameConflict = false
    var confirmationAlreadySignedIn = false
    var resultUser: MoodUser?
    var checking: (() async throws -> Bool)?

    init() { defaults = UserDefaults(suiteName: suite)! }
    func clean() { defaults.removePersistentDomain(forName: suite) }
    func record(_ event: String) throws {
        events.append(event)
        if failure == event { throw OnboardingError.network }
    }
    var adapter: OnboardingAdapter {
        OnboardingAdapter(services: OnboardingServices(
            checkUsername: { _ in
                try self.record("check")
                if let checking = self.checking { return try await checking() }
                return self.available
            },
            register: { _, _ in try self.record("register") },
            confirm: { code, email in
                try self.record("confirm:\(email)")
                guard code == "123456" || (code.isEmpty && self.confirmationAlreadySignedIn) else { throw OnboardingError.invalidCode }
                return "account-A"
            },
            resend: { email in try self.record("resend:\(email)") },
            login: { email, _ in self.loginEmail = email; try self.record("login"); return "account-A" },
            resetPassword: { _ in try self.record("reset") },
            setUsername: { name in
                try self.record("username:\(name)")
                if self.usernameConflict { throw OnboardingError.usernameTaken }
            },
            setDisplayName: { _ in try self.record("name") },
            setAvatar: { _ in try self.record("photo") },
            setAvatarEmoji: { _ in try self.record("emoji") },
            searchUser: { _ in try self.record("search"); return self.resultUser },
            addFriend: { _ in try self.record("add") },
            openDM: { _ in try self.record("dm") },
            joinServer: { _ in try self.record("join") },
            createServer: { _, template in try self.record("create:\(template.rawValue)") },
            requestNotifications: { try self.record("notifications") },
            finish: { try self.record("finish") }
        ))
    }
    func chooseUsername(_ model: OnboardingModel) async {
        model.go(.username); model.username = "demo"
        await model.checkUsername(); await model.submit()
        events.removeAll()
    }
    func model(_ userID: String? = nil) -> OnboardingModel {
        OnboardingModel(actions: adapter, defaults: defaults, userID: userID)
    }
}

@MainActor
struct OnboardingTests {
    @Test func signupOrdersAccountConfirmationAndAuthenticatedUsername() async {
        let fixture = OnboardingFixture(); defer { fixture.clean() }
        let model = fixture.model()
        await model.submit(); #expect(model.step == .email)
        model.email = "demo@example.invalid"
        await model.submit(); #expect(model.step == .account)
        model.password = "synthetic-password"
        #expect(model.canContinue && model.username.isEmpty)
        await model.submit()
        #expect(model.step == .confirmation && model.password.isEmpty && fixture.events == ["register"])
        model.code = "123456"; await model.submit()
        #expect(model.accountID == "account-A" && model.step == .displayName)
        model.displayName = "Alex"; await model.submit()
        #expect(model.step == .username && !model.canContinue)
        model.username = "demo"
        #expect(!model.canContinue && model.usernameAvailability == nil)
        await model.checkUsername(); #expect(model.canContinue)
        await model.submit(); #expect(model.step == .trust)
        #expect(fixture.events == ["register", "confirm:demo@example.invalid", "name", "check", "username:demo"])
        model.back(); #expect(model.step == .username)
    }

    @Test func confirmedAccountResumesAtUsernameUntilSaved() async {
        let fixture = OnboardingFixture(); defer { fixture.clean() }
        let model = fixture.model()
        model.go(.confirmation); model.email = "demo@example.invalid"
        model.code = "123456"; await model.submit()
        #expect(model.step == .displayName)
        let restored = fixture.model("account-A")
        #expect(restored.step == .username && restored.password.isEmpty && restored.code.isEmpty)
        restored.username = "demo"; await restored.checkUsername()
        fixture.usernameConflict = true; await restored.submit()
        #expect(restored.step == .username && restored.usernameAvailability == false)
        #expect(restored.fieldError == "Ce nom d'utilisateur est déjà pris.")
        #expect(fixture.model("account-A").step == .username)
        restored.username = "other"; fixture.usernameConflict = false
        #expect(!restored.canContinue && restored.usernameAvailability == nil)
        await restored.checkUsername(); await restored.submit()
        #expect(fixture.model("account-A").step == .trust)
        #expect(!fixture.events.contains("register"))
    }

    @Test func usernameCannotBeCheckedBeforeAuthenticationOrWithoutServerReply() async {
        let fixture = OnboardingFixture(); defer { fixture.clean() }
        let guest = fixture.model(); guest.go(.account); guest.username = "demo"
        await guest.checkUsername()
        #expect(guest.usernameAvailability == nil && fixture.events.isEmpty)
        let model = fixture.model("account-A"); model.username = "demo"
        #expect(!model.canContinue && model.usernameAvailability == nil)
        await model.checkUsername(); #expect(model.usernameAvailability == true)
        fixture.failure = "check"; await model.checkUsername()
        #expect(model.usernameAvailability == nil && model.networkError != nil && !model.canContinue)
        await model.skip(); #expect(model.step == .username)
        #expect(!OnboardingModel.isComplete(for: "account-A", defaults: fixture.defaults))
    }

    @Test func skipDisplayNameStillRequiresUsername() async {
        let fixture = OnboardingFixture(); defer { fixture.clean() }
        let model = fixture.model("account-A"); model.go(.displayName)
        await model.skip()
        #expect(model.step == .username && fixture.events.isEmpty)
    }

    @Test func restoredSessionBetweenOTPAndDraftAdoptionIsNotExempted() {
        let fixture = OnboardingFixture(); defer { fixture.clean() }
        let guest = fixture.model(); guest.go(.confirmation); guest.email = "demo@example.invalid"
        OnboardingLifecycle.bootstrap(restoredAccountID: "account-A", restoredEmail: "demo@example.invalid", defaults: fixture.defaults)
        #expect(!OnboardingModel.isComplete(for: "account-A", defaults: fixture.defaults))
        #expect(fixture.model("account-A").step == .username)
        #expect(fixture.model("account-A").email == "demo@example.invalid")
        #expect(fixture.defaults.data(forKey: OnboardingModel.progressKey(for: nil)) == nil)
    }

    @Test func anotherAccountsGuestConfirmationDoesNotRemoveUpgradeExemption() {
        let fixture = OnboardingFixture(); defer { fixture.clean() }
        let guest = fixture.model(); guest.go(.confirmation); guest.email = "other@example.invalid"
        OnboardingLifecycle.bootstrap(restoredAccountID: "existing", restoredEmail: "demo@example.invalid", defaults: fixture.defaults)
        #expect(OnboardingModel.isComplete(for: "existing", defaults: fixture.defaults))
        #expect(fixture.model("existing").email.isEmpty)
    }

    @Test func loginWithoutAccountDraftDiscardsGuestFields() async {
        let fixture = OnboardingFixture(); defer { fixture.clean() }
        let model = fixture.model()
        model.go(.account); model.username = "guest"; model.displayName = "Guest"
        model.inviteCode = "private"; model.selectAvatarEmoji("🐸")
        model.go(.signIn); model.email = "demo@example.invalid"; model.password = "synthetic-password"
        await model.submit()
        #expect(model.step == .username && model.username.isEmpty && model.displayName.isEmpty)
        #expect(model.inviteCode.isEmpty && model.avatarEmoji == nil)
    }

    @Test func legacyDraftWithoutUsernameCheckpointResumesAuthenticatedChoice() throws {
        let fixture = OnboardingFixture(); defer { fixture.clean() }
        let model = fixture.model("account-A"); model.go(.trust); model.displayName = "Alex"
        let key = OnboardingModel.progressKey(for: "account-A")
        let data = try #require(fixture.defaults.data(forKey: key))
        var legacy = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        legacy.removeValue(forKey: "usernameSaved")
        fixture.defaults.set(try JSONSerialization.data(withJSONObject: legacy), forKey: key)
        let restored = fixture.model("account-A")
        #expect(restored.step == .username && restored.displayName == "Alex")
        #expect(!restored.canContinue && restored.usernameAvailability == nil)
    }

    @Test func emailCallbackAdoptsSessionWithoutAnotherSignup() async {
        let fixture = OnboardingFixture(); defer { fixture.clean() }
        fixture.confirmationAlreadySignedIn = true
        let model = fixture.model(); model.go(.confirmation); model.email = "demo@example.invalid"
        await model.acceptConfirmedSession()
        #expect(model.accountID == "account-A" && model.step == .displayName)
        #expect(fixture.events == ["confirm:demo@example.invalid"])
        #expect(fixture.model("account-A").step == .username)
    }

    @Test func lateLookupAfterNavigationCannotApproveTheNextScreen() async {
        let fixture = OnboardingFixture(); defer { fixture.clean() }
        let model = fixture.model("account-A"); model.username = "demo"
        var continuation: CheckedContinuation<Bool, Never>?
        fixture.checking = { await withCheckedContinuation { continuation = $0 } }
        let task = Task { await model.checkUsername() }
        while continuation == nil { await Task.yield() }
        model.back(); #expect(model.step == .displayName)
        continuation?.resume(returning: true); await task.value
        #expect(model.usernameAvailability == nil && !model.isCheckingUsername)
        await model.skip(); #expect(model.step == .username && !model.canContinue)
    }

    @Test func validationBoundaries() {
        let fixture = OnboardingFixture(); defer { fixture.clean() }
        let model = fixture.model()
        for value in ["a@b.fr", "first.last+test@example.invalid", " test@example.invalid "] {
            model.email = value; #expect(model.emailIsValid)
        }
        for value in ["", "test", "a@b", "a b@c.fr", "@b.fr"] {
            model.email = value; #expect(!model.emailIsValid)
        }
        for value in ["ab", String(repeating: "a", count: 32), "a_1.b"] {
            model.username = value; #expect(model.usernameIsValid)
        }
        for value in ["a", String(repeating: "a", count: 33), "Ab", "a-b", "a..b", "éé", " a"] {
            model.username = value; #expect(!model.usernameIsValid)
        }
        model.password = "1234567"; #expect(!model.passwordIsValid)
        model.password = "12345678"; #expect(model.passwordIsValid)
        model.go(.confirmation)
        for value in ["", "12345", "abcdef", "１２３４５６", "1234567"] {
            model.code = value; #expect(!model.canContinue)
        }
        model.code = "012345"; #expect(model.canContinue)
    }

    @Test func draftsExcludeSecretsAndPhoto() throws {
        let fixture = OnboardingFixture(); defer { fixture.clean() }
        let model = fixture.model()
        model.go(.account)
        model.email = "demo@example.invalid"; model.username = "demo"
        model.displayName = "A long display name"
        model.friendUsername = "friend"; model.inviteCode = "invitation"
        model.serverName = "Study"; model.template = .studies; model.isCreatingServer = true
        model.password = "DO-NOT-PERSIST-PASSWORD"; model.code = "654321"
        model.setAvatarData(Data("DO-NOT-PERSIST-PHOTO".utf8))
        let data = try #require(fixture.defaults.data(forKey: OnboardingModel.progressKey(for: nil)))
        let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(object["password"] == nil && object["code"] == nil && object["avatarData"] == nil)
        let restored = fixture.model()
        #expect(restored.step == .account && restored.email == model.email && restored.username == model.username)
        #expect(restored.displayName == model.displayName && restored.friendUsername == "friend")
        #expect(restored.inviteCode == "invitation" && restored.serverName == "Study")
        #expect(restored.template == .studies && restored.isCreatingServer)
        #expect(restored.password.isEmpty && restored.code.isEmpty && restored.avatarData == nil)
        model.selectAvatarEmoji("🐸")
        #expect(fixture.model().avatarEmoji == "🐸")
    }

    @Test func guestAndAccountDraftsStayIsolatedOnLogin() async {
        let fixture = OnboardingFixture(); defer { fixture.clean() }
        let account = fixture.model("account-A")
        await fixture.chooseUsername(account)
        account.go(.friends); account.friendUsername = "saved_friend"
        let guest = fixture.model()
        guest.go(.account); guest.displayName = "Guest"
        #expect(fixture.model("account-B").displayName.isEmpty)
        guest.go(.signIn); guest.email = "demo@example.invalid"; guest.password = "synthetic-password"
        await guest.submit()
        #expect(guest.accountID == "account-A")
        #expect(guest.step == .friends && guest.friendUsername == "saved_friend")
        #expect(guest.displayName.isEmpty && guest.password.isEmpty)
        #expect(fixture.defaults.data(forKey: OnboardingModel.progressKey(for: nil)) == nil)
    }

    @Test func confirmationResumesWithoutPasswordAndMigratesGuest() async {
        let fixture = OnboardingFixture(); defer { fixture.clean() }
        let guest = fixture.model()
        guest.go(.confirmation); guest.email = "demo@example.invalid"; guest.username = "demo"
        let restored = fixture.model()
        restored.code = "123456"
        await restored.submit()
        #expect(restored.accountID == "account-A" && restored.step == .displayName)
        #expect(restored.password.isEmpty && restored.code.isEmpty)
        #expect(fixture.events == ["confirm:demo@example.invalid"])
        #expect(fixture.defaults.data(forKey: OnboardingModel.progressKey(for: nil)) == nil)
        #expect(fixture.model("account-A").email == "demo@example.invalid")
        restored.back(); #expect(restored.step == .displayName)
    }

    @Test func invalidAndResentCodeStayOnConfirmation() async {
        let fixture = OnboardingFixture(); defer { fixture.clean() }
        let model = fixture.model()
        model.go(.confirmation); model.email = "demo@example.invalid"; model.username = "demo"
        model.code = "000000"; await model.submit()
        #expect(model.step == .confirmation && model.accountID == nil && model.fieldError != nil)
        await model.resendCode()
        #expect(fixture.events.contains("resend:demo@example.invalid"))
        fixture.failure = "resend:demo@example.invalid"
        await model.resendCode(); #expect(model.networkError != nil && !model.isResendingCode)
    }

    @Test func serverAvailabilityIsAuthoritativeAndNetworkIsDistinct() async throws {
        let fixture = OnboardingFixture(); defer { fixture.clean() }
        let model = fixture.model("account-A")
        model.go(.username); model.username = "demo"
        fixture.available = false; await model.checkUsername()
        #expect(model.usernameAvailability == false && model.fieldError != nil && model.networkError == nil)
        fixture.available = true; fixture.failure = "check"; model.username = "other"
        await model.checkUsername()
        #expect(model.usernameAvailability == nil && model.networkError != nil)
        fixture.failure = nil; await model.checkUsername(); #expect(model.canContinue)
        fixture.failure = "username:other" // Save failures must not complete this step.
        await model.submit()
        #expect(!fixture.events.contains("register") && model.step == .username)
        fixture.failure = nil
        await model.checkUsername()
        await model.submit(); #expect(model.step == .trust && model.password.isEmpty)
    }

    @Test func successIsScopedAndClearsDrafts() async {
        let fixture = OnboardingFixture(); defer { fixture.clean() }
        let model = fixture.model("account-A")
        model.go(.avatar); model.selectAvatarEmoji("🐸")
        await model.submit()
        #expect(model.didFinish && fixture.events == ["emoji", "finish"])
        #expect(OnboardingModel.isComplete(for: "account-A", defaults: fixture.defaults))
        #expect(!OnboardingModel.isComplete(for: "account-B", defaults: fixture.defaults))
        #expect(fixture.defaults.data(forKey: OnboardingModel.progressKey(for: "account-A")) == nil)
    }

    @Test func failedFinishCanRetryWithoutLosingStep() async {
        let fixture = OnboardingFixture(); defer { fixture.clean() }
        let model = fixture.model("account-A")
        await fixture.chooseUsername(model)
        model.go(.avatar); model.selectAvatarEmoji("🐸"); fixture.failure = "finish"
        await model.submit()
        #expect(!model.didFinish && model.step == .avatar && model.networkError != nil && !model.isBusy)
        #expect(!OnboardingModel.isComplete(for: "account-A", defaults: fixture.defaults))
        #expect(fixture.model("account-A").step == .avatar)
        fixture.failure = nil; await model.skip()
        #expect(model.didFinish)
    }

    @Test func photoAndResetAreForwarded() async {
        let fixture = OnboardingFixture(); defer { fixture.clean() }
        let model = fixture.model("account-A")
        model.go(.avatar); model.setAvatarData(Data([1, 2, 3])); await model.submit()
        #expect(fixture.events == ["photo", "finish"])
        let login = fixture.model()
        login.go(.signIn); login.email = "demo@example.invalid"; login.password = "synthetic-password"
        await login.resetPassword()
        #expect(login.password.isEmpty)
        #expect(login.passwordResetSent && fixture.events.last == "reset")
        fixture.failure = "reset"; await login.resetPassword()
        #expect(!login.passwordResetSent && login.networkError != nil)
    }

    @Test func refusedInviteAndMissingFriendDoNotAdvance() async {
        let fixture = OnboardingFixture(); defer { fixture.clean() }
        let model = fixture.model("account-A")
        model.go(.trust); await model.submit(); #expect(model.step == .server)
        model.inviteCode = "rejected"; fixture.failure = "join"; await model.submit()
        #expect(model.step == .server && model.networkError != nil)
        await model.skip(); #expect(model.step == .notifications)
        model.continueWithoutNotifications(); #expect(model.step == .friends)
        model.friendUsername = "unknown"; await model.submit()
        #expect(model.step == .friends && model.fieldError != nil)
        #expect(!fixture.events.contains("notifications") && !fixture.events.contains("add"))
        await model.skip(); #expect(model.step == .avatar)
    }

    @Test func friendOpensDMOnlyAfterSuccessfulAddition() async {
        let fixture = OnboardingFixture(); defer { fixture.clean() }
        #if canImport(mood)
        fixture.resultUser = MockData.users.first
        #else
        fixture.resultUser = MoodUser()
        #endif
        let model = fixture.model("account-A")
        model.go(.friends); model.friendUsername = "friend"
        fixture.failure = "add"; await model.submit()
        #expect(model.step == .friends && !fixture.events.contains("dm"))
        fixture.failure = nil; await model.submit()
        #expect(model.step == .avatar && Array(fixture.events.suffix(3)) == ["search", "add", "dm"])
    }

    @Test func alreadyCompleteLoginSkipsOnboarding() async {
        let fixture = OnboardingFixture(); defer { fixture.clean() }
        fixture.defaults.set(true, forKey: OnboardingModel.completionKey(for: "account-A"))
        let model = fixture.model()
        model.go(.signIn); model.email = "  Demo@example.invalid  "; model.password = "synthetic-password"
        await model.submit()
        #expect(fixture.loginEmail == "demo@example.invalid")
        #expect(model.didFinish && model.accountID == "account-A" && model.password.isEmpty)
        #expect(fixture.events == ["login"])
    }

    @Test func staleAvailabilityResultCannotApproveAnotherName() async {
        let fixture = OnboardingFixture(); defer { fixture.clean() }
        let model = fixture.model("account-A")
        model.go(.username); model.username = "first"
        var continuation: CheckedContinuation<Bool, Never>?
        fixture.checking = { await withCheckedContinuation { continuation = $0 } }
        let task = Task { await model.checkUsername() }
        while continuation == nil { await Task.yield() }
        model.username = "second"
        continuation?.resume(returning: true)
        await task.value
        #expect(model.usernameAvailability == nil && !model.isCheckingUsername)
        fixture.checking = nil; fixture.available = false
        await model.checkUsername(); #expect(model.usernameAvailability == false)
    }

    @Test func busySkipCannotBypassAFailingAction() async {
        let fixture = OnboardingFixture(); defer { fixture.clean() }
        var continuation: CheckedContinuation<Void, Never>?
        // Suspend through the real action boundary, without a timer or network.
        let adapter = OnboardingAdapter(services: OnboardingServices(
            checkUsername: { _ in true }, register: { _, _ in }, confirm: { _, _ in "account-A" },
            resend: { _ in }, login: { _, _ in "account-A" }, resetPassword: { _ in },
            setUsername: { _ in }, setDisplayName: { _ in }, setAvatar: { _ in }, setAvatarEmoji: { _ in },
            searchUser: { _ in nil }, addFriend: { _ in }, openDM: { _ in }, joinServer: { _ in },
            createServer: { _, _ in }, requestNotifications: {}, finish: {
                await withCheckedContinuation { continuation = $0 }
                throw OnboardingError.finishFailed
            }
        ))
        let busyModel = OnboardingModel(actions: adapter, defaults: fixture.defaults, userID: "account-A")
        busyModel.go(.avatar)
        let task = Task { await busyModel.skip() }
        while continuation == nil { await Task.yield() }
        await busyModel.skip(); busyModel.back()
        #expect(busyModel.isBusy && !busyModel.didFinish && busyModel.step == .avatar)
        continuation?.resume(); await task.value
        #expect(!busyModel.didFinish && busyModel.networkError != nil)
    }

    @Test func eachTemplateMapsToRealChannels() async {
        let fixture = OnboardingFixture(); defer { fixture.clean() }
        for template in OnboardingTemplate.allCases {
            let model = fixture.model("account-A")
            model.go(.server); model.isCreatingServer = true; model.serverName = "Friends"; model.template = template
            await model.submit()
            #expect(model.step == .notifications && fixture.events.last == "create:\(template.rawValue)")
            #expect(template.channelNames.first == "général")
        }
        #expect(OnboardingTemplate.games.channelNames != OnboardingTemplate.studies.channelNames)
        #expect(OnboardingTemplate.blank.channelNames.count == 1)
    }

    @Test func notificationsOnlyWhenExplicitlyRequested() async {
        let fixture = OnboardingFixture(); defer { fixture.clean() }
        let model = fixture.model("account-A")
        model.go(.notifications); await model.skip()
        #expect(fixture.events.isEmpty)
        model.go(.notifications); await model.submit()
        #expect(fixture.events == ["notifications"] && model.step == .friends)
    }

    @Test func upgradeExemptsRestoredExistingSessionOnly() {
        let fixture = OnboardingFixture(); defer { fixture.clean() }
        OnboardingLifecycle.bootstrap(restoredAccountID: "existing", defaults: fixture.defaults)
        #expect(OnboardingModel.isComplete(for: "existing", defaults: fixture.defaults))
        #expect(!OnboardingModel.isComplete(for: "new", defaults: fixture.defaults))
        OnboardingLifecycle.bootstrap(restoredAccountID: "new", defaults: fixture.defaults)
        #expect(!OnboardingModel.isComplete(for: "new", defaults: fixture.defaults))
    }

    @Test func newInstallAndInterruptedOnboardingAreNotExempted() async {
        let fixture = OnboardingFixture(); defer { fixture.clean() }
        OnboardingLifecycle.bootstrap(restoredAccountID: nil, defaults: fixture.defaults)
        OnboardingLifecycle.bootstrap(restoredAccountID: "new", defaults: fixture.defaults)
        #expect(!OnboardingModel.isComplete(for: "new", defaults: fixture.defaults))
        fixture.defaults.removeObject(forKey: OnboardingLifecycle.migrationKey)
        let model = fixture.model("interrupted")
        await fixture.chooseUsername(model)
        model.go(.friends)
        OnboardingLifecycle.bootstrap(restoredAccountID: "interrupted", defaults: fixture.defaults)
        #expect(!OnboardingModel.isComplete(for: "interrupted", defaults: fixture.defaults))
        #expect(fixture.model("interrupted").step == .friends)
    }

    @Test func signoutErasesDraftsButPreservesCompletion() {
        let fixture = OnboardingFixture(); defer { fixture.clean() }
        let model = fixture.model("account-A"); model.displayName = "Private name"
        let guest = fixture.model(); guest.go(.email); guest.email = "private@example.invalid"
        fixture.defaults.set(true, forKey: OnboardingModel.completionKey(for: "account-A"))
        OnboardingModel.discardProgress(for: "account-A", defaults: fixture.defaults)
        #expect(fixture.model().email.isEmpty && fixture.model("account-A").displayName.isEmpty)
        #expect(OnboardingModel.isComplete(for: "account-A", defaults: fixture.defaults))
    }
}
