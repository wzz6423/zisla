import AppKit
import CoreGraphics
import Testing
@testable import ZislaKit

struct OverlayCoordinatorTests {
    @Test @MainActor
    func persistentContentRemainsOnEveryNonInteractiveDisplay() async {
        let coordinator = OverlayCoordinator(
            contentView: NSView(),
            collapseDelay: .zero,
            persistentContentViewProvider: { _ in NSView() },
            persistentPanelFrameProvider: { $0.collapsedFrame }
        )
        let firstScreen = ScreenSnapshot(
            displayID: 1,
            frame: CGRect(x: 0, y: 0, width: 1_440, height: 900),
            visibleFrame: CGRect(x: 0, y: 0, width: 1_440, height: 875)
        )
        let secondScreen = ScreenSnapshot(
            displayID: 2,
            frame: CGRect(x: 1_440, y: 0, width: 1_920, height: 1_080),
            visibleFrame: CGRect(x: 1_440, y: 0, width: 1_920, height: 1_056)
        )

        coordinator.updateScreens([firstScreen], repositionVisiblePanel: false)
        #expect(coordinator.persistentPanelDisplayIDs == [1])

        coordinator.updateScreens([
            firstScreen,
            secondScreen,
        ], repositionVisiblePanel: false)

        #expect(coordinator.persistentPanelDisplayIDs == [1, 2])

        coordinator.setPersistentContentVisible(false)
        #expect(coordinator.persistentPanelDisplayIDs.isEmpty)

        coordinator.setPersistentContentVisible(true)
        #expect(coordinator.persistentPanelDisplayIDs == [1, 2])

        coordinator.selectActiveDisplay(at: CGPoint(x: 720, y: 450))
        coordinator.setPinned(true)

        #expect(coordinator.persistentPanelDisplayIDs == [2])

        coordinator.setPinned(false)
        try? await Task.sleep(for: .milliseconds(20))

        #expect(coordinator.persistentPanelDisplayIDs == [1, 2])
        coordinator.stop()
    }

    @Test @MainActor
    func persistentPetRemainsAboveAppsWhenIslandIsSetToBottom() throws {
        let probe = PersistentPetPanelProbe()
        let coordinator = OverlayCoordinator(
            contentView: NSView(),
            persistentContentViewProvider: { probe.contentView(for: $0) },
            persistentPanelFrameProvider: { probe.frame(for: $0) }
        )
        defer { coordinator.stop() }

        coordinator.updateScreens([Self.builtInScreen], repositionVisiblePanel: false)
        coordinator.setCollapsedOnTop(false)

        let petPanel = try #require(probe.panel(for: Self.builtInID))
        #expect(petPanel.level == IslandPanel.onTopLevel)

        coordinator.refreshPersistentPanels()
        #expect(petPanel.level == IslandPanel.onTopLevel)

        coordinator.setCollapsedOnTop(true)
        #expect(petPanel.level == IslandPanel.onTopLevel)
    }

    @Test @MainActor
    func collapsedIslandAtBottomKeepsExpandedCanvasForCenteredReveal() throws {
        let contentView = NSView()
        let coordinator = OverlayCoordinator(contentView: contentView, collapseDelay: .zero)
        defer { coordinator.stop() }

        coordinator.updateScreens([Self.builtInScreen], repositionVisiblePanel: false)
        coordinator.selectActiveDisplay(at: CGPoint(x: 720, y: 450))
        coordinator.setCollapsedOnTop(false)
        coordinator.setPinned(true)

        let panel = try #require(contentView.window as? IslandPanel)
        let engine = ScreenLayoutEngine()
        let layout = engine.layout(for: Self.builtInScreen)

        #expect(panel.frame == layout.expandedFrame)

        coordinator.setPinned(false)

        #expect(panel.frame == layout.expandedFrame)
        #expect(panel.ignoresMouseEvents == true)
        #expect(panel.level == IslandPanel.onBottomLevel)
    }

    @Test @MainActor
    func collapsedIslandSwitchesBetweenTopAndBottomWindowLevels() throws {
        let contentView = NSView()
        let coordinator = OverlayCoordinator(contentView: contentView, collapseDelay: .zero)
        defer { coordinator.stop() }

        coordinator.updateScreens([Self.builtInScreen], repositionVisiblePanel: false)
        coordinator.selectActiveDisplay(at: CGPoint(x: 720, y: 450))
        coordinator.setCollapsedOnTop(false)
        coordinator.setPinned(true)

        let panel = try #require(contentView.window as? IslandPanel)
        #expect(panel.level == IslandPanel.onTopLevel)

        coordinator.setPinned(false)
        #expect(panel.level == IslandPanel.onBottomLevel)
        #expect(panel.level.rawValue < NSWindow.Level.normal.rawValue)

        let engine = ScreenLayoutEngine()
        let layout = engine.layout(for: Self.builtInScreen)
        #expect(panel.frame == layout.expandedFrame)

        coordinator.setCollapsedOnTop(true)
        #expect(panel.level == IslandPanel.onTopLevel)
        #expect(panel.frame == layout.expandedFrame)

        coordinator.setCollapsedOnTop(false)
        #expect(panel.level == IslandPanel.onBottomLevel)
        #expect(panel.frame == layout.expandedFrame)
    }

    @Test @MainActor
    func immediateCollapseOverridesPinnedAndTransientInteractionWithoutWaiting() throws {
        let contentView = NSView()
        let coordinator = OverlayCoordinator(
            contentView: contentView,
            collapseDelay: .seconds(10)
        )
        defer { coordinator.stop() }

        coordinator.updateScreens([Self.builtInScreen], repositionVisiblePanel: false)
        coordinator.selectActiveDisplay(at: CGPoint(x: 720, y: 450))
        coordinator.setKeepsNativeGlassActive(true)
        coordinator.setPinned(true)
        coordinator.setTransientInteractionVisible(true)

        let panel = try #require(contentView.window as? IslandPanel)
        #expect(!panel.ignoresMouseEvents)
        #expect(panel.keepsNativeGlassActive)
        #expect(panel.isPinned)

        coordinator.collapseImmediately()

        #expect(panel.ignoresMouseEvents)
        #expect(!panel.keepsNativeGlassActive)
        #expect(!panel.canBecomeKey)
        #expect(!panel.isPinned)
    }

    @Test @MainActor
    func transientInteractionKeepsIslandExpandedUntilPopoverCloses() throws {
        let contentView = NSView()
        let coordinator = OverlayCoordinator(
            contentView: contentView,
            collapseDelay: .zero
        )
        defer { coordinator.stop() }

        coordinator.updateScreens([Self.builtInScreen], repositionVisiblePanel: false)
        coordinator.selectActiveDisplay(at: CGPoint(x: 720, y: 450))
        coordinator.setDragging(true)
        let panel = try #require(contentView.window as? IslandPanel)

        coordinator.setTransientInteractionVisible(true)
        coordinator.setDragging(false)
        #expect(!panel.ignoresMouseEvents)

        coordinator.setTransientInteractionVisible(false)
        #expect(panel.ignoresMouseEvents)
    }

    @Test @MainActor
    func selectingDisplayReportsWhetherItHasAPhysicalNotch() {
        let coordinator = OverlayCoordinator(contentView: NSView())
        coordinator.updateScreens([
            ScreenSnapshot(
                displayID: 1,
                frame: CGRect(x: 0, y: 0, width: 1_512, height: 982),
                visibleFrame: CGRect(x: 0, y: 0, width: 1_512, height: 950),
                safeAreaInsets: ScreenInsets(top: 32),
                auxiliaryTopLeftArea: CGRect(x: 0, y: 950, width: 716, height: 32),
                auxiliaryTopRightArea: CGRect(x: 796, y: 950, width: 716, height: 32)
            ),
            ScreenSnapshot(
                displayID: 2,
                frame: CGRect(x: 1_512, y: 0, width: 1_440, height: 900),
                visibleFrame: CGRect(x: 1_512, y: 0, width: 1_440, height: 875)
            ),
        ], repositionVisiblePanel: false)
        var reportedValues: [Bool] = []
        coordinator.onActiveDisplayHasPhysicalNotchChanged = { reportedValues.append($0) }

        coordinator.selectActiveDisplay(at: CGPoint(x: 756, y: 960))
        coordinator.selectActiveDisplay(at: CGPoint(x: 2_232, y: 450))

        #expect(reportedValues == [true, false])
    }

    @Test @MainActor
    func selectingScreenUnderMenuBarClickReplacesPreviousActiveDisplay() {
        let coordinator = OverlayCoordinator(contentView: NSView())
        coordinator.updateScreens([
            ScreenSnapshot(
                displayID: 1,
                frame: CGRect(x: 0, y: 0, width: 1_440, height: 900),
                visibleFrame: CGRect(x: 0, y: 0, width: 1_440, height: 875)
            ),
            ScreenSnapshot(
                displayID: 2,
                frame: CGRect(x: 1_440, y: 0, width: 1_920, height: 1_080),
                visibleFrame: CGRect(x: 1_440, y: 0, width: 1_920, height: 1_056)
            ),
        ], repositionVisiblePanel: false)

        coordinator.selectActiveDisplay(at: CGPoint(x: 720, y: 450))
        coordinator.selectActiveDisplay(at: CGPoint(x: 2_400, y: 540))

        #expect(coordinator.activeDisplayID == 2)
    }

    @Test @MainActor
    func petPanelStaysVisibleWhenItsDisplayEntersAnotherAppsFullScreenSpace() throws {
        let probe = PersistentPetPanelProbe()
        let coordinator = OverlayCoordinator(
            contentView: NSView(),
            collapseDelay: .zero,
            persistentContentViewProvider: { probe.contentView(for: $0) },
            persistentPanelFrameProvider: { probe.frame(for: $0) }
        )
        defer { coordinator.stop() }
        let engine = ScreenLayoutEngine()

        coordinator.updateScreens(
            [Self.builtInScreen, Self.externalWindowedScreen],
            repositionVisiblePanel: false
        )

        #expect(coordinator.persistentPanelDisplayIDs == [Self.builtInID, Self.externalID])
        let externalPanel = try #require(probe.panel(for: Self.externalID))
        #expect(externalPanel.isVisible)
        #expect(externalPanel.frame == engine.layout(for: Self.externalWindowedScreen).collapsedFrame)
        // A full-screen Space is owned by the other app, so the pet panel only reaches it when it
        // may join every Space and every application's full-screen window.
        #expect(externalPanel.collectionBehavior.contains(.canJoinAllSpaces))
        #expect(externalPanel.collectionBehavior.contains(.fullScreenAuxiliary))
        #expect(externalPanel.collectionBehavior.contains(.canJoinAllApplications))
        #expect(externalPanel.collectionBehavior.contains(.stationary))
        #expect(!externalPanel.collectionBehavior.contains(.transient))

        coordinator.updateScreens(
            [Self.builtInScreen, Self.externalFullScreenScreen],
            repositionVisiblePanel: false
        )

        #expect(coordinator.persistentPanelDisplayIDs == [Self.builtInID, Self.externalID])
        #expect(externalPanel.isVisible)
        #expect(
            externalPanel.frame == engine.layout(for: Self.externalFullScreenScreen).collapsedFrame
        )

        // Expanding the island on the built-in display must not drop the pet on the display that
        // is showing another app's full-screen Space.
        coordinator.selectActiveDisplay(at: CGPoint(x: 720, y: 450))
        coordinator.setPinned(true)

        #expect(coordinator.persistentPanelDisplayIDs == [Self.externalID])
        #expect(try #require(probe.panel(for: Self.externalID)).isVisible)
    }

    @Test @MainActor
    func switchingIntoAnotherAppsFullScreenSpaceReordersPetPanels() throws {
        let probe = PersistentPetPanelProbe()
        let coordinator = OverlayCoordinator(
            contentView: NSView(),
            collapseDelay: .zero,
            persistentContentViewProvider: { probe.contentView(for: $0) },
            persistentPanelFrameProvider: { probe.frame(for: $0) }
        )
        defer { coordinator.stop() }

        coordinator.start()
        coordinator.updateScreens(
            [Self.builtInScreen, Self.externalWindowedScreen],
            repositionVisiblePanel: false
        )
        let baseline = probe.frameRequestCount

        // Entering another app's full-screen Space emits no screen-parameter change, so the pet
        // panels are only re-ordered into the new Space if the active-Space notification is heard.
        NSWorkspace.shared.notificationCenter.post(
            name: NSWorkspace.activeSpaceDidChangeNotification,
            object: NSWorkspace.shared
        )

        #expect(probe.frameRequestCount > baseline)
    }

    @Test @MainActor
    func persistentPetPanelsAppearOnAllScreensWhenEnabled() throws {
        let probe = PersistentPetPanelProbe()
        let coordinator = OverlayCoordinator(
            contentView: NSView(),
            collapseDelay: .zero,
            persistentContentViewProvider: { probe.contentView(for: $0) },
            persistentPanelFrameProvider: { probe.frame(for: $0) }
        )
        defer { coordinator.stop() }

        // Initially disable persistent content
        coordinator.setPersistentContentVisible(false)
        coordinator.updateScreens(
            [Self.builtInScreen, Self.externalWindowedScreen],
            repositionVisiblePanel: false
        )

        #expect(coordinator.persistentPanelDisplayIDs.isEmpty)

        // Enable persistent content - should show on all screens
        coordinator.setPersistentContentVisible(true)

        #expect(coordinator.persistentPanelDisplayIDs == [Self.builtInID, Self.externalID])

        coordinator.setCollapsedOnTop(false)

        let builtInPanel = try #require(probe.panel(for: Self.builtInID))
        let externalPanel = try #require(probe.panel(for: Self.externalID))
        #expect(builtInPanel.isVisible)
        #expect(externalPanel.isVisible)
        #expect(builtInPanel.level == IslandPanel.onTopLevel)
        #expect(externalPanel.level == IslandPanel.onTopLevel)
    }

    private static let builtInID: CGDirectDisplayID = 9_001
    private static let externalID: CGDirectDisplayID = 9_002

    private static let builtInScreen = ScreenSnapshot(
        displayID: builtInID,
        frame: CGRect(x: 0, y: 0, width: 1_440, height: 900),
        visibleFrame: CGRect(x: 0, y: 0, width: 1_440, height: 876)
    )

    /// Placed far outside any physical display so the panels created here cannot be mistaken for
    /// panels belonging to tests running in parallel.
    private static let externalWindowedScreen = ScreenSnapshot(
        displayID: externalID,
        frame: CGRect(x: 20_000, y: 0, width: 1_920, height: 1_080),
        visibleFrame: CGRect(x: 20_000, y: 0, width: 1_920, height: 1_056)
    )

    /// Another app going full screen on that display hands the menu bar strip back to the app, so
    /// the snapshot reports a visibleFrame that covers the whole screen.
    private static let externalFullScreenScreen = ScreenSnapshot(
        displayID: externalID,
        frame: externalWindowedScreen.frame,
        visibleFrame: externalWindowedScreen.frame
    )
}

@MainActor
private final class PersistentPetPanelProbe {
    private var contentViews: [CGDirectDisplayID: NSView] = [:]
    private(set) var frameRequestCount = 0

    func contentView(for layout: ScreenOverlayLayout) -> NSView? {
        if let existing = contentViews[layout.displayID] { return existing }
        let view = NSView(frame: CGRect(origin: .zero, size: layout.collapsedFrame.size))
        contentViews[layout.displayID] = view
        return view
    }

    func frame(for layout: ScreenOverlayLayout) -> CGRect {
        frameRequestCount += 1
        return layout.collapsedFrame
    }

    /// The coordinator keeps its persistent panels private; the injected content view is the only
    /// handle the test has on the panel that actually hosts the pet.
    func panel(for displayID: CGDirectDisplayID) -> IslandPanel? {
        contentViews[displayID]?.window as? IslandPanel
    }
}

extension OverlayCoordinatorTests {
    @Test @MainActor
    func pinningBeforePendingGlassActivationKeepsGlassWithoutEnablingKeyboardInput() async throws {
        let contentView = NSView()
        let coordinator = OverlayCoordinator(contentView: contentView, collapseDelay: .zero)
        defer { coordinator.stop() }

        coordinator.updateScreens([Self.builtInScreen], repositionVisiblePanel: false)
        coordinator.selectActiveDisplay(at: CGPoint(x: 720, y: 450))
        coordinator.setKeepsNativeGlassActive(true)
        coordinator.setDragging(true)

        let panel = try #require(contentView.window as? IslandPanel)
        coordinator.setPinned(true)

        try await Task.sleep(for: .milliseconds(10))

        #expect(panel.keepsNativeGlassActive)
        #expect(panel.allowsNativeGlassActivation)
        #expect(!panel.allowsKeyWindow)
        #expect(panel.canBecomeKey)
        #expect(panel.isPinned)
    }

    @Test @MainActor
    func pinnedPanelKeepsKeyboardEligibilityWhenItsSizeChanges() throws {
        let contentView = NSView()
        let coordinator = OverlayCoordinator(contentView: contentView, collapseDelay: .zero)
        defer { coordinator.stop() }

        coordinator.updateScreens([Self.builtInScreen], repositionVisiblePanel: false)
        coordinator.selectActiveDisplay(at: CGPoint(x: 720, y: 450))
        coordinator.setKeepsNativeGlassActive(true)
        coordinator.setDragging(true)
        coordinator.setPinned(true)
        coordinator.setAllowsKeyWindow(true)

        let panel = try #require(contentView.window as? IslandPanel)
        coordinator.updateExpandedSize(CGSize(width: 900, height: 360))

        #expect(panel.keepsNativeGlassActive)
        #expect(panel.allowsNativeGlassActivation)
        #expect(panel.allowsKeyWindow)
        #expect(panel.canBecomeKey)
        #expect(panel.isPinned)
    }

    @Test @MainActor
    func pinningExpandedGlassPanelStopsReclaimingFocus() async throws {
        let contentView = NSView()
        let coordinator = OverlayCoordinator(contentView: contentView, collapseDelay: .zero)
        defer { coordinator.stop() }

        coordinator.updateScreens([Self.builtInScreen], repositionVisiblePanel: false)
        coordinator.selectActiveDisplay(at: CGPoint(x: 720, y: 450))
        coordinator.setKeepsNativeGlassActive(true)
        coordinator.setDragging(true)

        let panel = try #require(contentView.window as? IslandPanel)
        try await Task.sleep(for: .milliseconds(10))
        #expect(panel.keepsNativeGlassActive)
        #expect(panel.canBecomeKey)
        #expect(!panel.isPinned)

        coordinator.setPinned(true)
        #expect(panel.keepsNativeGlassActive)
        #expect(!panel.allowsKeyWindow)
        #expect(panel.canBecomeKey)
        #expect(panel.isPinned)

        panel.resignKey()
        try await Task.sleep(for: .milliseconds(50))

        #expect(!panel.isKeyWindow)
    }

    @Test @MainActor
    func reexpandingVisiblePanelRestoresGlassBeforeItsFirstFrame() async throws {
        let contentView = NSView()
        let coordinator = OverlayCoordinator(contentView: contentView, collapseDelay: .zero)
        defer { coordinator.stop() }

        coordinator.updateScreens([Self.builtInScreen], repositionVisiblePanel: false)
        coordinator.selectActiveDisplay(at: CGPoint(x: 720, y: 450))
        coordinator.setKeepsNativeGlassActive(true)
        coordinator.setDragging(true)

        let panel = try #require(contentView.window as? IslandPanel)
        try await Task.sleep(for: .milliseconds(10))
        #expect(panel.keepsNativeGlassActive)

        coordinator.setDragging(false)
        #expect(!panel.keepsNativeGlassActive)

        coordinator.setDragging(true)
        #expect(panel.keepsNativeGlassActive)
    }

    @Test @MainActor
    func firstShowDelaysGlassActivationUntilAfterVisibilityChanged() async throws {
        let contentView = NSView()
        var visibilityEvents: [Bool] = []
        let coordinator = OverlayCoordinator(contentView: contentView, collapseDelay: .zero)
        coordinator.onVisibilityChanged = { visibilityEvents.append($0) }
        defer { coordinator.stop() }

        coordinator.updateScreens([Self.builtInScreen], repositionVisiblePanel: false)
        coordinator.selectActiveDisplay(at: CGPoint(x: 720, y: 450))
        coordinator.setKeepsNativeGlassActive(true)
        coordinator.setDragging(true)

        let panel = try #require(contentView.window as? IslandPanel)
        #expect(visibilityEvents == [true])
        #expect(panel.keepsNativeGlassActive == true)
        panel.orderOut(nil)

        try await Task.sleep(for: .milliseconds(10))
        #expect(panel.keepsNativeGlassActive == true)
    }

    @Test @MainActor
    func collapseCancelsPendingGlassActivation() async throws {
        let contentView = NSView()
        let coordinator = OverlayCoordinator(contentView: contentView, collapseDelay: .zero)
        defer { coordinator.stop() }

        coordinator.updateScreens([Self.builtInScreen], repositionVisiblePanel: false)
        coordinator.selectActiveDisplay(at: CGPoint(x: 720, y: 450))
        coordinator.setKeepsNativeGlassActive(true)
        coordinator.setDragging(true)

        let panel = try #require(contentView.window as? IslandPanel)
        coordinator.setDragging(false)

        try await Task.sleep(for: .milliseconds(10))
        #expect(panel.keepsNativeGlassActive == false)
    }

    @Test @MainActor
    func stoppingClearsGlassActivationBeforeNextShow() async throws {
        let contentView = NSView()
        let coordinator = OverlayCoordinator(contentView: contentView, collapseDelay: .zero)
        defer { coordinator.stop() }

        coordinator.updateScreens([Self.builtInScreen], repositionVisiblePanel: false)
        coordinator.selectActiveDisplay(at: CGPoint(x: 720, y: 450))
        coordinator.setKeepsNativeGlassActive(true)
        coordinator.setDragging(true)

        let panel = try #require(contentView.window as? IslandPanel)
        panel.orderOut(nil)
        try await Task.sleep(for: .milliseconds(10))
        #expect(panel.keepsNativeGlassActive == true)

        coordinator.stop()
        #expect(panel.keepsNativeGlassActive == false)

        coordinator.updateScreens([Self.builtInScreen], repositionVisiblePanel: false)
        coordinator.selectActiveDisplay(at: CGPoint(x: 720, y: 450))
        coordinator.setDragging(true)

        #expect(panel.keepsNativeGlassActive == true)
        panel.orderOut(nil)
        try await Task.sleep(for: .milliseconds(10))
        #expect(panel.keepsNativeGlassActive == true)
    }
}
