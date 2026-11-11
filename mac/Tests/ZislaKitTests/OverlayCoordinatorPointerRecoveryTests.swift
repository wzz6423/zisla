import AppKit
import CoreFoundation
import Testing
@testable import ZislaKit

@MainActor
struct OverlayCoordinatorPointerRecoveryTests {
    @Test
    func missedMouseEventsDoNotLeaveAVisibleNotchUnableToExpand() throws {
        let fixture = Fixture()
        defer { fixture.coordinator.stop() }
        let panel = try #require(fixture.content.window as? IslandPanel)
        var activations = 0
        fixture.coordinator.applicationActivationHandler = { activations += 1 }
        var visibilityChanges: [Bool] = []
        fixture.coordinator.onVisibilityChanged = { visibilityChanges.append($0) }
        #expect(panel.isVisible)
        #expect(panel.ignoresMouseEvents)

        fixture.pointer.location = fixture.trigger
        fixture.coordinator.pointerRecoveryTimer?.fire()

        #expect(!panel.ignoresMouseEvents,
                "A previously working, visible notch must expand even when mouse events stop arriving")
        #expect(panel.isVisible)
        #expect(!panel.isKeyWindow)

        fixture.pointer.location = fixture.outside
        fixture.coordinator.pointerRecoveryTimer?.fire()
        #expect(panel.ignoresMouseEvents, "A missed pointer exit must still fold the island")

        fixture.pointer.location = fixture.trigger
        fixture.coordinator.pointerRecoveryTimer?.fire()
        #expect(!panel.ignoresMouseEvents, "Recovery must continue without recreating the full-screen Space")
        #expect(visibilityChanges == [true, false, true])
        #expect(activations == 0, "Recovering hover must leave Chrome's keyboard focus alone")
    }

    @Test(arguments: [1, 2, 4])
    func recoveryWaitsForMouseReleaseInsteadOfTurningADragIntoHover(buttons: Int) throws {
        let fixture = Fixture()
        defer { fixture.coordinator.stop() }
        let panel = try #require(fixture.content.window as? IslandPanel)

        fixture.pointer.location = fixture.trigger
        fixture.pointer.pressedButtons = buttons
        fixture.coordinator.pointerRecoveryTimer?.fire()
        #expect(panel.ignoresMouseEvents, "Polling cannot classify a drag as an ordinary hover")

        fixture.pointer.pressedButtons = 0
        fixture.coordinator.pointerRecoveryTimer?.fire()
        #expect(!panel.ignoresMouseEvents, "A click or drag release must recover the lost hover")
    }

    @Test
    func recoveryDoesNotRepeatNormalEventsOrUndoAnExplicitCollapse() throws {
        let fixture = Fixture()
        defer { fixture.coordinator.stop() }
        let panel = try #require(fixture.content.window as? IslandPanel)
        var visibilityChanges: [Bool] = []
        fixture.coordinator.onVisibilityChanged = { visibilityChanges.append($0) }

        fixture.pointer.location = fixture.trigger
        fixture.coordinator.handlePointer(at: fixture.trigger)
        for _ in 0..<10 { fixture.coordinator.pointerRecoveryTimer?.fire() }
        #expect(visibilityChanges == [true])

        fixture.coordinator.collapseImmediately()
        for _ in 0..<10 { fixture.coordinator.pointerRecoveryTimer?.fire() }
        #expect(visibilityChanges == [true, false])
        #expect(panel.ignoresMouseEvents, "A stationary pointer cannot undo an explicit collapse")

        fixture.pointer.location = fixture.outside
        fixture.coordinator.pointerRecoveryTimer?.fire()
        fixture.pointer.location = fixture.trigger
        fixture.coordinator.pointerRecoveryTimer?.fire()
        #expect(!panel.ignoresMouseEvents, "Leaving and reentering must restore expansion")
    }

    @Test
    func stoppedCoordinatorCannotRecoverOrKeepItsTimerAlive() throws {
        let fixture = Fixture()
        let panel = try #require(fixture.content.window as? IslandPanel)
        let timer = fixture.coordinator.pointerRecoveryTimer
        fixture.coordinator.stop()
        fixture.pointer.location = fixture.trigger
        timer?.fire()

        #expect(!panel.isVisible)
        #expect(!fixture.coordinator.isRunning)
        #expect(fixture.coordinator.pointerRecoveryTimer == nil)
        #expect(timer?.isValid != true)
    }

    @Test
    func recoveryReleasesADragEvenWhenItsMouseUpAndExitWereLost() throws {
        let fixture = Fixture()
        defer { fixture.coordinator.stop() }
        let panel = try #require(fixture.content.window as? IslandPanel)
        fixture.coordinator.setDragging(true)
        #expect(!panel.ignoresMouseEvents)

        fixture.coordinator.pointerRecoveryTimer?.fire()
        #expect(panel.ignoresMouseEvents, "A lost mouse-up cannot hold the island open indefinitely")
    }

    @Test(arguments: ["locked", "recording", "hoverSuspended", "capturing", "screenshot"])
    func recoveryRespectsInteractionSuppressionAndResumesAfterRelease(state: String) throws {
        let fixture = Fixture()
        defer { fixture.coordinator.stop() }
        let panel = try #require(fixture.content.window as? IslandPanel)
        func suppress(_ active: Bool) {
            switch state {
            case "locked": fixture.coordinator.setScreenLocked(active)
            case "recording": fixture.coordinator.setVoiceRecording(active, at: fixture.outside)
            case "hoverSuspended": fixture.coordinator.setHoverActivationSuspended(active)
            case "capturing": fixture.coordinator.setScreenshotCaptureInProgress(active)
            default: fixture.coordinator.setScreenshotActive(active)
            }
        }
        suppress(true)
        fixture.pointer.location = fixture.trigger
        fixture.coordinator.pointerRecoveryTimer?.fire()
        #expect(!panel.isVisible || panel.ignoresMouseEvents,
                "Recovery must respect the existing interaction owner")

        suppress(false)
        fixture.coordinator.pointerRecoveryTimer?.fire()
        #expect(panel.isVisible)
        #expect(!panel.ignoresMouseEvents, "The same stationary pointer can recover when suppression ends")
    }

    @Test
    func recoveryPreservesPinnedPanelsAndTheExternalRevealGracePeriod() throws {
        let fixture = Fixture()
        defer { fixture.coordinator.stop() }
        let panel = try #require(fixture.content.window as? IslandPanel)
        fixture.coordinator.setPinned(true)
        for _ in 0..<10 { fixture.coordinator.pointerRecoveryTimer?.fire() }
        #expect(panel.isPinned)
        #expect(!panel.ignoresMouseEvents, "Recovery cannot fold a pinned island")

        fixture.coordinator.setPinned(false)
        #expect(panel.ignoresMouseEvents)
        fixture.coordinator.showExpanded(at: fixture.outside)
        fixture.coordinator.pointerRecoveryTimer?.fire()
        #expect(!panel.ignoresMouseEvents,
                "A menu or hotkey reveal still waits for the pointer to reach the island")
        fixture.pointer.location = fixture.trigger
        fixture.coordinator.pointerRecoveryTimer?.fire()
        fixture.pointer.location = fixture.outside
        fixture.coordinator.pointerRecoveryTimer?.fire()
        #expect(panel.ignoresMouseEvents, "After pointer entry the next exit folds the external reveal")
    }

    @Test
    func recoveryTimerIsBoundedAndReleasedOnStopRestartAndDeinit() throws {
        var coordinator: OverlayCoordinator? = OverlayCoordinator(contentView: NSView())
        coordinator?.screenSnapshotProvider = { [] }
        coordinator?.start()
        let timer = try #require(coordinator?.pointerRecoveryTimer)
        #expect(timer.timeInterval == 0.5)
        #expect(timer.tolerance == 0.1)
        #expect(timer.isValid)
        #expect(CFRunLoopContainsTimer(CFRunLoopGetMain(), timer, .commonModes),
                "Recovery must continue during AppKit event-tracking modes")
        coordinator?.start()
        #expect(coordinator?.pointerRecoveryTimer === timer)
        timer.fire()
        #expect(coordinator?.isVisible == false, "Missing displays must not create a recovery panel")

        coordinator?.stop()
        #expect(!timer.isValid)
        coordinator?.start()
        let replacement = try #require(coordinator?.pointerRecoveryTimer)
        #expect(replacement !== timer)
        weak var reference = coordinator
        coordinator = nil
        #expect(reference == nil, "The run-loop timer must not retain the coordinator")
        #expect(!replacement.isValid)
    }

    @Test
    func recoveryUsesTheDisplayUnderThePointerAfterASpaceChange() throws {
        let fixture = Fixture()
        defer { fixture.coordinator.stop() }
        let panel = try #require(fixture.content.window as? IslandPanel)
        let other = ScreenSnapshot(displayID: 302,
            frame: CGRect(x: -20_000, y: 20_000, width: 1_920, height: 1_080),
            visibleFrame: CGRect(x: -20_000, y: 20_000, width: 1_920, height: 1_080))
        fixture.coordinator.updateScreens([fixture.screen, other])
        NSWorkspace.shared.notificationCenter.post(
            name: NSWorkspace.activeSpaceDidChangeNotification, object: NSWorkspace.shared
        )
        let otherLayout = ScreenLayoutEngine().layout(for: other)
        fixture.pointer.location = CGPoint(x: otherLayout.triggerFrame.midX, y: otherLayout.triggerFrame.midY)
        fixture.coordinator.pointerRecoveryTimer?.fire()
        #expect(fixture.coordinator.activeDisplayID == other.displayID)
        #expect(panel.frame == otherLayout.expandedFrame)
        #expect(!panel.ignoresMouseEvents)

        fixture.pointer.location = fixture.trigger
        fixture.coordinator.pointerRecoveryTimer?.fire()
        #expect(fixture.coordinator.activeDisplayID == fixture.screen.displayID)
        #expect(panel.frame == ScreenLayoutEngine().layout(for: fixture.screen).expandedFrame)
        #expect(!panel.ignoresMouseEvents)
    }

    @MainActor
    private final class PointerSample {
        var location: CGPoint
        var pressedButtons = 0

        init(location: CGPoint) {
            self.location = location
        }
    }

    @MainActor
    private struct Fixture {
        let content = NSView()
        let coordinator: OverlayCoordinator
        let pointer: PointerSample
        let screen: ScreenSnapshot
        let trigger: CGPoint
        let outside: CGPoint

        init() {
            screen = ScreenSnapshot(
                displayID: 301,
                frame: CGRect(x: 20_000, y: 20_000, width: 1_512, height: 982),
                visibleFrame: CGRect(x: 20_000, y: 20_000, width: 1_512, height: 982),
                safeAreaInsets: ScreenInsets(top: 37),
                auxiliaryTopLeftArea: CGRect(x: 20_000, y: 20_945, width: 660, height: 37),
                auxiliaryTopRightArea: CGRect(x: 20_852, y: 20_945, width: 660, height: 37)
            )
            let layout = ScreenLayoutEngine().layout(for: screen)
            trigger = CGPoint(x: layout.triggerFrame.midX, y: layout.triggerFrame.midY)
            outside = CGPoint(x: screen.frame.midX, y: screen.frame.midY)
            let pointer = PointerSample(location: outside)
            self.pointer = pointer
            coordinator = OverlayCoordinator(contentView: content)
            coordinator.screenSnapshotProvider = { [screen] in [screen] }
            coordinator.pointerLocationProvider = { pointer.location }
            coordinator.pressedMouseButtonsProvider = { pointer.pressedButtons }
            coordinator.start()
            coordinator.handlePointer(at: trigger)
            coordinator.handlePointer(at: outside)
        }
    }
}
