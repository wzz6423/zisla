import Combine
import Foundation

@MainActor
public final class ClipboardHistoryStore: ObservableObject {
    @Published public private(set) var items: [ClipboardHistoryItem] = []
    @Published public private(set) var errorDescription: String?

    public let capacity: Int?
    public let maxImageBytes: Int

    private let database: ClipboardHistoryDatabase
    private let persistenceDelay: Duration
    private var persistenceTask: Task<Void, Never>?
    private var persistenceGeneration = 0

    public init(
        storageURL: URL = AppPaths.clipboardHistory,
        capacity: Int? = nil,
        maxImageBytes: Int = 10 * 1024 * 1024,
        persistenceDelay: Duration = .seconds(1)
    ) {
        database = ClipboardHistoryDatabase(storageURL: storageURL)
        self.capacity = capacity.map { max(1, $0) }
        self.maxImageBytes = max(1, maxImageBytes)
        self.persistenceDelay = persistenceDelay
        load()
    }

    public var pinnedItems: [ClipboardHistoryItem] {
        items.filter(\.isPinned)
    }

    public var historyItems: [ClipboardHistoryItem] {
        items.filter { !$0.isPinned }
    }

    @discardableResult
    public func record(_ content: ClipboardHistoryContent) -> Bool {
        insert(content, pinned: false)
    }

    /// Adds an item and pins it: if it already exists, refreshes its content and timestamp while keeping it pinned.
    /// Intended for direct use by UI/AppModel; correctly handles existence checks, deduplication, capacity, and async persistence semantics.
    /// Manually added favorites are always pinned.
    @discardableResult
    public func recordPinned(_ content: ClipboardHistoryContent) -> Bool {
        insert(content, pinned: true)
    }

    @discardableResult
    private func insert(_ content: ClipboardHistoryContent, pinned: Bool) -> Bool {
        guard isStorable(content) else { return false }

        let now = persistenceCompatibleDate()
        if let index = items.firstIndex(where: { $0.content == content }) {
            var item = items.remove(at: index)
            item.content = content
            item.lastCopiedAt = now
            if pinned { item.isPinned = true }
            items.append(item)
        } else {
            items.append(ClipboardHistoryItem(content: content, lastCopiedAt: now, isPinned: pinned))
        }
        normalizeOrder()
        trimHistoryToCapacity()
        schedulePersistence()
        return true
    }

    public func setPinned(id: UUID, isPinned: Bool) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        items[index].isPinned = isPinned
        items[index].lastCopiedAt = persistenceCompatibleDate()
        normalizeOrder()
        trimHistoryToCapacity()
        schedulePersistence()
    }

    public func remove(id: UUID) {
        guard items.contains(where: { $0.id == id }) else { return }
        items.removeAll { $0.id == id }
        schedulePersistence()
    }

    /// Clears history only; retains items the user has pinned.
    public func removeAllHistory() {
        guard items.contains(where: { !$0.isPinned }) else { return }
        items.removeAll { !$0.isPinned }
        schedulePersistence()
    }

    /// Commits the last coalesced batch of clipboard changes before the app quits.
    public func flushPendingChanges() {
        persistenceTask?.cancel()
        persistenceTask = nil
        persistenceGeneration += 1
        do {
            try database.flush(items)
            errorDescription = nil
        } catch {
            errorDescription = error.localizedDescription
        }
    }

    private func load() {
        do {
            let decoded = try database.load()
            let resolved = decoded.map(resolvingFileBookmark)
            items = resolved.filter { isStorable($0.content) }
            normalizeOrder()
            trimHistoryToCapacity()
            errorDescription = nil
            if items != decoded { try database.flush(items) }
        } catch {
            errorDescription = error.localizedDescription
        }
    }

    /// Restores the actual URL and security scope from a bookmark after relaunch;
    /// falls back to the original path if the bookmark is stale but the file still exists, then refreshes the bookmark.
    private func resolvingFileBookmark(_ item: ClipboardHistoryItem) -> ClipboardHistoryItem {
        guard case .file(let reference) = item.content else { return item }
        var stale = false
        let resolved = try? URL(
            resolvingBookmarkData: reference.bookmark,
            options: [.withSecurityScope, .withoutUI],
            relativeTo: nil,
            bookmarkDataIsStale: &stale
        )
        let url = (resolved ?? reference.url).standardizedFileURL
        guard FileManager.default.fileExists(atPath: url.path) else { return item }
        let bookmark = (resolved == nil || stale)
            ? ((try? ClipboardFileReference.makeBookmark(for: url)) ?? reference.bookmark)
            : reference.bookmark
        var updated = item
        updated.content = .file(ClipboardFileReference(
            url: url,
            displayName: reference.displayName,
            bookmark: bookmark
        ))
        return updated
    }

    private func normalizeOrder() {
        items.sort {
            if $0.isPinned != $1.isPinned { return $0.isPinned }
            return $0.lastCopiedAt > $1.lastCopiedAt
        }
    }

    private func trimHistoryToCapacity() {
        guard let capacity else { return }
        let historyIDs = items.filter { !$0.isPinned }.map(\.id)
        guard historyIDs.count > capacity else { return }
        let expired = Set(historyIDs.dropFirst(capacity))
        items.removeAll { expired.contains($0.id) }
    }

    private func isStorable(_ content: ClipboardHistoryContent) -> Bool {
        guard content.isStorable else { return false }
        switch content {
        case .image(let data):
            return data.count <= maxImageBytes
        case .file(let reference):
            return FileManager.default.fileExists(atPath: reference.url.standardizedFileURL.path)
        case .text:
            return true
        }
    }

    private func persistenceCompatibleDate() -> Date {
        Date(timeIntervalSinceReferenceDate: Date().timeIntervalSinceReferenceDate)
    }

    private func schedulePersistence() {
        persistenceTask?.cancel()
        let snapshot = items
        let delay = persistenceDelay
        persistenceGeneration += 1
        let generation = persistenceGeneration
        persistenceTask = Task { [weak self] in
            do {
                try await Task.sleep(for: delay)
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            self?.persistenceTask = nil
            self?.database.persist(snapshot) { [weak self] errorDescription in
                guard let self, persistenceGeneration == generation else { return }
                self.errorDescription = errorDescription
            }
        }
    }
}
