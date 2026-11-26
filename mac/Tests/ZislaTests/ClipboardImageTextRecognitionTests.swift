import AppKit
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers
import ZislaCore
@testable import Zisla
@testable import ZislaKit

@Suite(.serialized, .timeLimit(.minutes(1)))
struct ClipboardImageTextRecognitionTests {
    @Test(arguments: ["png", "tiff"])
    func supportedImageRecognitionRunsOffMainThreadAndPreservesReadingOrder(format: String) async throws {
        let data = try imageData(format: format)
        let original = data
        let text = try await ClipboardImageTextRecognition.recognize(data) { image, operation in
            Self.checkBackgroundThread()
            #expect(image.width == 32 && image.height == 24)
            try operation.checkCancellation()
            return [
                ScreenshotRecognizedFragment(text: "second 中文", boundingBox: CGRect(x: 0.1, y: 0.1, width: 0.5, height: 0.1)),
                ScreenshotRecognizedFragment(text: "first", boundingBox: CGRect(x: 0.1, y: 0.8, width: 0.5, height: 0.1)),
            ]
        }
        #expect(text == "first\nsecond 中文")
        #expect(data == original)
    }

    @Test(arguments: ["empty", "invalid", "truncated", "oversized-bytes", "oversized-pixels"])
    func unsafeImageInputNeverReachesRecognition(input: String) async throws {
        let data: Data
        switch input {
        case "empty": data = Data()
        case "invalid": data = Data("not an image".utf8)
        case "truncated": data = try imageData(format: "png").dropLast(16)
        case "oversized-bytes": data = Data(repeating: 0, count: 10 * 1_024 * 1_024 + 1)
        default:
            var forged = try imageData(format: "png")
            forged.replaceSubrange(16..<24, with: [0, 0, 0xFF, 0xFF, 0, 0, 0xFF, 0xFF])
            data = forged
        }
        do {
            _ = try await ClipboardImageTextRecognition.recognize(data) { _, _ in
                Issue.record("Invalid images must not allocate a decoded image or enter Vision")
                return []
            }
            Issue.record("Unsafe input must be rejected: \(input)")
        } catch let error as CocoaError {
            if input == "oversized-bytes" {
                #expect(error.code == .fileReadTooLarge)
            } else {
                #expect(error.code == .fileReadCorruptFile || error.code == .fileReadTooLarge)
            }
        }
    }

    @Test
    func validPNGDataSlicesAreValidatedAndRecognizedWithoutAbsoluteIndexTraps() async throws {
        let bytes = try imageData(format: "png")
        let buffer = Data(repeating: 0xEE, count: 64) + bytes
        let slice = buffer.dropFirst(64)
        #expect(slice.startIndex == 64)
        #expect(try FileShelfStore.imageFormat(for: slice, requiresExactPixelBytes: true) == "png")
        let text = try await ClipboardImageTextRecognition.recognize(slice) { image, _ in
            #expect(image.width == 32 && image.height == 24)
            return [ScreenshotRecognizedFragment(text: "sliced input", boundingBox: .zero)]
        }
        #expect(text == "sliced input")
    }

    @Test
    func cancellationDuringRecognitionCancelsTheOperationAndDiscardsLateFragments() async throws {
        let gate = ImageTextOperationGate()
        let data = try imageData(format: "png")
        let task = Task {
            try await ClipboardImageTextRecognition.recognize(data) { _, operation in
                try await gate.recognize(operation)
            }
        }
        await gate.waitUntilStarted()
        task.cancel()
        await gate.finish()
        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(await gate.operationWasCancelled)
    }

    @Test
    func whitespaceAndEngineFailuresKeepTheirDistinctOutcomes() async throws {
        let data = try imageData(format: "png")
        #expect(try await ClipboardImageTextRecognition.recognize(data) { _, _ in [] } == "")
        await #expect(throws: CocoaError.self) {
            try await ClipboardImageTextRecognition.recognize(data) { _, _ in throw CocoaError(.featureUnsupported) }
        }
    }

    private static func checkBackgroundThread() {
        #expect(!Thread.isMainThread)
    }

    private func imageData(format: String) throws -> Data {
        let context = try #require(CGContext(data: nil, width: 32, height: 24, bitsPerComponent: 8, bytesPerRow: 0,
                                             space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 32, height: 24))
        let image = try #require(context.makeImage())
        let output = NSMutableData()
        let type = format == "tiff" ? UTType.tiff.identifier : UTType.png.identifier
        let destination = try #require(CGImageDestinationCreateWithData(output, type as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, nil)
        try #require(CGImageDestinationFinalize(destination))
        return output as Data
    }
}

private actor ImageTextOperationGate {
    private var operation: ScreenshotRecognitionOperation?
    private var continuation: CheckedContinuation<[ScreenshotRecognizedFragment], any Error>?
    private var started: CheckedContinuation<Void, Never>?
    private(set) var operationWasCancelled = false

    func recognize(_ operation: ScreenshotRecognitionOperation) async throws -> [ScreenshotRecognizedFragment] {
        self.operation = operation
        started?.resume()
        started = nil
        return try await withCheckedThrowingContinuation { continuation = $0 }
    }

    func waitUntilStarted() async {
        if operation != nil { return }
        await withCheckedContinuation { started = $0 }
    }

    func finish() {
        do {
            try operation?.checkCancellation()
        } catch is CancellationError {
            operationWasCancelled = true
        } catch {
            Issue.record("Unexpected cancellation error: \(error)")
        }
        continuation?.resume(returning: [ScreenshotRecognizedFragment(text: "late", boundingBox: .zero)])
        continuation = nil
    }
}
