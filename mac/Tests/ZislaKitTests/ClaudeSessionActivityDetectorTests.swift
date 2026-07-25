import Foundation
import Testing
@testable import ZislaCore
@testable import ZislaKit

struct ClaudeSessionActivityDetectorTests {
    @Test
    func testDetectsRunningAssistantToolUseTurn() throws {
        let root = makeTempRoot("claude-running")
        defer { try? FileManager.default.removeItem(at: root) }

        try writeJSONL(
            under: root,
            relativePath: "proj/session-a.jsonl",
            lines: [
                claudeUser(timestamp: "2026-07-19T01:00:00.000Z", sessionId: "sess-a", text: "hi"),
                claudeAssistant(
                    timestamp: "2026-07-19T01:00:01.000Z",
                    sessionId: "sess-a",
                    stopReason: "tool_use",
                    model: "claude-sonnet-4",
                    toolUses: [("tool-1", "Bash")]
                ),
            ],
            modifiedAt: Date(timeIntervalSince1970: 1_900_000_100)
        )

        let tasks = try ClaudeSessionActivityDetector(projectsDirectory: root).activeTasks()
        #expect(tasks.count == 1)
        let task = try #require(tasks.first)
        #expect(task.id == ClaudeSessionActivityDetector.taskID(forSessionID: "sess-a"))
        #expect(task.provider == .claude)
        #expect(task.title == "Claude")
        #expect(task.status == .running)
        #expect(task.detail == "claude-sonnet-4")
        #expect(task.progress == nil)
    }

    @Test
    func testAskUserQuestionBlocksUntilMatchingToolResult() throws {
        let root = makeTempRoot("claude-blocked")
        defer { try? FileManager.default.removeItem(at: root) }
        let relative = "proj/session-b.jsonl"

        try writeJSONL(
            under: root,
            relativePath: relative,
            lines: [
                claudeUser(timestamp: "2026-07-19T01:00:00.000Z", sessionId: "sess-b", text: "q"),
                claudeAssistant(
                    timestamp: "2026-07-19T01:00:01.000Z",
                    sessionId: "sess-b",
                    stopReason: "tool_use",
                    model: "claude-opus",
                    toolUses: [("ask-1", "AskUserQuestion")]
                ),
            ],
            modifiedAt: Date(timeIntervalSince1970: 1_900_000_110)
        )

        let detector = ClaudeSessionActivityDetector(projectsDirectory: root)
        #expect(try detector.activeTasks().first?.status == .blocked)

        try appendJSONLLine(
            claudeUserToolResult(
                timestamp: "2026-07-19T01:00:02.000Z",
                sessionId: "sess-b",
                toolUseId: "ask-1",
                isError: false
            ),
            to: root.appendingPathComponent(relative)
        )
        #expect(try detector.activeTasks().first?.status == .running)
    }

    @Test
    func testToolResultErrorThenRecovery() throws {
        let root = makeTempRoot("claude-error")
        defer { try? FileManager.default.removeItem(at: root) }
        let relative = "proj/session-e.jsonl"

        try writeJSONL(
            under: root,
            relativePath: relative,
            lines: [
                claudeUser(timestamp: "2026-07-19T01:00:00.000Z", sessionId: "sess-e", text: "go"),
                claudeAssistant(
                    timestamp: "2026-07-19T01:00:01.000Z",
                    sessionId: "sess-e",
                    stopReason: "tool_use",
                    model: "claude-sonnet-4",
                    toolUses: [("t1", "Bash")]
                ),
                claudeUserToolResult(
                    timestamp: "2026-07-19T01:00:02.000Z",
                    sessionId: "sess-e",
                    toolUseId: "t1",
                    isError: true
                ),
            ],
            modifiedAt: Date(timeIntervalSince1970: 1_900_000_120)
        )

        let detector = ClaudeSessionActivityDetector(projectsDirectory: root)
        #expect(try detector.activeTasks().first?.status == .error)

        try appendJSONLLine(
            claudeUserToolResult(
                timestamp: "2026-07-19T01:00:03.000Z",
                sessionId: "sess-e",
                toolUseId: "t2",
                isError: false
            ),
            to: root.appendingPathComponent(relative)
        )
        #expect(try detector.activeTasks().first?.status == .running)
    }

    @Test
    func testEndTurnCompletesAndIdleYieldsEmpty() throws {
        let root = makeTempRoot("claude-idle")
        defer { try? FileManager.default.removeItem(at: root) }

        try writeJSONL(
            under: root,
            relativePath: "proj/session-done.jsonl",
            lines: [
                claudeUser(timestamp: "2026-07-19T01:00:00.000Z", sessionId: "sess-done", text: "hi"),
                claudeAssistant(
                    timestamp: "2026-07-19T01:00:01.000Z",
                    sessionId: "sess-done",
                    stopReason: "end_turn",
                    model: "claude-sonnet-4",
                    toolUses: []
                ),
            ],
            modifiedAt: Date(timeIntervalSince1970: 1_900_000_130)
        )

        let tasks = try ClaudeSessionActivityDetector(projectsDirectory: root).activeTasks()
        #expect(tasks.isEmpty)
    }

    @Test
    func testIgnoresCorruptLinesPartialTailAndMissingDirectory() throws {
        let root = makeTempRoot("claude-noisy")
        defer { try? FileManager.default.removeItem(at: root) }

        let url = root.appendingPathComponent("proj/noisy.jsonl")
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let body = [
            "{not-json",
            claudeUser(timestamp: "2026-07-19T01:00:00.000Z", sessionId: "sess-n", text: "x"),
            claudeAssistant(
                timestamp: "2026-07-19T01:00:01.000Z",
                sessionId: "sess-n",
                stopReason: "tool_use",
                model: "m",
                toolUses: [("t", "Read")]
            ),
            #"{"type":"assistant","timestamp":"2026-07-19T01:00:02.000Z""#,
        ].joined(separator: "\n")
        try Data(body.utf8).write(to: url)
        try FileManager.default.setAttributes(
            [.modificationDate: Date(timeIntervalSince1970: 1_900_000_140)],
            ofItemAtPath: url.path
        )

        let tasks = try ClaudeSessionActivityDetector(projectsDirectory: root).activeTasks()
        #expect(tasks.count == 1)
        #expect(tasks[0].status == .running)

        let missing = FileManager.default.temporaryDirectory
            .appendingPathComponent("Zisla-claude-missing-\(UUID().uuidString)", isDirectory: true)
        #expect(try ClaudeSessionActivityDetector(projectsDirectory: missing).activeTasks().isEmpty)
    }

    @Test
    func testVSCodeEntrypointStillDetected() throws {
        let root = makeTempRoot("claude-vscode")
        defer { try? FileManager.default.removeItem(at: root) }

        try writeJSONL(
            under: root,
            relativePath: "vscode-proj/session-vs.jsonl",
            lines: [
                """
                {"type":"user","timestamp":"2026-07-19T01:00:00.000Z","sessionId":"sess-vs","entrypoint":"claude-vscode","message":{"role":"user","content":[{"type":"text","text":"hi"}]}}
                """,
                claudeAssistant(
                    timestamp: "2026-07-19T01:00:01.000Z",
                    sessionId: "sess-vs",
                    stopReason: "tool_use",
                    model: "claude-sonnet-4",
                    toolUses: [("t", "Bash")]
                ),
            ],
            modifiedAt: Date(timeIntervalSince1970: 1_900_000_150)
        )

        let task = try #require(ClaudeSessionActivityDetector(projectsDirectory: root).activeTasks().first)
        #expect(task.provider == .claude)
        #expect(task.status == .running)
    }

    @Test
    func testOrdinaryToolUseIsNotBlocked() throws {
        let root = makeTempRoot("claude-tool-not-blocked")
        defer { try? FileManager.default.removeItem(at: root) }

        try writeJSONL(
            under: root,
            relativePath: "proj/session-t.jsonl",
            lines: [
                claudeUser(timestamp: "2026-07-19T01:00:00.000Z", sessionId: "sess-t", text: "run"),
                claudeAssistant(
                    timestamp: "2026-07-19T01:00:01.000Z",
                    sessionId: "sess-t",
                    stopReason: "tool_use",
                    model: "m",
                    toolUses: [("t1", "Bash"), ("t2", "Edit")]
                ),
            ],
            modifiedAt: Date(timeIntervalSince1970: 1_900_000_160)
        )

        #expect(try ClaudeSessionActivityDetector(projectsDirectory: root).activeTasks().first?.status == .running)
    }

    @Test
    func testAPIErrorMessageIsDetectedAsError() throws {
        let root = makeTempRoot("claude-api-error")
        defer { try? FileManager.default.removeItem(at: root) }

        try writeJSONL(
            under: root,
            relativePath: "project/error.jsonl",
            lines: [
                claudeUser(
                    timestamp: "2026-07-19T01:00:00.000Z",
                    sessionId: "sess-api",
                    text: "hello"
                ),
                #"{"type":"assistant","timestamp":"2026-07-19T01:00:01.000Z","sessionId":"sess-api","isApiErrorMessage":true,"apiErrorStatus":502,"error":"upstream failed","message":{"role":"assistant","model":"claude-sonnet-4","stop_reason":"stop_sequence","content":[]}}"#,
            ],
            modifiedAt: Date(timeIntervalSince1970: 1_910_000_200)
        )

        #expect(try ClaudeSessionActivityDetector(
            projectsDirectory: root
        ).activeTasks().first?.status == .error)
    }

    @Test
    func testColdStartIgnoresActivityOutsideTheBoundedTail() throws {
        let root = makeTempRoot("claude-bounded")
        defer { try? FileManager.default.removeItem(at: root) }
        let filler = (0..<80).map { index in
            #"{"type":"progress","timestamp":"2026-07-19T01:00:01.000Z","index":\#(index)}"#
        }
        try writeJSONL(
            under: root,
            relativePath: "project/bounded.jsonl",
            lines: [
                claudeUser(
                    timestamp: "2026-07-19T01:00:00.000Z",
                    sessionId: "sess-outside-tail",
                    text: "start"
                ),
            ] + filler,
            modifiedAt: Date(timeIntervalSince1970: 1_910_000_300)
        )

        let tasks = try ClaudeSessionActivityDetector(
            projectsDirectory: root,
            initialTailBytes: 256
        ).activeTasks()

        #expect(tasks.isEmpty)
    }
}

// MARK: - Fixtures

private func makeTempRoot(_ label: String) -> URL {
    FileManager.default.temporaryDirectory
        .appendingPathComponent("Zisla-\(label)-\(UUID().uuidString)", isDirectory: true)
}

private func writeJSONL(
    under root: URL,
    relativePath: String,
    lines: [String],
    modifiedAt: Date
) throws {
    let url = root.appendingPathComponent(relativePath)
    try FileManager.default.createDirectory(
        at: url.deletingLastPathComponent(),
        withIntermediateDirectories: true
    )
    try Data((lines.joined(separator: "\n") + "\n").utf8).write(to: url)
    try FileManager.default.setAttributes([.modificationDate: modifiedAt], ofItemAtPath: url.path)
}

private func appendJSONLLine(_ line: String, to url: URL) throws {
    let handle = try FileHandle(forWritingTo: url)
    defer { try? handle.close() }
    try handle.seekToEnd()
    try handle.write(contentsOf: Data((line + "\n").utf8))
}

private func claudeUser(timestamp: String, sessionId: String, text: String) -> String {
    """
    {"type":"user","timestamp":"\(timestamp)","sessionId":"\(sessionId)","message":{"role":"user","content":[{"type":"text","text":"\(text)"}]}}
    """
}

private func claudeUserToolResult(
    timestamp: String,
    sessionId: String,
    toolUseId: String,
    isError: Bool
) -> String {
    """
    {"type":"user","timestamp":"\(timestamp)","sessionId":"\(sessionId)","message":{"role":"user","content":[{"type":"tool_result","tool_use_id":"\(toolUseId)","is_error":\(isError),"content":"ok"}]}}
    """
}

private func claudeAssistant(
    timestamp: String,
    sessionId: String,
    stopReason: String,
    model: String,
    toolUses: [(String, String)]
) -> String {
    let content: String
    if toolUses.isEmpty {
        content = #"[{"type":"text","text":"done"}]"#
    } else {
        let parts = toolUses.map { id, name in
            #"{"type":"tool_use","id":"\#(id)","name":"\#(name)","input":{}}"#
        }.joined(separator: ",")
        content = "[\(parts)]"
    }
    return """
    {"type":"assistant","timestamp":"\(timestamp)","sessionId":"\(sessionId)","message":{"role":"assistant","model":"\(model)","stop_reason":"\(stopReason)","content":\(content)}}
    """
}
