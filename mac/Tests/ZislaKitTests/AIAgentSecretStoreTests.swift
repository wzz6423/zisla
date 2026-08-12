import Foundation
import Testing
@testable import ZislaKit

struct AIAgentSecretStoreTests {
    @Test
    func migratingStoreMovesEveryLegacyDatabaseValueAndRemovesTheOldDatabase() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("zisla-agent-secret-migration-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let databaseURL = directory.appendingPathComponent("legacy.sqlite")
        let primary = MemorySecretStore(values: ["current": "keychain-secret"])
        let legacy = DatabaseAIAgentSecretStore(storageURL: databaseURL)
        try legacy.setSecret("stale-secret", for: "current")
        try legacy.setSecret("orphaned-secret", for: "orphaned")

        let store = MigratingAIAgentSecretStore(primary: primary, legacy: legacy)

        #expect(try store.secret(for: "current") == "keychain-secret")
        #expect(try primary.secret(for: "orphaned") == "orphaned-secret")
        #expect(!FileManager.default.fileExists(atPath: databaseURL.path))

        try store.setSecret("new-secret", for: "new")
        #expect(!FileManager.default.fileExists(atPath: databaseURL.path))
    }

    @Test
    func completeMigrationDoesNotRetryOrDeleteLegacyDatabaseWhenPrimaryWriteFails() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("zisla-agent-secret-failed-migration-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let databaseURL = directory.appendingPathComponent("legacy.sqlite")
        let primary = MemorySecretStore(setError: TestSecretError.writeFailed)
        let legacy = DatabaseAIAgentSecretStore(storageURL: databaseURL)
        try legacy.setSecret("legacy-secret", for: "account")

        _ = MigratingAIAgentSecretStore(primary: primary, legacy: legacy)

        #expect(primary.setAttemptCount == 1)
        #expect(FileManager.default.fileExists(atPath: databaseURL.path))
        #expect(try legacy.secret(for: "account") == "legacy-secret")
    }

    @Test
    func databaseStoreRemovalDeletesSQLiteAndEverySidecar() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("zisla-agent-secret-cleanup-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let databaseURL = directory.appendingPathComponent("legacy.sqlite")
        let store = DatabaseAIAgentSecretStore(storageURL: databaseURL)
        try store.setSecret("legacy-secret", for: "account")
        let sidecars = ["-wal", "-shm", "-journal"].map {
            URL(fileURLWithPath: databaseURL.path + $0)
        }
        for url in sidecars {
            try Data("legacy-sidecar".utf8).write(to: url)
        }

        try store.removeStorage()

        #expect(!FileManager.default.fileExists(atPath: databaseURL.path))
        #expect(sidecars.allSatisfy { !FileManager.default.fileExists(atPath: $0.path) })
    }

    @Test
    func migratingStoreMovesLegacyValueOnlyAfterThePrimaryWriteSucceeds() throws {
        let primary = MemorySecretStore()
        let legacy = MemorySecretStore(values: ["account": "legacy-secret"])
        let store = MigratingAIAgentSecretStore(primary: primary, legacy: legacy)

        #expect(try store.secret(for: "account") == "legacy-secret")
        #expect(try primary.secret(for: "account") == "legacy-secret")
        #expect(try legacy.secret(for: "account") == nil)
    }

    @Test
    func migratingStoreRemovesLegacyCopyWhenPrimaryAlreadyHasTheValue() throws {
        let primary = MemorySecretStore(values: ["account": "keychain-secret"])
        let legacy = MemorySecretStore(values: ["account": "legacy-secret"])
        let store = MigratingAIAgentSecretStore(primary: primary, legacy: legacy)

        #expect(try store.secret(for: "account") == "keychain-secret")
        #expect(try legacy.secret(for: "account") == nil)
    }

    @Test
    func migratingStorePreservesLegacyValueWhenThePrimaryWriteFails() {
        let primary = MemorySecretStore(setError: TestSecretError.writeFailed)
        let legacy = MemorySecretStore(values: ["account": "legacy-secret"])
        let store = MigratingAIAgentSecretStore(primary: primary, legacy: legacy)

        #expect(throws: TestSecretError.writeFailed) {
            try store.secret(for: "account")
        }
        #expect((try? legacy.secret(for: "account")) == "legacy-secret")
    }

    @Test
    func migratingStoreRemovesStaleLegacyValuesOnSetAndDelete() throws {
        let primary = MemorySecretStore()
        let legacy = MemorySecretStore(values: ["account": "stale-secret"])
        let store = MigratingAIAgentSecretStore(primary: primary, legacy: legacy)

        try store.setSecret("new-secret", for: "account")

        #expect(try primary.secret(for: "account") == "new-secret")
        #expect(try legacy.secret(for: "account") == nil)

        try legacy.setSecret("stale-again", for: "account")
        try store.removeSecret(for: "account")

        #expect(try primary.secret(for: "account") == nil)
        #expect(try legacy.secret(for: "account") == nil)
    }
}

private enum TestSecretError: Error {
    case writeFailed
}

private final class MemorySecretStore: AIAgentSecretStoring, @unchecked Sendable {
    private let lock = NSLock()
    private var values: [String: String]
    private var setAttempts = 0
    private let setError: Error?

    init(values: [String: String] = [:], setError: Error? = nil) {
        self.values = values
        self.setError = setError
    }

    func secret(for reference: String) throws -> String? {
        lock.lock()
        defer { lock.unlock() }
        return values[reference]
    }

    func setSecret(_ secret: String, for reference: String) throws {
        lock.lock()
        defer { lock.unlock() }
        setAttempts += 1
        if let setError { throw setError }
        values[reference] = secret
    }

    var setAttemptCount: Int {
        lock.withLock { setAttempts }
    }

    func removeSecret(for reference: String) throws {
        lock.lock()
        defer { lock.unlock() }
        values.removeValue(forKey: reference)
    }
}
