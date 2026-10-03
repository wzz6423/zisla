import CoreGraphics
import Foundation

// Modified for Zisla; source revision and adaptation details are in ThirdPartyLicenses/README.md.
enum SystemMonitorMenuBarIconGeometry {
    static let canvas = CGRect(x: 0, y: 0, width: 120, height: 120)

    /// The x coordinate every element of the icon is centred on.
    ///
    /// This is deliberately **not** `canvas.midX`. The artwork is drawn on a
    /// 119-unit-wide box: `status-menubar.svg` runs the battery arc from
    /// `x = 15.5` to `x = 103.5`, so `(15.5 + 103.5) / 2 = 59.5`. The canvas is
    /// 120 wide, making `canvas.midX = 60.0`. Anchoring anything to the canvas
    /// midpoint instead of this constant shifts it half a unit right of all the
    /// hand-drawn art, which is what shipped in 1.3.x and is issue #30.
    static let artworkCenterX: CGFloat = 59.5

    // Derived from the SVG battery endpoints and radius.
    private static let batteryRadius: CGFloat = 51.5
    private static let batteryCenter = CGPoint(x: artworkCenterX, y: 61.48715261785473)
    private static let batteryStart: CGFloat = 148.69008689281117 * .pi / 180
    private static let batterySweep: CGFloat = 242.6198262143777 * .pi / 180
    static let batteryChargingBoltTopGapWidth: CGFloat = 50

    static func batteryHeaderGapWidth(contentWidth: CGFloat, strokeWidth: CGFloat) -> CGFloat {
        let halfWidth = contentWidth / 2 + strokeWidth / 2 + 5.5
        return 2 * batteryRadius * asin(halfWidth / batteryRadius)
    }

    static let batteryValueBaseFontSize: CGFloat = 20
    static let batteryChargingBoltCalibration: CGFloat = 220.0 / 180.0

    static func batteryValueBaseline(fontSize: CGFloat) -> CGPoint {
        let referenceFontSize: CGFloat = 20
        let referenceBaseline: CGFloat = 17
        let currentFontSize: CGFloat = 32
        let currentBaseline: CGFloat = 24
        let slope = (currentBaseline - referenceBaseline) / (currentFontSize - referenceFontSize)
        return CGPoint(
            x: artworkCenterX,
            y: referenceBaseline + (fontSize - referenceFontSize) * slope
        )
    }

    static func batteryTrack(
        hasTopGap: Bool = false,
        topGapWidth: CGFloat = batteryChargingBoltTopGapWidth
    ) -> CGPath {
        batteryArc(
            from: 0,
            to: 1,
            hasTopGap: hasTopGap,
            topGapWidth: topGapWidth
        )
    }

    static func batteryFill(
        progress: Double,
        hasTopGap: Bool = false,
        topGapWidth: CGFloat = batteryChargingBoltTopGapWidth
    ) -> CGPath {
        batteryArc(
            from: 0,
            to: progress,
            hasTopGap: hasTopGap,
            topGapWidth: topGapWidth
        )
    }

    private static func clampedUnit(_ value: Double) -> Double {
        guard value.isFinite else { return 0 }
        return min(1, max(0, value))
    }

    private static func batteryGapFraction(topGapWidth: CGFloat) -> Double {
        guard topGapWidth.isFinite, topGapWidth > 0 else { return 0 }
        let arcLength = batteryRadius * batterySweep
        guard arcLength.isFinite, arcLength > 0 else { return 0 }
        return min(1, max(0, Double(topGapWidth / arcLength)))
    }

    static func batteryChargingBolt(scale: CGFloat = 1) -> CGPath {
        let path = CGMutablePath()
        path.move(to: CGPoint(x: 62.1, y: 2.2))
        path.addQuadCurve(
            to: CGPoint(x: 62.6, y: 3.3),
            control: CGPoint(x: 62.8, y: 2.5)
        )
        path.addLine(to: CGPoint(x: 61.2, y: 7.8))
        path.addLine(to: CGPoint(x: 65.9, y: 7.8))
        path.addQuadCurve(
            to: CGPoint(x: 67.3, y: 8.6),
            control: CGPoint(x: 66.9, y: 7.8)
        )
        path.addQuadCurve(
            to: CGPoint(x: 67, y: 10),
            control: CGPoint(x: 67.6, y: 9.3)
        )
        path.addLine(to: CGPoint(x: 57, y: 21.3))
        path.addQuadCurve(
            to: CGPoint(x: 55.6, y: 21.6),
            control: CGPoint(x: 56.4, y: 22)
        )
        path.addQuadCurve(
            to: CGPoint(x: 55.3, y: 20.5),
            control: CGPoint(x: 55, y: 21.3)
        )
        path.addLine(to: CGPoint(x: 57.4, y: 14.1))
        path.addLine(to: CGPoint(x: 52.9, y: 14.1))
        path.addQuadCurve(
            to: CGPoint(x: 51.6, y: 13.3),
            control: CGPoint(x: 52, y: 14.1)
        )
        path.addQuadCurve(
            to: CGPoint(x: 51.9, y: 12),
            control: CGPoint(x: 51.3, y: 12.6)
        )
        path.addLine(to: CGPoint(x: 61.1, y: 2.7))
        path.addQuadCurve(
            to: CGPoint(x: 62.1, y: 2.2),
            control: CGPoint(x: 61.6, y: 2.1)
        )
        path.closeSubpath()

        guard scale.isFinite, scale > 0, scale != 1 else { return path }
        let pivot = batteryChargingBoltPivot
        var transform = CGAffineTransform(
            a: scale,
            b: 0,
            c: 0,
            d: scale,
            tx: pivot.x * (1 - scale),
            ty: pivot.y * (1 - scale)
        )
        return path.copy(using: &transform) ?? path
    }

    static let batteryChargingBoltPivot = CGPoint(x: artworkCenterX, y: 2.1)

    static func volumeDots() -> [CGPoint] {
        [
            CGPoint(x: 33, y: 104.2),
            CGPoint(x: 50.5, y: 111.2),
            CGPoint(x: 68.5, y: 111.7),
            CGPoint(x: 86, y: 105.8)
        ]
    }

    static let volumeDotRadius: CGFloat = 5.5

    static let volumeArcStartAngle: CGFloat = 121.82 * .pi / 180
    static let volumeArcEndAngle: CGFloat = 59.12 * .pi / 180

    static func volumeArcTrack() -> CGPath {
        let path = CGMutablePath()
        path.addArc(
            center: batteryCenter,
            radius: batteryRadius,
            startAngle: volumeArcStartAngle,
            endAngle: volumeArcEndAngle,
            clockwise: true
        )
        return path
    }

    static func volumeArcFill(progress: Double) -> CGPath {
        let clamped = min(1, max(0, progress))
        guard clamped > 0 else { return CGMutablePath() }
        let sweep = volumeArcStartAngle - volumeArcEndAngle
        let end = volumeArcStartAngle - sweep * CGFloat(clamped)
        let path = CGMutablePath()
        path.addArc(
            center: batteryCenter,
            radius: batteryRadius,
            startAngle: volumeArcStartAngle,
            endAngle: end,
            clockwise: true
        )
        return path
    }

    static func batteryArc(
        from start: Double,
        to end: Double,
        hasTopGap: Bool,
        topGapWidth: CGFloat
    ) -> CGPath {
        guard start.isFinite, end.isFinite else { return CGMutablePath() }
        let clampedStart = clampedUnit(start)
        let clampedEnd = clampedUnit(end)
        guard clampedEnd > clampedStart else { return CGMutablePath() }

        let path = CGMutablePath()
        guard hasTopGap else {
            path.addPath(arc(
                center: batteryCenter,
                radius: batteryRadius,
                start: batteryStart + batterySweep * CGFloat(clampedStart),
                end: batteryStart + batterySweep * CGFloat(clampedEnd)
            ))
            return path
        }

        let gapFraction = batteryGapFraction(topGapWidth: topGapWidth)
        let gapStartProgress = (1 - gapFraction) / 2
        let gapEndProgress = gapStartProgress + gapFraction

        let firstSegmentEnd = min(clampedEnd, gapStartProgress)
        if firstSegmentEnd > clampedStart {
            path.addPath(arc(
                center: batteryCenter,
                radius: batteryRadius,
                start: batteryStart + batterySweep * CGFloat(clampedStart),
                end: batteryStart + batterySweep * CGFloat(firstSegmentEnd)
            ))
        }

        let secondSegmentStart = max(clampedStart, gapEndProgress)
        if clampedEnd > secondSegmentStart {
            path.addPath(arc(
                center: batteryCenter,
                radius: batteryRadius,
                start: batteryStart + batterySweep * CGFloat(secondSegmentStart),
                end: batteryStart + batterySweep * CGFloat(clampedEnd)
            ))
        }
        return path
    }

    private static func arc(
        center: CGPoint,
        radius: CGFloat,
        start: CGFloat,
        end: CGFloat
    ) -> CGPath {
        let path = CGMutablePath()
        path.addArc(center: center, radius: radius, startAngle: start, endAngle: end, clockwise: false)
        return path
    }
}
