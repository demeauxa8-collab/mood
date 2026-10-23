import Foundation
import CryptoKit
import ImageIO
import UIKit

// MARK: - Credentials

/// Homeserver and access token for media requests. `MatrixClient` writes them whenever its session
/// changes; `MediaLoader` reads them from its own executor, hence the lock instead of an actor hop.
nonisolated final class MediaCredentials: @unchecked Sendable {
    static let shared = MediaCredentials()

    private let lock = NSLock()
    private var homeserver: URL?
    private var token: String?

    func setHomeserver(_ url: URL?) { lock.withLock { homeserver = url } }
    func setToken(_ token: String?) { lock.withLock { self.token = token } }

    var snapshot: (homeserver: URL?, token: String?) {
        lock.withLock { (homeserver, token) }
    }
}

// MARK: - Memory cache

/// Decoded images, readable synchronously from the main actor so a recycled row
/// shows its avatar on the first frame instead of flashing the placeholder.
nonisolated final class MediaImageCache: @unchecked Sendable {
    private let cache = NSCache<NSString, UIImage>()

    init() {
        cache.totalCostLimit = 96 * 1024 * 1024
        cache.countLimit = 800
    }

    func image(for key: String) -> UIImage? {
        cache.object(forKey: key as NSString)
    }

    func insert(_ image: UIImage, for key: String) {
        // Animated UIImage has no single cgImage. Repeated timing frames share buffers and
        // must count once, otherwise the animation cache either costs zero or overcounts them.
        var seen = Set<ObjectIdentifier>()
        let cost = (image.images ?? [image]).reduce(0) { total, frame in
            guard let cgImage = frame.cgImage, seen.insert(ObjectIdentifier(cgImage)).inserted else { return total }
            return total + cgImage.bytesPerRow * cgImage.height
        }
        cache.setObject(image, forKey: key as NSString, cost: cost)
    }

    func removeAll() {
        cache.removeAllObjects()
    }
}

// MARK: - Redirect guard

/// The Bearer token must never follow a redirect to another origin (a CDN, a proxy).
/// Completion-handler form on purpose: the async variant of this Objective-C delegate method
/// crashes Swift 6.4's SILGen (native-to-foreign thunk) in a full build.
nonisolated final class MediaRedirectGuard: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping @Sendable (URLRequest?) -> Void) {
        guard let original = task.originalRequest?.url, let target = request.url else {
            completionHandler(request)
            return
        }
        let sameOrigin = original.scheme == target.scheme && original.host == target.host && original.port == target.port
        guard !sameOrigin else {
            completionHandler(request)
            return
        }
        var stripped = request
        stripped.setValue(nil, forHTTPHeaderField: "Authorization")
        completionHandler(stripped)
    }
}

// MARK: - Media Loader

/// Authenticated media downloads (spec v1.11) with a memory cache of decoded images and a
/// 500 Mo LRU disk cache in `Caches/Mood/media/`. AsyncImage cannot send an Authorization header,
/// so every Matrix picture in the app goes through here (see `AuthenticatedImage`).
actor MediaLoader {
    nonisolated static let shared = MediaLoader()
    /// Message previews are shown at most 400×300 pt (×1.3 on Mac, ×2–3 retina).
    nonisolated static let defaultMaxPixelSize: CGFloat = 1600

    enum LoadError: LocalizedError {
        case http(status: Int, errcode: String?)
        case undecodable

        var errorDescription: String? {
            switch self {
            case .http(401, _), .http(403, _): "Accès au fichier refusé."
            case .http(404, _): "Ce fichier n'existe plus sur le serveur."
            case .http(let status, _): "Téléchargement impossible (erreur \(status))."
            case .undecodable: "Ce fichier n'est pas une image lisible."
            }
        }
    }

    nonisolated let images = MediaImageCache()

    private let session: URLSession
    private let directory: URL?
    private var diskUsage: Int64?
    /// Hosts that answered "unrecognized" to v1 media: go straight to v3 for them.
    private var legacyOnlyHosts: Set<String> = []
    private var inflight: [String: Task<Data, Error>] = [:]
    /// Media the server said is gone or forbidden: not asked again for a few minutes,
    /// so scrolling past a deleted picture does not refire the request for every recycled row.
    private var recentFailures: [String: (status: Int, date: Date)] = [:]
    private static let failureMemory: TimeInterval = 300

    init() {
        let config = URLSessionConfiguration.default
        config.urlCache = nil // responses carry a token-gated body: our own caches only
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.timeoutIntervalForRequest = 60
        session = URLSession(configuration: config, delegate: MediaRedirectGuard(), delegateQueue: nil)

        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
        let folder = caches?.appendingPathComponent("Mood/media", isDirectory: true)
        if let folder {
            try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        }
        directory = folder
    }

    // MARK: Public API

    nonisolated func cachedImage(for url: URL, maxPixelSize: CGFloat = MediaLoader.defaultMaxPixelSize) -> UIImage? {
        images.image(for: Self.imageKey(url, maxPixelSize: maxPixelSize))
    }

    func image(for url: URL, maxPixelSize: CGFloat = MediaLoader.defaultMaxPixelSize) async throws -> UIImage {
        let key = Self.imageKey(url, maxPixelSize: maxPixelSize)
        if let cached = images.image(for: key) { return cached }
        let data = try await data(for: url)
        guard let image = await Self.decode(data, maxPixelSize: maxPixelSize) else { throw LoadError.undecodable }
        images.insert(image, for: key)
        return image
    }

    /// Raw bytes, from the disk cache when possible. `file://` URLs (local echoes) are read directly.
    func data(for url: URL) async throws -> Data {
        if url.isFileURL { return try Data(contentsOf: url) }
        let key = Self.cacheKey(for: url)
        if let cached = readDisk(key: key) { return cached }
        if let failure = recentFailures[key], Date().timeIntervalSince(failure.date) < Self.failureMemory {
            throw LoadError.http(status: failure.status, errcode: nil)
        }
        if let running = inflight[key] { return try await running.value }

        let task = Task { try await self.fetch(url) }
        inflight[key] = task
        defer { inflight[key] = nil }
        do {
            let data = try await task.value
            writeDisk(data, key: key)
            recentFailures.removeValue(forKey: key)
            return data
        } catch LoadError.http(let status, let errcode) where status == 403 || status == 404 {
            recentFailures[key] = (status, Date())
            throw LoadError.http(status: status, errcode: errcode)
        }
    }

    /// Authenticated download to a temporary file, for Quick Look and the share sheet.
    func temporaryFile(for url: URL, fileName: String) async throws -> URL {
        let data = try await data(for: url)
        let folder = Self.temporaryRoot.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let file = folder.appendingPathComponent(Self.safeFileName(fileName))
        try data.write(to: file, options: .atomic)
        return file
    }

    /// Seeds the disk cache with a file we just uploaded, so our own picture never downloads back.
    func store(fileAt localURL: URL, for remoteURL: URL) {
        guard let data = try? Data(contentsOf: localURL) else { return }
        writeDisk(data, key: Self.cacheKey(for: remoteURL))
    }

    /// Logout: nothing from the previous account may stay on disk or in memory.
    func purge() {
        for task in inflight.values { task.cancel() }
        inflight = [:]
        images.removeAll()
        legacyOnlyHosts = []
        recentFailures = [:]
        if let directory {
            try? FileManager.default.removeItem(at: directory)
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        diskUsage = 0
        try? FileManager.default.removeItem(at: Self.temporaryRoot)
    }

    // MARK: Network

    private func fetch(_ url: URL) async throws -> Data {
        let credentials = MediaCredentials.shared.snapshot
        let host = Self.hostKey(url)
        if legacyOnlyHosts.contains(host), let legacy = MatrixMediaEndpoint.legacyEquivalent(of: url) {
            return try await perform(legacy, credentials: credentials)
        }
        do {
            return try await perform(url, credentials: credentials)
        } catch LoadError.http(let status, let errcode) where MatrixMediaEndpoint.shouldFallBackToLegacy(statusCode: status, errcode: errcode) {
            guard let legacy = MatrixMediaEndpoint.legacyEquivalent(of: url) else {
                throw LoadError.http(status: status, errcode: errcode)
            }
            let data = try await perform(legacy, credentials: credentials)
            legacyOnlyHosts.insert(host)
            return data
        }
    }

    private func perform(_ url: URL, credentials: (homeserver: URL?, token: String?)) async throws -> Data {
        var request = URLRequest(url: url)
        if let token = credentials.token, MatrixMediaEndpoint.shouldAuthorize(url, homeserver: credentials.homeserver) {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        var attempt = 0
        while true {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else { return data }
            if (200..<300).contains(http.statusCode) { return data }
            attempt += 1
            if attempt < 3,
               let delay = MatrixRateLimit.retryAfter(statusCode: http.statusCode, headers: http.allHeaderFields, body: data),
               delay <= MatrixRateLimit.maxHonouredDelay {
                try await Task.sleep(for: .seconds(delay))
                continue
            }
            throw LoadError.http(status: http.statusCode, errcode: MatrixRateLimit.errcode(in: data))
        }
    }

    // MARK: Disk cache

    private func fileURL(forKey key: String) -> URL? {
        directory?.appendingPathComponent(key, isDirectory: false)
    }

    private func readDisk(key: String) -> Data? {
        guard let file = fileURL(forKey: key), let data = try? Data(contentsOf: file) else { return nil }
        // LRU: the modification date is the last access.
        try? FileManager.default.setAttributes([.modificationDate: Date()], ofItemAtPath: file.path)
        return data
    }

    private func writeDisk(_ data: Data, key: String) {
        guard let file = fileURL(forKey: key) else { return }
        do {
            try data.write(to: file, options: .atomic)
        } catch {
            return
        }
        let usage = (diskUsage ?? measureDisk()) + Int64(data.count)
        diskUsage = usage
        if usage > MediaDiskCachePolicy.maxBytes { trimDisk() }
    }

    private func diskEntries() -> [MediaDiskCachePolicy.Entry] {
        guard let directory,
              let files = try? FileManager.default.contentsOfDirectory(
                at: directory, includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey]
              ) else { return [] }
        return files.compactMap { file in
            let values = try? file.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
            return MediaDiskCachePolicy.Entry(
                name: file.lastPathComponent,
                size: Int64(values?.fileSize ?? 0),
                lastAccess: values?.contentModificationDate ?? .distantPast
            )
        }
    }

    private func measureDisk() -> Int64 {
        diskEntries().reduce(0) { $0 + $1.size }
    }

    private func trimDisk() {
        let entries = diskEntries()
        let victims = Set(MediaDiskCachePolicy.evictions(entries))
        for name in victims {
            if let file = fileURL(forKey: name) { try? FileManager.default.removeItem(at: file) }
        }
        diskUsage = entries.filter { !victims.contains($0.name) }.reduce(0) { $0 + $1.size }
    }

    // MARK: Helpers

    private static var temporaryRoot: URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("MoodDownloads", isDirectory: true)
    }

    nonisolated static func cacheKey(for url: URL) -> String {
        SHA256.hash(data: Data(url.absoluteString.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    nonisolated static func imageKey(_ url: URL, maxPixelSize: CGFloat) -> String {
        "\(url.absoluteString)#\(Int(maxPixelSize))"
    }

    nonisolated static func hostKey(_ url: URL) -> String {
        "\(url.host?.lowercased() ?? ""):\(url.port ?? 443)"
    }

    /// A file name safe to create on disk: no path separators, never empty.
    nonisolated static func safeFileName(_ name: String) -> String {
        let cleaned = name
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: ".")))
        guard !cleaned.isEmpty else { return "fichier" }
        return String(cleaned.suffix(120))
    }

    /// Downsampled decode off every actor (EXIF orientation applied, never upscaled).
    @concurrent
    nonisolated static func decode(_ data: Data, maxPixelSize: CGFloat) async -> UIImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary) else {
            return nil
        }
        // Bound decoded animation memory; preserve timing using repeated frames at 20 ms ticks.
        let count = CGImageSourceGetCount(source)
        if count > 1 {
            var frames: [UIImage] = []
            var duration = 0.0
            let step = max(1, (count + 119) / 120)
            let decodedCount = max(1, (count + step - 1) / step)
            let pixelLimit = min(maxPixelSize, 480, sqrt(CGFloat(24 * 1024 * 1024 / (decodedCount * 4))))
            let options: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: pixelLimit
            ]
            for index in stride(from: 0, to: count, by: step) {
                guard let frame = CGImageSourceCreateThumbnailAtIndex(source, index, options as CFDictionary) else { continue }
                var delay = 0.0
                for frameIndex in index..<min(count, index + step) {
                    let props = CGImageSourceCopyPropertiesAtIndex(source, frameIndex, nil) as? [CFString: Any]
                    let gif = props?[kCGImagePropertyGIFDictionary] as? [CFString: Any]
                    delay += max(0.02, min(10, (gif?[kCGImagePropertyGIFUnclampedDelayTime] as? Double) ?? (gif?[kCGImagePropertyGIFDelayTime] as? Double) ?? 0.1))
                }
                let repeats = max(1, Int((delay / 0.02).rounded()))
                frames += Array(repeating: UIImage(cgImage: frame), count: repeats)
                duration += Double(repeats) * 0.02
            }
            if !frames.isEmpty { return UIImage.animatedImage(with: frames, duration: duration) }
        }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        return UIImage(cgImage: image)
    }
}
