import CryptoKit
import Foundation
import Testing
import ZislaCore
@testable import ZislaKit

@Suite(.enabled(if: ProcessInfo.processInfo.environment["ZISLA_SKILL_SYNC_TEST_HOME"] != nil))
struct AIAgentSkillSynchronizationSystemTests {
    @Test
    @MainActor
    func isolatedHomeLifecycle() throws {
        let environment = ProcessInfo.processInfo.environment
        let homePath = try #require(environment["ZISLA_SKILL_SYNC_TEST_HOME"])
        let home = URL(fileURLWithPath: homePath, isDirectory: true).resolvingSymlinksInPath()
        try #require(FileManager.default.homeDirectoryForCurrentUser.resolvingSymlinksInPath() == home)
        try #require(try String(contentsOf: home.appendingPathComponent(".skill-sync-test-home"), encoding: .utf8) == "isolated skill sync fixture")
        ProcessInfo.processInfo.processName = try #require(environment["ZISLA_SKILL_SYNC_TEST_PROCESS"])
        let count = try #require(Int(environment["ZISLA_SKILL_SYNC_TEST_COUNT"] ?? ""))
        try #require([0, 1, 50, 100, 150, 1000].contains(count))
        let layout = try #require(environment["ZISLA_SKILL_SYNC_TEST_LAYOUT"])
        let mode = try #require(AgentSkillSyncMode(rawValue: environment["ZISLA_SKILL_SYNC_TEST_MODE"] ?? ""))
        let failureLayouts = ["broken", "cycle", "readonly-backup"]
        try #require((["plain", "relative", "absolute", "chain", "root-link", "mixed"] + failureLayouts).contains(layout))
        let start = ProcessInfo.processInfo.systemUptime
        let fileManager = FileManager.default
        let storeURL = home.appendingPathComponent(".zisla/test-state.json")
        let store = AIAgentStore(storageURL: storeURL)
        store.state.skillSyncConfiguration.mode = mode
        let workspace = AIAgentWorkspace(store: store)
        let destinations = AgentSkillSyncDestination.allCases
        let roots = destinations.map { workspace.managedSkillDestinationDirectory(for: $0) }
        let fixtures = home.appendingPathComponent(".fixture-skills", isDirectory: true)
        try fileManager.createDirectory(at: fixtures, withIntermediateDirectories: true)
        for root in roots {
            try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        }

        for index in 0..<count {
            let name = index.isMultiple(of: 17) ? "技能 \(index)" : String(format: "skill-%04d", index)
            let fixture = fixtures.appendingPathComponent(name, isDirectory: true)
            try write("---\nname: \(name)\ndescription: Fixture \(index)\n---\n# Skill \(index)\n", to: fixture.appendingPathComponent("SKILL.md"))
            try write("#!/bin/sh\nprintf '%s\\n' 'skill \(index)'\n", to: fixture.appendingPathComponent("scripts/run.sh"))
            try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: fixture.appendingPathComponent("scripts/run.sh").path)
            try write("Reference \(index)\n", to: fixture.appendingPathComponent("references/deep/guide.txt"))
            try write("Hidden resource \(index)\n", to: fixture.appendingPathComponent(".resource"))

            let owner: Int
            if failureLayouts.contains(layout) {
                owner = 0
            } else {
                owner = ["plain", "mixed"].contains(layout) ? index % roots.count : 2
            }
            let installed = roots[owner].appendingPathComponent(name, isDirectory: true)
            try fileManager.copyItem(at: fixture, to: installed)
            if !(["plain"] + failureLayouts).contains(layout) {
                let references = installed.appendingPathComponent("references")
                try fileManager.removeItem(at: references)
                try fileManager.createSymbolicLink(atPath: references.path, withDestinationPath: "../../../.fixture-skills/\(name)/references")
                let script = installed.appendingPathComponent("scripts/run.sh")
                try fileManager.removeItem(at: script)
                try fileManager.createSymbolicLink(at: script, withDestinationURL: fixture.appendingPathComponent("scripts/run.sh"))
            }
            if ["relative", "absolute", "chain", "mixed"].contains(layout) {
                for other in roots.indices where other != owner {
                    let target = layout == "chain" && other == 0 ? 1 : owner
                    let link = roots[other].appendingPathComponent(name)
                    let relative = "../../.\(destinations[target].rawValue)/skills/\(name)"
                    let absolute = roots[target].appendingPathComponent(name).path
                    try fileManager.createSymbolicLink(
                        atPath: link.path,
                        withDestinationPath: layout == "absolute" || (layout == "mixed" && other == 1) ? absolute : relative
                    )
                }
            }
        }
        if layout == "root-link" {
            for root in roots.prefix(2) {
                try fileManager.removeItem(at: root)
                try fileManager.createSymbolicLink(atPath: root.path, withDestinationPath: "../.agents/skills")
            }
        }
        if ["broken", "cycle"].contains(layout) {
            try #require(count > 0)
            try fileManager.createSymbolicLink(
                atPath: roots[0].appendingPathComponent("技能 0/invalid").path,
                withDestinationPath: layout == "cycle" ? "." : "missing"
            )
        }
        if layout == "readonly-backup" {
            let backup = workspace.managedSkillBackupDirectory(for: .codex)
            try fileManager.createDirectory(at: backup, withIntermediateDirectories: true)
            try fileManager.setAttributes([.posixPermissions: 0o555], ofItemAtPath: backup.path)
        }

        let originalTrees = try roots.map { try manifest(at: $0) }
        let originalFixtures = try manifest(at: fixtures)
        workspace.synchronizeManagedSkills()
        if failureLayouts.contains(layout) {
            try #require(workspace.lastError != nil, "\(layout) must abort synchronization")
            #expect(try roots.map { try manifest(at: $0) } == originalTrees)
            #expect(try manifest(at: fixtures) == originalFixtures)
            #expect(try fileManager.contentsOfDirectory(atPath: workspace.managedSkillsDirectory.path).isEmpty)
            try expectNoStaging(in: home)
            print("SKILL_SYNC_RESULT \(layout) \(count) \(mode.rawValue) completed \(ProcessInfo.processInfo.systemUptime - start)s")
            return
        }

        var expected = originalFixtures
        try expectLibrary(workspace, manifest: expected, mode: mode, count: count)
        #expect(try manifest(at: fixtures) == originalFixtures)
        var originals: [URL] = []
        for (index, destination) in destinations.enumerated() {
            let backups = try fileManager.contentsOfDirectory(at: workspace.managedSkillBackupDirectory(for: destination), includingPropertiesForKeys: nil)
            try #require(backups.count == 1)
            let backup = try #require(backups.first)
            #expect(try manifest(at: backup) == originalTrees[index])
            originals.append(backup)
        }
        workspace.synchronizeManagedSkills()
        try expectLibrary(workspace, manifest: expected, mode: mode, count: count)
        for destination in destinations {
            #expect(try fileManager.contentsOfDirectory(atPath: workspace.managedSkillBackupDirectory(for: destination).path).count == 1)
        }
        store.flushPendingChanges()
        let reopenedStore = AIAgentStore(storageURL: storeURL)
        #expect(reopenedStore.state.skillSyncConfiguration == store.state.skillSyncConfiguration)

        let nextMode: AgentSkillSyncMode = mode == .symbolicLink ? .fileCopy : .symbolicLink
        workspace.updateManagedSkillSyncMode(nextMode)
        try expectLibrary(workspace, manifest: expected, mode: nextMode, count: count)
        if count > 0 {
            let skillPath = "技能 0/SKILL.md"
            try write("external update", to: fixtures.appendingPathComponent(skillPath))
            try expectLibrary(workspace, manifest: expected, mode: nextMode, count: count)
            try write("managed update", to: workspace.managedSkillsDirectory.appendingPathComponent(skillPath))
            expected[skillPath] = try entry(at: workspace.managedSkillsDirectory.appendingPathComponent(skillPath))
            if nextMode == .fileCopy {
                for root in roots {
                    #expect(try entry(at: root.appendingPathComponent(skillPath)) == originalFixtures[skillPath])
                }
            }
            workspace.synchronizeManagedSkills()
            try expectLibrary(workspace, manifest: expected, mode: nextMode, count: count)
            let process = Process()
            process.executableURL = workspace.managedSkillsDirectory.appendingPathComponent("技能 0/scripts/run.sh")
            let output = Pipe()
            process.standardOutput = output
            try process.run()
            process.waitUntilExit()
            #expect(process.terminationStatus == 0)
            #expect(String(data: output.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) == "skill 0\n")
        }
        for destination in destinations {
            workspace.setManagedSkillDestination(destination, enabled: false)
        }
        try #require(workspace.lastError == nil)
        #expect(try manifest(at: workspace.managedSkillsDirectory) == expected)
        for (index, root) in roots.enumerated() {
            #expect(!fileManager.fileExists(atPath: root.path))
            #expect((try? fileManager.destinationOfSymbolicLink(atPath: root.path)) == nil)
            try fileManager.moveItem(at: originals[index], to: root)
        }
        #expect(try roots.map { try manifest(at: $0) } == originalTrees)
        for root in roots {
            for name in try fileManager.contentsOfDirectory(atPath: root.path) {
                for suffix in ["SKILL.md", "scripts/run.sh", "references/deep/guide.txt", ".resource"] {
                    let relative = "\(name)/\(suffix)"
                    #expect(try digest(at: root.appendingPathComponent(relative)) == originalFixtures[relative]?.digest)
                }
            }
        }
        try expectNoStaging(in: home)
        store.flushPendingChanges()
        print("SKILL_SYNC_RESULT \(layout) \(count) \(mode.rawValue) completed \(ProcessInfo.processInfo.systemUptime - start)s")
    }

    private struct Entry: Equatable {
        let type: FileAttributeType
        let permissions: Int
        let digest: String?
        let link: String?
    }

    private func digest(at url: URL) throws -> String {
        SHA256.hash(data: try Data(contentsOf: url)).map { String(format: "%02x", $0) }.joined()
    }

    private func entry(at url: URL) throws -> Entry {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        let type = try #require(attributes[.type] as? FileAttributeType)
        return Entry(
            type: type,
            permissions: try #require(attributes[.posixPermissions] as? Int),
            digest: type == .typeRegular ? try digest(at: url) : nil,
            link: type == .typeSymbolicLink ? try FileManager.default.destinationOfSymbolicLink(atPath: url.path) : nil
        )
    }

    private func manifest(at root: URL) throws -> [String: Entry] {
        if (try? FileManager.default.destinationOfSymbolicLink(atPath: root.path)) != nil {
            return [".": try entry(at: root)]
        }
        let enumerator = try #require(FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil))
        var result: [String: Entry] = [:]
        for case let url as URL in enumerator {
            let relative = url.pathComponents.suffix(enumerator.level).joined(separator: "/")
            if relative != ".zisla-skill-sync" {
                result[relative] = try entry(at: url)
            }
        }
        return result
    }

    @MainActor
    private func expectLibrary(_ workspace: AIAgentWorkspace, manifest expected: [String: Entry], mode: AgentSkillSyncMode, count: Int) throws {
        try #require(workspace.lastError == nil, "\(workspace.lastError ?? "")")
        let managed = workspace.managedSkillsDirectory
        try expectManifest(expected, at: managed)
        for destination in AgentSkillSyncDestination.allCases {
            let root = workspace.managedSkillDestinationDirectory(for: destination)
            let link = try? FileManager.default.destinationOfSymbolicLink(atPath: root.path)
            #expect((link != nil) == (mode == .symbolicLink))
            let names = try FileManager.default.contentsOfDirectory(atPath: root.path).filter { $0 != ".zisla-skill-sync" }
            try #require(names.count == count, "\(destination.rawValue) must receive every skill in one synchronization")
            try expectManifest(expected, at: root.resolvingSymlinksInPath())
        }
        #expect(AIAgentSkillService().scan(roots: [managed] + AIAgentSkillService.defaultRoots).count == count)
    }

    private func expectManifest(_ expected: [String: Entry], at root: URL) throws {
        let actual = try manifest(at: root)
        try #require(actual.count == expected.count, "\(root.lastPathComponent) must contain every skill resource")
        for path in expected.keys.sorted() {
            try #require(actual[path] == expected[path], "\(root.path)/\(path) must preserve contents and permissions")
        }
    }

    private func write(_ text: String, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(text.utf8).write(to: url)
    }

    private func expectNoStaging(in home: URL) throws {
        let names = try FileManager.default.contentsOfDirectory(atPath: home.appendingPathComponent(".zisla").path)
        #expect(!names.contains { $0.hasPrefix(".zisla-skill-sync-") })
    }
}
