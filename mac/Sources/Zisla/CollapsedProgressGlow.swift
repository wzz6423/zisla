import SwiftUI
import ZislaKit

enum CollapsedProgress {
    struct SegmentWidths: Equatable {
        let leading: CGFloat
        let trailing: CGFloat
        let side: CGFloat
        let centerInset: CGFloat
    }

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

    static func segmentWidths(
        progress: Double,
        totalWidth: CGFloat,
        centerInset: CGFloat
    ) -> SegmentWidths {
        let width = max(0, totalWidth)
        let gap = min(max(0, centerInset), width)
        let visibleWidth = width - gap
        let fraction = min(max(progress.isFinite ? progress : 0, 0), 1)

        guard gap > 0 else {
            return SegmentWidths(
                leading: visibleWidth * fraction,
                trailing: 0,
                side: visibleWidth,
                centerInset: 0
            )
        }

        let sideWidth = visibleWidth / 2
        let filledWidth = visibleWidth * fraction
        return SegmentWidths(
            leading: min(filledWidth, sideWidth),
            trailing: min(max(filledWidth - sideWidth, 0), sideWidth),
            side: sideWidth,
            centerInset: gap
        )
    }

    private static func normalized(_ value: Double) -> Double? {
        guard value.isFinite else { return nil }
        return min(max(value, 0), 1)
    }
}

struct CollapsedProgressGlow: View {
    var progress: Double
    var centerInset: CGFloat = 0
    var tint: Color = .green

    var body: some View {
        GeometryReader { geometry in
            let trackWidth = max(0, geometry.size.width - 2)
            let segments = CollapsedProgress.segmentWidths(
                progress: progress,
                totalWidth: trackWidth,
                centerInset: centerInset
            )
            ZStack(alignment: .bottomLeading) {
                if segments.centerInset > 0 {
                    glowSegment(width: segments.leading)
                        .frame(width: segments.side, alignment: .leading)
                        .clipped()
                    glowSegment(width: segments.trailing)
                        .frame(width: segments.side, alignment: .leading)
                        .clipped()
                        .offset(x: segments.side + segments.centerInset)
                } else {
                    glowSegment(width: segments.leading)
                }
            }
            .frame(width: trackWidth, height: geometry.size.height, alignment: .bottomLeading)
            .padding(.horizontal, 1)
            .padding(.bottom, 0.5)
        }
        .allowsHitTesting(false)
    }

    private func glowSegment(width: CGFloat) -> some View {
        ZStack(alignment: .leading) {
            Capsule()
                .fill(tint.opacity(0.52))
                .frame(width: width, height: 1.5)
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
