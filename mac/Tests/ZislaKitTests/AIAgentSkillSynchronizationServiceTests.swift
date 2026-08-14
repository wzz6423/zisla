import Foundation
import Testing
@testable import ZislaKit

struct AIAgentSkillSynchronizationServiceTests {
    @Test
    func symbolicLinkReflectsManagedSkillChanges() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let managed = root.appendingPathComponent("managed", isDirectory: true)
        let destination = root.appendingPathComponent("codex/zisla-managed", isDirectory: true)
        let skillFile = managed.appendingPathComponent("review/SKILL.md")
        try FileManager.default.createDirectory(at: skillFile.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("first".utf8).write(to: skillFile)

        let service = AIAgentSkillSynchronizationService()
        try service.synchronize(managedDirectory: managed, to: destination, mode: .symbolicLink)
        try Data("updated".utf8).write(to: skillFile)

        let copiedFile = destination.appendingPathComponent("review/SKILL.md")
        #expect(try String(contentsOf: copiedFile, encoding: .utf8) == "updated")
        #expect((try destination.resourceValues(forKeys: [.isSymbolicLinkKey])).isSymbolicLink == true)
    }

    @Test
    func fileCopyStaysIndependentAndDisableKeepsManagedSkills() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let managed = root.appendingPathComponent("managed", isDirectory: true)
        let destination = root.appendingPathComponent("claude/zisla-managed", isDirectory: true)
        let backupRoot = root.appendingPathComponent("backups", isDirectory: true)
        let skillFile = managed.appendingPathComponent("review/SKILL.md")
        try FileManager.default.createDirectory(at: skillFile.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("first".utf8).write(to: skillFile)

        let service = AIAgentSkillSynchronizationService()
        try service.synchronize(managedDirectory: managed, to: destination, mode: .fileCopy)
        try Data("updated".utf8).write(to: skillFile)

        let copiedFile = destination.appendingPathComponent("review/SKILL.md")
        #expect(try String(contentsOf: copiedFile, encoding: .utf8) == "first")
        let userSkill = destination.appendingPathComponent("user-added/SKILL.md")
        try FileManager.default.createDirectory(at: userSkill.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("user content".utf8).write(to: userSkill)

        try service.disable(
            at: destination,
            managedDirectory: managed,
            backupRoot: backupRoot
        )
        #expect(!FileManager.default.fileExists(atPath: destination.path))
        #expect(FileManager.default.fileExists(atPath: skillFile.path))
        let backups = try FileManager.default.contentsOfDirectory(at: backupRoot, includingPropertiesForKeys: nil)
        #expect(backups.count == 1)
        #expect(try String(
            contentsOf: backups[0].appendingPathComponent("user-added/SKILL.md"),
            encoding: .utf8
        ) == "user content")
    }

    @Test
    func refusesToReplaceUnmanagedDestinationWithoutBackup() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let managed = root.appendingPathComponent("managed", isDirectory: true)
        let destination = root.appendingPathComponent("codex/zisla-managed", isDirectory: true)
        let existingFile = destination.appendingPathComponent("existing.txt")
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        try Data("keep".utf8).write(to: existingFile)

        let service = AIAgentSkillSynchronizationService()
        #expect(throws: AIAgentSkillSynchronizationError.self) {
            try service.synchronize(managedDirectory: managed, to: destination, mode: .symbolicLink)
        }
        #expect(try String(contentsOf: existingFile, encoding: .utf8) == "keep")
    }

    @Test
    func disableKeepsUnmanagedDestination() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let managed = root.appendingPathComponent("managed", isDirectory: true)
        let destination = root.appendingPathComponent("codex/skills", isDirectory: true)
        let existingFile = destination.appendingPathComponent("existing.txt")
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        try Data("keep".utf8).write(to: existingFile)

        try AIAgentSkillSynchronizationService().disable(
            at: destination,
            managedDirectory: managed
        )

        #expect(try String(contentsOf: existingFile, encoding: .utf8) == "keep")
    }

    @Test
    func takesOverUnmanagedSkillsRootWithBackup() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let managed = root.appendingPathComponent("managed", isDirectory: true)
        let destination = root.appendingPathComponent("claude/skills", isDirectory: true)
        let backupRoot = root.appendingPathComponent("backups", isDirectory: true)

        let existingSkill = destination.appendingPathComponent("user-skill/SKILL.md")
        try FileManager.default.createDirectory(at: existingSkill.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("user content".utf8).write(to: existingSkill)

        let service = AIAgentSkillSynchronizationService()
        try service.synchronize(managedDirectory: managed, to: destination, mode: .symbolicLink, backupRoot: backupRoot)

        var statInfo = stat()
        let isSymlink = lstat(destination.path, &statInfo) == 0 && (statInfo.st_mode & S_IFMT) == S_IFLNK
        #expect(isSymlink == true)
        let importedSkill = managed.appendingPathComponent("user-skill/SKILL.md")
        #expect(try String(contentsOf: importedSkill, encoding: .utf8) == "user content")

        let backups = try FileManager.default.contentsOfDirectory(at: backupRoot, includingPropertiesForKeys: nil)
        #expect(backups.count == 1)
        let backedUpSkill = backups[0].appendingPathComponent("user-skill/SKILL.md")
        #expect(try String(contentsOf: backedUpSkill, encoding: .utf8) == "user content")
    }

    @Test
    func preservesConflictingSkillsInBackup() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let managed = root.appendingPathComponent("managed", isDirectory: true)
        let destination = root.appendingPathComponent("claude/skills", isDirectory: true)
        let backupRoot = root.appendingPathComponent("backups", isDirectory: true)

        let managedSkill = managed.appendingPathComponent("review/SKILL.md")
        try FileManager.default.createDirectory(at: managedSkill.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("managed version".utf8).write(to: managedSkill)

        let existingConflict = destination.appendingPathComponent("review/SKILL.md")
        let existingUnique = destination.appendingPathComponent("custom/SKILL.md")
        try FileManager.default.createDirectory(at: existingConflict.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: existingUnique.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("user conflict".utf8).write(to: existingConflict)
        try Data("user unique".utf8).write(to: existingUnique)

        let service = AIAgentSkillSynchronizationService()
        try service.synchronize(managedDirectory: managed, to: destination, mode: .symbolicLink, backupRoot: backupRoot)

        let importedUnique = managed.appendingPathComponent("custom/SKILL.md")
        #expect(try String(contentsOf: importedUnique, encoding: .utf8) == "user unique")
        #expect(try String(contentsOf: managedSkill, encoding: .utf8) == "managed version")

        let backups = try FileManager.default.contentsOfDirectory(at: backupRoot, includingPropertiesForKeys: nil)
        #expect(backups.count == 1)
        let backupConflict = backups[0].appendingPathComponent("review/SKILL.md")
        #expect(try String(contentsOf: backupConflict, encoding: .utf8) == "user conflict")
    }

    @Test
    func flattensLegacyManagedChildDuringTakeover() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let managed = root.appendingPathComponent("managed", isDirectory: true)
        let destination = root.appendingPathComponent("codex/skills", isDirectory: true)
        let backupRoot = root.appendingPathComponent("backups", isDirectory: true)
        let legacySkill = destination.appendingPathComponent("zisla-managed/legacy/SKILL.md")
        try FileManager.default.createDirectory(
            at: legacySkill.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data("legacy content".utf8).write(to: legacySkill)

        try AIAgentSkillSynchronizationService().synchronize(
            managedDirectory: managed,
            to: destination,
            mode: .symbolicLink,
            backupRoot: backupRoot
        )

        #expect(try String(
            contentsOf: managed.appendingPathComponent("legacy/SKILL.md"),
            encoding: .utf8
        ) == "legacy content")
        #expect(!FileManager.default.fileExists(atPath: managed.appendingPathComponent("zisla-managed").path))
        let backups = try FileManager.default.contentsOfDirectory(at: backupRoot, includingPropertiesForKeys: nil)
        #expect(backups.count == 1)
        #expect(FileManager.default.fileExists(atPath: backups[0].appendingPathComponent("zisla-managed/legacy/SKILL.md").path))
    }

    @Test
    func idempotentWhenAlreadyManagedSymlink() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let managed = root.appendingPathComponent("managed", isDirectory: true)
        let destination = root.appendingPathComponent("claude/skills", isDirectory: true)
        let backupRoot = root.appendingPathComponent("backups", isDirectory: true)

        let skillFile = managed.appendingPathComponent("review/SKILL.md")
        try FileManager.default.createDirectory(at: skillFile.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("content".utf8).write(to: skillFile)

        let service = AIAgentSkillSynchronizationService()
        try service.synchronize(managedDirectory: managed, to: destination, mode: .symbolicLink)
        try service.synchronize(managedDirectory: managed, to: destination, mode: .symbolicLink, backupRoot: backupRoot)

        #expect((try destination.resourceValues(forKeys: [.isSymbolicLinkKey])).isSymbolicLink == true)
        #expect(!FileManager.default.fileExists(atPath: backupRoot.path))
    }

    @Test
    func idempotentWhenAlreadyManagedFileCopy() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let managed = root.appendingPathComponent("managed", isDirectory: true)
        let destination = root.appendingPathComponent("claude/skills", isDirectory: true)
        let backupRoot = root.appendingPathComponent("backups", isDirectory: true)

        let skillFile = managed.appendingPathComponent("review/SKILL.md")
        try FileManager.default.createDirectory(at: skillFile.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("content".utf8).write(to: skillFile)

        let service = AIAgentSkillSynchronizationService()
        try service.synchronize(managedDirectory: managed, to: destination, mode: .fileCopy)
        try service.synchronize(managedDirectory: managed, to: destination, mode: .fileCopy, backupRoot: backupRoot)

        let marker = destination.appendingPathComponent(".zisla-skill-sync")
        #expect(FileManager.default.fileExists(atPath: marker.path))
        #expect(!FileManager.default.fileExists(atPath: backupRoot.path))
    }

    @Test
    func takesOverUnmanagedSymlinkWithoutChangingItsTarget() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let managed = root.appendingPathComponent("managed", isDirectory: true)
        let destination = root.appendingPathComponent("agents/skills", isDirectory: true)
        let external = root.appendingPathComponent("external-skills", isDirectory: true)
        let backupRoot = root.appendingPathComponent("backups", isDirectory: true)
        let externalSkill = external.appendingPathComponent("external/SKILL.md")
        try FileManager.default.createDirectory(
            at: externalSkill.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data("external content".utf8).write(to: externalSkill)
        try FileManager.default.createDirectory(
            at: destination.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try FileManager.default.createSymbolicLink(at: destination, withDestinationURL: external)

        let service = AIAgentSkillSynchronizationService()
        try service.synchronize(
            managedDirectory: managed,
            to: destination,
            mode: .symbolicLink,
            backupRoot: backupRoot
        )

        #expect(try String(contentsOf: externalSkill, encoding: .utf8) == "external content")
        #expect(try String(
            contentsOf: managed.appendingPathComponent("external/SKILL.md"),
            encoding: .utf8
        ) == "external content")
        let backups = try FileManager.default.contentsOfDirectory(at: backupRoot, includingPropertiesForKeys: nil)
        #expect(backups.count == 1)
        #expect(try FileManager.default.destinationOfSymbolicLink(atPath: backups[0].path) == external.path)
    }

    private func temporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("zisla-skill-sync-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }
}
