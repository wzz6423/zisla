import Foundation
import ZislaCore

public enum ImageToolOperation: String, CaseIterable, Identifiable, Sendable {
    case compress
    case convert
    case resize
    case smallest

    public var id: Self { self }

    public var title: String {
        switch self {
        case .compress: "压缩图片"
        case .convert: "转换格式"
        case .resize: "缩放与裁剪"
        case .smallest: "选择最小格式"
        }
    }

    public var detail: String {
        switch self {
        case .compress: "减小图片体积，保留透明度与动画"
        case .convert: "同时导出 PNG、JPEG、WebP、AVIF 或 JPEG XL"
        case .resize: "按尺寸缩放，或智能裁剪为缩略图"
        case .smallest: "比较五种格式，仅导出体积最小的图片"
        }
    }

    public var symbol: String {
        switch self {
        case .compress: "arrow.down.right.and.arrow.up.left"
        case .convert: "arrow.triangle.2.circlepath"
        case .resize: "crop"
        case .smallest: "checkmark.seal"
        }
    }
}

public enum ImageOutputFormat: String, CaseIterable, Identifiable, Sendable {
    case png
    case jpeg
    case webp
    case avif
    case jpegXL
    case svg

    public static let conversionFormats: [Self] = [.png, .jpeg, .webp, .avif, .jpegXL]

    public var id: Self { self }
    public var fileExtension: String {
        switch self {
        case .jpeg: "jpg"
        case .jpegXL: "jxl"
        default: rawValue
        }
    }
    public var displayName: String {
        switch self {
        case .png: "PNG"
        case .jpeg: "JPEG"
        case .webp: "WebP"
        case .avif: "AVIF"
        case .jpegXL: "JPEG XL"
        case .svg: "SVG"
        }
    }
}

public enum ImageResizeMethod: String, CaseIterable, Identifiable, Sendable {
    case scale
    case fit
    case cover
    case thumb

    public var id: Self { self }
    public var title: String {
        switch self {
        case .scale: "按单边缩放"
        case .fit: "适应边界"
        case .cover: "智能裁剪"
        case .thumb: "缩略图（补齐背景）"
        }
    }
}

public struct ImageResizeOptions: Equatable, Sendable {
    public var method: ImageResizeMethod
    public var width: Int?
    public var height: Int?

    public init(method: ImageResizeMethod, width: Int?, height: Int?) {
        self.method = method
        self.width = width
        self.height = height
    }

    public var isValid: Bool {
        let dimensions = [width, height].compactMap { $0 }
        guard dimensions.allSatisfy({ (1...150_000).contains($0) }) else { return false }
        if method == .scale { return dimensions.count == 1 }
        return dimensions.count == 2 && Int64(width!) * Int64(height!) <= ImageProcessingService.maximumPixels
    }

    func dimensions(for summary: ImageFileSummary) -> (width: Int, height: Int) {
        switch method {
        case .thumb: return (width!, height!)
        case .cover: return (min(width!, summary.width), min(height!, summary.height))
        case .scale, .fit:
            let factor = min(1, Double(width ?? 150_000) / Double(summary.width), Double(height ?? 150_000) / Double(summary.height))
            return (max(1, Int((Double(summary.width) * factor).rounded())),
                    max(1, Int((Double(summary.height) * factor).rounded())))
        }
    }
}

public struct ImageProcessingOptions: Equatable, Sendable {
    public var formats: [ImageOutputFormat]
    public var smallestOnly: Bool
    public var quality: Int
    public var resize: ImageResizeOptions?
    public var preserveMetadata: Bool
    public var background: String

    public init(
        formats: [ImageOutputFormat] = [], smallestOnly: Bool = false, quality: Int = 80,
        resize: ImageResizeOptions? = nil, preserveMetadata: Bool = false, background: String = "#FFFFFF"
    ) {
        self.formats = formats
        self.smallestOnly = smallestOnly
        self.quality = quality
        self.resize = resize
        self.preserveMetadata = preserveMetadata
        self.background = background
    }

    public var isValid: Bool {
        (1...100).contains(quality) && (resize?.isValid ?? true) && backgroundChannels != nil
    }

    var backgroundChannels: String? {
        let hex = background.trimmingCharacters(in: .whitespacesAndNewlines)
        guard hex.count == 7, hex.first == "#", hex.dropFirst().allSatisfy(\.isHexDigit),
              let value = UInt32(hex.dropFirst(), radix: 16) else { return nil }
        return "\((value >> 16) & 255) \((value >> 8) & 255) \(value & 255)"
    }
}
