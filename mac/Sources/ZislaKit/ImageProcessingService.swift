import Foundation
import CoreImage
import ImageIO
import UniformTypeIdentifiers
import ZislaCore

public enum ImageProcessingError: LocalizedError, Equatable, Sendable {
    case engineUnavailable
    case avifEngineUnavailable
    case invalidInput(URL)
    case invalidOptions
    case resourceLimit
    case processingFailed(String)
    case animationUnsupported(ImageOutputFormat)
    case invalidOutput
    case outputAlreadyExists(URL)
    case emptyInput
    case rasterEditingAnimationUnsupported
    case rasterEditingMetadataUnsupported

    public var errorDescription: String? {
        switch self {
        case .engineUnavailable: AppLocalization.text("请先安装 libvips 图片处理组件")
        case .avifEngineUnavailable: AppLocalization.text("请先安装 libavif 动画处理组件")
        case let .invalidInput(url): AppLocalization.text("无法读取本地图片：%@", url.lastPathComponent)
        case .invalidOptions: AppLocalization.text("图片处理参数无效")
        case .resourceLimit: AppLocalization.text("图片超过处理上限（500 MB、SVG 20 MB、2.56 亿像素或 1000 帧）")
        case let .processingFailed(message): AppLocalization.text("图片处理失败：%@", message)
        case let .animationUnsupported(format): AppLocalization.text("此动画无法导出为 %@，请选择 PNG、WebP、AVIF 或 JPEG XL", format.displayName)
        case .invalidOutput: AppLocalization.text("图片输出无效，未保存")
        case let .outputAlreadyExists(url): AppLocalization.text("输出文件已存在，未覆盖：%@", url.lastPathComponent)
        case .emptyInput: AppLocalization.text("请先选择图片或包含图片的文件夹")
        case .rasterEditingAnimationUnsupported: AppLocalization.text("此编辑功能仅支持静态图片，请使用旋转或水印工具处理动画")
        case .rasterEditingMetadataUnsupported: AppLocalization.text("此编辑功能无法保留原始元数据，请关闭保留元数据")
        }
    }
}

public struct ImageFileSummary: Equatable, Sendable {
    public let width: Int
    public let height: Int
    public let frameCount: Int
    public let fileSize: Int64
    public let format: ImageOutputFormat?
    let hasMetadata: Bool
}

public struct ImageProcessedOutput: Identifiable, Equatable, Sendable {
    public let url: URL
    public let format: ImageOutputFormat
    public let summary: ImageFileSummary
    public var id: URL { url }
}

public struct ImageProcessedItem: Identifiable, Equatable, Sendable {
    public let inputURL: URL
    public let sourceURL: URL
    public let summary: ImageFileSummary
    public let outputs: [ImageProcessedOutput]
    public var id: URL { inputURL }
    public var smallest: ImageProcessedOutput? { outputs.min { $0.summary.fileSize < $1.summary.fileSize } }

    public init(inputURL: URL, sourceURL: URL, summary: ImageFileSummary, outputs: [ImageProcessedOutput]) {
        self.inputURL = inputURL
        self.sourceURL = sourceURL
        self.summary = summary
        self.outputs = outputs
    }
}

public struct ImageProcessingFailure: Equatable, Sendable {
    public let inputURL: URL
    public let format: ImageOutputFormat?
    public let message: String
}

public struct ImageProcessingBatch: Sendable {
    public let directoryURL: URL
    public let items: [ImageProcessedItem]
    public let failures: [ImageProcessingFailure]
}

public struct ImageProcessingService: Sendable {
    public static let supportedExtensions: Set<String> = ["png", "apng", "jpg", "jpeg", "webp", "avif", "jxl", "heic", "heif", "svg"]
    public static let maximumPixels: Int64 = 256_000_000
    public typealias ProcessRunner = @Sendable (URL, [String], URL, Data?) async throws -> AIAgentProcessOutput
    public typealias RasterTransform = @Sendable (CGImage, URL) async throws -> CGImage

    private let executableURL: URL?
    private let avifExecutableURL: URL?
    private let runner: ProcessRunner

    public init(executableURL: URL?, avifExecutableURL: URL? = nil, runner: ProcessRunner? = nil) {
        self.executableURL = executableURL
        self.avifExecutableURL = avifExecutableURL
        self.runner = runner ?? { executable, arguments, directory, input in
            var environment = ProcessInfo.processInfo.environment
            // libvips serializes translated EXIF descriptions in .v files and misreads them in a later process.
            environment["LC_ALL"] = "C"
            return try await AIAgentProcessRunner.run(
                executableURL: executable, arguments: arguments, standardInput: input, environment: environment, workingDirectoryURL: directory,
                timeout: 5 * 60, maximumOutputBytes: 64 * 1_024, maximumErrorBytes: 64 * 1_024
            )
        }
    }

    public static func collectInputs(_ urls: [URL]) throws -> [URL] {
        let manager = FileManager.default
        var inputs = Set<URL>()
        for url in urls {
            try Task.checkCancellation()
            guard url.isFileURL else { throw ImageProcessingError.invalidInput(url) }
            let values = try url.resourceValues(forKeys: [.isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey])
            guard values.isSymbolicLink != true else { throw ImageProcessingError.invalidInput(url) }
            if values.isDirectory == true {
                guard let enumerator = manager.enumerator(
                    at: url, includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey],
                    options: [.skipsHiddenFiles, .skipsPackageDescendants]
                ) else { throw ImageProcessingError.invalidInput(url) }
                for case let child as URL in enumerator {
                    try Task.checkCancellation()
                    let values = try child.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
                    if values.isRegularFile == true, values.isSymbolicLink != true,
                       supportedExtensions.contains(child.pathExtension.lowercased()) {
                        inputs.insert(child.standardizedFileURL)
                    }
                }
            } else {
                guard values.isRegularFile == true, supportedExtensions.contains(url.pathExtension.lowercased()) else {
                    throw ImageProcessingError.invalidInput(url)
                }
                inputs.insert(url.standardizedFileURL)
            }
        }
        return inputs.sorted { $0.path < $1.path }
    }

    public func process(
        _ inputURLs: [URL], options: ImageProcessingOptions,
        rasterTransform: RasterTransform? = nil,
        progress: @escaping @Sendable (Int, Int) async -> Void = { _, _ in }
    ) async throws -> ImageProcessingBatch {
        guard !inputURLs.isEmpty else { throw ImageProcessingError.emptyInput }
        guard options.isValid else { throw ImageProcessingError.invalidOptions }
        guard rasterTransform == nil || !options.preserveMetadata else { throw ImageProcessingError.rasterEditingMetadataUnsupported }
        let nativeRasterOutput = rasterTransform != nil && options.transform.isIdentity && options.resize == nil && options.watermark == nil
            && (options.formats.isEmpty || Set(options.formats) == [.png])
        guard nativeRasterOutput || (executableURL.map { FileManager.default.isExecutableFile(atPath: $0.path) } ?? false) else {
            throw ImageProcessingError.engineUnavailable
        }
        let manager = FileManager.default
        let directory = manager.temporaryDirectory.appendingPathComponent("zisla-image-tools-\(UUID())", isDirectory: true)
        try manager.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        do {
            let watermark: ImageWatermarkRenderer?
            if let options = options.watermark {
                switch options.content {
                case let .text(text): watermark = ImageWatermarkRenderer(options: options, content: .text(text))
                case let .image(url): watermark = ImageWatermarkRenderer(options: options, content: .image(try await loadRasterImage(url)))
                }
            } else { watermark = nil }
            var items: [ImageProcessedItem] = []
            var failures: [ImageProcessingFailure] = []
            for (index, input) in inputURLs.enumerated() {
                try Task.checkCancellation()
                let work = directory.appendingPathComponent(String(index), isDirectory: true)
                do {
                    try manager.createDirectory(at: work, withIntermediateDirectories: true)
                    // Only generated paths reach libvips: user filenames can contain its [loader-options] syntax.
                    let source = work.appendingPathComponent("source").appendingPathExtension(input.pathExtension.lowercased())
                    guard input.isFileURL else { throw ImageProcessingError.invalidInput(input) }
                    let values = try input.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
                    guard values.isRegularFile == true, values.isSymbolicLink != true,
                          Self.supportedExtensions.contains(input.pathExtension.lowercased()) else {
                        throw ImageProcessingError.invalidInput(input)
                    }
                    guard (values.fileSize ?? 0) <= 500 * 1_024 * 1_024 else { throw ImageProcessingError.resourceLimit }
                    try manager.copyItem(at: input, to: source)
                    let summary = try await inspect(source)
                    var encodingSource = source
                    var encodingSummary = summary
                    if let rasterTransform {
                        guard summary.frameCount == 1 else { throw ImageProcessingError.rasterEditingAnimationUnsupported }
                        let image = try await loadRasterImage(source)
                        let edited = try await rasterTransform(image, input)
                        try Task.checkCancellation()
                        guard edited.width <= 150_000, edited.height <= 150_000,
                              Int64(edited.width) * Int64(edited.height) <= Self.maximumPixels else { throw ImageProcessingError.resourceLimit }
                        encodingSource = work.appendingPathComponent("edited.png")
                        guard let destination = CGImageDestinationCreateWithURL(encodingSource as CFURL, UTType.png.identifier as CFString, 1, nil) else {
                            throw ImageProcessingError.invalidOutput
                        }
                        CGImageDestinationAddImage(destination, edited, nil)
                        guard CGImageDestinationFinalize(destination) else { throw ImageProcessingError.invalidOutput }
                        encodingSummary = try await inspect(encodingSource)
                    }
                    let expected = options.dimensions(for: encodingSummary)
                    guard Int64(expected.0) * Int64(expected.1) <= Self.maximumPixels / Int64(encodingSummary.frameCount) else {
                        throw ImageProcessingError.resourceLimit
                    }
                    let overlay = try watermark?.render(width: expected.0, height: expected.1, to: work.appendingPathComponent("watermark.png"))
                    let defaultFormat = rasterTransform != nil || (summary.format == .svg && (options.resize != nil || !options.transform.isIdentity || options.watermark != nil)) ? .png : summary.format ?? .jpeg
                    let formats: [ImageOutputFormat] = options.formats.isEmpty ? [defaultFormat] : Array(Set(options.formats)).sorted { $0.rawValue < $1.rawValue }
                    var outputs: [ImageProcessedOutput] = []
                    for format in formats {
                        try Task.checkCancellation()
                        let output = work.appendingPathComponent("output").appendingPathExtension(format.fileExtension)
                        do {
                            if nativeRasterOutput { try manager.copyItem(at: encodingSource, to: output) }
                            else { try await encode(encodingSource, summary: encodingSummary, format: format, options: options, output: output, work: work, stableCrop: false, overlay: overlay) }
                            var result = try await inspect(output)
                            guard result.format == format, result.frameCount == summary.frameCount,
                                  result.width == expected.0, result.height == expected.1 else {
                                throw ImageProcessingError.invalidOutput
                            }
                            if options.resize == nil, options.transform.isIdentity, options.watermark == nil, rasterTransform == nil, format == summary.format,
                               result.fileSize > summary.fileSize, options.preserveMetadata || !summary.hasMetadata {
                                try manager.removeItem(at: output)
                                try manager.copyItem(at: source, to: output)
                                result = summary
                            }
                            outputs.append(ImageProcessedOutput(url: output, format: format, summary: result))
                        } catch is CancellationError { throw CancellationError() }
                        catch {
                            if manager.fileExists(atPath: output.path) { try manager.removeItem(at: output) }
                            failures.append(ImageProcessingFailure(inputURL: input, format: format, message: error.localizedDescription))
                        }
                    }
                    if options.smallestOnly, let smallest = outputs.min(by: { $0.summary.fileSize < $1.summary.fileSize }) {
                        for output in outputs where output.url != smallest.url { try manager.removeItem(at: output.url) }
                        outputs = [smallest]
                    }
                    if !outputs.isEmpty {
                        let retained = Set((outputs.map(\.url) + [source]).map(\.lastPathComponent))
                        for url in try manager.contentsOfDirectory(at: work, includingPropertiesForKeys: nil) where !retained.contains(url.lastPathComponent) {
                            try manager.removeItem(at: url)
                        }
                        items.append(ImageProcessedItem(inputURL: input, sourceURL: source, summary: summary, outputs: outputs))
                    } else {
                        try manager.removeItem(at: work)
                    }
                } catch is CancellationError { throw CancellationError() }
                catch {
                    try? manager.removeItem(at: work)
                    failures.append(ImageProcessingFailure(inputURL: input, format: nil, message: error.localizedDescription))
                }
                await progress(index + 1, inputURLs.count)
            }
            try Task.checkCancellation()
            return ImageProcessingBatch(directoryURL: directory, items: items, failures: failures)
        } catch {
            try? manager.removeItem(at: directory)
            throw error
        }
    }

    public func inspect(_ url: URL) async throws -> ImageFileSummary {
        let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        guard size > 0, size <= 500 * 1_024 * 1_024 else { throw ImageProcessingError.resourceLimit }
        if url.pathExtension.lowercased() == "svg" { _ = try Self.svgDocument(url) }
        else {
            let file = try FileHandle(forReadingFrom: url)
            defer { try? file.close() }
            let bytes = [UInt8](try file.read(upToCount: 32) ?? Data())
            let raster = bytes.starts(with: [0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a])
                || bytes.starts(with: [0xff, 0xd8, 0xff]) || bytes.starts(with: [0xff, 0x0a])
                || bytes.starts(with: [0, 0, 0, 12, 0x4a, 0x58, 0x4c, 0x20, 0x0d, 0x0a, 0x87, 0x0a])
                || (bytes.count >= 12 && bytes[0..<4].elementsEqual("RIFF".utf8) && bytes[8..<12].elementsEqual("WEBP".utf8))
                || (bytes.count >= 12 && bytes[4..<8].elementsEqual("ftyp".utf8)
                    && ["avif", "avis", "heic", "heix", "hevc", "hevx", "mif1", "msf1"].contains { bytes[8..<12].elementsEqual($0.utf8) })
            guard raster else { throw ImageProcessingError.invalidInput(url) }
            // ImageIO treats a PNG missing IEND as complete, which must not become an edited result.
            if bytes.starts(with: [0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]) {
                var position: UInt64 = 8
                while true {
                    try Task.checkCancellation()
                    try file.seek(toOffset: position)
                    let chunk = [UInt8](try file.read(upToCount: 8) ?? Data())
                    guard chunk.count == 8 else { throw ImageProcessingError.invalidInput(url) }
                    let length = chunk.prefix(4).reduce(UInt64(0)) { ($0 << 8) | UInt64($1) }
                    guard position + length + 12 <= UInt64(size) else { throw ImageProcessingError.invalidInput(url) }
                    if chunk.suffix(4).elementsEqual("IEND".utf8) {
                        guard length == 0, try file.read(upToCount: 4) == Data([0xae, 0x42, 0x60, 0x82]) else { throw ImageProcessingError.invalidInput(url) }
                        break
                    }
                    position += length + 12
                }
            }
        }
        let summary: ImageFileSummary
        // ImageIO can omit JPEG XL frames and does not identify SVG consistently across macOS versions.
        if !["jxl", "svg"].contains(url.pathExtension.lowercased()), let source = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary),
           let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
           let width = properties[kCGImagePropertyPixelWidth] as? Int,
           let height = properties[kCGImagePropertyPixelHeight] as? Int {
            guard CGImageSourceGetStatus(source) == .statusComplete else { throw ImageProcessingError.invalidInput(url) }
            let type = CGImageSourceGetType(source) as String?
            let format = Self.nativeFormat(type)
            let frameCount = format == nil ? 1 : CGImageSourceGetCount(source)
            let orientation = properties[kCGImagePropertyOrientation] as? Int ?? 1
            let rotated = (5...8).contains(orientation)
            let hasMetadata = CGImageSourceCopyMetadataAtIndex(source, 0, nil) != nil
                || [kCGImagePropertyExifDictionary, kCGImagePropertyGPSDictionary, kCGImagePropertyIPTCDictionary, kCGImagePropertyTIFFDictionary]
                    .contains { (properties[$0] as? [AnyHashable: Any])?.isEmpty == false }
            summary = ImageFileSummary(width: rotated ? height : width, height: rotated ? width : height,
                frameCount: frameCount, fileSize: Int64(size), format: format, hasMetadata: hasMetadata)
        } else {
            let fields = try await header(url)
            guard let width = fields["width"].flatMap(Int.init), let height = fields["height"].flatMap(Int.init) else {
                throw ImageProcessingError.invalidInput(url)
            }
            let orientation = fields["orientation"].flatMap(Int.init) ?? 1
            let pageHeight = fields["page-height"].flatMap(Int.init) ?? height
            let rotated = (5...8).contains(orientation)
            summary = ImageFileSummary(width: rotated ? pageHeight : width, height: rotated ? width : pageHeight,
                frameCount: fields["n-pages"].flatMap(Int.init) ?? 1, fileSize: Int64(size),
                format: Self.loaderFormat(fields["vips-loader"]),
                hasMetadata: url.pathExtension.lowercased() == "svg" || ["exif-data", "xmp-data", "iptc-data"].contains { fields[$0] != nil })
        }
        guard summary.width > 0, summary.height > 0, summary.width <= 150_000, summary.height <= 150_000,
              summary.frameCount > 0, summary.frameCount <= 1_000,
              Int64(summary.width) * Int64(summary.height) <= Self.maximumPixels / Int64(summary.frameCount) else { throw ImageProcessingError.resourceLimit }
        return summary
    }

    public func loadRasterImage(_ url: URL) async throws -> CGImage {
        try Task.checkCancellation()
        guard url.isFileURL else { throw ImageProcessingError.invalidInput(url) }
        let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
        guard values.isRegularFile == true, values.isSymbolicLink != true,
              Self.supportedExtensions.contains(url.pathExtension.lowercased()) else { throw ImageProcessingError.invalidInput(url) }
        guard let size = values.fileSize, size > 0,
              size <= (url.pathExtension.lowercased() == "svg" ? 20 : 500) * 1_024 * 1_024 else { throw ImageProcessingError.resourceLimit }
        let manager = FileManager.default
        let directory = manager.temporaryDirectory.appendingPathComponent("zisla-image-raster-\(UUID())", isDirectory: true)
        try manager.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        defer { try? manager.removeItem(at: directory) }
        let staged = directory.appendingPathComponent("source").appendingPathExtension(url.pathExtension.lowercased())
        try manager.copyItem(at: url, to: staged)
        let summary = try await inspect(staged)
        guard summary.frameCount == 1 else { throw ImageProcessingError.rasterEditingAnimationUnsupported }
        if url.pathExtension.lowercased() != "svg", let source = CGImageSourceCreateWithURL(staged as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary) {
            guard CGImageSourceGetCount(source) == 1 else { throw ImageProcessingError.rasterEditingAnimationUnsupported }
            if let image = CGImageSourceCreateImageAtIndex(source, 0, [kCGImageSourceShouldCacheImmediately: true] as CFDictionary) {
                guard CGImageSourceGetStatusAtIndex(source, 0) == .statusComplete else { throw ImageProcessingError.invalidInput(url) }
                let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] ?? [:]
                let orientation = properties[kCGImagePropertyOrientation] as? Int ?? 1
                let normalized: CGImage
                if orientation == 1 { normalized = image }
                else {
                    // ImageIO's thumbnail transform can ignore orientation when a PNG also contains GPS metadata.
                    let oriented = CIImage(cgImage: image).oriented(forExifOrientation: Int32(orientation))
                    guard let raster = CIContext().createCGImage(oriented, from: oriented.extent) else { throw ImageProcessingError.invalidOutput }
                    normalized = raster
                }
                guard normalized.width == summary.width, normalized.height == summary.height else { throw ImageProcessingError.invalidInput(url) }
                try Task.checkCancellation()
                return normalized
            }
        }
        let normalized = directory.appendingPathComponent("normalized.v")
        let output = directory.appendingPathComponent("raster.png")
        _ = try await run(["autorot", staged.path + "[fail-on=error]", normalized.path], in: directory)
        _ = try await run(["pngsave", normalized.path, output.path, "--compression=9", "--keep=icc"], in: directory)
        let result = try await inspect(output)
        guard result.format == .png, result.frameCount == 1,
              result.width == summary.width, result.height == summary.height,
              let decoded = CGImageSourceCreateWithURL(output as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(decoded, 0, [kCGImageSourceShouldCacheImmediately: true] as CFDictionary),
              CGImageSourceGetStatusAtIndex(decoded, 0) == .statusComplete else { throw ImageProcessingError.invalidOutput }
        try Task.checkCancellation()
        return image
    }

    public static func export(_ items: [ImageProcessedItem], to directory: URL, smallestOnly: Bool) throws -> [URL] {
        try Task.checkCancellation()
        let manager = FileManager.default
        guard directory.isFileURL, try directory.resourceValues(forKeys: [.isDirectoryKey]).isDirectory == true else {
            throw ImageProcessingError.invalidInput(directory)
        }
        var names = Set<String>()
        var pairs: [(URL, URL)] = []
        for item in items {
            let outputs = smallestOnly ? item.smallest.map { [$0] } ?? [] : item.outputs
            for output in outputs {
                let base = item.inputURL.deletingPathExtension().lastPathComponent + "-" + output.format.fileExtension
                var name = base + "." + output.format.fileExtension
                var suffix = 2
                while !names.insert(name.lowercased()).inserted {
                    name = "\(base)-\(suffix).\(output.format.fileExtension)"
                    suffix += 1
                }
                let destination = directory.appendingPathComponent(name)
                guard !manager.fileExists(atPath: destination.path),
                      (try? destination.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) != true else {
                    throw ImageProcessingError.outputAlreadyExists(destination)
                }
                pairs.append((output.url, destination))
            }
        }
        guard !pairs.isEmpty else { throw ImageProcessingError.emptyInput }
        var created: [URL] = []
        do {
            for (source, destination) in pairs {
                try Task.checkCancellation()
                try manager.copyItem(at: source, to: destination)
                created.append(destination)
                try Task.checkCancellation()
            }
        } catch {
            for url in created { try? manager.removeItem(at: url) }
            throw error
        }
        return created
    }

    public func preview(_ url: URL) async throws -> Data {
        try Task.checkCancellation()
        _ = try await inspect(url)
        if let source = CGImageSourceCreateWithURL(url as CFURL, nil),
           let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
               kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceCreateThumbnailWithTransform: true,
               kCGImageSourceThumbnailMaxPixelSize: 1_200,
           ] as CFDictionary) {
            let data = NSMutableData()
            guard let destination = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil) else {
                throw ImageProcessingError.invalidOutput
            }
            CGImageDestinationAddImage(destination, image, nil)
            guard CGImageDestinationFinalize(destination) else { throw ImageProcessingError.invalidOutput }
            return data as Data
        }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("zisla-image-preview-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = directory.appendingPathComponent("source").appendingPathExtension(url.pathExtension)
        try FileManager.default.copyItem(at: url, to: source)
        let output = directory.appendingPathComponent("preview.png")
        _ = try await run(["thumbnail", source.path, output.path, "1200", "--size=down"], in: directory)
        return try Data(contentsOf: output)
    }

    private func header(_ url: URL) async throws -> [String: String] {
        let output = try await run(["-a", url.path], in: url.deletingLastPathComponent(), tool: "vipsheader")
        var fields: [String: String] = [:]
        for line in String(decoding: output.standardOutput, as: UTF8.self).split(separator: "\n") {
            let parts = line.split(separator: ":", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
            if parts.count == 2 { fields[parts[0]] = parts[1] }
        }
        return fields
    }

    func run(_ arguments: [String], in directory: URL, tool: String? = nil, input: Data? = nil) async throws -> AIAgentProcessOutput {
        try Task.checkCancellation()
        guard let executableURL else { throw ImageProcessingError.engineUnavailable }
        let executable: URL
        if tool == "avifenc" {
            guard let avifExecutableURL, FileManager.default.isExecutableFile(atPath: avifExecutableURL.path) else {
                throw ImageProcessingError.avifEngineUnavailable
            }
            executable = avifExecutableURL
        } else { executable = tool.map { executableURL.deletingLastPathComponent().appendingPathComponent($0) } ?? executableURL }
        let limits = tool == "avifenc" ? ["--jobs", "2"] : ["--vips-concurrency=2", "--vips-cache-max=0", "--vips-disc-threshold=67108864"]
        let output = try await runner(executable, arguments + limits, directory, input)
        try Task.checkCancellation()
        if output.didTimeout { throw ImageProcessingError.processingFailed(AppLocalization.text("转换超时")) }
        guard output.status == 0 else {
            throw ImageProcessingError.processingFailed(output.standardError)
        }
        return output
    }

    private func encode(_ source: URL, summary: ImageFileSummary, format: ImageOutputFormat,
                        options: ImageProcessingOptions, output: URL, work: URL, stableCrop: Bool, overlay: ImageWatermarkOverlay?) async throws {
        if format == .svg {
            guard summary.format == .svg, options.resize == nil, options.transform.isIdentity, overlay == nil else { throw ImageProcessingError.invalidOptions }
            let document = try Self.svgDocument(source)
            func optimize(_ node: XMLNode) {
                for child in node.children ?? [] {
                    if child.kind == .comment || (!options.preserveMetadata && child.localName?.lowercased() == "metadata") {
                        child.detach()
                    } else { optimize(child) }
                }
            }
            optimize(document)
            try document.xmlData(options: []).write(to: output)
            return
        }
        if summary.frameCount > 1 {
            try await encodeAnimation(source, summary: summary, format: format, options: options, output: output, work: work, overlay: overlay)
            return
        }
        let image = work.appendingPathComponent("prepared.v")
        var arguments: [String]
        var loader = source.path + "[fail-on=error]"
        if !options.transform.isIdentity {
            let normalized = work.appendingPathComponent("normalized.v")
            _ = try await run(["autorot", loader, normalized.path], in: work)
            var transformed = normalized
            if options.transform.rotation != .none {
                let rotated = work.appendingPathComponent("rotated.v")
                _ = try await run(["rot", transformed.path, rotated.path, "d\(options.transform.rotation.rawValue)"], in: work)
                transformed = rotated
            }
            if options.transform.flipHorizontal {
                let mirrored = work.appendingPathComponent("mirrored-horizontal.v")
                _ = try await run(["flip", transformed.path, mirrored.path, "horizontal"], in: work)
                transformed = mirrored
            }
            if options.transform.flipVertical {
                let mirrored = work.appendingPathComponent("mirrored-vertical.v")
                _ = try await run(["flip", transformed.path, mirrored.path, "vertical"], in: work)
                transformed = mirrored
            }
            loader = transformed.path
        }
        if let resize = options.resize {
            arguments = ["thumbnail", loader, image.path, String(resize.width ?? 150_000),
                         "--height=\(resize.height ?? 150_000)", "--size=down", "--fail-on=error"]
            if resize.method == .cover || resize.method == .thumb {
                // Content-dependent crop windows can move between frames of the same animation.
                arguments.append(stableCrop ? "--crop=centre" : "--crop=attention")
            }
        } else {
            arguments = ["autorot", loader, image.path]
        }
        _ = try await run(arguments, in: work)
        var prepared = image
        if let resize = options.resize, resize.method == .thumb {
            prepared = work.appendingPathComponent("padded.v")
            let colour = work.appendingPathComponent("colour.v")
            _ = try await run(["colourspace", image.path, colour.path, "srgb"], in: work)
            if try await header(colour)["bands"] == "4" {
                _ = try await run(["flatten", colour.path, prepared.path, "--background=\(options.backgroundChannels!)"], in: work)
            } else { prepared = colour }
            _ = try await run(["gravity", prepared.path, image.path, "centre", String(resize.width!), String(resize.height!),
                              "--extend=background", "--background=\(options.backgroundChannels!)"], in: work)
            prepared = image
        }
        if let overlay {
            let watermarked = work.appendingPathComponent("watermarked.v")
            _ = try await run(["composite2", prepared.path, overlay.url.path, watermarked.path, "over",
                              "--x=\(overlay.x)", "--y=\(overlay.y)", "--compositing-space=srgb"], in: work)
            prepared = watermarked
        }
        _ = try await run(Self.saveArguments(prepared, output: output, format: format, options: options), in: work)
    }

    private func encodeAnimation(_ sourceURL: URL, summary: ImageFileSummary, format: ImageOutputFormat,
                                 options: ImageProcessingOptions, output: URL, work: URL, overlay: ImageWatermarkOverlay?) async throws {
        guard [.png, .webp, .jpegXL, .avif].contains(format), [.png, .webp, .jpegXL, .avif].contains(summary.format) else {
            throw ImageProcessingError.animationUnsupported(format)
        }
        let source = summary.format == .jpegXL ? nil : CGImageSourceCreateWithURL(sourceURL as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary)
        let dictionary: CFString = summary.format == .png ? kCGImagePropertyPNGDictionary : summary.format == .avif ? "{AVIS}" as CFString : kCGImagePropertyWebPDictionary
        let delayKey = "UnclampedDelayTime" as CFString
        let clampedDelayKey = "DelayTime" as CFString
        let loopKey = "LoopCount" as CFString
        let fields = summary.format == .jpegXL ? try await header(sourceURL) : [:]
        let jxlDelays = fields["delay"]?.split(separator: " ").compactMap { Double($0).map { $0 / 1_000 } } ?? []
        let properties = source.flatMap { CGImageSourceCopyProperties($0, nil) as? [CFString: Any] } ?? [:]
        let loop = (properties[dictionary] as? [CFString: Any])?[loopKey] as? Int ?? fields["loop"].flatMap(Int.init) ?? 0
        guard (0...65_535).contains(loop) else { throw ImageProcessingError.invalidInput(sourceURL) }
        var delays: [Int] = []
        var frames: [URL] = []
        let destination = format == .png ? CGImageDestinationCreateWithURL(output as CFURL, UTType.png.identifier as CFString, summary.frameCount, nil) : nil
        if let destination {
            CGImageDestinationSetProperties(destination, [kCGImagePropertyPNGDictionary: [kCGImagePropertyAPNGLoopCount: loop]] as CFDictionary)
        } else if format == .png { throw ImageProcessingError.invalidOutput }
        for index in 0..<summary.frameCount {
            try Task.checkCancellation()
            let input = work.appendingPathComponent("frame.png")
            let frameProperties: [CFString: Any]
            let delay: Double
            if let source {
                guard let frame = CGImageSourceCreateImageAtIndex(source, index, nil),
                      CGImageSourceGetStatusAtIndex(source, index) == .statusComplete else { throw ImageProcessingError.invalidInput(sourceURL) }
                frameProperties = CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [CFString: Any] ?? [:]
                guard let frameDestination = CGImageDestinationCreateWithURL(input as CFURL, UTType.png.identifier as CFString, 1, nil) else {
                    throw ImageProcessingError.invalidOutput
                }
                let metadata = options.preserveMetadata ? frameProperties : [kCGImagePropertyOrientation: frameProperties[kCGImagePropertyOrientation] ?? 1]
                CGImageDestinationAddImage(frameDestination, frame, metadata as CFDictionary)
                guard CGImageDestinationFinalize(frameDestination) else { throw ImageProcessingError.invalidOutput }
                let timing = frameProperties[dictionary] as? [CFString: Any] ?? [:]
                guard let value = (timing[delayKey] ?? timing[clampedDelayKey]) as? Double else { throw ImageProcessingError.invalidInput(sourceURL) }
                delay = value
            } else {
                guard jxlDelays.count == summary.frameCount else { throw ImageProcessingError.invalidInput(sourceURL) }
                frameProperties = [:]
                delay = jxlDelays[index]
                _ = try await run(["copy", sourceURL.path + "[page=\(index),n=1,fail-on=error]", input.path + "[keep=\(options.preserveMetadata ? "all" : "icc")]"], in: work)
            }
            guard delay.isFinite, delay >= 0, delay * 1_000 <= 16_777_215 else { throw ImageProcessingError.invalidInput(sourceURL) }
            delays.append(Int((delay * 1_000).rounded()))
            let frameSummary = ImageFileSummary(width: summary.width, height: summary.height, frameCount: 1, fileSize: 0, format: .png, hasMetadata: false)
            let compressed = work.appendingPathComponent("frame-compressed.png")
            try await encode(input, summary: frameSummary, format: .png, options: options, output: compressed, work: work, stableCrop: true, overlay: overlay)
            if let destination {
                guard let compressedSource = CGImageSourceCreateWithURL(compressed as CFURL, nil),
                      // The frame file is overwritten on the next iteration; decode before ImageIO retains it.
                      let compressedFrame = CGImageSourceCreateImageAtIndex(compressedSource, 0, [kCGImageSourceShouldCacheImmediately: true] as CFDictionary) else { throw ImageProcessingError.invalidOutput }
                var savedProperties = options.preserveMetadata ? frameProperties : [:]
                savedProperties[kCGImagePropertyOrientation] = 1
                savedProperties[kCGImagePropertyPNGDictionary] = [kCGImagePropertyAPNGDelayTime: delay, kCGImagePropertyAPNGUnclampedDelayTime: delay]
                CGImageDestinationAddImage(destination, compressedFrame, savedProperties as CFDictionary)
            } else if format == .avif {
                let frame = work.appendingPathComponent("frame-\(index).png")
                try FileManager.default.copyItem(at: compressed, to: frame)
                frames.append(frame)
            } else {
                let frame = work.appendingPathComponent("frame-\(index).v")
                _ = try await run(["copy", compressed.path, frame.path], in: work)
                frames.append(frame)
            }
        }
        if let destination {
            guard CGImageDestinationFinalize(destination) else { throw ImageProcessingError.invalidOutput }
        } else if format == .avif {
            var arguments = ["--timescale", "1000", "--repetition-count", loop == 0 ? "infinite" : String(loop - 1),
                             "--qcolor", String(options.quality)]
            if !options.preserveMetadata { arguments += ["--ignore-exif", "--ignore-xmp"] }
            for (frame, delay) in zip(frames, delays) { arguments += ["--duration", String(delay), frame.path] }
            arguments += ["--output", output.path]
            _ = try await run(arguments, in: work, tool: "avifenc")
        } else {
            let stack = work.appendingPathComponent("animation.v")
            _ = try await run(["arrayjoin", frames.map(\.lastPathComponent).joined(separator: " "), stack.path, "--across=1"], in: work)
            let xml = try await run(["-f", "getext", stack.path], in: work, tool: "vipsheader")
            let document = try XMLDocument(data: xml.standardOutput)
            guard let meta = document.rootElement()?.elements(forName: "meta").first else { throw ImageProcessingError.invalidOutput }
            let dimensions = options.dimensions(for: summary)
            for (name, type, value) in [("page-height", "gint", String(dimensions.1)), ("n-pages", "gint", String(summary.frameCount)),
                                        ("loop", "gint", String(loop)), ("delay", "VipsArrayInt", delays.map(String.init).joined(separator: " "))] {
                for field in meta.elements(forName: "field") where field.attribute(forName: "name")?.stringValue == name { field.detach() }
                let field = XMLElement(name: "field", stringValue: value)
                field.addAttribute(XMLNode.attribute(withName: "name", stringValue: name) as! XMLNode)
                field.addAttribute(XMLNode.attribute(withName: "type", stringValue: type) as! XMLNode)
                meta.addChild(field)
            }
            _ = try await run(["--setext", stack.path], in: work, tool: "vipsedit", input: document.xmlData)
            _ = try await run(Self.saveArguments(stack, output: output, format: format, options: options), in: work)
        }
    }

    static func saveArguments(_ input: URL, output: URL, format: ImageOutputFormat, options: ImageProcessingOptions) throws -> [String] {
        let saver: String
        switch format {
        case .png: saver = "pngsave"
        case .jpeg: saver = "jpegsave"
        case .webp: saver = "webpsave"
        case .avif: saver = "heifsave"
        case .jpegXL: saver = "jxlsave"
        case .svg: throw ImageProcessingError.invalidOptions
        }
        var arguments = [saver, input.path, output.path, "--Q=\(options.quality)",
                         "--keep=\(options.preserveMetadata ? "all" : "icc")"]
        switch format {
        case .png: arguments += ["--palette", "--compression=9"]
        case .jpeg: arguments += ["--optimize-coding", "--interlace", "--background=\(options.backgroundChannels!)"]
        case .avif: arguments += ["--compression=av1"]
        case .webp, .jpegXL, .svg: break
        }
        return arguments
    }

    private static func nativeFormat(_ type: String?) -> ImageOutputFormat? {
        switch type {
        case UTType.png.identifier: .png
        case UTType.jpeg.identifier: .jpeg
        case UTType.webP.identifier: .webp
        case "public.avif", "public.avis": .avif
        case "public.jpeg-xl": .jpegXL
        default: nil
        }
    }

    private static func loaderFormat(_ loader: String?) -> ImageOutputFormat? {
        switch loader {
        case "pngload": .png
        case "jpegload": .jpeg
        case "webpload": .webp
        case "heifload": .avif
        case "jxlload": .jpegXL
        case "svgload": .svg
        default: nil
        }
    }

    private static func svgDocument(_ url: URL) throws -> XMLDocument {
        guard let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize, size <= 20 * 1_024 * 1_024 else {
            throw ImageProcessingError.resourceLimit
        }
        let data = try Data(contentsOf: url)
        guard let text = String(data: data, encoding: .utf8) else { throw ImageProcessingError.invalidInput(url) }
        // Reject external XML entities before parsing; SVG must stay entirely local.
        let upper = text.uppercased()
        guard !upper.contains("<!DOCTYPE"), !upper.contains("<!ENTITY") else {
            throw ImageProcessingError.invalidInput(url)
        }
        let document = try XMLDocument(data: data, options: .nodeLoadExternalEntitiesNever)
        guard document.rootElement()?.localName == "svg" else { throw ImageProcessingError.invalidInput(url) }
        let cssURLs = try NSRegularExpression(pattern: #"url\s*\(\s*['"]?([^)'"\s]+)"#, options: .caseInsensitive)
        func validateCSS(_ value: String) throws {
            guard !value.contains("\\"), !value.lowercased().contains("@import") else { throw ImageProcessingError.invalidInput(url) }
            for match in cssURLs.matches(in: value, range: NSRange(value.startIndex..., in: value)) {
                let reference = Range(match.range(at: 1), in: value).map { String(value[$0]) } ?? ""
                guard reference.hasPrefix("#") else { throw ImageProcessingError.invalidInput(url) }
            }
        }
        func validate(_ node: XMLNode) throws {
            guard node.kind != .processingInstruction else { throw ImageProcessingError.invalidInput(url) }
            if let element = node as? XMLElement {
                guard element.localName != "script", element.localName != "foreignObject" else { throw ImageProcessingError.invalidInput(url) }
                if element.localName == "style" { try validateCSS(element.stringValue ?? "") }
                for attribute in element.attributes ?? [] {
                    let name = attribute.localName?.lowercased() ?? ""
                    let value = attribute.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                    if name.hasPrefix("on") || name == "base" || (name == "href" && !value.hasPrefix("#")) {
                        throw ImageProcessingError.invalidInput(url)
                    }
                    try validateCSS(value)
                }
            }
            for child in node.children ?? [] { try validate(child) }
        }
        try validate(document)
        return document
    }
}
