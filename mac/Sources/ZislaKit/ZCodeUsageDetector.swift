import Foundation
import SQLite3
import ZislaCore

/// Extracts token usage from ZCode's shared local SQLite state. Only token totals,
/// timestamps, and model identifiers are read; message content is not accessed.
public final class ZCodeUsageDetector: AIUsageDetecting {
    public let databaseURL: URL

    private let fileManager: FileManager

    public init(
        databaseURL: URL? = nil,
        fileManager: FileManager = .default
    ) {
        self.databaseURL = databaseURL ?? Self.defaultDatabaseURL(
            home: fileManager.homeDirectoryForCurrentUser
        )
        self.fileManager = fileManager
    }

    public func usageSamples() throws -> [AIUsageSample] {
        guard fileManager.fileExists(atPath: databaseURL.path) else { return [] }

        var database: OpaquePointer?
        let openResult = sqlite3_open_v2(
            databaseURL.path,
            &database,
            SQLITE_OPEN_READONLY | SQLITE_OPEN_NOMUTEX,
            nil
        )
        guard openResult == SQLITE_OK, let database else {
            let message = sqliteMessage(database, fallback: AppLocalization.text("无法打开 ZCode 数据库"))
            sqlite3_close(database)
            throw AIStateRepositoryError.storageFailure(message)
        }
        defer { sqlite3_close(database) }
        sqlite3_busy_timeout(database, 500)

        // `input_tokens` already includes cached prompt tokens (Anthropic-style cache
        // columns are separate but additive-inclusive), so they must not be added on top.
        let sql = """
            SELECT id, model_id, started_at, input_tokens, output_tokens
            FROM model_usage
            WHERE input_tokens > 0 OR output_tokens > 0
            ORDER BY started_at ASC, id ASC
            """

        var statement: OpaquePointer?
        let prepareResult = sqlite3_prepare_v2(database, sql, -1, &statement, nil)
        guard prepareResult == SQLITE_OK, let statement else {
            let message = sqliteMessage(database, fallback: AppLocalization.text("无法查询 ZCode 用量"))
            sqlite3_finalize(statement)
            throw AIStateRepositoryError.storageFailure(message)
        }
        defer { sqlite3_finalize(statement) }

        var samples: [AIUsageSample] = []
        readRows: while true {
            switch sqlite3_step(statement) {
            case SQLITE_ROW:
                guard let requestID = stringColumn(statement, 0),
                      let model = stringColumn(statement, 1),
                      let startedAtMilliseconds = optionalInt64Column(statement, 2),
                      let inputTokens = optionalInt64Column(statement, 3),
                      let outputTokens = optionalInt64Column(statement, 4) else {
                    continue
                }
                samples.append(AIUsageSample(
                    sourceID: Self.sourceID(forRequestID: requestID),
                    provider: .zcode,
                    timestamp: Date(timeIntervalSince1970: Double(startedAtMilliseconds) / 1_000),
                    inputTokens: Int(inputTokens),
                    outputTokens: Int(outputTokens),
                    model: model
                ))
            case SQLITE_DONE:
                break readRows
            default:
                throw AIStateRepositoryError.storageFailure(
                    sqliteMessage(database, fallback: AppLocalization.text("无法读取 ZCode 用量"))
                )
            }
        }

        return samples
    }

    public static func sourceID(forRequestID requestID: String) -> String {
        "zcode-usage-\(requestID)"
    }

    public static func defaultDatabaseURL(
        home: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> URL {
        home.appendingPathComponent(".zcode/cli/db/db.sqlite", isDirectory: false)
    }

    private func stringColumn(_ statement: OpaquePointer?, _ index: Int32) -> String? {
        guard sqlite3_column_type(statement, index) != SQLITE_NULL,
              let value = sqlite3_column_text(statement, index) else {
            return nil
        }
        return String(cString: value)
    }

    private func optionalInt64Column(_ statement: OpaquePointer?, _ index: Int32) -> Int64? {
        guard sqlite3_column_type(statement, index) != SQLITE_NULL else { return nil }
        return sqlite3_column_int64(statement, index)
    }

    private func sqliteMessage(_ database: OpaquePointer?, fallback: String) -> String {
        guard let database, let message = sqlite3_errmsg(database) else { return fallback }
        return String(cString: message)
    }
}
