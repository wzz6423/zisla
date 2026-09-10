import Foundation
import Testing
import ZislaKit

/// `IslandCrownFade` is the eased alpha curve of the crown's black → glass blend.
///
/// That blend used to be a straight linear ramp. A ramp like that meets the flat glass on a slope
/// break, and the eye promotes the break into a soft bright Mach band — the blurry white line that
/// crossed the top of the glass on every expanded page, whichever module was showing. The curve
/// samples a smoothstep so *both* ends approach zero slope. These tests pin that shape, because a
/// regression back to a linear ramp keeps identical endpoints and only shows up in the slope
/// profile (and therefore in the render), never at the ends.
struct IslandCrownFadeTests {
    @Test
    func blendRunsFromTheSolidCrownDownToFullTransparency() throws {
        let curve = IslandCrownFade.curve
        let first = try #require(curve.first)
        let last = try #require(curve.last)

        #expect(first.location == 0)
        #expect(first.alpha == 1)
        #expect(last.location == 1)
        #expect(last.alpha == 0)
    }

    @Test
    func blendFadesMonotonicallyWithoutDensityJumps() {
        let curve = IslandCrownFade.curve
        for (previous, next) in zip(curve, curve.dropFirst()) {
            #expect(next.location > previous.location)
            #expect(next.alpha <= previous.alpha)
        }
    }

    /// A linear ramp holds the averaged slope all the way into the glass; the eased curve must end
    /// well under it, which is what removes the slope break the band is drawn from.
    @Test
    func blendEasesBothEndsToZeroSlope() throws {
        let slopes = Self.segmentSlopes()
        let linearSlope = Self.overallSlope()
        let headSlope = try #require(slopes.first)
        let tailSlope = try #require(slopes.last)
        let steepestSlope = try #require(slopes.max())

        #expect(headSlope < linearSlope * 0.5)
        #expect(tailSlope < linearSlope * 0.5)
        // The curve has to spend its fade somewhere, so its middle is steeper than a linear ramp's.
        #expect(steepestSlope > linearSlope * 1.15)
    }

    /// The three crown variants (expanded frosted, expanded transparent, compact recording) must all
    /// blend through the shared curve rather than their own straight ramps.
    @Test
    func everyCrownVariantBlendsThroughTheEasedCurve() throws {
        let source = try Self.surfaceSource()

        #expect(source.contains("crownFadeStops(peakOpacity: crownOpacity)"))
        #expect(source.contains("crownFadeStops(peakOpacity: 1)"))
        #expect(source.contains("crownFadeStops(peakOpacity: compactCrownOpacity)"))

        // The former inline ramps must not come back alongside the curve.
        #expect(!source.contains(".black.opacity(0.78)"))
        #expect(!source.contains(".black.opacity(0.34)"))
        #expect(!source.contains("crownOpacity * 0.70"))
        #expect(!source.contains("crownOpacity * 0.62"))
        #expect(!source.contains("crownOpacity * 0.35"))
        #expect(!source.contains("crownOpacity * 0.28"))
    }

    private static func segmentSlopes() -> [CGFloat] {
        let curve = IslandCrownFade.curve
        return zip(curve, curve.dropFirst()).map { previous, next in
            (previous.alpha - next.alpha) / (next.location - previous.location)
        }
    }

    /// Slope of the straight ramp the curve replaced, measured between the same endpoints.
    private static func overallSlope() -> CGFloat {
        let curve = IslandCrownFade.curve
        guard let first = curve.first, let last = curve.last else { return 0 }
        return (first.alpha - last.alpha) / (last.location - first.location)
    }

    private static func surfaceSource() throws -> String {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/Zisla/IslandSurface.swift")
        return try String(contentsOf: url, encoding: .utf8)
    }
}
