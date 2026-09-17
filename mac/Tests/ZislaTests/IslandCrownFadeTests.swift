import AppKit
import SwiftUI
import Testing
import ZislaKit

@testable import Zisla

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

    @MainActor
    @Test(arguments: CrownConfiguration.allCases, [1.0, 2.0])
    func renderedCrownPreservesItsSolidAndBlendHeights(configuration: CrownConfiguration, scale: CGFloat) throws {
        let crown = configuration.crown
        let bitmap = try Self.render(crown, scale: scale)
        try Self.expectProfile(bitmap, solidHeight: crown.solidHeight, blendHeight: crown.blendHeight)
    }

    @MainActor
    @Test(arguments: CrownConfiguration.allCases, [false, true])
    func animatedCrownHasNoBrightSeam(configuration: CrownConfiguration, isShrinking: Bool) throws {
        let expanded = configuration.crown
        let compact = configuration.initialCrown
        let start = isShrinking ? expanded : compact
        let end = isShrinking ? compact : expanded
        let progress = configuration.progress
        let solidHeight = start.solidHeight + (end.solidHeight - start.solidHeight) * progress
        let blendHeight = start.blendHeight + (end.blendHeight - start.blendHeight) * progress

        for scale: CGFloat in [1, 2] {
            // The parent surface resizes too; fixing its height hides the recycle regression.
            let bitmap = try Self.render(
                end, from: start, progress: progress, scale: scale,
                surfaceHeight: isShrinking ? 143 : 324,
                previousSurfaceHeight: isShrinking ? 324 : 143
            )
            try Self.expectProfile(bitmap, solidHeight: solidHeight, blendHeight: blendHeight)
        }
    }

    @MainActor
    @Test
    func emptyCrownDoesNotPaintAndCanExpand() throws {
        let empty = IslandCrownSurface(solidHeight: 0, blendHeight: 0, peakOpacity: 1)
        let bitmap = try Self.render(empty, scale: 2)
        let background = try Self.red(bitmap, x: 84, y: 8)
        for y: CGFloat in [0.5, 10, 200] {
            #expect(abs(try Self.red(bitmap, x: 32, y: y) - background) <= 1)
        }

        let expanded = CrownConfiguration.transparent.crown
        let animated = try Self.render(expanded, from: empty, progress: 0.375, scale: 2)
        try Self.expectProfile(
            animated, solidHeight: expanded.solidHeight * 0.375, blendHeight: expanded.blendHeight * 0.375
        )
    }

    @MainActor
    @Test(arguments: [0.0, 0.25, 34.0, 196.0])
    func gradientCoordinatesRemainFiniteAtEmptyAndSubpixelHeights(height: CGFloat) throws {
        let crown = IslandCrownSurface(solidHeight: height / 2, blendHeight: height / 2, peakOpacity: 1)
        let stops = crown.gradientStops
        #expect(stops.allSatisfy { $0.location.isFinite && (0...1).contains($0.location) })
        if height > 0 {
            #expect(try #require(stops.last).location == 1)
        }
    }

    enum CrownConfiguration: CaseIterable, Sendable {
        case frosted
        case transparent
        case compactFrosted
        case compactTransparent

        @MainActor
        var crown: IslandCrownSurface {
            switch self {
            case .frosted:
                IslandCrownSurface(solidHeight: 132, blendHeight: 60, peakOpacity: 0.98)
            case .transparent:
                IslandCrownSurface(solidHeight: 132, blendHeight: 64, peakOpacity: 1)
            case .compactFrosted:
                IslandCrownSurface(solidHeight: 34, blendHeight: 20, peakOpacity: 0.98)
            case .compactTransparent:
                IslandCrownSurface(solidHeight: 34, blendHeight: 20, peakOpacity: 1)
            }
        }

        @MainActor
        var initialCrown: IslandCrownSurface {
            switch self {
            case .frosted, .transparent:
                IslandCrownSurface(solidHeight: 114, blendHeight: 29, peakOpacity: crown.peakOpacity)
            case .compactFrosted, .compactTransparent:
                IslandCrownSurface(solidHeight: 24.5, blendHeight: 0, peakOpacity: crown.peakOpacity)
            }
        }

        var progress: CGFloat {
            switch self {
            case .frosted, .transparent: 0.375
            case .compactFrosted, .compactTransparent: 0.5
            }
        }
    }

    @MainActor
    private static func expectProfile(_ bitmap: NSBitmapImageRep, solidHeight: CGFloat, blendHeight: CGFloat) throws {
        let solid = try red(bitmap, x: 68, y: 8)
        let half = try red(bitmap, x: 76, y: 8)
        let background = try red(bitmap, x: 84, y: 8)
        let top = try red(bitmap, x: 32, y: solidHeight / 2)
        let middle = try red(bitmap, x: 32, y: solidHeight + blendHeight / 2)
        let bottom = try red(bitmap, x: 32, y: solidHeight + blendHeight + 2)

        #expect(abs(top - solid) <= 1)
        #expect(abs(middle - half) <= 5, "The blend must stay centered on its interpolated height.")
        #expect(abs(bottom - background) <= 1, "The crown must finish fading before the rest of the glass.")

        let scale = CGFloat(bitmap.pixelsWide) / 96
        let rows = 1..<Int((solidHeight + blendHeight + 1) * scale)
        let samples = try rows.map { try red(bitmap, x: 32, y: (CGFloat($0) + 0.5) / scale) }
        let brightestSeam = zip(samples, samples.dropFirst()).map { $0 - $1 }.max() ?? 0
        #expect(brightestSeam <= 5, "The crown may lighten toward the glass, but never flash bright and then dark again.")
    }

    @MainActor
    private static func render(
        _ crown: IslandCrownSurface,
        from previous: IslandCrownSurface? = nil,
        progress: CGFloat = 0.375,
        scale: CGFloat,
        surfaceHeight: CGFloat = 256,
        previousSurfaceHeight: CGFloat = 256
    ) throws -> NSBitmapImageRep {
        _ = NSApplication.shared
        let bounds = CGRect(x: 0, y: 0, width: 96, height: 256)
        let window = NSWindow(contentRect: bounds, styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        let host = NSHostingView(rootView: CrownRenderView(
            crown: previous ?? crown,
            progress: progress,
            scale: scale,
            surfaceHeight: previous == nil ? surfaceHeight : previousSurfaceHeight
        ))
        host.sizingOptions = []
        window.contentView = host
        let bitmap = try #require(NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int(bounds.width * scale),
            pixelsHigh: Int(bounds.height * scale),
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ))
        bitmap.size = bounds.size
        host.layoutSubtreeIfNeeded()
        host.cacheDisplay(in: host.bounds, to: bitmap)

        if let previous {
            host.rootView = CrownRenderView(
                crown: crown, progress: progress, scale: scale, surfaceHeight: surfaceHeight
            )
            let previousHeight = previous.solidHeight + previous.blendHeight
            let height = crown.solidHeight + crown.blendHeight
            let sampledHeight = previousHeight + (height - previousHeight) * progress
            let markerY = (previousHeight + sampledHeight) / 2
            let isGrowing = height > previousHeight
            let deadline = Date().addingTimeInterval(1)
            var sampledFrame = false
            repeat {
                RunLoop.main.run(mode: .default, before: min(deadline, Date().addingTimeInterval(1.0 / 120)))
                host.layoutSubtreeIfNeeded()
                host.cacheDisplay(in: host.bounds, to: bitmap)
                let marker = try color(bitmap, x: 92, y: markerY)
                let markerIsRed = marker.greenComponent < 0.1
                sampledFrame = markerIsRed == isGrowing
            } while !sampledFrame && Date() < deadline
            try #require(sampledFrame, "The hidden renderer must reach the frozen animation frame before pixels are inspected.")
        }

        #expect(!window.isVisible)
        return bitmap
    }

    private static func red(_ bitmap: NSBitmapImageRep, x: CGFloat, y: CGFloat) throws -> Int {
        let scale = CGFloat(bitmap.pixelsWide) / 96
        // Interpolate pixel centers so a 1x sample does not shift the blend midpoint by half a point.
        let row = y * scale - 0.5
        let fraction = row - floor(row)
        let lower = try color(bitmap, x: x, y: (floor(row) + 0.5) / scale).redComponent
        let upper = try color(bitmap, x: x, y: (floor(row) + 1.5) / scale).redComponent
        return Int(((lower + (upper - lower) * fraction) * 255).rounded())
    }

    private static func color(_ bitmap: NSBitmapImageRep, x: CGFloat, y: CGFloat) throws -> NSColor {
        let scale = CGFloat(bitmap.pixelsWide) / 96
        return try #require(bitmap.colorAt(x: Int(x * scale), y: Int(y * scale))?.usingColorSpace(.sRGB))
    }

    // Freeze the animation itself; the render loop only waits for that known frame to arrive.
    private struct FrozenProgress: CustomAnimation {
        let progress: CGFloat

        func animate<V: VectorArithmetic>(value: V, time: TimeInterval, context: inout AnimationContext<V>) -> V? {
            value.scaled(by: progress)
        }
    }

    private struct CrownRenderView: View {
        let crown: IslandCrownSurface
        let progress: CGFloat
        let scale: CGFloat
        let surfaceHeight: CGFloat

        var body: some View {
            HStack(spacing: 0) {
                ZStack(alignment: .top) {
                    Color(white: 0.42)
                    crown
                }
                .frame(width: 64, height: surfaceHeight)
                .frame(height: 256, alignment: .top)
                .background(Color(white: 0.42))
                Color(white: 0.42).overlay(.black.opacity(crown.peakOpacity)).frame(width: 8)
                Color(white: 0.42).overlay(.black.opacity(crown.peakOpacity / 2)).frame(width: 8)
                Color(white: 0.42).frame(width: 8)
                // This independent marker distinguishes the frozen frame from the initial snapshot.
                Color(red: 1, green: 0, blue: 0)
                    .frame(height: crown.solidHeight + crown.blendHeight)
                    .frame(maxHeight: .infinity, alignment: .top)
                    .frame(width: 8)
                    .background(.white)
            }
            .frame(width: 96, height: 256)
            .animation(
                Animation(FrozenProgress(progress: progress)),
                value: CGSize(width: crown.solidHeight, height: crown.blendHeight)
            )
            .environment(\.displayScale, scale)
        }
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

}
