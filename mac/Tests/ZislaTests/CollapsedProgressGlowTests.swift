import AppKit
import SwiftUI
import Testing
import ZislaCore
import ZislaKit

@testable import Zisla

struct CollapsedProgressGlowTests {
    @Test
    func nativeContoursKeepTheirClosedPathContractAndRecoverWhenTheSdkOmitsAnExactTopPoint() {
        let rect = CGRect(x: 10, y: 20, width: 70, height: 32)
        let path = CompactIslandShape(layoutStyle: .pill).path(in: rect)
        var closures = 0
        path.forEach { if case .closeSubpath = $0 { closures += 1 } }
        #expect(closures == 1, "A full outline must preserve the native closed contour at its stroke join")
        var missingTop = Path()
        missingTop.move(to: CGPoint(x: rect.minX, y: rect.midY))
        missingTop.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
        missingTop.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        missingTop.closeSubpath()
        let recovered = CompactIslandShape.topCenteredPath(missingTop, in: rect)
        #expect(recovered.cgPath == missingTop.cgPath,
                "If a native path has no exact top point, preserve its contour instead of failing")
    }

    @Test
    func playbackProgressAdvancesFromElapsedTime() {
        let timestamp = Date(timeIntervalSince1970: 1_000)
        let snapshot = NowPlayingSnapshot(
            title: "Track",
            artist: "Artist",
            album: nil,
            artworkData: nil,
            duration: 200,
            elapsedTime: 40,
            timestamp: timestamp,
            isPlaying: true
        )

        #expect(CollapsedProgress.playbackFraction(for: snapshot, at: timestamp.addingTimeInterval(20)) == 0.3)
    }

    @Test
    func playbackProgressRejectsUnavailableOrInvalidDuration() {
        let base = NowPlayingSnapshot(
            title: "Track",
            artist: "Artist",
            album: nil,
            artworkData: nil,
            duration: 0,
            elapsedTime: 20,
            isPlaying: true
        )

        #expect(CollapsedProgress.playbackFraction(for: base, at: .now) == nil)
        #expect(CollapsedProgress.playbackFraction(
            for: NowPlayingSnapshot(
                title: base.title,
                artist: base.artist,
                album: nil,
                artworkData: nil,
                duration: 100,
                elapsedTime: nil,
                isPlaying: true
            ),
            at: .now
        ) == nil)
        #expect(CollapsedProgress.playbackFraction(
            for: NowPlayingSnapshot(
                title: base.title,
                artist: base.artist,
                album: nil,
                artworkData: nil,
                duration: 100,
                elapsedTime: 20,
                isPlaying: false
            ),
            at: .now
        ) == nil)
    }

    @Test
    func playbackProgressClampsAtTrackEnd() {
        let snapshot = NowPlayingSnapshot(
            title: "Track",
            artist: "Artist",
            album: nil,
            artworkData: nil,
            duration: 100,
            elapsedTime: 140,
            isPlaying: true
        )

        #expect(CollapsedProgress.playbackFraction(for: snapshot, at: .now) == 1)
    }

    @Test
    func dismissalProgressCountsDownAndClampsAtBounds() {
        let deadline = Date(timeIntervalSince1970: 1_010)

        #expect(CollapsedProgress.remainingFraction(
            until: deadline,
            totalDuration: 20,
            at: Date(timeIntervalSince1970: 1_000)
        ) == 0.5)
        #expect(CollapsedProgress.remainingFraction(until: deadline, totalDuration: 20, at: deadline) == 0)
        #expect(CollapsedProgress.remainingFraction(
            until: deadline,
            totalDuration: 20,
            at: Date(timeIntervalSince1970: 990)
        ) == 1)
        #expect(CollapsedProgress.remainingFraction(until: deadline, totalDuration: nil, at: .now) == nil)
    }

    @Test
    func progressGlowKeepsLightSurfaceContrastAndClampsTheTrimFraction() {
        #expect(CollapsedProgress.contrastBackdropOpacity >= 0.5)
        #expect(CollapsedProgress.leadingSegmentOpacity >= 0.6)
        #expect(CollapsedProgress.filledSegmentOpacity >= 0.9)
        #expect(CollapsedProgress.trailingSegmentOpacity >= 0.6)
        #expect(CollapsedProgress.normalized(0.5) == 0.5)
        #expect(CollapsedProgress.normalized(0.75) == 0.75)
        #expect(CollapsedProgress.normalized(2) == 1)
        #expect(CollapsedProgress.normalized(-1) == 0)
        #expect(CollapsedProgress.normalized(.infinity) == nil)
        #expect(CollapsedProgress.normalized(-.infinity) == nil)
        #expect(CollapsedProgress.normalized(.nan) == nil)
    }

    @Test(arguments: IslandLayoutStyle.allCases)
    func progressPathStartsAtTopCenterAndRunsClockwise(style: IslandLayoutStyle) throws {
        for size in Self.sizes {
            let rect = CGRect(origin: CGPoint(x: 7, y: 11), size: size)
            let path = CompactIslandShape(layoutStyle: style).path(in: rect)
            let points = Self.flattened(path)
            let first = try #require(points.first)
            let next = try #require(points.dropFirst().first(where: { $0 != first }))

            #expect(abs(first.x - rect.midX) < 0.000_001)
            #expect(abs(first.y - rect.minY) < 0.000_001)
            #expect(next.x > first.x, "Progress must first travel towards the right side")
            #expect(try #require(points.last) == first)
            #expect(path.boundingRect == rect)
        }
    }

    @Test(arguments: IslandLayoutStyle.allCases)
    func trimLengthRepresentsTheFractionOfTheEntireOutline(style: IslandLayoutStyle) {
        for size in Self.sizes {
            let rect = CGRect(origin: .zero, size: size)
            let outline = CompactIslandShape(layoutStyle: style)
                .inset(by: CollapsedProgress.outlineInset)
            let totalLength = Self.length(of: outline.path(in: rect))

            #expect(totalLength > size.width + size.height)
            for fraction in [0.1, 0.25, 0.5, 0.75, 1] {
                let length = Self.length(of: outline.trim(from: 0, to: fraction).path(in: rect))
                #expect(abs(length / totalLength - fraction) < 0.012,
                        "\(style), \(size), \(fraction) must use perimeter length, including curved corners")
            }
        }
    }

    @Test
    func notchKeepsItsNativeContinuousBottomCornersAndPillKeepsItsCapsule() {
        for size in Self.sizes {
            let rect = CGRect(origin: .zero, size: size)
            let radius = min(CompactBarContourMetrics(size: size).bottomRadius, size.height / 2, size.width / 2)
            let originalNotch = UnevenRoundedRectangle(
                cornerRadii: .init(
                    topLeading: 0, bottomLeading: radius, bottomTrailing: radius, topTrailing: 0
                ),
                style: .continuous
            ).path(in: rect)
            let notch = CompactIslandShape().path(in: rect)
            let capsule = Capsule().path(in: rect)
            let pill = CompactIslandShape(layoutStyle: .pill).path(in: rect)

            for y in stride(from: 0.25, through: Double(size.height), by: 1.5) {
                for x in stride(from: 0.25, through: Double(size.width), by: 1.5) {
                    let point = CGPoint(x: x, y: y)
                    #expect(notch.contains(point) == originalNotch.contains(point))
                    #expect(pill.contains(point) == capsule.contains(point))
                }
            }
        }
    }

    @Test(arguments: IslandLayoutStyle.allCases)
    func insetStrokesStayInsideTheWindowInBothOrientations(style: IslandLayoutStyle) {
        for size in Self.sizes {
            let rect = CGRect(origin: .zero, size: size)
            let shape = CompactIslandShape(layoutStyle: style)
            let outline = shape.inset(by: CollapsedProgress.outlineInset).path(in: rect)
            let stroke = outline.strokedPath(StrokeStyle(
                lineWidth: CollapsedProgress.outlineWidth, lineCap: .round, lineJoin: .round
            ))
            #expect(rect.contains(stroke.boundingRect), "The stroke must not be clipped at the screen edge")
            for point in Self.flattened(outline) {
                #expect(shape.path(in: rect).contains(point))
            }
        }
        #expect(CompactIslandShape(layoutStyle: style).path(in: .zero).isEmpty)
        #expect(CompactIslandShape(layoutStyle: style).inset(by: 2).path(
            in: CGRect(x: 0, y: 0, width: 2, height: 2)
        ).isEmpty)
    }

    @Test(arguments: IslandLayoutStyle.allCases)
    @MainActor
    func fullProgressPaintsAllFourEdgesAndLeavesTheMiddleClear(style: IslandLayoutStyle) throws {
        for size in Self.sizes {
            let pixels = try Self.rendered(progress: 1, style: style, size: size)
            let width = Int(size.width)
            let height = Int(size.height)
            let middleX = width / 2
            let middleY = height / 2

            #expect(Self.lit(pixels, width: width, x: middleX - 2...middleX + 2, y: 0...4))
            #expect(Self.lit(pixels, width: width, x: middleX - 2...middleX + 2, y: height - 5...height - 1))
            #expect(Self.lit(pixels, width: width, x: 0...4, y: middleY - 2...middleY + 2))
            #expect(Self.lit(pixels, width: width, x: width - 5...width - 1, y: middleY - 2...middleY + 2))
            #expect(!Self.lit(pixels, width: width, x: middleX - 3...middleX + 3, y: middleY - 3...middleY + 3))
        }
    }

    @Test(arguments: IslandLayoutStyle.allCases)
    @MainActor
    func halfProgressPaintsOnlyTheClockwiseHalf(style: IslandLayoutStyle) throws {
        for size in Self.sizes {
            let half = try Self.rendered(progress: 0.5, style: style, size: size)
            let full = try Self.rendered(progress: 1, style: style, size: size)
            let width = Int(size.width)
            let height = Int(size.height)
            let middleX = width / 2
            let middleY = height / 2

            #expect(Self.lit(half, width: width, x: width - 5...width - 1, y: middleY - 2...middleY + 2))
            #expect(!Self.lit(half, width: width, x: 0...4, y: middleY - 2...middleY + 2))
            #expect(!Self.lit(half, width: width, x: middleX / 2 - 2...middleX / 2 + 2, y: 0...4))
            let coverage = Double(half.filter { $0 > 0.2 }.count) / Double(full.filter { $0 > 0.2 }.count)
            #expect((0.42...0.58).contains(coverage))
        }
    }

    @Test(arguments: [0.0, -1, Double.nan, Double.infinity, -Double.infinity])
    @MainActor
    func zeroAndInvalidProgressPaintNoStroke(progress: Double) throws {
        for style in IslandLayoutStyle.allCases {
            let pixels = try Self.rendered(progress: progress, style: style, size: CGSize(width: 180, height: 34))
            #expect(pixels.allSatisfy { $0 == 0 })
        }
    }

    @Test @MainActor
    func overcompleteProgressMatchesACompleteOutline() throws {
        #expect(try Self.rendered(progress: 2) == Self.rendered(progress: 1))
    }

    @Test @MainActor
    func accessibilityModesPreserveProgressGeometryAndOpaqueContrast() throws {
        let normal = try Self.rendered(progress: 0.5)
        let reducedMotion = try Self.rendered(progress: 0.5, reduceMotion: true)
        let opaque = try Self.rendered(progress: 0.5, reduceTransparency: true)

        #expect(normal == reducedMotion)
        #expect(zip(opaque, normal).allSatisfy { $0 + 0.001 >= $1 },
                "Opaque accessibility strokes must retain every normal stroke pixel and increase contrast")
        #expect(opaque.indices.filter { opaque[$0] > 0.001 } == normal.indices.filter { normal[$0] > 0.001 },
                "Opacity changes must preserve the stroked perimeter geometry")
        #expect(opaque.reduce(0, +) > normal.reduce(0, +))
    }

    @Test @MainActor
    func progressRetainsItsSelectedTint() throws {
        let renderer = ImageRenderer(content: CollapsedProgressGlow(progress: 1, tint: Color(.displayP3, red: 1, green: 0, blue: 0))
            .frame(width: 180, height: 34).background(.black))
        renderer.scale = 1
        let bitmap = NSBitmapImageRep(cgImage: try #require(renderer.cgImage))
        let color = try #require(bitmap.colorAt(x: 90, y: 1)?.usingColorSpace(.deviceRGB))

        #expect(color.redComponent > 0.5)
        #expect(color.greenComponent < 0.05 && color.blueComponent < 0.05)
    }

    @Test
    func progressGlowLocalizationKeysExistForEveryLanguage() throws {
        let packageRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let localizationRoot = packageRoot
            .appendingPathComponent("Resources", isDirectory: true)
            .appendingPathComponent("Localization", isDirectory: true)
        let keys = [
            "提示条进度光效",
            "在收起态提示条边沿显示播放、下载和自动关闭进度",
        ]

        for language in AppLanguage.allCases {
            let url = localizationRoot
                .appendingPathComponent("\(language.rawValue).lproj", isDirectory: true)
                .appendingPathComponent("Localizable.strings")
            let table = try #require(NSDictionary(contentsOf: url) as? [String: String])
            for key in keys {
                let value = try #require(table[key], "\(language.rawValue) 缺少「\(key)」")
                #expect(!value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                if language != .simplifiedChinese {
                    #expect(value != key, "\(language.rawValue) 未翻译「\(key)」")
                }
            }
        }
    }

    private static let sizes = [
        CGSize(width: 180, height: 34), CGSize(width: 34, height: 180), CGSize(width: 34, height: 34),
    ]

    private static func flattened(_ path: Path) -> [CGPoint] {
        var points: [CGPoint] = []
        var current = CGPoint.zero
        var start = CGPoint.zero
        path.forEach { element in
            switch element {
            case .move(to: let point):
                current = point
                start = point
                points.append(point)
            case .line(to: let point):
                current = point
                points.append(point)
            case .quadCurve(to: let end, control: let control):
                let origin = current
                for step in 1...64 {
                    let t = CGFloat(step) / 64
                    let u = 1 - t
                    points.append(CGPoint(
                        x: u * u * origin.x + 2 * u * t * control.x + t * t * end.x,
                        y: u * u * origin.y + 2 * u * t * control.y + t * t * end.y
                    ))
                }
                current = end
            case .curve(to: let end, control1: let first, control2: let second):
                let origin = current
                for step in 1...64 {
                    let t = CGFloat(step) / 64
                    let u = 1 - t
                    points.append(CGPoint(
                        x: u * u * u * origin.x + 3 * u * u * t * first.x + 3 * u * t * t * second.x + t * t * t * end.x,
                        y: u * u * u * origin.y + 3 * u * u * t * first.y + 3 * u * t * t * second.y + t * t * t * end.y
                    ))
                }
                current = end
            case .closeSubpath:
                points.append(start)
                current = start
            }
        }
        return points
    }

    private static func length(of path: Path) -> Double {
        let points = flattened(path)
        return zip(points, points.dropFirst()).reduce(0.0) { length, segment in
            length + hypot(segment.1.x - segment.0.x, segment.1.y - segment.0.y)
        }
    }

    @MainActor
    private static func rendered(
        progress: Double, style: IslandLayoutStyle = .notch, size: CGSize = CGSize(width: 180, height: 34),
        reduceMotion: Bool = false, reduceTransparency: Bool = false
    ) throws -> [Double] {
        let renderer = ImageRenderer(content: CollapsedProgressGlow.rendering(
            progress: progress, tint: .green, layoutStyle: style,
            reduceMotion: reduceMotion, reduceTransparency: reduceTransparency
        )
            .frame(width: size.width, height: size.height)
            .clipShape(CompactIslandShape(layoutStyle: style))
            .background(.black))
        renderer.scale = 1
        let bitmap = NSBitmapImageRep(cgImage: try #require(renderer.cgImage))
        #expect(bitmap.pixelsWide == Int(size.width) && bitmap.pixelsHigh == Int(size.height))
        return try (0..<bitmap.pixelsHigh).flatMap { y in
            try (0..<bitmap.pixelsWide).map { x in
                Double(try #require(bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB)).greenComponent)
            }
        }
    }

    private static func lit(_ pixels: [Double], width: Int, x: ClosedRange<Int>, y: ClosedRange<Int>) -> Bool {
        y.contains { row in x.contains { column in pixels[row * width + column] > 0.2 } }
    }
}
