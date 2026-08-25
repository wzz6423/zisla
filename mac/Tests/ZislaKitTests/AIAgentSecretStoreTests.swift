import Foundation
import Testing
@testable import ZislaKit

struct AIAgentSecretStoreTests {
    @Test
    func defaultFactoryUsesDatabaseStore() {
        #expect(AIAgentSecretStoreFactory.makeDefault() is DatabaseAIAgentSecretStore)
    }

    @Test
    func databaseStorePersistsUpdatesAndDeletesValues() throws {
        let directory = try makeDirectory(named: "zisla-agent-secret-database")
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = DatabaseAIAgentSecretStore(storageURL: directory.appendingPathComponent("secrets.sqlite"))

        #expect(try store.secret(for: "account") == nil)
        try store.setSecret("first-secret", for: "account")
        #expect(try store.secret(for: "account") == "first-secret")

        try store.setSecret("updated-secret", for: "account")
        #expect(try store.secret(for: "account") == "updated-secret")

        try store.removeSecret(for: "account")
        #expect(try store.secret(for: "account") == nil)
    }

    @Test
    func databaseStoreCreatesA0600DatabaseFile() throws {
        let directory = try makeDirectory(named: "zisla-agent-secret-permissions")
        defer { try? FileManager.default.removeItem(at: directory) }
        let databaseURL = directory.appendingPathComponent("secrets.sqlite")
        let store = DatabaseAIAgentSecretStore(storageURL: databaseURL)

        try store.setSecret("database-secret", for: "account")

        let attributes = try FileManager.default.attributesOfItem(atPath: databaseURL.path)
        let permissions = (attributes[.posixPermissions] as? NSNumber)?.uint16Value
        #expect(permissions == 0o600)
    }

    @Test
    func databaseStoreRestrictsContainingDirectory() throws {
        let directory = try makeDirectory(named: "zisla-agent-secret-directory-permissions")
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = DatabaseAIAgentSecretStore(
            storageURL: directory.appendingPathComponent("secrets.sqlite")
        )

        try store.setSecret("database-secret", for: "account")

        let attributes = try FileManager.default.attributesOfItem(atPath: directory.path)
        let permissions = (attributes[.posixPermissions] as? NSNumber)?.uint16Value
        #expect(permissions == 0o700)
    }

    @Test
    func databaseStoreRejectsBlankReferencesAndSecrets() throws {
        let directory = try makeDirectory(named: "zisla-agent-secret-validation")
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = DatabaseAIAgentSecretStore(storageURL: directory.appendingPathComponent("secrets.sqlite"))

        #expect(throws: AIAgentSecretStoreError.invalidReference) {
            try store.setSecret("secret", for: "  ")
        }
        #expect(throws: AIAgentSecretStoreError.invalidSecret) {
            try store.setSecret(" \n\t ", for: "account")
        }
    }

    private func makeDirectory(named prefix: String) throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(prefix)-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }
}
