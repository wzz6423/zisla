import Foundation
import Testing
@testable import ZislaCore
@testable import ZislaKit

struct HarnessSessionActivityDetectorTests {
    @Test
    func detectsRecentFileAsActive() throws {
        let root = try makeHarnessTempRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        let logURL = root.appendingPathComponent("session-recent.json")
        try Data(#"{"status":"running"}"#.utf8).write(to: logURL)

        let tasks = try HarnessSessionActivityDetector(
            dataRoot: root,
            recencyThreshold: 3600
        ).activeTasks()
        #expect(tasks.count == 1)
        #expect(tasks[0].provider == .harness)
        #expect(tasks[0].title == "harnext")
        #expect(tasks[0].status == .running)
    }

    @Test
    func ignoresStaleFiles() throws {
        let root = try makeHarnessTempRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        let logURL = root.appendingPathComponent("session-stale.log")
        try Data("old data".utf8).write(to: logURL)
        // Set modification time to 2 hours ago
        let oldTime = Date().addingTimeInterval(-7200)
        try FileManager.default.setAttributes(
            [.modificationDate: oldTime],
            ofItemAtPath: logURL.path
        )

        let tasks = try HarnessSessionActivityDetector(
            dataRoot: root,
            recencyThreshold: 60
        ).activeTasks()
        #expect(tasks.isEmpty)
    }

    @Test
    func handlesMissingDirectory() throws {
        let missing = FileManager.default.temporaryDirectory
            .appendingPathComponent("Zisla-harness-missing-\(UUID().uuidString)")
        #expect(try HarnessSessionActivityDetector(dataRoot: missing).activeTasks().isEmpty)
    }

    @Test
    func filtersByExtension() throws {
        let root = try makeHarnessTempRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        try Data("text".utf8).write(to: root.appendingPathComponent("readme.txt"))
        try Data("data".utf8).write(to: root.appendingPathComponent("session.json"))

        let tasks = try HarnessSessionActivityDetector(
            dataRoot: root,
            recencyThreshold: 3600
        ).activeTasks()
        #expect(tasks.count == 1)
        #expect(tasks[0].id == HarnessSessionActivityDetector.taskID(
            forFileURL: root.appendingPathComponent("session.json")
        ))
    }

    @Test
    func detectsDeepSeekHarnessSessionLog() throws {
        let home = try makeHarnessTempRoot()
        defer { try? FileManager.default.removeItem(at: home) }
        let root = HarnessSessionActivityDetector.deepSeekDataRoot(home: home)
        let sessionURL = root
            .appendingPathComponent("projects/example/session-1", isDirectory: true)
            .appendingPathComponent("session.jsonl.zstd")
        try FileManager.default.createDirectory(
            at: sessionURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data("session".utf8).write(to: sessionURL)

        let task = try #require(HarnessSessionActivityDetector(
            dataRoot: root,
            sourceName: HarnessSessionActivityDetector.deepSeekSourceName,
            recencyThreshold: 3600
        ).activeTasks().first)

        #expect(task.title == HarnessSessionActivityDetector.deepSeekSourceName)
    }

    @Test
    func keepsDeepSeekHarnessSessionsDistinct() throws {
        let home = try makeHarnessTempRoot()
        defer { try? FileManager.default.removeItem(at: home) }
        let root = HarnessSessionActivityDetector.deepSeekDataRoot(home: home)
        for sessionID in ["session-1", "session-2"] {
            let sessionURL = root
                .appendingPathComponent("projects/example/\(sessionID)", isDirectory: true)
                .appendingPathComponent("session.jsonl")
            try FileManager.default.createDirectory(
                at: sessionURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try Data("session".utf8).write(to: sessionURL)
        }

        let tasks = try HarnessSessionActivityDetector(
            dataRoot: root,
            sourceName: HarnessSessionActivityDetector.deepSeekSourceName,
            recencyThreshold: 3600
        ).activeTasks()

        #expect(Set(tasks.map(\.id)) == ["deepseek-harness-session-1", "deepseek-harness-session-2"])
    }

    @Test
    func ignoresDeepSeekHarnessConfigurationFiles() throws {
        let home = try makeHarnessTempRoot()
        defer { try? FileManager.default.removeItem(at: home) }
        let root = HarnessSessionActivityDetector.deepSeekDataRoot(home: home)
        let workspaceURL = root.appendingPathComponent("storages/workspace.json")
        try FileManager.default.createDirectory(
            at: workspaceURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data(#"{"workspaces":[]}"#.utf8).write(to: workspaceURL)

        let tasks = try HarnessSessionActivityDetector(
            dataRoot: root,
            sourceName: HarnessSessionActivityDetector.deepSeekSourceName,
            recencyThreshold: 3600
        ).activeTasks()

        #expect(tasks.isEmpty)
    }
}

private func makeHarnessTempRoot() throws -> URL {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("Zisla-harness-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}
