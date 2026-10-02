import Foundation
import Combine
import Testing
import ZislaCore
import ZislaKit

@testable import Zisla

struct AIResultSweepIntegrationTests {
    @Test @MainActor
    func codexToolErrorsFlowThroughMonitorOnceAndRearmAfterRecovery() throws {
        for payloadType in ["function_call_output", "custom_tool_call_output"] {
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            defer { try? FileManager.default.removeItem(at: directory) }
            let sessions = directory.appendingPathComponent("sessions")
            try FileManager.default.createDirectory(at: sessions, withIntermediateDirectories: true)
            let rollout = sessions.appendingPathComponent("rollout-tool-error.jsonl")
            let now = Date(timeIntervalSince1970: 1_800_000_100)
            let startedAt = now.addingTimeInterval(-10)
            let started = "{\"timestamp\":\"\(startedAt.ISO8601Format())\",\"type\":\"event_msg\",\"payload\":{\"type\":\"task_started\",\"turn_id\":\"tool-turn\"}}\n"
            try Data(started.utf8).write(to: rollout)
            try FileManager.default.setAttributes([.modificationDate: now], ofItemAtPath: rollout.path)
            func appendOutput(exitCode: Int, sequence: Int) throws {
                let timestamp = now.addingTimeInterval(Double(sequence))
                let record: [String: Any] = [
                    "timestamp": timestamp.ISO8601Format(),
                    "type": "response_item",
                    "payload": [
                        "type": payloadType, "call_id": "call-\(sequence)",
                        "internal_chat_message_metadata_passthrough": ["turn_id": "tool-turn"],
                        "output": [["type": "input_text", "text": "{\"exit_code\":\(exitCode),\"output\":\"fixture\"}"]],
                    ],
                ]
                let handle = try FileHandle(forWritingTo: rollout)
                defer { try? handle.close() }
                try handle.seekToEnd()
                try handle.write(contentsOf: JSONSerialization.data(withJSONObject: record) + Data([0x0A]))
                try FileManager.default.setAttributes([.modificationDate: timestamp], ofItemAtPath: rollout.path)
            }
            let detector = CodexSessionActivityDetector(
                sessionsDirectory: sessions, processIdentifiersForOpenFiles: { _ in [:] }, now: { now }
            )
            let monitor = AIStateMonitor(
                directoryURL: directory.appendingPathComponent("state"), activityDetectors: [detector], now: { now }
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
            monitor.reload(includeUsageSamples: false)
            #expect(monitor.state.tasks.first?.status == .running)
            #expect(sweep.current == nil)

            try appendOutput(exitCode: 1, sequence: 1)
            monitor.reload(includeUsageSamples: false)
            let errorTask = try #require(monitor.state.tasks.first)
            #expect(errorTask.status == .error)
            #expect(errorTask.failureReason == AppLocalization.text("工具执行失败"))
            let first = try #require(sweep.current, "工具失败已经到达监视器，必须触发红色扫光")
            #expect(first.status == .error)
            monitor.reload(includeUsageSamples: false)
            #expect(sweep.current?.id == first.id)
            sweep.finish(id: first.id)
            #expect(sweep.current == nil, "重复错误快照不能排入下一次扫光")
            monitor.reload(includeUsageSamples: false)
            #expect(sweep.current == nil)

            let historicalSweep = AIResultSweepController()
            defer { historicalSweep.cancel() }
            historicalSweep.receive(previous: nil, task: errorTask, observedSince: now, settings: .default)
            #expect(historicalSweep.current == nil, "观察开始前的错误不能补播")

            try appendOutput(exitCode: 0, sequence: 2)
            monitor.reload(includeUsageSamples: false)
            #expect(monitor.state.tasks.first?.status == .running)
            #expect(monitor.state.tasks.first?.failureReason == nil)
            #expect(sweep.current == nil)
            try appendOutput(exitCode: 1, sequence: 3)
            monitor.reload(includeUsageSamples: false)
            let second = try #require(sweep.current)
            #expect(second.status == .error)
            #expect(second.id != first.id)
            sweep.finish(id: second.id)
            #expect(sweep.current == nil)
        }
    }

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
            let playback = try #require(sweep.current)

            try FileManager.default.removeItem(at: rollout)
            monitor.reload(includeUsageSamples: false)
            #expect(monitor.state.tasks.isEmpty)
            let retained = sweep.presentationNotices(from: [])
            #expect(retained.count == 1, "客户端日志和活动状态消失后，结果动画仍须持有图标与计数")
            #expect(retained.first?.id == "ai-active-codex-\(running.id)")
            #expect(retained.first?.kind == status.noticeKind)
            sweep.finish(id: playback.id)
            #expect(sweep.presentationNotices(from: []).isEmpty)
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
