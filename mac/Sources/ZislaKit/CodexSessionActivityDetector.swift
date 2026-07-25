import Foundation
import ZislaCore

public final class CodexSessionActivityDetector {
    private struct Candidate {
        var url: URL
        var modificationDate: Date
        var size: UInt64
    }

    private struct Event {
        enum Kind: String {
            case started = "task_started"
            case completed = "task_complete"
            case aborted = "turn_aborted"
        }

        var kind: Kind
        var turnID: String
        var timestamp: Date
    }

    private struct StatusSignal {
        enum Kind {
            case blocked(callID: String)
            case output(callID: String?, failed: Bool)
        }

        var turnID: String
        var kind: Kind
        var timestamp: Date
    }

    private struct ParsedResponseItem {
        var turnID: String?
        var callID: String?
        var signal: StatusSignal.Kind?
        var timestamp: Date
    }

    private struct EventEnvelope: Decodable {
        struct Payload: Decodable {
            var type: String
            var turnID: String?

            private enum CodingKeys: String, CodingKey {
                case type
                case turnID = "turn_id"
            }
        }

        var timestamp: String
        var type: String
        var payload: Payload
    }

    private struct TurnContextEnvelope: Decodable {
        struct Payload: Decodable {
            var turnID: String
            var model: String
            var effort: String?
            var reasoningEffort: String?

            private enum CodingKeys: String, CodingKey {
                case turnID = "turn_id"
                case model
                case effort
                case reasoningEffort = "reasoning_effort"
            }

            var resolvedEffort: String? { effort ?? reasoningEffort }
        }

        var type: String
        var payload: Payload
    }

    private struct SessionMetadataEnvelope: Decodable {
        struct Payload: Decodable {
            var id: String
        }

        var type: String
        var payload: Payload
    }

    private struct SessionIndexEntry: Decodable {
        var id: String
        var threadName: String

        private enum CodingKeys: String, CodingKey {
            case id
            case threadName = "thread_name"
        }
    }

    private struct RolloutActivity {
        var events: [Event]
        var statusSignals: [StatusSignal]
        var modelsByTurnID: [String: String]
        var effortsByTurnID: [String: String]
        var sessionID: String?
    }

    private struct CachedRollout {
        var modificationDate: Date
        var readerState: IncrementalJSONLReader.State
        var events: [Event]
        var statusSignals: [StatusSignal]
        var modelsByTurnID: [String: String]
        var effortsByTurnID: [String: String]
        var turnIDsByCallID: [String: String]
        var sessionID: String?
    }

    private struct CachedSessionIndex {
        var modificationDate: Date
        var size: UInt64
        var titlesBySessionID: [String: String]
    }

    public let sessionsDirectory: URL
    public let sessionIndexURL: URL
    public let maxRolloutFiles: Int

    private let fileManager: FileManager
    private let jsonlReader: IncrementalJSONLReader
    private var cache: [URL: CachedRollout] = [:]
    private var sessionIndexCache: CachedSessionIndex?

    public init(
        sessionsDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".codex/sessions", isDirectory: true),
        sessionIndexURL: URL? = nil,
        maxRolloutFiles: Int = 12,
        initialTailBytes: Int = 1_024 * 1_024,
        fileManager: FileManager = .default
    ) {
        self.sessionsDirectory = sessionsDirectory
        self.sessionIndexURL = sessionIndexURL
            ?? sessionsDirectory.deletingLastPathComponent()
                .appendingPathComponent("session_index.jsonl")
        self.maxRolloutFiles = max(1, maxRolloutFiles)
        jsonlReader = IncrementalJSONLReader(initialTailBytes: initialTailBytes)
        self.fileManager = fileManager
    }

    public func activeTasks() throws -> [AIProgressTask] {
        let candidates = recentRollouts()
        let selectedURLs = Set(candidates.map(\.url))
        cache = cache.filter { selectedURLs.contains($0.key) }

        let titlesBySessionID = sessionTitlesByID()
        var allEvents: [(
            event: Event,
            activityDate: Date,
            model: String?,
            effort: String?,
            sessionID: String?
        )] = []
        var statusSignalsByTurnID: [String: [StatusSignal]] = [:]
        for candidate in candidates {
            let activity = try activity(in: candidate)
            let candidateEvents = activity.events
            let latestStartedTurnID = candidateEvents
                .filter { $0.kind == .started }
                .max { $0.timestamp < $1.timestamp }?
                .turnID
            allEvents.append(contentsOf: candidateEvents.map { event in
                let activityDate = event.kind == .started && event.turnID == latestStartedTurnID
                    ? max(event.timestamp, candidate.modificationDate)
                    : event.timestamp
                return (
                    event,
                    activityDate,
                    activity.modelsByTurnID[event.turnID],
                    activity.effortsByTurnID[event.turnID],
                    activity.sessionID
                )
            })
            for signal in activity.statusSignals {
                statusSignalsByTurnID[signal.turnID, default: []].append(signal)
            }
        }
        allEvents.sort {
            if $0.event.timestamp != $1.event.timestamp {
                return $0.event.timestamp < $1.event.timestamp
            }
            return Self.sortOrder(for: $0.event.kind) < Self.sortOrder(for: $1.event.kind)
        }

        var active: [String: (
            event: Event,
            activityDate: Date,
            model: String?,
            effort: String?,
            sessionID: String?
        )] = [:]
        for record in allEvents {
            let event = record.event
            switch event.kind {
            case .started:
                active[event.turnID] = record
            case .completed, .aborted:
                active.removeValue(forKey: event.turnID)
            }
        }

        return active.values
            .map { record in
                let event = record.event
                let provider = Self.provider(forModel: record.model)
                let fallbackTitle = provider == .gpt ? "ChatGPT" : "Codex"
                let status = Self.status(
                    from: statusSignalsByTurnID[event.turnID] ?? [],
                    startedAt: event.timestamp
                )
                return AIProgressTask(
                    id: Self.taskID(forTurnID: event.turnID),
                    provider: provider,
                    title: record.sessionID.flatMap { titlesBySessionID[$0] } ?? fallbackTitle,
                    detail: record.model,
                    progress: nil,
                    status: status,
                    updatedAt: record.activityDate,
                    sessionURL: record.sessionID.flatMap(Self.sessionURL(for:)),
                    effort: record.effort,
                    startedAt: event.timestamp
                )
            }
            .sorted {
                if $0.updatedAt != $1.updatedAt { return $0.updatedAt > $1.updatedAt }
                return $0.id < $1.id
            }
    }

    public static func taskID(forTurnID turnID: String) -> String {
        "codex-turn-\(turnID)"
    }

    private static func provider(forModel model: String?) -> AIProvider {
        guard let model = model?.lowercased() else { return .codex }
        if model.contains("codex") { return .codex }
        if model.contains("gpt") || model.contains("chatgpt") { return .gpt }
        return .codex
    }

    private static func sortOrder(for kind: Event.Kind) -> Int {
        switch kind {
        case .started: 0
        case .completed, .aborted: 1
        }
    }

    private static func status(from signals: [StatusSignal], startedAt: Date) -> AIProgressStatus {
        var blockedCallIDs: Set<String> = []
        var hasError = false
        for signal in signals
            .filter({ $0.timestamp >= startedAt })
            .sorted(by: { $0.timestamp < $1.timestamp }) {
            switch signal.kind {
            case let .blocked(callID):
                blockedCallIDs.insert(callID)
            case let .output(callID, failed):
                if let callID { blockedCallIDs.remove(callID) }
                hasError = failed
            }
        }
        if hasError { return .error }
        if !blockedCallIDs.isEmpty { return .blocked }
        return .running
    }

    private func recentRollouts() -> [Candidate] {
        guard fileManager.fileExists(atPath: sessionsDirectory.path) else {
            return []
        }

        var candidatesByURL: [URL: Candidate] = [:]
        for directory in rolloutSearchDirectories() {
            guard let enumerator = fileManager.enumerator(
                at: directory,
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
                guard url.lastPathComponent.hasPrefix("rollout-"),
                      url.pathExtension == "jsonl",
                      let values = try? url.resourceValues(forKeys: [
                        .isRegularFileKey,
                        .contentModificationDateKey,
                        .fileSizeKey,
                      ]),
                      values.isRegularFile == true else {
                    continue
                }
                candidatesByURL[url] = Candidate(
                    url: url,
                    modificationDate: values.contentModificationDate ?? .distantPast,
                    size: UInt64(max(0, values.fileSize ?? 0))
                )
            }
        }

        return Array(candidatesByURL.values.sorted {
            if $0.modificationDate != $1.modificationDate {
                return $0.modificationDate > $1.modificationDate
            }
            return $0.url.path < $1.url.path
        }.prefix(maxRolloutFiles))
    }

    private func rolloutSearchDirectories() -> [URL] {
        let years = numericDirectories(at: sessionsDirectory, componentLength: 4, limit: 2)
        guard !years.isEmpty else { return [sessionsDirectory] }

        var days: [URL] = []
        for year in years {
            for month in numericDirectories(at: year, componentLength: 2, limit: 2) {
                days.append(contentsOf: numericDirectories(
                    at: month,
                    componentLength: 2,
                    limit: 4
                ))
            }
        }
        return days.isEmpty ? [sessionsDirectory] : days
    }

    private func numericDirectories(
        at root: URL,
        componentLength: Int,
        limit: Int
    ) -> [URL] {
        guard let entries = try? fileManager.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }
        return Array(entries.filter { url in
            guard url.lastPathComponent.count == componentLength,
                  Int(url.lastPathComponent) != nil,
                  let values = try? url.resourceValues(forKeys: [.isDirectoryKey]) else {
                return false
            }
            return values.isDirectory == true
        }.sorted { $0.lastPathComponent > $1.lastPathComponent }.prefix(limit))
    }

    private func activity(in candidate: Candidate) throws -> RolloutActivity {
        if let cached = cache[candidate.url],
           cached.modificationDate == candidate.modificationDate,
           cached.readerState.offset == candidate.size {
            return RolloutActivity(
                events: cached.events,
                statusSignals: cached.statusSignals,
                modelsByTurnID: cached.modelsByTurnID,
                effortsByTurnID: cached.effortsByTurnID,
                sessionID: cached.sessionID
            )
        }

        var cached = cache[candidate.url]
        if cached == nil
            || candidate.size < (cached?.readerState.offset ?? 0)
            || (candidate.size == cached?.readerState.offset
                && candidate.modificationDate != cached?.modificationDate) {
            cached = CachedRollout(
                modificationDate: candidate.modificationDate,
                readerState: jsonlReader.initialState(fileSize: candidate.size),
                events: [],
                statusSignals: [],
                modelsByTurnID: [:],
                effortsByTurnID: [:],
                turnIDsByCallID: [:],
                sessionID: nil
            )
        }

        guard var next = cached else {
            return RolloutActivity(
                events: [],
                statusSignals: [],
                modelsByTurnID: [:],
                effortsByTurnID: [:],
                sessionID: nil
            )
        }
        var readerState = next.readerState
        try jsonlReader.readLines(
            from: candidate.url,
            fileSize: candidate.size,
            state: &readerState
        ) { data in
            if let sessionID = parseSessionID(data) {
                next.sessionID = sessionID
            } else if let context = parseTurnContext(data) {
                next.modelsByTurnID[context.turnID] = context.model
                if let effort = context.effort {
                    next.effortsByTurnID[context.turnID] = effort
                }
            } else if let item = parseResponseItem(data) {
                if let callID = item.callID, let turnID = item.turnID {
                    next.turnIDsByCallID[callID] = turnID
                }
                let turnID = item.turnID ?? item.callID.flatMap { next.turnIDsByCallID[$0] }
                if let turnID, let signal = item.signal {
                    next.statusSignals.append(StatusSignal(
                        turnID: turnID,
                        kind: signal,
                        timestamp: item.timestamp
                    ))
                }
            } else if let event = parseEvent(data) {
                next.events.append(event)
            }
        }
        next.readerState = readerState
        next.modificationDate = candidate.modificationDate
        pruneCachedActivity(&next)

        cache[candidate.url] = next
        return RolloutActivity(
            events: next.events,
            statusSignals: next.statusSignals,
            modelsByTurnID: next.modelsByTurnID,
            effortsByTurnID: next.effortsByTurnID,
            sessionID: next.sessionID
        )
    }

    private func pruneCachedActivity(_ cached: inout CachedRollout) {
        let maximumEvents = 256
        if cached.events.count > maximumEvents {
            cached.events.removeFirst(cached.events.count - maximumEvents)
        }
        let trackedTurnIDs = Set(cached.events.map(\.turnID))
        cached.modelsByTurnID = cached.modelsByTurnID.filter { trackedTurnIDs.contains($0.key) }
        cached.effortsByTurnID = cached.effortsByTurnID.filter { trackedTurnIDs.contains($0.key) }
        cached.turnIDsByCallID = cached.turnIDsByCallID.filter {
            trackedTurnIDs.contains($0.value)
        }
        cached.statusSignals = Array(cached.statusSignals
            .filter { trackedTurnIDs.contains($0.turnID) }
            .suffix(512))
    }

    private func sessionTitlesByID() -> [String: String] {
        guard let values = try? sessionIndexURL.resourceValues(forKeys: [
            .isRegularFileKey,
            .contentModificationDateKey,
            .fileSizeKey,
        ]),
        values.isRegularFile == true else {
            sessionIndexCache = nil
            return [:]
        }

        let modificationDate = values.contentModificationDate ?? .distantPast
        let size = UInt64(max(0, values.fileSize ?? 0))
        if let cached = sessionIndexCache,
           cached.modificationDate == modificationDate,
           cached.size == size {
            return cached.titlesBySessionID
        }

        guard let data = try? Data(contentsOf: sessionIndexURL) else {
            sessionIndexCache = nil
            return [:]
        }

        var titles: [String: String] = [:]
        for line in data.split(separator: 0x0A) {
            guard let entry = try? JSONDecoder().decode(SessionIndexEntry.self, from: Data(line)) else {
                continue
            }
            let id = entry.id.trimmingCharacters(in: .whitespacesAndNewlines)
            let title = entry.threadName.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !id.isEmpty, !title.isEmpty else { continue }
            titles[id] = title
        }
        sessionIndexCache = CachedSessionIndex(
            modificationDate: modificationDate,
            size: size,
            titlesBySessionID: titles
        )
        return titles
    }

    private func parseResponseItem(_ data: Data) -> ParsedResponseItem? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              root["type"] as? String == "response_item",
              let payload = root["payload"] as? [String: Any],
              let payloadType = payload["type"] as? String,
              let timestampValue = root["timestamp"] as? String,
              let timestamp = Self.parseTimestamp(timestampValue) else {
            return nil
        }

        let metadata = payload["internal_chat_message_metadata_passthrough"] as? [String: Any]
        let turnID = metadata?["turn_id"] as? String
        let callID = payload["call_id"] as? String
        let signal: StatusSignal.Kind?
        switch payloadType {
        case "function_call", "custom_tool_call":
            let name = (payload["name"] as? String)?.lowercased()
            let input = (payload["arguments"] as? String) ?? (payload["input"] as? String) ?? ""
            if (name == "request_user_input" || Self.requiresApproval(input)),
               let callID {
                signal = .blocked(callID: callID)
            } else {
                signal = nil
            }
        case "function_call_output", "custom_tool_call_output":
            signal = .output(
                callID: callID,
                failed: Self.outputIndicatesError(payload["output"])
            )
        default:
            signal = nil
        }
        return ParsedResponseItem(
            turnID: turnID,
            callID: callID,
            signal: signal,
            timestamp: timestamp
        )
    }

    private static func requiresApproval(_ input: String) -> Bool {
        let compact = input.lowercased().filter { !$0.isWhitespace }
        return compact.contains(#"sandbox_permissions:"require_escalated""#)
            || compact.contains(#""sandbox_permissions":"require_escalated""#)
            || compact.contains("sandbox_permissions:'require_escalated'")
            || compact.contains("'sandbox_permissions':'require_escalated'")
    }

    private static func outputIndicatesError(_ value: Any?) -> Bool {
        guard let value, !(value is NSNull) else { return false }
        if let values = value as? [Any] {
            return values.contains(where: outputIndicatesError)
        }
        if let object = value as? [String: Any] {
            if let isError = object["isError"] as? Bool {
                return isError
            }
            if let exitCode = integerValue(object["exit_code"] ?? object["exitCode"]) {
                return exitCode != 0
            }
            if let status = (object["status"] as? String)?.lowercased(),
               ["error", "failed", "failure"].contains(status) {
                return true
            }
            for key in ["structuredContent", "result", "text"] {
                if outputIndicatesError(object[key]) { return true }
            }
            return false
        }
        if let text = value as? String,
           let nestedData = text.data(using: .utf8),
           let nested = try? JSONSerialization.jsonObject(with: nestedData) {
            return outputIndicatesError(nested)
        }
        return false
    }

    private static func integerValue(_ value: Any?) -> Int? {
        if let number = value as? NSNumber { return number.intValue }
        if let string = value as? String { return Int(string) }
        return nil
    }

    private static func parseTimestamp(_ value: String) -> Date? {
        if let date = try? Date.ISO8601FormatStyle(includingFractionalSeconds: true).parse(value) {
            return date
        }
        return try? Date.ISO8601FormatStyle().parse(value)
    }

    private func parseEvent(_ data: Data) -> Event? {
        guard let envelope = try? JSONDecoder().decode(EventEnvelope.self, from: data),
              envelope.type == "event_msg",
              let kind = Event.Kind(rawValue: envelope.payload.type),
              let turnID = envelope.payload.turnID,
              !turnID.isEmpty,
              let timestamp = Self.parseTimestamp(envelope.timestamp) else {
            return nil
        }
        return Event(kind: kind, turnID: turnID, timestamp: timestamp)
    }

    private func parseTurnContext(
        _ data: Data
    ) -> (turnID: String, model: String, effort: String?)? {
        guard let envelope = try? JSONDecoder().decode(TurnContextEnvelope.self, from: data),
              envelope.type == "turn_context",
              !envelope.payload.turnID.isEmpty,
              !envelope.payload.model.isEmpty else {
            return nil
        }
        let effort = envelope.payload.resolvedEffort?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return (
            envelope.payload.turnID,
            envelope.payload.model,
            effort?.isEmpty == false ? effort : nil
        )
    }

    private func parseSessionID(_ data: Data) -> String? {
        guard let envelope = try? JSONDecoder().decode(SessionMetadataEnvelope.self, from: data),
              envelope.type == "session_meta" else {
            return nil
        }
        let sessionID = envelope.payload.id.trimmingCharacters(in: .whitespacesAndNewlines)
        return sessionID.isEmpty ? nil : sessionID
    }

    private static func sessionURL(for sessionID: String) -> URL? {
        var components = URLComponents()
        components.scheme = "codex"
        components.host = "threads"
        components.path = "/\(sessionID)"
        return components.url
    }
}
