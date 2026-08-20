import CoreGraphics
import ZislaCore

public struct SideNoticePresentation: Equatable, Sendable {
    public let activeAICount: Int
    public let activeAINotice: IslandNotice?
    public let activeUpdateNotice: IslandNotice?
    public let activeMediaNotice: IslandNotice?
    public let activeBackgroundSoundNotice: IslandNotice?
    public let activeFocusCountdownNotice: IslandNotice?
    public let activeFocusModeNotice: IslandNotice?
    public let activeTransientNotice: IslandNotice?
    public let activeMailNotice: IslandNotice?
    public let activeToolboxNotice: IslandNotice?
    public let activeBrowserDownloadNotice: IslandNotice?
    public let activeVideoDownloadNotice: IslandNotice?
    public let activeVoiceProcessingNotice: IslandNotice?
    public let ordinaryNotices: [IslandNotice]
    public let panelSize: CGSize
    public let compactWingsEnabled: Bool
    public let compactWingHeight: CGFloat
    public let compactPlaceholder: Bool

    public init(
        activeAICount: Int,
        activeAINotice: IslandNotice? = nil,
        activeUpdateNotice: IslandNotice? = nil,
        activeMediaNotice: IslandNotice? = nil,
        activeBackgroundSoundNotice: IslandNotice? = nil,
        activeFocusCountdownNotice: IslandNotice? = nil,
        activeFocusModeNotice: IslandNotice? = nil,
        activeTransientNotice: IslandNotice? = nil,
        activeMailNotice: IslandNotice? = nil,
        activeToolboxNotice: IslandNotice? = nil,
        activeBrowserDownloadNotice: IslandNotice? = nil,
        activeVideoDownloadNotice: IslandNotice? = nil,
        activeVoiceProcessingNotice: IslandNotice? = nil,
        ordinaryNotices: [IslandNotice],
        panelSize: CGSize,
        compactWingsEnabled: Bool = true,
        compactWingHeight: CGFloat = 34,
        compactPlaceholder: Bool = false
    ) {
        self.activeAICount = activeAICount
        self.activeAINotice = activeAINotice
        self.activeUpdateNotice = activeUpdateNotice
        self.activeMediaNotice = activeMediaNotice
        self.activeBackgroundSoundNotice = activeBackgroundSoundNotice
        self.activeFocusCountdownNotice = activeFocusCountdownNotice
        self.activeFocusModeNotice = activeFocusModeNotice
        self.activeTransientNotice = activeTransientNotice
        self.activeMailNotice = activeMailNotice
        self.activeToolboxNotice = activeToolboxNotice
        self.activeBrowserDownloadNotice = activeBrowserDownloadNotice
        self.activeVideoDownloadNotice = activeVideoDownloadNotice
        self.activeVoiceProcessingNotice = activeVoiceProcessingNotice
        self.ordinaryNotices = ordinaryNotices
        self.panelSize = panelSize
        self.compactWingsEnabled = compactWingsEnabled
        self.compactWingHeight = compactWingHeight
        self.compactPlaceholder = compactPlaceholder
    }

    public var hasCompactContent: Bool {
        activeAICount > 0 || activeMediaNotice != nil || activeBackgroundSoundNotice != nil
            || activeFocusCountdownNotice != nil
            || activeUpdateNotice != nil
            || activeFocusModeNotice != nil || activeTransientNotice != nil
            || activeToolboxNotice != nil
            || activeMailNotice != nil
            || activeBrowserDownloadNotice != nil || activeVideoDownloadNotice != nil
            || activeVoiceProcessingNotice != nil
            || compactPlaceholder
    }

    public var shouldExtendCompactBarForFocusCountdown: Bool {
        activeMediaNotice == nil && activeFocusCountdownNotice != nil
    }

    /// The compact bar renders only one status. Detailed media may widen it only when media wins that priority.
    public var displaysMediaInCompactBar: Bool {
        activeMediaNotice != nil
            && activeVideoDownloadNotice == nil
            && activeBrowserDownloadNotice == nil
            && activeFocusCountdownNotice == nil
            && activeToolboxNotice == nil
            && activeAICount == 0
    }
}

public enum CompactStatusVisibilityPolicy {
    public static func mustRemainVisible(
        notices: [IslandNotice],
        activityDuration: ActivityNoticeDisplayDuration,
        focusDuration: FocusModeNoticeDisplayDuration
    ) -> Bool {
        let hasActivity = notices.contains {
            $0.id.hasPrefix("ai-active-") || $0.id.hasPrefix("media-active-")
                || $0.id.hasPrefix("background-sound-")
        }
        let hasFocusMode = notices.contains { $0.id.hasPrefix("focus-mode-") }
        let hasVoiceProcessing = notices.contains { $0.id.hasPrefix("voice-processing-") }
        return hasVoiceProcessing
            || (hasActivity && activityDuration == .always)
            || (hasFocusMode && focusDuration == .always)
    }
}

public struct CompactBarContourMetrics: Equatable, Sendable {
    public static let maximumTopInset: CGFloat = 14

    public let topInset: CGFloat
    public let bottomInset: CGFloat
    public let bottomRadius: CGFloat
    public let topWidth: CGFloat
    public let bottomWidth: CGFloat

    public init(size: CGSize) {
        let width = max(0, size.width)
        let height = max(0, size.height)
        topInset = min(Self.maximumTopInset, width / 2)
        bottomInset = 0
        // Flat-top Dynamic-Island contour: a straight top edge that bleeds into
        // the screen frame, and bottom corners flared with the same proportion
        // (~40%) as the physical MacBook notch's bottom radius.
        bottomRadius = min(12, height * 0.4)
        topWidth = max(0, width - topInset * 2)
        bottomWidth = width
    }
}

public struct SideNoticeLayoutEngine: Equatable, Sendable {
    public static let compactStatusWingWidth: CGFloat = 40

    private enum Layout {
        static let compactWingWidth = SideNoticeLayoutEngine.compactStatusWingWidth
        /// Countdown expanded bar aligned to the simulated 240 pt island width for notch-less devices,
        /// ensuring `HH:MM:SS` is not squeezed by the notch's corner radii and masks.
        static let compactBarSideExtension: CGFloat = 40
        /// The music detail view needs to fit cover art + title/artist (left) or waveform + scrolling lyrics (right),
        /// requiring wider wings than the countdown expanded bar.
        static let compactBarMediaDetailSideWidth: CGFloat = 160
        /// Notch-less devices render one continuous media row and do not need the physical-notch center gap.
        static let compactBarMediaDetailSimulatedWidth: CGFloat = 380
        static let defaultCompactWingHeight: CGFloat = 34
        static let compactBarNavigationInset: CGFloat = 1
        static let compactOverlap: CGFloat = 0
        static let compactTopOverlap: CGFloat = 0
        static let ordinaryWidth: CGFloat = 252
        static let ordinaryRowHeight: CGFloat = 54
        static let rowSpacing: CGFloat = 6
        static let screenMargin: CGFloat = 8
        static let ordinaryTopGap: CGFloat = 4
    }

    public init() {}

    public func presentation(
        for notices: [IslandNotice],
        compactWingsEnabled: Bool = true,
        compactWingHeight: CGFloat = 34,
        reserveCompactWing: Bool = false
    ) -> SideNoticePresentation {
        let normalizedHeight = max(1, compactWingHeight)
        let activeMediaNotice = compactWingsEnabled
            ? notices.first(where: { $0.id.hasPrefix("media-active-") })
            : nil
        let activeBackgroundSoundNotice = compactWingsEnabled
            ? notices.first(where: { $0.id.hasPrefix("background-sound-") })
            : nil
        let activeFocusCountdownNotice = compactWingsEnabled
            ? notices.first(where: { $0.id.hasPrefix("focus-countdown-") })
            : nil
        let activeFocusModeNotice = compactWingsEnabled
            ? notices.first(where: { $0.id.hasPrefix("focus-mode-") })
            : nil
        let activeTransientNotice = compactWingsEnabled
            ? notices.first(where: { $0.id.hasPrefix("focus-transition") })
            : nil
        let activeMailNotice = compactWingsEnabled
            ? notices.first(where: { $0.id.hasPrefix("mail-notification-") })
            : nil
        let activeAINotices = compactWingsEnabled
            ? notices.filter { $0.id.hasPrefix("ai-active-") }
            : []
        let activeUpdateNotice = compactWingsEnabled
            ? notices.first(where: { $0.id.hasPrefix("update-available-") })
            : nil
        let activeToolboxNotice = compactWingsEnabled
            ? notices.first(where: { $0.id.hasPrefix("toolbox-reminder-") })
            : nil
        let activeBrowserDownloadNotice = compactWingsEnabled
            ? notices.first(where: { $0.id.hasPrefix("browser-download-") })
            : nil
        let activeVideoDownloadNotice = compactWingsEnabled
            ? notices.first(where: { $0.id.hasPrefix("video-download-") })
            : nil
        let activeVoiceProcessingNotice = compactWingsEnabled
            ? notices.first(where: { $0.id.hasPrefix("voice-processing-") })
            : nil
        let activeAICount = activeAINotices.count
        let ordinaryNotices = notices.filter {
            !$0.id.hasPrefix("ai-active-")
                && !$0.id.hasPrefix("update-available-")
                && !$0.id.hasPrefix("media-active-")
                && !$0.id.hasPrefix("background-sound-")
                && !$0.id.hasPrefix("focus-countdown-")
                && !$0.id.hasPrefix("focus-mode-")
                && !$0.id.hasPrefix("focus-transition")
                && !$0.id.hasPrefix("mail-notification-")
                && !$0.id.hasPrefix("toolbox-reminder-")
                && !$0.id.hasPrefix("browser-download-")
                && !$0.id.hasPrefix("video-download-")
                && !$0.id.hasPrefix("voice-processing-")
                && $0.style != .headphone
        }
        let panelSize = panelSize(
            activeAICount: activeAICount,
            hasUpdate: activeUpdateNotice != nil,
            hasMedia: activeMediaNotice != nil,
            hasBackgroundSound: activeBackgroundSoundNotice != nil,
            hasFocusCountdown: activeFocusCountdownNotice != nil,
            hasFocusMode: activeFocusModeNotice != nil,
            hasTransient: activeTransientNotice != nil,
            hasMail: activeMailNotice != nil,
            hasToolbox: activeToolboxNotice != nil,
            hasBrowserDownload: activeBrowserDownloadNotice != nil,
            hasVideoDownload: activeVideoDownloadNotice != nil,
            hasVoiceProcessing: activeVoiceProcessingNotice != nil,
            ordinaryCount: ordinaryNotices.count,
            compactWingHeight: normalizedHeight,
            reserveCompactWing: compactWingsEnabled && reserveCompactWing
        )
        let compactPlaceholder = compactWingsEnabled
            && reserveCompactWing
            && activeAICount == 0
            && activeUpdateNotice == nil
            && activeMediaNotice == nil
            && activeBackgroundSoundNotice == nil
            && activeFocusCountdownNotice == nil
            && activeFocusModeNotice == nil
            && activeTransientNotice == nil
            && activeMailNotice == nil
            && activeToolboxNotice == nil
            && activeBrowserDownloadNotice == nil
            && activeVideoDownloadNotice == nil
            && activeVoiceProcessingNotice == nil
        return SideNoticePresentation(
            activeAICount: activeAICount,
            activeAINotice: activeAINotices.first,
            activeUpdateNotice: activeUpdateNotice,
            activeMediaNotice: activeMediaNotice,
            activeBackgroundSoundNotice: activeBackgroundSoundNotice,
            activeFocusCountdownNotice: activeFocusCountdownNotice,
            activeFocusModeNotice: activeFocusModeNotice,
            activeTransientNotice: activeTransientNotice,
            activeMailNotice: activeMailNotice,
            activeToolboxNotice: activeToolboxNotice,
            activeBrowserDownloadNotice: activeBrowserDownloadNotice,
            activeVideoDownloadNotice: activeVideoDownloadNotice,
            activeVoiceProcessingNotice: activeVoiceProcessingNotice,
            ordinaryNotices: ordinaryNotices,
            panelSize: panelSize,
            compactWingsEnabled: compactWingsEnabled,
            compactWingHeight: normalizedHeight,
            compactPlaceholder: compactPlaceholder
        )
    }

    public func supportsCompactWings(for screen: ScreenSnapshot) -> Bool {
        ScreenLayoutEngine().layout(for: screen).topology.hasPhysicalNotch
    }

    public func compactWingHeight(for screen: ScreenSnapshot) -> CGFloat {
        let layout = ScreenLayoutEngine().layout(for: screen)
        guard layout.topology.hasPhysicalNotch else { return 0 }
        return compactBarHeight(for: screen, anchor: layout.topology.anchorFrame)
    }

    public func compactBarFrame(
        for screen: ScreenSnapshot,
        extendsForFocusCountdown: Bool = false,
        expandsForDetailedMedia: Bool = false
    ) -> CGRect {
        let topology = ScreenLayoutEngine().layout(for: screen).topology
        let anchor = topology.anchorFrame
        let baseWidth: CGFloat
        let height: CGFloat
        if topology.hasPhysicalNotch {
            let visibleWingWidth: CGFloat
            if expandsForDetailedMedia {
                visibleWingWidth = Layout.compactBarMediaDetailSideWidth - Layout.compactOverlap
            } else {
                visibleWingWidth = Layout.compactWingWidth
                    + (extendsForFocusCountdown ? Layout.compactBarSideExtension : 0)
                    - Layout.compactOverlap
            }
            baseWidth = anchor.width + visibleWingWidth * 2
            height = compactBarHeight(for: screen, anchor: anchor)
        } else {
            baseWidth = expandsForDetailedMedia
                ? Layout.compactBarMediaDetailSimulatedWidth
                : anchor.width
            height = anchor.height
        }
        let width = min(screen.frame.width, baseWidth)
        let idealX = anchor.midX - width / 2
        let x = min(max(screen.frame.minX, idealX), screen.frame.maxX - width)
        let topEdge = topology.hasPhysicalNotch ? screen.frame.maxY : anchor.maxY
        return CGRect(
            x: x,
            y: topEdge - height,
            width: width,
            height: height
        )
    }

    public func compactBarFrame(
        for screen: ScreenSnapshot,
        notices: [IslandNotice],
        settings: FeatureSettings
    ) -> CGRect? {
        guard let sizing = compactBarSizing(for: notices, settings: settings) else { return nil }
        return compactBarFrame(
            for: screen,
            extendsForFocusCountdown: sizing.extendsForCompactStatus,
            expandsForDetailedMedia: sizing.expandsForDetailedStatus
        )
    }

    /// Mirrors `compactBarFrame(for: ScreenSnapshot, ...)` for overlays that already own a screen layout.
    public func compactBarFrame(
        for layout: ScreenOverlayLayout,
        extendsForFocusCountdown: Bool = false,
        expandsForDetailedMedia: Bool = false
    ) -> CGRect {
        let anchor = layout.topology.anchorFrame
        let baseWidth: CGFloat
        if layout.topology.hasPhysicalNotch {
            let visibleWingWidth = expandsForDetailedMedia
                ? Layout.compactBarMediaDetailSideWidth - Layout.compactOverlap
                : Layout.compactWingWidth
                    + (extendsForFocusCountdown ? Layout.compactBarSideExtension : 0)
                    - Layout.compactOverlap
            baseWidth = anchor.width + visibleWingWidth * 2
        } else {
            baseWidth = expandsForDetailedMedia
                ? Layout.compactBarMediaDetailSimulatedWidth
                : anchor.width
        }
        let width = min(layout.screenFrame.width, baseWidth)
        let x = min(
            max(layout.screenFrame.minX, anchor.midX - width / 2),
            layout.screenFrame.maxX - width
        )
        let topEdge = layout.topology.hasPhysicalNotch ? layout.screenFrame.maxY : anchor.maxY
        return CGRect(
            x: x,
            y: topEdge - anchor.height,
            width: width,
            height: anchor.height
        )
    }

    public func compactBarFrame(
        for layout: ScreenOverlayLayout,
        notices: [IslandNotice],
        settings: FeatureSettings
    ) -> CGRect? {
        guard let sizing = compactBarSizing(for: notices, settings: settings) else { return nil }
        return compactBarFrame(
            for: layout,
            extendsForFocusCountdown: sizing.extendsForCompactStatus,
            expandsForDetailedMedia: sizing.expandsForDetailedStatus
        )
    }

    private func compactBarSizing(
        for notices: [IslandNotice],
        settings: FeatureSettings
    ) -> (extendsForCompactStatus: Bool, expandsForDetailedStatus: Bool)? {
        if notices.contains(where: { $0.id.hasPrefix("voice-processing-") }) {
            return (false, false)
        }
        let selectedPriority = settings.compactStatusPriority.first {
            Self.compactStatusIsAvailable($0, notices: notices)
        }
        guard let selectedPriority else { return nil }
        let expandsForDetailedStatus = switch selectedPriority {
        case .media:
            settings.mediaCompactStyle == .detailed
                && notices.contains { $0.id.hasPrefix("media-active-") }
        case .mail:
            settings.mailCompactStyle == .detailed
        default:
            false
        }
        return (
            selectedPriority == .transient || selectedPriority == .focusCountdown,
            expandsForDetailedStatus
        )
    }

    private static func compactStatusIsAvailable(
        _ priority: CompactStatusPriority,
        notices: [IslandNotice]
    ) -> Bool {
        return switch priority {
        case .transient:
            notices.contains { $0.id.hasPrefix("focus-transition") || $0.style == .headphone }
        case .updateAvailable:
            notices.contains { $0.id.hasPrefix("update-available-") }
        case .mail:
            notices.contains { $0.id.hasPrefix("mail-notification-") }
        case .videoDownload:
            notices.contains { $0.id.hasPrefix("video-download-") }
        case .browserDownload:
            notices.contains { $0.id.hasPrefix("browser-download-") }
        case .focusCountdown:
            notices.contains { $0.id.hasPrefix("focus-countdown-") }
        case .toolboxReminder:
            notices.contains { $0.id.hasPrefix("toolbox-reminder-") }
        case .aiActivity:
            notices.contains { $0.id.hasPrefix("ai-active-") }
        case .media:
            notices.contains {
                $0.id.hasPrefix("media-active-") || $0.id.hasPrefix("background-sound-")
            }
        case .focusMode:
            notices.contains { $0.id.hasPrefix("focus-mode-") }
        }
    }

    private func compactBarHeight(for screen: ScreenSnapshot, anchor: CGRect) -> CGFloat {
        let navigationBarHeight = max(0, screen.topBarHeight)
        let desiredHeight = max(
            anchor.height,
            navigationBarHeight - Layout.compactBarNavigationInset
        )
        return min(screen.frame.height, desiredHeight)
    }

    public func frame(
        side: NoticeSide,
        presentation: SideNoticePresentation,
        screen: ScreenSnapshot
    ) -> CGRect {
        guard presentation.panelSize != .zero else { return .zero }
        let layout = ScreenLayoutEngine().layout(for: screen)
        let anchor = layout.topology.anchorFrame
        if presentation.hasCompactContent,
           !layout.topology.hasPhysicalNotch,
           presentation.ordinaryNotices.isEmpty {
            return .zero
        }
        let size = presentation.panelSize
        let overlap = presentation.hasCompactContent && layout.topology.hasPhysicalNotch
            ? Layout.compactOverlap
            : 0
        let idealX = side == .left
            ? anchor.minX - size.width + overlap
            : anchor.maxX - overlap
        let minimumX = screen.frame.minX + Layout.screenMargin
        let maximumX = max(minimumX, screen.frame.maxX - size.width - Layout.screenMargin)
        let x = min(max(idealX, minimumX), maximumX)
        let idealY = presentation.hasCompactContent
            ? screen.frame.maxY - size.height + Layout.compactTopOverlap
            : anchor.minY - size.height - Layout.ordinaryTopGap
        let y = max(screen.frame.minY, idealY)

        return CGRect(origin: CGPoint(x: x, y: y), size: size)
    }

    private func panelSize(
        activeAICount: Int,
        hasUpdate: Bool,
        hasMedia: Bool,
        hasBackgroundSound: Bool,
        hasFocusCountdown: Bool,
        hasFocusMode: Bool,
        hasTransient: Bool,
        hasMail: Bool,
        hasToolbox: Bool,
        hasBrowserDownload: Bool,
        hasVideoDownload: Bool,
        hasVoiceProcessing: Bool,
        ordinaryCount: Int,
        compactWingHeight: CGFloat,
        reserveCompactWing: Bool
    ) -> CGSize {
        let hasCompact = activeAICount > 0 || hasUpdate || hasMedia || hasBackgroundSound || hasFocusCountdown || hasFocusMode || hasTransient
            || hasMail || hasToolbox || hasBrowserDownload || hasVideoDownload || hasVoiceProcessing || reserveCompactWing
        guard ordinaryCount > 0 else {
            return hasCompact
                ? CGSize(width: Layout.compactWingWidth, height: compactWingHeight)
                : .zero
        }

        let ordinaryHeight = CGFloat(ordinaryCount) * Layout.ordinaryRowHeight
        let ordinarySpacing = CGFloat(max(0, ordinaryCount - 1)) * Layout.rowSpacing
        let compactHeight = hasCompact ? compactWingHeight + Layout.rowSpacing : 0
        return CGSize(
            width: Layout.ordinaryWidth,
            height: compactHeight + ordinaryHeight + ordinarySpacing
        )
    }
}
