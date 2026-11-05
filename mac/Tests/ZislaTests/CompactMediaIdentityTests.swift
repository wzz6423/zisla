import AppKit
import SwiftUI
import Testing
import ZislaCore
@testable import ZislaKit
@testable import Zisla

@MainActor
@Suite(.serialized)
struct CompactMediaIdentityTests {
    private let date = Date(timeIntervalSince1970: 100)

    @Test(arguments: IslandEdge.allCases)
    func unavailableLyricsLeaveTheDetailedTextRegionEmpty(edge: IslandEdge) throws {
        let settings = settings(edge: edge, style: .detailed, visualization: .glow)
        let presentation = try presentation(settings: settings)
        for lyrics in [nil, SyncedLyrics(lines: []), SyncedLyrics(lines: [.init(time: 10, text: "Later")])] {
            let item = snapshot(lyrics: lyrics)
            let text = CompactPillStatusContent.displayText(for: presentation, settings: settings,
                item: item, at: date)
            #expect(text.isEmpty,
                "A detailed island must show the track identity while no synchronized line is available")
        }
    }

    @Test(arguments: [MediaCompactStyle.compact, .detailed], [false, true])
    func mediaIdentityRespectsTheInformationSettingAndUnavailableMetadata(
        style: MediaCompactStyle, informationEnabled: Bool
    ) throws {
        var settings = settings(edge: .left, style: style, visualization: .glow)
        settings.mediaShowLyricsAndInfo = informationEnabled
        let presentation = try presentation(settings: settings)
        let showsIdentity = style == .detailed && informationEnabled
        #expect(presentation.showsMediaIdentity == showsIdentity)
        var item = snapshot(lyrics: nil)
        item.title = "1234"
        item.artist = ""
        #expect(presentation.mediaIdentityLength(thickness: 32, edge: .left, text: "", item: item)
            == (showsIdentity ? 14 : 0),
            "A missing artist must leave the full column width available to the track title")
        item.isVideo = true
        #expect(presentation.mediaIdentityLength(thickness: 32, edge: .left, text: "", item: item) == 0,
            "Video playback must preserve its existing compact presentation")
        item.isVideo = false
        item.title = ""
        #expect(presentation.mediaIdentityLength(thickness: 32, edge: .left, text: "", item: item) == 0)
        #expect(presentation.mediaIdentityLength(thickness: 32, edge: .left, text: "", item: nil) == 0)
    }

    @Test(arguments: IslandEdge.allCases, [CGFloat(1), 2])
    func detailedMusicAlwaysRendersTheTitleAndArtist(edge: IslandEdge, scale: CGFloat) async throws {
        let settings = settings(edge: edge, style: .detailed, visualization: .glow)
        for lyrics in [nil, SyncedLyrics(lines: [.init(time: 0, text: String(repeating: "春", count: 40))])] {
            let original = snapshot(lyrics: lyrics)
            let baseline = try await render(original, settings: settings, edge: edge, scale: scale)
            var renamed = original
            renamed.title = "Different title"
            let changedTitle = try await render(renamed, settings: settings, edge: edge, scale: scale)
            #expect(try differences(baseline, changedTitle) > 20,
                "Changing the song title must change the visible detailed island with or without lyrics")
            renamed = original
            renamed.artist = "Different artist"
            let changedArtist = try await render(renamed, settings: settings, edge: edge, scale: scale)
            #expect(try differences(baseline, changedArtist) > 20,
                "Changing the artist must change the visible detailed island with or without lyrics")
        }
    }

    @Test(arguments: IslandEdge.allCases, [MediaVisualizationStyle.glow, .waveform])
    func compactMusicKeepsOnlyItsArtworkAndSelectedVisualization(
        edge: IslandEdge, visualization: MediaVisualizationStyle
    ) async throws {
        let settings = settings(edge: edge, style: .compact, visualization: visualization)
        let presentation = try presentation(settings: settings)
        #expect(presentation.text.isEmpty)
        #expect(!presentation.showsMediaIdentity)
        #expect(presentation.length(thickness: 32, edge: edge) == (visualization == .waveform ? 78 : 48))
        let original = snapshot(lyrics: nil)
        var changed = original
        changed.title = "A different title"
        changed.artist = "A different artist"
        changed.lyrics = SyncedLyrics(lines: [.init(time: 0, text: "A synchronized lyric")])
        let first = try await render(original, settings: settings, edge: edge, scale: 2)
        let next = try await render(changed, settings: settings, edge: edge, scale: 2)
        #expect(try differences(first, next) == 0,
            "Compact mode must reserve no text region for a title, artist or lyric")
    }

    @Test(arguments: IslandEdge.allCases, [MediaVisualizationStyle.glow, .waveform])
    func detailedMusicKeepsTheExistingMaximumTextBudget(
        edge: IslandEdge, visualization: MediaVisualizationStyle
    ) throws {
        let settings = settings(edge: edge, style: .detailed, visualization: visualization)
        let notice = IslandNotice(id: "media-active-fixture", title: "Music",
            metadata: ["compactLyric": String(repeating: "春", count: 100)])
        let presentation = try #require(SideNoticeLayoutEngine().compactBarSizing(
            for: [notice], settings: settings)?.customPillPresentation)
        #expect(presentation.showsMediaIdentity)
        #expect(presentation.length(thickness: 32, edge: edge) == (visualization == .waveform ? 252 : 222),
            "Track identity and lyrics must share the existing bounded compact island")
    }

    @Test(arguments: IslandEdge.allCases)
    func aMissingLiveSnapshotKeepsTheAvailableNoticeText(edge: IslandEdge) throws {
        let settings = settings(edge: edge, style: .detailed, visualization: .glow)
        let notice = IslandNotice(id: "media-active-fixture", title: "Music",
            detail: "Stored track", metadata: ["compactLyric": "Stored lyric"])
        let presentation = try #require(SideNoticeLayoutEngine().compactBarSizing(
            for: [notice], settings: settings)?.customPillPresentation)
        #expect(CompactPillStatusContent.displayText(for: presentation, settings: settings,
            item: nil, at: date) == "Stored lyric",
            "A snapshot transition must preserve the text already carried by the visible notice")
        let legacy = CompactPillStatusPresentation(priority: .media, notice: notice, text: "Stored lyric")
        #expect(!legacy.showsMediaIdentity)
        #expect(legacy.length(thickness: 32, edge: edge, item: snapshot(lyrics: nil))
            == legacy.length(thickness: 32, edge: edge),
            "A manually constructed compact presentation must retain its original text budget")
    }

    @Test(arguments: IslandEdge.allCases, [MediaVisualizationStyle.glow, .waveform])
    func thePresenterMeasuresTheVisibleTrackIdentityWithinTheExistingLimit(
        edge: IslandEdge, visualization: MediaVisualizationStyle
    ) throws {
        let suiteName = "Zisla.CompactMediaSizing.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        let store = FeatureSettingsStore(defaults: defaults)
        store.settings = settings(edge: edge, style: .detailed, visualization: visualization)
        store.settings.islandShowMoreInformation = false
        let media = NowPlayingService(loadLyrics: { _, _, _ in
            LyricsSearchResult(lyrics: nil, artistName: nil)
        }, initialRemoteSnapshot: snapshot(lyrics: nil))
        let queue = SideNoticeQueue()
        let sweep = AIResultSweepController()
        let presenter = SideNoticePresenter(queue: queue, resultSweep: sweep, media: media,
            browserDownloads: BrowserDownloadMonitor(), settingsStore: store,
            languageStore: AppLanguageStore(defaults: defaults), isScreenLocked: true,
            now: { date }, reduceMotion: { true }, screenSnapshotProvider: { [] })
        defer {
            presenter.stop()
            queue.removeAll()
            sweep.cancel()
            store.flushPendingChanges()
            defaults.removePersistentDomain(forName: suiteName)
        }
        let notices = [IslandNotice(id: "media-active-fixture", title: "Music")]
        media.publishSnapshot(snapshot(lyrics: nil))
        let short = try #require(presenter.compactConfiguration(for: notices, at: date).compactStatusLength)
        var longer = snapshot(lyrics: nil)
        longer.title = String(repeating: "Long track title ", count: 20)
        longer.artist = String(repeating: "Long artist ", count: 20)
        media.publishSnapshot(longer)
        let long = try #require(presenter.compactConfiguration(for: notices, at: date).compactStatusLength)
        #expect(long > short, "The native panel must measure the visible track identity before it is presented")
        #expect(long == (visualization == .waveform ? 252 : 222),
            "Without a lyric, long metadata must use the complete existing text budget and stop at its maximum")
    }

    @Test(arguments: IslandEdge.allCases, [LayoutDirection.leftToRight, .rightToLeft])
    func detailedWaveformsSeparateTrackIdentityFromTheLyricViewport(
        edge: IslandEdge, direction: LayoutDirection
    ) async throws {
        let settings = settings(edge: edge, style: .detailed, visualization: .waveform)
        var original = snapshot(lyrics: SyncedLyrics(lines: [.init(time: 0, text: String(repeating: "春", count: 40))]))
        original.artworkData = try artwork()
        let first = try await render(original, settings: settings, edge: edge, scale: 2, direction: direction)
        let regions = try textRegions(aroundWaveform: first, edge: edge, direction: direction)
        var changed = original
        changed.title = "Different title"
        let changedTitle = try await render(changed, settings: settings, edge: edge, scale: 2, direction: direction)
        #expect(try differences(first, changedTitle, in: regions.identity) > 20,
            "The song title must be visible before the waveform in the reading direction")
        changed = original
        changed.artist = "Different artist"
        let changedArtist = try await render(changed, settings: settings, edge: edge, scale: 2, direction: direction)
        #expect(try differences(first, changedArtist, in: regions.identity) > 20,
            "The artist must share the identity region before the waveform")
        changed = original
        changed.lyrics = SyncedLyrics(lines: [.init(time: 0, text: String(repeating: "江", count: 40))])
        let changedLyric = try await render(changed, settings: settings, edge: edge, scale: 2, direction: direction)
        #expect(try differences(first, changedLyric, in: regions.identity) == 0)
        #expect(try differences(first, changedLyric, in: regions.lyric) > 20,
            "The synchronized lyric must remain visible after the waveform while the identity stays fixed")
        var longIdentity = original
        longIdentity.title = String(repeating: "Long title ", count: 40)
        longIdentity.artist = String(repeating: "Long artist ", count: 40)
        let longFirst = try await render(longIdentity, settings: settings, edge: edge, scale: 2, direction: direction)
        let longRegions = try textRegions(aroundWaveform: longFirst, edge: edge, direction: direction)
        longIdentity.lyrics = changed.lyrics
        let longNext = try await render(longIdentity, settings: settings, edge: edge, scale: 2, direction: direction)
        #expect(try differences(longFirst, longNext, in: longRegions.lyric) > 20,
            "Long titles and artists must leave a visible lyric viewport inside the same maximum length")
    }

    @Test(arguments: [IslandEdge.top, .bottom], [LayoutDirection.leftToRight, .rightToLeft])
    func detailedLyricsFollowPlaybackAndRestartWithoutMovingTheTrackIdentity(
        edge: IslandEdge, direction: LayoutDirection
    ) async throws {
        let settings = settings(edge: edge, style: .detailed, visualization: .waveform)
        let firstLine = "春江潮水连海平海上明月共潮生滟滟随波千万里何处春江无月明"
        let secondLine = "江天一色无纤尘皎皎空中孤月轮江畔何人初见月江月何年初照人"
        var item = snapshot(lyrics: SyncedLyrics(lines: [
            .init(time: 0, text: firstLine), .init(time: 20, text: secondLine)]))
        item.isPlaying = true
        item.artworkData = try artwork()
        for scale in [CGFloat(1), 2] {
            let first = try await render(item, settings: settings, edge: edge, scale: scale, direction: direction)
            let regions = try textRegions(aroundWaveform: first, edge: edge, direction: direction)
            var previous = first
            for elapsed in [10.0, 19.9, 20.0, 30.0] {
                let next = try await render(item, settings: settings, edge: edge, scale: scale,
                    sampledDate: date.addingTimeInterval(elapsed), direction: direction)
                #expect(try differences(first, next, in: regions.identity) == 0,
                    "Advancing or changing the lyric must preserve the visible title and artist")
                #expect(try differences(previous, next, in: regions.lyric) > 20,
                    "The bounded lyric viewport must advance through the line and restart at the next timestamp")
                previous = next
            }
        }
    }

    private func settings(edge: IslandEdge, style: MediaCompactStyle,
        visualization: MediaVisualizationStyle) -> FeatureSettings {
        var settings = FeatureSettings(islandLayoutStyle: .pill,
            islandPlacement: IslandPlacement(mode: .custom, edge: edge))
        settings.mediaCompactStyle = style
        settings.mediaShowLyricsAndInfo = true
        settings.mediaVisualizationStyle = visualization
        return settings
    }

    private func presentation(settings: FeatureSettings) throws -> CompactPillStatusPresentation {
        try #require(SideNoticeLayoutEngine().compactBarSizing(
            for: [IslandNotice(id: "media-active-fixture", title: "Music")], settings: settings)?.customPillPresentation)
    }

    private func snapshot(lyrics: SyncedLyrics?) -> NowPlayingSnapshot {
        NowPlayingSnapshot(title: "Track", artist: "Artist", album: nil, artworkData: nil,
            duration: 40, elapsedTime: 0, timestamp: date, isPlaying: true, lyrics: lyrics)
    }

    private func render(_ item: NowPlayingSnapshot, settings: FeatureSettings, edge: IslandEdge,
        scale: CGFloat, sampledDate: Date? = nil,
        direction: LayoutDirection = .leftToRight) async throws -> NSBitmapImageRep {
        let presentation = try presentation(settings: settings)
        let suiteName = "Zisla.CompactMediaIdentity.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        let store = FeatureSettingsStore(defaults: defaults)
        store.settings = settings
        store.settings.islandNotchBackground = .black
        store.settings.collapsedProgressGlowEnabled = false
        var sampledItem = item
        sampledItem.elapsedTime = item.elapsedTime(at: sampledDate ?? date)
        sampledItem.timestamp = nil
        let media = NowPlayingService(loadLyrics: { _, _, _ in
            LyricsSearchResult(lyrics: nil, artistName: nil)
        }, initialRemoteSnapshot: sampledItem)
        media.publishSnapshot(sampledItem)
        let queue = SideNoticeQueue()
        queue.enqueue(IslandNotice(id: "media-active-fixture", title: "Music"), expiresAfter: nil)
        let sweep = AIResultSweepController()
        defer {
            queue.removeAll()
            sweep.cancel()
            store.flushPendingChanges()
            defaults.removePersistentDomain(forName: suiteName)
        }
        let state = SideNoticeDisplayState()
        state.placementMode = .custom
        state.islandEdge = edge
        state.compactWingHeight = 32
        let view = CompactStatusBarView(queue: queue, displayState: state, media: media,
            browserDownloads: BrowserDownloadMonitor(), settingsStore: store, resultSweep: sweep, onStatusHidden: {})
        let length: CGFloat = presentation.showsWaveform ? 252 : 222
        let size = edge.isVertical ? CGSize(width: 32, height: length) : CGSize(width: length, height: 32)
        let host = NSHostingView(rootView: view
            .frame(width: size.width, height: size.height)
            .background(.black)
            .environment(\._accessibilityReduceMotion, true)
            .environment(\.layoutDirection, direction)
            .transaction { $0.disablesAnimations = true })
        host.sizingOptions = []
        let window = RasterPanel(contentRect: CGRect(origin: CGPoint(x: 20_000, y: 0), size: size),
            styleMask: .borderless, backing: .buffered, defer: false)
        window.renderScale = scale
        window.isReleasedWhenClosed = false
        window.contentView = host
        defer { window.contentView = nil; window.close() }
        host.layoutSubtreeIfNeeded()
        let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        for _ in 0..<16 {
            host.layoutSubtreeIfNeeded()
            host.cacheDisplay(in: host.bounds, to: bitmap)
            await withCheckedContinuation { continuation in
                DispatchQueue.main.async { continuation.resume() }
            }
        }
        #expect(!window.isVisible)
        let converted = try #require(bitmap.converting(to: .sRGB, renderingIntent: .default))
        converted.size = size
        return converted
    }

    private func differences(_ first: NSBitmapImageRep, _ second: NSBitmapImageRep,
        in rect: CGRect? = nil) throws -> Int {
        #expect(first.pixelsWide == second.pixelsWide && first.pixelsHigh == second.pixelsHigh)
        var count = 0
        let scale = CGFloat(first.pixelsWide) / first.size.width
        let xs = rect.map { Int($0.minX * scale)..<Int($0.maxX * scale) } ?? 0..<first.pixelsWide
        let ys = rect.map { Int($0.minY * scale)..<Int($0.maxY * scale) } ?? 0..<first.pixelsHigh
        for y in ys {
            for x in xs {
                let firstColor = try #require(first.colorAt(x: x, y: y)?.usingColorSpace(.sRGB))
                let secondColor = try #require(second.colorAt(x: x, y: y)?.usingColorSpace(.sRGB))
                if abs(firstColor.redComponent - secondColor.redComponent) > 0.02 { count += 1 }
            }
        }
        return count
    }

    private func artwork() throws -> Data {
        let image = NSImage(size: CGSize(width: 24, height: 24), flipped: false) { rect in
            NSColor.red.setFill()
            rect.fill()
            return true
        }
        return try #require(image.tiffRepresentation)
    }

    private func textRegions(aroundWaveform bitmap: NSBitmapImageRep, edge: IslandEdge,
        direction: LayoutDirection) throws -> (identity: CGRect, lyric: CGRect) {
        let scale = CGFloat(bitmap.pixelsWide) / bitmap.size.width
        let length = edge.isVertical ? bitmap.size.height : bitmap.size.width
        let crossPixels = edge.isVertical ? bitmap.pixelsWide : bitmap.pixelsHigh
        var positions: [CGFloat] = []
        for axis in Int(42 * scale)..<Int((length - 42) * scale) {
            for cross in 0..<crossPixels {
                let color = try #require(bitmap.colorAt(x: edge.isVertical ? cross : axis,
                    y: edge.isVertical ? axis : cross)?.usingColorSpace(.sRGB))
                if color.redComponent > 0.4 && color.greenComponent < 0.2 && color.blueComponent < 0.2 {
                    positions.append(CGFloat(axis) / scale)
                    break
                }
            }
        }
        let start = try #require(positions.first, "The selected waveform must appear between the identity and lyric regions")
        let end = try #require(positions.last) + 1
        func region(from start: CGFloat, to end: CGFloat) -> CGRect {
            edge.isVertical ? CGRect(x: 0, y: start, width: 32, height: max(0, end - start))
                : CGRect(x: start, y: 0, width: max(0, end - start), height: 32)
        }
        if edge.isVertical || direction == .leftToRight {
            return (region(from: 42, to: start), region(from: end, to: length - 12))
        }
        return (region(from: end, to: length - 42), region(from: 12, to: start))
    }

    private final class RasterPanel: NSPanel {
        var renderScale: CGFloat = 1
        override var backingScaleFactor: CGFloat { renderScale }
    }
}
