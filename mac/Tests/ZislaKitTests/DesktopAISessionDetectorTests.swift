import Foundation
import SQLite3
import Testing
@testable import ZislaCore
@testable import ZislaKit

struct DesktopAISessionDetectorTests {
    private let now = Date(timeIntervalSince1970: 1_910_000_000)

    @Test func deltaReadsOnlyRecentStreamingUnarchivedMetadataAcrossAccounts() throws {
        let root = try fixtureRoot(); defer { try? FileManager.default.removeItem(at: root) }
        for account in ["user_a", "user_b"] {
            let database = root.appendingPathComponent("\(account)/data.sqlite")
            try execute("""
                CREATE TABLE app_threads (id TEXT, name TEXT, status TEXT, archived INTEGER,
                    created_at INTEGER, last_prompted_at INTEGER, stub BLOB, state BLOB);
                INSERT INTO app_threads VALUES ('same-id','Example','streaming',0,1909999700000,1909999990000,X'00',X'FF');
                INSERT INTO app_threads VALUES ('idle','Private','unread',0,1909999700000,1909999990000,X'00',X'FF');
                INSERT INTO app_threads VALUES ('archived','Private','streaming',1,1909999700000,1909999990000,X'00',X'FF');
                INSERT INTO app_threads VALUES ('old','Private','streaming',0,1909990000000,1909990000000,X'00',X'FF');
                """, at: database)
        }
        let detector = DeltaSessionActivityDetector(dataRoot: root, now: { now })
        let tasks = try detector.activeTasks()
        #expect(tasks.count == 2)
        #expect(Set(tasks.map(\.id)).count == 2)
        #expect(tasks.allSatisfy { $0.provider == .delta && $0.status == .running && $0.title == "Example" })
        #expect(tasks.allSatisfy { $0.sessionURL == nil && !$0.id.contains(root.path) })
        #expect(try detector.usageSamples().isEmpty) // Older Delta has no numeric usage table.
        #expect(detector.activityFileURLs.count == 2)
    }

    @Test func deltaUsageIsStableAndIncludesCachesWithoutOverflow() throws {
        let root = try fixtureRoot(); defer { try? FileManager.default.removeItem(at: root) }
        let database = root.appendingPathComponent("user_a/data.sqlite")
        try execute("""
            CREATE TABLE app_model_usage_daily (day INTEGER, access_provider TEXT, model_provider TEXT,
                model TEXT, pricing_tier TEXT, input_tokens INTEGER, output_tokens INTEGER,
                cache_write_tokens INTEGER, cache_read_tokens INTEGER);
            INSERT INTO app_model_usage_daily VALUES (22000,'direct','example','model-a','standard',10,20,30,40);
            INSERT INTO app_model_usage_daily VALUES (22000,'direct','example','model-a','fast',5,2,0,0);
            INSERT INTO app_model_usage_daily VALUES (22000,'direct','example','model-b','standard',9223372036854775807,1,9,9);
            INSERT INTO app_model_usage_daily VALUES (-1,'direct','example','model-c','standard',1,1,0,0);
            """, at: database)
        let detector = DeltaSessionActivityDetector(dataRoot: root)
        let first = try detector.usageSamples()
        #expect(first.count == 3)
        #expect(first.first { $0.model == "model-b" }?.inputTokens == Int.max)
        #expect(first.first { $0.inputTokens == 80 }?.outputTokens == 20)
        #expect(Set(first.compactMap(\.sourceID)).count == 3)
        #expect(Set(first.map(\.timestamp)) == [Date(timeIntervalSince1970: 22000 * 86400)])
        let repository = AIStateRepository(directoryURL: root.appendingPathComponent("zisla"))
        #expect(try repository.recordDetectedUsage(first) == 1)
        #expect(try repository.recordDetectedUsage(detector.usageSamples()) == 0)
    }

    @Test func orcaHookMetadataIgnoresIdleRemoteStaleAndIdentityOnlyRows() throws {
        let root = try fixtureRoot(); defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("profiles/test/agent-hooks/local/last-status.json")
        var entries: [String: [String: Any]] = [:]
        for (pane, state) in [("active", "working"), ("blocked", "blocked"), ("waiting", "waiting"), ("idle", "done")] {
            entries[pane] = hook(pane: pane, state: state)
        }
        entries["remote"] = hook(pane: "remote", state: "working", extra: ["connectionId": "remote-host"])
        entries["old"] = hook(pane: "old", state: "working", extra: ["evidenceObservedAt": 1_909_000_000_000])
        entries["identity"] = hook(pane: "identity", state: "working", extra: ["providerSessionOnly": true])
        entries["unconfirmed"] = hook(pane: "unconfirmed", state: "working", extra: ["restoredUnconfirmed": true])
        try writeJSON(["version": 2, "entries": entries], at: file)
        let detector = OrcaSessionActivityDetector(dataRoots: [root, root], now: { now })
        let tasks = try detector.activeTasks()
        #expect(tasks.count == 3)
        #expect(tasks.allSatisfy { $0.provider == .orca && !$0.title.contains("private prompt") })
        #expect(tasks.filter { $0.status == .blocked }.count == 2)
        #expect(Set(detector.activityFileURLs).count == 1)
        try writeJSON(["version": 99, "entries": entries], at: file)
        #expect(try detector.activeTasks().isEmpty)
    }

    @Test func orcaStructuredTurnsHonorLeaseBatchSettlementEpochAndTombstone() throws {
        let root = try fixtureRoot(); defer { try? FileManager.default.removeItem(at: root) }
        let database = root.appendingPathComponent("agent-session-journal.db")
        try execute("""
            CREATE TABLE agent_session_records (session_id TEXT, record_json TEXT);
            CREATE TABLE journal_sessions (session_id TEXT, epoch TEXT);
            CREATE TABLE journal_rows (session_id TEXT, epoch TEXT, seq INTEGER, ts INTEGER, row_json TEXT);
            INSERT INTO journal_sessions VALUES ('test-session','current');
            """, at: database)
        try insertRecord(record(), at: database)
        try insertTurn(seq: 1, state: "running", at: database)
        let detector = OrcaSessionActivityDetector(dataRoots: [root], now: { now })
        #expect(try detector.activeTasks().count == 1)
        let batch: [String: Any] = ["v": 3, "kind": "lifecycle-batch", "mutations": [
            ["kind": "item", "itemId": "turn", "revision": 2, "body": ["kind": "turn", "state": "completed"]]
        ]]
        try insertRow(batch, seq: 2, at: database)
        #expect(try detector.activeTasks().isEmpty)
        try insertTurn(seq: 3, state: "running", at: database)
        #expect(try detector.activeTasks().count == 1)
        try insertRow(["v": 3, "kind": "tombstone", "itemId": "turn", "revision": 4], seq: 4, at: database)
        #expect(try detector.activeTasks().isEmpty)
        try insertTurn(seq: 5, state: "running", epoch: "obsolete", at: database)
        #expect(try detector.activeTasks().isEmpty)
        try execute("DELETE FROM agent_session_records", at: database)
        var expired = record()
        expired["lease"] = ["claimStatus": "live", "runtimeFence": 1, "lastRenewedAt": 1_909_999_990_000, "leaseDeadlineAt": 1_909_999_999_000]
        try insertRecord(expired, at: database)
        try insertTurn(seq: 6, state: "running", at: database)
        #expect(try detector.activeTasks().isEmpty)
    }

    @Test func orcaReadsLegacyTurnsAndIgnoresLateOldRevisionsAndSubagents() throws {
        let root = try fixtureRoot(); defer { try? FileManager.default.removeItem(at: root) }
        let database = root.appendingPathComponent("agent-session-journal.db")
        try execute("""
            CREATE TABLE agent_session_records (session_id TEXT, record_json TEXT);
            CREATE TABLE journal_sessions (session_id TEXT, epoch TEXT);
            CREATE TABLE journal_rows (session_id TEXT, epoch TEXT, seq INTEGER, ts INTEGER, row_json TEXT);
            INSERT INTO journal_sessions VALUES ('test-session','current');
            """, at: database)
        try insertRecord(record(), at: database)
        let detector = OrcaSessionActivityDetector(dataRoots: [root], now: { now })
        try insertRow(["v": 2, "kind": "item", "itemId": "old", "revision": 1,
                       "body": ["kind": "status", "turnLifecycle": ["state": "running"]]], seq: 1, at: database)
        #expect(try detector.activeTasks().count == 1)
        try insertRow(["v": 2, "kind": "item", "itemId": "old", "revision": 2,
                       "body": ["kind": "status", "turnLifecycle": ["state": "completed"]]], seq: 2, at: database)
        #expect(try detector.activeTasks().isEmpty)
        // Newer append but lower revision must not resurrect a completed turn.
        try insertRow(["v": 2, "kind": "item", "itemId": "old", "revision": 1,
                       "body": ["kind": "status", "turnLifecycle": ["state": "running"]]], seq: 3, at: database)
        #expect(try detector.activeTasks().isEmpty)
        try insertTurn(seq: 4, state: "running", at: database)
        // Old turn's context report arrives after the current turn was created.
        try insertRow(["v": 2, "kind": "item", "itemId": "old", "revision": 3,
                       "body": ["kind": "status", "turnLifecycle": ["state": "completed"]]], seq: 5, at: database)
        try insertRow(["v": 3, "kind": "item", "itemId": "subagent", "revision": 1, "agentId": "child",
                       "body": ["kind": "turn", "state": "completed"]], seq: 6, at: database)
        #expect(try detector.activeTasks().count == 1)
        try insertRow(["v": 2, "kind": "item", "itemId": "approval", "revision": 1,
                       "body": ["kind": "approval", "resolution": ["state": "pending"]]], seq: 7, at: database)
        #expect(try detector.activeTasks().first?.status == .blocked)
        try insertRow(["v": 2, "kind": "item", "itemId": "approval", "revision": 2,
                       "body": ["kind": "approval", "resolution": ["state": "resolved"]]], seq: 8, at: database)
        #expect(try detector.activeTasks().first?.status == .running)
        // A future-version completion must fail closed, not leave an older running row visible.
        try insertRow(["v": 99, "kind": "item", "itemId": "turn", "revision": 7,
                       "body": ["kind": "turn", "state": "completed"]], seq: 9, at: database)
        #expect(try detector.activeTasks().isEmpty)
    }

    @Test func orcaRejectsUnreconciledAndDifferentOwnerLeases() throws {
        let root = try fixtureRoot(); defer { try? FileManager.default.removeItem(at: root) }
        let database = root.appendingPathComponent("agent-session-journal.db")
        try execute("""
            CREATE TABLE agent_session_records (session_id TEXT, record_json TEXT);
            CREATE TABLE journal_sessions (session_id TEXT, epoch TEXT);
            CREATE TABLE journal_rows (session_id TEXT, epoch TEXT, seq INTEGER, ts INTEGER, row_json TEXT);
            INSERT INTO journal_sessions VALUES ('test-session','current');
            """, at: database)
        try insertTurn(seq: 1, state: "running", at: database)
        let detector = OrcaSessionActivityDetector(dataRoots: [root], now: { now })
        var changed = record()
        var lease = try #require(changed["lease"] as? [String: Any])
        lease["runtimeFence"] = 2
        changed["lease"] = lease
        try insertRecord(changed, at: database)
        #expect(try detector.activeTasks().isEmpty)
        try execute("DELETE FROM agent_session_records", at: database)
        lease["runtimeFence"] = 1
        lease["unreconciled"] = true
        changed["lease"] = lease
        try insertRecord(changed, at: database)
        #expect(try detector.activeTasks().isEmpty)
    }

    @Test func orcaImportsExactTranscriptUsageWithRegularCLIEventIdentity() throws {
        let root = try fixtureRoot(); defer { try? FileManager.default.removeItem(at: root) }
        let transcript = root.appendingPathComponent("custom/projects/example/session.jsonl")
        try FileManager.default.createDirectory(at: transcript.deletingLastPathComponent(), withIntermediateDirectories: true)
        let event: [String: Any] = ["type": "assistant", "timestamp": "2030-07-10T12:00:00Z", "message": [
            "id": "example-message", "model": "example-model", "usage": ["input_tokens": 10, "output_tokens": 20,
                "cache_creation_input_tokens": 30, "cache_read_input_tokens": 40]
        ]]
        var data = try JSONSerialization.data(withJSONObject: event); data.append(10)
        try data.write(to: transcript)
        let file = root.appendingPathComponent("agent-hooks/last-status.json")
        let entry = hook(pane: "active", state: "working", extra: [
            "providerSession": ["key": "session_id", "id": "example", "transcriptPath": transcript.path]
        ])
        try writeJSON(["version": 2, "entries": ["active": entry]], at: file)
        // Pin the same Claude home as well: exact transcript + account discovery must dedupe.
        let database = root.appendingPathComponent("agent-session-journal.db")
        try execute("CREATE TABLE agent_session_records (session_id TEXT, record_json TEXT)", at: database)
        var pinned = record()
        pinned["accountHome"] = ["variable": "CLAUDE_CONFIG_DIR", "path": root.appendingPathComponent("custom").path]
        try insertRecord(pinned, at: database)
        let samples = try OrcaSessionActivityDetector(dataRoots: [root]).usageSamples()
        let direct = try AIUsageLogDetector(claudeProjectsDirectory: transcript.deletingLastPathComponent(),
            enabledProviders: [.claude]).usageSamples()
        #expect(samples == direct)
        #expect(samples.count == 1)
        #expect(samples[0].provider == .claude)
        #expect(samples[0].inputTokens == 80)
        let repository = AIStateRepository(directoryURL: root.appendingPathComponent("zisla"))
        #expect(try repository.recordDetectedUsage(samples + direct) == 1)
        #expect(try repository.recordDetectedUsage(samples + direct) == 0)
    }

    @Test func explicitTranscriptFilesHonorProviderFilterOutsideDefaultTree() throws {
        let root = try fixtureRoot(); defer { try? FileManager.default.removeItem(at: root) }
        let transcript = root.appendingPathComponent("outside/session.jsonl")
        try FileManager.default.createDirectory(at: transcript.deletingLastPathComponent(), withIntermediateDirectories: true)
        let event: [String: Any] = ["timestamp": "2030-07-10T12:00:00Z", "model": "example",
                                 "usage": ["input_tokens": 10, "output_tokens": 20]]
        var data = try JSONSerialization.data(withJSONObject: event); data.append(10)
        try data.write(to: transcript)
        let detector = AIUsageLogDetector(qoderRoots: [], enabledProviders: [.coder],
                                          additionalLogFiles: [.coder: [transcript, transcript], .claude: [transcript]])
        let samples = try detector.usageSamples()
        #expect(samples.count == 1)
        #expect(samples.first?.provider == .coder)
        #expect(samples.first?.inputTokens == 10)
        #expect(samples.first?.outputTokens == 20)
    }

    @Test @MainActor func defaultMonitorAndBrandIdentityIncludeDesktopTools() {
        #expect(AIProvider(token: "zed-delta") == .delta)
        #expect(AIProvider(token: "Orca-IDE") == .orca)
        #expect(AIProvider(token: "WorkBuddy-AI") == .workbuddy)
        #expect(AIMascotLibrary.providerDisplayName(for: .workbuddy) == "WorkBuddy AI")
        #expect(AIStateMonitor.defaultActivityDetectors().contains { $0 is WorkBuddyAISessionActivityDetector })
        #expect(AIMascotLibrary.providerDisplayName(for: .delta) == "Delta")
        #expect(AIMascotLibrary.providerDisplayName(for: .orca) == "Orca")
        #expect(AIStateMonitor.defaultActivityDetectors().contains { $0 is DeltaSessionActivityDetector })
        #expect(AIStateMonitor.defaultActivityDetectors().contains { $0 is OrcaSessionActivityDetector })
        #expect(AIStateMonitor.defaultUsageDetectors().contains { $0 is DeltaSessionActivityDetector })
        #expect(AIStateMonitor.defaultUsageDetectors().contains { $0 is OrcaSessionActivityDetector })
    }

    @Test func missingOrIncompatibleStoresFailClosed() throws {
        let root = try fixtureRoot(); defer { try? FileManager.default.removeItem(at: root) }
        #expect(try DeltaSessionActivityDetector(dataRoot: root).activeTasks().isEmpty)
        #expect(try OrcaSessionActivityDetector(dataRoots: [root]).usageSamples().isEmpty)
        try execute("CREATE TABLE unrelated (value TEXT)", at: root.appendingPathComponent("data.sqlite"))
        #expect(try DeltaSessionActivityDetector(dataRoot: root).usageSamples().isEmpty)
    }

    private func hook(pane: String, state: String, extra: [String: Any] = [:]) -> [String: Any] {
        var result: [String: Any] = ["paneKey": pane, "connectionId": NSNull(), "receivedAt": 1_909_999_990_000,
            "stateStartedAt": 1_909_999_980_000, "payload": ["state": state, "agentType": "claude", "prompt": "private prompt"]]
        result.merge(extra) { _, next in next }; return result
    }
    private func record() -> [String: Any] {
        ["schemaVersion": 2, "sessionId": "test-session", "provider": "claude", "conversationName": "Example",
         "location": ["executionHostId": "local", "wslDistro": NSNull()],
         "lease": ["claimStatus": "live", "runtimeFence": 1, "lastRenewedAt": 1_909_999_990_000, "leaseDeadlineAt": 1_910_000_100_000]]
    }
    private func fixtureRoot() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("zisla-desktop-ai-\(UUID())")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true); return url
    }
    private func writeJSON(_ json: [String: Any], at url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONSerialization.data(withJSONObject: json).write(to: url)
    }
    private func execute(_ sql: String, at url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        var database: OpaquePointer?
        guard sqlite3_open(url.path, &database) == SQLITE_OK, let database else { throw FixtureError.sqlite }
        defer { sqlite3_close(database) }
        guard sqlite3_exec(database, sql, nil, nil, nil) == SQLITE_OK else { throw FixtureError.sqlite }
    }
    private func jsonText(_ value: [String: Any]) throws -> String {
        String(decoding: try JSONSerialization.data(withJSONObject: value), as: UTF8.self).replacingOccurrences(of: "'", with: "''")
    }
    private func insertRecord(_ record: [String: Any], at url: URL) throws {
        try execute("INSERT INTO agent_session_records VALUES ('test-session','\(jsonText(record))')", at: url)
    }
    private func insertTurn(seq: Int, state: String, epoch: String = "current", at url: URL) throws {
        try insertRow(["v": 3, "kind": "item", "itemId": "turn", "revision": seq, "body": ["kind": "turn", "state": state]],
                      seq: seq, epoch: epoch, at: url)
    }
    private func insertRow(_ row: [String: Any], seq: Int, epoch: String = "current", at url: URL) throws {
        var envelope = row
        envelope["epoch"] = epoch
        envelope["seq"] = seq
        envelope["fence"] = 1
        envelope["ts"] = 1_909_999_990_000
        try execute("INSERT INTO journal_rows VALUES ('test-session','\(epoch)',\(seq),1909999990000,'\(jsonText(envelope))')", at: url)
    }
    private enum FixtureError: Error { case sqlite }
}
