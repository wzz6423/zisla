import Foundation
import SQLite3
import Testing
@testable import ZislaCore
@testable import ZislaKit

struct WorkBuddySessionActivityDetectorTests {
    private static let now = Date(timeIntervalSince1970: 1_800_000_000)
    private static let conversationID = "7a28637a-2ccb-46f8-9580-3304838750f6"

    @Test
    func detectsRunningSessionFromDatabase() throws {
        let databaseURL = try makeWorkBuddyDatabase()
        defer { removeWorkBuddyDatabase(at: databaseURL) }

        let startedAt = Self.now.addingTimeInterval(-40 * 60)
        try insertWorkBuddySession(
            at: databaseURL,
            id: Self.conversationID,
            title: "创建 worktree 分支并支持检测 workbuddy 任务",
            status: "working",
            model: "deepseek-v4.1-flash",
            createdAt: Self.milliseconds(startedAt),
            updatedAt: Self.milliseconds(Self.now.addingTimeInterval(-60))
        )

        let task = try #require(WorkBuddySessionActivityDetector(
            databaseURL: databaseURL,
            now: { Self.now }
        ).activeTasks().first)

        #expect(task.id == WorkBuddySessionActivityDetector.taskID(forConversationID: Self.conversationID))
        #expect(task.provider == .harness)
        #expect(task.title == "创建 worktree 分支并支持检测 workbuddy 任务")
        #expect(task.detail == "deepseek-v4.1-flash")
        #expect(task.progress == nil)
        #expect(task.status == .running)
        #expect(task.sessionURL?.absoluteString == "workbuddy://chat/\(Self.conversationID)")
        #expect(task.startedAt == startedAt)
        #expect(task.updatedAt == Self.now.addingTimeInterval(-60))
    }

    @Test
    func prefersCustomTitleOverGeneratedTitle() throws {
        let databaseURL = try makeWorkBuddyDatabase()
        defer { removeWorkBuddyDatabase(at: databaseURL) }

        try insertWorkBuddySession(
            at: databaseURL,
            id: Self.conversationID,
            title: "创建 worktree 分支并支持检测 workbuddy 任务",
            customTitle: "WorkBuddy 任务检测",
            status: "working",
            createdAt: Self.milliseconds(Self.now.addingTimeInterval(-5 * 60)),
            updatedAt: Self.milliseconds(Self.now)
        )

        let task = try #require(WorkBuddySessionActivityDetector(
            databaseURL: databaseURL,
            now: { Self.now }
        ).activeTasks().first)

        #expect(task.title == "WorkBuddy 任务检测")
    }

    @Test
    func fallsBackToDefaultTitleWhenTitlesAreMissing() throws {
        let databaseURL = try makeWorkBuddyDatabase()
        defer { removeWorkBuddyDatabase(at: databaseURL) }

        try insertWorkBuddySession(
            at: databaseURL,
            id: Self.conversationID,
            title: "   ",
            status: "working",
            createdAt: Self.milliseconds(Self.now),
            updatedAt: Self.milliseconds(Self.now)
        )

        let task = try #require(WorkBuddySessionActivityDetector(
            databaseURL: databaseURL,
            now: { Self.now }
        ).activeTasks().first)

        #expect(task.title == "WorkBuddy")
        #expect(task.detail == nil)
    }

    @Test
    func mapsDatabaseStatusesToProgressStatuses() throws {
        let databaseURL = try makeWorkBuddyDatabase()
        defer { removeWorkBuddyDatabase(at: databaseURL) }

        let expected: [String: AIProgressStatus] = [
            "workbuddy-session-1": .running,
            "workbuddy-session-2": .queued,
            "workbuddy-session-3": .blocked,
            "workbuddy-session-4": .error,
        ]
        // `Pending` is the schema default, so case-insensitive matching is required.
        for (offset, status) in ["working", "Pending", "blocked", "ERROR"].enumerated() {
            try insertWorkBuddySession(
                at: databaseURL,
                id: "\(offset + 1)",
                title: "session \(offset + 1)",
                status: status,
                createdAt: Self.milliseconds(Self.now.addingTimeInterval(-60)),
                updatedAt: Self.milliseconds(Self.now.addingTimeInterval(TimeInterval(-60 + offset)))
            )
        }

        let tasks = try WorkBuddySessionActivityDetector(
            databaseURL: databaseURL,
            now: { Self.now }
        ).activeTasks()

        #expect(tasks.count == expected.count)
        for task in tasks {
            #expect(expected[task.id] == task.status)
        }
    }

    @Test
    func ignoresFinishedArchivedAndDeletedSessions() throws {
        let databaseURL = try makeWorkBuddyDatabase()
        defer { removeWorkBuddyDatabase(at: databaseURL) }

        let finished: [(String, Int64?)] = [
            ("completed", nil),
            ("archived", nil),
            ("working", Self.milliseconds(Self.now)),
        ]
        for (offset, entry) in finished.enumerated() {
            try insertWorkBuddySession(
                at: databaseURL,
                id: "session-\(offset)",
                title: "session \(offset)",
                status: entry.0,
                createdAt: Self.milliseconds(Self.now.addingTimeInterval(-60)),
                updatedAt: Self.milliseconds(Self.now),
                deletedAt: entry.1
            )
        }

        #expect(try WorkBuddySessionActivityDetector(
            databaseURL: databaseURL,
            now: { Self.now }
        ).activeTasks().isEmpty)
    }

    @Test
    func ignoresStaleSessions() throws {
        let databaseURL = try makeWorkBuddyDatabase()
        defer { removeWorkBuddyDatabase(at: databaseURL) }

        let recencyThreshold: TimeInterval = 30 * 60
        // The cutoff is inclusive, so an activity exactly at the boundary is still reported.
        try insertWorkBuddySession(
            at: databaseURL,
            id: "session-boundary",
            title: "boundary",
            status: "working",
            createdAt: Self.milliseconds(Self.now.addingTimeInterval(-recencyThreshold - 60)),
            updatedAt: Self.milliseconds(Self.now.addingTimeInterval(-recencyThreshold))
        )
        try insertWorkBuddySession(
            at: databaseURL,
            id: "session-stale",
            title: "stale",
            status: "working",
            createdAt: Self.milliseconds(Self.now.addingTimeInterval(-recencyThreshold - 60)),
            updatedAt: Self.milliseconds(Self.now.addingTimeInterval(-recencyThreshold)),
            lastActivityAt: Self.milliseconds(Self.now.addingTimeInterval(-recencyThreshold - 0.001))
        )

        let tasks = try WorkBuddySessionActivityDetector(
            databaseURL: databaseURL,
            recencyThreshold: recencyThreshold,
            now: { Self.now }
        ).activeTasks()

        #expect(tasks.map(\.id) == [WorkBuddySessionActivityDetector.taskID(forConversationID: "session-boundary")])
    }

    @Test
    func fallsBackToUpdatedAtWhenLastActivityIsMissing() throws {
        let databaseURL = try makeWorkBuddyDatabase()
        defer { removeWorkBuddyDatabase(at: databaseURL) }

        // Sessions resumed before `last_activity_at` existed still carry a usable `updated_at`.
        let updatedAt = Self.now.addingTimeInterval(-15 * 60)
        try insertWorkBuddySession(
            at: databaseURL,
            id: Self.conversationID,
            title: "no activity column",
            status: "working",
            createdAt: Self.milliseconds(Self.now.addingTimeInterval(-60 * 60)),
            updatedAt: Self.milliseconds(updatedAt)
        )

        let task = try #require(WorkBuddySessionActivityDetector(
            databaseURL: databaseURL,
            now: { Self.now }
        ).activeTasks().first)

        #expect(task.updatedAt == updatedAt)
    }

    @Test
    func sortsByMostRecentActivity() throws {
        let databaseURL = try makeWorkBuddyDatabase()
        defer { removeWorkBuddyDatabase(at: databaseURL) }

        let sessionIDs = ["session-a", "session-b", "session-c"]
        for (offset, sessionID) in sessionIDs.enumerated() {
            try insertWorkBuddySession(
                at: databaseURL,
                id: sessionID,
                title: sessionID,
                status: "working",
                createdAt: Self.milliseconds(Self.now.addingTimeInterval(-60 * 60)),
                updatedAt: Self.milliseconds(Self.now.addingTimeInterval(-60 * 60)),
                lastActivityAt: Self.milliseconds(Self.now.addingTimeInterval(TimeInterval(-offset * 60)))
            )
        }

        let tasks = try WorkBuddySessionActivityDetector(
            databaseURL: databaseURL,
            now: { Self.now }
        ).activeTasks()

        #expect(tasks.map(\.id) == sessionIDs.map(WorkBuddySessionActivityDetector.taskID(forConversationID:)))
    }

    @Test
    func returnsNoTasksWhenDatabaseOrSchemaIsMissing() throws {
        // An unexpected schema (WorkBuddy migrated the database) must not break the AI state refresh.
        let emptyDatabaseURL = try makeWorkBuddyDatabase(createSessionTable: false)
        defer { removeWorkBuddyDatabase(at: emptyDatabaseURL) }
        #expect(try WorkBuddySessionActivityDetector(databaseURL: emptyDatabaseURL).activeTasks().isEmpty)

        let missingDatabaseURL = emptyDatabaseURL.deletingLastPathComponent()
            .appendingPathComponent("missing.db", isDirectory: false)
        #expect(try WorkBuddySessionActivityDetector(databaseURL: missingDatabaseURL).activeTasks().isEmpty)
    }
}

private extension WorkBuddySessionActivityDetectorTests {
    static func milliseconds(_ date: Date) -> Int64 {
        Int64((date.timeIntervalSince1970 * 1_000).rounded())
    }
}

// MARK: - SQLite Helpers

private enum WorkBuddyTestError: Error {
    case openFailed
}

private func makeWorkBuddyDatabase(createSessionTable: Bool = true) throws -> URL {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("Zisla-workbuddy-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let databaseURL = directory.appendingPathComponent("workbuddy.db", isDirectory: false)
    try createEmptyWorkBuddyDatabase(at: databaseURL)
    guard createSessionTable else { return databaseURL }

    var database: OpaquePointer?
    guard sqlite3_open(databaseURL.path, &database) == SQLITE_OK else {
        sqlite3_close(database)
        throw WorkBuddyTestError.openFailed
    }
    defer { sqlite3_close(database) }

    // Columns mirror the production `sessions` table for every field the detector reads.
    let sessionSQL = """
        CREATE TABLE sessions (
            id TEXT PRIMARY KEY,
            cwd TEXT NOT NULL,
            user_id TEXT NOT NULL,
            title TEXT,
            custom_title TEXT,
            status TEXT NOT NULL DEFAULT 'Pending',
            created_at INTEGER NOT NULL,
            updated_at INTEGER NOT NULL,
            deleted_at INTEGER,
            mode TEXT,
            model TEXT,
            last_activity_at INTEGER
        )
        """
    var error: UnsafeMutablePointer<CChar>?
    guard sqlite3_exec(database, sessionSQL, nil, nil, &error) == SQLITE_OK else {
        sqlite3_free(error)
        throw WorkBuddyTestError.openFailed
    }
    sqlite3_free(error)
    return databaseURL
}

private func createEmptyWorkBuddyDatabase(at url: URL) throws {
    var database: OpaquePointer?
    guard sqlite3_open(url.path, &database) == SQLITE_OK else {
        sqlite3_close(database)
        throw WorkBuddyTestError.openFailed
    }
    sqlite3_close(database)
}

private func removeWorkBuddyDatabase(at url: URL) {
    // `url` is the database file inside a per-test directory.
    try? FileManager.default.removeItem(at: url.deletingLastPathComponent())
}

private func insertWorkBuddySession(
    at url: URL,
    id: String,
    title: String?,
    customTitle: String? = nil,
    status: String,
    model: String? = nil,
    createdAt: Int64,
    updatedAt: Int64,
    lastActivityAt: Int64? = nil,
    deletedAt: Int64? = nil
) throws {
    var database: OpaquePointer?
    guard sqlite3_open(url.path, &database) == SQLITE_OK else {
        sqlite3_close(database)
        throw WorkBuddyTestError.openFailed
    }
    defer { sqlite3_close(database) }

    let sql = """
        INSERT INTO sessions (id, cwd, user_id, title, custom_title, status,
            created_at, updated_at, last_activity_at, model, deleted_at)
        VALUES (?, '/tmp', 'user', ?, ?, ?, ?, ?, ?, ?, ?)
        """
    var statement: OpaquePointer?
    guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else {
        sqlite3_finalize(statement)
        throw WorkBuddyTestError.openFailed
    }
    defer { sqlite3_finalize(statement) }

    sqlite3_bind_text(statement, 1, id, -1, SQLITE_TRANSIENT)
    bindWorkBuddyText(statement, 2, title)
    bindWorkBuddyText(statement, 3, customTitle)
    sqlite3_bind_text(statement, 4, status, -1, SQLITE_TRANSIENT)
    sqlite3_bind_int64(statement, 5, createdAt)
    sqlite3_bind_int64(statement, 6, updatedAt)
    bindWorkBuddyInteger(statement, 7, lastActivityAt)
    bindWorkBuddyText(statement, 8, model)
    bindWorkBuddyInteger(statement, 9, deletedAt)
    sqlite3_step(statement)
}

private func bindWorkBuddyText(_ statement: OpaquePointer?, _ index: Int32, _ value: String?) {
    if let value {
        sqlite3_bind_text(statement, index, value, -1, SQLITE_TRANSIENT)
    } else {
        sqlite3_bind_null(statement, index)
    }
}

private func bindWorkBuddyInteger(_ statement: OpaquePointer?, _ index: Int32, _ value: Int64?) {
    if let value {
        sqlite3_bind_int64(statement, index, value)
    } else {
        sqlite3_bind_null(statement, index)
    }
}

private let SQLITE_TRANSIENT = unsafeBitCast(
    OpaquePointer(bitPattern: -1),
    to: sqlite3_destructor_type.self
)
