import AppKit
import CoreText
import Foundation
import PDFKit

public struct PDFDocumentSummary: Equatable, Sendable {
    public let pageCount: Int
    public let fileSize: UInt64
    public let isEncrypted: Bool
    public let isLocked: Bool

    public init(pageCount: Int, fileSize: UInt64, isEncrypted: Bool, isLocked: Bool) {
        self.pageCount = pageCount
        self.fileSize = fileSize
        self.isEncrypted = isEncrypted
        self.isLocked = isLocked
    }
}

public struct PDFDocumentMetadata: Equatable, Sendable {
    public var title: String?
    public var author: String?
    public var subject: String?
    public var creator: String?
    public var keywords: [String]?

    public init(
        title: String? = nil,
        author: String? = nil,
        subject: String? = nil,
        creator: String? = nil,
        keywords: [String]? = nil
    ) {
        self.title = title
        self.author = author
        self.subject = subject
        self.creator = creator
        self.keywords = keywords
    }
}

public struct PDFPasswordProtection: Equatable, Sendable {
    public let userPassword: String
    public let ownerPassword: String

    public init(userPassword: String, ownerPassword: String) {
        self.userPassword = userPassword
        self.ownerPassword = ownerPassword
    }
}

public enum PDFProcessingError: LocalizedError, Equatable, Sendable {
    case invalidInput(URL)
    case invalidDocument(URL)
    case lockedDocument(URL)
    case invalidPageIndex(Int)
    case invalidRotation(Int)
    case invalidPageSelection(String)
    case emptyPageSelection
    case duplicateOutput(URL)
    case outputAlreadyExists(URL)
    case outputMatchesInput(URL)
    case cannotCreateOutputDirectory(String)
    case cannotWriteOutput(URL)
    case cannotRenderPage(Int)
    case unsupportedImage(URL)
    case invalidCropBox(CGRect)
    case invalidWatermarkScale(CGFloat)
    case invalidPassword
    case incorrectPassword

    public var errorDescription: String? {
        switch self {
        case let .invalidInput(url): "不是可访问的本地 PDF 文件：\(url.lastPathComponent)"
        case let .invalidDocument(url): "无法读取 PDF：\(url.lastPathComponent)"
        case let .lockedDocument(url): "PDF 已加密且尚未解锁：\(url.lastPathComponent)"
        case let .invalidPageIndex(index): "页码 \(index + 1) 超出文档范围"
        case let .invalidRotation(degrees): "旋转角度必须是 90 度的整数倍：\(degrees)"
        case let .invalidPageSelection(selection): "页码范围无效：\(selection)"
        case .emptyPageSelection: "至少需要选择一页"
        case let .duplicateOutput(url): "同一任务不能重复使用输出文件：\(url.lastPathComponent)"
        case let .outputAlreadyExists(url): "输出文件已存在，未覆盖：\(url.lastPathComponent)"
        case let .outputMatchesInput(url): "输出文件不能覆盖输入文件：\(url.lastPathComponent)"
        case let .cannotCreateOutputDirectory(message): "无法创建输出目录：\(message)"
        case let .cannotWriteOutput(url): "无法写入 PDF：\(url.lastPathComponent)"
        case let .cannotRenderPage(index): "无法渲染第 \(index + 1) 页"
        case let .unsupportedImage(url): "无法读取图片：\(url.lastPathComponent)"
        case let .invalidCropBox(rect): "裁剪区域无效：\(rect)"
        case let .invalidWatermarkScale(scale): "水印缩放比例无效：\(scale)"
        case .invalidPassword: "用户密码和所有者密码均不能为空"
        case .incorrectPassword: "PDF 密码不正确"
        }
    }
}

public enum PDFRasterImageFormat: String, CaseIterable, Sendable {
    case png
    case jpeg

    fileprivate var fileExtension: String { rawValue == "jpeg" ? "jpg" : rawValue }
}

public struct PDFTextWatermark: Equatable, Sendable {
    public var text: String
    public var fontSize: CGFloat
    public var opacity: CGFloat
    public var rotationDegrees: CGFloat

    public init(
        text: String,
        fontSize: CGFloat = 42,
        opacity: CGFloat = 0.22,
        rotationDegrees: CGFloat = -35
    ) {
        self.text = text
        self.fontSize = fontSize
        self.opacity = opacity
        self.rotationDegrees = rotationDegrees
    }
}

public enum PDFOverlayPosition: Equatable, Sendable {
    case topLeading
    case top
    case topTrailing
    case leading
    case center
    case trailing
    case bottomLeading
    case bottom
    case bottomTrailing
}

public struct PDFPageNumberStyle: Equatable, Sendable {
    public var prefix: String
    public var suffix: String
    public var fontSize: CGFloat
    public var position: PDFOverlayPosition
    public var inset: CGFloat

    public init(
        prefix: String = "",
        suffix: String = "",
        fontSize: CGFloat = 11,
        position: PDFOverlayPosition = .bottom,
        inset: CGFloat = 24
    ) {
        self.prefix = prefix
        self.suffix = suffix
        self.fontSize = fontSize
        self.position = position
        self.inset = inset
    }
}

/// Performs basic page operations with macOS PDFKit, requiring no external service.
public struct PDFProcessingService: Sendable {
    public init() {}

    public func inspect(_ inputURL: URL) throws -> PDFDocumentSummary {
        let document = try openDocument(at: inputURL)
        let attributes = try? FileManager.default.attributesOfItem(atPath: inputURL.path)
        let size = (attributes?[.size] as? NSNumber)?.uint64Value ?? 0
        return PDFDocumentSummary(
            pageCount: document.pageCount,
            fileSize: size,
            isEncrypted: document.isEncrypted,
            isLocked: document.isLocked
        )
    }

    /// Parses a 1-based page range such as `1-3,5`. The result preserves the order the user chose and deduplicates automatically.
    public func pageIndexes(in inputURL: URL, matching selection: String) throws -> [Int] {
        let document = try loadDocument(at: inputURL)
        let original = selection.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmed = Self.normalizedSelection(original)
        guard !trimmed.isEmpty else { throw PDFProcessingError.emptyPageSelection }

        var indexes: [Int] = []
        for component in trimmed.split(separator: ",", omittingEmptySubsequences: false) {
            let part = component.trimmingCharacters(in: .whitespaces)
            let bounds = part.split(separator: "-", omittingEmptySubsequences: false)
                .map { $0.trimmingCharacters(in: .whitespaces) }
            let range: ClosedRange<Int>
            switch bounds.count {
            case 1:
                guard let page = Int(bounds[0]), page > 0 else {
                    throw PDFProcessingError.invalidPageSelection(original)
                }
                range = page...page
            case 2:
                guard let first = Int(bounds[0]), let last = Int(bounds[1]), first > 0, first <= last else {
                    throw PDFProcessingError.invalidPageSelection(original)
                }
                range = first...last
            default:
                throw PDFProcessingError.invalidPageSelection(original)
            }
            guard range.upperBound <= document.pageCount else {
                throw PDFProcessingError.invalidPageSelection(original)
            }
            indexes.append(contentsOf: range.map { $0 - 1 })
        }
        var seen = Set<Int>()
        return indexes.filter { seen.insert($0).inserted }
    }

    /// A Chinese keyboard yields fullwidth digits and separators that look identical to the ASCII ones the
    /// placeholder asks for, so accept them instead of rejecting input the user cannot tell apart.
    private static let separatorAliases: [Character: Character] = [
        "、": ",", "；": ",", ";": ",",
        "–": "-", "—": "-", "~": "-", "至": "-",
    ]

    private static func normalizedSelection(_ selection: String) -> String {
        let halfwidth = selection.applyingTransform(.fullwidthToHalfwidth, reverse: false) ?? selection
        return String(halfwidth.map { separatorAliases[$0] ?? $0 })
    }

    public func extractText(
        from inputURL: URL,
        pageIndexes: [Int]? = nil
    ) throws -> String {
        let document = try loadDocument(at: inputURL)
        let indexes = pageIndexes ?? Array(0..<document.pageCount)
        var pages: [String] = []
        for pageIndex in indexes {
            guard let page = document.page(at: pageIndex) else {
                throw PDFProcessingError.invalidPageIndex(pageIndex)
            }
            pages.append(page.string ?? "")
        }
        return pages.joined(separator: "\n\n")
    }

    public func exportText(
        from inputURL: URL,
        pageIndexes: [Int]? = nil,
        outputURL: URL
    ) throws {
        let text = try extractText(from: inputURL, pageIndexes: pageIndexes)
        try prepareOutput(outputURL, inputURLs: [inputURL])
        do {
            try text.write(to: outputURL, atomically: true, encoding: .utf8)
        } catch {
            throw PDFProcessingError.cannotWriteOutput(outputURL)
        }
    }

    public func metadata(for inputURL: URL) throws -> PDFDocumentMetadata {
        let attributes = try loadDocument(at: inputURL).documentAttributes ?? [:]
        return PDFDocumentMetadata(
            title: attributes[AnyHashable(PDFDocumentAttribute.titleAttribute)] as? String,
            author: attributes[AnyHashable(PDFDocumentAttribute.authorAttribute)] as? String,
            subject: attributes[AnyHashable(PDFDocumentAttribute.subjectAttribute)] as? String,
            creator: attributes[AnyHashable(PDFDocumentAttribute.creatorAttribute)] as? String,
            keywords: attributes[AnyHashable(PDFDocumentAttribute.keywordsAttribute)] as? [String]
        )
    }

    public func updateMetadata(
        of inputURL: URL,
        metadata: PDFDocumentMetadata,
        outputURL: URL
    ) throws {
        let document = try loadDocument(at: inputURL)
        var attributes = document.documentAttributes ?? [:]
        set(metadata.title, for: .titleAttribute, in: &attributes)
        set(metadata.author, for: .authorAttribute, in: &attributes)
        set(metadata.subject, for: .subjectAttribute, in: &attributes)
        set(metadata.creator, for: .creatorAttribute, in: &attributes)
        set(metadata.keywords, for: .keywordsAttribute, in: &attributes)
        document.documentAttributes = attributes
        try prepareOutput(outputURL, inputURLs: [inputURL])
        try write(document, to: outputURL)
    }

    public func protect(
        _ inputURL: URL,
        with protection: PDFPasswordProtection,
        outputURL: URL
    ) throws {
        guard !protection.userPassword.isEmpty || !protection.ownerPassword.isEmpty else {
            throw PDFProcessingError.invalidPassword
        }
        let document = try loadDocument(at: inputURL)
        try prepareOutput(outputURL, inputURLs: [inputURL])
        var options: [PDFDocumentWriteOption: Any] = [
            .ownerPasswordOption: protection.ownerPassword,
        ]
        if !protection.userPassword.isEmpty {
            options[.userPasswordOption] = protection.userPassword
        }
        try write(document, to: outputURL, with: options)
    }

    public func unlock(
        _ inputURL: URL,
        password: String,
        outputURL: URL
    ) throws {
        let document = try openDocument(at: inputURL)
        guard document.isLocked else {
            throw PDFProcessingError.invalidDocument(inputURL)
        }
        guard document.unlock(withPassword: password) else {
            throw PDFProcessingError.incorrectPassword
        }
        let output = try copiedPages(from: document, pageIndexes: Array(0..<document.pageCount))
        try prepareOutput(outputURL, inputURLs: [inputURL])
        try write(output, to: outputURL)
    }

    public func merge(_ inputURLs: [URL], to outputURL: URL) throws {
        guard !inputURLs.isEmpty else { throw PDFProcessingError.emptyPageSelection }
        let documents = try inputURLs.map(loadDocument(at:))
        try prepareOutput(outputURL, inputURLs: inputURLs)

        let merged = PDFDocument()
        for document in documents {
            for pageIndex in 0..<document.pageCount {
                guard let page = document.page(at: pageIndex) else {
                    throw PDFProcessingError.invalidPageIndex(pageIndex)
                }
                merged.insert(page, at: merged.pageCount)
            }
        }
        try write(merged, to: outputURL)
    }

    public func exportPages(
        from inputURL: URL,
        pageIndexes: [Int],
        to outputURL: URL
    ) throws {
        guard !pageIndexes.isEmpty else { throw PDFProcessingError.emptyPageSelection }
        let input = try loadDocument(at: inputURL)
        _ = try copiedPages(from: input, pageIndexes: pageIndexes)
        try prepareOutput(outputURL, inputURLs: [inputURL])
        let output = try copiedPages(from: input, pageIndexes: pageIndexes)
        try write(output, to: outputURL)
    }

    public func split(
        _ inputURL: URL,
        pageGroups: [[Int]],
        outputURLs: [URL]
    ) throws {
        guard pageGroups.count == outputURLs.count, !pageGroups.isEmpty else {
            throw PDFProcessingError.emptyPageSelection
        }
        let input = try loadDocument(at: inputURL)
        let normalizedOutputs = outputURLs.map(\.standardizedFileURL)
        guard Set(normalizedOutputs).count == normalizedOutputs.count else {
            let duplicate = Dictionary(grouping: normalizedOutputs, by: { $0 })
                .first(where: { $0.value.count > 1 })?.key ?? normalizedOutputs[0]
            throw PDFProcessingError.duplicateOutput(duplicate)
        }
        for (group, outputURL) in zip(pageGroups, outputURLs) {
            guard !group.isEmpty else { throw PDFProcessingError.emptyPageSelection }
            _ = try copiedPages(from: input, pageIndexes: group)
            try prepareOutput(outputURL, inputURLs: [inputURL])
        }

        for (group, outputURL) in zip(pageGroups, outputURLs) {
            let output = try copiedPages(from: input, pageIndexes: group)
            try write(output, to: outputURL)
        }
    }

    public func rotate(
        _ inputURL: URL,
        pageIndexes: [Int],
        degrees: Int,
        to outputURL: URL
    ) throws {
        guard !pageIndexes.isEmpty else { throw PDFProcessingError.emptyPageSelection }
        guard degrees.isMultiple(of: 90) else {
            throw PDFProcessingError.invalidRotation(degrees)
        }
        let input = try loadDocument(at: inputURL)
        let output = try copiedPages(from: input, pageIndexes: Array(0..<input.pageCount))

        for pageIndex in pageIndexes {
            guard let page = output.page(at: pageIndex) else {
                throw PDFProcessingError.invalidPageIndex(pageIndex)
            }
            page.rotation = normalizedRotation(page.rotation + degrees)
        }
        try prepareOutput(outputURL, inputURLs: [inputURL])
        try write(output, to: outputURL)
    }

    /// Sets each page's crop box; does not rasterize the existing page content.
    public func crop(
        _ inputURL: URL,
        pageIndexes: [Int],
        to cropBox: CGRect,
        outputURL: URL
    ) throws {
        guard !pageIndexes.isEmpty, cropBox.width > 0, cropBox.height > 0 else {
            throw PDFProcessingError.emptyPageSelection
        }
        let input = try loadDocument(at: inputURL)
        let output = try copiedPages(from: input, pageIndexes: Array(0..<input.pageCount))
        for pageIndex in pageIndexes {
            guard let page = output.page(at: pageIndex) else {
                throw PDFProcessingError.invalidPageIndex(pageIndex)
            }
            guard page.bounds(for: .mediaBox).contains(cropBox) else {
                throw PDFProcessingError.invalidCropBox(cropBox)
            }
            page.setBounds(cropBox, for: .cropBox)
        }
        try prepareOutput(outputURL, inputURLs: [inputURL])
        try write(output, to: outputURL)
    }

    /// Converts images into a multi-page PDF in input order, one page per image.
    public func convertImagesToPDF(_ imageURLs: [URL], to outputURL: URL) throws {
        guard !imageURLs.isEmpty else { throw PDFProcessingError.emptyPageSelection }
        let images = try imageURLs.map(loadImage(at:))
        try prepareOutput(outputURL, inputURLs: imageURLs)

        var firstBox = CGRect(origin: .zero, size: CGSize(width: images[0].width, height: images[0].height))
        guard let context = CGContext(outputURL as CFURL, mediaBox: &firstBox, nil) else {
            throw PDFProcessingError.cannotWriteOutput(outputURL)
        }
        defer { context.closePDF() }

        for image in images {
            var box = CGRect(origin: .zero, size: CGSize(width: image.width, height: image.height))
            let pageInfo = [
                kCGPDFContextMediaBox as String: Data(bytes: &box, count: MemoryLayout<CGRect>.size),
            ] as CFDictionary
            context.beginPDFPage(pageInfo)
            context.interpolationQuality = .high
            context.draw(image, in: box)
            context.endPDFPage()
        }
    }

    /// Rasterizes every page to PNG or JPEG. Returned file names carry a page number starting at 001.
    public func renderPages(
        from inputURL: URL,
        to outputDirectory: URL,
        format: PDFRasterImageFormat = .png,
        dpi: Int = 144
    ) throws -> [URL] {
        guard dpi > 0 else { throw PDFProcessingError.invalidRotation(dpi) }
        let document = try loadDocument(at: inputURL)
        let normalizedDirectory = outputDirectory.standardizedFileURL
        try FileManager.default.createDirectory(at: normalizedDirectory, withIntermediateDirectories: true)

        let baseName = inputURL.deletingPathExtension().lastPathComponent
        let outputs = (0..<document.pageCount).map { index in
            normalizedDirectory.appendingPathComponent(
                "\(baseName)-\(String(format: "%03d", index + 1)).\(format.fileExtension)"
            )
        }
        for output in outputs where FileManager.default.fileExists(atPath: output.path) {
            throw PDFProcessingError.outputAlreadyExists(output)
        }

        for (index, outputURL) in outputs.enumerated() {
            guard let page = document.page(at: index) else {
                throw PDFProcessingError.cannotRenderPage(index)
            }
            let bounds = page.bounds(for: .mediaBox)
            let scale = CGFloat(dpi) / 72
            let thumbnail = page.thumbnail(
                of: NSSize(width: max(1, bounds.width * scale), height: max(1, bounds.height * scale)),
                for: .mediaBox
            )
            guard let data = rasterData(from: thumbnail, format: format) else {
                throw PDFProcessingError.cannotRenderPage(index)
            }
            try data.write(to: outputURL, options: .atomic)
        }
        return outputs
    }

    /// Draws the text directly onto each page's content, avoiding reliance on a removable annotation overlay.
    public func addTextWatermark(
        to inputURL: URL,
        watermark: PDFTextWatermark,
        outputURL: URL
    ) throws {
        guard !watermark.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw PDFProcessingError.emptyPageSelection
        }
        let document = try loadDocument(at: inputURL)
        try prepareOutput(outputURL, inputURLs: [inputURL])
        guard let firstPage = document.page(at: 0) else {
            throw PDFProcessingError.invalidDocument(inputURL)
        }
        var firstBox = firstPage.bounds(for: .mediaBox)
        guard let context = CGContext(outputURL as CFURL, mediaBox: &firstBox, nil) else {
            throw PDFProcessingError.cannotWriteOutput(outputURL)
        }
        defer { context.closePDF() }

        for pageIndex in 0..<document.pageCount {
            guard let page = document.page(at: pageIndex) else {
                throw PDFProcessingError.invalidPageIndex(pageIndex)
            }
            var pageBox = page.bounds(for: .mediaBox)
            let pageInfo = [
                kCGPDFContextMediaBox as String: Data(bytes: &pageBox, count: MemoryLayout<CGRect>.size),
            ] as CFDictionary
            context.beginPDFPage(pageInfo)
            page.draw(with: .mediaBox, to: context)
            draw(watermark, in: pageBox, context: context)
            context.endPDFPage()
        }
    }

    public func addImageWatermark(
        to inputURL: URL,
        imageURL: URL,
        position: PDFOverlayPosition = .center,
        scale: CGFloat = 0.25,
        opacity: CGFloat = 0.3,
        outputURL: URL
    ) throws {
        guard scale > 0, scale <= 1 else { throw PDFProcessingError.invalidWatermarkScale(scale) }
        let document = try loadDocument(at: inputURL)
        let image = try loadImage(at: imageURL)
        try prepareOutput(outputURL, inputURLs: [inputURL, imageURL])
        guard let firstPage = document.page(at: 0) else {
            throw PDFProcessingError.invalidDocument(inputURL)
        }
        var firstBox = firstPage.bounds(for: .mediaBox)
        guard let context = CGContext(outputURL as CFURL, mediaBox: &firstBox, nil) else {
            throw PDFProcessingError.cannotWriteOutput(outputURL)
        }
        defer { context.closePDF() }

        for pageIndex in 0..<document.pageCount {
            guard let page = document.page(at: pageIndex) else {
                throw PDFProcessingError.invalidPageIndex(pageIndex)
            }
            var pageBox = page.bounds(for: .mediaBox)
            let pageInfo = [
                kCGPDFContextMediaBox as String: Data(bytes: &pageBox, count: MemoryLayout<CGRect>.size),
            ] as CFDictionary
            context.beginPDFPage(pageInfo)
            page.draw(with: .mediaBox, to: context)
            context.saveGState()
            context.setAlpha(min(max(opacity, 0), 1))
            context.draw(image, in: imageRect(image, in: pageBox, position: position, scale: scale))
            context.restoreGState()
            context.endPDFPage()
        }
    }

    public func addPageNumbers(
        to inputURL: URL,
        style: PDFPageNumberStyle = PDFPageNumberStyle(),
        outputURL: URL
    ) throws {
        guard style.fontSize > 0 else { throw PDFProcessingError.invalidWatermarkScale(style.fontSize) }
        let document = try loadDocument(at: inputURL)
        try prepareOutput(outputURL, inputURLs: [inputURL])
        guard let firstPage = document.page(at: 0) else {
            throw PDFProcessingError.invalidDocument(inputURL)
        }
        var firstBox = firstPage.bounds(for: .mediaBox)
        guard let context = CGContext(outputURL as CFURL, mediaBox: &firstBox, nil) else {
            throw PDFProcessingError.cannotWriteOutput(outputURL)
        }
        defer { context.closePDF() }

        for pageIndex in 0..<document.pageCount {
            guard let page = document.page(at: pageIndex) else {
                throw PDFProcessingError.invalidPageIndex(pageIndex)
            }
            var pageBox = page.bounds(for: .mediaBox)
            let pageInfo = [
                kCGPDFContextMediaBox as String: Data(bytes: &pageBox, count: MemoryLayout<CGRect>.size),
            ] as CFDictionary
            context.beginPDFPage(pageInfo)
            page.draw(with: .mediaBox, to: context)
            drawPageNumber(
                "\(style.prefix)\(pageIndex + 1)\(style.suffix)",
                in: pageBox,
                style: style,
                context: context
            )
            context.endPDFPage()
        }
    }

    private func loadDocument(at url: URL) throws -> PDFDocument {
        let normalizedURL = url.standardizedFileURL
        let document = try openDocument(at: normalizedURL)
        guard !document.isLocked else {
            throw PDFProcessingError.lockedDocument(normalizedURL)
        }
        return document
    }

    private func openDocument(at url: URL) throws -> PDFDocument {
        let normalizedURL = url.standardizedFileURL
        guard normalizedURL.isFileURL,
              FileManager.default.fileExists(atPath: normalizedURL.path)
        else {
            throw PDFProcessingError.invalidInput(normalizedURL)
        }
        guard let document = PDFDocument(url: normalizedURL), document.pageCount > 0 else {
            throw PDFProcessingError.invalidDocument(normalizedURL)
        }
        return document
    }

    private func copiedPages(from input: PDFDocument, pageIndexes: [Int]) throws -> PDFDocument {
        let output = PDFDocument()
        output.documentAttributes = input.documentAttributes
        for pageIndex in pageIndexes {
            guard let page = input.page(at: pageIndex) else {
                throw PDFProcessingError.invalidPageIndex(pageIndex)
            }
            output.insert(page, at: output.pageCount)
        }
        return output
    }

    private func prepareOutput(_ outputURL: URL, inputURLs: [URL]) throws {
        let normalizedOutput = outputURL.standardizedFileURL
        guard normalizedOutput.isFileURL else {
            throw PDFProcessingError.invalidInput(normalizedOutput)
        }
        if inputURLs.map(\.standardizedFileURL).contains(normalizedOutput) {
            throw PDFProcessingError.outputMatchesInput(normalizedOutput)
        }
        guard !FileManager.default.fileExists(atPath: normalizedOutput.path) else {
            throw PDFProcessingError.outputAlreadyExists(normalizedOutput)
        }
        do {
            try FileManager.default.createDirectory(
                at: normalizedOutput.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
        } catch {
            throw PDFProcessingError.cannotCreateOutputDirectory(error.localizedDescription)
        }
    }

    private func write(_ document: PDFDocument, to outputURL: URL) throws {
        try write(document, to: outputURL, with: [:])
    }

    private func write(
        _ document: PDFDocument,
        to outputURL: URL,
        with options: [PDFDocumentWriteOption: Any]
    ) throws {
        guard document.write(to: outputURL, withOptions: options) else {
            try? FileManager.default.removeItem(at: outputURL)
            throw PDFProcessingError.cannotWriteOutput(outputURL)
        }
    }

    private func set(
        _ value: Any?,
        for key: PDFDocumentAttribute,
        in attributes: inout [AnyHashable: Any]
    ) {
        guard let value else { return }
        attributes[AnyHashable(key)] = value
    }

    private func imageRect(
        _ image: CGImage,
        in pageBox: CGRect,
        position: PDFOverlayPosition,
        scale: CGFloat
    ) -> CGRect {
        let maxSide = min(pageBox.width, pageBox.height) * scale
        let aspectRatio = CGFloat(image.width) / CGFloat(image.height)
        let size = aspectRatio >= 1
            ? CGSize(width: maxSide, height: maxSide / aspectRatio)
            : CGSize(width: maxSide * aspectRatio, height: maxSide)
        return CGRect(origin: overlayOrigin(for: size, in: pageBox, position: position, inset: 24), size: size)
    }

    private func drawPageNumber(
        _ text: String,
        in pageBox: CGRect,
        style: PDFPageNumberStyle,
        context: CGContext
    ) {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: style.fontSize, weight: .medium),
            .foregroundColor: NSColor.black,
        ]
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: attributes))
        let bounds = CTLineGetBoundsWithOptions(line, .useOpticalBounds)
        let origin = overlayOrigin(
            for: CGSize(width: bounds.width, height: bounds.height),
            in: pageBox,
            position: style.position,
            inset: style.inset
        )
        context.saveGState()
        context.textPosition = CGPoint(x: origin.x - bounds.minX, y: origin.y - bounds.minY)
        CTLineDraw(line, context)
        context.restoreGState()
    }

    private func overlayOrigin(
        for size: CGSize,
        in pageBox: CGRect,
        position: PDFOverlayPosition,
        inset: CGFloat
    ) -> CGPoint {
        let horizontal: CGFloat = switch position {
        case .topLeading, .leading, .bottomLeading:
            pageBox.minX + inset
        case .top, .center, .bottom:
            pageBox.midX - size.width / 2
        case .topTrailing, .trailing, .bottomTrailing:
            pageBox.maxX - inset - size.width
        }
        let vertical: CGFloat = switch position {
        case .topLeading, .top, .topTrailing:
            pageBox.maxY - inset - size.height
        case .leading, .center, .trailing:
            pageBox.midY - size.height / 2
        case .bottomLeading, .bottom, .bottomTrailing:
            pageBox.minY + inset
        }
        return CGPoint(x: horizontal, y: vertical)
    }

    private func loadImage(at url: URL) throws -> CGImage {
        let normalizedURL = url.standardizedFileURL
        guard normalizedURL.isFileURL,
              let image = NSImage(contentsOf: normalizedURL),
              let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil)
        else {
            throw PDFProcessingError.unsupportedImage(normalizedURL)
        }
        return cgImage
    }

    private func rasterData(from image: NSImage, format: PDFRasterImageFormat) -> Data? {
        guard let representation = NSBitmapImageRep(data: image.tiffRepresentation ?? Data()) else {
            return nil
        }
        return switch format {
        case .png:
            representation.representation(using: .png, properties: [:])
        case .jpeg:
            representation.representation(
                using: .jpeg,
                properties: [.compressionFactor: 0.9]
            )
        }
    }

    private func draw(_ watermark: PDFTextWatermark, in pageBox: CGRect, context: CGContext) {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.boldSystemFont(ofSize: watermark.fontSize),
            .foregroundColor: NSColor.black,
        ]
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: watermark.text, attributes: attributes))
        let bounds = CTLineGetBoundsWithOptions(line, .useOpticalBounds)
        context.saveGState()
        context.setAlpha(min(max(watermark.opacity, 0), 1))
        context.translateBy(x: pageBox.midX, y: pageBox.midY)
        context.rotate(by: watermark.rotationDegrees * .pi / 180)
        context.textPosition = CGPoint(x: -bounds.width / 2, y: -bounds.midY)
        CTLineDraw(line, context)
        context.restoreGState()
    }

    private func normalizedRotation(_ degrees: Int) -> Int {
        let normalized = degrees % 360
        return normalized >= 0 ? normalized : normalized + 360
    }
}
