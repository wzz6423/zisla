import Foundation
import Testing
@testable import ZislaCore
@testable import ZislaKit

struct DoubaoSessionActivityDetectorTests {
    @Test
    func detectsRecentFileAsActiveWhenDoubaoIsRunning() throws {
        let root = makeDoubaoTempRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        _ = try writeDoubaoChatActivity(in: root)

        let tasks = try DoubaoSessionActivityDetector(
            dataRoots: [root],
            recencyThreshold: 3600,
            scanInterval: 0,
            isDoubaoRunning: { true }
        ).activeTasks()
        #expect(tasks.count == 1)
        #expect(tasks[0].provider == .doubao)
        #expect(tasks[0].title == "豆包")
        #expect(tasks[0].status == .running)
    }

    @Test
    func doesNotDetectRecentFilesWhenDoubaoIsNotRunning() throws {
        let root = makeDoubaoTempRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        _ = try writeDoubaoChatActivity(in: root)

        #expect(try DoubaoSessionActivityDetector(
            dataRoots: [root],
            recencyThreshold: 3600,
            scanInterval: 0,
            isDoubaoRunning: { false }
        ).activeTasks().isEmpty)
    }

    @Test
    func detectsRecentAgentModeActivityWithoutReadingItsContent() throws {
        let root = makeDoubaoTempRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        _ = try writeDoubaoAgentActivity(in: root)

        let task = try #require(DoubaoSessionActivityDetector(
            dataRoots: [root],
            recencyThreshold: 3600,
            scanInterval: 0,
            isDoubaoRunning: { true }
        ).activeTasks().first)
        #expect(task.title == "豆包 Agent Mode")
        #expect(task.detail == "最近活动（90 秒内）")
    }

    @Test
    func matchesDoubaoMainApplicationButNotFinderSyncExtension() {
        #expect(DoubaoSessionActivityDetector.matchesDoubaoApplication(
            bundleIdentifier: "com.bot.pc.doubao",
            localizedName: nil,
            executableName: nil
        ))
        #expect(!DoubaoSessionActivityDetector.matchesDoubaoApplication(
            bundleIdentifier: "com.bot.pc.doubao.FinderSyncExtension",
            localizedName: "豆包",
            executableName: nil
        ))
    }

    @Test
    func ignoresStaleFiles() throws {
        let root = makeDoubaoTempRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        let fileURL = try writeDoubaoChatActivity(in: root, named: "old-data.log")
        let oldTime = Date().addingTimeInterval(-7200)
        try FileManager.default.setAttributes(
            [.modificationDate: oldTime],
            ofItemAtPath: fileURL.path
        )

        let tasks = try DoubaoSessionActivityDetector(
            dataRoots: [root],
            recencyThreshold: 60,
            scanInterval: 0,
            isDoubaoRunning: { true }
        ).activeTasks()
        #expect(tasks.isEmpty)
    }

    @Test
    func handlesMissingDirectory() throws {
        let missing = FileManager.default.temporaryDirectory
            .appendingPathComponent("Zisla-doubao-missing-\(UUID().uuidString)")
        #expect(try DoubaoSessionActivityDetector(
            dataRoots: [missing],
            scanInterval: 0,
            isDoubaoRunning: { true }
        ).activeTasks().isEmpty)
    }

    @Test
    func scansTheMostRecentCandidatesAfterSorting() throws {
        let root = makeDoubaoTempRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let current = Date(timeIntervalSince1970: 1_900_000_000)

        let staleURL = try writeDoubaoChatActivity(
            in: root,
            named: "000001-stale.log",
            includeTask: false
        )
        try FileManager.default.setAttributes(
            [.modificationDate: current.addingTimeInterval(-2)],
            ofItemAtPath: staleURL.path
        )
        let activeURL = try writeDoubaoChatActivity(
            in: root,
            named: "000002-active.log",
            taskCreatedAt: current.addingTimeInterval(-1)
        )
        try FileManager.default.setAttributes(
            [.modificationDate: current.addingTimeInterval(-1)],
            ofItemAtPath: activeURL.path
        )

        let tasks = try DoubaoSessionActivityDetector(
            dataRoots: [root],
            maxFiles: 1,
            recencyThreshold: 60,
            scanInterval: 0,
            isDoubaoRunning: { true },
            now: { current }
        ).activeTasks()

        #expect(tasks.count == 1)
        #expect(tasks[0].updatedAt == current.addingTimeInterval(-1))
    }

    @Test
    func usesMostRecentFileTimestamp() throws {
        let root = makeDoubaoTempRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        let oldFile = try writeDoubaoChatActivity(in: root, named: "old.log")
        try FileManager.default.setAttributes(
            [.modificationDate: Date().addingTimeInterval(-300)],
            ofItemAtPath: oldFile.path
        )

        _ = try writeDoubaoChatActivity(in: root, named: "new.log")

        let tasks = try DoubaoSessionActivityDetector(
            dataRoots: [root],
            recencyThreshold: 600,
            scanInterval: 0,
            isDoubaoRunning: { true }
        ).activeTasks()
        #expect(tasks.count == 1)
        #expect(tasks[0].updatedAt > Date().addingTimeInterval(-60))
    }

    @Test
    func ignoresUnknownAgentModeArtifacts() throws {
        let root = makeDoubaoTempRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let fileURL = root.appendingPathComponent(
            "Default/.doubao/agent_mode/workspace/.sessions/test/unknown.jsonl"
        )
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data("ignored".utf8).write(to: fileURL)

        #expect(try DoubaoSessionActivityDetector(
            dataRoots: [root],
            recencyThreshold: 3600,
            scanInterval: 0,
            isDoubaoRunning: { true }
        ).activeTasks().isEmpty)
    }

    @Test
    func prefersTheMostRecentActivitySource() throws {
        let root = makeDoubaoTempRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let current = Date(timeIntervalSince1970: 1_900_000_000)
        let chatURL = try writeDoubaoChatActivity(in: root)
        let agentURL = try writeDoubaoAgentActivity(in: root)
        try FileManager.default.setAttributes(
            [.modificationDate: current.addingTimeInterval(-2)],
            ofItemAtPath: chatURL.path
        )
        try FileManager.default.setAttributes(
            [.modificationDate: current.addingTimeInterval(-1)],
            ofItemAtPath: agentURL.path
        )

        let task = try #require(DoubaoSessionActivityDetector(
            dataRoots: [root],
            recencyThreshold: 60,
            scanInterval: 0,
            isDoubaoRunning: { true },
            now: { current }
        ).activeTasks().first)
        #expect(task.title == "豆包 Agent Mode")
        #expect(task.updatedAt == current.addingTimeInterval(-1))
    }

    @Test
    func expiresRecentAgentModeActivityAtTheRecencyThreshold() throws {
        let root = makeDoubaoTempRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        var current = Date(timeIntervalSince1970: 1_900_000_000)
        let activityURL = try writeDoubaoAgentActivity(in: root)
        try FileManager.default.setAttributes(
            [.modificationDate: current.addingTimeInterval(-1)],
            ofItemAtPath: activityURL.path
        )
        let detector = DoubaoSessionActivityDetector(
            dataRoots: [root],
            recencyThreshold: 60,
            scanInterval: 120,
            isDoubaoRunning: { true },
            now: { current }
        )

        #expect(try detector.activeTasks().count == 1)
        current = current.addingTimeInterval(60)
        #expect(try detector.activeTasks().isEmpty)
    }

    @Test
    func ignoresRecentNonChatCacheFiles() throws {
        let root = makeDoubaoTempRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let cacheURL = root.appendingPathComponent("Default/GPUCache/data_1")
        try FileManager.default.createDirectory(
            at: cacheURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data("cache".utf8).write(to: cacheURL)

        let tasks = try DoubaoSessionActivityDetector(
            dataRoots: [root],
            recencyThreshold: 3600,
            scanInterval: 0,
            isDoubaoRunning: { true }
        ).activeTasks()

        #expect(tasks.isEmpty)
    }

    @Test
    func expiresCachedActivityAtTheRecencyThreshold() throws {
        let root = makeDoubaoTempRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        var current = Date(timeIntervalSince1970: 1_900_000_000)
        let activityURL = try writeDoubaoChatActivity(
            in: root,
            taskCreatedAt: current.addingTimeInterval(-1)
        )
        try FileManager.default.setAttributes(
            [.modificationDate: current.addingTimeInterval(-1)],
            ofItemAtPath: activityURL.path
        )
        let detector = DoubaoSessionActivityDetector(
            dataRoots: [root],
            recencyThreshold: 60,
            scanInterval: 120,
            isDoubaoRunning: { true },
            now: { current }
        )

        #expect(try detector.activeTasks().count == 1)

        current = current.addingTimeInterval(60)

        #expect(try detector.activeTasks().isEmpty)
    }

    @Test
    func expiresCachedActivityAfterRescanWithUnchangedSignature() throws {
        let root = makeDoubaoTempRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        var current = Date(timeIntervalSince1970: 1_900_000_000)
        let activityURL = try writeDoubaoChatActivity(
            in: root,
            taskCreatedAt: current.addingTimeInterval(-1)
        )
        try FileManager.default.setAttributes(
            [.modificationDate: current.addingTimeInterval(-1)],
            ofItemAtPath: activityURL.path
        )
        let detector = DoubaoSessionActivityDetector(
            dataRoots: [root],
            recencyThreshold: 60,
            scanInterval: 0,
            isDoubaoRunning: { true },
            now: { current }
        )

        #expect(try detector.activeTasks().count == 1)

        current = current.addingTimeInterval(60)

        #expect(try detector.activeTasks().isEmpty)
    }

    @Test
    func defaultRecencyThresholdExpiresActivityAfterNinetySeconds() throws {
        let root = makeDoubaoTempRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        var current = Date(timeIntervalSince1970: 1_900_000_000)
        let activityURL = try writeDoubaoChatActivity(
            in: root,
            taskCreatedAt: current.addingTimeInterval(-1)
        )
        try FileManager.default.setAttributes(
            [.modificationDate: current.addingTimeInterval(-89)],
            ofItemAtPath: activityURL.path
        )
        let detector = DoubaoSessionActivityDetector(
            dataRoots: [root],
            scanInterval: 120,
            isDoubaoRunning: { true },
            now: { current }
        )

        #expect(try detector.activeTasks().count == 1)

        current = current.addingTimeInterval(2)

        #expect(try detector.activeTasks().isEmpty)
    }
}

private func makeDoubaoTempRoot() -> URL {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("Zisla-doubao-\(UUID().uuidString)", isDirectory: true)
    try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

private func writeDoubaoAgentActivity(
    in root: URL,
    named: String = "trajectory.jsonl"
) throws -> URL {
    let directory = root.appendingPathComponent(
        "Default/.doubao/agent_mode/workspace/.sessions/test/agents/agent/system",
        isDirectory: true
    )
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let url = directory.appendingPathComponent(named)
    try Data().write(to: url)
    return url
}

private func writeDoubaoChatActivity(
    in root: URL,
    named: String = "000001.log",
    taskCreatedAt: Date = Date(),
    taskKind: String = "sync",
    includeTask: Bool = true
) throws -> URL {
    let directory = root.appendingPathComponent(
        "Default/IndexedDB/chrome_doubao-chat_0.indexeddb.leveldb",
        isDirectory: true
    )
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let url = directory.appendingPathComponent(named)
    var bytes = Array("chat activity".utf8)
    if includeTask {
        bytes.append(contentsOf: Array(" mainTaskDataMap {\"type\":\"\(taskKind)\",\"createTime".utf8))
        bytes.append(0x4e)
        let timestamp = taskCreatedAt.timeIntervalSince1970 * 1_000
        let bitPattern = timestamp.bitPattern
        for index in 0..<MemoryLayout<UInt64>.size {
            bytes.append(UInt8((bitPattern >> UInt64(index * 8)) & 0xff))
        }
        bytes.append(contentsOf: Array(",\"requestQ\":{}}".utf8))
    }
    try Data(bytes).write(to: url)
    return url
}
