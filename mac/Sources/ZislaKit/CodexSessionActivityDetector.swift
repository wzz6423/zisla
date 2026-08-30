import CryptoKit
import Darwin
import Foundation
import ZislaCore

public final class CodexSessionActivityDetector {
    public static let defaultMaximumRolloutAge: TimeInterval = 30 * 24 * 60 * 60

    private struct Candidate {
        var url: URL
        var modificationDate: Date
        var changeDate: Date?
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
        var ordinal: UInt64
    }

    private struct StatusSignal {
        var turnID: String
        var failed: Bool
        var timestamp: Date
        var reason: String?
        var ordinal: UInt64
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
        var changeDate: Date?
        var size: UInt64
        var readerState: IncrementalJSONLReader.State
        var events: [Event]
        var statusSignals: [StatusSignal]
        var modelsByTurnID: [String: String]
        var effortsByTurnID: [String: String]
        var turnIDsByCallID: [String: String]
        var sessionID: String?
        var nextRecordOrdinal: UInt64
        var edgeHash: Data?
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
    private let processIdentifiersForOpenFiles: ([URL]) -> [URL: Int32]
    private let clientProvidersForProcessIdentifiers: (Set<Int32>) -> [Int32: AIProvider]
    private var cache: [URL: CachedRollout] = [:]
    private var sessionIndexCache: CachedSessionIndex?

    static let incrementalVerificationBytes = 4 * 1_024

    static func incrementalVerificationByteCount(for fileSize: UInt64) -> UInt64 {
        guard fileSize > 0 else { return 0 }
        let bytesPerEdge = incrementalVerificationBytesPerEdge(for: fileSize)
        return fileSize > bytesPerEdge ? bytesPerEdge * 2 : bytesPerEdge
    }

    private static func incrementalVerificationBytesPerEdge(for fileSize: UInt64) -> UInt64 {
        min(UInt64(incrementalVerificationBytes), max(1, fileSize / 2))
    }

    public init(
        sessionsDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".codex/sessions", isDirectory: true),
        sessionIndexURL: URL? = nil,
        maxRolloutFiles: Int = .max,
        initialTailBytes: Int = .max,
        maximumRolloutAge: TimeInterval = CodexSessionActivityDetector.defaultMaximumRolloutAge,
        fileManager: FileManager = .default,
        processIdentifiersForOpenFiles: @escaping ([URL]) -> [URL: Int32]
            = CodexSessionActivityDetector.defaultProcessIdentifiersForOpenFiles,
        clientProvidersForProcessIdentifiers: @escaping (Set<Int32>) -> [Int32: AIProvider]
            = CodexSessionActivityDetector.defaultClientProvidersForProcessIdentifiers,
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
        self.processIdentifiersForOpenFiles = processIdentifiersForOpenFiles
        self.clientProvidersForProcessIdentifiers = clientProvidersForProcessIdentifiers
        self.now = now
    }

    public func activeTasks() throws -> [AIProgressTask] {
        let candidates = recentRollouts()
        let selectedURLs = Set(candidates.map(\.url))
        cache = cache.filter { selectedURLs.contains($0.key) }

        let titlesBySessionID = sessionTitlesByID()
        // Codex may append to rollout files while scanning; one unreadable file must not discard other sessions.
        let activities: [(candidate: Candidate, activity: RolloutActivity)] = candidates.compactMap { candidate in
            guard let activity = try? activity(in: candidate) else { return nil }
            return (candidate, activity)
        }
        var allEvents: [(
            event: Event,
            activityDate: Date,
            model: String?,
            effort: String?,
            sessionID: String?,
            rolloutURL: URL
        )] = []
        var statusSignalsByTurnID: [String: [StatusSignal]] = [:]
        var mergedModelsByTurnID: [String: String] = [:]
        var mergedEffortsByTurnID: [String: String] = [:]

        for item in activities {
            let activity = item.activity
            mergedModelsByTurnID.merge(activity.modelsByTurnID) { _, new in new }
            mergedEffortsByTurnID.merge(activity.effortsByTurnID) { _, new in new }
            for signal in activity.statusSignals {
                statusSignalsByTurnID[signal.turnID, default: []].append(signal)
            }
        }

        for item in activities {
            let candidate = item.candidate
            let activity = item.activity
            let candidateEvents = activity.events
            let latestStartedTurnID = candidateEvents
                .filter { $0.kind == .started }
                .max(by: Self.isOrderedBefore)?
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
                    activity.sessionID,
                    candidate.url.standardizedFileURL
                )
            })
        }
        allEvents.sort {
            if $0.event.timestamp != $1.event.timestamp {
                return $0.event.timestamp < $1.event.timestamp
            }
            let lhsOrder = Self.sortOrder(for: $0.event.kind)
            let rhsOrder = Self.sortOrder(for: $1.event.kind)
            if lhsOrder != rhsOrder { return lhsOrder < rhsOrder }
            if $0.rolloutURL.path != $1.rolloutURL.path {
                return $0.rolloutURL.path < $1.rolloutURL.path
            }
            return $0.event.ordinal < $1.event.ordinal
        }

        var latestTurnIDsBySessionID: [String: String] = [:]
        for record in allEvents where record.event.kind == .started {
            if let sessionID = record.sessionID {
                latestTurnIDsBySessionID[sessionID] = record.event.turnID
            }
        }

        var active: [String: (
            event: Event,
            activityDate: Date,
            model: String?,
            effort: String?,
            sessionID: String?,
            rolloutURL: URL
        )] = [:]

        for record in allEvents {
            let event = record.event
            switch event.kind {
            case .started:
                if let sessionID = record.sessionID,
                   let latestTurnID = latestTurnIDsBySessionID[sessionID],
                   latestTurnID != event.turnID {
                    continue
                }
                active[event.turnID] = record
            case .completed, .aborted:
                active.removeValue(forKey: event.turnID)
            }
        }

        let activeTurnIDs = Set(active.keys)
        let processIdentifiersByURL = processIdentifiersForOpenFiles(
            Array(Set(active.values.map(\.rolloutURL)))
        )
        let clientProvidersByProcessIdentifier = clientProvidersForProcessIdentifiers(
            Set(processIdentifiersByURL.values)
        )
        let tasks = active.values
            .map { record in
                let event = record.event
                let processIdentifier = processIdentifiersByURL[record.rolloutURL]
                let provider = processIdentifier.flatMap {
                    clientProvidersByProcessIdentifier[$0]
                } ?? .codex
                let fallbackTitle = provider == .gpt ? "ChatGPT" : "Codex"
                let threadTitle = record.sessionID.flatMap { titlesBySessionID[$0] }
                let displayTitle = threadTitle ?? fallbackTitle
                let (status, reason) = Self.statusAndReason(
                    from: statusSignalsByTurnID[event.turnID] ?? [],
                    startedAt: event.timestamp
                )
                return AIProgressTask(
                    id: Self.taskID(forTurnID: event.turnID),
                    provider: provider,
                    title: displayTitle,
                    detail: record.model,
                    progress: nil,
                    status: status,
                    updatedAt: record.activityDate,
                    sessionURL: record.sessionID.flatMap(Self.sessionURL(for:)),
                    effort: record.effort,
                    startedAt: event.timestamp,
                    failureReason: reason,
                    processIdentifier: processIdentifier
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

    public static func defaultProcessIdentifiersForOpenFiles(_ urls: [URL]) -> [URL: Int32] {
        let standardizedURLs = Set(urls.map(\.standardizedFileURL))
        guard !standardizedURLs.isEmpty else { return [:] }

        guard let data = runProcessOutput(
            executableURL: URL(fileURLWithPath: "/usr/sbin/lsof"),
            arguments: ["-F", "pn", "--"] + standardizedURLs.map(\.path).sorted(),
            timeout: 2
        ) else { return [:] }
        return parseOpenFileProcessIdentifiers(data, matching: standardizedURLs)
    }

    public static func defaultClientProvidersForProcessIdentifiers(
        _ processIdentifiers: Set<Int32>
    ) -> [Int32: AIProvider] {
        guard !processIdentifiers.isEmpty,
              let data = runProcessOutput(
                  executableURL: URL(fileURLWithPath: "/bin/ps"),
                  arguments: ["-axo", "pid=,ppid=,command="],
                  timeout: 2
              ) else {
            return [:]
        }
        return parseClientProviders(
            fromProcessList: data,
            matching: processIdentifiers
        )
    }

    static func runProcessOutput(
        executableURL: URL,
        arguments: [String],
        timeout: TimeInterval,
        fileManager: FileManager = .default
    ) -> Data? {
        let outputURL = fileManager.temporaryDirectory
            .appendingPathComponent("zisla-codex-lsof-\(UUID().uuidString)")
        guard fileManager.createFile(atPath: outputURL.path, contents: nil),
              let output = try? FileHandle(forWritingTo: outputURL) else {
            return nil
        }
        defer {
            try? output.close()
            try? fileManager.removeItem(at: outputURL)
        }

        let process = Process()
        process.executableURL = executableURL
        process.arguments = arguments
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            return nil
        }

        let deadline = DispatchTime.now() + max(0, timeout)
        while process.isRunning, DispatchTime.now() < deadline {
            Thread.sleep(forTimeInterval: 0.01)
        }
        guard process.isRunning else {
            process.waitUntilExit()
            try? output.synchronize()
            try? output.close()
            return try? Data(contentsOf: outputURL)
        }

        process.terminate()
        let terminationDeadline = DispatchTime.now() + 0.25
        while process.isRunning, DispatchTime.now() < terminationDeadline {
            Thread.sleep(forTimeInterval: 0.01)
        }
        if process.isRunning {
            Darwin.kill(process.processIdentifier, SIGKILL)
            let killDeadline = DispatchTime.now() + 0.25
            while process.isRunning, DispatchTime.now() < killDeadline {
                Thread.sleep(forTimeInterval: 0.01)
            }
        }
        return nil
    }

    static func parseOpenFileProcessIdentifiers(
        _ data: Data,
        matching urls: Set<URL>
    ) -> [URL: Int32] {
        guard let output = String(data: data, encoding: .utf8) else { return [:] }
        var currentProcessIdentifier: Int32?
        var result: [URL: Int32] = [:]
        for line in output.split(whereSeparator: \.isNewline) {
            guard let field = line.first else { continue }
            let value = line.dropFirst()
            switch field {
            case "p":
                currentProcessIdentifier = Int32(value)
            case "n":
                guard let currentProcessIdentifier, currentProcessIdentifier > 0 else { continue }
                let url = URL(fileURLWithPath: String(value)).standardizedFileURL
                guard urls.contains(url), result[url] == nil else { continue }
                result[url] = currentProcessIdentifier
            default:
                continue
            }
        }
        return result
    }

    static func parseClientProviders(
        fromProcessList data: Data,
        matching processIdentifiers: Set<Int32>
    ) -> [Int32: AIProvider] {
        struct ProcessEntry {
            var parentIdentifier: Int32
            var command: Substring
        }

        var entries: [Int32: ProcessEntry] = [:]
        for line in String(decoding: data, as: UTF8.self).split(whereSeparator: \.isNewline) {
            let fields = line.split(maxSplits: 2, whereSeparator: \.isWhitespace)
            guard fields.count == 3,
                  let processIdentifier = Int32(fields[0]),
                  let parentIdentifier = Int32(fields[1]) else {
                continue
            }
            entries[processIdentifier] = ProcessEntry(
                parentIdentifier: parentIdentifier,
                command: fields[2]
            )
        }

        var providers: [Int32: AIProvider] = [:]
        for processIdentifier in processIdentifiers {
            var currentIdentifier = processIdentifier
            var visited = Set<Int32>()
            while visited.insert(currentIdentifier).inserted,
                  let entry = entries[currentIdentifier] {
                let command = entry.command.lowercased()
                if command.contains("/chatgpt.app/") {
                    providers[processIdentifier] = .gpt
                    break
                }
                if command.contains("/codex.app/") {
                    providers[processIdentifier] = .codex
                    break
                }
                guard entry.parentIdentifier > 0,
                      entry.parentIdentifier != currentIdentifier else {
                    break
                }
                currentIdentifier = entry.parentIdentifier
            }
        }
        return providers
    }

    private static func sortOrder(for kind: Event.Kind) -> Int {
        switch kind {
        case .started: 0
        case .completed, .aborted: 1
        }
    }

    private static func isOrderedBefore(_ lhs: Event, _ rhs: Event) -> Bool {
        if lhs.timestamp != rhs.timestamp { return lhs.timestamp < rhs.timestamp }
        let lhsOrder = sortOrder(for: lhs.kind)
        let rhsOrder = sortOrder(for: rhs.kind)
        if lhsOrder != rhsOrder { return lhsOrder < rhsOrder }
        return lhs.ordinal < rhs.ordinal
    }

    private static func isOrderedBefore(_ lhs: StatusSignal, _ rhs: StatusSignal) -> Bool {
        if lhs.timestamp != rhs.timestamp { return lhs.timestamp < rhs.timestamp }
        return lhs.ordinal < rhs.ordinal
    }

    private static func statusAndReason(from signals: [StatusSignal], startedAt: Date) -> (AIProgressStatus, String?) {
        let latestSignal = signals
            .filter({ $0.timestamp >= startedAt })
            .max(by: Self.isOrderedBefore)
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
                changeDate: Self.fileChangeDate(for: url),
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
           cached.changeDate == candidate.changeDate,
           cached.size == candidate.size,
           cached.readerState.offset == candidate.size {
            return RolloutActivity(
                events: cached.events,
                statusSignals: cached.statusSignals,
                modelsByTurnID: cached.modelsByTurnID,
                effortsByTurnID: cached.effortsByTurnID,
                sessionID: cached.sessionID
            )
        }

        let cachedEdgeMatches: Bool = {
            guard let cached = cache[candidate.url],
                  let cachedEdgeHash = cached.edgeHash,
                  cached.readerState.offset == cached.size,
                  candidate.size > cached.size else {
                return false
            }
            return edgeHash(of: candidate.url, byteCount: cached.size) == cachedEdgeHash
        }()

        let canContinue = cache[candidate.url].map {
            candidate.size > $0.size && cachedEdgeMatches
        } ?? false
        var next: CachedRollout
        if canContinue, let cached = cache[candidate.url] {
            next = cached
        } else {
            next = CachedRollout(
                modificationDate: candidate.modificationDate,
                changeDate: candidate.changeDate,
                size: candidate.size,
                readerState: jsonlReader.initialState(fileSize: candidate.size),
                events: [],
                statusSignals: [],
                modelsByTurnID: [:],
                effortsByTurnID: [:],
                turnIDsByCallID: [:],
                sessionID: nil,
                nextRecordOrdinal: 0,
                edgeHash: nil
            )
        }

        var readerState = next.readerState
        let consumeRecord: (Data) -> Bool = { data in
            guard let type = self.parseRecordType(data) else { return false }
            let ordinal = next.nextRecordOrdinal
            next.nextRecordOrdinal &+= 1
            switch type {
            case "session_meta":
                if let sessionID = self.parseSessionID(data) {
                    next.sessionID = sessionID
                }
            case "turn_context":
                if let context = self.parseTurnContext(data) {
                    next.modelsByTurnID[context.turnID] = context.model
                    if let effort = context.effort {
                        next.effortsByTurnID[context.turnID] = effort
                    }
                }
            case "response_item":
                guard let item = self.parseResponseItem(data) else { return true }
                if let callID = item.callID, let turnID = item.turnID {
                    next.turnIDsByCallID[callID] = turnID
                }
                let turnID = item.turnID ?? item.callID.flatMap { next.turnIDsByCallID[$0] }
                if let turnID, let failed = item.failed {
                    next.statusSignals.append(StatusSignal(
                        turnID: turnID,
                        failed: failed,
                        timestamp: item.timestamp,
                        reason: item.failureReason,
                        ordinal: ordinal
                    ))
                }
            case "event_msg":
                if let event = self.parseEvent(data, ordinal: ordinal) {
                    next.events.append(event)
                }
            default:
                break
            }
            return true
        }
        try jsonlReader.readLines(
            from: candidate.url,
            fileSize: candidate.size,
            state: &readerState
        ) { data in
            _ = consumeRecord(data)
        }
        readerState.consumePendingLineIfAccepted(consumeRecord)
        next.readerState = readerState
        next.modificationDate = candidate.modificationDate
        next.changeDate = candidate.changeDate
        next.size = candidate.size
        next.edgeHash = edgeHash(of: candidate.url, byteCount: readerState.offset)
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
        var latestEvents: [String: (started: Event?, terminal: Event?)] = [:]

        func replaces(_ candidate: Event, current: Event?) -> Bool {
            guard let current else { return true }
            return Self.isOrderedBefore(current, candidate)
        }

        for event in cached.events {
            var lifecycle = latestEvents[event.turnID] ?? (started: nil, terminal: nil)
            switch event.kind {
            case .started:
                if replaces(event, current: lifecycle.started) {
                    lifecycle.started = event
                }
            case .completed, .aborted:
                if replaces(event, current: lifecycle.terminal) {
                    lifecycle.terminal = event
                }
            }
            latestEvents[event.turnID] = lifecycle
        }
        cached.events = latestEvents.values.flatMap { lifecycle in
            [lifecycle.started, lifecycle.terminal].compactMap { $0 }
        }.sorted(by: Self.isOrderedBefore)

        var latestStatusSignals: [String: StatusSignal] = [:]
        for signal in cached.statusSignals {
            if let current = latestStatusSignals[signal.turnID] {
                if Self.isOrderedBefore(current, signal) {
                    latestStatusSignals[signal.turnID] = signal
                }
            } else {
                latestStatusSignals[signal.turnID] = signal
            }
        }
        cached.statusSignals = latestStatusSignals.values.sorted(by: Self.isOrderedBefore)
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

    private func parseEvent(_ data: Data, ordinal: UInt64) -> Event? {
        guard let envelope = try? JSONDecoder().decode(EventEnvelope.self, from: data),
              envelope.type == "event_msg",
              let kind = Event.Kind(rawValue: envelope.payload.type),
              let turnID = envelope.payload.turnID,
              !turnID.isEmpty,
              let timestamp = Self.parseTimestamp(envelope.timestamp) else {
            return nil
        }
        return Event(kind: kind, turnID: turnID, timestamp: timestamp, ordinal: ordinal)
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

    private static func fileChangeDate(for url: URL) -> Date? {
        var info = stat()
        guard lstat(url.path, &info) == 0 else { return nil }
        return Date(
            timeIntervalSince1970: TimeInterval(info.st_ctimespec.tv_sec)
                + TimeInterval(info.st_ctimespec.tv_nsec) / 1_000_000_000
        )
    }

    private func edgeHash(of url: URL, byteCount: UInt64) -> Data? {
        guard byteCount > 0 else { return Self.contentHash(for: SHA256()) }
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }

        let bytesPerEdge = Self.incrementalVerificationBytesPerEdge(for: byteCount)
        var hasher = SHA256()
        do {
            guard let first = try handle.read(upToCount: Int(bytesPerEdge)),
                  first.count == Int(bytesPerEdge) else {
                return nil
            }
            hasher.update(data: first)
            if byteCount > bytesPerEdge {
                try handle.seek(toOffset: byteCount - bytesPerEdge)
                guard let last = try handle.read(upToCount: Int(bytesPerEdge)),
                      last.count == Int(bytesPerEdge) else {
                    return nil
                }
                hasher.update(data: last)
            }
        } catch {
            return nil
        }
        return Self.contentHash(for: hasher)
    }

    private static func contentHash(for hasher: SHA256) -> Data {
        return Data(hasher.finalize())
    }

    private static func sessionURL(for sessionID: String) -> URL? {
        var components = URLComponents()
        components.scheme = "codex"
        components.host = "threads"
        components.path = "/\(sessionID)"
        return components.url
    }
}
