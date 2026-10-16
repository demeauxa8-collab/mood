import CoreText
import SwiftUI
import Testing
@testable import mood

#if targetEnvironment(macCatalyst)
@MainActor
struct DesktopPixelTests {
    @Test func cornerMasksAreSymmetricAndKeepSinglePixelInsets() throws {
        for scale: CGFloat in [1, 2, 3] {
            let outer = try #require(DesktopCornerCoverage.image(radius: 8, inset: 0, displayScale: scale))
            let inner = try #require(DesktopCornerCoverage.image(radius: 8, inset: 1 / scale, displayScale: scale))
            #expect(outer.width == Int(16 * scale) + 1)
            #expect(!outer.shouldInterpolate)
            let od = try #require(outer.dataProvider?.data)
            let id = try #require(inner.dataProvider?.data)
            let ob = try #require(CFDataGetBytePtr(od))
            let ib = try #require(CFDataGetBytePtr(id))
            let n = outer.width, middle = n / 2
            #expect(ob[middle * 4 + 3] == 255)
            #expect(ib[middle * 4 + 3] == 0)
            #expect(ib[(n + middle) * 4 + 3] == 255)
            for y in 0..<n {
                for x in 0..<n {
                    let i = (y * n + x) * 4 + 3
                    #expect(ob[i] == ob[(y * n + n - x - 1) * 4 + 3])
                    #expect(ob[i] == ob[((n - y - 1) * n + x) * 4 + 3])
                    #expect(ib[i] <= ob[i])
                }
            }
        }
    }

    @Test func cornerMasksCacheGeometryAndRejectUnsafeInputs() throws {
        let a = try #require(DesktopCornerCoverage.image(radius: 8, inset: 1, displayScale: 1))
        let b = try #require(DesktopCornerCoverage.image(radius: 8, inset: 1, displayScale: 1))
        #expect(a === b)
        #expect(DesktopCornerCoverage.image(radius: .nan, inset: 0, displayScale: 1) == nil)
        #expect(DesktopCornerCoverage.image(radius: 8, inset: -1, displayScale: 1) == nil)
        #expect(DesktopCornerCoverage.image(radius: 8, inset: 8, displayScale: 1) == nil)
        #expect(DesktopCornerCoverage.image(radius: 8, inset: 0, displayScale: 0) == nil)
        #expect(DesktopCornerCoverage.image(radius: 65, inset: 0, displayScale: 1) == nil)
    }

    @Test func roundedSurfacesKeepMeasuredGeometry() {
        #expect(DesktopSurfaceMetrics.composerRadius == 8)
        #expect(DesktopSurfaceMetrics.profileRadius == 9)
        #expect(DesktopSurfaceMetrics.profileButtonFontSize == 16)
        #expect(DesktopSurfaceMetrics.profileButtonTextOffset == -1)
        #expect(DesktopSurfaceMetrics.profileColumnWidth - 2 * DesktopSurfaceMetrics.profileInset == 306)
        #expect(DesktopSurfaceMetrics.radius(12, size: CGSize(width: 10, height: 100)) == 5)
        #expect(DesktopSurfaceMetrics.radius(-2, size: CGSize(width: 100, height: 100)) == 0)
        #expect(DesktopSurfaceMetrics.radius(.nan, size: CGSize(width: 100, height: 100)) == 0)
    }

    @Test func workspaceOwnsOnlyTopAndLeadingEdge() {
        let path = DesktopWorkspaceBorder().path(in: CGRect(x: 0, y: 0, width: 100, height: 200))
        #expect(path.boundingRect.minX == 0.5)
        #expect(path.boundingRect.minY == 0.5)
        #expect(path.boundingRect.maxX == 100)
        #expect(path.boundingRect.maxY == 200)
    }

    @Test func friendsTabsFollowPresenceNotTheSearchQuery() {
        #expect(DesktopNavigationIndex.friendsTabs(hasOnlineFriends: true) == [.online, .all, .pending])
        #expect(DesktopNavigationIndex.friendsTabs(hasOnlineFriends: false) == [.all, .pending])
    }

    private var navigationFixtures: [DesktopNavigationEntry] {
        [DesktopNavigationEntry(id: .friends, name: "Amis", detail: "Messages privés", icon: "figure.wave", kind: "@"),
         DesktopNavigationEntry(id: .directMessage(UUID()), name: "Clara", detail: "Message privé", icon: "person.fill", kind: "@"),
         DesktopNavigationEntry(id: .channel(server: UUID(), channel: UUID()), name: "général", detail: "Studio", icon: "number", kind: "#"),
         DesktopNavigationEntry(id: .channel(server: UUID(), channel: UUID()), name: "Vocal", detail: "Studio", icon: "speaker.wave.2", kind: "!")]
    }

    @Test func quickNavigationFiltersActualEntryKindsAndNames() {
        let entries = navigationFixtures
        #expect(DesktopNavigationIndex.filter(entries, query: " @ CLARA ").map(\.name) == ["Clara"])
        #expect(DesktopNavigationIndex.filter(entries, query: "#").map(\.name) == ["général"])
        #expect(DesktopNavigationIndex.filter(entries, query: "!studio").map(\.name) == ["Vocal"])
        #expect(DesktopNavigationIndex.filter(entries, query: "nothing").isEmpty)
        #expect(DesktopNavigationIndex.filter(entries, query: "").count == entries.count)
    }

    @Test func quickNavigationSelectionIsBoundedAndStable() {
        let entries = navigationFixtures
        #expect(DesktopNavigationIndex.selection(in: entries, current: entries[0].id, delta: 1) == entries[1].id)
        #expect(DesktopNavigationIndex.selection(in: entries, current: entries[0].id, delta: -1) == entries[0].id)
        #expect(DesktopNavigationIndex.selection(in: entries, current: entries.last?.id, delta: 1) == entries.last?.id)
        #expect(DesktopNavigationIndex.selection(in: [], current: nil, delta: 1) == nil)
        #expect(DesktopNavigationIndex.selection(in: entries, current: .directMessage(UUID()), delta: 0) == entries[0].id)
    }

    @Test func quickNavigationUsesLoadedServersAndConversations() {
        let servers = MockData.servers
        let conversations = MockData.dmConversations
        let entries = DesktopNavigationIndex.entries(servers: servers, conversations: conversations)
        #expect(entries.first?.id == .friends)
        #expect(DesktopNavigationIndex.filter(entries, query: "*").count == servers.count)
        #expect(DesktopNavigationIndex.filter(entries, query: "@").count == conversations.count + 1)
        #expect(entries.count == 1 + servers.count + servers.flatMap(\.categories).flatMap(\.channels).count + conversations.count)
        #expect(DesktopNavigationIndex.filter(entries, query: "*" + servers[0].name).first?.id == .server(servers[0].id))
        #expect(DesktopNavigationIndex.filter(entries, query: "!").allSatisfy { $0.kind == "!" })
    }

    @Test func rulesAreOnePhysicalPixel() {
        for scale: CGFloat in [1, 2, 3] {
            #expect(DesktopPixelMetrics.thickness(displayScale: scale) * scale == 1)
        }
    }

    @Test func invalidDensityDoesNotProduceInvalidFrames() {
        #expect(DesktopPixelMetrics.thickness(displayScale: 0) == 1)
        #expect(DesktopPixelMetrics.thickness(displayScale: .nan) == 1)
        #expect(DesktopPixelMetrics.thickness(displayScale: .infinity) == 1)
    }

    @Test func headersHaveNoFractionalRuleOffset() {
        #expect(DesktopPixelMetrics.legacyHeaderOffset == 0)
        #expect(LayoutMetrics.scale == 1)
        #expect(LayoutMetrics.desktopTitleBarHeight + LayoutMetrics.desktopHeaderHeight == 82)
    }

    @Test func measuredColumnGeometryIsPreserved() {
        #expect(LayoutMetrics.serverBarWidth + LayoutMetrics.channelListWidth == 357)
        #expect(LayoutMetrics.userPanelWidth == 341)
        #expect(LayoutMetrics.memberListWidth == 264)
        #expect(LayoutMetrics.friendsActivityPanelWidth == 419)
    }

    @Test func comparisonFontsResolveOrUseSystemFallback() {
        let cases: [(Font.Weight, String)] = [
            (.regular, "ggsans-Normal"), (.medium, "ggsans-Medium"),
            (.semibold, "ggsans-Semibold"), (.bold, "ggsans-Bold")
        ]
        for (weight, name) in cases {
            let font = DesktopFriendsTypography.ctFont(16, weight: weight)
            if DesktopFriendsTypography.hasLocalFonts {
                #expect(CTFontCopyPostScriptName(font) as String == name)
            } else {
                #expect(!(CTFontCopyPostScriptName(font) as String).contains("ggsans"))
            }
            #expect(CTFontGetSize(font) == 16)
        }
    }

    @Test func glyphPositionsUseQuarterPixelsWithoutLayoutDrift() {
        #expect(DesktopGlyphRasterizer.snap(0.12) == 0)
        #expect(DesktopGlyphRasterizer.snap(0.13) == 0.25)
        #expect(DesktopGlyphRasterizer.snap(1.88) == 2)
        #expect(DesktopGlyphRasterizer.layoutPhase(0.007) == 0)
        #expect(DesktopGlyphRasterizer.layoutPhase(0.672) == 43.0 / 64)
    }

    @Test func glyphCoverageIsBoundedAndMonotonic() {
        #expect(DesktopGlyphRasterizer.coverage(0) == 255)
        #expect(DesktopGlyphRasterizer.coverage(255) == 0)
        for black in 0..<255 {
            #expect(DesktopGlyphRasterizer.coverage(UInt8(black)) >= DesktopGlyphRasterizer.coverage(UInt8(black + 1)))
        }
    }

    @Test func invalidGlyphBoundsAreRejected() {
        let font = DesktopFriendsTypography.ctFont(16, weight: .medium)
        for bounds in [CGSize.zero, CGSize(width: CGFloat.nan, height: 22),
                       CGSize(width: 8193, height: 22), CGSize(width: 100, height: 257)] {
            #expect(DesktopGlyphRasterizer.image(value: "Amis", font: font, color: .white,
                bounds: bounds, displayScale: 1) == nil)
        }
        for scale: CGFloat in [0, .nan, .infinity] {
            #expect(DesktopGlyphRasterizer.image(value: "Amis", font: font, color: .white,
                bounds: CGSize(width: 100, height: 22), displayScale: scale) == nil)
        }
        #expect(DesktopGlyphRasterizer.image(value: "Amis", font: font, color: .white,
            bounds: CGSize(width: 100, height: 22), displayScale: 1, phase: 1e300) == nil)
    }

    @Test func colourMasksPreserveEndpointsAndMonotonicity() {
        for luminance in stride(from: 0, through: 255, by: 1) {
            #expect(DesktopGlyphRasterizer.preblend(coverage: 0, luminance: UInt8(luminance)) == 0)
            #expect(DesktopGlyphRasterizer.preblend(coverage: 255, luminance: UInt8(luminance)) == 255)
            for alpha in 0..<255 {
                #expect(DesktopGlyphRasterizer.preblend(coverage: UInt8(alpha), luminance: UInt8(luminance)) <=
                    DesktopGlyphRasterizer.preblend(coverage: UInt8(alpha + 1), luminance: UInt8(luminance)))
            }
        }
    }

    @Test func lightMasksRemainUnchangedAndGreyCorrectionIsShared() {
        for alpha in 0...255 {
            #expect(DesktopGlyphRasterizer.preblend(coverage: UInt8(alpha), luminance: 239) == UInt8(alpha))
            #expect(DesktopGlyphRasterizer.preblend(coverage: UInt8(alpha), luminance: 251) == UInt8(alpha))
            #expect(DesktopGlyphRasterizer.preblend(coverage: UInt8(alpha), luminance: 150) ==
                DesktopGlyphRasterizer.preblend(coverage: UInt8(alpha), luminance: 151))
        }
    }

    @Test func opaqueBlendPreservesColoursWithoutExtraEdgeRounding() {
        #expect(DesktopGlyphRasterizer.blend(foreground: 150, background: 26, alpha: 0) == 26)
        #expect(DesktopGlyphRasterizer.blend(foreground: 150, background: 26, alpha: 255) == 150)
        #expect(DesktopGlyphRasterizer.blend(foreground: 251, background: 26, alpha: 128) == 138)
    }

    @Test func glyphImagesRespectDensityAndCacheInputs() throws {
        let font = DesktopFriendsTypography.ctFont(16, weight: .medium)
        let bounds = CGSize(width: 100, height: 22)
        let first = try #require(DesktopGlyphRasterizer.image(value: "Clara", font: font,
            color: .white, bounds: bounds, displayScale: 1))
        let repeated = try #require(DesktopGlyphRasterizer.image(value: "Clara", font: font,
            color: .white, bounds: bounds, displayScale: 1))
        let different = try #require(DesktopGlyphRasterizer.image(value: "Léa", font: font,
            color: .white, bounds: bounds, displayScale: 1))
        let retina = try #require(DesktopGlyphRasterizer.image(value: "Clara", font: font,
            color: .white, bounds: bounds, displayScale: 2))
        #expect(first === repeated)
        #expect(first !== different)
        #expect(first.width == 100 && first.height == 22)
        #expect(retina.width == 200 && retina.height == 44)
        #expect(!first.shouldInterpolate)
    }

    @Test func glyphOpacityAndBackgroundAreNotDiscarded() throws {
        let font = DesktopFriendsTypography.ctFont(16, weight: .medium)
        let bounds = CGSize(width: 100, height: 22)
        let transparent = try #require(DesktopGlyphRasterizer.image(value: "Amis", font: font,
            color: .white.opacity(0), bounds: bounds, displayScale: 1))
        let transparentData = try #require(transparent.dataProvider?.data)
        let bytes = try #require(CFDataGetBytePtr(transparentData))
        for index in stride(from: 3, to: CFDataGetLength(transparentData), by: 4) {
            #expect(bytes[index] == 0)
        }
        let opaque = try #require(DesktopGlyphRasterizer.image(value: "Amis", font: font,
            color: .white.opacity(0), bounds: bounds, displayScale: 1, background: .black))
        let opaqueData = try #require(opaque.dataProvider?.data)
        let opaqueBytes = try #require(CFDataGetBytePtr(opaqueData))
        for index in stride(from: 0, to: CFDataGetLength(opaqueData), by: 4) {
            #expect(opaqueBytes[index] == 0 && opaqueBytes[index + 3] == 255)
        }
    }

    @Test func truncationWorksAndColourEmojiKeepNativeRendering() {
        let font = DesktopFriendsTypography.ctFont(16, weight: .medium)
        #expect(DesktopGlyphRasterizer.image(value: "Une étiquette vraiment très longue", font: font,
            color: .white, bounds: CGSize(width: 40, height: 22), displayScale: 1) != nil)
        #expect(DesktopGlyphRasterizer.image(value: "😊", font: font,
            color: .white, bounds: CGSize(width: 40, height: 22), displayScale: 1) == nil)
    }
}
#endif
