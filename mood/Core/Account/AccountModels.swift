import Foundation

struct AccountProfile: Codable, Sendable {
    let id: UUID
    let displayName: String?
    let avatarURL: String?
    let matrixUserId: String?
    let matrixHomeserver: String?
    let discordId: String?
    let discordUsername: String?
    let discordAvatarURL: String?
    let username: String?

    enum CodingKeys: String, CodingKey {
        case id, username
        case displayName = "display_name", avatarURL = "avatar_url"
        case matrixUserId = "matrix_user_id", matrixHomeserver = "matrix_homeserver"
        case discordId = "discord_id", discordUsername = "discord_username", discordAvatarURL = "discord_avatar_url"
    }
}

struct GuildImport: Decodable {
    let guildId: String
    let importedSpaceId: String?
    enum CodingKeys: String, CodingKey { case guildId = "guild_id", importedSpaceId = "imported_space_id" }
}

struct IdentityList: Decodable {
    let identities: [Identity]
    struct Identity: Decodable {
        let identityId: String
        let provider: String
        enum CodingKeys: String, CodingKey { case identityId = "identity_id", provider }
    }
}
