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
