import Darwin
import Foundation
import ZislaCore

/// Reads Pi's local JSONL session metadata without retaining prompt or response content.
public final class PiSessionActivityDetector: AIActivityDetecting {
    private struct Candidate {
        var url: URL
        var modificationDate: Date
        var size: UInt64
    }

    private struct SessionState {
        var id: String
        var title: String?
        var cwd: String?
        var model: String?
        var startedAt: Date?
        var updatedAt: Date = .distantPast
        var status: AIProgressStatus = .running
        var failureReason: String?
        var isActive = false
    }

    private struct CachedSession {
        var modificationDate: Date
        var size: UInt64
        var readerState: IncrementalJSONLReader.State
        var state: SessionState
        var task: AIProgressTask?
    }

    public let sessionsDirectory: URL
    public let maxSessionFiles: Int
    public let maximumSessionAge: TimeInterval

    private let fileManager: FileManager
    private let jsonlReader: IncrementalJSONLReader
    private let runningProcessIdentifiers: () -> [Int32]
    private let now: () -> Date
    private var cache: [URL: CachedSession] = [:]

    public init(
        sessionsDirectory: URL? = nil,
        maxSessionFiles: Int = 12,
        initialTailBytes: Int = 256 * 1_024,
        maximumLineBytes: Int = 256 * 1_024,
        maximumSessionAge: TimeInterval = 30 * 60,
        fileManager: FileManager = .default,
        runningProcessIdentifiers: @escaping () -> [Int32] = PiSessionActivityDetector.defaultRunningProcessIdentifiers,
        now: @escaping () -> Date = Date.init
    ) {
        self.sessionsDirectory = sessionsDirectory ?? fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent(".pi/agent/sessions", isDirectory: true)
        self.maxSessionFiles = max(1, maxSessionFiles)
        self.maximumSessionAge = max(0, maximumSessionAge)
        self.fileManager = fileManager
        self.jsonlReader = IncrementalJSONLReader(
            initialTailBytes: initialTailBytes,
            maximumLineBytes: maximumLineBytes
        )
        self.runningProcessIdentifiers = runningProcessIdentifiers
        self.now = now
    }

    public func activeTasks() throws -> [AIProgressTask] {
        let candidates = recentCandidates()
        let selectedURLs = Set(candidates.map(\.url))
        cache = cache.filter { selectedURLs.contains($0.key) }

        var processIdentifiers = runningProcessIdentifiers().makeIterator()
        return candidates.compactMap { candidate in
            guard let parsed = parse(candidate: candidate, cached: cache[candidate.url]) else { return nil }
            cache[candidate.url] = parsed
            guard var task = parsed.task else { return nil }
            task.processIdentifier = processIdentifiers.next()
            return task
        }
        .sorted {
            if $0.updatedAt != $1.updatedAt { return $0.updatedAt > $1.updatedAt }
            return $0.id < $1.id
        }
    }

    public static func taskID(forSessionID sessionID: String) -> String {
        "pi-session-\(sessionID)"
    }

    public static func defaultRunningProcessIdentifiers() -> [Int32] {
        guard let data = CodexSessionActivityDetector.runProcessOutput(
            executableURL: URL(fileURLWithPath: "/bin/ps"),
            arguments: ["-axo", "pid=,comm=,args="],
            timeout: 2
        ) else { return [] }
        return parseRunningProcessIdentifiers(data)
    }

    static func parseRunningProcessIdentifiers(_ data: Data) -> [Int32] {
        var identifiers: [Int32] = []
        var seen = Set<Int32>()
        for line in String(decoding: data, as: UTF8.self).split(whereSeparator: \.isNewline) {
            let fields = line.split(whereSeparator: \.isWhitespace)
            guard fields.count >= 2,
                  let processIdentifier = Int32(fields[0]) else {
                continue
            }
            let executable = URL(fileURLWithPath: String(fields[1])).lastPathComponent
            let arguments = fields.dropFirst(2).joined(separator: " ")
            guard executable == "pi"
                    || arguments.contains("/pi-coding-agent/")
                    || arguments.contains("pi-coding-agent/dist/cli")
            else { continue }
            if seen.insert(processIdentifier).inserted {
                identifiers.append(processIdentifier)
            }
        }
        return identifiers.sorted(by: >)
    }

    private func recentCandidates() -> [Candidate] {
        guard fileManager.fileExists(atPath: sessionsDirectory.path),
              let enumerator = fileManager.enumerator(
                  at: sessionsDirectory,
                  includingPropertiesForKeys: [.isRegularFileKey, .contentModificationDateKey, .fileSizeKey],
                  options: [.skipsHiddenFiles]
              ) else { return [] }

        let minimumDate = now().addingTimeInterval(-maximumSessionAge)
        var candidates: [Candidate] = []
        for case let url as URL in enumerator {
            guard url.pathExtension == "jsonl",
                  let values = try? url.resourceValues(forKeys: [
                      .isRegularFileKey, .contentModificationDateKey, .fileSizeKey,
                  ]),
                  values.isRegularFile == true else { continue }
            let modificationDate = values.contentModificationDate ?? .distantPast
            guard modificationDate >= minimumDate else { continue }
            candidates.append(Candidate(
                url: url,
                modificationDate: modificationDate,
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

    private func parse(candidate: Candidate, cached: CachedSession?) -> CachedSession? {
        var next: CachedSession
        if let cached,
           candidate.size >= cached.size,
           !(candidate.size == cached.size && candidate.modificationDate != cached.modificationDate) {
            next = cached
        } else {
            next = CachedSession(
                modificationDate: candidate.modificationDate,
                size: candidate.size,
                readerState: jsonlReader.initialState(fileSize: candidate.size),
                state: SessionState(
                    id: candidate.url.deletingPathExtension().lastPathComponent
                ),
                task: nil
            )
        }

        do {
            try jsonlReader.readLines(
                from: candidate.url,
                fileSize: candidate.size,
                state: &next.readerState
            ) { line in
                guard let root = try? JSONSerialization.jsonObject(with: line) as? [String: Any] else { return }
                updateState(&next.state, from: root, fallbackDate: candidate.modificationDate)
            }
        } catch {
            return nil
        }

        next.modificationDate = candidate.modificationDate
        next.size = candidate.size
        next.task = makeTask(from: next.state, candidate: candidate)
        return next
    }

    private func updateState(_ state: inout SessionState, from root: [String: Any], fallbackDate: Date) {
        let timestamp = Self.timestamp(root["timestamp"], fallback: fallbackDate)
        state.updatedAt = max(state.updatedAt, timestamp)

        switch (root["type"] as? String)?.lowercased() {
        case "session":
            if let id = root["id"] as? String, !id.isEmpty { state.id = id }
            state.cwd = root["cwd"] as? String
        case "session_info":
            if let title = root["name"] as? String, !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                state.title = title
            }
        case "model_change":
            state.model = root["modelId"] as? String
        case "message":
            guard let message = root["message"] as? [String: Any],
                  let role = (message["role"] as? String)?.lowercased() else { return }
            if let model = message["model"] as? String, !model.isEmpty { state.model = model }
            switch role {
            case "user":
                state.startedAt = timestamp
                state.updatedAt = max(state.updatedAt, timestamp)
                state.status = .running
                state.failureReason = nil
                state.isActive = true
            case "assistant":
                let stopReason = (message["stopReason"] as? String)?.lowercased()
                state.updatedAt = max(state.updatedAt, timestamp)
                switch stopReason {
                case "stop":
                    state.status = .succeeded
                    state.isActive = false
                case "error":
                    state.status = .error
                    state.failureReason = message["errorMessage"] as? String
                    state.isActive = true
                case "aborted":
                    state.status = .failed
                    state.isActive = false
                default:
                    state.status = .running
                    state.isActive = true
                }
            default:
                break
            }
        default:
            break
        }
    }

    private func makeTask(from state: SessionState, candidate: Candidate) -> AIProgressTask? {
        guard state.isActive else { return nil }
        let fallbackTitle = state.cwd.map { URL(fileURLWithPath: $0).lastPathComponent }
            .flatMap { $0.isEmpty ? nil : $0 }
            ?? "Pi"
        return AIProgressTask(
            id: Self.taskID(forSessionID: state.id),
            provider: .pi,
            title: state.title ?? fallbackTitle,
            detail: state.model,
            progress: nil,
            status: state.status,
            updatedAt: max(state.updatedAt, candidate.modificationDate),
            sessionURL: candidate.url.standardizedFileURL,
            startedAt: state.startedAt,
            failureReason: state.failureReason
        )
    }

    private static func timestamp(_ value: Any?, fallback: Date) -> Date {
        if let number = value as? NSNumber {
            let raw = number.doubleValue
            return Date(timeIntervalSince1970: raw > 10_000_000_000 ? raw / 1_000 : raw)
        }
        if let string = value as? String {
            if let date = try? Date.ISO8601FormatStyle(includingFractionalSeconds: true).parse(string) {
                return date
            }
            if let date = try? Date.ISO8601FormatStyle().parse(string) { return date }
        }
        return fallback
    }
}
