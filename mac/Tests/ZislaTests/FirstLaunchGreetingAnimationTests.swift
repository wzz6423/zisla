import AppKit
import SwiftUI
import Testing
import ZislaCore
@testable import Zisla

struct FirstLaunchGreetingAnimationTests {
    @Test(arguments: AppLanguage.allCases)
    func greetingSequenceIncludesEveryLanguageWithoutDeduplicatingTranslations(language: AppLanguage) {
        let timeline = FirstLaunchGreetingTimeline(preferredLanguage: language)
        let first: [AppLanguage] = [.english, .simplifiedChinese, .german]
        let expected = first + AppLanguage.allCases.filter { !first.contains($0) }
        #expect(timeline.languages == FirstLaunchOnboardingSession.greetingLanguages)
        #expect(timeline.languages == expected)
        #expect(timeline.languages.count == 17)
        #expect(Set(timeline.languages) == Set(AppLanguage.allCases))
        #expect(timeline.languages.contains(.simplifiedChinese))
        #expect(timeline.languages.contains(.traditionalChinese))
        #expect(timeline.wordDuration == 2.4)
    }

    @Test(arguments: AppLanguage.allCases)
    func everyGreetingRepeatsAcrossMultipleCycles(language: AppLanguage) {
        let timeline = FirstLaunchGreetingTimeline(preferredLanguage: language)
        let duration = Double(timeline.languages.count) * timeline.wordDuration
        for cycle in [0, 1, 2, 17, 1_000_000] {
            for (index, language) in timeline.languages.enumerated() {
                let frame = timeline.frame(at: Double(cycle) * duration + (Double(index) + 0.75) * timeline.wordDuration)
                #expect(frame.language == language)
                #expect(frame.progress == 1)
                #expect(frame.opacity == 1)
            }
        }
    }

    @Test
    func cycleBoundariesRestartWithoutFreezingOrSkippingTheLastFrame() {
        let timeline = FirstLaunchGreetingTimeline(preferredLanguage: .english)
        let duration = Double(timeline.languages.count) * timeline.wordDuration
        for cycle in [1, 2, 3, 17, 1_000_000] {
            let boundary = Double(cycle) * duration
            let before = timeline.frame(at: boundary.nextDown)
            #expect(before.language == timeline.languages.last)
            #expect(before.progress == 1)
            #expect(before.opacity >= 0 && before.opacity < 0.001)
            let first = timeline.frame(at: boundary)
            #expect(first.language == .english)
            #expect(first.progress == 0)
            #expect(first.opacity == 1)
            let after = timeline.frame(at: boundary.nextUp)
            #expect(after.language == .english)
            #expect(after.progress > 0 && after.progress < 0.001)
        }
        for (index, language) in timeline.languages.enumerated() {
            let frame = timeline.frame(at: Double(index) * timeline.wordDuration)
            #expect(frame.language == language)
            #expect(frame.progress == 0)
            #expect(frame.opacity == 1)
        }
    }

    @Test
    func framesStayBoundedForNegativeAndLongRunningElapsedTimes() {
        let timeline = FirstLaunchGreetingTimeline(preferredLanguage: .arabic)
        for elapsed in [-Double.greatestFiniteMagnitude, -1, 0, Double.greatestFiniteMagnitude, .infinity, -.infinity, .nan] {
            let frame = timeline.frame(at: elapsed)
            #expect(timeline.languages.contains(frame.language))
            #expect((0...1).contains(frame.progress))
            #expect((0...1).contains(frame.opacity))
        }
        for elapsed in [-1.0, 0] {
            let frame = timeline.frame(at: elapsed)
            #expect(frame.language == .english)
            #expect(frame.progress == 0)
            #expect(frame.opacity == 1)
        }
        let duration = Double(timeline.languages.count) * timeline.wordDuration
        for step in 0...1_224 {
            let frame = timeline.frame(at: Double(step) * duration / 408)
            #expect(timeline.languages.contains(frame.language))
            #expect((0...1).contains(frame.progress))
            #expect((0...1).contains(frame.opacity))
        }
    }

    @Test
    func penStrokesFitSmallLargeAndEmptyLayouts() {
        let artwork = Self.sampleArtwork
        #expect(!artwork.strokes.isEmpty)
        #expect(artwork.strokeLengths.allSatisfy { $0.isFinite && $0 > 0 })
        for size in [CGSize(width: 80, height: 56), CGSize(width: 240, height: 120), CGSize(width: 640, height: 180)] {
            let bounds = CGRect(origin: .zero, size: size)
            let fitted = artwork.fittedStrokes(in: size)
            #expect(fitted.count == artwork.strokes.count)
            for (index, stroke) in fitted.enumerated() {
                let radius = artwork.fittedLineWidth(in: size, index: index, baseWidth: 6) / 2
                #expect(!stroke.isEmpty)
                let points = Self.samples(stroke)
                #expect(!points.isEmpty)
                #expect(points.allSatisfy { $0.x.isFinite && $0.y.isFinite })
                #expect(bounds.contains(stroke.boundingRect.insetBy(dx: -radius, dy: -radius)))
            }
            let union = fitted.reduce(CGRect.null) { $0.union($1.boundingRect) }
            #expect(abs(union.midX - size.width / 2) < size.width * 0.15)
            let original = artwork.strokes.reduce(CGRect.null) { $0.union($1.boundingRect) }
            let scale = min((size.width - 16) / artwork.size.width, (size.height - 16) / artwork.size.height)
            #expect(abs(union.width - original.width * scale) < 0.001)
            #expect(abs(union.height - original.height * scale) < 0.001)
        }
        for size in [CGSize.zero, CGSize(width: 12, height: 120), CGSize(width: 240, height: 12)] {
            #expect(artwork.fittedStrokes(in: size).isEmpty)
            #expect(artwork.fittedLineWidth(in: size, index: 0, baseWidth: 5) == 0)
        }
    }

    @Test
    func artworkLanguageSetMatchesTheLocalizedGreetingContract() {
        let expected: [AppLanguage: String] = [
            .english: "Hello", .simplifiedChinese: "你好", .traditionalChinese: "你好",
            .german: "hallo", .spanish: "Hola", .french: "Bonjour", .brazilianPortuguese: "Olá",
            .indonesian: "Halo", .korean: "안녕하세요", .italian: "Ciao", .dutch: "Hallo",
            .russian: "привет", .arabic: "مرحبًا", .turkish: "Merhaba",
            .vietnamese: "Xin chào", .thai: "สวัสดี", .japanese: "こんにちは",
        ]
        #expect(Set(expected.keys) == Set(AppLanguage.allCases))
        for (language, text) in expected {
            #expect(AppLocalization.string("onboarding.hello", language: language) == text)
        }
    }

    @Test(arguments: AppLanguage.allCases) @MainActor
    func unavailableSystemLetteringRendersTheLocalizedGreeting(language: AppLanguage) throws {
        let view = FirstLaunchGreetingAnimation(
            timeline: FirstLaunchGreetingTimeline(preferredLanguage: language),
            startedAt: nil, preferredLanguage: language, artworkForLanguage: { _ in nil }
        )
        let reference = Text(AppLocalization.string("onboarding.hello", language: language))
            .font(.system(size: 64, weight: .light, design: .rounded))
            .foregroundStyle(Color.accentColor)
            .lineLimit(1)
            .minimumScaleFactor(0.2)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        func pixels(_ content: some View) throws -> [UInt8] {
            let renderer = ImageRenderer(content: content.frame(width: 240, height: 120)
                .background(.white)
                .accentColor(.blue)
                .environment(\.colorScheme, .light)
                .environment(\.layoutDirection, language.isRightToLeft ? .rightToLeft : .leftToRight))
            let bitmap = NSBitmapImageRep(cgImage: try #require(renderer.cgImage))
            var result: [UInt8] = []
            for y in 0..<bitmap.pixelsHigh {
                for x in 0..<bitmap.pixelsWide {
                    let color = try #require(bitmap.colorAt(x: x, y: y)?.usingColorSpace(.sRGB))
                    result.append(UInt8((color.redComponent * 255).rounded()))
                }
            }
            return result
        }
        let actual = try pixels(view)
        let expected = try pixels(reference)
        #expect(actual.contains { $0 < 128 }, "Missing system resources must leave a visible greeting")
        #expect(actual == expected, "The fallback must use the requested locale, including Russian and Arabic")
    }

    @Test
    func writingTimeTracksDistanceAndSoftensEachPenLift() {
        let short = Path { path in
            path.move(to: .zero)
            path.addCurve(to: CGPoint(x: 10, y: 0), control1: CGPoint(x: 3, y: 0), control2: CGPoint(x: 7, y: 0))
        }
        let long = Path { path in
            path.move(to: CGPoint(x: 10, y: 0))
            path.addCurve(to: CGPoint(x: 110, y: 0), control1: CGPoint(x: 40, y: 0), control2: CGPoint(x: 80, y: 0))
        }
        let artwork = FirstLaunchGreetingArtwork(strokes: [short, long], size: CGSize(width: 120, height: 30), lineWidths: [5, 5])
        #expect(abs(artwork.strokeLengths[0] - 10) < 0.001)
        #expect(abs(artwork.strokeLengths[1] - 100) < 0.001)
        #expect(abs(artwork.strokeProgress(at: 5.0 / 110, index: 0) - 0.5) < 0.001)
        #expect(artwork.strokeProgress(at: 10.0 / 110, index: 0) == 1)
        #expect(artwork.strokeProgress(at: 10.0 / 110, index: 1) == 0)
        #expect(abs(artwork.strokeProgress(at: 60.0 / 110, index: 1) - 0.5) < 0.001)
        let epsilon: CGFloat = 0.001
        #expect(artwork.strokeProgress(at: epsilon * 10 / 110, index: 0) < epsilon / 10)
        #expect(1 - artwork.strokeProgress(at: (1 - epsilon) * 10 / 110, index: 0) < epsilon / 10)
        #expect(artwork.strokeProgress(at: -1, index: 0) == 0)
        #expect(artwork.strokeProgress(at: 2, index: 1) == 1)
    }

    @Test
    func writingProgressIsMonotoneAndEveryStrokeCompletesBeforeFade() {
        let artwork = Self.sampleArtwork
        var previous = Array(repeating: CGFloat.zero, count: artwork.strokes.count)
        for step in 0...240 {
            let progress = CGFloat(step) / 240
            var hasUnfinishedStroke = false
            for index in artwork.strokes.indices {
                let value = artwork.strokeProgress(at: progress, index: index)
                #expect((0...1).contains(value))
                #expect(value >= previous[index])
                if hasUnfinishedStroke { #expect(value == 0) }
                if value < 1 { hasUnfinishedStroke = true }
                previous[index] = value
            }
        }
        #expect(previous.allSatisfy { $0 == 1 })
        let timeline = FirstLaunchGreetingTimeline(preferredLanguage: .english)
        for (index, language) in timeline.languages.enumerated() {
            let hold = timeline.frame(at: (Double(index) + 0.8) * timeline.wordDuration)
            #expect(hold.language == language)
            #expect(hold.progress == 1)
            #expect(hold.opacity == 1)
        }
    }

    @Test
    func fadeHasSoftEndpointsAndAVisibleCompletedWord() {
        let timeline = FirstLaunchGreetingTimeline(preferredLanguage: .english)
        let duration = timeline.wordDuration
        let epsilon = 0.0001
        let fadeStart = timeline.frame(at: duration * 0.87)
        let justFading = timeline.frame(at: duration * (0.87 + epsilon))
        let nearlyGone = timeline.frame(at: duration * (1 - epsilon))
        #expect(fadeStart.progress == 1)
        #expect(abs(fadeStart.opacity - 1) < 0.000001)
        #expect(1 - justFading.opacity < epsilon / 10)
        #expect(nearlyGone.opacity < epsilon / 10)
        var previous = 1.0
        for step in 0...100 {
            let frame = timeline.frame(at: duration * (0.87 + 0.129 * Double(step) / 100))
            #expect(frame.progress == 1)
            #expect(frame.opacity <= previous)
            previous = frame.opacity
        }
    }

    private static let sampleArtwork = FirstLaunchGreetingArtwork(
        strokes: [
            Path { path in
                path.move(to: CGPoint(x: 16, y: 148))
                path.addCurve(to: CGPoint(x: 280, y: 16),
                              control1: CGPoint(x: 16, y: 82), control2: CGPoint(x: 280, y: 82))
            },
            Path { path in
                path.move(to: CGPoint(x: 150, y: 16))
                path.addCurve(to: CGPoint(x: 150, y: 16),
                              control1: CGPoint(x: 150, y: 16), control2: CGPoint(x: 150, y: 16))
            },
        ],
        size: CGSize(width: 296, height: 164), lineWidths: [10, 14]
    )

    private static func samples(_ path: Path) -> [CGPoint] {
        var result: [CGPoint] = []
        var current = CGPoint.zero
        path.cgPath.applyWithBlock { pointer in
            let element = pointer.pointee
            switch element.type {
            case .moveToPoint:
                current = element.points[0]
                result.append(current)
            case .addCurveToPoint:
                let origin = current
                let c1 = element.points[0]
                let c2 = element.points[1]
                let end = element.points[2]
                for step in 1...12 {
                    let t = CGFloat(step) / 12
                    let u = 1 - t
                    result.append(CGPoint(
                        x: u * u * u * origin.x + 3 * u * u * t * c1.x + 3 * u * t * t * c2.x + t * t * t * end.x,
                        y: u * u * u * origin.y + 3 * u * u * t * c1.y + 3 * u * t * t * c2.y + t * t * t * end.y
                    ))
                }
                current = end
            default:
                Issue.record("Greeting artwork must contain cubic pen centerlines only")
            }
        }
        return result
    }
}
