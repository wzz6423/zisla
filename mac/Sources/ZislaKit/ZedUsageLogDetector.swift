import Foundation
import SQLite3
import ZislaCore
import zstd

/// 从 Zed 的本地线程数据库提取累计 token 用量；解压后的会话数据不会被持久化或展示。
public final class ZedUsageLogDetector: AIUsageDetecting {
    public let databaseURL: URL
    public let maxThreads: Int

    private let fileManager: FileManager

    public init(
        databaseURL: URL? = nil,
        maxThreads: Int = .max,
        fileManager: FileManager = .default
    ) {
        self.databaseURL = databaseURL ?? ZedSessionActivityDetector.defaultDatabaseURL(
            home: fileManager.homeDirectoryForCurrentUser
        )
        self.maxThreads = min(max(1, maxThreads), Int(Int32.max))
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
            let message = sqliteMessage(database, fallback: AppLocalization.text("无法打开 Zed 线程数据库"))
            sqlite3_close(database)
            throw AIStateRepositoryError.storageFailure(message)
        }
        defer { sqlite3_close(database) }
        sqlite3_busy_timeout(database, 500)

        let sql = """
            SELECT id, updated_at, data_type, data
            FROM threads
            ORDER BY updated_at DESC
            LIMIT ?
            """
        var statement: OpaquePointer?
        let prepareResult = sqlite3_prepare_v2(database, sql, -1, &statement, nil)
        guard prepareResult == SQLITE_OK, let statement else {
            let message = sqliteMessage(database, fallback: AppLocalization.text("无法查询 Zed 用量"))
            sqlite3_finalize(statement)
            throw AIStateRepositoryError.storageFailure(message)
        }
        defer { sqlite3_finalize(statement) }

        guard sqlite3_bind_int(statement, 1, Int32(maxThreads)) == SQLITE_OK else {
            throw AIStateRepositoryError.storageFailure(
                sqliteMessage(database, fallback: AppLocalization.text("无法设置 Zed 用量查询范围"))
            )
        }

        var samples: [AIUsageSample] = []
        readRows: while true {
            switch sqlite3_step(statement) {
            case SQLITE_ROW:
                guard let threadID = stringColumn(statement, 0)?.trimmingCharacters(in: .whitespacesAndNewlines),
                      !threadID.isEmpty,
                      let updatedAtText = stringColumn(statement, 1),
                      let updatedAt = Self.parseDate(updatedAtText),
                      let dataType = stringColumn(statement, 2),
                      let data = dataColumn(statement, 3),
                      let usage = tokenUsage(in: data, dataType: dataType) else {
                    continue
                }
                let inputTokens = AIUsageTokenMath.adding(
                    AIUsageTokenMath.adding(
                        tokenCount(usage, key: "input_tokens"),
                        tokenCount(usage, key: "cache_creation_input_tokens")
                    ),
                    tokenCount(usage, key: "cache_read_input_tokens")
                )
                let outputTokens = tokenCount(usage, key: "output_tokens")
                guard AIUsageTokenMath.adding(inputTokens, outputTokens) > 0 else { continue }

                samples.append(AIUsageSample(
                    sourceID: ZedSessionActivityDetector.taskID(forThreadID: threadID),
                    provider: .zed,
                    timestamp: updatedAt,
                    inputTokens: inputTokens,
                    outputTokens: outputTokens
                ))
            case SQLITE_DONE:
                break readRows
            default:
                throw AIStateRepositoryError.storageFailure(
                    sqliteMessage(database, fallback: AppLocalization.text("无法读取 Zed 用量"))
                )
            }
        }

        return samples.sorted {
            if $0.timestamp != $1.timestamp { return $0.timestamp < $1.timestamp }
            return ($0.sourceID ?? "") < ($1.sourceID ?? "")
        }
    }

    private func tokenUsage(in data: Data, dataType: String) -> [String: Any]? {
        let jsonData: Data
        switch dataType.lowercased() {
        case "json":
            jsonData = data
        case "zstd":
            guard let decompressed = try? ZStd.decompress(data) else { return nil }
            jsonData = decompressed
        default:
            return nil
        }

        guard let root = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any] else {
            return nil
        }
        let thread = root["thread"] as? [String: Any] ?? root
        return thread["cumulative_token_usage"] as? [String: Any]
    }

    private func tokenCount(_ usage: [String: Any], key: String) -> Int {
        guard let number = usage[key] as? NSNumber,
              let value = UInt64(number.stringValue) else {
            return 0
        }
        return value > UInt64(Int.max) ? Int.max : Int(value)
    }

    private func dataColumn(_ statement: OpaquePointer?, _ index: Int32) -> Data? {
        guard sqlite3_column_type(statement, index) != SQLITE_NULL else { return nil }
        let byteCount = Int(sqlite3_column_bytes(statement, index))
        guard byteCount > 0, let bytes = sqlite3_column_blob(statement, index) else { return nil }
        return Data(bytes: bytes, count: byteCount)
    }

    private func stringColumn(_ statement: OpaquePointer?, _ index: Int32) -> String? {
        guard sqlite3_column_type(statement, index) != SQLITE_NULL,
              let value = sqlite3_column_text(statement, index) else {
            return nil
        }
        return String(cString: value)
    }

    private static func parseDate(_ value: String) -> Date? {
        if let date = try? Date.ISO8601FormatStyle(includingFractionalSeconds: true).parse(value) {
            return date
        }
        return try? Date.ISO8601FormatStyle().parse(value)
    }

    private func sqliteMessage(_ database: OpaquePointer?, fallback: String) -> String {
        guard let database, let message = sqlite3_errmsg(database) else { return fallback }
        return String(cString: message)
    }
}
