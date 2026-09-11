import Foundation

/// Decides when the lid-close effect may start and when it has to let go, from
/// a stream of hinge-angle readings.
///
/// Kept out of `LidCloseController` because none of these rules need a sensor,
/// a window, or a run loop, and the repository requires the trigger contract to
/// carry assertions. The closing detection and angle prediction follow Mac Duo's
/// Apache-2.0 `LidController`; see `Resources/ThirdPartyLicenses/MacDuo-LICENSE.txt`.
struct LidCloseMotion {
    struct Tuning {
        /// Angle at or below which the effect may start.
        var thresholdAngle: Double = 90
        /// Degrees above `thresholdAngle` the lid must reach to release the effect.
        var releaseHysteresis: Double = 5
        /// Closing speed, in degrees per second, that counts as a deliberate
        /// close. A lid that nobody is moving reads under 0.5.
        var triggerClosingSpeed: Double = 2
        /// Closing speed at or above which the newest reading counts as stale,
        /// so the prediction takes over.
        var predictionSpeedFloor: Double = 40
        /// Sensor latency the prediction adds on top of the reading's own age.
        var predictionLatency: CFTimeInterval = 0.04
        /// How long after the lid last moved down the effect may still start.
        var closingMemory: CFTimeInterval = 1.5
    }

    let tuning: Tuning

    /// The most recent reading.
    private(set) var rawAngle: Double = 0
    /// Degrees per second, negative while the lid closes.
    private(set) var angularVelocity: Double = 0

    private var lastAngle: Double?
    private var lastAngleTime: CFTimeInterval = 0
    private var lastClosingTime = -CFTimeInterval.greatestFiniteMagnitude

    init(tuning: Tuning = Tuning()) {
        self.tuning = tuning
    }

    /// Forgets the movement history and adopts `angle` as the current reading.
    /// Used after waking, so a lid that is already nearly shut does not read as
    /// closing movement.
    mutating func reset(angle: Double?) {
        lastAngle = nil
        angularVelocity = 0
        lastClosingTime = -CFTimeInterval.greatestFiniteMagnitude
        if let angle {
            rawAngle = angle
        }
    }

    /// Adds one reading. `now` is `CACurrentMediaTime()` in production and a
    /// fixed clock under test.
    mutating func record(angle: Double, at now: CFTimeInterval) {
        defer {
            lastAngle = angle
            lastAngleTime = now
        }
        rawAngle = angle
        guard let previous = lastAngle else { return }
        let elapsed = max(now - lastAngleTime, 0.001)
        let instantaneousVelocity = (angle - previous) / elapsed
        angularVelocity = 0.5 * instantaneousVelocity + 0.5 * angularVelocity
        if angularVelocity <= -tuning.triggerClosingSpeed {
            lastClosingTime = now
        }
    }

    /// Whether the effect may start. It demands downward movement within the
    /// last `closingMemory` seconds, so a lid that is merely resting below the
    /// threshold while the app launches never covers the display on its own.
    func shouldEngage(at now: CFTimeInterval) -> Bool {
        guard now - lastClosingTime < tuning.closingMemory else { return false }
        return predictedAngle(at: now) <= tuning.thresholdAngle
    }

    /// Whether the lid has opened far enough to release the effect.
    func shouldRelease(angle: Double) -> Bool {
        angle >= tuning.thresholdAngle + tuning.releaseHysteresis
    }

    /// A reading can be a full sensor refresh old, so a fast close is judged
    /// from where the lid is heading rather than from the last reading.
    func predictedAngle(at now: CFTimeInterval) -> Double {
        guard angularVelocity < -tuning.predictionSpeedFloor else { return rawAngle }
        let staleness = min(now - lastAngleTime, 0.12)
        return rawAngle + angularVelocity * (staleness + tuning.predictionLatency)
    }
}
