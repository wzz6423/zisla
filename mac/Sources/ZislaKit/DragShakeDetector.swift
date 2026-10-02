import CoreGraphics
import Foundation

public struct DragShakeDetector {
    private var horizontal = Axis()
    private var vertical = Axis()
    private var lastTimestamp: TimeInterval?
    private var hasTriggered = false

    public init() {}

    public mutating func reset() {
        self = Self()
    }

    public mutating func record(_ point: CGPoint, at timestamp: TimeInterval) -> Bool {
        guard !hasTriggered else { return false }
        if let lastTimestamp, timestamp - lastTimestamp > 0.6 {
            horizontal = Axis()
            vertical = Axis()
        }
        lastTimestamp = timestamp
        let horizontalShake = horizontal.record(point.x, at: timestamp)
        let verticalShake = vertical.record(point.y, at: timestamp)
        hasTriggered = horizontalShake || verticalShake
        return hasTriggered
    }

    private struct Axis {
        private var extreme: CGFloat?
        private var direction: CGFloat = 0
        private var reversals: [TimeInterval] = []

        mutating func record(_ value: CGFloat, at timestamp: TimeInterval) -> Bool {
            reversals.removeAll { timestamp - $0 > 0.6 }
            guard let extreme else {
                self.extreme = value
                return false
            }
            let delta = value - extreme
            if direction != 0, delta * direction >= 0 {
                self.extreme = value
            } else if abs(delta) >= 22 {
                if direction != 0 { reversals.append(timestamp) }
                direction = delta > 0 ? 1 : -1
                self.extreme = value
            }
            return reversals.count >= 3
        }
    }
}
