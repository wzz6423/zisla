import Foundation
import SQLite3
import Testing

@testable import ZislaKit

struct DailyBriefingNotificationTests {
    private let start = Date(timeIntervalSinceReferenceDate: 815_500_000)

    private func withDatabase(_ body: (URL, OpaquePointer?) throws -> Void) throws {
        let library = FileManager.default.temporaryDirectory.appendingPathComponent("zisla-notification-test-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: library) }
        let folder = library.appendingPathComponent("Application Support/Knowledge")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        var database: OpaquePointer?
        #expect(sqlite3_open(folder.appendingPathComponent("knowledgeC.db").path, &database) == SQLITE_OK)
        defer { sqlite3_close(database) }
        try execute("""
            PRAGMA journal_mode=WAL;
            PRAGMA wal_autocheckpoint=0;
            CREATE TABLE ZSOURCE (Z_PK INTEGER PRIMARY KEY, ZDEVICEID TEXT);
            CREATE TABLE ZOBJECT (ZVALUESTRING TEXT, ZSTARTDATE REAL, ZENDDATE REAL, ZSTREAMNAME TEXT, ZSOURCE INTEGER);
            INSERT INTO ZSOURCE VALUES (1, NULL), (2, 'phone');
            """, in: database)
        try body(library, database)
    }

    private func execute(_ sql: String, in database: OpaquePointer?) throws {
        try #require(sqlite3_exec(database, sql, nil, nil, nil) == SQLITE_OK)
    }

    @Test
    func countsLocalReceiptsWithinHalfOpenIntervalAndPreservesWAL() throws {
        try withDatabase { library, database in
            let timestamp = start.timeIntervalSinceReferenceDate
            try execute("""
                INSERT INTO ZOBJECT VALUES
                  ('Receive', \(timestamp - 1), NULL, '/notification/usage', 1),
                  ('Receive', \(timestamp), NULL, '/notification/usage', 1),
                  ('Receive', \(timestamp + 30), NULL, '/notification/usage', 1),
                  ('Receive', \(timestamp + 60), NULL, '/notification/usage', 1),
                  ('Receive', \(timestamp + 120), NULL, '/notification/usage', 1),
                  ('Receive', \(timestamp + 10), NULL, '/notification/usage', 2),
                  ('Clear', \(timestamp + 30), NULL, '/notification/usage', 1),
                  ('Click', \(timestamp + 30), NULL, '/notification/usage', 1),
                  ('Receive', \(timestamp + 30), NULL, '/some/other/stream', 1),
                  ('com.example.editor', \(timestamp), \(timestamp + 60), '/app/usage', 1);
                """, in: database)
            let path = library.appendingPathComponent("Application Support/Knowledge/knowledgeC.db")
            let wal = URL(fileURLWithPath: path.path + "-wal")
            let original = try Data(contentsOf: path)
            let originalWAL = try Data(contentsOf: wal)

            let result = DailyBriefingScreenTimeReader(library: library).read(within: DateInterval(start: start, duration: 120))

            #expect(result.notificationCount == 3)
            #expect(result.local?.count == 1)
            #expect(result.local?.first?.bundleID == "com.example.editor")
            #expect(try Data(contentsOf: path) == original)
            #expect(try Data(contentsOf: wal) == originalWAL)
        }
    }

    @Test
    func availableReceiptHistoryCanReportZeroForAnotherDay() throws {
        try withDatabase { library, database in
            try execute("INSERT INTO ZOBJECT VALUES ('Receive', \(start.timeIntervalSinceReferenceDate - 86_400), NULL, '/notification/usage', 1)", in: database)
            let result = DailyBriefingScreenTimeReader(library: library).read(within: DateInterval(start: start, duration: 3600))
            #expect(result.notificationCount == 0)
        }
    }

    @Test(arguments: ["", "Click", "Clear"])
    func missingReceiptEvidenceStaysUnavailable(event: String) throws {
        try withDatabase { library, database in
            if !event.isEmpty {
                try execute("INSERT INTO ZOBJECT VALUES ('\(event)', \(start.timeIntervalSinceReferenceDate), NULL, '/notification/usage', 1)", in: database)
            }
            let result = DailyBriefingScreenTimeReader(library: library).read(within: DateInterval(start: start, duration: 3600))
            #expect(result.notificationCount == nil)
            #expect(result.local == [])
        }
    }

    @Test
    func malformedReceiptTimestampsDoNotEstablishCoverage() throws {
        try withDatabase { library, database in
            try execute("""
                INSERT INTO ZOBJECT VALUES
                  ('Receive', NULL, NULL, '/notification/usage', 1),
                  ('Receive', 'unknown', NULL, '/notification/usage', 1),
                  ('Receive', X'00', NULL, '/notification/usage', 1);
                """, in: database)
            let result = DailyBriefingScreenTimeReader(library: library).read(within: DateInterval(start: start, duration: 3600))
            #expect(result.notificationCount == nil)
        }
    }

    @Test
    func remoteOnlyReceiptsDoNotImplyLocalCoverage() throws {
        try withDatabase { library, database in
            try execute("INSERT INTO ZOBJECT VALUES ('Receive', \(start.timeIntervalSinceReferenceDate), NULL, '/notification/usage', 2)", in: database)
            #expect(DailyBriefingScreenTimeReader(library: library).read(within: DateInterval(start: start, duration: 3600)).notificationCount == nil)
        }
    }

    @Test
    func missingAndMalformedSourcesStayUnavailable() throws {
        try withDatabase { library, database in
            let reader = DailyBriefingScreenTimeReader(library: library)
            let range = DateInterval(start: start, duration: 3600)
            try execute("DROP TABLE ZSOURCE", in: database)
            #expect(reader.read(within: range).notificationCount == nil)
            let missing = library.appendingPathComponent("missing")
            #expect(DailyBriefingScreenTimeReader(library: missing).read(within: range).notificationCount == nil)
            let corrupt = missing.appendingPathComponent("Application Support/Knowledge")
            try FileManager.default.createDirectory(at: corrupt, withIntermediateDirectories: true)
            try Data("invalid database".utf8).write(to: corrupt.appendingPathComponent("knowledgeC.db"))
            #expect(DailyBriefingScreenTimeReader(library: missing).read(within: range).notificationCount == nil)
        }
    }
}
