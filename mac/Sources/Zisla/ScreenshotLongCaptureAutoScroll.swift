import CoreGraphics
import Darwin
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
        unsuccessfulCaptures = 0
    }

    mutating func stop() {
        isRunning = false
    }

    mutating func scrollFailed() {
        isWaitingForScrolledFrame = false
        stop()
    }

    mutating func nextStep(after result: ScreenshotLongCaptureFrameResult) -> Step {
        guard isRunning else {
            if result == .appended { isWaitingForScrolledFrame = false }
            return .none
        }
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
        windowInfo: () -> [[String: Any]]? = {
            CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
                as? [[String: Any]]
        },
        setWindowLocation: (CGEvent, CGPoint) -> Bool = bindWindowLocation,
        postEvent: (CGEvent, pid_t) -> Void = { $0.postToPid($1) }
    ) -> Bool {
        guard processIdentifier > 0, processIdentifier != currentProcessIdentifier,
              hasAccess(),
              let target = targetWindow(at: event.location, processIdentifier: processIdentifier, windows: windowInfo()),
              setWindowLocation(event, CGPoint(
                  x: event.location.x - target.bounds.minX,
                  y: event.location.y - target.bounds.minY
              ))
        else { return false }
        // Direct process posting bypasses WindowServer's window hit test. AppKit otherwise
        // receives window 0 and cannot route the wheel event to the selected scroll view.
        event.setIntegerValueField(CGEventField(rawValue: 51)!, value: target.number)
        postEvent(event, processIdentifier)
        return true
    }

    static func targetWindow(
        at point: CGPoint, processIdentifier: pid_t, windows: [[String: Any]]?
    ) -> (number: Int64, bounds: CGRect)? {
        for window in windows ?? [] {
            guard (window[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value == processIdentifier,
                  (window[kCGWindowLayer as String] as? NSNumber)?.intValue == 0,
                  let alpha = window[kCGWindowAlpha as String] as? NSNumber, alpha.doubleValue > 0.01,
                  let number = window[kCGWindowNumber as String] as? NSNumber, number.int64Value > 0,
                  let dictionary = window[kCGWindowBounds as String] as? NSDictionary,
                  let bounds = CGRect(dictionaryRepresentation: dictionary as CFDictionary),
                  bounds.contains(point)
            else { continue }
            return (number.int64Value, bounds)
        }
        return nil
    }

    private static func bindWindowLocation(_ event: CGEvent, _ point: CGPoint) -> Bool {
        guard let handle = dlopen(nil, RTLD_LAZY) else { return false }
        defer { dlclose(handle) }
        guard let symbol = dlsym(handle, "CGEventSetWindowLocation") else { return false }
        // This window-relative coordinate is separate from CGEvent.location. The latter
        // must stay in global display coordinates for WebKit and display routing.
        typealias Setter = @convention(c) (CGEvent, CGPoint) -> Void
        unsafeBitCast(symbol, to: Setter.self)(event, point)
        return true
    }
}
