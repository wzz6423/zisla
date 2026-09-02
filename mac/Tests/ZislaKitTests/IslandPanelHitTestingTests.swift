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
        panel.alphaValue = 0
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

    /// The whole point of the active-appearance override: glass no longer needs key status, so
    /// showing the glass surface must not widen the panel's focus eligibility by itself.
    @Test @MainActor
    func keepsNativeGlassActiveDoesNotMakePanelKeyEligible() {
        let panel = IslandPanel(
            contentView: NSView(),
            frame: CGRect(x: 0, y: 0, width: 240, height: 34)
        )
        panel.allowsKeyWindow = false
        panel.keepsNativeGlassActive = true

        #expect(!panel.canBecomeKey)
    }

    /// `NSGlassEffectView` renders full Liquid Glass only while its host window paints as active.
    /// The panel answers AppKit's private appearance query itself, which is what lets it stay
    /// non-key — and therefore leave the user's caret alone — without degrading to frosted glass.
    @Test @MainActor
    func panelClaimsActiveAppearanceWhileStayingNonKey() throws {
        let panel = IslandPanel(
            contentView: NSView(),
            frame: CGRect(x: 0, y: 0, width: 240, height: 34)
        )
        panel.present(at: panel.frame, animated: false)
        panel.alphaValue = 0
        defer { panel.orderOut(nil) }
        let selector = activeAppearanceSelector
        let override = try #require(class_getMethodImplementation(IslandPanel.self, selector))

        #expect(override != class_getMethodImplementation(NSPanel.self, selector))
        #expect(callsBackTrue(panel, selector))
        #expect(!panel.isKeyWindow)
        #expect(!panel.canBecomeKey)
    }

    @Test @MainActor
    func repositioningVisiblePanelRestoresItsFinalFrame() {
        let collapsedFrame = CGRect(x: 100, y: 700, width: 240, height: 34)
        let expandedFrame = CGRect(x: 0, y: 400, width: 860, height: 334)
        let panel = IslandPanel(contentView: NSView(), frame: collapsedFrame)
        panel.present(at: collapsedFrame)
        panel.alphaValue = 0
        defer { panel.orderOut(nil) }

        panel.present(at: expandedFrame)
        panel.alphaValue = 0

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
    func visiblePanelMovingToNewFrameIsClassifiedAsReposition() {
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
        panel.alphaValue = 0
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

    @Test @MainActor
    func pinnedPanelKeepsGlassActiveWithoutTakingFocus() async {
        let panel = IslandPanel(
            contentView: NSView(),
            frame: CGRect(x: 0, y: 0, width: 240, height: 34)
        )
        var activationCount = 0
        panel.applicationActivationHandler = { activationCount += 1 }
        panel.keepsNativeGlassActive = true
        panel.isPinned = true
        panel.present(at: panel.frame, animated: false)
        panel.alphaValue = 0
        defer { panel.orderOut(nil) }

        try? await Task.sleep(for: .milliseconds(50))

        #expect(panel.keepsNativeGlassActive)
        #expect(!panel.isKeyWindow)
        #expect(activationCount == 0)
    }
}

/// Built from a runtime string because `#selector` cannot name a private AppKit query.
private let activeAppearanceSelector: Selector = {
    let name = "_hasActiveAppearance"
    return Selector(name)
}()

/// Invokes a `BOOL`-returning, argument-less selector without going through `perform`, which would
/// misread the returned scalar as an object.
@MainActor
private func callsBackTrue(_ object: AnyObject, _ selector: Selector) -> Bool {
    typealias BoolQuery = @convention(c) (AnyObject, Selector) -> Bool
    guard let method = class_getInstanceMethod(type(of: object), selector) else { return false }
    return unsafeBitCast(method_getImplementation(method), to: BoolQuery.self)(object, selector)
}

@MainActor
private final class PassthroughContentView: NSView {
    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }
}
