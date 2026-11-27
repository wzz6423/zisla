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
                                         visibleFrame: CGRect(x: 20000, y: 0, width: 1440, height: 876),
                                         safeAreaInsets: ScreenInsets(top: 24),
                                         auxiliaryTopLeftArea: CGRect(x: 20000, y: 876, width: 680, height: 24),
                                         auxiliaryTopRightArea: CGRect(x: 20760, y: 876, width: 680, height: 24), persistentID: "primary")
    private let external = ScreenSnapshot(displayID: 2,
                                          frame: CGRect(x: -1920, y: -200, width: 1920, height: 1080),
                                          visibleFrame: CGRect(x: -1920, y: -200, width: 1920, height: 1056), persistentID: "external")

    @Test(arguments: [false, true])
    func unselectedDisplayKeepsItsIdleContentDuringAResultSweep(moreInformation: Bool) throws {
        let fixture = try StatusIconDestinationIntegrationTests.IconFixture(edge: .top)
        defer { fixture.close() }
        fixture.settings.settings.islandShowMoreInformation = moreInformation
        fixture.settings.settings.statusIconDestination = .menuBar
        fixture.settings.settings.islandNotchBackground = .black
        let state = SideNoticeDisplayState()
        state.islandLayoutStyle = .pill
        state.placementMode = .custom
        state.noticesEnabled = false
        state.compactWingHeight = 32
        let date = Date(timeIntervalSince1970: 100)
        var now = date
        let sweep = AIResultSweepController(now: { now })
        defer { sweep.cancel() }
        let view = CompactStatusBarView(queue: fixture.queue, displayState: state, media: fixture.media,
                                        browserDownloads: fixture.downloads, settingsStore: fixture.settings, resultSweep: sweep,
                                        pomodoro: PomodoroService(notificationRequestHandler: { _ in }, defaults: fixture.defaults), onStatusHidden: {})
        func pixels() throws -> Data {
            let renderer = ImageRenderer(content: view.statusBarContent(at: date)
                .frame(width: 128, height: 32).environment(\._accessibilityReduceMotion, true))
            renderer.scale = 1
            return try #require(renderer.cgImage?.dataProvider?.data) as Data
        }
        let idle = try pixels()
        fixture.queue.enqueue(IslandNotice(id: "ai-active-fixture", title: "Codex"), expiresAfter: nil)
        sweep.receive(previous: .running, task: AIProgressTask(id: "finished", provider: .codex, title: "Task",
                                                               progress: nil, status: .succeeded, updatedAt: date),
                      observedSince: .distantPast, settings: fixture.settings.settings)
        now = date.addingTimeInterval(AIResultSweep.duration / 2)
        #expect(sweep.current != nil)
        #expect(view.selectedCompactStatusPriority == nil)
        #expect(try pixels() == idle, "Activity and result animations on another display must leave the idle island unchanged")
    }

    @Test
    func bothDisplaysShowAnIdleIslandBeforeAnyActivity() async throws {
        let suite = "Zisla.SimultaneousIslands.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = FeatureSettingsStore(defaults: defaults)
        store.settings.islandDisplaySettings = [
            "primary": IslandDisplaySettings(mode: .notch),
            "external": IslandDisplaySettings(mode: .pill, placement: IslandPlacement(mode: .custom, edge: .left)),
        ]
        let queue = SideNoticeQueue()
        let sweep = AIResultSweepController()
        let presenter = SideNoticePresenter(queue: queue, resultSweep: sweep,
                                            media: NowPlayingService(), pomodoro: PomodoroService(notificationRequestHandler: { _ in }, defaults: defaults),
                                            browserDownloads: BrowserDownloadMonitor(), settingsStore: store,
                                            languageStore: AppLanguageStore(defaults: defaults), displayIDs: [primary.displayID],
                                            reduceMotion: { true }, screenSnapshotProvider: { [primary, external] })
        defer {
            presenter.stop()
            queue.removeAll()
            sweep.cancel()
            store.flushPendingChanges()
        }
        typealias IslandHost = NSHostingView<AppLanguageEnvironment<CompactStatusBarView>>
        func visibleIslands() -> [IslandHost] {
            NSApplication.shared.windows.compactMap { $0.contentView as? IslandHost }
                .filter { $0.rootView.content.settingsStore === store && $0.window?.isVisible == true }
        }
        let deadline = ContinuousClock.now + .seconds(2)
        while visibleIslands().count < 2, ContinuousClock.now < deadline { await Task.yield() }
        let hosts = visibleIslands()
        #expect(hosts.count == 2, "Both islands must appear before a pointer or activity event reaches either display")
        #expect(hosts.contains { primary.frame.contains($0.window?.frame ?? .null) })
        #expect(hosts.contains { external.frame.contains($0.window?.frame ?? .null) })
        let primaryHost = try #require(hosts.first { primary.frame.contains($0.window?.frame ?? .null) })
        let externalHost = try #require(hosts.first { external.frame.contains($0.window?.frame ?? .null) })
        let idlePrimaryLayout = ScreenLayoutEngine(configuration: store.settings.islandScreenConfiguration).layout(for: primary)
        #expect(primaryHost.window?.frame == idlePrimaryLayout.collapsedFrame.integral)
        let petFrame = try #require(CollapsedPetLayout.petFrame(for: idlePrimaryLayout, side: .right))
        #expect(!petFrame.intersects(try #require(primaryHost.window?.frame)),
                "The idle notch must not grow unused status wings over its neighboring pet")
        let idleExternalFrame = try #require(externalHost.window?.frame)
        queue.enqueue(IslandNotice(id: "ai-active-fixture", title: "Codex"), expiresAfter: nil)
        presenter.setStatusIcons([])
        #expect(primaryHost.rootView.content.selectedCompactStatusPriority == .aiActivity)
        #expect(externalHost.rootView.content.selectedCompactStatusPriority == nil)
        #expect(externalHost.window?.isVisible == true, "Notification selection must not hide the idle island")
        var publishedConfiguration = store.settings.islandScreenConfiguration
        publishedConfiguration.layoutStyle = .pill
        publishedConfiguration.placement = try #require(store.settings.islandDisplaySettings["external"]).placement
        presenter.onCompactLayoutChanged = { displayID, detailed, length, sideWidth, size in
            guard displayID == external.displayID else { return }
            publishedConfiguration.expandsForDetailedStatus = detailed
            publishedConfiguration.compactStatusLength = length
            publishedConfiguration.compactStatusSideWidth = sideWidth
            publishedConfiguration.statusIconSize = size
        }
        presenter.publishCompactLayout(on: external.displayID)
        #expect(ScreenLayoutEngine(configuration: publishedConfiguration).layout(for: external).collapsedFrame.integral == idleExternalFrame,
                "Activating a display outside the notification selection must preserve its idle geometry")
        let icons = [IslandStatusIcon(id: "cpu", content: .metric(.cpu, text: "20%", image: nil, style: .detailed), tooltip: "CPU")]
        store.settings.statusIconDestination = .island
        presenter.setStatusIcons(icons)
        let iconFrame = try #require(externalHost.window?.frame)
        let task = AIProgressTask(id: "fixture-result", provider: .codex, title: "Task", progress: nil,
                                  status: .succeeded, updatedAt: .now)
        sweep.receive(previous: .running, task: task, observedSince: .distantPast, settings: store.settings)
        presenter.setStatusIcons(icons)
        #expect(sweep.current != nil)
        #expect(externalHost.rootView.content.displayState.statusIcons == icons,
                "A result sweep on the notification display must not remove the other display's status icons")
        #expect(externalHost.window?.frame == iconFrame)
        sweep.cancel()
        presenter.setStatusIcons([])

        presenter.setClipboardAssistantVisible(true, on: primary.displayID)
        #expect(primaryHost.window?.isVisible == false && externalHost.window?.isVisible == true)
        presenter.setIslandExpanded(true, on: external.displayID)
        presenter.setClipboardAssistantVisible(false, on: primary.displayID)
        #expect(primaryHost.window?.isVisible == true && externalHost.window?.isVisible == false)
        presenter.setIslandExpanded(true, on: primary.displayID)
        #expect(primaryHost.window?.isVisible == false && externalHost.window?.isVisible == true)
        presenter.setIslandExpanded(false)

        let externalFrame = externalHost.window?.frame
        presenter.setVoiceRecording(true, on: primary.displayID)
        #expect(primaryHost.window?.isVisible == false && externalHost.window?.isVisible == true)
        #expect(externalHost.window?.frame == externalFrame)
        presenter.setTransientNoticePresented(true, message: "已保存", on: primary.displayID)
        presenter.setVoiceRecording(false)
        #expect(primaryHost.window?.isVisible == false && externalHost.window?.isVisible == true)
        #expect(externalHost.window?.frame == externalFrame, "A message on the primary display must not resize the external island")
        presenter.setScreenshotActive(true)
        #expect(hosts.allSatisfy { $0.window?.isVisible == false })
        presenter.setScreenshotActive(false)
        #expect(primaryHost.window?.isVisible == false && externalHost.window?.isVisible == true)
        presenter.setTransientNoticePresented(false)
        presenter.setScreenLocked(true)
        #expect(hosts.allSatisfy { $0.window?.isVisible == false })
        presenter.setScreenLocked(false)
        #expect(hosts.allSatisfy { $0.window?.isVisible == true })

        presenter.setDisplayIDs([external.displayID])
        #expect(primaryHost.rootView.content.selectedCompactStatusPriority == nil)
        #expect(externalHost.rootView.content.selectedCompactStatusPriority == .aiActivity)
        #expect(hosts.allSatisfy { $0.window?.isVisible == true })

        presenter.setPlacementSelectionActive(true)
        #expect(hosts.allSatisfy { $0.window?.isVisible == false })
        presenter.setPlacementSelectionActive(false)
        #expect(hosts.allSatisfy { $0.window?.isVisible == true })
    }

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
        controller.present(detection, visualStyle: .transparent, at: CGPoint(x: external.frame.midX, y: external.frame.midY))
        #expect(controller.presentationDisplayID == external.displayID)
        controller.dismiss(animated: false)
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
        #expect(primaryHosts.allSatisfy { $0.rootView.content.selectedCompactStatusPriority != .aiAccountBalance },
                "Persistent quota belongs only to a custom pill display; the other display retains its idle island")
        store.settings.islandDisplaySettings["external"]?.mode = .hidden
        presenter.setStatusIcons([])
        #expect(presenter.compactFrame(for: external, notices: []) == nil)
        #expect(externalHost.window?.isVisible != true)
    }
}
