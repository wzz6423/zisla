import AppKit
import ScreenCaptureKit
import Testing
import ZislaCore
import ZislaKit
@testable import Zisla

@MainActor
struct ContextNoteScreenshotCaptureTests {
    private let location = ContextNoteLocation.window(bundleIdentifier: "test.editor", applicationName: "Editor", title: "Document")
    private let frame = CGRect(x: -1800, y: 200, width: 800, height: 600)

    private func entry(id: CGWindowID = 11, owner: pid_t = 42, frame: CGRect? = nil, layer: Int = 0) -> [String: Any] {
        [kCGWindowNumber as String: NSNumber(value: id), kCGWindowOwnerPID as String: NSNumber(value: owner),
         kCGWindowBounds as String: (frame ?? self.frame).dictionaryRepresentation, kCGWindowLayer as String: NSNumber(value: layer)]
    }

    @Test
    func selectsTheExactCapturedWindowEvenWhenAnotherApplicationIsInFront() throws {
        let windows = [entry(id: 90, owner: 91), entry(id: 12, frame: frame.offsetBy(dx: 100, dy: 0)), entry()]
        let source = try ContextNoteScreenshotCapture.source(for: location,
            window: .init(processIdentifier: 42, frame: frame, title: "Document"), hasPermission: { true }, windowInfo: { windows })
        #expect(source == .window(11, processIdentifier: 42))
        let browser = ContextNoteLocation.webPage(url: URL(string: "https://example.invalid/page")!, title: "", applicationName: "Browser")
        #expect(try ContextNoteScreenshotCapture.source(for: browser,
            window: .init(processIdentifier: 42, frame: frame, title: ""), hasPermission: { true }, windowInfo: { windows }) == source)
    }

    @Test
    func overlappingWindowsOfTheSameApplicationUseTheCapturedWindowTitle() throws {
        var first = entry(id: 12)
        first[kCGWindowName as String] = "Other document"
        var second = entry()
        second[kCGWindowName as String] = "Document"
        let source = try ContextNoteScreenshotCapture.source(for: location,
            window: .init(processIdentifier: 42, frame: frame, title: "Document"),
            hasPermission: { true }, windowInfo: { [first, second] })
        #expect(source == .window(11, processIdentifier: 42))
    }

    @Test(arguments: ["missing owner", "foreign owner", "missing bounds", "invalid bounds", "wrong frame", "missing layer", "overlay", "missing number", "null id", "duplicate", "unavailable", "missing window", "missing frame"])
    func unavailableOrAmbiguousWindowsCannotFallBackToAnotherWindow(failure: String) {
        var info: [[String: Any]]? = [entry()]
        var window: ContextNoteScreenshotCapture.WindowReference? = .init(processIdentifier: 42, frame: frame, title: "Document")
        switch failure {
        case "missing owner": info?[0].removeValue(forKey: kCGWindowOwnerPID as String)
        case "foreign owner": info = [entry(owner: 91)]
        case "missing bounds": info?[0].removeValue(forKey: kCGWindowBounds as String)
        case "invalid bounds": info?[0][kCGWindowBounds as String] = NSDictionary()
        case "wrong frame": info = [entry(frame: frame.offsetBy(dx: 10, dy: 0))]
        case "missing layer": info?[0].removeValue(forKey: kCGWindowLayer as String)
        case "overlay": info = [entry(layer: 10)]
        case "missing number": info?[0].removeValue(forKey: kCGWindowNumber as String)
        case "null id": info = [entry(id: kCGNullWindowID)]
        case "duplicate":
            var duplicate = entry()
            duplicate[kCGWindowName as String] = "Document"
            var other = entry(id: 12)
            other[kCGWindowName as String] = "Document"
            info = [duplicate, other]
        case "unavailable": info = nil
        case "missing window": window = nil
        default: window = .init(processIdentifier: 42, frame: nil, title: "Document")
        }
        #expect(throws: ScreenshotCaptureError.windowUnavailable) {
            try ContextNoteScreenshotCapture.source(for: location, window: window,
                hasPermission: { true }, windowInfo: { info })
        }
    }

    @Test
    func desktopUsesItsPersistentDisplayIdentityWithoutReadingApplicationWindows() throws {
        let desktop = ContextNoteLocation.desktop(displayID: "external-display", displayName: "External")
        let source = try ContextNoteScreenshotCapture.source(for: desktop, window: nil, hasPermission: { true },
            windowInfo: { Issue.record("Desktop capture must not select an application window"); return nil },
            displayIdentifier: { #expect($0 == "external-display"); return 7 })
        #expect(source == .display(7))
        #expect(throws: ScreenshotCaptureError.screenUnavailable) {
            try ContextNoteScreenshotCapture.source(for: desktop, window: nil,
                hasPermission: { true }, displayIdentifier: { _ in nil })
        }
    }

    @Test
    func deniedPermissionDoesNotReadWindowOrDisplayMetadata() {
        #expect(throws: ScreenshotCaptureError.permissionRequired) {
            try ContextNoteScreenshotCapture.source(for: location, window: nil, hasPermission: { false },
                windowInfo: { Issue.record("No window metadata may be read without permission"); return nil },
                displayIdentifier: { _ in Issue.record("No display metadata may be read without permission"); return nil })
        }
    }

    @Test(arguments: [CGFloat(1), 2])
    func windowCaptureKeepsNativePixelSizeWithoutCursorShadowsOrDisplayClipping(scale: CGFloat) {
        let configuration = ContextNoteScreenshotCapture.configuration(for: frame, scale: scale)
        #expect(configuration.width == Int(800 * scale))
        #expect(configuration.height == Int(600 * scale))
        #expect(configuration.captureResolution == .best)
        #expect(!configuration.showsCursor)
        #expect(configuration.ignoreShadowsSingleWindow)
        #expect(configuration.ignoreGlobalClipSingleWindow)
    }

    @Test(arguments: [ContextNoteScreenshotSource.window(11, processIdentifier: 42), .display(7)])
    func captureWritesTheSelectedSourcesOriginalPixelsToPNG(source: ContextNoteScreenshotSource) async throws {
        let fixture = try ContextNoteScreenshotTestImage.make()
        let png = try await ContextNoteScreenshotCapture.capture(source, hasPermission: { true },
            windowCapture: { id, pid in
                #expect(source == .window(id, processIdentifier: pid))
                return fixture.image
            }, displayCapture: { id in
                #expect(source == .display(id))
                return fixture.image
            })
        let dimensions = try FileShelfStore.screenshotDimensions(png)
        #expect(dimensions.width == 80 && dimensions.height == 40)
        let bitmap = try #require(NSBitmapImageRep(data: png))
        let color = try #require(bitmap.colorAt(x: 40, y: 20))
        #expect(color.redComponent > 0.9 && color.greenComponent < 0.1)
    }

    @Test
    func permissionRevokedAfterPreparationPreventsCapturingPixels() async {
        await #expect(throws: ScreenshotCaptureError.permissionRequired) {
            try await ContextNoteScreenshotCapture.capture(.window(11, processIdentifier: 42), hasPermission: { false },
                windowCapture: { _, _ in Issue.record("Capture must not run after permission is revoked"); throw CocoaError(.fileReadNoPermission) },
                displayCapture: { _ in Issue.record("Capture must not run after permission is revoked"); throw CocoaError(.fileReadNoPermission) })
        }
    }

    @Test
    func imageEncodingFailureIsReported() async throws {
        let fixture = try ContextNoteScreenshotTestImage.make()
        await #expect(throws: CocoaError(.fileWriteUnknown)) {
            try await ContextNoteScreenshotCapture.capture(.window(11, processIdentifier: 42), hasPermission: { true },
                windowCapture: { _, _ in fixture.image }, encode: { _ in nil })
        }
    }

    @Test
    func cancellationBeforeSystemCaptureDoesNotReadPixels() async {
        let task = Task {
            try await ContextNoteScreenshotCapture.capture(.window(11, processIdentifier: 42), hasPermission: { true },
                windowCapture: { _, _ in
                    Issue.record("Cancelled capture must not start reading pixels")
                    throw CocoaError(.userCancelled)
                })
        }
        task.cancel()
        await #expect(throws: CancellationError.self) { try await task.value }
    }

    @Test
    func cancellationAfterSystemCaptureDoesNotEncodeOrReturnItsImage() async throws {
        let fixture = try ContextNoteScreenshotTestImage.make()
        let gate = ContextNoteScreenshotGate()
        let task = Task {
            try await ContextNoteScreenshotCapture.capture(.window(11, processIdentifier: 42), hasPermission: { true },
                windowCapture: { _, _ in _ = try await gate.capture(); return fixture.image },
                encode: { _ in Issue.record("Cancelled capture must not encode pixels"); return Data() })
        }
        await gate.waitUntilStarted()
        task.cancel()
        gate.finish(.success(Data()))
        await #expect(throws: CancellationError.self) { try await task.value }
    }
}

@MainActor
struct ContextNoteScreenshotDraftTests {
    private let location = ContextNoteLocation.desktop(displayID: "test", displayName: "Test")

    @Test
    func successfulCaptureFinishesLoadingAndKeepsTheOriginalPNG() async throws {
        let png = try ContextNoteScreenshotTestImage.make().png
        let draft = ContextNoteDraft(location: location)
        draft.text = "Keep this note"
        draft.captureScreenshot(from: .success(.display(7))) { _ in png }
        #expect(draft.isCapturingScreenshot)
        await draft.screenshotTask?.value
        #expect(!draft.isCapturingScreenshot)
        #expect(draft.screenshot?.png == png)
        #expect(draft.screenshotError == nil)
        #expect(draft.text == "Keep this note")
        draft.cancelScreenshotCapture()
        #expect(draft.screenshot?.png == png)
        #expect(draft.screenshotError == nil)
    }

    @Test
    func preparationFailureKeepsTextAndShowsTheLocalizedPermissionReason() {
        let draft = ContextNoteDraft(location: location)
        draft.text = "Keep this note"
        draft.captureScreenshot(from: .failure(ScreenshotCaptureError.permissionRequired)) { _ in
            Issue.record("A failed preparation must not capture pixels")
            return Data()
        }
        #expect(!draft.isCapturingScreenshot)
        #expect(draft.screenshot == nil)
        #expect(draft.screenshotError == AppLocalization.text("截图失败：%@",
            AppLocalization.text("请在系统设置的“隐私与安全性 > 屏幕录制”中允许 zisla")))
        #expect(draft.text == "Keep this note")
    }

    @Test(arguments: ["closed window", "invalid PNG"])
    func captureFailurePreservesTheEditableText(failure: String) async {
        let draft = ContextNoteDraft(location: location)
        draft.text = "Keep this note"
        draft.captureScreenshot(from: .success(.display(7))) { _ in
            if failure == "closed window" { throw ScreenshotCaptureError.windowUnavailable }
            return Data("invalid PNG".utf8)
        }
        await draft.screenshotTask?.value
        #expect(!draft.isCapturingScreenshot)
        #expect(draft.screenshot == nil)
        #expect(draft.screenshotError != nil)
        #expect(draft.text == "Keep this note")
    }

    @Test
    func aDecodableJPEGIsRejectedAsAPNGAttachment() throws {
        let png = try ContextNoteScreenshotTestImage.make().png
        let bitmap = try #require(NSBitmapImageRep(data: png))
        let jpeg = try #require(bitmap.representation(using: .jpeg, properties: [:]))
        #expect(NSImage(data: jpeg) != nil)
        #expect(throws: CocoaError(.fileReadCorruptFile)) { try ContextNoteScreenshot(png: jpeg) }
    }

    @Test
    func anIncompletePNGAcceptedByAppKitCannotBecomeAnAttachment() throws {
        let png = try #require(Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAIAAAACCAMAAABFaP0WAAAADklEQVR4nGP4/5/h/38AC/oD/eAlihAAAAAASUVORK5CYII="))
        #expect(NSImage(data: png) != nil)
        #expect(throws: CocoaError(.fileReadCorruptFile)) { try FileShelfStore.screenshotDimensions(png) }
        #expect(throws: CocoaError(.fileReadCorruptFile)) { try ContextNoteScreenshot(png: png) }
    }

    @Test(arguments: AppLanguage.allCases, [ScreenshotCaptureError.permissionRequired, .windowUnavailable, .screenUnavailable])
    func screenshotFailuresUseTheSelectedLanguage(language: AppLanguage, failure: ScreenshotCaptureError) throws {
        let defaults = UserDefaults.standard
        let original = defaults.volatileDomain(forName: UserDefaults.argumentDomain)
        var arguments = original
        arguments[AppLocalization.defaultsKey] = language.rawValue
        defaults.setVolatileDomain(arguments, forName: UserDefaults.argumentDomain)
        defer { defaults.setVolatileDomain(original, forName: UserDefaults.argumentDomain) }
        let draft = ContextNoteDraft(location: location)
        draft.captureScreenshot(from: .failure(failure)) { _ in
            Issue.record("A preparation failure must not start a capture")
            return Data()
        }
        let reason = AppLocalization.string(try #require(failure.errorDescription), language: language)
        #expect(draft.screenshotError == AppLocalization.format("截图失败：%@", locale: language.locale, [reason]))
    }

    @Test
    func cancelledDraftCannotAcceptALateImageOrLoseItsCancellationFeedback() async throws {
        let png = try ContextNoteScreenshotTestImage.make().png
        let gate = ContextNoteScreenshotGate()
        let draft = ContextNoteDraft(location: location)
        draft.captureScreenshot(from: .success(.display(7))) { _ in try await gate.capture() }
        let task = try #require(draft.screenshotTask)
        await gate.waitUntilStarted()
        draft.cancelScreenshotCapture()
        let error = draft.screenshotError
        gate.finish(.success(png))
        await task.value
        #expect(!draft.isCapturingScreenshot)
        #expect(draft.screenshot == nil)
        #expect(error != nil && draft.screenshotError == error)
    }

    @Test
    func cancellationBeforeTheTaskStartsDoesNotInvokeCapture() async throws {
        let draft = ContextNoteDraft(location: location)
        draft.captureScreenshot(from: .success(.display(7))) { _ in
            Issue.record("A discarded draft must not start a capture")
            return Data()
        }
        let task = try #require(draft.screenshotTask)
        draft.cancelScreenshotCapture()
        await task.value
        #expect(draft.screenshot == nil)
        #expect(!draft.isCapturingScreenshot)
    }

    @Test
    func releasingADraftCancelsItsTaskWithoutRetainingTheDraft() async throws {
        let gate = ContextNoteScreenshotGate()
        var wasCancelled = false
        var draft: ContextNoteDraft? = ContextNoteDraft(location: location)
        weak var releasedDraft = draft
        draft?.captureScreenshot(from: .success(.display(7))) { _ in
            let png = try await gate.capture()
            wasCancelled = Task.isCancelled
            return png
        }
        let task = try #require(draft?.screenshotTask)
        await gate.waitUntilStarted()
        draft = nil
        #expect(releasedDraft == nil)
        gate.finish(.success(try ContextNoteScreenshotTestImage.make().png))
        await task.value
        #expect(wasCancelled)
    }
}

@MainActor
enum ContextNoteScreenshotTestImage {
    static func make() throws -> (png: Data, image: CGImage) {
        let colorSpace = try #require(CGColorSpace(name: CGColorSpace.sRGB))
        let context = try #require(CGContext(data: nil, width: 80, height: 40, bitsPerComponent: 8,
            bytesPerRow: 320, space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(red: 1, green: 0, blue: 0, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: 80, height: 40))
        let image = try #require(context.makeImage())
        let png = try #require(NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]))
        return (png, image)
    }
}

@MainActor
final class ContextNoteScreenshotGate {
    private var continuation: CheckedContinuation<Data, Error>?
    private var started: CheckedContinuation<Void, Never>?
    private var hasStarted = false

    func capture() async throws -> Data {
        hasStarted = true
        started?.resume()
        started = nil
        return try await withCheckedThrowingContinuation { continuation = $0 }
    }

    func waitUntilStarted() async {
        if hasStarted { return }
        await withCheckedContinuation { started = $0 }
    }

    func finish(_ result: Result<Data, Error>) {
        continuation?.resume(with: result)
        continuation = nil
    }
}
