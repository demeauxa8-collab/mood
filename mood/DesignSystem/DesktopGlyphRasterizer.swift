import SwiftUI
import CoreText
import UIKit

/// Native, dynamic glyph masks. No screenshots or word-specific bitmaps.
/// Quarter-pixel placement and the CG smoothing inverse are validated separately
/// from the choice of font and from the layout. The old experiment remains available.
enum DesktopGlyphRasterizer {
    #if targetEnvironment(macCatalyst)
    static let enabled = !CommandLine.arguments.contains("-pixelNativeText")
        && !CommandLine.arguments.contains("-pixelTextMasks")
    #else
    static let enabled = false
    #endif
    static let imageDelivery = !CommandLine.arguments.contains("-pixelGlyphCanvas")
    static let opaqueDelivery = !CommandLine.arguments.contains("-pixelGlyphTransparent")

    private static let cache: NSCache<NSString, CGImage> = {
        let cache = NSCache<NSString, CGImage>()
        cache.countLimit = 200
        cache.totalCostLimit = 8 * 1024 * 1024
        return cache
    }()

    static func snap(_ physicalPosition: CGFloat) -> CGFloat {
        (physicalPosition * 4).rounded() / 4
    }

    static func coverage(_ black: UInt8) -> UInt8 {
        UInt8(255 - (Int(black) * Int(black) + 128) / 255)
    }

    /// Shared colour-dependent mask correction, calibrated against native PNGs.
    /// Inspired by Skia's macOS luminance correction; 1.75 is a measured model,
    /// not a claim about the installed Discord renderer's internal settings.
    private static let colourMasks: [[UInt8]] = (0..<8).map { bucket in
        // Halve the luminance before 3-bit canonicalisation (macOS Skia path).
        // The brightest bucket remains neutral, as measured on white labels.
        let halfBucket = bucket >> 1
        let canonical = (halfBucket << 5) | (halfBucket << 2) | (halfBucket >> 1)
        let source = Double(canonical) / 255
        let destination = 1 - source
        return (0...255).map { coverage in
            guard bucket < 7, abs(source - destination) >= 1.0 / 256 else { return UInt8(coverage) }
            let alpha = Double(coverage) / 255
            let blended = pow(pow(source, 1.75) * alpha + pow(destination, 1.75) * (1 - alpha), 1 / 1.75)
            let corrected = min(1, max(0, (blended - destination) / (source - destination)))
            return UInt8(clamping: Int((corrected * 255).rounded()))
        }
    }

    static func preblend(coverage: UInt8, luminance: UInt8) -> UInt8 {
        colourMasks[Int(luminance) >> 5][Int(coverage)]
    }

    static func blend(foreground: UInt8, background: UInt8, alpha: UInt8) -> UInt8 {
        UInt8((Int(foreground) * Int(alpha) + Int(background) * (255 - Int(alpha))) / 255)
    }

    /// Stabilise layout noise before selecting a glyph's quarter-pixel phase.
    /// This does not round or move the view's actual origin.
    static func layoutPhase(_ physicalFraction: CGFloat) -> CGFloat {
        (physicalFraction * 64).rounded() / 64
    }

    static func image(value: String, font: CTFont, color: Color, bounds: CGSize,
                      displayScale: CGFloat, phase: CGFloat = 0, background: Color? = nil) -> CGImage? {
        guard displayScale.isFinite, displayScale > 0,
              bounds.width.isFinite, bounds.height.isFinite,
              bounds.width > 0, bounds.height > 0,
              bounds.width * displayScale <= 8192,
              bounds.height * displayScale <= 256,
              phase.isFinite, abs(phase) <= 1 else { return nil }
        let scale = displayScale
        let width = Int(ceil(bounds.width * scale))
        let height = Int(ceil(bounds.height * scale))
        let bytes = width * height * 4
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let components = UIColor(color).cgColor.converted(to: space, intent: .relativeColorimetric, options: nil)?.components,
              components.count == 4, components.allSatisfy({ $0.isFinite }) else { return nil }
        let backgroundComponents = background.flatMap {
            UIColor($0).cgColor.converted(to: space, intent: .relativeColorimetric, options: nil)?.components
        }.flatMap { components -> [CGFloat]? in
            // An unknown translucent surface must keep native alpha composition.
            guard components.count == 4, components.allSatisfy({ $0.isFinite }),
                  components[3] >= 1 else { return nil }
            return components
        }
        let stablePhase = layoutPhase(phase)
        let key = NSString(string: "\(value.utf8.count):\(value)|\(CTFontCopyPostScriptName(font))|\(CTFontGetSize(font))|\(bounds.width),\(bounds.height)|\(scale)|\(stablePhase)|\(components)|\(String(describing: backgroundComponents))")
        if let cached = cache.object(forKey: key) { return cached }
        guard let context = CGContext(data: nil, width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return nil }
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.setFillColor(CGColor(gray: 0, alpha: 1))
        context.setShouldAntialias(true)
        context.setAllowsFontSmoothing(true)
        context.setShouldSmoothFonts(true)
        context.setAllowsFontSubpixelPositioning(true)
        context.setShouldSubpixelPositionFonts(true)
        context.setAllowsFontSubpixelQuantization(false)
        context.setShouldSubpixelQuantizeFonts(false)
        context.scaleBy(x: scale, y: scale)
        let attributes: [NSAttributedString.Key: Any] = [
            NSAttributedString.Key(kCTFontAttributeName as String): font,
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): CGColor(gray: 0, alpha: 1)
        ]
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: value, attributes: attributes))
        let token = CTLineCreateWithAttributedString(NSAttributedString(string: "…", attributes: attributes))
        let actualWidth = CTLineGetTypographicBounds(line, nil, nil, nil)
        let visibleLine = actualWidth > bounds.width + 1 / scale
            ? CTLineCreateTruncatedLine(line, Double(bounds.width), .end, token) ?? line
            : line
        let baseline = floor(CTFontGetDescent(font) * scale) / scale
        for run in CTLineGetGlyphRuns(visibleLine) as! [CTRun] {
            let count = CTRunGetGlyphCount(run)
            guard count > 0 else { continue }
            var glyphs = [CGGlyph](repeating: 0, count: count)
            var positions = [CGPoint](repeating: .zero, count: count)
            CTRunGetGlyphs(run, CFRange(location: 0, length: 0), &glyphs)
            CTRunGetPositions(run, CFRange(location: 0, length: 0), &positions)
            let runAttributes = CTRunGetAttributes(run) as NSDictionary
            let runFont = runAttributes[kCTFontAttributeName] as! CTFont
            // Colour emoji should retain their native colour renderer, not become masks.
            if (CTFontCopyPostScriptName(runFont) as String).contains("Emoji") { return nil }
            for i in positions.indices {
                positions[i].x = snap(positions[i].x * scale + stablePhase) / scale
                positions[i].y = baseline + positions[i].y
            }
            CTFontDrawGlyphs(runFont, glyphs, positions, count, context)
        }
        guard let data = context.data else { return nil }
        let raw = data.bindMemory(to: UInt8.self, capacity: bytes)
        let foreground = components.prefix(3).map { UInt8(clamping: Int(($0 * 255).rounded())) }
        let backgroundRGB = backgroundComponents.map { $0.prefix(3).map { UInt8(clamping: Int(($0 * 255).rounded())) } }
        let luminance = UInt8((54 * Int(foreground[0]) + 183 * Int(foreground[1]) + 19 * Int(foreground[2])) / 256)
        var output = Data(count: bytes)
        output.withUnsafeMutableBytes { storage in
            let pixels = storage.bindMemory(to: UInt8.self)
            for p in stride(from: 0, to: bytes, by: 4) {
                let r = Int(coverage(raw[p])), g = Int(coverage(raw[p+1])), b = Int(coverage(raw[p+2]))
                let mask = UInt8((54*r + 183*g + 19*b) / 256)
                let corrected = preblend(coverage: mask, luminance: luminance)
                let alpha = UInt8(clamping: Int((CGFloat(corrected) * components[3]).rounded()))
                for c in 0..<3 {
                    if let bg = backgroundRGB {
                        pixels[p+c] = blend(foreground: foreground[c], background: bg[c], alpha: alpha)
                    } else {
                        pixels[p+c] = foreground[c]
                    }
                }
                pixels[p+3] = backgroundComponents == nil
                    ? UInt8(clamping: alpha)
                    : 255
            }
        }
        guard let provider = CGDataProvider(data: output as CFData) else { return nil }
        guard let image = CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32,
            bytesPerRow: width * 4, space: space,
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.last.rawValue),
            provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent) else { return nil }
        cache.setObject(image, forKey: key, cost: bytes)
        return image
    }
}
