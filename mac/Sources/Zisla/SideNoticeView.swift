import AppKit
import QuartzCore
import ZislaCore
import ZislaKit
import SwiftUI

@MainActor
final class SideNoticeDisplayState: ObservableObject {
    @Published var compactWingsEnabled = true
    @Published var compactWingHeight: CGFloat = 34
    @Published var reserveCompactWing = false
    @Published var compactStatusHidden = false
    var compactStatusIDs: Set<String> = []
    /// Physical notch width; the detailed music layout must leave a gap here in the center. 0 on simulated-island devices.
    @Published var compactBarCenterInset: CGFloat = 0
    /// Voice-processing status is scoped to the display where the recording happened; every
    /// other display hides it so the collapsed pill (and the pet slot) stays in its normal place.
    @Published var hidesVoiceProcessingIndicator = false
}

private enum CompactStatusMetrics {
    static let wingWidth: CGFloat = 40
    static let horizontalContentInset: CGFloat = 5
}

private struct CompactNotchBackground: View {
    var style: IslandNotchBackground

    @ViewBuilder
    var body: some View {
        switch style {
        case .black:
            Color.black
        case .frosted:
            VisualEffectBackground(alphaValue: 0.92, material: .popover)
        }
    }
}

struct SideNoticeRootView: View {
    @ObservedObject var queue: SideNoticeQueue
    @ObservedObject var displayState: SideNoticeDisplayState
    var side: NoticeSide

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let presentation = SideNoticeLayoutEngine().presentation(
            for: notices,
            compactWingsEnabled: displayState.compactWingsEnabled,
            compactWingHeight: displayState.compactWingHeight,
            reserveCompactWing: displayState.reserveCompactWing
        )
        let activeAINotices = displayState.compactWingsEnabled ? compactAINotices : []

        VStack(alignment: side == .left ? .trailing : .leading, spacing: 6) {
            if let voiceProcessingNotice = presentation.activeVoiceProcessingNotice {
                CompactVoiceProcessingWing(
                    notice: voiceProcessingNotice,
                    side: side,
                    height: presentation.compactWingHeight
                )
                .transition(reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.82)))
            } else if let mediaNotice = presentation.activeMediaNotice {
                CompactMediaWing(
                    notice: mediaNotice,
                    side: side,
                    height: presentation.compactWingHeight
                )
                    .transition(reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.82)))
            } else if let backgroundSoundNotice = presentation.activeBackgroundSoundNotice {
                CompactBackgroundSoundWing(
                    notice: backgroundSoundNotice,
                    side: side,
                    height: presentation.compactWingHeight
                )
                .transition(reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.82)))
            } else if let focusCountdownNotice = presentation.activeFocusCountdownNotice {
                CompactFocusCountdownWing(
                    notice: focusCountdownNotice,
                    side: side,
                    height: presentation.compactWingHeight
                )
                .transition(reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.82)))
            } else if let focusModeNotice = presentation.activeFocusModeNotice {
                CompactFocusModeWing(
                    notice: focusModeNotice,
                    side: side,
                    height: presentation.compactWingHeight
                )
                .transition(reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.82)))
            } else if let transientNotice = presentation.activeTransientNotice {
                CompactTransientWing(
                    notice: transientNotice,
                    side: side,
                    height: presentation.compactWingHeight
                )
                .transition(reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.82)))
            } else if let toolboxNotice = presentation.activeToolboxNotice {
                CompactToolboxWing(
                    notice: toolboxNotice,
                    side: side,
                    height: presentation.compactWingHeight
                )
                .transition(reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.82)))
            } else if !activeAINotices.isEmpty {
                CompactAIWing(
                    notices: activeAINotices,
                    count: activeAINotices.count,
                    side: side,
                    height: presentation.compactWingHeight,
                    role: side == .left ? .identity : .status
                )
                .transition(reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.82)))
            } else if presentation.compactPlaceholder {
                CompactPlaceholderWing(
                    side: side,
                    height: presentation.compactWingHeight
                )
                .transition(reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.82)))
            }

            ForEach(presentation.ordinaryNotices) { notice in
                NoticeRow(notice: notice, side: side) {
                    queue.remove(id: notice.id)
                }
                .onHover { queue.setHovered($0, id: notice.id) }
                .transition(
                    reduceMotion
                        ? .opacity
                        : .move(edge: side == .left ? .leading : .trailing)
                            .combined(with: .opacity)
                )
            }
        }
        .frame(
            width: presentation.panelSize.width,
            height: presentation.panelSize.height,
            alignment: side == .left ? .topTrailing : .topLeading
        )
        .environment(\.colorScheme, .dark)
        .animation(reduceMotion ? nil : .snappy(duration: 0.22), value: presentation)
    }

    private var notices: [IslandNotice] {
        let own = side == .left ? queue.left : queue.right
        return displayState.hidesVoiceProcessingIndicator
            ? own.filter { !$0.id.hasPrefix("voice-processing-") }
            : own
    }

    private var compactMediaNotice: IslandNotice? {
        let own = side == .left ? queue.left : queue.right
        let opposite = side == .left ? queue.right : queue.left
        return (own + opposite).first { $0.id.hasPrefix("media-active-") }
    }

    private var compactAINotices: [IslandNotice] {
        (queue.left + queue.right)
            .filter { $0.id.hasPrefix("ai-active-") }
            .sorted { $0.createdAt > $1.createdAt }
    }
}

struct CompactStatusBarView: View {
    @ObservedObject var queue: SideNoticeQueue
    @ObservedObject var displayState: SideNoticeDisplayState
    @ObservedObject var media: NowPlayingService
    @ObservedObject var browserDownloads: BrowserDownloadMonitor
    @ObservedObject var settingsStore: FeatureSettingsStore
    var onStatusHidden: () -> Void

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    private var height: CGFloat { displayState.compactWingHeight }

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                if !displayState.compactStatusHidden {
                    compactStatusContent
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
            .background(compactStatusBackground)
            .clipShape(SimulatedIslandShape())
            .contentShape(SimulatedIslandShape())
            // NSHostingView's safe area can push the SwiftUI content down by a few
            // points when the panel sits under the physical notch or the auto-hide
            // menu bar. Ignoring the top safe area keeps the bar flush with the
            // panel's top edge (which itself is anchored to screen.frame.maxY).
            .ignoresSafeArea(edges: .top)
            .environment(\.colorScheme, .dark)
            .simultaneousGesture(
                DragGesture(minimumDistance: CompactStatusBarSwipeRecognizer.minimumDistance)
                    .onEnded { gesture in
                        guard CompactStatusBarSwipeRecognizer.hidesStatusContent(
                            startLocation: gesture.startLocation,
                            translation: gesture.translation,
                            containerWidth: geometry.size.width
                        ) else { return }
                        displayState.compactStatusHidden = true
                        onStatusHidden()
                    }
            )
        }
    }

    @ViewBuilder
    private var compactStatusBackground: some View {
        if reduceTransparency {
            Color.black
        } else {
            CompactNotchBackground(style: settingsStore.settings.islandNotchBackground)
        }
    }

    private var compactWingsUseTransparentBackground: Bool {
        settingsStore.settings.islandNotchBackground != .black && !reduceTransparency
    }

    private var mediaNotice: IslandNotice? {
        (queue.left + queue.right).first { $0.id.hasPrefix("media-active-") }
    }

    private var backgroundSoundNotice: IslandNotice? {
        (queue.left + queue.right).first { $0.id.hasPrefix("background-sound-") }
    }

    private var transientNotice: IslandNotice? {
        (queue.left + queue.right)
            .filter { $0.id.hasPrefix("focus-transition") || $0.style == .headphone }
            .max { $0.createdAt < $1.createdAt }
    }

    /// Detailed mode needs a live snapshot (lyrics advance with playback); the notice strip only carries a static cover and title.
    private var detailedMediaItem: NowPlayingSnapshot? {
        guard settingsStore.settings.mediaCompactStyle == .detailed,
              mediaNotice != nil,
              let snapshot = media.snapshot,
              snapshot.isPlaying
        else { return nil }
        return snapshot
    }

    private var toolboxNotice: IslandNotice? {
        (queue.left + queue.right).first { $0.id.hasPrefix("toolbox-reminder-") }
    }

    private var browserDownloadNotice: IslandNotice? {
        (queue.left + queue.right).first { $0.id.hasPrefix("browser-download-") }
    }

    private var videoDownloadNotice: IslandNotice? {
        (queue.left + queue.right).first { $0.id.hasPrefix("video-download-") }
    }

    private var focusCountdownNotice: IslandNotice? {
        (queue.left + queue.right).first { $0.id.hasPrefix("focus-countdown-") }
    }

    private var focusModeNotice: IslandNotice? {
        (queue.left + queue.right).first { $0.id.hasPrefix("focus-mode-") }
    }

    private var mailNotices: [IslandNotice] {
        (queue.left + queue.right)
            .filter { $0.id.hasPrefix("mail-notification-") }
    }

    private var mailLeftNotice: IslandNotice? {
        mailNotices.first { $0.side == .left }
    }

    private var mailRightNotice: IslandNotice? {
        mailNotices.first { $0.side == .right }
    }

    private var activeAINotices: [IslandNotice] {
        (queue.left + queue.right)
            .filter { $0.id.hasPrefix("ai-active-") }
            .sorted { $0.createdAt > $1.createdAt }
    }

    private var voiceProcessingNotice: IslandNotice? {
        guard !displayState.hidesVoiceProcessingIndicator else { return nil }
        return (queue.left + queue.right).first { $0.id.hasPrefix("voice-processing-") }
    }

    private var updateNotice: IslandNotice? {
        (queue.left + queue.right).first { $0.id.hasPrefix("update-available-") }
    }

    private var selectedCompactStatusPriority: CompactStatusPriority? {
        settingsStore.settings.compactStatusPriority.first(where: compactStatusIsAvailable)
    }

    private func compactStatusIsAvailable(_ priority: CompactStatusPriority) -> Bool {
        switch priority {
        case .transient: transientNotice != nil
        case .updateAvailable: updateNotice != nil
        case .mail: !mailNotices.isEmpty
        case .videoDownload: videoDownloadNotice != nil
        case .browserDownload: browserDownloadNotice != nil
        case .focusCountdown: focusCountdownNotice != nil
        case .toolboxReminder: toolboxNotice != nil
        case .aiActivity: !activeAINotices.isEmpty
        case .media: mediaNotice != nil || backgroundSoundNotice != nil
        case .focusMode: focusModeNotice != nil
        }
    }

    @ViewBuilder
    private var compactStatusContent: some View {
        // Voice processing is a short, user-initiated status; it takes precedence over the configured priority list.
        if let voiceProcessingNotice {
            HStack(spacing: 0) {
                CompactVoiceProcessingWing(
                    notice: voiceProcessingNotice,
                    side: .left,
                    height: height,
                    usesTransparentBackground: compactWingsUseTransparentBackground
                )
                Spacer(minLength: 0)
                CompactVoiceProcessingWing(
                    notice: voiceProcessingNotice,
                    side: .right,
                    height: height,
                    usesTransparentBackground: compactWingsUseTransparentBackground
                )
            }
        } else {
            configuredCompactStatusContent
        }
    }

    @ViewBuilder
    private var configuredCompactStatusContent: some View {
        switch selectedCompactStatusPriority {
        case .transient:
            if let transientNotice {
                if transientNotice.style == .headphone {
                    CompactHeadphoneConnectionBar(notice: transientNotice, height: height)
                } else {
                    CompactFocusTransitionBar(notice: transientNotice, height: height)
                }
            }
        case .updateAvailable:
            if let updateNotice {
                HStack(spacing: 0) {
                    CompactUpdateWing(
                        notice: updateNotice,
                        side: .left,
                        height: height,
                        usesTransparentBackground: compactWingsUseTransparentBackground
                    )
                    Spacer(minLength: 0)
                    CompactUpdateWing(
                        notice: updateNotice,
                        side: .right,
                        height: height,
                        usesTransparentBackground: compactWingsUseTransparentBackground
                    )
                }
            }
        case .mail:
            if let resolvedLeftNotice = mailLeftNotice ?? mailRightNotice {
                let resolvedRightNotice = mailRightNotice ?? resolvedLeftNotice
                if settingsStore.settings.mailCompactStyle == .detailed {
                    DetailedMailBar(
                        leftNotice: resolvedLeftNotice,
                        rightNotice: resolvedRightNotice,
                        height: height,
                        centerInset: displayState.compactBarCenterInset
                    )
                } else {
                    HStack(spacing: 0) {
                        CompactMailWing(
                            notice: resolvedLeftNotice,
                            side: .left,
                            height: height,
                            usesTransparentBackground: compactWingsUseTransparentBackground
                        )
                        Spacer(minLength: 0)
                        CompactMailWing(
                            notice: resolvedRightNotice,
                            side: .right,
                            height: height,
                            usesTransparentBackground: compactWingsUseTransparentBackground
                        )
                    }
                }
            }
        case .videoDownload:
            if let videoDownloadNotice {
                HStack(spacing: 0) {
                    CompactVideoDownloadWing(
                        notice: videoDownloadNotice,
                        side: .left,
                        height: height,
                        usesTransparentBackground: compactWingsUseTransparentBackground
                    )
                    Spacer(minLength: 0)
                    CompactVideoDownloadWing(
                        notice: videoDownloadNotice,
                        side: .right,
                        height: height,
                        usesTransparentBackground: compactWingsUseTransparentBackground
                    )
                }
            }
        case .browserDownload:
            if let browserDownloadNotice {
                HStack(spacing: 0) {
                    CompactBrowserDownloadWing(
                        notice: browserDownloadNotice,
                        snapshots: browserDownloads.snapshots,
                        uniqueAgents: browserDownloads.uniqueAgents,
                        side: .left,
                        height: height,
                        usesTransparentBackground: compactWingsUseTransparentBackground
                    )
                    Spacer(minLength: 0)
                    CompactBrowserDownloadWing(
                        notice: browserDownloadNotice,
                        snapshots: browserDownloads.snapshots,
                        uniqueAgents: browserDownloads.uniqueAgents,
                        side: .right,
                        height: height,
                        usesTransparentBackground: compactWingsUseTransparentBackground
                    )
                }
            }
        case .focusCountdown:
            if let focusCountdownNotice {
                CompactFocusCountdownBar(notice: focusCountdownNotice, height: height)
            }
        case .toolboxReminder:
            if let toolboxNotice {
                HStack(spacing: 0) {
                    CompactToolboxWing(
                        notice: toolboxNotice,
                        side: .left,
                        height: height,
                        usesTransparentBackground: compactWingsUseTransparentBackground
                    )
                    Spacer(minLength: 0)
                    CompactToolboxWing(
                        notice: toolboxNotice,
                        side: .right,
                        height: height,
                        usesTransparentBackground: compactWingsUseTransparentBackground
                    )
                }
            }
        case .aiActivity:
            if !activeAINotices.isEmpty {
                HStack(spacing: 0) {
                    CompactAIWing(
                        notices: activeAINotices,
                        count: activeAINotices.count,
                        side: .left,
                        height: height,
                        role: .identity,
                        usesTransparentBackground: compactWingsUseTransparentBackground
                    )
                    Spacer(minLength: 0)
                    CompactAIWing(
                        notices: activeAINotices,
                        count: activeAINotices.count,
                        side: .right,
                        height: height,
                        role: .status,
                        usesTransparentBackground: compactWingsUseTransparentBackground
                    )
                }
            }
        case .media:
            if let mediaNotice {
                if let item = detailedMediaItem {
                    DetailedMediaBar(
                        item: item,
                        lyrics: item.lyrics ?? media.resolvedLyrics,
                        height: height,
                        centerInset: displayState.compactBarCenterInset
                    )
                } else {
                    HStack(spacing: 0) {
                        CompactMediaWing(
                            notice: mediaNotice,
                            side: .left,
                            height: height,
                            usesTransparentBackground: compactWingsUseTransparentBackground
                        )
                        Spacer(minLength: 0)
                        CompactMediaWing(
                            notice: mediaNotice,
                            side: .right,
                            height: height,
                            usesTransparentBackground: compactWingsUseTransparentBackground
                        )
                    }
                }
            } else if let backgroundSoundNotice {
                HStack(spacing: 0) {
                    CompactBackgroundSoundWing(
                        notice: backgroundSoundNotice,
                        side: .left,
                        height: height,
                        usesTransparentBackground: compactWingsUseTransparentBackground
                    )
                    Spacer(minLength: 0)
                    CompactBackgroundSoundWing(
                        notice: backgroundSoundNotice,
                        side: .right,
                        height: height,
                        usesTransparentBackground: compactWingsUseTransparentBackground
                    )
                }
            }
        case .focusMode:
            if let focusModeNotice {
                HStack(spacing: 0) {
                    CompactFocusModeWing(
                        notice: focusModeNotice,
                        side: .left,
                        height: height,
                        usesTransparentBackground: compactWingsUseTransparentBackground
                    )
                    Spacer(minLength: 0)
                    CompactFocusModeWing(
                        notice: focusModeNotice,
                        side: .right,
                        height: height,
                        usesTransparentBackground: compactWingsUseTransparentBackground
                    )
                }
            }
        case nil:
            EmptyView()
        }
    }
}

private struct NoticeRow: View {
    var notice: IslandNotice
    var side: NoticeSide
    var onDismiss: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var isMessage: Bool { notice.style == .message }
    private var isStatus: Bool { notice.style == .status }
    private var isHeadphone: Bool { notice.style == .headphone }

    var body: some View {
        Group {
            if isMessage {
                messageBody
            } else if isStatus {
                statusBody
            } else if isHeadphone {
                HeadphoneConnectionNotice(notice: notice, onDismiss: onDismiss)
            } else {
                standardBody
            }
        }
        .padding(.horizontal, 11)
        .frame(width: 252, height: 54)
        .background(.regularMaterial, in: NoticeWingShape(side: side))
        .overlay {
            NoticeWingShape(side: side)
                .strokeBorder(color.opacity(0.3), lineWidth: 1)
        }
        .contentShape(NoticeWingShape(side: side))
    }

    @ViewBuilder
    private var statusBody: some View {
        if notice.side == .left {
            HStack(spacing: 9) {
                Image(systemName: symbol)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(color)
                    .frame(width: 24)

                Text(notice.title)
                    .font(.system(size: 11, weight: .semibold))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .minimumScaleFactor(0.86)
                    .layoutPriority(1)

                Spacer(minLength: 2)
                dismissButton
            }
        } else {
            HStack(spacing: 8) {
                Text(notice.title)
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(.green)
                    .monospaced()

                Spacer(minLength: 2)
                dismissButton
            }
        }
    }

    private var standardBody: some View {
        HStack(spacing: 9) {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(color)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(notice.title)
                    .font(.system(size: 11, weight: .semibold))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .minimumScaleFactor(0.86)

                if let detail = notice.detail, !detail.isEmpty {
                    Text(detail)
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .truncationMode(.tail)
                }
            }
            .layoutPriority(1)

            Spacer(minLength: 2)

            dismissButton
        }
    }

    @ViewBuilder
    private var messageBody: some View {
        if notice.side == .left {
            HStack(spacing: 9) {
                MessageAppIcon(bundleIdentifier: notice.appBundleIdentifier)
                    .frame(width: 28, height: 28)

                VStack(alignment: .leading, spacing: 2) {
                    Text(notice.title)
                        .font(.system(size: 11, weight: .semibold))
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .minimumScaleFactor(0.86)

                    if let appName = notice.appName ?? notice.detail, !appName.isEmpty {
                        Text(appName)
                            .font(.system(size: 9))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                }
                .layoutPriority(1)

                Spacer(minLength: 2)
                dismissButton
            }
        } else {
            HStack(spacing: 8) {
                MessageScrollingText(
                    text: notice.title,
                    reduceMotion: reduceMotion
                )
                .frame(maxWidth: .infinity, alignment: .leading)
                .clipped()

                dismissButton
            }
        }
    }

    private var dismissButton: some View {
        Button(action: onDismiss) {
            Image(systemName: "xmark")
                .font(.system(size: 9, weight: .bold))
                .frame(width: 24, height: 24)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
        .help("关闭")
    }

    private var symbol: String {
        if let symbolName = notice.symbolName, !symbolName.isEmpty { return symbolName }
        return switch notice.kind {
        case .info: "info.circle.fill"
        case .success: "checkmark.circle.fill"
        case .warning: "exclamationmark.triangle.fill"
        case .error: "xmark.octagon.fill"
        }
    }

    private var color: Color {
        if isMessage { return .blue }
        if isStatus { return notice.side == .right ? .green : .indigo }
        return switch notice.kind {
        case .info: .cyan
        case .success: .green
        case .warning: .orange
        case .error: .red
        }
    }
}

private struct HeadphoneConnectionNotice: View {
    var notice: IslandNotice
    var onDismiss: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isPresented = false

    var body: some View {
        HStack(spacing: 9) {
            HeadphonePairGlyph(isPresented: isPresented)
                .frame(width: 42, height: 34)

            VStack(alignment: .leading, spacing: 2) {
                Text(notice.title)
                    .font(.system(size: 11, weight: .semibold))
                    .lineLimit(1)
                    .truncationMode(.tail)
                Text(notice.detail ?? "已连接")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            .frame(minWidth: 54, maxWidth: .infinity, alignment: .leading)

            HeadphoneBatteryLevels(levels: notice.batteryLevels ?? [])

            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .bold))
                    .frame(width: 20, height: 24)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help("关闭")
        }
        .onAppear {
            guard !reduceMotion else {
                isPresented = true
                return
            }
            withAnimation(.spring(response: 0.38, dampingFraction: 0.72)) {
                isPresented = true
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(accessibilityDescription))
    }

    private var accessibilityDescription: String {
        let batteries = (notice.batteryLevels ?? []).map { level in
            "\(level.label)耳\(level.level.map { "\($0)%" } ?? "电量未知")"
        }
        return (["\(notice.title)已连接"] + batteries).joined(separator: "，")
    }
}

private struct HeadphonePairGlyph: View {
    var isPresented: Bool

    var body: some View {
        ZStack {
            Image(systemName: "airpod.left")
                .offset(x: -9, y: isPresented ? -1 : 5)
                .opacity(isPresented ? 1 : 0)
                .scaleEffect(isPresented ? 1 : 0.64)
            Image(systemName: "airpod.right")
                .offset(x: 9, y: isPresented ? 1 : -5)
                .opacity(isPresented ? 1 : 0)
                .scaleEffect(isPresented ? 1 : 0.64)
        }
        .font(.system(size: 25, weight: .medium))
        .foregroundStyle(.white)
        .shadow(color: .cyan.opacity(0.22), radius: 5, y: 1)
    }
}

private struct HeadphoneBatteryLevels: View {
    var levels: [NoticeBatteryLevel]

    var body: some View {
        HStack(spacing: 4) {
            ForEach(displayedLevels) { level in
                HeadphoneBatteryRing(level: level)
            }
        }
        .frame(width: 64, alignment: .trailing)
    }

    private var displayedLevels: [NoticeBatteryLevel] {
        let defaults = [
            NoticeBatteryLevel(label: "左", level: nil),
            NoticeBatteryLevel(label: "右", level: nil),
        ]
        return levels.isEmpty ? defaults : Array(levels.prefix(3))
    }
}

private struct HeadphoneBatteryRing: View {
    var level: NoticeBatteryLevel

    var body: some View {
        VStack(spacing: 2) {
            ZStack {
                Circle()
                    .stroke(Color.white.opacity(0.14), lineWidth: 2)
                if let level = level.level {
                    Circle()
                        .trim(from: 0, to: CGFloat(level) / 100)
                        .stroke(fillColor, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                }
                Text(level.level.map(String.init) ?? "--")
                    .font(.system(size: 7, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.white.opacity(level.level == nil ? 0.42 : 0.9))
            }
            .frame(width: 20, height: 20)
            Text(level.label)
                .font(.system(size: 7, weight: .medium))
                .foregroundStyle(.secondary)
        }
        .frame(width: 20)
    }

    private var fillColor: Color {
        guard let level = level.level else { return .clear }
        if level <= 15 { return .red }
        if level <= 35 { return .orange }
        return .green
    }
}

private struct CompactHeadphoneConnectionBar: View {
    var notice: IslandNotice
    var height: CGFloat

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isPresented = false

    var body: some View {
        HStack(spacing: 8) {
            HeadphonePairGlyph(isPresented: isPresented)
                .frame(width: 42, height: height)

            VStack(alignment: .leading, spacing: 1) {
                Text(notice.title)
                    .font(.system(size: 10, weight: .semibold))
                    .lineLimit(1)
                    .truncationMode(.tail)
                Text(notice.detail ?? "已连接")
                    .font(.system(size: 8, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            .frame(minWidth: 42, maxWidth: .infinity, alignment: .leading)

            HeadphoneBatteryLevels(levels: notice.batteryLevels ?? [])
        }
        .padding(.horizontal, 10)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            guard !reduceMotion else {
                isPresented = true
                return
            }
            withAnimation(.spring(response: 0.38, dampingFraction: 0.72)) {
                isPresented = true
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("耳机已连接：\(notice.title)"))
    }
}

private struct CompactFocusTransitionBar: View {
    var notice: IslandNotice
    var height: CGFloat

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: notice.symbolName ?? "moon.fill")
                .font(.system(size: min(15, height * 0.56), weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 1) {
                Text(notice.title)
                    .font(.system(size: 10, weight: .semibold))
                    .lineLimit(1)
                Text(notice.detail ?? "状态已更新")
                    .font(.system(size: 8, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Text(notice.kind == .success ? "ON" : "OFF")
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .monospaced()
                .foregroundStyle(notice.kind == .success ? .green : .secondary)
        }
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("\(notice.title)\(notice.detail ?? "状态已更新")"))
    }
}

private struct MessageAppIcon: View {
    var bundleIdentifier: String?

    var body: some View {
        Group {
            if let image = resolvedIcon {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fill)
            } else {
                Image(systemName: "message.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.blue)
            }
        }
        .frame(width: 28, height: 28)
        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
    }

    private var resolvedIcon: NSImage? {
        guard let bundleIdentifier, !bundleIdentifier.isEmpty,
              let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) else {
            return nil
        }
        return NSWorkspace.shared.icon(forFile: url.path)
    }
}

private struct MessageScrollingText: View {
    var text: String
    var reduceMotion: Bool

    @State private var textWidth: CGFloat = 0
    @State private var containerWidth: CGFloat = 0
    @State private var offset: CGFloat = 0

    var body: some View {
        GeometryReader { geo in
            let available = geo.size.width
            Group {
                if reduceMotion {
                    Text(text)
                        .font(.system(size: 11, weight: .medium))
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .frame(width: available, alignment: .leading)
                } else {
                    Text(text)
                        .font(.system(size: 11, weight: .medium))
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                        .background(
                            GeometryReader { textGeo in
                                Color.clear.preference(key: MessageTextWidthKey.self, value: textGeo.size.width)
                            }
                        )
                        .offset(x: textWidth <= available ? 0 : offset)
                        .frame(width: available, alignment: .leading)
                        .clipped()
                }
            }
            .frame(width: available, height: geo.size.height, alignment: .leading)
            .clipped()
            .onAppear {
                containerWidth = available
                startScrollIfNeeded()
            }
            .onChange(of: available) { _, newValue in
                containerWidth = newValue
                startScrollIfNeeded()
            }
            .onPreferenceChange(MessageTextWidthKey.self) { width in
                textWidth = width
                startScrollIfNeeded()
            }
        }
        .frame(height: 20)
        .clipped()
        .mask(
            LinearGradient(
                stops: [
                    .init(color: .clear, location: 0),
                    .init(color: .black, location: 0.04),
                    .init(color: .black, location: 0.96),
                    .init(color: .clear, location: 1),
                ],
                startPoint: .leading,
                endPoint: .trailing
            )
        )
    }

    private func startScrollIfNeeded() {
        guard !reduceMotion, textWidth > containerWidth, containerWidth > 0 else {
            offset = 0
            return
        }
        let travel = textWidth - containerWidth + 16
        offset = 0
        withAnimation(.linear(duration: max(3, Double(travel) / 90)).repeatForever(autoreverses: true)) {
            offset = -travel
        }
    }
}

private struct MessageTextWidthKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

private enum CompactAIWingRole {
    case identity
    case status
}

/// Collapsed-island wings shown while an AI model cleans up a recorded transcript:
/// the left wing carries a microphone glyph, the right wing one of the nine thinking-orb
/// animations (picked at random when processing starts).
private struct CompactVoiceProcessingWing: View {
    var notice: IslandNotice
    var side: NoticeSide
    var height: CGFloat
    var usesTransparentBackground = false

    private var orbState: ThinkingOrbState {
        ThinkingOrbState(rawValue: notice.metadata?["orbState"] ?? "") ?? .working
    }

    var body: some View {
        Group {
            if side == .left {
                Image(systemName: "mic.fill")
                    .font(.system(size: min(13, height * 0.44), weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.leading, CompactStatusMetrics.horizontalContentInset + 2)
                    .frame(
                        width: CompactStatusMetrics.wingWidth,
                        height: height,
                        alignment: .leading
                    )
            } else {
                ThinkingOrbView(
                    state: orbState,
                    size: min(22, height * 0.72),
                    tint: .white,
                    accessibilityLabel: "正在整理语音"
                )
                .padding(.trailing, CompactStatusMetrics.horizontalContentInset + 2)
                .frame(
                    width: CompactStatusMetrics.wingWidth,
                    height: height,
                    alignment: .trailing
                )
            }
        }
        .background(usesTransparentBackground ? Color.clear : Color.black, in: CompactAIWingShape(side: side))
        .contentShape(CompactAIWingShape(side: side))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("正在整理语音"))
        .help("正在整理语音…")
    }
}

private struct CompactUpdateWing: View {
    var notice: IslandNotice
    var side: NoticeSide
    var height: CGFloat
    var usesTransparentBackground: Bool

    private var isCLIUpdate: Bool { notice.id.hasPrefix("update-available-cli-") }

    var body: some View {
        Group {
            if side == .left {
                if isCLIUpdate {
                    AIMascotView(identity: AIMascotIdentity(noticeID: notice.id), size: min(20, height * 0.62))
                } else {
                    Image(nsImage: NSApp.applicationIconImage)
                        .resizable()
                        .interpolation(.high)
                        .scaledToFit()
                        .frame(width: min(19, height * 0.58), height: min(19, height * 0.58))
                }
            } else {
                    Image(systemName: "arrow.down.circle")
                    .font(.system(size: min(14, height * 0.46), weight: .semibold))
                    .foregroundStyle(.cyan)
            }
        }
        .frame(width: CompactStatusMetrics.wingWidth, height: height)
        .background(
            usesTransparentBackground ? Color.clear : Color.black,
            in: CompactAIWingShape(side: side)
        )
        .contentShape(CompactAIWingShape(side: side))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(side == .left ? "\(notice.title)有可用更新" : "查看更新"))
    }
}

private struct CompactAIWing: View {
    var notices: [IslandNotice]
    var count: Int
    var side: NoticeSide
    var height: CGFloat
    var role: CompactAIWingRole
    var usesTransparentBackground = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @ViewBuilder
    var body: some View {
        wing
    }

    private var wing: some View {
        Group {
            if role == .identity {
                mascotStack
            } else {
                HStack(spacing: 5) {
                    CompactStatusPulseView(
                        color: statusNSColor,
                        isAnimated: !reduceMotion
                    )
                    .frame(width: 4, height: 4)
                    Text("\(count)")
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .monospacedDigit()
                }
                .foregroundStyle(.white)
            }
        }
        .frame(maxHeight: min(22, height * 0.72))
        .padding(.horizontal, CompactStatusMetrics.horizontalContentInset)
        .frame(
            width: CompactStatusMetrics.wingWidth,
            height: height,
            alignment: side == .left ? .leading : .trailing
        )
        .background(usesTransparentBackground ? Color.clear : Color.black, in: CompactAIWingShape(side: side))
        .contentShape(CompactAIWingShape(side: side))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(
            role == .identity ? "AI 任务图标" : "\(count) 个 AI 任务\(statusDescription)\(errorAccessibilityText)"
        ))
    }

    @ViewBuilder
    private var mascotStack: some View {
        let identities = notices.reduce(into: [AIMascotIdentity]()) { result, notice in
            guard let provider = AIMascotLibrary.provider(fromNoticeID: notice.id) else { return }
            let identity = AIMascotIdentity(provider: provider, taskID: notice.id, title: notice.title)
            if !result.contains(identity) { result.append(identity) }
        }.prefix(3)
        if identities.count == 1, let identity = identities.first {
            AIMascotView(identity: identity, size: min(22, height * 0.72))
        } else {
            HStack(spacing: -10) {
                ForEach(identities) { identity in
                    AIMascotView(identity: identity, size: min(16, height * 0.54))
                        .padding(1)
                        .background(Color.black, in: Circle())
                }
            }
        }
    }

    private var statusColor: Color {
        Color(nsColor: statusNSColor)
    }

    private var statusNSColor: NSColor {
        if notices.contains(where: { $0.kind == .error }) { return .systemRed }
        if notices.contains(where: { $0.kind == .warning }) { return .systemYellow }
        return .systemGreen
    }

    private var statusDescription: String {
        if notices.contains(where: { $0.kind == .error }) { return "有错误" }
        if notices.contains(where: { $0.kind == .warning }) { return "等待操作" }
        return "正在运行"
    }

    private var errorCount: Int {
        notices.count(where: { $0.kind == .error })
    }

    private var errorAccessibilityText: String {
        errorCount > 0 ? "，其中 \(errorCount) 个错误" : ""
    }
}

private struct CompactStatusPulseView: NSViewRepresentable {
    var color: NSColor
    var isAnimated: Bool

    func makeNSView(context: Context) -> CompactStatusPulseNSView {
        let view = CompactStatusPulseNSView()
        view.configure(color: color, isAnimated: isAnimated)
        return view
    }

    func updateNSView(_ view: CompactStatusPulseNSView, context: Context) {
        view.configure(color: color, isAnimated: isAnimated)
    }
}

private final class CompactStatusPulseNSView: NSView {
    private static let animationKey = "zisla.compact-status-pulse"

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    override func layout() {
        super.layout()
        layer?.cornerRadius = min(bounds.width, bounds.height) / 2
        layer?.shadowPath = CGPath(ellipseIn: bounds.insetBy(dx: -1, dy: -1), transform: nil)
    }

    func configure(color: NSColor, isAnimated: Bool) {
        guard let layer else { return }
        layer.backgroundColor = color.cgColor
        layer.shadowColor = color.cgColor
        layer.shadowOpacity = 0.7
        layer.shadowRadius = 2
        layer.shadowOffset = .zero

        guard isAnimated else {
            layer.removeAnimation(forKey: Self.animationKey)
            return
        }
        guard layer.animation(forKey: Self.animationKey) == nil else { return }

        let opacity = CABasicAnimation(keyPath: "opacity")
        opacity.fromValue = 0.5
        opacity.toValue = 1
        let scale = CABasicAnimation(keyPath: "transform.scale")
        scale.fromValue = 0.9
        scale.toValue = 1.1
        let group = CAAnimationGroup()
        group.animations = [opacity, scale]
        group.duration = 0.7
        group.autoreverses = true
        group.repeatCount = .infinity
        group.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        layer.add(group, forKey: Self.animationKey)
    }
}

private struct CompactMediaWing: View {
    var notice: IslandNotice
    var side: NoticeSide
    var height: CGFloat
    var usesTransparentBackground = false

    @ViewBuilder
    var body: some View {
        if side == .left {
            sourceIcon
        } else {
            waveform
        }
    }

    private var sourceIcon: some View {
        ZStack(alignment: .leading) {
            Group {
                if let artwork = MediaArtworkImageCache.image(from: notice.artworkData) {
                    Image(nsImage: artwork)
                        .resizable()
                        .scaledToFill()
                        .frame(width: artworkSize, height: artworkSize)
                        .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                } else {
                    Image(systemName: sourceSymbol)
                        .font(.system(size: min(15, height * 0.56), weight: .semibold))
                        .foregroundStyle(.white)
                }
            }
            .padding(.leading, CompactStatusMetrics.horizontalContentInset)
        }
        .frame(width: CompactStatusMetrics.wingWidth, height: height)
        .background(usesTransparentBackground ? Color.clear : Color.black, in: CompactAIWingShape(side: side))
        .contentShape(CompactAIWingShape(side: side))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("正在播放 \(notice.title)"))
        .help("正在播放：\(notice.title)")
    }

    private var artworkSize: CGFloat {
        max(18, min(24, height - 6))
    }

    private var waveform: some View {
        MediaWaveformView(
            artworkData: notice.artworkData,
            width: 20,
            height: min(18, height * 0.68),
            isActive: true
        )
        .padding(.horizontal, CompactStatusMetrics.horizontalContentInset)
        .frame(
            width: CompactStatusMetrics.wingWidth,
            height: height,
            alignment: .trailing
        )
        .background(usesTransparentBackground ? Color.clear : Color.black, in: CompactAIWingShape(side: side))
        .contentShape(CompactAIWingShape(side: side))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("正在播放：\(notice.detail ?? notice.title)"))
        .help("正在播放：\(notice.detail ?? notice.title)")
    }

    private var sourceSymbol: String {
        let source = notice.title.lowercased()
        if source.contains("bilibili") || source.contains("哔哩") {
            return "play.rectangle.fill"
        }
        if source.contains("apple") || source.contains("music") {
            return "music.note.list"
        }
        if source.contains("qq") || source.contains("网易") || source.contains("酷狗")
            || source.contains("酷我") {
            return "music.note"
        }
        if source.contains("youtube") || source.contains("优酷") || source.contains("腾讯")
            || source.contains("爱奇艺") || source.contains("芒果") {
            return "play.rectangle.fill"
        }
        return "music.note"
    }
}

private struct CompactBackgroundSoundWing: View {
    var notice: IslandNotice
    var side: NoticeSide
    var height: CGFloat
    var usesTransparentBackground = false

    @ViewBuilder
    var body: some View {
        if side == .left {
            Text(notice.title)
                .font(.system(size: min(11, height * 0.4), weight: .semibold))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .allowsTightening(true)
                .truncationMode(.tail)
                .padding(.leading, CompactStatusMetrics.horizontalContentInset)
                .frame(width: CompactStatusMetrics.wingWidth, height: height, alignment: .leading)
                .background(usesTransparentBackground ? Color.clear : Color.black, in: CompactAIWingShape(side: side))
                .contentShape(CompactAIWingShape(side: side))
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text("背景音正在播放：\(notice.title)"))
                .help("背景音正在播放：\(notice.title)")
        } else {
            MediaWaveformView(
                artworkData: nil,
                width: 20,
                height: min(18, height * 0.68),
                isActive: true
            )
            .padding(.horizontal, CompactStatusMetrics.horizontalContentInset)
            .frame(width: CompactStatusMetrics.wingWidth, height: height, alignment: .trailing)
            .background(usesTransparentBackground ? Color.clear : Color.black, in: CompactAIWingShape(side: side))
            .contentShape(CompactAIWingShape(side: side))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text("背景音正在播放：\(notice.title)"))
            .help("背景音正在播放：\(notice.title)")
        }
    }
}

/// Compact music detail bar: split around a physical notch, or rendered as one continuous row on other displays.
private struct DetailedMediaBar: View {
    private static let maximumContentWidth: CGFloat = 160
    private static let inlineTrackWidth: CGFloat = 130

    var item: NowPlayingSnapshot
    var lyrics: SyncedLyrics?
    var height: CGFloat
    var centerInset: CGFloat

    var body: some View {
        GeometryReader { geometry in
            if centerInset > 0 {
                let reservedCenterWidth = min(centerInset, geometry.size.width)
                let sideWidth = min(
                    Self.maximumContentWidth,
                    max(0, (geometry.size.width - reservedCenterWidth) / 2)
                )
                let centerWidth = max(0, geometry.size.width - sideWidth * 2)
                HStack(spacing: 0) {
                    trackIdentity
                        .frame(width: sideWidth, height: height, alignment: .leading)
                    Spacer(minLength: 0)
                        .frame(width: centerWidth)
                    lyricsSection
                        .frame(width: sideWidth, height: height, alignment: .trailing)
                        .clipped()
                }
                .frame(width: geometry.size.width, height: geometry.size.height, alignment: .top)
            } else {
                inlineMediaBar
                    .frame(width: geometry.size.width, height: height, alignment: .leading)
                    .clipped()
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("正在播放 \(MediaTextFormatting.titleArtistText(item))"))
        .help("正在播放：\(MediaTextFormatting.titleArtistText(item))")
    }

    private var trackIdentity: some View {
        HStack(spacing: 7) {
            artwork
            trackText
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.leading, CompactStatusMetrics.horizontalContentInset)
        .padding(.trailing, 8)
    }

    private var inlineMediaBar: some View {
        HStack(spacing: 7) {
            artwork
            trackText
                .frame(width: Self.inlineTrackWidth, alignment: .leading)
            waveform
            lyricLine
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, CompactStatusMetrics.horizontalContentInset)
    }

    private var trackText: some View {
        VStack(alignment: .leading, spacing: 1) {
            MarqueeText(
                item.title,
                font: .system(size: 10.5, weight: .semibold),
                textColor: .white
            )
            if !artist.isEmpty {
                MarqueeText(
                    artist,
                    font: .system(size: 8.5, weight: .medium),
                    textColor: .white.opacity(0.62)
                )
            }
        }
    }

    private var lyricsSection: some View {
        HStack(spacing: 7) {
            waveform
            lyricLine
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.leading, 8)
        .padding(.trailing, CompactStatusMetrics.horizontalContentInset)
    }

    private var waveform: some View {
        MediaWaveformView(
            artworkData: item.artworkData,
            width: 20,
            height: min(18, height * 0.68),
            isActive: item.isPlaying
        )
    }

    /// Advances lyrics with playback; freezes on the current line when paused.
    @ViewBuilder
    private var lyricLine: some View {
        if item.isPlaying {
            TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: false)) { context in
                lyricMarquee(at: context.date)
            }
        } else {
            lyricMarquee(at: .now)
        }
    }

    private func lyricMarquee(at date: Date) -> some View {
        let elapsedTime = item.elapsedTime(at: date) ?? 0
        let scrollProgress = item.isVideo
            ? nil
            : lyrics?.currentLineProgress(at: elapsedTime, duration: item.duration)
        return MarqueeText(
            item.isVideo
                ? MediaTextFormatting.videoSecondaryText(item)
                : MediaTextFormatting.lyricLine(item, lyrics: lyrics, date: date),
            font: .system(size: min(14, max(13, height * 0.42)), weight: .medium),
            textColor: .white.opacity(0.72),
            scrollDirection: .left,
            repeats: false,
            scrollProgress: scrollProgress,
            clipsOverflowWhenStatic: true
        )
    }

    private var artist: String {
        item.artist.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var artworkSize: CGFloat {
        max(18, min(24, height - 6))
    }

    @ViewBuilder
    private var artwork: some View {
        if let image = MediaArtworkImageCache.image(from: item.artworkData) {
            Image(nsImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: artworkSize, height: artworkSize)
                .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
        } else {
            ZStack {
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(Color.white.opacity(0.12))
                Image(systemName: item.isVideo ? "play.rectangle.fill" : "music.note")
                    .font(.system(size: artworkSize * 0.5, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .frame(width: artworkSize, height: artworkSize)
        }
    }
}

private struct CompactToolboxWing: View {
    var notice: IslandNotice
    var side: NoticeSide
    var height: CGFloat
    var usesTransparentBackground = false

    var body: some View {
        Group {
            if side == .left {
                Image(systemName: "toolbox.fill")
                    .font(.system(size: min(15, height * 0.56), weight: .semibold))
            } else {
                Text(notice.detail ?? "工具")
                    .font(.system(size: compactFontSize, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.65)
            }
        }
        .foregroundStyle(.white)
        .padding(.horizontal, CompactStatusMetrics.horizontalContentInset)
        .frame(
            width: CompactStatusMetrics.wingWidth,
            height: height,
            alignment: side == .left ? .leading : .trailing
        )
        .background(usesTransparentBackground ? Color.clear : Color.black, in: CompactAIWingShape(side: side))
        .contentShape(CompactAIWingShape(side: side))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("小工具：\(notice.title)"))
        .help("小工具：\(notice.title)")
    }

    private var compactFontSize: CGFloat {
        (notice.detail?.count ?? 0) > 3 ? 8 : 10
    }
}

private struct CompactFocusCountdownWing: View {
    var notice: IslandNotice
    var side: NoticeSide
    var height: CGFloat
    var usesTransparentBackground = false

    var body: some View {
        Group {
            if side == .left {
                Image(systemName: "clock")
                    .font(.system(size: min(15, height * 0.56), weight: .semibold))
            } else {
                Text(notice.detail ?? "00:00:00")
                    .font(.system(size: 8, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.65)
            }
        }
        .foregroundStyle(.white)
        .padding(.horizontal, CompactStatusMetrics.horizontalContentInset)
        .frame(
            width: CompactStatusMetrics.wingWidth,
            height: height,
            alignment: side == .left ? .leading : .trailing
        )
        .background(usesTransparentBackground ? Color.clear : Color.black, in: CompactAIWingShape(side: side))
        .contentShape(CompactAIWingShape(side: side))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("专注倒计时：\(notice.detail ?? "00:00:00")"))
        .help("专注倒计时：\(notice.detail ?? "00:00:00")")
    }
}

private struct CompactFocusModeWing: View {
    var notice: IslandNotice
    var side: NoticeSide
    var height: CGFloat
    var usesTransparentBackground = false

    var body: some View {
        Group {
            if side == .left {
                Image(systemName: notice.symbolName ?? "moon.fill")
                    .font(.system(size: min(15, height * 0.56), weight: .semibold))
            } else {
                Text("ON")
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .monospaced()
            }
        }
        .foregroundStyle(.white)
        .padding(.horizontal, CompactStatusMetrics.horizontalContentInset)
        .frame(
            width: CompactStatusMetrics.wingWidth,
            height: height,
            alignment: side == .left ? .leading : .trailing
        )
        .background(usesTransparentBackground ? Color.clear : Color.black, in: CompactAIWingShape(side: side))
        .contentShape(CompactAIWingShape(side: side))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("专注模式：\(notice.title)"))
        .help("专注模式：\(notice.title)")
    }
}

private struct CompactTransientWing: View {
    var notice: IslandNotice
    var side: NoticeSide
    var height: CGFloat
    var usesTransparentBackground = false

    var body: some View {
        Group {
            if side == .left {
                Image(systemName: notice.symbolName ?? "moon.fill")
                    .font(.system(size: min(15, height * 0.56), weight: .semibold))
            } else {
                Text(notice.kind == .success ? "ON" : "OFF")
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .monospaced()
                    .foregroundStyle(notice.kind == .success ? .green : .secondary)
            }
        }
        .foregroundStyle(.white)
        .padding(.horizontal, CompactStatusMetrics.horizontalContentInset)
        .frame(
            width: CompactStatusMetrics.wingWidth,
            height: height,
            alignment: side == .left ? .leading : .trailing
        )
        .background(usesTransparentBackground ? Color.clear : Color.black, in: CompactAIWingShape(side: side))
        .contentShape(CompactAIWingShape(side: side))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("\(notice.title)\(notice.detail ?? "")"))
        .help("\(notice.title)\(notice.detail ?? "")")
    }
}

private struct CompactMailWing: View {
    var notice: IslandNotice
    var side: NoticeSide
    var height: CGFloat
    var usesTransparentBackground = false

    var body: some View {
        Group {
            if side == .left {
                Image(systemName: notice.symbolName ?? "envelope.fill")
                    .font(.system(size: min(15, height * 0.56), weight: .semibold))
            } else {
                Text(notice.title)
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.65)
            }
        }
        .foregroundStyle(.white)
        .padding(.horizontal, CompactStatusMetrics.horizontalContentInset)
        .frame(
            width: CompactStatusMetrics.wingWidth,
            height: height,
            alignment: side == .left ? .leading : .trailing
        )
        .background(usesTransparentBackground ? Color.clear : Color.black, in: CompactAIWingShape(side: side))
        .contentShape(CompactAIWingShape(side: side))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(side == .left ? "新邮件" : "新邮件 \(notice.title) 封"))
    }
}

private struct DetailedMailBar: View {
    private static let maximumContentWidth: CGFloat = 160

    var leftNotice: IslandNotice
    var rightNotice: IslandNotice
    var height: CGFloat
    var centerInset: CGFloat

    var body: some View {
        GeometryReader { geometry in
            let reservedCenterWidth = min(centerInset, geometry.size.width)
            let sideWidth = min(
                Self.maximumContentWidth,
                max(0, (geometry.size.width - reservedCenterWidth) / 2)
            )
            let centerWidth = max(0, geometry.size.width - sideWidth * 2)
            HStack(spacing: 0) {
                HStack(spacing: 7) {
                    Image(systemName: leftNotice.symbolName ?? "envelope.fill")
                        .font(.system(size: min(15, height * 0.56), weight: .semibold))
                    Text(leftNotice.title)
                        .font(.system(size: 10, weight: .semibold))
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                .padding(.leading, CompactStatusMetrics.horizontalContentInset)
                .padding(.trailing, 8)
                .frame(width: sideWidth, height: height, alignment: .leading)

                Spacer(minLength: 0)
                    .frame(width: centerWidth)

                HStack(spacing: 6) {
                    Text(leftNotice.detail ?? "未知发件人")
                        .font(.system(size: 9, weight: .medium))
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Text(rightNotice.title)
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .monospacedDigit()
                }
                .padding(.leading, 8)
                .padding(.trailing, CompactStatusMetrics.horizontalContentInset)
                .frame(width: sideWidth, height: height, alignment: .trailing)
            }
            .frame(width: geometry.size.width, height: geometry.size.height, alignment: .top)
        }
        .foregroundStyle(.white)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("新邮件：\(leftNotice.title)，来自 \(leftNotice.detail ?? "未知发件人")，共 \(rightNotice.title) 封"))
    }
}

private struct CompactBrowserDownloadWing: View {
    var notice: IslandNotice
    var snapshots: [BrowserDownloadSnapshot]
    var uniqueAgents: [BrowserDownloadAgent]
    var side: NoticeSide
    var height: CGFloat
    var usesTransparentBackground = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var isFinished: Bool { notice.kind == .success }
    private var downloadCount: Int { max(1, snapshots.count) }

    var body: some View {
        Group {
            if side == .left {
                leftContent
            } else {
                rightContent
            }
        }
        .padding(.horizontal, CompactStatusMetrics.horizontalContentInset)
        .frame(
            width: CompactStatusMetrics.wingWidth,
            height: height,
            alignment: side == .left ? .leading : .trailing
        )
        .background(usesTransparentBackground ? Color.clear : Color.black, in: CompactAIWingShape(side: side))
        .contentShape(CompactAIWingShape(side: side))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(accessibilityLabel))
        .help(accessibilityLabel)
    }

    @ViewBuilder
    private var leftContent: some View {
        if downloadCount == 1, let agent = snapshots.first?.agent {
            singleBrowserIcon(agent)
        } else if !uniqueAgents.isEmpty {
            browserIconStack
        } else {
            fallbackIcon
        }
    }

    @ViewBuilder
    private var rightContent: some View {
        if isFinished {
            Image(systemName: "checkmark")
                .font(.system(size: min(15, height * 0.56), weight: .bold))
                .foregroundStyle(.green)
        } else if downloadCount == 1 {
            Text(notice.detail ?? "…")
                .font(.system(size: min(13, height * 0.5), weight: .semibold, design: .rounded))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.65)
                .foregroundStyle(.white)
        } else if downloadCount == 2 {
            twoFileProgressStack
        } else {
            multiFileStatusDot
        }
    }

    private func singleBrowserIcon(_ agent: BrowserDownloadAgent) -> some View {
        Group {
            if let image = browserIcon(for: agent) {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
                    .frame(width: iconSize, height: iconSize)
            } else {
                Image(systemName: "arrow.down.circle.fill")
                    .font(.system(size: min(15, height * 0.56), weight: .semibold))
                    .foregroundStyle(.white)
            }
        }
    }

    private var browserIconStack: some View {
        let agents = Array(uniqueAgents.prefix(3))
        return Group {
            if agents.count == 1, let agent = agents.first {
                singleBrowserIcon(agent)
            } else {
                HStack(spacing: -10) {
                    ForEach(agents, id: \.self) { agent in
                        Group {
                            if let image = browserIcon(for: agent) {
                                Image(nsImage: image)
                                    .resizable()
                                    .interpolation(.high)
                                    .aspectRatio(contentMode: .fit)
                                    .frame(width: stackIconSize, height: stackIconSize)
                            } else {
                                Image(systemName: "arrow.down.circle.fill")
                                    .font(.system(size: stackIconSize * 0.7, weight: .semibold))
                                    .foregroundStyle(.white)
                                    .frame(width: stackIconSize, height: stackIconSize)
                            }
                        }
                        .padding(1)
                        .background(Color.black, in: Circle())
                    }
                }
            }
        }
    }

    private var fallbackIcon: some View {
        Image(systemName: notice.symbolName ?? "arrow.down.circle.fill")
            .font(.system(size: min(15, height * 0.56), weight: .semibold))
            .foregroundStyle(.white)
    }

    private var twoFileProgressStack: some View {
        VStack(spacing: 1) {
            ForEach(Array(snapshots.prefix(2))) { snapshot in
                Text(snapshot.progressText)
                    .font(.system(size: min(9, height * 0.35), weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.65)
                    .foregroundStyle(.white)
            }
        }
        .frame(maxHeight: min(22, height * 0.72))
    }

    private var multiFileStatusDot: some View {
        HStack(spacing: 5) {
            CompactStatusPulseView(
                color: .systemGreen,
                isAnimated: !reduceMotion
            )
            .frame(width: 4, height: 4)
            Text("\(downloadCount)")
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .monospacedDigit()
        }
        .foregroundStyle(.white)
    }

    private var iconSize: CGFloat { max(16, min(22, height - 12)) }
    private var stackIconSize: CGFloat { max(14, min(16, height * 0.54)) }

    private func browserIcon(for agent: BrowserDownloadAgent) -> NSImage? {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: agent.bundleIdentifier)
        else { return nil }
        return NSWorkspace.shared.icon(forFile: url.path)
    }

    private var accessibilityLabel: String {
        let source = notice.appName ?? "浏览器"
        guard isFinished else {
            if downloadCount == 1 {
                return "\(source) 下载中 \(notice.detail ?? "")：\(notice.title)"
            } else {
                return "\(source) 正在下载 \(downloadCount) 个文件"
            }
        }
        return "\(source) 下载完成：\(notice.title)"
    }
}

private struct CompactVideoDownloadWing: View {
    var notice: IslandNotice
    var side: NoticeSide
    var height: CGFloat
    var usesTransparentBackground = false

    private var isFinished: Bool { notice.kind == .success }

    var body: some View {
        Group {
            if side == .left {
                icon
            } else if isFinished {
                Image(systemName: "checkmark")
                    .font(.system(size: min(15, height * 0.56), weight: .bold))
                    .foregroundStyle(.green)
            } else {
                Text(notice.detail ?? "…")
                    .font(.system(size: min(13, height * 0.5), weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.65)
                    .foregroundStyle(.white)
            }
        }
        .padding(.horizontal, CompactStatusMetrics.horizontalContentInset)
        .frame(
            width: CompactStatusMetrics.wingWidth,
            height: height,
            alignment: side == .left ? .leading : .trailing
        )
        .background(usesTransparentBackground ? Color.clear : Color.black, in: CompactAIWingShape(side: side))
        .contentShape(CompactAIWingShape(side: side))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(accessibilityLabel))
        .help(accessibilityLabel)
    }

    private var iconSize: CGFloat { max(16, min(22, height - 12)) }

    @ViewBuilder
    private var icon: some View {
        if let image = resolvedIcon {
            Image(nsImage: image)
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fit)
                .frame(width: iconSize, height: iconSize)
        } else {
            Image(systemName: notice.symbolName ?? "arrow.down.circle.fill")
                .font(.system(size: min(15, height * 0.56), weight: .semibold))
                .foregroundStyle(.white)
        }
    }

    /// Bundled offline logos take priority; sites without one use favicon bytes pre-fetched by AppModel.
    private var resolvedIcon: NSImage? {
        if let platform = VideoDownloadPlatform(rawValue: notice.appBundleIdentifier ?? ""),
            let url = platform.bundledIconURL
        {
            return VideoDownloadIconCache.shared.image(
                for: "platform|\(platform.rawValue)",
                url: url
            )
        }
        guard let data = notice.artworkData, !data.isEmpty else { return nil }
        return NSImage(data: data)
    }

    private var accessibilityLabel: String {
        let source = notice.appName ?? "视频"
        guard isFinished else {
            return "\(source) 下载中 \(notice.detail ?? "")：\(notice.title)"
        }
        return "\(source) 下载完成：\(notice.title)"
    }
}

/// SVG decoding is not cheap; cache once per resource key.
@MainActor
private final class VideoDownloadIconCache {
    static let shared = VideoDownloadIconCache()

    private var values: [String: NSImage?] = [:]

    func image(for key: String, url: URL) -> NSImage? {
        if let value = values[key] { return value }
        let image = NSImage(contentsOf: url)
        values[key] = image
        return image
    }
}

private struct CompactFocusCountdownBar: View {
    var notice: IslandNotice
    var height: CGFloat

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "clock")
            Spacer(minLength: 8)
            Text(notice.detail ?? "00:00:00")
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.65)
        }
        .font(.system(size: min(14, height * 0.52), weight: .semibold, design: .rounded))
        .foregroundStyle(.white)
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("专注倒计时：\(notice.detail ?? "00:00:00")"))
        .help("专注倒计时：\(notice.detail ?? "00:00:00")")
    }
}

private struct CompactPlaceholderWing: View {
    var side: NoticeSide
    var height: CGFloat

    var body: some View {
        Color.black
            .frame(width: CompactStatusMetrics.wingWidth, height: height)
            .clipShape(CompactAIWingShape(side: side))
            .accessibilityHidden(true)
    }
}

private struct CompactAIWingShape: InsettableShape {
    var side: NoticeSide
    var insetAmount: CGFloat = 0

    func path(in rect: CGRect) -> Path {
        let rect = rect.insetBy(dx: insetAmount, dy: insetAmount)
        let topInset = min(12, rect.width * 0.32)
        let bottomInset = min(3, rect.width * 0.08)
        let radius = min(9, rect.height * 0.28)

        var path = Path()
        path.move(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.minX + topInset, y: rect.minY))
        path.addCurve(
            to: CGPoint(x: rect.minX, y: rect.maxY - radius),
            control1: CGPoint(x: rect.minX + topInset * 0.45, y: rect.minY + radius * 0.7),
            control2: CGPoint(x: rect.minX, y: rect.maxY - radius * 1.6)
        )
        path.addQuadCurve(
            to: CGPoint(x: rect.minX + bottomInset, y: rect.maxY),
            control: CGPoint(x: rect.minX, y: rect.maxY)
        )
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.closeSubpath()

        guard side == .right else { return path }
        return path.applying(CGAffineTransform(
            a: -1,
            b: 0,
            c: 0,
            d: 1,
            tx: rect.minX + rect.maxX,
            ty: 0
        ))
    }

    func inset(by amount: CGFloat) -> CompactAIWingShape {
        var copy = self
        copy.insetAmount += amount
        return copy
    }
}

private struct SimulatedIslandShape: Shape {
    func path(in rect: CGRect) -> Path {
        let contour = CompactBarContourMetrics(size: rect.size)
        let bottomRadius = min(contour.bottomRadius, rect.height / 2, rect.width / 2)
        return UnevenRoundedRectangle(
            cornerRadii: .init(
                topLeading: 0,
                bottomLeading: bottomRadius,
                bottomTrailing: bottomRadius,
                topTrailing: 0
            ),
            style: .continuous
        )
        .path(in: rect)
    }
}

private struct NoticeWingShape: InsettableShape {
    var side: NoticeSide
    var insetAmount: CGFloat = 0

    func path(in rect: CGRect) -> Path {
        let rect = rect.insetBy(dx: insetAmount, dy: insetAmount)
        let radius = min(8, rect.height / 2)
        let innerX = rect.maxX - 10
        let tabTop = min(rect.minY + 9, rect.midY - 7)
        let tabBottom = min(tabTop + 16, rect.maxY - 8)

        var path = Path()
        path.move(to: CGPoint(x: rect.minX + radius, y: rect.minY))
        path.addLine(to: CGPoint(x: innerX - 2, y: rect.minY))
        path.addQuadCurve(
            to: CGPoint(x: innerX, y: rect.minY + 2),
            control: CGPoint(x: innerX, y: rect.minY)
        )
        path.addLine(to: CGPoint(x: innerX, y: tabTop))
        path.addLine(to: CGPoint(x: rect.maxX, y: tabTop + 4))
        path.addLine(to: CGPoint(x: rect.maxX, y: tabBottom - 4))
        path.addLine(to: CGPoint(x: innerX, y: tabBottom))
        path.addLine(to: CGPoint(x: innerX, y: rect.maxY - 2))
        path.addQuadCurve(
            to: CGPoint(x: innerX - 2, y: rect.maxY),
            control: CGPoint(x: innerX, y: rect.maxY)
        )
        path.addLine(to: CGPoint(x: rect.minX + radius, y: rect.maxY))
        path.addQuadCurve(
            to: CGPoint(x: rect.minX, y: rect.maxY - radius),
            control: CGPoint(x: rect.minX, y: rect.maxY)
        )
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + radius))
        path.addQuadCurve(
            to: CGPoint(x: rect.minX + radius, y: rect.minY),
            control: CGPoint(x: rect.minX, y: rect.minY)
        )
        path.closeSubpath()

        guard side == .right else { return path }
        return path.applying(CGAffineTransform(
            a: -1,
            b: 0,
            c: 0,
            d: 1,
            tx: rect.minX + rect.maxX,
            ty: 0
        ))
    }

    func inset(by amount: CGFloat) -> NoticeWingShape {
        var copy = self
        copy.insetAmount += amount
        return copy
    }
}
