import Foundation

// MARK: - Content URI

/// A parsed `mxc://<server-name>/<media-id>` URI.
/// Both parts are validated so a hostile event cannot smuggle `..` or a query into the media path.
nonisolated struct MatrixContentURI: Equatable, Sendable {
    let serverName: String
    let mediaId: String

    init?(_ string: String) {
        guard string.hasPrefix("mxc://") else { return nil }
        let rest = string.dropFirst(6)
        guard let slash = rest.firstIndex(of: "/") else { return nil }
        let server = String(rest[..<slash])
        let media = String(rest[rest.index(after: slash)...])
        guard Self.isValidServerName(server), Self.isValidMediaId(media) else { return nil }
        serverName = server
        mediaId = media
    }

    var string: String { "mxc://\(serverName)/\(mediaId)" }

    /// Media ids are opaque but the spec restricts them to `[A-Za-z0-9_-]`.
    static func isValidMediaId(_ id: String) -> Bool {
        !id.isEmpty && id.unicodeScalars.allSatisfy { scalar in
            CharacterSet.alphanumerics.contains(scalar) && scalar.isASCII || scalar == "_" || scalar == "-"
        }
    }

    /// host, host:port, IPv4 or [IPv6]:port — nothing that changes the URL path.
    static func isValidServerName(_ name: String) -> Bool {
        guard !name.isEmpty, name.count <= 255 else { return false }
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789.-:[]")
        return name.unicodeScalars.allSatisfy(allowed.contains)
    }
}

// MARK: - Endpoints (authenticated v1, legacy v3 fallback)

/// Spec v1.11 moved media behind authentication: `/_matrix/client/v1/media/...` with a Bearer token.
/// Continuwuity refuses the legacy unauthenticated `/_matrix/media/v3/...` routes, older servers only
/// know those, so URLs are built for v1 and `MediaLoader` falls back to v3 once per host if needed.
nonisolated enum MatrixMediaEndpoint {
    static let authenticatedPrefix = "/_matrix/client/v1/media/"
    static let legacyPrefix = "/_matrix/media/v3/"

    static func downloadURL(for mxc: String, homeserver: URL, legacy: Bool = false) -> URL? {
        guard let uri = MatrixContentURI(mxc) else { return nil }
        return url(homeserver: homeserver, path: "\(legacy ? legacyPrefix : authenticatedPrefix)download/\(uri.serverName)/\(uri.mediaId)")
    }

    /// `method` is "crop" (avatars, exact square) or "scale" (message previews, keeps the aspect ratio).
    static func thumbnailURL(for mxc: String, homeserver: URL, width: Int, height: Int,
                             method: String = "crop", legacy: Bool = false) -> URL? {
        guard let uri = MatrixContentURI(mxc), width > 0, height > 0 else { return nil }
        return url(homeserver: homeserver,
                   path: "\(legacy ? legacyPrefix : authenticatedPrefix)thumbnail/\(uri.serverName)/\(uri.mediaId)",
                   query: [
                    URLQueryItem(name: "width", value: String(width)),
                    URLQueryItem(name: "height", value: String(height)),
                    URLQueryItem(name: "method", value: method == "scale" ? "scale" : "crop")
                   ])
    }

    /// The same request on the legacy v3 route, or nil if `url` is not an authenticated media URL.
    static func legacyEquivalent(of url: URL) -> URL? {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              components.percentEncodedPath.hasPrefix(authenticatedPrefix) else { return nil }
        let rest = components.percentEncodedPath.dropFirst(authenticatedPrefix.count)
        components.percentEncodedPath = legacyPrefix + rest
        return components.url
    }

    static func isAuthenticatedMediaURL(_ url: URL) -> Bool {
        url.path.hasPrefix(authenticatedPrefix)
    }

    /// A server without v1 media answers 404/400 `M_UNRECOGNIZED`, 405, or a bare 404 from its proxy.
    /// A real "this media does not exist" is 404 `M_NOT_FOUND` and must not trigger the fallback.
    static func shouldFallBackToLegacy(statusCode: Int, errcode: String?) -> Bool {
        if errcode == "M_UNRECOGNIZED" { return true }
        if statusCode == 405 { return true }
        return statusCode == 404 && errcode == nil
    }

    /// The access token only ever goes to the homeserver itself (same scheme, host and port).
    static func shouldAuthorize(_ url: URL, homeserver: URL?) -> Bool {
        guard let homeserver, let host = url.host?.lowercased(), let homeHost = homeserver.host?.lowercased(),
              url.scheme?.lowercased() == "https", homeserver.scheme?.lowercased() == "https" else { return false }
        return host == homeHost && (url.port ?? 443) == (homeserver.port ?? 443)
    }

    private static func url(homeserver: URL, path: String, query: [URLQueryItem]? = nil) -> URL? {
        guard var components = URLComponents(url: homeserver, resolvingAgainstBaseURL: false) else { return nil }
        // Server names and media ids are validated above, so the path needs no escaping
        // (and must not be escaped twice: a ":port" server name is legal in the path).
        components.percentEncodedPath = path
        components.queryItems = query
        return components.url
    }
}

// MARK: - Upload limits

nonisolated enum MediaUploadLimits {
    /// 25 Mo, the server's `max_request_size` (26 214 400 bytes) and Discord's free-tier limit.
    static let maxBytes = 25 * 1024 * 1024

    static func formatted(_ bytes: Int) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .binary
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        return formatter.string(fromByteCount: Int64(bytes))
    }

    static func tooLargeMessage(size: Int, limit: Int = maxBytes) -> String {
        "Ce fichier est trop volumineux (\(formatted(size))). La limite est de \(formatted(limit))."
    }
}

// MARK: - Image resize plan

/// What happens to a picked image before upload: kept as is, or re-encoded (≤ 2560 px, JPEG 0.85).
/// HEIC and other formats other clients may not decode always become JPEG (PNG when transparent).
nonisolated struct ImageUploadPlan: Equatable, Sendable {
    enum Output: String, Equatable, Sendable {
        case original, jpeg, png

        var mimeType: String? {
            switch self {
            case .original: nil
            case .jpeg: "image/jpeg"
            case .png: "image/png"
            }
        }

        var fileExtension: String? {
            switch self {
            case .original: nil
            case .jpeg: "jpg"
            case .png: "png"
            }
        }
    }

    static let maxDimension = 2560
    static let jpegQuality = 0.85
    static let thumbnailBox = (width: 800, height: 600)

    let output: Output
    /// Final size as displayed (EXIF orientation applied).
    let width: Int
    let height: Int

    var needsReencode: Bool { output != .original }

    private static let webSafeTypes: Set<String> = ["public.jpeg", "public.png", "com.compuserve.gif", "org.webmproject.webp"]

    /// - Parameters:
    ///   - typeIdentifier: the source UTType identifier (`public.heic`, `public.jpeg`…).
    ///   - width/height: pixel size *before* orientation.
    ///   - orientation: EXIF orientation (1…8); 5–8 swap width and height.
    static func make(typeIdentifier: String, width: Int, height: Int, orientation: Int = 1,
                     hasAlpha: Bool = false, isAnimated: Bool = false) -> ImageUploadPlan {
        let oriented = orientedSize(width: width, height: height, orientation: orientation)
        // Animations would be flattened by a re-encode: keep them untouched.
        if isAnimated {
            return ImageUploadPlan(output: .original, width: oriented.width, height: oriented.height)
        }
        let tooBig = max(oriented.width, oriented.height) > maxDimension
        let webSafe = webSafeTypes.contains(typeIdentifier)
        guard tooBig || !webSafe else {
            return ImageUploadPlan(output: .original, width: oriented.width, height: oriented.height)
        }
        let target = scaledSize(width: oriented.width, height: oriented.height, maxDimension: maxDimension)
        return ImageUploadPlan(output: hasAlpha ? .png : .jpeg, width: target.width, height: target.height)
    }

    static func orientedSize(width: Int, height: Int, orientation: Int) -> (width: Int, height: Int) {
        (5...8).contains(orientation) ? (height, width) : (width, height)
    }

    /// Aspect-preserving size whose longest side is at most `maxDimension` (never upscales).
    static func scaledSize(width: Int, height: Int, maxDimension: Int) -> (width: Int, height: Int) {
        guard width > 0, height > 0 else { return (max(width, 0), max(height, 0)) }
        let longest = max(width, height)
        guard longest > maxDimension else { return (width, height) }
        let ratio = Double(maxDimension) / Double(longest)
        return (max(1, Int((Double(width) * ratio).rounded())), max(1, Int((Double(height) * ratio).rounded())))
    }

    /// Size of the preview sent as `thumbnail_url`, fitted in 800×600; nil when the image already fits.
    static func thumbnailSize(width: Int, height: Int) -> (width: Int, height: Int)? {
        guard width > 0, height > 0, width > thumbnailBox.width || height > thumbnailBox.height else { return nil }
        let ratio = min(Double(thumbnailBox.width) / Double(width), Double(thumbnailBox.height) / Double(height))
        return (max(1, Int((Double(width) * ratio).rounded())), max(1, Int((Double(height) * ratio).rounded())))
    }
}

// MARK: - Disk cache policy

/// Least-recently-used eviction for the media disk cache (500 Mo, trimmed down to 90 %).
nonisolated enum MediaDiskCachePolicy {
    static let maxBytes: Int64 = 500 * 1024 * 1024
    static let trimTargetBytes: Int64 = 450 * 1024 * 1024

    struct Entry: Equatable, Sendable {
        let name: String
        let size: Int64
        let lastAccess: Date
    }

    /// Names to delete, oldest access first, so the remaining total fits in `target`.
    /// Nothing is evicted while the total is within `limit`.
    static func evictions(_ entries: [Entry], limit: Int64 = maxBytes, target: Int64 = trimTargetBytes) -> [String] {
        var total = entries.reduce(Int64(0)) { $0 + $1.size }
        guard total > limit else { return [] }
        var victims: [String] = []
        for entry in entries.sorted(by: { $0.lastAccess < $1.lastAccess }) where total > target {
            victims.append(entry.name)
            total -= entry.size
        }
        return victims
    }
}

// MARK: - Rate limiting

nonisolated enum MatrixRateLimit {
    /// Longest wait honoured inside one request before giving the error back to the caller.
    static let maxHonouredDelay: TimeInterval = 60

    /// Delay asked by a 429: `retry_after_ms` in the body, else the `Retry-After` header (seconds).
    static func retryAfter(statusCode: Int, headers: [AnyHashable: Any], body: Data?) -> TimeInterval? {
        guard statusCode == 429 else { return nil }
        if let ms = errorField("retry_after_ms", in: body) as? NSNumber, ms.doubleValue >= 0 {
            return ms.doubleValue / 1000
        }
        for (key, value) in headers {
            guard (key as? String)?.caseInsensitiveCompare("Retry-After") == .orderedSame else { continue }
            if let text = value as? String, let seconds = TimeInterval(text.trimmingCharacters(in: .whitespaces)), seconds >= 0 {
                return seconds
            }
        }
        return nil
    }

    /// `errcode` of a Matrix error body, nil for anything that is not one.
    static func errcode(in body: Data?) -> String? {
        errorField("errcode", in: body) as? String
    }

    private static func errorField(_ key: String, in body: Data?) -> Any? {
        guard let body, !body.isEmpty,
              let json = try? JSONSerialization.jsonObject(with: body) as? [String: Any] else { return nil }
        return json[key]
    }
}

// MARK: - Upload helpers

struct MatrixMediaConfigResponse: Codable, Sendable {
    let uploadSize: Int?

    enum CodingKeys: String, CodingKey {
        case uploadSize = "m.upload.size"
    }
}

/// Reports upload progress at most every 1 %, so SwiftUI is not flooded with updates.
nonisolated final class UploadProgressDelegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    private let onProgress: @Sendable (Double) -> Void
    private let lock = NSLock()
    private var lastReported = -1.0

    init(_ onProgress: @escaping @Sendable (Double) -> Void) {
        self.onProgress = onProgress
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didSendBodyData bytesSent: Int64,
                    totalBytesSent: Int64, totalBytesExpectedToSend: Int64) {
        guard totalBytesExpectedToSend > 0 else { return }
        let fraction = min(1, Double(totalBytesSent) / Double(totalBytesExpectedToSend))
        let shouldReport = lock.withLock {
            guard fraction - lastReported >= 0.01 || fraction >= 1 else { return false }
            lastReported = fraction
            return true
        }
        if shouldReport { onProgress(fraction) }
    }
}
