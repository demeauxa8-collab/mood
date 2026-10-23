import ImageIO
import UIKit

/// Re-encode bounded pixels before upload: accepts Photos' formats and drops source metadata.
@MainActor
enum OnboardingAvatar {
    static let maximumInputBytes = 20 * 1024 * 1024
    static let emojis = ["🙂", "😎", "🐸", "⭐️", "🐱", "🌙", "🦋", "🐼"]

    static func photo(_ data: Data) throws -> Data {
        guard !data.isEmpty, data.count <= maximumInputBytes,
              let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: 512,
                kCGImageSourceShouldCacheImmediately: true
              ] as CFDictionary),
              let encoded = UIImage(cgImage: image).jpegData(compressionQuality: 0.85) else {
            throw AccountError.server("Choisis une photo valide de moins de 20 Mo.")
        }
        return encoded
    }

    /// No emoji column exists on the shipped profile. Use the standard avatar media path.
    static func emoji(_ emoji: String) throws -> Data {
        guard emojis.contains(emoji) else { throw AccountError.server("Choisis un emoji proposé.") }
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: CGSize(width: 256, height: 256), format: format).pngData { _ in
            let text = emoji as NSString
            let attributes: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: 184)]
            let size = text.size(withAttributes: attributes)
            text.draw(at: CGPoint(x: (256 - size.width) / 2, y: (256 - size.height) / 2), withAttributes: attributes)
        }
    }
}
