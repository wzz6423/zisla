import Combine
import Foundation
import ZislaCore

@MainActor
public final class ClipboardHistoryStore: ObservableObject {
    private static let maximumPendingMutations = 512
    public static let recentHistoryPreviewLimit = 8
    @Published public private(set) var items: [ClipboardHistoryItem] = []
    @Published public private(set) var categoryCounts: [FileShelfCategory: Int] = [:]
    @Published public private(set) var errorDescription: String?
    @Published public private(set) var totalItemCount = 0
    @Published public private(set) var currentPage = 0
    @Published public private(set) var isLoading = true
    @Published public private(set) var isHistoryExpanded = false

    public let capacity: Int?
    public let maxImageBytes: Int
    public let pageSize: Int

    private let database: ClipboardHistoryDatabase
    private let persistenceDelay: Duration
    private let now: () -> Date
    private var cleanupPolicy: VoiceRecordingCleanupPolicy = .never
    private var cleanupGeneration = 0
    private(set) var cleanupTimer: Timer?
    private var scope: ClipboardHistoryScope = .all
    private var searchText = ""
    private var category: FileShelfCategory = .all
    private var grouping: ClipboardHistoryGrouping = .none
    private var hasItemsBeyondDisplayedPage = false
    @Published public private(set) var displayedQuery: (
        scope: ClipboardHistoryScope,
        searchText: String,
        category: FileShelfCategory,
        grouping: ClipboardHistoryGrouping,
        page: Int,
        isHistoryExpanded: Bool
    ) = (.all, "", .all, .none, 0, false)
    private var loadTask: Task<Void, Never>?
    private var loadGeneration = 0
    private var persistenceTask: Task<Void, Never>?
    private var persistenceGeneration = 0
    private var pendingMutations: [ClipboardHistoryMutation] = []
    private var inFlightMutations: [ClipboardHistoryMutation] = []
    private var inFlightPersistenceGeneration: Int?

    public init(
        storageURL: URL = AppPaths.clipboardHistory,
        capacity: Int? = nil,
        maxImageBytes: Int = 10 * 1024 * 1024,
        pageSize: Int = 20,
        persistenceDelay: Duration = .seconds(1),
        now: @escaping () -> Date = Date.init
    ) {
        database = ClipboardHistoryDatabase(storageURL: storageURL)
        self.capacity = capacity.map { max(1, $0) }
        self.maxImageBytes = max(1, maxImageBytes)
        self.pageSize = max(1, pageSize)
        self.persistenceDelay = persistenceDelay
        self.now = now
        reload()
    }

    isolated deinit {
        stopCleanup()
    }

    public func configureCleanup(policy: VoiceRecordingCleanupPolicy) {
        guard cleanupPolicy != policy else { return }
        stopCleanup()
        cleanupPolicy = policy
        guard let days = policy.daysThreshold else { return }
        cleanupOldHistory(policy: policy, now: now())
        let timer = Timer(timeInterval: Double(days) * 24 * 60 * 60, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.cleanupOldHistory(policy: policy, now: self.now())
            }
        }
        cleanupTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    public func stopCleanup() {
        cleanupTimer?.invalidate()
        cleanupTimer = nil
        cleanupPolicy = .never
        cleanupGeneration = database.cancelCleanup()
    }

    public func cleanupOldHistory(policy: VoiceRecordingCleanupPolicy, now: Date) {
        guard let days = policy.daysThreshold else { return }
        let cutoff = now.addingTimeInterval(-Double(days) * 24 * 60 * 60)
        schedulePersistence(.removeHistoryBefore(cutoff, generation: cleanupGeneration))
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

    public var isShowingHistoryPreview: Bool {
        pageSize > Self.recentHistoryPreviewLimit
            && !displayedQuery.isHistoryExpanded
            && displayedQuery.scope == .all
            && displayedQuery.searchText.isEmpty
            && displayedQuery.category == .all
            && displayedQuery.grouping == .none
    }

    public var currentQuery: (
        scope: ClipboardHistoryScope,
        searchText: String,
        category: FileShelfCategory,
        grouping: ClipboardHistoryGrouping
    ) {
        (scope, searchText, category, grouping)
    }

    public func waitUntilLoaded() async {
        while true {
            let generation = loadGeneration
            guard let task = loadTask else { return }
            await task.value
            if generation == loadGeneration { return }
        }
    }

    public func updateQuery(
        scope: ClipboardHistoryScope,
        searchText: String,
        category: FileShelfCategory = .all,
        grouping: ClipboardHistoryGrouping = .none
    ) {
        let normalizedSearch = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        let groupingChanged = self.grouping != grouping
        guard self.scope != scope || self.searchText != normalizedSearch || self.category != category
            || groupingChanged || !pendingMutations.isEmpty else { return }
        if groupingChanged {
            isHistoryExpanded = grouping == .sourceApp
        }
        if scope == .history || !normalizedSearch.isEmpty || category != .all {
            isHistoryExpanded = true
        }
        self.scope = scope
        self.searchText = normalizedSearch
        self.category = category
        self.grouping = grouping
        currentPage = 0
        reload()
    }

    public func loadPreviousPage() {
        guard canLoadPreviousPage else { return }
        isHistoryExpanded = true
        currentPage -= 1
        reload()
    }

    public func loadNextPage() {
        guard canLoadNextPage else { return }
        isHistoryExpanded = true
        currentPage += 1
        reload()
    }

    public func loadPage(number: Int) {
        guard (1...pageCount).contains(number) else { return }
        let page = number - 1
        guard currentPage != page else { return }
        isHistoryExpanded = true
        currentPage = page
        reload()
    }

    public func loadFullHistory() {
        guard isShowingHistoryPreview, errorDescription == nil || pendingMutations.isEmpty else { return }
        isHistoryExpanded = true
        currentPage = 0
        reload()
    }

    @discardableResult
    public func record(_ content: ClipboardHistoryContent, sourceApp: ClipboardSourceApp? = nil) -> Bool {
        insert(content, pinned: false, sourceApp: sourceApp)
    }

    @discardableResult
    public func recordPinned(_ content: ClipboardHistoryContent, sourceApp: ClipboardSourceApp? = nil) -> Bool {
        insert(content, pinned: true, sourceApp: sourceApp)
    }

    @discardableResult
    private func insert(_ content: ClipboardHistoryContent, pinned: Bool, sourceApp: ClipboardSourceApp?) -> Bool {
        guard isStorable(content) else { return false }

        let now = persistenceCompatibleDate()
        let pageBoundary = items.last
        let item: ClipboardHistoryItem
        if let index = items.firstIndex(where: { $0.content == content }) {
            var existing = items.remove(at: index)
            existing.content = content
            existing.lastCopiedAt = now
            existing.sourceApp = sourceApp
            if pinned { existing.isPinned = true }
            item = existing
        } else {
            item = ClipboardHistoryItem(content: content, lastCopiedAt: now, isPinned: pinned, sourceApp: sourceApp)
        }

        if displayedQuery.page == 0, matchesDisplayedQuery(item) {
            if displayedQuery.grouping == .none || !hasItemsBeyondDisplayedPage
                || pageBoundary.map({ !isOrderedBefore($0, item) }) == true {
                items.append(item)
                normalizeOrder()
                trimHistoryToCapacity()
                if items.count > pageSize { hasItemsBeyondDisplayedPage = true }
                trimToPageSize()
            }
        }
        schedulePersistence(.upsert(item, capacity: capacity))
        if displayedQuery.grouping == .sourceApp, hasItemsBeyondDisplayedPage, pageBoundary == nil {
            schedulePendingPersistence(immediately: true)
        }
        return true
    }

    public func setPinned(id: UUID, isPinned: Bool) {
        guard let index = items.firstIndex(where: { $0.id == id }),
              items[index].isPinned != isPinned else { return }
        items[index].isPinned = isPinned
        items[index].lastCopiedAt = persistenceCompatibleDate()
        let item = items[index]
        if matchesDisplayedQuery(item) {
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
        if displayedQuery.scope == .history {
            totalItemCount = 0
            hasItemsBeyondDisplayedPage = false
        } else {
            totalItemCount = max(0, totalItemCount - (previousCount - items.count))
        }
        schedulePersistence(.removeHistory)
    }

    public func flushPendingChanges() {
        persistenceTask?.cancel()
        persistenceTask = nil
        persistenceGeneration += 1
        let mutations = inFlightMutations + takePendingMutations()
        do {
            try database.flush(mutations)
            inFlightMutations.removeAll(keepingCapacity: true)
            inFlightPersistenceGeneration = nil
            errorDescription = nil
        } catch {
            pendingMutations = mutations + pendingMutations
            inFlightMutations.removeAll(keepingCapacity: true)
            inFlightPersistenceGeneration = nil
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
        let requestedCategory = category
        let requestedGrouping = grouping
        let requestedExpansion = isHistoryExpanded
        let pageSize = pageSize
        let isHistoryPreview = pageSize > Self.recentHistoryPreviewLimit
            && !requestedExpansion && requestedScope == .all && requestedSearch.isEmpty
            && requestedCategory == .all && requestedGrouping == .none
        let database = database
        isLoading = true
        schedulePendingPersistence(immediately: true)
        let persistenceTask = self.persistenceTask

        loadTask = Task { [weak self] in
            await persistenceTask?.value
            if let self {
                guard !Task.isCancelled, loadGeneration == generation else { return }
                if !pendingMutations.isEmpty {
                    scope = displayedQuery.scope
                    searchText = displayedQuery.searchText
                    category = displayedQuery.category
                    grouping = displayedQuery.grouping
                    currentPage = displayedQuery.page
                    isHistoryExpanded = displayedQuery.isHistoryExpanded
                    isLoading = false
                    return
                }
            }
            do {
                var page: ClipboardHistoryPage
                if isHistoryPreview {
                    page = try await database.loadRecentHistoryPreview(
                        limit: ClipboardHistoryStore.recentHistoryPreviewLimit
                    )
                } else {
                    page = try await database.loadPage(
                        scope: requestedScope,
                        searchText: requestedSearch,
                        category: requestedCategory,
                        grouping: requestedGrouping,
                        offset: requestedPage * pageSize,
                        limit: pageSize
                    )
                }
                guard !Task.isCancelled, let self, loadGeneration == generation else { return }

                let cleaned = cleanedItems(page.items)
                if !cleaned.mutations.isEmpty {
                    try await database.apply(cleaned.mutations)
                    if isHistoryPreview {
                        page = try await database.loadRecentHistoryPreview(
                            limit: ClipboardHistoryStore.recentHistoryPreviewLimit
                        )
                    } else {
                        page = try await database.loadPage(
                            scope: requestedScope,
                            searchText: requestedSearch,
                            category: requestedCategory,
                            grouping: requestedGrouping,
                            offset: requestedPage * pageSize,
                            limit: pageSize
                        )
                    }
                }
                guard !Task.isCancelled, loadGeneration == generation else { return }

                let maximumPage = isHistoryPreview ? 0 : (page.totalCount == 0 ? 0 : (page.totalCount - 1) / pageSize)
                if requestedPage > maximumPage {
                    currentPage = maximumPage
                    reload()
                    return
                }
                displayedQuery = (requestedScope, requestedSearch, requestedCategory, requestedGrouping, requestedPage, requestedExpansion)
                hasItemsBeyondDisplayedPage = page.totalCount > (requestedPage + 1) * pageSize
                items = cleanedItems(page.items).items
                totalItemCount = page.totalCount
                categoryCounts = page.categoryCounts
                errorDescription = nil
                isLoading = false
            } catch {
                guard !Task.isCancelled, let self, loadGeneration == generation else { return }
                scope = displayedQuery.scope
                searchText = displayedQuery.searchText
                category = displayedQuery.category
                grouping = displayedQuery.grouping
                currentPage = displayedQuery.page
                isHistoryExpanded = displayedQuery.isHistoryExpanded
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

    private func matchesDisplayedQuery(_ item: ClipboardHistoryItem) -> Bool {
        switch displayedQuery.scope {
        case .all:
            break
        case .pinned where !item.isPinned:
            return false
        case .history where item.isPinned:
            return false
        default:
            break
        }
        guard displayedQuery.category == .all || item.category == displayedQuery.category else { return false }
        return displayedQuery.searchText.isEmpty
            || item.content.previewText.localizedCaseInsensitiveContains(displayedQuery.searchText)
            || item.sourceApp?.name.localizedCaseInsensitiveContains(displayedQuery.searchText) == true
            || item.sourceApp?.bundleIdentifier.localizedCaseInsensitiveContains(displayedQuery.searchText) == true
    }

    private func normalizeOrder() {
        items.sort(by: isOrderedBefore)
    }

    private func isOrderedBefore(_ lhs: ClipboardHistoryItem, _ rhs: ClipboardHistoryItem) -> Bool {
        if displayedQuery.grouping == .sourceApp {
            switch (lhs.sourceApp?.bundleIdentifier, rhs.sourceApp?.bundleIdentifier) {
            case let (leftSource?, rightSource?):
                if !leftSource.utf8.elementsEqual(rightSource.utf8) {
                    return leftSource.utf8.lexicographicallyPrecedes(rightSource.utf8)
                }
            case (_?, nil):
                return true
            case (nil, _?):
                return false
            case (nil, nil):
                break
            }
        }
        if lhs.isPinned != rhs.isPinned { return lhs.isPinned }
        if lhs.lastCopiedAt != rhs.lastCopiedAt { return lhs.lastCopiedAt > rhs.lastCopiedAt }
        return displayedQuery.grouping == .sourceApp && lhs.id.uuidString < rhs.id.uuidString
    }

    private func trimHistoryToCapacity() {
        guard let capacity else { return }
        let retained = Set(items.filter { !$0.isPinned }.sorted { $0.lastCopiedAt > $1.lastCopiedAt }
            .prefix(capacity).map(\.id))
        items.removeAll { item in
            !item.isPinned && !retained.contains(item.id)
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
        Date(timeIntervalSinceReferenceDate: now().timeIntervalSinceReferenceDate)
    }

    private func schedulePersistence(_ mutation: ClipboardHistoryMutation) {
        pendingMutations.append(mutation)
        if isLoading {
            reload()
        } else {
            schedulePendingPersistence()
        }
    }

    private func schedulePendingPersistence(immediately: Bool = false) {
        guard !pendingMutations.isEmpty, inFlightPersistenceGeneration == nil else { return }
        persistenceTask?.cancel()
        persistenceGeneration += 1
        let generation = persistenceGeneration
        if immediately || pendingMutations.count >= Self.maximumPendingMutations {
            commitPendingMutations(generation: generation)
            return
        }
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
        guard inFlightPersistenceGeneration == nil, persistenceGeneration == generation else { return }
        let mutations = takePendingMutations()
        guard !mutations.isEmpty else { return }
        inFlightMutations = mutations
        inFlightPersistenceGeneration = generation
        let (completion, continuation) = AsyncStream<Void>.makeStream()
        persistenceTask = Task {
            for await _ in completion {}
        }
        database.persist(mutations) { [weak self] errorDescription in
            defer { continuation.finish() }
            guard let self, self.inFlightPersistenceGeneration == generation else { return }
            self.inFlightMutations.removeAll(keepingCapacity: true)
            self.inFlightPersistenceGeneration = nil
            if let errorDescription {
                self.pendingMutations = mutations + self.pendingMutations
                self.errorDescription = errorDescription
            } else {
                self.errorDescription = nil
                self.reload()
                self.schedulePendingPersistence()
            }
        }
    }

    private func takePendingMutations() -> [ClipboardHistoryMutation] {
        let mutations = pendingMutations
        pendingMutations.removeAll(keepingCapacity: true)
        return mutations
    }
}
