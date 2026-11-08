import Foundation
import SQLite3
import Testing
import ZislaCore

@testable import ZislaKit

struct AISessionWorkspaceCleanupTests {
    @Test
    func codexOnlyOffersDaysWhoseSessionsHaveBeenDeleted() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let orphan = fixture.workspace("Codex", "2026-07-02")
        let retained = fixture.workspace("Codex", "2026-07-06")
        let archived = fixture.workspace("Codex", "2026-07-16")
        try fixture.codexDatabase(rows: [
            ("retained", retained.appendingPathComponent("new-chat").path, "2026-07-06", false),
            ("archived", archived.appendingPathComponent("new-chat").path, "2026-07-16", true),
        ])

        let candidates = fixture.scan()

        #expect(candidates.map(\.url).contains(orphan), "Deleted sessions must leave a cleanable day directory")
        #expect(!candidates.contains { $0.url == retained || $0.url == archived })
    }

    @Test(arguments: [false, true])
    func codexEmptyWorkingDirectoriesKeepTheirDayWithoutBlockingDeletedDays(archived: Bool) throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let retained = fixture.workspace("Codex", "2026-05-25")
        let orphans = ["2026-10-15", "2026-07-02", "2026-11-06", "2026-09-29"].map {
            fixture.workspace("Codex", $0)
        }
        try fixture.codexDatabase(rows: [("no-workspace", "", "2026-05-25", archived)])

        let candidates = fixture.scan()

        #expect(Set(candidates.map(\.url)) == Set(orphans), "An empty cwd must not invalidate the retained-session inventory")
        #expect(candidates.allSatisfy { $0.isActionable })
        for orphan in orphans { fixture.files.trashResults[orphan] = .success(orphan) }
        let result = SystemDiskCleanup.trashSelected(candidates: candidates, fileManager: fixture.files)
        #expect(result.successCount == orphans.count)
        #expect(result.failures.isEmpty)
        #expect(Set(fixture.files.trashedURLs) == Set(orphans))
        #expect(!AISessionWorkspaceCleanup(fileManager: fixture.files, referenceDate: fixture.referenceDate).canTrash(retained))
    }

    @Test
    func retainedAndUnverifiableWorkspacesAreHiddenAndCannotBeTrashed() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let retained = fixture.workspace("Codex", "2026-07-02")
        let orphan = fixture.workspace("Codex", "2026-07-06")
        let unknown = fixture.workspace("ChatGPT", "2026-07-02")
        try fixture.codexDatabase(rows: [("retained", retained.path, "2026-07-02", true)])

        let candidates = fixture.scan()

        #expect(candidates.map(\.url) == [orphan])
        let protected = [retained, unknown].map {
            DiskCleanupCandidate(url: $0, kind: .aiSessionWorkspace, byteSize: 4096, displayName: $0.lastPathComponent)
        }
        let result = SystemDiskCleanup.trashSelected(candidates: protected, fileManager: fixture.files)
        #expect(result.successCount == 0)
        #expect(result.failures.count == protected.count)
        #expect(fixture.files.trashedURLs.isEmpty)
    }

    @Test
    func aRetainedSessionCreatedOnTheSameDayProtectsTheWholeDirectory() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let day = fixture.workspace("Codex", "2026-07-02")
        try fixture.codexDatabase(rows: [("retained", fixture.home.appendingPathComponent("project").path, "2026-07-02", true)])

        #expect(!fixture.scan().contains { $0.url == day })
    }

    @Test
    func anOrphanWorkspaceCanBeMovedToTrashWithoutRemovingItsToolRoot() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let day = fixture.workspace("Codex", "2026-07-02")
        try fixture.codexDatabase(rows: [])
        let candidate = try #require(fixture.scan().first { $0.url == day })
        fixture.files.trashResults[day] = .success(fixture.home.appendingPathComponent(".Trash/2026-07-02"))

        let result = SystemDiskCleanup.trashSelected(candidates: [candidate], fileManager: fixture.files, sizeProvider: { _ in 4096 })

        #expect(result.successCount == 1)
        #expect(result.freedBytes == 4096)
        #expect(result.failures.isEmpty)
        #expect(fixture.files.fileExists(atPath: day.deletingLastPathComponent().path))
    }

    @Test
    func cleanupRechecksRestoredAndArchivedSessionsAfterTheScan() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let day = fixture.workspace("Codex", "2026-07-02")
        try fixture.codexDatabase(rows: [])
        let candidate = try #require(fixture.scan().first { $0.url == day })
        try fixture.sql("INSERT INTO threads VALUES ('restored', '\(day.path)/new-chat', 1782993600, 1)", at: fixture.home.appendingPathComponent(".codex/state_5.sqlite"))
        fixture.files.trashResults[day] = .success(fixture.home.appendingPathComponent(".Trash/day"))

        let result = SystemDiskCleanup.trashSelected(candidates: [candidate], fileManager: fixture.files)

        #expect(result.successCount == 0)
        #expect(result.freedBytes == 0)
        #expect(result.failures.count == 1)
        #expect(fixture.files.trashedURLs.isEmpty)
    }

    @Test
    func rawURLsAndForgedOtherCategoriesCannotBypassRetainedSessionProtection() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let day = fixture.workspace("Codex", "2026-07-02")
        let output = day.appendingPathComponent("new-chat/output.txt")
        try fixture.codexDatabase(rows: [("retained", day.path, "2026-07-02", true)])
        let forged = DiskCleanupCandidate(url: output, kind: .largeFile, byteSize: 4096, displayName: "output.txt")

        for url in [day, output, day.deletingLastPathComponent(), fixture.home.appendingPathComponent("Documents")] {
            let result = SystemDiskCleanup.trashSelected(urls: [url], fileManager: fixture.files)
            #expect(result.successCount == 0)
            #expect(result.failures.count == 1)
        }
        #expect(SystemDiskCleanup.trashSelected(candidates: [forged], fileManager: fixture.files).successCount == 0)
        #expect(fixture.files.trashedURLs.isEmpty)
    }

    @Test
    func otherFileScansDoNotOfferFilesInsideManagedSessionRoots() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let day = fixture.workspace("Codex", "2026-07-02")
        let orphan = fixture.workspace("Codex", "2026-07-06")
        try fixture.codexDatabase(rows: [("retained", day.path, "2026-07-02", false)])
        let output = day.appendingPathComponent("new-chat/output.txt")
        fixture.files.fileAttributes[output.path]?[.modificationDate] = Date(timeIntervalSince1970: 0)
        let snapshots = Snapshots()
        let candidates = SystemDiskCleanup.scanCandidatesWithProgress(
            fileManager: fixture.files, kinds: [.largeFile, .aiSessionWorkspace], maxConcurrentScans: 1,
            options: DiskCleanupScanOptions(largeFileThreshold: 1, oldFileAge: 0, referenceDate: fixture.referenceDate),
            onProgress: { snapshots.append($0) }
        )
        #expect(candidates.map(\.url) == [orphan])
        #expect(!snapshots.values.isEmpty)
        #expect(snapshots.values.allSatisfy { $0.allSatisfy { $0.url == orphan && $0.kind == .aiSessionWorkspace && $0.isActionable } })
    }

    @Test
    func nonDateRootsBackupsAndInvalidDaysAreNeverOffered() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        try fixture.codexDatabase(rows: [])
        let orphan = fixture.workspace("Codex", "2026-07-02")
        for name in ["Backups", "cc-connect-workspace", "2026-02-30", "2026-13-01", "2026-11-07", "2099-01-01", "2026-07-02-extra"] {
            fixture.workspace("Codex", name)
        }

        #expect(fixture.scan().map(\.url) == [orphan])
    }

    @Test
    func missingAndDamagedInventoriesProtectWorkspaces() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        fixture.workspace("Codex", "2026-07-02")
        #expect(fixture.scan().isEmpty)
        let database = fixture.home.appendingPathComponent(".codex/state_5.sqlite")
        try FileManager.default.createDirectory(at: database.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("damaged sqlite".utf8).write(to: database)
        fixture.file(database, data: Data())
        #expect(fixture.scan().isEmpty)
        #expect(fixture.files.trashedURLs.isEmpty)
    }

    @Test
    func aBrokenInventoryKeepsItsToolWithoutBlockingVerifiedTools() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let orphan = fixture.workspace("Codex", "2026-07-02")
        let unknown = fixture.workspace("Claude Code", "2026-07-02")
        try fixture.codexDatabase(rows: [])
        fixture.jsonLog(".claude/projects/project/session.jsonl", "{broken\n")

        #expect(fixture.scan().map(\.url) == [orphan])
        #expect(!AISessionWorkspaceCleanup(fileManager: fixture.files, referenceDate: fixture.referenceDate).canTrash(unknown))
    }

    @Test(arguments: ["sessions", "archived_sessions"])
    func codexLegacyRolloutsKeepUnarchivedAndArchivedDays(folder: String) throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let retained = fixture.workspace("Codex", "2026-07-02")
        let orphan = fixture.workspace("Codex", "2026-07-06")
        fixture.jsonLog(".codex/\(folder)/2026/07/02/rollout-retained.jsonl", """
            {"type":"session_meta","timestamp":"2026-07-02T12:00:00Z","payload":{"id":"retained","cwd":"\(retained.path)/new-chat","timestamp":"2026-07-02T12:00:00Z"}}
            {"type":"response_item","payload":{"content":"irrelevant"}}

            """)

        #expect(fixture.scan().map(\.url) == [orphan])
    }

    @Test(arguments: ["Claude Code", "Pi", "Qwen"])
    func structuredTranscriptInventoriesProtectRetainedDays(tool: String) throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let day = fixture.workspace(tool, "2026-07-02")
        let orphan = fixture.workspace(tool, "2026-07-06")
        let paths = ["Claude Code": ".claude/projects/project/session.jsonl", "Pi": ".pi/agent/sessions/project/session.jsonl",
                     "Qwen": ".qwen/projects/project/session.jsonl"]
        fixture.jsonLog(try #require(paths[tool]), """
            {"type":"session","id":"retained","cwd":"\(day.path)/new-chat","timestamp":"2026-07-02T12:00:00Z"}

            """)

        #expect(fixture.scan().map(\.url) == [orphan])
    }

    @Test(arguments: ["Gemini", "OpenCode"])
    func jsonInventoriesKeepArchivedSessions(tool: String) throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let day = fixture.workspace(tool, "2026-07-02")
        let orphan = fixture.workspace(tool, "2026-07-06")
        let paths = ["Gemini": ".gemini/tmp/project/chats/session-retained.json",
                     "OpenCode": ".local/share/opencode/storage/session/project/id.json"]
        let object: [String: Any] = tool == "OpenCode"
            ? ["id": "retained", "directory": day.path, "time": ["created": 1_782_993_600_000], "time_archived": 1]
            : ["id": "retained", "cwd": day.path, "startTime": "2026-07-02T12:00:00Z", "created_at": "2026-07-02T12:00:00Z", "archived": true]
        fixture.file(fixture.home.appendingPathComponent(try #require(paths[tool])), data: try JSONSerialization.data(withJSONObject: object))

        #expect(fixture.scan().map(\.url) == [orphan])
    }

    @Test(arguments: ["OpenCode", "ZCode", "WorkBuddy", "WorkBuddy AI", "Zed", "Delta"])
    func databaseInventoriesKeepFinishedAndArchivedSessions(tool: String) throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let day = fixture.workspace(tool, "2026-07-02")
        let orphan = fixture.workspace(tool, "2026-07-06")
        let store = try #require(Self.databaseFixtures[tool])
        let url = fixture.home.appendingPathComponent(store.path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try fixture.sql(store.schema, at: url)
        try fixture.sql(store.insert.replacingOccurrences(of: "$CWD", with: day.path), at: url)
        fixture.file(url, data: Data())

        #expect(fixture.scan().map(\.url) == [orphan])
    }

    @Test(arguments: ["OpenCode", "ZCode", "WorkBuddy", "WorkBuddy AI"])
    func emptyWorkingDirectoriesInOtherDatabasesStillProtectTheirSessionDay(tool: String) throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let retained = fixture.workspace(tool, "2026-07-02")
        let orphan = fixture.workspace(tool, "2026-07-06")
        let store = try #require(Self.databaseFixtures[tool])
        let database = fixture.home.appendingPathComponent(store.path)
        try FileManager.default.createDirectory(at: database.deletingLastPathComponent(), withIntermediateDirectories: true)
        try fixture.sql(store.schema, at: database)
        try fixture.sql(store.insert.replacingOccurrences(of: "$CWD", with: ""), at: database)
        fixture.file(database, data: Data())

        #expect(fixture.scan().map(\.url) == [orphan])
        #expect(!AISessionWorkspaceCleanup(fileManager: fixture.files, referenceDate: fixture.referenceDate).canTrash(retained))
    }

    @Test(arguments: ["project", "./project", "../project", "~/project"])
    func nonemptyRelativeDatabaseWorkingDirectoriesRemainUnverifiable(cwd: String) throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let day = fixture.workspace("Codex", "2026-07-02")
        try fixture.codexDatabase(rows: [("invalid-path", cwd, "2026-07-06", false)])

        #expect(fixture.scan().isEmpty)
        #expect(!AISessionWorkspaceCleanup(fileManager: fixture.files, referenceDate: fixture.referenceDate).canTrash(day))
        #expect(fixture.files.trashedURLs.isEmpty)
    }

    @Test
    func anotherToolsRetainedWorkspaceReferenceProtectsTheCodexDay() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let day = fixture.workspace("Codex", "2026-07-02")
        try fixture.codexDatabase(rows: [])
        fixture.jsonLog(".claude/projects/project/session.jsonl", """
            {"type":"user","sessionId":"retained","cwd":"\(day.path)/new-chat","timestamp":"2026-07-20T12:00:00Z"}

            """)

        #expect(fixture.scan().isEmpty)
    }

    @Test
    func parentWorkingDirectoriesDoNotProtectUnreferencedDatedWorkspaces() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let orphan = fixture.workspace("Codex", "2026-07-02")
        let retained = fixture.workspace("Codex", "2026-07-06")
        let referenced = fixture.workspace("Codex", "2026-07-16")
        try fixture.codexDatabase(rows: [("retained", orphan.deletingLastPathComponent().path, "2026-07-06", true)])
        fixture.jsonLog(".claude/projects/project/parent.jsonl", """
            {"type":"user","sessionId":"home","cwd":"\(fixture.home.path)","timestamp":"2026-07-20T12:00:00Z"}

            """)
        fixture.jsonLog(".pi/agent/sessions/project/parent.jsonl", """
            {"type":"session","id":"documents","cwd":"\(fixture.home.path)/Documents","timestamp":"2026-07-20T12:00:00Z"}

            """)
        fixture.jsonLog(".claude/projects/project/referenced.jsonl", """
            {"type":"user","sessionId":"referenced","cwd":"\(referenced.path)/new-chat","timestamp":"2026-07-20T12:00:00Z"}

            """)

        let candidates = fixture.scan()

        #expect(candidates.map(\.url) == [orphan], "Launching from a parent directory does not reference every dated workspace")
        fixture.files.trashResults[orphan] = .success(orphan)
        let result = SystemDiskCleanup.trashSelected(candidates: candidates, fileManager: fixture.files)
        #expect(result.successCount == 1)
        #expect(result.failures.isEmpty)
        #expect(fixture.files.trashedURLs == [orphan])
        let cleanup = AISessionWorkspaceCleanup(fileManager: fixture.files, referenceDate: fixture.referenceDate)
        #expect(!cleanup.canTrash(retained))
        #expect(!cleanup.canTrash(referenced))
    }

    @Test
    func codexDatabaseOverridesStaleRolloutsAndPreservesCompressedSessions() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let orphan = fixture.workspace("Codex", "2026-07-02")
        try fixture.codexDatabase(rows: [])
        fixture.jsonLog(".codex/sessions/2026/07/02/rollout-stale.jsonl.zst", "compressed bytes")

        #expect(fixture.scan().map(\.url) == [orphan])
    }

    @Test
    func symbolicallyLinkedDaysAndStoresAreNeverTrusted() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let day = fixture.workspace("Codex", "2026-07-02")
        try fixture.codexDatabase(rows: [])
        fixture.files.fileAttributes[day.path]?[.type] = FileAttributeType.typeSymbolicLink
        #expect(fixture.scan().isEmpty)
        fixture.files.fileAttributes[day.path]?[.type] = FileAttributeType.typeDirectory
        fixture.files.fileAttributes[fixture.home.appendingPathComponent(".codex/state_5.sqlite").path]?[.type] = FileAttributeType.typeSymbolicLink
        #expect(fixture.scan().isEmpty)
    }

    @Test
    func everySupportedProviderHasADirectoryAliasAndUnknownNamesAreExcluded() {
        for provider in AIProvider.allCases {
            #expect(AISessionWorkspaceCleanup.provider(forDirectoryName: provider.rawValue) == provider)
            #expect(AISessionWorkspaceCleanup.provider(forDirectoryName: AIMascotLibrary.providerDisplayName(for: provider)) == provider)
        }
        for name in ["backups", "CodexProjects", "important-work", "qoderish", "some-ai"] {
            #expect(AISessionWorkspaceCleanup.provider(forDirectoryName: name) == nil)
        }
    }

    @Test
    func opaqueStoresAreProtectedFromGenericFileCleanup() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        for tool in ["TRAE", "Orca", "ChatGPT", "DeepSeek", "Muse", "Doubao", "Grok Bot"] {
            let day = fixture.workspace(tool, "2026-07-02")
            #expect(SystemDiskCleanup.trashSelected(urls: [day], fileManager: fixture.files).successCount == 0)
        }
        #expect(fixture.scan().isEmpty)
    }

    @Test
    func workBuddyDeletionMarkersAllowCleanupWhileArchiveStatusDoesNot() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let deleted = fixture.workspace("WorkBuddy", "2026-07-02")
        let archived = fixture.workspace("WorkBuddy", "2026-07-06")
        let database = fixture.home.appendingPathComponent(".workbuddy/workbuddy.db")
        try FileManager.default.createDirectory(at: database.deletingLastPathComponent(), withIntermediateDirectories: true)
        try fixture.sql("CREATE TABLE sessions(id TEXT, cwd TEXT, created_at INTEGER, deleted_at INTEGER, status TEXT)", at: database)
        try fixture.sql("INSERT INTO sessions VALUES ('deleted','\(deleted.path)',1782993600000,1,'Archived'), ('archived','\(archived.path)',1783339200000,NULL,'Archived')", at: database)
        fixture.file(database, data: Data())

        #expect(fixture.scan().map(\.url) == [deleted])
    }

    @Test
    func grokSummaryMetadataKeepsItsOriginalDayAndWorkingDirectory() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let retained = fixture.workspace("Grok", "2026-07-02")
        let orphan = fixture.workspace("Grok", "2026-07-06")
        fixture.file(fixture.home.appendingPathComponent(".grok/sessions/project/id/summary.json"), data: try JSONSerialization.data(withJSONObject: [
            "info": ["id": "retained", "cwd": retained.path], "created_at": "2026-07-02T12:00:00Z", "updated_at": "2026-07-20T12:00:00Z",
        ]))

        #expect(fixture.scan().map(\.url) == [orphan])
    }

    @Test
    func copilotCLISessionMetadataKeepsItsDay() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let retained = fixture.workspace("Copilot", "2026-07-02")
        let orphan = fixture.workspace("Copilot", "2026-07-06")
        fixture.jsonLog(".copilot/session-state/id/workspace.yaml", "id: retained\ncwd: \(retained.path)\ncreated_at: 2026-07-02T12:00:00Z\nupdated_at: 2026-07-20T12:00:00Z\n")

        #expect(fixture.scan().map(\.url) == [orphan])
    }

    @Test
    func qoderTranscriptStoreTakesPrecedenceOverStaleActivitySegments() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let day = fixture.workspace("Qoder", "2026-07-02")
        let orphan = fixture.workspace("Qoder", "2026-07-06")
        fixture.jsonLog(".qoderworkcn/projects/project/session.jsonl", """
            {"type":"runtime-config","sessionId":"retained","timestamp":"2026-07-02T12:00:00Z"}
            {"type":"user","sessionId":"retained","cwd":"\(day.path)","timestamp":"2026-07-02T12:00:00Z"}

            """)
        fixture.jsonLog(".qoderworkcn/logs/sessions/other/segments/0.jsonl", "broken activity log")

        #expect(fixture.scan().map(\.url) == [orphan])
    }

    @Test
    func qoderActivitySegmentsDoNotProveConversationDeletion() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let day = fixture.workspace("Qoder", "2026-07-02")
        let orphan = fixture.workspace("Qoder", "2026-07-06")
        fixture.jsonLog(".qoder/logs/sessions/id/segments/0.jsonl", """
            {"type":"session.config.loaded","ts":"2026-07-02T12:00:00Z","data":{"target_dir":"\(day.path)","project_root":"\(day.path)"}}

            """)

        #expect(fixture.scan().isEmpty)
        let cleanup = AISessionWorkspaceCleanup(fileManager: fixture.files, referenceDate: fixture.referenceDate)
        #expect(!cleanup.canTrash(day))
        #expect(!cleanup.canTrash(orphan))
    }

    @Test
    func configuredCodexHomeUsesTheConfiguredStore() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let day = fixture.workspace("Codex", "2026-07-02")
        let root = fixture.home.appendingPathComponent("custom-codex")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let database = root.appendingPathComponent("state_9.sqlite")
        try fixture.sql("CREATE TABLE threads(id TEXT, cwd TEXT, created_at INTEGER); INSERT INTO threads VALUES ('retained','\(day.path)',1782993600)", at: database)
        fixture.file(database, data: Data())

        let cleanup = AISessionWorkspaceCleanup(fileManager: fixture.files, referenceDate: fixture.referenceDate, environment: ["CODEX_HOME": root.path])

        #expect(cleanup.candidates().isEmpty)
        #expect(!cleanup.canTrash(day))
    }

    @Test
    func malformedMetadataCorpusFailsClosedWithinABoundedRead() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let day = fixture.workspace("Claude Code", "2026-07-02")
        let file = fixture.home.appendingPathComponent(".claude/projects/project/session.jsonl")
        var seed: UInt64 = 0x542
        let fixedCorpus: [Data] = [Data(), Data("{\n".utf8), Data("null\n".utf8), Data("[]\n".utf8),
                                 Data("{\"cwd\":\"../../outside\",\"timestamp\":\"2026-07-02T12:00:00Z\"}\n".utf8),
                                 Data(repeating: 0x20, count: 256 * 1024 + 1)]
        for bytes in fixedCorpus {
            fixture.file(file, data: bytes)
            #expect(fixture.scan().isEmpty)
            #expect(!AISessionWorkspaceCleanup(fileManager: fixture.files, referenceDate: fixture.referenceDate).canTrash(day))
        }
        for _ in 0..<24 {
            seed = seed &* 6_364_136_223_846_793_005 &+ 1
            let bytes = Data((0..<64).map { index in UInt8(truncatingIfNeeded: seed >> (index % 8 * 8)) })
            fixture.fileContents(file, bytes)
            #expect(fixture.scan().isEmpty)
        }
        #expect(fixture.files.trashedURLs.isEmpty)
    }

    @Test
    func productionPrefixReadsStayBoundedAndDoNotWriteToTheSource() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let file = fixture.home.appendingPathComponent("large-session.jsonl")
        let bytes = Data(repeating: 0x61, count: 1024 * 1024)
        try bytes.write(to: file)
        let manager = DefaultSystemMonitorFileManager()

        #expect(manager.readPrefix(at: file, maximumBytes: 128) == bytes.prefix(128))
        #expect(manager.readPrefix(at: fixture.home.appendingPathComponent("missing.jsonl"), maximumBytes: 128) == nil)
        #expect(try Data(contentsOf: file) == bytes)
    }

    @Test
    func unrelatedCacheCleanupDoesNotReadSessionMetadata() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        fixture.workspace("Claude Code", "2026-07-02")
        fixture.jsonLog(".claude/projects/project/session.jsonl", "broken metadata")
        let cache = fixture.home.appendingPathComponent("Library/Caches/cache")
        fixture.files.existingPaths.insert(cache.path)
        fixture.files.trashResults[cache] = .success(fixture.home.appendingPathComponent(".Trash/cache"))
        let root = fixture.home.appendingPathComponent(".claude/projects")
        let reads = fixture.files.directoryReadCount(atPath: root.path)

        let result = SystemDiskCleanup.trashSelected(urls: [cache], fileManager: fixture.files, allowedRoots: [cache])

        #expect(result.successCount == 1)
        #expect(fixture.files.directoryReadCount(atPath: root.path) == reads)
        _ = SystemDiskCleanup.scanCandidates(fileManager: fixture.files, kinds: [.appCache])
        #expect(fixture.files.directoryReadCount(atPath: root.path) == reads)
    }

    @Test
    func copilotPersistedChatSessionsKeepDatesAndCrossToolWorkspaceReferences() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let day = fixture.workspace("Copilot", "2026-07-02")
        let orphan = fixture.workspace("Copilot", "2026-07-06")
        let shared = fixture.workspace("Codex", "2026-07-20")
        try fixture.codexDatabase(rows: [])
        let workspace = fixture.home.appendingPathComponent("Library/Application Support/Code/User/workspaceStorage/id")
        fixture.file(workspace.appendingPathComponent("workspace.json"), data: try JSONSerialization.data(withJSONObject: ["folder": shared.absoluteString]))
        fixture.file(workspace.appendingPathComponent("chatSessions/retained.jsonl"), data: try JSONSerialization.data(withJSONObject: [
            "kind": 0, "v": ["sessionId": "retained", "creationDate": 1_782_993_600_000],
        ]))

        let candidates = fixture.scan()

        #expect(!candidates.contains { $0.url == day || $0.url == shared })
        #expect(candidates.map(\.url) == [orphan])
    }

    @Test(arguments: ["cursorDiskKV", "composerHeaders"])
    func cursorArchivedSessionsRemainProtectedInEitherMetadataStore(table: String) throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let day = fixture.workspace("Cursor", "2026-07-02")
        let orphan = fixture.workspace("Cursor", "2026-07-06")
        let database = fixture.home.appendingPathComponent("Library/Application Support/Cursor/User/globalStorage/state.vscdb")
        try FileManager.default.createDirectory(at: database.deletingLastPathComponent(), withIntermediateDirectories: true)
        try fixture.sql("CREATE TABLE \(table)(key TEXT, value TEXT); INSERT INTO \(table) VALUES ('composerData:retained', '{\"composerId\":\"retained\",\"createdAt\":1782993600000,\"isArchived\":true}')", at: database)
        fixture.file(database, data: Data())

        #expect(fixture.scan().map(\.url) == [orphan])
        #expect(!AISessionWorkspaceCleanup(fileManager: fixture.files).canTrash(day))
    }

    @Test
    func geminiDesktopChatsKeepTheirCreationDay() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let day = fixture.workspace("Gemini", "2026-07-02")
        let orphan = fixture.workspace("Gemini", "2026-07-06")
        let database = fixture.home.appendingPathComponent("Library/Caches/com.google.GeminiMacOS/Gemini/profile/ChatInfo2.store")
        try FileManager.default.createDirectory(at: database.deletingLastPathComponent(), withIntermediateDirectories: true)
        try fixture.sql("CREATE TABLE ZCHATMESSAGESTOREDMODEL(ZCHATUUID TEXT, ZCREATEDTIME REAL); INSERT INTO ZCHATMESSAGESTOREDMODEL VALUES ('retained', \(1_782_993_600 - 978_307_200))", at: database)
        fixture.file(database, data: Data())

        #expect(fixture.scan().map(\.url) == [orphan])
        #expect(!AISessionWorkspaceCleanup(fileManager: fixture.files).canTrash(day))
    }

    @Test
    func metadataProtectionDoesNotHideUnrelatedAIToolCaches() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        fixture.workspace("Codex", "2026-07-02")
        try fixture.codexDatabase(rows: [])
        let cache = fixture.home.appendingPathComponent(".workbuddy/cache")
        let database = fixture.home.appendingPathComponent(".workbuddy/workbuddy.db")
        fixture.directory(cache)
        let cleanup = AISessionWorkspaceCleanup(fileManager: fixture.files)

        #expect(cleanup.canTrash(cache))
        #expect(!cleanup.canTrash(database))
        #expect(!cleanup.canTrash(database.deletingLastPathComponent()))
        #expect(!cleanup.canTrash(fixture.home.appendingPathComponent("Library/Caches/com.google.GeminiMacOS")))
    }

    @Test
    func unavailableFileAttributesInvalidateTheSessionInventory() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let day = fixture.workspace("Claude Code", "2026-07-02")
        fixture.jsonLog(".claude/projects/project/session.jsonl", "{\"type\":\"session\",\"cwd\":\"\(day.path)\",\"timestamp\":\"2026-07-02T12:00:00Z\"}\n")
        fixture.files.fileAttributes.removeValue(forKey: fixture.home.appendingPathComponent(".claude/projects/project").path)

        #expect(fixture.scan().isEmpty)
        #expect(!AISessionWorkspaceCleanup(fileManager: fixture.files).canTrash(day))
    }

    @Test
    func forgedWorkspaceCandidatesMustPointAtAWholeRecognizedWorkspace() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let day = fixture.workspace("Codex", "2026-07-02")
        try fixture.codexDatabase(rows: [])
        let output = day.appendingPathComponent("new-chat/output.txt")
        let candidate = DiskCleanupCandidate(url: output, kind: .aiSessionWorkspace, byteSize: 4096, displayName: "output.txt")
        fixture.files.trashResults[output] = .success(output)

        #expect(SystemDiskCleanup.trashSelected(candidates: [candidate], fileManager: fixture.files).successCount == 0)
        #expect(fixture.files.trashedURLs.isEmpty)
    }

    @Test
    func missingDatabaseIsNotCreatedDuringReadOnlyVerification() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        fixture.workspace("Codex", "2026-07-02")
        let database = fixture.home.appendingPathComponent(".codex/state_5.sqlite")
        try FileManager.default.createDirectory(at: database.deletingLastPathComponent(), withIntermediateDirectories: true)
        fixture.file(database, data: Data())

        #expect(fixture.scan().isEmpty)
        #expect(!FileManager.default.fileExists(atPath: database.path))
    }

    @Test(arguments: ["directory", "rows", "depth"])
    func inventoriesThatExceedTheScanBudgetRemainProtected(limit: String) throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let day = fixture.workspace(limit == "rows" ? "Codex" : "Claude Code", "2026-07-02")
        if limit == "rows" {
            try fixture.codexDatabase(rows: [])
            try fixture.sql("WITH RECURSIVE numbers(n) AS (VALUES(1) UNION ALL SELECT n+1 FROM numbers WHERE n<20001) INSERT INTO threads SELECT CAST(n AS TEXT), '/project', 1783339200, 0 FROM numbers", at: fixture.home.appendingPathComponent(".codex/state_5.sqlite"))
        } else {
            let root = fixture.home.appendingPathComponent(".claude/projects")
            fixture.directory(root)
            if limit == "directory" {
                let file = root.appendingPathComponent("unrelated.dat")
                fixture.file(file, data: Data())
                fixture.files.directoryContents[root.path] = Array(repeating: file, count: 20_001)
            } else {
                fixture.jsonLog(".claude/projects/a/b/c/d/e/f/g/h/i/session.jsonl", "{\"cwd\":\"/project\",\"timestamp\":\"2026-07-06T12:00:00Z\"}\n")
            }
        }

        #expect(fixture.scan().isEmpty)
        #expect(!AISessionWorkspaceCleanup(fileManager: fixture.files).canTrash(day))
        #expect(fixture.files.trashedURLs.isEmpty)
    }

    @Test(arguments: ["documents", "inventory"])
    func directoryReadFailuresPreserveWorkspaces(failingDirectory: String) throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let day = fixture.workspace("Codex", "2026-07-02")
        try fixture.codexDatabase(rows: [])
        let path = fixture.home.appendingPathComponent(failingDirectory == "documents" ? "Documents" : ".codex").path
        fixture.files.directoryErrors[path] = .fileReadNoPermission
        fixture.files.trashResults[day] = .success(day)

        #expect(SystemDiskCleanup.trashSelected(urls: [day], fileManager: fixture.files).successCount == 0)
        #expect(fixture.files.trashedURLs.isEmpty)
    }

    @Test
    func symbolicallyLinkedInventoryParentsAreNotUsedAsDeletionEvidence() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let day = fixture.workspace("WorkBuddy", "2026-07-02")
        let database = fixture.home.appendingPathComponent(".workbuddy/workbuddy.db")
        try FileManager.default.createDirectory(at: database.deletingLastPathComponent(), withIntermediateDirectories: true)
        try fixture.sql("CREATE TABLE sessions(id TEXT, cwd TEXT, created_at INTEGER, deleted_at INTEGER)", at: database)
        fixture.file(database, data: Data())
        fixture.files.fileAttributes[database.deletingLastPathComponent().path]?[.type] = FileAttributeType.typeSymbolicLink

        #expect(fixture.scan().isEmpty)
        #expect(!AISessionWorkspaceCleanup(fileManager: fixture.files).canTrash(day))
    }

    @Test
    func cursorLegacyMetadataAlsoProtectsArchivedDays() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let retained = fixture.workspace("Cursor", "2026-07-02")
        let orphan = fixture.workspace("Cursor", "2026-07-06")
        let database = fixture.home.appendingPathComponent("Library/Application Support/Cursor/User/globalStorage/state.vscdb")
        try FileManager.default.createDirectory(at: database.deletingLastPathComponent(), withIntermediateDirectories: true)
        try fixture.sql("CREATE TABLE ItemTable(key TEXT, value TEXT); INSERT INTO ItemTable VALUES ('composer.composerData', '{\"allComposers\":[{\"composerId\":\"retained\",\"createdAt\":1782993600000,\"isArchived\":true}]}')", at: database)
        fixture.file(database, data: Data())

        #expect(fixture.scan().map(\.url) == [orphan])
        #expect(!AISessionWorkspaceCleanup(fileManager: fixture.files).canTrash(retained))
    }

    @Test
    func logOnlyAndUndatedInventoriesDoNotEstablishDeletion() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let grok = fixture.workspace("Grok", "2026-07-02")
        let kimi = fixture.workspace("Kimi", "2026-07-02")
        let qoder = fixture.workspace("Qoder", "2026-07-02")
        fixture.jsonLog(".grok/sessions/id/events.jsonl", "{\"type\":\"turn_ended\",\"ts\":\"2026-07-06T12:00:00Z\"}\n")
        fixture.jsonLog(".kimi-code/sessions/workspace/id/state.json", "{\"title\":\"Retained\",\"archived\":true}")
        fixture.jsonLog(".qoder/logs/sessions/id/segments/0.jsonl", "{\"type\":\"session.config.loaded\",\"ts\":\"2026-07-06T12:00:00Z\",\"data\":{\"target_dir\":\"/project\"}}\n")

        #expect(fixture.scan().isEmpty)
        let cleanup = AISessionWorkspaceCleanup(fileManager: fixture.files, referenceDate: fixture.referenceDate)
        for workspace in [grok, kimi, qoder] { #expect(!cleanup.canTrash(workspace)) }
    }

    @Test
    func dateAndSessionIDNamesUseTheirCreationDayAndIdentity() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let temp = fixture.workspace("Codex", "temp_20260702_1")
        let retainedID = fixture.workspace("Codex", "01A1B4C5-B784-7931-9051-03DEC1E9BB5C")
        let orphanID = fixture.workspace("Codex", "01A1B4C5-B784-7931-9051-03DEC1E9BB5D")
        let newID = fixture.workspace("Codex", "01A1B4C5-B784-7931-9051-03DEC1E9BB5E")
        let oldDate = try Date.ISO8601FormatStyle().parse("2026-07-02T00:00:00Z")
        for url in [retainedID, orphanID] { fixture.files.fileAttributes[url.path]?[.creationDate] = oldDate }
        fixture.files.fileAttributes[newID.path]?[.creationDate] = fixture.referenceDate
        try fixture.codexDatabase(rows: [(retainedID.lastPathComponent.lowercased(), "/project", "2026-07-06", true)])

        #expect(Set(fixture.scan().map(\.url)) == [temp, orphanID])
        #expect(!AISessionWorkspaceCleanup(fileManager: fixture.files, referenceDate: fixture.referenceDate).canTrash(newID))
    }

    @Test(arguments: ["Gemini", "Qwen"])
    func metadataWithoutACwdStillProtectsItsSessionDate(tool: String) throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let retained = fixture.workspace(tool, "2026-07-02")
        let orphan = fixture.workspace(tool, "2026-07-06")
        let path = tool == "Gemini" ? ".gemini/tmp/project/chats/session-retained.jsonl" : ".qwen/projects/project/session.jsonl"
        let metadata = tool == "Gemini"
            ? "{\"sessionId\":\"retained\",\"startTime\":\"2026-07-02T12:00:00Z\"}\n"
            : "{\"type\":\"user\",\"timestamp\":\"2026-07-02T12:00:00Z\",\"message\":{\"parts\":[{\"text\":\"hello\"}]}}\n"
        fixture.jsonLog(path, metadata)

        #expect(fixture.scan().map(\.url) == [orphan])
        #expect(!AISessionWorkspaceCleanup(fileManager: fixture.files).canTrash(retained))
    }

    @Test
    func aCopilotEventLogWithMissingWorkspaceMetadataRemainsUnverifiable() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let retained = fixture.workspace("Copilot", "2026-07-02")
        fixture.jsonLog(".copilot/session-state/id/events.jsonl", "{\"type\":\"session.start\",\"timestamp\":\"2026-07-02T12:00:00Z\"}\n")

        #expect(fixture.scan().isEmpty)
        #expect(!AISessionWorkspaceCleanup(fileManager: fixture.files).canTrash(retained))
    }

    @Test
    func symbolicallyLinkedTranscriptParentsRemainUnverifiable() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let retained = fixture.workspace("Claude Code", "2026-07-02")
        fixture.jsonLog(".claude/projects/project/session.jsonl", "{\"cwd\":\"/project\",\"timestamp\":\"2026-07-06T12:00:00Z\"}\n")
        fixture.files.fileAttributes[fixture.home.appendingPathComponent(".claude").path]?[.type] = FileAttributeType.typeSymbolicLink

        #expect(fixture.scan().isEmpty)
        #expect(!AISessionWorkspaceCleanup(fileManager: fixture.files).canTrash(retained))
    }

    @Test
    func compressedLegacyRolloutsNeverImplyThatTheirSessionsWereDeleted() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        fixture.workspace("Codex", "2026-07-02")
        fixture.jsonLog(".codex/archived_sessions/2026/07/02/rollout-retained.jsonl.zst", "compressed data")

        #expect(fixture.scan().isEmpty)
    }

    @Test
    func zcodeV2DeletedTasksDifferFromCompletedTasks() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let deleted = fixture.workspace("ZCode", "2026-07-02")
        let completed = fixture.workspace("ZCode", "2026-07-06")
        let database = fixture.home.appendingPathComponent(".zcode/v2/tasks-index.sqlite")
        try FileManager.default.createDirectory(at: database.deletingLastPathComponent(), withIntermediateDirectories: true)
        try fixture.sql("CREATE TABLE tasks(task_id TEXT, workspace_path TEXT, created_at INTEGER, deleted INTEGER, status TEXT); INSERT INTO tasks VALUES ('deleted','\(deleted.path)',1782993600000,1,'Completed'), ('retained','\(completed.path)',1783339200000,0,'Completed')", at: database)
        fixture.file(database, data: Data())

        #expect(fixture.scan().map(\.url) == [deleted])
    }

    @Test
    func invalidSessionCreationDatesDoNotBecomeDeletionEvidence() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        fixture.workspace("OpenCode", "2026-07-02")
        let file = fixture.home.appendingPathComponent(".local/share/opencode/storage/session/project/id.json")
        for timestamp: Any in [true, -1, "invalid", 1e100] {
            fixture.file(file, data: try JSONSerialization.data(withJSONObject: ["id": "retained", "time": ["created": timestamp]]))
            #expect(fixture.scan().isEmpty)
        }
    }

    @Test(arguments: SystemCleanupScope.allCases) @MainActor
    func automaticCleanupRespectsRetainedAndUnverifiableWorkspaces(scope: SystemCleanupScope) async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let retained = fixture.workspace("Codex", "2026-07-02")
        let orphan = fixture.workspace("Codex", "2026-07-06")
        fixture.workspace("ChatGPT", "2026-07-02")
        try fixture.codexDatabase(rows: [("retained", retained.path, "2026-07-02", true)])
        fixture.files.trashResults[orphan] = .success(orphan)
        let suite = "Zisla.SessionWorkspaceCleanup.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(fixture.referenceDate.addingTimeInterval(-7 * 86_400), forKey: "system-cleanup-last-run-v1")
        let service = SystemAutoCleanupService(
            defaults: defaults, now: { fixture.referenceDate },
            scan: { SystemDiskCleanup.scanCandidates(fileManager: fixture.files, kinds: $0, options: $1) },
            trash: { SystemDiskCleanup.trashSelected(candidates: $0, fileManager: fixture.files) },
            timerFactory: { Timer(timeInterval: $0, repeats: true, block: $1) }
        )
        defer { service.stop() }
        service.apply(settings: FeatureSettings(systemCleanupPolicy: .sevenDays, systemCleanupScope: scope))

        let task = try #require(service.runIfDue())
        let result = try #require(await task.value)

        #expect(result.successCount == (scope == .all ? 1 : 0))
        #expect(fixture.files.trashedURLs == (scope == .all ? [orphan] : []))
        #expect(result.failures.isEmpty)
    }

    private final class Snapshots: @unchecked Sendable {
        private let lock = NSLock()
        private var storage: [[DiskCleanupCandidate]] = []

        var values: [[DiskCleanupCandidate]] {
            lock.lock()
            defer { lock.unlock() }
            return storage
        }

        func append(_ candidates: [DiskCleanupCandidate]) {
            lock.lock()
            defer { lock.unlock() }
            storage.append(candidates)
        }
    }

    private static let databaseFixtures: [String: (path: String, schema: String, insert: String)] = [
        "OpenCode": (".local/share/opencode/opencode.db", "CREATE TABLE session(id TEXT, directory TEXT, time_created INTEGER, time_archived INTEGER)", "INSERT INTO session VALUES ('retained','$CWD',1782993600000,1)"),
        "ZCode": (".zcode/cli/db/db.sqlite", "CREATE TABLE session(id TEXT, directory TEXT, time_created INTEGER, time_archived INTEGER)", "INSERT INTO session VALUES ('retained','$CWD',1782993600000,1)"),
        "WorkBuddy": (".workbuddy/workbuddy.db", "CREATE TABLE sessions(id TEXT, cwd TEXT, created_at INTEGER, deleted_at INTEGER, status TEXT)", "INSERT INTO sessions VALUES ('retained','$CWD',1782993600000,NULL,'Archived')"),
        "WorkBuddy AI": (".workbuddy-ai/workbuddy.db", "CREATE TABLE sessions(id TEXT, cwd TEXT, created_at INTEGER, deleted_at INTEGER, status TEXT)", "INSERT INTO sessions VALUES ('retained','$CWD',1782993600000,NULL,'Completed')"),
        "Zed": ("Library/Application Support/Zed/threads/threads.db", "CREATE TABLE threads(id TEXT, created_at TEXT)", "INSERT INTO threads VALUES ('retained','2026-07-02T12:00:00Z')"),
        "Delta": ("Library/Application Support/Delta/user_test/data.sqlite", "CREATE TABLE app_threads(id TEXT, created_at INTEGER, archived INTEGER)", "INSERT INTO app_threads VALUES ('retained',1782993600000,1)"),
    ]

    private final class Fixture {
        let home: URL
        let files = MockFileManager()
        let referenceDate = Date(timeIntervalSince1970: 1_794_052_800)

        init() throws {
            home = FileManager.default.temporaryDirectory.appendingPathComponent("zisla-session-cleanup-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
            files.homeDirectory = home
            files.existingPaths.insert(home.path)
            files.fileAttributes[home.path] = [.type: FileAttributeType.typeDirectory]
            let documents = home.appendingPathComponent("Documents")
            files.searchPathResults[.documentDirectory] = [documents]
            directory(documents)
        }

        func remove() {
            try? FileManager.default.removeItem(at: home)
        }

        func directory(_ url: URL) {
            files.existingPaths.insert(url.path)
            files.fileAttributes[url.path] = [.type: FileAttributeType.typeDirectory]
            if files.directoryContents[url.path] == nil { files.directoryContents[url.path] = [] }
            let parent = url.deletingLastPathComponent()
            if !files.directoryContents[parent.path, default: []].contains(url) {
                files.directoryContents[parent.path, default: []].append(url)
            }
        }

        func file(_ url: URL, data: Data) {
            var directories: [URL] = []
            var parent = url.deletingLastPathComponent()
            while parent.path.hasPrefix(home.path + "/") {
                directories.append(parent)
                parent = parent.deletingLastPathComponent()
            }
            for directoryURL in directories.reversed() { directory(directoryURL) }
            files.existingPaths.insert(url.path)
            files.fileAttributes[url.path] = [.type: FileAttributeType.typeRegular, .size: NSNumber(value: data.count)]
            if !files.directoryContents[url.deletingLastPathComponent().path, default: []].contains(url) {
                files.directoryContents[url.deletingLastPathComponent().path, default: []].append(url)
            }
            files.fileContentsData[url.path] = data
        }

        func jsonLog(_ path: String, _ text: String) {
            file(home.appendingPathComponent(path), data: Data(text.utf8))
        }

        func fileContents(_ url: URL, _ data: Data) {
            files.fileContentsData[url.path] = data
            files.fileAttributes[url.path]?[.size] = NSNumber(value: data.count)
        }

        @discardableResult
        func workspace(_ tool: String, _ day: String) -> URL {
            let root = home.appendingPathComponent("Documents/\(tool)")
            directory(root)
            let url = root.appendingPathComponent(day)
            directory(url)
            let output = url.appendingPathComponent("new-chat/output.txt")
            directory(output.deletingLastPathComponent())
            files.existingPaths.insert(output.path)
            files.directoryContents[output.deletingLastPathComponent().path] = [output]
            files.fileAttributes[output.path] = [.type: FileAttributeType.typeRegular, .size: NSNumber(value: 4096)]
            return url.standardizedFileURL
        }

        func codexDatabase(rows: [(String, String, String, Bool)]) throws {
            let root = home.appendingPathComponent(".codex")
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            directory(root)
            let database = root.appendingPathComponent("state_5.sqlite")
            try sql("CREATE TABLE threads (id TEXT PRIMARY KEY, cwd TEXT NOT NULL, created_at INTEGER NOT NULL, archived INTEGER NOT NULL)", at: database)
            for (id, cwd, day, archived) in rows {
                let date = try Date.ISO8601FormatStyle().parse(day + "T12:00:00Z")
                try sql("INSERT INTO threads VALUES ('\(id)', '\(cwd)', \(Int(date.timeIntervalSince1970)), \(archived ? 1 : 0))", at: database)
            }
            files.existingPaths.insert(database.path)
            files.directoryContents[root.path] = [database]
            files.fileAttributes[database.path] = [.type: FileAttributeType.typeRegular]
        }

        func sql(_ text: String, at url: URL) throws {
            var database: OpaquePointer?
            guard sqlite3_open(url.path, &database) == SQLITE_OK, let database else {
                sqlite3_close(database)
                throw CocoaError(.fileReadUnknown)
            }
            defer { sqlite3_close(database) }
            guard sqlite3_exec(database, text, nil, nil, nil) == SQLITE_OK else {
                throw CocoaError(.fileReadCorruptFile)
            }
        }

        func scan() -> [DiskCleanupCandidate] {
            SystemDiskCleanup.scanCandidates(fileManager: files, maxConcurrentScans: 1, options: DiskCleanupScanOptions(referenceDate: referenceDate))
        }
    }
}
