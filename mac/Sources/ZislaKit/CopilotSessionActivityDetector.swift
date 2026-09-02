import Foundation
import ZislaCore

/// Infers active tasks from VS Code Copilot Chat transcripts and Copilot CLI workspace state.
public final class CopilotSessionActivityDetector: AIActivityDetecting {
    private struct TranscriptCandidate {
        var url: URL
        var modificationDate: Date
        var size: UInt64
    }

    private struct TranscriptState {
        var sessionID: String?
        var isActive = false
        var startedAt: Date?
        var updatedAt: Date = .distantPast
        var hasError = false
        var currentTurnHasToolRequests = false
    }

    private struct CachedTranscript {
        var modificationDate: Date
        var readerState: IncrementalJSONLReader.State
        var state: TranscriptState
        var task: AIProgressTask?
    }

    private struct CLISession {
        var id: String
        var workingDirectory: String?
        var startedAt: Date?
        var updatedAt: Date
    }

    public let workspaceStorageDirectories: [URL]
    public let cliSessionStateDirectory: URL
    public let maxTranscriptFiles: Int
    public let maxCLISessions: Int

    private let fileManager: FileManager
    private let jsonlReader: IncrementalJSONLReader
    private var transcriptCache: [URL: CachedTranscript] = [:]

    public init(
        workspaceStorageDirectories: [URL]? = nil,
        cliSessionStateDirectory: URL? = nil,
        maxTranscriptFiles: Int = 12,
        maxCLISessions: Int = 12,
        initialTailBytes: Int = 1_024 * 1_024,
        fileManager: FileManager = .default
    ) {
        let home = fileManager.homeDirectoryForCurrentUser
        self.workspaceStorageDirectories = workspaceStorageDirectories ?? [
            home.appendingPathComponent("Library/Application Support/Code/User/workspaceStorage", isDirectory: true),
            home.appendingPathComponent("Library/Application Support/Code - Insiders/User/workspaceStorage", isDirectory: true),
            home.appendingPathComponent("Library/Application Support/VSCodium/User/workspaceStorage", isDirectory: true),
            home.appendingPathComponent("Library/Application Support/Cursor/User/workspaceStorage", isDirectory: true),
            home.appendingPathComponent("Library/Application Support/Windsurf/User/workspaceStorage", isDirectory: true),
        ]
        self.cliSessionStateDirectory = cliSessionStateDirectory
            ?? home.appendingPathComponent(".copilot/session-state", isDirectory: true)
        self.maxTranscriptFiles = max(1, maxTranscriptFiles)
        self.maxCLISessions = max(1, maxCLISessions)
        jsonlReader = IncrementalJSONLReader(initialTailBytes: initialTailBytes)
        self.fileManager = fileManager
    }

    public func activeTasks() throws -> [AIProgressTask] {
        var tasksByID: [String: AIProgressTask] = [:]

        for task in activeVSCodeTasks() + activeCLITasks() {
            if let existing = tasksByID[task.id], existing.updatedAt >= task.updatedAt {
                continue
            }
            tasksByID[task.id] = task
        }

        return tasksByID.values.sorted {
            if $0.updatedAt != $1.updatedAt { return $0.updatedAt > $1.updatedAt }
            return $0.id < $1.id
        }
    }

    public static func vsCodeTaskID(forSessionID sessionID: String) -> String {
        "copilot-vscode-session-\(sessionID)"
    }

    public static func cliTaskID(forSessionID sessionID: String) -> String {
        "copilot-cli-session-\(sessionID)"
    }

    private func activeVSCodeTasks() -> [AIProgressTask] {
        let candidates = recentTranscriptFiles()
        let selectedURLs = Set(candidates.map(\.url))
        transcriptCache = transcriptCache.filter { selectedURLs.contains($0.key) }

        return candidates.compactMap { candidate in
            let task: AIProgressTask?
            if let cached = transcriptCache[candidate.url],
               cached.modificationDate == candidate.modificationDate,
               cached.readerState.offset == candidate.size {
                task = cached.task
            } else if let next = parseTranscript(candidate, cached: transcriptCache[candidate.url]) {
                transcriptCache[candidate.url] = next
                task = next.task
            } else {
                task = nil
            }
            return task
        }
    }

    private func recentTranscriptFiles() -> [TranscriptCandidate] {
        var candidates: [TranscriptCandidate] = []
        for root in workspaceStorageDirectories where fileManager.fileExists(atPath: root.path) {
            guard let enumerator = fileManager.enumerator(
                at: root,
                includingPropertiesForKeys: [
                    .isRegularFileKey,
                    .contentModificationDateKey,
                    .fileSizeKey,
                ],
                options: [.skipsHiddenFiles]
            ) else {
                continue
            }

            for case let url as URL in enumerator {
                guard url.pathExtension == "jsonl",
                      url.deletingLastPathComponent().lastPathComponent == "chatSessions",
                      let values = try? url.resourceValues(forKeys: [
                        .isRegularFileKey,
                        .contentModificationDateKey,
                        .fileSizeKey,
                      ]),
                      values.isRegularFile == true else {
                    continue
                }
                candidates.append(TranscriptCandidate(
                    url: url,
                    modificationDate: values.contentModificationDate ?? .distantPast,
                    size: UInt64(max(0, values.fileSize ?? 0))
                ))
            }
        }

        return Array(candidates.sorted {
            if $0.modificationDate != $1.modificationDate {
                return $0.modificationDate > $1.modificationDate
            }
            return $0.url.path < $1.url.path
        }.prefix(maxTranscriptFiles))
    }

    private func parseTranscript(
        _ candidate: TranscriptCandidate,
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
                state: TranscriptState(),
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
                let eventData = root["data"] as? [String: Any] ?? [:]
                let timestamp = Self.parseTimestamp(root["timestamp"]) ?? candidate.modificationDate

                if let sessionID = Self.nonEmptyString(eventData["sessionId"]), state.sessionID == nil {
                    state.sessionID = sessionID
                }
                state.updatedAt = max(state.updatedAt, timestamp)

                switch type {
                case "session.start":
                    state.sessionID = Self.nonEmptyString(eventData["sessionId"]) ?? state.sessionID
                    state.startedAt = Self.parseTimestamp(eventData["startTime"]) ?? timestamp
                case "user.message":
                    state.isActive = true
                    state.hasError = false
                    state.currentTurnHasToolRequests = false
                    state.startedAt = state.startedAt ?? timestamp
                case "assistant.turn_start":
                    state.isActive = true
                case "assistant.message":
                    state.currentTurnHasToolRequests = !(eventData["toolRequests"] as? [Any] ?? []).isEmpty
                case "assistant.turn_end":
                    state.isActive = state.currentTurnHasToolRequests
                    state.currentTurnHasToolRequests = false
                case "tool.execution_complete":
                    if eventData["success"] as? Bool == false {
                        state.isActive = true
                        state.hasError = true
                    }
                case "session.shutdown":
                    state.isActive = false
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

        guard (state.isActive || state.hasError), let sessionID = state.sessionID else {
            next.task = nil
            return next
        }
        next.task = AIProgressTask(
            id: Self.vsCodeTaskID(forSessionID: sessionID),
            provider: .copilot,
            title: "GitHub Copilot (VS Code)",
            detail: nil,
            progress: nil,
            status: state.hasError ? .error : .running,
            updatedAt: max(state.updatedAt, candidate.modificationDate),
            sessionURL: nil,
            effort: nil,
            startedAt: state.startedAt
        )
        return next
    }

    private func activeCLITasks() -> [AIProgressTask] {
        guard fileManager.fileExists(atPath: cliSessionStateDirectory.path),
              let directories = try? fileManager.contentsOfDirectory(
                at: cliSessionStateDirectory,
                includingPropertiesForKeys: [.isDirectoryKey, .contentModificationDateKey],
                options: [.skipsHiddenFiles]
              ) else {
            return []
        }

        let sessions = directories.compactMap(parseCLISession(at:)).sorted {
            if $0.updatedAt != $1.updatedAt { return $0.updatedAt > $1.updatedAt }
            return $0.id < $1.id
        }
        return sessions.prefix(maxCLISessions).map { session in
            AIProgressTask(
                id: Self.cliTaskID(forSessionID: session.id),
                provider: .copilot,
                title: "GitHub Copilot CLI",
                detail: session.workingDirectory,
                progress: nil,
                status: .running,
                updatedAt: session.updatedAt,
                sessionURL: nil,
                effort: nil,
                startedAt: session.startedAt
            )
        }
    }

    private func parseCLISession(at directory: URL) -> CLISession? {
        guard (try? directory.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else {
            return nil
        }
        let stateURL = directory.appendingPathComponent("workspace.yaml")
        guard let content = try? String(contentsOf: stateURL, encoding: .utf8) else {
            return nil
        }

        var values: [String: String] = [:]
        for line in content.split(whereSeparator: \.isNewline) {
            guard let separator = line.firstIndex(of: ":") else { continue }
            let key = String(line[..<separator]).trimmingCharacters(in: .whitespaces)
            let value = String(line[line.index(after: separator)...])
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .trimmingCharacters(in: CharacterSet(charactersIn: "\\\"'"))
            if ["id", "cwd", "created_at", "updated_at"].contains(key) {
                values[key] = value
            }
        }

        guard let id = Self.nonEmptyString(values["id"]) else { return nil }
        let fallbackDate = (try? stateURL.resourceValues(forKeys: [.contentModificationDateKey]))?
            .contentModificationDate ?? .distantPast
        return CLISession(
            id: id,
            workingDirectory: Self.nonEmptyString(values["cwd"]),
            startedAt: Self.parseTimestamp(values["created_at"]),
            updatedAt: Self.parseTimestamp(values["updated_at"]) ?? fallbackDate
        )
    }

    private static func nonEmptyString(_ value: Any?) -> String? {
        guard let value = value as? String else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func parseTimestamp(_ value: Any?) -> Date? {
        if let string = value as? String {
            if let date = try? Date.ISO8601FormatStyle(includingFractionalSeconds: true).parse(string) {
                return date
            }
            return try? Date.ISO8601FormatStyle().parse(string)
        }
        if let number = value as? NSNumber {
            let seconds = number.doubleValue > 1_000_000_000_000
                ? number.doubleValue / 1_000
                : number.doubleValue
            return Date(timeIntervalSince1970: seconds)
        }
        return nil
    }
}
