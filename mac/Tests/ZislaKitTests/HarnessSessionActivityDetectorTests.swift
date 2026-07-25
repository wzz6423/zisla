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
}

private func makeHarnessTempRoot() throws -> URL {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("Zisla-harness-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}
