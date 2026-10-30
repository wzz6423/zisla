import AppKit
import Combine
import Foundation
import Testing
import ZislaCore
@testable import ZislaKit

@testable import Zisla

struct IslandDashboardViewLayoutTests {
    @Test
    func dashboardCapsHeightAtKeyboardSurfaceHeight() {
        let layout = IslandModuleLayout.resolved(for: .dashboard, dashboardCardCount: 100)

        #expect(layout.islandSize.height == IslandModuleLayout.keyboardSound.islandSize.height)
        #expect(layout.panelSize.height == IslandModuleLayout.keyboardSound.panelSize.height)
    }

    @Test(arguments: [
        (IslandModuleLayout.toolbox, CGFloat(136)),
        (IslandModuleLayout.download, CGFloat(170)),
        (IslandModuleLayout.agenda, CGFloat(160)),
        (IslandModuleLayout.system, CGFloat(401)),
        (IslandModuleLayout.shelf, CGFloat(355)),
        (IslandModuleLayout.clipboard, CGFloat(355)),
        (IslandModuleLayout.ai, CGFloat(350)),
    ])
    func loweredHeaderPreservesEachFixedModulesContentBudget(
        layout: IslandModuleLayout, contentHeight: CGFloat
    ) {
        let chrome = ExpandedPetLayout.contentTopInset
            + IslandDashboardLayout.mediaHeaderHeight
            + IslandDashboardLayout.toolbarHeight
            + IslandDashboardLayout.toolbarBottomInset
        let availableContent = layout.islandSize.height - chrome
            - IslandSurfaceGeometry.moduleInset * 2
        #expect(availableContent == contentHeight,
                "Lowering the header must not take space from the module below it")
        #expect(layout.panelSize.height == layout.islandSize.height + 4)
    }

    @Test(arguments: [CGFloat(24), 32])
    func cameraHeaderClearsTheActualCollapsedRowByTwelvePoints(thickness: CGFloat) {
        let screen = ScreenSnapshot(displayID: 7,
            frame: CGRect(x: 0, y: 0, width: 1512, height: 982),
            visibleFrame: CGRect(x: 0, y: 0, width: 1512, height: 938),
            safeAreaInsets: ScreenInsets(top: 44),
            auxiliaryTopLeftArea: CGRect(x: 0, y: 938, width: 656, height: 44),
            auxiliaryTopRightArea: CGRect(x: 856, y: 938, width: 656, height: 44))
        let layout = ScreenLayoutEngine(configuration: ScreenLayoutConfiguration(
            layoutStyle: .pill, pillSize: CGSize(width: 80, height: thickness)
        )).layout(for: screen)
        #expect(layout.centerOcclusionWidth > 0)
        let headerTop = IslandRootView.contentTopInset(layoutStyle: .pill, screenLayout: layout)
        #expect(headerTop - layout.collapsedFrame.height == 12,
                "The expanded header must keep the requested gap below the camera-aligned row")
        #expect(headerTop == thickness + 12)
        #expect(IslandRootView.contentTopInset(layoutStyle: .notch, screenLayout: layout) == 16,
                "The original notch layout uses the shared lowered header inset")
    }

    @Test(arguments: IslandEdge.allCases)
    func unobstructedPillsAndMissingScreenLayoutsUseTheLoweredHeaderInset(edge: IslandEdge) {
        let screen = ScreenSnapshot(displayID: 8,
            frame: CGRect(x: -1440, y: 100, width: 1440, height: 900),
            visibleFrame: CGRect(x: -1440, y: 100, width: 1440, height: 876))
        let layout = ScreenLayoutEngine(configuration: ScreenLayoutConfiguration(
            layoutStyle: .pill, placement: IslandPlacement(mode: .custom, edge: edge)
        )).layout(for: screen)
        #expect(layout.centerOcclusionWidth == 0)
        #expect(IslandRootView.contentTopInset(layoutStyle: .pill, screenLayout: layout) == 16)
        #expect(IslandRootView.contentTopInset(layoutStyle: .pill, screenLayout: nil) == 16)
    }

    @Test(arguments: [CGFloat(24), 32])
    func cameraModuleSizesKeepTheirContentAndCrownBudgets(thickness: CGFloat) {
        let camera = cameraLayout(thickness: thickness)
        let topInset = IslandRootView.contentTopInset(layoutStyle: .pill, screenLayout: camera)
        let chrome = topInset + IslandDashboardLayout.mediaHeaderHeight
            + IslandDashboardLayout.toolbarHeight + IslandDashboardLayout.toolbarBottomInset
        for (module, contentHeight): (IslandModule, CGFloat) in [
            (.shelf, 355), (.clipboard, 355), (.toolbox, 136),
            (.agenda, 160), (.download, 160), (.system, 401), (.aiMonitor, 350)
        ] {
            let layout = IslandModuleLayout.resolved(
                for: module, dashboardCardCount: 0, contentTopInset: topInset
            )
            let published = AppDelegate.expandedPanelSize(
                module: module, isMirrorPresented: false, isTeleprompterPresented: false,
                dashboardCardCount: 0, includesPet: true, layoutStyle: .pill,
                contentTopInset: topInset
            )
            #expect(published == layout, "The window and its surface must reserve the same header height")
            #expect(layout.islandSize.height - chrome - IslandSurfaceGeometry.moduleInset * 2 == contentHeight)
            #expect(layout.panelSize.height == layout.islandSize.height + 4)
        }
        for cardCount in [0, 1, 2, 3, 100] {
            let layout = IslandModuleLayout.resolved(
                for: .dashboard, dashboardCardCount: cardCount, contentTopInset: topInset
            )
            let metrics = IslandCrownGeometry.crownMetrics(
                forSurfaceHeight: layout.islandSize.height, blendHeight: 64, contentTopInset: topInset
            )
            #expect(metrics.solidHeight >= topInset + IslandDashboardLayout.mediaHeaderHeight
                + IslandDashboardLayout.toolbarHeight, "The camera header's white toolbar must stay above the fade")
            #expect(metrics.solidHeight + metrics.blendHeight <= layout.islandSize.height)
            #expect(metrics.blendHeight > 0)
        }
    }

    @Test
    func panelSizePublisherFollowsCameraChangesWithoutRepeatingOrSurvivingCancellation() {
        let presentation = CurrentValueSubject<(IslandModule, Bool, Bool, Int), Never>((.shelf, false, false, 0))
        var pillSettings = FeatureSettings.default
        pillSettings.islandLayoutStyle = .pill
        let settings = CurrentValueSubject<FeatureSettings, Never>(pillSettings)
        let screen = CurrentValueSubject<ScreenOverlayLayout?, Never>(nil)
        var sizes: [CGSize] = []
        let subscription = AppDelegate.expandedPanelSizes(
            presentation: presentation.eraseToAnyPublisher(), settings: settings.eraseToAnyPublisher(),
            screenLayout: screen.eraseToAnyPublisher()
        ).sink { sizes.append($0) }
        defer { subscription.cancel() }
        #expect(sizes == [CGSize(width: 776, height: 512)])
        let camera = cameraLayout(thickness: 24)
        screen.send(camera)
        #expect(sizes.last == CGSize(width: 776, height: 532))
        var configuration = ScreenLayoutConfiguration(expandedSize: CGSize(width: 900, height: 700), layoutStyle: .pill)
        let union = ScreenLayoutEngine(configuration: configuration).layout(for: cameraScreen)
        screen.send(union)
        configuration.compactStatusLength = 44
        screen.send(ScreenLayoutEngine(configuration: configuration).layout(for: cameraScreen))
        #expect(sizes.count == 2, "Panel-frame feedback and activity width cannot restart the same resize")
        screen.send(cameraLayout(thickness: 32))
        #expect(sizes.last == CGSize(width: 776, height: 540))
        screen.send(nil)
        #expect(sizes.last == CGSize(width: 776, height: 512))
        presentation.send((.shelf, true, false, 0))
        #expect(sizes.last == IslandModuleLayout.mirror.panelSize)
        screen.send(camera)
        #expect(sizes.count == 5, "A camera change cannot alter the full-frame mirror")
        presentation.send((.shelf, false, true, 0))
        #expect(sizes.last == IslandModuleLayout.teleprompter.panelSize)
        presentation.send((.shelf, false, false, 0))
        #expect(sizes.last == CGSize(width: 776, height: 532))
        let count = sizes.count
        subscription.cancel()
        screen.send(nil)
        presentation.send((.dashboard, false, false, 100))
        #expect(sizes.count == count)
    }

    @Test @MainActor
    func cameraPanelFeedbackConvergesAndScreenSwitchingRestoresTheOrdinaryBudget() {
        let presentation = CurrentValueSubject<(IslandModule, Bool, Bool, Int), Never>((.shelf, false, false, 0))
        var pillSettings = FeatureSettings.default
        pillSettings.islandLayoutStyle = .pill
        let settings = CurrentValueSubject<FeatureSettings, Never>(pillSettings)
        let screen = CurrentValueSubject<ScreenOverlayLayout?, Never>(nil)
        let other = ScreenSnapshot(displayID: 8,
            frame: CGRect(x: -1440, y: 100, width: 1440, height: 900),
            visibleFrame: CGRect(x: -1440, y: 100, width: 1440, height: 876))
        let coordinator = OverlayCoordinator(contentView: NSView(), layoutEngine: ScreenLayoutEngine(
            configuration: ScreenLayoutConfiguration(expandedSize: IslandModuleLayout.shelf.panelSize, layoutStyle: .pill)
        ))
        coordinator.screenSnapshotProvider = { [cameraScreen, other] }
        coordinator.onActiveLayoutChanged = { screen.send($0) }
        var sizes: [CGSize] = []
        let subscription = AppDelegate.expandedPanelSizes(
            presentation: presentation.eraseToAnyPublisher(), settings: settings.eraseToAnyPublisher(),
            screenLayout: screen.eraseToAnyPublisher()
        ).sink { size in
            sizes.append(size)
            coordinator.updateExpandedSize(size)
        }
        defer { subscription.cancel(); coordinator.stop() }
        coordinator.updateScreens([cameraScreen, other], repositionVisiblePanel: false, refreshPersistentPanels: false)
        coordinator.selectActiveDisplay(at: CGPoint(x: cameraScreen.frame.midX, y: cameraScreen.frame.midY))
        #expect(sizes == [CGSize(width: 776, height: 512), CGSize(width: 776, height: 532)])
        coordinator.selectActiveDisplay(at: CGPoint(x: other.frame.midX, y: other.frame.midY))
        #expect(coordinator.activeLayout?.expandedFrame.height == 512)
        coordinator.selectActiveDisplay(at: CGPoint(x: cameraScreen.frame.midX, y: cameraScreen.frame.midY))
        #expect(coordinator.activeLayout?.expandedFrame.height == 532)
        let count = sizes.count
        coordinator.updateScreens([cameraScreen, other], repositionVisiblePanel: false, refreshPersistentPanels: false)
        #expect(sizes.count == count)
        #expect(!coordinator.isRunning && !coordinator.isVisible)
    }

    @Test @MainActor
    func recordingKeepsTheLatestScreenBudgetWithoutResizingItsCompactSurface() async throws {
        var delegate: AppDelegate? = AppDelegate()
        weak var weakDelegate = delegate
        let compact = IslandModuleLayout.compactSurface(
            collapsedSize: CGSize(width: 80, height: 24), overflowWidth: 80, edge: .top
        ).panelSize
        let coordinator = OverlayCoordinator(contentView: NSView(), layoutEngine: ScreenLayoutEngine(
            configuration: ScreenLayoutConfiguration(expandedSize: compact, layoutStyle: .pill)
        ))
        coordinator.screenSnapshotProvider = { [cameraScreen] }
        coordinator.updateScreens([cameraScreen], repositionVisiblePanel: false, refreshPersistentPanels: false)
        coordinator.selectActiveDisplay(at: CGPoint(x: cameraScreen.frame.midX, y: cameraScreen.frame.midY))
        defer { coordinator.stop() }
        for height: CGFloat in [532, 540, 512] {
            delegate?.updateExpandedPanelSize(
                CGSize(width: 776, height: height), duringVoiceRecording: true, coordinator: coordinator
            )
            for _ in 0..<6 { await Task.yield() }
            #expect(delegate?.voiceRecordingSavedPanelSize == CGSize(width: 776, height: height))
            #expect(coordinator.activeLayout?.expandedFrame.size == compact,
                    "Camera and screen changes must reserve the future budget without disturbing dictation")
        }
        let restored = try #require(delegate?.voiceRecordingSavedPanelSize)
        delegate?.updateExpandedPanelSize(restored, duringVoiceRecording: false, coordinator: coordinator)
        for _ in 0..<6 { await Task.yield() }
        #expect(coordinator.activeLayout?.expandedFrame.size == restored)
        delegate = nil
        #expect(weakDelegate == nil, "A queued panel update cannot retain the application owner")
    }

    @Test @MainActor
    func recordingOperationsAddAndRemoveDashboardRows() {
        let queue = SideNoticeQueue()
        defer { queue.removeAll() }
        queue.enqueue(IslandNotice(id: "browser-download-left", title: "Download"), expiresAfter: nil)
        #expect(queue.screenRecordingOperations.count == 0)
        queue.enqueue(IslandNotice(id: "screen-recording-operation-save", title: "Save"), expiresAfter: nil)
        #expect(queue.screenRecordingOperations.count == 1)
        #expect(IslandDashboardLayout.cardRowCount(forCardCount: 2 + queue.screenRecordingOperations.count) == 2)
        queue.remove(id: "screen-recording-operation-save")
        #expect(IslandDashboardLayout.cardRowCount(forCardCount: 2 + queue.screenRecordingOperations.count) == 1)
    }

    private var cameraScreen: ScreenSnapshot {
        ScreenSnapshot(displayID: 7,
            frame: CGRect(x: 0, y: 0, width: 1512, height: 982),
            visibleFrame: CGRect(x: 0, y: 0, width: 1512, height: 938),
            safeAreaInsets: ScreenInsets(top: 44),
            auxiliaryTopLeftArea: CGRect(x: 0, y: 938, width: 656, height: 44),
            auxiliaryTopRightArea: CGRect(x: 856, y: 938, width: 656, height: 44))
    }

    private func cameraLayout(thickness: CGFloat) -> ScreenOverlayLayout {
        ScreenLayoutEngine(configuration: ScreenLayoutConfiguration(
            layoutStyle: .pill, pillSize: CGSize(width: 80, height: thickness)
        )).layout(for: cameraScreen)
    }

}
