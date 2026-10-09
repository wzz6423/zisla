import CryptoKit
import Foundation
import SQLite3

/// Best-effort, read-only access to third-party metadata. Never migrates or creates their stores.
enum DesktopAIStorage {
    static func rows(at url: URL, sql: String, limit: Int = 10_000) -> [[String: Any]] {
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }
        var database: OpaquePointer?
        guard sqlite3_open_v2(url.path, &database, SQLITE_OPEN_READONLY | SQLITE_OPEN_NOMUTEX, nil) == SQLITE_OK,
              let database else {
            sqlite3_close(database)
            return []
        }
        defer { sqlite3_close(database) }
        sqlite3_busy_timeout(database, 500)
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            sqlite3_finalize(statement)
            return []
        }
        defer { sqlite3_finalize(statement) }
        var rows: [[String: Any]] = []
        while rows.count < limit {
            let result = sqlite3_step(statement)
            if result == SQLITE_DONE { return rows }
            guard result == SQLITE_ROW else { return [] }
            var row: [String: Any] = [:]
            for index in 0..<sqlite3_column_count(statement) {
                let key = String(cString: sqlite3_column_name(statement, index))
                switch sqlite3_column_type(statement, index) {
                case SQLITE_INTEGER: row[key] = sqlite3_column_int64(statement, index)
                case SQLITE_FLOAT: row[key] = sqlite3_column_double(statement, index)
                case SQLITE_TEXT:
                    if let text = sqlite3_column_text(statement, index) { row[key] = String(cString: text) }
                default: break
                }
            }
            rows.append(row)
        }
        return rows
    }

    static func json(at url: URL, maximumBytes: Int = 16 * 1_024 * 1_024) -> [String: Any]? {
        guard let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize,
              size <= maximumBytes,
              let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    }

    static func milliseconds(_ value: Any?) -> Date? {
        guard let number = value as? NSNumber, number.doubleValue.isFinite, number.doubleValue > 0 else { return nil }
        return Date(timeIntervalSince1970: number.doubleValue / 1_000)
    }

    static func tokenCount(_ value: Any?) -> Int {
        guard let number = value as? NSNumber else { return 0 }
        let value = number.doubleValue
        guard value.isFinite, value > 0 else { return 0 }
        return value >= Double(Int.max) ? Int.max : Int(value)
    }

    static func identity(_ components: [String]) -> String {
        // Length prefixes prevent delimiter collisions in model, account and session identifiers.
        let value = components.map { "\($0.utf8.count):\($0)" }.joined()
        return SHA256.hash(data: Data(value.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}
