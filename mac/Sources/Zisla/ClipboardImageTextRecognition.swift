import CoreGraphics
import Foundation
import ImageIO
import ZislaCore
import ZislaKit

enum ClipboardImageTextRecognition {
    static func recognize(
        _ data: Data,
        recognizeImage: @escaping @Sendable (CGImage, ScreenshotRecognitionOperation) async throws -> [ScreenshotRecognizedFragment] = {
            try await ScreenshotRecognitionWarmUp.shared.recognize($0, operation: $1)
        }
    ) async throws -> String {
        let operation = ScreenshotRecognitionOperation()
        let worker = Task.detached(priority: .utility) {
            try Task.checkCancellation()
            _ = try FileShelfStore.imageFormat(for: data, maximumBytes: 10 * 1_024 * 1_024)
            guard let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
                  let image = CGImageSourceCreateImageAtIndex(source, 0, [kCGImageSourceShouldCacheImmediately: true] as CFDictionary) else {
                throw CocoaError(.fileReadCorruptFile)
            }
            try operation.checkCancellation()
            let fragments = try await recognizeImage(image, operation)
            try operation.checkCancellation()
            return ScreenshotRecognitionFormatter.plainText(from: fragments)
        }
        return try await withTaskCancellationHandler {
            try await worker.value
        } onCancel: {
            operation.cancel()
            worker.cancel()
        }
    }
}
