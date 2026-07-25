import Foundation
import Testing
@testable import ZislaCore
@testable import ZislaKit

struct DoubaoSessionActivityDetectorTests {
    @Test
    func detectsRecentFileAsActive() throws {
        let root = makeDoubaoTempRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        try Data("cache".utf8).write(to: root.appendingPathComponent("data.json"))

        let tasks = try DoubaoSessionActivityDetector(
            dataRoots: [root],
            recencyThreshold: 3600,
            scanInterval: 0
        ).activeTasks()
        #expect(tasks.count == 1)
        #expect(tasks[0].provider == .doubao)
        #expect(tasks[0].title == "豆包")
        #expect(tasks[0].status == .running)
    }

    @Test
    func ignoresStaleFiles() throws {
        let root = makeDoubaoTempRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        let fileURL = root.appendingPathComponent("old-data.json")
        try Data("old".utf8).write(to: fileURL)
        let oldTime = Date().addingTimeInterval(-7200)
        try FileManager.default.setAttributes(
            [.modificationDate: oldTime],
            ofItemAtPath: fileURL.path
        )

        let tasks = try DoubaoSessionActivityDetector(
            dataRoots: [root],
            recencyThreshold: 60,
            scanInterval: 0
        ).activeTasks()
        #expect(tasks.isEmpty)
    }

    @Test
    func handlesMissingDirectory() throws {
        let missing = FileManager.default.temporaryDirectory
            .appendingPathComponent("Zisla-doubao-missing-\(UUID().uuidString)")
        #expect(try DoubaoSessionActivityDetector(
            dataRoots: [missing],
            scanInterval: 0
        ).activeTasks().isEmpty)
    }

    @Test
    func usesMostRecentFileTimestamp() throws {
        let root = makeDoubaoTempRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        let oldFile = root.appendingPathComponent("old.json")
        try Data("old".utf8).write(to: oldFile)
        try FileManager.default.setAttributes(
            [.modificationDate: Date().addingTimeInterval(-300)],
            ofItemAtPath: oldFile.path
        )

        let newFile = root.appendingPathComponent("new.json")
        try Data("new".utf8).write(to: newFile)

        let tasks = try DoubaoSessionActivityDetector(
            dataRoots: [root],
            recencyThreshold: 600,
            scanInterval: 0
        ).activeTasks()
        #expect(tasks.count == 1)
        #expect(tasks[0].updatedAt > Date().addingTimeInterval(-60))
    }
}

private func makeDoubaoTempRoot() -> URL {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("Zisla-doubao-\(UUID().uuidString)", isDirectory: true)
    try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}
