import Foundation
import Security
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

public final class KeychainAIAgentSecretStore: AIAgentSecretStoring, @unchecked Sendable {
    private let service: String
    private let lock = NSLock()

    public init(service: String = "com.zisla.ai-agent.secrets") {
        self.service = service
    }

    public func secret(for reference: String) throws -> String? {
        let reference = try normalizedReference(reference)
        return try lock.withLock {
            let query: [CFString: Any] = [
                kSecClass: kSecClassGenericPassword,
                kSecAttrService: service,
                kSecAttrAccount: reference,
                kSecMatchLimit: kSecMatchLimitOne,
                kSecReturnData: true,
            ]
            var result: CFTypeRef?
            let status = SecItemCopyMatching(query as CFDictionary, &result)
            if status == errSecItemNotFound { return nil }
            try check(status, operation: "读取")
            guard let data = result as? Data, let secret = String(data: data, encoding: .utf8) else {
                throw AIAgentSecretStoreError.storageFailed("钥匙串中的私有数据格式无效")
            }
            return secret
        }
    }

    public func setSecret(_ secret: String, for reference: String) throws {
        let reference = try normalizedReference(reference)
        guard !secret.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw AIAgentSecretStoreError.invalidSecret
        }
        let data = Data(secret.utf8)
        try lock.withLock {
            let query: [CFString: Any] = [
                kSecClass: kSecClassGenericPassword,
                kSecAttrService: service,
                kSecAttrAccount: reference,
            ]
            let status = SecItemUpdate(
                query as CFDictionary,
                [kSecValueData: data] as CFDictionary
            )
            if status == errSecItemNotFound {
                var item = query
                item[kSecValueData] = data
                item[kSecAttrAccessible] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
                try check(SecItemAdd(item as CFDictionary, nil), operation: "保存")
            } else {
                try check(status, operation: "更新")
            }
        }
    }

    public func removeSecret(for reference: String) throws {
        let reference = try normalizedReference(reference)
        try lock.withLock {
            let query: [CFString: Any] = [
                kSecClass: kSecClassGenericPassword,
                kSecAttrService: service,
                kSecAttrAccount: reference,
            ]
            let status = SecItemDelete(query as CFDictionary)
            if status != errSecItemNotFound { try check(status, operation: "删除") }
        }
    }

    private func normalizedReference(_ raw: String) throws -> String {
        let reference = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !reference.isEmpty else { throw AIAgentSecretStoreError.invalidReference }
        return reference
    }

    private func check(_ status: OSStatus, operation: String) throws {
        guard status == errSecSuccess else {
            let detail = SecCopyErrorMessageString(status, nil) as String? ?? "OSStatus \(status)"
            throw AIAgentSecretStoreError.storageFailed("钥匙串\(operation)失败：\(detail)")
        }
    }
}

final class MigratingAIAgentSecretStore: AIAgentSecretStoring, @unchecked Sendable {
    private let primary: AIAgentSecretStoring
    private let legacy: AIAgentSecretStoring
    private let lock = NSLock()
    private var usesLegacyStore = true

    init(primary: AIAgentSecretStoring, legacy: AIAgentSecretStoring) {
        self.primary = primary
        self.legacy = legacy
        migrateAllLegacySecretsIfPossible()
    }

    func secret(for reference: String) throws -> String? {
        try lock.withLock {
            guard usesLegacyStore else { return try primary.secret(for: reference) }
            if let secret = try primary.secret(for: reference) {
                try legacy.removeSecret(for: reference)
                return secret
            }
            guard let secret = try legacy.secret(for: reference) else { return nil }
            try primary.setSecret(secret, for: reference)
            try legacy.removeSecret(for: reference)
            return secret
        }
    }

    func setSecret(_ secret: String, for reference: String) throws {
        try lock.withLock {
            try primary.setSecret(secret, for: reference)
            if usesLegacyStore {
                try legacy.removeSecret(for: reference)
            }
        }
    }

    func removeSecret(for reference: String) throws {
        try lock.withLock {
            var firstError: Error?
            do { try primary.removeSecret(for: reference) } catch { firstError = error }
            if usesLegacyStore {
                do { try legacy.removeSecret(for: reference) } catch {
                    if firstError == nil { firstError = error }
                }
            }
            if let firstError { throw firstError }
        }
    }

    private func migrateAllLegacySecretsIfPossible() {
        guard let database = legacy as? DatabaseAIAgentSecretStore else { return }
        do {
            for entry in try database.allSecrets() where try primary.secret(for: entry.reference) == nil {
                try primary.setSecret(entry.secret, for: entry.reference)
            }
            try database.removeStorage()
            usesLegacyStore = false
        } catch {
            // Keep the old store so a later read by reference can retry the migration.
        }
    }
}

enum AIAgentSecretStoreFactory {
    static func makeDefault() -> AIAgentSecretStoring {
        let keychain = KeychainAIAgentSecretStore()
        guard FileManager.default.fileExists(atPath: AppPaths.aiAgentSecrets.path) else {
            return keychain
        }
        return MigratingAIAgentSecretStore(
            primary: keychain,
            legacy: DatabaseAIAgentSecretStore()
        )
    }
}

/// Legacy storage retained only to migrate existing installations and for explicit compatibility use.
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

    func allSecrets() throws -> [(reference: String, secret: String)] {
        try withDatabase { database in
            let statement = try prepare(
                "SELECT reference, value FROM ai_agent_secrets ORDER BY reference",
                database: database
            )
            defer { sqlite3_finalize(statement) }
            var result: [(reference: String, secret: String)] = []
            while sqlite3_step(statement) == SQLITE_ROW {
                guard let reference = textColumn(statement, index: 0),
                      let secret = textColumn(statement, index: 1) else {
                    throw AIAgentSecretStoreError.storageFailed("旧凭据数据库包含无效记录")
                }
                result.append((reference, secret))
            }
            guard sqlite3_errcode(database) == SQLITE_OK
                    || sqlite3_errcode(database) == SQLITE_DONE else {
                throw databaseError(database, fallback: "无法读取旧凭据数据库")
            }
            return result
        }
    }

    func removeStorage() throws {
        try queue.sync {
            let manager = FileManager.default
            for url in [
                URL(fileURLWithPath: storageURL.path + "-journal"),
                URL(fileURLWithPath: storageURL.path + "-shm"),
                URL(fileURLWithPath: storageURL.path + "-wal"),
                storageURL,
            ] where manager.fileExists(atPath: url.path) {
                try manager.removeItem(at: url)
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
