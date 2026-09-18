import Foundation
import Testing

@testable import Zisla

struct HeadphoneConnectionNoticeTests {
    @Test
    func headphoneGlyphUsesTheNativeAirPodsSymbolAndEffect() throws {
        let source = try String(contentsOf: Self.sideNoticeViewSourceURL, encoding: .utf8)
        let glyph = try Self.sourceSlice(
            in: source,
            from: "private struct HeadphoneGlyph: View",
            to: "private struct HeadphoneBatteryLevels: View"
        )

        #expect(glyph.contains("Image(systemName: isSingleUnit ? \"headphones\" : \"airpods.pro\")"))
        #expect(glyph.contains(".bounce.up.byLayer"))
        #expect(glyph.contains("value: isPresented"))
        #expect(!glyph.contains("airpod.left"))
        #expect(!glyph.contains("airpod.right"))
        #expect(!glyph.contains(".offset("))
        #expect(!glyph.contains(".scaleEffect("))
    }

    @Test
    func headphoneEffectsRespectReduceMotionInBothPresentations() throws {
        let source = try String(contentsOf: Self.sideNoticeViewSourceURL, encoding: .utf8)
        let detail = try Self.sourceSlice(
            in: source,
            from: "private struct HeadphoneConnectionNotice: View",
            to: "private struct HeadphoneGlyph: View"
        )
        let compact = try Self.sourceSlice(
            in: source,
            from: "private struct CompactHeadphoneConnectionBar: View",
            to: "private struct CompactFocusTransitionBar: View"
        )

        for presentation in [detail, compact] {
            #expect(presentation.contains("guard !reduceMotion else { return }"))
            #expect(presentation.contains("isPresented = true"))
            #expect(!presentation.contains("withAnimation"))
        }
    }

    private static var sideNoticeViewSourceURL: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/Zisla/SideNoticeView.swift")
    }

    private static func sourceSlice(
        in source: String,
        from start: String,
        to end: String
    ) throws -> Substring {
        let startRange = try #require(source.range(of: start))
        let endRange = try #require(source[startRange.upperBound...].range(of: end))
        return source[startRange.lowerBound..<endRange.lowerBound]
    }
}
