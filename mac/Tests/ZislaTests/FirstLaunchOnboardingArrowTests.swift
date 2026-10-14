import SwiftUI
import Testing
@testable import Zisla

struct FirstLaunchOnboardingArrowTests {
    @Test(arguments: [
        CGSize(width: 44, height: 40),
        CGSize(width: 11, height: 10),
        CGSize(width: 1, height: 1),
        CGSize(width: 440, height: 400),
        CGSize(width: 44, height: 12),
        CGSize(width: 12, height: 40),
    ])
    func roundedOutlineRemainsFiniteAndInsideFrame(size: CGSize) {
        let rect = CGRect(origin: CGPoint(x: 17, y: -23), size: size)
        let path = FirstLaunchOnboardingArrowShape().path(in: rect)
        let bounds = path.boundingRect

        #expect(!path.isEmpty)
        #expect(bounds.minX.isFinite && bounds.minY.isFinite)
        #expect(bounds.maxX.isFinite && bounds.maxY.isFinite)
        #expect(bounds.minX > rect.minX && bounds.maxX < rect.maxX)
        #expect(bounds.minY > rect.minY && bounds.maxY < rect.maxY)
        #expect(bounds.height > min(size.height, size.width * 40 / 44) * 0.7)

        path.forEach { element in
            let points: [CGPoint]
            switch element {
            case .move(to: let point), .line(to: let point):
                points = [point]
            case .quadCurve(to: let point, control: let control):
                points = [point, control]
            case .curve(to: let point, control1: let first, control2: let second):
                points = [point, first, second]
            case .closeSubpath:
                points = []
            }
            for point in points {
                #expect(point.x.isFinite && point.y.isFinite)
            }
        }
    }

    @Test(arguments: [
        CGRect.zero,
        CGRect(x: 0, y: 0, width: 0, height: 40),
        CGRect(x: 0, y: 0, width: 44, height: 0),
        CGRect(x: 0, y: 0, width: -44, height: 40),
        CGRect(x: 0, y: 0, width: 44, height: -40),
        CGRect(x: 0, y: 0, width: CGFloat.infinity, height: 40),
        CGRect(x: 0, y: 0, width: 44, height: CGFloat.nan),
        CGRect(x: CGFloat.infinity, y: 0, width: 44, height: 40),
    ])
    func degenerateFramesProduceNoInk(rect: CGRect) {
        #expect(FirstLaunchOnboardingArrowShape().path(in: rect).isEmpty)
    }
}
