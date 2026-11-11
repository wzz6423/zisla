import AppKit
import Combine
import Foundation
import ImageIO
import UniformTypeIdentifiers
import ZislaCore
import ZislaKit

enum ShelfContextAction: CaseIterable {
    case imagesToPDF
    case recognizeToQuickNote
    case editVideo

    var title: String {
        switch self {
        case .imagesToPDF: "图片转 PDF"
        case .recognizeToQuickNote: "识图并发送到随记"
        case .editVideo: "在录屏工作室中编辑"
        }
    }

    func supports(_ items: [FileShelfItem]) -> Bool {
        !items.isEmpty && items.allSatisfy { item in
            guard item.text == nil else { return false }
            let type = UTType(filenameExtension: item.url.pathExtension)
            switch self {
            case .imagesToPDF, .recognizeToQuickNote:
                return item.screenshotMetadata != nil || type?.conforms(to: .image) == true
            case .editVideo:
                return item.screenshotMetadata == nil && (type?.conforms(to: .movie) == true || type?.conforms(to: .video) == true)
            }
        }
    }
}

enum ShelfContextActionError: LocalizedError, Equatable {
    case unsupportedSelection
    case unavailableFile(String)
    case quickNoteUnavailable
    case studioUnavailable
    case noRecognizedText

    var errorDescription: String? {
        switch self {
        case .unsupportedSelection: AppLocalization.text("所选项目不支持此操作")
        case let .unavailableFile(name): AppLocalization.text("文件已失效或无法读取：%@", name)
        case .quickNoteUnavailable: AppLocalization.text("无法写入随记，请检查备忘录权限后重试")
        case .studioUnavailable: AppLocalization.text("录屏工作室当前不可用，请稍后重试")
        case .noRecognizedText: AppLocalization.text("未识别到文字")
        }
    }
}

@MainActor
final class ShelfContextActions: ObservableObject {
    @Published private(set) var isProcessing = false
    @Published private(set) var isCancellable = false
    @Published private(set) var message: String?
    @Published private(set) var generatedItemID: UUID?
    private(set) var task: Task<Void, Never>?
    var removeStagingDirectory: @Sendable (URL) throws -> Void = { try FileManager.default.removeItem(at: $0) }
    private let shelf: FileShelfStore
    private let temporaryDirectory: URL

    init(shelf: FileShelfStore, temporaryDirectory: URL = FileManager.default.temporaryDirectory) {
        self.shelf = shelf
        self.temporaryDirectory = temporaryDirectory
    }

    @discardableResult
    func perform(
        _ action: ShelfContextAction,
        items: [FileShelfItem],
        createQuickNote: @escaping @MainActor (String) async -> Bool,
        openStudio: @escaping @MainActor ([URL]) -> Bool,
        convertImages: @escaping @Sendable ([URL], URL) throws -> Void = {
            try PDFProcessingService().convertImagesToPDF($0, to: $1)
        },
        recognizeImage: @escaping @Sendable (CGImage, ScreenshotRecognitionOperation) async throws -> [ScreenshotRecognizedFragment] = {
            try await ScreenshotRecognitionWarmUp.shared.recognize($0, operation: $1)
        }
    ) -> Task<Void, Never>? {
        guard !isProcessing else { return nil }
        guard action.supports(items) else {
            message = ShelfContextActionError.unsupportedSelection.localizedDescription
            return nil
        }
        isProcessing = true
        generatedItemID = nil
        isCancellable = true
        message = AppLocalization.text("正在处理…")
        let operation = ScreenshotRecognitionOperation()
        task = Task { [self] in
            defer {
                isProcessing = false
                isCancellable = false
                task = nil
            }
            var staging: URL?
            do {
                try Task.checkCancellation()
                let urls = try Self.fileURLs(items, in: shelf)
                defer { urls.forEach(shelf.endAccessing) }
                switch action {
                case .imagesToPDF:
                    let directory = temporaryDirectory.appendingPathComponent("zisla-shelf-action-" + UUID().uuidString, isDirectory: true)
                    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false,
                        attributes: [.posixPermissions: 0o700])
                    staging = directory
                    let output = directory.appendingPathComponent("images.pdf")
                    let worker = Task.detached(priority: .userInitiated) {
                        try Task.checkCancellation()
                        try convertImages(urls, output)
                    }
                    try await withTaskCancellationHandler { try await worker.value } onCancel: { worker.cancel() }
                    try Task.checkCancellation()
                    guard shelf.importPromisedFile(at: output, from: directory) == 1 else {
                        throw CocoaError(.fileWriteUnknown, userInfo: [NSLocalizedDescriptionKey: shelf.errorDescription ?? ""])
                    }
                    generatedItemID = shelf.items.last?.id
                    message = AppLocalization.text("已加入 %ld 个项目", 1)
                case .recognizeToQuickNote:
                    let worker = Task.detached(priority: .userInitiated) {
                        var texts: [String] = []
                        for url in urls {
                            try operation.checkCancellation()
                            _ = try RecordingMediaImageStore.dimensions(of: url)
                            guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
                                  let image = CGImageSourceCreateImageAtIndex(source, 0,
                                    [kCGImageSourceShouldCacheImmediately: true] as CFDictionary) else {
                                throw ShelfContextActionError.unavailableFile(url.lastPathComponent)
                            }
                            let fragments = try await recognizeImage(image, operation)
                            try operation.checkCancellation()
                            let text = ScreenshotRecognitionFormatter.plainText(from: fragments)
                                .trimmingCharacters(in: .whitespacesAndNewlines)
                            guard !text.isEmpty else { throw ShelfContextActionError.noRecognizedText }
                            texts.append(text)
                        }
                        return texts.joined(separator: "\n\n")
                    }
                    let text = try await withTaskCancellationHandler { try await worker.value } onCancel: {
                        operation.cancel()
                        worker.cancel()
                    }
                    try Task.checkCancellation()
                    // Notes may commit while an AppleScript request is in flight, so cancellation ends before that boundary.
                    isCancellable = false
                    guard await createQuickNote(text) else { throw ShelfContextActionError.quickNoteUnavailable }
                    message = AppLocalization.text("已创建随记")
                case .editVideo:
                    try Task.checkCancellation()
                    guard openStudio(urls) else { throw ShelfContextActionError.studioUnavailable }
                    message = AppLocalization.text("已发送到录屏工作室")
                }
            } catch {
                message = error is CancellationError
                    ? AppLocalization.text("已取消操作")
                    : AppLocalization.text("操作失败：%@", error.localizedDescription)
            }
            if let staging {
                try? removeStagingDirectory(staging)
            }
        }
        return task
    }

    func cancel() {
        guard isCancellable else { return }
        task?.cancel()
    }

    static func fileURLs(_ items: [FileShelfItem], in shelf: FileShelfStore, requiresRegularFile: Bool = true) throws -> [URL] {
        var urls: [URL] = []
        do {
            for item in items {
                let url: URL
                if item.screenshotMetadata != nil {
                    url = try shelf.screenshotFileURL(id: item.id)
                    _ = url.startAccessingSecurityScopedResource()
                } else { url = shelf.beginAccessing(item) }
                urls.append(url)
                guard url.isFileURL,
                      FileManager.default.fileExists(atPath: url.path),
                      (!requiresRegularFile || (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true),
                      FileManager.default.isReadableFile(atPath: url.path) else {
                    throw ShelfContextActionError.unavailableFile(item.displayName)
                }
            }
            return urls
        } catch {
            urls.forEach(shelf.endAccessing)
            throw error
        }
    }
}
