import Foundation
import Testing

@testable import Zisla

/// The lid-close trigger contract: only a lid that really moved downwards
/// within the last moments may start the effect, so a lid resting below the
/// threshold, or one being opened, never covers the display by itself.
struct LidCloseMotionTests {
    @Test
    func restingLidBelowThresholdNeverEngages() {
        var motion = LidCloseMotion()
        // A lid parked at 60 degrees keeps reporting the same angle.
        for step in 0..<40 {
            motion.record(angle: 60, at: Double(step) * 0.1)
        }

        #expect(motion.angularVelocity == 0)
        #expect(!motion.shouldEngage(at: 4))
    }

    @Test
    func closingLidEngagesOnceItReachesTheThreshold() {
        var motion = LidCloseMotion()
        var now = 0.0
        var angle = 100.0
        motion.record(angle: angle, at: now)

        // 10 degrees per second is a deliberate close.
        while angle > 91 {
            now += 0.1
            angle -= 1
            motion.record(angle: angle, at: now)
        }
        #expect(!motion.shouldEngage(at: now))

        now += 0.1
        angle -= 1
        motion.record(angle: angle, at: now)
        #expect(motion.rawAngle == 90)
        #expect(motion.shouldEngage(at: now))
    }

    @Test
    func openingLidDoesNotEngage() {
        var motion = LidCloseMotion()
        motion.record(angle: 60, at: 0)
        motion.record(angle: 80, at: 0.1)

        #expect(motion.angularVelocity > 0)
        #expect(!motion.shouldEngage(at: 0.1))
    }

    @Test
    func movementOlderThanTheClosingMemoryDoesNotEngage() {
        var motion = LidCloseMotion()
        motion.record(angle: 100, at: 0)
        motion.record(angle: 90, at: 0.1)

        #expect(motion.shouldEngage(at: 0.1))
        // The lid stopped moving; the still lid must not be covered.
        #expect(!motion.shouldEngage(at: 1.7))
    }

    @Test
    func slowDriftBelowTheTriggerSpeedIsNotAClose() {
        var motion = LidCloseMotion()
        var now = 0.0
        var angle = 95.0
        motion.record(angle: angle, at: now)

        // 1 degree per second: a lid sliding on a soft surface, not a hand.
        for _ in 0..<10 {
            now += 1
            angle -= 1
            motion.record(angle: angle, at: now)
        }

        #expect((-1.01..<(-0.9)).contains(motion.angularVelocity))
        #expect(!motion.shouldEngage(at: now))
    }

    @Test
    func slowCloseIsJudgedFromTheNewestReadingOnly() {
        var motion = LidCloseMotion()
        var now = 0.0
        var angle = 100.0
        motion.record(angle: angle, at: now)

        // 12 degrees per second stays under the prediction floor.
        while angle > 90.4 {
            now += 0.1
            angle -= 1.2
            motion.record(angle: angle, at: now)
        }

        #expect(abs(angle - 90.4) < 0.0001)
        #expect(abs(motion.angularVelocity + 12) < 0.1)
        // A prediction would overshoot a slow close, so only the reading counts.
        #expect(abs(motion.predictedAngle(at: now) - motion.rawAngle) < 0.0001)
        #expect(!motion.shouldEngage(at: now))
    }

    @Test
    func fastCloseIsJudgedFromThePredictedAngle() {
        var motion = LidCloseMotion()
        motion.record(angle: 100, at: 0)
        motion.record(angle: 90, at: 0.1)

        // 100 degrees per second raw, halved against the still first sample.
        #expect(abs(motion.angularVelocity + 50) < 0.01)
        #expect(motion.rawAngle == 90)
        // The reading sits exactly on the threshold; the prediction carries it under.
        #expect(abs(motion.predictedAngle(at: 0.1) - 88) < 0.01)
        #expect(motion.shouldEngage(at: 0.1))
    }

    @Test
    func releaseNeedsTheFullHysteresis() {
        let motion = LidCloseMotion()

        #expect(!motion.shouldRelease(angle: 90))
        #expect(!motion.shouldRelease(angle: 94.999))
        #expect(motion.shouldRelease(angle: 95))
    }

    @Test
    func readingsWithNoElapsedTimeDoNotDivideByZero() {
        var motion = LidCloseMotion()
        motion.record(angle: 100, at: 1)
        motion.record(angle: 200, at: 1)

        #expect(motion.angularVelocity.isFinite)
    }

    @Test
    func wakeResetsTheMovementHistory() {
        var motion = LidCloseMotion()
        motion.record(angle: 100, at: 0)
        motion.record(angle: 80, at: 0.1)
        #expect(motion.shouldEngage(at: 0.1))

        motion.reset(angle: 80)

        #expect(motion.rawAngle == 80)
        #expect(motion.angularVelocity == 0)
        // The lid is nearly shut, but nothing says it was just closing.
        #expect(!motion.shouldEngage(at: 0.1))
    }

    @Test
    func resetWithoutAReadingKeepsTheLastAngle() {
        var motion = LidCloseMotion()
        motion.record(angle: 100, at: 0)

        // A MacBook without a lid sensor reports no angle at all.
        motion.reset(angle: nil)

        #expect(motion.rawAngle == 100)
        #expect(motion.angularVelocity == 0)
    }
}
