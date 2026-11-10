import Darwin
import Foundation
import LocalAuthentication
import Security
import Testing
@testable import ZislaCore
@testable import ZislaKit

struct AIAccountBalanceCredentialsTests {
    let now = Date(timeIntervalSince1970: 1_910_000_000)

    @Test func confirmedCLIAuthPathsUseReadOnlyCredentialsAndClock() throws {
        let token = jwt(["exp": 2_000_000_000, "sub": "fixture-user", "email": "fixture@example.test"])
        let fixtures: [(AIProvider, String, [String: Any])] = [
            (.codex, ".codex/auth.json", ["tokens": ["access_token": token, "account_id": "fixture-account"]]),
            (.claude, ".claude/.credentials.json", ["claudeAiOauth": ["accessToken": token, "expiresAt": 2_000_000_000_000]]),
            (.gemini, ".gemini/oauth_creds.json", ["access_token": token, "expiry_date": 2_000_000_000_000]),
            (.grok, ".grok/auth.json", ["https://auth.x.ai::fixture": ["key": token]]),
            (.kimi, ".kimi-code/credentials/kimi-code.json", ["access_token": token, "expires_at": 2_000_000_000]),
            (.opencode, ".local/share/opencode/auth.json", ["opencode-go": ["type": "api", "key": "fixture-key"]]),
        ]
        for (provider, path, object) in fixtures {
            let data = try JSONSerialization.data(withJSONObject: object)
            var source = makeSource()
            source.fileRead = { $0.path == "/fixture/" + path ? data : nil }
            let value = try #require(try source.load(for: provider, at: now))
            #expect(!value.token.isEmpty)
            #expect(!value.identity(provider: provider).contains("fixture-key"))
            #expect(!value.identity(provider: provider).contains(token))
        }
        var source = makeSource()
        source.cursorCookie = { time in
            #expect(time == now)
            return "WorkosCursorSessionToken=fixture%3A%3Afixture-jwt"
        }
        #expect(try source.load(for: .cursor, at: now)?.accountID == "fixture")
    }

    @Test func expiredUnsupportedAndHeaderInjectionFailWithoutRefreshOrWriting() throws {
        for payload in [["exp": 1_910_000_030], ["exp": true], [:]] as [[String: Any]] {
            #expect(throws: AIAccountBalanceError.credentialsExpired) { try AIAccountBalanceCredentials.claims(jwt(payload), at: now) }
        }
        for value in ["secret\r\nHost: injected", "", "密钥", String(repeating: "x", count: 33_000)] {
            #expect(throws: AIAccountBalanceError.invalidCredentials) { try AIAccountBalanceCredentials.header(value) }
        }
        var source = makeSource()
        source.fileRead = { _ in Data(#"{"OPENAI_API_KEY":"fixture"}"#.utf8) }
        #expect(throws: AIAccountBalanceError.unsupportedLogin) { try source.load(for: .codex, at: now) }
        source.environment = ["KIMI_CODE_BASE_URL": "https://untrusted.example"]
        source.fileRead = { _ in Issue.record("Unknown Kimi host must not read credentials"); return nil }
        #expect(throws: AIAccountBalanceError.unsupportedLogin) { try source.load(for: .kimi, at: now) }
    }

    @Test func copilotOfficialAppSourceHasStablePrecedenceAndConflictingLoginsFail() throws {
        let apps = try JSONSerialization.data(withJSONObject: [
            "github.com:Ov23liV9UpD7Rnfnskm3": ["access_token": "fixture-second", "login": "same-user"],
            "github.com:Iv1.b507a08c87ecfe98": ["oauth_token": "fixture-first", "login": "same-user"],
            "enterprise.example:Iv1.b507a08c87ecfe98": ["access_token": "must-not-use", "login": "private-user"],
        ])
        var source = makeSource()
        source.environment = ["XDG_CONFIG_HOME": "/fixture/xdg"]
        source.fileRead = { url in
            #expect(url.path == "/fixture/xdg/github-copilot/apps.json")
            return apps
        }
        #expect(try source.load(for: .copilot, at: now)?.token == "fixture-first")
        let conflict = try JSONSerialization.data(withJSONObject: [
            "github.com:Ov23liV9UpD7Rnfnskm3": ["access_token": "fixture-second", "login": "other-user"],
            "github.com:Iv1.b507a08c87ecfe98": ["oauth_token": "fixture-first", "login": "same-user"],
        ])
        source.fileRead = { _ in conflict }
        #expect(throws: AIAccountBalanceError.credentialsUnavailable) { try source.load(for: .copilot, at: now) }
        let legacy = Data(#"{"github.com":{"oauth_token":"fixture-legacy","user":"legacy-user"},"enterprise.example":{"oauth_token":"must-not-use"}}"#.utf8)
        source.fileRead = { $0.lastPathComponent == "hosts.json" ? legacy : nil }
        #expect(try source.load(for: .copilot, at: now)?.accountID == "legacy-user")
    }

    @Test func qoderReadsOnlySelectedRegionAndZedWebsiteFailureDoesNotReadNativeLogin() throws {
        var source = makeSource()
        source.websiteCookie = { website in
            #expect(website == .qoderChina, "The unselected region must not access saved credentials")
            return "session=fixture-cn"
        }
        let credential = try #require(try source.load(for: .coder, at: now, qoderRegion: .china))
        #expect(credential.region == "cn" && credential.isWebsiteCookie)
        source.websiteCookie = { website in #expect(website == .qoder); return nil }
        #expect(try source.load(for: .coder, at: now, qoderRegion: .global) == nil)
        source.websiteCookie = { _ in throw AIAccountBalanceError.invalidCredentials }
        source.keychainRead = { _, _ in Issue.record("Website credential failures must not read Keychain"); return nil }
        source.fileRead = { _ in Issue.record("Website credential failures must not read native files"); return nil }
        #expect(throws: AIAccountBalanceError.invalidCredentials) { try source.load(for: .zed, at: now) }
    }

    @Test func zedJSONCSettingsKeepTrustedHostAndInlineOpenCodeAuthNeverFallsBack() throws {
        var source = makeSource()
        let settings = Data("""
        {
          // The editor stores commented settings.
          "server_url": "https://zed.dev", /* trusted */
          "credentials_url": "https://zed.dev",
        }
        """.utf8)
        source.fileRead = { $0.path.hasSuffix(".config/zed/settings.json") ? settings : nil }
        source.keychainRead = { service, _ in
            #expect(service == "https://zed.dev")
            return .init(account: "fixture-zed", data: Data("fixture-token".utf8))
        }
        #expect(try source.load(for: .zed, at: now)?.accountID == "fixture-zed")
        let custom = Data("""
        {"server_url":"https://untrusted.example" /* never forward */,}
        """.utf8)
        source.fileRead = { _ in custom }
        source.keychainRead = { _, _ in Issue.record("Custom server must not access native credentials"); return nil }
        #expect(throws: AIAccountBalanceError.unsupportedLogin) { try source.load(for: .zed, at: now) }
        source.environment = ["OPENCODE_AUTH_CONTENT": #"{"opencode-go":{"type":"api","key":"fixture-inline"}}"#]
        source.fileRead = { _ in Issue.record("Inline auth must not read the file account"); return nil }
        #expect(try source.load(for: .opencode, at: now)?.token == "fixture-inline")
        source.environment = ["OPENCODE_AUTH_CONTENT": "invalid"]
        #expect(throws: AIAccountBalanceError.invalidResponse) { try source.load(for: .opencode, at: now) }
    }

    @Test func zcodeSelectionUsesAuthoritativeRegistryAndNeverStaleEncryptedMirror() throws {
        let config = try JSONSerialization.data(withJSONObject: ["provider": ["builtin:zai-coding-plan": ["options": ["apiKey": "fixture-key"]]]])
        let settings = try JSONSerialization.data(withJSONObject: ["providerFamilyConnectionSelections": ["zai": ["kind": "individual-coding-plan"]],
            "modelProviderFamilySelectedKeys": ["zai": "preset:builtin:zai"]])
        var source = makeSource()
        source.fileRead = { url in
            switch url.lastPathComponent { case "config.json": config; case "settings.json": settings; default: nil }
        }
        #expect(try source.load(for: .zcode, at: now)?.token == "fixture-key")
        source.fileRead = { url in
            switch url.lastPathComponent { case "config.json": config; case "settings.json": settings;
            case "credentials.json": Data(#"{"profile":"enc:v1:fixture"}"#.utf8); default: nil }
        }
        #expect(throws: AIAccountBalanceError.credentialsUnavailable) { try source.load(for: .zcode, at: now) }
        let unknown = try JSONSerialization.data(withJSONObject: ["providerFamilyConnectionSelections": ["zai": ["kind": "unknown"]],
            "modelProviderFamilySelectedKeys": ["zai": "coding-plan:builtin:zai-coding-plan"]])
        source.fileRead = { $0.lastPathComponent == "config.json" ? config : unknown }
        #expect(throws: AIAccountBalanceError.unsupportedLogin) { try source.load(for: .zcode, at: now) }
    }

    @Test func workbuddyRealmsEncryptedSessionsAndLogoutAreDistinct() throws {
        let path = "/fixture/Library/Application Support/CodeBuddyExtension/Data/Public/auth/workbuddy-desktop-ai.info"
        let data = try JSONSerialization.data(withJSONObject: ["auth": ["accessToken": "fixture", "expiresAt": 2_000_000_000_000,
            "domain": "www.workbuddy.ai"], "account": ["uid": "fixture-user", "enterpriseId": "fixture-team"]])
        var source = makeSource()
        source.fileRead = { $0.path == path ? data : nil }
        let credential = try #require(try source.load(for: .workbuddyAI, at: now))
        #expect(credential.region == "ai" && credential.headers["X-Tenant-Id"] == "fixture-team")
        let encrypted = Data(#"{"auth":{"accessToken":{"$wbEncrypted":"fixture"}},"account":{"uid":"fixture"}}"#.utf8)
        source.fileRead = { $0.path == path ? encrypted : nil }
        #expect(throws: AIAccountBalanceError.credentialsUnavailable) { try source.load(for: .workbuddyAI, at: now) }
        source.fileRead = { $0.path == path + ".logged-out" ? Data() : data }
        #expect(try source.load(for: .workbuddyAI, at: now) == nil)
    }

    @Test func credentialFilesRejectLinksNonRegularAndOversizeAndCloseDescriptors() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("zisla-balance-files-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("auth.json")
        let original = Data(#"{"fixture":true}"#.utf8)
        try original.write(to: file)
        for _ in 0..<50 { #expect(try AIAccountBalanceCredentials.readRegularFile(file) == original) }
        #expect(try Data(contentsOf: file) == original)
        #expect(try AIAccountBalanceCredentials.readRegularFile(root.appendingPathComponent("absent")) == nil)
        let symlink = root.appendingPathComponent("link")
        try FileManager.default.createSymbolicLink(at: symlink, withDestinationURL: file)
        #expect(throws: AIAccountBalanceError.credentialsUnavailable) { try AIAccountBalanceCredentials.readRegularFile(symlink) }
        #expect(throws: AIAccountBalanceError.credentialsUnavailable) { try AIAccountBalanceCredentials.readRegularFile(root) }
        let fifo = root.appendingPathComponent("fifo")
        #expect(mkfifo(fifo.path, 0o600) == 0)
        #expect(throws: AIAccountBalanceError.credentialsUnavailable) { try AIAccountBalanceCredentials.readRegularFile(fifo) }
        try Data(repeating: 1, count: 1_024 * 1_024 + 1).write(to: file)
        #expect(throws: AIAccountBalanceError.credentialsUnavailable) { try AIAccountBalanceCredentials.readRegularFile(file) }
    }

    @Test func keychainAccountAndPayloadReadKeepNoUIPreflightAndFailureClassification() throws {
        var calls = 0
        let result = try AISubscriptionCredentials.readKeychainCredentialWithoutPrompt(service: "https://zed.dev", internetPassword: true,
            copyMatching: { query in
                calls += 1
                let values = query as NSDictionary
                #expect(values[kSecClass] as? String == kSecClassInternetPassword as String)
                #expect(values[kSecAttrServer] as? String == "https://zed.dev")
                #expect((values[kSecUseAuthenticationContext] as? LAContext)?.interactionNotAllowed == true)
                #expect(values[kSecUseAuthenticationUI] as? String == "u_AuthUIF")
                if calls == 1 {
                    #expect(values[kSecReturnData] == nil)
                    return (errSecSuccess, [kSecValueRef as String: "fixture-reference", kSecAttrAccount as String: "42"] as CFDictionary)
                }
                #expect(values[kSecMatchItemList] as? [String] == ["fixture-reference"])
                return (errSecSuccess, Data("fixture-secret".utf8) as CFData)
            }, allowsRead: { _ in true })
        #expect(result?.account == "42" && result?.data == Data("fixture-secret".utf8) && calls == 2)
        #expect(try AISubscriptionCredentials.readKeychainCredentialWithoutPrompt(service: "fixture",
            copyMatching: { _ in (errSecItemNotFound, nil) }) == nil)
        #expect(throws: AISubscriptionCredentials.KeychainReadError.self) {
            try AISubscriptionCredentials.readKeychainCredentialWithoutPrompt(service: "fixture",
                copyMatching: { _ in (errSecInteractionNotAllowed, nil) })
        }
    }

    private func makeSource() -> AIAccountBalanceCredentials {
        var source = AIAccountBalanceCredentials(home: URL(fileURLWithPath: "/fixture"), environment: [:])
        source.fileRead = { _ in nil }
        source.cursorCookie = { _ in nil }
        source.keychainRead = { _, _ in nil }
        source.websiteCookie = { _ in nil }
        return source
    }

    private func jwt(_ payload: [String: Any]) -> String {
        let encoded = try! JSONSerialization.data(withJSONObject: payload).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
        return "e30.\(encoded).fixture"
    }
}
