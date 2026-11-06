import AppKit
import SwiftUI
import Testing
import ZislaCore
import ZislaKit
@testable import Zisla

struct VerticalCompactStatusTests {
    @Test(.serialized, arguments: AppLanguage.allCases) @MainActor
    func updateStatusExposesTheSameLocalizedTooltipAsTheNotch(language: AppLanguage) async throws {
        let releaseAccessibility = EnhancedAccessibilityTestScope.acquire()
        defer { releaseAccessibility() }
        let previousLanguage = UserDefaults.standard.object(forKey: AppLocalization.defaultsKey)
        UserDefaults.standard.set(language.rawValue, forKey: AppLocalization.defaultsKey)
        defer {
            if let previousLanguage { UserDefaults.standard.set(previousLanguage, forKey: AppLocalization.defaultsKey) }
            else { UserDefaults.standard.removeObject(forKey: AppLocalization.defaultsKey) }
        }
        let key = "%@有可用更新"
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        let table = try #require(NSDictionary(contentsOf: root.appendingPathComponent(
            "Resources/Localization/\(language.rawValue).lproj/Localizable.strings")) as? [String: String])
        let translation = try #require(table[key])
        #expect(translation.contains("%@"))
        #expect(AppLocalization.string(key, language: language) == translation)
        let expected = String(format: translation, locale: language.locale, "Codex")
        let presentation = CompactPillStatusPresentation(priority: .updateAvailable,
            notice: IslandNotice(id: "update-available-cli-codex-left", title: "Codex", symbolName: "sparkles"), text: "")
        let host = NSHostingView(rootView: CompactPillStatusContent(presentation: presentation,
            text: "", edge: .top, visualizationStyle: .waveform, item: nil, date: .distantPast)
            .frame(width: 78, height: 32).background(.black).environment(\.colorScheme, .dark))
        host.sizingOptions = []
        let window = NSWindow(contentRect: CGRect(x: 20000, y: 0, width: 78, height: 32),
            styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.alphaValue = 0
        window.contentView = host
        window.orderFrontRegardless()
        defer { window.close() }
        host.layoutSubtreeIfNeeded()
        await withCheckedContinuation { continuation in DispatchQueue.main.async { continuation.resume() } }
        var labels: [String] = []
        func visit(_ object: NSObject) {
            for key in ["accessibilityLabel", "accessibilityHelp"] {
                if object.responds(to: NSSelectorFromString(key)), let value = object.value(forKey: key) as? String {
                    labels.append(value)
                }
            }
            if object.responds(to: NSSelectorFromString("accessibilityChildren")) {
                for child in object.value(forKey: "accessibilityChildren") as? [NSObject] ?? [] { visit(child) }
            }
        }
        visit(host)
        #expect(labels.contains(expected), "The update status must announce and explain the available update in \(language.rawValue): \(labels)")
    }

    @Test
    func shortNumbersUseOneLineOfTheNaturalVerticalLength() {
        for text in ["20%", "25:00", "(1)", "[]", "12.5", "？，"] {
            let presentation = CompactPillStatusPresentation(priority: .transient,
                notice: IslandNotice(id: "fixture", title: "fixture"), text: text)
            #expect(presentation.length(thickness: 32, edge: .left) == 68,
                    "\(text) fits one 14pt row between the icon and two 12pt outer insets")
            #expect(CompactPillStatusPresentation.verticalTextRows(text, availableWidth: 32,
                availableHeight: 14).map(\.text) == [text])
        }
    }

    @Test
    func oversizedNumberRunsUseTheFewestRowsThatFitTheirWidth() {
        let rows = CompactPillStatusPresentation.verticalTextRows("12.34567890%", availableWidth: 24, availableHeight: 140)
        #expect(rows.map(\.text).joined() == "12.34567890%")
        #expect(rows.contains { $0.text.count > 1 })
        for row in rows {
            let width = ceil((row.text as NSString).size(withAttributes: [.font: NSFont.systemFont(ofSize: 11, weight: .medium)]).width)
            #expect(width <= 24)
            #expect(!row.rotatesClockwise)
        }
        let presentation = CompactPillStatusPresentation(priority: .transient,
            notice: IslandNotice(id: "fixture", title: "fixture"), text: "12.34567890%")
        #expect(presentation.length(thickness: 24, edge: .left) == 46 + CGFloat(rows.count) * 14)
    }

    @Test
    func onlyStandaloneVerticalBracketsRotateAndOrdinaryPunctuationStaysUpright() {
        for bracket in "()（）[]［］【】{}｛｝〈〉《》「」『』〔〕" {
            let rows = CompactPillStatusPresentation.verticalTextRows("甲\(bracket)乙", availableWidth: 32, availableHeight: 140)
            #expect(rows.map(\.text) == ["甲", String(bracket), "乙"])
            #expect(rows.map(\.rotatesClockwise) == [false, true, false])
        }
        let punctuation = CompactPillStatusPresentation.verticalTextRows("甲。？乙", availableWidth: 32, availableHeight: 140)
        #expect(punctuation.map(\.text) == ["甲", "。？", "乙"])
        #expect(punctuation.allSatisfy { !$0.rotatesClockwise })
        let inline = CompactPillStatusPresentation.verticalTextRows("甲(1)乙", availableWidth: 32, availableHeight: 140)
        #expect(inline.map(\.text) == ["甲", "(1)", "乙"])
        #expect(inline.allSatisfy { !$0.rotatesClockwise })
        let paired = CompactPillStatusPresentation.verticalTextRows("甲[]乙", availableWidth: 32, availableHeight: 140)
        #expect(paired.map(\.text) == ["甲", "[]", "乙"])
        #expect(paired.allSatisfy { !$0.rotatesClockwise }, "Brackets sharing one horizontal row must stay horizontal")
        let overflow = CompactPillStatusPresentation.verticalTextRows("[123456]", availableWidth: 24, availableHeight: 140)
        #expect(overflow.first?.text == "[" && overflow.first?.rotatesClockwise == true)
        #expect(overflow.last?.text == "]" && overflow.last?.rotatesClockwise == true)
        #expect(overflow.dropFirst().dropLast().allSatisfy { !$0.rotatesClockwise })
    }

    @Test @MainActor
    func monitorReadingSizesReserveTheirActualRowsAndKeepTheApplicationIconSmall() {
        #expect(IslandStatusIcon.readingSize("20%") == CGSize(width: 32, height: 44))
        #expect(IslandStatusIcon.readingSize("25:00") == CGSize(width: 32, height: 44))
        #expect(IslandStatusIcon.readingSize("--") == CGSize(width: 32, height: 44))
        #expect(IslandStatusIcon.readingSize(" ").height == 30)
        #expect(IslandStatusIcon(id: "app", content: .application, tooltip: "zisla").size(edge: .left)
            == CGSize(width: 24, height: 24))
        let reading = "2 GB/8 GB"
        let rows = CompactPillStatusPresentation.verticalTextRows(reading, availableWidth: 32, availableHeight: 200)
        #expect(IslandStatusIcon.readingSize(reading).height == 30 + CGFloat(rows.count) * 14)
    }

    @Test @MainActor
    func verticalTextRendersOneLineAndRotatesOnlyStandaloneBracketsClockwise() throws {
        func render(_ content: some View) throws -> NSBitmapImageRep {
            let renderer = ImageRenderer(content: content.frame(width: 32, height: 42).foregroundStyle(.white).background(.black))
            renderer.scale = 2
            return NSBitmapImageRep(cgImage: try #require(renderer.cgImage))
        }
        func expected(_ character: String, angle: Double) -> some View {
            VStack(spacing: 1) {
                Text("甲").font(.system(size: 11, weight: .medium)).fixedSize().frame(height: 13)
                Text(character).font(.system(size: 11, weight: .medium)).fixedSize()
                    .rotationEffect(.degrees(angle)).frame(height: 13)
                Text("乙").font(.system(size: 11, weight: .medium)).fixedSize().frame(height: 13)
            }
        }
        func differences(_ first: NSBitmapImageRep, _ second: NSBitmapImageRep) throws -> Int {
            #expect(first.pixelsWide == second.pixelsWide && first.pixelsHigh == second.pixelsHigh)
            var changed = 0
            for y in 0..<first.pixelsHigh {
                for x in 0..<first.pixelsWide {
                    let a = try #require(first.colorAt(x: x, y: y)?.usingColorSpace(.sRGB))
                    let b = try #require(second.colorAt(x: x, y: y)?.usingColorSpace(.sRGB))
                    if abs(a.redComponent - b.redComponent) > 0.01 { changed += 1 }
                }
            }
            return changed
        }
        for character in ["（", "[", "【"] {
            let actual = try render(VerticalStatusText(text: "甲\(character)乙", availableWidth: 32, availableHeight: 42))
            #expect(try differences(actual, render(expected(character, angle: 90))) == 0)
            #expect(try differences(actual, render(expected(character, angle: -90))) > 10,
                    "A standalone \(character) must face clockwise, not counterclockwise")
        }
        for character in ["。", "？"] {
            let actual = try render(VerticalStatusText(text: "甲\(character)乙", availableWidth: 32, availableHeight: 42))
            #expect(try differences(actual, render(expected(character, angle: 0))) == 0)
        }
        let numbers = try render(VerticalStatusText(text: "20%", availableWidth: 32, availableHeight: 14))
        let reference = try render(Text("20%").font(.system(size: 11, weight: .medium)).fixedSize().frame(height: 13))
        #expect(try differences(numbers, reference) == 0, "Short numeric readings must use the same pixels as one horizontal Text")
        let legacy = try render(VerticalStatusText(text: "20", availableHeight: 14))
        let legacyReference = try render(Text("20").font(.system(size: 11, weight: .medium)).fixedSize().frame(height: 13))
        #expect(try differences(legacy, legacyReference) == 0, "Existing 24pt callers retain a usable width without extra configuration")
    }

    @Test @MainActor
    func horizontalMonitorTextUsesTheSameMeasuredFontWithoutCroppingItsUnits() async throws {
        let text = "↓123.45 MB/s ↑67.89 MB/s"
        let icon = IslandStatusIcon(id: "network", content: .metric(.network, text: text, image: nil, style: .detailed), tooltip: "Network")
        let measured = try #require(IslandStatusIconLayout.size(icons: [icon], edge: .top))
        let renderSize = CGSize(width: measured.width + 80, height: 32)
        func render(_ content: some View) async throws -> NSBitmapImageRep {
            let host = NSHostingView(rootView: content.frame(width: renderSize.width, height: renderSize.height)
                .foregroundStyle(.white).background(.black))
            host.sizingOptions = []
            let window = NSWindow(contentRect: CGRect(origin: CGPoint(x: 20000, y: 0), size: renderSize),
                styleMask: .borderless, backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.alphaValue = 0
            window.contentView = host
            window.orderFrontRegardless()
            defer { window.close() }
            host.layoutSubtreeIfNeeded()
            host.displayIfNeeded()
            await withCheckedContinuation { continuation in
                DispatchQueue.main.async { continuation.resume() }
            }
            let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
            host.cacheDisplay(in: host.bounds, to: bitmap)
            return bitmap
        }
        let actual = try await render(IslandStatusIconStrip(icons: [icon], edge: .top, date: .distantPast)
            .frame(width: measured.width, height: measured.height))
        let expected = try await render(HStack(spacing: 6) {
            Image(systemName: SystemMonitorMenuBarMetric.network.symbolName).frame(width: 18)
            Text(text).font(.system(size: 12, weight: .medium)).monospacedDigit().fixedSize()
        }.frame(width: icon.size(edge: .top).width, height: 24)
            .padding(.horizontal, 8).padding(.vertical, 4)
            .frame(width: measured.width, height: measured.height))
        var changed = 0
        for y in 0..<actual.pixelsHigh {
            for x in 0..<actual.pixelsWide {
                let a = try #require(actual.colorAt(x: x, y: y)?.usingColorSpace(.sRGB))
                let b = try #require(expected.colorAt(x: x, y: y)?.usingColorSpace(.sRGB))
                if abs(a.redComponent - b.redComponent) > 0.02 { changed += 1 }
            }
        }
        #expect(changed == 0, "The complete network text must match the measured system font, including both MB/s suffixes")
    }

    @Test
    func verticalTextPreservesGraphemesAndHasAnEllipsisWithinItsBudget() {
        let text = "  A e\u{301} 👨‍👩‍👧‍👦 🇨🇳 \n B"
        #expect(CompactPillStatusPresentation.verticalTextRows(text, availableWidth: 24, availableHeight: 70).map(\.text)
            == ["A", "e\u{301}", "👨‍👩‍👧‍👦", "🇨🇳", "B"])
        #expect(CompactPillStatusPresentation.verticalTextRows(text, availableWidth: 24, availableHeight: 28).map(\.text) == ["A", "…"])
        #expect(CompactPillStatusPresentation.verticalTextRows(text, availableWidth: 24, availableHeight: 14).map(\.text) == ["…"])
        #expect(CompactPillStatusPresentation.verticalTextRows(text, availableWidth: 24, availableHeight: 13.9).isEmpty)
        #expect(CompactPillStatusPresentation.verticalTextRows(" \n", availableWidth: 24, availableHeight: 100).isEmpty)
    }

    @Test(arguments: [CGFloat(-1), -.greatestFiniteMagnitude, 0, .nan, .infinity, -.infinity])
    func invalidVerticalBudgetsDoNotCreateUnboundedGlyphs(height: CGFloat) {
        #expect(CompactPillStatusPresentation.verticalTextRows("测试", availableWidth: 24, availableHeight: height).isEmpty)
        #expect(CompactPillStatusPresentation.verticalTextRows("测试", availableWidth: height, availableHeight: 100).isEmpty)
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
        #expect(presentation.length(thickness: 32, edge: .left, text: first) == 98)
        #expect(presentation.length(thickness: 32, edge: .left, text: next) == 168)
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
                text: presentation.text, edge: edge, visualizationStyle: .waveform, item: nil, date: .now)
                .frame(width: size.width, height: size.height)
                .background(.black))
            renderer.scale = 2
            let bitmap = NSBitmapImageRep(cgImage: try #require(renderer.cgImage))
            #expect(bitmap.pixelsWide == Int(size.width * 2) && bitmap.pixelsHigh == Int(size.height * 2))
            let textStart = 42 * 2
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
        #expect(presentation.length(thickness: 32, edge: .left) == 96)
        #expect(!presentation.showsWaveform && !presentation.isMedia)
    }

    @Test(arguments: IslandEdge.allCases) @MainActor
    func aiCountsAndMediaContentLeaveClearSpaceAtTheEnd(edge: IslandEdge) throws {
        let presentations = [
            CompactPillStatusPresentation(priority: .aiActivity,
                notice: IslandNotice(id: "ai-active-openai", title: "AI"), text: "2"),
            CompactPillStatusPresentation(priority: .aiActivity,
                notice: IslandNotice(id: "ai-active-openai", title: "AI"), text: "999+"),
            CompactPillStatusPresentation(priority: .media,
                notice: IslandNotice(id: "media-active-fixture", title: "Music"), text: "爱的期限"),
            CompactPillStatusPresentation(priority: .media,
                notice: IslandNotice(id: "media-active-fixture", title: "Music"), text: "爱的期限", showsWaveform: true),
            CompactPillStatusPresentation(priority: .media,
                notice: IslandNotice(id: "media-active-fixture", title: "Music"), text: "", showsWaveform: true),
        ]
        for presentation in presentations {
            let length = presentation.length(thickness: 32, edge: edge)
            let size = edge.isVertical ? CGSize(width: 32, height: length) : CGSize(width: length, height: 32)
            let renderer = ImageRenderer(content: CompactPillStatusContent(presentation: presentation,
                text: presentation.text, edge: edge, visualizationStyle: .waveform, item: nil, date: .now)
                .frame(width: size.width, height: size.height).background(.black))
            renderer.scale = 2
            let bitmap = NSBitmapImageRep(cgImage: try #require(renderer.cgImage))
            let axisLength = edge.isVertical ? bitmap.pixelsHigh : bitmap.pixelsWide
            let crossLength = edge.isVertical ? bitmap.pixelsWide : bitmap.pixelsHigh
            var foreground = 0
            var endPixels = 0
            for axis in 0..<axisLength {
                for cross in 0..<crossLength {
                    let x = edge.isVertical ? cross : axis
                    let y = edge.isVertical ? axis : cross
                    let color = try #require(bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB))
                    if max(color.redComponent, color.greenComponent, color.blueComponent) > 0.25 {
                        foreground += 1
                        if axis >= axisLength - 24 { endPixels += 1 }
                    }
                }
            }
            #expect(foreground > 10)
            #expect(endPixels == 0, "\(presentation.notice.id) \(presentation.text) must leave 12pt empty at the end")
        }
    }

    @Test(arguments: [IslandEdge.top, .bottom]) @MainActor
    func waveformKeepsTheSameMeasuredGapAndEndInsetAsTheArtwork(edge: IslandEdge) throws {
        let image = NSImage(size: NSSize(width: 24, height: 24), flipped: false) { rect in
            NSColor.white.setFill()
            rect.fill()
            return true
        }
        let data = try #require(image.tiffRepresentation)
        let notice = IslandNotice(id: "media-active-insets", title: "Music", artworkData: data)
        let presentation = CompactPillStatusPresentation(priority: .media, notice: notice, text: "", showsWaveform: true)
        let item = NowPlayingSnapshot(title: "fixture", artist: "fixture", album: nil, artworkData: data,
            duration: 60, elapsedTime: 0, timestamp: .distantPast, isPlaying: false)
        let length = presentation.length(thickness: 32, edge: edge)
        let renderer = ImageRenderer(content: CompactPillStatusContent(presentation: presentation,
            text: "", edge: edge, visualizationStyle: .waveform, item: item, date: .now)
            .frame(width: length, height: 32).background(.black))
        renderer.scale = 2
        let bitmap = NSBitmapImageRep(cgImage: try #require(renderer.cgImage))
        var occupiedColumns: [Int] = []
        for x in 0..<bitmap.pixelsWide {
            for y in 0..<bitmap.pixelsHigh {
                let color = try #require(bitmap.colorAt(x: x, y: y)?.usingColorSpace(.sRGB))
                if min(color.redComponent, color.greenComponent, color.blueComponent) > 0.5 {
                    occupiedColumns.append(x)
                    break
                }
            }
        }
        #expect(occupiedColumns.first == 24)
        #expect(occupiedColumns.contains(71) && occupiedColumns.contains(84),
                "Artwork and waveform must keep the measured 6pt gap")
        #expect(occupiedColumns.last == Int((length - 12) * 2) - 1,
                "The waveform must end at the same 12pt inset as the artwork starts")
    }

    @Test(arguments: IslandEdge.allCases)
    @MainActor
    func compactContentKeepsItsColoredIconAtTheStartAndTextWithinTheAdjacentColumn(edge: IslandEdge) throws {
        let icon = NSImage(size: NSSize(width: 24, height: 24), flipped: false) { rect in
            NSColor(deviceRed: 1, green: 0, blue: 0, alpha: 1).setFill()
            rect.fill()
            return true
        }
        let data = try #require(icon.tiffRepresentation)
        let presentation = CompactPillStatusPresentation(priority: .mail,
            notice: IslandNotice(id: "mail-fixture", title: "fixture", artworkData: data), text: "字字字字")
        let length = presentation.length(thickness: 32, edge: edge)
        let size = edge.isVertical ? CGSize(width: 32, height: length) : CGSize(width: length, height: 32)
        let renderer = ImageRenderer(content: CompactPillStatusContent(presentation: presentation,
            text: presentation.text, edge: edge, visualizationStyle: .waveform, item: nil, date: .now)
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
        if edge.isVertical {
            #expect(abs(iconBounds.minY - 12) < 0.5 && abs(iconBounds.midX - 16) < 0.5,
                    "The actual icon edge must begin 12pt from the vertical pill's end")
            #expect(textBounds.minY >= 42 && textBounds.minY < 48)
            #expect(textBounds.height > textBounds.width * 2 && textBounds.maxX <= 32)
            #expect(size.height - textBounds.maxY >= 12, "Vertical content must leave a clear end below its last character")
        } else {
            #expect(abs(iconBounds.minX - 12) < 0.5 && abs(iconBounds.midY - 16) < 0.5,
                    "The actual icon edge must begin 12pt from the horizontal pill's end")
            #expect(textBounds.minX >= 42 && textBounds.minX < 48)
            #expect(textBounds.width > textBounds.height * 2 && textBounds.maxY <= 32)
            #expect(size.width - textBounds.maxX >= 12, "Horizontal content must leave a clear end after its last character")
        }
    }

    @Test(arguments: IslandEdge.allCases, [CGFloat(32), 48]) @MainActor
    func compactIconsKeepTwelvePointInsetsAtBothEnds(edge: IslandEdge, thickness: CGFloat) throws {
        let icon = NSImage(size: NSSize(width: 24, height: 24), flipped: false) { rect in
            NSColor(deviceRed: 1, green: 0, blue: 0, alpha: 1).setFill()
            rect.fill()
            return true
        }
        let presentation = CompactPillStatusPresentation(priority: .mail,
            notice: IslandNotice(id: "mail-insets", title: "fixture", artworkData: try #require(icon.tiffRepresentation)),
            text: "")
        let length = presentation.length(thickness: thickness, edge: edge)
        #expect(length == thickness - 8 + 24, "An empty status reserves its actual icon and two 12pt insets")
        let size = edge.isVertical ? CGSize(width: thickness, height: length) : CGSize(width: length, height: thickness)
        let renderer = ImageRenderer(content: CompactPillStatusContent(presentation: presentation,
            text: "", edge: edge, visualizationStyle: .waveform, item: nil, date: .now)
            .frame(width: size.width, height: size.height).background(.black))
        renderer.scale = 2
        let bitmap = NSBitmapImageRep(cgImage: try #require(renderer.cgImage))
        var bounds = CGRect.null
        for y in 0..<bitmap.pixelsHigh {
            for x in 0..<bitmap.pixelsWide {
                let color = try #require(bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB))
                if color.redComponent > 0.6 && color.greenComponent < 0.2 && color.blueComponent < 0.2 {
                    bounds = bounds.union(CGRect(x: CGFloat(x) / 2, y: CGFloat(y) / 2, width: 0.5, height: 0.5))
                }
            }
        }
        try #require(!bounds.isNull)
        let start = edge.isVertical ? bounds.minY : bounds.minX
        let end = length - (edge.isVertical ? bounds.maxY : bounds.maxX)
        #expect(abs(start - 12) < 0.5 && abs(end - 12) < 0.5,
                "Both visible icon edges must have the same 12pt margin, including the slot's former 4pt gap")
    }
}
