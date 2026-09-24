// Adapted from upstream provider credential readers; see Resources/ThirdPartyLicenses/AIQuota-LICENSE.txt.
// Modified for explicit Zisla configuration, bounded reads and read-only SQLite access.
import Foundation
import Darwin
import LocalAuthentication
import Security
import SQLite3
import ZislaCore

struct AIQuotaLocalLogin: Sendable {
    var home = FileManager.default.homeDirectoryForCurrentUser

    func read(_ configuration: AIQuotaConfiguration, now: Date) throws -> (AIQuotaCredential, String?) {
        let path: String
        switch configuration.provider {
        case .claudeCode: path = ".claude/.credentials.json"
        case .codex: path = ".codex/auth.json"
        case .cursor, .grokBot: path = "Library/Application Support/Cursor/User/globalStorage/state.vscdb"
        case .grok: path = ".grok/auth.json"
        case .openCodeGo: path = ".local/share/opencode/auth.json"
        case .commandCode: path = ".commandcode/auth.json"
        default: throw AIQuotaError.credentialUnavailable
        }
        let url = configuration.localPath.isEmpty ? home.appendingPathComponent(path)
            : URL(fileURLWithPath: (configuration.localPath as NSString).expandingTildeInPath)
        if configuration.provider == .cursor || configuration.provider == .grokBot {
            let token = try Self.cursorToken(url)
            return (AIQuotaCredential(token: try Self.cursorCookie(token, now: now)), nil)
        }
        let root: [String: Any]
        if configuration.provider == .claudeCode, configuration.localPath.isEmpty,
           let keychain = Self.claudeKeychain() { root = try AIQuotaResponseParser.object(keychain) }
        else { root = try AIQuotaResponseParser.object(Self.readFile(url)) }
        switch configuration.provider {
        case .claudeCode:
            guard let oauth = root["claudeAiOauth"] as? [String: Any], let token = oauth["accessToken"] as? String else { throw AIQuotaError.credentialUnavailable }
            if let expiry = AIQuotaResponseParser.number(oauth["expiresAt"]), expiry / 1_000 <= now.timeIntervalSince1970 { throw AIQuotaError.credentialRejected }
            return (AIQuotaCredential(token: token), nil)
        case .codex:
            guard let tokens = root["tokens"] as? [String: Any], let token = tokens["access_token"] as? String else { throw AIQuotaError.credentialUnavailable }
            return (AIQuotaCredential(token: token), tokens["account_id"] as? String)
        case .openCodeGo:
            guard let token = (root["opencode-go"] as? [String: Any])?["key"] as? String else { throw AIQuotaError.credentialUnavailable }
            return (AIQuotaCredential(token: token), nil)
        case .commandCode:
            guard let token = root["apiKey"] as? String else { throw AIQuotaError.credentialUnavailable }
            return (AIQuotaCredential(token: token), nil)
        case .grok:
            let entries = root.values.compactMap { value -> (String, Date)? in
                guard let entry = value as? [String: Any], let token = entry["key"] as? String else { return nil }
                let expiry = AIQuotaResponseParser.date(entry["expires_at"])
                guard expiry.map({ $0 > now }) ?? true else { return nil }
                return (token, expiry ?? .distantPast)
            }
            guard let newest = entries.max(by: { $0.1 < $1.1 }) else { throw AIQuotaError.credentialUnavailable }
            return (AIQuotaCredential(token: newest.0), nil)
        default: throw AIQuotaError.credentialUnavailable
        }
    }

    static func readFile(_ url: URL) throws -> Data {
        let descriptor = Darwin.open(url.path, O_RDONLY | O_NONBLOCK | O_CLOEXEC)
        guard descriptor >= 0 else { throw AIQuotaError.credentialUnavailable }
        let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        defer { try? handle.close() }
        var status = stat()
        guard fstat(descriptor, &status) == 0, (status.st_mode & S_IFMT) == S_IFREG else {
            throw AIQuotaError.credentialUnavailable
        }
        do {
            let data = try handle.read(upToCount: 1_024 * 1_024 + 1) ?? Data()
            guard data.count <= 1_024 * 1_024 else { throw AIQuotaError.responseTooLarge }
            return data
        } catch let error as AIQuotaError { throw error }
        catch { throw AIQuotaError.credentialUnavailable }
    }

    private static func claudeKeychain() -> Data? {
        let context = LAContext()
        context.interactionNotAllowed = true
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "Claude Code-credentials",
            kSecMatchLimit as String: kSecMatchLimitOne,
            kSecReturnData as String: true,
            kSecUseAuthenticationContext as String: context,
        ]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess else { return nil }
        return result as? Data
    }

    static func cursorCookie(_ token: String, now: Date) throws -> String {
        _ = try AIQuotaRequestBuilder.header(token)
        let parts = token.split(separator: ".")
        guard parts.count == 3 else { throw AIQuotaError.credentialInvalid }
        var encoded = parts[1].replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        encoded += String(repeating: "=", count: (4 - encoded.count % 4) % 4)
        guard let data = Data(base64Encoded: encoded) else { throw AIQuotaError.credentialInvalid }
        let claims = try AIQuotaResponseParser.object(data)
        guard let subject = claims["sub"] as? String,
              let account = subject.split(separator: "|").last, !account.isEmpty,
              let expiry = AIQuotaResponseParser.number(claims["exp"]), expiry > now.timeIntervalSince1970 + 60 else {
            throw AIQuotaError.credentialRejected
        }
        return try AIQuotaRequestBuilder.cookie("WorkosCursorSessionToken=\(account)%3A%3A\(token)", provider: .cursor)
    }

    static func cursorToken(_ url: URL) throws -> String {
        let descriptor = Darwin.open(url.path, O_RDONLY | O_NONBLOCK | O_CLOEXEC)
        guard descriptor >= 0 else { throw AIQuotaError.credentialUnavailable }
        var status = stat()
        let isRegular = fstat(descriptor, &status) == 0 && (status.st_mode & S_IFMT) == S_IFREG
        Darwin.close(descriptor)
        guard isRegular else { throw AIQuotaError.credentialUnavailable }
        var database: OpaquePointer?
        guard sqlite3_open_v2(url.path, &database, SQLITE_OPEN_READONLY | SQLITE_OPEN_NOMUTEX, nil) == SQLITE_OK else {
            sqlite3_close(database)
            throw AIQuotaError.credentialUnavailable
        }
        defer { sqlite3_close(database) }
        sqlite3_busy_timeout(database, 1_000)
        sqlite3_limit(database, SQLITE_LIMIT_LENGTH, 32_768)
        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }
        guard sqlite3_prepare_v2(database, "SELECT value FROM ItemTable WHERE key = 'cursorAuth/accessToken' LIMIT 1", -1, &statement, nil) == SQLITE_OK else { throw AIQuotaError.credentialUnavailable }
        guard sqlite3_step(statement) == SQLITE_ROW else { throw AIQuotaError.credentialUnavailable }
        let count = Int(sqlite3_column_bytes(statement, 0))
        guard count > 0, count <= 32_768, let bytes = sqlite3_column_blob(statement, 0) else { throw AIQuotaError.credentialUnavailable }
        let data = Data(bytes: bytes, count: count)
        let encoding: String.Encoding = data.count >= 2 && data[1] == 0 ? .utf16LittleEndian : .utf8
        guard let token = String(data: data, encoding: encoding) else { throw AIQuotaError.credentialUnavailable }
        return token
    }
}
