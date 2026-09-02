import AppKit
import Testing
@testable import ZislaKit

/// Verifies that panel refreshes — content re-layout, Space recovery, module resize — do not
/// reclaim keyboard activation once focus has moved to a text field elsewhere.
///
/// Serialized: `NSApp.keyWindow` is process-wide state, so parallel cases would clobber each other.
@Suite(.serialized)
struct IslandPanelFocusRetentionTests {
    /// Brings up a glass-active island panel, then hands focus to a stand-in for the user's text
    /// field — the state the island is in when a track lands while the user is typing.
    @MainActor
    private static func makeFocusedElsewhereScenario() -> (panel: IslandPanel, host: NSWindow) {
        let panel = IslandPanel(
            contentView: NSView(),
            frame: CGRect(x: 0, y: 0, width: 240, height: 34)
        )
        panel.allowsNativeGlassActivation = true
        panel.keepsNativeGlassActive = true
        panel.present(at: panel.frame, animated: false)

        let host = NSWindow(
            contentRect: CGRect(x: 20, y: 20, width: 240, height: 120),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        panel.avoidsAppActivation = true
        host.makeKeyAndOrderFront(nil)
        panel.avoidsAppActivation = false
        return (panel, host)
    }

    @Test @MainActor
    func refrontingVisiblePanelDoesNotReclaimKeyWindow() {
        let (panel, host) = Self.makeFocusedElsewhereScenario()
        defer {
            panel.orderOut(nil)
            host.orderOut(nil)
        }

        // Space recovery: already visible at the same frame, ordering must be re-asserted.
        panel.present(at: panel.frame, animated: false)

        #expect(!panel.isKeyWindow)
    }

    @Test @MainActor
    func repositioningVisiblePanelDoesNotReclaimKeyWindow() async {
        let (panel, host) = Self.makeFocusedElsewhereScenario()
        defer {
            panel.orderOut(nil)
            host.orderOut(nil)
        }

        // Module resize: a longer track title stretches the media header, moving the panel frame.
        panel.present(at: CGRect(x: 0, y: 0, width: 320, height: 48), animated: false)
        try? await Task.sleep(for: .milliseconds(10))

        #expect(!panel.isKeyWindow)
        #expect(panel.frame == CGRect(x: 0, y: 0, width: 320, height: 48))
    }


    @Test @MainActor
    func reassigningGlassFlagToSameValueDoesNotReclaimKeyWindow() {
        let (panel, host) = Self.makeFocusedElsewhereScenario()
        defer {
            panel.orderOut(nil)
            host.orderOut(nil)
        }

        // Island refresh re-applies the focus policy, re-asserting the unchanged glass flag.
        panel.keepsNativeGlassActive = true

        #expect(!panel.isKeyWindow)
    }

    @Test @MainActor
    func resizingVisiblePanelDoesNotReclaimKeyWindow() async {
        let (panel, host) = Self.makeFocusedElsewhereScenario()
        defer {
            panel.orderOut(nil)
            host.orderOut(nil)
        }

        panel.resize(to: CGRect(x: 0, y: 0, width: 320, height: 48))
        try? await Task.sleep(for: .milliseconds(10))

        #expect(!panel.isKeyWindow)
    }

    @Test @MainActor
    func resizeDoesNotAllowPendingGlassRecoveryToReclaimKeyWindow() async {
        var activationCount = 0
        let originalActivationHandler = IslandPanel.applicationActivationHandler
        IslandPanel.applicationActivationHandler = { activationCount += 1 }
        defer { IslandPanel.applicationActivationHandler = originalActivationHandler }

        let panel = IslandPanel(
            contentView: NSView(),
            frame: CGRect(x: 0, y: 0, width: 240, height: 34)
        )
        panel.allowsNativeGlassActivation = true
        panel.keepsNativeGlassActive = true
        panel.present(at: panel.frame, animated: false)
        activationCount = 0

        let host = NSWindow(
            contentRect: CGRect(x: 20, y: 20, width: 240, height: 120),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        defer {
            panel.avoidsAppActivation = true
            panel.keepsNativeGlassActive = false
            panel.orderOut(nil)
            host.orderOut(nil)
        }

        // The host resignation schedules Glass recovery on the next run-loop turn. A module
        // resize in that same turn must not let the delayed recovery reclaim this window.
        host.makeKeyAndOrderFront(nil)
        panel.resize(to: CGRect(x: 0, y: 0, width: 320, height: 48))
        try? await Task.sleep(for: .milliseconds(20))
        panel.resignKey()
        try? await Task.sleep(for: .milliseconds(20))

        #expect(activationCount == 0)
    }

    @Test @MainActor
    func resizingKeyPanelKeepsGlassPanelVisible() async {
        let (panel, host) = Self.makeFocusedElsewhereScenario()
        defer {
            panel.orderOut(nil)
            host.orderOut(nil)
        }

        panel.makeKeyAndOrderFront(nil)
        panel.resize(to: CGRect(x: 0, y: 0, width: 320, height: 48))
        try? await Task.sleep(for: .milliseconds(10))

        // The stable Glass resize path may cycle window ordering, but it must leave the panel visible
        // without activating the application.
        #expect(panel.isVisible)
        #expect(panel.frame == CGRect(x: 0, y: 0, width: 320, height: 48))
    }

    /// The deliberate-reveal path must still work, otherwise the transparent style's glass stays
    /// subdued when the user actually opens the island.
    @Test @MainActor
    func explicitActivationStillReclaimsKeyWindow() {
        let (panel, host) = Self.makeFocusedElsewhereScenario()
        defer {
            panel.orderOut(nil)
            host.orderOut(nil)
        }

        panel.activateNativeGlassIfNeeded()

        #expect(panel.isKeyWindow)
    }

    /// Losing key status to another app is a normal focus handoff, not a deliberate island reveal.
    /// The delayed Glass recovery must keep the compositor alive without activating Zisla again.
    @Test @MainActor
    func resigningGlassPanelDoesNotReactivateApplication() async {
        var activationCount = 0
        let originalActivationHandler = IslandPanel.applicationActivationHandler
        IslandPanel.applicationActivationHandler = { activationCount += 1 }
        defer { IslandPanel.applicationActivationHandler = originalActivationHandler }

        let panel = IslandPanel(
            contentView: NSView(),
            frame: CGRect(x: 0, y: 0, width: 240, height: 34)
        )
        panel.allowsNativeGlassActivation = true
        panel.keepsNativeGlassActive = true
        panel.present(at: panel.frame, animated: false)
        activationCount = 0
        defer {
            panel.keepsNativeGlassActive = false
            panel.orderOut(nil)
        }

        panel.resignKey()
        try? await Task.sleep(for: .milliseconds(20))

        #expect(activationCount == 0)
    }

    /// A panel arriving on screen is a reveal, not a refresh: it may take focus.
    @Test @MainActor
    func firstPresentReclaimsKeyWindowForGlassPanel() {
        let host = NSWindow(
            contentRect: CGRect(x: 20, y: 20, width: 240, height: 120),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        host.makeKeyAndOrderFront(nil)
        let panel = IslandPanel(
            contentView: NSView(),
            frame: CGRect(x: 0, y: 0, width: 240, height: 34)
        )
        panel.allowsNativeGlassActivation = true
        panel.keepsNativeGlassActive = true
        defer {
            panel.orderOut(nil)
            host.orderOut(nil)
        }

        panel.present(at: panel.frame, animated: false)

        #expect(panel.isKeyWindow)
    }
}
