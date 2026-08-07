import AppKit
import CoreGraphics

public struct ScreenInsets: Equatable, Sendable {
    public var top: CGFloat
    public var left: CGFloat
    public var bottom: CGFloat
    public var right: CGFloat

    public init(
        top: CGFloat = 0,
        left: CGFloat = 0,
        bottom: CGFloat = 0,
        right: CGFloat = 0
    ) {
        self.top = top
        self.left = left
        self.bottom = bottom
        self.right = right
    }
}

public struct ScreenSnapshot: Equatable, Identifiable, Sendable {
    public let displayID: CGDirectDisplayID
    public var frame: CGRect
    public var visibleFrame: CGRect
    public var safeAreaInsets: ScreenInsets
    public var auxiliaryTopLeftArea: CGRect?
    public var auxiliaryTopRightArea: CGRect?
    /// System menu bar depth used when the screen does not reserve top space.
    public var menuBarHeightFallback: CGFloat

    public var id: CGDirectDisplayID { displayID }

    /// The depth reserved by the current screen's menu bar/top safe area.
    /// `visibleFrame` is the most reliable per-display value; some virtual or
    /// full-screen configurations omit it, so safe-area, auxiliary-region, and
    /// system menu bar values provide conservative fallbacks.
    public var topBarHeight: CGFloat {
        let visibleFrameGap = frame.maxY - visibleFrame.maxY
        if visibleFrameGap > 0 {
            return min(visibleFrameGap, max(0, frame.height))
        }
        if safeAreaInsets.top > 0 {
            return min(safeAreaInsets.top, max(0, frame.height))
        }
        let auxiliaryHeight = max(
            auxiliaryTopLeftArea?.height ?? 0,
            auxiliaryTopRightArea?.height ?? 0
        )
        if auxiliaryHeight > 0 {
            return min(auxiliaryHeight, max(0, frame.height))
        }
        return min(max(0, menuBarHeightFallback), max(0, frame.height))
    }

    public init(
        displayID: CGDirectDisplayID,
        frame: CGRect,
        visibleFrame: CGRect,
        safeAreaInsets: ScreenInsets = ScreenInsets(),
        auxiliaryTopLeftArea: CGRect? = nil,
        auxiliaryTopRightArea: CGRect? = nil,
        menuBarHeightFallback: CGFloat = 0
    ) {
        self.displayID = displayID
        self.frame = frame
        self.visibleFrame = visibleFrame
        self.safeAreaInsets = safeAreaInsets
        self.auxiliaryTopLeftArea = auxiliaryTopLeftArea
        self.auxiliaryTopRightArea = auxiliaryTopRightArea
        self.menuBarHeightFallback = menuBarHeightFallback
    }

    @MainActor
    public init?(screen: NSScreen) {
        let screenNumberKey = NSDeviceDescriptionKey("NSScreenNumber")
        guard let number = screen.deviceDescription[screenNumberKey] as? NSNumber else {
            return nil
        }

        let insets = screen.safeAreaInsets
        self.init(
            displayID: CGDirectDisplayID(number.uint32Value),
            frame: screen.frame,
            visibleFrame: screen.visibleFrame,
            safeAreaInsets: ScreenInsets(
                top: insets.top,
                left: insets.left,
                bottom: insets.bottom,
                right: insets.right
            ),
            auxiliaryTopLeftArea: screen.auxiliaryTopLeftArea,
            auxiliaryTopRightArea: screen.auxiliaryTopRightArea,
            menuBarHeightFallback: max(24, NSStatusBar.system.thickness)
        )
    }
}

public enum TopTopology: Equatable, Sendable {
    case physicalNotch(frame: CGRect)
    case simulated(frame: CGRect)

    public var anchorFrame: CGRect {
        switch self {
        case .physicalNotch(let frame), .simulated(let frame):
            frame
        }
    }

    public var hasPhysicalNotch: Bool {
        if case .physicalNotch = self { return true }
        return false
    }
}

public struct ScreenLayoutConfiguration: Equatable, Sendable {
    /// Width of the simulated island and its fallback height when the menu bar
    /// depth is unavailable.
    public var simulatedIslandSize: CGSize
    public var expandedSize: CGSize
    public var transferDragTriggerSize: CGSize
    public var horizontalMargin: CGFloat
    public var notchTriggerHorizontalPadding: CGFloat

    public init(
        simulatedIslandSize: CGSize = CGSize(width: 240, height: 34),
        expandedSize: CGSize = CGSize(width: 420, height: 180),
        transferDragTriggerSize: CGSize = CGSize(width: 320, height: 48),
        horizontalMargin: CGFloat = 12,
        notchTriggerHorizontalPadding: CGFloat = 24
    ) {
        self.simulatedIslandSize = simulatedIslandSize
        self.expandedSize = expandedSize
        self.transferDragTriggerSize = transferDragTriggerSize
        self.horizontalMargin = horizontalMargin
        self.notchTriggerHorizontalPadding = notchTriggerHorizontalPadding
    }
}

public struct ScreenOverlayLayout: Equatable, Identifiable, Sendable {
    public let displayID: CGDirectDisplayID
    public let screenFrame: CGRect
    public let topology: TopTopology
    public let triggerFrame: CGRect
    public let transferDragTriggerFrame: CGRect
    public let expandedFrame: CGRect

    public var id: CGDirectDisplayID { displayID }
    public var collapsedFrame: CGRect { topology.anchorFrame }

    public func containsTrigger(_ point: CGPoint) -> Bool {
        point.x >= triggerFrame.minX && point.x <= triggerFrame.maxX
            && point.y >= triggerFrame.minY && point.y <= triggerFrame.maxY
    }

    public func containsTransferDragTrigger(_ point: CGPoint) -> Bool {
        point.x >= transferDragTriggerFrame.minX && point.x <= transferDragTriggerFrame.maxX
            && point.y >= transferDragTriggerFrame.minY
            && point.y <= transferDragTriggerFrame.maxY
    }
}

public struct ScreenLayoutEngine: Equatable, Sendable {
    public var configuration: ScreenLayoutConfiguration

    public init(configuration: ScreenLayoutConfiguration = ScreenLayoutConfiguration()) {
        self.configuration = configuration
    }

    public func layouts(for screens: [ScreenSnapshot]) -> [ScreenOverlayLayout] {
        screens.map(layout(for:))
    }

    public func layout(for screen: ScreenSnapshot) -> ScreenOverlayLayout {
        let topology = topology(for: screen)
        let anchor = topology.anchorFrame
        let triggerAnchor: CGRect
        if topology.hasPhysicalNotch {
            // On notched displays, the trigger covers only the notch with horizontal padding for narrow targets.
            let padding = max(0, configuration.notchTriggerHorizontalPadding)
            triggerAnchor = anchor.insetBy(dx: -padding, dy: 0)
                .intersection(screen.frame)
        } else {
            triggerAnchor = anchor
        }
        // Hovering triggers expansion only over the island itself, whether it is a notch or a simulated island.
        let triggerFrame = triggerAnchor

        let margin = min(max(0, configuration.horizontalMargin), screen.frame.width / 2)
        let availableWidth = max(0, screen.frame.width - margin * 2)
        let transferDragWidth = min(
            max(0, configuration.transferDragTriggerSize.width),
            availableWidth
        )
        let transferDragHeight = min(
            max(0, configuration.transferDragTriggerSize.height),
            screen.frame.height
        )
        let minimumMenuBarDepth = max(24, screen.safeAreaInsets.top)
        let menuBarBottom = min(
            screen.visibleFrame.maxY,
            screen.frame.maxY - minimumMenuBarDepth
        )
        let transferDragTriggerFrame = CGRect(
            x: screen.frame.midX - transferDragWidth / 2,
            y: max(screen.frame.minY, menuBarBottom - transferDragHeight),
            width: transferDragWidth,
            height: transferDragHeight
        )
        let expandedWidth = min(max(0, configuration.expandedSize.width), availableWidth)
        let expandedTop = topology.anchorFrame.maxY
        let expandedHeight = min(
            max(0, configuration.expandedSize.height),
            max(0, expandedTop - screen.frame.minY)
        )
        let expandedFrame = CGRect(
            x: screen.frame.midX - expandedWidth / 2,
            y: expandedTop - expandedHeight,
            width: expandedWidth,
            height: expandedHeight
        )

        return ScreenOverlayLayout(
            displayID: screen.displayID,
            screenFrame: screen.frame,
            topology: topology,
            triggerFrame: triggerFrame,
            transferDragTriggerFrame: transferDragTriggerFrame,
            expandedFrame: expandedFrame
        )
    }

    public func layout(
        containing point: CGPoint,
        in layouts: [ScreenOverlayLayout]
    ) -> ScreenOverlayLayout? {
        layouts.first { $0.containsTrigger(point) }
    }

    public func screenLayout(
        containing point: CGPoint,
        in layouts: [ScreenOverlayLayout]
    ) -> ScreenOverlayLayout? {
        layouts.first {
            point.x >= $0.screenFrame.minX && point.x < $0.screenFrame.maxX
                && point.y >= $0.screenFrame.minY && point.y < $0.screenFrame.maxY
        }
    }

    public func transferDragLayout(
        containing point: CGPoint,
        hasSupportedPayload: Bool,
        in layouts: [ScreenOverlayLayout]
    ) -> ScreenOverlayLayout? {
        guard hasSupportedPayload else { return nil }
        return layouts.first { $0.containsTransferDragTrigger(point) }
    }

    private func topology(for screen: ScreenSnapshot) -> TopTopology {
        if let notchFrame = physicalNotchFrame(for: screen) {
            return .physicalNotch(frame: notchFrame)
        }

        let width = min(max(0, configuration.simulatedIslandSize.width), screen.frame.width)
        let preferredHeight = screen.topBarHeight > 0
            ? screen.topBarHeight
            : configuration.simulatedIslandSize.height
        let height = min(max(0, preferredHeight), screen.frame.height)
        // Always bleed into the top edge: the island reads as a notch hanging
        // from the screen frame, not a floating pill dropped below the menu
        // bar. This matches the physical MacBook notch on screens that lack
        // one, and keeps the bar flush even when the menu bar is auto-hidden
        // or the screen does not reserve top space.
        let topEdge = screen.frame.maxY
        return .simulated(
            frame: CGRect(
                x: screen.frame.midX - width / 2,
                y: topEdge - height,
                width: width,
                height: height
            )
        )
    }

    private func physicalNotchFrame(for screen: ScreenSnapshot) -> CGRect? {
        guard screen.safeAreaInsets.top > 0,
            let leftArea = screen.auxiliaryTopLeftArea,
            let rightArea = screen.auxiliaryTopRightArea
        else {
            return nil
        }

        let minX = max(screen.frame.minX, leftArea.maxX)
        let maxX = min(screen.frame.maxX, rightArea.minX)
        guard maxX > minX else { return nil }

        let auxiliaryHeight = min(leftArea.height, rightArea.height)
        let height = min(
            max(screen.topBarHeight, screen.safeAreaInsets.top),
            max(0, auxiliaryHeight)
        )
        guard height > 0 else { return nil }
        let width = maxX - minX
        let centeredX = min(
            max(screen.frame.minX, screen.frame.midX - width / 2),
            screen.frame.maxX - width
        )
        return CGRect(
            x: centeredX,
            y: screen.frame.maxY - height,
            width: width,
            height: height
        )
    }
}
