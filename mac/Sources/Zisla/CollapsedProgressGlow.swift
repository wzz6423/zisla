import SwiftUI
import ZislaKit

enum CollapsedProgress {
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

    private static func normalized(_ value: Double) -> Double? {
        guard value.isFinite else { return nil }
        return min(max(value, 0), 1)
    }
}

struct CollapsedProgressGlow: View {
    var progress: Double

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width * min(max(progress, 0), 1)
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.green.opacity(0.52))
                    .frame(width: width, height: 1.5)
                    .blur(radius: 3)
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [.green.opacity(0.12), .green.opacity(0.82), .green.opacity(0.18)],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: width, height: 1)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
            .padding(.horizontal, 1)
            .padding(.bottom, 0.5)
        }
        .allowsHitTesting(false)
    }
}
