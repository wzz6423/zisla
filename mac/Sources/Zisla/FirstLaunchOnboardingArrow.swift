import SwiftUI

struct FirstLaunchOnboardingArrow: View {
    var body: some View {
        FirstLaunchOnboardingArrowShape()
            .fill(.primary)
            .environment(\.layoutDirection, .leftToRight)
            .accessibilityHidden(true)
            .allowsHitTesting(false)
    }
}

struct FirstLaunchOnboardingArrowShape: Shape {
    func path(in rect: CGRect) -> Path {
        guard rect.size.width.isFinite, rect.size.height.isFinite,
              rect.midX.isFinite, rect.midY.isFinite,
              rect.size.width > 0, rect.size.height > 0 else { return Path() }

        let scale = min(rect.width / 44, rect.height / 40)
        var strokes = Path()
        strokes.move(to: CGPoint(x: 25, y: 35))
        strokes.addCurve(
            to: CGPoint(x: 22, y: 5),
            control1: CGPoint(x: 30, y: 24),
            control2: CGPoint(x: 20, y: 17)
        )
        strokes.move(to: CGPoint(x: 11, y: 16))
        strokes.addCurve(
            to: CGPoint(x: 22, y: 5),
            control1: CGPoint(x: 15, y: 13),
            control2: CGPoint(x: 19, y: 8)
        )
        strokes.move(to: CGPoint(x: 22, y: 5))
        strokes.addCurve(
            to: CGPoint(x: 32, y: 15),
            control1: CGPoint(x: 25, y: 7),
            control2: CGPoint(x: 29, y: 10)
        )

        // Materialize the outline so SwiftUI scales its bounds together with the rounded stroke.
        return Path(strokes.strokedPath(StrokeStyle(lineWidth: 2.4, lineCap: .round, lineJoin: .round)).cgPath)
            .applying(CGAffineTransform(
                a: scale, b: 0, c: 0, d: scale,
                tx: rect.midX - 22 * scale,
                ty: rect.midY - 20 * scale
            ))
    }
}
