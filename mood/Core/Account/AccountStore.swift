import Foundation
import Observation

@Observable
@MainActor
final class AccountStore {
    private(set) var session: SupabaseSession?
    private(set) var profile: AccountProfile?
    private(set) var discord: DiscordIdentity?
    private(set) var guilds: [DiscordGuild] = []
    private(set) var importedGuildIds: Set<String> = []
    var isProvisioning = false
    var provisioningError: String?
    var matrixReady = false
    var showGuildImporter = false
    var isLoading = false
    var errorMessage: String?
    let client: SupabaseAuthClient?

    init(client: SupabaseAuthClient? = nil) {
        self.client = client ?? SupabaseAuthClient()
    }
    var isConfigured: Bool { client != nil }
    /// Discord sign-in is offered only once the provider is enabled in Supabase.
    private(set) var discordEnabled = false

    func loadProviders() async {
        guard let client else { return }
        discordEnabled = (try? await client.enabledProviders())?.contains("discord") ?? false
    }
    var isSignedIn: Bool { session != nil }
    var email: String? { session?.user.email }

    func connectMood(matrixStore: MatrixStore) async {
        guard !isProvisioning, let client, session != nil else { return }
        isProvisioning = true
        provisioningError = nil
        defer { isProvisioning = false }
        do {
            let result = try await client.matrixSession(deviceId: MoodDevice.identifier(), deviceName: MoodDevice.name)
            try await matrixStore.login(accessToken: result.accessToken, userId: result.userId,
                                        homeserver: result.homeserver, deviceId: result.deviceId)
            matrixReady = true
        } catch {
            matrixReady = false
            provisioningError = (error as? MoodProvisioningError)?.localizedDescription
                ?? "Impossible de joindre Mood. Vérifie ta connexion et réessaie."
        }
    }

    func completeEmailCallback(_ url: URL) async {
        guard !isLoading, let client else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            if SupabaseAuthClient.isRecoveryCallback(url) {
                let recovered = try await client.completeEmailCallback(url, persist: false)
                cancelPendingConfirmation()
                recoverySession = recovered
                recoveryEmail = recovered.user.email
                isRecoveringPassword = true
                errorMessage = nil
                return
            }
            session = try await client.completeEmailCallback(url)
            cancelPendingConfirmation()
            matrixReady = false
            errorMessage = nil
        } catch { errorMessage = error.localizedDescription }
    }

    func restore() async -> Bool {
        guard let client else { return false }
        do {
            session = try await client.restoreSession()
            guard session != nil else { return false }
            try await loadProfile()
            await loadDiscordIdentity()
            return true
        } catch {
            // A network or migration error must not destroy a saved session.
            errorMessage = error.localizedDescription
            return session != nil
        }
    }

    private func loadProfile() async throws {
        guard let client else { throw AccountError.notConfigured }
        profile = try await client.profile()
    }

    func signIn(email: String, password: String) async throws {
        guard !isLoading else { return }
        guard let client else { throw AccountError.notConfigured }
        isLoading = true
        defer { isLoading = false }
        session = try await client.signIn(email: email, password: password)
        try? await loadProfile()
        matrixReady = false
    }

    func signUp(email: String, password: String) async throws {
        guard !isLoading else { return }
        guard let client else { throw AccountError.notConfigured }
        isLoading = true
        defer { isLoading = false }
        do {
            session = try await client.signUp(email: email, password: password)
        } catch AccountError.emailConfirmationRequired {
            errorMessage = nil
            pendingConfirmationEmail = email
            pendingConfirmationPassword = password
            watchForConfirmation()
            return
        }
        matrixReady = false
        try? await loadProfile()
    }

    /// OTP-only onboarding: no password retained for polling or persisted in a draft.
    func registerForOnboarding(email: String, password: String) async throws {
        guard !isLoading else { throw AccountError.server("Une demande est déjà en cours.") }
        guard let client else { throw AccountError.notConfigured }
        cancelPendingConfirmation()
        isLoading = true
        defer { isLoading = false }
        do {
            session = try await client.signUp(email: email, password: password)
            matrixReady = false
            try? await loadProfile()
        } catch AccountError.emailConfirmationRequired {
            pendingConfirmationEmail = email
        }
    }

    // MARK: - E-mail confirmation

    /// Address of a sign-up waiting for its e-mail link. The link can be opened on any device (it
    /// rarely comes back to the app), so Mood signs in by itself as soon as the address is confirmed.
    private(set) var pendingConfirmationEmail: String?
    /// Kept in memory only, for the automatic sign-in; dropped once signed in or cancelled.
    private var pendingConfirmationPassword: String?
    private var confirmationWatch: Task<Void, Never>?

    /// One sign-in attempt every 15 s for 20 min, a pace well inside the Supabase sign-in rate limit.
    private func watchForConfirmation() {
        confirmationWatch?.cancel()
        confirmationWatch = Task { [weak self] in
            for _ in 0..<80 {
                try? await Task.sleep(for: .seconds(15))
                guard let self, !Task.isCancelled else { return }
                if await self.completeConfirmedSignUp(manual: false) { return }
            }
        }
    }

    /// Signs in with the sign-up credentials; true once signed in. A manual try explains a refusal.
    @discardableResult
    func completeConfirmedSignUp(manual: Bool) async -> Bool {
        guard !isLoading, let client, let email = pendingConfirmationEmail, let password = pendingConfirmationPassword else { return false }
        isLoading = true
        defer { isLoading = false }
        do {
            session = try await client.signIn(email: email, password: password)
        } catch {
            if manual { errorMessage = error.localizedDescription }
            return false
        }
        cancelPendingConfirmation()
        errorMessage = nil
        matrixReady = false
        try? await loadProfile()
        return true
    }

    func resendConfirmation() async {
        guard !isLoading, let client, let email = pendingConfirmationEmail else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            try await client.resendConfirmation(email: email)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func cancelPendingConfirmation() {
        confirmationWatch?.cancel()
        confirmationWatch = nil
        pendingConfirmationEmail = nil
        pendingConfirmationPassword = nil
    }

    func signInWithDiscord() async throws {
        guard let client else { throw AccountError.notConfigured }
        isLoading = true
        defer { isLoading = false }
        session = try await client.discordLogin()
        try? await synchronizeDiscord()
        matrixReady = false
        let preference = "discord.import.offered.\(session!.user.id.uuidString)"
        if !UserDefaults.standard.bool(forKey: preference) {
            showGuildImporter = true
            UserDefaults.standard.set(true, forKey: preference)
        }
    }

    func synchronizeDiscord() async throws {
        guard let client else { throw AccountError.notConfigured }
        do { discord = try await client.discordIdentity() }
        catch {
            guard let userId = session?.user.id else { throw AccountError.invalidResponse }
            session = try await client.discordLogin(expectedUserId: userId)
            discord = try await client.discordIdentity()
        }
        if let discord { try await client.saveDiscordProfile(discord) }
        try await refreshGuilds()
        try await loadProfile()
    }

    func loadDiscordIdentity() async {
        guard let client else { return }
        discord = try? await client.discordIdentity()
    }

    func refreshGuilds() async throws {
        guard let client else { throw AccountError.notConfigured }
        guilds = try await client.discordGuilds()
        importedGuildIds = Set(try await client.importedGuilds().filter { $0.importedSpaceId != nil }.map(\.guildId))
    }

    func unlinkDiscord() async throws {
        guard let client else { throw AccountError.notConfigured }
        try await client.unlinkDiscord()
        discord = nil
        guilds = []
        showGuildImporter = false
        try await loadProfile()
    }

    func importGuild(_ guild: DiscordGuild, matrixStore: MatrixStore) async throws {
        guard let client else { throw AccountError.notConfigured }
        guard !importedGuildIds.contains(guild.id) else { return }
        guard let userId = session?.user.id else { throw AccountError.invalidResponse }
        let recoveryKey = "discord.pendingImports.\(userId.uuidString)"
        var pending = UserDefaults.standard.dictionary(forKey: recoveryKey) as? [String: String] ?? [:]
        let server: MoodServer
        let spaceId: String
        if let savedSpace = pending[guild.id] {
            spaceId = savedSpace
            server = MoodServer(id: matrixStore.stableUUID(from: savedSpace), name: guild.name, iconEmoji: "", categories: [], members: [], memberRoles: [:], hasUnread: false, mentionCount: 0)
        } else {
            guard let id = await matrixStore.createServer(name: guild.name, isPublic: false) else {
                throw AccountError.server("Impossible de créer le serveur \(guild.name).")
            }
            server = matrixStore.servers.first(where: { $0.id == id }) ?? MoodServer(id: id, name: guild.name, iconEmoji: "", categories: [], members: [], memberRoles: [:], hasUnread: false, mentionCount: 0)
            guard let createdSpace = matrixStore.roomId(for: server) else { throw AccountError.invalidResponse }
            spaceId = createdSpace
            pending[guild.id] = spaceId
            UserDefaults.standard.set(pending, forKey: recoveryKey)
        }
        // Record the actual Matrix room ID immediately so icon failure cannot duplicate a server.
        try await client.upsertGuild(guild, importedSpaceId: spaceId)
        importedGuildIds.insert(guild.id)
        pending.removeValue(forKey: guild.id)
        UserDefaults.standard.set(pending, forKey: recoveryKey)
        if let imageURL = guild.iconURL {
            let data = try await DiscordSync.imageData(from: imageURL)
            matrixStore.errorMessage = nil
            await matrixStore.updateServerIcon(server, imageData: data, filename: "discord-\(guild.id).png")
            if let error = matrixStore.errorMessage { throw AccountError.server(error) }
        }
    }

    func applyDiscordProfile(matrixStore: MatrixStore) async throws {
        guard let discord else { throw AccountError.invalidResponse }
        matrixStore.errorMessage = nil
        await matrixStore.updateDisplayName(discord.displayName)
        if let error = matrixStore.errorMessage { throw AccountError.server(error) }
        if let url = discord.avatarURL {
            let data = try await DiscordSync.imageData(from: url)
            await matrixStore.updateAvatar(imageData: data, filename: "discord-avatar.png")
            if let error = matrixStore.errorMessage { throw AccountError.server(error) }
        }
    }

    func signOut() async {
        OnboardingModel.discardProgress(for: session?.user.id.uuidString)
        cancelPasswordRecovery()
        cancelPendingConfirmation()
        if let client { try? await client.signOut() }
        matrixReady = false
        provisioningError = nil
        session = nil
        profile = nil
        discord = nil
        guilds = []
        importedGuildIds = []
        showGuildImporter = false
    }

    // MARK: - Password reset

    private(set) var isRecoveringPassword = false
    private(set) var recoveryEmail: String?
    private var recoverySession: SupabaseSession?
    var hasRecoverySession: Bool { recoverySession != nil }

    func beginPasswordRecovery() {
        guard !isLoading else { return }
        cancelPendingConfirmation()
        recoveryEmail = nil
        recoverySession = nil
        errorMessage = nil
        isRecoveringPassword = true
    }

    func cancelPasswordRecovery() {
        guard !isLoading else { return }
        isRecoveringPassword = false
        recoveryEmail = nil
        recoverySession = nil
        errorMessage = nil
    }

    func sendRecoveryCode(email: String) async throws {
        guard !isLoading else { return }
        guard let client else { throw AccountError.notConfigured }
        isLoading = true
        defer { isLoading = false }
        let address = email.trimmingCharacters(in: .whitespacesAndNewlines)
        try await client.requestPasswordRecovery(email: address)
        recoveryEmail = address
        recoverySession = nil
        isRecoveringPassword = true
    }

    func finishPasswordRecovery(code: String, password: String, confirmation: String) async throws {
        guard !isLoading else { return }
        guard let client else { throw AccountError.notConfigured }
        guard AccountValidation.isValidPassword(password) else { throw AccountError.server("Le mot de passe doit contenir au moins 8 caractères.") }
        guard password == confirmation else { throw AccountError.server("Les mots de passe ne correspondent pas.") }
        isLoading = true
        defer { isLoading = false }
        if recoverySession == nil {
            guard let email = recoveryEmail else { throw AccountError.invalidResponse }
            recoverySession = try await client.verifyEmailCode(email: email, token: code, type: .recovery)
        }
        guard let recovered = recoverySession else { throw AccountError.invalidResponse }
        let updated = try await client.resetPassword(password, recoverySession: recovered)
        client.store(updated)
        session = updated
        recoverySession = nil
        recoveryEmail = nil
        isRecoveringPassword = false
        matrixReady = false
        errorMessage = nil
        try? await loadProfile()
    }

    func confirmSignup(code: String, email address: String? = nil) async throws {
        guard !isLoading else { return }
        guard let client, let email = address ?? pendingConfirmationEmail else { throw AccountError.invalidResponse }
        isLoading = true
        defer { isLoading = false }
        let confirmed = try await client.verifyEmailCode(email: email, token: code, type: .signup)
        client.store(confirmed)
        session = confirmed
        cancelPendingConfirmation()
        matrixReady = false
        errorMessage = nil
        try? await loadProfile()
    }

    /// Deterministic screenshots only; no network calls, passwords or persisted sessions.
    func prepareAuthPreview() {
        guard AccountAuthPreview.enabled else { return }
        switch AccountAuthPreview.screen {
        case "signup": pendingConfirmationEmail = "demo@example.invalid"
        case "code": isRecoveringPassword = true; recoveryEmail = "demo@example.invalid"
        case "link":
            isRecoveringPassword = true
            recoverySession = SupabaseSession(accessToken: "synthetic", refreshToken: "synthetic", expiresIn: 3600,
                user: SupabaseUser(id: UUID(), email: "demo@example.invalid", userMetadata: nil))
        case "recover": beginPasswordRecovery()
        default: break
        }
    }

    // MARK: - Account features

    func updateCredentials(email: String? = nil, password: String? = nil, nonce: String? = nil) async throws {
        guard let client, let old = session else { throw AccountError.notConfigured }
        if let email, !AccountValidation.isValidEmail(email) { throw AccountError.server("Entre une adresse e-mail valide.") }
        if let password, !AccountValidation.isValidPassword(password) { throw AccountError.server("Le mot de passe doit contenir au moins 8 caractères.") }
        let user = try await client.updateAccount(email: email, password: password, nonce: nonce)
        session = SupabaseSession(accessToken: old.accessToken, refreshToken: old.refreshToken,
                                  expiresIn: old.expiresIn, user: user, providerToken: old.providerToken)
    }

    func requestReauthentication() async throws {
        guard let client else { throw AccountError.notConfigured }
        try await client.requestReauthentication()
    }

    // MARK: - Finish basics

    /// Exact authenticated lookup; saving still arbitrates races and unlinked reserved profiles.
    func isUsernameAvailable(_ username: String) async throws -> Bool {
        guard MoodUsername.isValid(username) else { throw AccountError.server(MoodUsername.rule) }
        guard let client, isSignedIn else { throw AccountError.notConfigured }
        let owner = try await client.findUser(username: username)
        guard let owner else { return true }
        // Provisioning may have linked this profile after OTP loaded the first snapshot.
        try await loadProfile()
        return owner == profile?.matrixUserId && profile?.username == username
    }

    func setUsername(_ username: String) async throws {
        guard MoodUsername.isValid(username) else { throw AccountError.server(MoodUsername.rule) }
        guard let client, isSignedIn else { throw AccountError.notConfigured }
        try await client.setUsername(username)
        try await loadProfile()
    }

    /// Only our own handle is known; never substitute a Matrix localpart for a Mood username.
    func moodUsername(for user: MoodUser, currentUserId: String?) -> String? {
        if user.matrixId == currentUserId, currentUserId != nil { return profile?.username }
        if ProcessInfo.processInfo.arguments.contains("-uiPreview"), user.id == MockData.currentUser.id {
            return "augustin"
        }
        return nil
    }

}
