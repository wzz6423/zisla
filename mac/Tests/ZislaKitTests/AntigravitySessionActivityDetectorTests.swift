import Foundation
import SQLite3
import Testing
@testable import ZislaCore
@testable import ZislaKit

struct AntigravitySessionActivityDetectorTests {
    private static let now = Date(timeIntervalSince1970: 2_000_000_000)
    private static let startedAt = now.addingTimeInterval(-300)

    @Test
    func detectsOnlyExplicitlyRunningSessionsForEachLiveClient() throws {
        let fixture = try AntigravityFixture()
        defer { fixture.remove() }
        try fixture.insert(surface: "antigravity", id: "desktop", title: "Desktop task", updatedAt: Self.now.addingTimeInterval(-60))
        try fixture.insert(surface: "antigravity-ide", id: "ide", title: "IDE task", updatedAt: Self.now.addingTimeInterval(-30))
        try fixture.insert(surface: "antigravity-cli", id: "cli", title: "CLI task", updatedAt: Self.now.addingTimeInterval(-10))
        try fixture.insert(surface: "antigravity", id: "idle", title: "Idle task", updatedAt: Self.now, notFullyIdle: false)
        try fixture.insert(surface: "antigravity", id: "killed", title: "Killed task", updatedAt: Self.now, killed: true)

        let tasks = try AntigravitySessionActivityDetector(
            dataDirectoryURL: fixture.dataDirectoryURL,
            now: { Self.now },
            runningClients: { [
                "antigravity": Self.startedAt,
                "antigravity-ide": Self.startedAt,
                "antigravity-cli": Self.startedAt,
            ] }
        ).activeTasks()

        #expect(tasks.map(\.id) == ["antigravity-cli-cli", "antigravity-desktop", "antigravity-ide-ide"])
        #expect(tasks.map(\.provider) == [.antigravity, .antigravity, .antigravity])
        #expect(tasks.map(\.title) == ["CLI task", "Desktop task", "IDE task"])
        #expect(tasks.allSatisfy { $0.status == .running && $0.progress == nil })
    }

    @Test
    func rejectsHistoricalAndCrashResidualSummaries() throws {
        let fixture = try AntigravityFixture()
        defer { fixture.remove() }
        try fixture.insert(surface: "antigravity", id: "old", title: "Old", updatedAt: Self.now.addingTimeInterval(-3_600))
        try fixture.insert(surface: "antigravity", id: "prelaunch", title: "Prelaunch", updatedAt: Self.startedAt.addingTimeInterval(-1))
        try fixture.insert(surface: "antigravity", id: "future", title: "Future", updatedAt: Self.now.addingTimeInterval(60))
        try fixture.insert(surface: "antigravity-ide", id: "closed-client", title: "Closed", updatedAt: Self.now)

        let tasks = try AntigravitySessionActivityDetector(
            dataDirectoryURL: fixture.dataDirectoryURL,
            now: { Self.now },
            runningClients: { ["antigravity": Self.startedAt] }
        ).activeTasks()

        #expect(tasks.isEmpty)
    }

    @Test
    func keepsExplicitlyRunningLongToolCallVisible() throws {
        let fixture = try AntigravityFixture()
        defer { fixture.remove() }
        let launchedAt = Self.now.addingTimeInterval(-3 * 60 * 60)
        try fixture.insert(
            surface: "antigravity", id: "long-tool", title: "Long tool",
            updatedAt: launchedAt.addingTimeInterval(60)
        )

        let tasks = try AntigravitySessionActivityDetector(
            dataDirectoryURL: fixture.dataDirectoryURL,
            now: { Self.now },
            runningClients: { ["antigravity": launchedAt] }
        ).activeTasks()

        #expect(tasks.map(\.id) == ["antigravity-long-tool"])
        #expect(tasks.first?.updatedAt == Self.now)
    }

    @Test @MainActor
    func monitorRemovesSessionAfterItBecomesIdle() throws {
        let fixture = try AntigravityFixture()
        defer { fixture.remove() }
        try fixture.insert(
            surface: "antigravity", id: "finishing", title: "Finishing",
            updatedAt: Self.now.addingTimeInterval(-60)
        )
        let detector = AntigravitySessionActivityDetector(
            dataDirectoryURL: fixture.dataDirectoryURL,
            now: { Self.now },
            runningClients: { ["antigravity": Self.startedAt] }
        )
        let monitor = AIStateMonitor(
            directoryURL: fixture.dataDirectoryURL.appendingPathComponent("app-state", isDirectory: true),
            activityDetectors: [detector],
            now: { Self.now }
        )

        monitor.reload(includeUsageSamples: false)
        #expect(monitor.state.tasks.map(\.id) == ["antigravity-finishing"])

        try fixture.markIdle(surface: "antigravity", id: "finishing")
        monitor.reload(includeUsageSamples: false)
        #expect(monitor.state.tasks.isEmpty)
    }

    @Test
    func acceptsNumericUnixSecondsAndMilliseconds() throws {
        let fixture = try AntigravityFixture()
        defer { fixture.remove() }
        try fixture.insert(
            surface: "antigravity", id: "seconds", title: "Seconds",
            updatedAt: Self.now.addingTimeInterval(-60), timestampFormat: .seconds
        )
        try fixture.insert(
            surface: "antigravity", id: "milliseconds", title: "Milliseconds",
            updatedAt: Self.now.addingTimeInterval(-30), timestampFormat: .milliseconds
        )
        try fixture.insert(
            surface: "antigravity", id: "malformed", title: "Malformed",
            updatedAt: Self.now, timestampFormat: .malformed
        )

        let tasks = try AntigravitySessionActivityDetector(
            dataDirectoryURL: fixture.dataDirectoryURL,
            now: { Self.now },
            runningClients: { ["antigravity": Self.startedAt] }
        ).activeTasks()

        #expect(tasks.map(\.id) == ["antigravity-milliseconds", "antigravity-seconds"])
    }

    @Test
    func acceptsTimestampTextWithTimezoneOffset() throws {
        let fixture = try AntigravityFixture()
        defer { fixture.remove() }
        try fixture.insert(
            surface: "antigravity-ide", id: "timezone", title: "Timezone",
            updatedAt: Self.now.addingTimeInterval(-60), timestampFormat: .datetimeWithOffset
        )

        let tasks = try AntigravitySessionActivityDetector(
            dataDirectoryURL: fixture.dataDirectoryURL,
            now: { Self.now },
            runningClients: { ["antigravity-ide": Self.startedAt] }
        ).activeTasks()

        #expect(tasks.map(\.id) == ["antigravity-ide-timezone"])
    }

    @Test
    func acceptsSummariesWrittenAtClientLaunchAndCurrentTime() throws {
        let fixture = try AntigravityFixture()
        defer { fixture.remove() }
        try fixture.insert(surface: "antigravity", id: "launch", title: "Launch", updatedAt: Self.startedAt)
        try fixture.insert(surface: "antigravity", id: "now", title: "Now", updatedAt: Self.now)

        let tasks = try AntigravitySessionActivityDetector(
            dataDirectoryURL: fixture.dataDirectoryURL,
            now: { Self.now },
            runningClients: { ["antigravity": Self.startedAt] }
        ).activeTasks()

        #expect(Set(tasks.map(\.id)) == ["antigravity-launch", "antigravity-now"])
    }

    @Test @MainActor
    func monitorRemovesClosedAndRestartedClientsWithoutExpiringLongTasks() throws {
        let fixture = try AntigravityFixture()
        defer { fixture.remove() }
        let launchedAt = Self.now.addingTimeInterval(-3 * 60 * 60)
        var clients = ["antigravity": launchedAt]
        try fixture.insert(
            surface: "antigravity", id: "long", title: "Long task",
            updatedAt: launchedAt.addingTimeInterval(60)
        )
        let detector = AntigravitySessionActivityDetector(
            dataDirectoryURL: fixture.dataDirectoryURL,
            now: { Self.now },
            runningClients: { clients }
        )
        let monitor = AIStateMonitor(
            directoryURL: fixture.dataDirectoryURL.appendingPathComponent("app-state", isDirectory: true),
            activityDetectors: [detector],
            now: { Self.now }
        )

        monitor.reload(includeUsageSamples: false)
        #expect(monitor.state.tasks.map(\.id) == ["antigravity-long"])

        clients = [:]
        monitor.reload(includeUsageSamples: false)
        #expect(monitor.state.tasks.isEmpty)

        clients = ["antigravity": Self.startedAt]
        monitor.reload(includeUsageSamples: false)
        #expect(monitor.state.tasks.isEmpty)

        try fixture.insert(surface: "antigravity", id: "new", title: "New task", updatedAt: Self.now)
        monitor.reload(includeUsageSamples: false)
        #expect(monitor.state.tasks.map(\.id) == ["antigravity-new"])
    }

    @Test
    func ignoresMissingOrUnknownSchemaWithoutWritingToStore() throws {
        let fixture = try AntigravityFixture()
        defer { fixture.remove() }
        try fixture.createEmptyDatabase(surface: "antigravity")
        try FileManager.default.createDirectory(
            at: fixture.summaryURL(surface: "antigravity-cli").deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let detector = AntigravitySessionActivityDetector(
            dataDirectoryURL: fixture.dataDirectoryURL,
            now: { Self.now },
            runningClients: { ["antigravity": Self.startedAt, "antigravity-cli": Self.startedAt] }
        )

        #expect(try detector.activeTasks().isEmpty)
        #expect(!FileManager.default.fileExists(atPath: fixture.summaryURL(surface: "antigravity").path + "-wal"))
        #expect(!FileManager.default.fileExists(atPath: fixture.summaryURL(surface: "antigravity").path + "-shm"))
        #expect(!FileManager.default.fileExists(atPath: fixture.summaryURL(surface: "antigravity-cli").path))
    }

    @Test
    func rejectsMalformedIdentifiersAndUsesFallbackTitles() throws {
        let fixture = try AntigravityFixture()
        defer { fixture.remove() }
        try fixture.insert(surface: "antigravity", id: "blank-title", title: "  \n ", updatedAt: Self.now)
        try fixture.insert(
            surface: "antigravity", id: String(repeating: "a", count: 300),
            title: "Oversized identifier", updatedAt: Self.now
        )
        try fixture.execute("""
            INSERT INTO conversation_summaries VALUES
                (NULL, 'Null identifier', 2000000000, 1, 0),
                ('   ', 'Empty identifier', 2000000000, 1, 0),
                (CAST(X'FFFE' AS TEXT), 'Invalid UTF-8', 2000000000, 1, 0),
                (CAST(X'F09F92' AS TEXT), 'Truncated UTF-8', 2000000000, 1, 0),
                (CAST(X'61626300646566' AS TEXT), 'Embedded NUL', 2000000000, 1, 0),
                (X'616263', 'Blob identifier', 2000000000, 1, 0),
                ('null-title', NULL, 2000000000, 1, 0);
            """, at: fixture.summaryURL(surface: "antigravity"))

        let tasks = try AntigravitySessionActivityDetector(
            dataDirectoryURL: fixture.dataDirectoryURL,
            now: { Self.now },
            runningClients: { ["antigravity": Self.startedAt] }
        ).activeTasks()

        #expect(tasks.map(\.id) == ["antigravity-blank-title", "antigravity-null-title"])
        #expect(tasks.allSatisfy { $0.title == "Antigravity" })
    }

    @Test
    func boundsReturnedTasksAndUnicodeTitles() throws {
        let fixture = try AntigravityFixture()
        defer { fixture.remove() }
        let title = String(repeating: "题", count: 512)
        try fixture.insertMany(surface: "antigravity", count: 512, title: title)

        let tasks = try AntigravitySessionActivityDetector(
            dataDirectoryURL: fixture.dataDirectoryURL,
            now: { Self.now },
            runningClients: { ["antigravity": Self.startedAt] }
        ).activeTasks()

        #expect(tasks.count == 128)
        #expect(tasks.first?.id == "antigravity-bulk-000000")
        #expect(tasks.last?.id == "antigravity-bulk-000127")
        #expect(tasks.allSatisfy { $0.title == String(repeating: "题", count: 256) })
    }

    @Test
    func rejectsOversizedRowsAndRecoversAfterRemoval() throws {
        let fixture = try AntigravityFixture()
        defer { fixture.remove() }
        try fixture.insert(surface: "antigravity", id: "healthy", title: "Healthy", updatedAt: Self.now)
        try fixture.insert(
            surface: "antigravity", id: "oversized", title: String(repeating: "x", count: 2 * 1_024 * 1_024),
            updatedAt: Self.now
        )
        let detector = AntigravitySessionActivityDetector(
            dataDirectoryURL: fixture.dataDirectoryURL,
            now: { Self.now },
            runningClients: { ["antigravity": Self.startedAt] }
        )

        #expect(try detector.activeTasks().isEmpty)
        try fixture.execute(
            "DELETE FROM conversation_summaries WHERE conversation_id = 'oversized'",
            at: fixture.summaryURL(surface: "antigravity")
        )
        #expect(try detector.activeTasks().map(\.id) == ["antigravity-healthy"])
    }

    @Test
    func boundsQueryWorkAndRecoversFromAnOversizedStore() throws {
        let fixture = try AntigravityFixture()
        defer { fixture.remove() }
        try fixture.insertMany(surface: "antigravity", count: 100_000)
        let detector = AntigravitySessionActivityDetector(
            dataDirectoryURL: fixture.dataDirectoryURL,
            now: { Self.now },
            runningClients: { ["antigravity": Self.startedAt] }
        )

        #expect(try detector.activeTasks().isEmpty)
        try fixture.execute(
            "DELETE FROM conversation_summaries WHERE conversation_id != 'bulk-000000'",
            at: fixture.summaryURL(surface: "antigravity")
        )
        #expect(try detector.activeTasks().map(\.id) == ["antigravity-bulk-000000"])
    }

    @Test
    func scansLargeIdleHistoryWithoutDroppingAnOlderLongTask() throws {
        let fixture = try AntigravityFixture()
        defer { fixture.remove() }
        try fixture.insertMany(surface: "antigravity", count: 20_000, notFullyIdle: false)
        try fixture.insert(
            surface: "antigravity", id: "long", title: "Long task",
            updatedAt: Self.now.addingTimeInterval(-2 * 60 * 60)
        )

        let tasks = try AntigravitySessionActivityDetector(
            dataDirectoryURL: fixture.dataDirectoryURL,
            now: { Self.now },
            runningClients: { ["antigravity": Self.now.addingTimeInterval(-3 * 60 * 60)] }
        ).activeTasks()

        #expect(tasks.map(\.id) == ["antigravity-long"])
        #expect(tasks.first?.updatedAt == Self.now)
    }

    @Test
    func readsCommittedWALChangesWithoutWritingToStore() throws {
        let fixture = try AntigravityFixture()
        defer { fixture.remove() }
        try fixture.insert(surface: "antigravity", id: "wal", title: "WAL task", updatedAt: Self.now)
        let databaseURL = fixture.summaryURL(surface: "antigravity")
        let walURL = URL(fileURLWithPath: databaseURL.path + "-wal")
        let detector = AntigravitySessionActivityDetector(
            dataDirectoryURL: fixture.dataDirectoryURL,
            now: { Self.now },
            runningClients: { ["antigravity": Self.startedAt] }
        )

        try fixture.withDatabase(at: databaseURL) { writer in
            try #require(sqlite3_exec(writer, "PRAGMA journal_mode=WAL; BEGIN; UPDATE conversation_summaries SET not_fully_idle=0", nil, nil, nil) == SQLITE_OK)
            let databaseBefore = try Data(contentsOf: databaseURL)
            let walBefore = try Data(contentsOf: walURL)
            #expect(try detector.activeTasks().map(\.id) == ["antigravity-wal"])
            #expect(try Data(contentsOf: databaseURL) == databaseBefore)
            #expect(try Data(contentsOf: walURL) == walBefore)

            try #require(sqlite3_exec(writer, "COMMIT", nil, nil, nil) == SQLITE_OK)
            let committedWAL = try Data(contentsOf: walURL)
            #expect(try detector.activeTasks().isEmpty)
            #expect(try Data(contentsOf: databaseURL) == databaseBefore)
            #expect(try Data(contentsOf: walURL) == committedWAL)
        }
    }

    @Test
    func recoversAfterAnExclusiveLockWithoutSuppressingOtherSurfaces() throws {
        let fixture = try AntigravityFixture()
        defer { fixture.remove() }
        try fixture.insert(surface: "antigravity", id: "editor", title: "Editor", updatedAt: Self.now)
        try fixture.insert(surface: "antigravity-cli", id: "cli", title: "CLI", updatedAt: Self.now)
        let detector = AntigravitySessionActivityDetector(
            dataDirectoryURL: fixture.dataDirectoryURL,
            now: { Self.now },
            runningClients: { ["antigravity": Self.startedAt, "antigravity-cli": Self.startedAt] }
        )

        try fixture.withDatabase(at: fixture.summaryURL(surface: "antigravity")) { writer in
            try #require(sqlite3_exec(writer, "BEGIN EXCLUSIVE", nil, nil, nil) == SQLITE_OK)
            #expect(try detector.activeTasks().map(\.id) == ["antigravity-cli-cli"])
            try #require(sqlite3_exec(writer, "ROLLBACK", nil, nil, nil) == SQLITE_OK)
            #expect(try detector.activeTasks().map(\.id) == ["antigravity-cli-cli", "antigravity-editor"])
        }
    }

    @Test
    func rejectsCorruptStoresWithASeededInputBudgetAndRecovers() throws {
        let fixture = try AntigravityFixture()
        defer { fixture.remove() }
        try fixture.createEmptyDatabase(surface: "antigravity")
        try fixture.insert(surface: "antigravity-cli", id: "healthy", title: "Healthy", updatedAt: Self.now)
        let databaseURL = fixture.summaryURL(surface: "antigravity")
        let detector = AntigravitySessionActivityDetector(
            dataDirectoryURL: fixture.dataDirectoryURL,
            now: { Self.now },
            runningClients: { ["antigravity": Self.startedAt, "antigravity-cli": Self.startedAt] }
        )
        var seed: UInt64 = 0xA617_2026
        for iteration in 0..<64 {
            var malformed = Data([0xFF])
            for _ in 0..<(iteration * 8) {
                seed = seed &* 6_364_136_223_846_793_005 &+ 1
                malformed.append(UInt8(truncatingIfNeeded: seed >> 32))
            }
            try malformed.write(to: databaseURL, options: .atomic)
            #expect(try detector.activeTasks().map(\.id) == ["antigravity-cli-healthy"], "seed=0xA6172026, case=\(iteration)")
            #expect(try Data(contentsOf: databaseURL) == malformed)
        }

        try FileManager.default.removeItem(at: databaseURL)
        try fixture.insert(surface: "antigravity", id: "restored", title: "Restored", updatedAt: Self.now)
        #expect(try detector.activeTasks().map(\.id) == ["antigravity-cli-healthy", "antigravity-restored"])
    }

    @Test
    func processListMatchesOnlyAntigravityClientsAndKeepsEarliestLaunch() {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "EEE MMM d HH:mm:ss yyyy"
        let startedAt = formatter.string(from: Self.startedAt)
        let later = formatter.string(from: Self.startedAt.addingTimeInterval(60))
        let processList = """
            100 \(startedAt) /Applications/Antigravity.app/Contents/MacOS/Antigravity
            101 \(later) /Applications/Antigravity.app/Contents/MacOS/language_server_macos_arm
            102 \(startedAt) /Applications/Antigravity IDE.app/Contents/MacOS/Antigravity IDE
            103 \(startedAt) /opt/homebrew/bin/agy
            104 \(startedAt) /Applications/Windsurf.app/Contents/MacOS/language_server_macos_arm
            105 \(startedAt) /tmp/fake/antigravity-helper
            """

        let starts = AntigravitySessionActivityDetector.parseRunningClients(Data(processList.utf8))

        #expect(starts.keys.sorted() == ["antigravity", "antigravity-cli", "antigravity-ide"])
        #expect(starts["antigravity"] == Self.startedAt)
        #expect(starts["antigravity-ide"] == Self.startedAt)
        #expect(starts["antigravity-cli"] == Self.startedAt)
    }

    @Test
    func processListIgnoresOrphanedHelpersAndMalformedPIDs() {
        let processList = """
            100 Wed May 18 03:28:20 2033 /Applications/Antigravity.app/Contents/MacOS/language_server_macos_arm
            101 Wed May 18 03:28:20 2033 /Applications/Antigravity IDE.app/Contents/Frameworks/Antigravity Helper.app/Contents/MacOS/Antigravity Helper
            102 Wed May 18 03:28:20 2033 /Applications/Antigravity.app/Contents/MacOS/chrome_crashpad_handler
            0 Wed May 18 03:28:20 2033 /opt/homebrew/bin/agy
            -1 Wed May 18 03:28:20 2033 /opt/homebrew/bin/antigravity
            """

        #expect(AntigravitySessionActivityDetector.parseRunningClients(Data(processList.utf8)).isEmpty)
    }

    @Test
    func processListMapsEitherEditorToBothKnownStorageLayouts() {
        for executable in [
            "/Applications/Antigravity IDE.app/Contents/MacOS/Electron",
            "/Applications/Antigravity.app/Contents/MacOS/Antigravity",
        ] {
            let processList = "100 Wed May 18 03:28:20 2033 \(executable)"
            let starts = AntigravitySessionActivityDetector.parseRunningClients(Data(processList.utf8))
            #expect(starts.keys.sorted() == ["antigravity", "antigravity-ide"])
            #expect(starts["antigravity"] == starts["antigravity-ide"])
        }
    }

    @Test
    func processListRejectsInvalidDatesAndTruncatedRecords() {
        for listing in [
            "", "100", "100 Wed May 18 03:28:20",
            "2147483648 Wed May 18 03:28:20 2033 /opt/homebrew/bin/agy",
            "100 invalid May 99 99:99:99 2033 /opt/homebrew/bin/agy",
            "100 Wed May 18 03:28:20 2033 /Applications/Other.app/Contents/MacOS/antigravity",
        ] {
            #expect(AntigravitySessionActivityDetector.parseRunningClients(Data(listing.utf8)).isEmpty)
        }
    }
}

private struct AntigravityFixture {
    enum TimestampFormat {
        case datetime
        case datetimeWithOffset
        case seconds
        case milliseconds
        case malformed
    }

    let dataDirectoryURL: URL

    init() throws {
        dataDirectoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("Zisla-antigravity-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dataDirectoryURL, withIntermediateDirectories: true)
    }

    func remove() {
        try? FileManager.default.removeItem(at: dataDirectoryURL)
    }

    func summaryURL(surface: String) -> URL {
        dataDirectoryURL.appendingPathComponent(surface, isDirectory: true)
            .appendingPathComponent("conversation_summaries.db", isDirectory: false)
    }

    func createEmptyDatabase(surface: String) throws {
        let url = summaryURL(surface: surface)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try execute("CREATE TABLE unrelated (id TEXT)", at: url)
    }

    func markIdle(surface: String, id: String) throws {
        try execute(
            "UPDATE conversation_summaries SET not_fully_idle = 0 WHERE conversation_id = '\(id)'",
            at: summaryURL(surface: surface)
        )
    }

    func insertMany(surface: String, count: Int, title: String = "Task", notFullyIdle: Bool = true) throws {
        try insert(surface: surface, id: "seed", title: "Seed", updatedAt: Date(timeIntervalSince1970: 2_000_000_000), notFullyIdle: false)
        let quotedTitle = title.replacingOccurrences(of: "'", with: "''")
        try execute("""
            WITH RECURSIVE rows(value) AS (
                SELECT 0 UNION ALL SELECT value + 1 FROM rows WHERE value + 1 < \(count)
            )
            INSERT INTO conversation_summaries
            SELECT printf('bulk-%06d', value), '\(quotedTitle)', 1999999999, \(notFullyIdle ? 1 : 0), 0 FROM rows;
            """, at: summaryURL(surface: surface))
    }

    func insert(
        surface: String,
        id: String,
        title: String,
        updatedAt: Date,
        notFullyIdle: Bool = true,
        killed: Bool = false,
        timestampFormat: TimestampFormat = .datetime
    ) throws {
        let url = summaryURL(surface: surface)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let timestamp = Int64(updatedAt.timeIntervalSince1970)
        let storedTime: String
        switch timestampFormat {
        case .datetime:
            storedTime = "datetime(\(timestamp), 'unixepoch')"
        case .datetimeWithOffset:
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = TimeZone(secondsFromGMT: 8 * 60 * 60)
            formatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSSSSSXXXXX"
            storedTime = "'\(formatter.string(from: updatedAt))'"
        case .seconds:
            storedTime = String(timestamp)
        case .milliseconds:
            storedTime = String(timestamp * 1_000)
        case .malformed:
            storedTime = "'invalid date'"
        }
        try withDatabase(at: url) { database in
            guard sqlite3_exec(database,
            """
            CREATE TABLE IF NOT EXISTS conversation_summaries (
                conversation_id TEXT PRIMARY KEY, title TEXT, last_modified_time DATETIME,
                not_fully_idle NUMERIC, killed NUMERIC
            );
            """,
                nil, nil, nil
            ) == SQLITE_OK else { throw AntigravityFixtureError.statementFailed }
            var statement: OpaquePointer?
            let sql = "INSERT INTO conversation_summaries VALUES (?, ?, \(storedTime), ?, ?)"
            guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
                sqlite3_finalize(statement)
                throw AntigravityFixtureError.statementFailed
            }
            defer { sqlite3_finalize(statement) }
            let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
            sqlite3_bind_text(statement, 1, id, Int32(id.utf8.count), transient)
            sqlite3_bind_text(statement, 2, title, Int32(title.utf8.count), transient)
            sqlite3_bind_int(statement, 3, notFullyIdle ? 1 : 0)
            sqlite3_bind_int(statement, 4, killed ? 1 : 0)
            guard sqlite3_step(statement) == SQLITE_DONE else { throw AntigravityFixtureError.statementFailed }
        }
    }

    func execute(_ sql: String, at url: URL) throws {
        try withDatabase(at: url) { database in
            guard sqlite3_exec(database, sql, nil, nil, nil) == SQLITE_OK else {
                throw AntigravityFixtureError.statementFailed
            }
        }
    }

    func withDatabase<T>(at url: URL, _ body: (OpaquePointer) throws -> T) throws -> T {
        var database: OpaquePointer?
        guard sqlite3_open(url.path, &database) == SQLITE_OK, let database else {
            sqlite3_close(database)
            throw AntigravityFixtureError.openFailed
        }
        defer { sqlite3_close(database) }
        return try body(database)
    }
}

private enum AntigravityFixtureError: Error {
    case openFailed
    case statementFailed
}
