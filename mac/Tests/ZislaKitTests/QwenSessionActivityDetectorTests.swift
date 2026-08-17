import Foundation
import Testing
@testable import ZislaCore
@testable import ZislaKit

struct QwenSessionActivityDetectorTests {
    @Test
    func testDetectsRunningFunctionCallWhilePidAlive() throws {
        let root = makeTempRoot("qwen-running")
        defer { try? FileManager.default.removeItem(at: root) }

        try writeRuntimeAndTranscript(
            under: root,
            baseName: "chat-1",
            pid: 4242,
            sessionID: "qw-sess-1",
            qwenVersion: "0.9.0",
            transcriptLines: [
                qwenUser(timestamp: "2026-07-19T01:00:00.000Z"),
                qwenAssistantFunctionCall(
                    timestamp: "2026-07-19T01:00:01.000Z",
                    name: "run_shell",
                    model: "qwen3-coder"
                ),
            ]
        )

        let detector = QwenSessionActivityDetector(
            projectsDirectory: root,
            isProcessAlive: { $0 == 4242 }
        )
        let tasks = try detector.activeTasks()
        #expect(tasks.count == 1)
        let task = try #require(tasks.first)
        #expect(task.id == QwenSessionActivityDetector.taskID(forSessionID: "qw-sess-1"))
        #expect(task.provider == .qwen)
        #expect(task.title == "千问")
        #expect(task.status == .running)
        #expect(task.detail == "qwen3-coder")
    }

    @Test
    func testAskUserQuestionBlocks() throws {
        let root = makeTempRoot("qwen-blocked")
        defer { try? FileManager.default.removeItem(at: root) }

        try writeRuntimeAndTranscript(
            under: root,
            baseName: "chat-b",
            pid: 100,
            sessionID: "qw-b",
            transcriptLines: [
                qwenUser(timestamp: "2026-07-19T01:00:00.000Z"),
                qwenAssistantFunctionCall(
                    timestamp: "2026-07-19T01:00:01.000Z",
                    name: "ask_user_question",
                    model: "qwen3"
                ),
            ]
        )

        let tasks = try QwenSessionActivityDetector(
            projectsDirectory: root,
            isProcessAlive: { _ in true }
        ).activeTasks()
        #expect(tasks.first?.status == .blocked)
    }

    @Test
    func testToolResultErrorThenSuccessRecovers() throws {
        let root = makeTempRoot("qwen-error")
        defer { try? FileManager.default.removeItem(at: root) }
        let base = "chat-e"

        try writeRuntimeAndTranscript(
            under: root,
            baseName: base,
            pid: 200,
            sessionID: "qw-e",
            transcriptLines: [
                qwenUser(timestamp: "2026-07-19T01:00:00.000Z"),
                qwenAssistantFunctionCall(
                    timestamp: "2026-07-19T01:00:01.000Z",
                    name: "run_shell",
                    model: "qwen3"
                ),
                qwenToolResult(timestamp: "2026-07-19T01:00:02.000Z", status: "error"),
            ]
        )

        let detector = QwenSessionActivityDetector(
            projectsDirectory: root,
            isProcessAlive: { _ in true }
        )
        #expect(try detector.activeTasks().first?.status == .error)

        try appendJSONLLine(
            qwenToolResult(timestamp: "2026-07-19T01:00:03.000Z", status: "success"),
            to: root.appendingPathComponent("proj/\(base).jsonl")
        )
        #expect(try detector.activeTasks().first?.status == .running)
    }

    @Test
    func testAssistantWithoutFunctionCallEndsTurn() throws {
        let root = makeTempRoot("qwen-idle")
        defer { try? FileManager.default.removeItem(at: root) }

        try writeRuntimeAndTranscript(
            under: root,
            baseName: "chat-done",
            pid: 300,
            sessionID: "qw-done",
            transcriptLines: [
                qwenUser(timestamp: "2026-07-19T01:00:00.000Z"),
                #"{"type":"assistant","timestamp":"2026-07-19T01:00:01.000Z","message":{"parts":[{"text":"done"}],"model":"qwen3"}}"#,
            ]
        )

        let tasks = try QwenSessionActivityDetector(
            projectsDirectory: root,
            isProcessAlive: { _ in true }
        ).activeTasks()
        #expect(tasks.isEmpty)
    }

    @Test
    func testStalePidYieldsNoTaskEvenWithActiveTranscript() throws {
        let root = makeTempRoot("qwen-stale")
        defer { try? FileManager.default.removeItem(at: root) }

        try writeRuntimeAndTranscript(
            under: root,
            baseName: "chat-stale",
            pid: 9999,
            sessionID: "qw-stale",
            transcriptLines: [
                qwenUser(timestamp: "2026-07-19T01:00:00.000Z"),
                qwenAssistantFunctionCall(
                    timestamp: "2026-07-19T01:00:01.000Z",
                    name: "run_shell",
                    model: "qwen3"
                ),
            ]
        )

        let tasks = try QwenSessionActivityDetector(
            projectsDirectory: root,
            isProcessAlive: { _ in false }
        ).activeTasks()
        #expect(tasks.isEmpty)
    }

    @Test
    func testAlivePidWithIdleTranscriptYieldsNoTask() throws {
        let root = makeTempRoot("qwen-cli-idle")
        defer { try? FileManager.default.removeItem(at: root) }

        try writeRuntimeAndTranscript(
            under: root,
            baseName: "chat-idle",
            pid: 400,
            sessionID: "qw-idle",
            transcriptLines: [
                qwenUser(timestamp: "2026-07-19T01:00:00.000Z"),
                #"{"type":"assistant","timestamp":"2026-07-19T01:00:01.000Z","message":{"parts":[{"text":"done"}]}}"#,
            ]
        )

        let tasks = try QwenSessionActivityDetector(
            projectsDirectory: root,
            isProcessAlive: { _ in true }
        ).activeTasks()
        #expect(tasks.isEmpty)
    }

    @Test
    func testIgnoresCorruptLinesAndMissingDirectory() throws {
        let root = makeTempRoot("qwen-noisy")
        defer { try? FileManager.default.removeItem(at: root) }

        try writeRuntimeAndTranscript(
            under: root,
            baseName: "chat-n",
            pid: 500,
            sessionID: "qw-n",
            transcriptLines: [
                "{bad",
                qwenUser(timestamp: "2026-07-19T01:00:00.000Z"),
                qwenAssistantFunctionCall(
                    timestamp: "2026-07-19T01:00:01.000Z",
                    name: "run_shell",
                    model: "qwen3"
                ),
            ],
            trailingPartial: #"{"type":"assistant","timestamp":""#
        )

        let tasks = try QwenSessionActivityDetector(
            projectsDirectory: root,
            isProcessAlive: { _ in true }
        ).activeTasks()
        #expect(tasks.count == 1)

        let missing = FileManager.default.temporaryDirectory
            .appendingPathComponent("Zisla-qwen-missing-\(UUID().uuidString)", isDirectory: true)
        #expect(try QwenSessionActivityDetector(
            projectsDirectory: missing,
            isProcessAlive: { _ in true }
        ).activeTasks().isEmpty)
    }

    @Test
    func testVSCodeCompanionRuntimeStillDetected() throws {
        let root = makeTempRoot("qwen-vscode")
        defer { try? FileManager.default.removeItem(at: root) }

        try writeRuntimeAndTranscript(
            under: root,
            baseName: "vscode-companion",
            pid: 600,
            sessionID: "qw-vs",
            workDir: "/Users/dev/project",
            transcriptLines: [
                qwenUser(timestamp: "2026-07-19T01:00:00.000Z"),
                qwenAssistantFunctionCall(
                    timestamp: "2026-07-19T01:00:01.000Z",
                    name: "read_file",
                    model: "qwen3-coder"
                ),
            ]
        )

        let task = try #require(QwenSessionActivityDetector(
            projectsDirectory: root,
            isProcessAlive: { _ in true }
        ).activeTasks().first)
        #expect(task.provider == .qwen)
        #expect(task.status == .running)
    }

    @Test
    func testDetailFallsBackToQwenVersionWhenModelMissing() throws {
        let root = makeTempRoot("qwen-version-detail")
        defer { try? FileManager.default.removeItem(at: root) }

        try writeRuntimeAndTranscript(
            under: root,
            baseName: "chat-v",
            pid: 700,
            sessionID: "qw-v",
            qwenVersion: "1.2.3",
            transcriptLines: [
                qwenUser(timestamp: "2026-07-19T01:00:00.000Z"),
                #"{"type":"assistant","timestamp":"2026-07-19T01:00:01.000Z","message":{"parts":[{"functionCall":{"name":"run_shell"}}]}}"#,
            ]
        )

        let task = try #require(QwenSessionActivityDetector(
            projectsDirectory: root,
            isProcessAlive: { _ in true }
        ).activeTasks().first)
        #expect(task.detail == "1.2.3")
    }

    @Test
    func testRuntimeDirectoryTakesPrecedenceOverQwenHome() {
        #expect(QwenSessionActivityDetector.runtimeRootPath(environment: [
            "QWEN_RUNTIME_DIR": "/tmp/qwen-runtime",
            "QWEN_HOME": "/tmp/qwen-home",
        ]) == "/tmp/qwen-runtime")
        #expect(QwenSessionActivityDetector.runtimeRootPath(environment: [
            "QWEN_HOME": "/tmp/qwen-home",
        ]) == "/tmp/qwen-home")
    }

    @Test
    func testDeadNewerRuntimeDoesNotHideOlderLiveRuntime() throws {
        let root = makeTempRoot("qwen-live-before-limit")
        defer { try? FileManager.default.removeItem(at: root) }

        try writeRuntimeAndTranscript(
            under: root,
            baseName: "live",
            pid: 800,
            sessionID: "qw-live",
            transcriptLines: [
                qwenUser(timestamp: "2026-07-19T01:00:00.000Z"),
                qwenAssistantFunctionCall(
                    timestamp: "2026-07-19T01:00:01.000Z",
                    name: "run_shell",
                    model: "qwen3-coder"
                ),
            ]
        )
        try writeRuntimeAndTranscript(
            under: root,
            baseName: "dead",
            pid: 801,
            sessionID: "qw-dead",
            transcriptLines: [
                qwenUser(timestamp: "2026-07-19T02:00:00.000Z"),
                qwenAssistantFunctionCall(
                    timestamp: "2026-07-19T02:00:01.000Z",
                    name: "run_shell",
                    model: "qwen3-coder"
                ),
            ]
        )
        let project = root.appendingPathComponent("proj")
        let oldDate = Date(timeIntervalSince1970: 1_910_000_100)
        let newDate = Date(timeIntervalSince1970: 1_910_000_200)
        for name in ["live.runtime.json", "live.jsonl"] {
            try FileManager.default.setAttributes(
                [.modificationDate: oldDate],
                ofItemAtPath: project.appendingPathComponent(name).path
            )
        }
        for name in ["dead.runtime.json", "dead.jsonl"] {
            try FileManager.default.setAttributes(
                [.modificationDate: newDate],
                ofItemAtPath: project.appendingPathComponent(name).path
            )
        }

        let tasks = try QwenSessionActivityDetector(
            projectsDirectory: root,
            maxRuntimeFiles: 1,
            isProcessAlive: { $0 == 800 }
        ).activeTasks()
        #expect(tasks.map(\.id) == [QwenSessionActivityDetector.taskID(forSessionID: "qw-live")])
    }

    @Test
    func testColdStartIgnoresStateOutsideTheBoundedTail() throws {
        let root = makeTempRoot("qwen-bounded-tail")
        defer { try? FileManager.default.removeItem(at: root) }
        let padding = String(repeating: "x", count: 1_100_000)

        try writeRuntimeAndTranscript(
            under: root,
            baseName: "chat-old",
            pid: 900,
            sessionID: "qw-old",
            transcriptLines: [
                qwenUser(timestamp: "2026-07-19T01:00:00.000Z"),
                #"{"type":"metadata","padding":""# + padding + #""}"#,
            ]
        )

        #expect(try QwenSessionActivityDetector(
            projectsDirectory: root,
            isProcessAlive: { _ in true }
        ).activeTasks().isEmpty)
    }

    @Test
    func testPIDIsPassedToTask() throws {
        let root = makeTempRoot("qwen-pid")
        defer { try? FileManager.default.removeItem(at: root) }

        try writeRuntimeAndTranscript(
            under: root,
            baseName: "chat-pid",
            pid: 54321,
            sessionID: "qw-pid",
            transcriptLines: [
                qwenUser(timestamp: "2026-07-19T01:00:00.000Z"),
                qwenAssistantFunctionCall(
                    timestamp: "2026-07-19T01:00:01.000Z",
                    name: "run_shell",
                    model: "qwen3-coder"
                ),
            ]
        )

        let task = try #require(QwenSessionActivityDetector(
            projectsDirectory: root,
            isProcessAlive: { _ in true }
        ).activeTasks().first)
        #expect(task.processIdentifier == 54321)
    }
}

// MARK: - Fixtures

private func makeTempRoot(_ label: String) -> URL {
    FileManager.default.temporaryDirectory
        .appendingPathComponent("Zisla-\(label)-\(UUID().uuidString)", isDirectory: true)
}

private func writeRuntimeAndTranscript(
    under root: URL,
    baseName: String,
    pid: Int32,
    sessionID: String,
    qwenVersion: String? = nil,
    workDir: String? = nil,
    transcriptLines: [String],
    trailingPartial: String? = nil
) throws {
    let dir = root.appendingPathComponent("proj", isDirectory: true)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

    var sidecar: [String: Any] = [
        "schema_version": 1,
        "pid": pid,
        "session_id": sessionID,
        "hostname": "test-host",
        "started_at": "2026-07-19T00:59:00.000Z",
    ]
    if let qwenVersion { sidecar["qwen_version"] = qwenVersion }
    if let workDir { sidecar["work_dir"] = workDir }

    let runtimeURL = dir.appendingPathComponent("\(baseName).runtime.json")
    let runtimeData = try JSONSerialization.data(withJSONObject: sidecar, options: [.sortedKeys])
    try runtimeData.write(to: runtimeURL)

    let transcriptURL = dir.appendingPathComponent("\(baseName).jsonl")
    var body = transcriptLines.joined(separator: "\n") + "\n"
    if let trailingPartial {
        body += trailingPartial
    }
    try Data(body.utf8).write(to: transcriptURL)
}

private func appendJSONLLine(_ line: String, to url: URL) throws {
    let handle = try FileHandle(forWritingTo: url)
    defer { try? handle.close() }
    try handle.seekToEnd()
    try handle.write(contentsOf: Data((line + "\n").utf8))
}

private func qwenUser(timestamp: String) -> String {
    """
    {"type":"user","timestamp":"\(timestamp)","message":{"parts":[{"text":"hi"}]}}
    """
}

private func qwenAssistantFunctionCall(timestamp: String, name: String, model: String) -> String {
    """
    {"type":"assistant","timestamp":"\(timestamp)","message":{"model":"\(model)","parts":[{"functionCall":{"name":"\(name)","args":{}}}]}}
    """
}

private func qwenToolResult(timestamp: String, status: String) -> String {
    """
    {"type":"tool_result","timestamp":"\(timestamp)","toolCallResult":{"status":"\(status)"}}
    """
}
