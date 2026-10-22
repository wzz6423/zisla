import CoreGraphics
import CoreImage
import CoreImage.CIFilterBuiltins
import Foundation
import Vision
import ZislaCore

enum ScreenshotExtractionMode: String, CaseIterable, Identifiable, Sendable {
    case foreground
    case background
    case lasso

    var id: Self { self }

    var title: String {
        switch self {
        case .foreground: "提取主体"
        case .background: "提取背景"
        case .lasso: "自由圈选"
        }
    }

    var symbol: String {
        switch self {
        case .foreground: "person.crop.square"
        case .background: "photo"
        case .lasso: "lasso"
        }
    }
}

enum ScreenshotExtractionError: LocalizedError {
    case invalidSelection
    case maskSizeMismatch
    case renderingFailed

    var errorDescription: String? {
        switch self {
        case .invalidSelection: AppLocalization.text("圈选区域无效")
        case .maskSizeMismatch: AppLocalization.text("提取蒙版尺寸不匹配")
        case .renderingFailed: AppLocalization.text("无法生成提取图片")
        }
    }
}

enum ScreenshotImageExtraction {
    static func lassoMask(
        regions: [[CGPoint]],
        imageSize: CGSize,
        pixelWidth: Int,
        pixelHeight: Int,
        checkCancellation: () throws -> Void = {}
    ) throws -> CGImage? {
        try checkCancellation()
        guard imageSize.width.isFinite, imageSize.height.isFinite,
              imageSize.width > 0, imageSize.height > 0,
              pixelWidth > 0, pixelHeight > 0,
              regions.allSatisfy({ points in
                  points.count >= 3 && points.allSatisfy { $0.x.isFinite && $0.y.isFinite }
              })
        else { throw ScreenshotExtractionError.invalidSelection }

        var coverage = [UInt8](repeating: 0, count: pixelWidth * pixelHeight)
        let mask: CGImage? = coverage.withUnsafeMutableBytes { bytes in
            guard let context = CGContext(
                data: bytes.baseAddress,
                width: pixelWidth,
                height: pixelHeight,
                bitsPerComponent: 8,
                bytesPerRow: pixelWidth,
                space: CGColorSpaceCreateDeviceGray(),
                bitmapInfo: CGImageAlphaInfo.none.rawValue
            ) else { return nil }
            context.setFillColor(gray: 1, alpha: 1)
            context.setShouldAntialias(true)
            let scaleX = CGFloat(pixelWidth) / imageSize.width
            let scaleY = CGFloat(pixelHeight) / imageSize.height
            for points in regions {
                context.beginPath()
                context.move(to: CGPoint(
                    x: points[0].x * scaleX,
                    y: (imageSize.height - points[0].y) * scaleY
                ))
                for point in points.dropFirst() {
                    context.addLine(to: CGPoint(
                        x: point.x * scaleX,
                        y: (imageSize.height - point.y) * scaleY
                    ))
                }
                context.closePath()
                // Filling each loop independently keeps overlapping loops selected regardless of winding.
                context.drawPath(using: .eoFill)
            }
            return context.makeImage()
        }
        try checkCancellation()
        guard let mask else { throw ScreenshotExtractionError.renderingFailed }
        guard coverage.contains(where: { $0 > 0 }) else { return nil }
        return mask
    }

    static func applying(
        mask: CGImage,
        to image: CGImage,
        checkCancellation: () throws -> Void = {}
    ) throws -> CGImage {
        try checkCancellation()
        guard mask.width == image.width, mask.height == image.height else {
            throw ScreenshotExtractionError.maskSizeMismatch
        }
        let source = CIImage(cgImage: image)
        let filter = CIFilter.blendWithMask()
        filter.inputImage = source
        filter.backgroundImage = CIImage(color: .clear).cropped(to: source.extent)
        filter.maskImage = CIImage(cgImage: mask)
        guard let output = filter.outputImage,
              let extracted = CIContext().createCGImage(output, from: source.extent)
        else { throw ScreenshotExtractionError.renderingFailed }
        try checkCancellation()
        return extracted
    }

    static func containsVisiblePixels(_ image: CGImage) throws -> Bool {
        var pixels = [UInt8](repeating: 0, count: image.width * image.height * 4)
        let rendered = pixels.withUnsafeMutableBytes { bytes in
            guard let context = CGContext(
                data: bytes.baseAddress,
                width: image.width,
                height: image.height,
                bitsPerComponent: 8,
                bytesPerRow: image.width * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
            ) else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
            return true
        }
        guard rendered else { throw ScreenshotExtractionError.renderingFailed }
        return stride(from: 3, to: pixels.count, by: 4).contains { pixels[$0] > 0 }
    }
}

final class ScreenshotExtractionOperation: @unchecked Sendable {
    let mode: ScreenshotExtractionMode
    let imageSize: CGSize
    let regions: [[CGPoint]]
    private let lock = NSLock()
    private var isCancelled = false
    private let request: VNGenerateForegroundInstanceMaskRequest

    init(
        mode: ScreenshotExtractionMode,
        imageSize: CGSize,
        regions: [[CGPoint]] = [],
        request: VNGenerateForegroundInstanceMaskRequest = VNGenerateForegroundInstanceMaskRequest()
    ) {
        self.mode = mode
        self.imageSize = imageSize
        self.regions = regions
        self.request = request
    }

    func cancel() {
        lock.withLock { isCancelled = true }
        request.cancel()
    }

    func checkCancellation() throws {
        if lock.withLock({ isCancelled }) { throw CancellationError() }
    }

    func extract(_ image: CGImage) throws -> CGImage? {
        try checkCancellation()
        let mask: CGImage
        if mode == .lasso {
            guard let selection = try ScreenshotImageExtraction.lassoMask(
                regions: regions,
                imageSize: imageSize,
                pixelWidth: image.width,
                pixelHeight: image.height,
                checkCancellation: checkCancellation
            ) else { return nil }
            mask = selection
        } else {
            let handler = VNImageRequestHandler(cgImage: image, orientation: .up, options: [:])
            try handler.perform([request])
            try checkCancellation()
            guard let observation = request.results?.first, !observation.allInstances.isEmpty else { return nil }
            let instances = mode == .background ? IndexSet(integer: 0) : observation.allInstances
            let pixelBuffer = try observation.generateScaledMaskForImage(forInstances: instances, from: handler)
            let scaledMask = CIImage(cvPixelBuffer: pixelBuffer)
            guard let generated = CIContext().createCGImage(
                scaledMask,
                from: scaledMask.extent,
                format: .L8,
                colorSpace: CGColorSpaceCreateDeviceGray()
            ) else { throw ScreenshotExtractionError.renderingFailed }
            mask = generated
        }
        return try ScreenshotImageExtraction.applying(mask: mask, to: image, checkCancellation: checkCancellation)
    }
}
