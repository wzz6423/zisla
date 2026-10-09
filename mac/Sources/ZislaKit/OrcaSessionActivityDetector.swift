import Foundation
import ZislaCore

/// Reads Orca's local hook metadata and structured-chat ownership records. Orca is a host, not
/// a model provider: custom-account token logs keep their Claude/Codex identity for deduplication.
public final class OrcaSessionActivityDetector: AIActivityDetecting, AIUsageDetecting {
    public let dataRoots: [URL]
    public let maxSessions: Int
    public let recencyThreshold: TimeInterval
    private let fileManager: FileManager
    private let now: () -> Date
    private var usageReaders: [String: AIUsageLogDetector] = [:]

    public init(
        dataRoots: [URL]? = nil,
        maxSessions: Int = 8,
        recencyThreshold: TimeInterval = 30 * 60,
        fileManager: FileManager = .default,
        now: @escaping () -> Date = Date.init
    ) {
        self.dataRoots = dataRoots ?? Self.defaultDataRoots(home: fileManager.homeDirectoryForCurrentUser)
        self.maxSessions = max(1, maxSessions)
        self.recencyThreshold = max(0, recencyThreshold)
        self.fileManager = fileManager
        self.now = now
    }

    public static func defaultDataRoots(home: URL = FileManager.default.homeDirectoryForCurrentUser) -> [URL] {
        ["orca", "Orca", "orca-dev"].map { home.appendingPathComponent("Library/Application Support/\($0)", isDirectory: true) }
    }

    private var stateDirectories: [URL] {
        var directories = dataRoots
        for root in dataRoots {
            directories += ((try? fileManager.contentsOfDirectory(
                at: root.appendingPathComponent("profiles"), includingPropertiesForKeys: [.isDirectoryKey]
            )) ?? []).filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }
        }
        // Case-insensitive macOS may resolve Orca and orca to the same physical directory.
        var seenFiles: Set<NSObject> = []
        var seenPaths: Set<String> = []
        return directories.filter {
            if let identity = (try? $0.resourceValues(forKeys: [.fileResourceIdentifierKey]))?.fileResourceIdentifier as? NSObject {
                return seenFiles.insert(identity).inserted
            }
            return seenPaths.insert($0.resolvingSymlinksInPath().path).inserted
        }
    }

    private var statusFiles: [URL] {
        stateDirectories.flatMap { directory -> [URL] in
            let hooks = directory.appendingPathComponent("agent-hooks")
            let namespaces = ((try? fileManager.contentsOfDirectory(at: hooks, includingPropertiesForKeys: [.isDirectoryKey])) ?? [])
                .filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }
            return ([hooks] + namespaces).map { $0.appendingPathComponent("last-status.json") }
        }.filter { fileManager.fileExists(atPath: $0.path) }
    }

    private var journalFiles: [URL] {
        stateDirectories.map { $0.appendingPathComponent("agent-session-journal.db") }
            .filter { fileManager.fileExists(atPath: $0.path) }
    }

    public var activityFileURLs: [URL] {
        statusFiles + journalFiles.flatMap { [$0, URL(fileURLWithPath: $0.path + "-wal")] }
            .filter { fileManager.fileExists(atPath: $0.path) }
    }

    private func records(at database: URL) -> [[String: Any]] {
        DesktopAIStorage.rows(at: database, sql: """
            SELECT record_json FROM agent_session_records
            """).compactMap { row in
            guard let json = row["record_json"] as? String, let data = json.data(using: .utf8),
                  let record = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  record["schemaVersion"] as? Int == 2,
                  let location = record["location"] as? [String: Any],
                  location["executionHostId"] as? String == "local",
                  location["wslDistro"] == nil || location["wslDistro"] is NSNull else { return nil }
            return record
        }
    }

    public func activeTasks() throws -> [AIProgressTask] {
        let cutoff = now().addingTimeInterval(-recencyThreshold)
        var tasks: [AIProgressTask] = []
        for file in statusFiles {
            guard let root = DesktopAIStorage.json(at: file), root["version"] as? Int == 2,
                  let entries = root["entries"] as? [String: [String: Any]] else { continue }
            for (pane, entry) in entries {
                guard entry["paneKey"] as? String == pane,
                      entry["connectionId"] == nil || entry["connectionId"] is NSNull,
                      entry["providerSessionOnly"] as? Bool != true,
                      entry["retainedForLiveness"] as? Bool != true,
                      entry["restoredUnconfirmed"] as? Bool != true,
                      let payload = entry["payload"] as? [String: Any],
                      let state = Self.status(payload["state"] as? String),
                      let updated = DesktopAIStorage.milliseconds(entry["evidenceObservedAt"] ?? entry["receivedAt"]), updated >= cutoff else { continue }
                tasks.append(AIProgressTask(
                    id: "orca-pane-" + DesktopAIStorage.identity([file.standardizedFileURL.path, pane]), provider: .orca,
                    title: "Orca · \(payload["agentType"] as? String ?? "Agent")",
                    progress: nil, status: state, updatedAt: updated,
                    startedAt: DesktopAIStorage.milliseconds(entry["turnStartedAt"] ?? entry["stateStartedAt"])
                ))
            }
        }
        for database in journalFiles {
            let turns = currentTurns(at: database)
            for record in records(at: database) {
                guard let session = record["sessionId"] as? String,
                      let lease = record["lease"] as? [String: Any], lease["claimStatus"] as? String == "live",
                      lease["unreconciled"] as? Bool != true,
                      let renewed = DesktopAIStorage.milliseconds(lease["lastRenewedAt"]), renewed >= cutoff,
                      let deadline = DesktopAIStorage.milliseconds(lease["leaseDeadlineAt"]), deadline >= now() else { continue }
                // A live lease alone means an idle provider is alive, not that it is working.
                // Query only turn bodies from the current epoch; never read message bodies.
                guard let turn = turns.first(where: { $0["session_id"] as? String == session }),
                      let state = Self.status(turn["state"] as? String),
                      let ownerFence = turn["owner_fence"] as? NSNumber,
                      let runtimeFence = lease["runtimeFence"] as? NSNumber,
                      ownerFence == runtimeFence else { continue }
                tasks.append(AIProgressTask(
                    id: "orca-session-" + DesktopAIStorage.identity([database.standardizedFileURL.path, session]), provider: .orca,
                    title: record["conversationName"] as? String ?? "Orca Agent",
                    detail: record["provider"] as? String, progress: nil,
                    status: (turn["pending_prompt"] as? NSNumber)?.boolValue == true ? .blocked : state,
                    updatedAt: renewed, startedAt: DesktopAIStorage.milliseconds(turn["started_at"] ?? turn["ts"])
                ))
            }
        }
        return Array(tasks.sorted {
            $0.updatedAt != $1.updatedAt ? $0.updatedAt > $1.updatedAt : $0.id < $1.id
        }.prefix(maxSessions))
    }

    private func currentTurns(at database: URL) -> [[String: Any]] {
        // v1/v2 carry turns in status.turnLifecycle; v3 has a dedicated turn body. Highest
        // revision wins, not last append. An item's creating position orders turns, so a late
        // context-usage revision of an old completed turn cannot hide the current running turn.
        // Project lifecycle fields in SQLite; no message/tool body reaches this detector.
        DesktopAIStorage.rows(at: database, sql: """
            WITH epoch_rows AS (
                SELECT r.session_id, r.seq, r.ts,
                       CASE WHEN json_valid(r.row_json) THEN r.row_json ELSE '{}' END AS row_json
                FROM journal_rows r JOIN journal_sessions s
                  ON s.session_id = r.session_id AND s.epoch = r.epoch
            ), unreadable AS (
                SELECT DISTINCT session_id FROM epoch_rows
                WHERE COALESCE(json_extract(row_json, '$.v'), 0) NOT IN (1, 2, 3)
                   OR COALESCE(json_extract(row_json, '$.kind'), '') NOT IN
                      ('epoch', 'item', 'tombstone', 'submission', 'dispatch', 'lifecycle-batch')
                UNION
                SELECT DISTINCT r.session_id FROM epoch_rows r, json_each(r.row_json, '$.mutations') m
                WHERE json_extract(r.row_json, '$.kind') = 'lifecycle-batch'
                  AND COALESCE(json_extract(m.value, '$.kind'), '') NOT IN ('item', 'tombstone')
            ), current_rows AS (
                SELECT * FROM epoch_rows WHERE session_id NOT IN (SELECT session_id FROM unreadable)
            ), events AS (
                SELECT session_id, seq, 0 AS position_index, ts,
                       json_extract(row_json, '$.fence') AS fence,
                       json_extract(row_json, '$.revision') AS revision,
                       json_extract(row_json, '$.itemId') AS item,
                       json_extract(row_json, '$.kind') AS kind,
                       json_extract(row_json, '$.body') AS body,
                       json_extract(row_json, '$.agentId') AS agent_id,
                       json_extract(row_json, '$.producerKind') AS producer_kind
                FROM current_rows WHERE json_extract(row_json, '$.kind') IN ('item', 'tombstone')
                  AND json_extract(row_json, '$.stopEvent') IS NULL
                  AND json_extract(row_json, '$.queueResume') IS NULL
                  AND json_extract(row_json, '$.queueReopen') IS NULL
                UNION ALL
                SELECT r.session_id, r.seq, CAST(m.key AS INTEGER), r.ts,
                       json_extract(r.row_json, '$.fence'), json_extract(m.value, '$.revision'),
                       json_extract(m.value, '$.itemId'), json_extract(m.value, '$.kind'),
                       json_extract(m.value, '$.body'),
                       COALESCE(json_extract(m.value, '$.agentId'), json_extract(r.row_json, '$.agentId')),
                       COALESCE(json_extract(m.value, '$.producerKind'), json_extract(r.row_json, '$.producerKind'))
                FROM current_rows r, json_each(r.row_json, '$.mutations') m
                WHERE json_extract(r.row_json, '$.kind') = 'lifecycle-batch'
            ), revisions AS (
                SELECT *,
                       ROW_NUMBER() OVER (PARTITION BY session_id, item
                           ORDER BY revision DESC, seq ASC, position_index ASC) AS revision_rank,
                       FIRST_VALUE(seq) OVER (PARTITION BY session_id, item
                           ORDER BY seq ASC, position_index ASC) AS created_seq,
                       FIRST_VALUE(position_index) OVER (PARTITION BY session_id, item
                           ORDER BY seq ASC, position_index ASC) AS created_index,
                       FIRST_VALUE(fence) OVER (PARTITION BY session_id, item
                           ORDER BY seq ASC, position_index ASC) AS owner_fence
                FROM events WHERE item IS NOT NULL AND revision IS NOT NULL
            ), latest_turns AS (
                SELECT *, ROW_NUMBER() OVER (PARTITION BY session_id
                    ORDER BY created_seq DESC, created_index DESC) AS turn_rank
                FROM revisions WHERE revision_rank = 1 AND kind = 'item'
                  AND agent_id IS NULL AND COALESCE(producer_kind, '') != 'background'
                  AND (json_extract(body, '$.kind') = 'turn'
                       OR (json_extract(body, '$.kind') = 'status'
                           AND json_extract(body, '$.turnLifecycle') IS NOT NULL))
            )
            SELECT t.session_id, t.ts, t.owner_fence,
                   COALESCE(json_extract(t.body, '$.state'), json_extract(t.body, '$.turnLifecycle.state')) AS state,
                   COALESCE(json_extract(t.body, '$.startedAt'), json_extract(t.body, '$.turnLifecycle.startedAt')) AS started_at,
                   EXISTS (SELECT 1 FROM revisions p WHERE p.session_id = t.session_id
                       AND p.revision_rank = 1 AND p.kind = 'item' AND p.agent_id IS NULL
                       AND p.created_seq >= t.created_seq AND p.owner_fence = t.owner_fence
                       AND json_extract(p.body, '$.kind') IN ('approval', 'question')
                       AND json_extract(p.body, '$.resolution.state') = 'pending') AS pending_prompt
            FROM latest_turns t WHERE t.turn_rank = 1
            """)
    }

    static func status(_ state: String?) -> AIProgressStatus? {
        switch state {
        case "working", "running", "in_progress": .running
        case "waiting", "needs_input", "blocked", "permission": .blocked
        case "queued", "pending": .queued
        case "error": .error
        default: nil
        }
    }

    public func usageSamples() throws -> [AIUsageSample] {
        var bindings: [String: (AIProvider, URL)] = [:]
        for database in journalFiles {
            for record in records(at: database) {
                guard let home = record["accountHome"] as? [String: Any],
                      let path = home["path"] as? String, path.hasPrefix("/"),
                      let provider = AIProvider(token: record["provider"] as? String ?? ""),
                      (provider == .codex && home["variable"] as? String == "CODEX_HOME") ||
                        (provider == .claude && home["variable"] as? String == "CLAUDE_CONFIG_DIR") else { continue }
                let url = URL(fileURLWithPath: path).standardizedFileURL
                bindings["\(provider.rawValue):\(url.path)"] = (provider, url)
            }
        }
        var transcripts: [String: (AIProvider, URL)] = [:]
        for file in statusFiles {
            guard let root = DesktopAIStorage.json(at: file), root["version"] as? Int == 2,
                  let entries = root["entries"] as? [String: [String: Any]] else { continue }
            for entry in entries.values {
                guard entry["connectionId"] == nil || entry["connectionId"] is NSNull,
                      let payload = entry["payload"] as? [String: Any],
                      let provider = AIProvider(token: payload["agentType"] as? String ?? ""),
                      [.codex, .claude, .pi, .qwen, .coder].contains(provider),
                      let session = entry["providerSession"] as? [String: Any],
                      let path = session["transcriptPath"] as? String, path.hasPrefix("/") else { continue }
                let url = URL(fileURLWithPath: path).standardizedFileURL
                transcripts["file:\(provider.rawValue):\(url.path)"] = (provider, url)
            }
        }
        usageReaders = usageReaders.filter { bindings[$0.key] != nil || transcripts[$0.key] != nil }
        let exactSamples = transcripts.keys.sorted().flatMap { key -> [AIUsageSample] in
            guard let (provider, url) = transcripts[key] else { return [] }
            let unusedRoot = url.appendingPathComponent("not-a-directory")
            let reader = usageReaders[key] ?? AIUsageLogDetector(
                codexSessionsDirectory: unusedRoot, claudeProjectsDirectory: unusedRoot,
                qwenProjectsDirectory: unusedRoot, piSessionsDirectory: unusedRoot, qoderRoots: [],
                enabledProviders: [provider], additionalLogFiles: [provider: [url]], fileManager: fileManager
            )
            usageReaders[key] = reader
            return (try? reader.usageSamples()) ?? []
        }
        let boundSamples = bindings.keys.sorted().flatMap { key -> [AIUsageSample] in
            guard let (provider, home) = bindings[key] else { return [] }
            let reader = usageReaders[key] ?? AIUsageLogDetector(
                codexSessionsDirectory: home.appendingPathComponent("sessions"),
                claudeProjectsDirectory: home.appendingPathComponent("projects"),
                enabledProviders: [provider], fileManager: fileManager
            )
            usageReaders[key] = reader
            // Identical source IDs to the regular CLI reader: importing a default home through
            // Orca and directly through Claude/Codex never adds the same event twice.
            return (try? reader.usageSamples()) ?? []
        }
        var seen: Set<String> = []
        return (exactSamples + boundSamples).filter { seen.insert($0.sourceID ?? "").inserted }
    }
}
