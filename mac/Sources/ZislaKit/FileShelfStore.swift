import AppKit
import Combine
import Foundation
import ImageIO
import zlib
import UniformTypeIdentifiers
import ZislaCore

public enum FileShelfCategory: String, CaseIterable, Hashable, Identifiable, Sendable {
    case all = "全部"
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
    public static let clipboardCases = allCases
}

public struct FileShelfItem: Identifiable, Equatable {
    public var id: UUID
    public var url: URL
    public var addedAt: Date
    public var bookmarkData: Data
    public var text: String?
    public var isManaged: Bool

    public init(id: UUID, url: URL, addedAt: Date, bookmarkData: Data, text: String? = nil, isManaged: Bool = false) {
        self.id = id
        self.url = url
        self.addedAt = addedAt
        self.bookmarkData = bookmarkData
        self.text = text
        self.isManaged = isManaged
    }

    public var linkURL: URL? { text.flatMap(TransferPasteboard.webURL) }

    public var payload: TransferPasteboardPayload {
        text.map(TransferPasteboardPayload.text) ?? .file(url)
    }

    public var displayName: String {
        text.map { String($0.trimmingCharacters(in: .whitespacesAndNewlines).prefix(120)) }
            ?? url.lastPathComponent
    }

    public var category: FileShelfCategory {
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
    }

    private let storageURL: URL
    var managedDirectory: URL { storageURL.deletingPathExtension().appendingPathExtension("items") }

    public init(storageURL: URL = AppPaths.fileShelf) {
        self.storageURL = storageURL
        load()
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
                          !(items + additions).contains(where: { $0.text == text }) else { continue }
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

    public func remove(id: UUID) {
        let removed = items.filter { $0.id == id }
        let remaining = items.filter { $0.id != id }
        guard persist(remaining) else { return }
        items = remaining
        removed.forEach(removeManagedFile)
    }

    public func removeAll() {
        guard persist([]) else { return }
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

    static func imageFormat(for data: Data) throws -> String {
        guard data.count <= maximumImageBytes else { throw CocoaError(.fileReadTooLarge) }
        // Read dimensions without decoding first, so tiny compressed inputs cannot allocate huge bitmaps.
        guard let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
              CGImageSourceGetCount(source) == 1,
              let type = CGImageSourceGetType(source) as String?,
              type == UTType.png.identifier || type == UTType.tiff.identifier,
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int,
              width > 0, height > 0 else { throw CocoaError(.fileReadCorruptFile) }
        guard width <= maximumImagePixels / height else { throw CocoaError(.fileReadTooLarge) }
        if type == UTType.png.identifier, !hasCompletePNGData(data, maximumDecodedBytes: width * height * 9) {
            throw CocoaError(.fileReadCorruptFile)
        }
        return type == UTType.png.identifier ? "png" : "tiff"
    }

    private static func hasCompletePNGData(_ data: Data, maximumDecodedBytes: Int) -> Bool {
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
            for value in stored {
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
                    isManaged: value.isManaged ?? false
                ))
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
            let stored = items.map {
                StoredItem(id: $0.id, bookmarkData: $0.bookmarkData, addedAt: $0.addedAt, url: $0.url, text: $0.text, isManaged: $0.isManaged ? true : nil)
            }
            let data = try JSONEncoder().encode(stored)
            try data.write(to: storageURL, options: .atomic)
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
