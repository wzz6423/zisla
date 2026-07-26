import Foundation
import ZislaCore

/// Activity detection for Qoder / QoderWork / QoderWake and other multi-host clients (structured CLI logs + text SDK logs).
public final class QoderSessionActivityDetector: AIActivityDetecting {
    private struct Candidate {
        enum Kind {
            case structured
            case text
        }

        var url: URL
        var kind: Kind
        var modificationDate: Date
        var size: UInt64
    }

    private struct StructuredState {
        var isActive = false
        var startedAt: Date?
        var updatedAt: Date = .distantPast
        var hasError = false
        var model: String?
        var sessionID: String?
        var pendingPermissionToolCallIDs: Set<String> = []
        var anonymousPermissionCount = 0
    }

    private struct TextState {
        var isActive = false
        var startedAt: Date?
        var updatedAt: Date = .distantPast
        var hasError = false
        var pendingControlRequestIDs: Set<String> = []
    }

    private struct StructuredRecord {
        var root: [String: Any]
        var timestamp: Date
        var sequence: Int
        var filePath: String
        var lineNumber: Int
    }

    private struct CachedTask {
        var signature: String
        var task: AIProgressTask?
    }

    public let configRoots: [URL]
    public let textLogRoots: [URL]
    public let maxLogFiles: Int

    private let fileManager: FileManager
    private let lineReader: IncrementalJSONLReader
    private let discoveryInterval: TimeInterval
    private var cache: [String: CachedTask] = [:]
    private var discoveryCache: [Candidate] = []
    private var lastDiscoveryAt: Date = .distantPast

    public init(
        configRoots: [URL]? = nil,
        textLogRoots: [URL]? = nil,
        maxLogFiles: Int = 16,
        initialTailBytes: Int = 1_024 * 1_024,
        fileManager: FileManager = .default
    ) {
        let usesDefaultDiscovery = configRoots == nil && textLogRoots == nil
        let home = fileManager.homeDirectoryForCurrentUser
        if let configRoots {
            self.configRoots = configRoots
        } else {
            self.configRoots = Self.defaultConfigRoots(home: home, fileManager: fileManager)
        }
        if let textLogRoots {
            self.textLogRoots = textLogRoots
        } else {
            self.textLogRoots = Self.defaultTextLogRoots(home: home, fileManager: fileManager)
        }
        self.maxLogFiles = max(1, maxLogFiles)
        lineReader = IncrementalJSONLReader(initialTailBytes: initialTailBytes)
        self.fileManager = fileManager
        discoveryInterval = usesDefaultDiscovery ? 5 : 0
    }

    /// Discovers `~/.qoder*` config roots (including the default `~/.qoder`).
    public static func defaultConfigRoots(
        home: URL = FileManager.default.homeDirectoryForCurrentUser,
        fileManager: FileManager = .default
    ) -> [URL] {
        var roots: [URL] = []
        let defaultRoot = home.appendingPathComponent(".qoder", isDirectory: true)
        roots.append(defaultRoot)

        // Explicitly look for .qoder* including hidden.
        if let enumerator = fileManager.enumerator(
            at: home,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsSubdirectoryDescendants]
        ) {
            for case let url as URL in enumerator {
                let name = url.lastPathComponent.lowercased()
                guard name.hasPrefix(".qoder") else { continue }
                var isDir: ObjCBool = false
                guard fileManager.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue else {
                    continue
                }
                if !roots.contains(url) {
                    roots.append(url)
                }
            }
        }
        return roots.sorted { $0.path < $1.path }
    }

    /// Qoder log roots in Application Support and VS Code-compatible hosts.
    public static func defaultTextLogRoots(
        home: URL = FileManager.default.homeDirectoryForCurrentUser,
        fileManager: FileManager = .default
    ) -> [URL] {
        var roots: [URL] = []
        let appSupport = home
            .appendingPathComponent("Library/Application Support", isDirectory: true)

        if let entries = try? fileManager.contentsOfDirectory(
            at: appSupport,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) {
            for entry in entries {
                let name = entry.lastPathComponent.lowercased()
                if name.contains("qoder") {
                    roots.append(entry)
                }
            }
        }

        // VS Code compatible hosts: look for extension logs named with qoder.
        let vscodeHosts = [
            "Code",
            "Code - Insiders",
            "VSCodium",
            "Cursor",
            "Windsurf",
        ]
        for host in vscodeHosts {
            let hostRoot = appSupport.appendingPathComponent(host, isDirectory: true)
            let logsRoot = hostRoot.appendingPathComponent("logs", isDirectory: true)
            if fileManager.fileExists(atPath: logsRoot.path) {
                roots.append(logsRoot)
            }
        }

        let jetbrainsLogs = home.appendingPathComponent("Library/Logs/JetBrains", isDirectory: true)
        if fileManager.fileExists(atPath: jetbrainsLogs.path) {
            roots.append(jetbrainsLogs)
        }

        return roots
    }

    public func activeTasks() throws -> [AIProgressTask] {
        let candidates = recentLogCandidates()
        var tasksByKey: [String: AIProgressTask] = [:]
        var structuredBySession: [String: [Candidate]] = [:]
        var textCandidatesByPath: [String: Candidate] = [:]

        for candidate in candidates {
            switch candidate.kind {
            case .structured:
                structuredBySession[Self.structuredSessionKey(for: candidate.url), default: []]
                    .append(candidate)
            case .text:
                textCandidatesByPath[candidate.url.standardizedFileURL.path] = candidate
            }
        }

        var selectedCacheKeys: Set<String> = []

        for (sessionKey, sessionCandidates) in structuredBySession {
            let cacheKey = "structured:\(sessionKey)"
            selectedCacheKeys.insert(cacheKey)
            let task = cachedTask(
                key: cacheKey,
                candidates: sessionCandidates
            ) { [self] in
                parseStructuredLogs(sessionCandidates, sessionKey: sessionKey)
            }
            merge(task, into: &tasksByKey)
        }

        for candidate in textCandidatesByPath.values {
            let cacheKey = "text:\(candidate.url.standardizedFileURL.path)"
            selectedCacheKeys.insert(cacheKey)
            let task = cachedTask(key: cacheKey, candidates: [candidate]) { [self] in
                parseTextLog(candidate)
            }
            mergeTextTask(task, into: &tasksByKey)
        }

        cache = cache.filter { selectedCacheKeys.contains($0.key) }

        return tasksByKey.values.sorted {
            if $0.updatedAt != $1.updatedAt { return $0.updatedAt > $1.updatedAt }
            return $0.id < $1.id
        }
    }

    private func merge(_ task: AIProgressTask?, into tasks: inout [String: AIProgressTask]) {
        guard let task else { return }
        if let existing = tasks[task.id], existing.updatedAt > task.updatedAt {
            return
        }
        tasks[task.id] = task
    }

    private func mergeTextTask(
        _ task: AIProgressTask?,
        into tasks: inout [String: AIProgressTask]
    ) {
        guard let task else { return }
        let duplicates = tasks.filter {
            Self.representsSameDesktopTurn(structured: $0.value, text: task)
        }
        guard duplicates.count == 1, let duplicate = duplicates.first else {
            merge(task, into: &tasks)
            return
        }

        var merged = duplicate.value
        merged.detail = "Desktop"
        if let sessionID = Self.sessionID(fromTaskID: merged.id) {
            merged.sessionURL = Self.sessionURL(for: sessionID)
        }
        merged.status = Self.dominantActiveStatus(merged.status, task.status)
        merged.updatedAt = max(merged.updatedAt, task.updatedAt)
        merged.startedAt = [merged.startedAt, task.startedAt].compactMap { $0 }.min()
        tasks[duplicate.key] = merged
    }

    private static func representsSameDesktopTurn(
        structured: AIProgressTask,
        text: AIProgressTask
    ) -> Bool {
        guard structured.detail == "CLI",
              text.detail == "Desktop",
              let structuredStartedAt = structured.startedAt,
              let textStartedAt = text.startedAt else {
            return false
        }
        return abs(structuredStartedAt.timeIntervalSince(textStartedAt)) <= 2
    }

    private static func dominantActiveStatus(
        _ lhs: AIProgressStatus,
        _ rhs: AIProgressStatus
    ) -> AIProgressStatus {
        if lhs == .error || rhs == .error { return .error }
        if lhs == .blocked || rhs == .blocked { return .blocked }
        return lhs
    }

    private func cachedTask(
        key: String,
        candidates: [Candidate],
        parse: () -> AIProgressTask?
    ) -> AIProgressTask? {
        let signature = candidates
            .sorted { $0.url.path < $1.url.path }
            .map {
                "\($0.url.path)|\($0.size)|\($0.modificationDate.timeIntervalSinceReferenceDate)"
            }
            .joined(separator: "\n")
        if let cached = cache[key], cached.signature == signature {
            return cached.task
        }
        let task = parse()
        cache[key] = CachedTask(signature: signature, task: task)
        return task
    }

    private static func structuredSessionKey(for url: URL) -> String {
        let segmentsDirectory = url.deletingLastPathComponent()
        if segmentsDirectory.lastPathComponent == "segments" {
            return segmentsDirectory.deletingLastPathComponent().standardizedFileURL.path
        }
        return segmentsDirectory.standardizedFileURL.path
    }

    public static func taskID(forSessionID sessionID: String) -> String {
        "qoder-session-\(sessionID)"
    }

    public static func taskID(forLogPath path: String) -> String {
        let digest = stableDigest(path)
        return "qoder-log-\(digest)"
    }

    private static func sessionID(fromTaskID taskID: String) -> String? {
        let prefix = "qoder-session-"
        guard taskID.hasPrefix(prefix) else { return nil }
        let sessionID = String(taskID.dropFirst(prefix.count))
        return sessionID.isEmpty ? nil : sessionID
    }

    private static func sessionURL(for sessionID: String) -> URL? {
        var components = URLComponents()
        components.scheme = "qoder-work-cn"
        components.host = "notification-click"
        components.queryItems = [URLQueryItem(name: "chatId", value: sessionID)]
        return components.url
    }

    // MARK: - Discovery

    private func recentLogCandidates() -> [Candidate] {
        let now = Date()
        if discoveryInterval > 0,
           now.timeIntervalSince(lastDiscoveryAt) < discoveryInterval {
            discoveryCache = refreshedCandidates(discoveryCache)
            return discoveryCache
        }

        var candidates: [Candidate] = []

        for root in configRoots {
            candidates.append(contentsOf: structuredCandidates(under: root))
        }
        for root in textLogRoots {
            candidates.append(contentsOf: textCandidates(under: root))
        }

        let selected = Array(candidates.sorted {
            if $0.modificationDate != $1.modificationDate {
                return $0.modificationDate > $1.modificationDate
            }
            return $0.url.path < $1.url.path
        }.prefix(maxLogFiles))
        discoveryCache = selected
        lastDiscoveryAt = now
        return selected
    }

    private func refreshedCandidates(_ candidates: [Candidate]) -> [Candidate] {
        candidates.compactMap { candidate in
            guard let values = try? candidate.url.resourceValues(forKeys: [
                .isRegularFileKey,
                .contentModificationDateKey,
                .fileSizeKey,
            ]),
            values.isRegularFile == true else {
                return nil
            }
            return Candidate(
                url: candidate.url,
                kind: candidate.kind,
                modificationDate: values.contentModificationDate ?? .distantPast,
                size: UInt64(max(0, values.fileSize ?? 0))
            )
        }.sorted {
            if $0.modificationDate != $1.modificationDate {
                return $0.modificationDate > $1.modificationDate
            }
            return $0.url.path < $1.url.path
        }
    }

    private func structuredCandidates(under root: URL) -> [Candidate] {
        let sessions = root.appendingPathComponent("logs/sessions", isDirectory: true)
        guard fileManager.fileExists(atPath: sessions.path),
              let enumerator = fileManager.enumerator(
                at: sessions,
                includingPropertiesForKeys: [
                    .isRegularFileKey,
                    .contentModificationDateKey,
                    .fileSizeKey,
                ],
                options: [.skipsHiddenFiles]
              ) else {
            return []
        }

        var result: [Candidate] = []
        for case let url as URL in enumerator {
            // Prefer segments/*.jsonl under sessions
            guard url.pathExtension == "jsonl",
                  url.path.contains("/segments/") || url.path.contains("/logs/sessions/"),
                  let values = try? url.resourceValues(forKeys: [
                    .isRegularFileKey,
                    .contentModificationDateKey,
                    .fileSizeKey,
                  ]),
                  values.isRegularFile == true else {
                continue
            }
            result.append(Candidate(
                url: url,
                kind: .structured,
                modificationDate: values.contentModificationDate ?? .distantPast,
                size: UInt64(max(0, values.fileSize ?? 0))
            ))
        }
        return result
    }

    private func textCandidates(under root: URL) -> [Candidate] {
        guard fileManager.fileExists(atPath: root.path),
              let enumerator = fileManager.enumerator(
                at: root,
                includingPropertiesForKeys: [
                    .isRegularFileKey,
                    .contentModificationDateKey,
                    .fileSizeKey,
                ],
                options: [.skipsHiddenFiles]
              ) else {
            return []
        }

        var result: [Candidate] = []
        for case let url as URL in enumerator {
            let name = url.lastPathComponent.lowercased()
            let isQoderLog = name == "qoder-agent-sdk.log"
                || (name.contains("qoder") && (name.hasSuffix(".log") || name.hasSuffix(".txt")))
            guard isQoderLog,
                  let values = try? url.resourceValues(forKeys: [
                    .isRegularFileKey,
                    .contentModificationDateKey,
                    .fileSizeKey,
                  ]),
                  values.isRegularFile == true else {
                continue
            }
            // For VS Code host roots that are broad (Code/), only accept paths that mention qoder.
            let pathLower = url.path.lowercased()
            if !pathLower.contains("qoder") && name != "qoder-agent-sdk.log" {
                continue
            }
            result.append(Candidate(
                url: url,
                kind: .text,
                modificationDate: values.contentModificationDate ?? .distantPast,
                size: UInt64(max(0, values.fileSize ?? 0))
            ))
        }
        return result
    }

    // MARK: - Structured CLI logs

    private func parseStructuredLogs(
        _ candidates: [Candidate],
        sessionKey: String
    ) -> AIProgressTask? {
        var records: [StructuredRecord] = []
        for candidate in candidates {
            var readerState = lineReader.initialState(fileSize: candidate.size)
            var lineNumber = 0
            try? lineReader.readLines(
                from: candidate.url,
                fileSize: candidate.size,
                state: &readerState
            ) { data in
                defer { lineNumber += 1 }
                guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
                else { return }
                records.append(StructuredRecord(
                    root: root,
                    timestamp: Self.parseTimestamp(root["ts"] ?? root["timestamp"])
                        ?? candidate.modificationDate,
                    sequence: Self.intValue(root["seq"]) ?? lineNumber,
                    filePath: candidate.url.path,
                    lineNumber: lineNumber
                ))
            }
        }

        records.sort {
            if $0.timestamp != $1.timestamp { return $0.timestamp < $1.timestamp }
            if $0.sequence != $1.sequence { return $0.sequence < $1.sequence }
            if $0.filePath != $1.filePath { return $0.filePath < $1.filePath }
            return $0.lineNumber < $1.lineNumber
        }

        var state = StructuredState()
        state.sessionID = URL(fileURLWithPath: sessionKey).lastPathComponent
        for record in records {
            let root = record.root
            let type = (root["type"] as? String)?.lowercased() ?? ""
            let timestamp = record.timestamp
            let ids = root["ids"] as? [String: Any] ?? [:]
            let dataObj = root["data"] as? [String: Any] ?? [:]

            if let sessionID = (root["session_id"] as? String)
                ?? (root["sessionId"] as? String)
                ?? (ids["session_id"] as? String)
                ?? (ids["sessionId"] as? String),
               !sessionID.isEmpty {
                state.sessionID = sessionID
            }

            switch type {
            case "turn.started":
                state.isActive = true
                state.hasError = false
                state.pendingPermissionToolCallIDs.removeAll()
                state.anonymousPermissionCount = 0
                state.startedAt = timestamp
                state.updatedAt = timestamp
                if let model = dataObj["model"] as? String, !model.isEmpty {
                    state.model = model
                }
            case "permission.requested":
                state.isActive = true
                state.updatedAt = max(state.updatedAt, timestamp)
                if let toolCallID = Self.toolCallID(root: root, ids: ids, data: dataObj) {
                    state.pendingPermissionToolCallIDs.insert(toolCallID)
                } else {
                    state.anonymousPermissionCount += 1
                }
            case "permission.resolved":
                state.updatedAt = max(state.updatedAt, timestamp)
                if let toolCallID = Self.toolCallID(root: root, ids: ids, data: dataObj) {
                    state.pendingPermissionToolCallIDs.remove(toolCallID)
                } else if state.anonymousPermissionCount > 0 {
                    state.anonymousPermissionCount -= 1
                }
            case "permission.failed":
                state.updatedAt = max(state.updatedAt, timestamp)
                state.hasError = true
                state.isActive = true
                if let toolCallID = Self.toolCallID(root: root, ids: ids, data: dataObj) {
                    state.pendingPermissionToolCallIDs.remove(toolCallID)
                } else if state.anonymousPermissionCount > 0 {
                    state.anonymousPermissionCount -= 1
                }
            case "tool.execution.finished":
                state.updatedAt = max(state.updatedAt, timestamp)
                if let toolCallID = Self.toolCallID(root: root, ids: ids, data: dataObj) {
                    state.pendingPermissionToolCallIDs.remove(toolCallID)
                }
                if dataObj["is_error"] as? Bool == true
                    || dataObj["isError"] as? Bool == true
                    || dataObj["denied_by_permission"] as? Bool == true {
                    state.hasError = true
                } else if let status = (dataObj["status"] as? String)?.lowercased() {
                    if ["error", "failed", "failure", "denied"].contains(status) {
                        state.hasError = true
                    } else if ["success", "succeeded", "completed", "ok"].contains(status) {
                        state.hasError = false
                    }
                }
            case "tool.shell.finished":
                state.updatedAt = max(state.updatedAt, timestamp)
                if let toolCallID = Self.toolCallID(root: root, ids: ids, data: dataObj) {
                    state.pendingPermissionToolCallIDs.remove(toolCallID)
                }
                if let code = Self.intValue(dataObj["exit_code"] ?? dataObj["exitCode"]), code != 0 {
                    state.hasError = true
                } else if dataObj["exit_code"] != nil || dataObj["exitCode"] != nil {
                    state.hasError = false
                }
            case "tool.shell.failed":
                state.updatedAt = max(state.updatedAt, timestamp)
                state.hasError = true
            case "turn.finished":
                state.updatedAt = max(state.updatedAt, timestamp)
                state.pendingPermissionToolCallIDs.removeAll()
                state.anonymousPermissionCount = 0
                let reason = (dataObj["reason"] as? String)?.lowercased()
                let hasErrorPayload = dataObj["error"].map { !($0 is NSNull) } ?? false
                if reason == "error" || hasErrorPayload {
                    state.hasError = true
                    state.isActive = true
                } else {
                    state.hasError = false
                    state.isActive = false
                }
            default:
                break
            }
        }

        let blocked = !state.pendingPermissionToolCallIDs.isEmpty
            || state.anonymousPermissionCount > 0
        guard state.isActive || state.hasError || blocked else { return nil }

        let status: AIProgressStatus
        if state.hasError {
            status = .error
        } else if blocked {
            status = .blocked
        } else {
            status = .running
        }

        let id = state.sessionID.map(Self.taskID(forSessionID:))
            ?? Self.taskID(forLogPath: sessionKey)
        let modificationDate = candidates.map(\.modificationDate).max() ?? .distantPast

        return AIProgressTask(
            id: id,
            provider: .coder,
            title: "Qoder",
            detail: "CLI",
            progress: nil,
            status: status,
            updatedAt: max(state.updatedAt, modificationDate),
            sessionURL: nil,
            effort: nil,
            startedAt: state.startedAt
        )
    }

    // MARK: - Text SDK logs

    private func parseTextLog(_ candidate: Candidate) -> AIProgressTask? {
        var state = TextState()
        var readerState = lineReader.initialState(fileSize: candidate.size)
        try? lineReader.readLines(
            from: candidate.url,
            fileSize: candidate.size,
            state: &readerState
        ) { data in
            guard let line = String(data: data, encoding: .utf8) else { return }
            applyTextLine(line, state: &state, fallbackDate: candidate.modificationDate)
        }

        let blocked = !state.pendingControlRequestIDs.isEmpty
        guard state.isActive || state.hasError || blocked else { return nil }

        let status: AIProgressStatus
        if state.hasError {
            status = .error
        } else if blocked {
            status = .blocked
        } else {
            status = .running
        }

        return AIProgressTask(
            id: Self.taskID(forLogPath: candidate.url.path),
            provider: .coder,
            title: "Qoder",
            detail: Self.hostDetail(for: candidate.url.path),
            progress: nil,
            status: status,
            updatedAt: max(state.updatedAt, candidate.modificationDate),
            sessionURL: nil,
            effort: nil,
            startedAt: state.startedAt
        )
    }

    private func applyTextLine(
        _ line: String,
        state: inout TextState,
        fallbackDate: Date
    ) {
        // Lines start with ISO timestamp; only parse fixed markers.
        let timestamp = Self.parseLeadingTimestamp(line) ?? fallbackDate

        if line.contains("[QueryRunner] outbound session_message sent type=user") {
            state.isActive = true
            state.hasError = false
            state.startedAt = timestamp
            state.updatedAt = timestamp
            return
        }

        if line.contains("inbound session_message received type=result") {
            state.updatedAt = max(state.updatedAt, timestamp)
            if line.contains("subtype=error_during_execution") {
                state.hasError = true
                state.isActive = true
            } else if line.contains("subtype=success") {
                state.hasError = false
                state.isActive = false
                state.pendingControlRequestIDs.removeAll()
            }
            return
        }

        if line.contains("inbound control_request received"),
           line.contains("subtype=can_use_tool") {
            state.updatedAt = max(state.updatedAt, timestamp)
            if let requestID = Self.extractToken(line, key: "request_id") {
                state.pendingControlRequestIDs.insert(requestID)
            }
            return
        }

        if line.contains("inbound control_response sent"),
           line.contains("subtype=can_use_tool") {
            state.updatedAt = max(state.updatedAt, timestamp)
            if let requestID = Self.extractToken(line, key: "request_id") {
                state.pendingControlRequestIDs.remove(requestID)
            }
            // status non-success → error
            if let status = Self.extractToken(line, key: "status")?.lowercased(),
               status != "success" && status != "ok" {
                state.hasError = true
                state.isActive = true
            }
            return
        }
    }

    // MARK: - Helpers

    private static func toolCallID(
        root: [String: Any],
        ids: [String: Any],
        data: [String: Any]
    ) -> String? {
        let candidates: [Any?] = [
            root["tool_call_id"],
            root["toolCallId"],
            ids["tool_call_id"],
            ids["toolCallId"],
            data["tool_call_id"],
            data["toolCallId"],
        ]
        for value in candidates {
            if let string = value as? String, !string.isEmpty { return string }
        }
        return nil
    }

    private static func hostDetail(for path: String) -> String {
        let lower = path.lowercased()
        if lower.contains("/application support/code")
            || lower.contains("/application support/cursor")
            || lower.contains("/application support/vscodium")
            || lower.contains("/application support/windsurf")
            || lower.contains("/code/logs/")
            || lower.contains("/cursor/logs/")
            || lower.contains("/vscodium/logs/")
            || lower.contains("/windsurf/logs/") {
            return "VS Code"
        }
        if lower.contains("jetbrains") || lower.contains("intellij") || lower.contains("webstorm") {
            return "JetBrains"
        }
        if lower.contains("qoderwork") || lower.contains("qoderwake")
            || lower.contains("qoder") && (lower.contains("application support") || lower.contains("/logs/qoder")) {
            return "Desktop"
        }
        return "Host"
    }

    private static func extractToken(_ line: String, key: String) -> String? {
        let marker = "\(key)="
        guard let range = line.range(of: marker) else { return nil }
        let rest = line[range.upperBound...]
        var value = ""
        for ch in rest {
            if ch.isWhitespace { break }
            value.append(ch)
        }
        return value.isEmpty ? nil : value
    }

    private static func parseLeadingTimestamp(_ line: String) -> Date? {
        // e.g. 2026-07-19T01:00:00.000Z ... or 2026-07-19T01:00:00.000+08:00
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard let space = trimmed.firstIndex(of: " ") else {
            return parseTimestamp(trimmed)
        }
        let prefix = String(trimmed[..<space])
        return parseTimestamp(prefix)
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

    private static func intValue(_ value: Any?) -> Int? {
        if let number = value as? NSNumber { return number.intValue }
        if let string = value as? String { return Int(string) }
        return nil
    }

    private static func stableDigest(_ string: String) -> String {
        // FNV-1a 64-bit hex for stable compact ids without CryptoKit dependency noise.
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in string.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x100000001b3
        }
        return String(hash, radix: 16)
    }
}
