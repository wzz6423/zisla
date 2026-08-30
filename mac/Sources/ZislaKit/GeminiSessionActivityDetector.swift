import Foundation
import ZislaCore

/// Infers active tasks from Gemini CLI `~/.gemini/tmp/**/chats/session-*` session files.
public final class GeminiSessionActivityDetector: AIActivityDetecting {
    private struct Candidate {
        var url: URL
        var modificationDate: Date
        var size: UInt64
    }

    private struct SessionState {
        var sessionID: String?
        var isActive = false
        var isBlocked = false
        var hasError = false
        var startedAt: Date?
        var updatedAt: Date = .distantPast
        var model: String?
    }

    private struct CachedTask {
        var modificationDate: Date
        var size: UInt64
        var readerState: IncrementalJSONLReader.State?
        var state: SessionState
        var task: AIProgressTask?
    }

    public let sessionsRoot: URL
    public let maxSessionFiles: Int

    private let fileManager: FileManager
    private let jsonlReader: IncrementalJSONLReader
    private let maximumLegacyJSONBytes: Int
    private var cache: [URL: CachedTask] = [:]

    public init(
        sessionsRoot: URL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".gemini/tmp", isDirectory: true),
        maxSessionFiles: Int = 12,
        initialTailBytes: Int = 1_024 * 1_024,
        maximumLegacyJSONBytes: Int = 1_024 * 1_024,
        fileManager: FileManager = .default
    ) {
        self.sessionsRoot = sessionsRoot
        self.maxSessionFiles = max(1, maxSessionFiles)
        jsonlReader = IncrementalJSONLReader(initialTailBytes: initialTailBytes)
        self.maximumLegacyJSONBytes = max(1, maximumLegacyJSONBytes)
        self.fileManager = fileManager
    }

    public func activeTasks() throws -> [AIProgressTask] {
        let candidates = recentSessionFiles()
        let selectedURLs = Set(candidates.map(\.url))
        cache = cache.filter { selectedURLs.contains($0.key) }
        var tasksByID: [String: AIProgressTask] = [:]

        for candidate in candidates {
            let task: AIProgressTask?
            if let cached = cache[candidate.url],
               cached.modificationDate == candidate.modificationDate,
               cached.size == candidate.size {
                task = cached.task
            } else {
                let next = parseSession(candidate, cached: cache[candidate.url])
                cache[candidate.url] = next
                task = next.task
            }
            guard let task else { continue }
            if let existing = tasksByID[task.id], existing.updatedAt > task.updatedAt {
                continue
            }
            tasksByID[task.id] = task
        }

        return tasksByID.values.sorted {
            if $0.updatedAt != $1.updatedAt { return $0.updatedAt > $1.updatedAt }
            return $0.id < $1.id
        }
    }

    public static func taskID(forSessionID sessionID: String) -> String {
        "gemini-session-\(sessionID)"
    }

    private func recentSessionFiles() -> [Candidate] {
        guard fileManager.fileExists(atPath: sessionsRoot.path),
              let enumerator = fileManager.enumerator(
                at: sessionsRoot,
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
            guard url.lastPathComponent.hasPrefix("session-"),
                  url.pathExtension == "jsonl" || url.pathExtension == "json",
                  let values = try? url.resourceValues(forKeys: [
                    .isRegularFileKey,
                    .contentModificationDateKey,
                    .fileSizeKey,
                  ]),
                  values.isRegularFile == true else {
                continue
            }
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
        }.prefix(maxSessionFiles))
    }

    private func parseSession(_ candidate: Candidate, cached: CachedTask?) -> CachedTask {
        if candidate.url.pathExtension == "jsonl" {
            return parseJSONLSession(candidate, cached: cached)
        }

        var state = SessionState()
        if candidate.size <= UInt64(maximumLegacyJSONBytes),
           let data = try? Data(contentsOf: candidate.url),
           !data.isEmpty {
            applyLegacyJSON(data, to: &state, fallbackDate: candidate.modificationDate)
        }
        return CachedTask(
            modificationDate: candidate.modificationDate,
            size: candidate.size,
            readerState: nil,
            state: state,
            task: makeTask(from: state, candidate: candidate)
        )
    }

    private func parseJSONLSession(_ candidate: Candidate, cached: CachedTask?) -> CachedTask {
        var next: CachedTask
        if let cached,
           let readerState = cached.readerState,
           candidate.size >= readerState.offset,
           !(candidate.size == readerState.offset
               && candidate.modificationDate != cached.modificationDate),
           jsonlReader.hasUnchangedReadPrefix(at: candidate.url, state: readerState) {
            next = cached
        } else {
            next = CachedTask(
                modificationDate: candidate.modificationDate,
                size: candidate.size,
                readerState: jsonlReader.initialState(fileSize: candidate.size),
                state: SessionState(),
                task: nil
            )
        }

        guard var readerState = next.readerState else { return next }
        var state = next.state
        do {
            try jsonlReader.readLines(
                from: candidate.url,
                fileSize: candidate.size,
                state: &readerState
            ) { data in
                guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
                else { return }
                applyRecord(root, to: &state, fallbackDate: candidate.modificationDate)
            }
        } catch {
            next.task = nil
            return next
        }

        next.modificationDate = candidate.modificationDate
        next.size = candidate.size
        next.readerState = readerState
        next.state = state
        next.task = makeTask(from: state, candidate: candidate)
        return next
    }

    private func makeTask(from state: SessionState, candidate: Candidate) -> AIProgressTask? {
        guard state.isActive || state.isBlocked || state.hasError else { return nil }
        let fallbackID = candidate.url.deletingPathExtension().lastPathComponent
        let sessionID = state.sessionID ?? fallbackID
        let status: AIProgressStatus
        if state.hasError {
            status = .error
        } else if state.isBlocked {
            status = .blocked
        } else {
            status = .running
        }

        return AIProgressTask(
            id: Self.taskID(forSessionID: sessionID),
            provider: .gemini,
            title: "Gemini",
            detail: state.model,
            progress: nil,
            status: status,
            updatedAt: max(state.updatedAt, candidate.modificationDate),
            sessionURL: nil,
            effort: nil,
            startedAt: state.startedAt
        )
    }

    private func applyLegacyJSON(
        _ data: Data,
        to state: inout SessionState,
        fallbackDate: Date
    ) {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return
        }
        applyMetadata(root, to: &state)
        guard let messages = root["messages"] as? [[String: Any]] else { return }
        for message in messages {
            applyRecord(message, to: &state, fallbackDate: fallbackDate)
        }
    }

    private func applyRecord(
        _ root: [String: Any],
        to state: inout SessionState,
        fallbackDate: Date
    ) {
        applyMetadata(root, to: &state)
        if let updates = root["$set"] as? [String: Any] {
            applyMetadata(updates, to: &state)
            return
        }

        let type = (root["type"] as? String)?.lowercased() ?? ""
        let timestamp = Self.parseTimestamp(root["timestamp"])
            ?? Self.parseTimestamp(root["lastUpdated"])
            ?? fallbackDate
        switch type {
        case "user":
            state.isActive = true
            state.isBlocked = false
            state.hasError = false
            state.startedAt = timestamp
            state.updatedAt = max(state.updatedAt, timestamp)
        case "gemini", "assistant", "model":
            if let model = root["model"] as? String, !model.isEmpty {
                state.model = model
            }
            state.updatedAt = max(state.updatedAt, timestamp)
            let toolCalls = Self.toolCalls(in: root)
            if !toolCalls.isEmpty {
                let statuses = toolCalls.compactMap {
                    ($0["status"] as? String)?.lowercased()
                }
                state.hasError = statuses.contains {
                    ["error", "failed", "failure"].contains($0)
                }
                state.isBlocked = statuses.contains {
                    ["awaiting_approval", "awaiting-approval", "awaitingapproval"].contains($0)
                }
                state.isActive = true
            } else if Self.containsFunctionCall(root["content"]) {
                state.isActive = true
                state.isBlocked = false
                state.hasError = false
            } else {
                state.isActive = false
                state.isBlocked = false
                state.hasError = false
            }
        case "error":
            state.isActive = true
            state.isBlocked = false
            state.hasError = true
            state.updatedAt = max(state.updatedAt, timestamp)
        default:
            break
        }
    }

    private func applyMetadata(_ root: [String: Any], to state: inout SessionState) {
        if let sessionID = (root["sessionId"] as? String)
            ?? (root["session_id"] as? String),
           !sessionID.isEmpty {
            state.sessionID = sessionID
        }
        if state.startedAt == nil {
            state.startedAt = Self.parseTimestamp(root["startTime"])
                ?? Self.parseTimestamp(root["start_time"])
        }
    }

    private static func toolCalls(in root: [String: Any]) -> [[String: Any]] {
        (root["toolCalls"] as? [[String: Any]])
            ?? (root["tool_calls"] as? [[String: Any]])
            ?? []
    }

    private static func containsFunctionCall(_ value: Any?) -> Bool {
        guard let parts = value as? [[String: Any]] else { return false }
        return parts.contains { part in
            part["functionCall"] != nil
                || part["function_call"] != nil
                || (part["type"] as? String)?.lowercased() == "function_call"
        }
    }

    private static func parseTimestamp(_ value: Any?) -> Date? {
        if let string = value as? String {
            if let date = try? Date.ISO8601FormatStyle(includingFractionalSeconds: true)
                .parse(string) {
                return date
            }
            return try? Date.ISO8601FormatStyle().parse(string)
        }
        if let number = value as? NSNumber {
            let raw = number.doubleValue
            return Date(timeIntervalSince1970: raw > 1_000_000_000_000 ? raw / 1000 : raw)
        }
        return nil
    }
}
