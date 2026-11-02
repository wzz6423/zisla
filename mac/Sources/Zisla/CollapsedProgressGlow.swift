import SwiftUI
import ZislaCore
import ZislaKit

enum CollapsedProgress {
    static let outlineWidth: CGFloat = 2
    static let outlineInset: CGFloat = 1.5
    static let contrastBackdropOpacity = 0.56
    static let leadingSegmentOpacity = 0.64
    static let filledSegmentOpacity = 0.98
    static let trailingSegmentOpacity = 0.70

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

    static func normalized(_ value: Double) -> Double? {
        guard value.isFinite else { return nil }
        return min(max(value, 0), 1)
    }
}

struct CompactIslandShape: InsettableShape {
    var layoutStyle: IslandLayoutStyle = .notch
    var insetAmount: CGFloat = 0

    func path(in rect: CGRect) -> Path {
        let bounds = rect.insetBy(dx: insetAmount, dy: insetAmount)
        guard bounds.width > 0, bounds.height > 0 else { return Path() }
        let outline: Path
        if layoutStyle == .pill {
            outline = Capsule().path(in: bounds)
        } else {
            let contour = CompactBarContourMetrics(size: rect.size)
            let radius = max(0, min(contour.bottomRadius, rect.height / 2, rect.width / 2) - insetAmount)
            outline = UnevenRoundedRectangle(
                cornerRadii: .init(
                    topLeading: 0,
                    bottomLeading: radius,
                    bottomTrailing: radius,
                    topTrailing: 0
                ),
                style: .continuous
            ).path(in: bounds)
        }
        return Self.topCenteredPath(outline, in: bounds)
    }

    func inset(by amount: CGFloat) -> Self {
        var copy = self
        copy.insetAmount += amount
        return copy
    }

    static func topCenteredPath(_ outline: Path, in rect: CGRect) -> Path {
        var segments: [Segment] = []
        var point = CGPoint.zero
        var origin = CGPoint.zero
        outline.forEach { element in
            switch element {
            case .move(to: let target):
                point = target
                origin = target
            case .line(to: let target):
                segments.append(.line(point, target))
                point = target
            case .quadCurve(to: let target, control: let control):
                segments.append(.quad(point, control, target))
                point = target
            case .curve(to: let target, control1: let first, control2: let second):
                segments.append(.curve(point, first, second, target))
                point = target
            case .closeSubpath:
                segments.append(.line(point, origin))
            }
        }
        let top = CGPoint(x: rect.midX, y: rect.minY)
        // Keep the native continuous corner curves; only split the flat top and reorder segments.
        if let index = segments.firstIndex(where: { segment in
            guard case .line(let start, let end) = segment else { return false }
            return start.y == top.y && end.y == top.y && start.x < top.x && end.x > top.x
        }), case .line(let start, let end) = segments[index] {
            segments.replaceSubrange(index...index, with: [.line(start, top), .line(top, end)])
        }
        guard let startIndex = segments.firstIndex(where: { $0.start == top }) else { return outline }
        var path = Path()
        path.move(to: top)
        for segment in segments[startIndex...] + segments[..<startIndex] {
            segment.append(to: &path)
        }
        path.closeSubpath()
        return path
    }

    private enum Segment {
        case line(CGPoint, CGPoint)
        case quad(CGPoint, CGPoint, CGPoint)
        case curve(CGPoint, CGPoint, CGPoint, CGPoint)

        var start: CGPoint {
            switch self {
            case .line(let point, _), .quad(let point, _, _), .curve(let point, _, _, _): point
            }
        }

        func append(to path: inout Path) {
            switch self {
            case .line(_, let end): path.addLine(to: end)
            case .quad(_, let control, let end): path.addQuadCurve(to: end, control: control)
            case .curve(_, let first, let second, let end):
                path.addCurve(to: end, control1: first, control2: second)
            }
        }
    }
}

struct CollapsedProgressGlow: View {
    var progress: Double
    var tint: Color = .green
    var layoutStyle: IslandLayoutStyle = .notch
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        Self.rendering(
            progress: progress, tint: tint, layoutStyle: layoutStyle,
            reduceMotion: reduceMotion, reduceTransparency: reduceTransparency
        )
    }

    static func rendering(
        progress: Double, tint: Color, layoutStyle: IslandLayoutStyle,
        reduceMotion: Bool, reduceTransparency: Bool
    ) -> some View {
        let fraction = CollapsedProgress.normalized(progress) ?? 0
        let outline = CompactIslandShape(layoutStyle: layoutStyle)
            .inset(by: CollapsedProgress.outlineInset)
            .trim(from: 0, to: fraction)
        return ZStack {
            outline.stroke(
                Color.black.opacity(reduceTransparency ? 1 : CollapsedProgress.contrastBackdropOpacity),
                style: StrokeStyle(lineWidth: CollapsedProgress.outlineWidth, lineCap: .round, lineJoin: .round)
            )
            if reduceTransparency {
                outline.stroke(tint, style: StrokeStyle(lineWidth: 1, lineCap: .round, lineJoin: .round))
            } else {
                outline.stroke(
                    LinearGradient(
                        colors: [
                            tint.opacity(CollapsedProgress.leadingSegmentOpacity),
                            tint.opacity(CollapsedProgress.filledSegmentOpacity),
                            tint.opacity(CollapsedProgress.trailingSegmentOpacity),
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    ),
                    style: StrokeStyle(lineWidth: 1, lineCap: .round, lineJoin: .round)
                )
            }
        }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.18), value: fraction)
        .transaction { transaction in
            if reduceMotion { transaction.disablesAnimations = true }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
