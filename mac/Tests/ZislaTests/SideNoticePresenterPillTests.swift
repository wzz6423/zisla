import AppKit
import Foundation
import SwiftUI
import Testing
import ZislaCore
import ZislaKit
@testable import ZislaKit
@testable import Zisla

@MainActor
struct SideNoticePresenterPillTests {
    @Test
    func cameraDetailedMediaKeepsTheShortCenterClearForLongTitlesAndLyrics() async throws {
        let fixture = try Fixture(edge: .top)
        defer { fixture.close() }
        fixture.settings.settings.islandPlacement = IslandPlacement()
        fixture.settings.settings.islandNotchBackground = .black
        fixture.settings.settings.mediaCompactStyle = .detailed
        fixture.settings.settings.mediaShowLyricsAndInfo = true
        let title = String(repeating: "Long title ", count: 30)
        let notice = IslandNotice(id: "media-active-camera", title: title, side: .left)
        fixture.media.publishSnapshot(NowPlayingSnapshot(title: title, artist: "Artist", album: nil,
            artworkData: nil, duration: 60, elapsedTime: 0, timestamp: fixture.date, isPlaying: true,
            lyrics: SyncedLyrics(lines: [.init(time: 0, text: String(repeating: "Lyrics ", count: 30))])))
        fixture.queue.enqueue(notice, expiresAfter: nil)
        let state = SideNoticeDisplayState()
        state.placementMode = .camera
        state.islandEdge = .top
        state.compactWingHeight = 40
        state.compactBarCenterInset = 120
        let view = CompactStatusBarView(queue: fixture.queue, displayState: state, media: fixture.media,
            browserDownloads: fixture.downloads, settingsStore: fixture.settings, resultSweep: fixture.sweep,
            onStatusHidden: {})
        let bitmap = try await renderOffscreen(view.statusBarContent(at: fixture.date), size: CGSize(width: 240, height: 40))
        let scale = CGFloat(bitmap.pixelsWide) / 240
        var centerPixels = 0
        for x in Int(60 * scale)..<Int(180 * scale) {
            for y in 0..<bitmap.pixelsHigh {
                let color = try #require(bitmap.colorAt(x: x, y: y))
                if max(color.redComponent, color.greenComponent, color.blueComponent) > 0.4 { centerPixels += 1 }
            }
        }
        #expect(centerPixels == 0, "Long media text must not overflow the camera slot in a 240pt detailed pill")
    }

    @Test(arguments: [CGFloat(0), 16, 200])
    func cameraPanelsReserveTheShortCenterAndKeepTheExistingTwoWings(reservedWidth: CGFloat) async throws {
        let fixture = try Fixture(edge: .top)
        defer { fixture.close() }
        fixture.settings.settings.islandPlacement = IslandPlacement()
        fixture.settings.settings.islandNotchBackground = .black
        fixture.screen.visibleFrame.size.height = fixture.screen.frame.height - 44
        if reservedWidth > 0 {
            let frame = fixture.screen.frame
            fixture.screen.safeAreaInsets = ScreenInsets(top: 44)
            fixture.screen.auxiliaryTopLeftArea = CGRect(x: frame.minX, y: frame.maxY - 44,
                width: frame.width / 2 - reservedWidth / 2, height: 44)
            fixture.screen.auxiliaryTopRightArea = CGRect(x: frame.midX + reservedWidth / 2, y: frame.maxY - 44,
                width: frame.width / 2 - reservedWidth / 2, height: 44)
        }
        fixture.presenter.setScreenLocked(false)
        let host = try #require(NSApp.windows.compactMap {
            $0.contentView as? NSHostingView<AppLanguageEnvironment<CompactStatusBarView>>
        }.first { $0.rootView.content.settingsStore === fixture.settings })
        let state = host.rootView.content.displayState
        let centerWidth = max(120, reservedWidth)
        #expect(state.compactBarCenterInset == centerWidth)
        #expect(host.window?.frame.size == CGSize(width: centerWidth + 80, height: 40))
        for count in [1, 2, 3] {
            fixture.queue.removeAll()
            for index in 0..<count {
                fixture.queue.enqueue(IslandNotice(id: "ai-active-openai-\(index)", title: "OpenAI"), expiresAfter: nil)
            }
            fixture.presenter.setDisplayIDs([7])
            fixture.presenter.setStatusIcons([])
            #expect(state.compactBarCenterInset == centerWidth)
            #expect(host.window?.frame.size == CGSize(width: centerWidth + 80, height: 40))
            let bitmap = try await renderOffscreen(host.rootView.content.statusBarContent(at: fixture.date),
                size: CGSize(width: centerWidth + 80, height: 40))
            let wingWidth = Int(40 * CGFloat(bitmap.pixelsWide) / (centerWidth + 80))
            var wingPixels = [0, 0]
            var centerPixels = 0
            for x in 0..<bitmap.pixelsWide {
                for y in 0..<bitmap.pixelsHigh {
                    let color = try #require(bitmap.colorAt(x: x, y: y))
                    if max(color.redComponent, color.greenComponent, color.blueComponent) > 0.4 {
                        if x < wingWidth { wingPixels[0] += 1 }
                        else if x >= bitmap.pixelsWide - wingWidth { wingPixels[1] += 1 }
                        else { centerPixels += 1 }
                    }
                }
            }
            #expect(wingPixels.allSatisfy { $0 > 10 }, "The icon and task count must stay in their original two wings")
            #expect(centerPixels == 0, "The short camera slot must remain clear between both wings")
        }
        fixture.settings.settings.islandPlacement = IslandPlacement(mode: .custom, edge: .left)
        fixture.presenter.setStatusIcons([])
        #expect(state.compactBarCenterInset == 0)
        #expect(try #require(host.window).frame.width == 32)
        fixture.settings.settings.islandLayoutStyle = .notch
        fixture.presenter.setStatusIcons([])
        #expect(state.compactBarCenterInset == reservedWidth)
    }

    @Test
    func cameraNormalActivitiesKeepTheShortDefaultBeforeAndAfterDetails() throws {
        let fixture = try Fixture(edge: .top)
        defer { fixture.close() }
        fixture.settings.settings.islandPlacement = IslandPlacement()
        fixture.settings.settings.mediaCompactStyle = .compact
        let idle = try #require(fixture.presenter.compactFrame(for: fixture.screen, notices: [], at: fixture.date))
        #expect(idle.size == CGSize(width: 200, height: 40))
        let ai = (0..<3).map { IslandNotice(id: "ai-active-codex-\($0)", title: "Codex") }
        let ordinary = [IslandNotice(id: "media-active-camera", title: "Music"),
                        IslandNotice(id: "browser-download-camera", title: "Download", progress: 0.4),
                        IslandNotice(id: "video-download-camera", title: "Download", progress: 0.4),
                        IslandNotice(id: "voice-processing-camera", title: "Voice", detail: "Processing"),
                        IslandNotice(id: "screen-recording-operation-camera", title: "Recording", progress: 0.4)]
        for notices in [Array(ai.prefix(1)), Array(ai.prefix(2)), ai] + ordinary.map({ [$0] }) {
            #expect(try #require(fixture.presenter.compactFrame(for: fixture.screen, notices: notices,
                at: fixture.date)) == idle)
        }
        fixture.settings.settings.mediaCompactStyle = .detailed
        let long = try #require(fixture.presenter.compactFrame(for: fixture.screen,
            notices: [ordinary[0]], at: fixture.date))
        #expect(long.size == CGSize(width: 240, height: 40))
        #expect(long.midX == idle.midX && long.midY == idle.midY)
        #expect(try #require(fixture.presenter.compactFrame(for: fixture.screen, notices: [], at: fixture.date)) == idle)
        #expect(try #require(fixture.presenter.compactFrame(for: fixture.screen, notices: [ordinary[0]],
            at: fixture.date, statusHidden: true)) == idle)
    }

    @Test(arguments: IslandEdge.allCases)
    func eachLiveLyricUsesItsNaturalFrameAndReturnsFromLongToShortWithoutACache(edge: IslandEdge) throws {
        let fixture = try Fixture(edge: edge)
        defer { fixture.close() }
        let notice = IslandNotice(id: "media-active-left", title: "Music", side: .left,
            metadata: ["compactLyric": "旧内容"])
        let base = fixture.date
        var snapshot = NowPlayingSnapshot(title: "fixture", artist: "artist", album: nil, artworkData: nil,
            duration: 60, elapsedTime: 0, timestamp: base, isPlaying: true,
            lyrics: SyncedLyrics(lines: [.init(time: 0, text: "短"), .init(time: 10, text: "长一些的歌词"),
                                        .init(time: 20, text: "短")]))
        fixture.media.publishSnapshot(snapshot)
        fixture.settings.settings.mediaCompactStyle = .detailed
        let first = try #require(fixture.presenter.compactFrame(for: fixture.screen, notices: [notice], at: base))
        let long = try #require(fixture.presenter.compactFrame(for: fixture.screen, notices: [notice], at: base.addingTimeInterval(10)))
        let returned = try #require(fixture.presenter.compactFrame(for: fixture.screen, notices: [notice], at: base.addingTimeInterval(20)))
        #expect(returned == first)
        #expect((edge.isVertical ? long.height : long.width) > (edge.isVertical ? first.height : first.width))
        let configuration = fixture.presenter.compactConfiguration(for: [notice], at: base.addingTimeInterval(10))
        #expect(configuration.compactStatusLength == (edge.isVertical ? long.height : long.width))
        #expect(notice.metadata?["compactLyric"] == "旧内容")
        snapshot.isPlaying = false
        fixture.media.publishSnapshot(snapshot)
        fixture.settings.settings.mediaShowLyricsAndInfo = false
        let paused = fixture.presenter.compactConfiguration(for: [notice], at: base)
        #expect(paused.compactStatusLength == 78)
        fixture.settings.settings.mediaVisualizationStyle = .glow
        let compact = fixture.presenter.compactConfiguration(for: [notice], at: base)
        #expect(compact.compactStatusLength == 48)
    }

    @Test
    func cameraDetailsUseTheShorterFrameAndNotchSizingStaysUnchanged() throws {
        let fixture = try Fixture(edge: .top)
        defer { fixture.close() }
        let notice = IslandNotice(id: "media-active-left", title: "Music", side: .left)
        fixture.settings.settings.mediaCompactStyle = .detailed
        fixture.settings.settings.islandPlacement = IslandPlacement()
        let camera = try #require(fixture.presenter.compactFrame(for: fixture.screen, notices: [notice], at: fixture.date))
        #expect(camera.midX == fixture.screen.frame.midX)
        #expect(camera.midY == fixture.screen.frame.maxY - 22)
        #expect(camera.size == CGSize(width: 240, height: 40))
        fixture.settings.settings.islandLayoutStyle = .notch
        #expect(fixture.presenter.compactFrame(for: fixture.screen, notices: [notice], at: fixture.date)
            == SideNoticeLayoutEngine().compactBarFrame(for: fixture.screen, notices: [notice], settings: fixture.settings.settings))
    }

    @Test
    func cameraIdleAndHiddenContentLeaveNoStatusLengthAndRestoreAfterRemoval() throws {
        let fixture = try Fixture(edge: .top)
        defer { fixture.close() }
        fixture.settings.settings.islandPlacement = IslandPlacement()
        let snapshot = ScreenSnapshot(displayID: 7,
            frame: CGRect(x: 0, y: 0, width: 1512, height: 982),
            visibleFrame: CGRect(x: 0, y: 0, width: 1512, height: 938),
            safeAreaInsets: ScreenInsets(top: 44),
            auxiliaryTopLeftArea: CGRect(x: 0, y: 938, width: 656, height: 44),
            auxiliaryTopRightArea: CGRect(x: 856, y: 938, width: 656, height: 44))
        let idleConfiguration = fixture.presenter.compactConfiguration(for: [], at: fixture.date)
        #expect(idleConfiguration.compactStatusLength == nil)
        let idle = try #require(fixture.presenter.compactFrame(for: snapshot, notices: [], at: fixture.date))
        #expect(idle.size == CGSize(width: 280, height: 40))
        let notice = IslandNotice(id: "ai-active-test", title: "Codex")
        let active = try #require(fixture.presenter.compactFrame(for: snapshot, notices: [notice], at: fixture.date))
        #expect(active.width == 280)
        let hidden = fixture.presenter.compactConfiguration(for: [notice], at: fixture.date, statusHidden: true)
        #expect(hidden.compactStatusLength == nil)
        #expect(try #require(fixture.presenter.compactFrame(for: snapshot, notices: [notice], at: fixture.date, statusHidden: true)) == idle)
        #expect(fixture.presenter.compactConfiguration(for: [], at: fixture.date) == idleConfiguration)
        #expect(try #require(fixture.presenter.compactFrame(for: snapshot, notices: [], at: fixture.date)) == idle)
    }

    @Test(arguments: IslandEdge.allCases)
    func idleCustomPillsKeepTheFixedSizeBeforeAndAfterAnActivity(edge: IslandEdge) throws {
        let fixture = try Fixture(edge: edge)
        defer { fixture.close() }
        let expected = CGSize(width: 24, height: 24)
        let idle = try #require(fixture.presenter.compactFrame(for: fixture.screen, notices: [], at: fixture.date))
        #expect(idle.size == expected)
        #expect(fixture.presenter.compactConfiguration(for: [], at: fixture.date).compactStatusLength == nil)
        let notice = IslandNotice(id: "ai-active-test", title: "Codex")
        let active = try #require(fixture.presenter.compactFrame(for: fixture.screen, notices: [notice], at: fixture.date))
        #expect(active.size == (edge.isVertical ? CGSize(width: 32, height: 68) : CGSize(width: 60, height: 32)))
        #expect(try #require(fixture.presenter.compactFrame(
            for: fixture.screen, notices: [notice], at: fixture.date, statusHidden: true
        )) == idle)
        #expect(try #require(fixture.presenter.compactFrame(for: fixture.screen, notices: [], at: fixture.date)) == idle)
    }

    @Test
    func hidingContentShrinksTheCustomPillAndAStatusSwitchRestoresItsNaturalLength() throws {
        let fixture = try Fixture(edge: .left)
        defer { fixture.close() }
        let state = SideNoticeDisplayState()
        let notice = IslandNotice(id: "toolbox-reminder-left", title: "亮屏", detail: "保持屏幕开启")
        _ = SideNoticePresenter.updateCompactVisibility(notices: [notice], settings: fixture.settings.settings, displayState: state)
        state.compactStatusHidden = true
        #expect(!SideNoticePresenter.updateCompactVisibility(notices: [notice], settings: fixture.settings.settings, displayState: state))
        #expect(state.compactStatusHidden)
        let configuration = fixture.presenter.compactConfiguration(for: [notice], at: fixture.date, statusHidden: state.compactStatusHidden)
        #expect(configuration.compactStatusLength == nil)
        let frame = try #require(fixture.presenter.compactFrame(for: fixture.screen, notices: [notice], at: fixture.date, statusHidden: true))
        #expect(frame.size == CGSize(width: 24, height: 24))
        let next = IslandNotice(id: "ai-active-codex", title: "Codex")
        #expect(SideNoticePresenter.updateCompactVisibility(notices: [next], settings: fixture.settings.settings, displayState: state))
        #expect(!state.compactStatusHidden)
        #expect(fixture.presenter.compactConfiguration(for: [next], at: fixture.date).compactStatusLength == 68)
        _ = SideNoticePresenter.updateCompactVisibility(notices: [], settings: fixture.settings.settings, displayState: state)
        #expect(!state.compactStatusHidden && state.compactStatusIDs.isEmpty)
    }

    @Test
    func alwaysVisibleActivitiesCannotLeaveAHiddenCompactStatus() {
        let state = SideNoticeDisplayState()
        let notice = IslandNotice(id: "ai-active-codex", title: "Codex")
        var settings = FeatureSettings.default
        settings.activityNoticeDisplayDuration = .always
        _ = SideNoticePresenter.updateCompactVisibility(notices: [notice], settings: settings, displayState: state)
        state.compactStatusHidden = true
        #expect(!SideNoticePresenter.updateCompactVisibility(notices: [notice], settings: settings, displayState: state))
        #expect(!state.compactStatusHidden)
    }

    @Test
    func voiceProcessingDimensionsRemainScopedToTheRecordedDisplay() throws {
        let fixture = try Fixture(edge: .top)
        defer { fixture.close() }
        fixture.queue.enqueue(IslandNotice(id: "voice-processing-left", title: "语音", detail: "整理中"), expiresAfter: nil)
        fixture.presenter.setVoiceProcessingDisplayID(7)
        var dimensions: [UInt32: CGFloat?] = [:]
        fixture.presenter.onCompactLayoutChanged = { displayID, _, length, _ in dimensions[displayID] = length }
        fixture.presenter.publishCompactLayout(on: 7)
        fixture.presenter.publishCompactLayout(on: 8)
        #expect(try #require(dimensions[7] ?? nil) > 24)
        #expect(dimensions[8] == .some(nil))
    }

    @Test
    func stoppingThePresenterPreventsQueuedStateChangesFromRecreatingPanels() async throws {
        let fixture = try Fixture(edge: .right)
        var published = 0
        fixture.presenter.onCompactLayoutChanged = { _, _, _, _ in published += 1 }
        fixture.presenter.stop()
        fixture.queue.enqueue(IslandNotice(id: "ai-active-fixture", title: "Fixture"), expiresAfter: nil)
        for _ in 0..<6 { await Task.yield() }
        #expect(published == 0)
        fixture.close()
    }

    @Test(arguments: IslandEdge.allCases)
    func publishingLayoutDuringAScreenSwitchSettlesOnTheSameLivePill(edge: IslandEdge) throws {
        let fixture = try Fixture(edge: edge)
        defer { fixture.close() }
        let other = ScreenSnapshot(displayID: 8,
            frame: CGRect(x: 0, y: 0, width: 1440, height: 900),
            visibleFrame: CGRect(x: 0, y: 0, width: 1440, height: 876))
        let coordinator = OverlayCoordinator(contentView: NSView(),
            layoutEngine: ScreenLayoutEngine(configuration: fixture.settings.settings.islandScreenConfiguration))
        coordinator.screenSnapshotProvider = { [fixture.screen, other] }
        defer { coordinator.stop() }
        coordinator.updateScreens([fixture.screen, other])
        var published = 0
        coordinator.onActiveLayoutChanged = { layout in
            published += 1
            if let displayID = layout?.displayID { fixture.presenter.publishCompactLayout(on: displayID) }
        }
        fixture.presenter.onCompactLayoutChanged = { displayID, details, length, iconSize in
            guard coordinator.activeDisplayID == displayID else { return }
            coordinator.updateCompactStatus(expandsForDetailedStatus: details, compactStatusLength: length, statusIconSize: iconSize)
        }
        fixture.queue.enqueue(IslandNotice(id: "voice-processing-left", title: "语音", detail: "正在处理"), expiresAfter: nil)
        fixture.presenter.setVoiceProcessingDisplayID(7)
        coordinator.selectActiveDisplay(at: CGPoint(x: fixture.screen.frame.midX, y: fixture.screen.frame.midY))
        let recordingLayout = try #require(coordinator.activeLayout)
        #expect(recordingLayout.collapsedFrame.size == (edge.isVertical
            ? CGSize(width: 32, height: 110) : CGSize(width: 98, height: 32)))
        #expect(published <= 2, "Reentrant layout callbacks must converge without repeatedly resizing")
        coordinator.selectActiveDisplay(at: CGPoint(x: other.frame.midX, y: other.frame.midY))
        #expect(coordinator.activeLayout?.displayID == 8)
        #expect(coordinator.activeLayout?.collapsedFrame.size == CGSize(width: 24, height: 24))
        #expect(published <= 4)
        fixture.presenter.publishCompactLayout(on: 7)
        #expect(coordinator.activeLayout?.collapsedFrame.size == CGSize(width: 24, height: 24),
                "A notification from another display cannot change the current animation anchor")
    }

    @Test(arguments: IslandEdge.allCases)
    func transientMessagesUseOneNaturalPillAndRestoreThePreviousStatus(edge: IslandEdge) throws {
        let fixture = try Fixture(edge: edge)
        defer { fixture.close() }
        let notices = [IslandNotice(id: "ai-active-codex", title: "Codex")]
        let previous = fixture.presenter.compactConfiguration(for: notices, at: fixture.date)
        fixture.presenter.setTransientNoticePresented(true, message: "已保存")
        let short = fixture.presenter.compactConfiguration(for: notices, at: fixture.date)
        let text = CompactPillStatusContent.transientPresentation(message: "已保存")
        #expect(short.compactStatusLength == text.length(thickness: 32, edge: edge))
        #expect(!short.expandsForDetailedStatus)
        fixture.presenter.setTransientNoticePresented(true, message: "操作结果稍长一些")
        let long = fixture.presenter.compactConfiguration(for: notices, at: fixture.date)
        #expect(try #require(long.compactStatusLength) > #require(short.compactStatusLength))
        fixture.presenter.setTransientNoticePresented(false)
        #expect(fixture.presenter.compactConfiguration(for: notices, at: fixture.date) == previous)
        fixture.settings.settings.islandPlacement = IslandPlacement()
        let camera = fixture.presenter.compactConfiguration(for: notices, at: fixture.date)
        fixture.presenter.setTransientNoticePresented(true, message: "操作结果稍长一些")
        #expect(fixture.presenter.compactConfiguration(for: notices, at: fixture.date) == camera)
        fixture.settings.settings.islandLayoutStyle = .notch
        let notch = fixture.presenter.compactConfiguration(for: notices, at: fixture.date)
        fixture.presenter.setTransientNoticePresented(false)
        #expect(fixture.presenter.compactConfiguration(for: notices, at: fixture.date) == notch)
    }

    @MainActor
    private final class Fixture {
        let suiteName = "Zisla.PillPresenter.\(UUID().uuidString)"
        let defaults: UserDefaults
        let settings: FeatureSettingsStore
        let language: AppLanguageStore
        let media = NowPlayingService()
        let downloads = BrowserDownloadMonitor()
        let queue = SideNoticeQueue()
        let sweep = AIResultSweepController()
        let date = Date(timeIntervalSince1970: 100)
        var screen = ScreenSnapshot(displayID: 7,
            frame: CGRect(x: -1800, y: -240, width: 1800, height: 1100),
            visibleFrame: CGRect(x: -1800, y: -240, width: 1800, height: 1076))
        lazy var presenter = SideNoticePresenter(queue: queue, resultSweep: sweep, media: media,
            browserDownloads: downloads, settingsStore: settings, languageStore: language,
            isScreenLocked: true, now: { [unowned self] in date }, screenSnapshotProvider: { [unowned self] in [screen] })

        init(edge: IslandEdge) throws {
            defaults = try #require(UserDefaults(suiteName: suiteName))
            settings = FeatureSettingsStore(defaults: defaults)
            language = AppLanguageStore(defaults: defaults)
            settings.settings.islandLayoutStyle = .pill
            settings.settings.islandPlacement = IslandPlacement(mode: .custom, edge: edge)
        }

        func close() {
            presenter.stop()
            queue.removeAll()
            sweep.cancel()
            settings.flushPendingChanges()
            defaults.removePersistentDomain(forName: suiteName)
        }
    }

    private func renderOffscreen(_ content: some View, size: CGSize) async throws -> NSBitmapImageRep {
        let host = NSHostingView(rootView: content.frame(width: size.width, height: size.height)
            .background(.black))
        host.sizingOptions = []
        let window = NSWindow(contentRect: CGRect(origin: CGPoint(x: 20_000, y: 0), size: size),
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
        #expect(host.bounds.size == size && window.alphaValue == 0)
        return try #require(bitmap.converting(to: .sRGB, renderingIntent: .default))
    }
}
