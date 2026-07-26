import Foundation

/// Drop-target file shelf: deduplicates by standardized path, evicts the oldest entry when at capacity (FIFO).
public struct FileShelf: Equatable, Sendable {
    public let capacity: Int
    public private(set) var urls: [URL]

    public init(capacity: Int, urls: [URL] = []) {
        self.capacity = max(1, capacity)
        self.urls = urls.map(\.standardizedFileURL)
    }

    /// Adds a file. Returns false if already present (by standardized path); returns true on success.
    @discardableResult
    public mutating func add(_ url: URL) -> Bool {
        let normalized = url.standardizedFileURL
        guard !urls.contains(normalized) else { return false }
        urls.append(normalized)
        if urls.count > capacity {
            urls.removeFirst(urls.count - capacity)
        }
        return true
    }

    @discardableResult
    public mutating func remove(_ url: URL) -> Bool {
        let normalized = url.standardizedFileURL
        guard let index = urls.firstIndex(of: normalized) else { return false }
        urls.remove(at: index)
        return true
    }

    public mutating func clear() {
        urls.removeAll()
    }
}
