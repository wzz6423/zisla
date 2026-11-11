import AppKit
import SwiftUI
import Testing
import ZislaCore
@testable import ZislaKit
@testable import Zisla

@MainActor
@Suite(.serialized)
struct CompactPillLyricTests {
    private let date = Date(timeIntervalSince1970: 100)
    private let longLyric = "天地玄黄（宇宙）洪荒日月盈昃辰宿列张寒来暑往秋收冬藏闰"

    @Test(arguments: IslandEdge.allCases, [false, true])
    func longLyricsFillTheirFirstViewportAndFollowPlaybackWithinTheSameFrame(
        edge: IslandEdge, reduceMotion: Bool
    ) async throws {
        let presentation = presentation(text: longLyric)
        let item = snapshot(text: longLyric)
        let length = presentation.length(thickness: 32, edge: edge)
        #expect(length == 222 && length <= ScreenLayoutConfiguration.quickActionRowWidth)
        let size = edge.isVertical ? CGSize(width: 32, height: length) : CGSize(width: length, height: 32)
        let viewport = textViewport(edge: edge, length: length)
        for renderScale in [CGFloat(1), 2] {
            var samples: [[UInt8]] = []
            for elapsed in [0.0, 20, 40] {
                let actual = try await render(CompactPillStatusContent(presentation: presentation,
                    text: longLyric, edge: edge, visualizationStyle: .waveform, item: item,
                    date: date.addingTimeInterval(elapsed)), size: size, reduceMotion: reduceMotion, renderScale: renderScale)
                let reference = try await render(referenceText(longLyric, edge: edge,
                    size: viewport.size, progress: elapsed / 40), size: viewport.size,
                    reduceMotion: reduceMotion, renderScale: renderScale)
                let samplePixels = try pixels(actual, in: viewport)
                #expect(differences(samplePixels, try pixels(reference)) == 0,
                        "The lyric at \(elapsed)s must use its timestamp window inside the original \(size) frame")
                #expect(samplePixels.contains { $0 > 128 }, "A lyric viewport must never scroll in from an empty frame")
                let occupied = try inkPositions(actual, in: viewport, vertically: edge.isVertical)
                if edge.isVertical {
                    #expect(occupied.first.map { $0 < 14 } == true
                        && occupied.last.map { $0 >= Int(viewport.height) - 14 } == true,
                        "The first and last text rows must be visible throughout the lyric window")
                } else {
                    let referencePositions = try inkPositions(reference,
                        in: CGRect(origin: .zero, size: viewport.size), vertically: false)
                    #expect(!occupied.isEmpty && occupied.first == referencePositions.first
                        && occupied.last == referencePositions.last,
                        "The complete lyric window must preserve the reference glyph bearings")
                }
                let endInset = edge.isVertical ? CGRect(x: 0, y: length - 12, width: 32, height: 12)
                    : CGRect(x: length - 12, y: 0, width: 12, height: 32)
                #expect(try pixels(actual, in: endInset).allSatisfy { $0 < 10 },
                        "Overflowing lyric rows must stay inside their viewport and leave the end inset clear")
                samples.append(samplePixels)
            }
            #expect(differences(samples[0], samples[1]) > 30)
            #expect(differences(samples[1], samples[2]) > 30)
        }
    }

    @Test(arguments: [CGFloat(1), 2])
    func horizontalLyricWindowsMatchTheirActualBackingScale(renderScale: CGFloat) async throws {
        let presentation = presentation(text: longLyric)
        let item = snapshot(text: longLyric)
        let size = CGSize(width: presentation.length(thickness: 32, edge: .top), height: 32)
        let viewport = textViewport(edge: .top, length: size.width)
        for elapsed in [0.0, 20, 40] {
            let actual = try await render(CompactPillStatusContent(presentation: presentation,
                text: longLyric, edge: .top, visualizationStyle: .waveform, item: item,
                date: date.addingTimeInterval(elapsed)), size: size, renderScale: renderScale)
            var referenceScale: CGFloat?
            let reference = try await render(HorizontalLyricReference(text: longLyric,
                size: viewport.size, progress: elapsed / 40, onDisplayScale: { referenceScale = $0 }),
                size: viewport.size, renderScale: renderScale)
            #expect(referenceScale == renderScale,
                "The reference must use the scale of its actual hosting window")
            #expect(differences(try pixels(actual, in: viewport), try pixels(reference)) == 0,
                "The head, middle and tail must match the reference at \(renderScale)x without fixed pixel rounding")
        }
    }

    @Test(arguments: IslandEdge.allCases, [false, true])
    func changingTheLyricLineRestartsInsideTheExistingMaximumBudget(edge: IslandEdge, showsWaveform: Bool) async throws {
        let next = "春江潮水连海平海上明月共潮生滟滟随波远处何处春江无月明"
        let lines = SyncedLyrics(lines: [.init(time: 0, text: longLyric), .init(time: 20, text: next)])
        var item = snapshot(text: longLyric)
        item.lyrics = lines
        let presentation = CompactPillStatusPresentation(priority: .media,
            notice: IslandNotice(id: "media-active-lines", title: "Track"), text: longLyric,
            showsWaveform: showsWaveform)
        let length = presentation.length(thickness: 32, edge: edge)
        #expect(length == (showsWaveform ? 252 : 222))
        let size = edge.isVertical ? CGSize(width: 32, height: length) : CGSize(width: length, height: 32)
        let viewport = textViewport(edge: edge, length: length, showsWaveform: showsWaveform)
        var settings = FeatureSettings()
        settings.mediaCompactStyle = .detailed
        settings.mediaShowLyricsAndInfo = true
        for (elapsed, expectedText, progress) in [(10.0, longLyric, 0.5), (20, next, 0), (30, next, 0.5)] {
            let sampledDate = date.addingTimeInterval(elapsed)
            let text = CompactPillStatusContent.displayText(for: presentation, settings: settings, item: item, at: sampledDate)
            #expect(text == expectedText)
            let actual = try await render(CompactPillStatusContent(presentation: presentation,
                text: text, edge: edge, visualizationStyle: .waveform, item: item, date: sampledDate), size: size)
            let reference = try await render(referenceText(expectedText, edge: edge,
                size: viewport.size, progress: progress), size: viewport.size)
            #expect(differences(try pixels(actual, in: viewport), try pixels(reference)) == 0,
                "The next lyric must restart inside the same length budget and follow its own timing window")
        }
    }

    @Test(arguments: IslandEdge.allCases)
    func pausedLyricsKeepTheirInternalPositionAsTheClockAdvances(edge: IslandEdge) async throws {
        let presentation = presentation(text: longLyric)
        var item = snapshot(text: longLyric)
        item.isPlaying = false
        item.elapsedTime = 20
        let length = presentation.length(thickness: 32, edge: edge)
        let size = edge.isVertical ? CGSize(width: 32, height: length) : CGSize(width: length, height: 32)
        let viewport = textViewport(edge: edge, length: length)
        let first = try await render(CompactPillStatusContent(presentation: presentation,
            text: longLyric, edge: edge, visualizationStyle: .waveform, item: item, date: date), size: size)
        let later = try await render(CompactPillStatusContent(presentation: presentation,
            text: longLyric, edge: edge, visualizationStyle: .waveform, item: item,
            date: date.addingTimeInterval(100)), size: size)
        let reference = try await render(referenceText(longLyric, edge: edge,
            size: viewport.size, progress: 0.5), size: viewport.size)
        #expect(differences(try pixels(first, in: viewport), try pixels(reference)) == 0)
        #expect(differences(try pixels(first, in: viewport), try pixels(later, in: viewport)) == 0,
                "Paused playback must freeze the current lyric offset on every edge")
    }

    @Test(arguments: IslandEdge.allCases)
    func shortLyricsKeepTheirNaturalLengthAndDoNotMove(edge: IslandEdge) async throws {
        let text = "短"
        let presentation = presentation(text: text)
        let item = snapshot(text: text)
        let length = presentation.length(thickness: 32, edge: edge)
        #expect(length < 222)
        let size = edge.isVertical ? CGSize(width: 32, height: length) : CGSize(width: length, height: 32)
        let first = try await render(CompactPillStatusContent(presentation: presentation,
            text: text, edge: edge, visualizationStyle: .waveform, item: item, date: date), size: size)
        let later = try await render(CompactPillStatusContent(presentation: presentation,
            text: text, edge: edge, visualizationStyle: .waveform, item: item,
            date: date.addingTimeInterval(40)), size: size)
        #expect(differences(try pixels(first), try pixels(later)) == 0)
        #expect(try pixels(first, in: textViewport(edge: edge, length: length)).contains { $0 > 128 })
    }

    @Test(arguments: IslandEdge.allCases)
    func emptyLyricsKeepOnlyTheOriginalArtworkSlot(edge: IslandEdge) async throws {
        let presentation = presentation(text: "")
        let item = snapshot(text: "")
        let length = presentation.length(thickness: 32, edge: edge)
        #expect(length == 48)
        let size = edge.isVertical ? CGSize(width: 32, height: length) : CGSize(width: length, height: 32)
        let first = try await render(CompactPillStatusContent(presentation: presentation,
            text: "", edge: edge, visualizationStyle: .waveform, item: item, date: date), size: size)
        let later = try await render(CompactPillStatusContent(presentation: presentation,
            text: "", edge: edge, visualizationStyle: .waveform, item: item,
            date: date.addingTimeInterval(20)), size: size)
        #expect(try pixels(first).contains { $0 > 128 })
        #expect(differences(try pixels(first), try pixels(later)) == 0,
                "An empty lyric must not allocate or animate an additional text region")
    }

    @Test(arguments: [CGFloat(14), 42, 168])
    func verticalLyricsKeepWholeGraphemesAndOnlyRotateTheirBrackets(height: CGFloat) async throws {
        let text = "甲（乙）e\u{301}🇨🇳👨‍👩‍👧‍👦(1)丙丁戊己庚辛壬癸"
        let rows = ["甲", "（", "乙", "）", "e\u{301}", "🇨🇳", "👨‍👩‍👧‍👦", "(1)",
                    "丙", "丁", "戊", "己", "庚", "辛", "壬", "癸"]
        for progress in [0.0, 0.5, 1] {
            let actual = try await render(VerticalStatusText(text: text, availableWidth: 32,
                availableHeight: height, scrollProgress: progress).foregroundStyle(.white),
                size: CGSize(width: 32, height: height))
            let reference = try await render(referenceVerticalRows(rows,
                size: CGSize(width: 32, height: height), progress: progress),
                size: CGSize(width: 32, height: height))
            #expect(differences(try pixels(actual), try pixels(reference)) == 0,
                    "Scrolling must preserve the existing upright graphemes and clockwise standalone brackets")
        }
    }

    @Test
    func ordinaryVerticalStatusKeepsItsExistingEllipsisUnlessScrollingIsEnabled() async throws {
        let size = CGSize(width: 32, height: 42)
        let actual = try await render(VerticalStatusText(text: "甲乙丙丁戊己", availableWidth: 32,
            availableHeight: size.height).foregroundStyle(.white), size: size)
        let reference = try await render(referenceVerticalRows(["甲", "乙", "…"],
            size: size, progress: 0, scrolling: false), size: size)
        #expect(differences(try pixels(actual), try pixels(reference)) == 0,
                "Ordinary status callers must retain their existing bounded ellipsis")
    }

    @Test(arguments: [0.0, 0.5, 1], [CGFloat(1), 2])
    func automaticVerticalTextFillsItsViewportAndStopsAtTheTail(progress: Double, renderScale: CGFloat) async throws {
        let size = CGSize(width: 32, height: 168)
        var animations: [Animation] = []
        let actual = try await render(VerticalStatusText(text: longLyric, availableWidth: 32,
            availableHeight: size.height, scrollsAutomatically: true).foregroundStyle(.white),
            size: size, renderScale: renderScale, animationProgress: progress, onAnimation: { animations.append($0) })
        let reference = try await render(referenceVerticalRows(longLyric.map(String.init),
            size: size, progress: progress, animated: true), size: size, renderScale: renderScale)
        #expect(differences(try pixels(actual), try pixels(reference)) == 0,
                "Automatic vertical text must show its known head, middle and tail windows")
        let occupied = try inkPositions(actual, in: CGRect(origin: .zero, size: size), vertically: true)
        #expect(!occupied.isEmpty && occupied.first.map { $0 < 14 } == true
            && occupied.last.map { $0 >= Int(size.height) - 14 } == true,
            "The first and last text rows must remain visible throughout the automatic scroll")
        let travel = Double(longLyric.count * 14 - 1) - Double(size.height)
        #expect(animations.contains(.linear(duration: travel / 32)),
                "The one-pass vertical animation must use the shared 32pt/s reading speed")
    }

    @Test(arguments: ["短", "", " \n "])
    func automaticVerticalTextDoesNotAnimateContentThatFits(text: String) async throws {
        let size = CGSize(width: 32, height: 42)
        var animations: [Animation] = []
        let actual = try await render(VerticalStatusText(text: text, availableWidth: 32,
            availableHeight: size.height, scrollsAutomatically: true).foregroundStyle(.white),
            size: size, onAnimation: { animations.append($0) })
        let reference = try await render(referenceVerticalRows(text.filter { !$0.isWhitespace }.map(String.init),
            size: size, progress: 0), size: size)
        #expect(differences(try pixels(actual), try pixels(reference)) == 0)
        #expect(animations.isEmpty, "Short or empty vertical content must not start a scrolling task")
    }

    @Test(arguments: [-2.0, 0, 0.25, 1, 2], [false, true])
    func externalVerticalProgressTakesPriorityAndClampsToTheTextBounds(
        progress: Double, reduceMotion: Bool
    ) async throws {
        let size = CGSize(width: 32, height: 168)
        var animations: [Animation] = []
        let actual = try await render(VerticalStatusText(text: longLyric, availableWidth: 32,
            availableHeight: size.height, scrollProgress: progress, scrollsAutomatically: true)
            .foregroundStyle(.white), size: size, reduceMotion: reduceMotion,
            onAnimation: { animations.append($0) })
        let expectedProgress = progress < 0 ? 0 : progress > 1 ? 1 : progress
        let reference = try await render(referenceVerticalRows(longLyric.map(String.init),
            size: size, progress: expectedProgress), size: size)
        #expect(differences(try pixels(actual), try pixels(reference)) == 0,
                "External progress must override automatic scrolling, including Reduce Motion")
        #expect(animations.isEmpty, "Externally driven progress must not also launch an automatic animation")
    }

    @Test
    func reduceMotionKeepsTheFullAutomaticVerticalFirstViewportStationary() async throws {
        let size = CGSize(width: 32, height: 168)
        let reference = try await render(referenceVerticalRows(longLyric.map(String.init),
            size: size, progress: 0), size: size)
        var animations: [Animation] = []
        for progress in [0.0, 0.5, 1] {
            let actual = try await render(VerticalStatusText(text: longLyric, availableWidth: 32,
                availableHeight: size.height, scrollsAutomatically: true).foregroundStyle(.white),
                size: size, reduceMotion: true, animationProgress: progress,
                onAnimation: { animations.append($0) })
            #expect(differences(try pixels(actual), try pixels(reference)) == 0,
                    "Reduce Motion keeps the full first viewport readable without automatic movement")
        }
        #expect(animations.isEmpty)
    }

    @Test(arguments: [CGFloat(1), 2])
    func verticalScrollResetsForChangedContentAndViewportAndCancelsWhenDisabled(renderScale: CGFloat) async throws {
        let size = CGSize(width: 32, height: 168)
        func content(_ text: String, width: CGFloat = 32, height: CGFloat = 168, automatic: Bool = true,
            reduceMotion: Bool = false, progress: Double? = nil, sample: Double = 0.5) -> some View {
            VerticalStatusText(text: text, availableWidth: width, availableHeight: height,
                scrollProgress: progress, scrollsAutomatically: automatic)
                .foregroundStyle(.white)
                .frame(width: size.width, height: size.height, alignment: .top)
                .background(.black)
                .environment(\._accessibilityReduceMotion, reduceMotion)
                .transaction { transaction in
                    if transaction.animation != nil, !transaction.disablesAnimations {
                        transaction.animation = Animation(FrozenProgress(progress: sample))
                    }
                }
        }
        let host = NSHostingView(rootView: content(longLyric))
        host.sizingOptions = []
        let window = RasterPanel(contentRect: CGRect(origin: CGPoint(x: 20_000, y: 0), size: size),
            styleMask: .borderless, backing: .buffered, defer: false)
        window.renderScale = renderScale
        window.isReleasedWhenClosed = false
        window.contentView = host
        defer { window.contentView = nil; window.close() }
        func assertVisibleRows(_ rows: [String], width: CGFloat = 32, height: CGFloat = 168, progress: Double,
            animated: Bool = true, message: String) async throws {
            let reference = try await render(referenceVerticalRows(rows,
                size: CGSize(width: width, height: height), progress: progress, animated: animated)
                .frame(width: size.width, height: size.height, alignment: .top), size: size, renderScale: renderScale)
            let actual = try await sample(host, size: size)
            #expect(differences(try pixels(actual), try pixels(reference)) == 0, "\(message)")
            #expect(host.bounds.size == size && window.frame.size == size && !window.isVisible)
        }
        try await assertVisibleRows(longLyric.map(String.init), progress: 0.5, message: "Initial automatic midpoint")
        let replacement = "春江潮水连海平海上明月共潮生滟滟随波远处何处春江无月明"
        host.rootView = content(replacement, sample: 0)
        try await assertVisibleRows(replacement.map(String.init), progress: 0,
            message: "Changing text restarts from its full first viewport")
        host.rootView = content(replacement, height: 84, sample: 0.5)
        try await assertVisibleRows(replacement.map(String.init), height: 84, progress: 0.5,
            message: "Changing the viewport starts a fresh pass for the new travel")
        host.rootView = content(replacement, height: 84, progress: 0.75)
        try await assertVisibleRows(replacement.map(String.init), height: 84, progress: 0.75, animated: false,
            message: "External progress cancels the automatic position")
        host.rootView = content(replacement, height: 84, sample: 0)
        try await assertVisibleRows(replacement.map(String.init), height: 84, progress: 0,
            message: "Removing external progress starts a fresh automatic pass")
        host.rootView = content(replacement, height: 84, reduceMotion: true)
        try await assertVisibleRows(replacement.map(String.init), height: 84, progress: 0,
            message: "Reduce Motion cancels and resets an already running automatic pass")
        host.rootView = content(replacement, height: 84, sample: 0.5)
        try await assertVisibleRows(replacement.map(String.init), height: 84, progress: 0.5,
            message: "Disabling Reduce Motion restarts the pass instead of keeping stale progress")
        host.rootView = content(replacement, height: 84, automatic: false)
        try await assertVisibleRows(Array(replacement.prefix(5)).map(String.init) + ["…"], height: 84, progress: 0,
            message: "Removing the opt-in cancels automatic scrolling and restores ordinary ellipsis")
        host.rootView = content(replacement, height: 84, sample: 0.5)
        try await assertVisibleRows(replacement.map(String.init), height: 84, progress: 0.5,
            message: "Re-enabling the same text after the opt-in is disabled starts a fresh pass")
        let numeric = "12345678901234567890123456789012345678901234567890"
        host.rootView = content(numeric, height: 42, sample: 0.5)
        try await assertVisibleRows(["1234", "5678", "9012", "3456", "7890", "1234", "5678", "9012", "3456", "7890", "1234", "5678", "90"],
            height: 42, progress: 0.5, message: "Numeric runs preserve their four-digit rows at 32pt")
        host.rootView = content(numeric, width: 24, height: 42, sample: 0)
        try await assertVisibleRows(["123", "456", "789", "012", "345", "678", "901", "234", "567", "890", "123", "456", "789", "012", "345", "678", "90"],
            width: 24, height: 42, progress: 0, message: "Changing only width reflows numeric runs and restarts at the head")
        host.rootView = content("短", height: 84)
        try await assertVisibleRows(["短"], height: 84, progress: 0,
            message: "Replacing a long line with a short line removes the old scroll")
    }

    @Test(arguments: IslandEdge.allCases, [Double?.none, 0])
    func lyricsWithoutAnEndTimestampRemainReadableAtTheBeginning(edge: IslandEdge, duration: Double?) async throws {
        let presentation = presentation(text: longLyric)
        var item = snapshot(text: longLyric)
        item.duration = duration
        let length = presentation.length(thickness: 32, edge: edge)
        let size = edge.isVertical ? CGSize(width: 32, height: length) : CGSize(width: length, height: 32)
        let viewport = textViewport(edge: edge, length: length)
        let actual = try await render(CompactPillStatusContent(presentation: presentation,
            text: longLyric, edge: edge, visualizationStyle: .waveform, item: item,
            date: date.addingTimeInterval(20)), size: size)
        let reference = try await render(referenceText(longLyric, edge: edge,
            size: viewport.size, progress: 0), size: viewport.size)
        #expect(differences(try pixels(actual, in: viewport), try pixels(reference)) == 0,
                "A missing lyric timing window must not start an unrelated automatic scroll")
    }

    @Test(arguments: IslandEdge.allCases, [false, true])
    func videoMissingLyricsAndOrdinaryStatusesKeepTheirExistingTextBehavior(
        edge: IslandEdge, reduceMotion: Bool
    ) async throws {
        var video = snapshot(text: longLyric)
        video.isVideo = true
        var unsynced = video
        unsynced.isVideo = false
        unsynced.lyrics = nil
        let media = presentation(text: longLyric)
        let ordinary = CompactPillStatusPresentation(priority: .transient,
            notice: IslandNotice(id: "focus-transition-test", title: "Status"), text: longLyric)
        for (presentation, item) in [(media, Optional(video)), (media, unsynced), (media, nil),
                                     (ordinary, snapshot(text: longLyric))] {
            let length = presentation.length(thickness: 32, edge: edge)
            let size = edge.isVertical ? CGSize(width: 32, height: length) : CGSize(width: length, height: 32)
            let viewport = textViewport(edge: edge, length: length)
            let actual = try await render(CompactPillStatusContent(presentation: presentation,
                text: longLyric, edge: edge, visualizationStyle: .waveform, item: item, date: date),
                size: size, reduceMotion: reduceMotion)
            let reference = try await render(Group {
                if edge.isVertical {
                    VerticalStatusText(text: longLyric, availableWidth: 32, availableHeight: viewport.height)
                        .frame(width: 32, height: viewport.height, alignment: .top)
                } else {
                    MarqueeText(longLyric, font: .system(size: 11, weight: .medium), textColor: .white,
                        repeats: false)
                }
            }.foregroundStyle(.white), size: viewport.size, reduceMotion: reduceMotion)
            #expect(differences(try pixels(actual, in: viewport), try pixels(reference)) == 0,
                    "Only synchronized music lyrics may use playback to move the text")
        }
    }

    @Test(arguments: IslandEdge.allCases)
    func customStatusUsesTheSameDateForItsLyricAndInternalScroll(edge: IslandEdge) async throws {
        let suiteName = "Zisla.CompactLyric.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        let settings = FeatureSettingsStore(defaults: defaults)
        let queue = SideNoticeQueue()
        let sweep = AIResultSweepController()
        defer {
            queue.removeAll()
            sweep.cancel()
            settings.flushPendingChanges()
            defaults.removePersistentDomain(forName: suiteName)
        }
        settings.settings.islandLayoutStyle = .pill
        settings.settings.islandPlacement = IslandPlacement(mode: .custom, edge: edge)
        settings.settings.islandNotchBackground = .black
        settings.settings.mediaCompactStyle = .detailed
        settings.settings.mediaShowLyricsAndInfo = true
        settings.settings.mediaVisualizationStyle = .glow
        settings.settings.collapsedProgressGlowEnabled = false
        let media = NowPlayingService()
        let item = snapshot(text: longLyric)
        media.publishSnapshot(item)
        let notice = IslandNotice(id: "media-active-lyric-clock", title: "Track")
        queue.enqueue(notice, expiresAfter: nil)
        let state = SideNoticeDisplayState()
        state.placementMode = .custom
        state.islandEdge = edge
        state.compactWingHeight = 32
        let view = CompactStatusBarView(queue: queue, displayState: state, media: media,
            browserDownloads: BrowserDownloadMonitor(), settingsStore: settings,
            resultSweep: sweep, pomodoro: PomodoroService(notificationRequestHandler: { _ in }, defaults: defaults), onStatusHidden: {})
        let presentation = try #require(SideNoticeLayoutEngine().compactBarSizing(
            for: [notice], settings: settings.settings)?.customPillPresentation)
        let length = presentation.length(thickness: 32, edge: edge, text: longLyric, item: item)
        let size = edge.isVertical ? CGSize(width: 32, height: length) : CGSize(width: length, height: 32)
        let identityLength = presentation.mediaIdentityLength(thickness: 32, edge: edge,
            text: longLyric, item: item)
        var viewport = textViewport(edge: edge, length: length)
        if edge.isVertical {
            viewport.origin.y += identityLength + 6
            viewport.size.height -= identityLength + 6
        } else {
            viewport.origin.x += identityLength + 6
            viewport.size.width -= identityLength + 6
        }
        let sampledDate = date.addingTimeInterval(20)
        let actual = try await render(view.statusBarContent(at: sampledDate), size: size, reduceMotion: true)
        let reference = try await render(referenceText(longLyric, edge: edge,
            size: viewport.size, progress: 0.5), size: viewport.size)
        #expect(differences(try pixels(actual, in: viewport), try pixels(reference)) == 0,
                "The custom status must pass its sampled date through instead of reading wall-clock time")
    }

    private func presentation(text: String) -> CompactPillStatusPresentation {
        CompactPillStatusPresentation(priority: .media,
            notice: IslandNotice(id: "media-active-fixture", title: "Track"), text: text)
    }

    private func snapshot(text: String) -> NowPlayingSnapshot {
        NowPlayingSnapshot(title: "Track", artist: "Artist", album: nil, artworkData: nil,
            duration: 40, elapsedTime: 0, timestamp: date, isPlaying: true,
            lyrics: SyncedLyrics(lines: [.init(time: 0, text: text)]))
    }

    private func textViewport(edge: IslandEdge, length: CGFloat, showsWaveform: Bool = false) -> CGRect {
        let textLength = length - 54 - (showsWaveform ? 30 : 0)
        return edge.isVertical ? CGRect(x: 0, y: 42, width: 32, height: textLength)
            : CGRect(x: 42, y: 0, width: textLength, height: 32)
    }

    @ViewBuilder
    private func referenceText(_ text: String, edge: IslandEdge, size: CGSize, progress: Double) -> some View {
        if edge.isVertical {
            referenceVerticalRows(text.map(String.init), size: size, progress: progress)
        } else {
            HorizontalLyricReference(text: text, size: size, progress: progress)
        }
    }

    private func referenceVerticalRows(_ rows: [String], size: CGSize, progress: Double,
        scrolling: Bool = true, animated: Bool = false) -> some View {
        VerticalTextReference(rows: rows, size: size, progress: progress, scrolling: scrolling, animated: animated)
    }

    private struct VerticalTextReference: View {
        let rows: [String]
        let size: CGSize
        let progress: Double
        let scrolling: Bool
        let animated: Bool
        @State private var animatedProgress: CGFloat = 0

        var body: some View {
            VStack(spacing: 1) {
                ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                    Text(row).font(.system(size: 11, weight: .medium))
                        .rotationEffect(.degrees(["（", "）"].contains(row) ? 90 : 0)).frame(height: 13)
                }
            }
            .fixedSize(horizontal: false, vertical: true)
            .offset(y: -max(0, CGFloat(rows.count) * 14 - 1 - size.height)
                * (animated ? animatedProgress : CGFloat(progress)))
            .frame(width: size.width, height: size.height, alignment: scrolling ? .top : .center).clipped()
            .foregroundStyle(.white)
            .task {
                guard animated else { return }
                withAnimation(.linear(duration: 1)) { animatedProgress = 1 }
            }
            .transaction { transaction in
                if animated, transaction.animation != nil, !transaction.disablesAnimations {
                    transaction.animation = Animation(FrozenProgress(progress: progress))
                }
            }
        }
    }

    private func render(_ content: some View, size: CGSize, reduceMotion: Bool = false,
        renderScale: CGFloat? = nil, animationProgress: Double = 0.5, onAnimation: ((Animation) -> Void)? = nil) async throws -> NSBitmapImageRep {
        let host = NSHostingView(rootView: content.frame(width: size.width, height: size.height)
            .background(.black)
            .environment(\._accessibilityReduceMotion, reduceMotion)
            .transaction { transaction in
                if let animation = transaction.animation, !transaction.disablesAnimations {
                    onAnimation?(animation)
                    transaction.animation = Animation(FrozenProgress(progress: animationProgress))
                }
            })
        host.sizingOptions = []
        let window = RasterPanel(contentRect: CGRect(origin: CGPoint(x: 20_000, y: 0), size: size),
            styleMask: .borderless, backing: .buffered, defer: false)
        window.renderScale = renderScale
        window.isReleasedWhenClosed = false
        window.contentView = host
        defer { window.contentView = nil; window.close() }
        #expect(host.bounds.size == size && window.frame.size == size)
        let bitmap = try await sample(host, size: size)
        #expect(CGFloat(bitmap.pixelsWide) / size.width == window.backingScaleFactor
            && CGFloat(bitmap.pixelsHigh) / size.height == window.backingScaleFactor,
            "The captured bitmap must use its hosting window backing scale")
        #expect(host.bounds.size == size && window.frame.size == size,
                "Internal lyric scrolling must not alter the host or window dimensions")
        #expect(!window.isVisible)
        return bitmap
    }

    private func sample(_ host: NSView, size: CGSize) async throws -> NSBitmapImageRep {
        let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        for _ in 0..<16 {
            host.layoutSubtreeIfNeeded()
            host.cacheDisplay(in: host.bounds, to: bitmap)
            await withCheckedContinuation { continuation in
                DispatchQueue.main.async { continuation.resume() }
            }
        }
        let converted = try #require(bitmap.converting(to: .sRGB, renderingIntent: .default))
        converted.size = size
        return converted
    }

    private func pixels(_ bitmap: NSBitmapImageRep, in rect: CGRect? = nil) throws -> [UInt8] {
        let scale = CGFloat(bitmap.pixelsWide) / bitmap.size.width
        let xRange = rect.map { Int($0.minX * scale)..<Int($0.maxX * scale) } ?? 0..<bitmap.pixelsWide
        let yRange = rect.map { Int($0.minY * scale)..<Int($0.maxY * scale) } ?? 0..<bitmap.pixelsHigh
        var result: [UInt8] = []
        for y in yRange {
            for x in xRange {
                let red = try #require(bitmap.colorAt(x: x, y: y)).redComponent
                result.append(UInt8((red * 255).rounded()))
            }
        }
        return result
    }

    private func differences(_ first: [UInt8], _ second: [UInt8]) -> Int {
        #expect(first.count == second.count)
        return zip(first, second).filter { abs(Int($0) - Int($1)) > 3 }.count
    }

    private func inkPositions(_ bitmap: NSBitmapImageRep, in rect: CGRect, vertically: Bool) throws -> [Int] {
        let scale = CGFloat(bitmap.pixelsWide) / bitmap.size.width
        let axisLength = Int((vertically ? rect.height : rect.width) * scale)
        let crossLength = Int((vertically ? rect.width : rect.height) * scale)
        var positions: [Int] = []
        for axis in 0..<axisLength {
            for cross in 0..<crossLength {
                let x = Int(rect.minX * scale) + (vertically ? cross : axis)
                let y = Int(rect.minY * scale) + (vertically ? axis : cross)
                if try #require(bitmap.colorAt(x: x, y: y)).redComponent > 0.3 {
                    positions.append(Int(CGFloat(axis) / scale))
                    break
                }
            }
        }
        return positions
    }

    private struct HorizontalLyricReference: View {
        let text: String
        let size: CGSize
        let progress: Double
        var onDisplayScale: ((CGFloat) -> Void)?
        @Environment(\.displayScale) private var displayScale

        var body: some View {
            let width = ceil((text as NSString).size(withAttributes: [
                .font: NSFont.systemFont(ofSize: 11, weight: .regular)
            ]).width * displayScale) / displayScale
            Text(text).font(.system(size: 11, weight: .regular)).foregroundStyle(.white)
                .lineLimit(1).fixedSize(horizontal: true, vertical: false)
                .offset(x: -max(0, width - size.width) * progress)
                .frame(width: size.width, height: size.height, alignment: .leading).clipped()
                .onChange(of: displayScale, initial: true) { _, scale in onDisplayScale?(scale) }
        }
    }

    private final class RasterPanel: NSPanel {
        var renderScale: CGFloat?
        override var backingScaleFactor: CGFloat { renderScale ?? super.backingScaleFactor }
    }

    private struct FrozenProgress: CustomAnimation {
        let progress: Double

        func animate<V: VectorArithmetic>(value: V, time: TimeInterval, context: inout AnimationContext<V>) -> V? {
            value.scaled(by: progress)
        }
    }
}
