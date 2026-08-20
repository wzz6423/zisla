import Foundation
import ZislaCore

/// Infers active AI tasks from the local data directory of the harnext CLI.
///
/// Data directories: `~/.harnext/` and `~/.dsh/`.
/// Because the harnext log format may change between versions, a directory + file modification time
/// inference strategy is used: scan the most recently modified log/session files under `~/.harnext/`
/// and extract file IDs as task identifiers.
public final class HarnessSessionActivityDetector: AIActivityDetecting {
    private struct Candidate {
        var url: URL
        var modificationDate: Date
        var size: UInt64
    }

    private struct CachedFile {
        var modificationDate: Date
        var size: UInt64
        var task: AIProgressTask?
    }

    public let dataRoot: URL
    public let sourceName: String
    public let maxFiles: Int
    public let recencyThreshold: TimeInterval

    private let fileManager: FileManager
    private var cache: [URL: CachedFile] = [:]
    private var lastScanAt: Date = .distantPast
    private let scanInterval: TimeInterval

    public static let deepSeekSourceName = "DeepSeek Harness"

    public init(
        dataRoot: URL? = nil,
        sourceName: String = "harnext",
        maxFiles: Int = 8,
        recencyThreshold: TimeInterval = 30 * 60,
        scanInterval: TimeInterval = 5,
        fileManager: FileManager = .default
    ) {
        if let dataRoot {
            self.dataRoot = dataRoot
        } else {
            self.dataRoot = Self.defaultDataRoot(
                home: fileManager.homeDirectoryForCurrentUser
            )
        }
        self.maxFiles = max(1, maxFiles)
        self.sourceName = sourceName
        self.recencyThreshold = recencyThreshold
        self.scanInterval = max(0, scanInterval)
        self.fileManager = fileManager
    }

    public func activeTasks() throws -> [AIProgressTask] {
        let now = Date()
        if now.timeIntervalSince(lastScanAt) < scanInterval {
            return cache.values.compactMap(\.task)
        }
        lastScanAt = now

        guard fileManager.fileExists(atPath: dataRoot.path) else {
            cache.removeAll()
            return []
        }

        let candidates = recentFiles()
        let selectedURLs = Set(candidates.map(\.url))
        cache = cache.filter { selectedURLs.contains($0.key) }

        let thresholdMs = now.addingTimeInterval(-recencyThreshold)
        var tasks: [AIProgressTask] = []
        for candidate in candidates {
            guard candidate.modificationDate > thresholdMs else { continue }

            let task: AIProgressTask?
            if let cached = cache[candidate.url],
               cached.modificationDate == candidate.modificationDate,
               cached.size == candidate.size {
                task = cached.task
            } else {
                task = makeTask(from: candidate)
                cache[candidate.url] = CachedFile(
                    modificationDate: candidate.modificationDate,
                    size: candidate.size,
                    task: task
                )
            }
            if let task { tasks.append(task) }
        }

        return tasks.sorted {
            if $0.updatedAt != $1.updatedAt { return $0.updatedAt > $1.updatedAt }
            return $0.id < $1.id
        }
    }

    public static func taskID(forFileURL url: URL) -> String {
        "harness-file-\(url.lastPathComponent)"
    }

    private func taskID(forFileURL url: URL) -> String {
        guard sourceName == Self.deepSeekSourceName else {
            return Self.taskID(forFileURL: url)
        }
        return "deepseek-harness-\(url.deletingLastPathComponent().lastPathComponent)"
    }

    public static func defaultDataRoot(
        home: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> URL {
        home.appendingPathComponent(".harnext", isDirectory: true)
    }

    public static func deepSeekDataRoot(
        home: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> URL {
        home.appendingPathComponent(".dsh", isDirectory: true)
    }

    // MARK: - File Discovery

    private func recentFiles() -> [Candidate] {
        guard let enumerator = fileManager.enumerator(
            at: dataRoot,
            includingPropertiesForKeys: [
                .isRegularFileKey,
                .contentModificationDateKey,
                .fileSizeKey,
            ],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        var candidates: [Candidate] = []
        for case let url as URL in enumerator {
            if sourceName == Self.deepSeekSourceName {
                // DeepSeek keeps profiles and workspace configuration under ~/.dsh; only session transcripts represent work.
                guard ["session.jsonl", "session.jsonl.zstd"].contains(url.lastPathComponent) else { continue }
            } else {
                let ext = url.pathExtension.lowercased()
                guard ["log", "json", "jsonl"].contains(ext) else { continue }
            }
            guard let values = try? url.resourceValues(forKeys: [
                .isRegularFileKey,
                .contentModificationDateKey,
                .fileSizeKey,
            ]), values.isRegularFile == true else { continue }

            candidates.append(Candidate(
                url: url,
                modificationDate: values.contentModificationDate ?? .distantPast,
                size: UInt64(max(0, values.fileSize ?? 0))
            ))
        }

        return Array(candidates.sorted {
            if $0.modificationDate != $1.modificationDate {
                return $0.modificationDate > $1.modificationDate
            }
            return $0.url.path < $1.url.path
        }.prefix(maxFiles))
    }

    private func makeTask(from candidate: Candidate) -> AIProgressTask? {
        AIProgressTask(
            id: taskID(forFileURL: candidate.url),
            provider: .harness,
            title: sourceName,
            detail: nil,
            progress: nil,
            status: .running,
            updatedAt: candidate.modificationDate,
            sessionURL: nil,
            effort: nil,
            startedAt: nil
        )
    }
}
