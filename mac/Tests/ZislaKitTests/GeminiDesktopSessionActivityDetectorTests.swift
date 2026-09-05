import Foundation
import SQLite3
import Testing
@testable import ZislaCore
@testable import ZislaKit

struct GeminiDesktopSessionActivityDetectorTests {
    @Test
    func reportsChatsWhoseNewestTurnIsStillTheUsers() throws {
        let databaseURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("Zisla-gemini-desktop-\(UUID().uuidString).store")
        defer { try? FileManager.default.removeItem(at: databaseURL) }
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        let reference = now.timeIntervalSince1970 - 978_307_200
        // Turns synced from the server share one creation timestamp, so only ZMESSAGEINDEX orders them.
        let syncedAt = reference - 90
        try executeGeminiDesktopFixture(
            """
            \(geminiDesktopSchema)
            \(insertTurn) ('c_waiting', 1, 0, \(reference - 60));
            \(insertTurn) ('c_answered', 1, 0, \(reference - 300));
            \(insertTurn) ('c_answered', 0, 1, \(reference - 120));
            \(insertTurn) ('c_synced_waiting', 0, 0, \(syncedAt));
            \(insertTurn) ('c_synced_waiting', 1, 1, \(syncedAt));
            \(insertTurn) ('c_synced_answered', 1, 0, \(syncedAt));
            \(insertTurn) ('c_synced_answered', 0, 1, \(syncedAt));
            \(insertTurn) ('c_stale', 1, 0, \(reference - 3_600));
            """,
            at: databaseURL
        )

        let tasks = try GeminiDesktopSessionActivityDetector(
            databaseURLs: [databaseURL],
            recencyThreshold: 15 * 60,
            now: { now }
        ).activeTasks()

        #expect(tasks.map(\.id) == [
            GeminiDesktopSessionActivityDetector.taskID(forChatUUID: "c_waiting"),
            GeminiDesktopSessionActivityDetector.taskID(forChatUUID: "c_synced_waiting"),
        ])
        #expect(tasks[0].provider == .gemini)
        #expect(tasks[0].title == "Gemini")
        #expect(tasks[0].detail == "Desktop")
        #expect(tasks[0].status == .running)
        #expect(tasks[0].updatedAt == now.addingTimeInterval(-60))
        #expect(tasks[0].startedAt == now.addingTimeInterval(-60))
    }

    @Test
    func discoversEveryProfileStoreNewestSchemaFirst() throws {
        let home = FileManager.default.temporaryDirectory
            .appendingPathComponent("Zisla-gemini-home-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: home) }
        let chatsRoot = home.appendingPathComponent(
            "Library/Caches/com.google.GeminiMacOS/Gemini",
            isDirectory: true
        )
        for relativePath in ["user1/ChatInfo.store", "user1/ChatInfo2.store", "user2/ChatInfo2.store"] {
            let url = chatsRoot.appendingPathComponent(relativePath)
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try Data().write(to: url)
        }

        let discovered = GeminiDesktopSessionActivityDetector.defaultDatabaseURLs(home: home)

        #expect(discovered.map { "\($0.deletingLastPathComponent().lastPathComponent)/\($0.lastPathComponent)" } == [
            "user1/ChatInfo2.store",
            "user1/ChatInfo.store",
            "user2/ChatInfo2.store",
        ])
    }

    @Test
    func skipsMissingStoreAndReportsSchemaDrift() throws {
        let missing = FileManager.default.temporaryDirectory
            .appendingPathComponent("Zisla-gemini-desktop-missing-\(UUID().uuidString).store")
        #expect(try GeminiDesktopSessionActivityDetector(databaseURLs: [missing]).activeTasks().isEmpty)

        let empty = FileManager.default.temporaryDirectory
            .appendingPathComponent("Zisla-gemini-desktop-empty-\(UUID().uuidString).store")
        defer { try? FileManager.default.removeItem(at: empty) }
        try executeGeminiDesktopFixture("", at: empty)

        #expect(throws: AIStateRepositoryError.self) {
            try GeminiDesktopSessionActivityDetector(databaseURLs: [empty]).activeTasks()
        }
    }

    @Test
    func limitsReportedChatsToTheNewestOnes() throws {
        let databaseURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("Zisla-gemini-desktop-limit-\(UUID().uuidString).store")
        defer { try? FileManager.default.removeItem(at: databaseURL) }
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        let reference = now.timeIntervalSince1970 - 978_307_200
        try executeGeminiDesktopFixture(
            """
            \(geminiDesktopSchema)
            \(insertTurn) ('c_older', 1, 0, \(reference - 200));
            \(insertTurn) ('c_newer', 1, 0, \(reference - 30));
            """,
            at: databaseURL
        )

        let tasks = try GeminiDesktopSessionActivityDetector(
            databaseURLs: [databaseURL],
            maxChats: 1,
            now: { now }
        ).activeTasks()

        #expect(tasks.map(\.id) == [
            GeminiDesktopSessionActivityDetector.taskID(forChatUUID: "c_newer"),
        ])
    }
}

private let geminiDesktopSchema = """
    CREATE TABLE ZCHATMESSAGESTOREDMODEL (
        Z_PK INTEGER PRIMARY KEY AUTOINCREMENT, ZCHATUUID VARCHAR,
        ZISUSERTURN INTEGER, ZMESSAGEINDEX INTEGER, ZCREATEDTIME TIMESTAMP
    );
    """

private let insertTurn = """
    INSERT INTO ZCHATMESSAGESTOREDMODEL (ZCHATUUID, ZISUSERTURN, ZMESSAGEINDEX, ZCREATEDTIME) VALUES
    """

private func executeGeminiDesktopFixture(_ sql: String, at url: URL) throws {
    var database: OpaquePointer?
    guard sqlite3_open(url.path, &database) == SQLITE_OK, let database else {
        sqlite3_close(database)
        throw GeminiDesktopFixtureError.openFailed
    }
    defer { sqlite3_close(database) }
    var errorMessage: UnsafeMutablePointer<CChar>?
    guard sqlite3_exec(database, sql, nil, nil, &errorMessage) == SQLITE_OK else {
        let message = errorMessage.map { String(cString: $0) } ?? "unknown SQLite error"
        sqlite3_free(errorMessage)
        throw GeminiDesktopFixtureError.executionFailed(message)
    }
}

private enum GeminiDesktopFixtureError: Error {
    case openFailed
    case executionFailed(String)
}
