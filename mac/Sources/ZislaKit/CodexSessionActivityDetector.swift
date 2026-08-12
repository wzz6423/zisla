import Foundation
import ZislaCore

public final class CodexSessionActivityDetector {
    public static let defaultMaximumRolloutAge: TimeInterval = 30 * 24 * 60 * 60

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
        var turnID: String
        var failed: Bool
        var timestamp: Date
        var reason: String?
    }

    private struct ParsedResponseItem {
        var turnID: String?
        var callID: String?
        var failed: Bool?
        var timestamp: Date
        var failureReason: String?
    }

    private struct RecordEnvelope: Decodable {
        var type: String
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
    public let maximumRolloutAge: TimeInterval

    private let fileManager: FileManager
    private let jsonlReader: IncrementalJSONLReader
    private let now: () -> Date
    private var cache: [URL: CachedRollout] = [:]
    private var sessionIndexCache: CachedSessionIndex?

    public init(
        sessionsDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".codex/sessions", isDirectory: true),
        sessionIndexURL: URL? = nil,
        maxRolloutFiles: Int = .max,
        initialTailBytes: Int = .max,
        maximumRolloutAge: TimeInterval = CodexSessionActivityDetector.defaultMaximumRolloutAge,
        fileManager: FileManager = .default,
        now: @escaping () -> Date = Date.init
    ) {
        self.sessionsDirectory = sessionsDirectory
        self.sessionIndexURL = sessionIndexURL
            ?? sessionsDirectory.deletingLastPathComponent()
                .appendingPathComponent("session_index.jsonl")
        self.maxRolloutFiles = max(1, maxRolloutFiles)
        self.maximumRolloutAge = max(0, maximumRolloutAge)
        jsonlReader = IncrementalJSONLReader(initialTailBytes: initialTailBytes)
        self.fileManager = fileManager
        self.now = now
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
        var mergedModelsByTurnID: [String: String] = [:]
        var mergedEffortsByTurnID: [String: String] = [:]

        for candidate in candidates {
            let activity = try activity(in: candidate)
            mergedModelsByTurnID.merge(activity.modelsByTurnID) { _, new in new }
            mergedEffortsByTurnID.merge(activity.effortsByTurnID) { _, new in new }
            for signal in activity.statusSignals {
                statusSignalsByTurnID[signal.turnID, default: []].append(signal)
            }
        }

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
                    mergedModelsByTurnID[event.turnID],
                    mergedEffortsByTurnID[event.turnID],
                    activity.sessionID
                )
            })
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

        let activeTurnIDs = Set(active.keys)
        let tasks = active.values
            .map { record in
                let event = record.event
                let provider = Self.provider(forModel: record.model)
                let fallbackTitle = provider == .gpt ? "ChatGPT" : "Codex"
                let (status, reason) = Self.statusAndReason(
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
                    startedAt: event.timestamp,
                    failureReason: reason
                )
            }
            .sorted {
                if $0.updatedAt != $1.updatedAt { return $0.updatedAt > $1.updatedAt }
                return $0.id < $1.id
            }
        retainOnlyActiveActivity(for: activeTurnIDs)
        return tasks
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

    private static func statusAndReason(from signals: [StatusSignal], startedAt: Date) -> (AIProgressStatus, String?) {
        let latestSignal = signals
            .filter({ $0.timestamp >= startedAt })
            .max(by: { $0.timestamp < $1.timestamp })
        guard latestSignal?.failed == true else {
            return (.running, nil)
        }
        return (.error, latestSignal?.reason)
    }

    private func recentRollouts() -> [Candidate] {
        guard fileManager.fileExists(atPath: sessionsDirectory.path) else {
            return []
        }

        guard let enumerator = fileManager.enumerator(
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

        let minimumModificationDate = now().addingTimeInterval(-maximumRolloutAge)
        var candidates: [Candidate] = []
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
            let modificationDate = values.contentModificationDate ?? .distantPast
            guard modificationDate >= minimumModificationDate else { continue }
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
        }.prefix(maxRolloutFiles))
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
            guard let type = parseRecordType(data) else { return }
            switch type {
            case "session_meta":
                if let sessionID = parseSessionID(data) {
                    next.sessionID = sessionID
                }
            case "turn_context":
                if let context = parseTurnContext(data) {
                next.modelsByTurnID[context.turnID] = context.model
                if let effort = context.effort {
                    next.effortsByTurnID[context.turnID] = effort
                }
                }
            case "response_item":
                guard let item = parseResponseItem(data) else { return }
                if let callID = item.callID, let turnID = item.turnID {
                    next.turnIDsByCallID[callID] = turnID
                }
                let turnID = item.turnID ?? item.callID.flatMap { next.turnIDsByCallID[$0] }
                if let turnID, let failed = item.failed {
                    next.statusSignals.append(StatusSignal(
                        turnID: turnID,
                        failed: failed,
                        timestamp: item.timestamp,
                        reason: item.failureReason
                    ))
                }
            case "event_msg":
                if let event = parseEvent(data) {
                    next.events.append(event)
                }
            default:
                break
            }
        }
        next.readerState = readerState
        next.modificationDate = candidate.modificationDate
        coalesceCachedActivity(&next)

        cache[candidate.url] = next
        return RolloutActivity(
            events: next.events,
            statusSignals: next.statusSignals,
            modelsByTurnID: next.modelsByTurnID,
            effortsByTurnID: next.effortsByTurnID,
            sessionID: next.sessionID
        )
    }

    private func coalesceCachedActivity(_ cached: inout CachedRollout) {
        var latestEvents: [String: Event] = [:]
        for event in cached.events {
            guard let previous = latestEvents[event.turnID] else {
                latestEvents[event.turnID] = event
                continue
            }
            if event.timestamp > previous.timestamp
                || (event.timestamp == previous.timestamp
                    && Self.sortOrder(for: event.kind) >= Self.sortOrder(for: previous.kind)) {
                latestEvents[event.turnID] = event
            }
        }
        cached.events = Array(latestEvents.values)

        var latestStatusSignals: [String: StatusSignal] = [:]
        for signal in cached.statusSignals {
            if latestStatusSignals[signal.turnID]?.timestamp ?? .distantPast <= signal.timestamp {
                latestStatusSignals[signal.turnID] = signal
            }
        }
        cached.statusSignals = Array(latestStatusSignals.values)
    }

    private func retainOnlyActiveActivity(for activeTurnIDs: Set<String>) {
        for (url, var cached) in cache {
            cached.events = cached.events.filter { activeTurnIDs.contains($0.turnID) }
            cached.statusSignals = cached.statusSignals.filter { activeTurnIDs.contains($0.turnID) }
            cached.modelsByTurnID = cached.modelsByTurnID.filter { activeTurnIDs.contains($0.key) }
            cached.effortsByTurnID = cached.effortsByTurnID.filter { activeTurnIDs.contains($0.key) }
            cached.turnIDsByCallID = cached.turnIDsByCallID.filter {
                activeTurnIDs.contains($0.value)
            }
            cache[url] = cached
        }
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
        let failed: Bool?
        let failureReason: String?
        switch payloadType {
        case "function_call_output", "custom_tool_call_output":
            let output = payload["output"]
            failed = Self.outputIndicatesError(output)
            failureReason = failed == true ? "工具执行失败" : nil
        default:
            failed = nil
            failureReason = nil
        }
        return ParsedResponseItem(
            turnID: turnID,
            callID: callID,
            failed: failed,
            timestamp: timestamp,
            failureReason: failureReason
        )
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

    private func parseRecordType(_ data: Data) -> String? {
        try? JSONDecoder().decode(RecordEnvelope.self, from: data).type
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
