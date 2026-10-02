import AppKit
import Testing
@testable import Zisla

@MainActor
struct WiFiPopoverRegionTests {
    @Test
    func islandHostConnectsPopoverRegionsToItsOverlayCoordinator() throws {
        let appURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/Zisla/ZislaApp.swift")
        let source = try String(contentsOf: appURL, encoding: .utf8)
        #expect(source.contains(".environment(\\.islandTransientWindowChanged)"),
                "The island root must override the environment's no-op handler")
        #expect(source.contains("self?.overlayCoordinator?.setTransientInteractionWindow(window, anchor: anchor, id: id)"))
    }

    @Test
    func probePublishesTheActualPopoverWindowAndClearsOnClose() {
        let tracker = WiFiPopoverRegionTracker()
        let anchor = WiFiPopoverRegionView(tracker: tracker, role: .anchor)
        let content = WiFiPopoverRegionView(tracker: tracker, role: .popover)
        let anchorWindow = window()
        let popup = window()
        defer { anchorWindow.close(); popup.close() }
        var publishedWindow: NSWindow?
        var publishedAnchor: NSView?
        tracker.onChange = { _, window, anchor in
            publishedWindow = window
            publishedAnchor = anchor
        }
        anchorWindow.contentView = anchor
        popup.contentView = content
        #expect(publishedWindow === popup)
        #expect(publishedAnchor === anchor)

        popup.close()
        #expect(publishedWindow == nil)
    }

    @Test
    func movingAndResizingRevalidateTheLiveFrameAndDetachRemovesObservers() {
        let tracker = WiFiPopoverRegionTracker()
        let anchor = WiFiPopoverRegionView(tracker: tracker, role: .anchor)
        let content = WiFiPopoverRegionView(tracker: tracker, role: .popover)
        let anchorWindow = window()
        let popup = window()
        defer { anchorWindow.close(); popup.close() }
        var frames: [CGRect?] = []
        tracker.onChange = { _, window, _ in frames.append(window?.frame) }
        anchorWindow.contentView = anchor
        popup.contentView = content
        popup.setFrame(CGRect(x: 22_000, y: 200, width: 320, height: 240), display: false)
        frames.removeAll()
        NotificationCenter.default.post(name: NSWindow.didResizeNotification, object: popup)
        #expect(frames.last.flatMap { $0 } == popup.frame)
        tracker.detachPopover()
        #expect(frames.last == .some(nil))
        let count = frames.count
        NotificationCenter.default.post(name: NSWindow.didMoveNotification, object: popup)
        #expect(frames.count == count, "A detached popover must not restore its region")
    }

    @Test
    func replacingPopoverDoesNotLetOldViewTeardownClearTheNewWindow() {
        let tracker = WiFiPopoverRegionTracker()
        let anchor = WiFiPopoverRegionView(tracker: tracker, role: .anchor)
        let old = WiFiPopoverRegionView(tracker: tracker, role: .popover)
        let replacement = WiFiPopoverRegionView(tracker: tracker, role: .popover)
        let anchorWindow = window()
        let first = window()
        let second = window()
        defer { anchorWindow.close(); first.close(); second.close() }
        var published: NSWindow?
        tracker.onChange = { _, window, _ in published = window }
        anchorWindow.contentView = anchor
        first.contentView = old
        second.contentView = replacement
        first.contentView = NSView()
        WiFiPopoverRegionProbe.dismantleNSView(old, coordinator: ())
        #expect(published === second)
        WiFiPopoverRegionProbe.dismantleNSView(replacement, coordinator: ())
        #expect(published == nil)
    }

    @Test
    func replacingAnchorIgnoresOldAnchorTeardown() {
        let tracker = WiFiPopoverRegionTracker()
        let old = WiFiPopoverRegionView(tracker: tracker, role: .anchor)
        let replacement = WiFiPopoverRegionView(tracker: tracker, role: .anchor)
        let content = WiFiPopoverRegionView(tracker: tracker, role: .popover)
        let host = window()
        let popup = window()
        defer { host.close(); popup.close() }
        var publishedAnchor: NSView?
        tracker.onChange = { _, _, anchor in publishedAnchor = anchor }
        host.contentView = NSView()
        host.contentView?.addSubview(old)
        popup.contentView = content
        host.contentView?.addSubview(replacement)
        old.removeFromSuperview()
        tracker.detach(old, role: .anchor)
        #expect(publishedAnchor === replacement)
        tracker.detach(replacement, role: .anchor)
        #expect(publishedAnchor == nil)
    }

    private func window() -> NSWindow {
        let window = NSWindow(contentRect: CGRect(x: 20_000, y: 100, width: 300, height: 200),
                              styleMask: .borderless, backing: .buffered, defer: true)
        window.isReleasedWhenClosed = false
        return window
    }
}
