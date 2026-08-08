import AppKit
import CoreGraphics
import Testing

@testable import ZislaKit

struct WindowPlacementTests {
    @Test
    func centersWindowInVisibleScreenFrame() {
        let windowFrame = CGRect(x: 0, y: 0, width: 548, height: 510)
        let screenFrame = CGRect(x: 1_440, y: -120, width: 1_920, height: 1_080)

        #expect(
            WindowPlacement.centeredFrame(for: windowFrame, in: screenFrame)
                == CGRect(x: 2_126, y: 165, width: 548, height: 510)
        )
    }

    @Test
    func centeredFramePreservesWindowSizeOnNegativeDisplayCoordinates() {
        let windowFrame = CGRect(x: 90, y: 40, width: 420, height: 180)
        let screenFrame = CGRect(x: -1_920, y: -180, width: 1_920, height: 1_055)

        let centered = WindowPlacement.centeredFrame(for: windowFrame, in: screenFrame)

        #expect(centered.size == windowFrame.size)
        #expect(centered.midX == screenFrame.midX)
        #expect(centered.midY == screenFrame.midY)
    }

    @Test @MainActor
    func centersWindowOnRequestedScreenVisibleFrame() throws {
        let screen = try #require(NSScreen.screens.first)
        let window = NSWindow(
            contentRect: CGRect(x: 0, y: 0, width: 320, height: 180),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )

        WindowPlacement.center(window, on: screen)

        #expect(abs(window.frame.midX - screen.visibleFrame.midX) <= 1)
        #expect(abs(window.frame.midY - screen.visibleFrame.midY) <= 1)
    }

    @Test @MainActor
    func preparesModalWindowAboveDynamicIsland() throws {
        let screen = try #require(NSScreen.screens.first)
        let window = NSWindow(
            contentRect: CGRect(x: 0, y: 0, width: 320, height: 180),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )

        WindowPlacement.prepareModal(window, on: screen)

        #expect(window.level == WindowPlacement.modalWindowLevel)
        #expect(window.level.rawValue > IslandPanel.onTopLevel.rawValue)
        #expect(abs(window.frame.midX - screen.visibleFrame.midX) <= 1)
        #expect(abs(window.frame.midY - screen.visibleFrame.midY) <= 1)
    }

    @Test @MainActor
    func promotesTransientWindowAboveDynamicIsland() {
        let window = NSPanel(
            contentRect: CGRect(x: 0, y: 0, width: 320, height: 180),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )

        WindowPlacement.promoteTransientWindowIfNeeded(window)

        #expect(window.level == WindowPlacement.modalWindowLevel)
    }

    @Test @MainActor
    func promotesWindowThatBecomesKeyAfterSwiftUIPresentation() {
        let window = NSPanel(
            contentRect: CGRect(x: 0, y: 0, width: 320, height: 180),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        WindowPlacement.installTransientWindowPromotion()

        NotificationCenter.default.post(name: NSWindow.didBecomeKeyNotification, object: window)

        #expect(window.level == WindowPlacement.modalWindowLevel)
    }

    @Test @MainActor
    func leavesIslandAndHigherPriorityWindowsUntouched() {
        let island = IslandPanel(
            contentView: NSView(),
            frame: CGRect(x: 0, y: 0, width: 320, height: 180)
        )
        let screenSaverWindow = NSPanel(
            contentRect: CGRect(x: 0, y: 0, width: 320, height: 180),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        screenSaverWindow.level = .screenSaver

        WindowPlacement.promoteTransientWindowIfNeeded(island)
        WindowPlacement.promoteTransientWindowIfNeeded(screenSaverWindow)

        #expect(island.level == IslandPanel.onTopLevel)
        #expect(screenSaverWindow.level == .screenSaver)
    }

    /// The authorization anchor host should center on the requested screen's visible frame, stay tiny and invisible yet keyable,
    /// so the system permission sheet follows that screen. Tests only verify placement logic—no activate/front system side effects,
    /// and do not mock the system prompt itself.
    @Test @MainActor
    func authorizationPromptHostUsesRequestedScreen() throws {
        let screen = try #require(NSScreen.screens.first)
        let host = try #require(WindowPlacement.makeAuthorizationPromptHost(on: screen))

        #expect(host.canBecomeKey)
        #expect(host.frame.width > 0 && host.frame.width <= 2)
        #expect(host.frame.height > 0 && host.frame.height <= 2)
        #expect(abs(host.frame.midX - screen.visibleFrame.midX) <= 1)
        #expect(abs(host.frame.midY - screen.visibleFrame.midY) <= 1)
    }

    @Test @MainActor
    func authorizationPromptHostStaysAboveDynamicIsland() throws {
        let screen = try #require(NSScreen.screens.first)
        let host = try #require(WindowPlacement.makeAuthorizationPromptHost(on: screen))

        #expect(host.level == WindowPlacement.modalWindowLevel)
        #expect(host.level.rawValue > IslandPanel.onTopLevel.rawValue)
    }
}
