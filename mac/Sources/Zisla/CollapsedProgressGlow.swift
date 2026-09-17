import SwiftUI
import ZislaKit

enum CollapsedProgress {
    static let glowHeight: CGFloat = 2
    static let glowBottomInset: CGFloat = 0
    static let contrastBackdropOpacity = 0.56
    static let leadingSegmentOpacity = 0.64
    static let filledSegmentOpacity = 0.98
    static let trailingSegmentOpacity = 0.70
    static var requiredGlowClearance: CGFloat { glowHeight + glowBottomInset }

    static func playbackFraction(
        for snapshot: NowPlayingSnapshot,
        at date: Date
    ) -> Double? {
        guard snapshot.isPlaying,
              let duration = snapshot.duration,
              duration > 0,
              let elapsed = snapshot.elapsedTime(at: date) else {
            return nil
        }
        return normalized(elapsed / duration)
    }

    static func remainingFraction(
        until deadline: Date?,
        totalDuration: Double?,
        at date: Date
    ) -> Double? {
        guard let deadline, let totalDuration, totalDuration > 0 else { return nil }
        return normalized(deadline.timeIntervalSince(date) / totalDuration)
    }

    static func elapsedFraction(fromRemaining remaining: Double) -> Double? {
        normalized(1 - remaining)
    }

    static func filledWidth(
        progress: Double,
        totalWidth: CGFloat
    ) -> CGFloat {
        let width = max(0, totalWidth)
        let fraction = min(max(progress.isFinite ? progress : 0, 0), 1)
        return width * fraction
    }

    private static func normalized(_ value: Double) -> Double? {
        guard value.isFinite else { return nil }
        return min(max(value, 0), 1)
    }
}

struct CollapsedProgressGlow: View {
    var progress: Double
    var tint: Color = .green

    var body: some View {
        GeometryReader { geometry in
            let trackWidth = max(0, geometry.size.width - 2)
            let filledWidth = CollapsedProgress.filledWidth(
                progress: progress,
                totalWidth: trackWidth
            )
            ZStack(alignment: .bottomLeading) {
                glowSegment(width: filledWidth)
            }
            .frame(width: trackWidth, height: geometry.size.height, alignment: .bottomLeading)
            .padding(.horizontal, 1)
            .padding(.bottom, CollapsedProgress.glowBottomInset)
        }
        .allowsHitTesting(false)
    }

    private func glowSegment(width: CGFloat) -> some View {
        ZStack(alignment: .bottomLeading) {
            Capsule()
                .fill(Color.black.opacity(CollapsedProgress.contrastBackdropOpacity))
                .frame(width: width, height: CollapsedProgress.glowHeight)
            Capsule()
                .fill(
                    LinearGradient(
                        colors: [
                            tint.opacity(CollapsedProgress.leadingSegmentOpacity),
                            tint.opacity(CollapsedProgress.filledSegmentOpacity),
                            tint.opacity(CollapsedProgress.trailingSegmentOpacity),
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .frame(width: width, height: 1)
        }
    }
}
