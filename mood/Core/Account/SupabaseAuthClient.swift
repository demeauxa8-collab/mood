import AuthenticationServices
import CryptoKit
import Foundation
import UIKit

struct SupabaseUser: Codable, Sendable {
    let id: UUID
    let email: String?
    let userMetadata: [String: AnyCodable]?
    enum CodingKeys: String, CodingKey { case id, email; case userMetadata = "user_metadata" }
}

struct SupabaseSession: Codable, Sendable {
    let accessToken: String
    let refreshToken: String
    let expiresIn: Int
    let user: SupabaseUser
    var providerToken: String? = nil
    enum CodingKeys: String, CodingKey { case accessToken = "access_token", refreshToken = "refresh_token", expiresIn = "expires_in", user; case providerToken = "provider_token" }
}

struct DiscordGuild: Codable, Identifiable, Sendable {
    let id: String
    let name: String
    let icon: String?
    var iconURL: URL? { icon.flatMap { URL(string: "https://cdn.discordapp.com/icons/\(id)/\($0).png?size=128") } }
}

struct DiscordIdentity: Codable, Sendable {
    let id: String
    let username: String
    let globalName: String?
    let avatar: String?
    let banner: String?
    let accentColor: Int?
    enum CodingKeys: String, CodingKey { case id, username, avatar, banner; case globalName = "global_name"; case accentColor = "accent_color" }
    var displayName: String { globalName ?? username }
    var avatarURL: URL? { avatar.flatMap { URL(string: "https://cdn.discordapp.com/avatars/\(id)/\($0).png?size=256") } }
}

enum AccountError: LocalizedError {
    case notConfigured, invalidResponse, server(String), noMatrixLink, emailConfirmationRequired, usernameTaken
    var errorDescription: String? {
        switch self {
        case .emailConfirmationRequired: "Confirme ton e-mail, puis reviens dans Mood."
        case .usernameTaken: "Ce nom d'utilisateur est déjà pris."
        case .notConfigured: "Supabase n'est pas configuré."
        case .invalidResponse: "Réponse invalide du serveur."
        case .server(let message): message
        case .noMatrixLink: "Relie d'abord un compte Matrix."
        }
    }
}

@MainActor
final class SupabaseAuthClient: NSObject, ASWebAuthenticationPresentationContextProviding {
    static let redirectURI = "mood://auth-callback"
    let baseURL: URL
    let anonKey: String
    private let urlSession: URLSession
    private let persistsSession: Bool
    private var refreshTask: Task<SupabaseSession, Error>?
    private var webSession: ASWebAuthenticationSession?

    // MARK: - Session storage
    // Unsigned builds cannot write to the keychain (no entitlements), which broke every call after
    // sign-in. Values are kept in memory first; KeychainHelper persists them across launches (the
    // keychain, or its private-file fallback on unsigned builds).
    private var sessionCache: [String: String] = [:]

    private func saveSecret(_ key: String, value: String) {
        sessionCache[key] = value
        if persistsSession { KeychainHelper.save(key: key, value: value) }
    }

    private func loadSecret(_ key: String) -> String? {
        sessionCache[key] ?? (persistsSession ? KeychainHelper.load(key: key) : nil)
    }

    private func deleteSecret(_ key: String) {
        sessionCache.removeValue(forKey: key)
        if persistsSession { KeychainHelper.delete(key: key) }
    }

    init?(info: [String: Any] = Bundle.main.infoDictionary ?? [:], urlSession: URLSession = .shared, initialSession: SupabaseSession? = nil, persistsSession: Bool = true) {
        guard let rawURL = info["MoodSupabaseURL"] as? String, let url = URL(string: rawURL),
              let key = info["MoodSupabaseAnonKey"] as? String,
              url.scheme == "https", url.host != nil, !rawURL.contains("$("), !key.isEmpty, !key.contains("$("), !key.contains("your-supabase") else { return nil }
        baseURL = url; anonKey = key
        self.urlSession = urlSession
        self.persistsSession = persistsSession
        super.init()
        if let initialSession {
            if let data = try? JSONEncoder().encode(initialSession.user) {
                sessionCache["supabase.user"] = String(decoding: data, as: UTF8.self)
            }
            sessionCache["supabase.access_token"] = initialSession.accessToken
            sessionCache["supabase.expires_at"] = String(Date().timeIntervalSince1970 + Double(initialSession.expiresIn))
        }
    }

    nonisolated static func pkcePair(verifier: String? = nil) -> (verifier: String, challenge: String) {
        let value = verifier ?? Data((0..<32).map { _ in UInt8.random(in: 0...255) }).base64URL
        let digest = SHA256.hash(data: Data(value.utf8))
        return (value, Data(digest).base64URL)
    }

    nonisolated static func authorizationURL(baseURL: URL, challenge: String, redirectURI: String = "mood://auth-callback") -> URL? {
        var components = URLComponents(url: baseURL.appendingPathComponent("auth/v1/authorize"), resolvingAgainstBaseURL: false)
        components?.queryItems = [URLQueryItem(name: "provider", value: "discord"), URLQueryItem(name: "redirect_to", value: redirectURI), URLQueryItem(name: "code_challenge", value: challenge), URLQueryItem(name: "code_challenge_method", value: "s256"), URLQueryItem(name: "scopes", value: "identify email guilds")]
        return components?.url
    }

    nonisolated static func shouldRefresh(expiresAt: TimeInterval, now: TimeInterval) -> Bool { expiresAt <= now + 60 }

    func signUp(email: String, password: String) async throws -> SupabaseSession {
        let data = try await request("auth/v1/signup?redirect_to=mood%3A%2F%2Fauth-callback", method: "POST", bearer: nil, body: ["email": email, "password": password, "email_redirect_to": Self.redirectURI])
        guard let session = try? JSONDecoder().decode(SupabaseSession.self, from: data) else {
            _ = try JSONDecoder().decode(SupabaseUser.self, from: data)
            throw AccountError.emailConfirmationRequired
        }
        store(session)
        return session
    }
    func resendConfirmation(email: String) async throws {
        try await request("auth/v1/resend?redirect_to=mood%3A%2F%2Fauth-callback", method: "POST", bearer: nil,
                          body: ["type": "signup", "email": email])
    }
    func signIn(email: String, password: String) async throws -> SupabaseSession { try await auth("auth/v1/token?grant_type=password", body: ["email": email, "password": password]) }
    func refresh(refreshToken: String) async throws -> SupabaseSession { try await auth("auth/v1/token?grant_type=refresh_token", body: ["refresh_token": refreshToken]) }

    func restoreSession() async throws -> SupabaseSession? {
        guard let refresh = loadSecret("supabase.refresh_token") else { return nil }
        let expiry = Double(loadSecret("supabase.expires_at") ?? "0") ?? 0
        if !Self.shouldRefresh(expiresAt: expiry, now: Date().timeIntervalSince1970),
           let access = loadSecret("supabase.access_token"),
           let raw = loadSecret("supabase.user"), let data = raw.data(using: .utf8),
           let user = try? JSONDecoder().decode(SupabaseUser.self, from: data) {
            return SupabaseSession(accessToken: access, refreshToken: refresh, expiresIn: Int(expiry - Date().timeIntervalSince1970), user: user)
        }
        let session = try await self.refresh(refreshToken: refresh); store(session); return session
    }

    func store(_ session: SupabaseSession) {
        if let raw = loadSecret("supabase.user")?.data(using: .utf8),
           let previous = try? JSONDecoder().decode(SupabaseUser.self, from: raw), previous.id != session.user.id {
            deleteSecret("supabase.provider_token")
        }
        if let token = session.providerToken { saveSecret("supabase.provider_token", value: token) }
        saveSecret("supabase.access_token", value: session.accessToken)
        saveSecret("supabase.refresh_token", value: session.refreshToken)
        saveSecret("supabase.expires_at", value: String(Date().timeIntervalSince1970 + Double(session.expiresIn)))
        if let data = try? JSONEncoder().encode(session.user), let value = String(data: data, encoding: .utf8) { saveSecret("supabase.user", value: value) }
    }

    func clear() { ["supabase.access_token", "supabase.refresh_token", "supabase.expires_at", "supabase.user", "supabase.provider_token"].forEach { deleteSecret($0) } }
    func signOut() async throws {
        let access = loadSecret("supabase.access_token")
        clear()
        guard let access else { return }
        _ = try await request("auth/v1/logout", method: "POST", bearer: access)
    }

    func discordLogin(expectedUserId: UUID? = nil) async throws -> SupabaseSession {
        guard webSession == nil else { throw AccountError.server("Une connexion Discord est déjà en cours.") }
        defer { webSession = nil }
        let pair = Self.pkcePair()
        guard let url = Self.authorizationURL(baseURL: baseURL, challenge: pair.challenge) else { throw AccountError.invalidResponse }
        let callback: URL = try await withCheckedThrowingContinuation { continuation in
            let session = ASWebAuthenticationSession(url: url, callbackURLScheme: "mood") { url, error in
                if let error { continuation.resume(throwing: error) }
                else if let url { continuation.resume(returning: url) }
                else { continuation.resume(throwing: AccountError.invalidResponse) }
            }
            session.presentationContextProvider = self; session.prefersEphemeralWebBrowserSession = false; webSession = session
            if !session.start() { continuation.resume(throwing: AccountError.invalidResponse) }
        }
        guard callback.scheme == "mood", callback.host == "auth-callback",
              let components = URLComponents(url: callback, resolvingAgainstBaseURL: false),
              let code = components.queryItems?.first(where: { $0.name == "code" })?.value else { throw AccountError.invalidResponse }
        let data = try await request("auth/v1/token?grant_type=pkce", method: "POST", bearer: nil, body: ["auth_code": code, "code_verifier": pair.verifier])
        let session = try JSONDecoder().decode(SupabaseSession.self, from: data)
        if let expectedUserId, session.user.id != expectedUserId {
            throw AccountError.server("Utilise le compte Discord associé à la même adresse e-mail que ton compte Mood.")
        }
        store(session)
        return session
    }

    func matrixSession(deviceId: String, deviceName: String) async throws -> MoodMatrixSession {
        let data = try await request("functions/v1/matrix-session", method: "POST",
                                     bearer: validAccessToken(),
                                     body: ["device_id": deviceId, "device_name": deviceName])
        return try JSONDecoder().decode(MoodMatrixSession.self, from: data)
    }

    func completeEmailCallback(_ url: URL, persist: Bool = true) async throws -> SupabaseSession {
        guard url.scheme == "mood", url.host == "auth-callback" else { throw AccountError.invalidResponse }
        let items = URLComponents(string: "https://callback.invalid/?" + (url.fragment ?? ""))?.queryItems ?? []
        guard let access = items.first(where: { $0.name == "access_token" })?.value,
              let refresh = items.first(where: { $0.name == "refresh_token" })?.value else {
            throw AccountError.server("E-mail confirmé. Connecte-toi à Mood avec ton e-mail et ton mot de passe.")
        }
        let data = try await request("auth/v1/user", method: "GET", bearer: access)
        let user = try JSONDecoder().decode(SupabaseUser.self, from: data)
        let expiry = Int(items.first(where: { $0.name == "expires_in" })?.value ?? "3600") ?? 3600
        let session = SupabaseSession(accessToken: access, refreshToken: refresh, expiresIn: expiry, user: user)
        if persist { store(session) }
        return session
    }

    func discordIdentity() async throws -> DiscordIdentity {
        guard let token = loadSecret("supabase.provider_token") else { throw AccountError.invalidResponse }
        return try await DiscordSync.get("users/@me", token: token)
    }

    func discordGuilds() async throws -> [DiscordGuild] {
        guard let token = loadSecret("supabase.provider_token") else { throw AccountError.invalidResponse }
        return try await DiscordSync.get("users/@me/guilds", token: token)
    }

    func upsertGuild(_ guild: DiscordGuild, importedSpaceId: String?) async throws {
        let token = try await validAccessToken()
        guard let data = loadSecret("supabase.user")?.data(using: .utf8), let user = try? JSONDecoder().decode(SupabaseUser.self, from: data) else { throw AccountError.invalidResponse }
        var row: [String: Any] = ["user_id": user.id.uuidString, "guild_id": guild.id, "name": guild.name]
        row["icon_url"] = guild.iconURL?.absoluteString as Any? ?? NSNull()
        row["imported_space_id"] = importedSpaceId as Any? ?? NSNull()
        _ = try await request("rest/v1/discord_guilds_import?on_conflict=user_id,guild_id", method: "POST", bearer: token, body: row, prefer: "resolution=merge-duplicates")
    }

    func matrixLink() async throws -> (String?, String?) {
        let token = try await validAccessToken()
        guard let data = loadSecret("supabase.user")?.data(using: .utf8), let user = try? JSONDecoder().decode(SupabaseUser.self, from: data) else { return (nil, nil) }
        let rows: [[String: String?]] = try await JSONDecoder().decode([[String: String?]].self, from: request("rest/v1/profiles?select=matrix_user_id,matrix_homeserver&id=eq.\(user.id.uuidString)", method: "GET", bearer: token))
        return (rows.first?["matrix_user_id"] ?? nil, rows.first?["matrix_homeserver"] ?? nil)
    }

    func profile() async throws -> AccountProfile {
        let token = try await validAccessToken()
        guard let raw = loadSecret("supabase.user")?.data(using: .utf8) else { throw AccountError.invalidResponse }
        let user = try JSONDecoder().decode(SupabaseUser.self, from: raw)
        let data = try await request("rest/v1/profiles?id=eq.\(user.id.uuidString)&select=*", method: "GET", bearer: token)
        guard let profile = try JSONDecoder().decode([AccountProfile].self, from: data).first else {
            throw AccountError.server("Profil Mood absent. Vérifie la migration des comptes.")
        }
        return profile
    }

    func saveDiscordProfile(_ identity: DiscordIdentity) async throws {
        try await patchProfile(["discord_id": identity.id, "discord_username": identity.username,
                                "discord_avatar_url": identity.avatarURL?.absoluteString as Any? ?? NSNull(),
                                "display_name": identity.displayName, "avatar_url": identity.avatarURL?.absoluteString as Any? ?? NSNull()])
    }

    func unlinkDiscord() async throws {
        let token = try await validAccessToken()
        let data = try await request("auth/v1/user", method: "GET", bearer: token)
        let identities = try JSONDecoder().decode(IdentityList.self, from: data).identities
        guard identities.count > 1 else { throw AccountError.server("Ajoute un autre moyen de connexion avant de délier Discord.") }
        if let discord = identities.first(where: { $0.provider == "discord" }) {
            _ = try await request("auth/v1/user/identities/\(discord.identityId)", method: "DELETE", bearer: token)
        }
        try await patchProfile(["discord_id": NSNull(), "discord_username": NSNull(), "discord_avatar_url": NSNull()])
        deleteSecret("supabase.provider_token")
    }

    private func patchProfile(_ values: [String: Any]) async throws {
        let profile = try await profile()
        let data = try await request("rest/v1/profiles?id=eq.\(profile.id.uuidString)", method: "PATCH", bearer: validAccessToken(), body: values, prefer: "return=representation")
        guard !(try JSONDecoder().decode([AccountProfile].self, from: data)).isEmpty else { throw AccountError.invalidResponse }
    }

    func importedGuilds() async throws -> [GuildImport] {
        let data = try await request("rest/v1/discord_guilds_import?select=guild_id,imported_space_id", method: "GET", bearer: validAccessToken())
        return try JSONDecoder().decode([GuildImport].self, from: data)
    }

    private func validAccessToken() async throws -> String {
        let expiry = Double(loadSecret("supabase.expires_at") ?? "0") ?? 0
        if Self.shouldRefresh(expiresAt: expiry, now: Date().timeIntervalSince1970), let refreshToken = loadSecret("supabase.refresh_token") {
            if let refreshTask { return try await refreshTask.value.accessToken }
            let task = Task { try await self.refresh(refreshToken: refreshToken) }
            refreshTask = task
            defer { refreshTask = nil }
            return try await task.value.accessToken
        }
        guard let token = loadSecret("supabase.access_token") else { throw AccountError.invalidResponse }
        return token
    }

    private func auth(_ path: String, body: [String: Any]) async throws -> SupabaseSession {
        let data = try await request(path, method: "POST", bearer: nil, body: body)
        let session = try JSONDecoder().decode(SupabaseSession.self, from: data); store(session); return session
    }

    /// Exact Mood username → Matrix user id, through the `find_user_by_username` RPC (no listing).
    func findUser(username: String) async throws -> String? {
        struct Row: Decodable { let matrix_user_id: String? }
        let data = try await request("rest/v1/rpc/find_user_by_username", method: "POST",
                                     bearer: validAccessToken(), body: ["p_username": username])
        return try JSONDecoder().decode([Row].self, from: data).first?.matrix_user_id
    }

    /// Sign-in providers enabled on the project, from the public `auth/v1/settings` (e.g. ["email"]).
    func enabledProviders() async throws -> Set<String> {
        let data = try await request("auth/v1/settings", method: "GET", bearer: nil)
        let external = (try JSONSerialization.jsonObject(with: data) as? [String: Any])?["external"] as? [String: Any] ?? [:]
        return Set(external.compactMap { key, value in (value as? Bool) == true ? key : nil })
    }

    @discardableResult private func request(_ path: String, method: String, bearer: String?, body: Any? = nil, prefer: String? = nil) async throws -> Data {
        guard let url = URL(string: path, relativeTo: baseURL) else { throw AccountError.invalidResponse }
        var request = URLRequest(url: url); request.httpMethod = method; request.setValue(anonKey, forHTTPHeaderField: "apikey")
        if let bearer { request.setValue("Bearer \(bearer)", forHTTPHeaderField: "Authorization") }
        if let body { request.setValue("application/json", forHTTPHeaderField: "Content-Type"); request.httpBody = try JSONSerialization.data(withJSONObject: body) }
        if let prefer { request.setValue(prefer, forHTTPHeaderField: "Prefer") }
        let (data, response) = try await urlSession.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw AccountError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else {
            if path == "functions/v1/matrix-session" { throw MoodProvisioningError.http(http.statusCode) }
            if method == "PATCH", path.hasPrefix("rest/v1/profiles") {
                let code = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["code"] as? String
                if http.statusCode == 409 || code == "23505" { throw AccountError.usernameTaken }
                if let friendly = MoodUsername.updateError(status: http.statusCode, code: code) {
                    throw AccountError.server(friendly)
                }
            }
            let message = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["msg"] as? String ?? (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["message"] as? String ?? "Erreur Supabase (\(http.statusCode))."
            let code = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["code"] as? String
                ?? (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["error_code"] as? String
            throw AccountError.server(Self.frenchMessage(for: message, code: code, status: http.statusCode))
        }
        return data
    }

    /// Supabase Auth answers in English; the ones people actually meet, in French.
    nonisolated static func frenchMessage(for message: String, code: String? = nil, status: Int? = nil) -> String {
        let lower = message.lowercased()
        if status == 429 || code?.contains("rate_limit") == true || lower.contains("too many") || lower.contains("security purposes") { return "Trop de tentatives. Réessaie dans quelques minutes." }
        if code == "otp_expired" || code == "otp_disabled" || lower.contains("token has expired") || lower.contains("invalid otp") || lower.contains("invalid token") || lower.contains("otp expired") {
            return "Ce code ou ce lien est invalide ou expiré. Demande un nouveau code."
        }
        if code == "weak_password" || lower.contains("password should be at least") { return "Le mot de passe doit contenir au moins 8 caractères et respecter les règles du serveur." }
        if code == "same_password" || lower.contains("different from the old password") { return "Choisis un mot de passe différent de l’ancien." }
        if code == "session_not_found" || code == "bad_jwt" { return "Ce lien a expiré. Demande un nouveau code." }
        if lower.contains("email not confirmed") { return "Ton adresse n'est pas encore confirmée : ouvre le lien reçu par e-mail." }
        if lower.contains("invalid login credentials") { return "E-mail ou mot de passe incorrect." }
        if lower.contains("already registered") { return "Un compte existe déjà avec cette adresse : connecte-toi." }
        if lower.contains("rate limit") { return "Trop de tentatives. Réessaie dans quelques minutes." }
        return message
    }

    // MARK: - Password reset and confirmation codes

    func requestPasswordRecovery(email: String) async throws {
        guard AccountValidation.isValidEmail(email) else { throw AccountError.server("Entre une adresse e-mail valide.") }
        try await request("auth/v1/recover?redirect_to=mood%3A%2F%2Fauth-callback", method: "POST", bearer: nil, body: ["email": email])
    }

    enum EmailCodeType: String { case recovery, signup }

    /// Recovery sessions remain in memory until the password has actually changed.
    func verifyEmailCode(email: String, token: String, type: EmailCodeType) async throws -> SupabaseSession {
        guard AccountValidation.isValidEmail(email), AccountValidation.isValidEmailCode(token) else {
            throw AccountError.server("Entre le code à 6 chiffres reçu par e-mail.")
        }
        let data = try await request("auth/v1/verify", method: "POST", bearer: nil,
                                     body: ["type": type.rawValue, "email": email, "token": token])
        return try JSONDecoder().decode(SupabaseSession.self, from: data)
    }

    func resetPassword(_ password: String, recoverySession: SupabaseSession) async throws -> SupabaseSession {
        guard AccountValidation.isValidPassword(password) else {
            throw AccountError.server("Le mot de passe doit contenir au moins 8 caractères.")
        }
        let data = try await request("auth/v1/user", method: "PUT", bearer: recoverySession.accessToken, body: ["password": password])
        let user = try JSONDecoder().decode(SupabaseUser.self, from: data)
        return SupabaseSession(accessToken: recoverySession.accessToken, refreshToken: recoverySession.refreshToken,
                               expiresIn: recoverySession.expiresIn, user: user)
    }

    nonisolated static func isRecoveryCallback(_ url: URL) -> Bool {
        guard url.scheme == "mood", url.host == "auth-callback" else { return false }
        return URLComponents(string: "https://callback.invalid/?" + (url.fragment ?? ""))?.queryItems?
            .contains { $0.name == "type" && $0.value == "recovery" } == true
    }

    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor { UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first?.windows.first ?? ASPresentationAnchor() }
    // MARK: - Account features

    func updateAccount(email: String? = nil, password: String? = nil, nonce: String? = nil) async throws -> SupabaseUser {
        var body: [String: Any] = [:]
        if let email { body["email"] = email }
        if let password { body["password"] = password }
        if let nonce { body["nonce"] = nonce }
        let path = email == nil ? "auth/v1/user" : "auth/v1/user?redirect_to=mood%3A%2F%2Fauth-callback"
        let data = try await request(path, method: "PUT", bearer: validAccessToken(), body: body)
        let user = try JSONDecoder().decode(SupabaseUser.self, from: data)
        if let data = try? JSONEncoder().encode(user), let value = String(data: data, encoding: .utf8) {
            saveSecret("supabase.user", value: value)
        }
        return user
    }

    func requestReauthentication() async throws {
        _ = try await request("auth/v1/reauthenticate", method: "GET", bearer: validAccessToken())
    }

    // MARK: - Finish basics

    func setUsername(_ username: String) async throws {
        guard MoodUsername.isValid(username) else { throw AccountError.server(MoodUsername.rule) }
        try await patchProfile(["username": username])
    }

}

nonisolated private extension Data {
    var base64URL: String { base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "") }

}
