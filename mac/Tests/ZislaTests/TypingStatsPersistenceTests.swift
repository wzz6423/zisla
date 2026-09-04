import AppKit
import Foundation
import SQLite3
import Testing
import ZislaCore

@testable import KeyboardKit
@testable import Zisla

/// Typing statistics used to accumulate entirely inside the `-wal` sidecar: a cached `SELECT`
/// statement was left parked on `SQLITE_ROW`, so its read transaction blocked every checkpoint for
/// the whole process lifetime.
struct TypingStatsPersistenceTests {
    private static func makeBatch(now: Date) -> TypingStatsWriteBatch {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "en_US_POSIX")
        calendar.timeZone = .autoupdatingCurrent
        let localDate = TypingStatsStore.dateKey(for: now, calendar: calendar)
        let application = TypingApplicationIdentity(
            processKey: "com.example.editor",
            displayName: "Editor",
            processName: "Editor",
            bundleIdentifier: "com.example.editor"
        )
        return TypingStatsWriteBatch(
            characterAggregates: [
                TypingCharacterAggregate(
                    secondStart: Int64(now.timeIntervalSince1970),
                    localDate: localDate,
                    application: application,
                    count: 7
                )
            ],
            keyAggregates: [
                TypingKeyAggregate(localDate: localDate, keyCode: 0, count: 7)
            ]
        )
    }

    @Test
    func writesAreCheckpointableWhileTheStoreStaysOpen() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let databaseURL = directory.appendingPathComponent("typing-stats.sqlite3")

        let now = Date()
        let store = TypingStatsStore(databaseURL: databaseURL, nowProvider: { now })
        // The second write is the one that used to leak: the application id is cached by then, so
        // the parked SELECT would never be borrowed — and therefore never reset — again.
        try await store.record(Self.makeBatch(now: now))
        try await store.record(Self.makeBatch(now: now.addingTimeInterval(1)))

        var handle: OpaquePointer?
        #expect(sqlite3_open_v2(databaseURL.path, &handle, SQLITE_OPEN_READWRITE, nil) == SQLITE_OK)
        defer { sqlite3_close_v2(handle) }
        // A freshly opened connection has not attached the WAL yet, and sqlite3_wal_checkpoint_v2
        // silently no-ops in that state. One read forces the pager to open it.
        #expect(sqlite3_exec(handle, "SELECT count(*) FROM sqlite_master;", nil, nil, nil) == SQLITE_OK)

        var walFrames: Int32 = 0
        var checkpointedFrames: Int32 = 0
        let result = sqlite3_wal_checkpoint_v2(
            handle,
            nil,
            SQLITE_CHECKPOINT_PASSIVE,
            &walFrames,
            &checkpointedFrames
        )
        // A leaked read transaction turns this into SQLITE_LOCKED and leaves the WAL untouched.
        #expect(result == SQLITE_OK)
        #expect(walFrames > 0)
        #expect(checkpointedFrames == walFrames)
    }

    @Test
    func reopeningTheStoreSeesEarlierWrites() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let databaseURL = directory.appendingPathComponent("typing-stats.sqlite3")

        let now = Date()
        let writer = TypingStatsStore(databaseURL: databaseURL, nowProvider: { now })
        try await writer.record(Self.makeBatch(now: now))

        let reader = TypingStatsStore(databaseURL: databaseURL, nowProvider: { now })
        let snapshot = try await reader.loadSnapshot(timelineRange: .oneHour)
        #expect(snapshot.today.characterCount == 7)
    }

    /// Keyboard data has to follow the same debug/release split as the rest of the app, otherwise a
    /// debug build and a shipped build silently share one database.
    @Test
    func keyboardDataLivesInTheSharedApplicationSupportDirectory() {
        let databaseURL = TypingStatsStore.defaultDatabaseURL()
        #expect(databaseURL.deletingLastPathComponent() == LegacyAppDataMigration.applicationSupport)
        #expect(!databaseURL.path.contains("SimuBoard"))
    }

    /// `stop()` can only fire the final flush into a detached task, so the terminate handshake is
    /// the only thing that keeps the last buffered keystrokes.
    @Test
    func appDelegateHandlesTerminationForTypingStats() {
        #expect(
            AppDelegate.instancesRespond(
                to: #selector(NSApplicationDelegate.applicationShouldTerminate(_:))
            )
        )
    }
}
