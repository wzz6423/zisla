import Combine
import Foundation

@MainActor
public final class ClipboardHistoryStore: ObservableObject {
    @Published public private(set) var items: [ClipboardHistoryItem] = []
    @Published public private(set) var errorDescription: String?

    public let capacity: Int
    public let maxImageBytes: Int

    private let database: ClipboardHistoryDatabase
    private let persistenceDelay: Duration
    private var persistenceTask: Task<Void, Never>?
    private var persistenceGeneration = 0

    public init(
        storageURL: URL = AppPaths.clipboardHistory,
        capacity: Int = 999,
        maxImageBytes: Int = 10 * 1024 * 1024,
        persistenceDelay: Duration = .seconds(1)
    ) {
        database = ClipboardHistoryDatabase(storageURL: storageURL)
        self.capacity = max(1, capacity)
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
        guard isStorable(content) else { return false }

        let now = persistenceCompatibleDate()
        if let index = items.firstIndex(where: { $0.content == content }) {
            var item = items.remove(at: index)
            item.lastCopiedAt = now
            items.append(item)
        } else {
            items.append(ClipboardHistoryItem(content: content, lastCopiedAt: now))
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

    /// 仅清理历史记录，保留用户固定的常用信息。
    public func removeAllHistory() {
        guard items.contains(where: { !$0.isPinned }) else { return }
        items.removeAll { !$0.isPinned }
        schedulePersistence()
    }

    /// 应用退出前提交被合并的最后一批剪贴板变更。
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
            items = decoded.filter { isStorable($0.content) }
            normalizeOrder()
            trimHistoryToCapacity()
            errorDescription = nil
            if items != decoded { try database.flush(items) }
        } catch {
            errorDescription = error.localizedDescription
        }
    }

    private func normalizeOrder() {
        items.sort {
            if $0.isPinned != $1.isPinned { return $0.isPinned }
            return $0.lastCopiedAt > $1.lastCopiedAt
        }
    }

    private func trimHistoryToCapacity() {
        let historyIDs = items.filter { !$0.isPinned }.map(\.id)
        guard historyIDs.count > capacity else { return }
        let expired = Set(historyIDs.dropFirst(capacity))
        items.removeAll { expired.contains($0.id) }
    }

    private func isStorable(_ content: ClipboardHistoryContent) -> Bool {
        guard content.isStorable else { return false }
        if case .image(let data) = content {
            return data.count <= maxImageBytes
        }
        return true
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
