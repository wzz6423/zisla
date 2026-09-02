import AppKit
import CoreGraphics
import Testing
@testable import ZislaKit

@Suite(.serialized)
struct IslandAutomaticContentRefreshFocusTests {
    @Test @MainActor
    func expandedContentRefreshDoesNotActivateApplication() async throws {
        let recorder = ActivationRecorder()

        let contentView = NSView()
        let coordinator = OverlayCoordinator(contentView: contentView, collapseDelay: .zero)
        coordinator.applicationActivationHandler = { recorder.record() }
        defer { coordinator.stop() }
        coordinator.updateScreens([Self.screen], repositionVisiblePanel: false)
        coordinator.selectActiveDisplay(at: CGPoint(x: 720, y: 450))
        coordinator.setKeepsNativeGlassActive(true)
        coordinator.setDragging(true)
        let panel = try #require(contentView.window as? IslandPanel)
        await Self.drainMainActor()
        recorder.reset()

        coordinator.updateExpandedSize(CGSize(width: 900, height: 360))
        await Self.drainMainActor()

        #expect(recorder.count == 0)
        #expect(panel.isVisible)
        #expect(panel.keepsNativeGlassActive)
    }

    @Test @MainActor
    func persistentContentRefreshDoesNotActivateApplication() async throws {
        let recorder = ActivationRecorder()

        var offset: CGFloat = 0
        var persistentView: NSView?
        let coordinator = OverlayCoordinator(
            contentView: NSView(),
            persistentContentViewProvider: { layout in
                let view = NSView(frame: CGRect(origin: .zero, size: layout.collapsedFrame.size))
                persistentView = view
                return view
            },
            persistentPanelFrameProvider: { layout in
                var frame = layout.collapsedFrame
                frame.origin.x += offset
                return frame
            }
        )
        coordinator.applicationActivationHandler = { recorder.record() }
        defer { coordinator.stop() }
        coordinator.updateScreens([Self.screen], repositionVisiblePanel: false)
        let panel = try #require(persistentView?.window as? IslandPanel)
        panel.keepsNativeGlassActive = true
        await Self.drainMainActor()
        recorder.reset()

        let initialFrame = panel.frame
        offset = 20
        coordinator.refreshPersistentPanels()
        await Self.drainMainActor()

        #expect(recorder.count == 0)
        #expect(panel.isVisible)
        #expect(panel.frame.minX == initialFrame.minX + offset)
    }

    @Test @MainActor
    func unchangedGlassPolicyDoesNotActivateApplication() async {
        let recorder = ActivationRecorder()

        let panel = IslandPanel(
            contentView: NSView(),
            frame: CGRect(x: 0, y: 0, width: 240, height: 34)
        )
        panel.applicationActivationHandler = { recorder.record() }
        panel.keepsNativeGlassActive = true
        panel.present(at: panel.frame, animated: false)
        defer { panel.orderOut(nil) }
        await Self.drainMainActor()
        recorder.reset()

        panel.keepsNativeGlassActive = true
        await Self.drainMainActor()

        #expect(recorder.count == 0)
    }

    @Test @MainActor
    func automaticResizeDoesNotActivateApplication() async {
        let recorder = ActivationRecorder()

        let initialFrame = CGRect(x: 0, y: 0, width: 240, height: 34)
        let panel = IslandPanel(contentView: NSView(), frame: initialFrame)
        panel.applicationActivationHandler = { recorder.record() }
        panel.keepsNativeGlassActive = true
        panel.present(at: initialFrame, animated: false)
        defer { panel.orderOut(nil) }
        await Self.drainMainActor()
        recorder.reset()

        panel.resize(to: CGRect(x: 0, y: 0, width: 900, height: 360), animated: false)
        await Self.drainMainActor()

        #expect(recorder.count == 0)
    }

    @Test @MainActor
    func automaticPresentationDoesNotActivateApplication() async {
        let recorder = ActivationRecorder()

        let initialFrame = CGRect(x: 0, y: 0, width: 240, height: 34)
        let panel = IslandPanel(contentView: NSView(), frame: initialFrame)
        panel.applicationActivationHandler = { recorder.record() }
        panel.keepsNativeGlassActive = true
        panel.present(at: initialFrame, animated: false)
        defer { panel.orderOut(nil) }
        await Self.drainMainActor()
        recorder.reset()

        panel.present(at: CGRect(x: 0, y: 0, width: 900, height: 360), animated: false)
        await Self.drainMainActor()

        #expect(recorder.count == 0)
    }

    /// The Liquid Glass guarantee. Ordering the panel out — which the previous implementation did on
    /// every frame change — drops key status, and `NSGlassEffectView` renders subdued in a non-key
    /// non-activating panel, so the island fell back to frosted after each automatic refresh. Curing
    /// that by re-keying is what stole the caret, hence the invariant: an automatic refresh must never
    /// leave the window server's ordering.
    @Test @MainActor
    func automaticResizeKeepsPanelInWindowServerOrdering() async {
        let initialFrame = CGRect(x: 0, y: 0, width: 240, height: 34)
        let panel = IslandPanel(contentView: NSView(), frame: initialFrame)
        panel.keepsNativeGlassActive = true
        panel.present(at: initialFrame, animated: false)
        defer { panel.orderOut(nil) }
        await Self.drainMainActor()

        let recorder = VisibilityRecorder(panel: panel)
        panel.resize(to: CGRect(x: 0, y: 0, width: 900, height: 360), animated: false)
        await Self.drainMainActor()

        #expect(recorder.transitions.isEmpty)
        #expect(panel.isVisible)
        #expect(panel.frame.width == 900)
    }

    @Test @MainActor
    func automaticRepositionKeepsPanelInWindowServerOrdering() async {
        let initialFrame = CGRect(x: 0, y: 0, width: 240, height: 34)
        let panel = IslandPanel(contentView: NSView(), frame: initialFrame)
        panel.keepsNativeGlassActive = true
        panel.present(at: initialFrame, animated: false)
        defer { panel.orderOut(nil) }
        await Self.drainMainActor()

        let recorder = VisibilityRecorder(panel: panel)
        panel.present(at: initialFrame.offsetBy(dx: 40, dy: 0), animated: false)
        await Self.drainMainActor()

        #expect(recorder.transitions.isEmpty)
        #expect(panel.isVisible)
        #expect(panel.frame.minX == initialFrame.minX + 40)
    }

    /// A deliberate click stays the one and only way the island takes focus.
    @Test @MainActor
    func clickInsideIslandStillActivatesApplication() throws {
        let recorder = ActivationRecorder()

        let frame = CGRect(x: 0, y: 0, width: 240, height: 34)
        let panel = IslandPanel(
            contentView: NSView(),
            frame: frame,
            blocksClicksInTransparentAreas: true
        )
        panel.applicationActivationHandler = { recorder.record() }
        panel.keepsNativeGlassActive = true
        panel.present(at: frame, animated: false)
        panel.alphaValue = 0
        defer { panel.orderOut(nil) }
        let click = try #require(NSEvent.mouseEvent(
            with: .leftMouseDown,
            location: CGPoint(x: 120, y: 17),
            modifierFlags: [],
            timestamp: 0,
            windowNumber: panel.windowNumber,
            context: nil,
            eventNumber: 0,
            clickCount: 1,
            pressure: 1
        ))
        recorder.reset()

        panel.sendEvent(click)

        #expect(recorder.count == 1)
    }

    /// While dictating, even a click must leave the caret in the app being typed into.
    @Test @MainActor
    func clickWhileAvoidingActivationLeavesFocusAlone() throws {
        let recorder = ActivationRecorder()

        let frame = CGRect(x: 0, y: 0, width: 240, height: 34)
        let panel = IslandPanel(
            contentView: NSView(),
            frame: frame,
            blocksClicksInTransparentAreas: true
        )
        panel.applicationActivationHandler = { recorder.record() }
        panel.avoidsAppActivation = true
        panel.present(at: frame, animated: false)
        panel.alphaValue = 0
        defer { panel.orderOut(nil) }
        let click = try #require(NSEvent.mouseEvent(
            with: .leftMouseDown,
            location: CGPoint(x: 120, y: 17),
            modifierFlags: [],
            timestamp: 0,
            windowNumber: panel.windowNumber,
            context: nil,
            eventNumber: 0,
            clickCount: 1,
            pressure: 1
        ))
        recorder.reset()

        panel.sendEvent(click)

        #expect(recorder.count == 0)
        #expect(!panel.isKeyWindow)
    }

    /// Pinning is the user saying "keep this open", so a text surface revealed that way still gets
    /// the caret without a second click.
    @Test @MainActor
    func pinnedTextInputSurfaceClaimsFocus() async throws {
        let recorder = ActivationRecorder()

        let contentView = NSView()
        let coordinator = OverlayCoordinator(contentView: contentView, collapseDelay: .zero)
        coordinator.applicationActivationHandler = { recorder.record() }
        defer { coordinator.stop() }
        coordinator.updateScreens([Self.screen], repositionVisiblePanel: false)
        coordinator.selectActiveDisplay(at: CGPoint(x: 720, y: 450))
        coordinator.setKeepsNativeGlassActive(true)
        coordinator.setPinned(true)
        let panel = try #require(contentView.window as? IslandPanel)
        panel.alphaValue = 0
        await Self.drainMainActor()
        recorder.reset()

        coordinator.setAllowsKeyWindow(true)
        await Self.drainMainActor()

        #expect(recorder.count == 1)
        #expect(panel.canBecomeKey)
    }

    /// The bug that started this: an automatic reveal must stay hands-off even when the visible
    /// module happens to be a text surface. Only pinning grants the caret.
    @Test @MainActor
    func unpinnedRevealOfTextInputSurfaceLeavesFocusAlone() async throws {
        let recorder = ActivationRecorder()

        let contentView = NSView()
        let coordinator = OverlayCoordinator(contentView: contentView, collapseDelay: .zero)
        coordinator.applicationActivationHandler = { recorder.record() }
        defer { coordinator.stop() }
        coordinator.updateScreens([Self.screen], repositionVisiblePanel: false)
        coordinator.selectActiveDisplay(at: CGPoint(x: 720, y: 450))
        coordinator.setKeepsNativeGlassActive(true)
        coordinator.setDragging(true)
        let panel = try #require(contentView.window as? IslandPanel)
        panel.alphaValue = 0
        await Self.drainMainActor()
        recorder.reset()

        coordinator.setAllowsKeyWindow(true)
        await Self.drainMainActor()

        #expect(recorder.count == 0)
        #expect(!panel.isKeyWindow)
        // Still eligible, so a click can hand over the caret.
        #expect(panel.canBecomeKey)
    }

    @MainActor
    private static func drainMainActor() async {
        await Task.yield()
        await Task.yield()
        try? await Task.sleep(for: .milliseconds(20))
    }

    private static let screen = ScreenSnapshot(
        displayID: 8_001,
        frame: CGRect(x: 0, y: 0, width: 1_440, height: 900),
        visibleFrame: CGRect(x: 0, y: 0, width: 1_440, height: 876)
    )
}

@MainActor
private final class ActivationRecorder {
    private(set) var count = 0

    func record() {
        count += 1
    }

    func reset() {
        count = 0
    }
}

/// Records every `isVisible` transition, which is how leaving and rejoining the window server's
/// ordering shows up from the outside.
@MainActor
private final class VisibilityRecorder {
    private(set) var transitions: [Bool] = []
    private var observation: NSKeyValueObservation?

    init(panel: IslandPanel) {
        observation = panel.observe(\.isVisible, options: [.new]) { [weak self] _, change in
            guard let value = change.newValue else { return }
            MainActor.assumeIsolated { self?.transitions.append(value) }
        }
    }
}
