import Foundation
import Testing
@testable import ZislaCore
@testable import ZislaKit

struct AIAccountBalanceCookieStoreTests {
    /// Region isolation and private database permissions must survive deleting one website credential.
    @Test func storesRegionsSeparatelyInPrivateDatabaseAndClearsOnlyChosenCookie() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("zisla-balance-cookie-\(UUID())")
        defer { try? FileManager.default.removeItem(at: directory) }
        let database = directory.appendingPathComponent("secrets.sqlite")
        let secrets = DatabaseAIAgentSecretStore(storageURL: database)
        let store = AIAccountBalanceCookieStore(secrets: secrets)
        try secrets.setSecret("untouched", for: "other-account")
        try store.setCookie("Cookie: global=fixture-global", for: .qoder)
        try store.setCookie("cn=fixture-cn", for: .qoderChina)
        #expect(try store.cookie(for: .qoder) == "global=fixture-global")
        #expect(try store.cookie(for: .qoderChina) == "cn=fixture-cn")
        try store.removeCookie(for: .qoder)
        #expect(try store.cookie(for: .qoder) == nil)
        #expect(try store.cookie(for: .qoderChina) == "cn=fixture-cn")
        #expect(try secrets.secret(for: "other-account") == "untouched")
        #expect((try FileManager.default.attributesOfItem(atPath: database.path)[.posixPermissions] as? NSNumber)?.intValue == 0o600)
        #expect((try FileManager.default.attributesOfItem(atPath: directory.path)[.posixPermissions] as? NSNumber)?.intValue == 0o700)
    }

    /// Validation failures must preserve stored values, while unrelated browser cookies never enter Zed authentication.
    @Test func invalidCookiesHaveNoSideEffectsAndZedForwardsOnlyKnownSessionCookies() throws {
        let secrets = BalanceMemorySecrets()
        let store = AIAccountBalanceCookieStore(secrets: secrets)
        try store.setCookie("zed.session=fixture; unrelated=private; c15t=consent; cf_clearance=clear", for: .zed)
        #expect(try store.cookie(for: .zed) == "zed.session=fixture; c15t=consent; cf_clearance=clear")
        let before = secrets.values
        for value in ["", "secret", "session=\r\nHost: injected", "=missing", "session=", "bad key=secret", "other=secret"] {
            #expect(throws: AIAccountBalanceError.invalidCredentials) { try store.setCookie(value, for: .zed) }
        }
        #expect(secrets.values == before)
        #expect(!String(describing: AIAccountBalanceError.invalidCredentials).contains("private"))
    }

    /// Browser-style trailing separators are accepted without relaxing validation of any nonempty cookie pair.
    @Test func pastedCookiesIgnoreEmptySegmentsButRejectMalformedNonemptyParts() throws {
        let secrets = BalanceMemorySecrets()
        let store = AIAccountBalanceCookieStore(secrets: secrets)
        for website in AIAccountBalanceWebsite.allCases {
            try store.setCookie("Cookie: zed.session=fixture; ; c15t=consent; ", for: website)
            #expect(try store.cookie(for: website) == "zed.session=fixture; c15t=consent")
        }
        let before = secrets.values
        for value in ["; ; ", "session=fixture; broken;", "session=fixture; bad key=secret;", "session=fixture; empty=;"] {
            #expect(throws: AIAccountBalanceError.invalidCredentials) { try store.setCookie(value, for: .qoder) }
        }
        #expect(secrets.values == before)
    }

    /// Persistence failure must remain visible for save, clear, and load instead of producing false success.
    @Test func storageFailuresPropagateWithoutOverwritingOrReportingSuccess() throws {
        let store = AIAccountBalanceCookieStore(secrets: FailingBalanceSecrets())
        #expect(throws: AIAgentSecretStoreError.storageFailed("fixture")) { try store.setCookie("session=fixture", for: .trae) }
        #expect(throws: AIAgentSecretStoreError.storageFailed("fixture")) { try store.removeCookie(for: .trae) }
        #expect(throws: AIAgentSecretStoreError.storageFailed("fixture")) { try store.cookie(for: .trae) }
    }
}

private final class BalanceMemorySecrets: AIAgentSecretStoring, @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [String: String] = [:]
    var values: [String: String] { lock.withLock { storage } }
    func secret(for reference: String) throws -> String? { lock.withLock { storage[reference] } }
    func setSecret(_ secret: String, for reference: String) throws { lock.withLock { storage[reference] = secret } }
    func removeSecret(for reference: String) throws { _ = lock.withLock { storage.removeValue(forKey: reference) } }
}
private struct FailingBalanceSecrets: AIAgentSecretStoring {
    func secret(for reference: String) throws -> String? { throw AIAgentSecretStoreError.storageFailed("fixture") }
    func setSecret(_ secret: String, for reference: String) throws { throw AIAgentSecretStoreError.storageFailed("fixture") }
    func removeSecret(for reference: String) throws { throw AIAgentSecretStoreError.storageFailed("fixture") }
}
