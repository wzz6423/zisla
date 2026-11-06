import AppKit
import Foundation
import SwiftUI
import Testing
import ZislaCore
@testable import Zisla

struct FirstLaunchSystemGreetingArtworkTests {
    private typealias Curve = [String: [Double]]
    private static let curve: Curve = [
        "p0": [0, 0, 0, 3], "p1": [0, 50, 0, 3],
        "p2": [100, 50, 0, 3], "p3": [100, 100, 0, 3],
    ]

    private static func data(strokes: [[Curve]] = [[curve]], scale: [Double] = [1, 1, 1, 1.2]) throws -> Data {
        try JSONSerialization.data(withJSONObject: ["strokes": strokes, "scale": scale], options: [.sortedKeys])
    }

    @Test(arguments: AppLanguage.allCases)
    func systemResourceNamesCoverAllLocalesAndKeepChineseAsNiHao(language: AppLanguage) throws {
        let names: [AppLanguage: String] = [
            .simplifiedChinese: "zh_CN", .traditionalChinese: "zh_CN", .english: "en",
            .japanese: "ja", .korean: "ko", .french: "fr", .german: "de", .spanish: "es",
            .brazilianPortuguese: "pt_BR", .italian: "it", .dutch: "nl", .russian: "ru",
            .arabic: "ar", .thai: "th", .indonesian: "id", .vietnamese: "vi", .turkish: "tr",
        ]
        let data = try Self.data()
        var urls: [URL] = []
        let artwork = try FirstLaunchGreetingArtwork.systemArtwork(for: language) { url in
            urls.append(url)
            return data
        }
        #expect(Set(names.keys) == Set(AppLanguage.allCases))
        #expect(urls.map(\.path) == [
            "/System/Library/ExtensionKit/Extensions/Hello.appex/Contents/Resources/Languages/\(names[language]!).json",
        ])
        #expect(artwork.strokes.count == 1)
    }

    @Test
    func decodingPreservesBezierControlsAndUniformAspectWhileFlippingFontYAxis() throws {
        let data = try Self.data(scale: [2, 1, 1, 1.5])
        let artwork = try FirstLaunchGreetingArtwork(systemData: data)
        let expected = Path { path in
            path.move(to: CGPoint(x: 16, y: 148))
            path.addCurve(to: CGPoint(x: 280, y: 16),
                          control1: CGPoint(x: 16, y: 82), control2: CGPoint(x: 280, y: 82))
        }
        #expect(artwork.strokes.count == 1)
        try Self.expectPath(artwork.strokes[0], matching: expected)
        #expect(artwork.size == CGSize(width: 296, height: 164))
        #expect(abs(artwork.lineWidths[0] - 11.88) < 0.000001, "The source pen radius must become a stroke diameter")
        #expect(artwork.fittedLineWidth(in: CGSize(width: 640, height: 180), index: 0, baseWidth: 6) > artwork.lineWidths[0])
        let again = try FirstLaunchGreetingArtwork(systemData: data)
        #expect(artwork.strokes == again.strokes)
        #expect(artwork.size == again.size)
        #expect(artwork.lineWidths == again.lineWidths)
    }

    @Test
    func zeroTravelDotsHaveWritingTimeAndRenderAsRoundMarks() throws {
        let normal = Path { path in
            path.move(to: CGPoint(x: 10, y: 20))
            path.addCurve(to: CGPoint(x: 110, y: 20),
                          control1: CGPoint(x: 40, y: 20), control2: CGPoint(x: 80, y: 20))
        }
        let dot = Path { path in
            path.move(to: .zero)
            path.addCurve(to: .zero, control1: .zero, control2: .zero)
        }
        let artwork = FirstLaunchGreetingArtwork(strokes: [normal, dot], size: CGSize(width: 120, height: 30), lineWidths: [8, 8])
        #expect(artwork.strokeLengths[1] == 8)
        #expect(artwork.strokeProgress(at: 0, index: 1) == 0)
        #expect(artwork.strokeProgress(at: 100.0 / 108, index: 1) == 0)
        #expect(abs(artwork.strokeProgress(at: 104.0 / 108, index: 1) - 0.5) < 0.000001)
        #expect(artwork.strokeProgress(at: 1, index: 1) == 1)
        let empty = dot.trimmedPath(from: 0, to: artwork.strokeProgress(at: 0, index: 1))
        let written = dot.trimmedPath(from: 0, to: artwork.strokeProgress(at: 1, index: 1))
        #expect(empty.isEmpty)
        #expect(written.strokedPath(StrokeStyle(lineWidth: 8, lineCap: .round, lineJoin: .round)).boundingRect
                == CGRect(x: -4, y: -4, width: 8, height: 8))
    }

    @Test
    func sourceDotsRemainSeparateAndFinishAfterTheMainStroke() throws {
        let dot: Curve = ["p0": [50, 120, 0, 4], "p1": [50, 120, 0, 4],
                          "p2": [50, 120, 0, 4], "p3": [50, 120, 0, 4]]
        let artwork = try FirstLaunchGreetingArtwork(systemData: Self.data(strokes: [[Self.curve], [dot]]))
        #expect(artwork.strokes.count == 2)
        #expect(artwork.strokes[1].boundingRect.size == .zero)
        #expect(abs(artwork.lineWidths[1] / artwork.lineWidths[0] - 4.0 / 3) < 0.000001,
                "Dots must retain their own radius instead of inheriting the main pen width")
        #expect(artwork.strokeLengths.allSatisfy { $0 > 0 && $0.isFinite })
        #expect(artwork.strokeProgress(at: 0, index: 1) == 0)
        #expect(artwork.strokeProgress(at: 1, index: 1) == 1)
    }

    @Test @MainActor
    func completedAnimationPaintsTheIndependentDotInTheCanvas() throws {
        let dot: Curve = ["p0": [50, 120, 0, 4], "p1": [50, 120, 0, 4],
                          "p2": [50, 120, 0, 4], "p3": [50, 120, 0, 4]]
        let artwork = try FirstLaunchGreetingArtwork(systemData: Self.data(strokes: [[Self.curve], [dot]]))
        let size = CGSize(width: 240, height: 180)
        let renderer = ImageRenderer(content: FirstLaunchGreetingAnimation(
            timeline: FirstLaunchGreetingTimeline(preferredLanguage: .english),
            startedAt: nil, preferredLanguage: .english, artworkForLanguage: { _ in artwork }
        ).frame(width: size.width, height: size.height).accentColor(.blue).background(.white))
        let bitmap = NSBitmapImageRep(cgImage: try #require(renderer.cgImage))
        let center = artwork.fittedStrokes(in: size)[1].boundingRect.origin
        let color = try #require(bitmap.colorAt(x: Int(center.x.rounded()), y: Int(center.y.rounded()))?.usingColorSpace(.sRGB))
        #expect(color.redComponent < 0.5, "Canvas must paint zero-travel dots after the main stroke")
    }

    @Test
    func missingAndUnreadableSystemResourcesPropagateWithoutWriting() {
        for error in [CocoaError(.fileReadNoSuchFile), CocoaError(.fileReadNoPermission)] {
            var urls: [URL] = []
            #expect(throws: error) {
                try FirstLaunchGreetingArtwork.systemArtwork(for: .english) { url in
                    urls.append(url)
                    throw error
                }
            }
            #expect(urls.count == 1)
        }
    }

    @Test
    func catalogKeepsValidLocalesAndOmitsMissingUnreadableOrCorruptResources() throws {
        let valid = try Self.data()
        let catalog = FirstLaunchGreetingArtwork.makeCatalog { url in
            switch url.deletingPathExtension().lastPathComponent {
            case "en": throw CocoaError(.fileReadNoSuchFile)
            case "ar": throw CocoaError(.fileReadNoPermission)
            case "ru": return Data("{}".utf8)
            default: return valid
            }
        }
        #expect(Set(catalog.keys) == Set(AppLanguage.allCases).subtracting([.english, .arabic, .russian]))
        #expect(catalog.values.allSatisfy { $0.strokes.count == 1 && $0.lineWidths.count == 1 })
        #expect(FirstLaunchGreetingArtwork.makeCatalog { _ in throw CocoaError(.fileReadNoSuchFile) }.isEmpty)
        let recovered = FirstLaunchGreetingArtwork.makeCatalog { _ in valid }
        #expect(Set(recovered.keys) == Set(AppLanguage.allCases))
    }

    @Test
    func thickMarksFitWithoutClippingUnderIncreasedContrast() throws {
        let artwork = try FirstLaunchGreetingArtwork(systemData: Self.data(scale: [1, 1, 1, 8]))
        #expect(artwork.size.height > 164)
        for size in [CGSize(width: 80, height: 56), CGSize(width: 240, height: 120), CGSize(width: 640, height: 180)] {
            let bounds = CGRect(origin: .zero, size: size)
            let strokes = artwork.fittedStrokes(in: size)
            for (index, stroke) in strokes.enumerated() {
                let radius = artwork.fittedLineWidth(in: size, index: index, baseWidth: 6) / 2
                #expect(bounds.contains(stroke.boundingRect.insetBy(dx: -radius, dy: -radius)))
            }
        }
    }

    @Test
    func malformedScaleAndPointArraysAreRejectedBeforeIndexing() throws {
        for count in [0, 1, 2, 3, 5] {
            #expect(throws: DecodingError.self) {
                try FirstLaunchGreetingArtwork(systemData: Self.data(scale: Array(repeating: 1, count: count)))
            }
            for key in ["p0", "p1", "p2", "p3"] {
                var curve = Self.curve
                curve[key] = Array(repeating: 1, count: count)
                #expect(throws: DecodingError.self) {
                    try FirstLaunchGreetingArtwork(systemData: Self.data(strokes: [[curve]]))
                }
            }
        }
        for value in [0.0, -1] {
            for index in 0..<4 {
                var scale = [1.0, 1, 1, 1.2]
                scale[index] = value
                #expect(throws: DecodingError.self) {
                    try FirstLaunchGreetingArtwork(systemData: Self.data(scale: scale))
                }
            }
            for key in ["p0", "p1", "p2", "p3"] {
                var curve = Self.curve
                curve[key]![3] = value
                #expect(throws: DecodingError.self) {
                    try FirstLaunchGreetingArtwork(systemData: Self.data(strokes: [[curve]]))
                }
            }
        }
    }

    @Test
    func emptyFlatAndOverflowingDrawingsAreRejected() throws {
        let dot: Curve = ["p0": [0, 0, 0, 3], "p1": [0, 0, 0, 3],
                          "p2": [0, 0, 0, 3], "p3": [0, 0, 0, 3]]
        var vertical = Self.curve
        var horizontal = Self.curve
        for key in ["p0", "p1", "p2", "p3"] {
            vertical[key]![0] = 0
            horizontal[key]![1] = 0
        }
        for strokes in [[], [[]], [[dot]], [[vertical]], [[horizontal]], [[Self.curve], []]] as [[[Curve]]] {
            #expect(throws: DecodingError.self) {
                try FirstLaunchGreetingArtwork(systemData: Self.data(strokes: strokes))
            }
        }
        for scale in [[Double.greatestFiniteMagnitude, 1, 1, 1.2],
                      [1, Double.greatestFiniteMagnitude, 1, 1.2],
                      [1, 1, 1, Double.greatestFiniteMagnitude]] {
            #expect(throws: DecodingError.self) {
                try FirstLaunchGreetingArtwork(systemData: Self.data(scale: scale))
            }
        }
    }

    @Test
    func everyTruncatedFixtureIsRejectedAndAValidDecodeStillSucceeds() throws {
        let data = try Self.data()
        for end in data.indices {
            #expect(throws: DecodingError.self) {
                try FirstLaunchGreetingArtwork(systemData: data.prefix(end))
            }
        }
        #expect(try FirstLaunchGreetingArtwork(systemData: data).strokes.count == 1)
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["ZISLA_RUN_SYSTEM_GREETING_TESTS"] == "1"))
    func installedSystemLetteringKeepsEveryCurveDotAndLanguageWithoutMirroring() throws {
        struct Drawing: Decodable {
            let strokes: [[Curve]]
            let scale: [CGFloat]
        }
        let catalog = FirstLaunchGreetingArtwork.makeCatalog()
        #expect(Set(catalog.keys) == Set(AppLanguage.allCases))
        for language in AppLanguage.allCases {
            let artwork = try #require(FirstLaunchGreetingArtwork.artwork(for: language))
            var source: Data?
            _ = try FirstLaunchGreetingArtwork.systemArtwork(for: language) { url in
                let data = try Data(contentsOf: url)
                source = data
                return data
            }
            let drawing = try JSONDecoder().decode(Drawing.self, from: #require(source))
            let paths = drawing.strokes.map { curves in
                Path { path in
                    func point(_ values: [Double]) -> CGPoint {
                        CGPoint(x: CGFloat(values[0]) * drawing.scale[0], y: -CGFloat(values[1]) * drawing.scale[1])
                    }
                    path.move(to: point(curves[0]["p0"]!))
                    for curve in curves {
                        path.addCurve(to: point(curve["p3"]!),
                                      control1: point(curve["p1"]!), control2: point(curve["p2"]!))
                    }
                }
            }
            let bounds = paths.reduce(CGRect.null) { $0.union($1.boundingRect) }
            let scale = (artwork.size.height - 32) / bounds.height
            #expect(abs(artwork.size.width - (bounds.width * scale + 32)) < 0.001)
            #expect(artwork.strokes.count == paths.count)
            for (index, path) in paths.enumerated() {
                let expected = path.applying(CGAffineTransform(
                    a: scale, b: 0, c: 0, d: scale,
                    tx: 16 - bounds.minX * scale, ty: 16 - bounds.minY * scale
                ))
                try Self.expectPath(artwork.strokes[index], matching: expected)
                #expect(artwork.strokeProgress(at: 0, index: index) == 0)
                #expect(artwork.strokeProgress(at: 1, index: index) == 1)
            }
            for size in [CGSize(width: 80, height: 56), CGSize(width: 240, height: 120), CGSize(width: 640, height: 180)] {
                let fitted = artwork.fittedStrokes(in: size)
                for (index, path) in fitted.enumerated() {
                    let radius = artwork.fittedLineWidth(in: size, index: index, baseWidth: 6) / 2
                    #expect(CGRect(origin: .zero, size: size).contains(path.boundingRect.insetBy(dx: -radius, dy: -radius)))
                }
            }
            if [.french, .italian, .vietnamese, .arabic].contains(language) {
                #expect(artwork.strokes.contains { $0.boundingRect.size == .zero }, "Accented lettering must retain its separate dot")
            }
        }
        #expect(catalog[.simplifiedChinese]?.strokes == catalog[.traditionalChinese]?.strokes)
        #expect(catalog[.german]?.strokes == catalog[.dutch]?.strokes)
    }

    private static func expectPath(_ actual: Path, matching expected: Path) throws {
        var actualElements: [Path.Element] = []
        var expectedElements: [Path.Element] = []
        actual.forEach { actualElements.append($0) }
        expected.forEach { expectedElements.append($0) }
        #expect(actualElements.count == expectedElements.count)
        for (actual, expected) in zip(actualElements, expectedElements) {
            switch (actual, expected) {
            case let (.move(a), .move(b)):
                expectPoint(a, matching: b)
            case let (.curve(a, a1, a2), .curve(b, b1, b2)):
                expectPoint(a, matching: b)
                expectPoint(a1, matching: b1)
                expectPoint(a2, matching: b2)
            default:
                Issue.record("Importing artwork must retain every original cubic segment")
            }
        }
    }

    private static func expectPoint(_ actual: CGPoint, matching expected: CGPoint) {
        // SwiftUI stores transformed path coordinates at float precision.
        #expect(abs(actual.x - expected.x) < 0.0001 && abs(actual.y - expected.y) < 0.0001,
                "Importing artwork must preserve each endpoint and control point")
    }
}
