import AppKit
import Testing
import ZislaCore
@testable import ZislaKit

struct IslandDisplayLayoutTests {
    private let builtIn = ScreenSnapshot(displayID: 1,
                                         frame: CGRect(x: 20000, y: 0, width: 1512, height: 982),
                                         visibleFrame: CGRect(x: 20000, y: 0, width: 1512, height: 950), persistentID: "built-in")
    private let external = ScreenSnapshot(displayID: 2,
                                          frame: CGRect(x: -1920, y: -200, width: 1920, height: 1080),
                                          visibleFrame: CGRect(x: -1920, y: -200, width: 1920, height: 1056), persistentID: "external")

    @Test(arguments: IslandEdge.allCases)
    func mixedModesUseEachDisplaysConfirmedPlacement(edge: IslandEdge) throws {
        let placement = IslandPlacement(mode: .custom, edge: edge, offset: 0.23, inwardDistance: 28)
        let settings = FeatureSettings(statusIconDestination: .menuBar, islandDisplaySettings: [
            "built-in": IslandDisplaySettings(mode: .notch),
            "external": IslandDisplaySettings(mode: .pill, placement: placement),
        ])
        let engine = ScreenLayoutEngine(configuration: settings.islandScreenConfiguration)
        let layouts = engine.layouts(for: [builtIn, external])
        #expect(layouts.count == 2)
        #expect(layouts[0].style == .notch)
        #expect(layouts[1].style == .pill && layouts[1].edge == edge)
        let resolved = try #require(settings.islandSettings(for: external, displayCount: 2))
        #expect(resolved.islandPlacement == placement)
        #expect(layouts[1] == ScreenLayoutEngine(configuration: resolved.islandScreenConfiguration).layout(for: external))
        #expect(settings.islandSettings(for: layouts[1]).islandPlacement == placement)
        let notices = [IslandNotice(id: "ai-active-fixture", title: "Codex")]
        #expect(SideNoticeLayoutEngine().compactBarFrame(for: layouts[1], notices: notices,
                                                         settings: settings.islandSettings(for: layouts[1]))
                == SideNoticeLayoutEngine().compactBarFrame(for: external, notices: notices, settings: resolved))
        var iconSettings = resolved
        iconSettings.statusIconDestination = .island
        #expect(SideNoticeLayoutEngine().compactBarFrame(for: layouts[1], notices: notices,
                                                         settings: iconSettings) == layouts[1].collapsedFrame)
    }

    @Test
    func hiddenScreensHaveNoHoverOrDropTargetsAndSingleScreenUsesGlobalDefaults() throws {
        let settings = FeatureSettings(islandLayoutStyle: .pill, islandDisplaySettings: [
            "external": IslandDisplaySettings(mode: .hidden),
        ], islandPlacement: IslandPlacement(mode: .custom, edge: .left))
        let engine = ScreenLayoutEngine(configuration: settings.islandScreenConfiguration)
        let layouts = engine.layouts(for: [builtIn, external])
        #expect(layouts.map(\.displayID) == [1])
        let hiddenPoint = CGPoint(x: external.frame.midX, y: external.frame.maxY)
        #expect(engine.layout(containing: hiddenPoint, in: layouts) == nil)
        #expect(engine.transferDragLayout(containing: hiddenPoint, hasSupportedPayload: true, in: layouts) == nil)
        #expect(settings.islandSettings(for: external, displayCount: 2) == nil)
        let single = try #require(engine.layouts(for: [external]).first)
        #expect(single.style == .pill && single.edge == .left)
        #expect(engine.layouts(for: []).isEmpty)
        #expect(engine.layouts(for: [builtIn, external]) == layouts)
    }

    @Test
    func reconnectedDisplayRestoresSettingsUsingUUIDInsteadOfSessionNumber() throws {
        let settings = FeatureSettings(islandDisplaySettings: [
            "external": IslandDisplaySettings(mode: .pill, placement: IslandPlacement(mode: .custom, edge: .bottom)),
        ])
        let changedID = ScreenSnapshot(displayID: 99, frame: external.frame,
                                       visibleFrame: external.visibleFrame, persistentID: external.persistentID)
        let engine = ScreenLayoutEngine(configuration: settings.islandScreenConfiguration)
        let restored = try #require(engine.layouts(for: [builtIn, changedID]).last)
        #expect(restored.displayID == 99 && restored.style == .pill && restored.edge == .bottom)
        let unconfigured = ScreenSnapshot(displayID: external.displayID, frame: external.frame,
                                          visibleFrame: external.visibleFrame, persistentID: "new-display")
        #expect(engine.layouts(for: [builtIn, unconfigured]).last?.style == .notch)
    }

    @Test @MainActor
    func hidingAnExpandedScreenDismissesItsPanelAndAllHiddenScreensStayClosed() throws {
        let content = NSView()
        let coordinator = OverlayCoordinator(contentView: content, persistentContentViewProvider: { _ in NSView() },
                                             persistentPanelFrameProvider: { $0.collapsedFrame })
        coordinator.screenSnapshotProvider = { [builtIn, external] }
        coordinator.pointerLocationProvider = { CGPoint(x: external.frame.midX, y: external.frame.midY) }
        coordinator.start()
        defer { coordinator.stop() }
        coordinator.showExpanded(at: CGPoint(x: external.frame.midX, y: external.frame.maxY))
        let panel = try #require(content.window)
        #expect(panel.isVisible && coordinator.activeDisplayID == external.displayID)
        var pinEvents: [Bool] = []
        coordinator.onPinnedChanged = { pinEvents.append($0) }
        coordinator.setPinned(true)
        coordinator.updatePlacement(layoutStyle: .notch, placement: IslandPlacement(),
                                    displaySettings: ["external": IslandDisplaySettings(mode: .hidden)])
        #expect(!panel.isVisible && !coordinator.isVisible)
        #expect(pinEvents == [false])
        #expect((panel as? IslandPanel)?.isPinned == false)
        #expect(coordinator.persistentPanelDisplayIDs == [builtIn.displayID])
        coordinator.showExpanded(at: CGPoint(x: external.frame.midX, y: external.frame.maxY))
        #expect(!panel.isVisible && !coordinator.isVisible)
        coordinator.showExpanded(at: CGPoint(x: builtIn.frame.midX, y: builtIn.frame.maxY))
        #expect(panel.isVisible && coordinator.activeDisplayID == builtIn.displayID)
        coordinator.setPinned(true)
        coordinator.handlePointer(at: CGPoint(x: builtIn.frame.minX, y: builtIn.frame.midY))
        #expect(coordinator.isVisible)
        coordinator.updatePlacement(layoutStyle: .notch, placement: IslandPlacement(), displaySettings: [
            "built-in": IslandDisplaySettings(mode: .hidden), "external": IslandDisplaySettings(mode: .hidden),
        ])
        coordinator.setPinned(true)
        #expect(coordinator.layouts.isEmpty && coordinator.persistentPanelDisplayIDs.isEmpty)
        #expect(!panel.isVisible && !coordinator.isVisible)
    }

    @Test @MainActor
    func unpluggingAndReconnectingRestoresOverridesWithoutMutatingSavedSettings() throws {
        let content = NSView()
        var screens = [builtIn, external]
        let overrides = ["external": IslandDisplaySettings(mode: .pill,
                                                           placement: IslandPlacement(mode: .custom, edge: .right, offset: 0.7))]
        let coordinator = OverlayCoordinator(contentView: content,
                                             layoutEngine: ScreenLayoutEngine(configuration: ScreenLayoutConfiguration(displaySettings: overrides)))
        coordinator.screenSnapshotProvider = { screens }
        coordinator.start()
        defer { coordinator.stop() }
        #expect(coordinator.layouts.last?.style == .pill)
        screens = [external]
        coordinator.refreshScreens()
        #expect(coordinator.layouts.first?.style == .notch)
        screens = [builtIn, external]
        coordinator.refreshScreens()
        #expect(coordinator.layouts.last?.style == .pill && coordinator.layouts.last?.edge == .right)
        let layout = try #require(coordinator.layouts.last)
        coordinator.updateCompactStatus(for: external.displayID, expandsForDetailedStatus: true, compactStatusLength: 160)
        #expect(coordinator.layouts.last?.style == .pill && coordinator.layouts.last?.placement == layout.placement)
    }
}
