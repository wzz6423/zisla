import CoreGraphics
import Foundation
import Testing

@testable import ZislaKit

struct ContextNoteShakeDetectorTests {
    @Test(arguments: [28.0, 40.0, 80.0])
    func requiresThreeClearReversals(width: Double) {
        var detector = ContextNoteShakeDetector()
        let results = Self.samples(width: width).map { detector.record($0.point, at: $0.time) }
        #expect(results == [false, false, false, false, true])
    }

    @Test(arguments: [1, 3, 12, 48])
    func deliberateHorizontalShakeAllowsMinorDriftAtDifferentSamplingRates(samplesPerLeg: Int) {
        var detector = ContextNoteShakeDetector()
        let samples = Self.samples(samplesPerLeg: samplesPerLeg).map { sample in
            (point: CGPoint(x: sample.point.x, y: sample.time * 16), time: sample.time)
        }
        let results = samples.map { detector.record($0.point, at: $0.time) }
        #expect(results.filter { $0 }.count == 1)
    }

    @Test(arguments: [60.0, 125.0, 1_000.0], [0.0, 0.3, 0.7])
    func naturalHorizontalShakesSurvivePointerMoveCoalescing(sampleRate: Double, phase: Double) {
        for (legDuration, verticalRadius) in [(0.16, 0.0), (0.1, 20.0), (0.16, 20.0), (0.18, 20.0)] {
            var detector = ContextNoteShakeDetector()
            var throttle = PointerEdgeEventThrottle()
            var triggers = 0
            for index in 0...Int(sampleRate) {
                let time = Double(index) / sampleRate
                guard throttle.shouldEmit(eventType: .mouseMoved, timestamp: time) else { continue }
                let angle = Double.pi * (time / legDuration + phase)
                let point = CGPoint(x: 600 + 60 * cos(angle), y: 400 + verticalRadius * sin(angle))
                if detector.record(point, at: time) { triggers += 1 }
            }
            #expect(triggers == 1, "legDuration=\(legDuration), verticalRadius=\(verticalRadius)")
        }
    }

    @Test(arguments: [60.0, 125.0, 1_000.0], [40.0, 60.0])
    func aShortLightShakeIsEnough(sampleRate: Double, width: Double) {
        for phase in [0.0, 0.3, 0.7] {
            var detector = ContextNoteShakeDetector()
            var throttle = PointerEdgeEventThrottle()
            var triggers = 0
            for index in 0...Int(sampleRate * 0.7) {
                let time = Double(index) / sampleRate
                guard throttle.shouldEmit(eventType: .mouseMoved, timestamp: time) else { continue }
                let angle = Double.pi * (time / 0.16 + phase)
                let point = CGPoint(x: 600 + width / 2 * cos(angle), y: 400 + width / 4 * sin(angle))
                if detector.record(point, at: time) { triggers += 1 }
            }
            #expect(triggers == 1, "phase=\(phase)")
        }
    }

    @Test
    func aRelaxedContinuousShakeDoesNotRequireRushedTurns() {
        var detector = ContextNoteShakeDetector()
        var throttle = PointerEdgeEventThrottle()
        var triggers = 0
        for sample in Self.samples(legDuration: 0.28, samplesPerLeg: 12) {
            guard throttle.shouldEmit(eventType: .mouseMoved, timestamp: sample.time) else { continue }
            if detector.record(sample.point, at: sample.time) { triggers += 1 }
        }
        #expect(triggers == 1)
    }

    @Test(arguments: [8.0, 18.0, 27.0])
    func smallJitterNeverAccumulates(width: Double) {
        var detector = ContextNoteShakeDetector()
        for sample in Self.samples(width: width, legs: 30, legDuration: 0.05, samplesPerLeg: 8) {
            #expect(detector.record(sample.point, at: sample.time) == false)
        }
    }

    @Test
    func normalPointerTargetingAndStationarySamplesDoNotTrigger() {
        var detector = ContextNoteShakeDetector()
        for (index, x) in [0.0, 160, 30, 180].enumerated() {
            #expect(detector.record(CGPoint(x: x, y: 0), at: Double(index) * 0.1) == false)
        }
        for index in 1...500 {
            #expect(detector.record(CGPoint(x: 180, y: 0), at: 0.3 + Double(index) / 1_000) == false)
        }
    }

    @Test(arguments: [CGPoint(x: 0, y: 1), CGPoint(x: 1, y: 1), CGPoint(x: 1, y: 0.9)],
          [CGPoint.zero, CGPoint(x: 600, y: 400), CGPoint(x: -1400, y: -200)])
    func verticalAndSteepDiagonalShakesDoNotTrigger(axis: CGPoint, origin: CGPoint) {
        var detector = ContextNoteShakeDetector()
        for sample in Self.samples(legs: 16, samplesPerLeg: 8) {
            let point = CGPoint(x: origin.x + sample.point.x * axis.x, y: origin.y + sample.point.x * axis.y)
            #expect(detector.record(point, at: sample.time) == false)
        }
    }

    @Test(arguments: [0.4, 0.6])
    func slowMovementDoesNotTrigger(legDuration: TimeInterval) {
        var detector = ContextNoteShakeDetector()
        for sample in Self.samples(legs: 20, legDuration: legDuration, samplesPerLeg: 12) {
            #expect(detector.record(sample.point, at: sample.time) == false)
        }
    }

    @Test
    func aPauseDiscardsProgressEvenWhenStationaryEventsContinue() {
        var detector = ContextNoteShakeDetector()
        let samples: [(Double, Double)] = [
            (0, 0), (0.08, 80), (0.16, 0), (0.24, 80),
            (0.30, 80), (0.36, 80), (0.42, 80), (0.48, 80),
            (0.54, 80), (0.60, 80), (0.64, 0), (0.72, 80),
        ]
        for (time, x) in samples {
            #expect(detector.record(CGPoint(x: x, y: 0), at: time) == false)
        }
        let results = Self.samples(start: 2).map { detector.record($0.point, at: $0.time) }
        #expect(results.filter { $0 }.count == 1)
    }

    @Test
    func longGapsCannotCompleteAnEarlierGesture() {
        var detector = ContextNoteShakeDetector()
        for sample in Self.samples(legs: 3) {
            #expect(detector.record(sample.point, at: sample.time) == false)
        }
        #expect(detector.record(CGPoint(x: 80, y: 0), at: 5) == false)
        #expect(detector.record(.zero, at: 5.1) == false)
    }

    @Test
    func resetDiscardsIncompleteReversals() {
        var detector = ContextNoteShakeDetector()
        for sample in Self.samples(legs: 3) {
            #expect(detector.record(sample.point, at: sample.time) == false)
        }
        detector.reset()
        #expect(detector.record(CGPoint(x: 80, y: 0), at: 0.5) == false)
        let results = Self.samples(start: 1).map { detector.record($0.point, at: $0.time) }
        #expect(results.filter { $0 }.count == 1)
    }

    @Test
    func resetPreservesCooldownAndCooldownMovementCannotSeedAnotherGesture() {
        var detector = ContextNoteShakeDetector()
        let first = Self.samples().map { detector.record($0.point, at: $0.time) }
        #expect(first.filter { $0 }.count == 1)
        detector.reset()
        for sample in Self.samples(start: 0.6) + Self.samples(start: 2.1) {
            #expect(detector.record(sample.point, at: sample.time) == false)
        }
        detector.reset()
        let later = Self.samples(start: 2.7).map { detector.record($0.point, at: $0.time) }
        #expect(later.filter { $0 }.count == 1)
    }

    @Test(arguments: [0.2, 0.3])
    func reversedAndRepeatedTimestampsDiscardPendingReversals(timestamp: TimeInterval) {
        var detector = ContextNoteShakeDetector()
        for sample in Self.samples(legs: 3) {
            #expect(detector.record(sample.point, at: sample.time) == false)
        }
        #expect(detector.record(CGPoint(x: 80, y: 0), at: timestamp) == false)
        #expect(detector.record(.zero, at: 0.5) == false)
        #expect(detector.record(CGPoint(x: 80, y: 0), at: 0.6) == false)
        let results = Self.samples(start: 1).map { detector.record($0.point, at: $0.time) }
        #expect(results.filter { $0 }.count == 1)
    }

    @Test
    func nonfiniteSamplesDiscardProgressAndAllowRecovery() {
        let invalidSamples: [(CGPoint, TimeInterval)] = [
            (CGPoint(x: CGFloat.nan, y: 0), 0.5),
            (CGPoint(x: 80, y: CGFloat.infinity), 0.5),
            (CGPoint(x: 80, y: 0), .nan),
            (CGPoint(x: 80, y: 0), .infinity),
        ]
        for (point, time) in invalidSamples {
            var detector = ContextNoteShakeDetector()
            for sample in Self.samples(legs: 3) {
                #expect(detector.record(sample.point, at: sample.time) == false)
            }
            #expect(detector.record(point, at: time) == false)
            #expect(detector.record(.zero, at: 0.6) == false)
            let results = Self.samples(start: 1).map { detector.record($0.point, at: $0.time) }
            #expect(results.filter { $0 }.count == 1)
        }
    }

    private static func samples(
        width: Double = 80,
        start: TimeInterval = 0,
        legs: Int = 4,
        legDuration: TimeInterval = 0.1,
        samplesPerLeg: Int = 1
    ) -> [(point: CGPoint, time: TimeInterval)] {
        var result: [(point: CGPoint, time: TimeInterval)] = [(.zero, start)]
        for leg in 0..<legs {
            for sample in 1...samplesPerLeg {
                let fraction = Double(sample) / Double(samplesPerLeg)
                let x = leg.isMultiple(of: 2) ? width * fraction : width * (1 - fraction)
                result.append((CGPoint(x: x, y: 0), start + (Double(leg) + fraction) * legDuration))
            }
        }
        return result
    }
}
