import Darwin
import Foundation
import ZislaCore

/// Infers active tasks from `${QWEN_HOME:-~/.qwen}/projects/**/*.runtime.json` and transcripts.
public final class QwenSessionActivityDetector: AIActivityDetecting {
    private struct Candidate {
        var runtimeURL: URL
        var runtimeModificationDate: Date
        var runtimeSize: UInt64
        var transcriptURL: URL
        var transcriptModificationDate: Date
        var transcriptSize: UInt64

        var activityModificationDate: Date {
            max(runtimeModificationDate, transcriptModificationDate)
        }
    }

    private struct RuntimeSidecar {
        var pid: Int32
        var sessionID: String
        var workDir: String?
        var qwenVersion: String?
        var startedAt: Date?
    }

    private struct TurnState {
        var isActive = false
        var startedAt: Date?
        var updatedAt: Date = .distantPast
        var hasError = false
        var pendingAskUser = false
        var model: String?
    }

    private struct CachedTask {
        var runtimeModificationDate: Date
        var runtimeSize: UInt64
        var transcriptModificationDate: Date
        var transcriptSize: UInt64
        var readerState: IncrementalJSONLReader.State
        var state: TurnState
        var task: AIProgressTask?
    }

    public let projectsDirectory: URL
    public let maxRuntimeFiles: Int
    public let isProcessAlive: (Int32) -> Bool

    private let fileManager: FileManager
    private let jsonlReader: IncrementalJSONLReader
    private var cache: [URL: CachedTask] = [:]

    public init(
        projectsDirectory: URL? = nil,
        maxRuntimeFiles: Int = 12,
        initialTailBytes: Int = 1_024 * 1_024,
        isProcessAlive: @escaping (Int32) -> Bool = QwenSessionActivityDetector.defaultIsProcessAlive,
        fileManager: FileManager = .default
    ) {
        if let projectsDirectory {
            self.projectsDirectory = projectsDirectory
        } else if let runtimeRoot = Self.runtimeRootPath(
            environment: ProcessInfo.processInfo.environment
        ) {
            self.projectsDirectory = URL(fileURLWithPath: runtimeRoot, isDirectory: true)
                .appendingPathComponent("projects", isDirectory: true)
        } else {
            self.projectsDirectory = FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent(".qwen/projects", isDirectory: true)
        }
        self.maxRuntimeFiles = max(1, maxRuntimeFiles)
        jsonlReader = IncrementalJSONLReader(initialTailBytes: initialTailBytes)
        self.isProcessAlive = isProcessAlive
        self.fileManager = fileManager
    }

    public func activeTasks() throws -> [AIProgressTask] {
        let candidates = recentRuntimes()
        let selectedURLs = Set(candidates.map(\.runtimeURL))
        cache = cache.filter { selectedURLs.contains($0.key) }
        var tasksBySession: [String: AIProgressTask] = [:]
        var liveCandidateCount = 0

        for candidate in candidates {
            guard let sidecar = parseRuntime(at: candidate.runtimeURL),
                  isProcessAlive(sidecar.pid) else {
                continue
            }
            liveCandidateCount += 1
            guard liveCandidateCount <= maxRuntimeFiles else { break }

            let task: AIProgressTask?
            if let cached = cache[candidate.runtimeURL],
               cached.runtimeModificationDate == candidate.runtimeModificationDate,
               cached.runtimeSize == candidate.runtimeSize,
               cached.transcriptModificationDate == candidate.transcriptModificationDate,
               cached.transcriptSize == candidate.transcriptSize {
                task = cached.task
            } else {
                let next = parseTranscript(
                    candidate: candidate,
                    sidecar: sidecar,
                    cached: cache[candidate.runtimeURL]
                )
                cache[candidate.runtimeURL] = next
                task = next.task
            }
            guard let task else { continue }
            let existing = tasksBySession[task.id]
            if let existing, existing.updatedAt > task.updatedAt {
                continue
            }
            tasksBySession[task.id] = task
        }

        return tasksBySession.values.sorted {
            if $0.updatedAt != $1.updatedAt { return $0.updatedAt > $1.updatedAt }
            return $0.id < $1.id
        }
    }

    public static func taskID(forSessionID sessionID: String) -> String {
        "qwen-session-\(sessionID)"
    }

    public static func defaultIsProcessAlive(_ pid: Int32) -> Bool {
        if pid <= 0 { return false }
        let result = kill(pid, 0)
        if result == 0 { return true }
        // EPERM means the process exists but we lack permission.
        return errno == EPERM
    }

    static func runtimeRootPath(environment: [String: String]) -> String? {
        for key in ["QWEN_RUNTIME_DIR", "QWEN_HOME"] {
            if let value = environment[key], !value.isEmpty {
                return value
            }
        }
        return nil
    }

    private func recentRuntimes() -> [Candidate] {
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
            guard url.lastPathComponent.hasSuffix(".runtime.json") ||
                    (url.pathExtension == "json" && url.deletingPathExtension().pathExtension == "runtime"),
                  let values = try? url.resourceValues(forKeys: [
                    .isRegularFileKey,
                    .contentModificationDateKey,
                    .fileSizeKey,
                  ]),
                  values.isRegularFile == true else {
                continue
            }
            let transcriptURL = Self.transcriptURL(for: url)
            let transcriptValues = try? transcriptURL.resourceValues(forKeys: [
                .isRegularFileKey,
                .contentModificationDateKey,
                .fileSizeKey,
            ])
            candidates.append(Candidate(
                runtimeURL: url,
                runtimeModificationDate: values.contentModificationDate ?? .distantPast,
                runtimeSize: UInt64(max(0, values.fileSize ?? 0)),
                transcriptURL: transcriptURL,
                transcriptModificationDate: transcriptValues?.isRegularFile == true
                    ? transcriptValues?.contentModificationDate ?? .distantPast
                    : .distantPast,
                transcriptSize: transcriptValues?.isRegularFile == true
                    ? UInt64(max(0, transcriptValues?.fileSize ?? 0))
                    : 0
            ))
        }

        return candidates.sorted {
            if $0.activityModificationDate != $1.activityModificationDate {
                return $0.activityModificationDate > $1.activityModificationDate
            }
            return $0.runtimeURL.path < $1.runtimeURL.path
        }
    }

    private func parseRuntime(at url: URL) -> RuntimeSidecar? {
        guard let data = try? Data(contentsOf: url),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        // Tolerate missing schema_version; require pid + session_id.
        let pidValue = root["pid"]
        let pid: Int32?
        if let number = pidValue as? NSNumber {
            pid = number.int32Value
        } else if let string = pidValue as? String {
            pid = Int32(string)
        } else {
            pid = nil
        }
        guard let pid, pid > 0 else { return nil }
        let sessionID = ((root["session_id"] as? String) ?? (root["sessionId"] as? String))?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let sessionID, !sessionID.isEmpty else { return nil }

        return RuntimeSidecar(
            pid: pid,
            sessionID: sessionID,
            workDir: root["work_dir"] as? String,
            qwenVersion: root["qwen_version"] as? String,
            startedAt: Self.parseTimestamp(root["started_at"])
        )
    }

    private func parseTranscript(
        candidate: Candidate,
        sidecar: RuntimeSidecar,
        cached: CachedTask?
    ) -> CachedTask {
        var next: CachedTask
        if let cached,
           cached.runtimeModificationDate == candidate.runtimeModificationDate,
           cached.runtimeSize == candidate.runtimeSize,
           candidate.transcriptSize >= cached.readerState.offset,
           !(candidate.transcriptSize == cached.readerState.offset
               && candidate.transcriptModificationDate != cached.transcriptModificationDate),
           jsonlReader.hasUnchangedReadPrefix(
               at: candidate.transcriptURL,
               state: cached.readerState
           ) {
            next = cached
        } else {
            var initialState = TurnState()
            if let startedAt = sidecar.startedAt {
                initialState.startedAt = startedAt
                initialState.updatedAt = startedAt
            }
            next = CachedTask(
                runtimeModificationDate: candidate.runtimeModificationDate,
                runtimeSize: candidate.runtimeSize,
                transcriptModificationDate: candidate.transcriptModificationDate,
                transcriptSize: candidate.transcriptSize,
                readerState: jsonlReader.initialState(fileSize: candidate.transcriptSize),
                state: initialState,
                task: nil
            )
        }

        var readerState = next.readerState
        var state = next.state
        do {
            try jsonlReader.readLines(
                from: candidate.transcriptURL,
                fileSize: candidate.transcriptSize,
                state: &readerState
            ) { data in
                guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
                else { return }
                applyTranscriptRecord(
                    root,
                    state: &state,
                    fallbackDate: candidate.activityModificationDate
                )
            }
        } catch {
            next.task = nil
            return next
        }

        next.runtimeModificationDate = candidate.runtimeModificationDate
        next.runtimeSize = candidate.runtimeSize
        next.transcriptModificationDate = candidate.transcriptModificationDate
        next.transcriptSize = candidate.transcriptSize
        next.readerState = readerState
        next.state = state
        next.task = makeTask(from: state, candidate: candidate, sidecar: sidecar)
        return next
    }

    private func makeTask(
        from state: TurnState,
        candidate: Candidate,
        sidecar: RuntimeSidecar
    ) -> AIProgressTask? {
        guard state.isActive || state.hasError || state.pendingAskUser else {
            return nil
        }

        let status: AIProgressStatus
        if state.hasError {
            status = .error
        } else if state.pendingAskUser {
            status = .blocked
        } else {
            status = .running
        }

        let detail = state.model ?? sidecar.qwenVersion
        return AIProgressTask(
            id: Self.taskID(forSessionID: sidecar.sessionID),
            provider: .qwen,
            title: "千问",
            detail: detail,
            progress: nil,
            status: status,
            updatedAt: max(state.updatedAt, candidate.activityModificationDate),
            sessionURL: nil,
            effort: nil,
            startedAt: state.startedAt,
            processIdentifier: sidecar.pid
        )
    }

    private static func transcriptURL(for runtimeURL: URL) -> URL {
        let base = runtimeURL.deletingPathExtension()
        let name = base.pathExtension == "runtime"
            ? base.deletingPathExtension().lastPathComponent + ".jsonl"
            : base.lastPathComponent + ".jsonl"
        return runtimeURL.deletingLastPathComponent().appendingPathComponent(name)
    }

    private func applyTranscriptRecord(
        _ root: [String: Any],
        state: inout TurnState,
        fallbackDate: Date
    ) {
        let type = (root["type"] as? String)?.lowercased() ?? ""
        let timestamp = Self.parseTimestamp(root["timestamp"] ?? root["ts"]) ?? fallbackDate

        if let model = root["model"] as? String, !model.isEmpty {
            state.model = model
        }
        if let message = root["message"] as? [String: Any],
           let model = message["model"] as? String,
           !model.isEmpty {
            state.model = model
        }

        switch type {
        case "user":
            // Ordinary user starts a turn. tool-ish user payloads still count as user start
            // unless clearly only tool plumbing — keep simple: any user starts.
            state.isActive = true
            state.hasError = false
            state.pendingAskUser = false
            state.startedAt = timestamp
            state.updatedAt = timestamp
        case "assistant":
            state.updatedAt = max(state.updatedAt, timestamp)
            let parts = Self.messageParts(root)
            let functionCalls = parts.compactMap { part -> [String: Any]? in
                if let call = part["functionCall"] as? [String: Any] { return call }
                if (part["type"] as? String)?.lowercased() == "function_call" { return part }
                if let call = part["function_call"] as? [String: Any] { return call }
                return nil
            }
            if functionCalls.isEmpty {
                // Assistant without functionCall ends the turn.
                if !state.hasError {
                    state.isActive = false
                }
                state.pendingAskUser = false
            } else {
                state.isActive = true
                let hasAsk = functionCalls.contains { call in
                    let name = ((call["name"] as? String) ?? (call["functionName"] as? String))?
                        .lowercased() ?? ""
                    return name == "ask_user_question" || name == "askuserquestion"
                }
                state.pendingAskUser = hasAsk
            }
        case "tool_result":
            state.updatedAt = max(state.updatedAt, timestamp)
            let status = Self.toolResultStatus(root)?.lowercased()
            if let status {
                if ["error", "failed", "failure"].contains(status) {
                    state.hasError = true
                    state.isActive = true
                } else if ["success", "succeeded", "completed", "ok"].contains(status) {
                    state.hasError = false
                }
            }
            // Completing ask_user_question clears blocked if we see any tool_result
            // for it — without reliable id matching, any tool_result clears pending ask.
            if state.pendingAskUser {
                state.pendingAskUser = false
            }
        default:
            break
        }
    }

    private static func messageParts(_ root: [String: Any]) -> [[String: Any]] {
        if let message = root["message"] as? [String: Any] {
            if let parts = message["parts"] as? [[String: Any]] { return parts }
            if let content = message["content"] as? [[String: Any]] { return content }
        }
        if let parts = root["parts"] as? [[String: Any]] { return parts }
        return []
    }

    private static func toolResultStatus(_ root: [String: Any]) -> String? {
        if let result = root["toolCallResult"] as? [String: Any] {
            if let status = result["status"] as? String { return status }
        }
        if let result = root["tool_call_result"] as? [String: Any] {
            if let status = result["status"] as? String { return status }
        }
        if let status = root["status"] as? String { return status }
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
