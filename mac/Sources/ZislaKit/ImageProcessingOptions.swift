import Foundation
import ZislaCore

public enum ImageToolOperation: String, CaseIterable, Identifiable, Sendable {
    case compress
    case convert
    case resize
    case smallest
    case transform
    case watermark
    case obscure
    case recognize
    case extract

    public var id: Self { self }

    public var title: String {
        switch self {
        case .compress: "压缩图片"
        case .convert: "转换格式"
        case .resize: "缩放与裁剪"
        case .smallest: "选择最小格式"
        case .transform: "旋转与镜像"
        case .watermark: "添加水印"
        case .obscure: "马赛克与模糊"
        case .recognize: "识别文字与表格"
        case .extract: "本地抠图"
        }
    }

    public var detail: String {
        switch self {
        case .compress: "减小图片体积，保留透明度与动画"
        case .convert: "同时导出 PNG、JPEG、WebP、AVIF 或 JPEG XL"
        case .resize: "按尺寸缩放，或智能裁剪为缩略图"
        case .smallest: "比较五种格式，仅导出体积最小的图片"
        case .transform: "批量旋转或水平、垂直翻转图片"
        case .watermark: "批量叠加文字或图片水印"
        case .obscure: "框选或涂抹需要遮挡的区域"
        case .recognize: "本地识别图片，导出文字或表格"
        case .extract: "提取主体、背景，或自由圈选"
        }
    }

    public var symbol: String {
        switch self {
        case .compress: "arrow.down.right.and.arrow.up.left"
        case .convert: "arrow.triangle.2.circlepath"
        case .resize: "crop"
        case .smallest: "checkmark.seal"
        case .transform: "arrow.triangle.2.circlepath"
        case .watermark: "seal"
        case .obscure: "square.grid.3x3"
        case .recognize: "text.viewfinder"
        case .extract: "person.crop.square"
        }
    }

    public var requiresRasterEditing: Bool { self == .obscure || self == .extract }
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

public enum ImageRotation: Int, CaseIterable, Identifiable, Sendable {
    case none = 0
    case clockwise90 = 90
    case halfTurn = 180
    case clockwise270 = 270

    public var id: Self { self }
    public var title: String {
        switch self {
        case .none: "不旋转"
        case .clockwise90: "顺时针 90°"
        case .halfTurn: "旋转 180°"
        case .clockwise270: "顺时针 270°"
        }
    }
}

public struct ImageTransformOptions: Equatable, Sendable {
    public static let identity = Self()
    public var rotation: ImageRotation
    public var flipHorizontal: Bool
    public var flipVertical: Bool

    public init(rotation: ImageRotation = .none, flipHorizontal: Bool = false, flipVertical: Bool = false) {
        self.rotation = rotation
        self.flipHorizontal = flipHorizontal
        self.flipVertical = flipVertical
    }

    public var isIdentity: Bool { self == .identity }

    func dimensions(for summary: ImageFileSummary) -> (width: Int, height: Int) {
        rotation == .clockwise90 || rotation == .clockwise270 ? (summary.height, summary.width) : (summary.width, summary.height)
    }
}

public enum ImageWatermarkContent: Equatable, Sendable {
    case text(String)
    case image(URL)
}

public enum ImageWatermarkPosition: String, CaseIterable, Identifiable, Sendable {
    case center
    case topLeft
    case topRight
    case bottomLeft
    case bottomRight

    public var id: Self { self }
    public var title: String {
        switch self {
        case .center: "居中"
        case .topLeft: "左上"
        case .topRight: "右上"
        case .bottomLeft: "左下"
        case .bottomRight: "右下"
        }
    }
}

public struct ImageWatermarkOptions: Equatable, Sendable {
    public static let maximumTextLength = 4_096
    public var content: ImageWatermarkContent
    public var opacity: Double
    public var scale: Double
    public var position: ImageWatermarkPosition
    public var color: String

    public init(content: ImageWatermarkContent, opacity: Double = 0.35, scale: Double = 0.3,
                position: ImageWatermarkPosition = .bottomRight, color: String = "#FFFFFF") {
        self.content = content
        self.opacity = opacity
        self.scale = scale
        self.position = position
        self.color = color
    }

    public var isValid: Bool {
        guard (0...1).contains(opacity), (0.01...1).contains(scale) else { return false }
        switch content {
        case let .text(text):
            return !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                && text.utf16.count <= Self.maximumTextLength && colorValue != nil
                && text.unicodeScalars.allSatisfy { ($0.value >= 0x20 && !(0x7F...0x9F).contains($0.value)) || "\n\r\t".unicodeScalars.contains($0) }
        case let .image(url): return url.isFileURL
        }
    }

    var colorValue: UInt32? {
        let hex = color.trimmingCharacters(in: .whitespacesAndNewlines)
        guard hex.count == 7, hex.first == "#", hex.dropFirst().allSatisfy(\.isHexDigit) else { return nil }
        return UInt32(hex.dropFirst(), radix: 16)
    }
}

public struct ImageProcessingOptions: Equatable, Sendable {
    public var formats: [ImageOutputFormat]
    public var smallestOnly: Bool
    public var quality: Int
    public var resize: ImageResizeOptions?
    public var preserveMetadata: Bool
    public var background: String
    public var transform: ImageTransformOptions
    public var watermark: ImageWatermarkOptions?

    public init(
        formats: [ImageOutputFormat] = [], smallestOnly: Bool = false, quality: Int = 80,
        resize: ImageResizeOptions? = nil, preserveMetadata: Bool = false, background: String = "#FFFFFF",
        transform: ImageTransformOptions = .identity, watermark: ImageWatermarkOptions? = nil
    ) {
        self.formats = formats
        self.smallestOnly = smallestOnly
        self.quality = quality
        self.resize = resize
        self.preserveMetadata = preserveMetadata
        self.background = background
        self.transform = transform
        self.watermark = watermark
    }

    public var isValid: Bool {
        (1...100).contains(quality) && (resize?.isValid ?? true) && backgroundChannels != nil && (watermark?.isValid ?? true)
    }

    func dimensions(for summary: ImageFileSummary) -> (width: Int, height: Int) {
        let transformed = transform.dimensions(for: summary)
        let rotated = ImageFileSummary(width: transformed.width, height: transformed.height,
            frameCount: summary.frameCount, fileSize: summary.fileSize, format: summary.format, hasMetadata: summary.hasMetadata)
        return resize?.dimensions(for: rotated) ?? transformed
    }

    var backgroundChannels: String? {
        let hex = background.trimmingCharacters(in: .whitespacesAndNewlines)
        guard hex.count == 7, hex.first == "#", hex.dropFirst().allSatisfy(\.isHexDigit),
              let value = UInt32(hex.dropFirst(), radix: 16) else { return nil }
        return "\((value >> 16) & 255) \((value >> 8) & 255) \(value & 255)"
    }
}
