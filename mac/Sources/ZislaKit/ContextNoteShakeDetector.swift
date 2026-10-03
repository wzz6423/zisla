import CoreGraphics
import Foundation

public struct ContextNoteShakeDetector {
    private var extreme: CGFloat?
    private var direction: CGFloat = 0
    private var reversals = 0
    private var minimumY: CGFloat = 0
    private var maximumY: CGFloat = 0
    private var startedAt: TimeInterval?
    private var lastTurnAt: TimeInterval?
    private var lastTimestamp: TimeInterval?
    private var lastTriggeredAt: TimeInterval?

    public init() {}

    public mutating func reset() {
        // Closing a note must not turn the remaining shake into another gesture.
        let lastTriggeredAt = self.lastTriggeredAt
        self = Self()
        self.lastTriggeredAt = lastTriggeredAt
    }

    public mutating func record(_ point: CGPoint, at timestamp: TimeInterval) -> Bool {
        guard point.x.isFinite, point.y.isFinite, timestamp.isFinite else {
            reset()
            return false
        }
        if let lastTriggeredAt, timestamp - lastTriggeredAt < 2 {
            reset()
            return false
        }
        if let lastTimestamp, timestamp <= lastTimestamp {
            reset()
            return false
        }
        if let startedAt, timestamp - startedAt > 0.7 { reset() }
        if let lastTurnAt, timestamp - lastTurnAt > 0.2 { reset() }
        lastTimestamp = timestamp

        guard let extreme else {
            self.extreme = point.x
            minimumY = point.y
            maximumY = point.y
            startedAt = timestamp
            lastTurnAt = timestamp
            return false
        }
        minimumY = min(minimumY, point.y)
        maximumY = max(maximumY, point.y)
        guard maximumY - minimumY <= 30 else {
            reset()
            return false
        }

        let delta = point.x - extreme
        if direction != 0, delta * direction >= 0 {
            self.extreme = point.x
        } else if abs(delta) >= 60 {
            if direction != 0 { reversals += 1 }
            direction = delta > 0 ? 1 : -1
            self.extreme = point.x
            lastTurnAt = timestamp
        }
        guard reversals >= 4 else { return false }
        lastTriggeredAt = timestamp
        reset()
        return true
    }
}
