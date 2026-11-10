import CoreFoundation
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

    func identity(provider: AIProvider) -> String {
        DesktopAIStorage.identity([provider.rawValue, region ?? "", accountID ?? token])
    }
}

enum AIAccountBalanceError: Error, Equatable {
    case credentialsUnavailable, credentialsExpired, invalidCredentials, invalidResponse
    case httpStatus(Int), unsupportedLogin, noQuota
}

// Native read-only adaptation of CodexBar 7447bc77 and token-monitor 235a77c3 (MIT).
struct AIAccountBalanceCredentials: Sendable {
    let home: URL
    var environment: [String: String] = ProcessInfo.processInfo.environment
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

    func load(for provider: AIProvider, at now: Date, qoderRegion: AIAccountBalanceQoderRegion = .global) throws -> AIAccountBalanceCredential? {
        switch provider {
        case .copilot:
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
                guard let first = values.first else { return nil }
                guard values.allSatisfy({ $0.accountID != nil && $0.accountID == first.accountID }) || values.count == 1 else {
                    throw AIAccountBalanceError.credentialsUnavailable
                }
                return first
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
            let path = directory("CLAUDE_CONFIG_DIR", fallback: ".claude").appendingPathComponent(".credentials.json")
            let file = try fileRead(path)
            let data = try file ?? keychainRead("Claude Code-credentials", false)?.data
            guard let data else { return nil }
            let root = try Self.object(data)
            guard let oauth = root["claudeAiOauth"] as? [String: Any], let token = oauth["accessToken"] as? String else {
                throw AIAccountBalanceError.invalidCredentials
            }
            if let expiration = Self.number(oauth["expiresAt"]), expiration <= (now.timeIntervalSince1970 + 60) * 1_000 {
                throw AIAccountBalanceError.credentialsExpired
            }
            let claims = try? Self.claims(token, at: now)
            return try Self.credential(token: token, accountID: claims?["sub"] as? String)
        case .gemini:
            guard let root = try json(home.appendingPathComponent(".gemini/oauth_creds.json")) else { return nil }
            guard let token = root["access_token"] as? String else { throw AIAccountBalanceError.invalidCredentials }
            guard let expiration = Self.number(root["expiry_date"]), expiration > (now.timeIntervalSince1970 + 60) * 1_000 else {
                throw AIAccountBalanceError.credentialsExpired
            }
            let claims = (root["id_token"] as? String).flatMap { try? Self.claims($0, at: now, checkExpiration: false) }
            return try Self.credential(token: token, accountID: claims?["sub"] as? String, name: claims?["email"] as? String)
        case .grok:
            guard let root = try json(directory("GROK_HOME", fallback: ".grok").appendingPathComponent("auth.json")) else { return nil }
            let entries = root.sorted { $0.key < $1.key }.compactMap { key, value -> (String, [String: Any])? in
                guard let value = value as? [String: Any], let token = value["key"] as? String, !token.isEmpty else { return nil }
                return (key, value)
            }
            guard let entry = (entries.first { $0.0.hasPrefix("https://auth.x.ai::") }
                ?? entries.first { $0.0 == "https://accounts.x.ai/sign-in" })?.1,
                let token = entry["key"] as? String else { throw AIAccountBalanceError.invalidCredentials }
            let claims = try Self.claims(token, at: now)
            return try Self.credential(token: token, accountID: entry["user_id"] as? String ?? claims["sub"] as? String,
                name: entry["email"] as? String)
        case .kimi:
            guard environment["KIMI_CODE_BASE_URL"] == nil, environment["KIMI_CODE_OAUTH_HOST"] == nil,
                  environment["KIMI_OAUTH_HOST"] == nil else { throw AIAccountBalanceError.unsupportedLogin }
            let base = directory("KIMI_CODE_HOME", fallback: ".kimi-code")
            guard let root = try json(base.appendingPathComponent("credentials/kimi-code.json")) else { return nil }
            guard let token = root["access_token"] as? String else { throw AIAccountBalanceError.invalidCredentials }
            guard let expiration = Self.number(root["expires_at"]), expiration > now.timeIntervalSince1970 + 60 else {
                throw AIAccountBalanceError.credentialsExpired
            }
            let claims = try? Self.claims(token, at: now)
            var credential = try Self.credential(token: token, accountID: claims?["sub"] as? String, region: "cn")
            credential.headers = ["X-Msh-Platform": "kimi_code_cli", "X-Msh-Version": "1.0.0"]
            if let data = try fileRead(base.appendingPathComponent("device_id")),
               let value = String(data: data, encoding: .utf8) {
                credential.headers["X-Msh-Device-Id"] = try Self.header(value.trimmingCharacters(in: .whitespacesAndNewlines))
            }
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
            if let expiration = Self.number(auth["expiresAt"]), expiration <= (now.timeIntervalSince1970 + 30) * 1_000 {
                throw AIAccountBalanceError.credentialsExpired
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
            let settings = try fileRead(home.appendingPathComponent(".config/zed/settings.json")).map(Self.zedSettings)
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

    private func zcodeCredential() throws -> AIAccountBalanceCredential? {
        let base = home.appendingPathComponent(".zcode/v2")
        guard let config = try json(base.appendingPathComponent("config.json")),
              let providers = config["provider"] as? [String: Any],
              let settings = try json(base.appendingPathComponent("settings.json")) else { return nil }
        for family in ["zai", "bigmodel"] {
            let selection = settings["providerFamilyConnectionSelections"] as? [String: [String: Any]]
            let kind = selection?[family]?["kind"] as? String
            let providerID: String?
            if let kind {
                if kind == "start-plan" { throw AIAccountBalanceError.credentialsUnavailable }
                guard kind == "individual-coding-plan" || kind == "team-coding-plan" else { continue }
                providerID = "builtin:\(family)-coding-plan"
            } else {
                let selected = (settings["modelProviderFamilySelectedKeys"] as? [String: String])?[family]
                providerID = selected?.components(separatedBy: ":").dropFirst().joined(separator: ":")
            }
            guard let providerID, providerID == "builtin:\(family)-coding-plan",
                  let provider = providers[providerID] as? [String: Any] else { continue }
            if provider["enabled"] as? Bool == false,
               (provider["systemDisabledReason"] == nil || provider["systemDisabledReason"] as? String == "oauth_provider_inactive") {
                return nil
            }
            let store = try json(base.appendingPathComponent("credentials.json"))
            // A store supersedes plaintext mirrors; sealed entries require the owning app's access.
            if store != nil { throw AIAccountBalanceError.credentialsUnavailable }
            guard let token = (provider["options"] as? [String: Any])?["apiKey"] as? String else {
                throw AIAccountBalanceError.invalidCredentials
            }
            return try Self.credential(token: token, region: family)
        }
        throw AIAccountBalanceError.unsupportedLogin
    }

    private func directory(_ key: String, fallback: String) -> URL {
        if let path = environment[key], path.hasPrefix("/") { return URL(fileURLWithPath: path) }
        return home.appendingPathComponent(fallback)
    }

    private func json(_ path: URL) throws -> [String: Any]? {
        try fileRead(path).map(Self.object)
    }

    static func header(_ value: String) throws -> String {
        guard !value.isEmpty, value.utf8.count <= 32 * 1_024,
              value.unicodeScalars.allSatisfy({ (0x20...0x7e).contains($0.value) }) else {
            throw AIAccountBalanceError.invalidCredentials
        }
        return value
    }

    private static func credential(token: String, accountID: String? = nil,
                                   name: String? = nil, region: String? = nil) throws -> AIAccountBalanceCredential {
        let token = try header(token)
        let accountID = try accountID.map(header)
        let name = name.map { String(String(String.UnicodeScalarView($0.unicodeScalars.filter {
            !CharacterSet.controlCharacters.contains($0) && !CharacterSet.newlines.contains($0)
        })).prefix(160)) }
        return .init(token: token, accountID: accountID, accountName: name, region: region)
    }

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

    static func object(_ data: Data) throws -> [String: Any] {
        guard data.count <= 1_024 * 1_024, let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw AIAccountBalanceError.invalidResponse
        }
        return root
    }

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

    static func number(_ value: Any?) -> Double? {
        if let value = value as? NSNumber, CFGetTypeID(value) != CFBooleanGetTypeID() {
            return value.doubleValue.isFinite ? value.doubleValue : nil
        }
        if let value = value as? String, !value.isEmpty, let number = Double(value), number.isFinite { return number }
        return nil
    }

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
