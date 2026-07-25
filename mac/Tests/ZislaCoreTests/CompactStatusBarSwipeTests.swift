import CoreGraphics
import Testing

@testable import ZislaCore

struct CompactStatusBarSwipeTests {
    @Test
    func inwardSwipeFromEitherWingHidesStatusContent() {
        #expect(
            CompactStatusBarSwipeRecognizer.hidesStatusContent(
                startLocation: CGPoint(x: 20, y: 16),
                translation: CGSize(width: 30, height: 0),
                containerWidth: 160
            )
        )
        #expect(
            CompactStatusBarSwipeRecognizer.hidesStatusContent(
                startLocation: CGPoint(x: 140, y: 16),
                translation: CGSize(width: -30, height: 0),
                containerWidth: 160
            )
        )
    }

    @Test
    func outwardOrMiddleSwipeDoesNotHideStatusContent() {
        #expect(
            !CompactStatusBarSwipeRecognizer.hidesStatusContent(
                startLocation: CGPoint(x: 20, y: 16),
                translation: CGSize(width: -30, height: 0),
                containerWidth: 160
            )
        )
        #expect(
            !CompactStatusBarSwipeRecognizer.hidesStatusContent(
                startLocation: CGPoint(x: 80, y: 16),
                translation: CGSize(width: 30, height: 0),
                containerWidth: 160
            )
        )
    }

    @Test
    func unrelatedMotionDoesNotChangeStatusVisibility() {
        #expect(
            !CompactStatusBarSwipeRecognizer.hidesStatusContent(
                startLocation: CGPoint(x: 20, y: 16),
                translation: CGSize(width: -30, height: 0),
                containerWidth: 160
            )
        )
        #expect(
            !CompactStatusBarSwipeRecognizer.hidesStatusContent(
                startLocation: CGPoint(x: 80, y: 16),
                translation: CGSize(width: 10, height: 30),
                containerWidth: 160
            )
        )
        #expect(
            !CompactStatusBarSwipeRecognizer.hidesStatusContent(
                startLocation: CGPoint(x: 20, y: 16),
                translation: CGSize(width: 30, height: 31),
                containerWidth: 160
            )
        )
    }
}
