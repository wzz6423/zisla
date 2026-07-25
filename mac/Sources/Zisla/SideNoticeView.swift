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
}

private enum CompactStatusMetrics {
    static let wingWidth: CGFloat = 40
    static let horizontalContentInset: CGFloat = 5
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
            if let mediaNotice = presentation.activeMediaNotice {
                CompactMediaWing(
                    notice: mediaNotice,
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
        side == .left ? queue.left : queue.right
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
    var onStatusHidden: () -> Void

    private var height: CGFloat { displayState.compactWingHeight }

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                if !displayState.compactStatusHidden {
                    Group {
                        if let mediaNotice {
                            HStack(spacing: 0) {
                                CompactMediaWing(notice: mediaNotice, side: .left, height: height)
                                Spacer(minLength: 0)
                                CompactMediaWing(notice: mediaNotice, side: .right, height: height)
                            }
                        } else if let focusCountdownNotice {
                            CompactFocusCountdownBar(notice: focusCountdownNotice, height: height)
                        } else if let toolboxNotice {
                            HStack(spacing: 0) {
                                CompactToolboxWing(notice: toolboxNotice, side: .left, height: height)
                                Spacer(minLength: 0)
                                CompactToolboxWing(notice: toolboxNotice, side: .right, height: height)
                            }
                        } else if !activeAINotices.isEmpty {
                            HStack(spacing: 0) {
                                CompactAIWing(
                                    notices: activeAINotices,
                                    count: activeAINotices.count,
                                    side: .left,
                                    height: height,
                                    role: .identity
                                )
                                Spacer(minLength: 0)
                                CompactAIWing(
                                    notices: activeAINotices,
                                    count: activeAINotices.count,
                                    side: .right,
                                    height: height,
                                    role: .status
                                )
                            }
                        }
                    }
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
            .background(Color.black, in: SimulatedIslandShape())
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

    private var mediaNotice: IslandNotice? {
        (queue.left + queue.right).first { $0.id.hasPrefix("media-active-") }
    }

    private var toolboxNotice: IslandNotice? {
        (queue.left + queue.right).first { $0.id.hasPrefix("toolbox-reminder-") }
    }

    private var focusCountdownNotice: IslandNotice? {
        (queue.left + queue.right).first { $0.id.hasPrefix("focus-countdown-") }
    }

    private var activeAINotices: [IslandNotice] {
        (queue.left + queue.right)
            .filter { $0.id.hasPrefix("ai-active-") }
            .sorted { $0.createdAt > $1.createdAt }
    }
}

private struct NoticeRow: View {
    var notice: IslandNotice
    var side: NoticeSide
    var onDismiss: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var isMessage: Bool { notice.style == .message }
    private var isStatus: Bool { notice.style == .status }

    var body: some View {
        Group {
            if isMessage {
                messageBody
            } else if isStatus {
                statusBody
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

private struct CompactAIWing: View {
    var notices: [IslandNotice]
    var count: Int
    var side: NoticeSide
    var height: CGFloat
    var role: CompactAIWingRole

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
                    if count > 1 {
                        Text("\(count)")
                            .font(.system(size: 10, weight: .bold, design: .rounded))
                            .monospacedDigit()
                    } else {
                        Image(systemName: "ellipsis")
                            .font(.system(size: 9, weight: .bold))
                    }
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
        .background(Color.black, in: CompactAIWingShape(side: side))
        .contentShape(CompactAIWingShape(side: side))
        .overlay {
            if role == .status, count == 1, let progress = notices.first?.progress {
                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(Color.white.opacity(0.72), style: StrokeStyle(lineWidth: 1.2, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .frame(width: min(27, height * 0.82), height: min(27, height * 0.82))
                    .allowsHitTesting(false)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(
            role == .identity ? "AI 任务图标" : "\(count) 个 AI 任务\(statusDescription)"
        ))
    }

    @ViewBuilder
    private var mascotStack: some View {
        let identities = AIMascotLibrary
            .uniqueProviders(fromNoticeIDs: notices.map(\.id))
            .prefix(3)
            .map { AIMascotIdentity(provider: $0, taskID: "") }
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
                if let artworkData = notice.artworkData,
                   let artwork = NSImage(data: artworkData) {
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
        .background(Color.black, in: CompactAIWingShape(side: side))
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
        .background(Color.black, in: CompactAIWingShape(side: side))
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

private struct CompactToolboxWing: View {
    var notice: IslandNotice
    var side: NoticeSide
    var height: CGFloat

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
        .background(Color.black, in: CompactAIWingShape(side: side))
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
        .background(Color.black, in: CompactAIWingShape(side: side))
        .contentShape(CompactAIWingShape(side: side))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("专注倒计时：\(notice.detail ?? "00:00:00")"))
        .help("专注倒计时：\(notice.detail ?? "00:00:00")")
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
