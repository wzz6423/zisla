import SwiftUI
import ZislaKit

enum CollapsedProgress {
    static let glowHeight: CGFloat = 1.5
    static let glowBottomInset: CGFloat = 0.5
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
        ZStack(alignment: .leading) {
            Capsule()
                .fill(tint.opacity(0.52))
                .frame(width: width, height: CollapsedProgress.glowHeight)
                .blur(radius: 3)
            Capsule()
                .fill(
                    LinearGradient(
                        colors: [
                            tint.opacity(0.12),
                            tint.opacity(0.82),
                            tint.opacity(0.18),
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .frame(width: width, height: 1)
        }
    }
}
