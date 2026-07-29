import SwiftUI

enum MarqueeScrollDirection: Hashable {
    case left
    case right
}

/// Scrolls text horizontally (marquee) when it overflows the container; otherwise keeps it static and left-aligned.
/// Degrades to static text when the system "Reduce Motion" setting is on.
///
/// Usage:
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
    /// Scroll speed (points/second).
    var pointsPerSecond: Double = 32
    /// Gap between the two copies of the text.
    var gap: CGFloat = 28
    var scrollDirection: MarqueeScrollDirection = .left
    var repeats = true
    var scrollProgress: Double?
    var clipsOverflowWhenStatic = false

    init(
        _ text: String,
        font: Font,
        textColor: Color = .primary,
        fontWeight: Font.Weight = .regular,
        pointsPerSecond: Double = 32,
        gap: CGFloat = 28,
        scrollDirection: MarqueeScrollDirection = .left,
        repeats: Bool = true,
        scrollProgress: Double? = nil,
        clipsOverflowWhenStatic: Bool = false
    ) {
        self.text = text
        self.font = font
        self.textColor = textColor
        self.fontWeight = fontWeight
        self.pointsPerSecond = pointsPerSecond
        self.gap = gap
        self.scrollDirection = scrollDirection
        self.repeats = repeats
        self.scrollProgress = scrollProgress
        self.clipsOverflowWhenStatic = clipsOverflowWhenStatic
    }

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var textWidth: CGFloat = 0
    @State private var containerWidth: CGFloat = 0
    @State private var automaticScrollProgress: CGFloat = 0

    var body: some View {
        ZStack(alignment: .leading) {
            if needsScroll {
                Group {
                    if let scrollProgress, !repeats {
                        marqueeLabel
                            .fixedSize(horizontal: true, vertical: false)
                            .offset(x: scrollOffset(for: scrollProgress))
                    } else {
                        Group {
                            if repeats {
                                HStack(spacing: gap) {
                                    marqueeLabel
                                    marqueeLabel
                                }
                            } else {
                                marqueeLabel
                            }
                        }
                        .fixedSize(horizontal: true, vertical: false)
                        .offset(x: scrollOffset(for: Double(automaticScrollProgress)))
                    }
                }
                .frame(width: max(0, containerWidth), alignment: .leading)
                .clipped()
            } else {
                if clipsOverflowWhenStatic {
                    marqueeLabel
                        .fixedSize(horizontal: true, vertical: false)
                        .frame(width: max(0, containerWidth), alignment: .leading)
                        .clipped()
                } else {
                    marqueeLabel
                        .truncationMode(.tail)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .clipped()
        .task(id: automaticAnimationIdentity) {
            var transaction = Transaction(animation: nil)
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                automaticScrollProgress = 0
            }
            guard needsScroll, scrollProgress == nil, pointsPerSecond > 0 else { return }

            await Task.yield()
            guard !Task.isCancelled else { return }
            let duration = max(0.01, Double(scrollTravel) / pointsPerSecond)
            let animation = Animation.linear(duration: duration)
            withAnimation(repeats ? animation.repeatForever(autoreverses: false) : animation) {
                automaticScrollProgress = 1
            }
        }
        .overlay(alignment: .leading) {
            // The intrinsic-width probe must not participate in layout or it can push neighboring content under the notch.
            Text(text)
                .font(font)
                .fontWeight(fontWeight)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
                .background(WidthReporter(onWidth: updateTextWidth))
                .hidden()
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
        .overlay(alignment: .leading) {
            // Container width measurement layer.
            Color.clear
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(
                    WidthReporter(onWidth: updateContainerWidth)
                )
                .allowsHitTesting(false)
        }
    }

    private var needsScroll: Bool {
        !reduceMotion && containerWidth > 0 && textWidth > containerWidth + 1
    }

    private var marqueeLabel: some View {
        Text(text)
            .font(font)
            .fontWeight(fontWeight)
            .foregroundColor(textColor)
            .lineLimit(1)
    }

    private func scrollOffset(for progress: Double) -> CGFloat {
        let travel = scrollTravel
        let clampedProgress = CGFloat(min(max(progress, 0), 1))
        return switch scrollDirection {
        case .left: -travel * clampedProgress
        case .right: travel * (clampedProgress - 1)
        }
    }

    private var scrollTravel: CGFloat {
        repeats ? textWidth + gap : max(0, textWidth - containerWidth)
    }

    private var automaticAnimationIdentity: AutomaticAnimationIdentity {
        AutomaticAnimationIdentity(
            text: text,
            textWidth: textWidth,
            containerWidth: containerWidth,
            pointsPerSecond: pointsPerSecond,
            gap: gap,
            direction: scrollDirection,
            repeats: repeats,
            usesExternalProgress: scrollProgress != nil,
            reduceMotion: reduceMotion
        )
    }

    private func updateTextWidth(_ width: CGFloat) {
        guard abs(textWidth - width) > 0.5 else { return }
        textWidth = width
    }

    private func updateContainerWidth(_ width: CGFloat) {
        guard abs(containerWidth - width) > 0.5 else { return }
        containerWidth = width
    }

    private struct AutomaticAnimationIdentity: Hashable {
        let text: String
        let textWidth: CGFloat
        let containerWidth: CGFloat
        let pointsPerSecond: Double
        let gap: CGFloat
        let direction: MarqueeScrollDirection
        let repeats: Bool
        let usesExternalProgress: Bool
        let reduceMotion: Bool
    }
}

/// Reports the host view's width via a GeometryReader callback.
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
