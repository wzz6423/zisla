import Foundation
import SQLite3
import Testing
@testable import ZislaCore
@testable import ZislaKit

struct ZCodeSessionActivityDetectorTests {
    @Test
    func detectsActiveTurnsFromDesktopAndCLISharedState() throws {
        let databaseURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("Zisla-zcode-\(UUID().uuidString).sqlite")
        defer { try? FileManager.default.removeItem(at: databaseURL) }
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        let nowMilliseconds = Int64(now.timeIntervalSince1970 * 1_000)
        try execute(
            """
            CREATE TABLE session (id TEXT PRIMARY KEY, time_updated INTEGER NOT NULL);
            CREATE TABLE turn_usage (
                session_id TEXT NOT NULL, turn_id TEXT NOT NULL, status TEXT NOT NULL,
                started_at INTEGER NOT NULL, first_token_at INTEGER, completed_at INTEGER,
                error_code TEXT, PRIMARY KEY (session_id, turn_id)
            );
            CREATE TABLE model_usage (
                id TEXT PRIMARY KEY, session_id TEXT NOT NULL, turn_id TEXT,
                model_id TEXT NOT NULL, started_at INTEGER NOT NULL
            );
            INSERT INTO session VALUES ('desktop-session', \(nowMilliseconds - 1_000));
            INSERT INTO session VALUES ('cli-session', \(nowMilliseconds - 2_000));
            INSERT INTO session VALUES ('completed-session', \(nowMilliseconds));
            INSERT INTO session VALUES ('stale-error-session', \(nowMilliseconds - 7_200_000));
            INSERT INTO turn_usage VALUES (
                'desktop-session', 'desktop-turn', 'running', \(nowMilliseconds - 7_300_000), NULL, NULL, NULL
            );
            INSERT INTO turn_usage VALUES (
                'cli-session', 'cli-turn', 'error', \(nowMilliseconds - 10_000), NULL,
                \(nowMilliseconds - 2_000), 'MODEL_UNAVAILABLE'
            );
            INSERT INTO turn_usage VALUES (
                'completed-session', 'completed-turn', 'completed', \(nowMilliseconds - 2_000), NULL,
                \(nowMilliseconds - 1_000), NULL
            );
            INSERT INTO turn_usage VALUES (
                'stale-error-session', 'stale-error-turn', 'error', \(nowMilliseconds - 7_300_000), NULL,
                \(nowMilliseconds - 7_200_000), 'STALE'
            );
            INSERT INTO model_usage VALUES (
                'desktop-model', 'desktop-session', 'desktop-turn', 'glm-5', \(nowMilliseconds - 4_000)
            );
            """,
            at: databaseURL
        )

        let tasks = try ZCodeSessionActivityDetector(
            databaseURL: databaseURL,
            recencyThreshold: 3_600,
            now: { now }
        ).activeTasks()

        #expect(tasks.count == 2)
        #expect(tasks[0].id == ZCodeSessionActivityDetector.taskID(
            forSessionID: "desktop-session",
            turnID: "desktop-turn"
        ))
        #expect(tasks[0].provider == .zcode)
        #expect(tasks[0].title == "ZCode")
        #expect(tasks[0].detail == "glm-5")
        #expect(tasks[0].status == .running)
        #expect(tasks[0].updatedAt == Date(timeIntervalSince1970: Double(nowMilliseconds - 1_000) / 1_000))
        #expect(tasks[1].status == .error)
        #expect(tasks[1].failureReason == "MODEL_UNAVAILABLE")
    }

    @Test
    func usesSharedStatePathAndHandlesMissingDatabase() throws {
        let home = URL(fileURLWithPath: "/Users/tester", isDirectory: true)
        let databaseURL = ZCodeSessionActivityDetector.defaultDatabaseURL(home: home)

        #expect(databaseURL.path == "/Users/tester/.zcode/cli/db/db.sqlite")
        #expect(try ZCodeSessionActivityDetector(databaseURL: databaseURL).activeTasks().isEmpty)
    }

    @Test
    func reportsSchemaErrorsInsteadOfTreatingDatabaseAsIdle() throws {
        let databaseURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("Zisla-zcode-empty-\(UUID().uuidString).sqlite")
        defer { try? FileManager.default.removeItem(at: databaseURL) }
        try execute("", at: databaseURL)

        #expect(throws: AIStateRepositoryError.self) {
            try ZCodeSessionActivityDetector(databaseURL: databaseURL).activeTasks()
        }
    }
}

private func execute(_ sql: String, at url: URL) throws {
    var database: OpaquePointer?
    guard sqlite3_open(url.path, &database) == SQLITE_OK, let database else {
        sqlite3_close(database)
        throw ZCodeFixtureError.openFailed
    }
    defer { sqlite3_close(database) }
    var errorMessage: UnsafeMutablePointer<CChar>?
    guard sqlite3_exec(database, sql, nil, nil, &errorMessage) == SQLITE_OK else {
        let message = errorMessage.map { String(cString: $0) } ?? "unknown SQLite error"
        sqlite3_free(errorMessage)
        throw ZCodeFixtureError.executionFailed(message)
    }
}

private enum ZCodeFixtureError: Error {
    case openFailed
    case executionFailed(String)
}
