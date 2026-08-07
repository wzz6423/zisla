import Combine
import Foundation

@MainActor
public final class ClipboardHistoryStore: ObservableObject {
    @Published public private(set) var items: [ClipboardHistoryItem] = []
    @Published public private(set) var errorDescription: String?
    @Published public private(set) var totalItemCount = 0
    @Published public private(set) var currentPage = 0
    @Published public private(set) var isLoading = true

    public let capacity: Int?
    public let maxImageBytes: Int
    public let pageSize: Int

    private let database: ClipboardHistoryDatabase
    private let persistenceDelay: Duration
    private var scope: ClipboardHistoryScope = .all
    private var searchText = ""
    private var loadTask: Task<Void, Never>?
    private var loadGeneration = 0
    private var persistenceTask: Task<Void, Never>?
    private var persistenceGeneration = 0
    private var pendingMutations: [ClipboardHistoryMutation] = []

    public init(
        storageURL: URL = AppPaths.clipboardHistory,
        capacity: Int? = nil,
        maxImageBytes: Int = 10 * 1024 * 1024,
        pageSize: Int = 20,
        persistenceDelay: Duration = .seconds(1)
    ) {
        database = ClipboardHistoryDatabase(storageURL: storageURL)
        self.capacity = capacity.map { max(1, $0) }
        self.maxImageBytes = max(1, maxImageBytes)
        self.pageSize = max(1, pageSize)
        self.persistenceDelay = persistenceDelay
        reload()
    }

    public var pinnedItems: [ClipboardHistoryItem] {
        items.filter(\.isPinned)
    }

    public var historyItems: [ClipboardHistoryItem] {
        items.filter { !$0.isPinned }
    }

    public var pageCount: Int {
        max(1, (totalItemCount + pageSize - 1) / pageSize)
    }

    public var canLoadPreviousPage: Bool {
        currentPage > 0
    }

    public var canLoadNextPage: Bool {
        (currentPage + 1) * pageSize < totalItemCount
    }

    public func waitUntilLoaded() async {
        while true {
            let generation = loadGeneration
            guard let task = loadTask else { return }
            await task.value
            if generation == loadGeneration { return }
        }
    }

    public func updateQuery(scope: ClipboardHistoryScope, searchText: String) {
        let normalizedSearch = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard self.scope != scope || self.searchText != normalizedSearch else { return }
        self.scope = scope
        self.searchText = normalizedSearch
        currentPage = 0
        reload()
    }

    public func loadPreviousPage() {
        guard canLoadPreviousPage else { return }
        currentPage -= 1
        reload()
    }

    public func loadNextPage() {
        guard canLoadNextPage else { return }
        currentPage += 1
        reload()
    }

    @discardableResult
    public func record(_ content: ClipboardHistoryContent) -> Bool {
        insert(content, pinned: false)
    }

    @discardableResult
    public func recordPinned(_ content: ClipboardHistoryContent) -> Bool {
        insert(content, pinned: true)
    }

    @discardableResult
    private func insert(_ content: ClipboardHistoryContent, pinned: Bool) -> Bool {
        guard isStorable(content) else { return false }

        let now = persistenceCompatibleDate()
        let item: ClipboardHistoryItem
        if let index = items.firstIndex(where: { $0.content == content }) {
            var existing = items.remove(at: index)
            existing.content = content
            existing.lastCopiedAt = now
            if pinned { existing.isPinned = true }
            item = existing
        } else {
            item = ClipboardHistoryItem(content: content, lastCopiedAt: now, isPinned: pinned)
        }

        if currentPage == 0, matchesCurrentQuery(item) {
            items.append(item)
            normalizeOrder()
            trimHistoryToCapacity()
            trimToPageSize()
        }
        schedulePersistence(.upsert(item, capacity: capacity))
        return true
    }

    public func setPinned(id: UUID, isPinned: Bool) {
        guard let index = items.firstIndex(where: { $0.id == id }),
              items[index].isPinned != isPinned else { return }
        items[index].isPinned = isPinned
        items[index].lastCopiedAt = persistenceCompatibleDate()
        let item = items[index]
        if matchesCurrentQuery(item) {
            normalizeOrder()
            trimHistoryToCapacity()
        } else {
            items.remove(at: index)
        }
        schedulePersistence(.upsert(item, capacity: capacity))
    }

    public func remove(id: UUID) {
        guard items.contains(where: { $0.id == id }) else { return }
        items.removeAll { $0.id == id }
        totalItemCount = max(0, totalItemCount - 1)
        schedulePersistence(.remove(id))
    }

    public func removeAllHistory() {
        let previousCount = items.count
        items.removeAll { !$0.isPinned }
        if scope == .history {
            totalItemCount = 0
        } else {
            totalItemCount = max(0, totalItemCount - (previousCount - items.count))
        }
        schedulePersistence(.removeHistory)
    }

    public func flushPendingChanges() {
        persistenceTask?.cancel()
        persistenceTask = nil
        persistenceGeneration += 1
        let mutations = takePendingMutations()
        do {
            try database.flush(mutations)
            errorDescription = nil
        } catch {
            errorDescription = error.localizedDescription
        }
    }

    private func reload() {
        loadTask?.cancel()
        loadGeneration += 1
        let generation = loadGeneration
        let requestedPage = currentPage
        let requestedScope = scope
        let requestedSearch = searchText
        let pageSize = pageSize
        let database = database
        isLoading = true

        loadTask = Task { [weak self] in
            do {
                var page = try await database.loadPage(
                    scope: requestedScope,
                    searchText: requestedSearch,
                    offset: requestedPage * pageSize,
                    limit: pageSize
                )
                guard !Task.isCancelled, let self, loadGeneration == generation else { return }

                let cleaned = cleanedItems(page.items)
                if !cleaned.mutations.isEmpty {
                    try await database.apply(cleaned.mutations)
                    page = try await database.loadPage(
                        scope: requestedScope,
                        searchText: requestedSearch,
                        offset: requestedPage * pageSize,
                        limit: pageSize
                    )
                }
                guard !Task.isCancelled, loadGeneration == generation else { return }

                let maximumPage = page.totalCount == 0 ? 0 : (page.totalCount - 1) / pageSize
                if requestedPage > maximumPage {
                    currentPage = maximumPage
                    reload()
                    return
                }
                items = cleanedItems(page.items).items
                totalItemCount = page.totalCount
                errorDescription = nil
                isLoading = false
            } catch {
                guard !Task.isCancelled, let self, loadGeneration == generation else { return }
                errorDescription = error.localizedDescription
                isLoading = false
            }
        }
    }

    private func cleanedItems(
        _ loadedItems: [ClipboardHistoryItem]
    ) -> (items: [ClipboardHistoryItem], mutations: [ClipboardHistoryMutation]) {
        var result: [ClipboardHistoryItem] = []
        var mutations: [ClipboardHistoryMutation] = []
        result.reserveCapacity(loadedItems.count)
        for loaded in loadedItems {
            let resolved = resolvingFileBookmark(loaded)
            guard isStorable(resolved.content) else {
                mutations.append(.remove(loaded.id))
                continue
            }
            result.append(resolved)
            if fileReferenceChanged(from: loaded, to: resolved) {
                mutations.append(.upsert(resolved, capacity: capacity))
            }
        }
        return (result, mutations)
    }

    private func fileReferenceChanged(
        from original: ClipboardHistoryItem,
        to resolved: ClipboardHistoryItem
    ) -> Bool {
        guard case .file(let originalReference) = original.content,
              case .file(let resolvedReference) = resolved.content else { return false }
        return originalReference.url != resolvedReference.url
            || originalReference.displayName != resolvedReference.displayName
            || originalReference.bookmark != resolvedReference.bookmark
    }

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

    private func matchesCurrentQuery(_ item: ClipboardHistoryItem) -> Bool {
        switch scope {
        case .all:
            break
        case .pinned where !item.isPinned:
            return false
        case .history where item.isPinned:
            return false
        default:
            break
        }
        return searchText.isEmpty
            || item.content.previewText.localizedCaseInsensitiveContains(searchText)
    }

    private func normalizeOrder() {
        items.sort {
            if $0.isPinned != $1.isPinned { return $0.isPinned }
            return $0.lastCopiedAt > $1.lastCopiedAt
        }
    }

    private func trimHistoryToCapacity() {
        guard let capacity else { return }
        var historyCount = 0
        items.removeAll { item in
            guard !item.isPinned else { return false }
            historyCount += 1
            return historyCount > capacity
        }
    }

    private func trimToPageSize() {
        if items.count > pageSize {
            items.removeLast(items.count - pageSize)
        }
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

    private func schedulePersistence(_ mutation: ClipboardHistoryMutation) {
        pendingMutations.append(mutation)
        persistenceTask?.cancel()
        persistenceGeneration += 1
        let generation = persistenceGeneration
        let delay = persistenceDelay
        persistenceTask = Task { [weak self] in
            do {
                try await Task.sleep(for: delay)
            } catch {
                return
            }
            guard !Task.isCancelled, let self, persistenceGeneration == generation else { return }
            commitPendingMutations(generation: generation)
        }
    }

    private func commitPendingMutations(generation: Int) {
        let mutations = takePendingMutations()
        guard !mutations.isEmpty else { return }
        persistenceTask = nil
        database.persist(mutations) { [weak self] errorDescription in
            guard let self, persistenceGeneration == generation else { return }
            self.errorDescription = errorDescription
            if errorDescription == nil {
                self.reload()
            }
        }
    }

    private func takePendingMutations() -> [ClipboardHistoryMutation] {
        let mutations = pendingMutations
        pendingMutations.removeAll(keepingCapacity: true)
        return mutations
    }
}
