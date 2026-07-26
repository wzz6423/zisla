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
        let skillFile = managed.appendingPathComponent("review/SKILL.md")
        try FileManager.default.createDirectory(at: skillFile.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("first".utf8).write(to: skillFile)

        let service = AIAgentSkillSynchronizationService()
        try service.synchronize(managedDirectory: managed, to: destination, mode: .fileCopy)
        try Data("updated".utf8).write(to: skillFile)

        let copiedFile = destination.appendingPathComponent("review/SKILL.md")
        #expect(try String(contentsOf: copiedFile, encoding: .utf8) == "first")
        try service.disable(at: destination, managedDirectory: managed)
        #expect(!FileManager.default.fileExists(atPath: destination.path))
        #expect(FileManager.default.fileExists(atPath: skillFile.path))
    }

    @Test
    func refusesToReplaceUnmanagedDestination() throws {
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

    private func temporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("zisla-skill-sync-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }
}
