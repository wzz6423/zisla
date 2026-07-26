import Foundation
import Testing
@testable import ZislaCore
@testable import ZislaKit

struct QoderSessionActivityDetectorTests {
    @Test
    func testStructuredCLIDetectsRunningTurn() throws {
        let configRoot = makeTempRoot("qoder-cli-running")
        defer { try? FileManager.default.removeItem(at: configRoot) }

        try writeJSONL(
            under: configRoot,
            relativePath: "logs/sessions/sess-1/segments/0001.jsonl",
            lines: [
                qoderStructured(
                    type: "turn.started",
                    ts: "2026-07-19T01:00:00.000Z",
                    ids: ["session_id": "sess-1", "turn_id": "t1"],
                    data: ["model": "qoder-pro"]
                ),
            ]
        )

        let tasks = try QoderSessionActivityDetector(
            configRoots: [configRoot],
            textLogRoots: []
        ).activeTasks()
        #expect(tasks.count == 1)
        let task = try #require(tasks.first)
        #expect(task.id == QoderSessionActivityDetector.taskID(forSessionID: "sess-1"))
        #expect(task.provider == .coder)
        #expect(task.title == "Qoder")
        #expect(task.status == .running)
        #expect(task.detail == "CLI")
    }

    @Test
    func testStructuredPermissionBlocksUntilResolved() throws {
        let configRoot = makeTempRoot("qoder-cli-blocked")
        defer { try? FileManager.default.removeItem(at: configRoot) }
        let relative = "logs/sessions/sess-p/segments/0001.jsonl"

        try writeJSONL(
            under: configRoot,
            relativePath: relative,
            lines: [
                qoderStructured(
                    type: "turn.started",
                    ts: "2026-07-19T01:00:00.000Z",
                    ids: ["session_id": "sess-p", "turn_id": "t1"],
                    data: ["model": "m"]
                ),
                qoderStructured(
                    type: "permission.requested",
                    ts: "2026-07-19T01:00:01.000Z",
                    ids: ["session_id": "sess-p", "tool_call_id": "tc-1"],
                    data: [:]
                ),
            ]
        )

        let detector = QoderSessionActivityDetector(configRoots: [configRoot], textLogRoots: [])
        #expect(try detector.activeTasks().first?.status == .blocked)

        try appendJSONLLine(
            qoderStructured(
                type: "permission.resolved",
                ts: "2026-07-19T01:00:02.000Z",
                ids: ["session_id": "sess-p", "tool_call_id": "tc-1"],
                data: [:]
            ),
            to: configRoot.appendingPathComponent(relative)
        )
        #expect(try detector.activeTasks().first?.status == .running)
    }

    @Test
    func testStructuredToolErrorShellAndRecovery() throws {
        let configRoot = makeTempRoot("qoder-cli-error")
        defer { try? FileManager.default.removeItem(at: configRoot) }
        let relative = "logs/sessions/sess-e/segments/0001.jsonl"

        try writeJSONL(
            under: configRoot,
            relativePath: relative,
            lines: [
                qoderStructured(
                    type: "turn.started",
                    ts: "2026-07-19T01:00:00.000Z",
                    ids: ["session_id": "sess-e", "turn_id": "t1"],
                    data: [:]
                ),
                qoderStructured(
                    type: "tool.execution.finished",
                    ts: "2026-07-19T01:00:01.000Z",
                    ids: ["session_id": "sess-e"],
                    data: ["status": "error", "is_error": true]
                ),
            ]
        )

        let detector = QoderSessionActivityDetector(configRoots: [configRoot], textLogRoots: [])
        #expect(try detector.activeTasks().first?.status == .error)

        try appendJSONLLine(
            qoderStructured(
                type: "tool.shell.finished",
                ts: "2026-07-19T01:00:02.000Z",
                ids: ["session_id": "sess-e"],
                data: ["exit_code": 0]
            ),
            to: configRoot.appendingPathComponent(relative)
        )
        #expect(try detector.activeTasks().first?.status == .running)

        try appendJSONLLine(
            qoderStructured(
                type: "tool.shell.failed",
                ts: "2026-07-19T01:00:03.000Z",
                ids: ["session_id": "sess-e"],
                data: [:]
            ),
            to: configRoot.appendingPathComponent(relative)
        )
        #expect(try detector.activeTasks().first?.status == .error)
    }

    @Test
    func testStructuredTurnFinishedCompletesOrKeepsError() throws {
        let configRoot = makeTempRoot("qoder-cli-finish")
        defer { try? FileManager.default.removeItem(at: configRoot) }

        try writeJSONL(
            under: configRoot,
            relativePath: "logs/sessions/sess-f/segments/0001.jsonl",
            lines: [
                qoderStructured(
                    type: "turn.started",
                    ts: "2026-07-19T01:00:00.000Z",
                    ids: ["session_id": "sess-f", "turn_id": "t1"],
                    data: [:]
                ),
                qoderStructured(
                    type: "turn.finished",
                    ts: "2026-07-19T01:00:05.000Z",
                    ids: ["session_id": "sess-f", "turn_id": "t1"],
                    data: ["reason": "completed"]
                ),
            ]
        )
        #expect(try QoderSessionActivityDetector(
            configRoots: [configRoot],
            textLogRoots: []
        ).activeTasks().isEmpty)

        try writeJSONL(
            under: configRoot,
            relativePath: "logs/sessions/sess-fe/segments/0001.jsonl",
            lines: [
                qoderStructured(
                    type: "turn.started",
                    ts: "2026-07-19T02:00:00.000Z",
                    ids: ["session_id": "sess-fe", "turn_id": "t2"],
                    data: [:]
                ),
                qoderStructured(
                    type: "turn.finished",
                    ts: "2026-07-19T02:00:05.000Z",
                    ids: ["session_id": "sess-fe", "turn_id": "t2"],
                    data: ["reason": "error"]
                ),
            ]
        )
        #expect(try QoderSessionActivityDetector(
            configRoots: [configRoot],
            textLogRoots: []
        ).activeTasks().first?.status == .error)
    }

    @Test
    func testTextSDKRunningBlockedErrorAndComplete() throws {
        let textRoot = makeTempRoot("qoder-text")
        defer { try? FileManager.default.removeItem(at: textRoot) }
        let logRelative = "QoderWork/logs/qoder-agent-sdk.log"
        let relativeURL = textRoot.appendingPathComponent(logRelative)

        try writeTextLog(
            to: relativeURL,
            lines: [
                #"2026-07-19T01:00:00.000Z [QueryRunner] outbound session_message sent type=user"#,
            ]
        )

        let detector = QoderSessionActivityDetector(configRoots: [], textLogRoots: [textRoot])
        let running = try detector.activeTasks()
        #expect(running.count == 1)
        #expect(running[0].status == .running)
        #expect(running[0].provider == .coder)
        #expect(running[0].detail == "Desktop" || running[0].detail == "Host")

        try appendTextLine(
            #"2026-07-19T01:00:01.000Z inbound control_request received request_id=req-1 subtype=can_use_tool"#,
            to: relativeURL
        )
        #expect(try detector.activeTasks().first?.status == .blocked)

        try appendTextLine(
            #"2026-07-19T01:00:02.000Z inbound control_response sent request_id=req-1 subtype=can_use_tool status=success"#,
            to: relativeURL
        )
        #expect(try detector.activeTasks().first?.status == .running)

        try appendTextLine(
            #"2026-07-19T01:00:03.000Z inbound session_message received type=result subtype=error_during_execution"#,
            to: relativeURL
        )
        #expect(try detector.activeTasks().first?.status == .error)

        try appendTextLine(
            #"2026-07-19T01:00:04.000Z [QueryRunner] outbound session_message sent type=user"#,
            to: relativeURL
        )
        #expect(try detector.activeTasks().first?.status == .running)

        try appendTextLine(
            #"2026-07-19T01:00:05.000Z inbound session_message received type=result subtype=success"#,
            to: relativeURL
        )
        #expect(try detector.activeTasks().isEmpty)
    }

    @Test
    func testDiscoversVSCodeCompatibleHostLogRoots() throws {
        let home = makeTempRoot("qoder-home-discover")
        defer { try? FileManager.default.removeItem(at: home) }

        let appSupport = home.appendingPathComponent("Library/Application Support", isDirectory: true)
        let codeRoot = appSupport.appendingPathComponent("Code", isDirectory: true)
        let codeLogsRoot = codeRoot.appendingPathComponent("logs", isDirectory: true)
        let logURL = codeLogsRoot
            .appendingPathComponent("20260719/exthost/output_logging_qoder", isDirectory: true)
            .appendingPathComponent("qoder-agent-sdk.log")

        try writeTextLog(
            to: logURL,
            lines: [
                #"2026-07-19T01:00:00.000Z [QueryRunner] outbound session_message sent type=user"#,
            ]
        )

        let roots = QoderSessionActivityDetector.defaultTextLogRoots(home: home)
        #expect(roots.contains(where: { $0.path == codeLogsRoot.path }))

        let tasks = try QoderSessionActivityDetector(
            configRoots: [],
            textLogRoots: roots
        ).activeTasks()
        #expect(tasks.count == 1)
        #expect(tasks[0].status == .running)
        #expect(tasks[0].detail == "VS Code")
    }

    @Test
    func testSameFileIsNotDuplicatedAcrossScans() throws {
        let configRoot = makeTempRoot("qoder-dedupe")
        defer { try? FileManager.default.removeItem(at: configRoot) }

        try writeJSONL(
            under: configRoot,
            relativePath: "logs/sessions/sess-d/segments/0001.jsonl",
            lines: [
                qoderStructured(
                    type: "turn.started",
                    ts: "2026-07-19T01:00:00.000Z",
                    ids: ["session_id": "sess-d", "turn_id": "t1"],
                    data: [:]
                ),
            ]
        )

        let tasks = try QoderSessionActivityDetector(
            configRoots: [configRoot, configRoot],
            textLogRoots: []
        ).activeTasks()
        #expect(tasks.count == 1)
        #expect(tasks[0].id == QoderSessionActivityDetector.taskID(forSessionID: "sess-d"))
    }

    @Test
    func testDeduplicatesDesktopSDKAndStructuredTurn() throws {
        let configRoot = makeTempRoot("qoder-desktop-structured")
        let textRoot = makeTempRoot("qoder-desktop-sdk")
        defer {
            try? FileManager.default.removeItem(at: configRoot)
            try? FileManager.default.removeItem(at: textRoot)
        }

        try writeJSONL(
            under: configRoot,
            relativePath: "logs/sessions/workspace/sess-desktop/segments/0001.jsonl",
            lines: [
                qoderStructured(
                    type: "turn.started",
                    ts: "2026-07-19T01:00:00.453Z",
                    ids: ["session_id": "sess-desktop", "turn_id": "t1"],
                    data: [:]
                ),
            ]
        )
        try writeTextLog(
            to: textRoot.appendingPathComponent("QoderWork/logs/qoder-agent-sdk.log"),
            lines: [
                #"2026-07-19T01:00:00.000Z [QueryRunner] outbound session_message sent type=user"#,
                #"2026-07-19T01:00:01.000Z inbound control_request received request_id=req-1 subtype=can_use_tool"#,
            ]
        )

        let detector = QoderSessionActivityDetector(
            configRoots: [configRoot],
            textLogRoots: [textRoot]
        )
        let tasks = try detector.activeTasks()
        #expect(tasks.count == 1)
        let task = try #require(tasks.first)
        #expect(task.id == QoderSessionActivityDetector.taskID(forSessionID: "sess-desktop"))
        #expect(task.detail == "Desktop")
        #expect(task.status == .blocked)
        #expect(task.sessionURL?.absoluteString == "qoder-work-cn://notification-click?chatId=sess-desktop")

        let cachedTasks = try detector.activeTasks()
        #expect(cachedTasks == tasks)
    }

    @Test
    func testDoesNotDeduplicateDesktopOutsideTimeWindow() throws {
        let configRoot = makeTempRoot("qoder-outside-window-structured")
        let textRoot = makeTempRoot("qoder-outside-window-sdk")
        defer {
            try? FileManager.default.removeItem(at: configRoot)
            try? FileManager.default.removeItem(at: textRoot)
        }

        try writeJSONL(
            under: configRoot,
            relativePath: "logs/sessions/workspace/sess-late/segments/0001.jsonl",
            lines: [
                qoderStructured(
                    type: "turn.started",
                    ts: "2026-07-19T01:00:03.000Z",
                    ids: ["session_id": "sess-late", "turn_id": "t1"],
                    data: [:]
                ),
            ]
        )
        try writeTextLog(
            to: textRoot.appendingPathComponent("QoderWork/logs/qoder-agent-sdk.log"),
            lines: [
                #"2026-07-19T01:00:00.000Z [QueryRunner] outbound session_message sent type=user"#,
            ]
        )

        let tasks = try QoderSessionActivityDetector(
            configRoots: [configRoot],
            textLogRoots: [textRoot]
        ).activeTasks()
        #expect(tasks.count == 2)
    }

    @Test
    func testDoesNotDeduplicateVSCodeWithStructuredTurn() throws {
        let configRoot = makeTempRoot("qoder-vscode-structured")
        let textRoot = makeTempRoot("qoder-vscode-sdk")
        defer {
            try? FileManager.default.removeItem(at: configRoot)
            try? FileManager.default.removeItem(at: textRoot)
        }

        try writeJSONL(
            under: configRoot,
            relativePath: "logs/sessions/workspace/sess-vscode/segments/0001.jsonl",
            lines: [
                qoderStructured(
                    type: "turn.started",
                    ts: "2026-07-19T01:00:00.453Z",
                    ids: ["session_id": "sess-vscode", "turn_id": "t1"],
                    data: [:]
                ),
            ]
        )
        try writeTextLog(
            to: textRoot.appendingPathComponent("Code/logs/qoder-agent-sdk.log"),
            lines: [
                #"2026-07-19T01:00:00.000Z [QueryRunner] outbound session_message sent type=user"#,
            ]
        )

        let tasks = try QoderSessionActivityDetector(
            configRoots: [configRoot],
            textLogRoots: [textRoot]
        ).activeTasks()
        #expect(tasks.count == 2)
        #expect(tasks.contains(where: { $0.detail == "VS Code" }))
    }

    @Test
    func testDoesNotGuessWhenMultipleStructuredTurnsMatchDesktop() throws {
        let configRoot = makeTempRoot("qoder-concurrent-structured")
        let textRoot = makeTempRoot("qoder-concurrent-sdk")
        defer {
            try? FileManager.default.removeItem(at: configRoot)
            try? FileManager.default.removeItem(at: textRoot)
        }

        for (sessionID, timestamp) in [
            ("sess-a", "2026-07-19T01:00:00.453Z"),
            ("sess-b", "2026-07-19T01:00:00.700Z"),
        ] {
            try writeJSONL(
                under: configRoot,
                relativePath: "logs/sessions/workspace/\(sessionID)/segments/0001.jsonl",
                lines: [
                    qoderStructured(
                        type: "turn.started",
                        ts: timestamp,
                        ids: ["session_id": sessionID, "turn_id": "t1"],
                        data: [:]
                    ),
                ]
            )
        }
        try writeTextLog(
            to: textRoot.appendingPathComponent("QoderWork/logs/qoder-agent-sdk.log"),
            lines: [
                #"2026-07-19T01:00:00.000Z [QueryRunner] outbound session_message sent type=user"#,
            ]
        )

        let tasks = try QoderSessionActivityDetector(
            configRoots: [configRoot],
            textLogRoots: [textRoot]
        ).activeTasks()
        #expect(tasks.count == 3)
    }

    @Test
    func testIgnoresCorruptLinesPartialTailAndMissingRoots() throws {
        let configRoot = makeTempRoot("qoder-noisy")
        defer { try? FileManager.default.removeItem(at: configRoot) }

        let url = configRoot.appendingPathComponent("logs/sessions/sess-n/segments/0001.jsonl")
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let body = [
            "{bad",
            qoderStructured(
                type: "turn.started",
                ts: "2026-07-19T01:00:00.000Z",
                ids: ["session_id": "sess-n", "turn_id": "t1"],
                data: [:]
            ),
            #"{"type":"turn.started","ts":""#,
        ].joined(separator: "\n")
        try Data(body.utf8).write(to: url)

        let tasks = try QoderSessionActivityDetector(
            configRoots: [configRoot],
            textLogRoots: []
        ).activeTasks()
        #expect(tasks.count == 1)

        let missing = FileManager.default.temporaryDirectory
            .appendingPathComponent("Zisla-qoder-missing-\(UUID().uuidString)", isDirectory: true)
        #expect(try QoderSessionActivityDetector(
            configRoots: [missing],
            textLogRoots: [missing]
        ).activeTasks().isEmpty)
    }

    @Test
    func testColdStartIgnoresStateOutsideBoundedStructuredAndTextTails() throws {
        let configRoot = makeTempRoot("qoder-bounded-structured")
        let textRoot = makeTempRoot("qoder-bounded-text")
        defer {
            try? FileManager.default.removeItem(at: configRoot)
            try? FileManager.default.removeItem(at: textRoot)
        }
        let padding = String(repeating: "x", count: 1_100_000)

        try writeJSONL(
            under: configRoot,
            relativePath: "logs/sessions/sess-old/segments/0001.jsonl",
            lines: [
                qoderStructured(
                    type: "turn.started",
                    ts: "2026-07-19T01:00:00.000Z",
                    ids: ["session_id": "sess-old", "turn_id": "t1"],
                    data: [:]
                ),
                #"{"type":"metadata","padding":""# + padding + #""}"#,
            ]
        )
        try writeTextLog(
            to: textRoot.appendingPathComponent("QoderWork/logs/qoder-agent-sdk.log"),
            lines: [
                #"2026-07-19T01:00:00.000Z [QueryRunner] outbound session_message sent type=user"#,
                padding,
            ]
        )

        #expect(try QoderSessionActivityDetector(
            configRoots: [configRoot],
            textLogRoots: [textRoot]
        ).activeTasks().isEmpty)
    }

    @Test
    func testPermissionFailedIsError() throws {
        let configRoot = makeTempRoot("qoder-perm-fail")
        defer { try? FileManager.default.removeItem(at: configRoot) }

        try writeJSONL(
            under: configRoot,
            relativePath: "logs/sessions/sess-pf/segments/0001.jsonl",
            lines: [
                qoderStructured(
                    type: "turn.started",
                    ts: "2026-07-19T01:00:00.000Z",
                    ids: ["session_id": "sess-pf", "turn_id": "t1"],
                    data: [:]
                ),
                qoderStructured(
                    type: "permission.requested",
                    ts: "2026-07-19T01:00:01.000Z",
                    ids: ["session_id": "sess-pf", "tool_call_id": "tc-x"],
                    data: [:]
                ),
                qoderStructured(
                    type: "permission.failed",
                    ts: "2026-07-19T01:00:02.000Z",
                    ids: ["session_id": "sess-pf", "tool_call_id": "tc-x"],
                    data: [:]
                ),
            ]
        )

        #expect(try QoderSessionActivityDetector(
            configRoots: [configRoot],
            textLogRoots: []
        ).activeTasks().first?.status == .error)
    }

    @Test
    func testCodexProtocolConformanceExists() throws {
        let detector: any AIActivityDetecting = CodexSessionActivityDetector(
            sessionsDirectory: FileManager.default.temporaryDirectory
                .appendingPathComponent("missing-codex-\(UUID().uuidString)")
        )
        #expect(try detector.activeTasks().isEmpty)
    }

    @Test
    func testRealCLIShapeMergesSegmentsAndUsesTopLevelToolCallID() throws {
        let root = makeTempRoot("qoder-real-segments")
        defer { try? FileManager.default.removeItem(at: root) }
        let prefix = "logs/sessions/workspace/session-real/segments"

        try writeJSONL(
            under: root,
            relativePath: "\(prefix)/0001.jsonl",
            lines: [
                #"{"ts":"2026-07-19T01:00:00.000Z","seq":1,"type":"turn.started","turn_id":"turn-1","data":{"model":"qoder-pro"}}"#,
            ]
        )
        try writeJSONL(
            under: root,
            relativePath: "\(prefix)/0002.jsonl",
            lines: [
                #"{"ts":"2026-07-19T01:00:01.000Z","seq":2,"type":"permission.requested","turn_id":"turn-1","tool_call_id":"tool-1","data":{"tool_name":"Bash"}}"#,
            ]
        )
        let detector = QoderSessionActivityDetector(configRoots: [root], textLogRoots: [])
        let blocked = try #require(detector.activeTasks().first)
        #expect(blocked.id == QoderSessionActivityDetector.taskID(forSessionID: "session-real"))
        #expect(blocked.status == .blocked)

        try writeJSONL(
            under: root,
            relativePath: "\(prefix)/0003.jsonl",
            lines: [
                #"{"ts":"2026-07-19T01:00:02.000Z","seq":3,"type":"permission.resolved","turn_id":"turn-1","tool_call_id":"tool-1","data":{"allowed":true}}"#,
                #"{"ts":"2026-07-19T01:00:03.000Z","seq":4,"type":"turn.finished","turn_id":"turn-1","data":{"reason":"end_turn"}}"#,
            ]
        )
        #expect(try detector.activeTasks().isEmpty)
    }

    @Test
    func testDiscoversQoderProductAndConfigVariants() throws {
        let home = makeTempRoot("qoder-variants")
        defer { try? FileManager.default.removeItem(at: home) }
        let appSupport = home.appendingPathComponent("Library/Application Support")
        for name in ["Qoder", "QoderWork CN", "QoderWake", "Acme Qoder Preview"] {
            try FileManager.default.createDirectory(
                at: appSupport.appendingPathComponent(name),
                withIntermediateDirectories: true
            )
        }
        for name in [".qoder", ".qoderworkcn", ".qoderwake", ".qoder-preview"] {
            try FileManager.default.createDirectory(
                at: home.appendingPathComponent(name),
                withIntermediateDirectories: true
            )
        }

        let textNames = Set(QoderSessionActivityDetector
            .defaultTextLogRoots(home: home)
            .map(\.lastPathComponent))
        #expect(textNames.isSuperset(of: [
            "Qoder", "QoderWork CN", "QoderWake", "Acme Qoder Preview",
        ]))

        let configNames = Set(QoderSessionActivityDetector
            .defaultConfigRoots(home: home)
            .map(\.lastPathComponent))
        #expect(configNames.isSuperset(of: [
            ".qoder", ".qoderworkcn", ".qoderwake", ".qoder-preview",
        ]))
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
    modifiedAt: Date = Date(timeIntervalSince1970: 1_920_000_100)
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

private func writeTextLog(to url: URL, lines: [String]) throws {
    try FileManager.default.createDirectory(
        at: url.deletingLastPathComponent(),
        withIntermediateDirectories: true
    )
    try Data((lines.joined(separator: "\n") + "\n").utf8).write(to: url)
}

private func appendTextLine(_ line: String, to url: URL) throws {
    let handle = try FileHandle(forWritingTo: url)
    defer { try? handle.close() }
    try handle.seekToEnd()
    try handle.write(contentsOf: Data((line + "\n").utf8))
}

private func qoderStructured(
    type: String,
    ts: String,
    ids: [String: String],
    data: [String: Any]
) -> String {
    let idsJSON = ids
        .map { "\"\($0.key)\":\"\($0.value)\"" }
        .sorted()
        .joined(separator: ",")
    let dataJSON: String
    if data.isEmpty {
        dataJSON = "{}"
    } else {
        let parts = data.keys.sorted().compactMap { key -> String? in
            guard let value = data[key] else { return nil }
            if let string = value as? String {
                return "\"\(key)\":\"\(string)\""
            }
            if let bool = value as? Bool {
                return "\"\(key)\":\(bool)"
            }
            if let number = value as? NSNumber {
                return "\"\(key)\":\(number)"
            }
            if let int = value as? Int {
                return "\"\(key)\":\(int)"
            }
            return nil
        }
        dataJSON = "{\(parts.joined(separator: ","))}"
    }
    return """
    {"ts":"\(ts)","type":"\(type)","ids":{\(idsJSON)},"data":\(dataJSON)}
    """
}
