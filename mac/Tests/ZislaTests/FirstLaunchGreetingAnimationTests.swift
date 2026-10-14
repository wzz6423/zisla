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
        for elapsed in [-Double.greatestFiniteMagnitude, -1, 0, Double.greatestFiniteMagnitude] {
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

    @Test(arguments: [AppLanguage.english, .german, .simplifiedChinese, .traditionalChinese])
    func originalStrokesFitSmallAndLargeLayouts(language: AppLanguage) throws {
        let artwork = try #require(FirstLaunchGreetingArtwork.artwork(for: language))
        #expect(!artwork.strokes.isEmpty)
        for size in [CGSize(width: 240, height: 120), CGSize(width: 640, height: 180)] {
            let bounds = CGRect(origin: .zero, size: size)
            for stroke in artwork.fittedStrokes(in: size) {
                #expect(!stroke.isEmpty)
                #expect(bounds.contains(stroke.boundingRect))
            }
        }
    }

    @Test(arguments: [CGFloat(-1), 0, 0.25, 1, 2])
    func nativeScriptRevealRespectsDirectionAndBounds(progress: CGFloat) {
        let size = CGSize(width: 320, height: 180)
        let expectedWidth = size.width * min(1, max(0, progress))
        let left = FirstLaunchGreetingTimeline.revealRect(in: size, progress: progress, rightToLeft: false)
        let right = FirstLaunchGreetingTimeline.revealRect(in: size, progress: progress, rightToLeft: true)
        #expect(left.width == expectedWidth)
        #expect(left.minX == 0)
        #expect(right.width == expectedWidth)
        #expect(right.maxX == size.width)
        #expect(left.height == size.height)
        #expect(right.height == size.height)
    }
}
