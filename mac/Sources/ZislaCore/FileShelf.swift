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

public struct FileShelfSelection: Equatable, Sendable {
    public private(set) var isSelecting = false
    public private(set) var ids: [UUID] = []

    public init() {}

    public mutating func toggleMode() {
        isSelecting.toggle()
        ids.removeAll()
    }

    public mutating func toggle(_ id: UUID) {
        guard isSelecting else { return }
        if let index = ids.firstIndex(of: id) { ids.remove(at: index) }
        else { ids.append(id) }
    }

    public mutating func selectAll(_ visibleIDs: [UUID]) {
        guard isSelecting else { return }
        for id in visibleIDs where !ids.contains(id) { ids.append(id) }
    }

    public mutating func clear() { ids.removeAll() }

    public mutating func retainVisible(_ visibleIDs: [UUID]) {
        let visible = Set(visibleIDs)
        ids.removeAll { !visible.contains($0) }
    }

    public func actionIDs(availableIDs: [UUID], contextID: UUID? = nil) -> [UUID] {
        let available = Set(availableIDs)
        if isSelecting { return ids.filter { available.contains($0) } }
        if let contextID { return available.contains(contextID) ? [contextID] : [] }
        return availableIDs
    }
}
