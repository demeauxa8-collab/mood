import SwiftUI
import CoreText
import UIKit

/// Private local comparison assets extracted from the installed Discord cache.
/// Do not distribute these fonts with Mood without appropriate font rights.
enum DesktopFriendsTypography {
    static let hasLocalFonts: Bool = {
        var success = true
        for name in ["ggsans-Normal", "ggsans-Medium", "ggsans-Semibold", "ggsans-Bold"] {
            guard let url = Bundle.main.url(forResource: name, withExtension: "ttf", subdirectory: "DiscordLocal/Fonts")
                    ?? Bundle.main.url(forResource: name, withExtension: "ttf") else {
                success = false
                continue
            }
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }
        return success
    }()

    static func font(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        guard hasLocalFonts else { return .system(size: size * LayoutMetrics.scale, weight: weight) }
        return .custom(name(weight), fixedSize: size * LayoutMetrics.scale)
    }

    private static func name(_ weight: Font.Weight) -> String {
        let name: String
        switch weight {
        case .bold: name = "ggsans-Bold"
        case .semibold: name = "ggsans-Semibold"
        case .medium: name = "ggsans-Medium"
        default: name = "ggsans-Normal"
        }
        return name
    }

    static func ctFont(_ size: CGFloat, weight: Font.Weight) -> CTFont {
        guard hasLocalFonts else {
            let uiWeight: UIFont.Weight = switch weight {
            case .bold: .bold
            case .semibold: .semibold
            case .medium: .medium
            default: .regular
            }
            return UIFont.systemFont(ofSize: size * LayoutMetrics.scale, weight: uiWeight) as CTFont
        }
        return CTFontCreateWithName(name(weight) as CFString, size * LayoutMetrics.scale, nil)
    }
}

private struct DesktopFriendsFontModifier: ViewModifier {
    @Environment(\.desktopFriendsCalibration) private var calibrated
    let size: CGFloat
    let weight: Font.Weight
    func body(content: Content) -> some View {
        content.font(calibrated ? DesktopFriendsTypography.font(size, weight: weight) : .mood(size, weight: weight))
    }
}

extension View {
    func desktopFriendsFont(_ size: CGFloat, weight: Font.Weight = .regular) -> some View {
        modifier(DesktopFriendsFontModifier(size: size, weight: weight))
    }
}

/// Desktop-only calibration; never enabled on iPhone/iPad.
private struct DesktopFriendsCalibrationKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var desktopFriendsCalibration: Bool {
        get { self[DesktopFriendsCalibrationKey.self] }
        set { self[DesktopFriendsCalibrationKey.self] = newValue }
    }
}

/// sRGB measurements from the native Discord PNG, ICC converted, 2026-10-07.
/// Keep these separate from the application's shared theme and accent.
enum DesktopFriendsPalette {
    static var sidebarPrimary: Color { MoodTheme.shared.theme == .dark ? Color(hex: "efeff1") : MoodTheme.textPrimary }
    static var selected: Color { MoodTheme.shared.theme == .dark ? Color(hex: "313135") : MoodTheme.selectedBg }
    static var selectedTab: Color { MoodTheme.shared.theme == .dark ? Color(hex: "37373c") : MoodTheme.selectedBg }
    static var sidebarSearch: Color { MoodTheme.shared.theme == .dark ? Color(hex: "262628") : MoodTheme.dmSearchBackground }
    static var search: Color { MoodTheme.shared.theme == .dark ? Color(hex: "17171b") : MoodTheme.headerSearchBackground }
    static var outline: Color { MoodTheme.shared.theme == .dark ? Color(hex: "343439") : MoodTheme.headerSearchBorder }
    static var rule: Color { MoodTheme.shared.theme == .dark ? Color(hex: "2c2c31") : MoodTheme.divider }
    static var primary: Color { MoodTheme.textPrimary }
    static var secondary: Color { MoodTheme.textSecondary }
    static var hint: Color { MoodTheme.shared.theme == .dark ? Color(hex: "81828a") : MoodTheme.textSubtle }
    static var placeholder: Color { MoodTheme.shared.theme == .dark ? Color(hex: "8f9097") : MoodTheme.friendsSearchPlaceholder }
    static var icon: Color { MoodTheme.textSupporting }
    static var panel: Color { MoodTheme.shared.theme == .dark ? Color(hex: "212125") : MoodTheme.glassBg }
    static let sidebarWidth: CGFloat = 285 * LayoutMetrics.scale
    static let userPanelWidth: CGFloat = 341 * LayoutMetrics.scale
    static let headerHeight: CGFloat = 49 * LayoutMetrics.scale
}

/// Filled orthogonal strip: a single physical pixel, without blended offsets.
struct DesktopFriendsRule: View {
    var vertical = false
    var color: Color = DesktopFriendsPalette.rule

    var body: some View {
        DesktopPixelRule(vertical: vertical, color: color)
    }
}

/// Monochrome paths in a 24-unit grid; no SF Symbol palette, shadow or layers.
/// The same paths are reused in chrome, navigation and friend-row actions.
struct DesktopFriendsIcon: View {
    let name: String
    var size: CGFloat = 24

    private var reference: (String, CGFloat)? {
        switch name {
        case "desktop.title.friends": return ("ref-title-friends", 16)
        case "figure.wave", "person.2.fill": return ("ref-friends", 24)
        case "circle.hexagongrid.fill": return ("ref-nitro", 24)
        case "envelope.fill": return ("ref-envelope", 24)
        case "bag.fill": return ("ref-shop", 24)
        case "flag.fill": return ("ref-quests", 24)
        case "magnifyingglass": return ("ref-search", 18)
        case "bubble.left.fill": return ("ref-message", 20)
        case "ellipsis": return ("ref-more", 24)
        case "person.badge.plus": return ("ref-group", 24)
        case "mic.fill": return ("ref-microphone", 20)
        case "headphones": return ("ref-headphones", 20)
        case "gearshape.fill": return ("ref-settings", 20)
        case "chevron.down": return ("ref-chevron", 12)
        case "number": return ("ref-channel", 24)
        case "square.stack.3d.up.fill": return ("ref-threads", 24)
        case "bell.fill": return ("ref-bell", 24)
        case "pin", "pin.fill": return ("ref-pin", 24)
        case "desktop.members": return ("ref-members", 24)
        case "desktop.invite": return ("ref-invite", 24)
        case "desktop.attach": return ("ref-attach", 24)
        case "gift": return ("ref-gift", 24)
        case "face.dashed": return ("ref-sticker", 24)
        case "face.smiling": return ("ref-emoji", 24)
        case "square.grid.2x2.fill": return ("ref-apps", 24)
        case "tray.full.fill": return ("ref-inbox", 18)
        case "questionmark.circle.fill": return ("ref-help", 18)
        default: return nil
        }
    }

    var body: some View {
        Group {
            if let (asset, nativeSize) = reference,
               let url = Bundle.main.url(forResource: asset, withExtension: "png", subdirectory: "DiscordLocal/ReferenceIcons") ?? Bundle.main.url(forResource: asset, withExtension: "png"),
               let bitmap = UIImage(contentsOfFile: url.path) {
                Image(uiImage: bitmap).renderingMode(.template).interpolation(.none)
                    .frame(width: nativeSize, height: nativeSize)
                    .frame(width: size, height: size)
            } else if Self.vectorNames.contains(name) {
                vector
            } else {
                // Unmeasured symbols must remain usable, never silently vanish.
                Image(systemName: Self.fallbackSymbol(name)).font(.system(size: size, weight: .regular))
            }
        }
        .frame(width: size * LayoutMetrics.scale, height: size * LayoutMetrics.scale)
        .accessibilityHidden(true)
    }

    private static func fallbackSymbol(_ name: String) -> String {
        switch name {
        case "desktop.title.friends": "person.2.fill"
        case "desktop.members": "person.2.fill"
        case "desktop.invite": "person.badge.plus"
        case "desktop.attach": "plus"
        default: name
        }
    }

    private static let vectorNames: Set<String> = [
        "plus", "xmark.circle.fill", "arrow.left", "arrow.right", "arrow.down.to.line",
        "mic.slash.fill", "speaker.slash.fill", "safari"
    ]

    private var vector: some View {
        Canvas { context, bounds in
            context.scaleBy(x: bounds.width / 24, y: bounds.height / 24)
            let ink = GraphicsContext.Shading.foreground
            func fill(_ path: Path) { context.fill(path, with: ink) }
            func stroke(_ path: Path, _ width: CGFloat = 2) {
                context.stroke(path, with: ink, style: StrokeStyle(lineWidth: width, lineCap: .round, lineJoin: .round))
            }
            func line(_ points: [CGPoint]) -> Path {
                Path { p in
                    guard let first = points.first else { return }
                    p.move(to: first)
                    for point in points.dropFirst() { p.addLine(to: point) }
                }
            }
            switch name {
            case "figure.wave", "person.2.fill":
                fill(Path(ellipseIn: CGRect(x: 10, y: 2, width: 7, height: 7)))
                fill(Path { p in
                    p.move(to: CGPoint(x: 5, y: 7)); p.addQuadCurve(to: CGPoint(x: 8, y: 16), control: CGPoint(x: 5, y: 14))
                    p.addLine(to: CGPoint(x: 18, y: 16)); p.addQuadCurve(to: CGPoint(x: 20, y: 20), control: CGPoint(x: 21, y: 16))
                    p.addLine(to: CGPoint(x: 19, y: 22)); p.addLine(to: CGPoint(x: 8, y: 22))
                    p.addQuadCurve(to: CGPoint(x: 2, y: 8), control: CGPoint(x: 2, y: 17)); p.closeSubpath()
                })
                fill(Path { p in
                    p.move(to: CGPoint(x: 10, y: 11)); p.addLine(to: CGPoint(x: 15, y: 11)); p.addLine(to: CGPoint(x: 19, y: 16))
                    p.addLine(to: CGPoint(x: 10, y: 16)); p.closeSubpath()
                })
            case "bubble.left.fill":
                fill(Path { p in
                    p.move(to: CGPoint(x: 4, y: 19)); p.addLine(to: CGPoint(x: 5, y: 15))
                    p.addCurve(to: CGPoint(x: 3, y: 10), control1: CGPoint(x: 3, y: 14), control2: CGPoint(x: 3, y: 12))
                    p.addCurve(to: CGPoint(x: 12, y: 2), control1: CGPoint(x: 3, y: 5), control2: CGPoint(x: 7, y: 2))
                    p.addCurve(to: CGPoint(x: 21, y: 11), control1: CGPoint(x: 17, y: 2), control2: CGPoint(x: 21, y: 6))
                    p.addCurve(to: CGPoint(x: 12, y: 20), control1: CGPoint(x: 21, y: 16), control2: CGPoint(x: 17, y: 20))
                    p.addLine(to: CGPoint(x: 4, y: 20)); p.closeSubpath()
                })
            case "magnifyingglass":
                stroke(Path(ellipseIn: CGRect(x: 3, y: 3, width: 14, height: 14)), 2)
                stroke(line([CGPoint(x: 15, y: 15), CGPoint(x: 21, y: 21)]))
            case "ellipsis":
                for y in [5, 12, 19] { fill(Path(ellipseIn: CGRect(x: 10.5, y: CGFloat(y) - 1.5, width: 3, height: 3))) }
            case "plus":
                stroke(line([CGPoint(x: 5, y: 12), CGPoint(x: 19, y: 12)]))
                stroke(line([CGPoint(x: 12, y: 5), CGPoint(x: 12, y: 19)]))
            case "xmark.circle.fill":
                stroke(Path(ellipseIn: CGRect(x: 3, y: 3, width: 18, height: 18)))
                stroke(line([CGPoint(x: 8, y: 8), CGPoint(x: 16, y: 16)]))
                stroke(line([CGPoint(x: 16, y: 8), CGPoint(x: 8, y: 16)]))
            case "chevron.down":
                stroke(line([CGPoint(x: 6, y: 9), CGPoint(x: 12, y: 15), CGPoint(x: 18, y: 9)]))
            case "arrow.left", "arrow.right", "arrow.down.to.line":
                let axis = name == "arrow.left" ? -1.0 : 1.0
                if name == "arrow.down.to.line" {
                    stroke(line([CGPoint(x: 12, y: 3), CGPoint(x: 12, y: 17)]))
                    stroke(line([CGPoint(x: 7, y: 12), CGPoint(x: 12, y: 17), CGPoint(x: 17, y: 12)]))
                    stroke(line([CGPoint(x: 4, y: 21), CGPoint(x: 20, y: 21)]))
                } else {
                    stroke(line([CGPoint(x: 4, y: 12), CGPoint(x: 20, y: 12)]))
                    stroke(line([CGPoint(x: 12, y: 5), CGPoint(x: 12 + 8 * axis, y: 12), CGPoint(x: 12, y: 19)]))
                }
            case "tray.full.fill":
                context.fill(Path { p in
                    p.addRoundedRect(in: CGRect(x: 2, y: 3, width: 20, height: 18), cornerSize: CGSize(width: 2, height: 2))
                    p.addRect(CGRect(x: 5, y: 6, width: 14, height: 8))
                    p.addRoundedRect(in: CGRect(x: 8, y: 11, width: 8, height: 6), cornerSize: CGSize(width: 2, height: 2))
                }, with: ink, style: FillStyle(eoFill: true))
            case "person.badge.plus":
                fill(Path(ellipseIn: CGRect(x: 8, y: 2, width: 10, height: 10)))
                fill(Path { p in
                    p.move(to: CGPoint(x: 2, y: 21)); p.addQuadCurve(to: CGPoint(x: 12, y: 12), control: CGPoint(x: 2, y: 12))
                    p.addQuadCurve(to: CGPoint(x: 16, y: 14), control: CGPoint(x: 15, y: 12))
                    p.addLine(to: CGPoint(x: 16, y: 21)); p.closeSubpath()
                })
                stroke(line([CGPoint(x: 16, y: 18), CGPoint(x: 23, y: 18)]))
                stroke(line([CGPoint(x: 19.5, y: 14.5), CGPoint(x: 19.5, y: 21.5)]))
            case "mic.fill", "mic.slash.fill":
                fill(Path(roundedRect: CGRect(x: 9, y: 2, width: 6, height: 12), cornerRadius: 3))
                stroke(Path { p in p.move(to: CGPoint(x: 5, y: 10)); p.addCurve(to: CGPoint(x: 19, y: 10), control1: CGPoint(x: 5, y: 21), control2: CGPoint(x: 19, y: 21)) })
                stroke(line([CGPoint(x: 12, y: 18), CGPoint(x: 12, y: 22)]))
                stroke(line([CGPoint(x: 9, y: 22), CGPoint(x: 15, y: 22)]))
                if name.contains("slash") { stroke(line([CGPoint(x: 3, y: 3), CGPoint(x: 21, y: 21)])) }
            case "headphones", "speaker.slash.fill":
                stroke(Path { p in p.move(to: CGPoint(x: 3, y: 17)); p.addLine(to: CGPoint(x: 3, y: 11)); p.addCurve(to: CGPoint(x: 21, y: 11), control1: CGPoint(x: 3, y: -1), control2: CGPoint(x: 21, y: -1)); p.addLine(to: CGPoint(x: 21, y: 17)) }, 3)
                fill(Path(roundedRect: CGRect(x: 2, y: 12, width: 5, height: 9), cornerRadius: 2))
                fill(Path(roundedRect: CGRect(x: 17, y: 12, width: 5, height: 9), cornerRadius: 2))
                if name.contains("slash") { stroke(line([CGPoint(x: 3, y: 3), CGPoint(x: 21, y: 21)])) }
            case "bag.fill":
                fill(Path(roundedRect: CGRect(x: 3, y: 7, width: 18, height: 15), cornerRadius: 2))
                stroke(Path { p in p.move(to: CGPoint(x: 8, y: 8)); p.addLine(to: CGPoint(x: 8, y: 5)); p.addCurve(to: CGPoint(x: 16, y: 5), control1: CGPoint(x: 8, y: 0), control2: CGPoint(x: 16, y: 0)); p.addLine(to: CGPoint(x: 16, y: 8)) })
            case "circle.hexagongrid.fill":
                stroke(Path(ellipseIn: CGRect(x: 3, y: 3, width: 18, height: 18)), 4)
                stroke(line([CGPoint(x: 2, y: 5), CGPoint(x: 9, y: 5), CGPoint(x: 9, y: 12), CGPoint(x: 3, y: 12)]), 3)
            case "flag.fill":
                stroke(Path(ellipseIn: CGRect(x: 4, y: 4, width: 16, height: 16)), 3)
                for i in 0..<8 {
                    let a = Double(i) * .pi / 4
                    stroke(line([CGPoint(x: 12 + 9 * cos(a), y: 12 + 9 * sin(a)), CGPoint(x: 12 + 11 * cos(a), y: 12 + 11 * sin(a))]), 3)
                }
            case "gearshape.fill":
                var gear = Path()
                for i in 0..<32 {
                    let a = Double(i) * .pi / 16
                    let r = (i % 4 == 0 || i % 4 == 3) ? 11.0 : 8.0
                    let point = CGPoint(x: 12 + r * cos(a), y: 12 + r * sin(a))
                    if i == 0 { gear.move(to: point) } else { gear.addLine(to: point) }
                }
                gear.closeSubpath(); gear.addEllipse(in: CGRect(x: 8, y: 8, width: 8, height: 8))
                context.fill(gear, with: ink, style: FillStyle(eoFill: true))
            case "questionmark.circle.fill":
                stroke(Path(ellipseIn: CGRect(x: 3, y: 3, width: 18, height: 18)), 3)
                stroke(Path { p in p.move(to: CGPoint(x: 9, y: 9)); p.addCurve(to: CGPoint(x: 12, y: 14), control1: CGPoint(x: 9, y: 3), control2: CGPoint(x: 19, y: 8)) })
                fill(Path(ellipseIn: CGRect(x: 11, y: 17, width: 2, height: 2)))
            case "safari":
                stroke(Path(ellipseIn: CGRect(x: 2, y: 2, width: 20, height: 20)))
                stroke(line([CGPoint(x: 16, y: 8), CGPoint(x: 14, y: 14), CGPoint(x: 8, y: 16), CGPoint(x: 10, y: 10), CGPoint(x: 16, y: 8)]))
            default: break
            }
        }
        .frame(width: size * LayoutMetrics.scale, height: size * LayoutMetrics.scale)
        .accessibilityHidden(true)
    }
}

/// Desktop-only reference symbols, with SF fallback for unmeasured controls.
struct CalibratedDesktopSymbol: View {
    @Environment(\.desktopFriendsCalibration) private var calibrated
    let name: String
    var size: CGFloat = 20
    var calibratedSize: CGFloat? = nil
    var weight: Font.Weight = .regular

    var body: some View {
        if calibrated {
            DesktopFriendsIcon(name: name, size: calibratedSize ?? size)
        } else {
            Image(systemName: name).font(.mood(size, weight: weight))
        }
    }
}

/// One explicit ink color. Native Mac rendering avoids the old 77% resampling.
/// The reference font is explicit; glyph rasterisation is verified separately.
struct CalibratedDesktopText: View {
    @Environment(\.desktopFriendsCalibration) private var calibrated
    @Environment(\.displayScale) private var displayScale
    let value: String
    var size: CGFloat = 14
    var weight: Font.Weight = .regular
    var color: Color = MoodTheme.textPrimary
    var glyphBackground: Color? = nil

    var body: some View {
        if calibrated {
            let font = DesktopFriendsTypography.ctFont(size, weight: weight)
            let descent = CTFontGetDescent(font)
            let lineHeight = CTFontGetAscent(font) + descent + CTFontGetLeading(font)
            let attributes: [NSAttributedString.Key: Any] = [
                NSAttributedString.Key(kCTFontAttributeName as String): font,
                NSAttributedString.Key(kCTForegroundColorAttributeName as String): UIColor(color).cgColor
            ]
            let line = CTLineCreateWithAttributedString(NSAttributedString(string: value, attributes: attributes))
            let inkWidth = CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil))
            // The new renderer keeps typographic advances exact; only the legacy
            // Canvas path reserves a whole point for its rounded backing bounds.
            let width = DesktopGlyphRasterizer.enabled ? inkWidth : ceil(inkWidth)
            GeometryReader { geometry in
            let origin = geometry.frame(in: .global).origin
            let physicalPhase = origin.x * displayScale - floor(origin.x * displayScale)
            if DesktopGlyphRasterizer.enabled && DesktopGlyphRasterizer.imageDelivery,
               let bitmap = DesktopGlyphRasterizer.image(value: value, font: font,
                   color: color, bounds: geometry.size, displayScale: displayScale, phase: physicalPhase,
                   background: DesktopGlyphRasterizer.opaqueDelivery ? glyphBackground : nil) {
                Image(decorative: bitmap, scale: displayScale)
                    .interpolation(.none)
                    .offset(x: -physicalPhase / displayScale,
                            y: geometry.size.height - CGFloat(bitmap.height) / displayScale)
            } else {
            Canvas { context, bounds in
                if DesktopGlyphRasterizer.enabled,
                   let bitmap = DesktopGlyphRasterizer.image(value: value, font: font,
                       color: color, bounds: bounds, displayScale: displayScale, phase: physicalPhase,
                       background: DesktopGlyphRasterizer.opaqueDelivery ? glyphBackground : nil) {
                    context.withCGContext { cg in
                        cg.interpolationQuality = .none
                        cg.translateBy(x: 0, y: bounds.height)
                        cg.scaleBy(x: 1, y: -1)
                        cg.draw(bitmap, in: CGRect(x: -physicalPhase / displayScale, y: 0,
                            width: CGFloat(bitmap.width) / displayScale,
                            height: CGFloat(bitmap.height) / displayScale))
                    }
                    return
                }
                if DesktopGlyphMaskExperiment.enabled,
                   let bitmap = DesktopGlyphMaskExperiment.image(value: value, font: font,
                        color: color, bounds: bounds, displayScale: displayScale) {
                    context.withCGContext { cg in
                        cg.interpolationQuality = .none
                        cg.translateBy(x: 0, y: bounds.height)
                        cg.scaleBy(x: 1, y: -1)
                        cg.draw(bitmap, in: CGRect(x: 0, y: 0,
                            width: CGFloat(bitmap.width) / displayScale,
                            height: CGFloat(bitmap.height) / displayScale))
                    }
                    return
                }
                context.withCGContext { cg in
                    cg.setShouldAntialias(true)
                    cg.setAllowsFontSmoothing(true)
                    cg.setShouldSmoothFonts(true)
                    cg.translateBy(x: 0, y: bounds.height)
                    cg.scaleBy(x: 1, y: -1)
                    cg.textPosition = CGPoint(x: 0, y: descent)
                    let token = CTLineCreateWithAttributedString(NSAttributedString(string: "…", attributes: attributes))
                    CTLineDraw(inkWidth > bounds.width + 0.01 ? CTLineCreateTruncatedLine(line, Double(bounds.width), .end, token) ?? line : line, cg)
                }
            }
            }
            }
            .frame(minWidth: 0, idealWidth: width, maxWidth: width,
                   minHeight: lineHeight, maxHeight: lineHeight)
            .clipped()
            .accessibilityElement()
            .accessibilityLabel(value)
        } else {
            Text(value).font(.mood(size, weight: weight)).foregroundStyle(color)
        }
    }
}
