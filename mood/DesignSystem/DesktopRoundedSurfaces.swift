import SwiftUI

/// Measured desktop surfaces. Kept separate from mobile and from straight rules.
enum DesktopSurfaceMetrics {
    static let composerRadius: CGFloat = 8
    static let userRadius: CGFloat = 8
    static let profileRadius: CGFloat = 9
    static let profileColumnWidth: CGFloat = 320
    static let profileInset: CGFloat = 7
    static let profileButtonFontSize: CGFloat = 16
    static let profileButtonTextOffset: CGFloat = -1

    static func radius(_ requested: CGFloat, size: CGSize) -> CGFloat {
        guard requested.isFinite, size.width.isFinite, size.height.isFinite else { return 0 }
        return max(0, min(requested, min(size.width, size.height) / 2))
    }
}

enum DesktopSurfacePalette {
    static func composerBorder(focused: Bool) -> Color {
        MoodTheme.shared.theme == .dark ? Color(hex: focused ? "323338" : "27282c") : MoodTheme.composerBorder
    }
    static var userFill: Color { MoodTheme.shared.theme == .dark ? Color(hex: "202024") : MoodTheme.glassBg }
    static var userBorder: Color { MoodTheme.shared.theme == .dark ? Color(hex: "25252a") : MoodTheme.glassBorder }
    static var profileBorder: Color { MoodTheme.shared.theme == .dark ? Color(hex: "313135") : MoodTheme.glassBorder }
    static var profileButton: Color { MoodTheme.shared.theme == .dark ? Color(hex: "37383d") : DesktopUXPalette.settingsSelected }
    static var profileButtonFill: Color { MoodTheme.shared.theme == .dark ? Color(hex: "323338") : DesktopUXPalette.settingsSelected }
}

/// Coverage of an actual circle, shared by all four corners. The tiny alpha tile
/// is generated from geometry, never from a reference screenshot. Its center
/// stretches; its corners stay on the physical pixel grid at either density.
enum DesktopCornerCoverage {
    private static let cache: NSCache<NSString, CGImage> = {
        let cache = NSCache<NSString, CGImage>()
        cache.countLimit = 24
        cache.totalCostLimit = 1024 * 1024
        return cache
    }()

    static func image(radius: CGFloat, inset: CGFloat, displayScale: CGFloat) -> CGImage? {
        guard radius.isFinite, inset.isFinite, displayScale.isFinite,
              radius > 0, inset >= 0, inset < radius, displayScale > 0,
              radius * displayScale <= 64 else { return nil }
        let r = radius * displayScale, b = inset * displayScale
        let cap = Int(ceil(r)), side = 2 * cap + 1
        let key = NSString(string: "\(r)|\(b)")
        if let image = cache.object(forKey: key) { return image }
        // Integrate horizontal circle slices. Straight edges remain exactly
        // opaque/transparent, rather than a second antialiased stroke.
        var alpha = [UInt8](repeating: 0, count: side * side)
        let samples = 128
        for y in 0...cap {
            for x in 0...cap {
                var area: CGFloat = 0
                for sample in 0..<samples {
                    let py = CGFloat(y) + (CGFloat(sample) + 0.5) / CGFloat(samples)
                    guard py >= b else { continue }
                    let dy = max(0, r - py)
                    let innerRadius = r - b
                    guard dy <= innerRadius else { continue }
                    let left = max(b, r - sqrt(max(0, innerRadius * innerRadius - dy * dy)))
                    area += min(1, max(0, CGFloat(x + 1) - max(CGFloat(x), left)))
                }
                let value = UInt8(clamping: Int((area / CGFloat(samples) * 255).rounded()))
                for yy in Set([y, side - y - 1]) {
                    for xx in Set([x, side - x - 1]) { alpha[yy * side + xx] = value }
                }
            }
        }
        var rgba = [UInt8](repeating: 0, count: side * side * 4)
        for index in alpha.indices {
            for channel in 0..<4 { rgba[index * 4 + channel] = alpha[index] }
        }
        guard let provider = CGDataProvider(data: Data(rgba) as CFData),
              let space = CGColorSpace(name: CGColorSpace.sRGB),
              let image = CGImage(width: side, height: side, bitsPerComponent: 8,
                  bitsPerPixel: 32, bytesPerRow: side * 4, space: space,
                  bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                  provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent) else { return nil }
        cache.setObject(image, forKey: key, cost: rgba.count)
        return image
    }
}

private struct DesktopCornerMask: View {
    let radius: CGFloat
    let inset: CGFloat
    let scale: CGFloat
    var body: some View {
        if let image = DesktopCornerCoverage.image(radius: radius, inset: inset, displayScale: scale) {
            let cap = CGFloat(image.width / 2) / scale
            Image(decorative: image, scale: scale)
                .resizable(capInsets: EdgeInsets(top: cap, leading: cap, bottom: cap, trailing: cap))
                .interpolation(.none)
        } else {
            RoundedRectangle(cornerRadius: radius, style: .circular).inset(by: inset)
        }
    }
}

/// One physical pixel outline, without changing content layout or hit targets.
struct DesktopRoundedSurface: ViewModifier {
    @Environment(\.displayScale) private var displayScale
    let radius: CGFloat
    let border: Color

    func body(content: Content) -> some View {
        let width = DesktopPixelMetrics.thickness(displayScale: displayScale)
        content
            .mask(DesktopCornerMask(radius: radius, inset: width, scale: displayScale))
            .background {
                Rectangle().fill(border)
                    .mask(DesktopCornerMask(radius: radius, inset: 0, scale: displayScale))
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
    }
}

extension View {
    @ViewBuilder
    func desktopRoundedSurface(calibrated: Bool, radius: CGFloat, border: Color, legacyBorder: Color) -> some View {
        if calibrated {
            modifier(DesktopRoundedSurface(radius: radius, border: border))
        } else {
            clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(legacyBorder, lineWidth: LayoutMetrics.scale))
        }
    }
}

/// Only the top and server-side edge belong to this frame; no right/bottom line.
/// A single connected path prevents a doubled seam at the rounded top-left join.
struct DesktopWorkspaceBorder: Shape {
    var thickness: CGFloat = 1

    func path(in rect: CGRect) -> Path {
        let radius = DesktopSurfaceMetrics.radius(LayoutMetrics.workspaceCornerRadius, size: rect.size)
        let inset = max(0, thickness) / 2
        let r = max(0, radius - inset)
        let k: CGFloat = 0.552284749831
        return Path { path in
            path.move(to: CGPoint(x: rect.minX + inset, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.minX + inset, y: rect.minY + radius))
            path.addCurve(to: CGPoint(x: rect.minX + radius, y: rect.minY + inset),
                control1: CGPoint(x: rect.minX + inset, y: rect.minY + radius - r * k),
                control2: CGPoint(x: rect.minX + radius - r * k, y: rect.minY + inset))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + inset))
        }
    }
}

struct DesktopWorkspaceOutline: View {
    @Environment(\.displayScale) private var displayScale
    var body: some View {
        let width = DesktopPixelMetrics.thickness(displayScale: displayScale)
        DesktopWorkspaceBorder(thickness: width)
            .stroke(DesktopFriendsPalette.sidebarSearch, lineWidth: width)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}
