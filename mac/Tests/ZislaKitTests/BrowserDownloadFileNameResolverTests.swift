import Foundation
import SQLite3
import Testing

@testable import ZislaKit

struct BrowserDownloadHistoryFixture {
    let root: URL
    let home: URL
    let databaseURL: URL
    let temporaryURL: URL

    init(historyPath: String = "Google/Chrome/Default/History") throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        home = root.appendingPathComponent("Home", isDirectory: true)
        databaseURL = home.appendingPathComponent("Library/Application Support/\(historyPath)")
        temporaryURL = root.appendingPathComponent("Downloads/未确认 156370.crdownload")
        try FileManager.default.createDirectory(
            at: databaseURL.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: temporaryURL.deletingLastPathComponent(), withIntermediateDirectories: true
        )
    }

    func insertDownload(
        currentPath: String? = nil,
        targetPath: String,
        state: Int32 = 0,
        startTime: Int64 = 1,
        databaseURL: URL? = nil
    ) throws {
        let databaseURL = databaseURL ?? self.databaseURL
        try FileManager.default.createDirectory(
            at: databaseURL.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        var connection: OpaquePointer?
        let opened = sqlite3_open(databaseURL.path, &connection)
        defer { sqlite3_close(connection) }
        #expect(opened == SQLITE_OK)
        let database = try #require(connection)
        #expect(sqlite3_exec(database, """
            CREATE TABLE IF NOT EXISTS downloads (
                current_path TEXT, target_path TEXT, state INTEGER, start_time INTEGER
            )
            """, nil, nil, nil) == SQLITE_OK)
        var statement: OpaquePointer?
        #expect(sqlite3_prepare_v2(database, "INSERT INTO downloads VALUES (?, ?, ?, ?)", -1, &statement, nil) == SQLITE_OK)
        defer { sqlite3_finalize(statement) }
        let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        #expect((currentPath ?? temporaryURL.path).withCString {
            sqlite3_bind_text(statement, 1, $0, -1, transient)
        } == SQLITE_OK)
        #expect(targetPath.withCString { sqlite3_bind_text(statement, 2, $0, -1, transient) } == SQLITE_OK)
        #expect(sqlite3_bind_int(statement, 3, state) == SQLITE_OK)
        #expect(sqlite3_bind_int64(statement, 4, startTime) == SQLITE_OK)
        #expect(sqlite3_step(statement) == SQLITE_DONE)
    }
}

struct BrowserDownloadFileNameResolverTests {
    @Test(arguments: [
        (BrowserDownloadAgent.chrome, "Google/Chrome/Default/History"),
        (.chrome, "Google/Chrome Beta/Profile 1/History"),
        (.chrome, "Google/Chrome Canary/Default/History"),
        (.edge, "Microsoft Edge/Default/History"),
        (.edge, "Microsoft Edge Beta/Profile 2/History"),
        (.brave, "BraveSoftware/Brave-Browser/Default/History"),
        (.brave, "BraveSoftware/Brave-Browser-Beta/Default/History"),
        (.arc, "Arc/User Data/Default/History"),
        (.vivaldi, "Vivaldi/Default/History"),
        (.opera, "com.operasoftware.Opera/History"),
        (.opera, "com.operasoftware.OperaGX/Default/History"),
    ])
    func unconfirmedDownloadDisplaysItsTargetName(agent: BrowserDownloadAgent, historyPath: String) throws {
        let fixture = try BrowserDownloadHistoryFixture(historyPath: historyPath)
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        try fixture.insertDownload(targetPath: fixture.root.appendingPathComponent("Downloads/Cursor-darwin-arm64.dmg").path)
        let names = BrowserDownloadFileNameResolver(homeDirectory: fixture.home)
            .fileNames(for: [fixture.temporaryURL: agent])

        let displayed = names[fixture.temporaryURL]
            ?? BrowserDownloadAgentResolver.displayFileName(for: fixture.temporaryURL)
        #expect(displayed == "Cursor-darwin-arm64.dmg")
    }

    @Test
    func exactPathsAndQuotedNamesKeepConcurrentDownloadsSeparate() throws {
        let fixture = try BrowserDownloadHistoryFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let quoted = fixture.temporaryURL.deletingLastPathComponent().appendingPathComponent("Unconfirmed ' OR 1=1 --.crdownload")
        try fixture.insertDownload(targetPath: "/Downloads/Cursor-darwin-arm64.dmg")
        try fixture.insertDownload(currentPath: quoted.path, targetPath: "/Downloads/学习资料 '1'.zip")
        try fixture.insertDownload(currentPath: "/Other/未确认 156370.crdownload", targetPath: "/Downloads/unrelated.dmg", startTime: 99)
        let before = try Data(contentsOf: fixture.databaseURL)
        let filesBefore = try FileManager.default.contentsOfDirectory(atPath: fixture.databaseURL.deletingLastPathComponent().path)
        let names = BrowserDownloadFileNameResolver(homeDirectory: fixture.home)
            .fileNames(for: [fixture.temporaryURL: .chrome, quoted: .chrome])

        #expect(names == [fixture.temporaryURL: "Cursor-darwin-arm64.dmg", quoted: "学习资料 '1'.zip"])
        #expect(try Data(contentsOf: fixture.databaseURL) == before)
        #expect(try FileManager.default.contentsOfDirectory(atPath: fixture.databaseURL.deletingLastPathComponent().path) == filesBefore)
    }

    @Test(arguments: [1, 2, 3])
    func completedCancelledAndInterruptedRecordsDoNotNameANewDownload(state: Int32) throws {
        let fixture = try BrowserDownloadHistoryFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        try fixture.insertDownload(targetPath: "/Downloads/old.dmg", state: state)
        #expect(BrowserDownloadFileNameResolver(homeDirectory: fixture.home)
            .fileNames(for: [fixture.temporaryURL: .chrome]).isEmpty)
    }

    @Test(arguments: ["", "relative.dmg", "/", "https://example.invalid/file.dmg", "/Downloads/Unconfirmed 1.crdownload"])
    func invalidTargetsKeepTheExistingName(targetPath: String) throws {
        let fixture = try BrowserDownloadHistoryFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        try fixture.insertDownload(targetPath: targetPath)
        #expect(BrowserDownloadFileNameResolver(homeDirectory: fixture.home)
            .fileNames(for: [fixture.temporaryURL: .chrome]).isEmpty)
    }

    @Test(arguments: [false, true])
    func missingAndCorruptDatabasesDoNotCreateOrChangeFiles(corrupt: Bool) throws {
        let fixture = try BrowserDownloadHistoryFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let invalidData = Data("invalid database".utf8)
        if corrupt { try invalidData.write(to: fixture.databaseURL) }
        let temporaryBefore = try FileManager.default.contentsOfDirectory(atPath: fixture.root.path).sorted()
        #expect(BrowserDownloadFileNameResolver(homeDirectory: fixture.home, temporaryDirectory: fixture.root)
            .fileNames(for: [fixture.temporaryURL: .chrome]).isEmpty)
        #expect(try FileManager.default.contentsOfDirectory(atPath: fixture.root.path).sorted() == temporaryBefore)
        if corrupt {
            #expect(try Data(contentsOf: fixture.databaseURL) == invalidData)
        } else {
            #expect(!FileManager.default.fileExists(atPath: fixture.databaseURL.path))
        }
    }

    @Test
    func unsupportedBrowsersAndNonTemporaryURLsDoNotReadChromiumNames() throws {
        let fixture = try BrowserDownloadHistoryFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        try fixture.insertDownload(targetPath: "/Downloads/Cursor.dmg")
        let resolver = BrowserDownloadFileNameResolver(homeDirectory: fixture.home)
        for agent in [BrowserDownloadAgent.airDrop, .safari, .firefox] {
            #expect(resolver.fileNames(for: [fixture.temporaryURL: agent]).isEmpty)
        }
        #expect(resolver.fileNames(for: [:]).isEmpty)
        #expect(resolver.fileNames(for: [fixture.temporaryURL.deletingPathExtension(): .chrome]).isEmpty)
        #expect(resolver.fileNames(for: [URL(string: "https://example.invalid/file.crdownload")!: .chrome]).isEmpty)
    }

    @Test(arguments: [false, true])
    func profileConflictsCannotChooseTheWrongTarget(conflicting: Bool) throws {
        let fixture = try BrowserDownloadHistoryFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        try fixture.insertDownload(targetPath: "/Downloads/Cursor.dmg")
        let otherProfile = fixture.databaseURL.deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Profile 1/History")
        try fixture.insertDownload(targetPath: conflicting ? "/Downloads/other.dmg" : "/Downloads/Cursor.dmg", databaseURL: otherProfile)
        let names = BrowserDownloadFileNameResolver(homeDirectory: fixture.home)
            .fileNames(for: [fixture.temporaryURL: .chrome])
        #expect(names[fixture.temporaryURL] == (conflicting ? nil : "Cursor.dmg"))
    }

    @Test
    func seededQuotedAndUnicodePathsOnlyResolveTheirOwnTargets() throws {
        let fixture = try BrowserDownloadHistoryFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        var seed: UInt64 = 0x156370
        let characters = Array("a' ;()中文😺%_#\\\"")
        var downloads: [URL: BrowserDownloadAgent] = [:]
        var expected: [URL: String] = [:]
        for index in 0..<48 {
            let suffix = String((0..<16).map { _ in
                seed = seed &* 6_364_136_223_846_793_005 &+ 1
                return characters[Int((seed >> 32) % UInt64(characters.count))]
            })
            let current = fixture.temporaryURL.deletingLastPathComponent()
                .appendingPathComponent("Unconfirmed \(index) \(suffix).crdownload")
            let targetName = "download-\(index)-\(suffix).dmg"
            try fixture.insertDownload(currentPath: current.path, targetPath: "/Downloads/\(targetName)")
            downloads[current] = .chrome
            expected[current] = targetName
        }
        #expect(BrowserDownloadFileNameResolver(homeDirectory: fixture.home).fileNames(for: downloads) == expected)
    }

    @Test
    func unrelatedDownloadRecordsCannotExhaustTheReadBudget() throws {
        let fixture = try BrowserDownloadHistoryFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        try fixture.insertDownload(currentPath: "/Other/first.crdownload", targetPath: "/Other/first.dmg")
        var database: OpaquePointer?
        #expect(sqlite3_open(fixture.databaseURL.path, &database) == SQLITE_OK)
        defer { sqlite3_close(database) }
        #expect(sqlite3_exec(database, """
            WITH RECURSIVE records(id) AS (
                SELECT 1 UNION ALL SELECT id + 1 FROM records WHERE id < 10000
            ) INSERT INTO downloads
                SELECT '/Other/' || id || '.crdownload', '/Other/' || id || '.dmg', 0, id FROM records
            """, nil, nil, nil) == SQLITE_OK)
        try fixture.insertDownload(targetPath: "/Downloads/Cursor.dmg")
        #expect(BrowserDownloadFileNameResolver(homeDirectory: fixture.home)
            .fileNames(for: [fixture.temporaryURL: .chrome])[fixture.temporaryURL] == "Cursor.dmg")
    }

    @Test(arguments: ["DELETE", "WAL"])
    func runningBrowserExclusiveLockStillResolvesCommittedTarget(journalMode: String) throws {
        let fixture = try BrowserDownloadHistoryFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        try fixture.insertDownload(targetPath: "/Downloads/old.dmg")
        var database: OpaquePointer?
        #expect(sqlite3_open(fixture.databaseURL.path, &database) == SQLITE_OK)
        defer { sqlite3_close(database) }
        #expect(sqlite3_exec(database, """
            PRAGMA locking_mode=EXCLUSIVE;
            PRAGMA journal_mode=\(journalMode);
            PRAGMA wal_autocheckpoint=0;
            UPDATE downloads SET target_path='/Downloads/Cursor.dmg';
            """, nil, nil, nil) == SQLITE_OK)
        let directory = fixture.databaseURL.deletingLastPathComponent()
        let filesBefore = try FileManager.default.contentsOfDirectory(atPath: directory.path).sorted()
        let dataBefore = try filesBefore.map { try Data(contentsOf: directory.appendingPathComponent($0)) }
        let temporaryBefore = try FileManager.default.contentsOfDirectory(atPath: fixture.root.path).sorted()
        let names = BrowserDownloadFileNameResolver(homeDirectory: fixture.home, temporaryDirectory: fixture.root)
            .fileNames(for: [fixture.temporaryURL: .chrome])
        #expect(names[fixture.temporaryURL] == "Cursor.dmg")
        #expect(try FileManager.default.contentsOfDirectory(atPath: directory.path).sorted() == filesBefore)
        #expect(try filesBefore.map { try Data(contentsOf: directory.appendingPathComponent($0)) } == dataBefore)
        #expect(try FileManager.default.contentsOfDirectory(atPath: fixture.root.path).sorted() == temporaryBefore)
    }
}
