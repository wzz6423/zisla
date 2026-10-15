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

    @Test(arguments: AppLanguage.allCases)
    func originalStrokesFitSmallAndLargeLayouts(language: AppLanguage) {
        let artwork = FirstLaunchGreetingArtwork.artwork(for: language)
        #expect(!artwork.strokes.isEmpty)
        #expect(artwork.strokeLengths.allSatisfy { $0.isFinite && $0 > 0 })
        for size in [CGSize(width: 80, height: 56), CGSize(width: 240, height: 120), CGSize(width: 640, height: 180)] {
            let bounds = CGRect(origin: .zero, size: size)
            let fitted = artwork.fittedStrokes(in: size)
            #expect(fitted.count == artwork.strokes.count)
            let radius = artwork.fittedLineWidth(in: size, baseWidth: 6) / 2
            for stroke in fitted {
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
            #expect(artwork.fittedLineWidth(in: size, baseWidth: 5) == 0)
        }
    }

    @Test(arguments: AppLanguage.allCases)
    func penCurvesMeetWithoutSharpCornersIncludingClosedLoops(language: AppLanguage) {
        let artwork = FirstLaunchGreetingArtwork.artwork(for: language)
        for stroke in artwork.strokes {
            var current = CGPoint.zero
            var start = CGPoint.zero
            var firstTangent: CGPoint?
            var lastTangent: CGPoint?
            stroke.cgPath.applyWithBlock { pointer in
                let element = pointer.pointee
                switch element.type {
                case .moveToPoint:
                    current = element.points[0]
                    start = current
                case .addCurveToPoint:
                    let incoming = CGPoint(x: element.points[0].x - current.x, y: element.points[0].y - current.y)
                    if let lastTangent {
                        #expect(hypot(incoming.x - lastTangent.x, incoming.y - lastTangent.y) < 0.001)
                    } else {
                        firstTangent = incoming
                    }
                    current = element.points[2]
                    lastTangent = CGPoint(x: current.x - element.points[1].x, y: current.y - element.points[1].y)
                default:
                    Issue.record("Greeting pen strokes must use smooth cubic curves")
                }
            }
            if current == start, let firstTangent, let lastTangent {
                #expect(hypot(firstTangent.x - lastTangent.x, firstTangent.y - lastTangent.y) < 0.001)
            }
        }
    }

    @Test
    func artworkLanguageSetMatchesTheLocalizedGreetingContract() {
        let expected: [AppLanguage: String] = [
            .english: "Hello", .simplifiedChinese: "你好", .traditionalChinese: "你好",
            .german: "hallo", .spanish: "Hola", .french: "Bonjour", .brazilianPortuguese: "Olá",
            .indonesian: "Halo", .korean: "안녕하세요", .italian: "Ciao", .dutch: "Hallo",
            .russian: "Здравствуйте", .arabic: "مرحبًا", .turkish: "Merhaba",
            .vietnamese: "Xin chào", .thai: "สวัสดี", .japanese: "こんにちは",
        ]
        #expect(Set(expected.keys) == Set(AppLanguage.allCases))
        for (language, text) in expected {
            #expect(AppLocalization.string("onboarding.hello", language: language) == text)
            let artwork = FirstLaunchGreetingArtwork.artwork(for: language)
            for index in artwork.strokes.indices {
                #expect(artwork.strokeProgress(at: 0, index: index) == 0)
                #expect(artwork.strokeProgress(at: 1, index: index) == 1)
            }
        }
        let english = FirstLaunchGreetingArtwork.artwork(for: .english)
        let german = FirstLaunchGreetingArtwork.artwork(for: .german)
        #expect(english.strokes[0] != german.strokes[0])
        #expect(english.strokes[0] == FirstLaunchGreetingArtwork.artwork(for: .dutch).strokes[0])
        #expect(english.strokes[3] != FirstLaunchGreetingArtwork.artwork(for: .dutch).strokes[3])
    }

    @Test
    func latinAccentsAndTheVietnameseWordGapRemainVisible() throws {
        let portuguese = FirstLaunchGreetingArtwork.artwork(for: .brazilianPortuguese)
        let acute = try #require(portuguese.strokes.last)
        let acutePoints = Self.samples(acute)
        let acuteStart = try #require(acutePoints.first)
        let acuteEnd = try #require(acutePoints.last)
        #expect(acuteEnd.x > acuteStart.x)
        #expect(acuteEnd.y < acuteStart.y)
        #expect(acute.boundingRect.maxY < 65)
        let vietnamese = FirstLaunchGreetingArtwork.artwork(for: .vietnamese)
        let graveStrokes = vietnamese.strokes.filter { stroke in
            let bounds = stroke.boundingRect
            return bounds.maxY <= 62 && bounds.width > 8 && bounds.height > 8
        }
        #expect(graveStrokes.count == 1)
        let grave = try #require(graveStrokes.first)
        let gravePoints = Self.samples(grave)
        let graveStart = try #require(gravePoints.first)
        let graveEnd = try #require(gravePoints.last)
        #expect(graveEnd.x > graveStart.x)
        #expect(graveEnd.y > graveStart.y)
        let points = vietnamese.strokes.flatMap(Self.samples)
        #expect(points.contains { (150...165).contains($0.x) })
        #expect(!points.contains { (180...205).contains($0.x) })
        #expect(points.contains { (220...245).contains($0.x) })
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
        let artwork = FirstLaunchGreetingArtwork(strokes: [short, long], size: CGSize(width: 120, height: 30))
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

    @Test(arguments: AppLanguage.allCases)
    func writingProgressIsMonotoneAndEveryStrokeCompletesBeforeFade(language: AppLanguage) {
        let artwork = FirstLaunchGreetingArtwork.artwork(for: language)
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
        let timeline = FirstLaunchGreetingTimeline(preferredLanguage: language)
        let index = timeline.languages.firstIndex(of: language)!
        let hold = timeline.frame(at: (Double(index) + 0.8) * timeline.wordDuration)
        #expect(hold.language == language)
        #expect(hold.progress == 1)
        #expect(hold.opacity == 1)
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

    @Test
    func nonLatinInkCoversEveryCharacterAndItsDistinctiveMarks() {
        let cells: [(AppLanguage, [ClosedRange<CGFloat>])] = [
            (.japanese, [18...75, 95...165, 178...248, 273...335, 358...442]),
            (.korean, [12...94, 115...183, 210...302, 310...396, 415...490]),
            (.russian, [20...75, 86...148, 159...207, 217...268, 278...325, 335...380,
                        390...441, 451...498, 508...558, 568...617, 627...678, 688...735]),
            (.thai, [12...70, 82...136, 156...214, 232...289]),
        ]
        for (language, ranges) in cells {
            let points = FirstLaunchGreetingArtwork.artwork(for: language).strokes.flatMap(Self.samples)
            for range in ranges {
                let column = points.filter { range.contains($0.x) }
                #expect(column.count > 10)
                #expect(column.contains { $0.y < 85 })
                #expect(column.contains { $0.y > 95 })
            }
        }
        let landmarks: [(AppLanguage, [CGPoint])] = [
            (.korean, [.init(x: 91, y: 54), .init(x: 158, y: 45), .init(x: 157, y: 63),
                       .init(x: 225, y: 30), .init(x: 352, y: 75), .init(x: 440, y: 94), .init(x: 465, y: 93)]),
            (.thai, [.init(x: 90, y: 45), .init(x: 130, y: 37), .init(x: 285, y: 25)]),
            (.arabic, [.init(x: 355, y: 88), .init(x: 277, y: 132), .init(x: 206, y: 101),
                       .init(x: 170, y: 121), .init(x: 118, y: 35), .init(x: 178, y: 61), .init(x: 177, y: 70)]),
        ]
        for (language, targets) in landmarks {
            let points = FirstLaunchGreetingArtwork.artwork(for: language).strokes.flatMap(Self.samples)
            for target in targets {
                #expect(points.contains { hypot($0.x - target.x, $0.y - target.y) < 2 })
            }
        }
    }

    @Test
    func arabicJoinsAndPenTravelRunRightToLeftWithoutMirroring() throws {
        let artwork = FirstLaunchGreetingArtwork.artwork(for: .arabic)
        let meem = Self.samples(artwork.strokes[0])
        let ra = Self.samples(artwork.strokes[1])
        let joinedHaBaAlif = Self.samples(artwork.strokes[2])
        let start = try #require(joinedHaBaAlif.first)
        let end = try #require(joinedHaBaAlif.last)
        #expect(start.x > end.x)
        #expect(meem.last == ra.first)
        #expect(ra.last != joinedHaBaAlif.first)
        for x in [CGFloat(130), 150, 170, 190, 210] {
            #expect(joinedHaBaAlif.contains { abs($0.x - x) < 4 && (85...106).contains($0.y) })
        }
        let fitted = artwork.fittedStrokes(in: CGSize(width: 240, height: 100))
        let fittedStart = try #require(Self.samples(fitted[2]).first)
        let fittedEnd = try #require(Self.samples(fitted[2]).last)
        #expect(fittedStart.x > fittedEnd.x)
    }

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
