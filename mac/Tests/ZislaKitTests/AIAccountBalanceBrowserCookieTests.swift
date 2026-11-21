import Darwin
import Foundation
import SQLite3
import Testing
import ZislaCore
@testable import ZislaKit

struct AIAccountBalanceBrowserCookieTests {
    private let now = Date(timeIntervalSince1970: 1_900_000_000)
    private let encrypted = "djEwr0TXaxFe0SiR8p6DfboYwWQKoobkB1hVgQCDAwHe/n3F8cJKBGtZqPn0QwnWdDzsua0awIVzycshuBKP6+5Ywg=="

    @Test func defaultBrowserSelectsOnlyItsActiveProfileWithoutScanningAnotherBrowser() throws {
        let fixture = try BalanceBrowserFixture()
        defer { fixture.remove() }
        let chrome = try fixture.application("com.google.Chrome")
        let profile = "Google/Chrome/Profile 2/Network/Cookies"
        try fixture.touch(profile)
        try fixture.touch("Google/Chrome/Default/Cookies")
        try fixture.touch("Microsoft Edge/Default/Cookies")
        try fixture.metadata(["profile": ["last_used": "Profile 2"]], path: "Google/Chrome/Local State")
        let resolver = AIAccountBalanceBrowserCookieSourceResolver(home: fixture.home, defaultApplication: { _ in chrome })
        let source = try resolver.resolve(for: .qoder)
        #expect(source.browser == .chrome)
        #expect(source.databaseURL == fixture.support.appendingPathComponent(profile))
        #expect(source.keychainAccount == "Chrome")
        try FileManager.default.removeItem(at: source.databaseURL)
        #expect(throws: AIAccountBalanceBrowserCookieError.cookiesNotFound) { try resolver.resolve(for: .qoder) }
    }

    @Test func unknownDefaultBrowserAndNoHandlerFailWithoutFallingBackToChrome() throws {
        let fixture = try BalanceBrowserFixture()
        defer { fixture.remove() }
        try fixture.touch("Google/Chrome/Default/Cookies")
        for bundle in ["com.example.Chromeish", "com.example.Chrome", "company.thebrowser.Browser",
                       "com.apple.SafariTechnologyPreview", "org.mozilla.firefoxdeveloperedition"] {
            let application = try fixture.application(bundle)
            #expect(throws: AIAccountBalanceBrowserCookieError.unsupportedBrowser) {
                try AIAccountBalanceBrowserCookieSourceResolver(home: fixture.home, defaultApplication: { _ in application }).resolve(for: .qoder)
            }
        }
        #expect(throws: AIAccountBalanceBrowserCookieError.noDefaultBrowser) {
            try AIAccountBalanceBrowserCookieSourceResolver(home: fixture.home, defaultApplication: { _ in nil }).resolve(for: .qoder)
        }
    }

    @Test func profileMetadataCannotEscapeHomeAndFirefoxDoesNotMergeInstallDefaults() throws {
        let fixture = try BalanceBrowserFixture()
        defer { fixture.remove() }
        let chrome = try fixture.application("com.google.Chrome")
        for path in ["../Other", "/tmp", "Profile 1/Other", ".", "..", "", "Profile\n1", "Profile\\Other", String(repeating: "a", count: 161)] {
            try fixture.metadata(["profile": ["last_used": path]], path: "Google/Chrome/Local State")
            #expect(throws: AIAccountBalanceBrowserCookieError.invalidData) {
                try AIAccountBalanceBrowserCookieSourceResolver(home: fixture.home, defaultApplication: { _ in chrome }).resolve(for: .qoder)
            }
        }
        let firefox = try fixture.application("org.mozilla.firefox")
        try fixture.touch("Firefox/Profiles/active.default/cookies.sqlite")
        try fixture.text("[InstallA]\nDefault=Profiles/active.default\n[Profile0]\nDefault=1\nIsRelative=1\nPath=Profiles/other.default\n", path: "Firefox/profiles.ini")
        let resolver = AIAccountBalanceBrowserCookieSourceResolver(home: fixture.home, defaultApplication: { _ in firefox })
        #expect(try resolver.resolve(for: .qoder).databaseURL == fixture.support.appendingPathComponent("Firefox/Profiles/active.default/cookies.sqlite"))
        try fixture.text("[InstallA]\nDefault=Profiles/active.default\n[InstallB]\nDefault=Profiles/other.default\n", path: "Firefox/profiles.ini")
        #expect(throws: AIAccountBalanceBrowserCookieError.invalidData) { try resolver.resolve(for: .qoder) }
    }

    @Test(arguments: [
        ("com.google.Chrome", BrowserDownloadAgent.chrome, "Google/Chrome/Default/Cookies", "Chrome"),
        ("com.google.Chrome.beta", .chrome, "Google/Chrome Beta/Default/Cookies", "Chrome"),
        ("com.google.Chrome.canary", .chrome, "Google/Chrome Canary/Default/Cookies", "Chrome"),
        ("com.microsoft.edgemac", .edge, "Microsoft Edge/Default/Cookies", "Microsoft Edge"),
        ("com.microsoft.edgemac.Beta", .edge, "Microsoft Edge Beta/Default/Cookies", "Microsoft Edge"),
        ("com.brave.Browser", .brave, "BraveSoftware/Brave-Browser/Default/Cookies", "Brave"),
        ("com.brave.Browser.beta", .brave, "BraveSoftware/Brave-Browser-Beta/Default/Cookies", "Brave"),
        ("com.vivaldi.Vivaldi", .vivaldi, "Vivaldi/Default/Cookies", "Vivaldi"),
        ("com.operasoftware.Opera", .opera, "com.operasoftware.Opera/Cookies", "Opera"),
        ("com.operasoftware.OperaGX", .opera, "com.operasoftware.OperaGX/Cookies", "Opera"),
    ])
    func supportedDefaultBrowserReleaseUsesItsOwnProfileRootAndKeychainAccount(configuration: (String, BrowserDownloadAgent, String, String)) throws {
        let (bundle, browser, path, account) = configuration
        let fixture = try BalanceBrowserFixture()
        defer { fixture.remove() }
        let application = try fixture.application(bundle)
        try fixture.touch(path)
        if browser == .opera {
            try fixture.text("profileless", path: path.replacingOccurrences(of: "/Cookies", with: "/Local State"))
        }
        let resolver = AIAccountBalanceBrowserCookieSourceResolver(home: fixture.home, defaultApplication: { _ in application })
        let source = try resolver.resolve(for: .qoder)
        #expect(source.browser == browser && source.keychainAccount == account)
        #expect(source.databaseURL == fixture.support.appendingPathComponent(path))
    }

    @Test func safariPrefersContainerAndUsesLegacyLocationOnlyWhenContainerIsAbsent() throws {
        let fixture = try BalanceBrowserFixture()
        defer { fixture.remove() }
        let application = try fixture.application("com.apple.Safari")
        let library = fixture.home.appendingPathComponent("Library")
        let container = library.appendingPathComponent("Containers/com.apple.Safari/Data/Library/Cookies/Cookies.binarycookies")
        let legacy = library.appendingPathComponent("Cookies/Cookies.binarycookies")
        for file in [container, legacy] {
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data().write(to: file)
        }
        let resolver = AIAccountBalanceBrowserCookieSourceResolver(home: fixture.home, defaultApplication: { _ in application })
        #expect(try resolver.resolve(for: .zed).databaseURL == container)
        try FileManager.default.removeItem(at: container)
        #expect(try resolver.resolve(for: .zed).databaseURL == legacy)
    }

    @Test func malformedProfileMetadataAndBlockedCookieFilesDoNotTriggerAnotherProfileFallback() throws {
        let fixture = try BalanceBrowserFixture()
        defer { fixture.remove() }
        let application = try fixture.application("com.google.Chrome")
        let resolver = AIAccountBalanceBrowserCookieSourceResolver(home: fixture.home, defaultApplication: { _ in application })
        try fixture.touch("Google/Chrome/Default/Cookies")
        for value in ["not-json", "{}", "{\"profile\":{\"last_used\":1}}"] {
            try fixture.text(value, path: "Google/Chrome/Local State")
            #expect(throws: AIAccountBalanceBrowserCookieError.invalidData) { try resolver.resolve(for: .qoder) }
        }
        let metadata = fixture.support.appendingPathComponent("Google/Chrome/Local State")
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: metadata.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: metadata.path) }
        #expect(throws: AIAccountBalanceBrowserCookieError.accessFailed) { try resolver.resolve(for: .qoder) }
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: metadata.path)
        try FileManager.default.removeItem(at: metadata)
        let root = fixture.support.appendingPathComponent("Google/Chrome/Default")
        let cookies = root.appendingPathComponent("Network/Cookies")
        try FileManager.default.createDirectory(at: cookies, withIntermediateDirectories: true)
        #expect(throws: AIAccountBalanceBrowserCookieError.accessFailed) { try resolver.resolve(for: .qoder) }
    }

    @Test func firefoxRelativeDefaultFallbackRejectsAbsoluteProfilesAndUnsupportedDatabaseVersions() throws {
        let fixture = try BalanceBrowserFixture()
        defer { fixture.remove() }
        let application = try fixture.application("org.mozilla.firefox")
        let database = fixture.support.appendingPathComponent("Firefox/Profiles/active.default/cookies.sqlite")
        try fixture.sql("""
            PRAGMA user_version=17;
            CREATE TABLE moz_cookies(host TEXT, name TEXT, value TEXT, path TEXT, expiry INTEGER, originAttributes TEXT);
            INSERT INTO moz_cookies VALUES('.qoder.com', 'session', 'firefox', '/', 2000000000000, '');
            """, database: database)
        let resolver = AIAccountBalanceBrowserCookieSourceResolver(home: fixture.home, defaultApplication: { _ in application })
        let reader = AIAccountBalanceBrowserCookieReader(temporaryDirectory: fixture.root, now: { [now] in now }, keychainRead: { _, _ in nil })
        try fixture.text("[Profile0]\nDefault=1\nIsRelative=1\nPath=Profiles/active.default\n", path: "Firefox/profiles.ini")
        let source = try resolver.resolve(for: .qoder)
        #expect(source.databaseURL == database)
        #expect(try reader.header(from: source, website: .qoder) == "session=firefox")
        try fixture.sql("PRAGMA user_version=18", database: database)
        #expect(throws: AIAccountBalanceBrowserCookieError.invalidData) { try reader.header(from: source, website: .qoder) }
        try fixture.text("[Profile0]\nDefault=1\nIsRelative=0\nPath=Profiles/active.default\n", path: "Firefox/profiles.ini")
        #expect(throws: AIAccountBalanceBrowserCookieError.invalidData) { try resolver.resolve(for: .qoder) }
    }

    @Test func chromiumEncryptedCookiesRespectRegionHostPathExpiryAndPrivateSnapshotCleanup() throws {
        let fixture = try BalanceBrowserFixture()
        defer { fixture.remove() }
        let database = try fixture.chromium()
        try fixture.insertChrome(database, host: ".qoder.com", name: "session", encrypted: Data(base64Encoded: encrypted)!)
        try fixture.insertChrome(database, host: ".qoder.com.cn", name: "session", value: "other-region")
        try fixture.insertChrome(database, host: "qoder.com", name: "host", value: "exact")
        try fixture.insertChrome(database, host: ".qoder.com", name: "account", value: "wrong-path", path: "/account")
        try fixture.insertChrome(database, host: ".qoder.com", name: "expired", value: "expired", expires: 1)
        try fixture.insertChrome(database, host: ".qoder.com", name: "partitioned", value: "other-context", partition: "https://other.invalid")
        let before = try fixture.files(at: database.deletingLastPathComponent())
        let temporary = fixture.root.appendingPathComponent("Temporary", isDirectory: true)
        try FileManager.default.createDirectory(at: temporary, withIntermediateDirectories: true)
        let reader = AIAccountBalanceBrowserCookieReader(temporaryDirectory: temporary, now: { [now] in now }, keychainRead: { service, account in
            #expect(service == "Chrome Safe Storage" && account == "Chrome")
            let directories = try FileManager.default.contentsOfDirectory(at: temporary, includingPropertiesForKeys: nil)
            let directory = try #require(directories.first)
            #expect(try fixture.permissions(directory) == 0o700)
            #expect(try fixture.permissions(directory.appendingPathComponent("Cookies")) == 0o600)
            return Data("fixture-cookie-password".utf8)
        })
        let header = try reader.header(from: .init(browser: .chrome, databaseURL: database, keychainAccount: "Chrome"), website: .qoder)
        #expect(header == "host=exact; session=fixture-imported")
        #expect(try fixture.files(at: database.deletingLastPathComponent()) == before)
        #expect(try FileManager.default.contentsOfDirectory(atPath: temporary.path).isEmpty)
    }

    @Test func independentLegacyCryptoFixtureAndDomainHashMismatchFailClosed() throws {
        let fixture = try BalanceBrowserFixture()
        defer { fixture.remove() }
        let database = try fixture.chromium(version: 23)
        try fixture.insertChrome(database, host: ".qoder.com", name: "session", encrypted: Data(base64Encoded: "djEwBY3QaU9YxYrGt0W1OuIu8A==")!)
        let reader = AIAccountBalanceBrowserCookieReader(temporaryDirectory: fixture.root, now: { [now] in now }, keychainRead: { _, _ in Data("fixture-cookie-password".utf8) })
        let source = AIAccountBalanceBrowserCookieSource(browser: .chrome, databaseURL: database, keychainAccount: "Chrome")
        #expect(try reader.header(from: source, website: .qoder) == "session=fixture-legacy")
        try fixture.sql("DELETE FROM cookies; UPDATE meta SET value = '24'", database: database)
        let wrongHostCiphertext = Data(base64Encoded: "djEwJJ9LnGbE7MCx7WMch55JDv0H9l9EFeCdifKYRi6E353DKBNikJ+aLqxs7zd+i/NT")!
        try fixture.insertChrome(database, host: ".qoder.com", name: "session", encrypted: wrongHostCiphertext)
        #expect(throws: AIAccountBalanceBrowserCookieError.invalidData) { try reader.header(from: source, website: .qoder) }
    }

    @Test func firefoxMillisecondsContainersAndEndpointHostOnlyRulesAreAppliedBeforeImport() throws {
        let fixture = try BalanceBrowserFixture()
        defer { fixture.remove() }
        let database = fixture.support.appendingPathComponent("Firefox/Profiles/active/cookies.sqlite")
        try fixture.sql("""
            PRAGMA user_version = 16;
            CREATE TABLE moz_cookies(host TEXT, name TEXT, value TEXT, path TEXT, expiry INTEGER, isSecure INTEGER, originAttributes TEXT);
            INSERT INTO moz_cookies VALUES
            ('.trae.cn', 'session', 'trae-fixture', '/', 2000000000000, 1, ''),
            ('www.trae.cn', 'hostOnly', 'wrong-host', '/', 2000000000000, 1, ''),
            ('.trae.cn', 'container', 'other-account', '/', 2000000000000, 1, '^userContextId=2'),
            ('.trae.cn', 'expired', 'too-old', '/', 1800000000000, 1, ''),
            ('.trae.cn', 'path', 'not-both-endpoints', '/cloudide', 2000000000000, 1, '');
            """, database: database)
        let reader = AIAccountBalanceBrowserCookieReader(temporaryDirectory: fixture.root, now: { [now] in now }, keychainRead: { _, _ in
            Issue.record("Firefox must not read Keychain"); return nil
        })
        #expect(try reader.header(from: .init(browser: .firefox, databaseURL: database, keychainAccount: nil), website: .trae) == "session=trae-fixture")
        #expect(try reader.header(from: .init(browser: .firefox, databaseURL: database, keychainAccount: nil), website: .trae)
            .contains("other-account") == false)
    }

    @Test func sessionCookiesAndZedAllowedNamesStaySeparateFromPersistentAndUnrelatedCookies() throws {
        let fixture = try BalanceBrowserFixture()
        defer { fixture.remove() }
        let database = try fixture.chromium()
        try fixture.insertChrome(database, host: ".zed.dev", name: "zed.session", value: "zed-fixture", expires: 1, persistent: false)
        try fixture.insertChrome(database, host: "dashboard.zed.dev", name: "zed.session", value: "dashboard-only")
        try fixture.insertChrome(database, host: ".zed.dev", name: "unrelated", value: "tracking")
        try fixture.insertChrome(database, host: ".zed.dev", name: "cf_clearance", value: "clearance")
        let reader = AIAccountBalanceBrowserCookieReader(temporaryDirectory: fixture.root, now: { [now] in now }, keychainRead: { _, _ in
            Issue.record("Plaintext must not read Keychain"); return nil
        })
        #expect(try reader.header(from: .init(browser: .chrome, databaseURL: database, keychainAccount: "Chrome"), website: .zed)
            == "cf_clearance=clearance; zed.session=zed-fixture")
    }

    @Test func lockedKeychainMalformedCookiesAndMissingDatabasesPreserveAllStoredCredentials() throws {
        let fixture = try BalanceBrowserFixture()
        defer { fixture.remove() }
        let chrome = try fixture.application("com.google.Chrome")
        let database = try fixture.chromium()
        try fixture.insertChrome(database, host: ".qoder.com", name: "session", encrypted: Data(base64Encoded: encrypted)!)
        let secrets = BalanceBrowserMemorySecrets()
        let store = AIAccountBalanceCookieStore(secrets: secrets)
        try store.setCookie("saved=manual", for: .qoder)
        try store.setCookie("saved=china", for: .qoderChina)
        let source = AIAccountBalanceBrowserCookieSourceResolver(home: fixture.home, defaultApplication: { _ in chrome })
        let denied = AIAccountBalanceBrowserCookieReader(temporaryDirectory: fixture.root, now: { [now] in now }, keychainRead: { _, _ in
            throw NSError(domain: "contains-fixture-imported", code: 1)
        })
        let before = secrets.values
        #expect(throws: AIAccountBalanceBrowserCookieError.accessFailed) {
            try AIAccountBalanceBrowserCookieImporter(store: store, source: source, reader: denied).importCookie(for: .qoder)
        }
        #expect(secrets.values == before)
        #expect(!AIAccountBalanceBrowserCookieError.accessFailed.statusKey.contains("fixture-imported"))
        #expect(try fixture.rootContents().allSatisfy { !$0.hasPrefix("zisla-quota-cookies-") })
        try fixture.sql("DELETE FROM cookies", database: database)
        try fixture.insertChrome(database, host: ".qoder.com", name: "session", value: "fixture\r\nInjected: header")
        #expect(throws: AIAccountBalanceBrowserCookieError.accessFailed) {
            try AIAccountBalanceBrowserCookieImporter(store: store, source: source, reader: denied).importCookie(for: .qoder)
        }
        #expect(secrets.values == before)
    }

    @Test func importingOneWebsiteWritesOnlyItsSecretAfterSuccessfulRead() throws {
        let fixture = try BalanceBrowserFixture()
        defer { fixture.remove() }
        let application = try fixture.application("com.google.Chrome")
        let database = try fixture.chromium()
        try fixture.insertChrome(database, host: ".qoder.com.cn", name: "session", value: "china-imported")
        let secrets = BalanceBrowserMemorySecrets()
        let store = AIAccountBalanceCookieStore(secrets: secrets)
        try store.setCookie("manual=global", for: .qoder)
        let importer = AIAccountBalanceBrowserCookieImporter(store: store,
            source: .init(home: fixture.home, defaultApplication: { _ in application }),
            reader: .init(temporaryDirectory: fixture.root, now: { [now] in now }, keychainRead: { _, _ in nil }))
        try importer.importCookie(for: .qoderChina)
        #expect(try store.cookie(for: .qoder) == "manual=global")
        #expect(try store.cookie(for: .qoderChina) == "session=china-imported")
    }

    @Test func parentHostOnlyCookiesPathBoundariesAndDuplicateNamesUseBrowserRequestScope() throws {
        let fixture = try BalanceBrowserFixture()
        defer { fixture.remove() }
        let database = try fixture.chromium()
        try fixture.insertChrome(database, host: "qoder.com", name: "scope", value: "root", path: "/")
        try fixture.insertChrome(database, host: ".qoder.com", name: "scope", value: "api", path: "/api")
        try fixture.insertChrome(database, host: ".qoder.com", name: "scope", value: "api-slash", path: "/api/")
        try fixture.insertChrome(database, host: ".qoder.com", name: "exact", value: "endpoint", path: "/api/v2/me/usages/big_model_credits")
        try fixture.insertChrome(database, host: ".qoder.com", name: "partial", value: "wrong-boundary", path: "/api/v2/me/usage")
        try fixture.insertChrome(database, host: ".qoder.com", name: "nonabsolute", value: "wrong-path", path: "api")
        try fixture.insertChrome(database, host: "zed.dev", name: "zed.session", value: "host-only-parent")
        try fixture.insertChrome(database, host: ".zed.dev", name: "zed.session", value: "domain-parent")
        let reader = AIAccountBalanceBrowserCookieReader(temporaryDirectory: fixture.root, now: { [now] in now }, keychainRead: { _, _ in nil })
        let source = AIAccountBalanceBrowserCookieSource(browser: .chrome, databaseURL: database, keychainAccount: "Chrome")
        #expect(try reader.header(from: source, website: .qoder)
            == "exact=endpoint; scope=api-slash; scope=api; scope=root")
        #expect(try reader.header(from: source, website: .zed) == "zed.session=domain-parent")
    }

    @Test(arguments: [256, 257])
    func selectedCookieCountBudgetRejectsOverflowWithoutReturningAPartialHeader(count: Int) throws {
        let fixture = try BalanceBrowserFixture()
        defer { fixture.remove() }
        let application = try fixture.application("com.google.Chrome")
        let database = try fixture.chromium()
        try fixture.sql("""
            WITH RECURSIVE records(id) AS (SELECT 1 UNION ALL SELECT id+1 FROM records WHERE id<\(count))
            INSERT INTO cookies SELECT '.qoder.com','c'||id,'v',X'', '/',0,1,'',0,0 FROM records;
            """, database: database)
        let secrets = BalanceBrowserMemorySecrets()
        let store = AIAccountBalanceCookieStore(secrets: secrets)
        try store.setCookie("saved=before", for: .qoder)
        let importer = AIAccountBalanceBrowserCookieImporter(store: store,
            source: .init(home: fixture.home, defaultApplication: { _ in application }),
            reader: .init(temporaryDirectory: fixture.root, now: { [now] in now }, keychainRead: { _, _ in nil }))
        if count == 256 {
            try importer.importCookie(for: .qoder)
            #expect(try store.cookie(for: .qoder)?.components(separatedBy: "; ").count == count)
        } else {
            #expect(throws: AIAccountBalanceBrowserCookieError.invalidData) { try importer.importCookie(for: .qoder) }
            #expect(try store.cookie(for: .qoder) == "saved=before")
        }
        #expect(try fixture.rootContents().allSatisfy { !$0.hasPrefix("zisla-quota-cookies-") })
    }

    @Test(arguments: ["column-budget", "row-budget", "nul", "utf8", "number-type", "negative-expiry", "boolean", "missing-column", "empty-cookie"])
    func malformedCookieRowsAndTextBudgetsFailWithoutLeakingOrChangingSavedCookies(failure: String) throws {
        let fixture = try BalanceBrowserFixture()
        defer { fixture.remove() }
        let application = try fixture.application("com.google.Chrome")
        let database = try fixture.chromium()
        try fixture.insertChrome(database, host: ".qoder.com", name: "session", value: "fixture-private")
        let update: String
        switch failure {
        case "column-budget": update = "UPDATE cookies SET value=replace(hex(zeroblob(32769)), '00', 'x')"
        case "row-budget": update = "UPDATE cookies SET value=replace(hex(zeroblob(70000)), '00', 'x')"
        case "nul": update = "UPDATE cookies SET value=CAST(X'6669780074757265' AS TEXT)"
        case "utf8": update = "UPDATE cookies SET value=CAST(X'FF' AS TEXT)"
        case "number-type": update = "UPDATE cookies SET expires_utc='not-a-number'"
        case "negative-expiry": update = "UPDATE cookies SET expires_utc=-1"
        case "boolean": update = "UPDATE cookies SET has_expires=2"
        case "missing-column": update = "ALTER TABLE cookies RENAME COLUMN path TO moved_path"
        case "empty-cookie": update = "UPDATE cookies SET value=''"
        default: throw CocoaError(.fileReadCorruptFile)
        }
        try fixture.sql(update, database: database)
        let secrets = BalanceBrowserMemorySecrets()
        let store = AIAccountBalanceCookieStore(secrets: secrets)
        try store.setCookie("saved=manual", for: .qoder)
        let before = secrets.values
        let importer = AIAccountBalanceBrowserCookieImporter(store: store,
            source: .init(home: fixture.home, defaultApplication: { _ in application }),
            reader: .init(temporaryDirectory: fixture.root, now: { [now] in now }, keychainRead: { _, _ in nil }))
        let expected: AIAccountBalanceBrowserCookieError = failure == "empty-cookie" ? .accessFailed : .invalidData
        #expect(throws: expected) { try importer.importCookie(for: .qoder) }
        #expect(secrets.values == before)
        #expect(try fixture.rootContents().allSatisfy { !$0.hasPrefix("zisla-quota-cookies-") })
    }

    @Test(arguments: ["missing", "empty", "encoding", "wrong-key", "unsupported-cipher"])
    func keychainAndEncryptedPayloadFailuresKeepSavedCookiesAndCleanSnapshots(failure: String) throws {
        let fixture = try BalanceBrowserFixture()
        defer { fixture.remove() }
        let application = try fixture.application("com.google.Chrome")
        let database = try fixture.chromium()
        let ciphertext = failure == "unsupported-cipher" ? Data("v20unsupported".utf8) : Data(base64Encoded: encrypted)!
        try fixture.insertChrome(database, host: ".qoder.com", name: "session", encrypted: ciphertext)
        let reader = AIAccountBalanceBrowserCookieReader(temporaryDirectory: fixture.root, now: { [now] in now }, keychainRead: { _, _ in
            switch failure {
            case "missing": nil
            case "empty": Data()
            case "encoding": Data([0xff])
            case "wrong-key": Data("different-key".utf8)
            default: Data("fixture-cookie-password".utf8)
            }
        })
        let secrets = BalanceBrowserMemorySecrets()
        let store = AIAccountBalanceCookieStore(secrets: secrets)
        try store.setCookie("saved=manual", for: .qoder)
        let before = secrets.values
        let importer = AIAccountBalanceBrowserCookieImporter(store: store,
            source: .init(home: fixture.home, defaultApplication: { _ in application }), reader: reader)
        let expected: AIAccountBalanceBrowserCookieError = ["wrong-key", "unsupported-cipher"].contains(failure) ? .invalidData : .accessFailed
        #expect(throws: expected) { try importer.importCookie(for: .qoder) }
        #expect(secrets.values == before)
        #expect(try fixture.rootContents().allSatisfy { !$0.hasPrefix("zisla-quota-cookies-") })
    }

    @Test(arguments: ["short-chunks", "premature-eof", "io-failure"])
    func snapshotReadFailuresAndShortReadsDoNotLeakDescriptorsOrReplaceCookies(mode: String) throws {
        let fixture = try BalanceBrowserFixture()
        defer { fixture.remove() }
        let application = try fixture.application("com.google.Chrome")
        let database = try fixture.chromium()
        try fixture.insertChrome(database, host: ".qoder.com", name: "session", value: "imported")
        let capture = BalanceBrowserReadCapture()
        let reader = AIAccountBalanceBrowserCookieReader(temporaryDirectory: fixture.root, now: { [now] in now }, keychainRead: { _, _ in nil },
            readFile: { descriptor, bytes, count in
                capture.record(descriptor)
                switch mode {
                case "premature-eof": return 0
                case "io-failure": errno = EIO; return -1
                default: return Darwin.read(descriptor, bytes, min(count, 7))
                }
            })
        let secrets = BalanceBrowserMemorySecrets()
        let store = AIAccountBalanceCookieStore(secrets: secrets)
        try store.setCookie("saved=manual", for: .qoder)
        let importer = AIAccountBalanceBrowserCookieImporter(store: store,
            source: .init(home: fixture.home, defaultApplication: { _ in application }), reader: reader)
        if mode == "short-chunks" {
            try importer.importCookie(for: .qoder)
            #expect(try store.cookie(for: .qoder) == "session=imported")
        } else {
            #expect(throws: AIAccountBalanceBrowserCookieError.accessFailed) { try importer.importCookie(for: .qoder) }
            #expect(try store.cookie(for: .qoder) == "saved=manual")
        }
        #expect(!capture.containsOpenSourceDescriptor)
        #expect(try fixture.rootContents().allSatisfy { !$0.hasPrefix("zisla-quota-cookies-") })
    }

    @Test func ancestorSymlinksAndPermissionDeniedCookieFilesCannotImportAnotherDirectory() throws {
        let fixture = try BalanceBrowserFixture()
        defer { fixture.remove() }
        let application = try fixture.application("com.google.Chrome")
        let database = try fixture.chromium()
        try fixture.insertChrome(database, host: ".qoder.com", name: "session", value: "private")
        let reader = AIAccountBalanceBrowserCookieReader(temporaryDirectory: fixture.root, now: { [now] in now }, keychainRead: { _, _ in nil })
        let source = AIAccountBalanceBrowserCookieSource(browser: .chrome, databaseURL: database, keychainAccount: "Chrome")
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: database.path)
        #expect(throws: AIAccountBalanceBrowserCookieError.accessFailed) { try reader.header(from: source, website: .qoder) }
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: database.path)
        let actualProfile = database.deletingLastPathComponent().deletingLastPathComponent()
        let alternateProfile = actualProfile.deletingLastPathComponent().appendingPathComponent("Moved")
        try FileManager.default.moveItem(at: actualProfile, to: alternateProfile)
        try FileManager.default.createSymbolicLink(at: actualProfile, withDestinationURL: alternateProfile)
        #expect(throws: AIAccountBalanceBrowserCookieError.accessFailed) { try reader.header(from: source, website: .qoder) }
        let resolver = AIAccountBalanceBrowserCookieSourceResolver(home: fixture.home, defaultApplication: { _ in application })
        #expect(throws: AIAccountBalanceBrowserCookieError.accessFailed) { try resolver.resolve(for: .qoder) }
        #expect(try fixture.rootContents().allSatisfy { !$0.hasPrefix("zisla-quota-cookies-") })
    }

    @Test func databaseCopiesRejectSymlinksFIFOsAndBudgetOverflowAndAlwaysCleanUp() throws {
        let fixture = try BalanceBrowserFixture()
        defer { fixture.remove() }
        let database = try fixture.chromium()
        let source = AIAccountBalanceBrowserCookieSource(browser: .chrome, databaseURL: database, keychainAccount: "Chrome")
        let reader = AIAccountBalanceBrowserCookieReader(temporaryDirectory: fixture.root, now: { [now] in now }, keychainRead: { _, _ in nil })
        let link = fixture.root.appendingPathComponent("linked.sqlite")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: database)
        #expect(throws: AIAccountBalanceBrowserCookieError.accessFailed) {
            try reader.header(from: .init(browser: .chrome, databaseURL: link, keychainAccount: "Chrome"), website: .qoder)
        }
        let fifo = fixture.root.appendingPathComponent("pipe.sqlite")
        #expect(mkfifo(fifo.path, 0o600) == 0)
        #expect(throws: AIAccountBalanceBrowserCookieError.accessFailed) {
            try reader.header(from: .init(browser: .chrome, databaseURL: fifo, keychainAccount: "Chrome"), website: .qoder)
        }
        let file = try FileHandle(forWritingTo: database)
        try file.truncate(atOffset: UInt64(AIAccountBalanceBrowserCookieReader.maximumDatabaseBytes + 1))
        try file.close()
        #expect(throws: AIAccountBalanceBrowserCookieError.accessFailed) { try reader.header(from: source, website: .qoder) }
        #expect(try fixture.rootContents().allSatisfy { !$0.hasPrefix("zisla-quota-cookies-") })
    }

    @Test(arguments: ["DELETE", "WAL"])
    func lockedRunningBrowserSnapshotReadsCommittedCookiesWithoutChangingItsFiles(journalMode: String) throws {
        let fixture = try BalanceBrowserFixture()
        defer { fixture.remove() }
        let database = try fixture.chromium()
        try fixture.insertChrome(database, host: ".qoder.com", name: "session", value: "old")
        var connection: OpaquePointer?
        #expect(sqlite3_open(database.path, &connection) == SQLITE_OK)
        defer { sqlite3_close(connection) }
        #expect(sqlite3_exec(connection, "PRAGMA locking_mode=EXCLUSIVE; PRAGMA journal_mode=\(journalMode); PRAGMA wal_autocheckpoint=0; UPDATE cookies SET value='committed';", nil, nil, nil) == SQLITE_OK)
        let before = try fixture.files(at: database.deletingLastPathComponent())
        let reader = AIAccountBalanceBrowserCookieReader(temporaryDirectory: fixture.root, now: { [now] in now }, keychainRead: { _, _ in nil })
        #expect(try reader.header(from: .init(browser: .chrome, databaseURL: database, keychainAccount: "Chrome"), website: .qoder) == "session=committed")
        #expect(try fixture.files(at: database.deletingLastPathComponent()) == before)
        #expect(try fixture.rootContents().allSatisfy { !$0.hasPrefix("zisla-quota-cookies-") })
    }

    @Test(arguments: ["same-length-write", "database-replacement", "wal-replacement", "wal-appears", "wal-disappears", "database-write-after-wal"])
    func changingDatabaseOrWALDuringSnapshotFailsBeforeOverwritingStoredCookies(change: String) throws {
        let fixture = try BalanceBrowserFixture()
        defer { fixture.remove() }
        let application = try fixture.application("com.google.Chrome")
        let database = try fixture.chromium()
        try fixture.insertChrome(database, host: ".qoder.com", name: "session", value: "old")
        let wal = URL(fileURLWithPath: database.path + "-wal")
        var connection: OpaquePointer?
        if ["wal-replacement", "wal-disappears", "database-write-after-wal"].contains(change) {
            #expect(sqlite3_open(database.path, &connection) == SQLITE_OK)
            #expect(sqlite3_exec(connection,
                "PRAGMA journal_mode=WAL; PRAGMA wal_autocheckpoint=0; UPDATE cookies SET value='wal';", nil, nil, nil) == SQLITE_OK)
        }
        defer { sqlite3_close(connection) }
        let observedFile = change == "database-write-after-wal" ? wal : database
        let mutation = try BalanceBrowserReadMutation(observedFile: observedFile) {
            switch change {
            case "same-length-write":
                let before = try Data(contentsOf: database)
                try fixture.sql("UPDATE cookies SET value='new'", database: database)
                #expect(try Data(contentsOf: database).count == before.count)
                try fixture.forceModifiedTime(database)
            case "database-write-after-wal":
                let file = try FileHandle(forWritingTo: database)
                defer { try? file.close() }
                try file.seek(toOffset: 60)
                try file.write(contentsOf: Data([0, 0, 0, 1]))
                try fixture.forceModifiedTime(database)
            case "database-replacement", "wal-replacement":
                let file = change == "database-replacement" ? database : wal
                let replacement = URL(fileURLWithPath: file.path + ".replacement")
                let oldAttributes = try FileManager.default.attributesOfItem(atPath: file.path)
                try Data(contentsOf: file).write(to: replacement)
                if let date = oldAttributes[.modificationDate] {
                    try FileManager.default.setAttributes([.modificationDate: date], ofItemAtPath: replacement.path)
                }
                #expect(rename(replacement.path, file.path) == 0)
            case "wal-appears": try Data("new-wal".utf8).write(to: wal)
            case "wal-disappears": try FileManager.default.removeItem(at: wal)
            default: Issue.record("Unknown fixture mutation")
            }
        }
        let secrets = BalanceBrowserMemorySecrets()
        let store = AIAccountBalanceCookieStore(secrets: secrets)
        try store.setCookie("saved=manual", for: .qoder)
        try store.setCookie("saved=china", for: .qoderChina)
        let before = secrets.values
        let reader = AIAccountBalanceBrowserCookieReader(temporaryDirectory: fixture.root, now: { [now] in now },
            keychainRead: { _, _ in Issue.record("Unstable snapshots must fail before Keychain access"); return nil },
            readFile: { mutation.read($0, $1, $2) })
        let importer = AIAccountBalanceBrowserCookieImporter(store: store,
            source: .init(home: fixture.home, defaultApplication: { _ in application }), reader: reader)
        #expect(throws: AIAccountBalanceBrowserCookieError.accessFailed) { try importer.importCookie(for: .qoder) }
        #expect(mutation.didMutate, "Fixture must change the source at the copy boundary")
        #expect(secrets.values == before, "An unstable snapshot must not overwrite manual or other-region cookies")
        #expect(try fixture.rootContents().allSatisfy { !$0.hasPrefix("zisla-quota-cookies-") })
    }

    @Test func safariBinaryCookieFixtureRespectsEndpointHostAndCorruptOffsets() throws {
        let fixture = try BalanceBrowserFixture()
        defer { fixture.remove() }
        let reader = AIAccountBalanceBrowserCookieReader(temporaryDirectory: fixture.root, now: { [now] in now }, keychainRead: { _, _ in nil })
        let file = fixture.root.appendingPathComponent("Cookies.binarycookies")
        let data = Self.safariFixture(domain: ".zed.dev", name: "zed.session", value: "safari-fixture")
        try data.write(to: file)
        let source = AIAccountBalanceBrowserCookieSource(browser: .safari, databaseURL: file, keychainAccount: nil)
        #expect(try reader.header(from: source, website: .zed) == "zed.session=safari-fixture")
        try Self.safariFixture(domain: "dashboard.zed.dev", name: "zed.session", value: "host-only").write(to: file)
        #expect(throws: AIAccountBalanceBrowserCookieError.cookiesNotFound) { try reader.header(from: source, website: .zed) }
        var invalid = data
        invalid.replaceSubrange(20..<24, with: [255, 255, 255, 127])
        try invalid.write(to: file)
        #expect(throws: AIAccountBalanceBrowserCookieError.invalidData) { try reader.header(from: source, website: .zed) }
    }

    @Test(arguments: ["file-budget", "cookie-budget", "value-budget", "short-chunks", "premature-eof", "io-failure"])
    func safariBudgetsAndReadFailuresPreserveSavedCookiesWithoutLeakingFileDescriptors(mode: String) throws {
        let fixture = try BalanceBrowserFixture()
        defer { fixture.remove() }
        let application = try fixture.application("com.apple.Safari")
        let file = fixture.home.appendingPathComponent("Library/Cookies/Cookies.binarycookies")
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = mode == "cookie-budget" ? Self.safariFixture(domain: ".zed.dev", name: "zed.session", value: "fixture", count: 257)
            : Self.safariFixture(domain: ".zed.dev", name: "zed.session", value: mode == "value-budget" ? String(repeating: "a", count: 32 * 1_024 + 1) : "fixture")
        try data.write(to: file)
        if mode == "file-budget" {
            let writer = try FileHandle(forWritingTo: file)
            try writer.truncate(atOffset: 16 * 1_024 * 1_024 + 1)
            try writer.close()
        }
        let capture = BalanceBrowserReadCapture()
        let reader = AIAccountBalanceBrowserCookieReader(temporaryDirectory: fixture.root, now: { [now] in now }, keychainRead: { _, _ in nil },
            readFile: { descriptor, bytes, count in
                capture.record(descriptor)
                switch mode {
                case "premature-eof": return 0
                case "io-failure": errno = EIO; return -1
                case "short-chunks": return Darwin.read(descriptor, bytes, min(7, count))
                default: return Darwin.read(descriptor, bytes, count)
                }
            })
        let secrets = BalanceBrowserMemorySecrets()
        let store = AIAccountBalanceCookieStore(secrets: secrets)
        try store.setCookie("zed.session=saved", for: .zed)
        let importer = AIAccountBalanceBrowserCookieImporter(store: store,
            source: .init(home: fixture.home, defaultApplication: { _ in application }), reader: reader)
        if mode == "short-chunks" {
            try importer.importCookie(for: .zed)
            #expect(try store.cookie(for: .zed) == "zed.session=fixture")
        } else {
            let expected: AIAccountBalanceBrowserCookieError = ["cookie-budget", "value-budget"].contains(mode) ? .invalidData : .accessFailed
            #expect(throws: expected) { try importer.importCookie(for: .zed) }
            #expect(try store.cookie(for: .zed) == "zed.session=saved")
        }
        #expect(!capture.containsOpenSourceDescriptor)
    }

    @Test(arguments: ["signature", "pages", "page-size", "page-signature", "cookie-count", "offset-before-record", "offset-after-page",
                      "record-too-short", "record-too-long", "string-before-header", "string-after-record", "missing-nul", "utf8"])
    func safariCorruptPageAndRecordFieldsAreRejectedWithoutCrashing(field: String) throws {
        var data = Self.safariFixture(domain: ".zed.dev", name: "zed.session", value: "fixture")
        func set(_ offset: Int, _ value: UInt32, bigEndian: Bool = false) {
            data.replaceSubrange(offset..<(offset + 4), with: (0..<4).map {
                UInt8(truncatingIfNeeded: value >> ((bigEndian ? 3 - $0 : $0) * 8))
            })
        }
        switch field {
        case "signature": data[0] = 0
        case "pages": set(4, 0xffff_ffff, bigEndian: true)
        case "page-size": set(8, UInt32(data.count + 1), bigEndian: true)
        case "page-signature": set(12, 0)
        case "cookie-count": set(16, 0xffff_ffff)
        case "offset-before-record": set(20, 1)
        case "offset-after-page": set(20, 0xffff_ffff)
        case "record-too-short": set(28, 1)
        case "record-too-long": set(28, 0xffff_ffff)
        case "string-before-header": set(44, 1)
        case "string-after-record": set(44, 0xffff_ffff)
        case "missing-nul": data[data.count - 1] = 0x61
        case "utf8": data[data.count - 2] = 0xff
        default: throw CocoaError(.fileReadCorruptFile)
        }
        let reader = AIAccountBalanceBrowserCookieReader(now: { [now] in now }, keychainRead: { _, _ in nil })
        #expect(throws: AIAccountBalanceBrowserCookieError.invalidData) { try reader.safariCookies(data, website: .zed) }
    }

    @Test func seededBoundedCorruptionNeverLeaksCookieValuesOrAcceptsBadCrypto() throws {
        let reader = AIAccountBalanceBrowserCookieReader(now: { [now] in now }, keychainRead: { _, _ in nil })
        var seed: UInt64 = 0x2026_1120
        for count in 0..<96 {
            let data = Data((0..<count).map { _ in
                seed = seed &* 6_364_136_223_846_793_005 &+ 1
                return UInt8(truncatingIfNeeded: seed >> 32)
            })
            #expect(throws: AIAccountBalanceBrowserCookieError.invalidData) { try reader.safariCookies(data, website: .zed) }
            #expect(AISubscriptionCredentials.decryptChromiumData(data, password: "fixture") == nil)
        }
        for length in [0, 1, 7, 12, 20, 40, 60] {
            let fixture = Self.safariFixture(domain: ".zed.dev", name: "zed.session", value: "private-fixture")
            #expect(throws: AIAccountBalanceBrowserCookieError.invalidData) { try reader.safariCookies(Data(fixture.prefix(length)), website: .zed) }
        }
    }

    private static func safariFixture(domain: String, name: String, value: String, count: Int = 1) -> Data {
        func integer(_ value: UInt32, bigEndian: Bool = false) -> [UInt8] {
            (0..<4).map { UInt8(truncatingIfNeeded: value >> ((bigEndian ? 3 - $0 : $0) * 8)) }
        }
        var strings: [UInt8] = []
        var offsets: [UInt32] = []
        for value in [domain, name, "/", value] { offsets.append(UInt32(56 + strings.count)); strings += Array(value.utf8) + [0] }
        let expiration = (2_000_000_000 - Date.timeIntervalBetween1970AndReferenceDate).bitPattern
        var record = integer(UInt32(56 + strings.count)) + integer(0) + integer(1) + integer(0)
        for offset in offsets { record += integer(offset) }
        record += [UInt8](repeating: 0, count: 8)
        record += (0..<8).map { UInt8(truncatingIfNeeded: expiration >> ($0 * 8)) }
        record += [UInt8](repeating: 0, count: 8)
        record += strings
        let headerSize = 12 + count * 4
        var page = [UInt8]([0, 0, 1, 0]) + integer(UInt32(count))
        for index in 0..<count { page += integer(UInt32(headerSize + index * record.count)) }
        page += integer(0)
        for _ in 0..<count { page += record }
        return Data(Array("cook".utf8) + integer(1, bigEndian: true) + integer(UInt32(page.count), bigEndian: true) + page)
    }
}

private struct BalanceBrowserFixture: @unchecked Sendable {
    let root: URL
    let home: URL
    var support: URL { home.appendingPathComponent("Library/Application Support", isDirectory: true) }

    init() throws {
        root = FileManager.default.temporaryDirectory.resolvingSymlinksInPath().appendingPathComponent("zisla-browser-cookie-test-\(UUID())", isDirectory: true)
        home = root.appendingPathComponent("Home", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
    }
    func remove() { try? FileManager.default.removeItem(at: root) }
    func application(_ bundle: String) throws -> URL {
        let app = root.appendingPathComponent(bundle + ".app", isDirectory: true)
        let info = app.appendingPathComponent("Contents/Info.plist")
        try FileManager.default.createDirectory(at: info.deletingLastPathComponent(), withIntermediateDirectories: true)
        try PropertyListSerialization.data(fromPropertyList: ["CFBundleIdentifier": bundle, "CFBundleName": "Fixture"], format: .xml, options: 0).write(to: info)
        return app
    }
    func touch(_ path: String) throws { try text("", path: path) }
    func text(_ text: String, path: String) throws {
        let file = support.appendingPathComponent(path)
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(text.utf8).write(to: file)
    }
    func metadata(_ json: [String: Any], path: String) throws {
        try text(String(decoding: JSONSerialization.data(withJSONObject: json), as: UTF8.self), path: path)
    }
    func chromium(version: Int = 24) throws -> URL {
        let file = support.appendingPathComponent("Google/Chrome/Default/Network/Cookies")
        try sql("""
            CREATE TABLE meta(key TEXT PRIMARY KEY, value TEXT);
            INSERT INTO meta VALUES ('version', '\(version)');
            CREATE TABLE cookies(host_key TEXT, name TEXT, value TEXT, encrypted_value BLOB, path TEXT, expires_utc INTEGER,
                is_secure INTEGER, top_frame_site_key TEXT, has_expires INTEGER, is_persistent INTEGER);
            """, database: file)
        return file
    }
    func sql(_ sql: String, database: URL) throws {
        try FileManager.default.createDirectory(at: database.deletingLastPathComponent(), withIntermediateDirectories: true)
        var handle: OpaquePointer?
        #expect(sqlite3_open(database.path, &handle) == SQLITE_OK)
        defer { sqlite3_close(handle) }
        #expect(sqlite3_exec(handle, sql, nil, nil, nil) == SQLITE_OK)
    }
    func insertChrome(_ database: URL, host: String, name: String, value: String = "", encrypted: Data = Data(),
                      path: String = "/", expires: Double = 2_000_000_000, partition: String = "", persistent: Bool = true) throws {
        var handle: OpaquePointer?
        #expect(sqlite3_open(database.path, &handle) == SQLITE_OK)
        defer { sqlite3_close(handle) }
        var statement: OpaquePointer?
        #expect(sqlite3_prepare_v2(handle, "INSERT INTO cookies VALUES (?, ?, ?, ?, ?, ?, 1, ?, ?, ?)", -1, &statement, nil) == SQLITE_OK)
        defer { sqlite3_finalize(statement) }
        let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        for (index, text) in [(1, host), (2, name), (3, value), (5, path), (7, partition)] {
            #expect(text.withCString { sqlite3_bind_text(statement, Int32(index), $0, -1, transient) } == SQLITE_OK)
        }
        #expect(encrypted.withUnsafeBytes { sqlite3_bind_blob(statement, 4, $0.baseAddress, Int32($0.count), transient) } == SQLITE_OK)
        #expect(sqlite3_bind_int64(statement, 6, Int64((expires + 11_644_473_600) * 1_000_000)) == SQLITE_OK)
        #expect(sqlite3_bind_int(statement, 8, persistent ? 1 : 0) == SQLITE_OK)
        #expect(sqlite3_bind_int(statement, 9, persistent ? 1 : 0) == SQLITE_OK)
        #expect(sqlite3_step(statement) == SQLITE_DONE)
    }
    func files(at directory: URL) throws -> [String: Data] {
        let files = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
        return try Dictionary(uniqueKeysWithValues: files.map { ($0.lastPathComponent, try Data(contentsOf: $0)) })
    }
    func permissions(_ file: URL) throws -> Int {
        try #require(FileManager.default.attributesOfItem(atPath: file.path)[.posixPermissions] as? NSNumber).intValue
    }
    func rootContents() throws -> [String] { try FileManager.default.contentsOfDirectory(atPath: root.path) }
    func forceModifiedTime(_ file: URL) throws {
        var times = [timespec(tv_sec: 1_800_000_000, tv_nsec: 0), timespec(tv_sec: 1_800_000_001, tv_nsec: 0)]
        #expect(times.withUnsafeMutableBufferPointer { utimensat(AT_FDCWD, file.path, $0.baseAddress!, 0) } == 0)
    }
}

private final class BalanceBrowserReadMutation: @unchecked Sendable {
    private let lock = NSLock()
    private let device: dev_t
    private let inode: ino_t
    private let mutation: @Sendable () throws -> Void
    private var mutated = false
    var didMutate: Bool { lock.withLock { mutated } }

    init(observedFile: URL, mutation: @escaping @Sendable () throws -> Void) throws {
        var metadata = stat()
        try #require(lstat(observedFile.path, &metadata) == 0)
        device = metadata.st_dev
        inode = metadata.st_ino
        self.mutation = mutation
    }

    func read(_ descriptor: Int32, _ bytes: UnsafeMutableRawPointer, _ count: Int) -> Int {
        let result = Darwin.read(descriptor, bytes, count)
        var metadata = stat()
        guard result == 0, fstat(descriptor, &metadata) == 0, metadata.st_dev == device, metadata.st_ino == inode
        else { return result }
        let shouldMutate = lock.withLock { () -> Bool in
            guard !mutated else { return false }
            mutated = true
            return true
        }
        if shouldMutate {
            do { try mutation() }
            catch { Issue.record("Fixture mutation failed: \(error)"); return -1 }
        }
        return result
    }
}

private final class BalanceBrowserReadCapture: @unchecked Sendable {
    private let lock = NSLock()
    private var captured: [Int32: (dev_t, ino_t)] = [:]

    func record(_ descriptor: Int32) {
        var metadata = stat()
        if fstat(descriptor, &metadata) == 0 {
            lock.withLock { captured[descriptor] = (metadata.st_dev, metadata.st_ino) }
        }
    }

    var containsOpenSourceDescriptor: Bool {
        lock.withLock {
            captured.contains { descriptor, identity in
                var metadata = stat()
                return fstat(descriptor, &metadata) == 0 && metadata.st_dev == identity.0 && metadata.st_ino == identity.1
            }
        }
    }
}

private final class BalanceBrowserMemorySecrets: AIAgentSecretStoring, @unchecked Sendable {
    private let lock = NSLock()
    private var valuesStore: [String: String] = [:]
    var values: [String: String] { lock.withLock { valuesStore } }
    func secret(for reference: String) throws -> String? { lock.withLock { valuesStore[reference] } }
    func setSecret(_ secret: String, for reference: String) throws { lock.withLock { valuesStore[reference] = secret } }
    func removeSecret(for reference: String) throws { _ = lock.withLock { valuesStore.removeValue(forKey: reference) } }
}
