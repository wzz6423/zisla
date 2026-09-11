import AppKit

// Adapted for Zisla from Mac Duo's Apache-2.0 `DepthGeometry` and `DepthTuning`.
// The type names are kept as upstream so the file can be diffed against the
// original; see `Resources/ThirdPartyLicenses/MacDuo-LICENSE.txt`.

/// Where the picture lands on the glass.
///
/// The picture is a sheet hinged to the bottom edge of the screen, turned back
/// in world space by the angle the lid has travelled. The eye stays where it
/// is while the glass turns under it, so the projection takes both the current
/// lid angle and the eye position.
struct DepthGeometry {

    /// Past 90 degrees the picture turns its face away from the glass.
    var maxSeparationDegrees: Double = 88

    /// Bottom-left, bottom-right, top-right, top-left.
    func corners(
        startAngle: Double,
        currentAngle: Double,
        viewingDistanceRatio: Double,
        recession: Double,
        screenSize: CGSize
    ) -> [CGPoint] {
        let width = Double(screenSize.width)
        let height = Double(screenSize.height)
        let start = startAngle * .pi / 180
        let current = currentAngle * .pi / 180
        let travel = max(startAngle - currentAngle, 0)
        let separation = min(recession * travel, maxSeparationDegrees) * .pi / 180

        // The eye in world axes, hinge at the origin.
        let reach = height * viewingDistanceRatio + height / 2 * cos(start)
        let rise = height / 2 * sin(start)

        // The same eye, measured along the glass and away from it.
        let along = reach * cos(current) + rise * sin(current)
        let depth = max(reach * sin(current) - rise * cos(current), height / 10)

        let half = width / 2
        func project(_ x: Double, _ y: Double) -> CGPoint {
            let scale = depth / (depth + y * sin(separation))
            return CGPoint(
                x: half + (x - half) * scale,
                y: along + (y * cos(separation) - along) * scale
            )
        }
        return [project(0, 0), project(width, 0), project(width, height), project(0, height)]
    }
}

/// The settings that shape one frame.
///
/// The tuning is Mac Duo's hand-tuned `DepthTuning` default as one coherent
/// set, not its `Preferences.factory` values: with the factory geometry
/// (6 and 1) the far edge leaves the screen almost immediately, and with the
/// factory dim (maxDim 1, blur 135) the upper half of the sheet is crushed to
/// the same black as the picture's padding, so on a screen whose bright
/// content sits off-centre the fold reads as leaning to that side - only the
/// bright part stays visible. The defaults keep the whole sheet visible while
/// it folds, which is what reads as glass turning away. zisla exposes no
/// depth controls, so whatever is here is the look.
struct DepthTuning {
    var viewingDistance: Double = 2.7
    var recession: Double = 2
    var blurEvenness: Double = 0.4
    var dimReach: Double = 0.7
    var maxBlurRadius: Double = 55
    var maxDim: Double = 0.4
}
