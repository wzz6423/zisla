import AppKit
import SwiftUI
import Testing
import Vision
import ZislaCore
@testable import ZislaKit
@testable import Zisla

@MainActor
@Suite(.serialized)
struct ScreenshotRecognitionTests {
    @Test(arguments: [ScreenshotRecognitionMode.text, .table])
    func cancellationBeforeQueuedTaskStartsDoesNotOpenDialogsOrChangeStatus(mode: ScreenshotRecognitionMode) async throws {
        let model = ScreenshotEditorModel(image: try makeImage())
        let task = try #require(model.recognize(mode, chooseTableDestination: {
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
    func recognizesSyntheticTextUsingTheProductionVisionWorker() async throws {
        let model = ScreenshotEditorModel(image: try makeImage(text: "Screenshot OCR 2468"))
        for pass in 1...2 {
            let mainQueueProgress = DispatchSemaphore(value: 0)
            let start = ContinuousClock.now
            var result: String?
            let task = try #require(model.recognize(.text, recognizeImage: { image, operation in
                try Self.recognizeSynthetic(image, operation: operation, mainQueueProgress: mainQueueProgress)
            }) { text, _ in result = text })
            await task.value
            print("Synthetic OCR pass \(pass): \(start.duration(to: .now))")
            #expect(result?.contains("Screenshot OCR 2468") == true)
            #expect(!model.isRecognizing)
        }
    }

    private nonisolated static func fragments(_ text: String) -> [ScreenshotRecognizedFragment] {
        [ScreenshotRecognizedFragment(text: text, boundingBox: CGRect(x: 0.1, y: 0.5, width: 0.8, height: 0.2))]
    }

    private nonisolated static func recognizeSynthetic(
        _ image: CGImage,
        operation: ScreenshotRecognitionOperation,
        mainQueueProgress: DispatchSemaphore
    ) throws -> [ScreenshotRecognizedFragment] {
        #expect(!Thread.isMainThread, "Vision must run outside the UI thread")
        DispatchQueue.main.async { mainQueueProgress.signal() }
        let fragments = try operation.recognize(image)
        #expect(mainQueueProgress.wait(timeout: .now() + 2) == .success,
                "The main queue must stay responsive while recognition is running")
        return fragments
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
        var onSupportedLanguages: (() -> Void)?
        override func cancel() { wasCancelled = true; super.cancel() }
        override func supportedRecognitionLanguages() throws -> [String] {
            onSupportedLanguages?()
            return ["en-US"]
        }
    }

    private final class PresentationProbeAlert: NSAlert {
        var wasPresented = false
        var onPresent: (() -> Void)?
        override func runModal() -> NSApplication.ModalResponse {
            wasPresented = true
            onPresent?()
            return .alertFirstButtonReturn
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
