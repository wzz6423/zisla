import CoreFoundation
import Darwin
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
                    #expect(values[kSecUseAuthenticationUI] as? String == "u_AuthUIF")
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
                #expect(values[kSecUseAuthenticationUI] as? String == "u_AuthUIF")
                if calls == 1 { return (errSecSuccess, [kSecValueRef as String: "fixture-ref"] as CFDictionary) }
                #expect(values[kSecReturnData] as? Bool == true)
                #expect(values[kSecReturnRef] == nil)
                #expect(values[kSecMatchItemList] as? [String] == ["fixture-ref"])
                return (errSecSuccess, expected as CFData)
            }, allowsRead: { _ in true })
        #expect(result == expected && calls == 2)
    }

    @Test func keychainReadRejectsMissingUIPolicyBeforeInspectingCredentials() {
        let result = AISubscriptionCredentials.readKeychainWithoutPrompt(service: "fixture", account: "fixture",
            copyMatching: { _ in Issue.record("Missing UI-fail policy must not query Keychain"); return (errSecSuccess, nil) },
            allowsRead: { _ in Issue.record("Missing UI-fail policy must not inspect ACL"); return true },
            uiFailPolicy: nil)
        #expect(result == nil)
    }

    @Test func keychainReadRejectsInvalidReferencesAndSecondReadFailures() {
        for result in [nil, "invalid-result" as CFString?, [:] as CFDictionary?] as [CFTypeRef?] {
            #expect(AISubscriptionCredentials.readKeychainWithoutPrompt(service: "fixture", account: "fixture",
                copyMatching: { _ in (errSecSuccess, result) },
                allowsRead: { _ in Issue.record("Invalid preflight must not inspect ACL"); return true }) == nil)
        }
        #expect(AISubscriptionCredentials.readKeychainWithoutPrompt(service: "fixture", account: "fixture",
            copyMatching: { _ in (errSecSuccess, [kSecValueRef as String: "invalid-reference"] as CFDictionary) }) == nil)
        for status in [errSecInteractionNotAllowed, errSecAuthFailed] {
            var calls = 0
            #expect(AISubscriptionCredentials.readKeychainWithoutPrompt(service: "fixture", account: "fixture",
                copyMatching: { _ in
                    calls += 1
                    return calls == 1
                        ? (errSecSuccess, [kSecValueRef as String: "fixture-ref"] as CFDictionary)
                        : (status, Data("fixture-secret".utf8) as CFData)
                }, allowsRead: { _ in true }) == nil)
            #expect(calls == 2)
        }
        for payload in [nil, "invalid-payload" as CFString?, [:] as CFDictionary?] as [CFTypeRef?] {
            var calls = 0
            #expect(AISubscriptionCredentials.readKeychainWithoutPrompt(service: "fixture", account: "fixture",
                copyMatching: { _ in
                    calls += 1
                    return calls == 1
                        ? (errSecSuccess, [kSecValueRef as String: "fixture-ref"] as CFDictionary)
                        : (errSecSuccess, payload)
                }, allowsRead: { _ in true }) == nil)
            #expect(calls == 2)
        }
    }

    @Test func dynamicACLRejectsMissingSymbolsPathsAndInvalidItemTypes() throws {
        let fixture = try KeychainACLFixture()
        for missing in ["SecKeychainItemGetTypeID", "SecKeychainItemCopyAccess",
                        "SecAccessCopyMatchingACLList", "SecACLCopyContents"] {
            #expect(!fixture.evaluate(missingSymbol: missing))
        }
        #expect(!fixture.evaluate(executablePath: nil))
        #expect(!fixture.evaluate(item: Data("fixture-item".utf8) as CFData))
        fixture.returnedApplications = fixture.applications
        #expect(!fixture.evaluate(missingSymbol: "SecTrustedApplicationValidateWithPath"))
    }

    @Test func dynamicACLAllowsOnlyNoninteractiveTrustedApplications() throws {
        let fixture = try KeychainACLFixture()
        #expect(fixture.evaluate())
        fixture.selector = SecKeychainPromptSelector(rawValue: 1)
        #expect(!fixture.evaluate())
        fixture.selector = SecKeychainPromptSelector()
        fixture.returnedApplications = [] as CFArray
        #expect(!fixture.evaluate())
        fixture.returnedApplications = ["invalid-application"] as CFArray
        #expect(!fixture.evaluate())
        fixture.returnedApplications = fixture.applications
        #expect(fixture.evaluate())
        #expect(!fixture.evaluate(executablePath: "/fixture/other-application"))
        fixture.validationStatus = errSecAuthFailed
        #expect(!fixture.evaluate())
        fixture.validationStatus = errSecSuccess
        #expect(fixture.evaluate())
    }

    @Test func dynamicACLRejectsCopyFailuresAndReleasesOwnedResults() throws {
        let fixture = try KeychainACLFixture()
        fixture.accessStatus = errSecAuthFailed
        #expect(!fixture.evaluate())
        fixture.accessStatus = errSecSuccess
        fixture.returnsAccess = false
        #expect(!fixture.evaluate())
        fixture.returnsAccess = true
        for invalid in [nil, [] as CFArray?, ["invalid-acl"] as CFArray?] {
            fixture.returnedACLs = invalid
            #expect(!fixture.evaluate())
        }
        fixture.returnedACLs = [fixture.acl] as CFArray
        fixture.returnedApplications = fixture.applications
        fixture.contentsStatus = errSecAuthFailed
        #expect(!fixture.evaluate())
        fixture.contentsStatus = errSecSuccess
        fixture.selector = SecKeychainPromptSelector(rawValue: 1)
        #expect(!fixture.evaluate())
        fixture.selector = SecKeychainPromptSelector()
        #expect(fixture.evaluate())
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

// In-memory Security objects preserve CF type checks without creating or querying Keychain items.
private final class KeychainACLFixture {
    let access: SecAccess
    let acl: SecACL
    let applications: CFArray
    let description: CFString
    var accessStatus = errSecSuccess
    var returnsAccess = true
    var returnedACLs: CFArray?
    var returnedApplications: CFArray?
    var contentsStatus = errSecSuccess
    var selector = SecKeychainPromptSelector()
    var validationStatus = errSecSuccess

    init() throws {
        let framework = try #require(dlopen("/System/Library/Frameworks/Security.framework/Security", RTLD_NOW))
        defer { dlclose(framework) }
        let createAccess = unsafeBitCast(try #require(dlsym(framework, "SecAccessCreate")), to: CreateAccess.self)
        var accessReference: Unmanaged<SecAccess>?
        #expect(createAccess("fixture-only" as CFString, [] as CFArray, &accessReference) == errSecSuccess)
        access = try #require(accessReference?.takeRetainedValue())
        let createACL = unsafeBitCast(try #require(dlsym(framework, "SecACLCreateWithSimpleContents")), to: CreateACL.self)
        var aclReference: Unmanaged<SecACL>?
        #expect(createACL(access, nil, "fixture-only" as CFString, SecKeychainPromptSelector(), &aclReference) == errSecSuccess)
        acl = try #require(aclReference?.takeRetainedValue())
        returnedACLs = [acl] as CFArray
        let createApplication = unsafeBitCast(try #require(dlsym(framework, "SecTrustedApplicationCreateFromPath")), to: CreateApplication.self)
        var applicationReference: Unmanaged<SecTrustedApplication>?
        #expect(createApplication(nil, &applicationReference) == errSecSuccess)
        let application = try #require(applicationReference?.takeRetainedValue())
        applications = [application] as CFArray
        description = try #require(CFStringCreateMutableCopy(nil, 0, "fixture-description" as CFString))
    }

    func evaluate(item: CFTypeRef = "fixture-item" as CFString,
                  executablePath: String? = "/fixture/zisla", missingSymbol: String? = nil) -> Bool {
        let references: [CFTypeRef] = [access, acl, applications, description] + [returnedACLs, returnedApplications].compactMap { $0 }
        let counts = references.map { CFGetRetainCount($0) }
        Thread.current.threadDictionary[Self.contextKey] = self
        defer { Thread.current.threadDictionary.removeObject(forKey: Self.contextKey) }
        let allowed = autoreleasepool {
            AISubscriptionCredentials.keychainItemAllowsRead(item, executablePath: executablePath) { name in
                if name == missingSymbol { return nil }
                switch name {
                case "SecKeychainItemGetTypeID": return unsafeBitCast(fixtureItemTypeID, to: UnsafeMutableRawPointer.self)
                case "SecKeychainItemCopyAccess": return unsafeBitCast(fixtureCopyAccess, to: UnsafeMutableRawPointer.self)
                case "SecAccessCopyMatchingACLList": return unsafeBitCast(fixtureCopyACLs, to: UnsafeMutableRawPointer.self)
                case "SecACLCopyContents": return unsafeBitCast(fixtureCopyContents, to: UnsafeMutableRawPointer.self)
                case "SecTrustedApplicationValidateWithPath": return unsafeBitCast(fixtureValidateApplication, to: UnsafeMutableRawPointer.self)
                default: Issue.record("Unexpected Security symbol: \(name)"); return nil
                }
            }
        }
        #expect(references.map { CFGetRetainCount($0) } == counts, "Security Copy results must release their transferred ownership")
        return allowed
    }

    static let contextKey = "zisla-keychain-acl-fixture"
    static var current: KeychainACLFixture { Thread.current.threadDictionary[contextKey] as! KeychainACLFixture }
    private typealias CreateAccess = @convention(c) (CFString, CFArray?, UnsafeMutablePointer<Unmanaged<SecAccess>?>) -> OSStatus
    private typealias CreateACL = @convention(c) (
        SecAccess, CFArray?, CFString, SecKeychainPromptSelector, UnsafeMutablePointer<Unmanaged<SecACL>?>) -> OSStatus
    private typealias CreateApplication = @convention(c) (
        UnsafePointer<CChar>?, UnsafeMutablePointer<Unmanaged<SecTrustedApplication>?>) -> OSStatus
}

private let fixtureItemTypeID: @convention(c) () -> CFTypeID = { CFStringGetTypeID() }
private let fixtureCopyAccess: @convention(c) (
    CFTypeRef, UnsafeMutablePointer<Unmanaged<SecAccess>?>) -> OSStatus = { _, result in
    let fixture = KeychainACLFixture.current
    result.pointee = fixture.returnsAccess ? .passRetained(fixture.access) : nil
    return fixture.accessStatus
}
private let fixtureCopyACLs: @convention(c) (SecAccess, CFTypeRef) -> Unmanaged<CFArray>? = { _, tag in
    #expect(CFEqual(tag, kSecACLAuthorizationDecrypt))
    return KeychainACLFixture.current.returnedACLs.map { .passRetained($0) }
}
private let fixtureCopyContents: @convention(c) (
    SecACL, UnsafeMutablePointer<Unmanaged<CFArray>?>, UnsafeMutablePointer<Unmanaged<CFString>?>,
    UnsafeMutablePointer<SecKeychainPromptSelector>) -> OSStatus = { acl, applications, description, selector in
    let fixture = KeychainACLFixture.current
    guard CFEqual(acl, fixture.acl) else { return errSecParam }
    applications.pointee = fixture.returnedApplications.map { .passRetained($0) }
    description.pointee = .passRetained(fixture.description)
    selector.pointee = fixture.selector
    return fixture.contentsStatus
}
private let fixtureValidateApplication: @convention(c) (SecTrustedApplication, UnsafePointer<CChar>) -> OSStatus = { application, path in
    let fixture = KeychainACLFixture.current
    guard CFArrayContainsValue(fixture.applications, CFRange(location: 0, length: 1),
                              Unmanaged.passUnretained(application).toOpaque()) else { return errSecParam }
    return String(cString: path) == "/fixture/zisla" ? fixture.validationStatus : errSecAuthFailed
}
