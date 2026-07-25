import Combine
import Foundation

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
}

@MainActor
public final class FileShelfStore: ObservableObject {
    @Published public private(set) var items: [FileShelfItem] = []
    @Published public private(set) var errorDescription: String?

    public let capacity: Int

    private struct StoredItem: Codable {
        var id: UUID
        var bookmarkData: Data
        var addedAt: Date
    }

    private let storageURL: URL

    public init(storageURL: URL = AppPaths.fileShelf, capacity: Int = 99) {
        self.storageURL = storageURL
        self.capacity = max(1, capacity)
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
        if items.count > capacity {
            items.removeFirst(items.count - capacity)
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
                let url = try URL(
                    resolvingBookmarkData: value.bookmarkData,
                    options: [.withSecurityScope, .withoutUI],
                    relativeTo: nil,
                    bookmarkDataIsStale: &stale
                )
                guard FileManager.default.fileExists(atPath: url.path) else { continue }
                let bookmark = stale ? try makeBookmark(for: url) : value.bookmarkData
                loaded.append(FileShelfItem(
                    id: value.id,
                    url: url.standardizedFileURL,
                    addedAt: value.addedAt,
                    bookmarkData: bookmark
                ))
            }
            items = Array(loaded.suffix(capacity))
            errorDescription = nil
            if loaded.count != stored.count || stored.contains(where: { record in
                !items.contains(where: { $0.id == record.id && $0.bookmarkData == record.bookmarkData })
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
                StoredItem(id: $0.id, bookmarkData: $0.bookmarkData, addedAt: $0.addedAt)
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
