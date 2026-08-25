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
                    isError: true,
                    content: "Permission denied"
                ),
            ],
            modifiedAt: Date(timeIntervalSince1970: 1_900_000_120)
        )

        let detector = ClaudeSessionActivityDetector(projectsDirectory: root)
        let failed = try #require(detector.activeTasks().first)
        #expect(failed.status == .error)
        #expect(failed.failureReason == "工具执行失败")
        #expect(failed.failureReason?.contains("Permission denied") == false)

        try appendJSONLLine(
            claudeUserToolResult(
                timestamp: "2026-07-19T01:00:03.000Z",
                sessionId: "sess-e",
                toolUseId: "t2",
                isError: false
            ),
            to: root.appendingPathComponent(relative)
        )
        let recovered = try #require(detector.activeTasks().first)
        #expect(recovered.status == .running)
        #expect(recovered.failureReason == nil)
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
        #expect(task.title == "Claude Code (VS Code)")
        #expect(task.status == .running)
        #expect(task.sessionURL?.absoluteString == "vscode://anthropic.claude-code/open?session=sess-vs")
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

        let task = try #require(ClaudeSessionActivityDetector(
            projectsDirectory: root
        ).activeTasks().first)
        #expect(task.status == .error)
        #expect(task.failureReason == "API 请求失败（HTTP 502）")
        #expect(task.failureReason?.contains("upstream failed") == false)
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

    @Test
    func testExtractsAITitleFromTranscript() throws {
        let root = makeTempRoot("claude-ai-title")
        defer { try? FileManager.default.removeItem(at: root) }

        try writeJSONL(
            under: root,
            relativePath: "proj/session-title.jsonl",
            lines: [
                #"{"type":"ai-title","sessionId":"sess-title","aiTitle":"Fix navigation bug"}"#,
                claudeUser(timestamp: "2026-07-19T01:00:00.000Z", sessionId: "sess-title", text: "fix nav"),
                claudeAssistant(
                    timestamp: "2026-07-19T01:00:01.000Z",
                    sessionId: "sess-title",
                    stopReason: "tool_use",
                    model: "claude-sonnet-4",
                    toolUses: [("t1", "Read")]
                ),
            ],
            modifiedAt: Date(timeIntervalSince1970: 1_900_000_170)
        )

        let task = try #require(ClaudeSessionActivityDetector(projectsDirectory: root).activeTasks().first)
        #expect(task.title == "Fix navigation bug")
    }

    @Test
    func testReadsPIDFromSessionFile() throws {
        let root = makeTempRoot("claude-pid")
        defer { try? FileManager.default.removeItem(at: root) }

        let sessionsDir = root.appendingPathComponent(".claude/sessions", isDirectory: true)
        try FileManager.default.createDirectory(at: sessionsDir, withIntermediateDirectories: true)
        let sessionFile = sessionsDir.appendingPathComponent("12345.json")
        try Data(#"{"pid":12345,"sessionId":"sess-pid"}"#.utf8).write(to: sessionFile)

        try writeJSONL(
            under: root.appendingPathComponent(".claude/projects", isDirectory: true),
            relativePath: "proj/session-pid.jsonl",
            lines: [
                claudeUser(timestamp: "2026-07-19T01:00:00.000Z", sessionId: "sess-pid", text: "hi"),
                claudeAssistant(
                    timestamp: "2026-07-19T01:00:01.000Z",
                    sessionId: "sess-pid",
                    stopReason: "tool_use",
                    model: "claude-opus",
                    toolUses: [("t1", "Bash")]
                ),
            ],
            modifiedAt: Date(timeIntervalSince1970: 1_900_000_180)
        )

        let detector = ClaudeSessionActivityDetector(
            projectsDirectory: root.appendingPathComponent(".claude/projects"),
            isProcessAlive: { $0 == 12345 }
        )
        let task = try #require(detector.activeTasks().first)
        #expect(task.processIdentifier == 12345)
    }

    @Test
    func testIgnoresDeadOrMismatchedSessionSidecars() throws {
        let root = makeTempRoot("claude-stale-pid")
        defer { try? FileManager.default.removeItem(at: root) }
        let projectsDir = root.appendingPathComponent(".claude/projects", isDirectory: true)
        let sessionsDir = root.appendingPathComponent(".claude/sessions", isDirectory: true)
        try FileManager.default.createDirectory(at: sessionsDir, withIntermediateDirectories: true)
        try Data(#"{"pid":111,"sessionId":"another-session"}"#.utf8)
            .write(to: sessionsDir.appendingPathComponent("111.json"))
        try Data(#"{"pid":222,"sessionId":"sess-stale"}"#.utf8)
            .write(to: sessionsDir.appendingPathComponent("222.json"))
        try writeJSONL(
            under: projectsDir,
            relativePath: "proj/session-stale.jsonl",
            lines: [
                claudeUser(timestamp: "2026-07-19T01:00:00.000Z", sessionId: "sess-stale", text: "hi"),
                claudeAssistant(
                    timestamp: "2026-07-19T01:00:01.000Z",
                    sessionId: "sess-stale",
                    stopReason: "tool_use",
                    model: "claude-opus",
                    toolUses: [("t1", "Bash")]
                ),
            ],
            modifiedAt: Date(timeIntervalSince1970: 1_900_000_181)
        )

        let task = try #require(ClaudeSessionActivityDetector(
            projectsDirectory: projectsDir,
            isProcessAlive: { $0 == 111 }
        ).activeTasks().first)
        #expect(task.processIdentifier == nil)
    }

    @Test
    func testSubagentTranscriptDoesNotReplaceParentTask() throws {
        let root = makeTempRoot("claude-subagent")
        defer { try? FileManager.default.removeItem(at: root) }

        try writeJSONL(
            under: root,
            relativePath: "proj/sess-parent.jsonl",
            lines: [
                #"{"type":"ai-title","sessionId":"sess-parent","aiTitle":"父会话标题"}"#,
                claudeUser(timestamp: "2026-07-19T01:00:00.000Z", sessionId: "sess-parent", text: "go"),
                claudeAssistant(
                    timestamp: "2026-07-19T01:00:01.000Z",
                    sessionId: "sess-parent",
                    stopReason: "tool_use",
                    model: "claude-opus-5",
                    toolUses: [("t1", "Task")]
                ),
            ],
            modifiedAt: Date(timeIntervalSince1970: 1_900_000_190)
        )
        // 子代理转录沿用父会话 ID，且更晚落盘，不能顶掉父任务。
        try writeJSONL(
            under: root,
            relativePath: "proj/sess-parent/subagents/agent-a1.jsonl",
            lines: [
                claudeUser(timestamp: "2026-07-19T01:00:02.000Z", sessionId: "sess-parent", text: "sub"),
                claudeAssistant(
                    timestamp: "2026-07-19T01:00:03.000Z",
                    sessionId: "sess-parent",
                    stopReason: "tool_use",
                    model: "claude-opus-5",
                    toolUses: [("t2", "Grep")]
                ),
            ],
            modifiedAt: Date(timeIntervalSince1970: 1_900_000_191)
        )

        let tasks = try ClaudeSessionActivityDetector(projectsDirectory: root).activeTasks()
        #expect(tasks.count == 1)
        #expect(tasks.first?.title == "父会话标题")
    }

    @Test
    func testLiveSessionsSurviveTranscriptLimit() throws {
        let root = makeTempRoot("claude-live-overflow")
        defer { try? FileManager.default.removeItem(at: root) }
        let projectsDir = root.appendingPathComponent(".claude/projects", isDirectory: true)
        let sessionsDir = root.appendingPathComponent(".claude/sessions", isDirectory: true)
        try FileManager.default.createDirectory(at: sessionsDir, withIntermediateDirectories: true)
        try Data(#"{"pid":901,"sessionId":"sess-old-live"}"#.utf8)
            .write(to: sessionsDir.appendingPathComponent("901.json"))

        for (sessionID, offset) in [("sess-old-live", 0), ("sess-newer", 10)] {
            try writeJSONL(
                under: projectsDir,
                relativePath: "proj/\(sessionID).jsonl",
                lines: [
                    claudeUser(timestamp: "2026-07-19T01:00:00.000Z", sessionId: sessionID, text: "go"),
                    claudeAssistant(
                        timestamp: "2026-07-19T01:00:01.000Z",
                        sessionId: sessionID,
                        stopReason: "tool_use",
                        model: "claude-opus-5",
                        toolUses: [("t1", "Bash")]
                    ),
                ],
                modifiedAt: Date(timeIntervalSince1970: 1_900_000_200 + Double(offset))
            )
        }

        let tasks = try ClaudeSessionActivityDetector(
            projectsDirectory: projectsDir,
            maxTranscriptFiles: 1,
            isProcessAlive: { $0 == 901 }
        ).activeTasks()

        #expect(Set(tasks.map(\.id)) == [
            ClaudeSessionActivityDetector.taskID(forSessionID: "sess-old-live"),
            ClaudeSessionActivityDetector.taskID(forSessionID: "sess-newer"),
        ])
    }

    @Test
    func testKeepsAITitleAcrossIdleTurns() throws {
        let root = makeTempRoot("claude-title-retained")
        defer { try? FileManager.default.removeItem(at: root) }
        let relative = "proj/session-retained.jsonl"

        try writeJSONL(
            under: root,
            relativePath: relative,
            lines: [
                #"{"type":"ai-title","sessionId":"sess-keep","aiTitle":"保留的标题"}"#,
                claudeUser(timestamp: "2026-07-19T01:00:00.000Z", sessionId: "sess-keep", text: "go"),
                claudeAssistant(
                    timestamp: "2026-07-19T01:00:01.000Z",
                    sessionId: "sess-keep",
                    stopReason: "end_turn",
                    model: "claude-opus-5",
                    toolUses: []
                ),
            ],
            modifiedAt: Date(timeIntervalSince1970: 1_900_000_210)
        )

        let detector = ClaudeSessionActivityDetector(projectsDirectory: root)
        #expect(try detector.activeTasks().isEmpty)

        // 新一轮开始时 `ai-title` 还没重写，标题必须来自缓存而不是回落成 "Claude"。
        try appendJSONLLine(
            claudeUser(timestamp: "2026-07-19T01:05:00.000Z", sessionId: "sess-keep", text: "again"),
            to: root.appendingPathComponent(relative)
        )
        #expect(try detector.activeTasks().first?.title == "保留的标题")
    }

    @Test
    func testIgnoresSyntheticModelPlaceholder() throws {
        let root = makeTempRoot("claude-synthetic-model")
        defer { try? FileManager.default.removeItem(at: root) }

        try writeJSONL(
            under: root,
            relativePath: "proj/session-synthetic.jsonl",
            lines: [
                claudeUser(timestamp: "2026-07-19T01:00:00.000Z", sessionId: "sess-syn", text: "hi"),
                claudeAssistant(
                    timestamp: "2026-07-19T01:00:01.000Z",
                    sessionId: "sess-syn",
                    stopReason: "tool_use",
                    model: "claude-opus-5",
                    toolUses: [("tool-1", "Bash")]
                ),
                claudeAssistant(
                    timestamp: "2026-07-19T01:00:02.000Z",
                    sessionId: "sess-syn",
                    stopReason: "tool_use",
                    model: "<synthetic>",
                    toolUses: []
                ),
            ],
            modifiedAt: Date(timeIntervalSince1970: 1_900_000_220)
        )

        let task = try #require(ClaudeSessionActivityDetector(projectsDirectory: root).activeTasks().first)
        #expect(task.detail == "claude-opus-5")
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
    isError: Bool,
    content: String = "ok"
) -> String {
    """
    {"type":"user","timestamp":"\(timestamp)","sessionId":"\(sessionId)","message":{"role":"user","content":[{"type":"tool_result","tool_use_id":"\(toolUseId)","is_error":\(isError),"content":"\(content)"}]}}
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
