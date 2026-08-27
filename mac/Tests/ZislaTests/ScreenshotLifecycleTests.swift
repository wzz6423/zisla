import Foundation
import Testing

@Suite("Screenshot lifecycle")
struct ScreenshotLifecycleTests {
    @Test
    func screenshotCapturePreservesCurrentIslandPresentation() throws {
        let source = try String(contentsOf: Self.appSourceURL, encoding: .utf8)
        let beginScreenshot = try #require(source.range(of: "private func beginScreenshot"))
        let registerHotkeys = try #require(source.range(
            of: "private func registerScreenshotHotkeys",
            range: beginScreenshot.upperBound..<source.endIndex
        ))
        let captureLifecycle = source[beginScreenshot.lowerBound..<registerHotkeys.lowerBound]

        #expect(!captureLifecycle.contains("overlayCoordinator?.stop()"))
        #expect(captureLifecycle.contains("setScreenshotSessionActive(true)"))
        #expect(captureLifecycle.contains("endScreenshotSessionIfNeeded()"))
        #expect(captureLifecycle.contains("noticePresenter?.setScreenshotActive(active)"))

        // The clipboard assistant row returns only after the capture is frozen, so it stays visible
        // during the selection without ever appearing inside the screenshot.
        let capture = try #require(captureLifecycle.range(of: "controller.start(on: captureScreens)"))
        let restoreRow = try #require(captureLifecycle.range(
            of: "clipboardAssistant.setScreenshotSelectionActive(true)"
        ))
        #expect(capture.upperBound < restoreRow.lowerBound)
        #expect(captureLifecycle.contains("guard controller.selectionWindowCount > 0 else { return }"))
        #expect(captureLifecycle.contains("clipboardAssistant.setScreenshotSelectionActive(false)"))

        // A pinned screenshot keeps the session open, so the row must leave the display on every
        // capture instead of only on the first one.
        let rowLeavesCapture = try #require(captureLifecycle.range(
            of: "AppModel.shared.clipboardAssistant.setScreenshotActive(active)"
        ))
        let sessionGuard = try #require(captureLifecycle.range(
            of: "guard isScreenshotSessionActive != active else { return }"
        ))
        #expect(rowLeavesCapture.upperBound < sessionGuard.lowerBound)
    }

    @Test
    func screenshotHotkeysStartCaptureSynchronouslyWhileMenusAreTracking() throws {
        let source = try String(contentsOf: Self.appSourceURL, encoding: .utf8)
        let registerHotkeys = try #require(source.range(of: "private func registerScreenshotHotkeys"))
        let registration = source[registerHotkeys.lowerBound..<source.endIndex]

        #expect(registration.contains("onKeyDown: { [weak self] in self?.startScreenshot() }"))
        #expect(registration.contains("onKeyDown: { [weak self] in self?.startPinnedScreenshot() }"))
        #expect(!registration.contains("Task { @MainActor [weak self] in self?.startScreenshot() }"))
    }

    @Test
    func longCaptureKeepsToolbarInteractiveWhileRangePassesThroughScrolling() throws {
        let source = try String(contentsOf: Self.editorSourceURL, encoding: .utf8)
        let captureNextScreen = try #require(source.range(of: "private func captureNextScreen()"))
        let captureLifecycle = source[captureNextScreen.lowerBound..<source.endIndex]
        let showRange = try #require(captureLifecycle.range(of: "self.showLongCaptureRangeOverlay(on: screen)"))
        let activateCapturedApplication = try #require(
            captureLifecycle.range(of: "capturedApplication?.activate()")
        )
        let rangePassesThrough = try #require(
            captureLifecycle.range(of: "rangeWindow.ignoresMouseEvents = true")
        )
        let toolbarAcceptsInput = try #require(
            captureLifecycle.range(of: "window.ignoresMouseEvents = false")
        )
        let completeToolbar = try #require(
            captureLifecycle.range(of: "configureLongCaptureToolbar(in: window)")
        )

        #expect(activateCapturedApplication.lowerBound < showRange.lowerBound)
        #expect(rangePassesThrough.lowerBound < completeToolbar.lowerBound)
        #expect(toolbarAcceptsInput.lowerBound < completeToolbar.lowerBound)
    }

    @Test
    func longCaptureDoesNotDependOnGlobalScrollMonitoring() throws {
        let source = try String(contentsOf: Self.editorSourceURL, encoding: .utf8)
        let captureNextScreen = try #require(source.range(of: "private func captureNextScreen()"))
        let captureLifecycle = source[captureNextScreen.lowerBound..<source.endIndex]

        #expect(!captureLifecycle.contains("NSEvent.addGlobalMonitorForEvents(matching: .scrollWheel)"))
        #expect(captureLifecycle.contains("scheduleLongCapture(screen: screen, sessionID: sessionID"))
    }

    @Test
    func longCaptureUsesTheDisplayBackingPixelResolution() throws {
        let source = try String(contentsOf: Self.captureSourceURL, encoding: .utf8)

        #expect(source.contains("max(screen.backingScaleFactor, 1)"))
        #expect(source.contains("Int((screen.frame.width * scale).rounded())"))
        #expect(source.contains("Int((screen.frame.height * scale).rounded())"))
    }

    @Test
    func longCaptureFinishesAfterCapturingTheCurrentFrame() throws {
        let source = try String(contentsOf: Self.editorSourceURL, encoding: .utf8)
        let finish = try #require(source.range(of: "private func finishLongCapture()"))
        let captureNext = try #require(source.range(
            of: "private func captureNextScreen()",
            range: finish.upperBound..<source.endIndex
        ))
        let finishLifecycle = source[finish.lowerBound..<captureNext.lowerBound]

        #expect(finishLifecycle.contains("captureLongCaptureScreen"))
    }

    @Test
    func longCaptureRangeWindowUsesConvertedSelectionFrame() throws {
        let source = try String(contentsOf: Self.editorSourceURL, encoding: .utf8)
        let showRange = try #require(source.range(of: "private func showLongCaptureRangeOverlay"))
        let toolbarFrame = try #require(source.range(
            of: "private func longCaptureToolbarFrame",
            range: showRange.upperBound..<source.endIndex
        ))
        let rangePresentation = source[showRange.lowerBound..<toolbarFrame.lowerBound]

        #expect(rangePresentation.contains("ScreenshotLongCaptureRangeGeometry.windowFrame"))
        #expect(rangePresentation.contains("ScreenshotWindowGeometry.localContentRect"))
        #expect(rangePresentation.contains("ScreenshotLongCaptureRangeView(selection: captureRect)"))
    }

    @Test
    func longCaptureToolbarFollowsTheSelectionInsteadOfTheScreenBottom() throws {
        let source = try String(contentsOf: Self.editorSourceURL, encoding: .utf8)
        let toolbar = try #require(source.range(of: "private func longCaptureToolbarFrame"))
        let restore = try #require(source.range(
            of: "private func restoreEditorPresentation",
            range: toolbar.upperBound..<source.endIndex
        ))
        let toolbarSource = source[toolbar.lowerBound..<restore.lowerBound]

        #expect(toolbarSource.contains("selectionFrame = ScreenshotLongCaptureRangeGeometry.windowFrame"))
        #expect(toolbarSource.contains("let belowY = selectionFrame.minY"))
        #expect(toolbarSource.contains("let aboveY = selectionFrame.maxY"))
        #expect(!toolbarSource.contains("y: visibleFrame.minY + 12"))
    }

    @Test
    func longCaptureShowsAndUpdatesASidePreview() throws {
        let source = try String(contentsOf: Self.editorSourceURL, encoding: .utf8)
        let showRange = try #require(source.range(of: "private func showLongCaptureRangeOverlay"))
        let capture = try #require(source.range(
            of: "private func captureLongCaptureScreen",
            range: showRange.upperBound..<source.endIndex
        ))
        let lifecycle = source[showRange.lowerBound..<source.endIndex]
        let captureLifecycle = source[capture.lowerBound..<source.endIndex]

        #expect(lifecycle.contains("ScreenshotLongCapturePreviewGeometry.frame"))
        #expect(lifecycle.contains("ScreenshotLongCapturePreviewView(model: model)"))
        #expect(lifecycle.contains("longCapturePreviewWindow"))
        #expect(captureLifecycle.contains("updateLongCapturePreviewFrame(on: screen)"))
    }

    @Test
    func longCaptureWindowsAreExcludedFromScreenCapture() throws {
        let source = try String(contentsOf: Self.editorSourceURL, encoding: .utf8)
        let showRange = try #require(source.range(of: "private func showLongCaptureRangeOverlay"))
        let capture = try #require(source.range(
            of: "private func captureLongCaptureScreen",
            range: showRange.upperBound..<source.endIndex
        ))
        let presentation = source[showRange.lowerBound..<capture.lowerBound]

        #expect(presentation.contains("rangeWindow.sharingType = .none"))
        #expect(presentation.contains("previewWindow.sharingType = .none"))
        #expect(presentation.contains("window.sharingType = .none"))
    }

    @Test
    func completedLongCaptureRendersTheCombinedImageInTheEditorCanvas() throws {
        let source = try String(contentsOf: Self.editorSourceURL, encoding: .utf8)

        #expect(source.contains("canvas(showsImage: model.hasLongCaptureResult)"))
        #expect(source.contains("invalidateLongCaptureSession(preservingLongCaptureResult: true)"))
    }

    @Test
    func completedLongCaptureEnablesCanvasZoomControls() throws {
        let source = try String(contentsOf: Self.editorSourceURL, encoding: .utf8)

        #expect(source.contains("@State private var canvasZoom: CGFloat = 1"))
        #expect(source.contains("zoom: model.hasLongCaptureResult ? canvasZoom : 1"))
        #expect(source.contains("adjustCanvasZoom(by: magnification)"))
        #expect(source.contains("iconButton(\"minus.magnifyingglass\", title: \"缩小\")"))
        #expect(source.contains("iconButton(\"plus.magnifyingglass\", title: \"放大\")"))
    }

    @Test
    func recognitionAlertCopiesOnlyFromItsCopyButton() throws {
        let source = try String(contentsOf: Self.editorSourceURL, encoding: .utf8)
        let recognize = try #require(source.range(of: "private func recognize("))
        let recognition = source[recognize.lowerBound..<source.endIndex]
        let visibleFrame = try #require(recognition.range(of: "visibleFrame.height"))
        let maximumHeight = try #require(recognition.range(of: "max(120, visibleHeight - 220)"))
        let lightMaterial = try #require(recognition.range(of: "resultContainer.material = .sidebar"))
        let transparentScrollBackground = try #require(recognition.range(of: "scrollView.drawsBackground = false"))
        let scrollView = try #require(recognition.range(of: "scrollView.hasVerticalScroller = true"))
        let copyButton = try #require(recognition.range(of: "alert.addButton(withTitle: \"复制\")"))
        let closeButton = try #require(recognition.range(of: "alert.addButton(withTitle: \"关闭\")"))
        let copyGuard = try #require(recognition.range(of: "guard response == .alertFirstButtonReturn else { return }"))
        let pasteboard = try #require(recognition.range(of: "let pasteboard = NSPasteboard.general"))

        #expect(visibleFrame.lowerBound < maximumHeight.lowerBound)
        #expect(lightMaterial.lowerBound < copyButton.lowerBound)
        #expect(transparentScrollBackground.lowerBound < scrollView.lowerBound)
        #expect(maximumHeight.lowerBound < scrollView.lowerBound)
        #expect(copyButton.lowerBound < closeButton.lowerBound)
        #expect(copyGuard.lowerBound < pasteboard.lowerBound)
    }

    private static let appSourceURL = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent("Sources/Zisla/ZislaApp.swift")

    private static let editorSourceURL = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent("Sources/Zisla/ScreenshotEditorView.swift")

    private static let captureSourceURL = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent("Sources/Zisla/ScreenshotCapture.swift")
}
