import CoreGraphics
import Foundation

public struct ContextNoteShakeDetector {
    private var detector = DragShakeDetector()
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
        lastTimestamp = timestamp
        // Match the original horizontal gesture; the held shortcut prevents accidental activation.
        guard detector.record(CGPoint(x: point.x, y: 0), at: timestamp) else { return false }
        lastTriggeredAt = timestamp
        reset()
        return true
    }
}
