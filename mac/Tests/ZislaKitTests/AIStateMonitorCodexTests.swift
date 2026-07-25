import Foundation
import Testing

@testable import ZislaCore
@testable import ZislaKit

struct AIStateMonitorCodexTests {
    @Test @MainActor
    func reloadMergesAutomaticCodexAndPersistedTasks() throws {
        let stateDirectory = temporaryDirectory(named: "state")
        let sessionsDirectory = temporaryDirectory(named: "sessions")
        defer {
            try? FileManager.default.removeItem(at: stateDirectory)
            try? FileManager.default.removeItem(at: sessionsDirectory)
        }

        let repository = AIStateRepository(directoryURL: stateDirectory)
        try repository.upsert(AIProgressTask(
            id: "claude-manual",
            provider: .claude,
            title: "手工任务",
            progress: 0.4,
            updatedAt: Date(timeIntervalSince1970: 100)
        ))
        try writeCodexEvents(
            to: sessionsDirectory,
            lines: [codexEvent("task_started", turnID: "turn-live")]
        )

        let monitor = AIStateMonitor(
            directoryURL: stateDirectory,
            codexSessionsDirectory: sessionsDirectory,
            activeTaskTTL: .greatestFiniteMagnitude
        )
        monitor.reload()

        #expect(Set(monitor.state.tasks.map(\.id)) == [
            "claude-manual",
            CodexSessionActivityDetector.taskID(forTurnID: "turn-live"),
        ])
    }

    @Test @MainActor
    func completedCodexTurnDisappearsWithoutRemovingPersistedTask() throws {
        let stateDirectory = temporaryDirectory(named: "state")
        let sessionsDirectory = temporaryDirectory(named: "sessions")
        defer {
            try? FileManager.default.removeItem(at: stateDirectory)
            try? FileManager.default.removeItem(at: sessionsDirectory)
        }

        let repository = AIStateRepository(directoryURL: stateDirectory)
        try repository.upsert(AIProgressTask(
            id: "grok-manual",
            provider: .grok,
            title: "手工任务",
            progress: nil,
            updatedAt: Date(timeIntervalSince1970: 100)
        ))
        let rollout = try writeCodexEvents(
            to: sessionsDirectory,
            lines: [codexEvent("task_started", turnID: "turn-finished")]
        )

        let monitor = AIStateMonitor(
            directoryURL: stateDirectory,
            codexSessionsDirectory: sessionsDirectory,
            activeTaskTTL: .greatestFiniteMagnitude
        )
        monitor.reload()
        #expect(monitor.state.tasks.count == 2)

        let completion = codexEvent("task_complete", turnID: "turn-finished") + "\n"
        let handle = try FileHandle(forWritingTo: rollout)
        try handle.seekToEnd()
        try handle.write(contentsOf: Data(completion.utf8))
        try handle.close()
        monitor.reload()

        #expect(monitor.state.tasks.map(\.id) == ["grok-manual"])
    }

    @Test @MainActor
    func staleRunningTaskIsIgnoredAfterReload() throws {
        let stateDirectory = temporaryDirectory(named: "stale-state")
        defer { try? FileManager.default.removeItem(at: stateDirectory) }

        let repository = AIStateRepository(directoryURL: stateDirectory)
        try repository.upsert(AIProgressTask(
            id: "old-task",
            provider: .claude,
            title: "旧任务",
            progress: 0.4,
            updatedAt: Date(timeIntervalSinceNow: -AIStateMonitor.defaultActiveTaskTTL - 1)
        ))

        let monitor = AIStateMonitor(
            directoryURL: stateDirectory,
            codexSessionsDirectory: nil
        )
        monitor.reload()

        #expect(monitor.state.tasks.isEmpty)
    }

    @Test @MainActor
    func staleBlockedAndErrorTasksAreAlsoIgnoredAfterReload() throws {
        let stateDirectory = temporaryDirectory(named: "stale-attention-state")
        defer { try? FileManager.default.removeItem(at: stateDirectory) }
        let repository = AIStateRepository(directoryURL: stateDirectory)
        let staleDate = Date(timeIntervalSinceNow: -AIStateMonitor.defaultActiveTaskTTL - 1)
        for status in [AIProgressStatus.blocked, .error] {
            try repository.upsert(AIProgressTask(
                id: status.rawValue,
                provider: .codex,
                title: status.rawValue,
                progress: nil,
                status: status,
                updatedAt: staleDate
            ))
        }

        let monitor = AIStateMonitor(
            directoryURL: stateDirectory,
            codexSessionsDirectory: nil
        )
        monitor.reload()

        #expect(monitor.state.tasks.isEmpty)
    }
}

private func temporaryDirectory(named component: String) -> URL {
    FileManager.default.temporaryDirectory
        .appendingPathComponent("Zisla-\(component)-\(UUID().uuidString)", isDirectory: true)
}

@discardableResult
private func writeCodexEvents(to root: URL, lines: [String]) throws -> URL {
    let url = root.appendingPathComponent("2026/07/19/rollout-test.jsonl")
    try FileManager.default.createDirectory(
        at: url.deletingLastPathComponent(),
        withIntermediateDirectories: true
    )
    try Data((lines.joined(separator: "\n") + "\n").utf8).write(to: url)
    return url
}

private func codexEvent(_ type: String, turnID: String) -> String {
    """
    {"timestamp":"2026-07-19T01:00:00.000Z","type":"event_msg","payload":{"type":"\(type)","turn_id":"\(turnID)"}}
    """
}
