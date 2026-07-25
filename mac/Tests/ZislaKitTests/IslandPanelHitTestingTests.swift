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

    @Test @MainActor
    func panelRemainsVisibleAcrossSpacesAndFullScreen() {
        let panel = IslandPanel(
            contentView: NSView(),
            frame: CGRect(x: 0, y: 0, width: 240, height: 34)
        )

        #expect(panel.collectionBehavior.contains(.canJoinAllSpaces))
        #expect(panel.collectionBehavior.contains(.fullScreenAuxiliary))
        #expect(panel.collectionBehavior.contains(.canJoinAllApplications))
        #expect(panel.collectionBehavior.contains(.stationary))
        #expect(panel.collectionBehavior.contains(.ignoresCycle))
        #expect(panel.level == .statusBar)
        #expect(!panel.isFloatingPanel)
        // Primary/Auxiliary/CanJoinAllApplications 三者互斥，确保没有误设冲突位。
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
