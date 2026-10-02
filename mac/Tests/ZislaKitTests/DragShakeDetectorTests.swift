import CoreGraphics
import Foundation
import Testing

@testable import ZislaKit

struct DragShakeDetectorTests {
    @Test(arguments: [CGPoint(x: 1, y: 0), CGPoint(x: 0, y: 1), CGPoint(x: 1, y: 1)])
    func deliberateShakeTriggersInEveryDirection(axis: CGPoint) {
        var detector = DragShakeDetector()
        let results = [0.0, 50, -10, 50, -10].enumerated().map { index, value in
            detector.record(CGPoint(x: value * axis.x, y: value * axis.y), at: Double(index) * 0.1)
        }
        #expect(results == [false, false, false, false, true])
    }

    @Test
    func straightDragAndTinyJitterDoNotTrigger() {
        var straight = DragShakeDetector()
        var jitter = DragShakeDetector()
        for index in 0..<1_000 {
            let timestamp = Double(index) / 120
            let straightResult = straight.record(CGPoint(x: index * 2, y: index), at: timestamp)
            let jitterResult = jitter.record(CGPoint(x: index.isMultiple(of: 2) ? 5 : -5, y: 0), at: timestamp)
            #expect(!straightResult)
            #expect(!jitterResult)
        }
    }

    @Test
    func slowReversalsAndLongPausesDoNotCombine() {
        var detector = DragShakeDetector()
        for (index, value) in [0.0, 50, -10, 50, -10, 50, -10].enumerated() {
            let triggered = detector.record(CGPoint(x: value, y: 0), at: Double(index) * 0.5)
            #expect(!triggered)
        }
        detector.reset()
        for (timestamp, value) in [(0.0, 0.0), (0.1, 50), (0.2, -10), (2.0, 50), (2.1, -10)] {
            let triggered = detector.record(CGPoint(x: value, y: 0), at: timestamp)
            #expect(!triggered)
        }
    }

    @Test(arguments: [1, 4, 16, 64])
    func triggerDoesNotDependOnMouseSamplingRate(samplesPerLeg: Int) {
        var detector = DragShakeDetector()
        var triggers = 0
        let turns = [0.0, 50, -10, 50, -10]
        _ = detector.record(.zero, at: 0)
        for leg in 0..<(turns.count - 1) {
            for sample in 1...samplesPerLeg {
                let fraction = Double(sample) / Double(samplesPerLeg)
                let point = CGPoint(x: turns[leg] + (turns[leg + 1] - turns[leg]) * fraction, y: 0)
                if detector.record(point, at: (Double(leg) + fraction) * 0.1) { triggers += 1 }
            }
        }
        #expect(triggers == 1)
    }

    @Test
    func oneTriggerPerDragUntilReset() {
        var detector = DragShakeDetector()
        var triggers = 0
        for index in 0..<20 {
            let point = CGPoint(x: index.isMultiple(of: 2) ? 0 : 50, y: 0)
            if detector.record(point, at: Double(index) * 0.1) { triggers += 1 }
        }
        #expect(triggers == 1)
        detector.reset()
        for index in 0..<5 {
            let point = CGPoint(x: index.isMultiple(of: 2) ? 0 : 50, y: 0)
            if detector.record(point, at: Double(index) * 0.1) { triggers += 1 }
        }
        #expect(triggers == 2)
    }

    @Test
    func resetDiscardsAnIncompleteGesture() {
        var detector = DragShakeDetector()
        for (index, value) in [0.0, 50, -10, 50].enumerated() {
            let triggered = detector.record(CGPoint(x: value, y: 0), at: Double(index) * 0.1)
            #expect(!triggered)
        }
        detector.reset()
        let first = detector.record(CGPoint(x: -10, y: 0), at: 0.4)
        let second = detector.record(CGPoint(x: 50, y: 0), at: 0.5)
        #expect(!first)
        #expect(!second)
    }

    @Test
    func stationarySamplesCannotManufactureReversals() {
        var detector = DragShakeDetector()
        for index in 0..<2_000 {
            let triggered = detector.record(CGPoint(x: 50, y: 50), at: Double(index) / 1_000)
            #expect(!triggered)
        }
    }

    @Test
    func followsTurningPointsAfterAnInitialStraightDrag() {
        var detector = DragShakeDetector()
        let points = [0.0, 30, 200, 160, 200, 160]
        let results = points.enumerated().map { index, value in
            detector.record(CGPoint(x: value, y: 0), at: Double(index) * 0.08)
        }
        #expect(results == [false, false, false, false, false, true])
    }

    @Test
    func pauseDiscardsThePreviousTurningPoint() {
        var detector = DragShakeDetector()
        for (timestamp, value) in [(0.0, 0.0), (0.1, 50), (0.2, -10), (2.0, 50), (2.1, -10), (2.2, 50)] {
            let triggered = detector.record(CGPoint(x: value, y: 0), at: timestamp)
            #expect(!triggered)
        }
    }
}
