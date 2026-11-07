import CommonCrypto
import CoreFoundation
import Darwin
import Foundation
import LocalAuthentication
import Security

/// Adapted from CodexBar's CursorAppAuth and ChromiumSafeStorage (MIT).
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
        allowsRead: (CFTypeRef) -> Bool = { keychainItemAllowsRead($0) },
        uiFailPolicy: CFString? = keychainUIFailPolicy
    ) -> Data? {
        guard let uiFailPolicy else { return nil }
        let context = LAContext()
        context.interactionNotAllowed = true
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
            kSecAttrAccount as String: account, kSecMatchLimit as String: kSecMatchLimitOne,
            kSecUseAuthenticationContext as String: context,
            kSecUseAuthenticationUI as String: uiFailPolicy,
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

    static func keychainItemAllowsRead(
        _ item: CFTypeRef,
        executablePath: String? = Bundle.main.executablePath,
        symbol: (String) -> UnsafeMutableRawPointer? = { name in
            guard let securityFramework else { return nil }
            return dlsym(securityFramework, name)
        }
    ) -> Bool {
        guard let getTypeIDSymbol = symbol("SecKeychainItemGetTypeID"),
              let copyAccessSymbol = symbol("SecKeychainItemCopyAccess"),
              let copyACLListSymbol = symbol("SecAccessCopyMatchingACLList"),
              let copyContentsSymbol = symbol("SecACLCopyContents"),
              let path = executablePath else { return false }
        let getTypeID = unsafeBitCast(getTypeIDSymbol, to: KeychainItemTypeID.self)
        guard CFGetTypeID(item) == getTypeID() else { return false }
        let copyAccess = unsafeBitCast(copyAccessSymbol, to: KeychainItemCopyAccess.self)
        let copyACLList = unsafeBitCast(copyACLListSymbol, to: AccessCopyMatchingACLList.self)
        let copyContents = unsafeBitCast(copyContentsSymbol, to: ACLCopyContents.self)
        var accessReference: Unmanaged<SecAccess>?
        let accessStatus = copyAccess(item, &accessReference)
        let access = accessReference?.takeRetainedValue()
        guard accessStatus == errSecSuccess, let access,
              let rawACLs = copyACLList(access, kSecACLAuthorizationDecrypt)?.takeRetainedValue(),
              let acls = rawACLs as? [SecACL] else { return false }
        for acl in acls {
            var applicationsReference: Unmanaged<CFArray>?
            var descriptionReference: Unmanaged<CFString>?
            var selector = SecKeychainPromptSelector()
            let status = copyContents(acl, &applicationsReference, &descriptionReference, &selector)
            let applications = applicationsReference?.takeRetainedValue()
            _ = descriptionReference?.takeRetainedValue()
            guard status == errSecSuccess, selector.rawValue == 0 else { continue }
            guard let applications else { return true }
            guard let validateSymbol = symbol("SecTrustedApplicationValidateWithPath") else { continue }
            let validate = unsafeBitCast(validateSymbol, to: TrustedApplicationValidator.self)
            if let trusted = applications as? [SecTrustedApplication], trusted.contains(where: { application in
                path.withCString { validate(application, $0) == errSecSuccess }
            }) { return true }
        }
        return false
    }

    // Legacy ACLs can still prompt with LAContext alone; retain the explicit UI-fail policy.
    private static var keychainUIFailPolicy: CFString? {
        guard let securityFramework,
              let symbol = dlsym(securityFramework, "kSecUseAuthenticationUIFail") else { return nil }
        return symbol.assumingMemoryBound(to: CFString?.self).pointee
    }

    // Legacy ACL inspection has no SecItem equivalent. Resolve its C ABI without deprecated imports.
    private typealias KeychainItemTypeID = @convention(c) () -> CFTypeID
    private typealias KeychainItemCopyAccess = @convention(c) (
        CFTypeRef, UnsafeMutablePointer<Unmanaged<SecAccess>?>) -> OSStatus
    private typealias AccessCopyMatchingACLList = @convention(c) (SecAccess, CFTypeRef) -> Unmanaged<CFArray>?
    private typealias ACLCopyContents = @convention(c) (
        SecACL, UnsafeMutablePointer<Unmanaged<CFArray>?>, UnsafeMutablePointer<Unmanaged<CFString>?>,
        UnsafeMutablePointer<SecKeychainPromptSelector>) -> OSStatus
    private typealias TrustedApplicationValidator = @convention(c) (SecTrustedApplication, UnsafePointer<CChar>) -> OSStatus
    private nonisolated(unsafe) static let securityFramework = dlopen(
        "/System/Library/Frameworks/Security.framework/Security", RTLD_NOW
    )
}
