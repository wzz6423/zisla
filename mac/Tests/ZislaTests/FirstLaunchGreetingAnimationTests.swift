import SwiftUI
import Testing
import ZislaCore
@testable import Zisla

struct FirstLaunchGreetingAnimationTests {
    @Test(arguments: AppLanguage.allCases)
    func greetingSequenceIncludesRequiredWordsAndPreferredLanguage(language: AppLanguage) {
        let timeline = FirstLaunchGreetingTimeline(preferredLanguage: language)
        #expect(Array(timeline.languages.prefix(3)) == [.english, .simplifiedChinese, .german])
        let words = timeline.languages.map { AppLocalization.string("onboarding.hello", language: $0) }
        #expect(words.contains(AppLocalization.string("onboarding.hello", language: language)))
        #expect(Set(words).count == words.count)
        #expect((3...4).contains(words.count))
        #expect(abs(timeline.wordDuration * Double(words.count) - FirstLaunchOnboardingScore.duration) <= FirstLaunchOnboardingScore.duration.ulp)
    }

    @Test(arguments: AppLanguage.allCases)
    func framesStayBoundedAndFinishAtTheFinalGreeting(language: AppLanguage) {
        let timeline = FirstLaunchGreetingTimeline(preferredLanguage: language)
        for step in -1...73 {
            let frame = timeline.frame(at: Double(step) / 10)
            #expect(timeline.languages.contains(frame.language))
            #expect((0...1).contains(frame.progress))
            #expect((0...1).contains(frame.opacity))
        }
        #expect(timeline.frame(at: -1).language == .english)
        #expect(timeline.frame(at: -1).progress == 0)
        for (index, language) in timeline.languages.enumerated() {
            let frame = timeline.frame(at: (Double(index) + 0.75) * timeline.wordDuration)
            #expect(frame.language == language)
            #expect(frame.progress == 1)
            #expect(frame.opacity == 1)
        }
        let final = timeline.frame(at: FirstLaunchOnboardingScore.duration)
        #expect(final.language == timeline.languages.last)
        #expect(final.progress == 1)
        #expect(final.opacity == 1)
        #expect(timeline.frame(at: FirstLaunchOnboardingScore.duration.nextDown).language == timeline.languages.last)
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
