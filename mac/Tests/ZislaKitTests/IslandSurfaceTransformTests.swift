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
}
