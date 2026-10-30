import AppKit
import CoreGraphics
import ZislaCore

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
    public var layoutStyle: IslandLayoutStyle
    public var placement: IslandPlacement
    public var pillSize: CGSize
    public var edgeInset: CGFloat
    public var expandsForDetailedStatus: Bool
    public var compactStatusLength: CGFloat?

    public init(
        simulatedIslandSize: CGSize = CGSize(width: 240, height: 34),
        expandedSize: CGSize = CGSize(width: 420, height: 180),
        transferDragTriggerSize: CGSize = CGSize(width: 320, height: 48),
        horizontalMargin: CGFloat = 12,
        notchTriggerHorizontalPadding: CGFloat = 24,
        layoutStyle: IslandLayoutStyle = .notch,
        placement: IslandPlacement = IslandPlacement(),
        pillSize: CGSize = CGSize(width: 80, height: 24),
        edgeInset: CGFloat = 8,
        expandsForDetailedStatus: Bool = false,
        compactStatusLength: CGFloat? = nil
    ) {
        self.simulatedIslandSize = simulatedIslandSize
        self.expandedSize = expandedSize
        self.transferDragTriggerSize = transferDragTriggerSize
        self.horizontalMargin = horizontalMargin
        self.notchTriggerHorizontalPadding = notchTriggerHorizontalPadding
        self.layoutStyle = layoutStyle
        self.placement = placement
        self.pillSize = pillSize
        self.edgeInset = edgeInset
        self.expandsForDetailedStatus = expandsForDetailedStatus
        self.compactStatusLength = compactStatusLength
    }
}

public struct ScreenOverlayLayout: Equatable, Identifiable, Sendable {
    public let displayID: CGDirectDisplayID
    public let screenFrame: CGRect
    public let topBarHeight: CGFloat
    public let topology: TopTopology
    public let triggerFrame: CGRect
    public let transferDragTriggerFrame: CGRect
    public let expandedFrame: CGRect
    public let style: IslandLayoutStyle
    public let edge: IslandEdge
    public let physicalOcclusionFrame: CGRect?
    public let placementBounds: CGRect
    public let placementMode: IslandPlacementMode

    public var id: CGDirectDisplayID { displayID }
    public var collapsedFrame: CGRect { topology.anchorFrame }

    public var centerOcclusionWidth: CGFloat {
        guard let physicalOcclusionFrame else { return 0 }
        let intersection = collapsedFrame.intersection(physicalOcclusionFrame)
        return intersection.isEmpty ? 0 : intersection.width
    }

    public var collapsedFrameInExpanded: CGRect {
        collapsedFrame.offsetBy(dx: -expandedFrame.minX, dy: -expandedFrame.minY)
    }

    public var collapsedFrameInExpandedTopLeading: CGRect {
        CGRect(
            x: collapsedFrame.minX - expandedFrame.minX,
            y: expandedFrame.maxY - collapsedFrame.maxY,
            width: collapsedFrame.width,
            height: collapsedFrame.height
        )
    }

    public init(
        displayID: CGDirectDisplayID,
        screenFrame: CGRect,
        topBarHeight: CGFloat,
        topology: TopTopology,
        triggerFrame: CGRect,
        transferDragTriggerFrame: CGRect,
        expandedFrame: CGRect,
        style: IslandLayoutStyle = .notch,
        edge: IslandEdge = .top,
        physicalOcclusionFrame: CGRect? = nil,
        placementBounds: CGRect? = nil,
        placementMode: IslandPlacementMode = .camera
    ) {
        self.displayID = displayID
        self.screenFrame = screenFrame
        self.topBarHeight = topBarHeight
        self.topology = topology
        self.triggerFrame = triggerFrame
        self.transferDragTriggerFrame = transferDragTriggerFrame
        self.expandedFrame = expandedFrame
        self.style = style
        self.edge = edge
        self.physicalOcclusionFrame = physicalOcclusionFrame
            ?? (topology.hasPhysicalNotch ? topology.anchorFrame : nil)
        self.placementBounds = placementBounds ?? screenFrame
        self.placementMode = placementMode
    }

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
        if configuration.layoutStyle == .pill {
            return pillLayout(for: screen)
        }
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
            topBarHeight: screen.topBarHeight,
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

    public func placement(
        nearest point: CGPoint,
        on screen: ScreenSnapshot,
        preferredEdge: IslandEdge = .top
    ) -> IslandPlacement {
        let frame = screen.frame
        let x = min(frame.maxX, max(frame.minX, point.x))
        let y = min(frame.maxY, max(frame.minY, point.y))
        let distances: [(IslandEdge, CGFloat)] = [
            (.top, hypot(point.x - x, point.y - frame.maxY)),
            (.bottom, hypot(point.x - x, point.y - frame.minY)),
            (.left, hypot(point.x - frame.minX, point.y - y)),
            (.right, hypot(point.x - frame.maxX, point.y - y)),
        ]
        let nearestDistance = distances.map(\.1).min()!
        let candidates = distances.filter { abs($0.1 - nearestDistance) < 0.001 }
        let edge = candidates.first { $0.0 == preferredEdge }?.0 ?? candidates[0].0
        let length = edge.isVertical ? frame.height : frame.width
        let position = edge.isVertical ? y - frame.minY : x - frame.minX
        return IslandPlacement(
            mode: .custom,
            edge: edge,
            offset: Double(position / length)
        )
    }

    private func pillLayout(for screen: ScreenSnapshot) -> ScreenOverlayLayout {
        let isCamera = configuration.placement.mode == .camera
        let edge = isCamera ? .top : configuration.placement.edge
        let offset = isCamera ? 0.5 : configuration.placement.offset
        let inset = isCamera ? 2 : finiteNonnegative(configuration.edgeInset, fallback: 8)
        let bounds = screen.frame.insetBy(
            dx: min(inset, screen.frame.width / 2),
            dy: min(inset, screen.frame.height / 2)
        )
        let menuBarHeight = min(screen.frame.height, screen.topBarHeight > 0 ? screen.topBarHeight : 24)
        let occlusion = physicalNotchFrame(for: screen)
        var horizontalSize = CGSize(
            width: finiteNonnegative(configuration.pillSize.width, fallback: 80),
            height: finiteNonnegative(configuration.pillSize.height, fallback: 24)
        )
        if isCamera {
            horizontalSize.height = min(horizontalSize.height, 32, max(0, menuBarHeight - 4))
        }
        let size = CGSize(
            width: min(edge.isVertical ? horizontalSize.height : horizontalSize.width, bounds.width),
            height: min(edge.isVertical ? horizontalSize.width : horizontalSize.height, bounds.height)
        )
        let centerX = screen.frame.minX + screen.frame.width * offset
        let centerY = screen.frame.minY + screen.frame.height * offset
        var anchor = CGRect(
            x: clampedOrigin(centerX - size.width / 2, length: size.width, minimum: bounds.minX, maximum: bounds.maxX),
            y: clampedOrigin(centerY - size.height / 2, length: size.height, minimum: bounds.minY, maximum: bounds.maxY),
            width: size.width,
            height: size.height
        )
        switch edge {
        case .top: anchor.origin.y = bounds.maxY - size.height
        case .bottom: anchor.origin.y = bounds.minY
        case .left: anchor.origin.x = bounds.minX
        case .right: anchor.origin.x = bounds.maxX - size.width
        }

        if isCamera {
            anchor.origin.y = screen.frame.maxY - menuBarHeight / 2 - anchor.height / 2
        }
        anchor = Self.compactPillFrame(
            anchor, edge: edge, bounds: bounds,
            center: edge.isVertical ? centerY : centerX,
            physicalOcclusionFrame: occlusion, placementMode: configuration.placement.mode,
            edgeInset: inset, expandsForDetailedStatus: configuration.expandsForDetailedStatus,
            compactStatusLength: configuration.compactStatusLength
        )

        let transferSize = edge.isVertical
            ? CGSize(width: configuration.transferDragTriggerSize.height, height: configuration.transferDragTriggerSize.width)
            : configuration.transferDragTriggerSize
        var expandedFrame = inwardFrame(size: configuration.expandedSize, from: anchor, edge: edge, in: bounds)
        if edge.isVertical {
            if anchor.midY >= screen.frame.midY {
                expandedFrame.size.height = min(expandedFrame.height, anchor.maxY - bounds.minY)
                expandedFrame.origin.y = anchor.maxY - expandedFrame.height
            } else {
                expandedFrame.size.height = min(expandedFrame.height, bounds.maxY - anchor.minY)
                expandedFrame.origin.y = anchor.minY
            }
        }
        return ScreenOverlayLayout(
            displayID: screen.displayID,
            screenFrame: screen.frame,
            topBarHeight: screen.topBarHeight,
            topology: .simulated(frame: anchor),
            triggerFrame: anchor,
            transferDragTriggerFrame: inwardFrame(size: transferSize, from: anchor, edge: edge, in: bounds),
            expandedFrame: expandedFrame,
            style: .pill,
            edge: edge,
            physicalOcclusionFrame: occlusion,
            placementBounds: bounds,
            placementMode: configuration.placement.mode
        )
    }

    static func compactPillFrame(
        _ initial: CGRect,
        edge: IslandEdge,
        bounds: CGRect,
        center: CGFloat,
        physicalOcclusionFrame: CGRect?,
        placementMode: IslandPlacementMode,
        edgeInset: CGFloat,
        expandsForDetailedStatus: Bool,
        compactStatusLength: CGFloat? = nil
    ) -> CGRect {
        var frame = initial
        let desiredLength: CGFloat?
        if placementMode == .camera, expandsForDetailedStatus {
            desiredLength = max(SideNoticeLayoutEngine.Layout.compactBarMediaDetailSimulatedWidth,
                                (physicalOcclusionFrame?.width ?? 0) + 320)
        } else if placementMode == .camera, compactStatusLength != nil, let physicalOcclusionFrame {
            desiredLength = max(frame.width,
                                physicalOcclusionFrame.width + SideNoticeLayoutEngine.compactStatusWingWidth * 2)
        } else if placementMode == .custom, let compactStatusLength {
            let thickness = edge.isVertical ? frame.width : frame.height
            desiredLength = max(thickness, compactStatusLength)
        } else {
            desiredLength = nil
        }
        if let desiredLength {
            if edge.isVertical {
                let length = min(bounds.height, desiredLength)
                frame.origin.y = min(bounds.maxY - length, max(bounds.minY, center - length / 2))
                frame.size.height = length
            } else {
                let length = min(bounds.width, desiredLength)
                frame.origin.x = min(bounds.maxX - length, max(bounds.minX, center - length / 2))
                frame.size.width = length
            }
        }
        if placementMode == .custom, edge == .top, let physicalOcclusionFrame,
           frame.intersects(physicalOcclusionFrame) {
            // The reserved screen region may cover more than the camera aperture.
            let top = min(bounds.maxY, max(bounds.minY, physicalOcclusionFrame.minY - edgeInset))
            frame.size.height = min(frame.height, top - bounds.minY)
            frame.origin.y = top - frame.height
        }
        return frame
    }

    private func inwardFrame(size: CGSize, from anchor: CGRect, edge: IslandEdge, in bounds: CGRect) -> CGRect {
        let width = min(max(anchor.width, size.width), bounds.width)
        var height = min(max(anchor.height, size.height), bounds.height)
        switch edge {
        case .top: height = min(height, anchor.maxY - bounds.minY)
        case .bottom, .left, .right: break
        }
        var frame = CGRect(
            x: clampedOrigin(anchor.midX - width / 2, length: width, minimum: bounds.minX, maximum: bounds.maxX),
            y: clampedOrigin(anchor.midY - height / 2, length: height, minimum: bounds.minY, maximum: bounds.maxY),
            width: width,
            height: height
        )
        switch edge {
        case .top: frame.origin.y = anchor.maxY - height
        case .bottom: frame.origin.y = anchor.minY
        case .left: frame.origin.x = anchor.minX
        case .right: frame.origin.x = anchor.maxX - width
        }
        return frame
    }

    private func clampedOrigin(_ value: CGFloat, length: CGFloat, minimum: CGFloat, maximum: CGFloat) -> CGFloat {
        min(maximum - length, max(minimum, value))
    }

    private func finiteNonnegative(_ value: CGFloat, fallback: CGFloat) -> CGFloat {
        value.isFinite ? max(0, value) : fallback
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
        guard let leftArea = screen.auxiliaryTopLeftArea,
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
