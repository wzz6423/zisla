import AppKit
import CoreGraphics
import Testing
import ZislaCore
@testable import ZislaKit

@MainActor
struct OverlayCoordinatorMultiDisplayTests {
    @MainActor
    private final class MutableState {
        var screens: [ScreenSnapshot]
        var pointer: CGPoint

        init(screens: [ScreenSnapshot], pointer: CGPoint = .zero) {
            self.screens = screens
            self.pointer = pointer
        }
    }

    @Test
    func newlyConnectedDisplayExpandsImmediatelyEvenWhenScreenNotificationWasMissed() throws {
        let state = MutableState(
            screens: [Self.builtInScreen],
            pointer: CGPoint(x: Self.builtInScreen.frame.midX, y: Self.builtInScreen.frame.midY)
        )
        let content = NSView()
        let coordinator = OverlayCoordinator(contentView: content, collapseDelay: .zero)
        coordinator.screenSnapshotProvider = { state.screens }
        coordinator.pointerLocationProvider = { state.pointer }
        coordinator.start()
        defer { coordinator.stop() }
        coordinator.prewarmPanel()

        state.screens = [Self.builtInScreen, Self.externalScreen]
        let externalLayout = ScreenLayoutEngine().layout(for: Self.externalScreen)
        let externalTrigger = CGPoint(x: externalLayout.triggerFrame.midX, y: externalLayout.triggerFrame.midY)

        coordinator.handlePointer(at: externalTrigger)

        let panel = try #require(content.window as? IslandPanel)
        #expect(coordinator.activeDisplayID == Self.externalScreen.displayID)
        #expect(panel.isVisible)
        #expect(!panel.ignoresMouseEvents)
        #expect(panel.frame == externalLayout.expandedFrame)
    }

    @Test
    func externalRevealReconcilesNewlyConnectedDisplayBeforeSelectingActiveScreen() throws {
        let state = MutableState(screens: [Self.builtInScreen])
        let content = NSView()
        let coordinator = OverlayCoordinator(contentView: content, collapseDelay: .zero)
        coordinator.screenSnapshotProvider = { state.screens }
        coordinator.start()
        defer { coordinator.stop() }

        state.screens = [Self.builtInScreen, Self.externalScreen]
        let externalLayout = ScreenLayoutEngine().layout(for: Self.externalScreen)
        coordinator.showExpanded(at: CGPoint(x: Self.externalScreen.frame.midX, y: Self.externalScreen.frame.maxY))

        let panel = try #require(content.window as? IslandPanel)
        #expect(coordinator.activeDisplayID == Self.externalScreen.displayID)
        #expect(panel.frame == externalLayout.expandedFrame)
        #expect(!panel.ignoresMouseEvents)
    }

    @Test
    func silentScreenResizeOrOffsetReconcilesOnRecoveryTimerSpaceChangeAndWake() throws {
        let initialExternal = ScreenSnapshot(
            displayID: Self.externalScreen.displayID,
            frame: CGRect(x: 20_000, y: 0, width: 2_560, height: 1_440),
            visibleFrame: CGRect(x: 20_000, y: 0, width: 2_560, height: 1_415)
        )
        let resizedExternal = ScreenSnapshot(
            displayID: Self.externalScreen.displayID,
            frame: CGRect(x: 20_000, y: 0, width: 1_920, height: 1_080),
            visibleFrame: CGRect(x: 20_000, y: 0, width: 1_920, height: 1_055)
        )
        let resizedLayout = ScreenLayoutEngine().layout(for: resizedExternal)
        let resizedTrigger = CGPoint(x: resizedLayout.triggerFrame.midX, y: resizedLayout.triggerFrame.midY)

        for triggerKind in ["timer", "space", "screensDidWake", "didWake"] {
            let state = MutableState(screens: [Self.builtInScreen, initialExternal], pointer: resizedTrigger)
            let content = NSView()
            let coordinator = OverlayCoordinator(contentView: content, collapseDelay: .zero)
            coordinator.screenSnapshotProvider = { state.screens }
            coordinator.pointerLocationProvider = { state.pointer }
            coordinator.pressedMouseButtonsProvider = { 0 }
            coordinator.start()
            defer { coordinator.stop() }

            state.screens = [Self.builtInScreen, resizedExternal]
            switch triggerKind {
            case "timer":
                coordinator.pointerRecoveryTimer?.fire()
            case "space":
                NSWorkspace.shared.notificationCenter.post(
                    name: NSWorkspace.activeSpaceDidChangeNotification,
                    object: NSWorkspace.shared
                )
                coordinator.handlePointer(at: resizedTrigger)
            case "screensDidWake":
                NSWorkspace.shared.notificationCenter.post(
                    name: NSWorkspace.screensDidWakeNotification,
                    object: NSWorkspace.shared
                )
                coordinator.handlePointer(at: resizedTrigger)
            default:
                NSWorkspace.shared.notificationCenter.post(
                    name: NSWorkspace.didWakeNotification,
                    object: NSWorkspace.shared
                )
                coordinator.handlePointer(at: resizedTrigger)
            }

            let panel = try #require(content.window as? IslandPanel)
            #expect(coordinator.activeDisplayID == resizedExternal.displayID,
                    "Failed to reconcile resized external screen via \(triggerKind)")
            #expect(panel.isVisible)
            #expect(!panel.ignoresMouseEvents)
            #expect(panel.frame == resizedLayout.expandedFrame)

            // Stopping unregisters wake and Space observers so later notifications do not reactivate layouts.
            coordinator.stop()
            state.screens = [Self.builtInScreen]
            NSWorkspace.shared.notificationCenter.post(
                name: NSWorkspace.screensDidWakeNotification,
                object: NSWorkspace.shared
            )
            NSWorkspace.shared.notificationCenter.post(
                name: NSWorkspace.didWakeNotification,
                object: NSWorkspace.shared
            )
            #expect(!coordinator.isRunning)
            #expect(coordinator.activeDisplayID == nil)
        }
    }

    @Test
    func hoveringAnotherDisplayAfterExplicitCollapseStillExpandsWithoutIntermediateExit() throws {
        let content = NSView()
        let coordinator = OverlayCoordinator(contentView: content, collapseDelay: .zero)
        coordinator.screenSnapshotProvider = { [Self.builtInScreen, Self.externalScreen] }
        var visibilityEvents: [Bool] = []
        coordinator.onVisibilityChanged = { visibilityEvents.append($0) }
        coordinator.start()
        defer { coordinator.stop() }

        let builtInLayout = ScreenLayoutEngine().layout(for: Self.builtInScreen)
        let externalLayout = ScreenLayoutEngine().layout(for: Self.externalScreen)
        let builtInTrigger = CGPoint(x: builtInLayout.triggerFrame.midX, y: builtInLayout.triggerFrame.midY)
        let externalTrigger = CGPoint(x: externalLayout.triggerFrame.midX, y: externalLayout.triggerFrame.midY)

        coordinator.handlePointer(at: builtInTrigger)
        coordinator.collapseImmediately()
        let panel = try #require(content.window as? IslandPanel)
        #expect(panel.ignoresMouseEvents)

        // Stationary pointer on the same display remains collapsed.
        coordinator.handlePointer(at: builtInTrigger)
        #expect(panel.ignoresMouseEvents)

        // Reaching another display's trigger must expand even when no outside sample intervened.
        coordinator.handlePointer(at: externalTrigger)
        #expect(coordinator.activeDisplayID == Self.externalScreen.displayID)
        #expect(!panel.ignoresMouseEvents)
        #expect(panel.frame == externalLayout.expandedFrame)
        #expect(visibilityEvents == [true, false, true])
    }

    @Test
    func topEdgePointerCoordinatesSelectAndKeepExternalDisplayExpanded() throws {
        let screens = [Self.builtInScreen, Self.externalScreen]
        let engine = ScreenLayoutEngine()
        let layouts = engine.layouts(for: screens)
        let externalLayout = try #require(layouts.first { $0.displayID == Self.externalScreen.displayID })

        let topEdgeOutsideTrigger = CGPoint(
            x: externalLayout.expandedFrame.minX + 10,
            y: Self.externalScreen.frame.maxY
        )
        #expect(!externalLayout.containsTrigger(topEdgeOutsideTrigger))
        #expect(
            engine.screenLayout(containing: topEdgeOutsideTrigger, in: layouts)?.displayID
                == Self.externalScreen.displayID
        )

        let content = NSView()
        let coordinator = OverlayCoordinator(contentView: content, collapseDelay: .zero)
        coordinator.screenSnapshotProvider = { screens }
        coordinator.start()
        defer { coordinator.stop() }

        coordinator.selectActiveDisplay(at: CGPoint(x: Self.builtInScreen.frame.midX, y: Self.builtInScreen.frame.midY))
        coordinator.showExpanded(at: CGPoint(x: Self.externalScreen.frame.minX + 40, y: Self.externalScreen.frame.maxY))
        let panel = try #require(content.window as? IslandPanel)
        #expect(coordinator.activeDisplayID == Self.externalScreen.displayID)
        #expect(panel.frame == externalLayout.expandedFrame)
        #expect(!panel.ignoresMouseEvents)

        // Entering the expanded surface via normal hover and sliding along the exact top edge (Quartz y == 0) must keep it open.
        coordinator.collapseImmediately()
        coordinator.handlePointer(at: CGPoint(x: Self.externalScreen.frame.midX, y: Self.externalScreen.frame.midY))
        coordinator.handlePointer(at: CGPoint(x: externalLayout.triggerFrame.midX, y: externalLayout.triggerFrame.midY))
        #expect(!panel.ignoresMouseEvents)
        coordinator.handlePointer(at: topEdgeOutsideTrigger)
        #expect(!panel.ignoresMouseEvents)
        #expect(coordinator.activeDisplayID == Self.externalScreen.displayID)
    }

    @Test
    func stackedDisplaysKeepSharedBorderDeterministicWhileAcceptingOuterTopEdge() {
        let lower = ScreenSnapshot(
            displayID: 501,
            frame: CGRect(x: 0, y: 0, width: 1_512, height: 982),
            visibleFrame: CGRect(x: 0, y: 0, width: 1_512, height: 945)
        )
        let upper = ScreenSnapshot(
            displayID: 502,
            frame: CGRect(x: 0, y: 982, width: 2_560, height: 1_440),
            visibleFrame: CGRect(x: 0, y: 982, width: 2_560, height: 1_415)
        )
        let engine = ScreenLayoutEngine()
        let layouts = engine.layouts(for: [lower, upper])

        #expect(engine.screenLayout(containing: CGPoint(x: 756, y: 982), in: layouts)?.displayID == upper.displayID)
        #expect(engine.screenLayout(containing: CGPoint(x: 756, y: 2_422), in: layouts)?.displayID == upper.displayID)
        #expect(engine.screenLayout(containing: CGPoint(x: 2_560, y: 1_200), in: layouts)?.displayID == upper.displayID)
    }

    @Test
    func physicalNotchTriggerHeightSurvivesTransientAuxiliaryAreaDropout() throws {
        let state = MutableState(screens: [Self.builtInScreen, Self.externalScreen])
        let content = NSView()
        let coordinator = OverlayCoordinator(contentView: content, collapseDelay: .zero)
        coordinator.screenSnapshotProvider = { state.screens }
        coordinator.start()
        defer { coordinator.stop() }

        var notchGap = Self.builtInScreen
        notchGap.visibleFrame = notchGap.frame
        notchGap.safeAreaInsets = ScreenInsets()
        notchGap.auxiliaryTopLeftArea = nil
        notchGap.auxiliaryTopRightArea = nil
        notchGap.menuBarHeightFallback = 24
        state.screens = [notchGap, Self.externalScreen]
        coordinator.refreshScreens()

        // Point inside the bottom 13pt of the 37pt physical notch, below the 24pt simulated fallback.
        let lowerNotchPoint = CGPoint(x: Self.builtInScreen.frame.midX, y: Self.builtInScreen.frame.maxY - 32)
        coordinator.handlePointer(at: lowerNotchPoint)

        let panel = try #require(content.window as? IslandPanel)
        #expect(coordinator.activeDisplayID == Self.builtInScreen.displayID)
        #expect(!panel.ignoresMouseEvents)
        #expect(coordinator.activeLayout?.topology.hasPhysicalNotch == true)

        // Changing display resolution invalidates the cached physical notch geometry.
        var resized = notchGap
        resized.frame.size.width += 100
        resized.visibleFrame = resized.frame
        state.screens = [resized, Self.externalScreen]
        coordinator.refreshScreens()
        #expect(coordinator.activeLayout?.topology.hasPhysicalNotch == false)
    }

    @Test
    func transientEmptyScreenSnapshotResetsVisibilityAndRecoversOnReconnect() throws {
        let state = MutableState(screens: [Self.builtInScreen, Self.externalScreen])
        let content = NSView()
        let coordinator = OverlayCoordinator(contentView: content, collapseDelay: .zero)
        coordinator.screenSnapshotProvider = { state.screens }
        var visibilityEvents: [Bool] = []
        coordinator.onVisibilityChanged = { visibilityEvents.append($0) }
        coordinator.start()
        defer { coordinator.stop() }

        let builtInLayout = ScreenLayoutEngine().layout(for: Self.builtInScreen)
        coordinator.handlePointer(at: CGPoint(x: builtInLayout.triggerFrame.midX, y: builtInLayout.triggerFrame.midY))
        #expect(visibilityEvents == [true])

        state.screens = []
        coordinator.refreshScreens()
        #expect(visibilityEvents == [true, false])
        #expect(!coordinator.isVisible)

        state.screens = [Self.builtInScreen, Self.externalScreen]
        let externalLayout = ScreenLayoutEngine().layout(for: Self.externalScreen)
        coordinator.handlePointer(at: CGPoint(x: externalLayout.triggerFrame.midX, y: externalLayout.triggerFrame.midY))
        let panel = try #require(content.window as? IslandPanel)
        #expect(coordinator.activeDisplayID == Self.externalScreen.displayID)
        #expect(!panel.ignoresMouseEvents)
        #expect(visibilityEvents == [true, false, true])
    }

    @Test
    func crossDisplayExpansionFromBottomLevelPresentsOnceAtOnTopLevel() throws {
        let content = NSView()
        let coordinator = OverlayCoordinator(contentView: content, collapseDelay: .zero)
        coordinator.screenSnapshotProvider = { [Self.builtInScreen, Self.externalScreen] }
        coordinator.setCollapsedOnTop(false)
        coordinator.start()
        defer { coordinator.stop() }

        let builtInLayout = ScreenLayoutEngine().layout(for: Self.builtInScreen)
        let externalLayout = ScreenLayoutEngine().layout(for: Self.externalScreen)
        coordinator.handlePointer(at: CGPoint(x: builtInLayout.triggerFrame.midX, y: builtInLayout.triggerFrame.midY))
        coordinator.handlePointer(at: CGPoint(x: Self.builtInScreen.frame.midX, y: Self.builtInScreen.frame.midY))

        let panel = try #require(content.window as? IslandPanel)
        #expect(panel.isVisible)
        #expect(panel.level == IslandPanel.onBottomLevel)

        var collapsedSizeNotifications = 0
        coordinator.onCollapsedSizeChanged = { _ in collapsedSizeNotifications += 1 }

        coordinator.handlePointer(at: CGPoint(x: externalLayout.triggerFrame.midX, y: externalLayout.triggerFrame.midY))

        #expect(coordinator.activeDisplayID == Self.externalScreen.displayID)
        #expect(panel.isVisible)
        #expect(!panel.ignoresMouseEvents)
        #expect(panel.level == IslandPanel.onTopLevel)
        #expect(panel.frame == externalLayout.expandedFrame)
        #expect(collapsedSizeNotifications == 1,
                "Switching displays from collapsed to expanded must present once in the expanded state")
    }

    @Test
    func crossDisplayPresentationDetachesOldSpaceOrdersFrontAtTopLevelAndConvergesDriftedFrames() throws {
        let content = NSView()
        let coordinator = OverlayCoordinator(contentView: content, collapseDelay: .zero)
        coordinator.screenSnapshotProvider = { [Self.builtInScreen, Self.externalScreen] }
        coordinator.setCollapsedOnTop(false)
        coordinator.start()
        defer { coordinator.stop() }

        let builtInLayout = ScreenLayoutEngine().layout(for: Self.builtInScreen)
        let externalLayout = ScreenLayoutEngine().layout(for: Self.externalScreen)
        let builtInTrigger = CGPoint(x: builtInLayout.triggerFrame.midX, y: builtInLayout.triggerFrame.midY)
        let builtInOutside = CGPoint(x: Self.builtInScreen.frame.midX, y: Self.builtInScreen.frame.midY)
        let externalTrigger = CGPoint(x: externalLayout.triggerFrame.midX, y: externalLayout.triggerFrame.midY)
        let externalOutside = CGPoint(x: Self.externalScreen.frame.midX, y: Self.externalScreen.frame.midY)

        coordinator.handlePointer(at: builtInTrigger)
        coordinator.handlePointer(at: builtInOutside)
        let panel = try #require(content.window as? IslandPanel)
        #expect(panel.isVisible)
        #expect(panel.level == IslandPanel.onBottomLevel)

        var events: [String] = []
        var simulateMixedDPIDrift = true
        panel.panelOrderOutHandler = { panel in
            events.append("orderOut:visible=\(panel.isVisible)")
            panel.orderOut(nil)
        }
        panel.panelFrameApplier = { panel, target in
            if simulateMixedDPIDrift {
                simulateMixedDPIDrift = false
                events.append("setFrame:drifted")
                panel.setFrame(target.offsetBy(dx: 0, dy: -80), display: true)
            } else {
                events.append("setFrame:exact")
                panel.setFrame(target, display: true)
            }
        }
        panel.panelOrderFrontHandler = { panel in
            events.append("orderFront:level=\(panel.level == IslandPanel.onTopLevel):ignores=\(panel.ignoresMouseEvents)")
            panel.orderFrontRegardless()
        }

        // Moving to the external display must detach first, converge the drifted frame, and order front at onTopLevel.
        coordinator.handlePointer(at: externalTrigger)
        #expect(events == [
            "orderOut:visible=true",
            "setFrame:drifted",
            "setFrame:exact",
            "orderFront:level=true:ignores=false",
        ])
        #expect(panel.frame == externalLayout.expandedFrame)
        #expect(panel.isVisible)

        // Re-expanding on the same display must not detach via orderOut.
        events.removeAll()
        coordinator.handlePointer(at: externalOutside)
        coordinator.handlePointer(at: externalTrigger)
        #expect(events == ["orderFront:level=true:ignores=false"])
    }

    @Test
    func perDisplayCompactStatusExpandsNonActiveDisplayWithoutDisturbingActiveDisplayAnchor() throws {
        let content = NSView()
        let configuration = ScreenLayoutConfiguration(
            layoutStyle: .pill,
            placement: IslandPlacement(mode: .custom, edge: .top, inwardDistance: 20)
        )
        let coordinator = OverlayCoordinator(
            contentView: content,
            layoutEngine: ScreenLayoutEngine(configuration: configuration),
            collapseDelay: .zero
        )
        coordinator.screenSnapshotProvider = { [Self.builtInScreen, Self.externalScreen] }
        coordinator.start()
        defer { coordinator.stop() }

        coordinator.selectActiveDisplay(at: CGPoint(x: Self.builtInScreen.frame.midX, y: Self.builtInScreen.frame.midY))
        coordinator.prewarmPanel()
        let activeBefore = try #require(coordinator.activeLayout)
        var activeNotifications = 0
        coordinator.onActiveLayoutChanged = { _ in activeNotifications += 1 }

        // Only the non-active external display widens its compact pill.
        coordinator.updateCompactStatus(
            for: Self.externalScreen.displayID,
            expandsForDetailedStatus: false,
            compactStatusLength: 220
        )

        #expect(coordinator.activeLayout == activeBefore,
                "Updating another display's compact status must not disturb the active display's anchor")
        #expect(activeNotifications == 0)

        let externalLayout = try #require(
            coordinator.layouts.first { $0.displayID == Self.externalScreen.displayID }
        )
        #expect(externalLayout.collapsedFrame.width == 220)

        // Updating the active display while prewarmed keeps its collapsed metrics in sync.
        var collapsedSizes: [CGSize] = []
        coordinator.onCollapsedSizeChanged = { collapsedSizes.append($0) }
        coordinator.updateCompactStatus(
            for: Self.builtInScreen.displayID,
            expandsForDetailedStatus: false,
            compactStatusLength: 140
        )
        #expect(collapsedSizes.last?.width == 140)

        // Hovering near the outer edge of the external display's widened pill (outside a 24pt idle circle) must expand.
        let outerEdgePoint = CGPoint(x: externalLayout.collapsedFrame.minX + 4, y: externalLayout.collapsedFrame.midY)
        coordinator.handlePointer(at: outerEdgePoint)

        let panel = try #require(content.window as? IslandPanel)
        #expect(coordinator.activeDisplayID == Self.externalScreen.displayID)
        #expect(!panel.ignoresMouseEvents)
        #expect(panel.frame == externalLayout.expandedFrame)

        // Disconnecting the external display clears its stale compact status override.
        coordinator.updateScreens([Self.builtInScreen])
        coordinator.updateScreens([Self.builtInScreen, Self.externalScreen])
        let reconnectedExternal = try #require(
            coordinator.layouts.first { $0.displayID == Self.externalScreen.displayID }
        )
        #expect(reconnectedExternal.collapsedFrame.width == 24)

        // A global update clears per-display overrides consistently.
        coordinator.collapseImmediately()
        coordinator.updateCompactStatus(expandsForDetailedStatus: false)
        #expect(coordinator.activeLayout?.collapsedFrame.width == 24)
    }

    @Test
    func spaceChangeReassertsPersistentPanelsEvenAfterFirstExpandCollapse() throws {
        var frameRequests = 0
        var petViews: [CGDirectDisplayID: NSView] = [:]
        let coordinator = OverlayCoordinator(
            contentView: NSView(),
            collapseDelay: .zero,
            persistentContentViewProvider: { layout in
                let view = NSView()
                petViews[layout.displayID] = view
                return view
            },
            persistentPanelFrameProvider: { layout in
                frameRequests += 1
                return layout.collapsedFrame
            }
        )
        coordinator.screenSnapshotProvider = { [Self.builtInScreen, Self.externalScreen] }
        coordinator.start()
        defer { coordinator.stop() }

        let builtInLayout = ScreenLayoutEngine().layout(for: Self.builtInScreen)
        coordinator.handlePointer(at: CGPoint(x: builtInLayout.triggerFrame.midX, y: builtInLayout.triggerFrame.midY))
        coordinator.handlePointer(at: CGPoint(x: Self.builtInScreen.frame.midX, y: Self.builtInScreen.frame.midY))
        #expect(coordinator.isVisible)

        let externalPetPanel = try #require(petViews[Self.externalScreen.displayID]?.window as? IslandPanel)
        var orderFrontCount = 0
        externalPetPanel.panelOrderFrontHandler = { panel in
            orderFrontCount += 1
            panel.orderFrontRegardless()
        }

        NSWorkspace.shared.notificationCenter.post(
            name: NSWorkspace.activeSpaceDidChangeNotification,
            object: NSWorkspace.shared
        )

        #expect(orderFrontCount == 1,
                "Persistent panels must re-assert ordering on Space changes even after the island has been collapsed")
        #expect(frameRequests > 0)
    }

    @Test
    func deterministicMultiDisplayChaosAlwaysExpandsOnTargetedDisplay() throws {
        let screens = [Self.builtInScreen, Self.externalScreen]
        let state = MutableState(screens: screens)
        let content = NSView()
        let coordinator = OverlayCoordinator(contentView: content, collapseDelay: .zero)
        coordinator.screenSnapshotProvider = { state.screens }
        coordinator.start()
        defer { coordinator.stop() }

        var seed: UInt64 = 0x5EED_D159
        func nextRandom() -> UInt64 {
            seed = seed &* 6_364_136_223_846_793_005 &+ 1
            return seed >> 33
        }

        for step in 0..<80 {
            let action = nextRandom() % 7
            let targetIndex = Int(nextRandom() % 2)
            let targetScreen = screens[targetIndex]
            switch action {
            case 0:
                // Toggle collapsed window level.
                coordinator.setCollapsedOnTop(step.isMultiple(of: 2))
            case 1:
                // Explicit collapse while active.
                coordinator.collapseImmediately()
            case 2:
                // Simulate temporary external display disconnect then reconnect without notification.
                state.screens = [Self.builtInScreen]
                coordinator.refreshScreens()
                state.screens = screens
            case 3:
                // Simulate transient physical notch auxiliary dropout on built-in display.
                var gap = Self.builtInScreen
                gap.visibleFrame = gap.frame
                gap.safeAreaInsets = ScreenInsets()
                gap.auxiliaryTopLeftArea = nil
                gap.auxiliaryTopRightArea = nil
                state.screens = [gap, Self.externalScreen]
                coordinator.refreshScreens()
                state.screens = screens
            case 4:
                // Move pointer outside both triggers.
                coordinator.handlePointer(at: CGPoint(x: targetScreen.frame.midX, y: targetScreen.frame.midY))
            case 5:
                // Space switch notification.
                NSWorkspace.shared.notificationCenter.post(
                    name: NSWorkspace.activeSpaceDidChangeNotification,
                    object: NSWorkspace.shared
                )
            default:
                // Hover the targeted display's trigger at either midY or exact screen top edge (maxY).
                let targetLayout = ScreenLayoutEngine().layout(for: targetScreen)
                let y = step.isMultiple(of: 2) ? targetLayout.triggerFrame.midY : targetScreen.frame.maxY
                coordinator.handlePointer(at: CGPoint(x: targetLayout.triggerFrame.midX, y: y))
                let panel = try #require(content.window as? IslandPanel)
                #expect(coordinator.activeDisplayID == targetScreen.displayID, "Chaos step \(step) targeted wrong display")
                #expect(!panel.ignoresMouseEvents, "Chaos step \(step) failed to expand")
                #expect(panel.level == IslandPanel.onTopLevel, "Chaos step \(step) ordered at wrong level")
                #expect(panel.frame == targetLayout.expandedFrame, "Chaos step \(step) landed on wrong frame")
            }
        }
    }

    private static let builtInScreen = ScreenSnapshot(
        displayID: 401,
        frame: CGRect(x: 18_000, y: 0, width: 1_512, height: 982),
        visibleFrame: CGRect(x: 18_000, y: 0, width: 1_512, height: 945),
        safeAreaInsets: ScreenInsets(top: 37),
        auxiliaryTopLeftArea: CGRect(x: 18_000, y: 945, width: 660, height: 37),
        auxiliaryTopRightArea: CGRect(x: 18_852, y: 945, width: 660, height: 37),
        menuBarHeightFallback: 24
    )

    private static let externalScreen = ScreenSnapshot(
        displayID: 402,
        frame: CGRect(x: 20_000, y: 0, width: 2_560, height: 1_440),
        visibleFrame: CGRect(x: 20_000, y: 0, width: 2_560, height: 1_415),
        menuBarHeightFallback: 24
    )
}
