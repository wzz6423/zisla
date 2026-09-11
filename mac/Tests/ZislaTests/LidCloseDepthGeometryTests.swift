import Foundation
import Testing

@testable import Zisla

/// The lid-close picture is a sheet hinged to the bottom edge of the screen and
/// turned backward in world space, seen from a fixed eye. These assertions pin
/// the two properties the look depends on: the hinge edge never moves, and the
/// far edge narrows away from the viewer instead of swelling toward it.
struct LidCloseDepthGeometryTests {
    private let screen = CGSize(width: 1512, height: 982)
    private let startAngle = 90.0

    private func corners(travel: Double) -> [CGPoint] {
        DepthGeometry().corners(
            startAngle: startAngle,
            currentAngle: startAngle - travel,
            viewingDistanceRatio: DepthTuning().viewingDistance,
            recession: DepthTuning().recession,
            screenSize: screen
        )
    }

    @Test
    func travelFreeLeavesThePictureOnTheGlass() {
        let corners = corners(travel: 0)
        let expected = [
            CGPoint(x: 0, y: 0),
            CGPoint(x: screen.width, y: 0),
            CGPoint(x: screen.width, y: screen.height),
            CGPoint(x: 0, y: screen.height),
        ]
        for (corner, target) in zip(corners, expected) {
            #expect(abs(corner.x - target.x) < 0.001)
            #expect(abs(corner.y - target.y) < 0.001)
        }
    }

    @Test
    func theHingeEdgeIsStillAtEveryAngle() {
        for travel in stride(from: 0.0, through: 60.0, by: 5.0) {
            let corners = corners(travel: travel)
            #expect(corners[0] == .zero)
            #expect(abs(corners[1].y) < 0.001)
            #expect(abs(corners[1].x - screen.width) < 0.001)
        }
    }

    @Test
    func theFarEdgeNarrowsAsTheLidCloses() {
        var previousWidth = screen.width
        for travel in stride(from: 5.0, through: 60.0, by: 5.0) {
            let corners = corners(travel: travel)
            let farWidth = corners[2].x - corners[3].x
            // Receding means converging, not magnifying: a sheet turning toward
            // the viewer would come back wider than the hinge edge.
            #expect(farWidth < screen.width)
            #expect(farWidth < previousWidth)
            previousWidth = farWidth
        }
        // At the end of the travel the picture has visibly drawn away.
        #expect(previousWidth < screen.width * 0.8)
    }

    @Test
    func thePictureStaysCentredWhileItRecedes() {
        let midX = screen.width / 2
        for travel in stride(from: 0.0, through: 60.0, by: 5.0) {
            let corners = corners(travel: travel)
            for (left, right) in [(corners[0], corners[1]), (corners[3], corners[2])] {
                #expect(abs((midX - left.x) - (right.x - midX)) < 0.001)
                #expect(abs(left.y - right.y) < 0.001)
            }
        }
    }

    @Test
    func theFarEdgeLiftsAwayFromTheHinge() {
        // The hinge edge is fixed, so everything above it has to move for the
        // sheet to turn: the far edge rises out of the frame rather than
        // sliding down over the near one.
        let still = corners(travel: 0)
        let turned = corners(travel: 60)
        #expect(turned[2].y > still[2].y)
        #expect(turned[3].y > still[3].y)
    }
}
