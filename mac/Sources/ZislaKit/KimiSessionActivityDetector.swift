import Foundation
import ZislaCore

/// Infers active tasks from the session wire log in the Kimi Code shared directory.
///
/// The Kimi Code VS Code extension and CLI share `KIMI_CODE_HOME` (default `~/.kimi-code`).
/// The official extension currently provides no URI handler to open a session by ID, so only monitoring is done — no synthetic deep links.
public final class KimiSessionActivityDetector: AIActivityDetecting {
    private struct Candidate {
        var sessionID: String
        var stateURL: URL
        var wireURL: URL
        var modificationDate: Date
        var size: UInt64
    }

    private struct SessionMetadata {
        var title: String?
        var archived: Bool
    }

    private struct TurnState {
        var isActive = false
        var isBlocked = false
        var hasError = false
        var startedAt: Date?
        var updatedAt: Date = .distantPast
        var model: String?
    }

    private struct CachedTask {
        var modificationDate: Date
        var readerState: IncrementalJSONLReader.State
        var state: TurnState
    }

    public let homeDirectory: URL
    public let maxSessionFiles: Int

    private let fileManager: FileManager
    private let jsonlReader: IncrementalJSONLReader
    private var cache: [URL: CachedTask] = [:]

    public init(
        homeDirectory: URL? = nil,
        maxSessionFiles: Int = 12,
        initialTailBytes: Int = 1_024 * 1_024,
        fileManager: FileManager = .default
    ) {
        self.homeDirectory = homeDirectory ?? Self.defaultHomeDirectory(
            environment: ProcessInfo.processInfo.environment,
            fileManager: fileManager
        )
        self.maxSessionFiles = max(1, maxSessionFiles)
        jsonlReader = IncrementalJSONLReader(initialTailBytes: initialTailBytes)
        self.fileManager = fileManager
    }

    public func activeTasks() throws -> [AIProgressTask] {
        let candidates = recentWireLogs()
        let selectedURLs = Set(candidates.map(\.wireURL))
        cache = cache.filter { selectedURLs.contains($0.key) }
        var tasks: [AIProgressTask] = []

        for candidate in candidates {
            let metadata = readMetadata(at: candidate.stateURL)
            guard !metadata.archived else { continue }

            let state: TurnState
            if let cached = cache[candidate.wireURL],
               cached.modificationDate == candidate.modificationDate,
               cached.readerState.offset == candidate.size {
                state = cached.state
            } else if let parsed = parseSession(candidate, cached: cache[candidate.wireURL]) {
                cache[candidate.wireURL] = parsed
                state = parsed.state
            } else {
                continue
            }

            guard state.isActive || state.isBlocked || state.hasError else { continue }
            let status: AIProgressStatus
            if state.hasError {
                status = .error
            } else if state.isBlocked {
                status = .blocked
            } else {
                status = .running
            }

            tasks.append(AIProgressTask(
                id: Self.taskID(forSessionID: candidate.sessionID),
                provider: .kimi,
                title: metadata.title ?? "Kimi Code",
                detail: state.model,
                progress: nil,
                status: status,
                updatedAt: max(state.updatedAt, candidate.modificationDate),
                sessionURL: nil,
                effort: nil,
                startedAt: state.startedAt
            ))
        }

        return tasks.sorted {
            if $0.updatedAt != $1.updatedAt { return $0.updatedAt > $1.updatedAt }
            return $0.id < $1.id
        }
    }

    public static func taskID(forSessionID sessionID: String) -> String {
        "kimi-session-\(sessionID)"
    }

    static func defaultHomeDirectory(
        environment: [String: String],
        fileManager: FileManager = .default
    ) -> URL {
        if let configured = environment["KIMI_CODE_HOME"]?.trimmingCharacters(in: .whitespacesAndNewlines),
           !configured.isEmpty {
            return URL(fileURLWithPath: configured, isDirectory: true)
        }
        return fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent(".kimi-code", isDirectory: true)
    }

    private func recentWireLogs() -> [Candidate] {
        let sessionsDirectory = homeDirectory.appendingPathComponent("sessions", isDirectory: true)
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

        var candidatesBySessionID: [String: Candidate] = [:]
        for case let wireURL as URL in enumerator {
            guard wireURL.lastPathComponent == "wire.jsonl",
                  let values = try? wireURL.resourceValues(forKeys: [
                    .isRegularFileKey,
                    .contentModificationDateKey,
                    .fileSizeKey,
                  ]),
                  values.isRegularFile == true,
                  let sessionDirectory = Self.sessionDirectory(for: wireURL),
                  let relativePathComponents = Self.relativePathComponents(
                    of: sessionDirectory,
                    below: sessionsDirectory
                  ),
                  relativePathComponents.count == 2 else {
                continue
            }

            let sessionID = sessionDirectory.lastPathComponent
            guard !sessionID.isEmpty else { continue }
            let candidate = Candidate(
                sessionID: sessionID,
                stateURL: sessionDirectory.appendingPathComponent("state.json"),
                wireURL: wireURL,
                modificationDate: values.contentModificationDate ?? .distantPast,
                size: UInt64(max(0, values.fileSize ?? 0))
            )
            if let existing = candidatesBySessionID[sessionID],
               existing.modificationDate >= candidate.modificationDate {
                continue
            }
            candidatesBySessionID[sessionID] = candidate
        }

        return Array(candidatesBySessionID.values.sorted {
            if $0.modificationDate != $1.modificationDate {
                return $0.modificationDate > $1.modificationDate
            }
            return $0.wireURL.path < $1.wireURL.path
        }.prefix(maxSessionFiles))
    }

    private static func sessionDirectory(for wireURL: URL) -> URL? {
        let parent = wireURL.deletingLastPathComponent()
        if parent.lastPathComponent == "main",
           parent.deletingLastPathComponent().lastPathComponent == "agents" {
            return parent.deletingLastPathComponent().deletingLastPathComponent()
        }
        return parent
    }

    private static func relativePathComponents(of url: URL, below directory: URL) -> [String]? {
        let directoryPath = directory.standardizedFileURL.path
        let path = url.standardizedFileURL.path
        guard path.hasPrefix(directoryPath + "/") else { return nil }
        return path.dropFirst(directoryPath.count + 1)
            .split(separator: "/")
            .map(String.init)
    }

    private func readMetadata(at stateURL: URL) -> SessionMetadata {
        guard let data = try? Data(contentsOf: stateURL),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return SessionMetadata(title: nil, archived: false)
        }
        let title = (root["title"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        return SessionMetadata(
            title: title?.isEmpty == false ? title : nil,
            archived: root["archived"] as? Bool ?? false
        )
    }

    private func parseSession(
        _ candidate: Candidate,
        cached: CachedTask?
    ) -> CachedTask? {
        var next: CachedTask
        if let cached,
           candidate.size >= cached.readerState.offset,
           !(candidate.size == cached.readerState.offset
               && candidate.modificationDate != cached.modificationDate),
           jsonlReader.hasUnchangedReadPrefix(at: candidate.wireURL, state: cached.readerState) {
            next = cached
        } else {
            next = CachedTask(
                modificationDate: candidate.modificationDate,
                readerState: jsonlReader.initialState(fileSize: candidate.size),
                state: TurnState()
            )
        }

        var readerState = next.readerState
        var state = next.state
        do {
            try jsonlReader.readLines(
                from: candidate.wireURL,
                fileSize: candidate.size,
                state: &readerState
            ) { data in
                guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                    return
                }
                applyRecord(root, state: &state, fallbackDate: candidate.modificationDate)
            }
        } catch {
            return nil
        }

        next.modificationDate = candidate.modificationDate
        next.readerState = readerState
        next.state = state
        return next
    }

    private func applyRecord(
        _ root: [String: Any],
        state: inout TurnState,
        fallbackDate: Date
    ) {
        let type = (root["type"] as? String)?.lowercased() ?? ""
        let timestamp = Self.parseTimestamp(root["time"] ?? root["timestamp"]) ?? fallbackDate
        state.updatedAt = max(state.updatedAt, timestamp)

        switch type {
        case "turn.prompt", "turn.steer":
            state.isActive = true
            state.isBlocked = false
            state.hasError = false
            state.startedAt = timestamp
        case "llm.request":
            if let model = root["model"] as? String, !model.isEmpty {
                state.model = model
            }
            state.isActive = true
        case "turn.cancel":
            state.isActive = false
            state.isBlocked = false
        case "context.append_loop_event":
            applyLoopEvent(root["event"] as? [String: Any], state: &state)
        default:
            break
        }
    }

    private func applyLoopEvent(_ event: [String: Any]?, state: inout TurnState) {
        guard let event,
              let type = (event["type"] as? String)?.lowercased() else {
            return
        }

        switch type {
        case "step.begin":
            state.isActive = true
            state.isBlocked = false
            state.hasError = false
        case "step.end":
            let finishReason = (event["finishReason"] as? String)?.lowercased()
            switch finishReason {
            case "tool_use":
                state.isActive = true
            case "paused":
                state.isActive = true
                state.isBlocked = true
            default:
                state.isActive = false
                state.isBlocked = false
            }
        case "turn.interrupted":
            state.isActive = true
            state.isBlocked = false
            state.hasError = true
        default:
            break
        }
    }

    private static func parseTimestamp(_ value: Any?) -> Date? {
        if let number = value as? NSNumber {
            let raw = number.doubleValue
            return Date(timeIntervalSince1970: raw > 1_000_000_000_000 ? raw / 1_000 : raw)
        }
        if let string = value as? String {
            if let date = try? Date.ISO8601FormatStyle(includingFractionalSeconds: true).parse(string) {
                return date
            }
            return try? Date.ISO8601FormatStyle().parse(string)
        }
        return nil
    }
}
