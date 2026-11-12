import CoreGraphics
import Foundation
import ZislaCore
import ZislaKit

enum ImageToolsExtractionError: LocalizedError {
    case noRegion
    case failed(String)

    var errorDescription: String? {
        switch self {
        case .noRegion: AppLocalization.text("未找到可提取区域")
        case let .failed(message): AppLocalization.text("提取失败：%@", message)
        }
    }
}

extension ImageToolsModel {
    @discardableResult
    func startExtraction(
        service: ImageProcessingService,
        mode: ScreenshotExtractionMode,
        extractImage: @escaping @Sendable (CGImage, ScreenshotExtractionOperation) async throws -> CGImage? = {
            try $1.extract($0)
        }
    ) -> Task<Void, Never>? {
        start(service: service, options: .init(formats: [.png]), rasterTransform: { source, _ in
            let operation = ScreenshotExtractionOperation(mode: mode,
                imageSize: CGSize(width: source.width, height: source.height))
            let work = Task.detached(priority: .userInitiated) {
                do {
                    let result = try await extractImage(source, operation)
                    guard let result else { throw ImageToolsExtractionError.noRegion }
                    guard result.width == source.width, result.height == source.height else {
                        throw ScreenshotExtractionError.maskSizeMismatch
                    }
                    guard try ScreenshotImageExtraction.containsVisiblePixels(result) else {
                        throw ImageToolsExtractionError.noRegion
                    }
                    return result
                } catch {
                    if error is CancellationError || error is ImageToolsExtractionError { throw error }
                    throw ImageToolsExtractionError.failed(error.localizedDescription)
                }
            }
            return try await withTaskCancellationHandler { try await work.value } onCancel: {
                operation.cancel()
                work.cancel()
            }
        })
    }
}
