import AppKit
import Foundation
import Testing
import ZislaCore
import ZislaKit
@testable import ZislaKit
@testable import Zisla

@MainActor
struct SideNoticePresenterPillTests {
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
        #expect(paused.compactStatusLength == 70)
        fixture.settings.settings.mediaVisualizationStyle = .glow
        let compact = fixture.presenter.compactConfiguration(for: [notice], at: base)
        #expect(compact.compactStatusLength == 32)
    }

    @Test
    func cameraDetailsAndNotchFramesPreserveTheirExistingSizingRules() throws {
        let fixture = try Fixture(edge: .top)
        defer { fixture.close() }
        let notice = IslandNotice(id: "media-active-left", title: "Music", side: .left)
        fixture.settings.settings.mediaCompactStyle = .detailed
        fixture.settings.settings.islandPlacement = IslandPlacement()
        let camera = try #require(fixture.presenter.compactFrame(for: fixture.screen, notices: [notice], at: fixture.date))
        #expect(camera.midX == fixture.screen.frame.midX)
        #expect(camera.midY == fixture.screen.frame.maxY - fixture.screen.topBarHeight / 2)
        #expect(camera.width >= 380)
        fixture.settings.settings.islandLayoutStyle = .notch
        #expect(fixture.presenter.compactFrame(for: fixture.screen, notices: [notice], at: fixture.date)
            == SideNoticeLayoutEngine().compactBarFrame(for: fixture.screen, notices: [notice], settings: fixture.settings.settings))
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
        #expect(configuration.compactStatusLength == 32)
        let frame = try #require(fixture.presenter.compactFrame(for: fixture.screen, notices: [notice], at: fixture.date, statusHidden: true))
        #expect(frame.size == CGSize(width: 32, height: 32))
        let next = IslandNotice(id: "ai-active-codex", title: "Codex")
        #expect(SideNoticePresenter.updateCompactVisibility(notices: [next], settings: fixture.settings.settings, displayState: state))
        #expect(!state.compactStatusHidden)
        #expect(fixture.presenter.compactConfiguration(for: [next], at: fixture.date).compactStatusLength == 52)
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
        fixture.presenter.onCompactLayoutChanged = { displayID, _, length in dimensions[displayID] = length }
        fixture.presenter.publishCompactLayout(on: 7)
        fixture.presenter.publishCompactLayout(on: 8)
        #expect(try #require(dimensions[7] ?? nil) > 32)
        #expect(dimensions[8] == 32)
    }

    @Test
    func stoppingThePresenterPreventsQueuedStateChangesFromRecreatingPanels() async throws {
        let fixture = try Fixture(edge: .right)
        var published = 0
        fixture.presenter.onCompactLayoutChanged = { _, _, _ in published += 1 }
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
        fixture.presenter.onCompactLayoutChanged = { displayID, details, length in
            guard coordinator.activeDisplayID == displayID else { return }
            coordinator.updateCompactStatus(expandsForDetailedStatus: details, compactStatusLength: length)
        }
        fixture.queue.enqueue(IslandNotice(id: "voice-processing-left", title: "语音", detail: "正在处理"), expiresAfter: nil)
        fixture.presenter.setVoiceProcessingDisplayID(7)
        coordinator.selectActiveDisplay(at: CGPoint(x: fixture.screen.frame.midX, y: fixture.screen.frame.midY))
        let recordingLayout = try #require(coordinator.activeLayout)
        #expect(recordingLayout.collapsedFrame.size == (edge.isVertical
            ? CGSize(width: 32, height: 94) : CGSize(width: 82, height: 32)))
        #expect(published <= 2, "Reentrant layout callbacks must converge without repeatedly resizing")
        coordinator.selectActiveDisplay(at: CGPoint(x: other.frame.midX, y: other.frame.midY))
        #expect(coordinator.activeLayout?.displayID == 8)
        #expect(coordinator.activeLayout?.collapsedFrame.size == CGSize(width: 32, height: 32))
        #expect(published <= 4)
        fixture.presenter.publishCompactLayout(on: 7)
        #expect(coordinator.activeLayout?.collapsedFrame.size == CGSize(width: 32, height: 32),
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
        let screen = ScreenSnapshot(displayID: 7,
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
}
