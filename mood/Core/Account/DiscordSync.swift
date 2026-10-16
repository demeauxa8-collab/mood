import Foundation

/// Discord OAuth exposes identity and guild metadata, never friends or messages.
enum DiscordSync {
    static func get<T: Decodable>(_ path: String, token: String) async throws -> T {
        guard let url = URL(string: "https://discord.com/api/v10/\(path)") else { throw AccountError.invalidResponse }
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw AccountError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else {
            throw AccountError.server("Discord ne répond pas (\(http.statusCode)). Reconnecte Discord si son autorisation a expiré.")
        }
        return try JSONDecoder().decode(T.self, from: data)
    }

    static func imageData(from url: URL) async throws -> Data {
        let (data, response) = try await URLSession.shared.data(from: url)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
              http.mimeType?.hasPrefix("image/") == true else { throw AccountError.invalidResponse }
        return data
    }
}
