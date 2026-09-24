import Foundation
import Testing

@testable import ZislaCore
@testable import ZislaKit

@MainActor
struct AIQuotaConfigurationTests {
    private func withStore(_ body: (AIQuotaConfigurationStore, AIQuotaMemoryCredentials, UserDefaults) throws -> Void) rethrows {
        let name = "AIQuotaConfigurationTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let credentials = AIQuotaMemoryCredentials()
        try body(AIQuotaConfigurationStore(defaults: defaults, credentials: credentials), credentials, defaults)
    }

    @Test(arguments: AIQuotaProvider.allCases)
    func everyProviderCanBeConfiguredAndReloadedWithoutReadingCredentials(_ provider: AIQuotaProvider) throws {
        try withStore { store, credentials, defaults in
            let configuration = AIQuotaFixtures.configuration(provider)
            try store.save(configuration, credential: provider.requiresLocalClient ? nil : AIQuotaFixtures.credential(configuration))
            #expect(store.configurations == [configuration])
            #expect(credentials.readIDs.isEmpty)
            let raw = try #require(defaults.data(forKey: AIQuotaConfigurationStore.defaultsKey))
            #expect(!String(decoding: raw, as: UTF8.self).contains("fictional"))
            let reloaded = AIQuotaConfigurationStore(defaults: defaults, credentials: credentials)
            #expect(reloaded.configurations == [configuration])
            #expect(credentials.readIDs.isEmpty)
        }
    }

    @Test
    func writeAndDeleteFailuresLeaveConfigurationUnchanged() throws {
        try withStore { store, credentials, defaults in
            let configuration = AIQuotaFixtures.configuration(.deepSeek)
            credentials.rejectWrites = true
            #expect(throws: AIQuotaError.storageUnavailable) { try store.save(configuration, credential: AIQuotaFixtures.credential(configuration)) }
            #expect(store.configurations.isEmpty)
            #expect(defaults.data(forKey: AIQuotaConfigurationStore.defaultsKey) == nil)
            credentials.rejectWrites = false
            try store.save(configuration, credential: AIQuotaFixtures.credential(configuration))
            let before = defaults.data(forKey: AIQuotaConfigurationStore.defaultsKey)
            credentials.rejectRemovals = true
            #expect(throws: AIQuotaError.storageUnavailable) { try store.remove(configuration) }
            #expect(store.configurations == [configuration])
            #expect(defaults.data(forKey: AIQuotaConfigurationStore.defaultsKey) == before)
            credentials.rejectRemovals = false
            try store.remove(configuration)
            #expect(store.configurations.isEmpty)
            #expect(credentials.stored.isEmpty)
        }
    }

    @Test
    func capacityFailureCannotLeaveAnOrphanCredential() throws {
        try withStore { store, credentials, _ in
            for index in 0..<100 {
                let configuration = AIQuotaConfiguration(id: "local-\(index)", provider: .codex)
                try store.save(configuration, credential: nil)
            }
            let overflow = AIQuotaFixtures.configuration(.deepSeek)
            #expect(throws: AIQuotaError.invalidConfiguration) { try store.save(overflow, credential: AIQuotaFixtures.credential(overflow)) }
            #expect(store.configurations.count == 100)
            #expect(credentials.writeIDs.isEmpty)
        }
    }

    @Test
    func disablingAnAccountNeverRequiresUnlockingKeychain() throws {
        try withStore { store, credentials, _ in
            var configuration = AIQuotaFixtures.configuration(.deepSeek)
            try store.save(configuration, credential: AIQuotaFixtures.credential(configuration))
            credentials.rejectReads = true
            configuration.isEnabled = false
            try store.save(configuration, credential: nil)
            #expect(store.configurations == [configuration])
            #expect(credentials.readIDs.isEmpty)
        }
    }

    @Test
    func changingDestinationRequiresFreshCredentialsButRenamingDoesNot() throws {
        try withStore { store, credentials, _ in
            var configuration = AIQuotaFixtures.configuration(.sub2api)
            try store.save(configuration, credential: AIQuotaFixtures.credential(configuration))
            configuration.label = "Renamed"
            try store.save(configuration, credential: nil)
            configuration.baseURL = "https://another.example.test"
            #expect(throws: AIQuotaError.credentialMissing) { try store.save(configuration, credential: nil) }
            #expect(store.configurations.first?.baseURL != configuration.baseURL)
            try store.save(configuration, credential: AIQuotaFixtures.credential(configuration))
            #expect(credentials.stored[configuration.id]?.scope == AIQuotaRequestBuilder.credentialScope(configuration))
        }
    }

    @Test
    func damagedOrDuplicateConfigurationDoesNotSilentlyLoadAccounts() throws {
        try withStore { _, credentials, defaults in
            defaults.set(Data("truncated".utf8), forKey: AIQuotaConfigurationStore.defaultsKey)
            let damaged = AIQuotaConfigurationStore(defaults: defaults, credentials: credentials)
            #expect(damaged.configurations.isEmpty)
            #expect(damaged.loadError == .invalidConfiguration)
            let configuration = AIQuotaFixtures.configuration(.codex)
            defaults.set(try JSONEncoder().encode([configuration, configuration]), forKey: AIQuotaConfigurationStore.defaultsKey)
            let duplicated = AIQuotaConfigurationStore(defaults: defaults, credentials: credentials)
            #expect(duplicated.loadError == .invalidConfiguration)
            #expect(duplicated.configurations.isEmpty)
            #expect(credentials.readIDs.isEmpty)
        }
    }

    @Test
    func tamperedDestinationCannotReceiveTheSavedToken() async throws {
        let credentials = AIQuotaMemoryCredentials()
        var configuration = AIQuotaFixtures.configuration(.sub2api)
        try credentials.write(AIQuotaFixtures.credential(configuration), id: configuration.id)
        configuration.baseURL = "https://unrelated.example.test"
        let http = AIQuotaMockHTTP([.success(AIQuotaFixtures.reference["sub2api-wallet"]!)])
        let reader = AIQuotaProviderReader(configuration: configuration, credentials: credentials, http: http)
        await #expect(throws: AIQuotaError.credentialMissing) { try await reader.read() }
        #expect(await http.requests.isEmpty)
    }

    @Test
    func disabledReaderDoesNotReadCredentialOrSendRequest() async throws {
        let credentials = AIQuotaMemoryCredentials()
        credentials.rejectReads = true
        var configuration = AIQuotaFixtures.configuration(.deepSeek)
        configuration.isEnabled = false
        let http = AIQuotaMockHTTP([])
        let reader = AIQuotaProviderReader(configuration: configuration, credentials: credentials, http: http)
        #expect(try await reader.read().isEmpty)
        #expect(credentials.readIDs.isEmpty)
        #expect(await http.requests.isEmpty)
    }

    @Test
    func credentialsCannotInjectHeadersAndTheirDescriptionRedactsSecrets() throws {
        let credential = AIQuotaCredential(token: "fictional-token", secret: "fictional-secret")
        #expect(!String(describing: credential).contains("fictional"))
        for value in ["abc\r\nX-Injected: yes", "abc\0def", "токен", String(repeating: "a", count: 32_769)] {
            #expect(throws: AIQuotaError.credentialInvalid) { try AIQuotaRequestBuilder.header(value) }
        }
    }
}
