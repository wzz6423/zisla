import CommonCrypto
import CoreFoundation
import Darwin
import Foundation
import LocalAuthentication
import Security

/// Adapted from CodexBar's CursorAppAuth, MuseCredentials and ChromiumSafeStorage (MIT).
struct AISubscriptionCredentials: Sendable {
    let home: URL
    var environment: [String: String] = ProcessInfo.processInfo.environment
    var keychainRead: @Sendable (String, String) -> Data? = { readKeychainWithoutPrompt(service: $0, account: $1) }

    func cursorCookie(now: Date) throws -> String? {
        let database = CursorSessionActivityDetector.defaultUserDirectory(home: home)
            .appendingPathComponent("globalStorage/state.vscdb")
        let row = DesktopAIStorage.rows(at: database, sql: "SELECT value FROM ItemTable WHERE key = 'cursorAuth/accessToken' LIMIT 1").first
        let configHome = environment["XDG_CONFIG_HOME"].flatMap { $0.hasPrefix("/") ? URL(fileURLWithPath: $0) : nil }
            ?? home.appendingPathComponent(".config")
        let cliFile = configHome.appendingPathComponent("cursor/auth.json")
        let rawToken = row?["value"] as? String ?? DesktopAIStorage.json(at: cliFile)?["accessToken"] as? String
        guard var token = rawToken else { return nil }
        guard token.utf8.count <= 32 * 1_024 else { throw AISubscriptionUsageError.invalidCredentials }
        if token.hasPrefix("cursor-safe-storage:") {
            let prefix = "cursor-safe-storage:v1:"
            guard token.hasPrefix(prefix), let encrypted = Data(base64Encoded: String(token.dropFirst(prefix.count))),
                  let passwordData = keychainRead("Cursor Safe Storage", "Cursor"),
                  let password = String(data: passwordData, encoding: .utf8),
                  let decoded = Self.decryptCursorToken(encrypted, password: password) else {
                throw AISubscriptionUsageError.invalidCredentials
            }
            token = decoded
        }
        return try Self.cursorCookie(token: token, now: now)
    }

    static func cursorCookie(token: String, now: Date) throws -> String {
        let parts = token.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 3, token.utf8.count <= 16 * 1_024,
              token.unicodeScalars.allSatisfy({ $0.isASCII && (CharacterSet.alphanumerics.contains($0) || "-_.".unicodeScalars.contains($0)) }) else {
            throw AISubscriptionUsageError.invalidCredentials
        }
        var payload = String(parts[1]).replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        payload += String(repeating: "=", count: (4 - payload.count % 4) % 4)
        guard let data = Data(base64Encoded: payload),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let subject = json["sub"] as? String,
              let userID = subject.split(separator: "|").last,
              !userID.isEmpty,
              userID.unicodeScalars.allSatisfy({ $0.isASCII && (CharacterSet.alphanumerics.contains($0) || "._-".unicodeScalars.contains($0)) }),
              let expiration = json["exp"] as? NSNumber, CFGetTypeID(expiration) != CFBooleanGetTypeID(),
              expiration.doubleValue.isFinite,
              expiration.doubleValue > now.timeIntervalSince1970 + 60 else {
            throw AISubscriptionUsageError.invalidCredentials
        }
        return "WorkosCursorSessionToken=\(userID)%3A%3A\(token)"
    }

    func museToken() throws -> String? {
        let authFile = environment["MUSE_AUTH_PATH"].flatMap { $0.hasPrefix("/") ? URL(fileURLWithPath: $0) : nil }
            ?? home.appendingPathComponent(".config/muse/auth.json")
        let auth = DesktopAIStorage.json(at: authFile)
        let meta = (auth?["providers"] as? [String: Any])?["meta"] as? [String: Any]
        guard let meta else { return nil }
        let inline = (meta["access_token"] as? String).flatMap { $0.isEmpty ? nil : $0 }
        var token = inline
        if token == nil, (meta["mechanism"] as? String)?.lowercased() == "oauth",
           let data = keychainRead("ai.meta.dev.credentials", "meta"),
           let payload = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            token = payload["access_token"] as? String
        }
        guard let token, token.hasPrefix("dca:"), token.utf8.count > 4, token.utf8.count <= 16 * 1_024,
              token.unicodeScalars.allSatisfy({ (0x21...0x7E).contains($0.value) }) else {
            throw AISubscriptionUsageError.invalidCredentials
        }
        return token
    }

    static func decryptCursorToken(_ encrypted: Data, password: String) -> String? {
        guard encrypted.starts(with: Data("v10".utf8)), encrypted.count > 3,
              (encrypted.count - 3).isMultiple(of: kCCBlockSizeAES128) else { return nil }
        let salt = Data("saltysalt".utf8)
        var key = Data(count: kCCKeySizeAES128)
        let keyLength = key.count
        let derivation = key.withUnsafeMutableBytes { keyBytes in
            password.utf8CString.withUnsafeBytes { passBytes in
                salt.withUnsafeBytes { saltBytes in
                    CCKeyDerivationPBKDF(CCPBKDFAlgorithm(kCCPBKDF2), passBytes.bindMemory(to: Int8.self).baseAddress,
                        passBytes.count - 1, saltBytes.bindMemory(to: UInt8.self).baseAddress, salt.count,
                        CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA1), 1003,
                        keyBytes.bindMemory(to: UInt8.self).baseAddress, keyLength)
                }
            }
        }
        guard derivation == kCCSuccess else { return nil }
        let payload = Data(encrypted.dropFirst(3))
        let iv = Data(repeating: 0x20, count: kCCBlockSizeAES128)
        var output = Data(count: payload.count + kCCBlockSizeAES128)
        let capacity = output.count
        var count = 0
        let status = output.withUnsafeMutableBytes { out in
            payload.withUnsafeBytes { bytes in
                key.withUnsafeBytes { keyBytes in
                    iv.withUnsafeBytes { ivBytes in
                        CCCrypt(CCOperation(kCCDecrypt), CCAlgorithm(kCCAlgorithmAES), CCOptions(kCCOptionPKCS7Padding),
                            keyBytes.baseAddress, key.count, ivBytes.baseAddress, bytes.baseAddress, payload.count,
                            out.baseAddress, capacity, &count)
                    }
                }
            }
        }
        guard status == kCCSuccess else { return nil }
        output.count = count
        return String(data: output, encoding: .utf8)
    }

    static func readKeychainWithoutPrompt(
        service: String, account: String,
        copyMatching: (CFDictionary) -> (OSStatus, CFTypeRef?) = { query in
            var result: CFTypeRef?
            let status = SecItemCopyMatching(query, &result)
            return (status, result)
        },
        allowsRead: (CFTypeRef) -> Bool = { item in
            guard CFGetTypeID(item) == SecKeychainItemGetTypeID() else { return false }
            return keychainItemAllowsRead(unsafeDowncast(item, to: SecKeychainItem.self))
        }
    ) -> Data? {
        let context = LAContext()
        context.interactionNotAllowed = true
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
            kSecAttrAccount as String: account, kSecMatchLimit as String: kSecMatchLimitOne,
            kSecUseAuthenticationContext as String: context,
            kSecUseAuthenticationUI as String: kSecUseAuthenticationUIFail,
            kSecReturnAttributes as String: true, kSecReturnRef as String: true,
        ]
        let (status, reference) = copyMatching(query as CFDictionary)
        guard status == errSecSuccess,
              let attributes = reference as? [String: Any], let value = attributes[kSecValueRef as String],
              allowsRead(value as AnyObject) else { return nil }
        query.removeValue(forKey: kSecReturnAttributes as String)
        query.removeValue(forKey: kSecReturnRef as String)
        query[kSecReturnData as String] = true
        query[kSecMatchItemList as String] = [value]
        let (readStatus, result) = copyMatching(query as CFDictionary)
        guard readStatus == errSecSuccess else { return nil }
        return result as? Data
    }

    private static func keychainItemAllowsRead(_ item: SecKeychainItem) -> Bool {
        var access: SecAccess?
        guard SecKeychainItemCopyAccess(item, &access) == errSecSuccess, let access,
              let rawACLs = SecAccessCopyMatchingACLList(access, kSecACLAuthorizationDecrypt),
              let acls = rawACLs as? [SecACL],
              let path = Bundle.main.executablePath else { return false }
        for acl in acls {
            var applications: CFArray?
            var description: CFString?
            var selector = SecKeychainPromptSelector()
            guard SecACLCopyContents(acl, &applications, &description, &selector) == errSecSuccess,
                  selector.rawValue == 0 else { continue }
            guard let applications else { return true }
            guard let framework = securityFramework,
                  let symbol = dlsym(framework, "SecTrustedApplicationValidateWithPath") else { continue }
            let validate = unsafeBitCast(symbol, to: TrustedApplicationValidator.self)
            if let trusted = applications as? [SecTrustedApplication], trusted.contains(where: { application in
                path.withCString { validate(application, $0) == errSecSuccess }
            }) { return true }
        }
        return false
    }

    private typealias TrustedApplicationValidator = @convention(c) (SecTrustedApplication, UnsafePointer<CChar>) -> OSStatus
    private nonisolated(unsafe) static let securityFramework = dlopen(
        "/System/Library/Frameworks/Security.framework/Security", RTLD_NOW
    )
}
