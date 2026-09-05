import Combine
import Foundation
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

    public static let fileShelfCases = allCases.filter { $0 != .url && $0 != .path && $0 != .text }
    public static let clipboardCases = allCases
}

public struct FileShelfItem: Identifiable, Equatable {
    public var id: UUID
    public var url: URL
    public var addedAt: Date
    public var bookmarkData: Data

    public init(id: UUID, url: URL, addedAt: Date, bookmarkData: Data) {
        self.id = id
        self.url = url
        self.addedAt = addedAt
        self.bookmarkData = bookmarkData
    }

    public var category: FileShelfCategory {
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
    @Published public private(set) var errorDescription: String?

    private struct StoredItem: Codable {
        var id: UUID
        var bookmarkData: Data
        var addedAt: Date
        var url: URL?
    }

    private let storageURL: URL

    public init(storageURL: URL = AppPaths.fileShelf) {
        self.storageURL = storageURL
        load()
    }

    @discardableResult
    public func add(_ urls: [URL]) -> Int {
        var added = 0
        for url in urls where url.isFileURL {
            let normalized = url.standardizedFileURL
            guard FileManager.default.fileExists(atPath: normalized.path) else { continue }
            guard !items.contains(where: { $0.url.standardizedFileURL == normalized }) else { continue }
            do {
                let bookmark = try makeBookmark(for: normalized)
                items.append(FileShelfItem(
                    id: UUID(),
                    url: normalized,
                    addedAt: Date(),
                    bookmarkData: bookmark
                ))
                added += 1
            } catch {
                errorDescription = error.localizedDescription
            }
        }
        if added > 0 { persist() }
        return added
    }

    public func remove(id: UUID) {
        items.removeAll { $0.id == id }
        persist()
    }

    public func removeAll() {
        items.removeAll()
        persist()
    }

    public func beginAccessing(_ item: FileShelfItem) -> URL {
        _ = item.url.startAccessingSecurityScopedResource()
        return item.url
    }

    public func endAccessing(_ item: FileShelfItem) {
        item.url.stopAccessingSecurityScopedResource()
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
                    bookmarkData: bookmark
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
                persist()
            }
        } catch {
            errorDescription = error.localizedDescription
        }
    }

    private func persist() {
        do {
            try FileManager.default.createDirectory(
                at: storageURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let stored = items.map {
                StoredItem(
                    id: $0.id,
                    bookmarkData: $0.bookmarkData,
                    addedAt: $0.addedAt,
                    url: $0.url
                )
            }
            let data = try JSONEncoder().encode(stored)
            try data.write(to: storageURL, options: .atomic)
            errorDescription = nil
        } catch {
            errorDescription = error.localizedDescription
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
