import AppKit
import SwiftUI
import Testing
import ZislaCore
import ZislaKit
@testable import ZislaKit
@testable import Zisla

@MainActor
struct IslandDisplayPresentationTests {
    private let primary = ScreenSnapshot(displayID: 1,
                                         frame: CGRect(x: 20000, y: 0, width: 1440, height: 900),
                                         visibleFrame: CGRect(x: 20000, y: 0, width: 1440, height: 876), persistentID: "primary")
    private let external = ScreenSnapshot(displayID: 2,
                                          frame: CGRect(x: -1920, y: -200, width: 1920, height: 1080),
                                          visibleFrame: CGRect(x: -1920, y: -200, width: 1920, height: 1056), persistentID: "external")

    @Test
    func hidingTheScreenDismissesAnAlreadyPresentedQuickAction() throws {
        let screen = try #require(NSScreen.screens.first)
        let snapshot = try #require(ScreenSnapshot(screen: screen))
        let other = ScreenSnapshot(displayID: snapshot.displayID &+ 1,
                                   frame: CGRect(x: 20000, y: 0, width: 1000, height: 800),
                                   visibleFrame: CGRect(x: 20000, y: 0, width: 1000, height: 776), persistentID: "other")
        let controller = ClipboardAssistantController(windowPresenter: { _, _ in })
        controller.screenSnapshotProvider = { [snapshot, other] }
        controller.screenAtPoint = { _ in screen }
        controller.displayDuration = .never
        defer { controller.dismiss(animated: false) }
        var events: [Bool] = []
        controller.onPresentationChanged = { events.append($0) }
        let detection = ClipboardAssistantDetection(kind: .text, title: "synthetic text")
        controller.present(detection, visualStyle: .transparent,
                           at: CGPoint(x: snapshot.frame.midX, y: snapshot.frame.midY))
        #expect(controller.presentation.detection == detection && events == [true])
        controller.screenLayoutConfiguration.displaySettings[snapshot.persistentID] = IslandDisplaySettings(mode: .hidden)
        #expect(controller.presentation.detection == nil && events == [true, false])
        #expect(controller.actionHotkeys.isEmpty)
    }

    @Test
    func quickActionsUseTheTargetScreensLayoutAndSuppressHiddenScreens() throws {
        var settings = FeatureSettings(islandDisplaySettings: [
            "external": IslandDisplaySettings(mode: .pill, placement: IslandPlacement(mode: .custom, edge: .left, offset: 0.3)),
        ])
        let controller = ClipboardAssistantController(windowPresenter: { _, _ in })
        controller.screenSnapshotProvider = { [primary, external] }
        controller.screenLayoutConfiguration = settings.islandScreenConfiguration
        defer { controller.dismiss(animated: false) }
        let detection = ClipboardAssistantDetection(kind: .text, title: "synthetic text")
        let row = controller.rowLayout(for: detection, on: external)
        #expect(row.style == .pill && row.edge == .left && row.placementMode == .custom)
        settings.islandDisplaySettings["external"]?.mode = .hidden
        controller.screenLayoutConfiguration = settings.islandScreenConfiguration
        #expect(controller.present(detection, visualStyle: .transparent,
                                   at: CGPoint(x: external.frame.midX, y: external.frame.midY)) == nil)
        #expect(controller.presentation.detection == nil)
        controller.screenSnapshotProvider = { [external] }
        #expect(controller.rowLayout(for: detection, on: external).style == .notch)
    }

    @Test
    func sideNoticesAndIdleStatusUseEachScreensModeAndRemoveHiddenPanels() throws {
        let suite = "Zisla.DisplayPresentation.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = FeatureSettingsStore(defaults: defaults)
        store.settings.islandDisplaySettings = [
            "external": IslandDisplaySettings(mode: .pill, placement: IslandPlacement(mode: .custom, edge: .left, offset: 0.3)),
        ]
        let queue = SideNoticeQueue()
        let sweep = AIResultSweepController()
        let presenter = SideNoticePresenter(queue: queue, resultSweep: sweep,
                                            media: NowPlayingService(), pomodoro: PomodoroService(notificationRequestHandler: { _ in }, defaults: defaults),
                                            browserDownloads: BrowserDownloadMonitor(), settingsStore: store,
                                            languageStore: AppLanguageStore(defaults: defaults), isScreenLocked: true,
                                            screenSnapshotProvider: { [primary, external] })
        defer {
            presenter.stop()
            queue.removeAll()
            sweep.cancel()
            store.flushPendingChanges()
        }
        presenter.setScreenLocked(false)
        presenter.setStatusIcons([])
        let hosts = NSApp.windows.compactMap { $0.contentView as? NSHostingView<AppLanguageEnvironment<CompactStatusBarView>> }
        let externalHost = try #require(hosts.first {
            $0.rootView.content.settingsStore === store && $0.rootView.content.displayState.islandEdge == .left
        })
        #expect(externalHost.rootView.content.displayState.islandLayoutStyle == .pill)
        let frame = try #require(presenter.compactFrame(for: external, notices: []))
        #expect(externalHost.window?.frame == frame.integral)
        let icons = [IslandStatusIcon(id: "cpu", content: .metric(.cpu, text: "20%", image: nil, style: .detailed), tooltip: "CPU")]
        presenter.setStatusIcons(icons)
        #expect(externalHost.rootView.content.displayState.statusIcons == icons)
        #expect(externalHost.rootView.content.displayState.islandEdge == .left)
        let quota = IslandNotice(id: AIAccountBalanceNoticeController.pinnedID, title: "Codex", style: .status)
        #expect(presenter.compactFrame(for: primary, notices: [quota]) == presenter.compactFrame(for: primary, notices: []))
        queue.enqueue(quota, expiresAfter: nil)
        presenter.setStatusIcons(icons)
        let primaryHosts = NSApp.windows.compactMap { $0.contentView as? NSHostingView<AppLanguageEnvironment<CompactStatusBarView>> }
            .filter { $0.rootView.content.settingsStore === store && $0.rootView.content.displayState.islandEdge == .top }
        #expect(primaryHosts.allSatisfy { $0.window?.isVisible != true }, "Persistent quota belongs only to a custom pill display")
        store.settings.islandDisplaySettings["external"]?.mode = .hidden
        presenter.setStatusIcons([])
        #expect(presenter.compactFrame(for: external, notices: []) == nil)
        #expect(externalHost.window?.isVisible != true)
    }
}
