import AppKit
import SwiftUI
import Testing
import ZislaCore
import ZislaKit
@testable import Zisla

struct VerticalCompactStatusTests {
    @Test
    func verticalTextPreservesGraphemesAndHasAnEllipsisWithinItsBudget() {
        let text = "  A e\u{301} 👨‍👩‍👧‍👦 🇨🇳 \n B"
        #expect(VerticalStatusText.characters(text, availableHeight: 70) == ["A", "e\u{301}", "👨‍👩‍👧‍👦", "🇨🇳", "B"])
        #expect(VerticalStatusText.characters(text, availableHeight: 28) == ["A", "…"])
        #expect(VerticalStatusText.characters(text, availableHeight: 14) == ["…"])
        #expect(VerticalStatusText.characters(text, availableHeight: 13.9).isEmpty)
        #expect(VerticalStatusText.characters(" \n", availableHeight: 100).isEmpty)
    }

    @Test(arguments: [CGFloat(-1), -.greatestFiniteMagnitude, 0, .nan, .infinity, -.infinity])
    func invalidVerticalBudgetsDoNotCreateUnboundedGlyphs(height: CGFloat) {
        #expect(VerticalStatusText.characters("测试", availableHeight: height).isEmpty)
    }

    @Test
    func liveLyricTextUsesTheSameClockForContentAndNaturalLength() throws {
        let notice = IslandNotice(id: "media-active-left", title: "Music", side: .left,
            metadata: ["compactLyric": "旧歌词"])
        var settings = FeatureSettings(islandLayoutStyle: .pill,
            islandPlacement: IslandPlacement(mode: .custom, edge: .left))
        settings.mediaCompactStyle = .detailed
        let presentation = try #require(SideNoticeLayoutEngine().compactBarSizing(
            for: [notice], settings: settings)?.customPillPresentation)
        let date = Date(timeIntervalSince1970: 100)
        let item = NowPlayingSnapshot(title: "fixture", artist: "artist", album: nil, artworkData: nil,
            duration: 60, elapsedTime: 0, timestamp: date, isPlaying: true,
            lyrics: SyncedLyrics(lines: [.init(time: 0, text: "短"), .init(time: 10, text: "长一些的歌词")]))
        let first = CompactPillStatusContent.displayText(for: presentation, settings: settings, item: item, at: date)
        let next = CompactPillStatusContent.displayText(for: presentation, settings: settings, item: item, at: date.addingTimeInterval(10))
        #expect(first == "短" && next == "长一些的歌词")
        #expect(presentation.length(thickness: 32, edge: .left, text: first) == 90)
        #expect(presentation.length(thickness: 32, edge: .left, text: next) == 160)
        #expect(presentation.text == "旧歌词")
        var paused = item
        paused.isPlaying = false
        #expect(CompactPillStatusContent.displayText(for: presentation, settings: settings, item: paused,
            at: date.addingTimeInterval(20)) == "短")
        settings.mediaShowLyricsAndInfo = false
        #expect(CompactPillStatusContent.displayText(for: presentation, settings: settings, item: item, at: date) == "旧歌词")
        #expect(CompactPillStatusContent.displayText(for: presentation, settings: settings, item: nil, at: date) == "旧歌词")
    }

    @Test(arguments: IslandEdge.allCases)
    @MainActor
    func everyCompactStatusPutsVisibleTextImmediatelyAfterItsIcon(edge: IslandEdge) throws {
        let symbolNotices = [
            IslandNotice(id: "toolbox-reminder-left", title: "亮屏", detail: "保持", symbolName: "display"),
            IslandNotice(id: "browser-download-left", title: "下载", detail: "下载", progress: 0.5),
            IslandNotice(id: "focus-countdown-left", title: "专注", detail: "25:00"),
            IslandNotice(id: "voice-processing-left", title: "语音", detail: "处理"),
            IslandNotice(id: "mail-notification-left", title: "邮件", detail: "新邮件"),
            IslandNotice(id: "focus-transition-left", title: "状态", detail: "已保存", symbolName: "exclamationmark.triangle.fill"),
        ]
        var settings = FeatureSettings(islandLayoutStyle: .pill,
            islandPlacement: IslandPlacement(mode: .custom, edge: edge))
        settings.mailCompactStyle = .detailed
        for notice in symbolNotices {
            let presentation = try #require(SideNoticeLayoutEngine().compactBarSizing(
                for: [notice], settings: settings)?.customPillPresentation)
            let length = presentation.length(thickness: 32, edge: edge)
            let size = edge.isVertical ? CGSize(width: 32, height: length) : CGSize(width: length, height: 32)
            let renderer = ImageRenderer(content: CompactPillStatusContent(presentation: presentation,
                text: presentation.text, edge: edge, visualizationStyle: .waveform, item: nil)
                .frame(width: size.width, height: size.height)
                .background(.black))
            renderer.scale = 2
            let bitmap = NSBitmapImageRep(cgImage: try #require(renderer.cgImage))
            #expect(bitmap.pixelsWide == Int(size.width * 2) && bitmap.pixelsHigh == Int(size.height * 2))
            let textStart = 38 * 2
            let lengthPixels = edge.isVertical ? bitmap.pixelsHigh : bitmap.pixelsWide
            var firstTextPixel: Int?
            for axis in textStart..<min(lengthPixels, textStart + 32) {
                let perpendicular = edge.isVertical ? bitmap.pixelsWide : bitmap.pixelsHigh
                for other in 0..<perpendicular {
                    let x = edge.isVertical ? other : axis
                    let y = edge.isVertical ? axis : other
                    if let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB), color.redComponent > 0.25 {
                        firstTextPixel = axis
                        break
                    }
                }
                if firstTextPixel != nil { break }
            }
            #expect(firstTextPixel != nil, "\(notice.id) must show text immediately after the icon, without a camera gap")
        }
    }

    @Test
    func aTransientMessageUsesTheSameWarningAndTextAsItsNaturalLength() {
        let presentation = CompactPillStatusContent.transientPresentation(message: "  已保存  ")
        #expect(presentation.priority == .transient)
        #expect(presentation.notice.symbolName == "exclamationmark.triangle.fill")
        #expect(presentation.text == "已保存")
        #expect(presentation.length(thickness: 32, edge: .left) == 80)
        #expect(!presentation.showsWaveform && !presentation.isMedia)
    }

    @Test(arguments: IslandEdge.allCases)
    @MainActor
    func compactContentKeepsItsColoredIconAtTheStartAndTextWithinTheAdjacentColumn(edge: IslandEdge) throws {
        let icon = NSImage(size: NSSize(width: 24, height: 24), flipped: false) { rect in
            NSColor.red.setFill()
            rect.fill()
            return true
        }
        let data = try #require(icon.tiffRepresentation)
        let presentation = CompactPillStatusPresentation(priority: .mail,
            notice: IslandNotice(id: "mail-fixture", title: "fixture", artworkData: data), text: "字字字字")
        let length = presentation.length(thickness: 32, edge: edge)
        let size = edge.isVertical ? CGSize(width: 32, height: length) : CGSize(width: length, height: 32)
        let renderer = ImageRenderer(content: CompactPillStatusContent(presentation: presentation,
            text: presentation.text, edge: edge, visualizationStyle: .waveform, item: nil)
            .environment(\.layoutDirection, .leftToRight)
            .frame(width: size.width, height: size.height).background(.black))
        renderer.scale = 2
        let bitmap = NSBitmapImageRep(cgImage: try #require(renderer.cgImage))
        var iconBounds = CGRect.null
        var textBounds = CGRect.null
        for y in 0..<bitmap.pixelsHigh {
            for x in 0..<bitmap.pixelsWide {
                let color = try #require(bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB))
                let point = CGRect(x: CGFloat(x) / 2, y: CGFloat(y) / 2, width: 0.5, height: 0.5)
                if color.redComponent > 0.6 && color.greenComponent < 0.2 && color.blueComponent < 0.2 {
                    iconBounds = iconBounds.union(point)
                }
                if min(color.redComponent, color.greenComponent, color.blueComponent) > 0.65 {
                    textBounds = textBounds.union(point)
                }
            }
        }
        #expect(!iconBounds.isNull && !textBounds.isNull)
        #expect(abs(iconBounds.midX - 16) < 1 && abs(iconBounds.midY - 16) < 1,
                "The icon must stay centered in the first 32-point square")
        if edge.isVertical {
            #expect(textBounds.minY >= 38 && textBounds.minY < 44)
            #expect(textBounds.height > textBounds.width * 2 && textBounds.maxX <= 32)
        } else {
            #expect(textBounds.minX >= 38 && textBounds.minX < 44)
            #expect(textBounds.width > textBounds.height * 2 && textBounds.maxY <= 32)
        }
    }
}
