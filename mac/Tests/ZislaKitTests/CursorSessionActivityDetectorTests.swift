import Foundation
import SQLite3
import Testing
@testable import ZislaCore
@testable import ZislaKit

struct CursorSessionActivityDetectorTests {
    private let now = Date(timeIntervalSince1970: 1_910_000_000)

    @Test func readsRecentActiveMetadataAndExcludesArchivedDraftStaleAndFutureRowsBeforeLimit() throws {
        let root = try fixtureRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let database = root.appendingPathComponent("globalStorage/state.vscdb")
        try execute("CREATE TABLE cursorDiskKV (key TEXT PRIMARY KEY, value TEXT)", at: database)
        let examples: [(String, [String: Any])] = [
            ("active", ["status": "generating", "hasBlockingPendingActions": true]),
            ("second", ["status": "generating"]),
            ("unfinished", ["status": "aborted", "unfinishedRunAt": 1_909_999_980_000]),
            ("idle", ["status": "completed"]),
            ("archived", ["status": "generating", "isArchived": true, "lastUpdatedAt": 1_909_999_999_000]),
            ("draft", ["status": "generating", "isDraft": true]),
            ("stale", ["status": "generating", "lastUpdatedAt": 1_909_000_000_000]),
            ("future", ["status": "generating", "lastUpdatedAt": 1_911_000_000_000]),
            ("", ["status": "generating"]),
        ]
        for (id, values) in examples { try insert(composer(id, values), key: "composerData:\(id)", at: database) }
        try execute("INSERT INTO cursorDiskKV VALUES ('composerData:broken','not-json')", at: database)
        let before = try Data(contentsOf: database)
        let detector = CursorSessionActivityDetector(userDirectory: root, maxSessions: 2,
            isApplicationRunning: { true }, now: { now })
        let tasks = try detector.activeTasks()
        #expect(tasks.count == 2)
        #expect(Set(tasks.map(\.title)) == ["active", "second"])
        #expect(tasks.first { $0.title == "active" }?.status == .blocked)
        #expect(tasks.first { $0.title == "second" }?.status == .running)
        #expect(tasks.allSatisfy { $0.provider == .cursor && $0.detail == "fixture-model" && $0.sessionURL == nil })
        #expect(tasks.allSatisfy { !$0.id.contains(root.path) && !$0.title.contains("private prompt") })
        #expect(try Data(contentsOf: database) == before)
        #expect(detector.activityFileURLs == [database])
    }

    @Test func readsLegacyArraysAndWorkspaceHeadsAndDeduplicatesByNewestComposer() throws {
        let root = try fixtureRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let global = root.appendingPathComponent("globalStorage/state.vscdb")
        let legacy = root.appendingPathComponent("workspaceStorage/fixture/state.vscdb")
        try execute("CREATE TABLE cursorDiskKV (key TEXT, value TEXT)", at: global)
        try insert(composer("same", ["status": "generating", "name": "newest"]), key: "composerData:same", at: global)
        try execute("CREATE TABLE ItemTable (key TEXT, value TEXT)", at: legacy)
        try insert(["allComposers": [
            composer("same", ["status": "generating", "lastUpdatedAt": 1_909_999_970_000]),
            composer("head", ["unfinishedRunAt": 1_909_999_980_000, "lastUpdatedAt": 0]),
            composer("settled", ["status": "completed", "unfinishedRunAt": 1_909_999_980_000]),
            composer("aborted", ["status": "aborted", "unfinishedRunAt": 1_909_999_980_000]),
        ]], key: "composer.composerData", table: "ItemTable", at: legacy)
        try insert([composer("array", ["status": "generating"])], key: "allComposers", table: "ItemTable", at: legacy)
        let detector = CursorSessionActivityDetector(userDirectory: root, isApplicationRunning: { true }, now: { now })
        let tasks = try detector.activeTasks()
        #expect(tasks.count == 3)
        #expect(Set(tasks.map(\.title)) == ["newest", "head", "array"])
        #expect(tasks.first { $0.title == "head" }?.startedAt == Date(timeIntervalSince1970: 1_909_999_980))
        #expect(Set(tasks.map(\.id)).count == 3)
        #expect(detector.activityFileURLs.count == 2)
    }

    @Test func applicationClosureAndMissingOrCorruptedStoresProduceNoTasksAndNoFiles() throws {
        let root = try fixtureRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let missing = root.appendingPathComponent("missing")
        let detector = CursorSessionActivityDetector(userDirectory: missing, isApplicationRunning: { true }, now: { now })
        #expect(try detector.activeTasks().isEmpty)
        #expect(!FileManager.default.fileExists(atPath: missing.path))
        let database = root.appendingPathComponent("globalStorage/state.vscdb")
        try execute("CREATE TABLE cursorDiskKV (key TEXT, value TEXT)", at: database)
        try insert(composer("active", ["status": "generating"]), key: "composerData:active", at: database)
        let closed = CursorSessionActivityDetector(userDirectory: root, isApplicationRunning: { false }, now: { now })
        #expect(try closed.activeTasks().isEmpty)
        try Data("invalid database".utf8).write(to: database)
        let corrupt = CursorSessionActivityDetector(userDirectory: root, isApplicationRunning: { true }, now: { now })
        #expect(try corrupt.activeTasks().isEmpty)
        #expect(try Data(contentsOf: database) == Data("invalid database".utf8))
    }

    @Test func handlesMalformedLegacyEnvelopeWithoutLosingValidRows() throws {
        let root = try fixtureRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let database = root.appendingPathComponent("globalStorage/state.vscdb")
        try execute("CREATE TABLE ItemTable (key TEXT, value TEXT)", at: database)
        try execute("INSERT INTO ItemTable VALUES ('allComposers','{')", at: database)
        try insert(["allComposers": [composer("valid", ["status": "generating"])]],
            key: "composer.composerData", table: "ItemTable", at: database)
        let detector = CursorSessionActivityDetector(userDirectory: root, isApplicationRunning: { true }, now: { now })
        #expect(try detector.activeTasks().map(\.title) == ["valid"])
    }

    @Test func canonicalHeaderDetectsSerializedRunningTurnAndClearsAfterCompletion() throws {
        let root = try fixtureRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let database = root.appendingPathComponent("globalStorage/state.vscdb")
        try execute("CREATE TABLE cursorDiskKV (key TEXT PRIMARY KEY, value TEXT)", at: database)
        try execute("CREATE TABLE composerHeaders (composerId TEXT PRIMARY KEY, value TEXT)", at: database)
        try insert(composer("canonical", ["status": "aborted", "unfinishedRunAt": 1_909_999_990_000]),
            key: "composerData:canonical", at: database)
        var header: [String: Any] = [
            "type": "head", "composerId": "canonical", "name": "canonical", "isDraft": false,
            "createdAt": 1_909_999_950_000, "lastUpdatedAt": 1_909_999_990_000,
            "unfinishedRunAt": 1_909_999_990_000, "hasBlockingPendingActions": false,
        ]
        try insert(header, key: "canonical", table: "composerHeaders", at: database)
        let detector = CursorSessionActivityDetector(userDirectory: root, isApplicationRunning: { true }, now: { now })
        let before = try Data(contentsOf: database)
        let task = try #require(detector.activeTasks().first)
        #expect(task.provider == .cursor && task.title == "canonical" && task.status == .running)
        #expect(task.startedAt == Date(timeIntervalSince1970: 1_909_999_990))
        #expect(task.detail == nil && task.sessionURL == nil)
        #expect(try Data(contentsOf: database) == before)
        let closed = CursorSessionActivityDetector(userDirectory: root, isApplicationRunning: { false }, now: { now })
        #expect(try closed.activeTasks().isEmpty)
        header["hasBlockingPendingActions"] = true
        try execute("DELETE FROM composerHeaders", at: database)
        try insert(header, key: "canonical", table: "composerHeaders", at: database)
        #expect(try detector.activeTasks().first?.status == .blocked)
        header.removeValue(forKey: "unfinishedRunAt")
        header["lastUpdatedAt"] = 1_909_999_999_000
        try execute("DELETE FROM composerHeaders", at: database)
        try insert(header, key: "canonical", table: "composerHeaders", at: database)
        #expect(try detector.activeTasks().isEmpty)
        #expect(try CursorSessionActivityDetector(userDirectory: root, isApplicationRunning: { true }, now: { now })
            .activeTasks().isEmpty)
    }

    @Test func canonicalHeadersFilterInvalidInactiveAndInvisibleRowsBeforeLimit() throws {
        let root = try fixtureRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let database = root.appendingPathComponent("globalStorage/state.vscdb")
        try execute("CREATE TABLE composerHeaders (composerId TEXT PRIMARY KEY, value TEXT)", at: database)
        let examples: [(String, [String: Any])] = [
            ("active", ["lastUpdatedAt": 1_909_999_980_000]),
            ("blocked", ["hasBlockingPendingActions": true, "lastUpdatedAt": 1_909_999_990_000]),
            ("archived", ["isArchived": true]),
            ("draft", ["isDraft": true]),
            ("completed", ["status": "completed"]),
            ("aborted", ["status": "aborted"]),
            ("stale-marker", ["unfinishedRunAt": 1_909_000_000_000]),
            ("future-marker", ["unfinishedRunAt": 1_911_000_000_000]),
            ("zero-marker", ["unfinishedRunAt": 0]),
            ("boolean-marker", ["unfinishedRunAt": true]),
            ("string-marker", ["unfinishedRunAt": "1909999990000"]),
            ("stale-update", ["lastUpdatedAt": 1_909_000_000_000]),
            ("future-update", ["lastUpdatedAt": 1_911_000_000_000]),
            ("wrong-type", ["type": "full"]),
            ("", [:]),
        ]
        for (id, values) in examples {
            try insert(composer(id, ["type": "head", "unfinishedRunAt": 1_909_999_980_000,
                "lastUpdatedAt": 1_909_999_999_000].merging(values) { _, new in new }),
                key: id, table: "composerHeaders", at: database)
        }
        try execute("INSERT INTO composerHeaders VALUES ('broken','{')", at: database)
        try insert(composer("idle", ["type": "head"]), key: "idle", table: "composerHeaders", at: database)
        let before = try Data(contentsOf: database)
        let detector = CursorSessionActivityDetector(userDirectory: root, maxSessions: 2,
            isApplicationRunning: { true }, now: { now })
        let tasks = try detector.activeTasks()
        #expect(tasks.map(\.title) == ["blocked", "active"])
        #expect(tasks.map(\.status) == [.blocked, .running])
        #expect(try Data(contentsOf: database) == before)
    }

    @Test @MainActor func canonicalHeaderWALUpdatesPublishAndRemoveMonitorTasks() async throws {
        let root = try fixtureRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let databaseURL = root.appendingPathComponent("globalStorage/state.vscdb")
        try execute("PRAGMA journal_mode=WAL; CREATE TABLE composerHeaders (composerId TEXT PRIMARY KEY, value TEXT)",
            at: databaseURL)
        var database: OpaquePointer?
        #expect(sqlite3_open(databaseURL.path, &database) == SQLITE_OK)
        defer { sqlite3_close(database) }
        var header: [String: Any] = [
            "type": "head", "composerId": "watched", "name": "watched", "isDraft": false,
            "createdAt": 1_909_999_950_000, "lastUpdatedAt": 1_909_999_990_000,
        ]
        try insert(header, key: "watched", table: "composerHeaders", at: databaseURL)
        let detector = CursorSessionActivityDetector(userDirectory: root, isApplicationRunning: { true }, now: { now })
        let monitor = AIStateMonitor(directoryURL: root.appendingPathComponent("monitor"), activityDetectors: [detector],
            detectorRefreshInterval: 86_400, now: { now })
        defer { monitor.stop() }
        monitor.start()
        #expect(detector.activityFileURLs.contains(URL(fileURLWithPath: databaseURL.path + "-wal")))
        header["unfinishedRunAt"] = 1_909_999_990_000
        try execute("DELETE FROM composerHeaders", at: databaseURL)
        try insert(header, key: "watched", table: "composerHeaders", at: databaseURL)
        for _ in 0..<200 where monitor.state.tasks.isEmpty {
            try await Task.sleep(for: .milliseconds(10))
        }
        let task = try #require(monitor.state.tasks.first)
        #expect(task.provider == .cursor && task.title == "watched" && task.status == .running)
        header.removeValue(forKey: "unfinishedRunAt")
        try execute("DELETE FROM composerHeaders", at: databaseURL)
        try insert(header, key: "watched", table: "composerHeaders", at: databaseURL)
        for _ in 0..<200 where !monitor.state.tasks.isEmpty {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(monitor.state.tasks.isEmpty)
        #expect(monitor.state.usageSamples.isEmpty && monitor.errorDescription == nil)
        monitor.stop()
        header["unfinishedRunAt"] = 1_909_999_990_000
        try execute("DELETE FROM composerHeaders", at: databaseURL)
        try insert(header, key: "watched", table: "composerHeaders", at: databaseURL)
        #expect(monitor.state.tasks.isEmpty)
    }

    private func composer(_ id: String, _ values: [String: Any]) -> [String: Any] {
        ["composerId": id, "name": id, "lastUpdatedAt": 1_909_999_990_000,
         "createdAt": 1_909_999_950_000, "modelConfig": ["modelName": "fixture-model"],
         "conversation": [["text": "private prompt must not be selected"]]]
            .merging(values) { _, new in new }
    }

    private func fixtureRoot() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("zisla-cursor-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    private func execute(_ sql: String, at url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        var database: OpaquePointer?
        guard sqlite3_open(url.path, &database) == SQLITE_OK else { throw FixtureError.sqlite }
        defer { sqlite3_close(database) }
        guard sqlite3_exec(database, sql, nil, nil, nil) == SQLITE_OK else { throw FixtureError.sqlite }
    }

    private func insert(_ value: Any, key: String, table: String = "cursorDiskKV", at url: URL) throws {
        let text = String(decoding: try JSONSerialization.data(withJSONObject: value), as: UTF8.self)
            .replacingOccurrences(of: "'", with: "''")
        try execute("INSERT INTO \(table) VALUES ('\(key)','\(text)')", at: url)
    }

    private enum FixtureError: Error { case sqlite }
}
