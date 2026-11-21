import AppKit
import CoreML
import SwiftUI
import Testing
import Vision
import XCTest
import ZislaCore
@testable import ZislaKit
@testable import Zisla

@MainActor
@Suite(.serialized)
struct ScreenshotRecognitionTests {
    @Test(arguments: ["识图 / OCR", "翻译并复制", "表格识别"])
    func toolbarMenuStartsRecognitionBeforeReturningToTheEditor(title: String) throws {
        let releaseAccessibility = EnhancedAccessibilityTestScope.acquire()
        defer { releaseAccessibility() }
        let fixture = try Fixture(image: makeImage())
        defer { fixture.close() }
        let window = try #require(fixture.controller.window)
        let host = try #require(window.contentView)
        window.setFrameOrigin(CGPoint(x: -100_000, y: -100_000))
        window.orderFrontRegardless()
        for _ in 0..<3 {
            host.layoutSubtreeIfNeeded()
            RunLoop.main.run(mode: .default, before: Date(timeIntervalSinceNow: 0.01))
        }
        let control = try #require(Self.accessibilityObjects(host).first {
            $0.responds(to: NSSelectorFromString("accessibilityHelp"))
                && $0.value(forKey: "accessibilityHelp") as? String
                == AppLocalization.text("识别图片中的文字或表格")
        })
        let selection = RecognitionMenuSelection(title: AppLocalization.text(title), model: fixture.model)
        NotificationCenter.default.addObserver(selection, selector: #selector(RecognitionMenuSelection.began(_:)),
                                               name: NSMenu.didBeginTrackingNotification, object: nil)
        defer { NotificationCenter.default.removeObserver(selection) }
        let action = NSSelectorFromString("accessibilityPerformPress")
        try #require(control.responds(to: action))
        control.performSelector(onMainThread: action, with: nil, waitUntilDone: true)
        let deadline = Date(timeIntervalSinceNow: 3)
        while !selection.selected, Date() < deadline {
            RunLoop.main.run(mode: .default, before: deadline)
        }
        #expect(selection.selected, "The screenshot menu must dispatch its selected recognition action")
        #expect(selection.startedRecognition, "Selecting \(title) must start a recognition operation")
        #expect(!fixture.model.isRecognizing, "Cancelling a queued menu action must stop recognition")
    }

    @Test(arguments: [ScreenshotRecognitionMode.text, .translate, .table], ["failure", "empty"])
    func engineFailureRecoversOCRTranslationAndTableOnCPU(mode: ScreenshotRecognitionMode, outcome: String) async throws {
        let model = ScreenshotEditorModel(image: try makeImage())
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let destination = directory.appendingPathComponent("recovered.xlsx")
        let source = "识别成功 2468"
        var result: String?
        let task = try #require(model.recognize(mode,
                                                translationService: .init(providers: [{ text, _ in
                                                    #expect(text == source, "Translation must receive the recovered OCR text")
                                                    return "Recovered translation"
                                                }]), chooseTableDestination: { destination }, recognizeImage: { image, operation in
                                                    try operation.recognize(image) { _, request in
                                                        #expect(request.recognitionLevel == .accurate, "Recovery must retain accurate Chinese recognition")
                                                        #expect(request.recognitionLanguages.contains("zh-Hans"))
                                                        if request.computeDevice(for: .main) == nil {
                                                            if outcome == "failure" { throw Self.engineFailure }
                                                            return []
                                                        }
                                                        #expect(Self.usesCPU(request), "The failed engine must recover without Neural Engine acceleration")
                                                        return Self.fragments(source)
                                                    }
                                                }) { text, _ in result = text })
        await task.value
        #expect(!model.isRecognizing)
        switch mode {
        case .text: #expect(result == source && model.statusMessage == nil)
        case .translate: #expect(result == "Recovered translation" && model.statusMessage == nil)
        case .table:
            #expect(result == nil)
            #expect(FileManager.default.fileExists(atPath: destination.path), "Recovered table recognition must save a workbook")
            if FileManager.default.fileExists(atPath: destination.path) {
                #expect(try Data(contentsOf: destination).starts(with: [0x50, 0x4B]))
                let output = try await AIAgentProcessRunner.run(executableURL: URL(fileURLWithPath: "/usr/bin/unzip"),
                                                                arguments: ["-p", destination.path, "xl/worksheets/sheet1.xml"], workingDirectoryURL: directory)
                #expect(output.status == 0)
                #expect(String(decoding: output.standardOutput, as: UTF8.self).contains(source))
            }
            #expect(model.statusMessage == AppLocalization.text("表格已保存：%@", destination.lastPathComponent))
        }
    }

    @Test(arguments: ["failure", "empty", "unsupported CPU"])
    func unsuccessfulCPURecoveryReportsAResultAndAllowsRetry(outcome: String) async throws {
        let model = ScreenshotEditorModel(image: try makeImage())
        let request = CancellationProbeRequest()
        request.supportsCPU = outcome != "unsupported CPU"
        let task = try #require(model.recognize(.text, recognizeImage: { image, _ in
            try ScreenshotRecognitionOperation(request: request).recognize(image) { _, request in
                if request.computeDevice(for: .main) == nil { throw Self.engineFailure }
                #expect(Self.usesCPU(request))
                if outcome == "empty" { return [] }
                throw RecognitionFailure()
            }
        }) { _, _ in Issue.record("Failed recovery must not present a result") })
        await task.value
        #expect(!model.isRecognizing)
        if outcome == "empty" {
            #expect(model.statusMessage == AppLocalization.text("未识别到文字"))
        } else {
            let failure = outcome == "unsupported CPU" ? Self.engineFailure.localizedDescription
                : RecognitionFailure().localizedDescription
            #expect(model.statusMessage == AppLocalization.text("识别失败：%@", failure))
        }
        var result: String?
        let retry = try #require(model.recognize(.text, recognizeImage: { _, _ in Self.fragments("retry") }) {
            text, _ in result = text
        })
        await retry.value
        #expect(result == "retry" && model.statusMessage == nil && !model.isRecognizing)
    }

    @Test(arguments: ["before retry", "during CPU configuration", "during retry", "first result", "Vision cancellation", "Swift cancellation"])
    func cancellationStopsCPURecoveryAndDiscardsItsResult(stage: String) throws {
        let request = CancellationProbeRequest()
        let operation = ScreenshotRecognitionOperation(request: request)
        if stage == "during CPU configuration" { request.onSupportedDevices = { [weak operation] in operation?.cancel() } }
        let image = try #require(makeImage().cgImage(forProposedRect: nil, context: nil, hints: nil))
        #expect(throws: CancellationError.self) {
            try operation.recognize(image) { _, request in
                if request.computeDevice(for: .main) == nil {
                    if stage == "first result" {
                        operation.cancel()
                        return Self.fragments("late first result")
                    }
                    if stage == "Vision cancellation" {
                        throw NSError(domain: VNErrorDomain, code: VNErrorCode.requestCancelled.rawValue)
                    }
                    if stage == "Swift cancellation" { throw CancellationError() }
                    if stage == "before retry" { operation.cancel() }
                    throw Self.engineFailure
                }
                #expect(stage == "during retry", "Cancelled work must not start CPU recovery")
                operation.cancel()
                return Self.fragments("late result")
            }
        }
    }

    @Test
    func normalRecognitionKeepsAutomaticAcceleration() throws {
        let request = CancellationProbeRequest()
        let operation = ScreenshotRecognitionOperation(request: request)
        let image = try #require(makeImage().cgImage(forProposedRect: nil, context: nil, hints: nil))
        let fragments = try operation.recognize(image) { _, request in
            #expect(request.computeDevice(for: .main) == nil, "Successful OCR must retain Vision's default device choice")
            return Self.fragments("normal result")
        }
        #expect(fragments == Self.fragments("normal result"))
    }

    @Test(arguments: ["failure", "empty"], [false, true])
    func deviceDiscoveryFailurePreservesTheOCROutcomeUnlessCancelled(outcome: String, cancel: Bool) throws {
        let request = CancellationProbeRequest()
        request.supportedDevicesError = RecognitionFailure()
        let operation = ScreenshotRecognitionOperation(request: request)
        if cancel { request.onSupportedDevices = { operation.cancel() } }
        let image = try #require(makeImage().cgImage(forProposedRect: nil, context: nil, hints: nil))
        do {
            let fragments = try operation.recognize(image) { _, _ in
                if outcome == "failure" { throw Self.engineFailure }
                return []
            }
            #expect(!cancel && outcome == "empty" && fragments.isEmpty,
                    "Unavailable device discovery must retain the original empty result")
        } catch is CancellationError {
            #expect(cancel && request.wasCancelled)
        } catch {
            #expect(!cancel && outcome == "failure" && (error as NSError) == Self.engineFailure,
                    "Unavailable device discovery must retain the original OCR error")
        }
        #expect(request.computeDevice(for: .main) == nil)
    }

    @Test(arguments: ["success", "failure", "cancelled"])
    func CPURecoveryRestoresAutomaticDeviceSelectionForTheNextImage(outcome: String) throws {
        let request = CancellationProbeRequest()
        let operation = ScreenshotRecognitionOperation(request: request)
        let image = try #require(makeImage().cgImage(forProposedRect: nil, context: nil, hints: nil))
        do {
            let fragments = try operation.recognize(image) { _, request in
                if request.computeDevice(for: .main) == nil { return [] }
                #expect(Self.usesCPU(request))
                if outcome == "failure" { throw RecognitionFailure() }
                if outcome == "cancelled" { operation.cancel() }
                return Self.fragments("recovered")
            }
            #expect(outcome == "success" && fragments == Self.fragments("recovered"))
        } catch is CancellationError {
            #expect(outcome == "cancelled")
        } catch {
            #expect(outcome == "failure" && error is RecognitionFailure)
        }
        #expect(request.computeDevice(for: .main) == nil,
                "CPU recovery must not force later images in the batch to use the CPU")
        if outcome != "cancelled" {
            let next = try operation.recognize(image) { _, request in
                #expect(request.computeDevice(for: .main) == nil,
                        "The next image must start with Vision's automatic device selection")
                return Self.fragments("next image")
            }
            #expect(next == Self.fragments("next image"))
        }
    }

    @Test(arguments: ["Vision cancellation", "cancelled error", "ordinary error"])
    func CPURecoveryChecksCancellationWhenItsAttemptThrows(outcome: String) throws {
        let request = CancellationProbeRequest()
        let operation = ScreenshotRecognitionOperation(request: request)
        let image = try #require(makeImage().cgImage(forProposedRect: nil, context: nil, hints: nil))
        do {
            _ = try operation.recognize(image) { _, request in
                if request.computeDevice(for: .main) == nil { return [] }
                if outcome == "Vision cancellation" {
                    throw NSError(domain: VNErrorDomain, code: VNErrorCode.requestCancelled.rawValue)
                }
                if outcome == "cancelled error" { operation.cancel() }
                throw RecognitionFailure()
            }
            Issue.record("An unsuccessful CPU attempt must not return a result")
        } catch is CancellationError {
            #expect(outcome != "ordinary error")
        } catch {
            #expect(outcome == "ordinary error" && error is RecognitionFailure,
                    "CPU attempts must distinguish cancellation from ordinary recognition failures")
        }
    }

    @Test
    func missingRecognitionMenuItemStillEndsTracking() throws {
        let fixture = try Fixture(image: makeImage())
        defer { fixture.close() }
        let selection = RecognitionMenuSelection(title: "Synthetic missing item", model: fixture.model)
        selection.began(Notification(name: NSMenu.didBeginTrackingNotification, object: NSMenu()))
        RunLoop.main.run(mode: .eventTracking, before: Date(timeIntervalSinceNow: 0.05))
        #expect(selection.selected && !selection.startedRecognition,
                "A missing menu item must end tracking rather than block the test host")
        #expect(!fixture.model.isRecognizing)
    }

    @Test(arguments: AppLanguage.allCases)
    func screenshotOverlayShowsRecognitionAndExportStatusInEveryLanguage(language: AppLanguage) async throws {
        let previous = UserDefaults.standard.volatileDomain(forName: UserDefaults.argumentDomain)
        var arguments = previous
        arguments[AppLocalization.defaultsKey] = language.rawValue
        UserDefaults.standard.setVolatileDomain(arguments, forName: UserDefaults.argumentDomain)
        defer { UserDefaults.standard.setVolatileDomain(previous, forName: UserDefaults.argumentDomain) }
        let releaseAccessibility = EnhancedAccessibilityTestScope.acquire()
        defer { releaseAccessibility() }
        let fixture = try Fixture(image: makeImage())
        defer { fixture.close() }
        let window = try #require(fixture.controller.window)
        window.setContentSize(CGSize(width: 1_600, height: 600))
        let frame = window.frame
        let host = try #require(window.contentView)
        let localizationRoot = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Resources/Localization")
        let translations = try #require(NSDictionary(contentsOf: localizationRoot
                .appendingPathComponent("\(language.rawValue).lproj/Localizable.strings")) as? [String: String])
        let keys = ["正在识别...", "正在翻译…", "识别失败：%@", "未识别到文字", "翻译失败，请重试或使用浏览器翻译", "表格已保存：%@"]
        for key in keys {
            let translation = try #require(translations[key], "Missing \(language.rawValue) recognition status: \(key)")
            #expect(!translation.isEmpty)
            #expect(translation.components(separatedBy: "%@").count == key.components(separatedBy: "%@").count)
            #expect(AppLocalization.string(key, language: language) == translation)
            let message = key.contains("%@")
                ? AppLocalization.format(key, locale: language.locale, ["synthetic.xlsx"])
                : AppLocalization.string(key, language: language)
            fixture.model.statusMessage = message
            for _ in 0..<3 {
                host.layoutSubtreeIfNeeded()
                await withCheckedContinuation { continuation in DispatchQueue.main.async { continuation.resume() } }
            }
            #expect(Self.accessibilityObjects(host).contains { object in
                ["accessibilityTitle", "accessibilityLabel", "accessibilityValue"].contains { key in
                    object.responds(to: NSSelectorFromString(key)) && object.value(forKey: key) as? String == message
                }
            }, "The screenshot overlay must expose its \(language.rawValue) status: \(message)")
            try Self.expectStatusBesideRecognition(message, in: host)
        }
        #expect(window.frame == frame && fixture.model.annotations.isEmpty && !fixture.model.canUndo)
    }

    @Test(arguments: ["正在识别...", "正在翻译…"])
    func recognitionStatusMovesWithItsToolbarAndDisappearsWhenCleared(key: String) async throws {
        let releaseAccessibility = EnhancedAccessibilityTestScope.acquire()
        defer { releaseAccessibility() }
        let fixture = try Fixture(image: makeImage())
        defer { fixture.close() }
        let window = try #require(fixture.controller.window)
        window.setContentSize(CGSize(width: 1_600, height: 600))
        let host = try #require(window.contentView)
        let message = AppLocalization.text(key)
        fixture.model.statusMessage = message
        for _ in 0..<3 {
            host.layoutSubtreeIfNeeded()
            await withCheckedContinuation { continuation in DispatchQueue.main.async { continuation.resume() } }
        }
        let handle = try #require(Self.dragHandle(in: host))
        let toolbar = try #require(handle.superview)
        let originalFrame = toolbar.convert(toolbar.bounds, to: host)
        let start = handle.convert(CGPoint(x: 10, y: ScreenshotToolbarLayout.height / 2), to: nil)
        let finish = CGPoint(x: start.x + 100, y: start.y - 100)
        for (type, point) in [(NSEvent.EventType.leftMouseDown, start), (.leftMouseDragged, finish), (.leftMouseUp, finish)] {
            let event = try #require(NSEvent.mouseEvent(with: type, location: point, modifierFlags: [], timestamp: 0,
                                                        windowNumber: window.windowNumber, context: nil, eventNumber: 1, clickCount: 1, pressure: 1))
            switch type {
            case .leftMouseDown: handle.mouseDown(with: event)
            case .leftMouseDragged: handle.mouseDragged(with: event)
            default: handle.mouseUp(with: event)
            }
        }
        for _ in 0..<3 {
            host.layoutSubtreeIfNeeded()
            await withCheckedContinuation { continuation in DispatchQueue.main.async { continuation.resume() } }
        }
        let movedFrame = toolbar.convert(toolbar.bounds, to: host)
        #expect(abs(movedFrame.midY - originalFrame.midY) >= 90)
        try Self.expectStatusBesideRecognition(message, in: host)
        fixture.model.statusMessage = nil
        for _ in 0..<3 {
            host.layoutSubtreeIfNeeded()
            await withCheckedContinuation { continuation in DispatchQueue.main.async { continuation.resume() } }
        }
        #expect(!Self.accessibilityObjects(host).contains {
            $0.responds(to: NSSelectorFromString("accessibilityValue"))
                && $0.value(forKey: "accessibilityValue") as? String == message
        }, "Clearing the operation status must remove its toolbar label")
        #expect(!fixture.model.isRecognizing && fixture.model.annotations.isEmpty && !fixture.model.canUndo)
    }

    @Test(arguments: [AppLanguage.simplifiedChinese, .english, .arabic], [CGFloat(800), 1_600])
    func longRecognitionStatusKeepsTheToolbarInsideItsViewport(language: AppLanguage, availableWidth: CGFloat) async throws {
        let previous = UserDefaults.standard.volatileDomain(forName: UserDefaults.argumentDomain)
        var arguments = previous
        arguments[AppLocalization.defaultsKey] = language.rawValue
        UserDefaults.standard.setVolatileDomain(arguments, forName: UserDefaults.argumentDomain)
        defer { UserDefaults.standard.setVolatileDomain(previous, forName: UserDefaults.argumentDomain) }
        let releaseAccessibility = EnhancedAccessibilityTestScope.acquire()
        defer { releaseAccessibility() }
        let fixture = try Fixture(image: makeImage())
        defer { fixture.close() }
        let window = try #require(fixture.controller.window)
        window.setContentSize(CGSize(width: availableWidth, height: 600))
        let host = try #require(window.contentView)
        for _ in 0..<3 {
            host.layoutSubtreeIfNeeded()
            await withCheckedContinuation { continuation in DispatchQueue.main.async { continuation.resume() } }
        }
        let toolbar = try #require(Self.dragHandle(in: host)?.superview)
        let originalWidth = toolbar.frame.width
        let frame = window.frame
        let message = AppLocalization.text("识别失败：%@", String(repeating: "Synthetic OCR ", count: 80))
        fixture.model.statusMessage = message
        for _ in 0..<3 {
            host.layoutSubtreeIfNeeded()
            await withCheckedContinuation { continuation in DispatchQueue.main.async { continuation.resume() } }
        }
        let statusObject = try #require(Self.accessibilityObjects(host).first {
            $0.responds(to: NSSelectorFromString("accessibilityValue"))
                && $0.value(forKey: "accessibilityValue") as? String == message
        })
        let status = try #require(statusObject as? any NSAccessibilityElementProtocol)
        let statusFrame = status.accessibilityFrame()
        #expect(statusFrame.width > 0 && statusFrame.width <= 240,
                "A long recognition error must not consume an unbounded width in the toolbar")
        #expect(statusFrame.height <= ScreenshotToolbarLayout.height,
                "A long recognition error must remain on one toolbar row")
        #expect(statusObject.value(forKey: "accessibilityHelp") as? String == message,
                "Truncating the visible status must retain the complete error in its tooltip")
        #expect(toolbar.frame.width <= availableWidth - 24)
        #expect(toolbar.frame.width == min(originalWidth + 240 + ScreenshotToolbarLayout.spacing, availableWidth - 24),
                "Showing status must reserve room within the available toolbar viewport")
        if availableWidth == 1_600 { try Self.expectStatusBesideRecognition(message, in: host) }
        fixture.model.statusMessage = nil
        for _ in 0..<3 {
            host.layoutSubtreeIfNeeded()
            await withCheckedContinuation { continuation in DispatchQueue.main.async { continuation.resume() } }
        }
        #expect(toolbar.frame.width == originalWidth && window.frame == frame)
        #expect(fixture.model.annotations.isEmpty && !fixture.model.canUndo)
    }

    @Test
    func longCaptureToolbarReservesSpaceForRecognitionStatus() throws {
        let previous = UserDefaults.standard.volatileDomain(forName: UserDefaults.argumentDomain)
        var arguments = previous
        arguments[AppLocalization.defaultsKey] = AppLanguage.english.rawValue
        UserDefaults.standard.setVolatileDomain(arguments, forName: UserDefaults.argumentDomain)
        defer { UserDefaults.standard.setVolatileDomain(previous, forName: UserDefaults.argumentDomain) }
        let fixture = try Fixture(image: makeImage())
        defer { fixture.close() }
        let screen = try #require(NSScreen.screens.first)
        let originalFrame = fixture.controller.longCaptureToolbarFrame(on: screen)
        let message = AppLocalization.text("正在识别...")
        fixture.model.statusMessage = message
        let frame = fixture.controller.longCaptureToolbarFrame(on: screen)
        #expect(frame.width == min(originalFrame.width + ScreenshotToolbarLayout.statusWidth(for: message)
                    + ScreenshotToolbarLayout.spacing, screen.visibleFrame.width - 24),
        "The floating toolbar window must account for its inline recognition status")
        #expect(screen.visibleFrame.contains(frame))
        fixture.model.statusMessage = nil
        #expect(fixture.controller.longCaptureToolbarFrame(on: screen) == originalFrame)
    }

    @Test(arguments: [ScreenshotRecognitionMode.text, .table, .translate])
    func cancellationBeforeQueuedTaskStartsDoesNotOpenDialogsOrChangeStatus(mode: ScreenshotRecognitionMode) async throws {
        let model = ScreenshotEditorModel(image: try makeImage())
        let task = try #require(model.recognize(mode, makeTranslationFailureAlert: {
            Issue.record("A screenshot closed before dispatch must not open an error dialog")
            return NSAlert()
        }, chooseTableDestination: {
            Issue.record("A screenshot closed before dispatch must not open its destination panel")
            return nil
        }, recognizeImage: { _, _ in
            Issue.record("A screenshot closed before dispatch must not start recognition")
            return []
        }) { _, _ in Issue.record("Cancelled recognition must not present a result") })
        model.cancelRecognition()
        model.statusMessage = "new screenshot state"
        await task.value
        #expect(model.statusMessage == "new screenshot state")
        #expect(!model.isRecognizing)
    }

    @Test
    func replacingAnIdleCapturePreservesItsExistingStatus() throws {
        let model = ScreenshotEditorModel(image: try makeImage())
        model.statusMessage = "existing editor status"
        model.image = try makeImage()
        #expect(model.statusMessage == "existing editor status")
        #expect(!model.isRecognizing)
    }

    @Test(arguments: AppLanguage.allCases)
    func translationUsesRecognizedTextAndTheQuickActionsTargetLanguage(language: AppLanguage) async throws {
        let model = ScreenshotEditorModel(image: try makeImage())
        let source = "First line\nSecond line + & <text>"
        let translated = "  Translated line\nSecond translated line  "
        var result: String?
        let task = try #require(model.recognize(.translate,
                                                targetLanguage: language.translateTargetCode,
                                                translationService: .init(providers: [{ text, target in
                                                    #expect(text == source)
                                                    #expect(target == language.translateTargetCode)
                                                    return translated
                                                }]),
                                                recognizeImage: { _, _ in Self.fragments(source) }) { text, _ in result = text })
        await task.value
        #expect(result == translated)
        #expect(model.statusMessage == nil)
        #expect(!model.isRecognizing)
    }

    @Test(arguments: ["empty", "failure", "invalid image"])
    func unsuccessfulOCRNeverStartsTranslation(outcome: String) async throws {
        let model = ScreenshotEditorModel(image: outcome == "invalid image" ? NSImage() : try makeImage())
        let task = try #require(model.recognize(.translate,
                                                translationService: .init(providers: [{ _, _ in
                                                    Issue.record("Unsuccessful OCR must not send text to translation providers")
                                                    return "unexpected"
                                                }]),
                                                recognizeImage: { _, _ in
                                                    if outcome == "failure" { throw RecognitionFailure() }
                                                    if outcome == "invalid image" { Issue.record("Invalid image must not reach Vision") }
                                                    return []
                                                }) { _, _ in Issue.record("Unsuccessful OCR must not present a translation") })
        await task.value
        #expect(!model.isRecognizing)
        #expect(model.statusMessage != nil)
    }

    @Test(arguments: [false, true])
    func failedTranslationReportsFailureAndAllowsRetry(unrelatedWindowIsKey: Bool) async throws {
        _ = NSApplication.shared
        let model = ScreenshotEditorModel(image: try makeImage())
        let screenshot = ScreenshotEditorWindow(contentRect: CGRect(x: -100_000, y: -100_000, width: 320, height: 200),
                                                styleMask: [.borderless], backing: .buffered, defer: false)
        screenshot.isReleasedWhenClosed = false
        screenshot.alphaValue = 0
        screenshot.level = .screenSaver
        screenshot.orderFrontRegardless()
        let other = NSWindow(contentRect: screenshot.frame, styleMask: [.titled], backing: .buffered, defer: false)
        other.isReleasedWhenClosed = false
        other.alphaValue = 0
        if unrelatedWindowIsKey { other.makeKeyAndOrderFront(nil) }
        let alert = PresentationProbeAlert()
        alert.window.isReleasedWhenClosed = false
        alert.window.alphaValue = 0
        defer { alert.window.close(); other.close(); screenshot.close() }
        alert.onPresent = {
            #expect(!model.isRecognizing, "Failure must release the toolbar before opening its error dialog")
            #expect(alert.window.level.rawValue > screenshot.level.rawValue)
            alert.window.level = .normal
            NotificationCenter.default.post(name: NSWindow.didBecomeKeyNotification, object: alert.window)
            #expect(alert.window.level.rawValue > screenshot.level.rawValue,
                    "AppKit making the error dialog key must not place it below the screenshot")
        }
        let failed = try #require(model.recognize(.translate,
                                                  translationService: .init(providers: [{ _, _ in throw URLError(.notConnectedToInternet) }],
                                                                            waitForTimeout: {}),
                                                  makeTranslationFailureAlert: { alert },
                                                  recognizeImage: { _, _ in Self.fragments("source") }) { _, _ in Issue.record("A failed translation must not present or copy the OCR source") })
        await failed.value
        await withCheckedContinuation { continuation in
            RunLoop.main.perform(inModes: [.common]) { continuation.resume() }
        }
        #expect(alert.wasPresented, "Translation failure must open its error dialog")
        #expect(alert.messageText == AppLocalization.text("翻译"))
        #expect(alert.informativeText.hasPrefix(AppLocalization.text("翻译失败，请重试或使用浏览器翻译")))
        #expect(alert.buttons.map(\.title) == [AppLocalization.text("关闭")])
        #expect(alert.buttons.first?.keyEquivalent == "\u{1b}")
        #expect(alert.accessoryView == nil, "Failure must not display or copy untranslated OCR text")
        #expect(model.statusMessage == nil)
        #expect(!model.isRecognizing)
        #expect(screenshot.isVisible)
        alert.window.level = .normal
        NotificationCenter.default.post(name: NSWindow.didBecomeKeyNotification, object: alert.window)
        #expect(alert.window.level == .normal, "A closed error dialog must release its level observer")
        var result: String?
        let retry = try #require(model.recognize(.translate,
                                                 translationService: .init(providers: [{ _, _ in "recovered translation" }]),
                                                 recognizeImage: { _, _ in Self.fragments("source") }) { text, _ in result = text })
        await retry.value
        #expect(result == "recovered translation")
        #expect(!model.isRecognizing)
        #expect(model.statusMessage == nil)
    }

    @Test(arguments: ["unavailable", "timeout", "system", "localized"])
    func translationFailureDialogExplainsTheErrorWithoutPresentingASuccess(kind: String) async throws {
        _ = NSApplication.shared
        let model = ScreenshotEditorModel(image: try makeImage())
        let alert = PresentationProbeAlert()
        alert.window.isReleasedWhenClosed = false
        alert.window.alphaValue = 0
        defer { alert.window.close() }
        let error: any Error = switch kind {
        case "unavailable": ClipboardTranslationError.unavailable
        case "timeout": URLError(.timedOut)
        case "system": NSError(domain: "TranslationErrorDomain", code: 11,
                               userInfo: [NSLocalizedDescriptionKey: "Synthetic target language is unavailable"])
        default: RecognitionFailure()
        }
        let task = try #require(model.recognize(.text, recognizeImage: { _, _ in Self.fragments("source") }) {
            _, operation in
            model.presentTranslationFailure(error, operation: operation, alert: alert)
        })
        await task.value
        await withCheckedContinuation { continuation in
            RunLoop.main.perform(inModes: [.common]) { continuation.resume() }
        }
        let summary = AppLocalization.text("翻译失败，请重试或使用浏览器翻译")
        #expect(alert.wasPresented)
        #expect(alert.messageText == AppLocalization.text("翻译"))
        #expect(alert.informativeText == (kind == "unavailable"
                ? summary : summary + "\n\n" + error.localizedDescription))
        #expect(alert.buttons.map(\.title) == [AppLocalization.text("关闭")])
        #expect(alert.accessoryView == nil)
        #expect(model.statusMessage == nil)
    }

    @Test(arguments: ["close", "replace"])
    func aQueuedTranslationFailureIsDiscardedWhenItsCaptureIsInvalidated(action: String) async throws {
        _ = NSApplication.shared
        let fixture = try Fixture(image: makeImage())
        defer { fixture.close() }
        let model = fixture.model
        let replacement = try makeImage()
        let alert = PresentationProbeAlert()
        alert.window.isReleasedWhenClosed = false
        alert.window.alphaValue = 0
        defer { alert.window.close() }
        let task = try #require(model.recognize(.translate,
                                                translationService: .init(providers: [{ _, _ in throw ClipboardTranslationError.unavailable }],
                                                                          waitForTimeout: {}),
                                                makeTranslationFailureAlert: {
                                                    switch action {
                                                    case "close": fixture.controller.close()
                                                    default: model.image = replacement
                                                    }
                                                    model.statusMessage = "replacement capture"
                                                    return alert
                                                }, recognizeImage: { _, _ in Self.fragments("source") }) { _, _ in Issue.record("Failed translation must not present a successful result") })
        await task.value
        await withCheckedContinuation { continuation in
            RunLoop.main.perform(inModes: [.common]) { continuation.resume() }
        }
        #expect(!alert.wasPresented, "An invalidated capture must not open a queued error dialog")
        #expect(model.statusMessage == "replacement capture")
        #expect(!model.isRecognizing)
    }

    @Test
    func directTaskCancellationDuringTranslationNeverShowsAnErrorDialog() async throws {
        let model = ScreenshotEditorModel(image: try makeImage())
        let gate = TranslationGate()
        let task = try #require(model.recognize(.translate,
                                                translationService: .init(providers: [{ _, _ in await gate.translate() }]),
                                                makeTranslationFailureAlert: {
                                                    Issue.record("Task cancellation must not be reported as a translation failure")
                                                    return NSAlert()
                                                }, recognizeImage: { _, _ in Self.fragments("source") }) { _, _ in Issue.record("Task cancellation must not present or copy a translation") })
        #expect(await XCTWaiter.fulfillment(of: [gate.started], timeout: 3) == .completed)
        task.cancel()
        let completed = XCTestExpectation(description: "Cancelled translation finished")
        let completion = Task {
            await task.value
            completed.fulfill()
        }
        #expect(await XCTWaiter.fulfillment(of: [completed, gate.cancelled], timeout: 3) == .completed)
        await gate.finish("late translation")
        await completion.value
        #expect(await XCTWaiter.fulfillment(of: [gate.returned], timeout: 3) == .completed)
        #expect(model.statusMessage == nil)
        #expect(!model.isRecognizing)
    }

    @Test(arguments: ["close", "replace", "cancel"])
    func cancellationDuringTranslationDiscardsLateResultsAndReleasesTheProvider(action: String) async throws {
        let fixture = try Fixture(image: makeImage())
        defer { fixture.close() }
        let model = fixture.model
        let gate = TranslationGate()
        let task = try #require(model.recognize(.translate,
                                                translationService: .init(providers: [{ _, _ in await gate.translate() }]),
                                                makeTranslationFailureAlert: {
                                                    Issue.record("Cancelled translation must not open an error dialog")
                                                    return NSAlert()
                                                },
                                                recognizeImage: { _, _ in Self.fragments("source") }) { _, _ in Issue.record("Cancelled translation must not present or copy a result") })
        #expect(await XCTWaiter.fulfillment(of: [gate.started], timeout: 3) == .completed)
        #expect(model.isRecognizing)
        #expect(model.statusMessage == AppLocalization.text("正在翻译…"))
        let duplicate = model.recognize(.translate) { _, _ in
            Issue.record("Repeated clicks must share the in-flight translation")
        }
        #expect(duplicate == nil)
        switch action {
        case "close": fixture.controller.close()
        case "replace": model.image = try makeImage()
        default: model.cancelRecognition()
        }
        model.statusMessage = "new capture status"
        let completed = XCTestExpectation(description: "Cancelled translation finished promptly")
        let completion = Task {
            await task.value
            completed.fulfill()
        }
        #expect(await XCTWaiter.fulfillment(of: [completed, gate.cancelled], timeout: 3) == .completed)
        await gate.finish("late translation")
        await completion.value
        #expect(await XCTWaiter.fulfillment(of: [gate.returned], timeout: 3) == .completed)
        #expect(model.statusMessage == "new capture status")
        #expect(!model.isRecognizing)
    }

    @Test
    func replacingTheCaptureAfterAProviderWinsCannotPresentItsQueuedTranslation() async throws {
        let model = ScreenshotEditorModel(image: try makeImage())
        let output = AsyncStream<String>.makeStream()
        defer { output.continuation.finish() }
        let providerStarted = XCTestExpectation(description: "Translation provider started")
        let timeoutStarted = XCTestExpectation(description: "Translation timeout started")
        let providerWon = DispatchSemaphore(value: 0)
        let service = ClipboardTranslationService(providers: [{ _, _ in
            providerStarted.fulfill()
            for await text in output.stream { return text }
            throw CancellationError()
        }], waitForTimeout: {
            try await withTaskCancellationHandler {
                timeoutStarted.fulfill()
                try await Task.sleep(for: .seconds(60))
            } onCancel: {
                providerWon.signal()
            }
        })
        let task = try #require(model.recognize(.translate, translationService: service,
                                                recognizeImage: { _, _ in Self.fragments("old screenshot") }) { _, _ in Issue.record("A winning translation queued before capture replacement must be discarded") })
        #expect(await XCTWaiter.fulfillment(of: [providerStarted, timeoutStarted], timeout: 3) == .completed)
        output.continuation.yield("old translation")
        // Keep the main actor occupied until the service has returned its winning result.
        let winner = { providerWon.wait(timeout: .now() + 3) }()
        #expect(winner == .success)
        model.image = try makeImage()
        model.statusMessage = "replacement capture"
        await task.value
        #expect(model.statusMessage == "replacement capture")
        #expect(!model.isRecognizing)
    }

    @Test(arguments: [ScreenshotRecognitionMode.text, .translate], [false, true])
    func OCRAndTranslationShareTheResultDialogAndOnlyTranslationCopiesAutomatically(
        mode: ScreenshotRecognitionMode, copiesSuccessfully: Bool
    ) async throws {
        _ = NSApplication.shared
        let model = ScreenshotEditorModel(image: try makeImage())
        let alert = PresentationProbeAlert()
        alert.response = .alertSecondButtonReturn
        alert.window.isReleasedWhenClosed = false
        alert.window.alphaValue = 0
        defer { alert.window.close() }
        let text = "  Complete result\nSecond line  "
        var copies: [String] = []
        alert.onPresent = {
            #expect(copies == (mode == .translate ? [text] : []))
        }
        let task = try #require(model.recognize(mode,
                                                translationService: .init(providers: [{ _, _ in text }]),
                                                recognizeImage: { _, _ in Self.fragments(text) }) { result, operation in
                model.presentRecognitionResult(result, mode: mode, operation: operation, alert: alert) {
                    copies.append($0)
                    return copiesSuccessfully
                }
            })
        await task.value
        await withCheckedContinuation { continuation in
            RunLoop.main.perform(inModes: [.common]) { continuation.resume() }
        }
        #expect(alert.wasPresented)
        #expect(alert.messageText == AppLocalization.text(mode.title))
        #expect(alert.buttons.map(\.title) == [AppLocalization.text("复制"), AppLocalization.text("关闭")])
        #expect(alert.buttons[1].keyEquivalent == "\u{1b}")
        let scroll = try #require(alert.accessoryView as? NSScrollView)
        let textView = try #require(scroll.documentView as? NSTextView)
        #expect(scroll.frame.width == 480)
        #expect(!scroll.drawsBackground && !scroll.contentView.drawsBackground && !textView.drawsBackground)
        #expect(textView.string == text)
        #expect(textView.isSelectable && !textView.isEditable)
        #expect(scroll.hasVerticalScroller && !scroll.hasHorizontalScroller)
        if mode == .translate {
            #expect(model.statusMessage == (copiesSuccessfully
                    ? AppLocalization.text("%@，结果已复制", AppLocalization.text(mode.title))
                    : AppLocalization.text("无法写入剪贴板")))
        } else {
            #expect(copies.isEmpty)
            #expect(model.statusMessage == nil)
        }
    }

    @Test(arguments: ["short", "path", "unspaced", "tabs", "unicode", "multiline"],
          [NSAppearance.Name.aqua, .darkAqua])
    func recognitionResultsWrapWithinTheViewportAndInheritTheDialogAppearance(
        content: String, appearanceName: NSAppearance.Name
    ) async throws {
        _ = NSApplication.shared
        let model = ScreenshotEditorModel(image: try makeImage())
        let alert = PresentationProbeAlert()
        alert.response = .alertSecondButtonReturn
        alert.window.isReleasedWhenClosed = false
        alert.window.alphaValue = 0
        alert.window.appearance = NSAppearance(named: appearanceName)
        defer { alert.window.close() }
        let text = switch content {
        case "short": "  Short result\nSecond line  "
        case "path": "/Users/" + String(repeating: "directory/", count: 300) + "file.txt"
        case "unspaced": String(repeating: "abcdefghijkABCDEFGHIJK1234567890", count: 100)
        case "tabs": String(repeating: "\t", count: 30) + String(repeating: "lastColumn", count: 100)
        case "unicode": String(repeating: "截图翻译👨‍👩‍👧‍👦é مرحبا بالعالم ", count: 100)
        default: String(repeating: "Recognized line\n", count: 120)
        }
        let task = try #require(model.recognize(.text, recognizeImage: { _, _ in Self.fragments(text) }) {
            result, operation in
            model.presentRecognitionResult(result, mode: .text, operation: operation, alert: alert)
        })
        await task.value
        await withCheckedContinuation { continuation in
            RunLoop.main.perform(inModes: [.common]) { continuation.resume() }
        }
        alert.layout()
        let accessory = try #require(alert.accessoryView)
        let scroll = try #require((accessory as? NSScrollView)
            ?? accessory.subviews.compactMap { $0 as? NSScrollView }.first)
        let textView = try #require(scroll.documentView as? NSTextView)
        #expect(!(accessory is NSVisualEffectView), "The result must use the surrounding dialog background")
        #expect(accessory.appearance == nil && scroll.appearance == nil && textView.appearance == nil)
        #expect(!scroll.drawsBackground && !scroll.contentView.drawsBackground && !textView.drawsBackground)
        #expect(textView.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == appearanceName)
        textView.effectiveAppearance.performAsCurrentDrawingAppearance {
            #expect(textView.textColor?.usingColorSpace(.deviceRGB) == NSColor.labelColor.usingColorSpace(.deviceRGB))
        }
        for width: CGFloat in [480, 240] {
            scroll.frame.size.width = width
            scroll.tile()
            #expect(abs(scroll.contentSize.width - width) <= 0.5,
                    "Scrollbar chrome must preserve the width used to measure and wrap the result")
            try Self.expectCompleteRecognitionLayout(text, in: scroll)
        }
        if content == "short" {
            #expect(scroll.frame.height <= 160, "Short results must keep a compact dialog")
            #expect(textView.frame.height <= scroll.contentSize.height + 1)
        } else if content == "multiline" {
            #expect(textView.frame.height > scroll.contentSize.height, "Long results must scroll vertically")
            let screenHeight = alert.window.screen?.visibleFrame.height ?? 800
            #expect(alert.window.frame.height <= screenHeight, "The result and its buttons must fit on screen")
            textView.scrollRangeToVisible(NSRange(location: text.utf16.count - 1, length: 1))
            #expect(scroll.contentView.bounds.maxY >= textView.frame.height - 1,
                    "The final line must remain reachable by vertical scrolling")
        }
    }

    private static func expectCompleteRecognitionLayout(_ text: String, in scroll: NSScrollView) throws {
        let textView = try #require(scroll.documentView as? NSTextView)
        let container = try #require(textView.textContainer)
        let layoutManager = try #require(textView.layoutManager)
        layoutManager.ensureLayout(for: container)
        let glyphRange = layoutManager.glyphRange(for: container)
        #expect(glyphRange == NSRange(location: 0, length: layoutManager.numberOfGlyphs))
        #expect(layoutManager.characterRange(forGlyphRange: glyphRange, actualGlyphRange: nil)
            == NSRange(location: 0, length: text.utf16.count))
        #expect(textView.string == text && textView.accessibilityValue() == text)
        #expect(textView.isSelectable && !textView.isEditable)
        #expect(textView.frame.width <= scroll.contentSize.width + 0.5)
        var lineCount = 0
        layoutManager.enumerateLineFragments(forGlyphRange: glyphRange) { fragment, used, _, _, _ in
            lineCount += 1
            for rect in [fragment, used] {
                let bounds = rect.offsetBy(dx: textView.textContainerOrigin.x, dy: textView.textContainerOrigin.y)
                #expect(bounds.minX >= -0.5 && bounds.maxX <= scroll.contentSize.width + 0.5,
                        "Every laid-out line must fit within the visible result width")
                #expect(bounds.maxY <= textView.frame.height + 1, "Every line must have reachable document space")
            }
        }
        #expect(lineCount > 1)
        #expect(scroll.hasVerticalScroller && !scroll.hasHorizontalScroller)
    }

    @Test(arguments: [ScreenshotRecognitionMode.text, .translate])
    func theSharedCopyButtonWritesTheCompleteResult(mode: ScreenshotRecognitionMode) async throws {
        let model = ScreenshotEditorModel(image: try makeImage())
        let alert = PresentationProbeAlert()
        alert.window.isReleasedWhenClosed = false
        alert.window.alphaValue = 0
        defer { alert.window.close() }
        let text = "  Full result\nLine two + & <text>\n/Users/"
            + String(repeating: "directory/", count: 120) + String(repeating: "X", count: 600) + "  "
        var copies: [String] = []
        let task = try #require(model.recognize(mode,
                                                translationService: .init(providers: [{ text, _ in text }]),
                                                recognizeImage: { _, _ in Self.fragments(text) }) { text, operation in
                model.presentRecognitionResult(text, mode: mode, operation: operation, alert: alert) {
                    copies.append($0)
                    return true
                }
            })
        await task.value
        await withCheckedContinuation { continuation in
            RunLoop.main.perform(inModes: [.common]) { continuation.resume() }
        }
        #expect(copies == Array(repeating: text, count: mode == .translate ? 2 : 1))
        #expect(model.statusMessage == AppLocalization.text("%@，结果已复制", AppLocalization.text(mode.title)))
    }

    @Test(arguments: [ScreenshotRecognitionMode.text, .translate])
    func cancelledResultsCannotCopyOrOpenTheSharedDialog(mode: ScreenshotRecognitionMode) async throws {
        let model = ScreenshotEditorModel(image: try makeImage())
        let alert = PresentationProbeAlert()
        alert.window.isReleasedWhenClosed = false
        defer { alert.window.close() }
        let task = try #require(model.recognize(mode,
                                                translationService: .init(providers: [{ text, _ in text }]),
                                                recognizeImage: { _, _ in Self.fragments("stale result") }) { text, operation in
                model.presentRecognitionResult(text, mode: mode, operation: operation, alert: alert) { _ in
                    Issue.record("A result invalidated before presentation must not change the clipboard")
                    return true
                }
                model.cancelRecognition()
            })
        await task.value
        await withCheckedContinuation { continuation in
            RunLoop.main.perform(inModes: [.common]) { continuation.resume() }
        }
        #expect(!alert.wasPresented)
    }

    @Test
    func repeatedClicksShareOneRecognitionAndAllowRetryAfterCompletion() async throws {
        let model = ScreenshotEditorModel(image: try makeImage())
        let gate = RecognitionGate()
        var results: [String] = []
        let first = try #require(model.recognize(.text, recognizeImage: { _, _ in
            try await gate.recognize()
        }) { text, _ in results.append(text) })
        #expect(model.isRecognizing, "The toolbar must become busy before recognition starts")
        await gate.waitUntilStarted()
        let duplicate = model.recognize(.text, recognizeImage: { _, _ in
            Issue.record("A second click must not start another Vision request")
            return []
        }) { _, _ in Issue.record("A duplicate click must not present a second result") }
        #expect(duplicate == nil)
        await gate.finish(.success(Self.fragments("first")))
        await first.value
        #expect(results == ["first"])
        #expect(!model.isRecognizing)
        #expect(model.statusMessage == nil)

        let retry = try #require(model.recognize(.text, recognizeImage: { _, _ in
            Self.fragments("retry")
        }) { text, _ in results.append(text) })
        await retry.value
        #expect(results == ["first", "retry"])
        #expect(!model.isRecognizing)
    }

    @Test(arguments: [false, true])
    func closingFirstScreenshotDiscardsItsLateResultWhileSecondRecognizes(fails: Bool) async throws {
        let first = try Fixture(image: makeImage())
        let second = try Fixture(image: makeImage())
        defer { first.close(); second.close() }
        let firstGate = RecognitionGate()
        let secondGate = RecognitionGate()
        var results: [String] = []
        let oldTask = try #require(first.model.recognize(.text, recognizeImage: { _, operation in
            await firstGate.setOperation(operation)
            return try await firstGate.recognize()
        }) { text, _ in results.append(text) })
        await firstGate.waitUntilStarted()
        first.controller.close()
        #expect(!first.model.isRecognizing)
        let operation = try #require(await firstGate.operation)
        #expect(throws: CancellationError.self) { try operation.checkCancellation() }
        first.model.statusMessage = "closed screenshot"

        let newTask = try #require(second.model.recognize(.text, recognizeImage: { _, _ in
            try await secondGate.recognize()
        }) { text, _ in results.append(text) })
        await secondGate.waitUntilStarted()
        await firstGate.finish(fails ? .failure(RecognitionFailure()) : .success(Self.fragments("old")))
        await oldTask.value
        #expect(results.isEmpty, "A closed screenshot must not open a stale OCR alert")
        #expect(first.model.statusMessage == "closed screenshot")
        #expect(second.model.isRecognizing)
        #expect(second.model.statusMessage == AppLocalization.text("正在识别..."))

        await secondGate.finish(.success(Self.fragments("new")))
        await newTask.value
        #expect(results == ["new"])
        #expect(!second.model.isRecognizing)
    }

    @Test(arguments: [false, true])
    func replacingCaptureCancelsRecognitionWithoutFinishingTheNextRequest(fails: Bool) async throws {
        let model = ScreenshotEditorModel(image: try makeImage())
        let oldGate = RecognitionGate()
        let newGate = RecognitionGate()
        var results: [String] = []
        let oldTask = try #require(model.recognize(.text, recognizeImage: { _, operation in
            await oldGate.setOperation(operation)
            return try await oldGate.recognize()
        }) { text, _ in results.append(text) })
        await oldGate.waitUntilStarted()
        model.replaceCapture(with: try makeImage(), translatingAnnotationsBy: .zero)
        #expect(!model.isRecognizing)
        #expect(model.statusMessage == nil)
        let oldOperation = try #require(await oldGate.operation)
        #expect(throws: CancellationError.self) { try oldOperation.checkCancellation() }

        let newTask = try #require(model.recognize(.text, recognizeImage: { _, _ in
            try await newGate.recognize()
        }) { text, _ in results.append(text) })
        await newGate.waitUntilStarted()
        await oldGate.finish(fails ? .failure(RecognitionFailure()) : .success(Self.fragments("old")))
        await oldTask.value
        #expect(model.isRecognizing, "An old completion must not clear the new request's busy state")
        #expect(model.statusMessage == AppLocalization.text("正在识别..."))
        #expect(results.isEmpty)
        await newGate.finish(.success(Self.fragments("replacement")))
        await newTask.value
        #expect(results == ["replacement"])
        #expect(!model.isRecognizing)
    }

    @Test(arguments: ["empty", "failure", "invalid image"])
    func unsuccessfulRecognitionClearsBusyStateAndAllowsRetry(outcome: String) async throws {
        let model = ScreenshotEditorModel(image: outcome == "invalid image" ? NSImage() : try makeImage())
        let task = try #require(model.recognize(.text, recognizeImage: { _, _ in
            if outcome == "failure" { throw RecognitionFailure() }
            if outcome == "invalid image" { Issue.record("Invalid image must not reach Vision") }
            return []
        }) { _, _ in Issue.record("Empty or failed recognition must not present a result") })
        await task.value
        #expect(!model.isRecognizing)
        switch outcome {
        case "empty": #expect(model.statusMessage == AppLocalization.text("未识别到文字"))
        case "failure":
            #expect(model.statusMessage == AppLocalization.text("识别失败：%@", RecognitionFailure().localizedDescription))
        default: #expect(model.statusMessage == AppLocalization.text("无法读取图片"))
        }
        model.image = try makeImage()
        var result: String?
        let retry = try #require(model.recognize(.text, recognizeImage: { _, _ in
            Self.fragments("recovered")
        }) { text, _ in result = text })
        await retry.value
        #expect(result == "recovered")
        #expect(!model.isRecognizing)
    }

    @Test
    func destinationChosenAfterClosingCannotStartRecognitionOrWriteAFile() async throws {
        let fixture = try Fixture(image: makeImage())
        defer { fixture.close() }
        let gate = DestinationGate()
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let destination = directory.appendingPathComponent("late.xlsx")
        let task = try #require(fixture.model.recognize(.table, chooseTableDestination: {
            await gate.choose()
        }, recognizeImage: { _, _ in
            Issue.record("A save-panel callback from a closed screenshot must not start Vision")
            return Self.fragments("late")
        }) { _, _ in Issue.record("A table recognition must not present a text alert") })
        await gate.waitUntilStarted()
        #expect(fixture.model.isRecognizing)
        fixture.controller.close()
        fixture.model.statusMessage = "closed"
        await gate.finish(destination)
        await task.value
        #expect(!FileManager.default.fileExists(atPath: destination.path))
        #expect(fixture.model.statusMessage == "closed")
        #expect(!fixture.model.isRecognizing)
    }

    @Test
    func cancelledDestinationAllowsAnotherRecognition() async throws {
        let model = ScreenshotEditorModel(image: try makeImage())
        let task = try #require(model.recognize(.table, chooseTableDestination: { nil }, recognizeImage: { _, _ in
            Issue.record("Cancelling the save panel must not start Vision")
            return []
        }) { _, _ in Issue.record("Cancelling the save panel must not present a result") })
        await task.value
        #expect(!model.isRecognizing)
        #expect(model.statusMessage == AppLocalization.text("已取消保存表格"))
        let retry = try #require(model.recognize(.text, recognizeImage: { _, _ in Self.fragments("retry") }) { _, _ in })
        await retry.value
        #expect(!model.isRecognizing)
    }

    @Test(arguments: ["saved", "empty", "write failure"])
    func tableRecognitionSavesItsWorkbookOrReportsTheFailure(outcome: String) async throws {
        let model = ScreenshotEditorModel(image: try makeImage())
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let destination = directory.appendingPathComponent(outcome == "write failure" ? "missing/table.xlsx" : "table.xlsx")
        let task = try #require(model.recognize(.table, chooseTableDestination: { destination }, recognizeImage: { _, _ in
            outcome == "empty" ? [] : Self.fragments("table")
        }) { _, _ in Issue.record("Table recognition must use the workbook destination") })
        await task.value
        #expect(!model.isRecognizing)
        if outcome == "saved" {
            #expect(try Data(contentsOf: destination).starts(with: [0x50, 0x4B]))
            #expect(model.statusMessage == AppLocalization.text("表格已保存：%@", destination.lastPathComponent))
        } else {
            #expect(!FileManager.default.fileExists(atPath: destination.path))
            if outcome == "empty" {
                #expect(model.statusMessage == AppLocalization.text("未识别到文字"))
            } else {
                #expect(model.statusMessage?.hasPrefix(AppLocalization.text("识别失败：%@", "")) == true)
            }
        }
    }

    @Test
    func cancelledTableRecognitionPreservesExistingDestination() async throws {
        let model = ScreenshotEditorModel(image: try makeImage())
        let gate = RecognitionGate()
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let destination = directory.appendingPathComponent("table.xlsx")
        let original = Data("existing workbook".utf8)
        try original.write(to: destination)
        let task = try #require(model.recognize(.table, chooseTableDestination: { destination }, recognizeImage: { _, _ in
            try await gate.recognize()
        }) { _, _ in Issue.record("A table recognition must not present a text alert") })
        await gate.waitUntilStarted()
        model.cancelRecognition()
        await gate.finish(.success(Self.fragments("old table")))
        await task.value
        #expect(try Data(contentsOf: destination) == original)
        #expect(!model.isRecognizing)
    }

    @Test
    func cancellationDuringWorkbookPackagingPreservesExistingDestination() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let destination = directory.appendingPathComponent("table.xlsx")
        let original = Data("existing workbook".utf8)
        try original.write(to: destination)
        let table = ScreenshotRecognizedTable(rows: [["synthetic", "42"]], merges: [])
        #expect(throws: CancellationError.self) {
            try ScreenshotXLSXExporter.write(table, to: destination, checkCancellation: { throw CancellationError() })
        }
        #expect(try Data(contentsOf: destination) == original)
    }

    @Test(arguments: [false, true])
    func cancellationReachesVisionAndRejectsWorkThatHasNotStarted(duringConfiguration: Bool) throws {
        let request = CancellationProbeRequest()
        let operation = ScreenshotRecognitionOperation(request: request)
        if duringConfiguration {
            request.onSupportedLanguages = { [weak operation] in operation?.cancel() }
        } else {
            operation.cancel()
        }
        let image = try #require(makeImage().cgImage(forProposedRect: nil, context: nil, hints: nil))
        #expect(throws: CancellationError.self) { try operation.recognize(image) }
        #expect(request.wasCancelled)
        #expect(throws: CancellationError.self) { try operation.checkCancellation() }
    }

    @Test(arguments: [false, true])
    func invalidatedResultNeverCompletesItsAlert(duringPresentation: Bool) async throws {
        _ = NSApplication.shared
        let model = ScreenshotEditorModel(image: try makeImage())
        let alert = PresentationProbeAlert()
        alert.window.isReleasedWhenClosed = false
        alert.window.alphaValue = 0
        defer { alert.window.close() }
        let task = try #require(model.recognize(.text, recognizeImage: { _, _ in Self.fragments("old") }) { _, operation in
            if duringPresentation { alert.onPresent = { model.cancelRecognition() } }
            ScreenshotDialogPresentation.present(alert, shouldPresent: { model.isCurrentRecognition(operation) }) { _ in
                Issue.record("An invalidated result must not invoke its alert completion")
            }
            if !duringPresentation { model.cancelRecognition() }
        })
        await task.value
        await withCheckedContinuation { continuation in
            RunLoop.main.perform(inModes: [.common]) { continuation.resume() }
        }
        #expect(alert.wasPresented == duringPresentation)
    }

    @Test
    func warmUpRunsOffMainThreadOnlyOnce() async throws {
        let warmUp = ScreenshotRecognitionWarmUp()
        let gate = RecognitionGate()
        let mainQueueProgress = DispatchSemaphore(value: 0)
        warmUp.start {
            Self.checkBackgroundProgress(mainQueueProgress)
            #expect(Task.currentPriority == .utility)
            _ = try await gate.recognize()
        }
        await gate.waitUntilStarted()
        let first = try #require(warmUp.task)
        warmUp.start { Issue.record("Repeated startup callbacks must not compile another model") }
        let repeated = try #require(warmUp.task)
        await gate.finish(.success([]))
        try await first.value
        try await repeated.value
        warmUp.start { Issue.record("A completed warm-up must remain cached for this launch") }
        try await warmUp.task?.value
    }

    @Test(arguments: [false, true])
    func recognitionWaitsForWarmUpEvenWhenCancelled(cancel: Bool) async throws {
        let warmUp = ScreenshotRecognitionWarmUp()
        let gate = RecognitionGate()
        let ready = DispatchSemaphore(value: 0)
        warmUp.start {
            _ = try await gate.recognize()
            ready.signal()
        }
        await gate.waitUntilStarted()
        let request = CancellationProbeRequest()
        request.onSupportedLanguages = {
            #expect(!Thread.isMainThread, "The first real Vision request must stay off the UI thread")
            #expect(ready.wait(timeout: .now()) == .success,
                    "A user request must not race the model compilation")
        }
        let operation = ScreenshotRecognitionOperation(request: request)
        let image = try #require(makeImage().cgImage(forProposedRect: nil, context: nil, hints: nil))
        let started = AsyncStream<Void>.makeStream()
        let task = Task.detached {
            started.continuation.yield()
            started.continuation.finish()
            return try await warmUp.recognize(image, operation: operation)
        }
        for await _ in started.stream {}
        if cancel { operation.cancel() }
        await gate.finish(.success([]))
        do {
            let result = try await task.value
            #expect(!cancel)
            #expect(result.map(\.text).joined().contains("Synthetic"))
        } catch is CancellationError {
            #expect(cancel)
            #expect(request.wasCancelled)
        }
    }

    @Test(arguments: ["not started", "failed", "empty"])
    func recognitionStillWorksWithoutSuccessfulWarmUp(outcome: String) async throws {
        let warmUp = ScreenshotRecognitionWarmUp()
        if outcome != "not started" {
            warmUp.start {
                if outcome == "failed" { throw RecognitionFailure() }
            }
        }
        let model = ScreenshotEditorModel(image: try makeImage())
        var result: String?
        let task = try #require(model.recognize(.text, recognizeImage: { image, operation in
            try await warmUp.recognize(image, operation: operation)
        }) { text, _ in result = text })
        await task.value
        #expect(result?.contains("Synthetic") == true)
        #expect(model.statusMessage == nil)
        #expect(!model.isRecognizing)
    }

    @Test
    func recognizesSyntheticTextUsingTheProductionVisionWorker() async throws {
        let warmUp = ScreenshotRecognitionWarmUp()
        warmUp.start()
        try await warmUp.task?.value
        let model = ScreenshotEditorModel(image: try makeImage(text: "Screenshot OCR 2468"))
        for pass in 1...2 {
            let mainQueueProgress = DispatchSemaphore(value: 0)
            let start = ContinuousClock.now
            var result: String?
            let task = try #require(model.recognize(.text, recognizeImage: { image, operation in
                try await Self.recognizeSynthetic(image, operation: operation, warmUp: warmUp,
                                                  mainQueueProgress: mainQueueProgress)
            }) { text, _ in result = text })
            await task.value
            print("Synthetic OCR pass \(pass): \(start.duration(to: .now))")
            #expect(result?.contains("Screenshot OCR 2468") == true)
            #expect(!model.isRecognizing)
        }
    }

    @Test(arguments: [false, true])
    func CPURecoveryRecognizesSyntheticChineseAndHDRUsingVision(hdr: Bool) async throws {
        let text = "中文 OCR 2468"
        let source = try #require(makeImage(text: text).cgImage(forProposedRect: nil, context: nil, hints: nil))
        let image: CGImage
        if hdr {
            let context = try #require(CGContext(data: nil, width: source.width, height: source.height,
                                                 bitsPerComponent: 16, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.extendedLinearSRGB)!,
                                                 bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                                                     | CGBitmapInfo.floatComponents.rawValue | CGBitmapInfo.byteOrder16Little.rawValue))
            context.draw(source, in: CGRect(x: 0, y: 0, width: source.width, height: source.height))
            image = try #require(context.makeImage())
        } else { image = source }
        let fragments = try await Task.detached(priority: .userInitiated) {
            try ScreenshotRecognitionOperation().recognize(image) { image, request in
                if request.computeDevice(for: .main) == nil { throw Self.engineFailure }
                #expect(Self.usesCPU(request))
                try VNImageRequestHandler(cgImage: image, options: [:]).perform([request])
                return (request.results ?? []).compactMap { observation in
                    guard let candidate = observation.topCandidates(1).first else { return nil }
                    return ScreenshotRecognizedFragment(text: candidate.string, boundingBox: observation.boundingBox)
                }
            }
        }.value
        #expect(fragments.map(\.text).joined().contains(text), "CPU recovery must preserve Chinese text and numbers")
        #expect(fragments.allSatisfy { !$0.boundingBox.isEmpty })
    }

    private nonisolated static func fragments(_ text: String) -> [ScreenshotRecognizedFragment] {
        [ScreenshotRecognizedFragment(text: text, boundingBox: CGRect(x: 0.1, y: 0.5, width: 0.8, height: 0.2))]
    }

    private nonisolated static var engineFailure: NSError {
        NSError(domain: "CRImageReaderErrorDomain", code: -1, userInfo: [
            NSLocalizedDescriptionKey: "E5RT compute operation failed (Code: 13)",
        ])
    }

    private nonisolated static func usesCPU(_ request: VNRecognizeTextRequest) -> Bool {
        if case .cpu? = request.computeDevice(for: .main) { return true }
        return false
    }

    private static func accessibilityObjects(_ root: NSObject) -> [NSObject] {
        let children = root.responds(to: NSSelectorFromString("accessibilityChildren"))
            ? root.value(forKey: "accessibilityChildren") as? [NSObject] ?? [] : []
        return [root] + children.flatMap(accessibilityObjects)
    }

    private static func expectStatusBesideRecognition(_ message: String, in host: NSView) throws {
        let objects = accessibilityObjects(host)
        let status = try #require(objects.first { object in
            ["accessibilityTitle", "accessibilityLabel", "accessibilityValue"].contains { key in
                object.responds(to: NSSelectorFromString(key)) && object.value(forKey: key) as? String == message
            }
        } as? any NSAccessibilityElementProtocol)
        let recognition = try #require(objects.first {
            $0.responds(to: NSSelectorFromString("accessibilityHelp"))
                && $0.value(forKey: "accessibilityHelp") as? String == AppLocalization.text("识别图片中的文字或表格")
        } as? any NSAccessibilityElementProtocol)
        let window = try #require(host.window)
        let statusFrame = host.convert(window.convertFromScreen(status.accessibilityFrame()), from: nil)
        let recognitionFrame = host.convert(window.convertFromScreen(recognition.accessibilityFrame()), from: nil)
        let handle = try #require(dragHandle(in: host))
        let toolbar = try #require(handle.superview)
        let toolbarFrame = toolbar.convert(toolbar.bounds, to: host)
        #expect(toolbarFrame.insetBy(dx: -1, dy: -1).contains(statusFrame),
                "Recognition status must stay within the toolbar instead of the screen's notch area")
        #expect(abs(statusFrame.midY - recognitionFrame.midY) <= 2,
                "OCR and translation status must share the recognition button's row")
        let gap = min(abs(statusFrame.minX - recognitionFrame.maxX), abs(recognitionFrame.minX - statusFrame.maxX))
        #expect(gap <= ScreenshotToolbarLayout.spacing + 2 && !statusFrame.intersects(recognitionFrame),
                "The status must sit beside the recognition button in both text directions")
    }

    private static func dragHandle(in view: NSView) -> ScreenshotToolbarDragHandleView? {
        (view as? ScreenshotToolbarDragHandleView) ?? view.subviews.lazy.compactMap { dragHandle(in: $0) }.first
    }

    private nonisolated static func recognizeSynthetic(
        _ image: CGImage,
        operation: ScreenshotRecognitionOperation,
        warmUp: ScreenshotRecognitionWarmUp,
        mainQueueProgress: DispatchSemaphore
    ) async throws -> [ScreenshotRecognizedFragment] {
        checkBackgroundProgress(mainQueueProgress)
        let fragments = try await warmUp.recognize(image, operation: operation)
        checkBackgroundProgress(mainQueueProgress)
        return fragments
    }

    private nonisolated static func checkBackgroundProgress(_ mainQueueProgress: DispatchSemaphore) {
        #expect(!Thread.isMainThread, "Vision must run outside the UI thread")
        DispatchQueue.main.async { mainQueueProgress.signal() }
        #expect(mainQueueProgress.wait(timeout: .now() + 2) == .success,
                "The main queue must stay responsive while recognition is running")
    }

    private func makeImage(text: String = "Synthetic") throws -> NSImage {
        let size = CGSize(width: 720, height: 160)
        let context = try #require(CGContext(data: nil, width: Int(size.width), height: Int(size.height),
                                             bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                                             bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
        NSColor.white.setFill()
        NSRect(origin: .zero, size: size).fill()
        text.draw(at: CGPoint(x: 24, y: 60), withAttributes: [
            .font: NSFont.monospacedSystemFont(ofSize: 42, weight: .regular),
            .foregroundColor: NSColor.black,
        ])
        return NSImage(cgImage: try #require(context.makeImage()), size: size)
    }

    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("zisla-recognition-test-\(UUID())")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private struct RecognitionFailure: LocalizedError {
        var errorDescription: String? { "Synthetic recognition failure" }
    }

    private actor RecognitionGate {
        var operation: ScreenshotRecognitionOperation?
        private var continuation: CheckedContinuation<[ScreenshotRecognizedFragment], any Error>?
        private var startedWaiters: [CheckedContinuation<Void, Never>] = []

        func setOperation(_ operation: ScreenshotRecognitionOperation) { self.operation = operation }

        func recognize() async throws -> [ScreenshotRecognizedFragment] {
            try await withCheckedThrowingContinuation { continuation in
                self.continuation = continuation
                startedWaiters.forEach { $0.resume() }
                startedWaiters = []
            }
        }

        func waitUntilStarted() async {
            if continuation != nil { return }
            await withCheckedContinuation { startedWaiters.append($0) }
        }

        func finish(_ result: Result<[ScreenshotRecognizedFragment], any Error>) {
            continuation?.resume(with: result)
            continuation = nil
        }
    }

    private actor DestinationGate {
        private var continuation: CheckedContinuation<URL?, Never>?
        private var startedWaiters: [CheckedContinuation<Void, Never>] = []

        func choose() async -> URL? {
            await withCheckedContinuation { continuation in
                self.continuation = continuation
                startedWaiters.forEach { $0.resume() }
                startedWaiters = []
            }
        }

        func waitUntilStarted() async {
            if continuation != nil { return }
            await withCheckedContinuation { startedWaiters.append($0) }
        }

        func finish(_ url: URL?) { continuation?.resume(returning: url); continuation = nil }
    }

    private final class CancellationProbeRequest: VNRecognizeTextRequest, @unchecked Sendable {
        var wasCancelled = false
        var supportsCPU = true
        var onSupportedLanguages: (() -> Void)?
        var onSupportedDevices: (() -> Void)?
        var supportedDevicesError: Error?
        override func cancel() { wasCancelled = true; super.cancel() }
        override func supportedRecognitionLanguages() throws -> [String] {
            onSupportedLanguages?()
            return ["en-US"]
        }
        override func __supportedComputeStageDevices() throws -> [VNComputeStage: [any MLComputeDeviceProtocol]] {
            onSupportedDevices?()
            if let supportedDevicesError { throw supportedDevicesError }
            return [.main: supportsCPU ? MLComputeDevice.allComputeDevices.compactMap {
                if case let .cpu(device) = $0 { return device }
                return nil
            } : []]
        }
    }

    private final class PresentationProbeAlert: NSAlert {
        var wasPresented = false
        var onPresent: (() -> Void)?
        var response = NSApplication.ModalResponse.alertFirstButtonReturn
        override func runModal() -> NSApplication.ModalResponse {
            wasPresented = true
            onPresent?()
            return response
        }
    }

    private actor TranslationGate {
        nonisolated let started = XCTestExpectation(description: "Translation provider started")
        nonisolated let cancelled = XCTestExpectation(description: "Translation provider cancelled")
        nonisolated let returned = XCTestExpectation(description: "Late translation returned")
        private var continuation: CheckedContinuation<String, Never>?

        func translate() async -> String {
            defer { returned.fulfill() }
            return await withTaskCancellationHandler {
                await withCheckedContinuation {
                    continuation = $0
                    started.fulfill()
                }
            } onCancel: {
                cancelled.fulfill()
            }
        }

        func finish(_ text: String) {
            continuation?.resume(returning: text)
            continuation = nil
        }
    }

    @MainActor
    private final class RecognitionMenuSelection: NSObject {
        let title: String
        let model: ScreenshotEditorModel
        var selected = false
        var startedRecognition = false
        private var menu: NSMenu?

        init(title: String, model: ScreenshotEditorModel) {
            self.title = title
            self.model = model
        }

        @objc func began(_ notification: Notification) {
            guard let menu = notification.object as? NSMenu else { return }
            let index = menu.items.firstIndex(where: { $0.title == title })
            self.menu = menu
            RunLoop.main.perform(inModes: [.eventTracking]) {
                MainActor.assumeIsolated {
                    self.menu?.cancelTrackingWithoutAnimation()
                    if let index { self.menu?.performActionForItem(at: index) }
                    self.startedRecognition = self.model.isRecognizing
                    self.model.cancelRecognition()
                    self.selected = true
                    self.menu = nil
                }
            }
        }
    }

    @MainActor
    private final class Fixture {
        let defaults: UserDefaults
        let defaultsName = "zisla-recognition-settings-\(UUID())"
        let settings: FeatureSettingsStore
        let controller: ScreenshotEditorWindowController
        let model: ScreenshotEditorModel

        init(image: NSImage) throws {
            defaults = try #require(UserDefaults(suiteName: defaultsName))
            settings = FeatureSettingsStore(defaults: defaults)
            let pixels = try #require(image.cgImage(forProposedRect: nil, context: nil, hints: nil))
            controller = ScreenshotEditorWindowController(image: image, screenImage: image, screenCGImage: pixels,
                                                          screen: nil, captureRect: CGRect(origin: .zero, size: image.size), capturedApplication: nil,
                                                          settingsStore: settings, onStash: { _, _ in }, writeImageToPasteboard: { _ in false },
                                                          onClose: {})
            controller.window?.alphaValue = 0
            let hosting = try #require(controller.window?.contentView as? NSHostingView<AppLanguageEnvironment<ScreenshotEditorView>>)
            model = hosting.rootView.content.model
        }

        func close() {
            controller.close()
            settings.flushPendingChanges()
            defaults.removePersistentDomain(forName: defaultsName)
        }
    }
}
