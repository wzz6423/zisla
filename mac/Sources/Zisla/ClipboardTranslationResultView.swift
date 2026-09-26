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

    var body: some View {
        let generation = presentation.translationGeneration
        let rowText = translation.rowText(locale: locale)
        let geometry = VoiceRecordingIslandGeometry(
            collapsedSize: CGSize(width: size.width, height: presentation.islandTopHeight),
            availableSize: size
        )
        IslandSurface(
            isCollapsed: false,
            collapsedSize: geometry.collapsedSize,
            expandedSize: geometry.surfaceSize,
            visualStyle: presentation.visualStyle,
            usesCompactGlassSurface: true,
            bottomCornerRadius: VoiceRecordingIslandGeometry.bottomCornerRadius
        ) {
            VStack(spacing: 0) {
                HStack {
                    Image(systemName: translation == .loading ? "character.bubble" : "character.book.closed")
                        .font(.system(size: 12, weight: .semibold))
                        .accessibilityLabel(AppLocalization.string(translation.statusKey, locale: locale))
                    Spacer(minLength: 12)
                    Button {
                        controller.dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 10, weight: .semibold))
                    }
                    .buttonStyle(.plain)
                    .help(AppLocalization.string("关闭", locale: locale))
                    .accessibilityLabel(AppLocalization.string("关闭", locale: locale))
                }
                .padding(.horizontal, 12)
                .foregroundStyle(.white.opacity(0.85))
                .frame(height: geometry.topRowFrame.height)

                MarqueeText(
                    rowText,
                    font: TransientNoticeMetrics.font,
                    textColor: .white.opacity(0.82),
                    fontWeight: TransientNoticeMetrics.fontWeight,
                    pointsPerSecond: presentation.translationIsPaused ? 0 : TransientNoticeMetrics.pointsPerSecond,
                    repeats: false
                )
                .padding(.horizontal, TransientNoticeMetrics.rowHorizontalPadding)
                .frame(height: geometry.transcriptRowFrame.height)
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
}
