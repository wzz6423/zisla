import CoreGraphics
import Testing
@testable import ZislaKit

struct IslandSurfaceTransformTests {
    @Test
    func collapsedSurfaceUsesTheTopCenterAsItsOnlyAnchor() {
        let expanded = CGSize(width: 660, height: 340)
        let transform = IslandSurfaceTransform(
            collapsedSize: CGSize(width: 80, height: 32),
            expandedSize: expanded,
            isCollapsed: true
        )

        #expect(transform.visibleFrame(in: expanded) == CGRect(x: 290, y: 0, width: 80, height: 32))
    }

    @Test
    func collapsedSurfaceKeepsTheTopEdgeAtZero() {
        let expanded = CGSize(width: 860, height: 504)
        let transform = IslandSurfaceTransform(
            collapsedSize: CGSize(width: 80, height: 32),
            expandedSize: expanded,
            isCollapsed: true
        )

        #expect(transform.visibleFrame(in: expanded).minY == 0)
        #expect(transform.visibleFrame(in: expanded).midX == expanded.width / 2)
    }

    @Test
    func intermediateSurfaceKeepsTheTopCenterFixed() {
        let expanded = CGSize(width: 660, height: 340)
        let transform = IslandSurfaceTransform(
            collapsedSize: CGSize(width: 80, height: 32),
            expandedSize: expanded,
            revealProgress: 0.5
        )

        let frame = transform.visibleFrame(in: expanded)
        #expect(frame.minY == 0)
        #expect(frame.midX == expanded.width / 2)
        #expect(abs(frame.width - 370) < 0.001)
        #expect(abs(frame.height - 186) < 0.001)
    }

    @Test
    func expandedSurfaceUsesTheUntranslatedFullFrame() {
        let expanded = CGSize(width: 660, height: 340)
        let transform = IslandSurfaceTransform(
            collapsedSize: CGSize(width: 80, height: 32),
            expandedSize: expanded,
            isCollapsed: false
        )

        #expect(transform.visibleFrame(in: expanded) == CGRect(origin: .zero, size: expanded))
    }

    @Test
    func fittingSizeKeepsEveryEdgeInsideTheAvailablePanel() {
        #expect(
            IslandSurfaceTransform.fittingSize(
                contentSize: CGSize(width: 1_060, height: 524),
                availableSize: CGSize(width: 936, height: 524)
            ) == CGSize(width: 936, height: 524)
        )
        #expect(
            IslandSurfaceTransform.fittingSize(
                contentSize: CGSize(width: 660, height: 560),
                availableSize: CGSize(width: 660, height: 420)
            ) == CGSize(width: 660, height: 420)
        )
        #expect(
            IslandSurfaceTransform.fittingSize(
                contentSize: CGSize(width: 660, height: 340),
                availableSize: CGSize(width: 860, height: 344)
            ) == CGSize(width: 660, height: 340)
        )
        #expect(
            IslandSurfaceTransform.fittingSize(
            contentSize: CGSize(width: 1_060, height: 524),
            availableSize: CGSize(width: -1, height: 524)
        ) == CGSize(width: 0, height: 524)
        )
    }

    @Test
    func revealAnimationExpandsFromHorizontalCenterAndTopEdge() {
        let expanded = CGSize(width: 748, height: 324)
        let collapsed = CGSize(width: 240, height: 34)

        let collapsedFrame = IslandSurfaceTransform(
            collapsedSize: collapsed,
            expandedSize: expanded,
            revealProgress: 0
        ).visibleFrame(in: expanded)

        let midFrame = IslandSurfaceTransform(
            collapsedSize: collapsed,
            expandedSize: expanded,
            revealProgress: 0.5
        ).visibleFrame(in: expanded)

        let expandedFrame = IslandSurfaceTransform(
            collapsedSize: collapsed,
            expandedSize: expanded,
            revealProgress: 1
        ).visibleFrame(in: expanded)

        // The horizontal center remains fixed throughout expansion.
        #expect(abs(collapsedFrame.midX - expanded.width / 2) < 0.001)
        #expect(abs(midFrame.midX - expanded.width / 2) < 0.001)
        #expect(abs(expandedFrame.midX - expanded.width / 2) < 0.001)

        // The top edge remains at y = 0 throughout expansion.
        #expect(collapsedFrame.minY == 0)
        #expect(midFrame.minY == 0)
        #expect(expandedFrame.minY == 0)

        // The side edges expand outward from the center.
        #expect(midFrame.minX < collapsedFrame.minX)
        #expect(midFrame.maxX > collapsedFrame.maxX)
        #expect(expandedFrame.minX < midFrame.minX)
        #expect(expandedFrame.maxX > midFrame.maxX)

        // The bottom edge expands downward.
        #expect(midFrame.maxY > collapsedFrame.maxY)
        #expect(expandedFrame.maxY > midFrame.maxY)
    }

    @Test
    func collapsedCenterOffsetUnwindsAsTheSurfaceReachesFullReveal() {
        // The pet slot pushes the expanded surface 22pt off the panel center, so the pill has to
        // drift back that far to land on the notch — and drift to nothing once fully revealed.
        #expect(IslandSurfaceTransform.collapsedCenterOffset(22, revealProgress: 0) == 22)
        #expect(IslandSurfaceTransform.collapsedCenterOffset(22, revealProgress: 0.5) == 11)
        #expect(IslandSurfaceTransform.collapsedCenterOffset(22, revealProgress: 1) == 0)
        // Mirrored pet side.
        #expect(IslandSurfaceTransform.collapsedCenterOffset(-22, revealProgress: 0) == -22)
        // Spring overshoot must not push the pill past the notch or past the surface center.
        #expect(IslandSurfaceTransform.collapsedCenterOffset(22, revealProgress: 1.2) == 0)
        #expect(IslandSurfaceTransform.collapsedCenterOffset(22, revealProgress: -0.3) == 22)
        // No slot reserved: the surface is already centered on the notch.
        #expect(IslandSurfaceTransform.collapsedCenterOffset(0, revealProgress: 0) == 0)
    }
}
