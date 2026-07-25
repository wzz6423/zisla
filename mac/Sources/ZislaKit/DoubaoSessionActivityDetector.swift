import Foundation
import ZislaCore

/// 从豆包桌面端（PWA 壳）的本地数据目录推断活动状态。
///
/// 数据目录：`~/Library/Application Support/Doubao/`
/// 豆包是 PWA 壳，无结构化 AI 任务日志；采用本地数据目录文件修改时间推断：
/// 若数据目录中有文件在 TTL 窗口内被修改，判定为活动状态。
public final class DoubaoSessionActivityDetector: AIActivityDetecting {
    private struct Candidate {
        var url: URL
        var modificationDate: Date
    }

    public let dataRoots: [URL]
    public let maxFiles: Int
    public let recencyThreshold: TimeInterval

    private let fileManager: FileManager
    private var cachedTask: AIProgressTask?
    private var cachedSignature: String?
    private var lastScanAt: Date = .distantPast
    private let scanInterval: TimeInterval

    public init(
        dataRoots: [URL]? = nil,
        maxFiles: Int = 32,
        recencyThreshold: TimeInterval = 10 * 60,
        scanInterval: TimeInterval = 5,
        fileManager: FileManager = .default
    ) {
        if let dataRoots {
            self.dataRoots = dataRoots
        } else {
            self.dataRoots = Self.defaultDataRoots(
                home: fileManager.homeDirectoryForCurrentUser,
                fileManager: fileManager
            )
        }
        self.maxFiles = max(1, maxFiles)
        self.recencyThreshold = recencyThreshold
        self.scanInterval = max(0, scanInterval)
        self.fileManager = fileManager
    }

    public func activeTasks() throws -> [AIProgressTask] {
        let now = Date()
        if now.timeIntervalSince(lastScanAt) < scanInterval,
           let cached = cachedTask {
            return [cached]
        }
        lastScanAt = now

        let candidates = recentFiles()
        let signature = signature(for: candidates)
        if signature == cachedSignature, let cached = cachedTask {
            return [cached]
        }
        cachedSignature = signature

        guard let latest = candidates.first,
              latest.modificationDate > now.addingTimeInterval(-recencyThreshold) else {
            cachedTask = nil
            return []
        }

        let task = AIProgressTask(
            id: Self.taskID,
            provider: .doubao,
            title: "豆包",
            detail: nil,
            progress: nil,
            status: .running,
            updatedAt: latest.modificationDate,
            sessionURL: nil,
            effort: nil,
            startedAt: nil
        )
        cachedTask = task
        return [task]
    }

    public static let taskID = "doubao-active"

    public static func defaultDataRoots(
        home: URL = FileManager.default.homeDirectoryForCurrentUser,
        fileManager: FileManager = .default
    ) -> [URL] {
        var roots: [URL] = []
        let appSupport = home.appendingPathComponent("Library/Application Support", isDirectory: true)

        let doubaoRoot = appSupport.appendingPathComponent("Doubao", isDirectory: true)
        if fileManager.fileExists(atPath: doubaoRoot.path) {
            roots.append(doubaoRoot)
        }

        // PWA variants may use different directory names.
        if let entries = try? fileManager.contentsOfDirectory(
            at: appSupport,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) {
            for entry in entries {
                let name = entry.lastPathComponent.lowercased()
                if name.contains("doubao") && !roots.contains(entry) {
                    roots.append(entry)
                }
            }
        }

        let cachesRoot = home.appendingPathComponent("Library/Caches", isDirectory: true)
        let doubaoCache = cachesRoot.appendingPathComponent("Doubao", isDirectory: true)
        if fileManager.fileExists(atPath: doubaoCache.path) {
            roots.append(doubaoCache)
        }

        return roots
    }

    // MARK: - File Discovery

    private func recentFiles() -> [Candidate] {
        var candidates: [Candidate] = []
        for root in dataRoots {
            guard let enumerator = fileManager.enumerator(
                at: root,
                includingPropertiesForKeys: [
                    .isRegularFileKey,
                    .contentModificationDateKey,
                ],
                options: [.skipsHiddenFiles]
            ) else { continue }

            for case let url as URL in enumerator {
                guard let values = try? url.resourceValues(forKeys: [
                    .isRegularFileKey,
                    .contentModificationDateKey,
                ]), values.isRegularFile == true else { continue }
                candidates.append(Candidate(
                    url: url,
                    modificationDate: values.contentModificationDate ?? .distantPast
                ))
                if candidates.count >= maxFiles { break }
            }
        }

        return candidates.sorted { $0.modificationDate > $1.modificationDate }
    }

    private func signature(for candidates: [Candidate]) -> String {
        candidates.prefix(8).map { "\($0.url.lastPathComponent):\($0.modificationDate.timeIntervalSince1970)" }
            .joined(separator: "|")
    }
}
