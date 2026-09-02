import Darwin
import Foundation
import ZislaCore

/// Infers active tasks from `~/.claude/projects/**/*.jsonl` written by Claude Code / Claude VS Code.
public final class ClaudeSessionActivityDetector: AIActivityDetecting {
    private struct Candidate {
        var url: URL
        var modificationDate: Date
        var size: UInt64
    }

    private struct SessionState {
        var isActive = false
        var status: AIProgressStatus = .running
        var startedAt: Date?
        var updatedAt: Date = .distantPast
        var model: String?
        var pendingAskToolUseIDs: Set<String> = []
        var hasError = false
        var failureReason: String?
        var isVSCode = false
        var aiTitle: String?
    }

    private struct CachedTranscript {
        var modificationDate: Date
        var readerState: IncrementalJSONLReader.State
        var stateBySession: [String: SessionState]
        /// `ai-title` is written only once per turn, so the title must remain available after idle sessions are pruned.
        var titleBySession: [String: String]
        var fallbackSessionID: String
        var task: AIProgressTask?
    }

    /// Claude Code writes subagent transcripts to `<session>/subagents/` and reuses the parent session ID.
    private static let sidechainDirectoryName = "subagents"
    private static let syntheticModelPlaceholder = "<synthetic>"

    public let projectsDirectory: URL
    public let sessionsDirectory: URL
    public let maxTranscriptFiles: Int
    public let isProcessAlive: (Int32) -> Bool

    private let fileManager: FileManager
    private let jsonlReader: IncrementalJSONLReader
    private var cache: [URL: CachedTranscript] = [:]

    public init(
        projectsDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/projects", isDirectory: true),
        sessionsDirectory: URL? = nil,
        maxTranscriptFiles: Int = 12,
        initialTailBytes: Int = 1_024 * 1_024,
        isProcessAlive: @escaping (Int32) -> Bool = ClaudeSessionActivityDetector.defaultIsProcessAlive,
        fileManager: FileManager = .default
    ) {
        self.projectsDirectory = projectsDirectory
        self.sessionsDirectory = sessionsDirectory ?? projectsDirectory
            .deletingLastPathComponent()
            .appendingPathComponent("sessions", isDirectory: true)
        self.maxTranscriptFiles = max(1, maxTranscriptFiles)
        jsonlReader = IncrementalJSONLReader(initialTailBytes: initialTailBytes)
        self.isProcessAlive = isProcessAlive
        self.fileManager = fileManager
    }

    public func activeTasks() throws -> [AIProgressTask] {
        let processIdentifiersBySessionID = sessionProcessIdentifiers()
        let candidates = recentTranscripts(liveSessionIDs: Set(processIdentifiersBySessionID.keys))
        let selectedURLs = Set(candidates.map(\.url))
        cache = cache.filter { selectedURLs.contains($0.key) }
        var tasksBySession: [String: AIProgressTask] = [:]

        for candidate in candidates {
            let parsed: AIProgressTask?
            if let cached = cache[candidate.url],
               cached.modificationDate == candidate.modificationDate,
               cached.readerState.offset == candidate.size {
                parsed = cached.task
            } else if let next = parseSession(at: candidate, cached: cache[candidate.url]) {
                cache[candidate.url] = next
                parsed = next.task
            } else {
                parsed = nil
            }
            guard var parsed else { continue }
            if let sessionID = Self.sessionID(forTaskID: parsed.id) {
                parsed.processIdentifier = processIdentifiersBySessionID[sessionID]
            }
            let existing = tasksBySession[parsed.id]
            if let existing, existing.updatedAt > parsed.updatedAt {
                continue
            }
            tasksBySession[parsed.id] = parsed
        }

        return tasksBySession.values.sorted {
            if $0.updatedAt != $1.updatedAt { return $0.updatedAt > $1.updatedAt }
            return $0.id < $1.id
        }
    }

    public static func taskID(forSessionID sessionID: String) -> String {
        "claude-session-\(sessionID)"
    }

    public static func defaultIsProcessAlive(_ pid: Int32) -> Bool {
        guard pid > 0 else { return false }
        if kill(pid, 0) == 0 { return true }
        return errno == EPERM
    }

    private func recentTranscripts(liveSessionIDs: Set<String>) -> [Candidate] {
        guard fileManager.fileExists(atPath: projectsDirectory.path),
              let enumerator = fileManager.enumerator(
                at: projectsDirectory,
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
            if url.lastPathComponent == Self.sidechainDirectoryName {
                enumerator.skipDescendants()
                continue
            }
            guard url.pathExtension == "jsonl",
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

        let sorted = candidates.sorted {
            if $0.modificationDate != $1.modificationDate {
                return $0.modificationDate > $1.modificationDate
            }
            return $0.url.path < $1.url.path
        }
        guard sorted.count > maxTranscriptFiles else { return sorted }
        // Concurrent CLI runs can fill the newest-file quota, so live sessions must always be included to avoid missing tasks.
        return Array(sorted.prefix(maxTranscriptFiles))
            + sorted.dropFirst(maxTranscriptFiles).filter {
                liveSessionIDs.contains($0.url.deletingPathExtension().lastPathComponent)
            }
    }

    private func parseSession(
        at candidate: Candidate,
        cached: CachedTranscript?
    ) -> CachedTranscript? {
        var next: CachedTranscript
        if let cached,
           candidate.size >= cached.readerState.offset,
           !(candidate.size == cached.readerState.offset
               && candidate.modificationDate != cached.modificationDate),
           jsonlReader.hasUnchangedReadPrefix(at: candidate.url, state: cached.readerState) {
            next = cached
        } else {
            next = CachedTranscript(
                modificationDate: candidate.modificationDate,
                readerState: jsonlReader.initialState(fileSize: candidate.size),
                stateBySession: [:],
                titleBySession: cached?.titleBySession ?? [:],
                fallbackSessionID: candidate.url.deletingPathExtension().lastPathComponent,
                task: nil
            )
        }

        var readerState = next.readerState
        do {
            try jsonlReader.readLines(
                from: candidate.url,
                fileSize: candidate.size,
                state: &readerState
            ) { data in
                guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                    return
                }
                // Inline subagent records reuse the parent session ID and would contaminate the parent task's activity state.
                if root["isSidechain"] as? Bool == true { return }
                let type = (root["type"] as? String)?.lowercased() ?? ""
                let sessionID = ((root["sessionId"] as? String)
                    ?? (root["session_id"] as? String))?
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                let sid: String
                if let sessionID, !sessionID.isEmpty {
                    next.fallbackSessionID = sessionID
                    sid = sessionID
                } else {
                    sid = next.fallbackSessionID
                }
                var state = next.stateBySession[sid] ?? SessionState()

                if (root["entrypoint"] as? String)?.lowercased() == "claude-vscode" {
                    state.isVSCode = true
                }

                let timestamp = Self.parseTimestamp(root["timestamp"])
                    ?? candidate.modificationDate
                if let model = Self.extractModel(root) {
                    state.model = model
                }
                if let aiTitle = Self.extractAITitle(root) {
                    state.aiTitle = aiTitle
                    next.titleBySession[sid] = aiTitle
                }

                switch type {
                case "user":
                    applyUserRecord(root, timestamp: timestamp, state: &state)
                case "assistant":
                    applyAssistantRecord(root, timestamp: timestamp, state: &state)
                default:
                    break
                }
                next.stateBySession[sid] = state
            }
        } catch {
            return nil
        }
        next.readerState = readerState
        next.modificationDate = candidate.modificationDate
        next.stateBySession = next.stateBySession.filter {
            $0.value.isActive || $0.value.hasError || !$0.value.pendingAskToolUseIDs.isEmpty
        }

        let active = next.stateBySession
            .filter { $0.value.isActive || $0.value.hasError }
            .max { lhs, rhs in
                if lhs.value.updatedAt != rhs.value.updatedAt {
                    return lhs.value.updatedAt < rhs.value.updatedAt
                }
                return lhs.key > rhs.key
            }
        guard let active else {
            next.task = nil
            return next
        }

        var status: AIProgressStatus = .running
        if active.value.hasError {
            status = .error
        } else if !active.value.pendingAskToolUseIDs.isEmpty {
            status = .blocked
        } else if active.value.isActive {
            status = .running
        } else {
            next.task = nil
            return next
        }

        let updatedAt = max(active.value.updatedAt, candidate.modificationDate)
        let displayTitle = active.value.aiTitle
            ?? next.titleBySession[active.key]
            ?? (active.value.isVSCode ? "Claude Code (VS Code)" : "Claude")
        next.task = AIProgressTask(
            id: Self.taskID(forSessionID: active.key),
            provider: .claude,
            title: displayTitle,
            detail: active.value.model,
            progress: nil,
            status: status,
            updatedAt: updatedAt,
            sessionURL: active.value.isVSCode ? Self.vsCodeSessionURL(for: active.key) : nil,
            effort: nil,
            startedAt: active.value.startedAt,
            failureReason: status == .error ? active.value.failureReason : nil
        )
        return next
    }

    private static func vsCodeSessionURL(for sessionID: String) -> URL? {
        var components = URLComponents()
        components.scheme = "vscode"
        components.host = "anthropic.claude-code"
        components.path = "/open"
        components.queryItems = [URLQueryItem(name: "session", value: sessionID)]
        return components.url
    }

    private func applyUserRecord(
        _ root: [String: Any],
        timestamp: Date,
        state: inout SessionState
    ) {
        let contents = Self.messageContents(root["message"] ?? root)
        let toolResults = contents.filter {
            (($0["type"] as? String)?.lowercased() ?? "") == "tool_result"
        }

        if !toolResults.isEmpty {
            for result in toolResults {
                if let toolUseID = (result["tool_use_id"] as? String)
                    ?? (result["toolUseId"] as? String) {
                    state.pendingAskToolUseIDs.remove(toolUseID)
                }
                if result["is_error"] as? Bool == true || result["isError"] as? Bool == true {
                    state.hasError = true
                    state.failureReason = "工具执行失败"
                } else {
                    // Successful tool_result can clear error.
                    state.hasError = false
                    state.failureReason = nil
                }
            }
            state.updatedAt = max(state.updatedAt, timestamp)
            // tool_result-only user records do not start a new turn.
            if state.isActive || state.hasError || !state.pendingAskToolUseIDs.isEmpty {
                // keep active if we were mid-turn waiting for tools
            }
            return
        }

        // Ordinary user message starts a new turn.
        state.isActive = true
        state.hasError = false
        state.failureReason = nil
        state.pendingAskToolUseIDs.removeAll()
        state.startedAt = timestamp
        state.updatedAt = timestamp
    }

    private func applyAssistantRecord(
        _ root: [String: Any],
        timestamp: Date,
        state: inout SessionState
    ) {
        if root["isApiErrorMessage"] as? Bool == true
            || root["apiErrorStatus"] != nil
            || root["error"] != nil {
            state.isActive = true
            state.hasError = true
            state.failureReason = Self.apiFailureReason(from: root["apiErrorStatus"])
            state.updatedAt = max(state.updatedAt, timestamp)
            if state.startedAt == nil {
                state.startedAt = timestamp
            }
            return
        }

        let message = root["message"] as? [String: Any] ?? [:]
        if let model = Self.extractModel(root) {
            state.model = model
        }
        let stopReason = ((message["stop_reason"] as? String) ?? (root["stop_reason"] as? String))?
            .lowercased()
        let contents = Self.messageContents(message)

        for item in contents {
            let itemType = (item["type"] as? String)?.lowercased() ?? ""
            guard itemType == "tool_use" else { continue }
            let name = (item["name"] as? String)?.lowercased() ?? ""
            if name == "askuserquestion" {
                if let id = item["id"] as? String {
                    state.pendingAskToolUseIDs.insert(id)
                }
            }
        }

        state.updatedAt = max(state.updatedAt, timestamp)
        if state.startedAt == nil {
            state.startedAt = timestamp
        }

        switch stopReason {
        case "tool_use":
            state.isActive = true
        case "end_turn", "stop_sequence":
            // End of turn unless still blocked waiting for AskUserQuestion answer.
            if state.pendingAskToolUseIDs.isEmpty && !state.hasError {
                state.isActive = false
            } else {
                state.isActive = true
            }
        default:
            // Missing stop_reason with content: treat as still potentially active only if tool_use.
            if stopReason == nil {
                let hasToolUse = contents.contains {
                    (($0["type"] as? String)?.lowercased() ?? "") == "tool_use"
                }
                if hasToolUse {
                    state.isActive = true
                }
            }
        }
    }

    private static func messageContents(_ value: Any?) -> [[String: Any]] {
        if let message = value as? [String: Any] {
            if let content = message["content"] as? [[String: Any]] {
                return content
            }
            if let content = message["content"] as? [String: Any] {
                return [content]
            }
            // content may be a string for plain user text
            return []
        }
        if let list = value as? [[String: Any]] {
            return list
        }
        return []
    }

    private static func extractModel(_ root: [String: Any]) -> String? {
        if let model = root["model"] as? String, isRealModel(model) { return model }
        if let message = root["message"] as? [String: Any],
           let model = message["model"] as? String,
           isRealModel(model) {
            return model
        }
        return nil
    }

    /// Claude Code assigns a placeholder model name to synthetic messages; overwriting the real model would show `<synthetic>` in the details.
    private static func isRealModel(_ model: String) -> Bool {
        !model.isEmpty && model != syntheticModelPlaceholder
    }

    private static func extractAITitle(_ root: [String: Any]) -> String? {
        if let title = root["aiTitle"] as? String {
            let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
        return nil
    }

    private static func sessionID(forTaskID taskID: String) -> String? {
        let prefix = "claude-session-"
        guard taskID.hasPrefix(prefix) else { return nil }
        let sessionID = String(taskID.dropFirst(prefix.count))
        return sessionID.isEmpty ? nil : sessionID
    }

    private func sessionProcessIdentifiers() -> [String: Int32] {
        guard let urls = try? fileManager.contentsOfDirectory(
            at: sessionsDirectory,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return [:]
        }

        var result: [String: Int32] = [:]
        for url in urls where url.pathExtension == "json" {
            guard let data = try? Data(contentsOf: url),
                  let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let sessionID = ((root["sessionId"] as? String) ?? (root["session_id"] as? String))?
                    .trimmingCharacters(in: .whitespacesAndNewlines),
                  !sessionID.isEmpty,
                  let processIdentifier = Self.processIdentifier(root["pid"]),
                  url.deletingPathExtension().lastPathComponent == String(processIdentifier),
                  isProcessAlive(processIdentifier) else {
                continue
            }
            result[sessionID] = processIdentifier
        }
        return result
    }

    private static func processIdentifier(_ value: Any?) -> Int32? {
        let processIdentifier: Int32?
        if let number = value as? NSNumber {
            processIdentifier = number.int32Value
        } else if let string = value as? String {
            processIdentifier = Int32(string)
        } else {
            processIdentifier = nil
        }
        guard let processIdentifier, processIdentifier > 0 else { return nil }
        return processIdentifier
    }

    private static func apiFailureReason(from value: Any?) -> String {
        if let status = value as? NSNumber { return "API 请求失败（HTTP \(status.intValue)）" }
        if let status = value as? String, !status.isEmpty { return "API 请求失败（HTTP \(status)）" }
        return "API 请求失败，未提供详细原因"
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
            // Heuristic: ms vs s
            if double > 1_000_000_000_000 {
                return Date(timeIntervalSince1970: double / 1000)
            }
            return Date(timeIntervalSince1970: double)
        }
        return nil
    }
}
