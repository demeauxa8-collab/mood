import SwiftUI
import CoreText
import UIKit

/// Opt-in local experiment, not the default renderer. Generates real glyphs
/// from the font; never stores screenshots or substitutes bitmap label strings.
enum DesktopGlyphMaskExperiment {
    static let enabled = CommandLine.arguments.contains("-pixelTextMasks")

    static func image(value: String, font: CTFont, color: Color, bounds: CGSize,
                      displayScale: CGFloat) -> CGImage? {
        let scale = max(1, displayScale)
        let width = Int(ceil(bounds.width * scale))
        let height = Int(ceil(bounds.height * scale))
        guard width > 0, height > 0,
              let context = CGContext(data: nil, width: width, height: height,
                  bitsPerComponent: 8, bytesPerRow: width * 4,
                  space: CGColorSpaceCreateDeviceRGB(),
                  bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return nil }
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.scaleBy(x: scale, y: scale)
        context.setShouldAntialias(true)
        context.setAllowsFontSmoothing(true)
        context.setShouldSmoothFonts(true)
        context.setAllowsFontSubpixelPositioning(true)
        context.setShouldSubpixelPositionFonts(true)
        context.setAllowsFontSubpixelQuantization(false)
        context.setShouldSubpixelQuantizeFonts(false)
        let attributes: [NSAttributedString.Key: Any] = [
            NSAttributedString.Key(kCTFontAttributeName as String): font,
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): CGColor(gray: 0, alpha: 1)
        ]
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: value, attributes: attributes))
        let token = CTLineCreateWithAttributedString(NSAttributedString(string: "…", attributes: attributes))
        let actualWidth = CTLineGetTypographicBounds(line, nil, nil, nil)
        context.textPosition = CGPoint(x: 0, y: ceil(CTFontGetDescent(font) * scale) / scale)
        CTLineDraw(actualWidth > bounds.width + 0.01
            ? CTLineCreateTruncatedLine(line, Double(bounds.width), .end, token) ?? line
            : line, context)
        guard let data = context.data,
              let space = CGColorSpace(name: CGColorSpace.sRGB),
              let components = UIColor(color).cgColor.converted(to: space, intent: .relativeColorimetric, options: nil)?.components,
              components.count >= 3 else { return nil }
        let raw = data.bindMemory(to: UInt8.self, capacity: width * height * 4)
        let byteCount = width * height * 4
        var output = Data(count: byteCount)
        output.withUnsafeMutableBytes { bytes in
            let pixels = bytes.bindMemory(to: UInt8.self)
            for p in stride(from: 0, to: byteCount, by: 4) {
                let black = (Double(raw[p]) + Double(raw[p+1]) + Double(raw[p+2])) / (3 * 255)
                // Trial curve, measured against multiple reference labels.
                // This is not a claim of complete Skia rasteriser equivalence.
                let coverage = pow(max(0, 1 - black * black), 1.25)
                for c in 0..<3 {
                    pixels[p+c] = UInt8(clamping: Int((components[c] * 255).rounded()))
                }
                pixels[p+3] = UInt8(clamping: Int((coverage * 255).rounded()))
            }
        }
        guard let provider = CGDataProvider(data: output as CFData) else { return nil }
        return CGImage(width: width, height: height, bitsPerComponent: 8,
            bitsPerPixel: 32, bytesPerRow: width * 4, space: space,
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.last.rawValue),
            provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
    }
}
