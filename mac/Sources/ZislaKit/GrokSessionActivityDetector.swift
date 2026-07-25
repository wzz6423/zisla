import Foundation
import ZislaCore

/// 从 Grok CLI `~/.grok/sessions/**/events.jsonl` 推断活动任务。
public final class GrokSessionActivityDetector: AIActivityDetecting {
    private struct Candidate {
        var url: URL
        var sessionID: String
        var modificationDate: Date
        var size: UInt64
    }

    private struct SessionState {
        var isActive = false
        var startedAt: Date?
        var updatedAt: Date = .distantPast
        var hasError = false
        var sessionID: String?
        var model: String?
        /// request_id -> pending count (usually 0/1)
        var pendingPermissionsByID: [String: Int] = [:]
        /// Permissions without request_id tracked as a simple counter.
        var anonymousPermissionCount = 0
    }

    private struct CachedTask {
        var modificationDate: Date
        var readerState: IncrementalJSONLReader.State
        var state: SessionState
        var task: AIProgressTask?
    }

    public let sessionsDirectory: URL
    public let maxSessionFiles: Int

    private let fileManager: FileManager
    private let jsonlReader: IncrementalJSONLReader
    private var cache: [URL: CachedTask] = [:]

    public init(
        sessionsDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".grok/sessions", isDirectory: true),
        maxSessionFiles: Int = 12,
        initialTailBytes: Int = 1_024 * 1_024,
        fileManager: FileManager = .default
    ) {
        self.sessionsDirectory = sessionsDirectory
        self.maxSessionFiles = max(1, maxSessionFiles)
        jsonlReader = IncrementalJSONLReader(initialTailBytes: initialTailBytes)
        self.fileManager = fileManager
    }

    public func activeTasks() throws -> [AIProgressTask] {
        let candidates = recentEventFiles()
        let selectedURLs = Set(candidates.map(\.url))
        cache = cache.filter { selectedURLs.contains($0.key) }
        var tasks: [AIProgressTask] = []

        for candidate in candidates {
            let task: AIProgressTask?
            if let cached = cache[candidate.url],
               cached.modificationDate == candidate.modificationDate,
               cached.readerState.offset == candidate.size {
                task = cached.task
            } else if let next = parseSession(candidate, cached: cache[candidate.url]) {
                cache[candidate.url] = next
                task = next.task
            } else {
                task = nil
            }
            guard let task else { continue }
            tasks.append(task)
        }

        return tasks.sorted {
            if $0.updatedAt != $1.updatedAt { return $0.updatedAt > $1.updatedAt }
            return $0.id < $1.id
        }
    }

    public static func taskID(forSessionID sessionID: String) -> String {
        "grok-session-\(sessionID)"
    }

    private func recentEventFiles() -> [Candidate] {
        guard fileManager.fileExists(atPath: sessionsDirectory.path),
              let enumerator = fileManager.enumerator(
                at: sessionsDirectory,
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
            guard url.lastPathComponent == "events.jsonl",
                  let values = try? url.resourceValues(forKeys: [
                    .isRegularFileKey,
                    .contentModificationDateKey,
                    .fileSizeKey,
                  ]),
                  values.isRegularFile == true else {
                continue
            }
            let sessionID = url.deletingLastPathComponent().lastPathComponent
            guard !sessionID.isEmpty else { continue }
            candidates.append(Candidate(
                url: url,
                sessionID: sessionID,
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

    private func parseSession(
        _ candidate: Candidate,
        cached: CachedTask?
    ) -> CachedTask? {
        var next: CachedTask
        if let cached,
           candidate.size >= cached.readerState.offset,
           !(candidate.size == cached.readerState.offset
               && candidate.modificationDate != cached.modificationDate) {
            next = cached
        } else {
            next = CachedTask(
                modificationDate: candidate.modificationDate,
                readerState: jsonlReader.initialState(fileSize: candidate.size),
                state: SessionState(),
                task: nil
            )
        }

        var readerState = next.readerState
        var state = next.state
        do {
            try jsonlReader.readLines(
                from: candidate.url,
                fileSize: candidate.size,
                state: &readerState
            ) { data in
                guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                    return
                }
                let type = (root["type"] as? String)?.lowercased() ?? ""
                let timestamp = Self.parseTimestamp(root["ts"] ?? root["timestamp"])
                    ?? candidate.modificationDate

                switch type {
                case "turn_started":
                    state.isActive = true
                    state.hasError = false
                    state.startedAt = timestamp
                    state.updatedAt = timestamp
                    if let sessionID = root["session_id"] as? String, !sessionID.isEmpty {
                        state.sessionID = sessionID
                    }
                    if let model = root["model_id"] as? String, !model.isEmpty {
                        state.model = model
                    }
                    state.pendingPermissionsByID.removeAll()
                    state.anonymousPermissionCount = 0
                case "turn_ended":
                    let outcome = ((root["outcome"] as? String)
                        ?? (root["data"] as? [String: Any])?["outcome"] as? String)?
                        .lowercased()
                    state.updatedAt = max(state.updatedAt, timestamp)
                    state.pendingPermissionsByID.removeAll()
                    state.anonymousPermissionCount = 0
                    switch outcome {
                    case "error":
                        state.hasError = true
                        state.isActive = true
                    case "completed", "cancelled":
                        state.hasError = false
                        state.isActive = false
                    default:
                        state.isActive = false
                    }
                case "permission_requested":
                    state.updatedAt = max(state.updatedAt, timestamp)
                    guard state.isActive || state.hasError else { break }
                    if let requestID = Self.requestID(from: root) {
                        state.pendingPermissionsByID[requestID, default: 0] += 1
                    } else {
                        state.anonymousPermissionCount += 1
                    }
                case "permission_resolved":
                    state.updatedAt = max(state.updatedAt, timestamp)
                    if let requestID = Self.requestID(from: root) {
                        if let count = state.pendingPermissionsByID[requestID] {
                            if count <= 1 {
                                state.pendingPermissionsByID.removeValue(forKey: requestID)
                            } else {
                                state.pendingPermissionsByID[requestID] = count - 1
                            }
                        }
                    } else if state.anonymousPermissionCount > 0 {
                        state.anonymousPermissionCount -= 1
                    }
                case "tool_completed":
                    state.updatedAt = max(state.updatedAt, timestamp)
                    let outcome = ((root["outcome"] as? String)
                        ?? (root["data"] as? [String: Any])?["outcome"] as? String)?
                        .lowercased()
                    if outcome == "error" || outcome == "failed" {
                        state.hasError = true
                    } else if outcome == "success"
                        || outcome == "succeeded"
                        || outcome == "completed" {
                        state.hasError = false
                    }
                default:
                    break
                }
            }
        } catch {
            return nil
        }
        next.readerState = readerState
        next.modificationDate = candidate.modificationDate
        next.state = state

        let pendingBlocked = !state.pendingPermissionsByID.isEmpty || state.anonymousPermissionCount > 0
        guard state.isActive || state.hasError || pendingBlocked else {
            next.task = nil
            return next
        }

        let status: AIProgressStatus
        if state.hasError {
            status = .error
        } else if pendingBlocked {
            status = .blocked
        } else {
            status = .running
        }

        next.task = AIProgressTask(
            id: Self.taskID(forSessionID: state.sessionID ?? candidate.sessionID),
            provider: .grok,
            title: "Grok",
            detail: state.model,
            progress: nil,
            status: status,
            updatedAt: max(state.updatedAt, candidate.modificationDate),
            sessionURL: nil,
            effort: nil,
            startedAt: state.startedAt
        )
        return next
    }

    private static func requestID(from root: [String: Any]) -> String? {
        if let id = root["request_id"] as? String, !id.isEmpty { return id }
        if let id = root["requestId"] as? String, !id.isEmpty { return id }
        if let data = root["data"] as? [String: Any] {
            if let id = data["request_id"] as? String, !id.isEmpty { return id }
            if let id = data["requestId"] as? String, !id.isEmpty { return id }
        }
        return nil
    }

    private static func parseTimestamp(_ value: Any?) -> Date? {
        if let string = value as? String {
            if let date = try? Date.ISO8601FormatStyle(includingFractionalSeconds: true).parse(string) {
                return date
            }
            return try? Date.ISO8601FormatStyle().parse(string)
        }
        if let number = value as? NSNumber {
            let double = number.doubleValue
            if double > 1_000_000_000_000 {
                return Date(timeIntervalSince1970: double / 1000)
            }
            return Date(timeIntervalSince1970: double)
        }
        return nil
    }
}
