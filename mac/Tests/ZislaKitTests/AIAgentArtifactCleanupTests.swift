import Foundation
import Testing

@testable import ZislaKit

struct AIAgentArtifactCleanupTests {
    @Test(arguments: [
        ".gemini", ".claude", ".codex", ".grok", ".qwen", ".kimi-code", ".pi/agent", ".copilot", ".qoder",
        ".qoderwork", ".qoderworkcn", ".qoderwake", ".zcode", ".workbuddy", ".workbuddy-ai", ".trae",
        ".harnext", ".dsh", ".local/share/opencode", ".local/share/muse",
    ])
    func emptyAgentTasksIncludeNestedEmptyAndFinderDirectories(tool: String) throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let task = try fixture.directory(tool + "/tasks/task-1/backup/empty").deletingLastPathComponent().deletingLastPathComponent()
        try fixture.file(tool + "/tasks/task-1/.DS_Store", contents: "finder metadata")

        let candidate = try #require(fixture.scan().first { $0.url == task })

        #expect(candidate.kind == .temporaryFiles)
        #expect(candidate.safetyLevel == .requiresManualReview)
        #expect(candidate.displayName == tool + "/tasks/task-1")
        let result = SystemDiskCleanup.trashSelected(candidates: [candidate], fileManager: fixture.files)
        #expect(result.successCount == 1)
        #expect(fixture.files.trashedURLs == [task])
        #expect(FileManager.default.fileExists(atPath: task.deletingLastPathComponent().path))
    }

    @Test
    func geminiTaskBackupIsOfferedWithoutOfferingItsWorkspaceOrMetadata() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let backup = try fixture.directory(".gemini/tasks/c_ea7fe066187964a6/backup/Users/test/project").deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        try fixture.file(".gemini/tasks/c_ea7fe066187964a6/backup/Users/test/project/source.swift", contents: "saved source")
        let metadata = try fixture.file(".gemini/tasks/c_ea7fe066187964a6/task.json", contents: "task metadata")
        let workspace = try fixture.file(".gemini/tasks/c_ea7fe066187964a6/workspace/result.txt", contents: "keep output")

        let candidates = fixture.scan()

        #expect(candidates.map(\.url) == [backup])
        #expect(candidates.first?.byteSize ?? 0 > 0)
        #expect(candidates.first?.safetyLevel == .requiresManualReview)
        #expect(SystemDiskCleanup.trashSelected(candidates: candidates, fileManager: fixture.files).successCount == 1)
        #expect(try String(contentsOf: metadata, encoding: .utf8) == "task metadata")
        #expect(try String(contentsOf: workspace, encoding: .utf8) == "keep output")
    }

    @Test
    func emptyTasksAreRecheckedAfterHiddenContentAppears() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let task = try fixture.directory(".claude/tasks/session-empty")
        let candidate = try #require(fixture.scan().first { $0.url == task })
        let state = try fixture.file(".claude/tasks/session-empty/.state", contents: "keep task")

        let result = SystemDiskCleanup.trashSelected(candidates: [candidate], fileManager: fixture.files)

        #expect(result.successCount == 0)
        #expect(result.failures.count == 1)
        #expect(fixture.files.trashedURLs.isEmpty)
        #expect(SystemDiskCleanup.trashSelected(urls: [task], fileManager: fixture.files, allowedRoots: [fixture.home]).successCount == 0)
        #expect(try String(contentsOf: state, encoding: .utf8) == "keep task")
    }

    @Test
    func unreadableTasksAndTaskAncestorsCannotBeTrashed() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let task = try fixture.directory(".gemini/tasks/empty")
        fixture.files.deniedPaths.insert(task.path)

        #expect(!fixture.scan().contains { $0.url == task })
        for url in [task, task.deletingLastPathComponent(), fixture.home.appendingPathComponent(".gemini")] {
            let candidate = DiskCleanupCandidate(url: url, kind: .temporaryFiles, byteSize: 0, displayName: url.lastPathComponent)
            #expect(SystemDiskCleanup.trashSelected(candidates: [candidate], fileManager: fixture.files).successCount == 0)
        }
        #expect(fixture.files.trashedURLs.isEmpty)
    }

    @Test
    func linkedTasksAndBackupsDoNotExposeTheirTargets() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let outside = try fixture.directory("Documents/important")
        let original = try fixture.file("Documents/important/source.txt", contents: "keep source")
        let tasks = try fixture.directory(".gemini/tasks")
        try FileManager.default.createSymbolicLink(at: tasks.appendingPathComponent("linked-task"), withDestinationURL: outside)
        let task = try fixture.directory(".gemini/tasks/task-with-link")
        try FileManager.default.createSymbolicLink(at: task.appendingPathComponent("backup"), withDestinationURL: outside)

        #expect(fixture.scan().isEmpty)
        let candidate = DiskCleanupCandidate(url: task.appendingPathComponent("backup"), kind: .temporaryFiles, byteSize: 0, displayName: "backup")
        #expect(SystemDiskCleanup.trashSelected(candidates: [candidate], fileManager: fixture.files).successCount == 0)
        #expect(SystemDiskCleanup.trashSelected(urls: [candidate.url], fileManager: fixture.files, allowedRoots: [fixture.home]).successCount == 0)
        #expect(fixture.files.trashedURLs.isEmpty)
        #expect(try String(contentsOf: original, encoding: .utf8) == "keep source")
    }

    @Test(arguments: [".state.json.bak", "state.json.backup", "state-backup", "STATE.BAK"])
    func staleHiddenBackupsAreOfferedButRecentAndRetainedStateStayProtected(name: String) throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let stale = try fixture.file(".codex/" + name, contents: "old backup", age: 8 * 86400)
        let recent = try fixture.file(".codex/config.toml.backup", contents: "recent backup")
        let retained = try fixture.file(".codex/state_5.sqlite", contents: "keep sessions", age: 8 * 86400)
        let session = try fixture.file(".claude/projects/project/session.jsonl", contents: "keep session", age: 8 * 86400)

        #expect(fixture.scan().map(\.url) == [stale])
        let forged = [recent, retained, session].map {
            DiskCleanupCandidate(url: $0, kind: .temporaryFiles, byteSize: 0, displayName: $0.lastPathComponent)
        }
        #expect(SystemDiskCleanup.trashSelected(candidates: forged, fileManager: fixture.files).successCount == 0)
        #expect(fixture.files.trashedURLs.isEmpty)
    }

    @Test
    func backupTreesWithRecentFilesAreNotClassifiedAsStale() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let backup = try fixture.directory(".gemini/antigravity-backup")
        try fixture.file(".gemini/antigravity-backup/recent.txt", contents: "keep recent")
        try FileManager.default.setAttributes([.modificationDate: fixture.referenceDate.addingTimeInterval(-8 * 86400)], ofItemAtPath: backup.path)

        #expect(fixture.scan().isEmpty)
        let candidate = DiskCleanupCandidate(url: backup, kind: .temporaryFiles, byteSize: 0, displayName: "backup")
        #expect(SystemDiskCleanup.trashSelected(candidates: [candidate], fileManager: fixture.files).successCount == 0)
    }

    @Test
    func duplicateScanIncludesHiddenFilesAndHiddenFoldersWhileKeepingOneCopy() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let visible = try fixture.file("Downloads/source.txt", contents: "identical contents")
        let hidden = try fixture.file("Downloads/.source-copy", contents: "identical contents")
        let nested = try fixture.file("Documents/.backups/source.txt", contents: "identical contents")
        try fixture.file("Documents/.backups/different.txt", contents: "different contents")
        fixture.files.extraChildren[visible.deletingLastPathComponent().path] = [hidden, visible]

        let candidates = SystemDiskCleanup.scanCandidates(fileManager: fixture.files, kinds: [.duplicateFile])

        #expect(Set(candidates.map(\.url)) == Set([visible, hidden, nested]).subtracting([visible]), "Visible originals must be retained before hidden copies")
        #expect(candidates.allSatisfy { $0.safetyLevel == .requiresManualReview })
        #expect(SystemDiskCleanup.trashSelected(candidates: candidates, fileManager: fixture.files).successCount == 2)
        #expect(!fixture.files.trashedURLs.contains(visible))
    }

    @Test(arguments: [".git", ".svn", ".hg"])
    func hiddenVersionControlMetadataIsNotUsedAsADuplicateCopy(directory: String) throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        try fixture.file("Documents/project/" + directory + "/objects/entry", contents: "shared data")
        try fixture.file("Downloads/original.txt", contents: "shared data")

        #expect(SystemDiskCleanup.scanCandidates(fileManager: fixture.files, kinds: [.duplicateFile]).isEmpty)
    }

    @Test
    func finderMetadataUnderTasksDoesNotBecomeAnEmptyTaskCandidate() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        try fixture.file(".claude/tasks/.DS_Store", contents: "finder metadata")

        #expect(fixture.scan().isEmpty)
    }

    @Test
    func staleUserBackupFilesIncludeHiddenFoldersAndRecheckAgeBeforeCleanup() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let backup = try fixture.file("Documents/.backups/source.swift.bak", contents: "old copy", age: 8 * 86400)
        try fixture.file("Documents/recent.bak", contents: "new copy")
        try fixture.file("Downloads/important.txt", contents: "keep original", age: 8 * 86400)
        let candidate = try #require(fixture.scan().first { $0.url == backup })

        #expect(fixture.scan().map(\.url) == [backup])
        #expect(SystemDiskCleanup.trashSelected(candidates: [candidate], fileManager: fixture.files).successCount == 1)
        fixture.files.trashedURLs.removeAll()
        try FileManager.default.setAttributes([.modificationDate: fixture.referenceDate], ofItemAtPath: backup.path)
        #expect(SystemDiskCleanup.trashSelected(candidates: [candidate], fileManager: fixture.files).successCount == 0)
        #expect(fixture.files.trashedURLs.isEmpty)
    }

    @Test
    func backupFilesCannotBecomeTheRetainedDuplicateOriginal() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let backup = try fixture.file("Downloads/source.bak", contents: "identical contents", age: 8 * 86400)
        let original = try fixture.file("Documents/source.txt", contents: "identical contents", age: 8 * 86400)
        let duplicate = try fixture.file("Documents/.source-copy", contents: "identical contents", age: 8 * 86400)

        let candidates = SystemDiskCleanup.scanCandidates(fileManager: fixture.files, kinds: [.temporaryFiles, .duplicateFile], options: DiskCleanupScanOptions(referenceDate: fixture.referenceDate))

        #expect(Set(candidates.map(\.url)) == Set([backup, duplicate]))
        #expect(candidates.contains { $0.url == backup && $0.kind == .temporaryFiles })
        #expect(candidates.first { $0.kind == .duplicateFile }?.detail?.contains(original.path) == true)
    }

    @Test(arguments: ["backup", "backups", ".backup", ".backups"])
    func oldFilesInNamedBackupFoldersAreScanned(name: String) throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let backup = try fixture.file("Documents/" + name + "/old.txt", contents: "old copy", age: 8 * 86400)
        try fixture.file("Documents/" + name + "/new.txt", contents: "new copy")

        let candidates = fixture.scan()

        #expect(candidates.map(\.url) == [backup])
        #expect(SystemDiskCleanup.trashSelected(candidates: candidates, fileManager: fixture.files).successCount == 1)
    }

    @Test
    func userBackupCleanupRejectsAFileReplacedByADirectoryOrLinkedParent() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let backup = try fixture.file("Documents/backups/copy.bak", contents: "old copy", age: 8 * 86400)
        let candidate = try #require(fixture.scan().first { $0.url == backup })
        try FileManager.default.removeItem(at: backup)
        try fixture.directory("Documents/backups/copy.bak/important")
        try FileManager.default.setAttributes([.modificationDate: fixture.referenceDate.addingTimeInterval(-8 * 86400)], ofItemAtPath: backup.path)

        #expect(SystemDiskCleanup.trashSelected(candidates: [candidate], fileManager: fixture.files).successCount == 0)
        try FileManager.default.removeItem(at: backup.deletingLastPathComponent())
        let source = try fixture.file("Documents/retained/copy.bak", contents: "keep original", age: 8 * 86400)
        try FileManager.default.createSymbolicLink(at: backup.deletingLastPathComponent(), withDestinationURL: source.deletingLastPathComponent())
        #expect(SystemDiskCleanup.trashSelected(candidates: [candidate], fileManager: fixture.files).successCount == 0)
        #expect(fixture.files.trashedURLs.isEmpty)
        #expect(try String(contentsOf: source, encoding: .utf8) == "keep original")
    }

    @Test
    func hiddenDuplicateReadFailuresNeverOfferTheRemainingOriginal() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let hidden = try fixture.file("Downloads/.copy", contents: "identical contents")
        let original = try fixture.file("Downloads/original.txt", contents: "identical contents")
        fixture.files.unreadableDigests.insert(hidden.path)

        #expect(SystemDiskCleanup.scanCandidates(fileManager: fixture.files, kinds: [.duplicateFile]).isEmpty)
        #expect(fixture.files.trashedURLs.isEmpty)
        #expect(try String(contentsOf: original, encoding: .utf8) == "identical contents")
    }

    @Test
    func staleAgentBackupDirectoriesAreOfferedAndRejectRecentDescendants() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let backup = try fixture.directory(".gemini/antigravity-backup")
        let file = try fixture.file(".gemini/antigravity-backup/saved.txt", contents: "old copy", age: 8 * 86400)
        try FileManager.default.setAttributes([.modificationDate: fixture.referenceDate.addingTimeInterval(-8 * 86400)], ofItemAtPath: backup.path)
        let candidate = try #require(fixture.scan().first { $0.url == backup })

        #expect(SystemDiskCleanup.trashSelected(candidates: [candidate], fileManager: fixture.files).successCount == 1)
        fixture.files.trashedURLs.removeAll()
        try FileManager.default.setAttributes([.modificationDate: fixture.referenceDate], ofItemAtPath: file.path)
        #expect(SystemDiskCleanup.trashSelected(candidates: [candidate], fileManager: fixture.files).successCount == 0)
        #expect(fixture.files.trashedURLs.isEmpty)
    }

    @Test(arguments: ["depth", "entries", "total", "tasks"])
    func emptyTaskTraversalStopsAtItsBudget(limit: String) throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let task = try fixture.directory(".claude/tasks/large")
        if limit == "depth" {
            try fixture.directory(".claude/tasks/large/" + Array(repeating: "nested", count: 17).joined(separator: "/"))
        } else if limit == "tasks" {
            fixture.files.extraChildren[task.deletingLastPathComponent().path] = Array(repeating: task, count: 20_001)
        } else if limit == "entries" {
            fixture.files.extraChildren[task.path] = Array(repeating: task.appendingPathComponent("empty"), count: 20_001)
        } else {
            let nested = try fixture.directory(".claude/tasks/large/nested")
            let empty = try fixture.directory(".claude/tasks/large/nested/empty")
            fixture.files.extraChildren[task.path] = Array(repeating: nested, count: 200)
            fixture.files.extraChildren[nested.path] = Array(repeating: empty, count: 101)
            for url in [task, nested, empty, task.deletingLastPathComponent(), fixture.home.appendingPathComponent(".claude")] {
                fixture.files.attributeOverrides[url.path] = try FileManager.default.attributesOfItem(atPath: url.path)
            }
        }

        #expect(fixture.scan().isEmpty)
        #expect(AIAgentArtifactCleanup(fileManager: fixture.files).canTrash(task) == (limit == "tasks"))
    }

    @Test
    func directoryEnumerationCannotInjectAnotherTaskPath() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let tasks = try fixture.directory(".claude/tasks")
        let outside = try fixture.directory(".claude/important")
        fixture.files.extraChildren[tasks.path] = [outside]

        #expect(fixture.scan().isEmpty)
        #expect(fixture.files.trashedURLs.isEmpty)
    }

    @Test
    func cancelledAgentScanningProducesNoCandidates() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        try fixture.directory(".claude/tasks/empty")
        try fixture.file(".gemini/tasks/current/backup/source.txt", contents: "backup copy")
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return AIAgentArtifactCleanup(fileManager: fixture.files).candidates()
        }

        #expect(await task.value.isEmpty)
    }

    @Test
    func cancellationDuringTaskEnumerationStopsRecursiveScanning() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let task = try fixture.directory(".claude/tasks/empty")
        fixture.files.cancelAtPath = task.deletingLastPathComponent().path
        let scan = Task { AIAgentArtifactCleanup(fileManager: fixture.files).candidates() }

        #expect(await scan.value.isEmpty)
    }

    @Test
    func agentBackupChildrenCannotBeForgedAsSeparateCleanupCandidates() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let file = try fixture.file(".codex/state-backup/child.bak", contents: "keep group", age: 8 * 86400)
        let candidate = DiskCleanupCandidate(url: file, kind: .temporaryFiles, byteSize: 0, displayName: "child")

        #expect(SystemDiskCleanup.trashSelected(candidates: [candidate], fileManager: fixture.files).successCount == 0)
        #expect(fixture.files.trashedURLs.isEmpty)
    }

    @Test
    func changedBackupPermissionsAndMissingAttributesPreserveFiles() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let backup = try fixture.directory(".gemini/antigravity-backup")
        try fixture.file(".gemini/antigravity-backup/copy", contents: "old copy", age: 8 * 86400)
        try FileManager.default.setAttributes([.modificationDate: fixture.referenceDate.addingTimeInterval(-8 * 86400)], ofItemAtPath: backup.path)
        let candidate = try #require(fixture.scan().first { $0.url == backup })
        fixture.files.deniedPaths.insert(backup.path)

        #expect(SystemDiskCleanup.trashSelected(candidates: [candidate], fileManager: fixture.files).successCount == 0)
        fixture.files.deniedPaths.removeAll()
        fixture.files.missingAttributes.insert(backup.path)
        #expect(SystemDiskCleanup.trashSelected(candidates: [candidate], fileManager: fixture.files).successCount == 0)
        #expect(fixture.files.trashedURLs.isEmpty)
    }

    @Test
    func linkedAgentRootsCannotAuthorizeBackupFiles() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let file = try fixture.file("retained-state/copy.bak", contents: "keep state", age: 8 * 86400)
        let link = fixture.home.appendingPathComponent(".codex", isDirectory: true)
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: file.deletingLastPathComponent())
        let candidate = DiskCleanupCandidate(url: link.appendingPathComponent("copy.bak"), kind: .temporaryFiles, byteSize: 0, displayName: "copy")

        #expect(SystemDiskCleanup.trashSelected(candidates: [candidate], fileManager: fixture.files).successCount == 0)
        #expect(fixture.files.trashedURLs.isEmpty)
        #expect(AIAgentArtifactCleanup(fileManager: fixture.files).canTrash(file) == nil)
        #expect(try String(contentsOf: file, encoding: .utf8) == "keep state")
    }

    @Test
    func forgedWorkspaceAndNestedTaskCandidatesStayProtected() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let task = try fixture.directory(".claude/tasks/empty")
        let candidate = DiskCleanupCandidate(url: task, kind: .aiSessionWorkspace, byteSize: 0, displayName: "empty")
        #expect(SystemDiskCleanup.trashSelected(candidates: [candidate], fileManager: fixture.files).successCount == 0)
        let file = try fixture.file(".gemini/tasks/current/backup/source.txt", contents: "backup")
        let forged = DiskCleanupCandidate(url: file, kind: .temporaryFiles, byteSize: 0, displayName: "source")
        #expect(SystemDiskCleanup.trashSelected(candidates: [forged], fileManager: fixture.files).successCount == 0)
        #expect(fixture.files.trashedURLs.isEmpty)
    }

    @Test
    func progressScanPublishesTheSameAgentArtifactsAsTheFinalResult() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let task = try fixture.directory(".codex/tasks/empty")
        let snapshots = ProgressResults()
        let candidates = SystemDiskCleanup.scanCandidatesWithProgress(
            fileManager: fixture.files, kinds: [.temporaryFiles],
            options: DiskCleanupScanOptions(referenceDate: fixture.referenceDate),
            onProgress: { snapshots.append($0) }
        )

        #expect(candidates.map(\.url) == [task])
        #expect(snapshots.values.last?.map(\.url) == [task])
    }

    @Test
    func staleClaudeFileHistoryIsScannedWithoutTouchingSessionTranscripts() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let id = "90ae01cf-4d42-4da0-bba5-5fbf2b349190"
        let history = try fixture.directory(".claude/file-history/" + id)
        try fixture.file(".claude/file-history/" + id + "/source@v1", contents: "old version", age: 8 * 86400)
        let transcript = try fixture.file(".claude/projects/project/" + id + ".jsonl", contents: "keep conversation")
        try FileManager.default.setAttributes([.modificationDate: fixture.referenceDate.addingTimeInterval(-8 * 86400)], ofItemAtPath: history.path)
        let candidates = fixture.scan()

        #expect(candidates.map(\.url) == [history])
        #expect(SystemDiskCleanup.trashSelected(candidates: candidates, fileManager: fixture.files).successCount == 1)
        #expect(try String(contentsOf: transcript, encoding: .utf8) == "keep conversation")
        #expect(SystemDiskCleanup.trashSelected(urls: [history.deletingLastPathComponent()], fileManager: fixture.files, allowedRoots: [fixture.home]).successCount == 0)
    }

    @Test
    func unknownFileHistoryNamesAndNonFileEnumerationResultsStayProtected() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let history = try fixture.directory(".claude/file-history/important")
        try FileManager.default.setAttributes([.modificationDate: fixture.referenceDate.addingTimeInterval(-8 * 86400)], ofItemAtPath: history.path)
        let backup = try fixture.file(".codex/copy.bak", contents: "old backup", age: 8 * 86400)
        fixture.files.extraChildren[backup.deletingLastPathComponent().path] = [try #require(URL(string: "https://example.invalid" + backup.path))]

        #expect(fixture.scan().isEmpty)
    }

    @Test
    func recentlyTouchedBackupDirectoryWithOnlyOldFilesRemainsProtected() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let backup = try fixture.directory(".codex/state-backup")
        try fixture.file(".codex/state-backup/copy", contents: "old copy", age: 8 * 86400)
        try FileManager.default.setAttributes([.modificationDate: fixture.referenceDate], ofItemAtPath: backup.path)

        #expect(fixture.scan().isEmpty)
        #expect(AIAgentArtifactCleanup(fileManager: fixture.files).canTrash(backup) == false)
    }

    @Test
    func nestedBackupNamesCannotAuthorizeRemovingTaskWorkspaceFiles() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let file = try fixture.file(".gemini/tasks/current/workspace/source.bak", contents: "keep workspace", age: 8 * 86400)
        let candidate = DiskCleanupCandidate(url: file, kind: .temporaryFiles, byteSize: 0, displayName: "source")

        #expect(AIAgentArtifactCleanup(fileManager: fixture.files).canTrash(file) == false)
        #expect(SystemDiskCleanup.trashSelected(candidates: [candidate], fileManager: fixture.files).successCount == 0)
        #expect(fixture.files.trashedURLs.isEmpty)
    }

    @Test
    func agentRootAncestorsStayProtectedInEitherCleanupEntry() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let root = try fixture.directory(".grok/tasks/empty").deletingLastPathComponent().deletingLastPathComponent()
        let cleanup = AIAgentArtifactCleanup(fileManager: fixture.files)

        #expect(cleanup.canTrash(root) == false)
        #expect(cleanup.canTrash(fixture.home) == false)
        #expect(SystemDiskCleanup.trashSelected(urls: [root], fileManager: fixture.files, allowedRoots: [fixture.home]).successCount == 0)
        #expect(fixture.files.trashedURLs.isEmpty)
    }

    @Test(arguments: ["unreadable", "symlink", "type", "depth", "entries"])
    func taskBackupDescendantsAreRecheckedBeforeSizingAndTrash(failure: String) throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let backup = try fixture.directory(".gemini/tasks/current/backup")
        try fixture.file(".gemini/tasks/current/backup/source.txt", contents: "recent backup")
        let candidate = try #require(fixture.scan().first { $0.url == backup })
        fixture.files.clearSizedDirectories()
        let nested = try fixture.directory(".gemini/tasks/current/backup/nested")
        switch failure {
        case "unreadable": fixture.files.deniedPaths.insert(nested.path)
        case "symlink":
            let target = try fixture.directory("Documents/retained")
            try FileManager.default.createSymbolicLink(at: nested.appendingPathComponent("linked"), withDestinationURL: target)
        case "type":
            let file = try fixture.file(".gemini/tasks/current/backup/nested/socket", contents: "")
            fixture.files.attributeOverrides[file.path] = [.type: FileAttributeType.typeSocket]
        case "depth":
            try fixture.directory(".gemini/tasks/current/backup/nested/" + Array(repeating: "child", count: 17).joined(separator: "/"))
        default:
            fixture.files.extraChildren[nested.path] = Array(repeating: nested.appendingPathComponent("child"), count: 20_001)
        }

        #expect(!fixture.scan().contains { $0.url == backup }, "An unverifiable task backup must not be offered")
        #expect(!fixture.files.sizedDirectories.contains(backup.path), "Unverifiable backups must be rejected before size enumeration")
        let result = SystemDiskCleanup.trashSelected(candidates: [candidate], fileManager: fixture.files)
        #expect(result.successCount == 0)
        #expect(result.failures.count == 1)
        #expect(fixture.files.trashedURLs.isEmpty)
    }

    @Test(arguments: [".git", ".svn", ".hg"])
    func regularVersionControlMetadataFilesNeverBecomeCleanupCandidates(name: String) throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        try fixture.file("Downloads/project/" + name, contents: "gitdir: shared-checkout")
        try fixture.file("Documents/project/" + name, contents: "gitdir: shared-checkout")

        #expect(SystemDiskCleanup.scanCandidates(fileManager: fixture.files, kinds: [.duplicateFile]).isEmpty)
        #expect(fixture.files.trashedURLs.isEmpty)
    }

    @Test(arguments: ["roots", "subtrees"])
    func visibleDuplicateOriginalWinsAcrossRootsAndSubtrees(layout: String) throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let hidden: URL
        let original: URL
        if layout == "roots" {
            hidden = try fixture.file("Downloads/.copy", contents: "identical contents")
            original = try fixture.file("Documents/original.txt", contents: "identical contents")
        } else {
            hidden = try fixture.file("Downloads/early/.hidden/copy", contents: "identical contents")
            original = try fixture.file("Downloads/later/original.txt", contents: "identical contents")
            fixture.files.extraChildren[fixture.home.appendingPathComponent("Downloads").path] = [
                fixture.home.appendingPathComponent("Downloads/early", isDirectory: true),
                fixture.home.appendingPathComponent("Downloads/later", isDirectory: true),
            ]
        }

        let candidates = SystemDiskCleanup.scanCandidates(fileManager: fixture.files, kinds: [.duplicateFile])

        #expect(candidates.map(\.url) == [hidden])
        #expect(candidates.first?.detail?.contains(original.path) == true)
        #expect(SystemDiskCleanup.trashSelected(candidates: candidates, fileManager: fixture.files).successCount == 1)
        #expect(!fixture.files.trashedURLs.contains(original))
    }

    @Test
    func duplicatesWithOnlyHiddenPathsKeepOneOriginal() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let original = try fixture.file("Downloads/.original", contents: "identical contents")
        let copy = try fixture.file("Documents/.copy", contents: "identical contents")

        let candidates = SystemDiskCleanup.scanCandidates(fileManager: fixture.files, kinds: [.duplicateFile])

        #expect(candidates.map(\.url) == [copy])
        #expect(candidates.first?.detail?.contains(original.path) == true)
    }

    @Test
    func backupCandidatesUseOnlyUserRootsAuthorizedForTrash() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let authorized = try fixture.file("Documents/backups/copy.bak", contents: "old copy", age: 8 * 86400)
        try fixture.file("Projects/backups/copy.bak", contents: "outside cleanup roots", age: 8 * 86400)
        let candidates = SystemDiskCleanup.scanCandidates(
            fileManager: fixture.files, kinds: [.temporaryFiles],
            options: DiskCleanupScanOptions(referenceDate: fixture.referenceDate, additionalUserDirectories: [fixture.home.appendingPathComponent("Projects")])
        )

        #expect(candidates.map(\.url) == [authorized])
        let result = SystemDiskCleanup.trashSelected(candidates: candidates, fileManager: fixture.files)
        #expect(result.successCount == 1)
        #expect(result.failures.isEmpty)
        #expect(fixture.files.trashedURLs == [authorized])
    }

    private final class ProgressResults: @unchecked Sendable {
        private let lock = NSLock()
        private var storage: [[DiskCleanupCandidate]] = []
        var values: [[DiskCleanupCandidate]] { lock.withLock { storage } }
        func append(_ candidates: [DiskCleanupCandidate]) { lock.withLock { storage.append(candidates) } }
    }

    private struct Fixture {
        let home: URL
        let files: SandboxFileManager
        let referenceDate = Date()

        init() throws {
            home = FileManager.default.temporaryDirectory.appendingPathComponent("zisla-agent-cleanup-" + UUID().uuidString).resolvingSymlinksInPath()
            try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
            files = SandboxFileManager(home: home)
            for name in ["Downloads", "Desktop", "Documents", ".Trash"] { try directory(name) }
        }

        @discardableResult
        func directory(_ path: String) throws -> URL {
            let url = home.appendingPathComponent(path, isDirectory: true)
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            return url
        }

        @discardableResult
        func file(_ path: String, contents: String, age: TimeInterval = 0) throws -> URL {
            let url = home.appendingPathComponent(path)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(contents.utf8).write(to: url)
            try FileManager.default.setAttributes([.modificationDate: referenceDate.addingTimeInterval(-age)], ofItemAtPath: url.path)
            return url
        }

        func scan() -> [DiskCleanupCandidate] {
            SystemDiskCleanup.scanCandidates(fileManager: files, kinds: [.temporaryFiles], options: DiskCleanupScanOptions(referenceDate: referenceDate))
                .filter { $0.url.path.hasPrefix(home.path + "/") }
        }

        func remove() { try? FileManager.default.removeItem(at: home) }
    }

    private final class SandboxFileManager: SystemMonitorFileManaging, @unchecked Sendable {
        let home: URL
        var deniedPaths = Set<String>()
        var extraChildren: [String: [URL]] = [:]
        var unreadableDigests = Set<String>()
        var missingAttributes = Set<String>()
        var attributeOverrides: [String: [FileAttributeKey: Any]] = [:]
        var cancelAtPath: String?
        private let enumerationLock = NSLock()
        private var enumerationPaths: [String] = []
        var sizedDirectories: [String] { enumerationLock.withLock { enumerationPaths } }
        func clearSizedDirectories() { enumerationLock.withLock { enumerationPaths.removeAll() } }
        var trashedURLs: [URL] = []
        private let base = DefaultSystemMonitorFileManager()

        init(home: URL) { self.home = home }
        func homeDirectoryForCurrentUser() -> URL { home }
        func temporaryDirectoryForCurrentUser() -> URL { home.appendingPathComponent("tmp") }
        func applicationExecutablePaths() -> Set<String>? { [] }
        func fileExists(atPath path: String) -> Bool { URL(fileURLWithPath: path).standardizedFileURL.path.hasPrefix(home.path + "/") && base.fileExists(atPath: path) }
        func urls(for directory: FileManager.SearchPathDirectory, in domainMask: FileManager.SearchPathDomainMask) -> [URL] {
            let name: String
            switch directory {
            case .downloadsDirectory: name = "Downloads"
            case .desktopDirectory: name = "Desktop"
            case .documentDirectory: name = "Documents"
            case .trashDirectory: name = ".Trash"
            default: return []
            }
            return [home.appendingPathComponent(name)]
        }
        func contentsOfDirectory(at url: URL, includingPropertiesForKeys keys: [URLResourceKey]?, options: FileManager.DirectoryEnumerationOptions) throws -> [URL] {
            let path = url.standardizedFileURL.path
            guard path == home.path || path.hasPrefix(home.path + "/") else { throw CocoaError(.fileReadNoSuchFile) }
            if deniedPaths.contains(path) { throw CocoaError(.fileReadNoPermission) }
            if path == cancelAtPath { withUnsafeCurrentTask { $0?.cancel() } }
            if let children = extraChildren[path] { return children }
            return try base.contentsOfDirectory(at: url, includingPropertiesForKeys: keys, options: options)
        }
        func attributesOfFileSystem(forPath path: String) throws -> [FileAttributeKey: Any] { try base.attributesOfFileSystem(forPath: path) }
        func attributesOfItem(atPath path: String) throws -> [FileAttributeKey: Any] {
            let normalized = URL(fileURLWithPath: path).standardizedFileURL.path
            if missingAttributes.contains(normalized) { throw CocoaError(.fileReadNoSuchFile) }
            if let attributes = attributeOverrides[normalized] { return attributes }
            return try base.attributesOfItem(atPath: path)
        }
        func enumerator(at url: URL, includingPropertiesForKeys keys: [URLResourceKey]?, options: FileManager.DirectoryEnumerationOptions) -> FileManager.DirectoryEnumerator? {
            enumerationLock.withLock { enumerationPaths.append(url.standardizedFileURL.path) }
            return base.enumerator(at: url, includingPropertiesForKeys: keys, options: options)
        }
        func trashItem(at url: URL) throws -> URL {
            trashedURLs.append(url)
            return home.appendingPathComponent(".Trash/" + url.lastPathComponent)
        }
        func createDirectory(at url: URL, withIntermediateDirectories: Bool) throws { try base.createDirectory(at: url, withIntermediateDirectories: withIntermediateDirectories) }
        func removeItem(at url: URL) throws { try base.removeItem(at: url) }
        func createFile(atPath path: String, contents data: Data?) -> Bool { base.createFile(atPath: path, contents: data) }
        func contents(atPath path: String) -> Data? { base.contents(atPath: path) }
        func readPrefix(at url: URL, maximumBytes: Int) -> Data? { base.readPrefix(at: url, maximumBytes: maximumBytes) }
        func sha256Digest(at url: URL) -> Data? {
            unreadableDigests.contains(url.standardizedFileURL.path) ? nil : base.sha256Digest(at: url)
        }
    }
}
