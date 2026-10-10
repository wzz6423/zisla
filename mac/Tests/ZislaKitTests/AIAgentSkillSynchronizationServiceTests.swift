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

    @Test(arguments: [AIAgentSkillSynchronizationMode.symbolicLink, .fileCopy], ["alias", "alias/"])
    func takesOverIndirectManagedRootLinkWithBackup(mode: AIAgentSkillSynchronizationMode, target: String) throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let managed = root.appendingPathComponent("managed", isDirectory: true)
        let alias = root.appendingPathComponent("alias")
        let destination = root.appendingPathComponent("skills")
        let backupRoot = root.appendingPathComponent("backups")
        try writeFile("original", at: managed.appendingPathComponent("review/SKILL.md"))
        try FileManager.default.createSymbolicLink(atPath: alias.path, withDestinationPath: "managed")
        try FileManager.default.createSymbolicLink(atPath: destination.path, withDestinationPath: target)
        let service = AIAgentSkillSynchronizationService()

        #expect(throws: AIAgentSkillSynchronizationError.self) {
            try service.synchronize(managedDirectory: managed, to: destination, mode: mode)
        }
        try service.synchronize(managedDirectory: managed, to: destination, mode: mode, backupRoot: backupRoot)

        #expect(try String(contentsOf: destination.appendingPathComponent("review/SKILL.md"), encoding: .utf8) == "original")
        #expect(try FileManager.default.destinationOfSymbolicLink(atPath: alias.path) == "managed")
        let backups = try FileManager.default.contentsOfDirectory(at: backupRoot, includingPropertiesForKeys: nil)
        try #require(backups.count == 1)
        let backup = try #require(backups.first)
        #expect(try FileManager.default.destinationOfSymbolicLink(atPath: backup.path) == target)
        try service.synchronize(managedDirectory: managed, to: destination, mode: mode, backupRoot: backupRoot)
        #expect(try FileManager.default.contentsOfDirectory(atPath: backupRoot.path).count == 1)
        try FileManager.default.removeItem(at: destination)
        try FileManager.default.moveItem(at: backup, to: destination)
        #expect(try String(contentsOf: destination.appendingPathComponent("review/SKILL.md"), encoding: .utf8) == "original")
        try expectNoStagingDirectories(beside: managed)
    }

    @Test(arguments: ["alias", "alias/"])
    func disableKeepsThirdPartyIndirectManagedRootLink(target: String) throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let managed = root.appendingPathComponent("managed", isDirectory: true)
        let alias = root.appendingPathComponent("alias")
        let destination = root.appendingPathComponent("skills")
        try writeFile("original", at: managed.appendingPathComponent("review/SKILL.md"))
        try FileManager.default.createSymbolicLink(atPath: alias.path, withDestinationPath: "managed")
        try FileManager.default.createSymbolicLink(atPath: destination.path, withDestinationPath: target)

        try AIAgentSkillSynchronizationService().disable(at: destination, managedDirectory: managed)

        #expect(try FileManager.default.destinationOfSymbolicLink(atPath: destination.path) == target)
        #expect(try String(contentsOf: destination.appendingPathComponent("review/SKILL.md"), encoding: .utf8) == "original")
    }

    @Test(arguments: [AIAgentSkillSynchronizationMode.symbolicLink, .fileCopy])
    func preservesLinksWhoseDotDotTargetResolvesOutsideManagedRoot(mode: AIAgentSkillSynchronizationMode) throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let managed = root.appendingPathComponent("managed", isDirectory: true)
        let destination = root.appendingPathComponent("skills")
        let alias = root.appendingPathComponent("alias")
        let external = root.appendingPathComponent("external/managed", isDirectory: true)
        let backupRoot = root.appendingPathComponent("backups")
        try writeFile("managed", at: managed.appendingPathComponent("review/SKILL.md"))
        try writeFile("external", at: external.appendingPathComponent("custom/SKILL.md"))
        try FileManager.default.createDirectory(at: root.appendingPathComponent("external/nested"), withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(atPath: alias.path, withDestinationPath: "external/nested")
        try FileManager.default.createSymbolicLink(atPath: destination.path, withDestinationPath: "alias/../managed")
        let service = AIAgentSkillSynchronizationService()

        try service.disable(at: destination, managedDirectory: managed)
        #expect(try FileManager.default.destinationOfSymbolicLink(atPath: destination.path) == "alias/../managed")
        try service.synchronize(managedDirectory: managed, to: destination, mode: mode, backupRoot: backupRoot)

        #expect(try String(contentsOf: managed.appendingPathComponent("custom/SKILL.md"), encoding: .utf8) == "external")
        #expect(try String(contentsOf: external.appendingPathComponent("custom/SKILL.md"), encoding: .utf8) == "external")
        let backups = try FileManager.default.contentsOfDirectory(at: backupRoot, includingPropertiesForKeys: nil)
        try #require(backups.count == 1)
        let backup = try #require(backups.first)
        #expect(try FileManager.default.destinationOfSymbolicLink(atPath: backup.path) == "alias/../managed")
        try FileManager.default.removeItem(at: destination)
        try FileManager.default.moveItem(at: backup, to: destination)
        #expect(try String(contentsOf: destination.appendingPathComponent("custom/SKILL.md"), encoding: .utf8) == "external")
        try expectNoStagingDirectories(beside: managed)
    }

    @Test(arguments: [AIAgentSkillSynchronizationMode.symbolicLink, .fileCopy])
    func refusesTakeoverWhenManagedRootDependsOnDestination(mode: AIAgentSkillSynchronizationMode) throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let managed = root.appendingPathComponent("managed")
        let destination = root.appendingPathComponent("skills")
        let external = root.appendingPathComponent("external", isDirectory: true)
        let backupRoot = root.appendingPathComponent("backups")
        try writeFile("original", at: external.appendingPathComponent("review/SKILL.md"))
        try FileManager.default.createSymbolicLink(atPath: destination.path, withDestinationPath: "external")
        try FileManager.default.createSymbolicLink(atPath: managed.path, withDestinationPath: "skills")

        #expect(throws: AIAgentSkillSynchronizationError.self) {
            try AIAgentSkillSynchronizationService().synchronize(
                managedDirectory: managed, to: destination, mode: mode, backupRoot: backupRoot
            )
        }

        #expect(try FileManager.default.destinationOfSymbolicLink(atPath: managed.path) == "skills")
        #expect(try FileManager.default.destinationOfSymbolicLink(atPath: destination.path) == "external")
        #expect(try String(contentsOf: managed.appendingPathComponent("review/SKILL.md"), encoding: .utf8) == "original")
        #expect(try FileManager.default.contentsOfDirectory(atPath: external.path) == ["review"])
        #expect((try? FileManager.default.contentsOfDirectory(atPath: backupRoot.path))?.isEmpty != false)
        try expectNoStagingDirectories(beside: managed)
    }

    @Test(arguments: [AIAgentSkillSynchronizationMode.symbolicLink, .fileCopy])
    func importsRelativeSkillLinksAndKeepsRestorableOriginals(mode: AIAgentSkillSynchronizationMode) throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let managed = root.appendingPathComponent(".zisla/skills", isDirectory: true)
        let destination = root.appendingPathComponent(".claude/skills", isDirectory: true)
        let backupRoot = root.appendingPathComponent("backups", isDirectory: true)
        let original = root.appendingPathComponent(".claude/shared/review/SKILL.md")
        try FileManager.default.createDirectory(at: original.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("original skill".utf8).write(to: original)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(
            atPath: destination.appendingPathComponent("review").path,
            withDestinationPath: "../shared/review"
        )

        try AIAgentSkillSynchronizationService().synchronize(
            managedDirectory: managed,
            to: destination,
            mode: mode,
            backupRoot: backupRoot
        )

        #expect(try String(contentsOf: managed.appendingPathComponent("review/SKILL.md"), encoding: .utf8) == "original skill")
        #expect(try String(contentsOf: destination.appendingPathComponent("review/SKILL.md"), encoding: .utf8) == "original skill")
        #expect(try String(contentsOf: original, encoding: .utf8) == "original skill")
        let backups = try FileManager.default.contentsOfDirectory(at: backupRoot, includingPropertiesForKeys: nil)
        #expect(backups.count == 1)
        let backup = try #require(backups.first)
        #expect(try FileManager.default.destinationOfSymbolicLink(atPath: backup.appendingPathComponent("review").path) == "../shared/review")
        try FileManager.default.removeItem(at: destination)
        try FileManager.default.moveItem(at: backup, to: destination)
        #expect(try String(contentsOf: destination.appendingPathComponent("review/SKILL.md"), encoding: .utf8) == "original skill")
    }

    @Test(arguments: [AIAgentSkillSynchronizationMode.symbolicLink, .fileCopy])
    func importingLinkedRootsDoesNotCreateSelfReferencingSkills(mode: AIAgentSkillSynchronizationMode) throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let managed = root.appendingPathComponent(".zisla/skills", isDirectory: true)
        let codex = root.appendingPathComponent(".codex/skills", isDirectory: true)
        let agents = root.appendingPathComponent(".agents/skills", isDirectory: true)
        let original = agents.appendingPathComponent("review/SKILL.md")
        try FileManager.default.createDirectory(at: original.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("central skill".utf8).write(to: original)
        try FileManager.default.createDirectory(at: codex, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(
            atPath: codex.appendingPathComponent("review").path,
            withDestinationPath: "../../.agents/skills/review"
        )

        let service = AIAgentSkillSynchronizationService()
        for destination in [codex, agents] {
            try service.synchronize(
                managedDirectory: managed,
                to: destination,
                mode: mode,
                backupRoot: root.appendingPathComponent("backups/\(destination.deletingLastPathComponent().lastPathComponent)")
            )
        }

        for directory in [managed, codex, agents] {
            #expect(try String(contentsOf: directory.appendingPathComponent("review/SKILL.md"), encoding: .utf8) == "central skill")
        }
    }

    @Test(arguments: [0, 1, 3])
    func importsNestedRelativeResourceLinks(depth: Int) throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let managed = root.appendingPathComponent("managed", isDirectory: true)
        let destination = root.appendingPathComponent(".claude/skills", isDirectory: true)
        let original = root.appendingPathComponent(".claude/shared/reference.md")
        try FileManager.default.createDirectory(at: original.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("reference content".utf8).write(to: original)
        let skill = destination.appendingPathComponent("review", isDirectory: true)
        try FileManager.default.createDirectory(at: skill, withIntermediateDirectories: true)
        try Data("skill".utf8).write(to: skill.appendingPathComponent("SKILL.md"))
        let resourcePath = (["review"] + (0..<depth).map { "nested-\($0)" } + ["reference.md"]).joined(separator: "/")
        let resourceLink = destination.appendingPathComponent(resourcePath)
        try FileManager.default.createDirectory(at: resourceLink.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(
            atPath: resourceLink.path,
            withDestinationPath: String(repeating: "../", count: depth + 2) + "shared/reference.md"
        )

        try AIAgentSkillSynchronizationService().synchronize(
            managedDirectory: managed,
            to: destination,
            mode: .symbolicLink,
            backupRoot: root.appendingPathComponent("backups")
        )

        #expect(try String(contentsOf: managed.appendingPathComponent(resourcePath), encoding: .utf8) == "reference content")
        #expect(try String(contentsOf: original, encoding: .utf8) == "reference content")
    }

    @Test
    func preservesRelativeRootLinkAndExecutableResourcesInBackup() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let managed = root.appendingPathComponent("managed", isDirectory: true)
        let destination = root.appendingPathComponent(".agents/skills", isDirectory: true)
        let external = root.appendingPathComponent(".agents/catalog", isDirectory: true)
        let script = external.appendingPathComponent("review/scripts/run.sh")
        let backupRoot = root.appendingPathComponent("backups", isDirectory: true)
        try writeFile("skill", at: external.appendingPathComponent("review/SKILL.md"))
        try writeFile("#!/bin/sh\nexit 0\n", at: script)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: script.path)
        try FileManager.default.createSymbolicLink(atPath: destination.path, withDestinationPath: "catalog")
        try FileManager.default.createSymbolicLink(
            atPath: external.appendingPathComponent("review/scripts/current.sh").path,
            withDestinationPath: "run.sh"
        )

        try AIAgentSkillSynchronizationService().synchronize(
            managedDirectory: managed, to: destination, mode: .symbolicLink, backupRoot: backupRoot
        )

        let importedScript = managed.appendingPathComponent("review/scripts/current.sh")
        #expect(try String(contentsOf: importedScript, encoding: .utf8) == "#!/bin/sh\nexit 0\n")
        #expect(try FileManager.default.attributesOfItem(atPath: importedScript.path)[.posixPermissions] as? Int == 0o755)
        let backups = try FileManager.default.contentsOfDirectory(at: backupRoot, includingPropertiesForKeys: nil)
        #expect(backups.count == 1)
        let backup = try #require(backups.first)
        #expect(try FileManager.default.destinationOfSymbolicLink(atPath: backup.path) == "catalog")
        try FileManager.default.removeItem(at: destination)
        try FileManager.default.moveItem(at: backup, to: destination)
        #expect(try String(contentsOf: destination.appendingPathComponent("review/SKILL.md"), encoding: .utf8) == "skill")
    }

    @Test
    func fileCopyMaterializesManagedLinksWithoutChangingTheirSources() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let managed = root.appendingPathComponent(".zisla/skills", isDirectory: true)
        let destination = root.appendingPathComponent(".claude/skills", isDirectory: true)
        let external = root.appendingPathComponent(".zisla/shared/SKILL.md")
        try writeFile("first", at: external)
        try FileManager.default.createDirectory(at: managed, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(
            atPath: managed.appendingPathComponent("review").path, withDestinationPath: "../shared"
        )

        try AIAgentSkillSynchronizationService().synchronize(managedDirectory: managed, to: destination, mode: .fileCopy)
        try Data("changed".utf8).write(to: external)

        #expect(try String(contentsOf: destination.appendingPathComponent("review/SKILL.md"), encoding: .utf8) == "first")
        #expect(try String(contentsOf: managed.appendingPathComponent("review/SKILL.md"), encoding: .utf8) == "changed")
        #expect(try FileManager.default.destinationOfSymbolicLink(atPath: managed.appendingPathComponent("review").path) == "../shared")
        try expectNoStagingDirectories(beside: managed)
    }

    @Test(arguments: ["missing", "."])
    func rejectsInvalidResourceLinksWithoutChangingOriginals(target: String) throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let managed = root.appendingPathComponent("managed", isDirectory: true)
        let destination = root.appendingPathComponent(".claude/skills", isDirectory: true)
        let original = destination.appendingPathComponent("review/SKILL.md")
        let link = destination.appendingPathComponent("review/reference")
        let backupRoot = root.appendingPathComponent("backups")
        try writeFile("keep original", at: original)
        try FileManager.default.createSymbolicLink(atPath: link.path, withDestinationPath: target)
        let fileManager = SkillSyncFailingFileManager()
        fileManager.maximumCopies = 1

        do {
            try AIAgentSkillSynchronizationService(fileManager: fileManager).synchronize(
                managedDirectory: managed, to: destination, mode: .symbolicLink, backupRoot: backupRoot
            )
            Issue.record("An invalid link must abort migration")
        } catch {
            if target == "." {
                #expect((error as? POSIXError)?.code == .ELOOP)
            } else {
                #expect((error as? CocoaError)?.code == .fileReadNoSuchFile)
            }
        }

        #expect(try String(contentsOf: original, encoding: .utf8) == "keep original")
        #expect(try FileManager.default.destinationOfSymbolicLink(atPath: link.path) == target)
        #expect(try FileManager.default.contentsOfDirectory(atPath: managed.path).isEmpty)
        #expect(!FileManager.default.fileExists(atPath: backupRoot.path))
        try expectNoStagingDirectories(beside: managed)
    }

    @Test(arguments: [false, true])
    func rejectsLinksContainingTheStagingDirectoryBeforeCopying(filesystemRoot: Bool) throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let managed = root.appendingPathComponent("managed", isDirectory: true)
        let destination = root.appendingPathComponent(".claude/skills", isDirectory: true)
        let target = filesystemRoot ? URL(fileURLWithPath: "/", isDirectory: true) : root
        try writeFile("keep", at: destination.appendingPathComponent("review/SKILL.md"))
        try FileManager.default.createSymbolicLink(
            at: destination.appendingPathComponent("review/ancestor"), withDestinationURL: target
        )
        let fileManager = SkillSyncFailingFileManager()
        // Reject a recursive copy even if the containment check regresses.
        fileManager.copyFailureSource = target

        #expect(throws: POSIXError.self) {
            try AIAgentSkillSynchronizationService(fileManager: fileManager).synchronize(
                managedDirectory: managed, to: destination, mode: .symbolicLink,
                backupRoot: root.appendingPathComponent("backups")
            )
        }
        #expect(try String(contentsOf: destination.appendingPathComponent("review/SKILL.md"), encoding: .utf8) == "keep")
        #expect(try FileManager.default.contentsOfDirectory(atPath: managed.path).isEmpty)
        try expectNoStagingDirectories(beside: managed)
    }

    @Test(arguments: ["snapshot", "backup", "import", "install", "installed"])
    func failedTakeoverRestoresOriginalsAndRemovesPartialImports(failure: String) throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let managed = root.appendingPathComponent("managed", isDirectory: true)
        let destination = root.appendingPathComponent(".claude/skills", isDirectory: true)
        let backupRoot = root.appendingPathComponent("backups", isDirectory: true)
        try writeFile("managed version", at: managed.appendingPathComponent("keep/SKILL.md"))
        try writeFile("first original", at: destination.appendingPathComponent("first/SKILL.md"))
        try writeFile("second original", at: destination.appendingPathComponent("second/SKILL.md"))
        let fileManager = SkillSyncFailingFileManager()
        fileManager.failure = failure
        fileManager.originalDestination = destination
        if failure == "snapshot" {
            fileManager.copyFailureSource = destination.appendingPathComponent("second")
        }

        #expect(throws: CocoaError.self) {
            try AIAgentSkillSynchronizationService(fileManager: fileManager).synchronize(
                managedDirectory: managed, to: destination, mode: .symbolicLink, backupRoot: backupRoot
            )
        }

        #expect(try String(contentsOf: destination.appendingPathComponent("first/SKILL.md"), encoding: .utf8) == "first original")
        #expect(try String(contentsOf: destination.appendingPathComponent("second/SKILL.md"), encoding: .utf8) == "second original")
        #expect(try String(contentsOf: managed.appendingPathComponent("keep/SKILL.md"), encoding: .utf8) == "managed version")
        #expect(try FileManager.default.contentsOfDirectory(atPath: managed.path) == ["keep"])
        #expect((try? FileManager.default.destinationOfSymbolicLink(atPath: destination.path)) == nil)
        try expectNoStagingDirectories(beside: managed)
    }

    @Test(arguments: ["snapshot", "install", "installed"])
    func failedFileCopyRefreshKeepsPreviousCopy(failure: String) throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let managed = root.appendingPathComponent("managed", isDirectory: true)
        let destination = root.appendingPathComponent(".claude/skills", isDirectory: true)
        let skill = managed.appendingPathComponent("review/SKILL.md")
        try writeFile("first", at: skill)
        try AIAgentSkillSynchronizationService().synchronize(managedDirectory: managed, to: destination, mode: .fileCopy)
        try Data("updated".utf8).write(to: skill)
        let fileManager = SkillSyncFailingFileManager()
        fileManager.failure = failure
        if failure == "snapshot" { fileManager.copyFailureSource = managed }

        #expect(throws: CocoaError.self) {
            try AIAgentSkillSynchronizationService(fileManager: fileManager).synchronize(
                managedDirectory: managed, to: destination, mode: .fileCopy
            )
        }

        #expect(try String(contentsOf: destination.appendingPathComponent("review/SKILL.md"), encoding: .utf8) == "first")
        #expect(try String(contentsOf: skill, encoding: .utf8) == "updated")
        try expectNoStagingDirectories(beside: managed)
    }

    @Test
    func failedRestorationRetainsRecoverablePreviousCopy() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let managed = root.appendingPathComponent("managed", isDirectory: true)
        let destination = root.appendingPathComponent(".claude/skills", isDirectory: true)
        try writeFile("original", at: managed.appendingPathComponent("review/SKILL.md"))
        try AIAgentSkillSynchronizationService().synchronize(managedDirectory: managed, to: destination, mode: .fileCopy)
        let fileManager = SkillSyncFailingFileManager()
        fileManager.failure = "install"
        fileManager.failsRestoration = true

        #expect(throws: CocoaError.self) {
            try AIAgentSkillSynchronizationService(fileManager: fileManager).synchronize(
                managedDirectory: managed, to: destination, mode: .fileCopy
            )
        }

        let stagingDirectories = try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)
            .filter { $0.lastPathComponent.hasPrefix(".zisla-skill-sync-") }
        #expect(stagingDirectories.count == 1)
        let previous = try #require(stagingDirectories.first).appendingPathComponent("previous")
        #expect(try String(contentsOf: previous.appendingPathComponent("review/SKILL.md"), encoding: .utf8) == "original")
        try FileManager.default.moveItem(at: previous, to: destination)
        #expect(try String(contentsOf: destination.appendingPathComponent("review/SKILL.md"), encoding: .utf8) == "original")
    }

    @Test(arguments: ["same", "source-inside-destination", "destination-inside-source", "destination-parent-alias", "reverse-alias"])
    func refusesOverlappingDirectoriesWithoutRemovingSkills(layout: String) throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let managed: URL
        let destination: URL
        switch layout {
        case "same":
            managed = root.appendingPathComponent("skills", isDirectory: true)
            destination = managed
        case "source-inside-destination":
            destination = root.appendingPathComponent("skills", isDirectory: true)
            managed = destination.appendingPathComponent("managed", isDirectory: true)
        case "destination-inside-source":
            managed = root.appendingPathComponent("skills", isDirectory: true)
            destination = managed.appendingPathComponent("destination", isDirectory: true)
        case "destination-parent-alias":
            managed = root.appendingPathComponent("skills", isDirectory: true)
            let alias = root.appendingPathComponent("alias", isDirectory: true)
            try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: managed)
            destination = alias.appendingPathComponent("destination", isDirectory: true)
        default:
            managed = root.appendingPathComponent("managed", isDirectory: true)
            destination = root.appendingPathComponent("skills", isDirectory: true)
            try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
            try FileManager.default.createSymbolicLink(at: managed, withDestinationURL: destination)
        }
        let skill = managed.appendingPathComponent("review/SKILL.md")
        try writeFile("keep", at: skill)
        let service = AIAgentSkillSynchronizationService()

        #expect(throws: AIAgentSkillSynchronizationError.self) {
            try service.synchronize(
                managedDirectory: managed, to: destination, mode: .symbolicLink,
                backupRoot: root.appendingPathComponent("backups")
            )
        }
        #expect(throws: AIAgentSkillSynchronizationError.self) {
            try service.disable(at: destination, managedDirectory: managed)
        }
        #expect(try String(contentsOf: skill, encoding: .utf8) == "keep")
    }

    @Test
    func legacyAndTopLevelConflictsRemainInOriginalBackup() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let managed = root.appendingPathComponent("managed", isDirectory: true)
        let destination = root.appendingPathComponent(".claude/skills", isDirectory: true)
        let backupRoot = root.appendingPathComponent("backups")
        try writeFile("current", at: destination.appendingPathComponent("review/SKILL.md"))
        try writeFile("legacy", at: destination.appendingPathComponent("zisla-managed/review/SKILL.md"))

        try AIAgentSkillSynchronizationService().synchronize(
            managedDirectory: managed, to: destination, mode: .symbolicLink, backupRoot: backupRoot
        )

        let imported = try String(contentsOf: managed.appendingPathComponent("review/SKILL.md"), encoding: .utf8)
        #expect(["current", "legacy"].contains(imported))
        let backups = try FileManager.default.contentsOfDirectory(at: backupRoot, includingPropertiesForKeys: nil)
        #expect(backups.count == 1)
        let backup = try #require(backups.first)
        #expect(try String(contentsOf: backup.appendingPathComponent("review/SKILL.md"), encoding: .utf8) == "current")
        #expect(try String(contentsOf: backup.appendingPathComponent("zisla-managed/review/SKILL.md"), encoding: .utf8) == "legacy")
    }

    @Test
    func refusesSelfReferencingManagedRootWithoutRemovingIt() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let managed = root.appendingPathComponent("managed", isDirectory: true)
        try FileManager.default.createSymbolicLink(at: managed, withDestinationURL: managed)
        let service = AIAgentSkillSynchronizationService()

        #expect(throws: AIAgentSkillSynchronizationError.self) {
            try service.synchronize(managedDirectory: managed, to: managed, mode: .symbolicLink)
        }
        #expect(throws: AIAgentSkillSynchronizationError.self) {
            try service.disable(at: managed, managedDirectory: managed)
        }
        #expect(try FileManager.default.destinationOfSymbolicLink(atPath: managed.path) == managed.path)
    }

    @Test(arguments: [AIAgentSkillSynchronizationMode.symbolicLink, .fileCopy])
    func emptyLibraryCanSwitchModesAndDisable(mode: AIAgentSkillSynchronizationMode) throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let managed = root.appendingPathComponent("managed", isDirectory: true)
        let destination = root.appendingPathComponent(".claude/skills", isDirectory: true)
        let service = AIAgentSkillSynchronizationService()
        try service.synchronize(managedDirectory: managed, to: destination, mode: .symbolicLink)
        try service.synchronize(managedDirectory: managed, to: destination, mode: .fileCopy)
        try service.synchronize(managedDirectory: managed, to: destination, mode: mode)
        try service.disable(at: destination, managedDirectory: managed)

        #expect(!FileManager.default.fileExists(atPath: destination.path))
        #expect((try? FileManager.default.destinationOfSymbolicLink(atPath: destination.path)) == nil)
        #expect(try FileManager.default.contentsOfDirectory(atPath: managed.path).isEmpty)
        try expectNoStagingDirectories(beside: managed)
    }

    private func writeFile(_ contents: String, at url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(contents.utf8).write(to: url)
    }

    private func expectNoStagingDirectories(beside directory: URL) throws {
        let names = try FileManager.default.contentsOfDirectory(atPath: directory.deletingLastPathComponent().path)
        #expect(!names.contains { $0.hasPrefix(".zisla-skill-sync-") })
    }

    private func temporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("zisla-skill-sync-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }
}

private final class SkillSyncFailingFileManager: FileManager, @unchecked Sendable {
    var failure = ""
    var copyFailureSource: URL?
    var originalDestination: URL?
    var failsRestoration = false
    var maximumCopies: Int?
    private var copies = 0
    private var importedItems = 0

    override func copyItem(at srcURL: URL, to dstURL: URL) throws {
        copies += 1
        if let maximumCopies, copies > maximumCopies {
            throw CocoaError(.fileReadNoPermission)
        }
        if srcURL.standardizedFileURL == copyFailureSource?.standardizedFileURL {
            throw CocoaError(.fileReadNoPermission)
        }
        try super.copyItem(at: srcURL, to: dstURL)
    }

    override func moveItem(at srcURL: URL, to dstURL: URL) throws {
        if failure == "backup", srcURL == originalDestination {
            throw CocoaError(.fileWriteNoPermission)
        }
        if srcURL.deletingLastPathComponent().lastPathComponent == "imports" {
            importedItems += 1
            if failure == "import", importedItems == 2 {
                throw CocoaError(.fileWriteNoPermission)
            }
        }
        if srcURL.lastPathComponent == "replacement", failure == "install" {
            throw CocoaError(.fileWriteNoPermission)
        }
        if srcURL.lastPathComponent == "previous", failsRestoration {
            throw CocoaError(.fileWriteNoPermission)
        }
        try super.moveItem(at: srcURL, to: dstURL)
        if srcURL.lastPathComponent == "replacement", failure == "installed" {
            throw CocoaError(.fileWriteUnknown)
        }
    }
}
