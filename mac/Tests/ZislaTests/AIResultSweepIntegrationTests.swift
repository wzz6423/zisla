import Foundation
import Combine
import Testing
import ZislaCore
import ZislaKit

@testable import Zisla

struct AIResultSweepIntegrationTests {
    @Test @MainActor
    func shortTurnsCompleteBetweenScansWithoutReplayingHistoryOrInventingSuccess() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let rollout = directory.appendingPathComponent("rollout-short.jsonl")
        let clock = TestClock()
        let startedAt = clock.now
        func line(_ type: String, turn: String, at date: Date) -> String {
            "{\"timestamp\":\"\(date.ISO8601Format())\",\"type\":\"event_msg\",\"payload\":{\"type\":\"\(type)\",\"turn_id\":\"\(turn)\"}}\n"
        }
        let history = line("task_started", turn: "old", at: startedAt.addingTimeInterval(-100))
            + line("task_complete", turn: "old", at: startedAt.addingTimeInterval(-90))
        try Data(history.utf8).write(to: rollout)
        let detector = CodexSessionActivityDetector(
            sessionsDirectory: directory, processIdentifiersForOpenFiles: { _ in [:] }, now: { clock.now }
        )
        #expect(try detector.taskUpdates().isEmpty)
        clock.advance(by: 10)
        let short = line("task_started", turn: "short", at: startedAt.addingTimeInterval(1))
            + line("task_complete", turn: "short", at: startedAt.addingTimeInterval(2))
        try Data((history + short).utf8).write(to: rollout)
        let result = try #require(detector.taskUpdates().first)
        let sweep = AIResultSweepController()
        defer { sweep.cancel() }
        sweep.receive(previous: nil, task: result, observedSince: startedAt, settings: .default)
        #expect(sweep.current?.status == .succeeded)
        sweep.cancel()
        sweep.receive(previous: nil, task: result, observedSince: clock.now, settings: .default)
        #expect(sweep.current == nil)

        clock.advance(by: 10)
        try Data((history + short).utf8).write(to: rollout, options: .atomic)
        #expect(try detector.taskUpdates().isEmpty)
        let missing = line("task_started", turn: "missing", at: clock.now)
        try Data(missing.utf8).write(to: rollout)
        #expect(try detector.taskUpdates().first?.status == .running)
        try FileManager.default.removeItem(at: rollout)
        #expect(try detector.taskUpdates().isEmpty, "日志消失不是任务成功")
    }

    @Test @MainActor
    func watchedCompletionTriggersWithoutWaitingForThePeriodicScanAndStopsCleanly() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let sessions = directory.appendingPathComponent("sessions")
        try FileManager.default.createDirectory(at: sessions, withIntermediateDirectories: true)
        let rollout = sessions.appendingPathComponent("rollout-watch.jsonl")
        let now = Date()
        func line(_ type: String, turn: String = "watched-turn") -> Data {
            Data("{\"timestamp\":\"\(now.ISO8601Format())\",\"type\":\"event_msg\",\"payload\":{\"type\":\"\(type)\",\"turn_id\":\"\(turn)\"}}\n".utf8)
        }
        try line("task_started").write(to: rollout)
        let detector = CodexSessionActivityDetector(
            sessionsDirectory: sessions, processIdentifiersForOpenFiles: { _ in [:] }, now: { now }
        )
        let monitor = AIStateMonitor(
            directoryURL: directory.appendingPathComponent("state"), activityDetectors: [detector],
            detectorRefreshInterval: 3600, now: { now }
        )
        let sweep = AIResultSweepController()
        var statuses: [String: AIProgressStatus] = [:]
        let subscription = monitor.$state.sink { state in
            for task in state.tasks {
                sweep.receive(previous: statuses[task.id], task: task, observedSince: now, settings: .default)
                statuses[task.id] = task.status
            }
        }
        defer { subscription.cancel(); sweep.cancel(); monitor.stop() }
        monitor.start()
        #expect(await waitUntil { monitor.state.tasks.contains { $0.status == .running } })
        let handle = try FileHandle(forWritingTo: rollout)
        defer { try? handle.close() }
        try handle.seekToEnd()
        try handle.write(contentsOf: line("task_complete"))
        #expect(await waitUntil { sweep.current?.status == .succeeded })
        let first = try #require(sweep.current)
        sweep.finish(id: first.id)
        try handle.write(contentsOf: line("task_complete"))
        monitor.refresh()
        #expect(await waitUntil { monitor.state.tasks.isEmpty })
        #expect(sweep.current == nil)

        try line("task_started", turn: "replacement").write(to: rollout, options: .atomic)
        #expect(await waitUntil { monitor.state.tasks.contains { $0.status == .running } })
        let replacement = try FileHandle(forWritingTo: rollout)
        defer { try? replacement.close() }
        try replacement.seekToEnd()
        try replacement.write(contentsOf: line("task_complete", turn: "replacement"))
        #expect(await waitUntil { sweep.current?.status == .succeeded })
        #expect(sweep.current?.id != first.id)
        sweep.cancel()
        let stoppedState = monitor.state
        monitor.stop()
        try replacement.write(contentsOf: line("task_started", turn: "after-stop"))
        try await Task.sleep(for: .milliseconds(400))
        #expect(monitor.state == stoppedState)
        #expect(sweep.current == nil)
    }

    @MainActor
    private func waitUntil(_ predicate: () -> Bool) async -> Bool {
        let deadline = ContinuousClock.now.advanced(by: .seconds(5))
        while ContinuousClock.now < deadline {
            if predicate() { return true }
            try? await Task.sleep(for: .milliseconds(10))
        }
        return predicate()
    }

    @Test @MainActor
    func codexCompletionFlowsFromRolloutThroughMonitorToSweep() throws {
        for (event, status): (String, AIProgressStatus) in [("task_complete", .succeeded), ("turn_aborted", .failed)] {
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            defer { try? FileManager.default.removeItem(at: directory) }
            let sessions = directory.appendingPathComponent("sessions")
            try FileManager.default.createDirectory(at: sessions, withIntermediateDirectories: true)
            let rollout = sessions.appendingPathComponent("rollout-test.jsonl")
            let now = Date()
            func line(_ type: String) -> Data {
                Data("{\"timestamp\":\"\(now.ISO8601Format())\",\"type\":\"event_msg\",\"payload\":{\"type\":\"\(type)\",\"turn_id\":\"test-turn\"}}\n".utf8)
            }
            try line("task_started").write(to: rollout)
            let detector = CodexSessionActivityDetector(
                sessionsDirectory: sessions,
                processIdentifiersForOpenFiles: { _ in [:] },
                now: { now }
            )
            let monitor = AIStateMonitor(
                directoryURL: directory.appendingPathComponent("state"),
                activityDetectors: [detector],
                now: { now }
            )
            let sweep = AIResultSweepController()
            defer { sweep.cancel(); monitor.stop() }
            monitor.reload(includeUsageSamples: false)
            let running = try #require(monitor.state.tasks.first)
            #expect(running.status == .running)

            let handle = try FileHandle(forWritingTo: rollout)
            try handle.seekToEnd()
            try handle.write(contentsOf: line(event))
            try handle.close()
            monitor.reload(includeUsageSamples: false)
            for task in monitor.state.tasks {
                sweep.receive(previous: task.id == running.id ? running.status : nil, task: task, observedSince: now, settings: .default)
            }
            #expect(sweep.current?.status == status, "明确的 Codex 结束事件必须触发扫光")
            #expect(!monitor.state.tasks.contains { $0.status.isActive })
        }
    }
}

private final class TestClock: @unchecked Sendable {
    private let lock = NSLock()
    private var value = Date()

    var now: Date { lock.withLock { value } }

    func advance(by interval: TimeInterval) {
        lock.withLock { value.addTimeInterval(interval) }
    }
}
