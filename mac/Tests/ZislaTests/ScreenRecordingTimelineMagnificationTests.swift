import AppKit
import Testing
import ZislaCore

@testable import Zisla

@MainActor
@Suite(.serialized)
struct ScreenRecordingTimelineMagnificationTests {
    @Test
    func pinchChangesTheExistingTimelineScaleWithoutCompoundingCumulativeEvents() throws {
        let harness = Harness()
        defer { harness.view.detach() }
        let original = try #require(ScreenRecordingTimelineStripGeometry(
            segments: [.init(start: 0, end: 80)], viewportWidth: 784, zoom: harness.zoom))
        harness.view.magnify(by: 0, phase: .began, location: 208)
        harness.view.magnify(by: 0.5, phase: .changed, location: 208)
        #expect(harness.zoom == 1.5)
        harness.view.magnify(by: 1, phase: .changed, location: 208)
        #expect(harness.zoom == 2)
        harness.view.magnify(by: 1, phase: .ended, location: 208)
        let enlarged = try #require(ScreenRecordingTimelineStripGeometry(
            segments: [.init(start: 0, end: 80)], viewportWidth: 784, zoom: harness.zoom))
        #expect(enlarged.pointsPerSecond == original.pointsPerSecond * 2)
        #expect(enlarged.ticks.count > original.ticks.count)
        #expect(enlarged.duration == original.duration)
        harness.view.magnify(by: 0.5, phase: .began, location: 208)
        #expect(harness.zoom == 3, "A new pinch must start from the zoom left by the previous gesture")
        #expect(!harness.hasPendingTrim)
    }

    @Test
    func pinchKeepsTheTimeUnderItsStartingPointAfterTheDocumentResizes() {
        let harness = Harness(zoom: 2)
        defer { harness.view.detach() }
        harness.scrollView.contentView.scroll(to: CGPoint(x: 200, y: 0))
        let viewportX = 208.0
        let sourceFraction = (200 + viewportX - 8) / (784 * harness.zoom)
        harness.resizeOnZoom = false
        harness.view.magnify(by: 1, phase: .began, location: 200 + viewportX)
        harness.view.applyPendingScroll()
        #expect(harness.scrollView.contentView.bounds.minX == 200,
                "Wait for SwiftUI's larger document before changing the scroll position")
        harness.document.setFrameSize(CGSize(width: 784 * harness.zoom + 16, height: 78))
        harness.view.applyPendingScroll()
        let offset = harness.scrollView.contentView.bounds.minX
        #expect(abs((offset + viewportX - 8) / (784 * harness.zoom) - sourceFraction) < 0.000_001)
        #expect(offset == 600)
        harness.scrollView.contentView.scroll(to: CGPoint(x: 400, y: 0))
        harness.view.applyPendingScroll()
        #expect(harness.scrollView.contentView.bounds.minX == 400,
                "Ordinary scrolling after a pinch must not be undone by an already-applied anchor")
    }

    @Test
    func pinchClampsZoomAndScrollingAtBothEndsOfTheTimeline() {
        let harness = Harness(zoom: 4)
        defer { harness.view.detach() }
        harness.scrollView.contentView.scroll(to: CGPoint(x: 2_352, y: 0))
        harness.view.magnify(by: 100, phase: .began, location: 3_152)
        harness.view.applyPendingScroll()
        #expect(harness.zoom == 16)
        #expect(harness.scrollView.contentView.bounds.maxX == harness.document.frame.width)
        harness.view.magnify(by: 100, phase: .ended, location: 3_152)
        harness.view.magnify(by: -10, phase: .began, location: 0)
        harness.view.applyPendingScroll()
        #expect(harness.zoom == 1)
        #expect(harness.scrollView.contentView.bounds.minX == 0)
    }

    @Test(arguments: [NSGestureRecognizer.State.cancelled, .failed, .ended])
    func finishedGesturesCannotChangeZoomUntilAnotherPinchBegins(_ phase: NSGestureRecognizer.State) {
        let harness = Harness()
        defer { harness.view.detach() }
        harness.view.magnify(by: 1, phase: .began, location: 200)
        harness.view.magnify(by: 1, phase: phase, location: 200)
        harness.view.magnify(by: 3, phase: .changed, location: 200)
        #expect(harness.zoom == 2)
        harness.view.magnify(by: 0.5, phase: .began, location: 200)
        #expect(harness.zoom == 3)
    }

    @Test
    func disabledEditingCancelsThePinchAndDoesNotResumeItsOldBase() {
        let harness = Harness()
        defer { harness.view.detach() }
        harness.view.magnify(by: 1, phase: .began, location: 200)
        harness.configure(isEnabled: false)
        harness.view.magnify(by: 3, phase: .changed, location: 200)
        harness.view.magnify(by: 3, phase: .began, location: 200)
        #expect(harness.zoom == 2)
        harness.configure(isEnabled: true)
        harness.view.magnify(by: 3, phase: .changed, location: 200)
        #expect(harness.zoom == 2)
        harness.view.magnify(by: 0.5, phase: .began, location: 200)
        #expect(harness.zoom == 3)
    }

    @Test(arguments: [NSGestureRecognizer.State.cancelled, .failed, .possible])
    func cancelledOrDisabledPinchesDoNotScrollAfterALateDocumentResize(_ phase: NSGestureRecognizer.State) {
        let harness = Harness(zoom: 2)
        defer { harness.view.detach() }
        harness.resizeOnZoom = false
        harness.scrollView.contentView.scroll(to: CGPoint(x: 200, y: 0))
        harness.view.magnify(by: 1, phase: .began, location: 408)
        if phase == .possible { harness.configure(isEnabled: false) }
        else { harness.view.magnify(by: 1, phase: phase, location: 408) }
        harness.document.setFrameSize(CGSize(width: 784 * harness.zoom + 16, height: 78))
        harness.view.applyPendingScroll()
        #expect(harness.zoom == 4)
        #expect(harness.scrollView.contentView.bounds.minX == 200)
    }

    @Test
    func invalidSamplesAndEventsOutsideAPinchLeaveTheViewportUnchanged() {
        let harness = Harness()
        defer { harness.view.detach() }
        harness.view.magnify(by: 2, phase: .changed, location: 200)
        harness.view.magnify(by: 2, phase: .possible, location: 200)
        for value in [CGFloat.nan, .infinity, -.infinity] {
            harness.view.magnify(by: value, phase: .began, location: 200)
            harness.view.magnify(by: 2, phase: .began, location: value)
        }
        #expect(harness.zoom == 1)
        #expect(harness.scrollView.contentView.bounds.minX == 0)
        #expect(harness.hasPendingTrim)
        harness.view.magnify(by: 1, phase: .began, location: 200)
        harness.view.magnify(by: .nan, phase: .ended, location: 200)
        harness.view.magnify(by: 3, phase: .changed, location: 200)
        #expect(harness.zoom == 2)
    }

    @Test
    func nativeRecognizerLeavesScrollingAndHitTestingAloneAndDetachesWithItsView() {
        let harness = Harness()
        defer { harness.view.detach() }
        let recognizer = harness.view.magnificationRecognizer
        #expect(recognizer.view === harness.scrollView)
        #expect(harness.view.hitTest(.zero) == nil)
        #expect(harness.view.gestureRecognizer(recognizer, shouldRecognizeSimultaneouslyWith: NSPanGestureRecognizer()))
        harness.view.magnify(by: 1, phase: .began, location: 200)
        harness.view.detach()
        #expect(recognizer.view == nil)
        harness.view.applyPendingScroll()
        harness.view.magnify(by: 3, phase: .began, location: 200)
        #expect(harness.zoom == 2)
        #expect(harness.scrollView.contentView.bounds.minX == 0)
        harness.configure(isEnabled: true)
        #expect(recognizer.view === harness.scrollView)
        harness.view.magnify(by: 3, phase: .changed, location: 200)
        #expect(harness.zoom == 2)
    }

    @Test
    func movingBetweenScrollViewsRemovesTheOldNativeGestureTarget() {
        let harness = Harness()
        let replacement = Harness()
        defer { harness.view.detach(); replacement.view.detach() }
        replacement.document.addSubview(harness.view)
        harness.configure(isEnabled: true)
        #expect(harness.view.magnificationRecognizer.view === replacement.scrollView)
        #expect(!harness.scrollView.gestureRecognizers.contains(harness.view.magnificationRecognizer))
    }

    @MainActor
    private final class Harness {
        let scrollView = NSScrollView(frame: .init(x: 0, y: 0, width: 800, height: 98))
        let document = NSView()
        let view = ScreenRecordingTimelineMagnificationView()
        var zoom: Double
        var resizeOnZoom = true
        var hasPendingTrim = true

        init(zoom: Double = 1) {
            self.zoom = zoom
            document.frame = .init(x: 0, y: 0, width: 784 * zoom + 16, height: 78)
            scrollView.documentView = document
            view.frame = document.bounds
            document.addSubview(view)
            configure(isEnabled: true)
        }

        func configure(isEnabled: Bool) {
            view.configure(zoom: zoom, isEnabled: isEnabled, onZoom: { [weak self] proposed in
                guard let self else { return }
                zoom = proposed
                if resizeOnZoom { document.setFrameSize(.init(width: 784 * proposed + 16, height: 78)) }
            }, onBegan: { [weak self] in self?.hasPendingTrim = false })
        }
    }
}
