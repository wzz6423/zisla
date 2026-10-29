import AppKit
import SwiftUI
import ZislaCore
import ZislaKit

enum ClipboardTranslationPresentation: Equatable {
    case loading
    case result(text: String, copied: Bool?)
    case failed

    func rowText(locale: Locale) -> String {
        switch self {
        case .loading: AppLocalization.string("正在翻译…", locale: locale)
        case .result(let text, _): text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        case .failed: AppLocalization.string("翻译失败，请重试或使用浏览器翻译", locale: locale)
        }
    }

    var statusKey: String {
        switch self {
        case .loading: "正在翻译…"
        case .result(_, nil): "自动翻译"
        case .result(_, let copied): copied == false ? "无法写入剪贴板" : "已复制"
        case .failed: "翻译失败，请重试或使用浏览器翻译"
        }
    }

    static func readingSeconds(for text: String, rowWidth: CGFloat) -> Double {
        let travel = max(0, TransientNoticeMetrics.textWidth(of: text)
            - max(0, rowWidth - TransientNoticeMetrics.rowHorizontalPadding * 2))
        return max(4, Double(travel) / TransientNoticeMetrics.pointsPerSecond + 2.4)
    }
}

struct ClipboardTranslationResultView: View {
    let translation: ClipboardTranslationPresentation
    @ObservedObject var presentation: ClipboardAssistantPresentation
    let controller: ClipboardAssistantController
    let size: CGSize
    @Environment(\.locale) private var locale

    static func compactLength(text: String, edge: IslandEdge) -> CGFloat {
        let textLength = edge.isVertical
            ? CGFloat(text.filter { !$0.isWhitespace }.count) * 14
            : ceil((text as NSString).size(withAttributes: [
                .font: NSFont.systemFont(ofSize: 11, weight: .medium)
            ]).width)
        return 16 + 20 + 12 + min(168, textLength) + 20
    }

    var body: some View {
        let generation = presentation.translationGeneration
        let rowText = translation.rowText(locale: locale)
        let style = presentation.layout?.style ?? .notch
        let edge = presentation.layout?.edge ?? .top
        let collapsed = presentation.layout?.collapsedFrameInSurface
            ?? CGRect(x: 0, y: 0, width: size.width, height: presentation.islandTopHeight)
        let isCompact = style == .pill && presentation.layout?.placementMode == .custom && translation == .loading
        let geometry = VoiceRecordingIslandGeometry(
            collapsedSize: collapsed.size, availableSize: size
        )
        IslandSurface(
            isCollapsed: isCompact || presentation.isFolding,
            collapsedSize: collapsed.size,
            expandedSize: isCompact ? size : geometry.surfaceSize,
            visualStyle: presentation.visualStyle,
            notchBackground: presentation.notchBackground,
            usesCompactGlassSurface: !isCompact && !presentation.isFolding,
            bottomCornerRadius: VoiceRecordingIslandGeometry.bottomCornerRadius,
            layoutStyle: style, collapsedFrame: style == .pill ? collapsed : nil, edge: edge
        ) {
            if isCompact {
                compactLoading(rowText, edge: edge)
            } else {
                VStack(spacing: 0) {
                    HStack {
                        statusIcon
                        Spacer(minLength: 12)
                        closeButton
                    }
                    .padding(.horizontal, 12)
                    .foregroundStyle(.white.opacity(0.85))
                    .frame(height: min(presentation.islandTopHeight, size.height))

                    MarqueeText(
                        rowText,
                        font: TransientNoticeMetrics.font,
                        textColor: .white.opacity(0.82),
                        fontWeight: TransientNoticeMetrics.fontWeight,
                        pointsPerSecond: presentation.translationIsPaused ? 0 : TransientNoticeMetrics.pointsPerSecond,
                        repeats: false
                    )
                    .padding(.horizontal, TransientNoticeMetrics.rowHorizontalPadding)
                    .frame(height: VoiceRecordingIslandGeometry.transcriptRowHeight)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }
        }
        .onHover { controller.setHovered($0) }
        .task(id: translation) {
            await Task.yield()
            guard !Task.isCancelled else { return }
            controller.translationDidAppear(translation, for: generation, rowWidth: size.width, locale: locale)
        }
        .accessibilityElement(children: .contain)
    }

    private func compactLoading(_ text: String, edge: IslandEdge) -> some View {
        let layout = edge.isVertical
            ? AnyLayout(VStackLayout(spacing: 6))
            : AnyLayout(HStackLayout(spacing: 6))
        return layout {
            statusIcon.frame(width: 20, height: 20)
            if edge.isVertical {
                VerticalStatusText(text: text, availableHeight: max(0, size.height - 68))
            } else {
                MarqueeText(text, font: .system(size: 11, weight: .medium), textColor: .white,
                            pointsPerSecond: TransientNoticeMetrics.pointsPerSecond, repeats: false)
                    .frame(width: max(0, size.width - 68), height: 20)
            }
            closeButton.frame(width: 20, height: 20)
        }
        .padding(8)
        .frame(width: size.width, height: size.height)
        .foregroundStyle(.white.opacity(0.85))
    }

    private var statusIcon: some View {
        Image(systemName: translation == .loading ? "character.bubble" : "character.book.closed")
            .font(.system(size: 12, weight: .semibold))
            .accessibilityLabel(AppLocalization.string(translation.statusKey, locale: locale))
    }

    private var closeButton: some View {
        Button { controller.dismiss() } label: {
            Image(systemName: "xmark").font(.system(size: 10, weight: .semibold))
        }
        .buttonStyle(.plain)
        .help(AppLocalization.string("关闭", locale: locale))
        .accessibilityLabel(AppLocalization.string("关闭", locale: locale))
    }
}
