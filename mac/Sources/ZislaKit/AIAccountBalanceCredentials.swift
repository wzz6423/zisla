import CoreFoundation
import CryptoKit
import Darwin
import Foundation
import Security
import ZislaCore

struct AIAccountBalanceCredential: Sendable {
    let token: String
    var accountID: String?
    var accountName: String?
    var region: String?
    var isWebsiteCookie = false
    var headers: [String: String] = [:]

    /// Separates provider, region, and account episodes without exposing a raw credential in row IDs.
    func identity(provider: AIProvider) -> String {
        DesktopAIStorage.identity([provider.rawValue, region ?? "", accountID ?? token])
    }
}

enum AIAccountBalanceError: Error, Equatable {
    case credentialsUnavailable, credentialsExpired, invalidCredentials, invalidResponse
    case httpStatus(Int), unsupportedLogin, noQuota
}

// Native read-only adaptation of CodexBar 7447bc77 and token-monitor 5915414 (MIT).
struct AIAccountBalanceCredentials: Sendable {
    let home: URL
    var environment: [String: String] = ProcessInfo.processInfo.environment
    var username: String = NSUserName()
    var fileRead: @Sendable (URL) throws -> Data? = Self.readRegularFile
    var cursorCookie: @Sendable (Date) throws -> String?
    var keychainRead: @Sendable (String, Bool) throws -> AISubscriptionCredentials.KeychainCredential? = {
        try AISubscriptionCredentials.readKeychainCredentialWithoutPrompt(service: $0, internetPassword: $1)
    }
    var websiteCookie: @Sendable (AIAccountBalanceWebsite) throws -> String? = { try AIAccountBalanceCookieStore().cookie(for: $0) }

    init(home: URL = FileManager.default.homeDirectoryForCurrentUser,
         environment: [String: String] = ProcessInfo.processInfo.environment) {
        self.home = home
        self.environment = environment
        let subscription = AISubscriptionCredentials(home: home, environment: environment)
        cursorCookie = { try subscription.cursorCookie(now: $0) }
    }

    /// Reads only the selected provider's established login source, without refreshing or writing credentials.
    /// Explicit website or inline credentials remain authoritative; errors must not select another account.
    /// Conflicting Copilot logins and unsupported hosts or encrypted sessions fail before any quota request.
    func load(for provider: AIProvider, at now: Date, qoderRegion: AIAccountBalanceQoderRegion = .global) throws -> AIAccountBalanceCredential? {
        switch provider {
        case .copilot:
            if let token = envToken(["COPILOT_API_TOKEN", "GITHUB_COPILOT_TOKEN"]) {
                return try Self.credential(token: token)
            }
            let config = environment["XDG_CONFIG_HOME"].flatMap { $0.hasPrefix("/") ? URL(fileURLWithPath: $0) : nil }
                ?? home.appendingPathComponent(".config")
            let base = config.appendingPathComponent("github-copilot")
            if let apps = try json(base.appendingPathComponent("apps.json")) {
                let knownIDs = ["Iv1.b507a08c87ecfe98", "Ov23liV9UpD7Rnfnskm3"]
                let entries = knownIDs.compactMap { apps["github.com:" + $0] }
                let values = try entries.map { raw -> AIAccountBalanceCredential in
                    guard let auth = raw as? [String: Any], let token = auth["access_token"] as? String ?? auth["oauth_token"] as? String else {
                        throw AIAccountBalanceError.credentialsUnavailable
                    }
                    return try Self.credential(token: token, accountID: auth["login"] as? String ?? auth["user"] as? String)
                }
                if let first = values.first {
                    guard values.allSatisfy({ $0.accountID != nil && $0.accountID == first.accountID }) || values.count == 1 else {
                        throw AIAccountBalanceError.credentialsUnavailable
                    }
                    return first
                }
            }
            guard let hosts = try json(base.appendingPathComponent("hosts.json")),
                  let auth = hosts["github.com"] as? [String: Any], let token = auth["oauth_token"] as? String ?? auth["access_token"] as? String else { return nil }
            return try Self.credential(token: token, accountID: auth["user"] as? String ?? auth["login"] as? String)
        case .coder, .trae:
            let website: AIAccountBalanceWebsite = provider == .trae ? .trae : (qoderRegion == .china ? .qoderChina : .qoder)
            guard let cookie = try websiteCookie(website) else { return nil }
            var credential = try Self.credential(token: cookie, region: website == .qoderChina || website == .trae ? "cn" : "global")
            credential.isWebsiteCookie = true
            return credential
        case .codex, .gpt:
            guard let root = try json(directory("CODEX_HOME", fallback: ".codex").appendingPathComponent("auth.json")) else { return nil }
            guard let tokens = root["tokens"] as? [String: Any], let token = tokens["access_token"] as? String else {
                if root["OPENAI_API_KEY"] != nil { throw AIAccountBalanceError.unsupportedLogin }
                throw AIAccountBalanceError.invalidCredentials
            }
            let claims = try Self.claims(token, at: now)
            let idClaims = (tokens["id_token"] as? String).flatMap { try? Self.claims($0, at: now, checkExpiration: false) }
            let auth = idClaims?["https://api.openai.com/auth"] as? [String: Any]
            let accountID = tokens["account_id"] as? String ?? auth?["chatgpt_account_id"] as? String
            return try Self.credential(token: token, accountID: accountID,
                                       name: idClaims?["email"] as? String ?? claims["email"] as? String)
        case .claude:
            if let token = envToken(["CLAUDE_CODE_OAUTH_TOKEN"]) {
                let claims = try? Self.claims(token, at: now, checkExpiration: false)
                return try Self.credential(token: token, accountID: claims?["sub"] as? String)
            }
            let path = directory("CLAUDE_CONFIG_DIR", fallback: ".claude").appendingPathComponent(".credentials.json")
            let file = try fileRead(path)
            let data = try file ?? keychainRead("Claude Code-credentials", false)?.data
            guard let data else { return nil }
            let root = try Self.object(data)
            let oauth = root["claudeAiOauth"] as? [String: Any] ?? root["oauth"] as? [String: Any] ?? root
            guard let token = oauth["accessToken"] as? String ?? oauth["access_token"] as? String else {
                throw AIAccountBalanceError.invalidCredentials
            }
            if let rawExpiry = oauth["expiresAt"] ?? oauth["expires_at"], !(rawExpiry is NSNull) {
                guard let expiration = Self.expirationSeconds(rawExpiry), expiration > now.timeIntervalSince1970 + 60 else {
                    throw AIAccountBalanceError.credentialsExpired
                }
            }
            let claims = try? Self.claims(token, at: now, checkExpiration: false)
            return try Self.credential(token: token, accountID: claims?["sub"] as? String)
        case .gemini:
            guard let root = try geminiOAuthDocument() else { return nil }
            guard let token = root["access_token"] as? String else { throw AIAccountBalanceError.invalidCredentials }
            if let rawExpiry = root["expiry_date"], !(rawExpiry is NSNull) {
                guard let expiration = Self.expirationSeconds(rawExpiry), expiration > now.timeIntervalSince1970 + 60 else {
                    throw AIAccountBalanceError.credentialsExpired
                }
            }
            let claims = (root["id_token"] as? String).flatMap { try? Self.claims($0, at: now, checkExpiration: false) }
            return try Self.credential(token: token, accountID: claims?["sub"] as? String, name: claims?["email"] as? String)
        case .grok:
            if let token = envToken(["GROK_BEARER_TOKEN"]) {
                return try grokCredential(token: token, accountID: nil, email: nil, at: now)
            }
            guard let root = try json(directory("GROK_HOME", fallback: ".grok").appendingPathComponent("auth.json")) else { return nil }
            let entries = root.sorted { $0.key < $1.key }.compactMap { key, value -> (String, [String: Any])? in
                guard let value = value as? [String: Any], let token = value["key"] as? String, !token.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
                return (key, value)
            }
            guard let entry = (entries.first { $0.0.hasPrefix("https://auth.x.ai::") }
                ?? entries.first { $0.0 == "https://accounts.x.ai/sign-in" || $0.0.contains("/sign-in") }
                ?? entries.first)?.1,
                let rawToken = entry["key"] as? String else { throw AIAccountBalanceError.invalidCredentials }
            return try grokCredential(
                token: rawToken.trimmingCharacters(in: .whitespaces),
                accountID: entry["user_id"] as? String,
                email: entry["email"] as? String,
                at: now
            )
        case .kimi:
            guard environment["KIMI_CODE_BASE_URL"] == nil, environment["KIMI_CODE_OAUTH_HOST"] == nil,
                  environment["KIMI_OAUTH_HOST"] == nil else { throw AIAccountBalanceError.unsupportedLogin }
            let base = directory("KIMI_CODE_HOME", fallback: ".kimi-code")
            if let token = envToken(["KIMI_CODE_API_KEY"]) {
                var credential = try Self.credential(token: token, region: "cn")
                try attachKimiHeaders(&credential, base: base)
                return credential
            }
            let primaryPath = base.appendingPathComponent("credentials/kimi-code.json")
            let fallbackPath = environment["KIMI_CODE_HOME"] == nil
                ? home.appendingPathComponent(".kimi/credentials/kimi-code.json")
                : nil
            let document = try json(primaryPath) ?? fallbackPath.flatMap { try json($0) }
            guard let root = document else { return nil }
            guard let token = root["access_token"] as? String else { throw AIAccountBalanceError.invalidCredentials }
            if let rawExpiry = root["expires_at"], !(rawExpiry is NSNull) {
                guard let expiration = Self.expirationSeconds(rawExpiry), expiration > now.timeIntervalSince1970 + 60 else {
                    throw AIAccountBalanceError.credentialsExpired
                }
            }
            let claims = try? Self.claims(token, at: now, checkExpiration: false)
            var credential = try Self.credential(token: token, accountID: claims?["sub"] as? String, region: "cn")
            try attachKimiHeaders(&credential, base: base)
            return credential
        case .cursor, .grokBot:
            guard let cookie = try cursorCookie(now) else { return nil }
            return try Self.credential(token: cookie,
                                       accountID: cookie.components(separatedBy: "%3A%3A")[0].replacingOccurrences(of: "WorkosCursorSessionToken=", with: ""))
        case .workbuddy, .workbuddyAI:
            let realm = provider == .workbuddyAI ? "ai" : "cn"
            let filename = provider == .workbuddyAI ? "workbuddy-desktop-ai.info" : "workbuddy-desktop.info"
            let path = home.appendingPathComponent("Library/Application Support/CodeBuddyExtension/Data/Public/auth/" + filename)
            if try fileRead(URL(fileURLWithPath: path.path + ".logged-out")) != nil { return nil }
            guard let root = try json(path) else { return nil }
            guard let auth = root["auth"] as? [String: Any], let account = root["account"] as? [String: Any] else {
                throw AIAccountBalanceError.invalidCredentials
            }
            if auth["accessToken"] is [String: Any] { throw AIAccountBalanceError.credentialsUnavailable }
            guard let token = auth["accessToken"] as? String, let uid = account["uid"] as? String else {
                throw AIAccountBalanceError.invalidCredentials
            }
            if let rawExpiry = auth["expiresAt"], !(rawExpiry is NSNull) {
                guard let expiration = Self.expirationSeconds(rawExpiry), expiration > now.timeIntervalSince1970 + 30 else {
                    throw AIAccountBalanceError.credentialsExpired
                }
            }
            let domain = auth["domain"] as? String ?? ""
            let isInternational = domain == "workbuddy.ai" || domain.hasSuffix(".workbuddy.ai") || domain.hasSuffix("codebuddy.ai")
            guard domain.isEmpty || (realm == "ai" ? domain == "www.workbuddy.ai" || domain == "workbuddy.ai" : !isInternational) else {
                throw AIAccountBalanceError.invalidCredentials
            }
            let enterprise = account["enterpriseId"] as? String ?? ""
            var credential = try Self.credential(token: token, accountID: uid + ":" + enterprise,
                                                 name: account["name"] as? String, region: realm)
            credential.headers["X-User-Id"] = try Self.header(uid)
            if !enterprise.isEmpty {
                credential.headers["X-Enterprise-Id"] = try Self.header(enterprise)
                credential.headers["X-Tenant-Id"] = try Self.header(enterprise)
            }
            if !domain.isEmpty { credential.headers["X-Domain"] = try Self.header(domain) }
            if let department = (account["departmentFullName"] as? String ?? account["departmentInfo"] as? String)?
                .trimmingCharacters(in: .whitespacesAndNewlines),
               let safeDepartment = try? Self.header(department) {
                credential.headers["X-Department-Info"] = safeDepartment
            }
            return credential
        case .opencode:
            let dataRoot = environment["XDG_DATA_HOME"].flatMap { $0.hasPrefix("/") ? URL(fileURLWithPath: $0) : nil }
                ?? home.appendingPathComponent(".local/share")
            let root: [String: Any]
            if let content = environment["OPENCODE_AUTH_CONTENT"] {
                root = try Self.object(Data(content.utf8))
            } else {
                guard let document = try json(dataRoot.appendingPathComponent("opencode/auth.json")) else { return nil }
                root = document
            }
            guard let go = root["opencode-go"] as? [String: Any] else {
                if root["opencode"] != nil { throw AIAccountBalanceError.unsupportedLogin }
                return nil
            }
            guard go["type"] as? String == "api", let key = go["key"] as? String else {
                throw AIAccountBalanceError.invalidCredentials
            }
            return try Self.credential(token: key)
        case .zcode:
            return try zcodeCredential()
        case .zed:
            if let cookie = try websiteCookie(.zed) {
                var credential = try Self.credential(token: cookie)
                credential.isWebsiteCookie = true
                return credential
            }
            let settings = try fileRead(home.appendingPathComponent(".config/zed/settings.json")
                .resolvingSymlinksInPath()).map(Self.zedSettings)
            if let server = settings?["server_url"] as? String, server != "https://zed.dev" {
                throw AIAccountBalanceError.unsupportedLogin
            }
            if let service = settings?["credentials_url"] as? String, service != "https://zed.dev" {
                throw AIAccountBalanceError.unsupportedLogin
            }
            guard let item = try keychainRead("https://zed.dev", true) ?? keychainRead("https://zed.dev", false) else { return nil }
            guard let userID = item.account, let token = String(data: item.data, encoding: .utf8) else {
                throw AIAccountBalanceError.invalidCredentials
            }
            return try Self.credential(token: token, accountID: userID)
        default: return nil
        }
    }

    private func geminiOAuthDocument() throws -> [String: Any]? {
        if let override = environment["GEMINI_CLI_HOME"], override.hasPrefix("/") {
            let root = URL(fileURLWithPath: override)
            if let nested = try json(root.appendingPathComponent(".gemini/oauth_creds.json")) {
                return nested
            }
            return try json(root.appendingPathComponent("oauth_creds.json"))
        }
        return try json(home.appendingPathComponent(".gemini/oauth_creds.json"))
    }

    private func grokCredential(token: String, accountID: String?, email: String?, at now: Date) throws -> AIAccountBalanceCredential {
        let resolvedID: String?
        if token.split(separator: ".", omittingEmptySubsequences: false).count == 3 {
            let claims = try Self.claims(token, at: now)
            resolvedID = accountID ?? claims["sub"] as? String
        } else {
            resolvedID = accountID
        }
        return try Self.credential(token: token, accountID: resolvedID, name: email)
    }

    private func attachKimiHeaders(_ credential: inout AIAccountBalanceCredential, base: URL) throws {
        credential.headers = ["X-Msh-Platform": "kimi_code_cli", "X-Msh-Version": "1.0.0"]
        if let data = try fileRead(base.appendingPathComponent("device_id")),
           let value = String(data: data, encoding: .utf8) {
            credential.headers["X-Msh-Device-Id"] = try Self.header(value.trimmingCharacters(in: .whitespacesAndNewlines))
        }
    }

    /// Reads ZCode's `setting.json`, `config.json`, and in-memory AES-256-GCM `credentials.json`.
    /// A present credential store supersedes plaintext mirrors; undecryptable or missing entries fail closed.
    private func zcodeCredential() throws -> AIAccountBalanceCredential? {
        let baseRoot = environment["ZCODE_DATA_BASE_DIR"].flatMap { $0.hasPrefix("/") ? URL(fileURLWithPath: $0) : nil } ?? home
        let base = baseRoot.appendingPathComponent(".zcode/v2")
        guard let config = try json(base.appendingPathComponent("config.json")),
              let providers = config["provider"] as? [String: Any],
              let settings = try json(base.appendingPathComponent("setting.json")) else { return nil }
        let families: [String]
        if let rawDomain = settings["providerFamilyDomain"] as? String {
            let domain = rawDomain.trimmingCharacters(in: .whitespacesAndNewlines)
            guard domain == "zai" || domain == "bigmodel" else { return nil }
            families = [domain]
        } else {
            families = ["zai", "bigmodel"]
        }
        for family in families {
            let selection = settings["providerFamilyConnectionSelections"] as? [String: [String: Any]]
            let kind = (selection?[family]?["kind"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
            let providerID: String?
            if let kind, !kind.isEmpty {
                switch kind {
                case "start-plan":
                    providerID = "builtin:\(family)-start-plan"
                case "individual-coding-plan", "team-coding-plan":
                    providerID = "builtin:\(family)-coding-plan"
                default:
                    continue
                }
            } else {
                let selected = (settings["modelProviderFamilySelectedKeys"] as? [String: String])?[family]?
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if let selected, let prefix = ["coding-plan:", "preset:"].first(where: { selected.hasPrefix($0) }) {
                    providerID = String(selected.dropFirst(prefix.count)).trimmingCharacters(in: .whitespacesAndNewlines)
                } else {
                    providerID = nil
                }
            }
            let isStartPlan = providerID == "builtin:\(family)-start-plan"
            let isCodingPlan = providerID == "builtin:\(family)-coding-plan"
            guard let providerID, isStartPlan || isCodingPlan,
                  let provider = providers[providerID] as? [String: Any] else { continue }
            if provider["enabled"] as? Bool == false {
                let reason = (provider["systemDisabledReason"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                if reason.isEmpty || reason == "oauth_provider_inactive" { return nil }
            }
            let store = try json(base.appendingPathComponent("credentials.json"))
            let secret = zcodeCredentialSecret()
            if isStartPlan {
                let token: String
                if let store {
                    guard let encrypted = store["zcodejwttoken"] as? String,
                          let decrypted = Self.decryptZcodeCredential(encrypted, secret: secret) else {
                        throw AIAccountBalanceError.credentialsUnavailable
                    }
                    token = decrypted
                } else if let mirror = (provider["options"] as? [String: Any])?["apiKey"] as? String, !mirror.isEmpty {
                    token = mirror
                } else {
                    throw AIAccountBalanceError.invalidCredentials
                }
                var credential = try Self.credential(token: token, region: "start-plan")
                if let telemetry = try? json(base.appendingPathComponent("telemetry-state.json")),
                   let deviceMid = (telemetry["deviceMid"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
                   let safeMid = try? Self.header(deviceMid) {
                    credential.headers["X-Device-Mid"] = safeMid
                }
                return credential
            }
            let token: String
            if let store {
                guard let selectionKind = kind, !selectionKind.isEmpty,
                      let identity = Self.zcodeStoredProfileIdentity(store: store, family: family, secret: secret) else {
                    throw AIAccountBalanceError.credentialsUnavailable
                }
                let keyName = "account-provider:coding-plan:account:\(family)-\(selectionKind):account:\(Self.encodeURIComponent(identity)):api-key"
                guard let encrypted = store[keyName] as? String,
                      let decrypted = Self.decryptZcodeCredential(encrypted, secret: secret) else {
                    throw AIAccountBalanceError.credentialsUnavailable
                }
                token = decrypted
            } else {
                guard let mirror = (provider["options"] as? [String: Any])?["apiKey"] as? String else {
                    throw AIAccountBalanceError.invalidCredentials
                }
                token = mirror
            }
            return try Self.credential(token: token, region: family)
        }
        throw AIAccountBalanceError.unsupportedLogin
    }

    private func zcodeCredentialSecret() -> String {
        if let explicit = environment["ZCODE_CREDENTIAL_SECRET"]?.trimmingCharacters(in: .whitespacesAndNewlines), !explicit.isEmpty {
            return explicit
        }
        let user = username.isEmpty ? "unknown" : username
        return "zcode-credential-fallback:darwin:\(home.path):\(user)"
    }

    /// Reproduces ZCode's `enc:v1:<iv>.<tag>.<cipher>` AES-256-GCM decryption in memory without touching Keychain.
    static func decryptZcodeCredential(_ value: String, secret: String) -> String? {
        let prefix = "enc:v1:"
        guard value.hasPrefix(prefix) else { return nil }
        let parts = value.dropFirst(prefix.count).split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 3,
              let iv = decodeBase64URL(String(parts[0])), iv.count == 12,
              let tag = decodeBase64URL(String(parts[1])), tag.count == 16,
              let cipher = decodeBase64URL(String(parts[2])) else { return nil }
        let digest = SHA256.hash(data: Data(secret.utf8))
        let key = SymmetricKey(data: digest)
        guard let nonce = try? AES.GCM.Nonce(data: iv),
              let sealed = try? AES.GCM.SealedBox(nonce: nonce, ciphertext: cipher, tag: tag),
              let plainData = try? AES.GCM.open(sealed, using: key),
              let plain = String(data: plainData, encoding: .utf8), !plain.isEmpty else { return nil }
        return plain
    }

    private static func zcodeStoredProfileIdentity(store: [String: Any], family: String, secret: String) -> String? {
        guard let encrypted = store["oauth:\(family):user_info"] as? String,
              let profileText = decryptZcodeCredential(encrypted, secret: secret),
              let profile = try? object(Data(profileText.utf8)) else { return nil }
        let normalizedProfile = profile["id"] is String && profile["username"] is String && profile["displayName"] is String
        let rawIdentity = normalizedProfile ? (profile["id"] as? String) : (family == "zai" ? profile["user_id"] as? String : nil)
        let identity = rawIdentity?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return identity.isEmpty ? nil : identity
    }

    private static func encodeURIComponent(_ value: String) -> String {
        let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_.!~*'()")
        return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
    }

    private static func decodeBase64URL(_ value: String) -> Data? {
        guard !value.isEmpty else { return nil }
        var base64 = value.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        base64 += String(repeating: "=", count: (4 - base64.count % 4) % 4)
        return Data(base64Encoded: base64)
    }

    private func envToken(_ keys: [String]) -> String? {
        for key in keys {
            guard let raw = environment[key]?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else { continue }
            return raw
        }
        return nil
    }

    /// Accepts only absolute home overrides so relative environment values cannot redirect credential reads.
    private func directory(_ key: String, fallback: String) -> URL {
        if let path = environment[key], path.hasPrefix("/") { return URL(fileURLWithPath: path) }
        return home.appendingPathComponent(fallback)
    }

    private func json(_ path: URL) throws -> [String: Any]? {
        try fileRead(path).map(Self.object)
    }

    /// Normalizes Unix seconds, Unix milliseconds (> 20e9), or ISO-8601 expiry timestamps to Unix seconds.
    static func expirationSeconds(_ value: Any?) -> Double? {
        if let numeric = number(value) {
            return numeric > 20_000_000_000 ? numeric / 1_000 : numeric
        }
        if let text = value as? String {
            let fractional = ISO8601DateFormatter()
            fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = fractional.date(from: text) ?? ISO8601DateFormatter().date(from: text) {
                return date.timeIntervalSince1970
            }
        }
        return nil
    }

    /// Bounds credential headers to printable ASCII, rejecting control bytes before URLSession receives them.
    static func header(_ value: String) throws -> String {
        guard !value.isEmpty, value.utf8.count <= 32 * 1_024,
              value.unicodeScalars.allSatisfy({ (0x20...0x7e).contains($0.value) }) else {
            throw AIAccountBalanceError.invalidCredentials
        }
        return value
    }

    /// Validates authentication fields independently from the optional, bounded display name.
    private static func credential(token: String, accountID: String? = nil,
                                   name: String? = nil, region: String? = nil) throws -> AIAccountBalanceCredential {
        let token = try header(token)
        let accountID = try accountID.map(header)
        let name = name.map { String(String(String.UnicodeScalarView($0.unicodeScalars.filter {
            !CharacterSet.controlCharacters.contains($0) && !CharacterSet.newlines.contains($0)
        })).prefix(160)) }
        return .init(token: token, accountID: accountID, accountName: name, region: region)
    }

    /// Decodes local JWT metadata and optionally checks expiry with a safety margin; this does not verify signatures.
    /// Claims can identify an account but cannot establish authentication or authorize another host.
    static func claims(_ token: String, at now: Date, checkExpiration: Bool = true) throws -> [String: Any] {
        let token = try header(token)
        let parts = token.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 3 else { throw AIAccountBalanceError.invalidCredentials }
        var payload = String(parts[1]).replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        payload += String(repeating: "=", count: (4 - payload.count % 4) % 4)
        guard let data = Data(base64Encoded: payload) else { throw AIAccountBalanceError.invalidCredentials }
        let claims = try object(data)
        if checkExpiration {
            guard let expiry = number(claims["exp"]), expiry > now.timeIntervalSince1970 + 60 else {
                throw AIAccountBalanceError.credentialsExpired
            }
        }
        return claims
    }

    /// Requires a bounded JSON object so malformed or oversized input cannot become a missing quota.
    static func object(_ data: Data) throws -> [String: Any] {
        guard data.count <= 1_024 * 1_024, let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw AIAccountBalanceError.invalidResponse
        }
        return root
    }

    /// Reads the two host overrides from Zed's JSONC settings without interpreting unrelated configuration.
    private static func zedSettings(_ data: Data) throws -> [String: Any] {
        guard data.count <= 1_024 * 1_024 else { throw AIAccountBalanceError.invalidResponse }
        struct Settings: Decodable {
            var server_url: String?
            var credentials_url: String?
        }
        let decoder = JSONDecoder()
        decoder.allowsJSON5 = true
        guard let settings = try? decoder.decode(Settings.self, from: data) else { throw AIAccountBalanceError.invalidResponse }
        return ["server_url": settings.server_url, "credentials_url": settings.credentials_url].compactMapValues { $0 }
    }

    /// Rejects booleans and nonfinite values even though Foundation bridges JSON booleans as NSNumber.
    static func number(_ value: Any?) -> Double? {
        if let value = value as? NSNumber, CFGetTypeID(value) != CFBooleanGetTypeID() {
            return value.doubleValue.isFinite ? value.doubleValue : nil
        }
        if let value = value as? String, !value.isEmpty, let number = Double(value), number.isFinite { return number }
        return nil
    }

    /// Refuses final symlinks and nonregular files, using nonblocking open so a FIFO cannot stall polling.
    /// The 1 MiB limit is enforced again while reading to cover file growth, and every descriptor is closed.
    static func readRegularFile(_ url: URL) throws -> Data? {
        let descriptor = open(url.path, O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC)
        guard descriptor >= 0 else {
            if errno == ENOENT { return nil }
            throw AIAccountBalanceError.credentialsUnavailable
        }
        defer { close(descriptor) }
        var info = stat()
        guard fstat(descriptor, &info) == 0, (info.st_mode & S_IFMT) == S_IFREG,
              info.st_size >= 0, info.st_size <= 1_024 * 1_024 else {
            throw AIAccountBalanceError.credentialsUnavailable
        }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 16 * 1_024)
        while true {
            let count = read(descriptor, &buffer, buffer.count)
            guard count >= 0 else { throw AIAccountBalanceError.credentialsUnavailable }
            if count == 0 { return data }
            guard data.count + count <= 1_024 * 1_024 else { throw AIAccountBalanceError.credentialsUnavailable }
            data.append(contentsOf: buffer.prefix(count))
        }
    }
}
