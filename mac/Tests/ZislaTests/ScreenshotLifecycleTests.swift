import AppKit
import Foundation
import Testing

@testable import Zisla

@Suite("Screenshot lifecycle")
struct ScreenshotLifecycleTests {
    @Test @MainActor
    func screenshotSelectionDismissesOnlyAnActiveModalSession() {
        var abortCount = 0

        ScreenshotModalSession.dismissForSelectionPresentation(
            modalWindow: nil,
            abortModal: { abortCount += 1 }
        )
        #expect(abortCount == 0)

        ScreenshotModalSession.dismissForSelectionPresentation(
            modalWindow: NSWindow(
                contentRect: .zero,
                styleMask: [.borderless],
                backing: .buffered,
                defer: false
            ),
            abortModal: { abortCount += 1 }
        )
        #expect(abortCount == 1)
    }

    @Test
    func modalSnapshotUsesTopLeftDisplayCoordinates() {
        let screenFrame = CGRect(x: 1_440, y: -900, width: 1_920, height: 1_080)
        let modalFrame = CGRect(x: 1_560, y: -300, width: 500, height: 400)

        #expect(ScreenshotModalWindowSnapshot.localTopLeftFrame(
            for: modalFrame,
            on: screenFrame
        ) == CGRect(x: 120, y: 80, width: 500, height: 400))
    }

    @Test
    func modalSnapshotIsCompositedAtItsTopLeftScreenPosition() throws {
        let background = try #require(Self.solidImage(width: 8, height: 8, color: (0, 0, 0)))
        let modal = try #require(Self.solidImage(width: 2, height: 2, color: (255, 0, 0)))
        let image = try #require(ScreenshotModalWindowSnapshot.composite(
            modal,
            in: CGRect(x: 2, y: 3, width: 2, height: 2),
            over: background,
            screenSize: CGSize(width: 8, height: 8)
        ))

        let inside = try #require(ScreenshotCaptureService.pixelColor(
            at: CGPoint(x: 2, y: 3),
            in: image,
            screenSize: CGSize(width: 8, height: 8)
        ))
        let above = try #require(ScreenshotCaptureService.pixelColor(
            at: CGPoint(x: 2, y: 2),
            in: image,
            screenSize: CGSize(width: 8, height: 8)
        ))
        #expect(inside.hex == "#FF0000")
        #expect(above.hex == "#000000")
    }

    @Test
    func screenshotCapturePreservesCurrentIslandPresentation() throws {
        let source = try String(contentsOf: Self.appSourceURL, encoding: .utf8)
        let beginScreenshot = try #require(source.range(of: "private func beginScreenshot"))
        let sessionState = try #require(source.range(
            of: "private func setScreenshotSessionActive",
            range: beginScreenshot.upperBound..<source.endIndex
        ))
        let captureLifecycle = source[beginScreenshot.lowerBound..<sessionState.lowerBound]

        #expect(!captureLifecycle.contains("overlayCoordinator?.stop()"))
        #expect(captureLifecycle.contains("setScreenshotSessionActive(true)"))

        let selectionWillPresent = try #require(captureLifecycle.range(
            of: "controller.onSelectionWillPresent = {"
        ))
        let controllerCreation = try #require(captureLifecycle.range(
            of: "let controller = ScreenshotSelectionController("
        ))
        let modalDismissal = try #require(captureLifecycle.range(
            of: "ScreenshotModalSession.dismissForSelectionPresentation()"
        ))
        let modalSnapshot = try #require(captureLifecycle.range(
            of: "let modalWindowSnapshot = ScreenshotModalWindowSnapshot.capture()"
        ))
        let liveCaptureStart = try #require(captureLifecycle.range(
            of: "setScreenshotLiveCaptureActive(true)"
        ))
        let captured = try #require(captureLifecycle.range(
            of: "controller.onCaptured",
            range: selectionWillPresent.upperBound..<captureLifecycle.endIndex
        ))
        let selectionPresentation = captureLifecycle[selectionWillPresent.lowerBound..<captured.lowerBound]
        let liveCaptureEnd = try #require(selectionPresentation.range(
            of: "self.setScreenshotLiveCaptureActive(false)"
        ))
        let frozenPresentation = try #require(selectionPresentation.range(
            of: "self.setScreenshotFrozenPresentationActive(true)"
        ))
        #expect(selectionPresentation.contains("self.setScreenshotFrozenPresentationActive(true)"))
        #expect(selectionPresentation.contains("clipboardAssistant.setScreenshotSelectionActive(true)"))
        #expect(!selectionPresentation.contains("ScreenshotModalSession.dismissForSelectionPresentation()"))
        #expect(modalSnapshot.lowerBound < modalDismissal.lowerBound)
        #expect(modalDismissal.lowerBound < controllerCreation.lowerBound)
        #expect(captureLifecycle.contains("modalWindowSnapshot?.restoreAfterModalDismissal()"))
        #expect(captureLifecycle.contains("onClose: { [weak self] in"))
        #expect(captureLifecycle.contains("modalWindowSnapshot?.restoreAfterModalDismissal()\n                    self.endScreenshotSessionIfNeeded()"))
        #expect(source.contains("modalWindow.windowController?.showWindow(nil)"))
        #expect(source.contains("title == \"取消更新\" || title == \"Cancel Update\""))
        #expect(source.contains("button.action = #selector(ScreenshotModalDismissTarget.close(_:))"))
        #expect(source.contains("window?.close()"))
        #expect(source.contains("modalWindow.level = WindowPlacement.modalWindowLevel"))
        #expect(source.contains("modalWindow.makeKeyAndOrderFront(nil)"))
        #expect(liveCaptureStart.lowerBound < controllerCreation.lowerBound)
        #expect(liveCaptureEnd.lowerBound < frozenPresentation.lowerBound)
        #expect(selectionPresentation.contains("await Task.yield()"))
        #expect(captureLifecycle.contains("captureScreen: { screen in"))
        #expect(captureLifecycle.contains("modalWindowSnapshot?.composited(over: capture, on: screen) ?? capture"))
        #expect(source.contains("CGFloat(captureImage.height) - modalFrame.maxY * scaleY"))

        let captureSource = try String(contentsOf: Self.captureSourceURL, encoding: .utf8)
        #expect(captureSource.contains("typealias WillPresentPanels = @MainActor () async -> Void"))
        #expect(captureSource.contains("if let onSelectionWillPresent {\n            await onSelectionWillPresent()"))

        let capture = try #require(captureLifecycle.range(of: "controller.start(on: captureScreens)"))
        #expect(selectionWillPresent.lowerBound < capture.lowerBound)
        let afterCapture = captureLifecycle[capture.upperBound..<captureLifecycle.endIndex]
        #expect(!afterCapture.contains("clipboardAssistant.setScreenshotSelectionActive(true)"))
        #expect(!captureLifecycle.contains("overlayCoordinator?.setScreenshotActive"))
        #expect(!captureLifecycle.contains("noticePresenter?.setScreenshotActive"))
        #expect(!captureLifecycle.contains("Task.sleep(nanoseconds: 120_000_000)"))

        let cancelled = try #require(captureLifecycle.range(
            of: "controller.onCancelled",
            range: captured.upperBound..<captureLifecycle.endIndex
        ))
        let cancelledLifecycle = captureLifecycle[cancelled.lowerBound..<captureLifecycle.endIndex]
        let capturedLifecycle = captureLifecycle[captured.lowerBound..<cancelled.lowerBound]
        #expect(!capturedLifecycle.contains("self.setScreenshotFrozenPresentationActive(false)"))
        #expect(!capturedLifecycle.contains("clipboardAssistant.setScreenshotSelectionActive(false)"))
        #expect(capturedLifecycle.contains("self.endScreenshotSessionIfNeeded()"))
        #expect(cancelledLifecycle.contains("self.setScreenshotLiveCaptureActive(false)"))

        let sessionLifecycle = source[sessionState.lowerBound...]
        let rowEntersCapture = try #require(sessionLifecycle.range(
            of: "AppModel.shared.clipboardAssistant.setScreenshotActive(active)"
        ))
        let sessionGuard = try #require(sessionLifecycle.range(
            of: "guard isScreenshotSessionActive != active else { return }"
        ))
        #expect(rowEntersCapture.upperBound < sessionGuard.lowerBound)
        #expect(sessionLifecycle.contains("if !active {"))
        #expect(sessionLifecycle.contains("setScreenshotLiveCaptureActive(false)"))
        #expect(sessionLifecycle.contains("setScreenshotFrozenPresentationActive(false)"))
    }

    @Test
    func screenshotHotkeysStartCaptureSynchronouslyWhileMenusAreTracking() throws {
        let source = try String(contentsOf: Self.appSourceURL, encoding: .utf8)
        let registerHotkeys = try #require(source.range(of: "private func registerScreenshotHotkeys"))
        let registration = source[registerHotkeys.lowerBound..<source.endIndex]

        #expect(registration.contains("onKeyDown: { [weak self] in self?.startScreenshot() }"))
        #expect(registration.contains("onKeyDown: { [weak self] in self?.startPinnedScreenshot() }"))
        #expect(!registration.contains("Task { @MainActor [weak self] in self?.startScreenshot() }"))

        let beginScreenshot = try #require(source.range(of: "private func beginScreenshot"))
        let sessionState = try #require(source.range(
            of: "private func setScreenshotSessionActive",
            range: beginScreenshot.upperBound..<source.endIndex
        ))
        let captureLifecycle = source[beginScreenshot.lowerBound..<sessionState.lowerBound]
        #expect(!captureLifecycle.contains("cancelTrackingWithoutAnimation()"))
        #expect(!captureLifecycle.contains("Task.sleep(nanoseconds: 120_000_000)"))
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
    func screenshotCaptureUsesTheMacOS26ConfigurationAndKeepsAnOlderFallback() throws {
        let source = try String(contentsOf: Self.captureSourceURL, encoding: .utf8)

        #expect(source.contains("if #available(macOS 26.0, *)"))
        #expect(source.contains("SCScreenshotConfiguration()"))
        #expect(source.contains("SCScreenshotManager.captureScreenshot("))
        #expect(source.contains("configuration.displayIntent = .local"))
        #expect(source.contains("configuration.dynamicRange = .sdr"))
        #expect(source.contains("output.sdrImage"))
        #expect(source.contains("detachedImageAndDiagnose(image, api: \"SCScreenshotConfiguration\")"))
        #expect(source.contains("detachedImageAndDiagnose(image, api: \"SCStreamConfiguration\")"))
        #expect(source.contains("api: \"CGDisplayCreateImage\""))
        #expect(source.contains("static func detachedImage(from image: CGImage) -> CGImage?"))
        #expect(source.contains("static func frameDiagnostics("))
    }

    @Test
    func systemScreenshotNotificationObserversDoNotRetainTheMonitor() throws {
        let source = try String(contentsOf: Self.systemScreenshotMonitorSourceURL, encoding: .utf8)

        #expect(source.contains("queue: .main) { [weak self] notification in"))
        #expect(source.contains("Task { @MainActor [weak self] in"))
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
        #expect(source.contains("iconButton(\"minus.magnifyingglass\", title: AppLocalization.text(\"缩小\"))"))
        #expect(source.contains("iconButton(\"plus.magnifyingglass\", title: AppLocalization.text(\"放大\"))"))
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
        let copyButton = try #require(recognition.range(of: "alert.addButton(withTitle: AppLocalization.text(\"复制\"))"))
        let closeButton = try #require(recognition.range(of: "alert.addButton(withTitle: AppLocalization.text(\"关闭\"))"))
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

    private static let systemScreenshotMonitorSourceURL = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent("Sources/Zisla/SystemScreenshotMonitor.swift")

    private static func solidImage(
        width: Int,
        height: Int,
        color: (UInt8, UInt8, UInt8)
    ) -> CGImage? {
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        for offset in stride(from: 0, to: pixels.count, by: 4) {
            pixels[offset] = color.0
            pixels[offset + 1] = color.1
            pixels[offset + 2] = color.2
            pixels[offset + 3] = 255
        }
        guard let provider = CGDataProvider(data: Data(pixels) as CFData) else { return nil }
        return CGImage(
            width: width,
            height: height,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.last.rawValue),
            provider: provider,
            decode: nil,
            shouldInterpolate: false,
            intent: .defaultIntent
        )
    }
}
