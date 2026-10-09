import AppKit
import Combine
import Foundation
import ImageIO
import zlib
import UniformTypeIdentifiers
import ZislaCore

public enum FileShelfCategory: String, CaseIterable, Hashable, Identifiable, Sendable {
    case all = "全部"
    case note = "便签"
    case screenshot = "暂存截图"
    case folder = "文件夹"
    case image = "图片"
    case url = "URL"
    case path = "路径"
    case video = "视频"
    case audio = "音频"
    case text = "文本"
    case document = "文档"
    case archive = "压缩包"
    case code = "代码"
    case other = "其他"

    public var id: String { rawValue }

    /// Raw values are persisted in the clipboard database, so localize only the display label.
    public var title: String { AppLocalization.text(rawValue) }

    public var symbol: String {
        switch self {
        case .all: return "square.grid.2x2"
        case .note: return "note.text"
        case .screenshot: return "camera"
        case .folder: return "folder"
        case .image: return "photo"
        case .url: return "link"
        case .path: return "arrow.turn.down.right"
        case .video: return "video"
        case .audio: return "music.note"
        case .document: return "doc.text"
        case .archive: return "archivebox"
        case .code: return "chevron.left.forwardslash.chevron.right"
        case .text: return "text.alignleft"
        case .other: return "doc.questionmark"
        }
    }

    public static let fileShelfCases = allCases.filter { $0 != .path }
    public static let clipboardCases = allCases.filter { $0 != .note && $0 != .screenshot }
}

public struct FileShelfItem: Identifiable, Equatable {
    public var id: UUID
    public var url: URL
    public var addedAt: Date
    public var bookmarkData: Data
    public var text: String?
    public var isManaged: Bool
    public var noteLocation: ContextNoteLocation?
    public var screenshotMetadata: ShelfScreenshotMetadata?

    public init(id: UUID, url: URL, addedAt: Date, bookmarkData: Data, text: String? = nil, isManaged: Bool = false, noteLocation: ContextNoteLocation? = nil, screenshotMetadata: ShelfScreenshotMetadata? = nil) {
        self.id = id
        self.url = url
        self.addedAt = addedAt
        self.bookmarkData = bookmarkData
        self.text = text
        self.isManaged = isManaged
        self.noteLocation = noteLocation
        self.screenshotMetadata = screenshotMetadata
    }

    public var linkURL: URL? { text.flatMap(TransferPasteboard.webURL) }

    public var payload: TransferPasteboardPayload {
        text.map(TransferPasteboardPayload.text) ?? .file(url)
    }

    public var displayName: String {
        if let metadata = screenshotMetadata {
            return [AppLocalization.text(metadata.isLongScreenshot ? "长截图" : "截图"),
                    metadata.source.applicationName, metadata.source.capturedAt.formatted()]
                .compactMap { $0 }.joined(separator: " · ")
        }
        return text.map { String($0.trimmingCharacters(in: .whitespacesAndNewlines).prefix(120)) }
            ?? url.lastPathComponent
    }

    public var searchText: String {
        guard let metadata = screenshotMetadata else { return text ?? url.lastPathComponent }
        return [displayName, metadata.source.bundleIdentifier,
                metadata.source.processIdentifier.map(String.init),
                metadata.source.capturedAt.ISO8601Format(),
                "\(metadata.pixelWidth)×\(metadata.pixelHeight)"]
            .compactMap { $0 }.joined(separator: " ")
    }

    public var category: FileShelfCategory {
        if screenshotMetadata != nil { return .screenshot }
        if noteLocation != nil { return .note }
        if text != nil { return linkURL == nil ? .text : .url }
        var isDirectory: ObjCBool = false
        if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory),
           isDirectory.boolValue {
            return .folder
        }

        guard let contentType = try? url.resourceValues(forKeys: [.contentTypeKey]).contentType else {
            return .other
        }

        if contentType.conforms(to: .image) {
            return .image
        } else if contentType.conforms(to: .movie) || contentType.conforms(to: .video) {
            return .video
        } else if contentType.conforms(to: .audio) {
            return .audio
        } else if contentType.conforms(to: .archive) || contentType.conforms(to: .zip) {
            return .archive
        } else if contentType.conforms(to: .sourceCode) || contentType.conforms(to: .script) {
            return .code
        } else if contentType.conforms(to: .text) || contentType.conforms(to: .pdf) ||
                  contentType.conforms(to: .spreadsheet) || contentType.conforms(to: .presentation) {
            return .document
        }

        return .other
    }
}

@MainActor
public final class FileShelfStore: ObservableObject {
    @Published public private(set) var items: [FileShelfItem] = []
    @Published public fileprivate(set) var errorDescription: String?

    private struct StoredItem: Codable {
        var id: UUID
        var bookmarkData: Data
        var addedAt: Date
        var url: URL?
        var text: String?
        var isManaged: Bool?
        var noteLocation: ContextNoteLocation?
        var shelfOrder: Int64?
    }

    private let storageURL: URL
    private let screenshotDatabase: ShelfScreenshotDatabase
    // Notes can be backdated, so insertion order must not depend on capture or creation dates.
    private var shelfOrder: [UUID: Int64] = [:]
    var managedDirectory: URL { storageURL.deletingPathExtension().appendingPathExtension("items") }

    public init(storageURL: URL = AppPaths.fileShelf) {
        self.storageURL = storageURL
        screenshotDatabase = ShelfScreenshotDatabase(directory: storageURL.deletingPathExtension().appendingPathExtension("screenshots"))
        load()
        loadScreenshots()
    }

    /// A database commit is durable; drag and share files are recoverable caches.
    @discardableResult
    public func stashScreenshot(png: Data, metadata: ShelfScreenshotMetadata) throws -> FileShelfItem {
        let dimensions = try Self.screenshotDimensions(png)
        guard dimensions.width == metadata.pixelWidth, dimensions.height == metadata.pixelHeight else {
            throw CocoaError(.fileReadCorruptFile)
        }
        let record = ShelfScreenshotRecord(id: UUID(), addedAt: Date(), shelfOrder: try nextShelfOrder(),
                                           metadata: metadata, png: png)
        do {
            try screenshotDatabase.insert(record)
        } catch {
            errorDescription = error.localizedDescription
            throw error
        }
        let item = screenshotItem(id: record.id, addedAt: record.addedAt, metadata: record.metadata)
        shelfOrder[record.id] = record.shelfOrder
        items.append(item)
        errorDescription = nil
        do { _ = try cacheScreenshot(record) }
        catch { errorDescription = error.localizedDescription }
        return item
    }

    public func screenshotData(id: UUID) throws -> Data {
        try screenshotDatabase.record(id: id).png
    }

    private func nextShelfOrder() throws -> Int64 {
        let result = (shelfOrder.values.max() ?? -1).addingReportingOverflow(1)
        guard !result.overflow else { throw CocoaError(.fileReadCorruptFile) }
        return result.partialValue
    }

    public func screenshotFileURL(id: UUID) throws -> URL {
        try cacheScreenshot(screenshotDatabase.record(id: id)).url
    }

    public static func screenshotDimensions(_ data: Data) throws -> (width: Int, height: Int) {
        guard try imageFormat(for: data, maximumBytes: Int(Int32.max), maximumPixels: Int.max / 9, requiresExactPixelBytes: true) == "png",
              let source = CGImageSourceCreateWithData(data as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int else {
            throw CocoaError(.fileReadCorruptFile)
        }
        return (width, height)
    }

    private func cacheScreenshot(_ record: ShelfScreenshotRecord) throws -> FileShelfItem {
        let dimensions = try Self.screenshotDimensions(record.png)
        guard dimensions.width == record.metadata.pixelWidth, dimensions.height == record.metadata.pixelHeight else {
            throw CocoaError(.fileReadCorruptFile)
        }
        let directory = screenshotDatabase.directory.appendingPathComponent("cache", isDirectory: true)
        let manager = FileManager.default
        try manager.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try manager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: screenshotDatabase.directory.path)
        try manager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
        let url = directory.appendingPathComponent(record.id.uuidString + ".png")
        try record.png.write(to: url, options: [.atomic])
        try manager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        return screenshotItem(id: record.id, addedAt: record.addedAt, metadata: record.metadata)
    }

    private func screenshotItem(id: UUID, addedAt: Date, metadata: ShelfScreenshotMetadata) -> FileShelfItem {
        FileShelfItem(id: id,
            url: screenshotDatabase.directory.appendingPathComponent("cache").appendingPathComponent(id.uuidString + ".png"),
            addedAt: addedAt, bookmarkData: Data(), screenshotMetadata: metadata)
    }

    private func removeScreenshotCache(id: UUID) {
        let url = screenshotDatabase.directory.appendingPathComponent("cache").appendingPathComponent(id.uuidString + ".png")
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        do { try FileManager.default.removeItem(at: url) }
        catch {
            errorDescription = [errorDescription, error.localizedDescription].compactMap { $0 }.joined(separator: "\n")
        }
    }

    private func loadScreenshots() {
        do {
            let records = try screenshotDatabase.records()
            for record in records {
                shelfOrder[record.id] = record.shelfOrder
                let item = screenshotItem(id: record.id, addedAt: record.addedAt, metadata: record.metadata)
                items.append(item)
                if !FileManager.default.fileExists(atPath: item.url.path) {
                    do { _ = try cacheScreenshot(screenshotDatabase.record(id: record.id)) }
                    catch { errorDescription = error.localizedDescription }
                }
            }
            if !records.isEmpty {
                items.sort {
                    let first = shelfOrder[$0.id] ?? 0
                    let second = shelfOrder[$1.id] ?? 0
                    return first == second ? $0.id.uuidString < $1.id.uuidString : first < second
                }
            }
            let cache = screenshotDatabase.directory.appendingPathComponent("cache", isDirectory: true)
            if FileManager.default.fileExists(atPath: cache.path) {
                let retained = Set(records.map(\.id))
                for url in try FileManager.default.contentsOfDirectory(at: cache, includingPropertiesForKeys: nil) {
                    if url.pathExtension == "png", let id = UUID(uuidString: url.deletingPathExtension().lastPathComponent),
                       !retained.contains(id) { removeScreenshotCache(id: id) }
                }
            }
        } catch { errorDescription = error.localizedDescription }
    }

    @discardableResult
    public func add(_ urls: [URL]) -> Int {
        add(payloads: urls.map(TransferPasteboardPayload.file))
    }

    @discardableResult
    public func add(payloads: [TransferPasteboardPayload]) -> Int {
        var additions: [FileShelfItem] = []
        var failure: String?
        for payload in payloads {
            do {
                let item: FileShelfItem
                switch payload {
                case .file(let url):
                    let normalized = url.standardizedFileURL
                    guard url.isFileURL, FileManager.default.fileExists(atPath: normalized.path),
                          !(items + additions).contains(where: { $0.text == nil && $0.url == normalized }) else { continue }
                    item = FileShelfItem(id: UUID(), url: normalized, addedAt: Date(), bookmarkData: try makeBookmark(for: normalized))
                case .text(let text):
                    guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                          !(items + additions).contains(where: { $0.noteLocation == nil && $0.text == text }) else { continue }
                    let link = TransferPasteboard.webURL(from: text)
                    let data = try link.map {
                        try PropertyListSerialization.data(fromPropertyList: ["URL": $0.absoluteString], format: .xml, options: 0)
                    } ?? Data(text.utf8)
                    item = try makeManagedItem(name: link == nil ? "text.txt" : "link.webloc", text: text) {
                        try data.write(to: $0, options: .atomic)
                    }
                }
                additions.append(item)
            } catch {
                failure = error.localizedDescription
            }
        }
        guard !additions.isEmpty else {
            errorDescription = failure
            return 0
        }
        guard persist(items + additions) else {
            additions.forEach(removeManagedFile)
            return 0
        }
        items += additions
        errorDescription = failure
        return additions.count
    }

    public func addContextNote(_ text: String, location: ContextNoteLocation, addedAt: Date = Date()) -> FileShelfItem? {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        do {
            var item = try makeManagedItem(name: "note.txt", text: text) {
                try Data(text.utf8).write(to: $0, options: .atomic)
            }
            item.noteLocation = location
            item.addedAt = addedAt
            guard persist(items + [item]) else {
                removeManagedFile(item)
                return nil
            }
            items.append(item)
            return item
        } catch {
            errorDescription = error.localizedDescription
            return nil
        }
    }

    public func updateContextNote(id: UUID, text: String) -> FileShelfItem? {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        guard let index = items.firstIndex(where: { $0.id == id && $0.noteLocation != nil && $0.isManaged }) else {
            errorDescription = CocoaError(.fileReadNoSuchFile).localizedDescription
            return nil
        }
        let original = items[index]
        let directory = managedDirectory.appendingPathComponent(id.uuidString, isDirectory: true)
        guard original.url.deletingLastPathComponent().standardizedFileURL == directory.standardizedFileURL,
              directory.resolvingSymlinksInPath().path.hasPrefix(managedDirectory.resolvingSymlinksInPath().path + "/") else {
            errorDescription = CocoaError(.fileWriteNoPermission).localizedDescription
            return nil
        }
        let replacementURL = directory.appendingPathComponent("note-\(UUID().uuidString).txt")
        do {
            // Commit a new file reference so a failed index write cannot alter the saved version.
            try Data(text.utf8).write(to: replacementURL, options: .atomic)
            var updated = original
            updated.url = replacementURL
            updated.bookmarkData = try makeBookmark(for: replacementURL)
            updated.text = text
            var candidates = items
            candidates[index] = updated
            guard persist(candidates) else {
                try FileManager.default.removeItem(at: replacementURL)
                return nil
            }
            items = candidates
            do {
                try FileManager.default.removeItem(at: original.url)
            } catch {
                errorDescription = error.localizedDescription
            }
            return updated
        } catch {
            errorDescription = error.localizedDescription
            if FileManager.default.fileExists(atPath: replacementURL.path) {
                do { try FileManager.default.removeItem(at: replacementURL) }
                catch { errorDescription = error.localizedDescription }
            }
            return nil
        }
    }

    public func remove(id: UUID) {
        let removed = items.filter { $0.id == id }
        let remaining = items.filter { $0.id != id }
        if removed.contains(where: { $0.screenshotMetadata != nil }) {
            do {
                try screenshotDatabase.remove(ids: [id])
                items = remaining
                errorDescription = nil
                removeScreenshotCache(id: id)
            } catch { errorDescription = error.localizedDescription }
            return
        }
        guard persist(remaining) else { return }
        items = remaining
        removed.forEach(removeManagedFile)
    }

    public func removeAll() {
        let screenshots = items.filter { $0.screenshotMetadata != nil }
        // Each store commits separately; failed commits must retain their cards.
        if !screenshots.isEmpty {
            do {
                try screenshotDatabase.remove(ids: screenshots.map(\.id))
                items.removeAll { $0.screenshotMetadata != nil }
                errorDescription = nil
                screenshots.forEach { removeScreenshotCache(id: $0.id) }
            } catch {
                errorDescription = error.localizedDescription
                return
            }
        }
        let cacheError = errorDescription
        guard persist([]) else { return }
        errorDescription = cacheError
        let removed = items
        items = []
        removed.forEach(removeManagedFile)
    }

    public func beginAccessing(_ item: FileShelfItem) -> URL {
        _ = item.url.startAccessingSecurityScopedResource()
        return item.url
    }

    public func endAccessing(_ item: FileShelfItem) {
        item.url.stopAccessingSecurityScopedResource()
    }

    public func receive(_ dropItems: [FileShelfDropItem], completion: @escaping (Int) -> Void) {
        guard dropItems.contains(where: { if case .content = $0 { false } else { true } }) else {
            completion(add(payloads: dropItems.compactMap { if case .content(let value) = $0 { value } else { nil } }))
            return
        }
        do {
            let session = try FileShelfPromiseSession(store: self, items: dropItems, completion: completion)
            session.start()
        } catch {
            errorDescription = error.localizedDescription
            completion(0)
        }
    }

    func importPromisedFile(at url: URL, from stagingDirectory: URL) -> Int {
        let resolved = url.resolvingSymlinksInPath().standardizedFileURL
        let staging = stagingDirectory.resolvingSymlinksInPath().standardizedFileURL
        guard url.isFileURL, resolved.path.hasPrefix(staging.path + "/") else {
            errorDescription = CocoaError(.fileReadNoPermission).localizedDescription
            return 0
        }
        do {
            let item = try makeManagedItem(name: url.lastPathComponent, text: nil) {
                try FileManager.default.copyItem(at: url, to: $0)
            }
            guard persist(items + [item]) else {
                removeManagedFile(item)
                return 0
            }
            items.append(item)
            return 1
        } catch {
            errorDescription = error.localizedDescription
            return 0
        }
    }

    func importImage(_ data: Data) -> Int {
        do {
            let format = try Self.imageFormat(for: data)
            let item = try makeManagedItem(name: "image." + format, text: nil) {
                try data.write(to: $0, options: .atomic)
            }
            guard persist(items + [item]) else {
                removeManagedFile(item)
                return 0
            }
            items.append(item)
            return 1
        } catch {
            errorDescription = error.localizedDescription
            return 0
        }
    }

    static let maximumImageBytes = 32 * 1_024 * 1_024
    static let maximumImagePixels = 16_000_000

    static func imageFormat(for data: Data, maximumBytes: Int = maximumImageBytes, maximumPixels: Int = maximumImagePixels,
                            requiresExactPixelBytes: Bool = false) throws -> String {
        guard data.count <= maximumBytes else { throw CocoaError(.fileReadTooLarge) }
        // Read dimensions without decoding first, so tiny compressed inputs cannot allocate huge bitmaps.
        guard let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
              CGImageSourceGetCount(source) == 1,
              let type = CGImageSourceGetType(source) as String?,
              type == UTType.png.identifier || type == UTType.tiff.identifier,
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int,
              width > 0, height > 0 else { throw CocoaError(.fileReadCorruptFile) }
        guard width <= maximumPixels / height else { throw CocoaError(.fileReadTooLarge) }
        if type == UTType.png.identifier {
            let expectedBytes = requiresExactPixelBytes ? pngPixelStreamBytes(data, width: width, height: height) : nil
            guard !requiresExactPixelBytes || expectedBytes != nil,
                  hasCompletePNGData(data, maximumDecodedBytes: expectedBytes ?? width * height * 9,
                                     expectedDecodedBytes: expectedBytes) else { throw CocoaError(.fileReadCorruptFile) }
        }
        return type == UTType.png.identifier ? "png" : "tiff"
    }

    private static func pngPixelStreamBytes(_ data: Data, width: Int, height: Int) -> Int? {
        guard data.count >= 33 else { return nil }
        let depth = Int(data[24])
        let samples: Int
        switch data[25] {
        case 0: guard [1, 2, 4, 8, 16].contains(depth) else { return nil }; samples = 1
        case 2: guard [8, 16].contains(depth) else { return nil }; samples = 3
        case 3: guard [1, 2, 4, 8].contains(depth) else { return nil }; samples = 1
        case 4: guard [8, 16].contains(depth) else { return nil }; samples = 2
        case 6: guard [8, 16].contains(depth) else { return nil }; samples = 4
        default: return nil
        }
        let bits = depth * samples
        guard width <= (Int.max - 7) / bits, data[26] == 0, data[27] == 0 else { return nil }
        func passBytes(x: Int, y: Int, dx: Int, dy: Int) -> Int {
            guard width > x, height > y else { return 0 }
            let columns = (width - x + dx - 1) / dx
            let rows = (height - y + dy - 1) / dy
            return ((columns * bits + 7) / 8 + 1) * rows
        }
        switch data[28] {
        case 0: return passBytes(x: 0, y: 0, dx: 1, dy: 1)
        case 1:
            return [(0, 0, 8, 8), (4, 0, 8, 8), (0, 4, 4, 8), (2, 0, 4, 4),
                    (0, 2, 2, 4), (1, 0, 2, 2), (0, 1, 1, 2)].reduce(0) {
                $0 + passBytes(x: $1.0, y: $1.1, dx: $1.2, dy: $1.3)
            }
        default: return nil
        }
    }

    private static func hasCompletePNGData(_ data: Data, maximumDecodedBytes: Int, expectedDecodedBytes: Int? = nil) -> Bool {
        // ImageIO repairs truncated PNGs and invalid pixel streams, which must not be saved as originals.
        var offset = 8
        var compressed = Data()
        var hasEnd = false
        func integer(at index: Int) -> UInt32 {
            data[index..<(index + 4)].reduce(0) { $0 << 8 | UInt32($1) }
        }
        while offset + 12 <= data.count {
            let length = Int(integer(at: offset))
            guard length <= data.count - offset - 12 else { return false }
            let end = offset + 8 + length
            let checksum = data.withUnsafeBytes { bytes in
                crc32(0, bytes.bindMemory(to: Bytef.self).baseAddress! + offset + 4, uInt(length + 4))
            }
            guard checksum == integer(at: end) else { return false }
            let type = integer(at: offset + 4)
            if type == 0x49444154 { compressed.append(data[(offset + 8)..<end]) }
            offset = end + 4
            if type == 0x49454E44 {
                hasEnd = length == 0 && offset == data.count
                break
            }
        }
        guard hasEnd else { return false }
        var stream = z_stream()
        guard inflateInit_(&stream, ZLIB_VERSION, Int32(MemoryLayout<z_stream>.size)) == Z_OK else { return false }
        defer { inflateEnd(&stream) }
        var output = [UInt8](repeating: 0, count: 65_536)
        return compressed.withUnsafeMutableBytes { input in
            stream.next_in = input.bindMemory(to: Bytef.self).baseAddress
            stream.avail_in = uInt(input.count)
            var status = Z_OK
            while status == Z_OK {
                status = output.withUnsafeMutableBytes { buffer in
                    stream.next_out = buffer.bindMemory(to: Bytef.self).baseAddress
                    stream.avail_out = uInt(min(buffer.count, maximumDecodedBytes + 1 - Int(stream.total_out)))
                    return inflate(&stream, Z_NO_FLUSH)
                }
                guard stream.total_out <= maximumDecodedBytes else { return false }
            }
            return status == Z_STREAM_END && stream.avail_in == 0
                && (expectedDecodedBytes == nil || Int(stream.total_out) == expectedDecodedBytes)
        }
    }

    private func makeManagedItem(name: String, text: String?, write: (URL) throws -> Void) throws -> FileShelfItem {
        let id = UUID()
        let directory = managedDirectory.appendingPathComponent(id.uuidString, isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            let url = directory.appendingPathComponent(name)
            try write(url)
            return FileShelfItem(id: id, url: url, addedAt: Date(), bookmarkData: try makeBookmark(for: url), text: text, isManaged: true)
        } catch {
            try? FileManager.default.removeItem(at: directory)
            throw error
        }
    }

    private func removeManagedFile(_ item: FileShelfItem) {
        let directory = managedDirectory.appendingPathComponent(item.id.uuidString, isDirectory: true)
        guard item.isManaged, item.url.deletingLastPathComponent().standardizedFileURL == directory.standardizedFileURL else { return }
        do {
            try FileManager.default.removeItem(at: directory)
        } catch {
            errorDescription = error.localizedDescription
        }
    }

    private func load() {
        guard let data = try? Data(contentsOf: storageURL) else { return }
        do {
            let stored = try JSONDecoder().decode([StoredItem].self, from: data)
            var loaded: [FileShelfItem] = []
            for (index, value) in stored.enumerated() {
                var stale = false
                let url: URL
                do {
                    url = try URL(
                        resolvingBookmarkData: value.bookmarkData,
                        options: [.withSecurityScope, .withoutUI],
                        relativeTo: nil,
                        bookmarkDataIsStale: &stale
                    )
                } catch {
                    guard let fallbackURL = value.url else { continue }
                    url = fallbackURL
                }
                guard url.isFileURL else { continue }
                let bookmark: Data
                if stale, FileManager.default.fileExists(atPath: url.path) {
                    bookmark = (try? makeBookmark(for: url)) ?? value.bookmarkData
                } else {
                    bookmark = value.bookmarkData
                }
                loaded.append(FileShelfItem(
                    id: value.id,
                    url: url.standardizedFileURL,
                    addedAt: value.addedAt,
                    bookmarkData: bookmark,
                    text: value.text,
                    isManaged: value.isManaged ?? false,
                    noteLocation: value.noteLocation
                ))
                shelfOrder[value.id] = value.shelfOrder ?? Int64(index)
            }
            items = loaded
            errorDescription = nil
            if loaded.count != stored.count || stored.contains(where: { record in
                !items.contains(where: {
                    $0.id == record.id &&
                    $0.bookmarkData == record.bookmarkData &&
                    $0.url == record.url
                })
            }) {
                persist(items)
            }
        } catch {
            errorDescription = error.localizedDescription
        }
    }

    @discardableResult
    private func persist(_ items: [FileShelfItem]) -> Bool {
        do {
            try FileManager.default.createDirectory(at: storageURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            var order = shelfOrder
            var next = try nextShelfOrder()
            let stored = try items.filter { $0.screenshotMetadata == nil }.map { item in
                if order[item.id] == nil {
                    order[item.id] = next
                    guard next < Int64.max else { throw CocoaError(.fileReadCorruptFile) }
                    next += 1
                }
                return StoredItem(id: item.id, bookmarkData: item.bookmarkData, addedAt: item.addedAt, url: item.url,
                    text: item.text, isManaged: item.isManaged ? true : nil, noteLocation: item.noteLocation, shelfOrder: order[item.id])
            }
            let data = try JSONEncoder().encode(stored)
            try data.write(to: storageURL, options: .atomic)
            shelfOrder = order
            errorDescription = nil
            return true
        } catch {
            errorDescription = error.localizedDescription
            return false
        }
    }

    private func makeBookmark(for url: URL) throws -> Data {
        do {
            return try url.bookmarkData(
                options: .withSecurityScope,
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
        } catch {
            return try url.bookmarkData(
                options: .minimalBookmark,
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
        }
    }
}

public enum FileShelfDropItem {
    case content(TransferPasteboardPayload)
    case promise(NSFilePromiseReceiver)
    case image(Data)
}

@MainActor
final class FileShelfPromiseSession {
    let stagingDirectory: URL
    private let store: FileShelfStore
    private var items: [FileShelfDropItem]
    private let completion: (Int) -> Void
    private var files: [Int: [URL]] = [:]
    private var seen = Set<URL>()
    private var remaining = 0
    private var isStarting = true
    private var failure: String?
    private var finished = false
    private var timeout: Task<Void, Never>?

    init(store: FileShelfStore, items: [FileShelfDropItem], completion: @escaping (Int) -> Void) throws {
        self.store = store
        self.items = items
        self.completion = completion
        stagingDirectory = FileManager.default.temporaryDirectory.appendingPathComponent("zisla-shelf-drop-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: stagingDirectory, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
    }

    func start() {
        for (index, item) in items.enumerated() {
            guard case .promise(let receiver) = item else { continue }
            // AppKit requires every receiver in one drag to share a destination.
            receiver.receivePromisedFiles(atDestination: stagingDirectory, options: [:], operationQueue: .main) { [self] url, error in
                MainActor.assumeIsolated { receive(url, error: error, at: index) }
            }
            remaining += max(1, receiver.fileNames.count)
        }
        isStarting = false
        if remaining == 0 {
            finish()
            return
        }
        timeout = Task { [self] in
            do { try await Task.sleep(for: .seconds(120)) } catch { return }
            expire()
        }
    }

    func expire() {
        failure = CocoaError(.userCancelled).localizedDescription
        finish()
    }

    func receive(_ url: URL, error: Error?, at index: Int) {
        guard !finished else {
            if FileManager.default.fileExists(atPath: stagingDirectory.path) {
                do { try FileManager.default.removeItem(at: stagingDirectory) } catch { store.errorDescription = error.localizedDescription }
            }
            return
        }
        if let error {
            failure = error.localizedDescription
        } else {
            guard seen.insert(url.standardizedFileURL).inserted else { return }
            let resolved = url.resolvingSymlinksInPath().standardizedFileURL
            let root = stagingDirectory.resolvingSymlinksInPath().standardizedFileURL
            do {
                guard url.isFileURL, resolved.path.hasPrefix(root.path + "/") else {
                    throw CocoaError(.fileReadNoPermission)
                }
                let snapshotDirectory = stagingDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
                try FileManager.default.createDirectory(at: snapshotDirectory, withIntermediateDirectories: false)
                let snapshot = snapshotDirectory.appendingPathComponent(url.lastPathComponent)
                // Copy while the NSFilePromiseReceiver coordinated read is still active.
                try FileManager.default.copyItem(at: url, to: snapshot)
                files[index, default: []].append(snapshot)
            } catch {
                failure = error.localizedDescription
            }
        }
        remaining -= 1
        if remaining == 0, !isStarting { finish() }
    }

    func finish() {
        guard !finished else { return }
        finished = true
        timeout?.cancel()
        timeout = nil
        var count = 0
        for (index, item) in items.enumerated() {
            switch item {
            case .content(let payload):
                count += store.add(payloads: [payload])
                if let message = store.errorDescription {
                    failure = message
                }
            case .image(let data):
                count += store.importImage(data)
                if let message = store.errorDescription { failure = message }
            case .promise(let receiver):
                let ordered = (files[index] ?? []).sorted {
                    (receiver.fileNames.firstIndex(of: $0.lastPathComponent) ?? Int.max)
                        < (receiver.fileNames.firstIndex(of: $1.lastPathComponent) ?? Int.max)
                }
                for url in ordered {
                    count += store.importPromisedFile(at: url, from: stagingDirectory)
                    if let message = store.errorDescription {
                        failure = message
                    }
                }
            }
        }
        items = []
        do { try FileManager.default.removeItem(at: stagingDirectory) } catch { failure = error.localizedDescription }
        if let failure { store.errorDescription = failure }
        completion(count)
    }
}
