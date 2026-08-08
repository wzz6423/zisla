import AppKit
import Testing

@testable import ZislaKit

struct IslandPanelHitTestingTests {
    @Test @MainActor
    func expandedPanelInterceptsTransparentCoveredArea() throws {
        let frame = CGRect(x: 0, y: 0, width: 748, height: 324)
        let content = PassthroughContentView(frame: frame)
        let panel = IslandPanel(
            contentView: content,
            frame: frame,
            blocksClicksInTransparentAreas: true
        )
        let blockingView = try #require(panel.contentView)
        let bitmap = try #require(
            blockingView.bitmapImageRepForCachingDisplay(in: blockingView.bounds)
        )
        blockingView.cacheDisplay(in: blockingView.bounds, to: bitmap)
        let coveredPixel = try #require(bitmap.colorAt(x: 20, y: 20))

        #expect(blockingView.hitTest(CGPoint(x: 20, y: 20)) != nil)
        #expect(coveredPixel.alphaComponent > 0)
    }

    @Test @MainActor
    func expandedPanelPreservesInteractiveContentHitTarget() {
        let frame = CGRect(x: 0, y: 0, width: 748, height: 324)
        let content = NSButton(frame: frame)
        let panel = IslandPanel(
            contentView: content,
            frame: frame,
            blocksClicksInTransparentAreas: true
        )

        #expect(panel.contentView?.hitTest(CGPoint(x: 20, y: 20)) === content)
    }

    @Test @MainActor
    func genericClickDoesNotClaimFocusWhenPanelAllowsKeyboardInput() throws {
        let panel = IslandPanel(
            contentView: NSView(),
            frame: CGRect(x: 0, y: 0, width: 240, height: 34)
        )
        panel.allowsKeyWindow = true
        panel.present(at: panel.frame, animated: false)
        defer { panel.orderOut(nil) }
        let click = try #require(NSEvent.mouseEvent(
            with: .leftMouseDown,
            location: .zero,
            modifierFlags: [],
            timestamp: 0,
            windowNumber: panel.windowNumber,
            context: nil,
            eventNumber: 0,
            clickCount: 1,
            pressure: 1
        ))

        #expect(panel.canBecomeKey)
        panel.sendEvent(click)
        #expect(!panel.isKeyWindow)
    }

    @Test @MainActor
    func nonKeyWindowPanelDoesNotStealFocusOnClick() throws {
        let panel = IslandPanel(
            contentView: NSView(),
            frame: CGRect(x: 0, y: 0, width: 240, height: 34)
        )
        panel.allowsKeyWindow = false
        let click = try #require(NSEvent.mouseEvent(
            with: .leftMouseDown,
            location: .zero,
            modifierFlags: [],
            timestamp: 0,
            windowNumber: panel.windowNumber,
            context: nil,
            eventNumber: 0,
            clickCount: 1,
            pressure: 1
        ))

        #expect(!panel.canBecomeKey)
        panel.sendEvent(click)
        #expect(!panel.canBecomeKey)
    }

    @Test @MainActor
    func panelDoesNotReclaimFocusAfterResigningKey() {
        let panel = IslandPanel(
            contentView: NSView(),
            frame: CGRect(x: 0, y: 0, width: 240, height: 34)
        )
        panel.allowsKeyWindow = false
        panel.keepsNativeGlassActive = true
        panel.present(at: panel.frame)
        defer { panel.orderOut(nil) }

        panel.resignKey()

        #expect(!panel.canBecomeKey)
        #expect(!panel.isKeyWindow)
    }

    @Test @MainActor
    func repositioningVisiblePanelRestoresItsFinalFrame() {
        let collapsedFrame = CGRect(x: 100, y: 700, width: 240, height: 34)
        let expandedFrame = CGRect(x: 0, y: 400, width: 860, height: 334)
        let panel = IslandPanel(contentView: NSView(), frame: collapsedFrame)
        panel.present(at: collapsedFrame)
        defer { panel.orderOut(nil) }

        panel.present(at: expandedFrame)

        #expect(panel.isVisible)
        #expect(panel.frame == expandedFrame)
    }

    /// Re-presenting an unchanged panel is the active-Space recovery path: when another app opens a
    /// full-screen Space, WindowServer drops the pet panel from that Space's ordering, and only a
    /// fresh `orderFrontRegardless()` rejoins it. Resolving this case to a no-op made the pet
    /// permanently invisible behind other apps' full-screen windows.
    @Test @MainActor
    func visiblePanelAtUnchangedFrameStillReassertsWindowOrder() {
        let frame = CGRect(x: 40, y: 600, width: 240, height: 34)

        #expect(
            IslandPanel.presentationPlan(
                isVisible: true,
                currentFrame: frame,
                targetFrame: frame
            ) == .refront
        )
    }

    @Test @MainActor
    func hiddenPanelIsPositionedBeforeBeingOrderedIn() {
        let frame = CGRect(x: 40, y: 600, width: 240, height: 34)

        #expect(
            IslandPanel.presentationPlan(
                isVisible: false,
                currentFrame: .zero,
                targetFrame: frame
            ) == .show
        )
    }

    @Test @MainActor
    func visiblePanelMovingToNewFrameLeavesCompositingLayerFirst() {
        #expect(
            IslandPanel.presentationPlan(
                isVisible: true,
                currentFrame: CGRect(x: 40, y: 600, width: 240, height: 34),
                targetFrame: CGRect(x: 0, y: 400, width: 860, height: 334)
            ) == .reposition
        )
    }

    @Test @MainActor
    func reassertingOrderKeepsPanelVisibleAtSameFrameAndFullyOpaque() {
        let frame = CGRect(x: 40, y: 600, width: 240, height: 34)
        let panel = IslandPanel(contentView: NSView(), frame: frame)
        panel.present(at: frame)
        defer { panel.orderOut(nil) }
        // Mimics a dismiss fade still in flight when the Space change re-presents the panel.
        panel.alphaValue = 0

        panel.present(at: frame, animated: false)

        #expect(panel.isVisible)
        #expect(panel.frame == frame)
        #expect(panel.alphaValue == 1)
    }

    @Test @MainActor
    func panelRemainsVisibleAcrossSpacesAndOtherAppsFullScreen() {
        let panel = IslandPanel(
            contentView: NSView(),
            frame: CGRect(x: 0, y: 0, width: 240, height: 34)
        )

        #expect(panel.collectionBehavior.contains(.canJoinAllSpaces))
        #expect(panel.collectionBehavior.contains(.fullScreenAuxiliary))
        #expect(panel.collectionBehavior.contains(.canJoinAllApplications))
        #expect(panel.collectionBehavior.contains(.stationary))
        #expect(!panel.collectionBehavior.contains(.transient))
        #expect(panel.collectionBehavior.contains(.ignoresCycle))
        #expect(panel.level == .statusBar)
        #expect(!panel.isFloatingPanel)
        // Primary/Auxiliary/CanJoinAllApplications are mutually exclusive; ensure no conflicting bits are set.
        #expect(!panel.collectionBehavior.contains(.primary))
        #expect(!panel.collectionBehavior.contains(.auxiliary))
    }
}

@MainActor
private final class PassthroughContentView: NSView {
    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }
}
