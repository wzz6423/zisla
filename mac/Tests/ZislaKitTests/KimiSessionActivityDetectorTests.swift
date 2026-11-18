import Foundation
import Testing
@testable import ZislaCore
@testable import ZislaKit

struct KimiSessionActivityDetectorTests {
    @Test
    func testDetectsRunningVSCodeSharedSessionWithoutJumpURL() throws {
        let home = makeKimiTempHome("running")
        defer { try? FileManager.default.removeItem(at: home) }
        try writeKimiSession(
            under: home,
            sessionID: "kimi-vscode-1",
            title: "Implement monitor",
            lines: [
                #"{"type":"turn.prompt","input":[{"type":"text","text":"implement"}],"origin":{"kind":"user"},"time":1910000000000}"#,
                #"{"type":"llm.request","model":"kimi-k2.5","time":1910000001000}"#,
                #"{"type":"context.append_loop_event","event":{"type":"step.begin"},"time":1910000002000}"#,
            ]
        )

        let task = try #require(KimiSessionActivityDetector(homeDirectory: home).activeTasks().first)
        #expect(task.id == KimiSessionActivityDetector.taskID(forSessionID: "kimi-vscode-1"))
        #expect(task.provider == .kimi)
        #expect(task.title == "Implement monitor")
        #expect(task.detail == "kimi-k2.5")
        #expect(task.status == .running)
        #expect(task.sessionURL == nil)
    }

    @Test
    func testTerminalStepAndCancellationClearTask() throws {
        let home = makeKimiTempHome("terminal")
        defer { try? FileManager.default.removeItem(at: home) }
        let wireURL = try writeKimiSession(
            under: home,
            sessionID: "kimi-terminal",
            lines: [
                #"{"type":"turn.prompt","time":1910000010000}"#,
                #"{"type":"context.append_loop_event","event":{"type":"step.end","finishReason":"end_turn"},"time":1910000011000}"#,
            ]
        )
        let detector = KimiSessionActivityDetector(homeDirectory: home)
        #expect(try detector.activeTasks().isEmpty)

        try appendKimiLine(#"{"type":"turn.prompt","time":1910000012000}"#, to: wireURL)
        #expect(try detector.activeTasks().count == 1)
        try appendKimiLine(#"{"type":"turn.cancel","time":1910000013000}"#, to: wireURL)
        #expect(try detector.activeTasks().isEmpty)
    }

    @Test(arguments: [
        (#"{"type":"step.end","finishReason":"tool_use"}"#, AIProgressStatus.running),
        (#"{"type":"step.end","finishReason":"paused"}"#, AIProgressStatus.blocked),
        (#"{"type":"turn.interrupted"}"#, AIProgressStatus.error),
    ])
    func testCancellationClearsActivityAndAllowsTheNextTurn(loopEvent: String, status: AIProgressStatus) throws {
        let home = makeKimiTempHome("cancel-state")
        defer { try? FileManager.default.removeItem(at: home) }
        let wireURL = try writeKimiSession(
            under: home,
            sessionID: "kimi-cancel-state",
            lines: [
                #"{"type":"turn.prompt","time":1910000040000}"#,
                "{\"type\":\"context.append_loop_event\",\"event\":\(loopEvent),\"time\":1910000041000}",
            ]
        )
        let detector = KimiSessionActivityDetector(homeDirectory: home)
        #expect(try detector.activeTasks().first?.status == status)

        try appendKimiLine(#"{"type":"turn.cancel","time":1910000042000}"#, to: wireURL)
        #expect(try detector.activeTasks().isEmpty, "Cancellation must clear the previous activity state")
        #expect(try detector.activeTasks().isEmpty, "Cached cancellation must not revive a task")
        #expect(try KimiSessionActivityDetector(homeDirectory: home).activeTasks().isEmpty,
            "Replaying a cancelled transcript must remain idle")

        try appendKimiLine(#"{"type":"turn.prompt","time":1910000043000}"#, to: wireURL)
        let next = try #require(detector.activeTasks().first)
        #expect(next.id == KimiSessionActivityDetector.taskID(forSessionID: "kimi-cancel-state"))
        #expect(next.status == .running)
        #expect(next.startedAt == Date(timeIntervalSince1970: 1910000043))
    }

    @Test
    func testPartialCancellationClearsErrorOnlyAfterTheRecordCompletes() throws {
        let home = makeKimiTempHome("partial-cancel")
        defer { try? FileManager.default.removeItem(at: home) }
        let wireURL = try writeKimiSession(
            under: home,
            sessionID: "kimi-partial-cancel",
            lines: [
                #"{"type":"turn.prompt","time":1910000050000}"#,
                #"{"type":"context.append_loop_event","event":{"type":"turn.interrupted"},"time":1910000051000}"#,
            ]
        )
        let detector = KimiSessionActivityDetector(homeDirectory: home)
        #expect(try detector.activeTasks().first?.status == .error)
        let handle = try FileHandle(forWritingTo: wireURL)
        defer { try? handle.close() }
        try handle.seekToEnd()
        try handle.write(contentsOf: Data(#"{"type":"turn.cancel","time":1910000052000"#.utf8))
        #expect(try detector.activeTasks().first?.status == .error,
            "An incomplete cancellation must preserve the last readable activity")
        try handle.write(contentsOf: Data("}".utf8))
        #expect(try detector.activeTasks().first?.status == .error,
            "A cancellation without a newline must preserve the last readable activity")
        try handle.write(contentsOf: Data("\n".utf8))
        #expect(try detector.activeTasks().isEmpty, "Completing the cancellation must clear the error")
    }

    @Test
    func testCancellationDoesNotEndAnotherSession() throws {
        let home = makeKimiTempHome("cancel-isolation")
        defer { try? FileManager.default.removeItem(at: home) }
        let wireURL = try writeKimiSession(
            under: home,
            sessionID: "kimi-cancelled",
            lines: [
                #"{"type":"turn.prompt","time":1910000060000}"#,
                #"{"type":"context.append_loop_event","event":{"type":"turn.interrupted"},"time":1910000061000}"#,
            ]
        )
        try writeKimiSession(
            under: home,
            sessionID: "kimi-other",
            lines: [#"{"type":"turn.prompt","time":1910000060000}"#]
        )
        let detector = KimiSessionActivityDetector(homeDirectory: home)
        let before = try detector.activeTasks()
        let other = try #require(before.first { $0.id == KimiSessionActivityDetector.taskID(forSessionID: "kimi-other") })
        #expect(before.count == 2)
        try appendKimiLine(#"{"type":"turn.cancel","time":1910000062000}"#, to: wireURL)
        #expect(try detector.activeTasks() == [other], "Cancellation must only end its own session")
    }

    @Test
    func testPausedStepBlocksAndArchivedSessionIsIgnored() throws {
        let home = makeKimiTempHome("blocked")
        defer { try? FileManager.default.removeItem(at: home) }
        let stateURL = home.appendingPathComponent("sessions/workspace/kimi-blocked/state.json")
        try writeKimiSession(
            under: home,
            sessionID: "kimi-blocked",
            lines: [
                #"{"type":"turn.prompt","time":1910000020000}"#,
                #"{"type":"context.append_loop_event","event":{"type":"step.end","finishReason":"paused"},"time":1910000021000}"#,
            ]
        )

        let detector = KimiSessionActivityDetector(homeDirectory: home)
        #expect(try detector.activeTasks().first?.status == .blocked)
        try Data(#"{"archived":true}"#.utf8).write(to: stateURL)
        #expect(try detector.activeTasks().isEmpty)
    }

    @Test
    func testConfiguredHomeAndInvalidRecordsAreHandled() throws {
        let home = makeKimiTempHome("configured")
        defer { try? FileManager.default.removeItem(at: home) }
        #expect(KimiSessionActivityDetector.defaultHomeDirectory(
            environment: ["KIMI_CODE_HOME": home.path]
        ) == home)

        let wireURL = try writeKimiSession(
            under: home,
            sessionID: "kimi-noisy",
            lines: [
                "{bad",
                #"{"type":"turn.prompt","time":1910000030000}"#,
            ]
        )
        try appendKimiLine(#"{"type":"context.append_loop_event"#, to: wireURL)
        #expect(try KimiSessionActivityDetector(homeDirectory: home).activeTasks().count == 1)
    }
}

private func makeKimiTempHome(_ label: String) -> URL {
    FileManager.default.temporaryDirectory
        .appendingPathComponent("Zisla-kimi-\(label)-\(UUID().uuidString)", isDirectory: true)
}

@discardableResult
private func writeKimiSession(
    under home: URL,
    sessionID: String,
    title: String? = nil,
    lines: [String]
) throws -> URL {
    let sessionDirectory = home.appendingPathComponent("sessions/workspace/\(sessionID)")
    let agentsDirectory = sessionDirectory.appendingPathComponent("agents/main")
    try FileManager.default.createDirectory(at: agentsDirectory, withIntermediateDirectories: true)
    var state: [String: Any] = ["archived": false]
    if let title { state["title"] = title }
    let stateData = try JSONSerialization.data(withJSONObject: state)
    try stateData.write(to: sessionDirectory.appendingPathComponent("state.json"))

    let wireURL = agentsDirectory.appendingPathComponent("wire.jsonl")
    try Data((lines.joined(separator: "\n") + "\n").utf8).write(to: wireURL)
    return wireURL
}

private func appendKimiLine(_ line: String, to url: URL) throws {
    let handle = try FileHandle(forWritingTo: url)
    defer { try? handle.close() }
    try handle.seekToEnd()
    try handle.write(contentsOf: Data((line + "\n").utf8))
}
