import SwiftUI

/// 文本超出容器宽度时自动水平滚动（跑马灯）；否则静态左对齐、尾部省略。
/// 开启系统「减弱动态效果」时退化为普通截断文本，不滚动。
///
/// 用法：
/// ```swift
/// MarqueeText(songTitle,
///             font: .system(size: 13, weight: .semibold),
///             textColor: .primary)
///     .frame(maxWidth: 170)
/// ```
struct MarqueeText: View {
    let text: String
    let font: Font
    var textColor: Color = .primary
    var fontWeight: Font.Weight = .regular
    /// 滚动速度（点/秒）。
    var pointsPerSecond: Double = 32
    /// 两份文本之间的间隙。
    var gap: CGFloat = 28

    init(
        _ text: String,
        font: Font,
        textColor: Color = .primary,
        fontWeight: Font.Weight = .regular,
        pointsPerSecond: Double = 32,
        gap: CGFloat = 28
    ) {
        self.text = text
        self.font = font
        self.textColor = textColor
        self.fontWeight = fontWeight
        self.pointsPerSecond = pointsPerSecond
        self.gap = gap
    }

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var textWidth: CGFloat = 0
    @State private var containerWidth: CGFloat = 0
    @State private var offset: CGFloat = 0
    @State private var isAnimating = false

    var body: some View {
        ZStack(alignment: .leading) {
            // 测量层：不可见，仅用于撑出文字高度并量出单行文字真实宽度。
            Text(text)
                .font(font)
                .fontWeight(fontWeight)
                .lineLimit(1)
                .background(WidthReporter { w in textWidth = w })
                .opacity(0)
                .accessibilityHidden(true)

            if needsScroll {
                HStack(spacing: gap) {
                    Text(text)
                        .font(font)
                        .fontWeight(fontWeight)
                        .foregroundColor(textColor)
                        .lineLimit(1)
                    Text(text)
                        .font(font)
                        .fontWeight(fontWeight)
                        .foregroundColor(textColor)
                        .lineLimit(1)
                }
                .fixedSize(horizontal: true, vertical: false)
                .offset(x: offset)
                .onAppear { startLoop() }
            } else {
                Text(text)
                    .font(font)
                    .fontWeight(fontWeight)
                    .foregroundColor(textColor)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .clipped()
        .overlay(alignment: .leading) {
            // 容器宽度测量层。
            Color.clear
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(
                    WidthReporter { w in
                        containerWidth = w
                        evaluate()
                    }
                )
                .allowsHitTesting(false)
        }
    }

    private var needsScroll: Bool {
        !reduceMotion && containerWidth > 0 && textWidth > containerWidth + 1
    }

    private func evaluate() {
        if needsScroll {
            startLoop()
        } else {
            isAnimating = false
            offset = 0
        }
    }

    private func startLoop() {
        guard !isAnimating else { return }
        guard !reduceMotion else { return }
        let travel = textWidth + gap
        let duration = travel / pointsPerSecond
        guard duration > 0, textWidth > containerWidth + 1 else {
            isAnimating = false
            offset = 0
            return
        }
        isAnimating = true
        offset = 0
        withAnimation(.linear(duration: duration).repeatForever(autoreverses: false)) {
            offset = -travel
        }
    }
}

/// 通过 GeometryReader 量出宿主视图宽度并回传。
private struct WidthReporter: View {
    let onWidth: (CGFloat) -> Void

    var body: some View {
        GeometryReader { geo in
            Color.clear
                .onAppear { onWidth(geo.size.width) }
                .onChange(of: geo.size.width) { _, w in onWidth(w) }
        }
    }
}
