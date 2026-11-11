import CoreGraphics
import Foundation

enum ScreenshotLongCaptureFrameResult {
    case appended
    case unchanged
    case rejected
}

struct ScreenshotLongCaptureAutoScroll {
    enum Step {
        case scroll
        case capture
        case pause
        case none
    }

    static let settleDelay: TimeInterval = 0.8
    private(set) var isRunning = false
    private(set) var isWaitingForScrolledFrame = false
    private var unsuccessfulCaptures = 0

    mutating func start() {
        isRunning = true
        isWaitingForScrolledFrame = false
        unsuccessfulCaptures = 0
    }

    mutating func stop() {
        isRunning = false
    }

    mutating func nextStep(after result: ScreenshotLongCaptureFrameResult) -> Step {
        guard isRunning else { return .none }
        // The first stationary frame confirms the starting position. After a scroll, only a
        // successful stitch permits another scroll, so a slow repaint cannot leave a gap.
        if result == .appended || (result == .unchanged && !isWaitingForScrolledFrame) {
            unsuccessfulCaptures = 0
            isWaitingForScrolledFrame = true
            return .scroll
        }
        unsuccessfulCaptures += 1
        if unsuccessfulCaptures >= 3 {
            stop()
            return .pause
        }
        return .capture
    }

    static func event(
        selection: CGRect,
        displayBounds: CGRect,
        direction: ScreenshotLongCaptureDirection,
        placement: ScreenshotLongCapturePlacement
    ) -> CGEvent? {
        guard selection.minX.isFinite, selection.minY.isFinite,
              selection.width.isFinite, selection.height.isFinite,
              selection.width >= 2, selection.height >= 2,
              displayBounds.minX.isFinite, displayBounds.minY.isFinite,
              displayBounds.width.isFinite, displayBounds.height.isFinite,
              CGRect(origin: .zero, size: displayBounds.size).contains(selection)
        else { return nil }
        let axisLength = direction == .vertical ? selection.height : selection.width
        let distance = Int32(max(1, min(80, (axisLength * 0.2).rounded(.down))))
        let delta = placement == .append ? -distance : distance
        guard let event = CGEvent(
            scrollWheelEvent2Source: CGEventSource(stateID: .privateState),
            units: .pixel,
            wheelCount: 2,
            wheel1: direction == .vertical ? delta : 0,
            wheel2: direction == .horizontal ? delta : 0,
            wheel3: 0
        ) else { return nil }
        event.location = ScreenshotSnapTargetGeometry.globalPoint(
            CGPoint(x: selection.midX, y: selection.midY),
            in: displayBounds
        )
        return event
    }

    static func post(
        _ event: CGEvent,
        to processIdentifier: pid_t,
        currentProcessIdentifier: pid_t = ProcessInfo.processInfo.processIdentifier,
        hasAccess: () -> Bool = CGPreflightPostEventAccess,
        postEvent: (CGEvent, pid_t) -> Void = { $0.postToPid($1) }
    ) -> Bool {
        guard processIdentifier > 0, processIdentifier != currentProcessIdentifier,
              hasAccess()
        else { return false }
        postEvent(event, processIdentifier)
        return true
    }
}
