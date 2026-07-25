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
}
