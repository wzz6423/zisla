import Foundation
import ZislaCore

/// Infers active AI tasks from TRAE SOLO CN / TRAE Work ai-agent logs.
///
/// Log path: `~/Library/Application Support/TRAE SOLO CN/logs/<timestamp>/Modular/ai-agent_*_stdout.log`
/// Log format: Rust tracing — `2026-07-23T20:08:01.801423+08:00  LEVEL module_path: message key=value`
/// Activity signal: module path contains `do_chat` and the line includes `task_id=xxx`; ERROR lines mark errors.
public final class TraeSessionActivityDetector: AIActivityDetecting {
    private struct Candidate {
        var url: URL
        var modificationDate: Date
        var size: UInt64
    }

    private struct TaskState {
        var sessionID: String
        var startedAt: Date?
        var updatedAt: Date = .distantPast
        var hasError = false
        var lastErrorAt: Date?
    }

    private struct CachedFile {
        var modificationDate: Date
        var size: UInt64
        var tasks: [String: TaskState]
    }

    public let logsRoot: URL
    public let maxLogFiles: Int
    public let tailBytes: UInt64

    private let fileManager: FileManager
    private var cache: [URL: CachedFile] = [:]

    public init(
        logsRoot: URL? = nil,
        maxLogFiles: Int = 4,
        tailBytes: UInt64 = 524_288,
        fileManager: FileManager = .default
    ) {
        if let logsRoot {
            self.logsRoot = logsRoot
        } else {
            self.logsRoot = Self.defaultLogsRoot(
                home: fileManager.homeDirectoryForCurrentUser,
                fileManager: fileManager
            )
        }
        self.maxLogFiles = max(1, maxLogFiles)
        self.tailBytes = tailBytes
        self.fileManager = fileManager
    }

    public func activeTasks() throws -> [AIProgressTask] {
        let candidates = recentLogFiles()
        let selectedURLs = Set(candidates.map(\.url))
        cache = cache.filter { selectedURLs.contains($0.key) }

        var tasksByTaskID: [String: TaskState] = [:]
        for candidate in candidates {
            let parsed: [String: TaskState]
            if let cached = cache[candidate.url],
               cached.modificationDate == candidate.modificationDate,
               cached.size == candidate.size {
                parsed = cached.tasks
            } else {
                parsed = parseTail(of: candidate)
                cache[candidate.url] = CachedFile(
                    modificationDate: candidate.modificationDate,
                    size: candidate.size,
                    tasks: parsed
                )
            }
            for (taskID, state) in parsed {
                let existing = tasksByTaskID[taskID]
                if existing == nil || existing!.updatedAt < state.updatedAt {
                    tasksByTaskID[taskID] = state
                }
            }
        }

        return tasksByTaskID.compactMap { taskID, state in
            guard state.updatedAt > .distantPast else { return nil }
            let status: AIProgressStatus = state.hasError ? .error : .running
            return AIProgressTask(
                id: Self.taskID(forTaskID: taskID),
                provider: .trae,
                title: "TRAE",
                detail: nil,
                progress: nil,
                status: status,
                updatedAt: state.updatedAt,
                sessionURL: Self.sessionURL(for: state.sessionID),
                effort: nil,
                startedAt: state.startedAt
            )
        }
        .sorted {
            if $0.updatedAt != $1.updatedAt { return $0.updatedAt > $1.updatedAt }
            return $0.id < $1.id
        }
    }

    public static func taskID(forTaskID taskID: String) -> String {
        "trae-task-\(taskID)"
    }

    private static func sessionURL(for sessionID: String) -> URL? {
        var components = URLComponents()
        components.scheme = "solo-cn"
        components.host = "solo-deeplink.ai"
        components.path = "/teleport_session"
        components.queryItems = [URLQueryItem(name: "sid", value: sessionID)]
        return components.url
    }

    public static func defaultLogsRoot(
        home: URL = FileManager.default.homeDirectoryForCurrentUser,
        fileManager: FileManager = .default
    ) -> URL {
        home.appendingPathComponent(
            "Library/Application Support/TRAE SOLO CN/logs",
            isDirectory: true
        )
    }

    // MARK: - File Discovery

    private func recentLogFiles() -> [Candidate] {
        guard fileManager.fileExists(atPath: logsRoot.path),
              let sessionDirs = try? fileManager.contentsOfDirectory(
                at: logsRoot,
                includingPropertiesForKeys: [.isDirectoryKey, .contentModificationDateKey],
                options: [.skipsHiddenFiles]
              ) else {
            return []
        }

        let sortedDirs = sessionDirs
            .filter { dir in
                var isDir: ObjCBool = false
                guard fileManager.fileExists(atPath: dir.path, isDirectory: &isDir),
                      isDir.boolValue else { return false }
                return dir.lastPathComponent.count == 15  // e.g. "20260723T174155"
            }
            .sorted { $0.lastPathComponent > $1.lastPathComponent }

        var candidates: [Candidate] = []
        for dir in sortedDirs.prefix(3) {
            let modularDir = dir.appendingPathComponent("Modular", isDirectory: true)
            guard let files = try? fileManager.contentsOfDirectory(
                at: modularDir,
                includingPropertiesForKeys: [
                    .isRegularFileKey,
                    .contentModificationDateKey,
                    .fileSizeKey,
                ],
                options: [.skipsHiddenFiles]
            ) else { continue }

            for file in files {
                let name = file.lastPathComponent
                guard name.hasPrefix("ai-agent_") && name.hasSuffix("_stdout.log") else { continue }
                guard let values = try? file.resourceValues(forKeys: [
                    .isRegularFileKey,
                    .contentModificationDateKey,
                    .fileSizeKey,
                ]), values.isRegularFile == true else { continue }

                candidates.append(Candidate(
                    url: file,
                    modificationDate: values.contentModificationDate ?? .distantPast,
                    size: UInt64(max(0, values.fileSize ?? 0))
                ))
            }
            if candidates.count >= maxLogFiles { break }
        }

        return Array(candidates.sorted {
            if $0.modificationDate != $1.modificationDate {
                return $0.modificationDate > $1.modificationDate
            }
            return $0.url.path < $1.url.path
        }.prefix(maxLogFiles))
    }

    // MARK: - Log Parsing

    private func parseTail(of candidate: Candidate) -> [String: TaskState] {
        guard let handle = try? FileHandle(forReadingFrom: candidate.url) else { return [:] }
        defer { try? handle.close() }

        let fileSize = candidate.size
        let readOffset: UInt64 = fileSize > tailBytes ? fileSize - tailBytes : 0
        if readOffset > 0 {
            try? handle.seek(toOffset: readOffset)
        }
        let data = (try? handle.readToEnd()) ?? Data()
        guard let content = String(data: data, encoding: .utf8) else { return [:] }

        var tasks: [String: TaskState] = [:]
        for line in content.split(separator: "\n", omittingEmptySubsequences: true) {
            parseLine(String(line), into: &tasks)
        }
        return tasks
    }

    private func parseLine(_ line: String, into tasks: inout [String: TaskState]) {
        // Format: 2026-07-23T20:08:01.801423+08:00  LEVEL module_path: message key=value
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.count > 30 else { return }

        // Extract timestamp from the beginning.
        let timestampEnd = trimmed.firstIndex(of: " ") ?? trimmed.endIndex
        let timestampStr = String(trimmed[..<timestampEnd])
        guard let timestamp = parseTimestamp(timestampStr) else { return }

        // Check for do_chat activity and error level.
        let lower = trimmed.lowercased()
        let isChatActivity = lower.contains("do_chat")
        let isError = trimmed.range(of: " ERROR ") != nil
        guard isChatActivity || isError else { return }

        // Extract task_id and session_id from key=value pairs.
        let taskID = extractKeyValue(trimmed, key: "task_id")
        guard let taskID, !taskID.isEmpty else { return }
        let sessionID = extractKeyValue(trimmed, key: "session_id") ?? ""

        var state = tasks[taskID] ?? TaskState(sessionID: sessionID)
        if state.startedAt == nil || timestamp < state.startedAt! {
            state.startedAt = timestamp
        }
        state.updatedAt = max(state.updatedAt, timestamp)

        if isError {
            state.hasError = true
            state.lastErrorAt = timestamp
        } else if isChatActivity {
            if let lastError = state.lastErrorAt, timestamp > lastError {
                state.hasError = false
            }
        }

        if state.sessionID.isEmpty { state.sessionID = sessionID }
        tasks[taskID] = state
    }

    private func extractKeyValue(_ line: String, key: String) -> String? {
        // Match `key=value` or `key="value"` patterns.
        let patterns = ["\(key)=\"", "\(key)="]
        for pattern in patterns {
            guard let range = line.range(of: pattern) else { continue }
            let rest = line[range.upperBound...]
            if pattern.hasSuffix("\"") {
                if let endQuote = rest.firstIndex(of: "\"") {
                    return String(rest[..<endQuote])
                }
            } else {
                let end = rest.firstIndex { $0.isWhitespace } ?? rest.endIndex
                return String(rest[..<end])
            }
        }
        return nil
    }

    private func parseTimestamp(_ value: String) -> Date? {
        // 2026-07-23T20:08:01.801423+08:00
        if let date = try? Date.ISO8601FormatStyle(includingFractionalSeconds: true).parse(value) {
            return date
        }
        return try? Date.ISO8601FormatStyle().parse(value)
    }
}
