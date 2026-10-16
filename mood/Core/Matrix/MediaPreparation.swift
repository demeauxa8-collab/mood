import Foundation
import ImageIO
import UniformTypeIdentifiers
import AVFoundation
import UIKit

/// Turns a picked file into an `OutgoingAttachment` whose files sit in the outbox folder:
/// images are resized to ≤ 2560 px and re-encoded as JPEG 0.85 when needed (HEIC always), get an
/// 800×600 thumbnail, and lose their GPS metadata; other files are copied as they are.
nonisolated enum MediaPreparation {
    enum PreparationError: LocalizedError {
        case unreadable(String)
        case tooLarge(size: Int, limit: Int)

        var errorDescription: String? {
            switch self {
            case .unreadable(let name): "Impossible de lire \(name)."
            case .tooLarge(let size, let limit): MediaUploadLimits.tooLargeMessage(size: size, limit: limit)
            }
        }
    }

    /// Runs off the main actor: decoding a 48 Mpx HEIC takes a while.
    @concurrent
    static func prepare(sourceURL: URL, txnId: String, folder: URL, limit: Int) async throws -> OutgoingAttachment {
        let values = try? sourceURL.resourceValues(forKeys: [.contentTypeKey, .fileSizeKey, .nameKey])
        let fileName = values?.name ?? sourceURL.lastPathComponent
        let type = values?.contentType ?? UTType(filenameExtension: sourceURL.pathExtension) ?? .data
        let sourceSize = values?.fileSize ?? 0

        if type.conforms(to: .image), let prepared = try prepareImage(sourceURL, type: type, fileName: fileName,
                                                                     txnId: txnId, folder: folder, limit: limit) {
            return prepared
        }

        // Plain file (or an image ImageIO cannot read): checked before copying anything.
        guard sourceSize <= limit else { throw PreparationError.tooLarge(size: sourceSize, limit: limit) }
        let localName = localFileName(txnId: txnId, suffix: "", extension: sourceURL.pathExtension)
        let destination = folder.appendingPathComponent(localName)
        do {
            try? FileManager.default.removeItem(at: destination)
            try FileManager.default.copyItem(at: sourceURL, to: destination)
        } catch {
            throw PreparationError.unreadable(fileName)
        }
        let size = (try? destination.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? sourceSize
        guard size <= limit else {
            try? FileManager.default.removeItem(at: destination)
            throw PreparationError.tooLarge(size: size, limit: limit)
        }
        var attachment = OutgoingAttachment(
            kind: kind(of: type), fileName: fileName, localFile: localName,
            mimeType: type.preferredMIMEType ?? "application/octet-stream", size: size
        )
        if attachment.kind == .video || attachment.kind == .audio {
            let asset = AVURLAsset(url: destination)
            if let duration = try? await asset.load(.duration), duration.seconds.isFinite {
                attachment.duration = max(0, Int(duration.seconds * 1000))
            }
            if attachment.kind == .video {
                let generator = AVAssetImageGenerator(asset: asset)
                generator.appliesPreferredTrackTransform = true
                generator.maximumSize = CGSize(width: 800, height: 600)
                if let frame = try? await generator.image(at: .zero).image,
                   let data = UIImage(cgImage: frame).jpegData(compressionQuality: 0.8) {
                    let name = localFileName(txnId: txnId, suffix: "-thumb", extension: "jpg")
                    try data.write(to: folder.appendingPathComponent(name), options: .atomic)
                    attachment.thumbnailFile = name
                    attachment.thumbnailMimeType = "image/jpeg"
                    attachment.thumbnailSize = data.count
                    attachment.thumbnailWidth = frame.width
                    attachment.thumbnailHeight = frame.height
                }
                if let track = try? await asset.loadTracks(withMediaType: .video).first,
                   let size = try? await track.load(.naturalSize),
                   let transform = try? await track.load(.preferredTransform) {
                    let displayed = size.applying(transform)
                    attachment.width = Int(abs(displayed.width))
                    attachment.height = Int(abs(displayed.height))
                }
            }
        }
        return attachment
    }

    static func kind(of type: UTType) -> OutgoingAttachment.Kind {
        if type.conforms(to: .image) { return .image }
        if type.conforms(to: .movie) || type.conforms(to: .video) { return .video }
        if type.conforms(to: .audio) { return .audio }
        return .file
    }

    /// MIME type of encoded image bytes (avatars and server icons arrive as raw data).
    static func imageMimeType(of data: Data) -> String? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let identifier = CGImageSourceGetType(source) as String? else { return nil }
        return UTType(identifier)?.preferredMIMEType
    }

    static func localFileName(txnId: String, suffix: String, extension ext: String) -> String {
        let safeTxn = txnId.filter { $0.isLetter || $0.isNumber || $0 == "-" }
        return ext.isEmpty ? "\(safeTxn)\(suffix)" : "\(safeTxn)\(suffix).\(ext.lowercased())"
    }

    // MARK: Images

    private static func prepareImage(_ sourceURL: URL, type: UTType, fileName: String, txnId: String,
                                     folder: URL, limit: Int) throws -> OutgoingAttachment? {
        guard let source = CGImageSourceCreateWithURL(sourceURL as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let pixelWidth = (properties[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue,
              let pixelHeight = (properties[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue,
              pixelWidth > 0, pixelHeight > 0 else { return nil }

        let orientation = (properties[kCGImagePropertyOrientation] as? NSNumber)?.intValue ?? 1
        let hasAlpha = (properties[kCGImagePropertyHasAlpha] as? NSNumber)?.boolValue ?? false
        let isAnimated = CGImageSourceGetCount(source) > 1
        let plan = ImageUploadPlan.make(typeIdentifier: type.identifier, width: pixelWidth, height: pixelHeight,
                                        orientation: orientation, hasAlpha: hasAlpha, isAnimated: isAnimated)

        let mainName: String
        let mimeType: String
        let shownName: String
        if plan.needsReencode, let ext = plan.output.fileExtension, let mime = plan.output.mimeType,
           let outputType = UTType(mimeType: mime) {
            mainName = localFileName(txnId: txnId, suffix: "", extension: ext)
            let written = writeThumbnail(from: source, maxPixelSize: max(plan.width, plan.height), type: outputType,
                                         quality: ImageUploadPlan.jpegQuality, to: folder.appendingPathComponent(mainName))
            guard written != nil else { throw PreparationError.unreadable(fileName) }
            mimeType = mime
            shownName = renamed(fileName, extension: ext)
        } else {
            mainName = localFileName(txnId: txnId, suffix: "", extension: sourceURL.pathExtension)
            copyStrippingLocation(source: source, sourceURL: sourceURL, type: type, to: folder.appendingPathComponent(mainName))
            mimeType = type.preferredMIMEType ?? "application/octet-stream"
            shownName = fileName
        }

        let mainURL = folder.appendingPathComponent(mainName)
        guard let size = try? mainURL.resourceValues(forKeys: [.fileSizeKey]).fileSize else {
            throw PreparationError.unreadable(fileName)
        }
        guard size <= limit else {
            try? FileManager.default.removeItem(at: mainURL)
            throw PreparationError.tooLarge(size: size, limit: limit)
        }

        var attachment = OutgoingAttachment(
            kind: .image, fileName: shownName, localFile: mainName, mimeType: mimeType, size: size,
            width: plan.width, height: plan.height
        )

        if let box = ImageUploadPlan.thumbnailSize(width: plan.width, height: plan.height) {
            let thumbnailType: UTType = hasAlpha ? .png : .jpeg
            let thumbnailName = localFileName(txnId: txnId, suffix: "-thumb", extension: hasAlpha ? "png" : "jpg")
            let thumbnailURL = folder.appendingPathComponent(thumbnailName)
            if let written = writeThumbnail(from: source, maxPixelSize: max(box.width, box.height), type: thumbnailType,
                                            quality: 0.8, to: thumbnailURL),
               let thumbnailSize = try? thumbnailURL.resourceValues(forKeys: [.fileSizeKey]).fileSize {
                attachment.thumbnailFile = thumbnailName
                attachment.thumbnailMimeType = thumbnailType.preferredMIMEType
                attachment.thumbnailSize = thumbnailSize
                attachment.thumbnailWidth = written.width
                attachment.thumbnailHeight = written.height
            }
        }
        return attachment
    }

    /// Decodes at most `maxPixelSize` (orientation applied) and encodes to `url`. Returns the written size.
    private static func writeThumbnail(from source: CGImageSource, maxPixelSize: Int, type: UTType, quality: Double,
                                       to url: URL) -> (width: Int, height: Int)? {
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary),
              let destination = CGImageDestinationCreateWithURL(url as CFURL, type.identifier as CFString, 1, nil) else { return nil }
        // No metadata is copied: the re-encoded file carries no EXIF, so no location either.
        CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else {
            try? FileManager.default.removeItem(at: url)
            return nil
        }
        return (image.width, image.height)
    }

    /// Lossless copy without GPS tags; falls back to a byte copy for formats ImageIO cannot rewrite.
    private static func copyStrippingLocation(source: CGImageSource, sourceURL: URL, type: UTType, to url: URL) {
        try? FileManager.default.removeItem(at: url)
        if CGImageSourceGetCount(source) > 1 {
            try? FileManager.default.copyItem(at: sourceURL, to: url)
            return
        }
        if let destination = CGImageDestinationCreateWithURL(url as CFURL, type.identifier as CFString, 1, nil) {
            let options: [CFString: Any] = [kCGImageMetadataShouldExcludeGPS: true]
            var error: Unmanaged<CFError>?
            if CGImageDestinationCopyImageSource(destination, source, options as CFDictionary, &error) {
                return
            }
            try? FileManager.default.removeItem(at: url)
        }
        try? FileManager.default.copyItem(at: sourceURL, to: url)
    }

    private static func renamed(_ fileName: String, extension ext: String) -> String {
        let base = (fileName as NSString).deletingPathExtension
        return "\(base.isEmpty ? "image" : base).\(ext)"
    }
}
