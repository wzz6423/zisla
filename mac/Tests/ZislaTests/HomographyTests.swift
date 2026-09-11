import Foundation
import Testing
import simd

@testable import Zisla

/// The depth pass draws by inverting this mapping, so the mapping has to put
/// the picture rectangle exactly onto the projected corners.
struct HomographyTests {
    private func project(_ matrix: simd_double3x3, _ point: SIMD2<Double>) -> SIMD2<Double> {
        let mapped = matrix * SIMD3(point.x, point.y, 1)
        return SIMD2(mapped.x / mapped.z, mapped.y / mapped.z)
    }

    @Test
    func theIdentityQuadLeavesTheRectangleAlone() {
        let width = 1512.0
        let height = 982.0
        let corners = [
            CGPoint(x: 0, y: 0),
            CGPoint(x: width, y: 0),
            CGPoint(x: width, y: height),
            CGPoint(x: 0, y: height),
        ]
        let matrix = Homography.matrix(width: width, height: height, to: corners)
        for point in [SIMD2(0.0, 0.0), SIMD2(width, 0.0), SIMD2(width, height), SIMD2(0.0, height), SIMD2(width / 3, height / 5)] {
            let mapped = project(matrix, point)
            #expect(abs(mapped.x - point.x) < 0.001)
            #expect(abs(mapped.y - point.y) < 0.001)
        }
    }

    @Test
    func everyPictureCornerLandsOnItsProjectedCorner() {
        let screen = CGSize(width: 1512, height: 982)
        let corners = DepthGeometry().corners(
            startAngle: 90,
            currentAngle: 30,
            viewingDistanceRatio: DepthTuning().viewingDistance,
            recession: DepthTuning().recession,
            screenSize: screen
        )
        let width = Double(screen.width)
        let height = Double(screen.height)
        let matrix = Homography.matrix(width: width, height: height, to: corners)

        let rectangle = [
            SIMD2(0.0, 0.0),
            SIMD2(width, 0.0),
            SIMD2(width, height),
            SIMD2(0.0, height),
        ]
        for (point, corner) in zip(rectangle, corners) {
            let mapped = project(matrix, point)
            #expect(abs(mapped.x - Double(corner.x)) < 0.01)
            #expect(abs(mapped.y - Double(corner.y)) < 0.01)
        }
    }
}
