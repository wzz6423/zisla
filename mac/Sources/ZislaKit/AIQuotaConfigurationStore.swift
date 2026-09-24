import Combine
import Foundation
import LocalAuthentication
import Security
import ZislaCore

public struct AIQuotaCredential: Codable, Equatable, Sendable, CustomStringConvertible {
    public var token: String
    public var secret: String
    public var scope: String?
    public var description: String { "<AIQuota credential>" }

    public init(token: String, secret: String = "", scope: String? = nil) {
        self.token = token
        self.secret = secret
        self.scope = scope
    }
}

public protocol AIQuotaCredentialStoring: Sendable {
    func read(id: String) throws -> AIQuotaCredential?
    func write(_ credential: AIQuotaCredential, id: String) throws
    func remove(id: String) throws
}

public struct AIQuotaKeychain: AIQuotaCredentialStoring {
    private static let service = "com.zisla.ai-quota"

    public init() {}

    private func query(_ id: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: Self.service,
         kSecAttrAccount as String: id]
    }

    public func read(id: String) throws -> AIQuotaCredential? {
        let context = LAContext()
        context.interactionNotAllowed = true
        var query = query(id)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        query[kSecUseAuthenticationContext as String] = context
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data,
              let credential = try? JSONDecoder().decode(AIQuotaCredential.self, from: data)
        else { throw AIQuotaError.storageUnavailable }
        return credential
    }

    public func write(_ credential: AIQuotaCredential, id: String) throws {
        let data = try JSONEncoder().encode(credential)
        let query = query(id)
        let values = [kSecValueData as String: data]
        let updated = SecItemUpdate(query as CFDictionary, values as CFDictionary)
        if updated == errSecSuccess { return }
        guard updated == errSecItemNotFound else { throw AIQuotaError.storageUnavailable }
        var item = query
        item[kSecValueData as String] = data
        item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        guard SecItemAdd(item as CFDictionary, nil) == errSecSuccess else {
            throw AIQuotaError.storageUnavailable
        }
    }

    public func remove(id: String) throws {
        let status = SecItemDelete(query(id) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw AIQuotaError.storageUnavailable
        }
    }
}

@MainActor
public final class AIQuotaConfigurationStore: ObservableObject {
    @Published public private(set) var configurations: [AIQuotaConfiguration] = []
    @Published public private(set) var loadError: AIQuotaError?
    public let credentials: any AIQuotaCredentialStoring
    private let defaults: UserDefaults
    static let defaultsKey = "zisla.aiQuota.accounts.v1"

    public init(defaults: UserDefaults = .standard, credentials: any AIQuotaCredentialStoring = AIQuotaKeychain()) {
        self.defaults = defaults
        self.credentials = credentials
        if let data = defaults.data(forKey: Self.defaultsKey) {
            do {
                let values = try JSONDecoder().decode([AIQuotaConfiguration].self, from: data)
                guard values.count <= 100, Set(values.map(\.id)).count == values.count else {
                    throw AIQuotaError.invalidConfiguration
                }
                configurations = values
            } catch { loadError = .invalidConfiguration }
        }
    }

    public func save(_ configuration: AIQuotaConfiguration, credential: AIQuotaCredential?) throws {
        try AIQuotaRequestBuilder.validate(configuration)
        let existing = configurations.first { $0.id == configuration.id }
        guard existing != nil || configurations.count < 100 else { throw AIQuotaError.invalidConfiguration }
        var next = configurations
        if let index = next.firstIndex(where: { $0.id == configuration.id }) {
            next[index] = configuration
        } else {
            next.append(configuration)
        }
        let data = try JSONEncoder().encode(next)
        if configuration.source == .manual && (configuration.isEnabled || credential != nil) {
            if let existing,
               existing.source != .manual || existing.provider != configuration.provider || existing.baseURL != configuration.baseURL
                || existing.organization != configuration.organization || existing.chinaSite != configuration.chinaSite {
                guard credential != nil else { throw AIQuotaError.credentialMissing }
            }
            if let credential {
                _ = try AIQuotaRequestBuilder.validatedCredential(credential, provider: configuration.provider)
                var stored = credential
                stored.scope = AIQuotaRequestBuilder.credentialScope(configuration)
                try credentials.write(stored, id: configuration.id)
            } else if try credentials.read(id: configuration.id)?.scope != AIQuotaRequestBuilder.credentialScope(configuration) {
                throw AIQuotaError.credentialMissing
            }
        }
        defaults.set(data, forKey: Self.defaultsKey)
        loadError = nil
        configurations = next
    }

    public func remove(_ configuration: AIQuotaConfiguration) throws {
        try credentials.remove(id: configuration.id)
        let next = configurations.filter { $0.id != configuration.id }
        defaults.set(try JSONEncoder().encode(next), forKey: Self.defaultsKey)
        configurations = next
    }
}
