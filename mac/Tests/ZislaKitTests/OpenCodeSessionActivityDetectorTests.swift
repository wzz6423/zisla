import Foundation
import SQLite3
import Testing
@testable import ZislaCore
@testable import ZislaKit

struct OpenCodeSessionActivityDetectorTests {
    @Test
    func detectsUserMessageAsRunning() throws {
        let dbURL = makeTempDB()
        defer { try? FileManager.default.removeItem(at: dbURL) }

        let nowMs = Int64(Date().timeIntervalSince1970 * 1000)
        try createTables(at: dbURL)
        try insertSession(at: dbURL, id: "ses-active", title: "Active session", updatedAt: nowMs)
        try insertMessage(at: dbURL, id: "msg-1", sessionID: "ses-active", updatedAt: nowMs,
                          data: #"{"role":"user","time":{"created":\#(nowMs)}}"#)

        let task = try #require(OpenCodeSessionActivityDetector(
            databaseURL: dbURL,
            recencyThreshold: 3600
        ).activeTasks().first)
        #expect(task.id == OpenCodeSessionActivityDetector.taskID(forSessionID: "ses-active"))
        #expect(task.provider == .opencode)
        #expect(task.title == "Active session")
        #expect(task.status == .running)
    }

    @Test
    func ignoresCompletedAssistant() throws {
        let dbURL = makeTempDB()
        defer { try? FileManager.default.removeItem(at: dbURL) }

        let nowMs = Int64(Date().timeIntervalSince1970 * 1000)
        try createTables(at: dbURL)
        try insertSession(at: dbURL, id: "ses-done", title: "Done", updatedAt: nowMs)
        try insertMessage(at: dbURL, id: "msg-1", sessionID: "ses-done", updatedAt: nowMs,
                          data: #"{"role":"assistant","time":{"created":\#(nowMs),"completed":\#(nowMs + 1000)},"finish":"stop","modelID":"test-model"}"#)

        #expect(try OpenCodeSessionActivityDetector(
            databaseURL: dbURL,
            recencyThreshold: 3600
        ).activeTasks().isEmpty)
    }

    @Test
    func detectsAssistantWithoutCompletedAsRunning() throws {
        let dbURL = makeTempDB()
        defer { try? FileManager.default.removeItem(at: dbURL) }

        let nowMs = Int64(Date().timeIntervalSince1970 * 1000)
        try createTables(at: dbURL)
        try insertSession(at: dbURL, id: "ses-gen", title: "Generating", updatedAt: nowMs)
        try insertMessage(at: dbURL, id: "msg-1", sessionID: "ses-gen", updatedAt: nowMs,
                          data: #"{"role":"assistant","time":{"created":\#(nowMs)},"modelID":"claude-3.5"}"#)

        let task = try #require(OpenCodeSessionActivityDetector(
            databaseURL: dbURL,
            recencyThreshold: 3600
        ).activeTasks().first)
        #expect(task.status == .running)
        #expect(task.detail == "claude-3.5")
    }

    @Test
    func ignoresArchivedSessions() throws {
        let dbURL = makeTempDB()
        defer { try? FileManager.default.removeItem(at: dbURL) }

        let nowMs = Int64(Date().timeIntervalSince1970 * 1000)
        try createTables(at: dbURL)
        try insertSession(at: dbURL, id: "ses-archived", title: "Archived", updatedAt: nowMs, archivedAt: nowMs)
        try insertMessage(at: dbURL, id: "msg-1", sessionID: "ses-archived", updatedAt: nowMs,
                          data: #"{"role":"user","time":{"created":\#(nowMs)}}"#)

        #expect(try OpenCodeSessionActivityDetector(
            databaseURL: dbURL,
            recencyThreshold: 3600
        ).activeTasks().isEmpty)
    }

    @Test
    func handlesMissingDatabase() throws {
        let missing = FileManager.default.temporaryDirectory
            .appendingPathComponent("Zisla-opencode-missing-\(UUID().uuidString).db")
        #expect(try OpenCodeSessionActivityDetector(databaseURL: missing).activeTasks().isEmpty)
    }
}

// MARK: - SQLite Helpers

private func makeTempDB() -> URL {
    FileManager.default.temporaryDirectory
        .appendingPathComponent("Zisla-opencode-\(UUID().uuidString).db")
}

private func createTables(at url: URL) throws {
    var db: OpaquePointer?
    guard sqlite3_open(url.path, &db) == SQLITE_OK else {
        sqlite3_close(db)
        throw OpenCodeTestError.openFailed
    }
    defer { sqlite3_close(db) }

    let sessionSQL = """
        CREATE TABLE `session` (
            `id` text PRIMARY KEY,
            `project_id` text NOT NULL,
            `parent_id` text,
            `slug` text NOT NULL,
            `directory` text NOT NULL,
            `title` text NOT NULL,
            `version` text NOT NULL,
            `share_url` text,
            `summary_additions` integer,
            `summary_deletions` integer,
            `summary_files` integer,
            `summary_diffs` text,
            `revert` text,
            `permission` text,
            `time_created` integer NOT NULL,
            `time_updated` integer NOT NULL,
            `time_compacting` integer,
            `time_archived` integer,
            `workspace_id` text
        )
        """
    let messageSQL = """
        CREATE TABLE `message` (
            `id` text PRIMARY KEY,
            `session_id` text NOT NULL,
            `time_created` integer NOT NULL,
            `time_updated` integer NOT NULL,
            `data` text NOT NULL
        )
        """

    var err: UnsafeMutablePointer<CChar>?
    sqlite3_exec(db, sessionSQL, nil, nil, &err)
    sqlite3_free(err)
    sqlite3_exec(db, messageSQL, nil, nil, &err)
    sqlite3_free(err)
}

private func insertSession(
    at url: URL,
    id: String,
    title: String,
    updatedAt: Int64,
    archivedAt: Int64? = nil
) throws {
    var db: OpaquePointer?
    guard sqlite3_open(url.path, &db) == SQLITE_OK else {
        sqlite3_close(db)
        throw OpenCodeTestError.openFailed
    }
    defer { sqlite3_close(db) }

    let sql = """
        INSERT INTO `session` (id, project_id, slug, directory, title, version,
            time_created, time_updated, time_archived)
        VALUES (?, 'proj1', 'slug', '/tmp', ?, '1.0', ?, ?, ?)
        """
    var stmt: OpaquePointer?
    sqlite3_prepare_v2(db, sql, -1, &stmt, nil)
    sqlite3_bind_text(stmt, 1, id, -1, SQLITE_TRANSIENT)
    sqlite3_bind_text(stmt, 2, title, -1, SQLITE_TRANSIENT)
    sqlite3_bind_int64(stmt, 3, updatedAt - 60000)
    sqlite3_bind_int64(stmt, 4, updatedAt)
    if let archivedAt {
        sqlite3_bind_int64(stmt, 5, archivedAt)
    } else {
        sqlite3_bind_null(stmt, 5)
    }
    sqlite3_step(stmt)
    sqlite3_finalize(stmt)
}

private func insertMessage(
    at url: URL,
    id: String,
    sessionID: String,
    updatedAt: Int64,
    data: String
) throws {
    var db: OpaquePointer?
    guard sqlite3_open(url.path, &db) == SQLITE_OK else {
        sqlite3_close(db)
        throw OpenCodeTestError.openFailed
    }
    defer { sqlite3_close(db) }

    let sql = """
        INSERT INTO `message` (id, session_id, time_created, time_updated, data)
        VALUES (?, ?, ?, ?, ?)
        """
    var stmt: OpaquePointer?
    sqlite3_prepare_v2(db, sql, -1, &stmt, nil)
    sqlite3_bind_text(stmt, 1, id, -1, SQLITE_TRANSIENT)
    sqlite3_bind_text(stmt, 2, sessionID, -1, SQLITE_TRANSIENT)
    sqlite3_bind_int64(stmt, 3, updatedAt - 1000)
    sqlite3_bind_int64(stmt, 4, updatedAt)
    sqlite3_bind_text(stmt, 5, data, -1, SQLITE_TRANSIENT)
    sqlite3_step(stmt)
    sqlite3_finalize(stmt)
}

private enum OpenCodeTestError: Error {
    case openFailed
}

private let SQLITE_TRANSIENT = unsafeBitCast(
    OpaquePointer(bitPattern: -1),
    to: sqlite3_destructor_type.self
)
