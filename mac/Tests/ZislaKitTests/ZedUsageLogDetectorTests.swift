import Foundation
import SQLite3
import Testing
@testable import ZislaCore
@testable import ZislaKit

struct ZedUsageLogDetectorTests {
    @Test
    func readsJSONAndZstdCumulativeUsageWithoutCountingRequestBreakdown() throws {
        let databaseURL = temporaryDatabaseURL("usage")
        defer { try? FileManager.default.removeItem(at: databaseURL) }
        try execute(
            """
            CREATE TABLE threads (
                id TEXT PRIMARY KEY,
                summary TEXT NOT NULL,
                updated_at TEXT NOT NULL,
                data_type TEXT NOT NULL,
                data BLOB NOT NULL
            );
            INSERT INTO threads VALUES (
                'json-thread', 'private summary', '2033-05-17T03:28:20.000000+00:00', 'json',
                CAST('{"thread":{"cumulative_token_usage":{"input_tokens":17,"output_tokens":6},"request_token_usage":{"request":{"input_tokens":900,"output_tokens":100}}}}' AS BLOB)
            );
            INSERT INTO threads VALUES (
                'zstd-thread', 'private summary', '2033-05-18T03:28:20.000000+00:00', 'zstd',
                X'28b52ffd0458a5020082441016a0b901a32d99655cebcca748a1aaa9d37e80a7aa0f01ade1e09fcea04028ab20516a57569b6cacee1944e0dcf257501f3bc785ae4fc447f2e4a55d914f7e8f050500537106a84e44157751b205b1f9045b461f45'
            );
            """,
            at: databaseURL
        )

        let samples = try ZedUsageLogDetector(databaseURL: databaseURL).usageSamples()

        #expect(samples.map(\.sourceID) == ["zed-thread-json-thread", "zed-thread-zstd-thread"])
        #expect(samples.map(\.provider) == [.zed, .zed])
        #expect(samples.map(\.inputTokens) == [17, 150])
        #expect(samples.map(\.outputTokens) == [6, 40])
    }

    @Test
    func skipsMissingUsageAndMalformedCompressedThreads() throws {
        let databaseURL = temporaryDatabaseURL("invalid")
        defer { try? FileManager.default.removeItem(at: databaseURL) }
        try execute(
            """
            CREATE TABLE threads (
                id TEXT PRIMARY KEY,
                summary TEXT NOT NULL,
                updated_at TEXT NOT NULL,
                data_type TEXT NOT NULL,
                data BLOB NOT NULL
            );
            INSERT INTO threads VALUES (
                'empty-thread', 'private summary', '2033-05-18T03:28:20.000000+00:00', 'json',
                CAST('{"thread":{"messages":[]}}' AS BLOB)
            );
            INSERT INTO threads VALUES (
                'broken-thread', 'private summary', '2033-05-18T03:29:20.000000+00:00', 'zstd', X'28B52FFD'
            );
            """,
            at: databaseURL
        )

        #expect(try ZedUsageLogDetector(databaseURL: databaseURL).usageSamples().isEmpty)
    }

    @Test
    func usesSharedDefaultPathAndClampsThreadLimit() throws {
        let home = URL(fileURLWithPath: "/Users/tester", isDirectory: true)
        let databaseURL = ZedSessionActivityDetector.defaultDatabaseURL(home: home)

        #expect(databaseURL.path == "/Users/tester/Library/Application Support/Zed/threads/threads.db")
        #expect(try ZedUsageLogDetector(databaseURL: databaseURL).usageSamples().isEmpty)
        #expect(ZedUsageLogDetector(maxThreads: 0).maxThreads == 1)
        #expect(ZedUsageLogDetector(maxThreads: .max).maxThreads == Int(Int32.max))
    }
}

private func temporaryDatabaseURL(_ name: String) -> URL {
    FileManager.default.temporaryDirectory
        .appendingPathComponent("Zisla-zed-usage-\(name)-\(UUID().uuidString).sqlite")
}

private func execute(_ sql: String, at url: URL) throws {
    var database: OpaquePointer?
    guard sqlite3_open(url.path, &database) == SQLITE_OK, let database else {
        sqlite3_close(database)
        throw ZedUsageFixtureError.openFailed
    }
    defer { sqlite3_close(database) }
    var errorMessage: UnsafeMutablePointer<CChar>?
    guard sqlite3_exec(database, sql, nil, nil, &errorMessage) == SQLITE_OK else {
        let message = errorMessage.map { String(cString: $0) } ?? "unknown SQLite error"
        sqlite3_free(errorMessage)
        throw ZedUsageFixtureError.executionFailed(message)
    }
}

private enum ZedUsageFixtureError: Error {
    case openFailed
    case executionFailed(String)
}
