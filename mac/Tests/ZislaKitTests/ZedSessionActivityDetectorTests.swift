import Foundation
import SQLite3
import Testing
@testable import ZislaCore
@testable import ZislaKit

struct ZedSessionActivityDetectorTests {
    @Test
    func detectsRecentThreadsWithoutReadingSummaryOrCompressedData() throws {
        let databaseURL = temporaryDatabaseURL("active")
        defer { try? FileManager.default.removeItem(at: databaseURL) }
        let now = try #require(ZedSessionActivityDetector.parseFixtureDate("2033-05-18T03:33:20.000000+00:00"))
        let expectedUpdatedAt = try #require(ZedSessionActivityDetector.parseFixtureDate("2033-05-18T03:28:20.000000+00:00"))
        let expectedStartedAt = try #require(ZedSessionActivityDetector.parseFixtureDate("2033-05-18T03:20:20.000000+00:00"))
        try execute(
            """
            CREATE TABLE threads (
                id TEXT PRIMARY KEY,
                summary TEXT NOT NULL,
                updated_at TEXT NOT NULL,
                data_type TEXT NOT NULL,
                data BLOB NOT NULL,
                created_at TEXT
            );
            INSERT INTO threads VALUES (
                'active-thread', 'private summary', '2033-05-18T03:28:20.000000+00:00',
                'zstd', X'28B52FFD', '2033-05-18T03:20:20.000000+00:00'
            );
            INSERT INTO threads VALUES (
                'stale-thread', 'old summary', '2033-05-18T01:28:20.000000+00:00',
                'zstd', X'28B52FFD', '2033-05-18T01:20:20.000000+00:00'
            );
            """,
            at: databaseURL
        )

        let tasks = try ZedSessionActivityDetector(
            databaseURL: databaseURL,
            recencyThreshold: 30 * 60,
            now: { now }
        ).activeTasks()

        let task = try #require(tasks.first)
        #expect(tasks.count == 1)
        #expect(task.id == ZedSessionActivityDetector.taskID(forThreadID: "active-thread"))
        #expect(task.provider == .zed)
        #expect(task.title == "Zed Agent")
        #expect(task.status == .running)
        #expect(task.updatedAt == expectedUpdatedAt)
        #expect(task.startedAt == expectedStartedAt)
        #expect(task.sessionURL == nil)
    }

    @Test
    func usesZedThreadDatabasePathAndHandlesMissingDatabase() throws {
        let home = URL(fileURLWithPath: "/Users/tester", isDirectory: true)
        let databaseURL = ZedSessionActivityDetector.defaultDatabaseURL(home: home)

        #expect(databaseURL.path == "/Users/tester/Library/Application Support/Zed/threads/threads.db")
        #expect(try ZedSessionActivityDetector(databaseURL: databaseURL).activeTasks().isEmpty)
    }

    @Test
    func clampsThreadLimitToTheSQLiteBindingRange() {
        #expect(ZedSessionActivityDetector(maxThreads: 0).maxThreads == 1)
        #expect(ZedSessionActivityDetector(maxThreads: .max).maxThreads == Int(Int32.max))
    }

    @Test
    func reportsSchemaErrorsInsteadOfTreatingDatabaseAsIdle() throws {
        let databaseURL = temporaryDatabaseURL("empty")
        defer { try? FileManager.default.removeItem(at: databaseURL) }
        try execute("", at: databaseURL)

        #expect(throws: AIStateRepositoryError.self) {
            try ZedSessionActivityDetector(databaseURL: databaseURL).activeTasks()
        }
    }
}

private extension ZedSessionActivityDetector {
    static func parseFixtureDate(_ value: String) -> Date? {
        try? Date.ISO8601FormatStyle(includingFractionalSeconds: true).parse(value)
    }
}

private func temporaryDatabaseURL(_ name: String) -> URL {
    FileManager.default.temporaryDirectory
        .appendingPathComponent("Zisla-zed-\(name)-\(UUID().uuidString).sqlite")
}

private func execute(_ sql: String, at url: URL) throws {
    var database: OpaquePointer?
    guard sqlite3_open(url.path, &database) == SQLITE_OK, let database else {
        sqlite3_close(database)
        throw ZedFixtureError.openFailed
    }
    defer { sqlite3_close(database) }
    var errorMessage: UnsafeMutablePointer<CChar>?
    guard sqlite3_exec(database, sql, nil, nil, &errorMessage) == SQLITE_OK else {
        let message = errorMessage.map { String(cString: $0) } ?? "unknown SQLite error"
        sqlite3_free(errorMessage)
        throw ZedFixtureError.executionFailed(message)
    }
}

private enum ZedFixtureError: Error {
    case openFailed
    case executionFailed(String)
}
