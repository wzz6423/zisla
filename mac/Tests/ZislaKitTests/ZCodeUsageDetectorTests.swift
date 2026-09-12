import Foundation
import SQLite3
import Testing
@testable import ZislaCore
@testable import ZislaKit

struct ZCodeUsageDetectorTests {
    @Test
    func parsesTokenUsageFromModelUsageRows() throws {
        let databaseURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("Zisla-zcode-usage-\(UUID().uuidString).sqlite")
        defer { try? FileManager.default.removeItem(at: databaseURL) }
        let reference = Date(timeIntervalSince1970: 2_000_000_000)
        let referenceMilliseconds = Int64(reference.timeIntervalSince1970 * 1_000)
        try execute(
            """
            CREATE TABLE model_usage (
                id TEXT PRIMARY KEY, session_id TEXT NOT NULL, turn_id TEXT,
                model_id TEXT NOT NULL, started_at INTEGER NOT NULL,
                input_tokens INTEGER NOT NULL DEFAULT 0, output_tokens INTEGER NOT NULL DEFAULT 0,
                cache_creation_input_tokens INTEGER NOT NULL DEFAULT 0,
                cache_read_input_tokens INTEGER NOT NULL DEFAULT 0
            );
            -- Real ZCode rows report cached prompt tokens inside input_tokens:
            -- computed_total_tokens == input_tokens + output_tokens.
            INSERT INTO model_usage VALUES (
                'req-2', 'sess-1', 'turn-1', 'GLM-5.3-Flash', \(referenceMilliseconds - 1_000),
                152662, 840, 0, 151040
            );
            INSERT INTO model_usage VALUES (
                'req-1', 'sess-1', 'turn-1', 'GLM-4.6', \(referenceMilliseconds - 5_000),
                1200, 300, 0, 0
            );
            INSERT INTO model_usage VALUES (
                'req-3', 'sess-1', 'turn-1', 'GLM-5.3-Flash', \(referenceMilliseconds - 100),
                0, 0, 0, 0
            );
            """,
            at: databaseURL
        )

        let samples = try ZCodeUsageDetector(
            databaseURL: databaseURL
        ).usageSamples()

        #expect(samples.count == 2)
        #expect(samples[0].sourceID == "zcode-usage-req-1")
        #expect(samples[0].provider == .zcode)
        #expect(samples[0].timestamp == Date(timeIntervalSince1970: Double(referenceMilliseconds - 5_000) / 1_000))
        #expect(samples[0].inputTokens == 1200)
        #expect(samples[0].outputTokens == 300)
        #expect(samples[0].model == "GLM-4.6")
        #expect(samples[1].sourceID == "zcode-usage-req-2")
        // The cache-read total must not be added on top of the already-inclusive input count.
        #expect(samples[1].inputTokens == 152662)
        #expect(samples[1].outputTokens == 840)
    }

    @Test
    func returnsEmptyWhenDatabaseIsMissing() throws {
        let home = URL(fileURLWithPath: "/Users/tester", isDirectory: true)
        #expect(try ZCodeUsageDetector(
            databaseURL: ZCodeUsageDetector.defaultDatabaseURL(home: home)
        ).usageSamples().isEmpty)
    }

    @Test
    func reportsSchemaErrorsInsteadOfTreatingDatabaseAsIdle() throws {
        let databaseURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("Zisla-zcode-usage-empty-\(UUID().uuidString).sqlite")
        defer { try? FileManager.default.removeItem(at: databaseURL) }
        try execute("", at: databaseURL)

        #expect(throws: AIStateRepositoryError.self) {
            try ZCodeUsageDetector(databaseURL: databaseURL).usageSamples()
        }
    }

    @Test @MainActor
    func defaultUsageDetectorsIncludeZCodeModelUsage() {
        #expect(AIStateMonitor.defaultUsageDetectors().contains {
            $0 is ZCodeUsageDetector
        })
    }
}

private func execute(_ sql: String, at url: URL) throws {
    var database: OpaquePointer?
    guard sqlite3_open(url.path, &database) == SQLITE_OK, let database else {
        sqlite3_close(database)
        throw ZCodeUsageFixtureError.openFailed
    }
    defer { sqlite3_close(database) }
    var errorMessage: UnsafeMutablePointer<CChar>?
    guard sqlite3_exec(database, sql, nil, nil, &errorMessage) == SQLITE_OK else {
        let message = errorMessage.map { String(cString: $0) } ?? "unknown SQLite error"
        sqlite3_free(errorMessage)
        throw ZCodeUsageFixtureError.executionFailed(message)
    }
}

private enum ZCodeUsageFixtureError: Error {
    case openFailed
    case executionFailed(String)
}
