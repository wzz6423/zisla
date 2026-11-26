import CryptoKit
import Darwin
import Foundation
import LocalAuthentication
import Security
import Testing
@testable import ZislaCore
@testable import ZislaKit

struct AIAccountBalanceCredentialsTests {
    let now = Date(timeIntervalSince1970: 1_910_000_000)

    /// Injected official login files prove provider selection and expiry-clock use without touching real accounts.
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

    /// Expiry, API-key login, header injection, and custom-host failures must stop before credentialed network work.
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

    /// Multiple official app entries may share one login but must not silently select between different accounts.
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

    /// A website or region decision is authoritative, including failure, so native fallback cannot select another account.
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

    @Test(arguments: AIAccountBalanceQoderRegion.allCases, [AIProvider.trae, .zed])
    func qoderRegionChoiceDoesNotChangeTRAEOrZedCredentialSource(region: AIAccountBalanceQoderRegion, provider: AIProvider) throws {
        var source = makeSource()
        source.websiteCookie = { website in
            #expect(website == (provider == .trae ? .trae : .zed),
                    "The Qoder region must not select another provider's website session")
            return "session=fixture-independent"
        }
        source.fileRead = { _ in Issue.record("Selected website login must not read native credentials"); return nil }
        source.keychainRead = { _, _ in Issue.record("Selected website login must not read native Keychain"); return nil }
        let credential = try #require(try source.load(for: provider, at: now, qoderRegion: region))
        #expect(credential.isWebsiteCookie)
        #expect(credential.region == (provider == .trae ? "cn" : nil))
    }

    /// Commented settings remain readable while host overrides and invalid inline auth cannot escape their source boundary.
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

    /// Dotfile links may configure Zed, but malformed targets must fail before the fake native credential read.
    @Test(arguments: ["regular", "directory", "oversize", "invalid", "custom-server", "custom-credentials"])
    func zedLinkedSettingsRetainNativeLoginAndFailClosedForUnsafeTargets(kind: String) throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("zisla-zed-settings-\(UUID())")
        let home = root.appendingPathComponent("home"), dotfiles = root.appendingPathComponent("dotfiles")
        let settings = home.appendingPathComponent(".config/zed/settings.json")
        try FileManager.default.createDirectory(at: settings.deletingLastPathComponent(), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: dotfiles, withIntermediateDirectories: true)
        let target = dotfiles.appendingPathComponent("settings.json")
        let data: Data?
        let expectedError: AIAccountBalanceError?
        switch kind {
        case "directory": (data, expectedError) = (nil, .credentialsUnavailable)
        case "oversize": (data, expectedError) = (Data(repeating: 0x20, count: 1_024 * 1_024 + 1), .credentialsUnavailable)
        case "invalid": (data, expectedError) = (Data("{invalid".utf8), .invalidResponse)
        case "custom-server":
            (data, expectedError) = (Data(#"{"server_url":"https://untrusted.example"}"#.utf8), .unsupportedLogin)
        case "custom-credentials":
            (data, expectedError) = (Data(#"{"credentials_url":"https://untrusted.example"}"#.utf8), .unsupportedLogin)
        default:
            (data, expectedError) = (Data(#"{"server_url":"https://zed.dev","credentials_url":"https://zed.dev",}"#.utf8), nil)
        }
        if let data { try data.write(to: target) }
        else { try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true) }
        try FileManager.default.createSymbolicLink(at: settings, withDestinationURL: target)
        var source = AIAccountBalanceCredentials(home: home, environment: [:])
        source.cursorCookie = { _ in nil }
        source.websiteCookie = { _ in nil }
        source.keychainRead = { service, internetPassword in
            guard kind == "regular" else { Issue.record("Unsafe Zed settings must not read native credentials"); return nil }
            #expect(service == "https://zed.dev" && internetPassword)
            return .init(account: "fixture-zed", data: Data("fixture-zed-token".utf8))
        }
        if let expectedError {
            #expect(throws: expectedError) { try source.load(for: .zed, at: now) }
        } else {
            let credential = try #require(try source.load(for: .zed, at: now))
            #expect(credential.accountID == "fixture-zed" && credential.token == "fixture-zed-token")
            #expect(!credential.isWebsiteCookie)
        }
        #expect(try FileManager.default.destinationOfSymbolicLink(atPath: settings.path) == target.path)
        if let data { #expect(try Data(contentsOf: target) == data, "Reading linked settings must not change dotfiles") }
    }

    /// Modern selections, `setting.json`, and encrypted stores supersede legacy hints and plaintext mirrors.
    @Test func zcodeSelectionUsesAuthoritativeRegistryAndDecryptsCredentialsStore() throws {
        let config = try JSONSerialization.data(withJSONObject: [
            "provider": [
                "builtin:zai-coding-plan": ["options": ["apiKey": "fixture-mirror-key"]],
                "builtin:bigmodel-coding-plan": ["options": ["apiKey": "fixture-bigmodel-mirror"]],
                "builtin:zai-start-plan": ["options": ["apiKey": "fixture-start-mirror"]],
            ],
        ])
        let settings = try JSONSerialization.data(withJSONObject: [
            "providerFamilyDomain": "zai",
            "providerFamilyConnectionSelections": ["zai": ["kind": "individual-coding-plan"]],
            "modelProviderFamilySelectedKeys": ["zai": "preset:builtin:zai"],
        ])
        var source = makeSource()
        source.username = "fixtureuser"
        source.fileRead = { url in
            switch url.lastPathComponent { case "config.json": config; case "setting.json": settings; default: nil }
        }
        #expect(try source.load(for: .zcode, at: now)?.token == "fixture-mirror-key")

        // Unreadable credentials.json must fail closed and never fall back to plaintext mirror.
        source.fileRead = { url in
            switch url.lastPathComponent { case "config.json": config; case "setting.json": settings;
            case "credentials.json": Data(#"{"profile":"enc:v1:fixture"}"#.utf8); default: nil }
        }
        #expect(throws: AIAccountBalanceError.credentialsUnavailable) { try source.load(for: .zcode, at: now) }

        // Valid AES-256-GCM encrypted credentials.json decrypts the active account's coding-plan key.
        let secret = "zcode-credential-fallback:darwin:/fixture:fixtureuser"
        let zaiProfile = try encryptZcode(#"{"user_id":"user/42"}"#, secret: secret)
        let zaiKey = try encryptZcode("fixture-live-zai-key", secret: secret)
        let storeData = try JSONSerialization.data(withJSONObject: [
            "oauth:zai:user_info": zaiProfile,
            "account-provider:coding-plan:account:zai-individual-coding-plan:account:user%2F42:api-key": zaiKey,
        ])
        source.fileRead = { url in
            switch url.lastPathComponent {
            case "config.json": config
            case "setting.json": settings
            case "credentials.json": storeData
            default: nil
            }
        }
        let liveCoding = try #require(try source.load(for: .zcode, at: now))
        #expect(liveCoding.token == "fixture-live-zai-key" && liveCoding.region == "zai")

        // providerFamilyDomain selects bigmodel over zai and ZCODE_DATA_BASE_DIR redirects root only for absolute paths.
        let bigmodelSettings = try JSONSerialization.data(withJSONObject: [
            "providerFamilyDomain": "bigmodel",
            "providerFamilyConnectionSelections": ["bigmodel": ["kind": "team-coding-plan"]],
        ])
        source.environment = ["ZCODE_DATA_BASE_DIR": "/custom/zcode-base"]
        source.fileRead = { url in
            #expect(url.path.hasPrefix("/custom/zcode-base/.zcode/v2/"))
            return switch url.lastPathComponent {
            case "config.json": config
            case "setting.json": bigmodelSettings
            default: nil
            }
        }
        let bigmodel = try #require(try source.load(for: .zcode, at: now))
        #expect(bigmodel.token == "fixture-bigmodel-mirror" && bigmodel.region == "bigmodel")

        // Start plan decrypts zcodejwttoken and attaches X-Device-Mid from telemetry-state.json.
        let startSettings = try JSONSerialization.data(withJSONObject: [
            "providerFamilyDomain": "zai",
            "providerFamilyConnectionSelections": ["zai": ["kind": "start-plan"]],
        ])
        let jwtEncrypted = try encryptZcode("fixture-start-jwt", secret: "explicit-secret")
        let startStore = try JSONSerialization.data(withJSONObject: ["zcodejwttoken": jwtEncrypted])
        let telemetry = Data(#"{"deviceMid":"mid-1234"}"#.utf8)
        source.environment = ["ZCODE_CREDENTIAL_SECRET": "explicit-secret"]
        source.fileRead = { url in
            switch url.lastPathComponent {
            case "config.json": config
            case "setting.json": startSettings
            case "credentials.json": startStore
            case "telemetry-state.json": telemetry
            default: nil
            }
        }
        let startPlan = try #require(try source.load(for: .zcode, at: now))
        #expect(startPlan.token == "fixture-start-jwt" && startPlan.region == "start-plan")
        #expect(startPlan.headers["X-Device-Mid"] == "mid-1234")

        let unknown = try JSONSerialization.data(withJSONObject: [
            "providerFamilyDomain": "zai",
            "providerFamilyConnectionSelections": ["zai": ["kind": "unknown"]],
            "modelProviderFamilySelectedKeys": ["zai": "coding-plan:builtin:zai-coding-plan"],
        ])
        source.environment = [:]
        source.fileRead = { $0.lastPathComponent == "config.json" ? config : ($0.lastPathComponent == "setting.json" ? unknown : nil) }
        #expect(throws: AIAccountBalanceError.unsupportedLogin) { try source.load(for: .zcode, at: now) }
    }

    /// Provider env overrides, fallback paths, opaque Grok tokens, and flexible expiry units must load cleanly.
    @Test func providerCredentialFallbacksAndFlexibleExpiriesWorkAcrossProviders() throws {
        // Copilot falls through to hosts.json when apps.json has no matching github.com entry.
        var source = makeSource()
        let enterpriseOnlyApps = Data(#"{"enterprise.example:Iv1.b507a08c87ecfe98":{"access_token":"must-not-use"}}"#.utf8)
        let hosts = Data(#"{"github.com":{"oauth_token":"fixture-hosts-token","user":"hosts-user"}}"#.utf8)
        source.fileRead = { url in
            switch url.lastPathComponent {
            case "apps.json": enterpriseOnlyApps
            case "hosts.json": hosts
            default: nil
            }
        }
        #expect(try source.load(for: .copilot, at: now)?.token == "fixture-hosts-token")

        // Claude supports CLAUDE_CODE_OAUTH_TOKEN, oauth wrapper, and Unix-seconds expiresAt.
        source = makeSource()
        source.environment = ["CLAUDE_CODE_OAUTH_TOKEN": "fixture-claude-env"]
        #expect(try source.load(for: .claude, at: now)?.token == "fixture-claude-env")
        source = makeSource()
        let claudeSeconds = Data(#"{"oauth":{"accessToken":"fixture-claude-sec","expiresAt":2000000000}}"#.utf8)
        source.fileRead = { $0.lastPathComponent == ".credentials.json" ? claudeSeconds : nil }
        #expect(try source.load(for: .claude, at: now)?.token == "fixture-claude-sec")

        // Gemini honors GEMINI_CLI_HOME and allows absent expiry_date.
        source = makeSource()
        source.environment = ["GEMINI_CLI_HOME": "/custom/gemini"]
        let geminiData = Data(#"{"access_token":"fixture-gemini-token"}"#.utf8)
        source.fileRead = { $0.path == "/custom/gemini/.gemini/oauth_creds.json" ? geminiData : nil }
        #expect(try source.load(for: .gemini, at: now)?.token == "fixture-gemini-token")

        // Grok accepts opaque tokens and sign-in scope fallback.
        source = makeSource()
        let grokData = Data(#"{"https://accounts.x.ai/custom/sign-in":{"key":"opaque-grok-token","email":"user@example.test"}}"#.utf8)
        source.fileRead = { $0.lastPathComponent == "auth.json" ? grokData : nil }
        let grok = try #require(try source.load(for: .grok, at: now))
        #expect(grok.token == "opaque-grok-token" && grok.accountName == "user@example.test")

        // Kimi supports KIMI_CODE_API_KEY and millisecond expires_at.
        source = makeSource()
        source.environment = ["KIMI_CODE_API_KEY": "fixture-kimi-env"]
        #expect(try source.load(for: .kimi, at: now)?.token == "fixture-kimi-env")
        source = makeSource()
        let kimiMs = Data(#"{"access_token":"fixture-kimi-ms","expires_at":2000000000000}"#.utf8)
        source.fileRead = { $0.path == "/fixture/.kimi/credentials/kimi-code.json" ? kimiMs : nil }
        #expect(try source.load(for: .kimi, at: now)?.token == "fixture-kimi-ms")
    }

    /// Realm-specific tenant headers, inaccessible encryption, and a logout marker must yield distinct login outcomes.
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

    /// Temporary-file probes cover unchanged contents, nonblocking FIFO rejection, and size bounds without user credential access.
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

    /// An injected Keychain query proves no-UI preflight and matching account/payload reads without querying the real Keychain.
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

    private func encryptZcode(_ plain: String, secret: String) throws -> String {
        let key = SymmetricKey(data: SHA256.hash(data: Data(secret.utf8)))
        let nonce = try AES.GCM.Nonce(data: Data(repeating: 7, count: 12))
        let sealed = try AES.GCM.seal(Data(plain.utf8), using: key, nonce: nonce)
        func b64url(_ data: Data) -> String {
            data.base64EncodedString()
                .replacingOccurrences(of: "+", with: "-")
                .replacingOccurrences(of: "/", with: "_")
                .replacingOccurrences(of: "=", with: "")
        }
        return "enc:v1:\(b64url(Data(nonce))).\(b64url(sealed.tag)).\(b64url(sealed.ciphertext))"
    }

    private func jwt(_ payload: [String: Any]) -> String {
        let encoded = try! JSONSerialization.data(withJSONObject: payload).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
        return "e30.\(encoded).fixture"
    }
}
