import Foundation

/// 拖拽文件暂存架：按标准化路径去重，按 FIFO 在满容量时淘汰最旧项。
public struct FileShelf: Equatable, Sendable {
    public let capacity: Int
    public private(set) var urls: [URL]

    public init(capacity: Int, urls: [URL] = []) {
        self.capacity = max(1, capacity)
        self.urls = urls.map(\.standardizedFileURL)
    }

    /// 加入一个文件。已存在（标准化后相等）返回 false；成功加入返回 true。
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
