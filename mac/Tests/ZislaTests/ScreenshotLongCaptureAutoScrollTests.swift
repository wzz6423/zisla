import AppKit
import Foundation
import SwiftUI
import Testing
import ZislaCore

@testable import Zisla
@testable import ZislaKit

@Suite("Long capture automatic scrolling")
struct ScreenshotLongCaptureAutoScrollTests {
    @Test
    func stationaryBaselineStartsScrollingOnlyOnce() {
        var scrolling = ScreenshotLongCaptureAutoScroll()
        #expect(scrolling.nextStep(after: .unchanged) == .none)

        scrolling.start()
        #expect(scrolling.nextStep(after: .unchanged) == .scroll)
        #expect(scrolling.isWaitingForScrolledFrame)
        #expect(scrolling.nextStep(after: .unchanged) == .capture)
        #expect(scrolling.nextStep(after: .unchanged) == .capture)
        #expect(scrolling.nextStep(after: .unchanged) == .pause)
        #expect(!scrolling.isRunning)
        #expect(scrolling.nextStep(after: .unchanged) == .none)
    }

    @Test
    func failedOverlapNeverScrollsPastUncapturedContent() {
        var scrolling = ScreenshotLongCaptureAutoScroll()
        scrolling.start()

        #expect(scrolling.nextStep(after: .rejected) == .capture)
        #expect(scrolling.nextStep(after: .rejected) == .capture)
        #expect(scrolling.nextStep(after: .rejected) == .pause)
        #expect(!scrolling.isRunning)
    }

    @Test
    func successfulStitchResetsTheRetryBudget() {
        var scrolling = ScreenshotLongCaptureAutoScroll()
        scrolling.start()
        #expect(scrolling.nextStep(after: .unchanged) == .scroll)
        #expect(scrolling.nextStep(after: .rejected) == .capture)
        #expect(scrolling.nextStep(after: .unchanged) == .capture)
        #expect(scrolling.nextStep(after: .appended) == .scroll)
        #expect(scrolling.nextStep(after: .rejected) == .capture)
        #expect(scrolling.nextStep(after: .rejected) == .capture)
        #expect(scrolling.nextStep(after: .rejected) == .pause)
    }

    @Test
    func pauseAndRestartKeepTheUncapturedScrollPosition() {
        var scrolling = ScreenshotLongCaptureAutoScroll()
        scrolling.start()
        #expect(scrolling.nextStep(after: .unchanged) == .scroll)
        #expect(scrolling.nextStep(after: .rejected) == .capture)
        scrolling.stop()

        #expect(!scrolling.isRunning)
        #expect(scrolling.isWaitingForScrolledFrame)
        #expect(scrolling.nextStep(after: .unchanged) == .none)
        scrolling.start()
        #expect(scrolling.nextStep(after: .unchanged) == .capture,
            "Resuming before the scrolled frame repaints must not scroll past it")
        #expect(scrolling.nextStep(after: .rejected) == .capture)
        #expect(scrolling.nextStep(after: .appended) == .scroll)
        scrolling.stop()
        #expect(scrolling.nextStep(after: .appended) == .none)
        scrolling.start()
        #expect(scrolling.nextStep(after: .unchanged) == .scroll,
            "A frame stitched while paused must permit the next automatic step")
    }

    @Test(arguments: ScreenshotLongCaptureDirection.allCases, [ScreenshotLongCapturePlacement.append, .prepend])
    func eventUsesTheSelectedAxisAndContentDirection(
        direction: ScreenshotLongCaptureDirection,
        placement: ScreenshotLongCapturePlacement
    ) throws {
        let event = try #require(ScreenshotLongCaptureAutoScroll.event(
            selection: CGRect(x: 40, y: 60, width: 300, height: 400),
            displayBounds: CGRect(x: -1_920, y: 900, width: 1_920, height: 1_080),
            direction: direction,
            placement: placement
        ))
        let expected: Int64 = placement == .append ? -1 : 1
        #expect(event.type == .scrollWheel)
        #expect(event.location == CGPoint(x: -1_730, y: 1_160))
        #expect(event.flags.isEmpty)
        #expect(event.getIntegerValueField(.scrollWheelEventIsContinuous) == 1)
        #expect(event.getIntegerValueField(.scrollWheelEventPointDeltaAxis1)
            == (direction == .vertical ? expected * 80 : 0))
        #expect(event.getIntegerValueField(.scrollWheelEventPointDeltaAxis2)
            == (direction == .horizontal ? expected * 60 : 0))
    }

    @Test(arguments: [CGFloat(2), 40, 100, 399, 400, 1_000, 10_000])
    func scrollStepPreservesMostOfTheSelection(axisLength: CGFloat) throws {
        let event = try #require(ScreenshotLongCaptureAutoScroll.event(
            selection: CGRect(x: 0, y: 0, width: 500, height: axisLength),
            displayBounds: CGRect(x: 0, y: 0, width: 500, height: axisLength),
            direction: .vertical,
            placement: .append
        ))
        let distance = abs(event.getIntegerValueField(.scrollWheelEventPointDeltaAxis1))
        #expect(distance > 0)
        #expect(distance <= 80)
        #expect(CGFloat(distance) <= max(1, axisLength * 0.2))
        #expect(ScreenshotLongCaptureAutoScroll.settleDelay >= 0.8)
    }

    @Test(arguments: [
        CGRect.zero,
        CGRect(x: 0, y: 0, width: 1, height: 300),
        CGRect(x: 0, y: 0, width: 300, height: -10),
        CGRect(x: -1, y: 0, width: 100, height: 300),
        CGRect(x: 0, y: 0, width: 501, height: 300),
        CGRect(x: CGFloat.infinity, y: 0, width: 100, height: 300),
        CGRect(x: 0, y: 0, width: CGFloat.nan, height: 300),
    ])
    func invalidSelectionCannotProduceAnInputEvent(selection: CGRect) {
        #expect(ScreenshotLongCaptureAutoScroll.event(
            selection: selection,
            displayBounds: CGRect(x: 0, y: 0, width: 500, height: 500),
            direction: .vertical,
            placement: .append
        ) == nil)
    }

    @Test @MainActor
    func frameResultsDistinguishStillnessFromFailedOverlap() throws {
        let source = try #require(Self.page(width: 96, height: 480))
        let first = try #require(source.cropping(to: CGRect(x: 0, y: 0, width: 96, height: 400)))
        let next = try #require(source.cropping(to: CGRect(x: 0, y: 80, width: 96, height: 400)))
        let image = NSImage(cgImage: first, size: CGSize(width: 96, height: 400))
        let model = ScreenshotEditorModel(image: image)
        model.beginLongCapturePreview()

        #expect(!model.append(image: image, direction: .vertical))
        #expect(model.lastLongCaptureFrameResult == .unchanged)
        #expect(!model.canUndo)
        #expect(!model.append(
            image: NSImage(size: image.size), direction: .vertical
        ))
        #expect(model.lastLongCaptureFrameResult == .rejected)
        #expect(model.image.size == image.size)
        #expect(model.append(
            image: NSImage(cgImage: next, size: image.size), direction: .vertical
        ))
        #expect(model.lastLongCaptureFrameResult == .appended)
        #expect(model.image.size == CGSize(width: 96, height: 480))
        #expect(model.autoScrollPlacement == .append)
    }

    @Test @MainActor
    func automaticScrollingKeepsTheExistingPrependDirection() throws {
        let source = try #require(Self.page(width: 96, height: 480))
        let first = try #require(source.cropping(to: CGRect(x: 0, y: 80, width: 96, height: 400)))
        let next = try #require(source.cropping(to: CGRect(x: 0, y: 0, width: 96, height: 400)))
        let model = ScreenshotEditorModel(
            image: NSImage(cgImage: first, size: CGSize(width: 96, height: 400))
        )
        model.beginLongCapturePreview()
        #expect(model.append(
            image: NSImage(cgImage: next, size: model.image.size), direction: .vertical
        ))
        #expect(model.lastLongCaptureFrameResult == .appended)
        #expect(model.autoScrollPlacement == .prepend)
        model.completeLongCapturePreview()
        #expect(model.autoScrollPlacement == .append)
        #expect(model.hasLongCaptureResult)
    }

    @Test
    func revokedInputPermissionNeverPostsAnEvent() throws {
        let event = try #require(ScreenshotLongCaptureAutoScroll.event(
            selection: CGRect(x: 0, y: 0, width: 100, height: 300),
            displayBounds: CGRect(x: 0, y: 0, width: 500, height: 500),
            direction: .vertical, placement: .append
        ))
        var hasAccess = true
        var postedTargets: [pid_t] = []
        let post = { (event: CGEvent, pid: pid_t) in postedTargets.append(pid) }
        let windows = [Self.window(number: 123, owner: 42)]
        #expect(ScreenshotLongCaptureAutoScroll.post(
            event, to: 42, currentProcessIdentifier: 10,
            hasAccess: { hasAccess }, windowInfo: { windows },
            setWindowLocation: { _, _ in true }, postEvent: post
        ))
        hasAccess = false
        #expect(!ScreenshotLongCaptureAutoScroll.post(
            event, to: 42, currentProcessIdentifier: 10,
            hasAccess: { hasAccess }, windowInfo: { windows },
            setWindowLocation: { _, _ in true }, postEvent: post
        ))
        #expect(postedTargets == [42])
    }

    @Test
    func processPostingTargetsTheFrontmostContainingWindowAndLocalPoint() throws {
        let event = try #require(ScreenshotLongCaptureAutoScroll.event(
            selection: CGRect(x: 40, y: 60, width: 300, height: 400),
            displayBounds: CGRect(x: -1_920, y: 900, width: 1_920, height: 1_080),
            direction: .vertical, placement: .append
        ))
        let bounds = CGRect(x: -1_800, y: 1_000, width: 500, height: 600)
        let windows = [
            Self.window(number: 1, owner: 99, bounds: bounds),
            Self.window(number: 2, owner: 42, bounds: bounds, layer: 100),
            Self.window(number: 3, owner: 42, bounds: bounds, alpha: 0),
            Self.window(number: 4, owner: 42, bounds: CGRect(x: 0, y: 0, width: 500, height: 500)),
            Self.window(number: 0, owner: 42, bounds: bounds),
            [String: Any](),
            Self.window(number: 123, owner: 42, bounds: bounds),
            Self.window(number: 456, owner: 42, bounds: bounds),
        ]
        var point: CGPoint?
        var deliveredWindow: Int64?
        #expect(ScreenshotLongCaptureAutoScroll.post(
            event, to: 42, currentProcessIdentifier: 10, hasAccess: { true },
            windowInfo: { windows }, setWindowLocation: { _, value in point = value; return true },
            postEvent: { event, _ in deliveredWindow = event.getIntegerValueField(CGEventField(rawValue: 51)!) }
        ))
        #expect(point == CGPoint(x: 70, y: 160))
        #expect(deliveredWindow == 123)
        #expect(event.location == CGPoint(x: -1_730, y: 1_160))
    }

    @Test(arguments: ["missing", "closed", "binding unavailable"])
    func unrouteableEventsPauseWithoutPosting(failure: String) throws {
        let event = try #require(ScreenshotLongCaptureAutoScroll.event(
            selection: CGRect(x: 0, y: 0, width: 100, height: 300),
            displayBounds: CGRect(x: 0, y: 0, width: 500, height: 500),
            direction: .vertical, placement: .append
        ))
        var posted = false
        #expect(!ScreenshotLongCaptureAutoScroll.post(
            event, to: 42, currentProcessIdentifier: 10, hasAccess: { true },
            windowInfo: {
                failure == "missing" ? nil : (failure == "closed" ? [] : [Self.window(number: 123, owner: 42)])
            }, setWindowLocation: { _, _ in false }, postEvent: { _, _ in posted = true }
        ))
        #expect(!posted)
    }

    @Test(arguments: [AppLanguage.simplifiedChinese, .english, .arabic]) @MainActor
    func capturePreviewShowsPausedAndPermissionFeedback(language: AppLanguage) async throws {
        let releaseAccessibility = EnhancedAccessibilityTestScope.acquire()
        defer { releaseAccessibility() }
        let model = ScreenshotEditorModel(image: NSImage(size: CGSize(width: 48, height: 160)))
        model.beginLongCapturePreview()
        let host = NSHostingView(rootView: ScreenshotLongCapturePreviewView(model: model)
            .environment(\.locale, language.locale)
            .environment(\.layoutDirection, language.isRightToLeft ? .rightToLeft : .leftToRight))
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 220, height: 420),
            styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        defer { window.contentView = nil; window.close() }
        for key in ["自动滚动已暂停，可手动滚动或点击“完成”", "自动滚动需要在系统设置中允许辅助功能", "无法自动滚动，请手动滚动页面"] {
            let message = AppLocalization.string(key, language: language)
            model.statusMessage = message
            for _ in 0..<3 {
                host.layoutSubtreeIfNeeded()
                await withCheckedContinuation { continuation in DispatchQueue.main.async { continuation.resume() } }
            }
            var labels: [String] = []
            func visit(_ object: NSObject) {
                for name in ["accessibilityLabel", "accessibilityValue", "accessibilityTitle"] {
                    if object.responds(to: NSSelectorFromString(name)), let value = object.value(forKey: name) as? String {
                        labels.append(value)
                    }
                }
                if object.responds(to: NSSelectorFromString("accessibilityChildren")) {
                    for child in object.value(forKey: "accessibilityChildren") as? [NSObject] ?? [] { visit(child) }
                }
            }
            visit(host)
            #expect(labels.contains(message), "The active long-capture preview must expose its \(language.rawValue) feedback")
        }
        #expect(!window.isVisible && !window.isKeyWindow)
    }

    @Test(arguments: ["queued", "in flight"]) @MainActor
    func finishingIncludesTheLastFrameWithoutFurtherScrolling(timing: String) async throws {
        let screen = try #require(NSScreen.main)
        let suite = "zisla-auto-scroll-finish-\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        let settings = FeatureSettingsStore(defaults: defaults)
        defer { settings.flushPendingChanges(); defaults.removePersistentDomain(forName: suite) }
        let source = try #require(Self.page(width: Int(screen.frame.width), height: Int(screen.frame.height) + 32))
        let first = try #require(source.cropping(to: CGRect(x: 0, y: 0, width: 48, height: 160)))
        let last = try #require(source.cropping(to: CGRect(x: 0, y: 32, width: screen.frame.width, height: screen.frame.height)))
        let image = NSImage(cgImage: first, size: CGSize(width: 48, height: 160))
        var scheduled: [(delay: TimeInterval, work: DispatchWorkItem)] = []
        var posted = 0
        var frames = 0
        let entered = AsyncStream<Void>.makeStream()
        let release = AsyncStream<Void>.makeStream()
        let controller = ScreenshotEditorWindowController(
            image: image, screenImage: image, screenCGImage: first, screen: screen,
            captureRect: CGRect(x: 0, y: 0, width: 48, height: 160), capturedApplication: nil,
            settingsStore: settings, onStash: { _, _ in }, writeImageToPasteboard: { _ in false },
            presentSavePanel: { _, _ in }, captureScreen: { _, _ in
                frames += 1
                if timing == "in flight" {
                    entered.continuation.yield()
                    for await _ in release.stream {}
                }
                return (NSImage(cgImage: last, size: screen.frame.size), last, nil)
            }, scheduleLongCaptureWork: { delay, work in scheduled.append((delay, work)) },
            hasLongCaptureInputAccess: { true }, postLongCaptureEvent: { _, _ in posted += 1; return true }, onClose: {}
        )
        defer { release.continuation.finish(); controller.close() }
        controller.window?.alphaValue = 0
        let host = try #require(controller.window?.contentView as? NSHostingView<AppLanguageEnvironment<ScreenshotEditorView>>)
        let model = host.rootView.content.model
        model.beginLongCapturePreview()
        model.longCaptureAutoScroll.start()
        _ = model.longCaptureAutoScroll.nextStep(after: .unchanged)
        let previousWork: DispatchWorkItem?
        let capture: Task<Void, Never>?
        if timing == "in flight" {
            capture = try #require(controller.captureLongCaptureScreen(on: screen, sessionID: 0))
            var entering = entered.stream.makeAsyncIterator()
            try #require(await entering.next())
            previousWork = nil
        } else {
            controller.finishLongCapture()
            previousWork = try #require(scheduled.last?.work)
            #expect(scheduled.last?.delay == ScreenshotLongCaptureAutoScroll.settleDelay)
            capture = nil
        }
        controller.finishLongCapture()
        #expect(!model.longCaptureAutoScroll.isRunning)
        if timing == "queued" {
            #expect(previousWork?.isCancelled == true)
            let finalWork = try #require(scheduled.last?.work)
            #expect(!finalWork.isCancelled)
            let finalCapture = try #require(controller.captureLongCaptureScreen(on: screen, sessionID: 0))
            await finalCapture.value
            finalWork.perform()
        } else {
            release.continuation.finish()
            await capture?.value
        }
        #expect(frames == 1)
        #expect(posted == 0)
        #expect(model.hasLongCaptureResult && !model.isLongCapturePreviewing)
        #expect(model.image.size == CGSize(width: 48, height: 192), "Done must keep the last 32pt of content")
        #expect(model.statusMessage == AppLocalization.text("长截图已完成"))
    }

    @Test(arguments: ["normal", "repaint", "permission revoked"]) @MainActor
    func controllerWaitsForEachScrolledFrameAndPausesAtTheBoundary(scenario: String) async throws {
        let screen = try #require(NSScreen.main)
        let suite = "zisla-auto-scroll-loop-\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        let settings = FeatureSettingsStore(defaults: defaults)
        defer { settings.flushPendingChanges(); defaults.removePersistentDomain(forName: suite) }
        let source = try #require(Self.page(width: Int(screen.frame.width), height: Int(screen.frame.height) + 64))
        let first = try #require(source.cropping(to: CGRect(x: 0, y: 0, width: 48, height: 160)))
        let image = NSImage(cgImage: first, size: CGSize(width: 48, height: 160))
        var offset = 0
        var posted = 0
        var scheduled: [(delay: TimeInterval, work: DispatchWorkItem)] = []
        var repainting = false
        var inputAccess = true
        let captureQueue = AsyncStream<Void>.makeStream()
        let controller = ScreenshotEditorWindowController(
            image: image, screenImage: image, screenCGImage: first, screen: screen,
            captureRect: CGRect(x: 0, y: 0, width: 48, height: 160), capturedApplication: .current,
            settingsStore: settings, onStash: { _, _ in }, writeImageToPasteboard: { _ in false },
            presentSavePanel: { _, _ in }, captureScreen: { _, _ in
                let next = try #require(source.cropping(to: CGRect(
                    x: 0, y: CGFloat(offset), width: screen.frame.width, height: screen.frame.height)))
                return (NSImage(cgImage: next, size: screen.frame.size), next, nil)
            }, scheduleLongCaptureWork: { delay, work in
                scheduled.append((delay, work))
                captureQueue.continuation.yield()
            },
            hasLongCaptureInputAccess: { inputAccess }, postLongCaptureEvent: { event, _ in
                guard inputAccess else { return false }
                posted += 1
                #expect(event.getIntegerValueField(.scrollWheelEventPointDeltaAxis1) == -32)
                if !repainting { offset = min(64, offset + 32) }
                return true
            }, onClose: {}
        )
        defer { controller.close() }
        controller.window?.alphaValue = 0
        let host = try #require(controller.window?.contentView as? NSHostingView<AppLanguageEnvironment<ScreenshotEditorView>>)
        let model = host.rootView.content.model
        model.beginLongCapturePreview()
        model.longCaptureAutoScroll.start()
        if scenario == "repaint" { repainting = true }
        let baseline = try #require(controller.captureLongCaptureScreen(on: screen, sessionID: 0))
        await baseline.value
        var queue = captureQueue.stream.makeAsyncIterator()
        try #require(await queue.next())
        var pending = try #require(scheduled.last)
        #expect(posted == 1)
        #expect(model.image.size.height == 160)
        #expect(scheduled.last?.delay == ScreenshotLongCaptureAutoScroll.settleDelay)

        if scenario == "permission revoked" { inputAccess = false }
        if scenario == "repaint" {
            for _ in 0..<2 {
                pending.1.perform()
                try #require(await queue.next())
        pending = try #require(scheduled.last)
                #expect(posted == 1, "An unchanged repaint must not permit another wheel event")
                #expect(model.image.size.height == 160)
            }
            repainting = false
            offset = 32
        }
        pending.1.perform()
        try #require(await queue.next())
            pending = try #require(scheduled.last)
        #expect(model.image.size.height == 192)
        if scenario == "permission revoked" {
            #expect(posted == 1 && !model.longCaptureAutoScroll.isRunning)
            #expect(model.statusMessage == AppLocalization.text("无法自动滚动，请手动滚动页面"))
            pending.1.perform()
            try #require(await queue.next())
            pending = try #require(scheduled.last)
            #expect(model.statusMessage == AppLocalization.text("无法自动滚动，请手动滚动页面"),
                "An idle capture must preserve the delivery failure")
            model.longCaptureAutoScroll.start()
            inputAccess = true
            pending.1.perform()
            try #require(await queue.next())
            pending = try #require(scheduled.last)
            #expect(posted == 2, "Restored permission must allow scrolling from the last stitched frame")
        } else {
            #expect(posted == 2)
            pending.1.perform()
            try #require(await queue.next())
            pending = try #require(scheduled.last)
            #expect(model.image.size.height == 224)
            #expect(posted == 3)
            for _ in 0..<3 {
                pending.1.perform()
                try #require(await queue.next())
                pending = try #require(scheduled.last)
            }
            #expect(posted == 3 && !model.longCaptureAutoScroll.isRunning)
            #expect(model.statusMessage == AppLocalization.text("自动滚动已暂停，可手动滚动或点击“完成”"))
            pending.1.perform()
            try #require(await queue.next())
            pending = try #require(scheduled.last)
            #expect(model.statusMessage == AppLocalization.text("自动滚动已暂停，可手动滚动或点击“完成”"),
                "End-of-page feedback must remain visible until another action")
        }
        #expect(scheduled.filter { $0.delay != 0.35 }.allSatisfy { $0.delay >= ScreenshotLongCaptureAutoScroll.settleDelay })
        controller.finishLongCapture()
        let final = try #require(controller.captureLongCaptureScreen(on: screen, sessionID: 0))
        await final.value
        #expect(model.hasLongCaptureResult)
        let endedCount = posted
        scheduled.forEach { $0.work.perform() }
        #expect(posted == endedCount, "Retired scheduled work must never scroll again")
    }

    @Test @MainActor
    func toolbarTogglesAutomaticScrollingAndPermissionDenialKeepsItStopped() throws {
        let screen = try #require(NSScreen.main)
        let suite = "zisla-auto-scroll-toggle-\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        let settings = FeatureSettingsStore(defaults: defaults)
        defer { settings.flushPendingChanges(); defaults.removePersistentDomain(forName: suite) }
        let pixels = try #require(Self.page(width: 48, height: 160))
        let image = NSImage(cgImage: pixels, size: CGSize(width: 48, height: 160))
        var scheduled: [(delay: TimeInterval, work: DispatchWorkItem)] = []
        var inputAccess = false
        let controller = ScreenshotEditorWindowController(
            image: image, screenImage: image, screenCGImage: pixels, screen: screen,
            captureRect: CGRect(x: 0, y: 0, width: 48, height: 160), capturedApplication: nil,
            settingsStore: settings, onStash: { _, _ in }, writeImageToPasteboard: { _ in false },
            presentSavePanel: { _, _ in }, captureScreen: { _, _ in (image, pixels, nil) },
            scheduleLongCaptureWork: { delay, work in scheduled.append((delay, work)) },
            hasLongCaptureInputAccess: { inputAccess }, postLongCaptureEvent: { _, _ in false }, onClose: {}
        )
        defer { controller.close() }
        controller.window?.alphaValue = 0
        let host = try #require(controller.window?.contentView as? NSHostingView<AppLanguageEnvironment<ScreenshotEditorView>>)
        let model = host.rootView.content.model
        controller.captureNextScreen()
        let openWork = try #require(scheduled.last?.work)
        #expect(model.isLongCapturePreviewing && !model.longCaptureAutoScroll.isRunning)
        controller.captureNextScreen()
        #expect(!model.longCaptureAutoScroll.isRunning)
        #expect(model.statusMessage == AppLocalization.text("自动滚动需要在系统设置中允许辅助功能"))
        inputAccess = true
        controller.captureNextScreen()
        #expect(model.longCaptureAutoScroll.isRunning)
        #expect(scheduled.last?.delay == ScreenshotLongCaptureAutoScroll.settleDelay)
        controller.captureNextScreen()
        #expect(!model.longCaptureAutoScroll.isRunning)
        #expect(model.statusMessage == AppLocalization.text("自动滚动已暂停，可手动滚动或点击“完成”"))
        controller.finishLongCapture()
        controller.captureNextScreen()
        #expect(!model.longCaptureAutoScroll.isRunning, "Done must prevent a restart while its last frame is pending")
        controller.close()
        openWork.perform()
        #expect(!controller.window!.isVisible && !model.isLongCapturePreviewing)
    }

    @Test(arguments: [pid_t(-1), 0, 10])
    func invalidOrOwnProcessNeverReceivesSyntheticInput(processIdentifier: pid_t) throws {
        let event = try #require(ScreenshotLongCaptureAutoScroll.event(
            selection: CGRect(x: 0, y: 0, width: 100, height: 300),
            displayBounds: CGRect(x: 0, y: 0, width: 500, height: 500),
            direction: .vertical, placement: .append
        ))
        var posted = false
        #expect(!ScreenshotLongCaptureAutoScroll.post(
            event, to: processIdentifier, currentProcessIdentifier: 10,
            hasAccess: { true }, postEvent: { _, _ in posted = true }
        ))
        #expect(!posted)
    }

    @Test @MainActor
    func endingCaptureStopsAutomaticInputAndKeepsTheImage() throws {
        let source = try #require(Self.page(width: 96, height: 400))
        let image = NSImage(cgImage: source, size: CGSize(width: 96, height: 400))
        let model = ScreenshotEditorModel(image: image)
        model.beginLongCapturePreview()
        model.longCaptureAutoScroll.start()
        #expect(model.longCaptureAutoScroll.nextStep(after: .unchanged) == .scroll)
        model.completeLongCapturePreview()

        #expect(!model.longCaptureAutoScroll.isRunning)
        #expect(model.longCaptureAutoScroll.nextStep(after: .appended) == .none)
        #expect(model.hasLongCaptureResult)
        #expect(model.image === image)
        model.beginLongCapturePreview()
        model.longCaptureAutoScroll.start()
        #expect(model.longCaptureAutoScroll.nextStep(after: .unchanged) == .scroll,
            "A new capture must not inherit the previous session's pending frame")
        model.endLongCapturePreview()
        #expect(!model.longCaptureAutoScroll.isRunning)
        #expect(!model.isLongCapturePreviewing)
        #expect(model.image === image)
    }

    @Test(arguments: ScreenshotLongCaptureDirection.allCases, [1, 2]) @MainActor
    func slowAutomaticStepsStitchEveryPixelBeforePausingAtTheEnd(
        direction: ScreenshotLongCaptureDirection, pixelScale: Int
    ) throws {
        let pageSize = direction == .vertical
            ? CGSize(width: 48, height: 256) : CGSize(width: 256, height: 48)
        let frameSize = direction == .vertical
            ? CGSize(width: 48, height: 160) : CGSize(width: 160, height: 48)
        let source = try #require(Self.page(
            width: Int(pageSize.width) * pixelScale, height: Int(pageSize.height) * pixelScale
        ))
        func frame(at offset: Int) throws -> NSImage {
            let rect = direction == .vertical
                ? CGRect(x: 0, y: offset * pixelScale, width: 48 * pixelScale, height: 160 * pixelScale)
                : CGRect(x: offset * pixelScale, y: 0, width: 160 * pixelScale, height: 48 * pixelScale)
            return NSImage(cgImage: try #require(source.cropping(to: rect)), size: frameSize)
        }
        let first = try frame(at: 0)
        let model = ScreenshotEditorModel(image: first)
        model.beginLongCapturePreview()
        model.longCaptureAutoScroll.start()
        #expect(!model.append(image: first, direction: direction))
        #expect(model.longCaptureAutoScroll.nextStep(after: model.lastLongCaptureFrameResult) == .scroll)

        for offset in [32, 64, 96] {
            let next = try frame(at: offset)
            #expect(model.append(image: next, direction: direction))
            #expect(model.longCaptureAutoScroll.nextStep(after: model.lastLongCaptureFrameResult) == .scroll)
        }
        let last = try frame(at: 96)
        for expected in [ScreenshotLongCaptureAutoScroll.Step.capture, .capture, .pause] {
            #expect(!model.append(image: last, direction: direction))
            #expect(model.longCaptureAutoScroll.nextStep(after: model.lastLongCaptureFrameResult) == expected)
        }
        #expect(!model.longCaptureAutoScroll.isRunning)
        let combined = try #require(model.image.cgImage(forProposedRect: nil, context: nil, hints: nil))
        #expect(model.image.size == pageSize)
        #expect(combined.width == source.width && combined.height == source.height)
        #expect(try Self.pixels(in: combined) == Self.pixels(in: source))
    }

    @Test(arguments: ["save", "pin", "close"]) @MainActor
    func editorExitActionsStopAutomaticScrolling(action: String) throws {
        let suite = "zisla-auto-scroll-exit-\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        let settings = FeatureSettingsStore(defaults: defaults)
        defer { settings.flushPendingChanges(); defaults.removePersistentDomain(forName: suite) }
        let source = try #require(Self.page(width: 48, height: 160))
        let image = NSImage(cgImage: source, size: CGSize(width: 48, height: 160))
        var saved = false
        let controller = ScreenshotEditorWindowController(
            image: image, screenImage: image, screenCGImage: source,
            screen: nil, captureRect: CGRect(origin: .zero, size: image.size), capturedApplication: nil,
            settingsStore: settings, onStash: { _, _ in }, writeImageToPasteboard: { _ in false },
            presentSavePanel: { _, _ in saved = true }, onClose: {}
        )
        defer { controller.close() }
        let host = try #require(controller.window?.contentView as? NSHostingView<AppLanguageEnvironment<ScreenshotEditorView>>)
        let editor = host.rootView.content
        let model = editor.model
        model.beginLongCapturePreview()
        model.longCaptureAutoScroll.start()
        #expect(model.longCaptureAutoScroll.nextStep(after: .unchanged) == .scroll)
        switch action {
        case "save": editor.onSave()
        case "pin": controller.setPinned(true)
        default: controller.close()
        }
        #expect(!model.longCaptureAutoScroll.isRunning)
        #expect(model.longCaptureAutoScroll.nextStep(after: .appended) == .none)
        #expect(model.image === image)
        #expect(saved == (action == "save"))
    }

    @Test(arguments: ["pin", "close"], [false, true]) @MainActor
    func lateCaptureCallbacksCannotRestartARetiredSession(action: String, fails: Bool) async throws {
        let suite = "zisla-auto-scroll-late-\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        let settings = FeatureSettingsStore(defaults: defaults)
        defer { settings.flushPendingChanges(); defaults.removePersistentDomain(forName: suite) }
        let screen = try #require(NSScreen.screens.first)
        let source = try #require(Self.page(width: 48, height: 160))
        let image = NSImage(cgImage: source, size: screen.frame.size)
        let entered = AsyncStream<Void>.makeStream()
        let release = AsyncStream<Void>.makeStream()
        let controller = ScreenshotEditorWindowController(
            image: image, screenImage: image, screenCGImage: source,
            screen: nil, captureRect: CGRect(origin: .zero, size: image.size), capturedApplication: nil,
            settingsStore: settings, onStash: { _, _ in }, writeImageToPasteboard: { _ in false },
            presentSavePanel: { _, _ in },
            captureScreen: { _, _ in
                entered.continuation.yield(())
                for await _ in release.stream {}
                if fails { throw ScreenshotCaptureError.permissionRequired }
                return (image, source, nil)
            }, onClose: {}
        )
        controller.window?.alphaValue = 0
        defer { release.continuation.finish(); entered.continuation.finish(); controller.close() }
        let host = try #require(controller.window?.contentView as? NSHostingView<AppLanguageEnvironment<ScreenshotEditorView>>)
        let model = host.rootView.content.model
        model.beginLongCapturePreview()
        model.longCaptureAutoScroll.start()
        model.statusMessage = "retired session"
        let capture = try #require(controller.captureLongCaptureScreen(on: screen, sessionID: 0))
        var entering = entered.stream.makeAsyncIterator()
        try #require(await entering.next())
        #expect(controller.captureLongCaptureScreen(on: screen, sessionID: 0) == nil)
        if action == "pin" { controller.setPinned(true) } else { controller.close() }
        release.continuation.finish()
        await capture.value

        #expect(model.image === image)
        #expect(model.statusMessage == "retired session")
        #expect(!model.longCaptureAutoScroll.isRunning)
        #expect(!model.isLongCapturePreviewing)
        #expect(model.hasLongCaptureResult == (action == "pin"))
        #expect(!model.canUndo)
        #expect(!controller.window!.isVisible)
    }

    private static func pixels(in image: CGImage) throws -> [UInt8] {
        var pixels = [UInt8](repeating: 0, count: image.width * image.height * 4)
        try pixels.withUnsafeMutableBytes { bytes in
            let context = try #require(CGContext(
                data: bytes.baseAddress, width: image.width, height: image.height,
                bitsPerComponent: 8, bytesPerRow: image.width * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ))
            context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        }
        return pixels
    }

    @Test(arguments: AppLanguage.allCases)
    func automaticScrollControlsAndStatusesTranslateEveryLanguage(language: AppLanguage) throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let source = try String(contentsOf: root.appendingPathComponent("Sources/Zisla/ScreenshotEditorView.swift"), encoding: .utf8)
        let calls = try NSRegularExpression(pattern: #"AppLocalization\.text\("([^"]*自动滚动[^"]*|暂停滚动)"\)"#)
        let keys = Set(calls.matches(in: source, range: NSRange(source.startIndex..., in: source)).compactMap { match in
            Range(match.range(at: 1), in: source).map { String(source[$0]) }
        })
        #expect(keys.count == 6)
        let resource = root.appendingPathComponent("Resources/Localization/\(language.rawValue).lproj/Localizable.strings")
        let table = try #require(try PropertyListSerialization.propertyList(
            from: Data(contentsOf: resource), format: nil
        ) as? [String: String])
        for key in keys {
            let value = try #require(table[key], "Missing \(language.rawValue) translation for \(key)")
            #expect(!value.isEmpty)
            #expect(AppLocalization.string(key, language: language) == value)
            if language != .simplifiedChinese && language != .traditionalChinese { #expect(value != key) }
        }
        #expect(AppLocalization.string("自动滚动", language: .english) == "Auto Scroll")
        #expect(AppLocalization.string("暂停滚动", language: .arabic) == "إيقاف التمرير مؤقتًا")
    }

    private static func page(width: Int, height: Int) -> CGImage? {
        var pixels = [UInt8](repeating: 255, count: width * height * 4)
        for y in 0..<height {
            for x in 0..<width {
                let offset = (y * width + x) * 4
                pixels[offset] = UInt8((x * 3 + y) % 251)
                pixels[offset + 1] = UInt8((x + y * 2) % 253)
                pixels[offset + 2] = UInt8((x * 2 + y * 3) % 255)
            }
        }
        return pixels.withUnsafeMutableBytes { bytes in
            CGContext(
                data: bytes.baseAddress, width: width, height: height,
                bitsPerComponent: 8, bytesPerRow: width * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )?.makeImage()
        }
    }

    private static func window(
        number: Int, owner: pid_t, bounds: CGRect = CGRect(x: 0, y: 0, width: 500, height: 500),
        layer: Int = 0, alpha: Double = 1
    ) -> [String: Any] {
        [kCGWindowOwnerPID as String: NSNumber(value: owner), kCGWindowLayer as String: NSNumber(value: layer),
         kCGWindowNumber as String: NSNumber(value: number), kCGWindowAlpha as String: NSNumber(value: alpha),
         kCGWindowBounds as String: bounds.dictionaryRepresentation]
    }
}
