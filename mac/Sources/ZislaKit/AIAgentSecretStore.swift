import Foundation
import SQLite3

public protocol AIAgentSecretStoring: Sendable {
    func secret(for reference: String) throws -> String?
    func setSecret(_ secret: String, for reference: String) throws
    func removeSecret(for reference: String) throws
}

public enum AIAgentSecretStoreError: LocalizedError, Sendable {
    case invalidReference
    case invalidSecret
    case storageFailed(String)

    public var errorDescription: String? {
        switch self {
        case .invalidReference: "密钥引用无效"
        case .invalidSecret: "API Key 不能为空"
        case let .storageFailed(detail): "无法保存 AI Agent 私有数据：\(detail)"
        }
    }
}

private let aiAgentSQLiteTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

/// Sensitive AI Agent data is stored in the app's own SQLite database, without relying on the system keychain.
public final class DatabaseAIAgentSecretStore: AIAgentSecretStoring, @unchecked Sendable {
    private let storageURL: URL
    private let queue = DispatchQueue(label: "com.zisla.ai-agent.secrets", qos: .utility)

    public init(storageURL: URL = AppPaths.aiAgentSecrets) {
        self.storageURL = storageURL
    }

    public func secret(for reference: String) throws -> String? {
        let reference = try normalizedReference(reference)
        return try withDatabase { database in
            let statement = try prepare(
                "SELECT value FROM ai_agent_secrets WHERE reference = ? LIMIT 1",
                database: database
            )
            defer { sqlite3_finalize(statement) }
            try bind(reference, to: statement, index: 1, database: database)
            switch sqlite3_step(statement) {
            case SQLITE_ROW:
                return textColumn(statement, index: 0)
            case SQLITE_DONE:
                return nil
            default:
                throw databaseError(database, fallback: "无法读取 AI Agent 私有数据")
            }
        }
    }

    public func setSecret(_ secret: String, for reference: String) throws {
        let reference = try normalizedReference(reference)
        guard !secret.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw AIAgentSecretStoreError.invalidSecret
        }
        try withDatabase { database in
            let statement = try prepare(
                """
                INSERT INTO ai_agent_secrets (reference, value) VALUES (?, ?)
                ON CONFLICT(reference) DO UPDATE SET value = excluded.value
                """,
                database: database
            )
            defer { sqlite3_finalize(statement) }
            try bind(reference, to: statement, index: 1, database: database)
            try bind(secret, to: statement, index: 2, database: database)
            guard sqlite3_step(statement) == SQLITE_DONE else {
                throw databaseError(database, fallback: "无法保存 AI Agent 私有数据")
            }
        }
    }

    public func removeSecret(for reference: String) throws {
        let reference = try normalizedReference(reference)
        try withDatabase { database in
            let statement = try prepare(
                "DELETE FROM ai_agent_secrets WHERE reference = ?",
                database: database
            )
            defer { sqlite3_finalize(statement) }
            try bind(reference, to: statement, index: 1, database: database)
            guard sqlite3_step(statement) == SQLITE_DONE else {
                throw databaseError(database, fallback: "无法删除 AI Agent 私有数据")
            }
        }
    }

    private func normalizedReference(_ raw: String) throws -> String {
        let reference = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !reference.isEmpty else { throw AIAgentSecretStoreError.invalidReference }
        return reference
    }

    private func withDatabase<T>(_ body: (OpaquePointer) throws -> T) throws -> T {
        try queue.sync {
            let manager = FileManager.default
            do {
                try manager.createDirectory(
                    at: storageURL.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )
                var database: OpaquePointer?
                let opened = sqlite3_open_v2(
                    storageURL.path,
                    &database,
                    SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX,
                    nil
                )
                guard opened == SQLITE_OK, let database else {
                    sqlite3_close(database)
                    throw AIAgentSecretStoreError.storageFailed("无法打开私有 SQLite 数据库")
                }
                defer { sqlite3_close_v2(database) }
                guard sqlite3_busy_timeout(database, 1_000) == SQLITE_OK else {
                    throw databaseError(database, fallback: "无法配置私有 SQLite 数据库")
                }
                try execute(
                    """
                    CREATE TABLE IF NOT EXISTS ai_agent_secrets (
                        reference TEXT PRIMARY KEY NOT NULL,
                        value TEXT NOT NULL
                    )
                    """,
                    database: database
                )
                try manager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: storageURL.path)
                return try body(database)
            } catch let error as AIAgentSecretStoreError {
                throw error
            } catch {
                throw AIAgentSecretStoreError.storageFailed(error.localizedDescription)
            }
        }
    }

    private func prepare(_ sql: String, database: OpaquePointer) throws -> OpaquePointer {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK,
              let statement else {
            sqlite3_finalize(statement)
            throw databaseError(database, fallback: "无法准备私有 SQLite 操作")
        }
        return statement
    }

    private func bind(_ value: String, to statement: OpaquePointer, index: Int32, database: OpaquePointer) throws {
        let result = value.withCString {
            sqlite3_bind_text(statement, index, $0, -1, aiAgentSQLiteTransient)
        }
        guard result == SQLITE_OK else {
            throw databaseError(database, fallback: "无法写入私有 SQLite 数据")
        }
    }

    private func textColumn(_ statement: OpaquePointer, index: Int32) -> String? {
        guard sqlite3_column_type(statement, index) != SQLITE_NULL,
              let text = sqlite3_column_text(statement, index) else {
            return nil
        }
        return String(cString: text)
    }

    private func execute(_ sql: String, database: OpaquePointer) throws {
        var errorMessage: UnsafeMutablePointer<CChar>?
        let result = sqlite3_exec(database, sql, nil, nil, &errorMessage)
        defer { sqlite3_free(errorMessage) }
        guard result == SQLITE_OK else {
            let detail = errorMessage.map { String(cString: $0) } ?? "私有 SQLite 操作失败"
            throw AIAgentSecretStoreError.storageFailed(detail)
        }
    }

    private func databaseError(_ database: OpaquePointer, fallback: String) -> AIAgentSecretStoreError {
        let detail = sqlite3_errmsg(database).map { String(cString: $0) } ?? fallback
        return .storageFailed(detail)
    }
}
