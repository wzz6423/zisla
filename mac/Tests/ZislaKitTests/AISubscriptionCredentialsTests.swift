import Foundation
import LocalAuthentication
import Security
import SQLite3
import Testing
@testable import ZislaKit

struct AISubscriptionCredentialsTests {
    private let now = Date(timeIntervalSince1970: 1_910_000_000)
    private let token = "eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiJhdXRoMHxmaXh0dXJlLXVzZXIiLCJleHAiOjIwMDAwMDAwMDB9.fixture"
    private let encrypted = "djEwoKC7vNRT4TN9oiQQNHHK4zuVRblBTH7YxBJQ+gzgF1jMWouStORNi9rF2IMDTQJ18A1SsBwQoMC+NcVut3QnkMtcd79WAa7C0IPSh4t7M/SscIUKV4edBpwa/rwUv2bV"

    @Test func cursorCookieValidatesExpirationSubjectAndHeaderSafety() throws {
        #expect(try AISubscriptionCredentials.cursorCookie(token: token, now: now)
            == "WorkosCursorSessionToken=fixture-user%3A%3A\(token)")
        for invalid in [token + "\r\nCookie: injected", "broken", jwt(["sub": "bad/user", "exp": 2_000_000_000]),
                        jwt(["sub": "auth0|fixture", "exp": 1_910_000_030]), jwt(["sub": "auth0|fixture", "exp": true]),
                        jwt(["sub": "auth0|用户名", "exp": 2_000_000_000]), String(repeating: "x", count: 20_000)] {
            #expect(throws: AISubscriptionUsageError.invalidCredentials) {
                try AISubscriptionCredentials.cursorCookie(token: invalid, now: now)
            }
        }
    }

    @Test func cursorSafeStorageMatchesIndependentAESFixtureAndFailsClosedWithoutKeychainAccess() throws {
        let root = try fixtureRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let encryptedData = try #require(Data(base64Encoded: encrypted))
        #expect(AISubscriptionCredentials.decryptCursorToken(encryptedData, password: "fixture-password") == token)
        #expect(AISubscriptionCredentials.decryptCursorToken(encryptedData, password: "incorrect") == nil)
        #expect(AISubscriptionCredentials.decryptCursorToken(Data("v10truncated".utf8), password: "fixture-password") == nil)
        let database = CursorSessionActivityDetector.defaultUserDirectory(home: root)
            .appendingPathComponent("globalStorage/state.vscdb")
        try FileManager.default.createDirectory(at: database.deletingLastPathComponent(), withIntermediateDirectories: true)
        var handle: OpaquePointer?
        #expect(sqlite3_open(database.path, &handle) == SQLITE_OK)
        defer { sqlite3_close(handle) }
        #expect(sqlite3_exec(handle, "CREATE TABLE ItemTable (key TEXT, value TEXT)", nil, nil, nil) == SQLITE_OK)
        #expect(sqlite3_exec(handle,
            "INSERT INTO ItemTable VALUES ('cursorAuth/accessToken','cursor-safe-storage:v1:\(encrypted)')", nil, nil, nil) == SQLITE_OK)
        let credentials = AISubscriptionCredentials(home: root, environment: [:], keychainRead: { service, account in
            service == "Cursor Safe Storage" && account == "Cursor" ? Data("fixture-password".utf8) : nil
        })
        #expect(try credentials.cursorCookie(now: now) == "WorkosCursorSessionToken=fixture-user%3A%3A\(token)")
        let denied = AISubscriptionCredentials(home: root, environment: [:], keychainRead: { _, _ in nil })
        #expect(throws: AISubscriptionUsageError.invalidCredentials) { try denied.cursorCookie(now: now) }
    }

    @Test func CLIFileFallbackAndMuseInlineOrOAuthFollowConfirmedSourcePaths() throws {
        let root = try fixtureRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let missing = AISubscriptionCredentials(home: root, environment: [:], keychainRead: { _, _ in nil })
        #expect(try missing.cursorCookie(now: now) == nil && missing.museToken() == nil)
        let config = root.appendingPathComponent("config")
        try write(["accessToken": token], at: config.appendingPathComponent("cursor/auth.json"))
        let cli = AISubscriptionCredentials(home: root, environment: ["XDG_CONFIG_HOME": config.path], keychainRead: { _, _ in nil })
        #expect(try cli.cursorCookie(now: now) != nil)
        let auth = root.appendingPathComponent(".config/muse/auth.json")
        try write(["providers": ["meta": ["access_token": "dca:fixture-inline"]]], at: auth)
        #expect(try missing.museToken() == "dca:fixture-inline")
        try write(["providers": ["meta": ["mechanism": "oauth", "access_token": ""]]], at: auth)
        let oauth = AISubscriptionCredentials(home: root, environment: [:], keychainRead: { service, account in
            service == "ai.meta.dev.credentials" && account == "meta" ? Data(#"{"access_token":"dca:fixture-oauth"}"#.utf8) : nil
        })
        #expect(try oauth.museToken() == "dca:fixture-oauth")
        #expect(throws: AISubscriptionUsageError.invalidCredentials) { try missing.museToken() }
        for invalid in ["dca:", "dca:token with space", "dca:token\r\n", "other:token"] {
            try write(["providers": ["meta": ["access_token": invalid]]], at: auth)
            #expect(throws: AISubscriptionUsageError.invalidCredentials) { try missing.museToken() }
        }
    }

    @Test func keychainNoUIPreflightNeverReadsPayloadWhenLockedOrUntrusted() {
        for status in [errSecItemNotFound, errSecInteractionNotAllowed] {
            var calls = 0
            let result = AISubscriptionCredentials.readKeychainWithoutPrompt(service: "fixture", account: "fixture",
                copyMatching: { query in
                    calls += 1
                    let values = query as NSDictionary
                    #expect(values[kSecReturnData] == nil)
                    #expect((values[kSecUseAuthenticationContext] as? LAContext)?.interactionNotAllowed == true)
                    return (status, nil)
                }, allowsRead: { _ in Issue.record("Locked item must not inspect ACL"); return true })
            #expect(result == nil && calls == 1)
        }
        var calls = 0
        let result = AISubscriptionCredentials.readKeychainWithoutPrompt(service: "fixture", account: "fixture",
            copyMatching: { _ in
                calls += 1
                return (errSecSuccess, [kSecValueRef as String: "fixture-ref"] as CFDictionary)
            }, allowsRead: { _ in false })
        #expect(result == nil && calls == 1)
    }

    @Test func allowedKeychainReadKeepsNoUIAndUsesPreflightItemReference() {
        var calls = 0
        let expected = Data("fixture-secret".utf8)
        let result = AISubscriptionCredentials.readKeychainWithoutPrompt(service: "fixture", account: "fixture",
            copyMatching: { query in
                calls += 1
                let values = query as NSDictionary
                #expect((values[kSecUseAuthenticationContext] as? LAContext)?.interactionNotAllowed == true)
                if calls == 1 { return (errSecSuccess, [kSecValueRef as String: "fixture-ref"] as CFDictionary) }
                #expect(values[kSecReturnData] as? Bool == true)
                #expect(values[kSecReturnRef] == nil)
                #expect(values[kSecMatchItemList] as? [String] == ["fixture-ref"])
                return (errSecSuccess, expected as CFData)
            }, allowsRead: { _ in true })
        #expect(result == expected && calls == 2)
    }

    private func jwt(_ payload: [String: Any]) -> String {
        let data = try! JSONSerialization.data(withJSONObject: payload)
        let encoded = data.base64EncodedString().replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
        return "e30.\(encoded).fixture"
    }

    private func fixtureRoot() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("zisla-credentials-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }
    private func write(_ object: [String: Any], at url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONSerialization.data(withJSONObject: object).write(to: url)
    }
}
