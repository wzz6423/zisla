import Foundation
import Testing
@testable import ZislaCore
@testable import ZislaKit

struct CodexSessionActivityDetectorTests {
    @Test
    func detectsUnpairedTaskStartedAsRunningCodexTask() throws {
        let root = makeSessionsRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        try writeRollout(
            under: root,
            relativePath: "2026/07/19/rollout-active.jsonl",
            lines: [
                eventLine(timestamp: "2026-07-19T01:00:00.000Z", payloadType: "task_started", turnID: "turn-active"),
            ],
            modifiedAt: Date(timeIntervalSince1970: 1_800_000_100)
        )

        let detector = CodexSessionActivityDetector(sessionsDirectory: root)
        let tasks = try detector.activeTasks()

        #expect(tasks.count == 1)
        let task = try #require(tasks.first)
        #expect(task.id == CodexSessionActivityDetector.taskID(forTurnID: "turn-active"))
        #expect(task.provider == .codex)
        #expect(task.status == .running)
        #expect(task.progress == nil)
        #expect(task.title == "Codex")
        #expect(task.sessionURL == nil)
        #expect(task.effort == nil)
        #expect(task.startedAt == iso8601Date("2026-07-19T01:00:00.000Z"))
        #expect(task.updatedAt == Date(timeIntervalSince1970: 1_800_000_100))
    }

    @Test
    func pendingUserInputRemainsARunningTask() throws {
        let root = makeSessionsRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let relativePath = "2026/07/19/rollout-question.jsonl"
        try writeRollout(
            under: root,
            relativePath: relativePath,
            lines: [
                eventLine(timestamp: "2026-07-19T01:00:00.000Z", payloadType: "task_started", turnID: "turn-question"),
                try responseItemLine(
                    timestamp: "2026-07-19T01:00:01.000Z",
                    turnID: "turn-question",
                    payload: [
                        "type": "function_call",
                        "name": "request_user_input",
                        "call_id": "call-question",
                    ]
                ),
            ],
            modifiedAt: Date(timeIntervalSince1970: 1_800_000_110)
        )
        let detector = CodexSessionActivityDetector(sessionsDirectory: root)

        #expect(try detector.activeTasks().first?.status == .running)
    }

    @Test
    func failedToolOutputTurnsRedUntilASuccessfulOutputArrives() throws {
        let root = makeSessionsRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let relativePath = "2026/07/19/rollout-error.jsonl"
        try writeRollout(
            under: root,
            relativePath: relativePath,
            lines: [
                eventLine(timestamp: "2026-07-19T01:00:00.000Z", payloadType: "task_started", turnID: "turn-error"),
                try responseItemLine(
                    timestamp: "2026-07-19T01:00:01.000Z",
                    turnID: "turn-error",
                    payload: [
                        "type": "custom_tool_call_output",
                        "call_id": "call-error",
                        "output": [[
                            "type": "input_text",
                            "text": #"{"exit_code":1,"output":"failed"}"#,
                        ]],
                    ]
                ),
            ],
            modifiedAt: Date(timeIntervalSince1970: 1_800_000_130)
        )
        let detector = CodexSessionActivityDetector(sessionsDirectory: root)

        let task = try #require(detector.activeTasks().first)
        #expect(task.status == .error)
        #expect(task.failureReason == "failed")

        try appendLine(
            try responseItemLine(
                timestamp: "2026-07-19T01:00:02.000Z",
                turnID: "turn-error",
                payload: [
                    "type": "custom_tool_call_output",
                    "call_id": "call-recovery",
                    "output": [[
                        "type": "input_text",
                        "text": #"{"exit_code":0,"output":"ok"}"#,
                    ]],
                ]
            ),
            to: root.appendingPathComponent(relativePath)
        )

        let recovered = try #require(detector.activeTasks().first)
        #expect(recovered.status == .running)
        #expect(recovered.failureReason == nil)
    }

    @Test
    func mapsSessionTitleAndDeepLinkFromSessionIndex() throws {
        let root = makeSessionsRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let sessionIndexURL = root.appendingPathComponent("session_index.jsonl")

        try writeRollout(
            under: root,
            relativePath: "2026/07/19/rollout-session.jsonl",
            lines: [
                sessionMetadataLine(sessionID: "session-123"),
                turnContextLine(
                    timestamp: "2026-07-19T01:00:00.000Z",
                    turnID: "turn-session",
                    model: "gpt-5.6-sol",
                    effort: "xhigh"
                ),
                eventLine(
                    timestamp: "2026-07-19T01:00:01.000Z",
                    payloadType: "task_started",
                    turnID: "turn-session"
                ),
            ],
            modifiedAt: Date(timeIntervalSince1970: 1_800_000_125)
        )
        try writeSessionIndex(
            to: sessionIndexURL,
            entries: [.init(id: "session-123", threadName: "修复任务会话跳转")]
        )

        let task = try #require(CodexSessionActivityDetector(
            sessionsDirectory: root,
            sessionIndexURL: sessionIndexURL
        ).activeTasks().first)

        #expect(task.title == "修复任务会话跳转")
        #expect(task.sessionURL?.absoluteString == "codex://threads/session-123")
        #expect(task.effort == "xhigh")
        #expect(task.startedAt == iso8601Date("2026-07-19T01:00:01.000Z"))
    }

    @Test
    func blankSessionTitleFallsBackToProviderName() throws {
        let root = makeSessionsRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let sessionIndexURL = root.appendingPathComponent("session_index.jsonl")

        try writeRollout(
            under: root,
            relativePath: "2026/07/19/rollout-blank-title.jsonl",
            lines: [
                sessionMetadataLine(sessionID: "session-blank"),
                turnContextLine(
                    timestamp: "2026-07-19T01:00:00.000Z",
                    turnID: "turn-blank",
                    model: "gpt-5.6-sol"
                ),
                eventLine(
                    timestamp: "2026-07-19T01:00:01.000Z",
                    payloadType: "task_started",
                    turnID: "turn-blank"
                ),
            ],
            modifiedAt: Date(timeIntervalSince1970: 1_800_000_130)
        )
        try writeSessionIndex(
            to: sessionIndexURL,
            entries: [.init(id: "session-blank", threadName: "  \n ")]
        )

        let task = try #require(CodexSessionActivityDetector(
            sessionsDirectory: root,
            sessionIndexURL: sessionIndexURL
        ).activeTasks().first)

        #expect(task.title == "ChatGPT")
        #expect(task.sessionURL?.absoluteString == "codex://threads/session-blank")
    }

    @Test
    func missingSessionIndexFallsBackWithoutDroppingActiveTask() throws {
        let root = makeSessionsRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        try writeRollout(
            under: root,
            relativePath: "2026/07/19/rollout-missing-index.jsonl",
            lines: [
                sessionMetadataLine(sessionID: "session-without-index"),
                eventLine(
                    timestamp: "2026-07-19T01:00:01.000Z",
                    payloadType: "task_started",
                    turnID: "turn-without-index"
                ),
            ],
            modifiedAt: Date(timeIntervalSince1970: 1_800_000_135)
        )

        let tasks = try CodexSessionActivityDetector(
            sessionsDirectory: root,
            sessionIndexURL: root.appendingPathComponent("missing-session-index.jsonl")
        ).activeTasks()
        let task = try #require(tasks.first)

        #expect(tasks.count == 1)
        #expect(task.title == "Codex")
        #expect(task.sessionURL?.absoluteString == "codex://threads/session-without-index")
    }

    @Test
    func mapsTurnModelToChatGPTOrCodexIdentity() throws {
        let root = makeSessionsRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        try writeRollout(
            under: root,
            relativePath: "2026/07/19/rollout-models.jsonl",
            lines: [
                turnContextLine(
                    timestamp: "2026-07-19T01:00:00.000Z",
                    turnID: "turn-gpt",
                    model: "gpt-5.6-sol",
                    effort: "medium"
                ),
                eventLine(
                    timestamp: "2026-07-19T01:00:01.000Z",
                    payloadType: "task_started",
                    turnID: "turn-gpt"
                ),
                eventLine(
                    timestamp: "2026-07-19T01:00:02.000Z",
                    payloadType: "task_started",
                    turnID: "turn-codex"
                ),
                turnContextLine(
                    timestamp: "2026-07-19T01:00:03.000Z",
                    turnID: "turn-codex",
                    model: "gpt-5.2-codex"
                ),
            ],
            modifiedAt: Date(timeIntervalSince1970: 1_800_000_150)
        )

        let tasks = try CodexSessionActivityDetector(sessionsDirectory: root).activeTasks()
        let byID = Dictionary(uniqueKeysWithValues: tasks.map { ($0.id, $0) })
        let gpt = try #require(byID[CodexSessionActivityDetector.taskID(forTurnID: "turn-gpt")])
        let codex = try #require(byID[CodexSessionActivityDetector.taskID(forTurnID: "turn-codex")])

        #expect(gpt.provider == .gpt)
        #expect(gpt.title == "ChatGPT")
        #expect(gpt.detail == "gpt-5.6-sol")
        #expect(gpt.effort == "medium")
        #expect(gpt.startedAt == iso8601Date("2026-07-19T01:00:01.000Z"))
        #expect(codex.provider == .codex)
        #expect(codex.title == "Codex")
        #expect(codex.detail == "gpt-5.2-codex")
        #expect(codex.effort == nil)
        #expect(codex.startedAt == iso8601Date("2026-07-19T01:00:02.000Z"))
    }

    @Test
    func completedAndAbortedTurnsAreNotReturned() throws {
        let root = makeSessionsRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        try writeRollout(
            under: root,
            relativePath: "2026/07/19/rollout-mixed.jsonl",
            lines: [
                eventLine(timestamp: "2026-07-19T01:00:00.000Z", payloadType: "task_started", turnID: "turn-done"),
                eventLine(timestamp: "2026-07-19T01:01:00.000Z", payloadType: "task_complete", turnID: "turn-done"),
                eventLine(timestamp: "2026-07-19T01:02:00.000Z", payloadType: "task_started", turnID: "turn-abort"),
                eventLine(timestamp: "2026-07-19T01:03:00.000Z", payloadType: "turn_aborted", turnID: "turn-abort"),
                eventLine(timestamp: "2026-07-19T01:04:00.000Z", payloadType: "task_started", turnID: "turn-live"),
            ],
            modifiedAt: Date(timeIntervalSince1970: 1_800_000_200)
        )

        let detector = CodexSessionActivityDetector(sessionsDirectory: root)
        let tasks = try detector.activeTasks()

        #expect(tasks.map(\.id) == [CodexSessionActivityDetector.taskID(forTurnID: "turn-live")])
    }

    @Test
    func ignoresCorruptLinesAndDedupesSameTurn() throws {
        let root = makeSessionsRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        try writeRollout(
            under: root,
            relativePath: "2026/07/19/rollout-noisy.jsonl",
            lines: [
                "{not-json",
                eventLine(timestamp: "2026-07-19T01:00:00.000Z", payloadType: "task_started", turnID: "turn-dup"),
                #"{"timestamp":"2026-07-19T01:00:01.000Z","type":"event_msg","payload":{"type":"task_started"}}"#,
                eventLine(timestamp: "2026-07-19T01:00:02.000Z", payloadType: "task_started", turnID: "turn-dup"),
                #"{"timestamp":"2026-07-19T01:00:03.000Z","type":"response_item","payload":{"type":"message"}}"#,
            ],
            modifiedAt: Date(timeIntervalSince1970: 1_800_000_300)
        )

        let detector = CodexSessionActivityDetector(sessionsDirectory: root)
        let tasks = try detector.activeTasks()

        #expect(tasks.count == 1)
        #expect(tasks[0].id == CodexSessionActivityDetector.taskID(forTurnID: "turn-dup"))
        #expect(tasks[0].updatedAt == Date(timeIntervalSince1970: 1_800_000_300))
    }

    @Test
    func scansOnlyRecentlyModifiedRolloutsWithinLimit() throws {
        let root = makeSessionsRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        try writeRollout(
            under: root,
            relativePath: "2026/07/18/rollout-old.jsonl",
            lines: [
                eventLine(timestamp: "2026-07-18T01:00:00.000Z", payloadType: "task_started", turnID: "turn-old"),
            ],
            modifiedAt: Date(timeIntervalSince1970: 1_800_000_001)
        )
        try writeRollout(
            under: root,
            relativePath: "2026/07/19/rollout-new.jsonl",
            lines: [
                eventLine(timestamp: "2026-07-19T02:00:00.000Z", payloadType: "task_started", turnID: "turn-new"),
            ],
            modifiedAt: Date(timeIntervalSince1970: 1_800_000_900)
        )
        try writeRollout(
            under: root,
            relativePath: "2026/07/19/notes.txt",
            lines: [
                eventLine(timestamp: "2026-07-19T03:00:00.000Z", payloadType: "task_started", turnID: "turn-ignored-ext"),
            ],
            modifiedAt: Date(timeIntervalSince1970: 1_800_000_950)
        )

        let detector = CodexSessionActivityDetector(
            sessionsDirectory: root,
            maxRolloutFiles: 1
        )
        let tasks = try detector.activeTasks()

        #expect(tasks.map(\.id) == [CodexSessionActivityDetector.taskID(forTurnID: "turn-new")])
    }

    @Test
    func ignoresRolloutsWithoutRecentWrites() throws {
        let root = makeSessionsRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let now = iso8601Date("2026-08-07T12:00:00.000Z")
        try writeRollout(
            under: root,
            relativePath: "2026/06/01/rollout-old.jsonl",
            lines: [
                eventLine(timestamp: "2026-06-01T01:00:00.000Z", payloadType: "task_started", turnID: "turn-old"),
            ],
            modifiedAt: now.addingTimeInterval(-31 * 24 * 60 * 60)
        )
        try writeRollout(
            under: root,
            relativePath: "2026/08/07/rollout-recent.jsonl",
            lines: [
                eventLine(timestamp: "2026-08-07T01:00:00.000Z", payloadType: "task_started", turnID: "turn-recent"),
            ],
            modifiedAt: now.addingTimeInterval(-24 * 60 * 60)
        )

        let tasks = try CodexSessionActivityDetector(
            sessionsDirectory: root,
            now: { now }
        ).activeTasks()

        #expect(tasks.map(\.id) == [CodexSessionActivityDetector.taskID(forTurnID: "turn-recent")])
    }

    @Test
    func pairsCompletionAcrossRecentlyScannedFiles() throws {
        let root = makeSessionsRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        try writeRollout(
            under: root,
            relativePath: "2026/07/19/rollout-a.jsonl",
            lines: [
                eventLine(timestamp: "2026-07-19T01:00:00.000Z", payloadType: "task_started", turnID: "turn-cross"),
            ],
            modifiedAt: Date(timeIntervalSince1970: 1_800_000_500)
        )
        try writeRollout(
            under: root,
            relativePath: "2026/07/19/rollout-b.jsonl",
            lines: [
                eventLine(timestamp: "2026-07-19T01:05:00.000Z", payloadType: "task_complete", turnID: "turn-cross"),
                eventLine(timestamp: "2026-07-19T01:06:00.000Z", payloadType: "task_started", turnID: "turn-still-open"),
            ],
            modifiedAt: Date(timeIntervalSince1970: 1_800_000_600)
        )

        let detector = CodexSessionActivityDetector(sessionsDirectory: root, maxRolloutFiles: 8)
        let tasks = try detector.activeTasks()

        #expect(tasks.map(\.id) == [CodexSessionActivityDetector.taskID(forTurnID: "turn-still-open")])
    }

    @Test
    func missingSessionsDirectoryYieldsEmptyResult() throws {
        let missing = FileManager.default.temporaryDirectory
            .appendingPathComponent("Zisla-codex-missing-\(UUID().uuidString)", isDirectory: true)
        let detector = CodexSessionActivityDetector(sessionsDirectory: missing)
        let tasks = try detector.activeTasks()
        #expect(tasks.isEmpty)
    }

    @Test
    func taskIdentifiersAreStableAcrossCalls() throws {
        let root = makeSessionsRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        try writeRollout(
            under: root,
            relativePath: "2026/07/19/rollout-stable.jsonl",
            lines: [
                eventLine(timestamp: "2026-07-19T04:00:00.000Z", payloadType: "task_started", turnID: "turn-stable"),
            ],
            modifiedAt: Date(timeIntervalSince1970: 1_800_001_000)
        )

        let detector = CodexSessionActivityDetector(sessionsDirectory: root)
        let first = try detector.activeTasks()
        let second = try detector.activeTasks()
        #expect(first.map(\.id) == second.map(\.id))
        #expect(first.first?.id == "codex-turn-turn-stable")
    }

    @Test
    func coldStartIgnoresLifecycleEventsOutsideTheBoundedTail() throws {
        let root = makeSessionsRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let filler = (0..<80).map { index in
            #"{"timestamp":"2026-07-19T01:00:01.000Z","type":"ignored","index":\#(index)}"#
        }
        try writeRollout(
            under: root,
            relativePath: "2026/07/19/rollout-bounded.jsonl",
            lines: [
                eventLine(
                    timestamp: "2026-07-19T01:00:00.000Z",
                    payloadType: "task_started",
                    turnID: "turn-outside-tail"
                ),
            ] + filler,
            modifiedAt: Date(timeIntervalSince1970: 1_800_001_200)
        )

        let tasks = try CodexSessionActivityDetector(
            sessionsDirectory: root,
            initialTailBytes: 256
        ).activeTasks()

        #expect(tasks.isEmpty)
    }
}

    @Test
    func vscodeSessionMetaSourceStillDetected() throws {
        let root = makeSessionsRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        try writeRollout(
            under: root,
            relativePath: "2026/07/19/rollout-vscode.jsonl",
            lines: [
                #"{"type":"session_meta","payload":{"id":"session-vscode","source":"vscode"}}"#,
                eventLine(timestamp: "2026-07-19T01:00:00.000Z", payloadType: "task_started", turnID: "turn-vscode"),
            ],
            modifiedAt: Date(timeIntervalSince1970: 1_800_001_100)
        )

        let tasks = try CodexSessionActivityDetector(sessionsDirectory: root).activeTasks()
        #expect(tasks.count == 1)
        #expect(tasks[0].id == CodexSessionActivityDetector.taskID(forTurnID: "turn-vscode"))
        #expect(tasks[0].status == .running)
        #expect(tasks[0].sessionURL?.absoluteString == "codex://threads/session-vscode")
    }

    @Test
    func detectsEveryActiveTurnAcrossMoreThanTheFormerRolloutLimit() throws {
        let root = makeSessionsRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        for index in 0..<13 {
            try writeRollout(
                under: root,
                relativePath: "2026/07/19/rollout-concurrent-\(index).jsonl",
                lines: [
                    eventLine(
                        timestamp: "2026-07-19T01:00:00.000Z",
                        payloadType: "task_started",
                        turnID: "turn-concurrent-\(index)"
                    ),
                ],
                modifiedAt: Date(timeIntervalSince1970: 1_800_002_000 + Double(index))
            )
        }

        let tasks = try CodexSessionActivityDetector(sessionsDirectory: root).activeTasks()

        #expect(Set(tasks.map(\.id)) == Set((0..<13).map {
            CodexSessionActivityDetector.taskID(forTurnID: "turn-concurrent-\($0)")
        }))
    }

    @Test
    func detectsLongRunningTurnWhoseStartPrecedesTheFormerTailLimit() throws {
        let root = makeSessionsRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let filler = String(repeating: "x", count: 4_096)
        let lines = [
            eventLine(
                timestamp: "2026-07-19T01:00:00.000Z",
                payloadType: "task_started",
                turnID: "turn-long-running"
            ),
        ] + (0..<300).map { index in
            #"{"timestamp":"2026-07-19T01:00:01.000Z","type":"ignored","index":\#(index),"text":"\#(filler)"}"#
        }
        try writeRollout(
            under: root,
            relativePath: "2026/07/19/rollout-long-running.jsonl",
            lines: lines,
            modifiedAt: Date(timeIntervalSince1970: 1_800_002_100)
        )

        let tasks = try CodexSessionActivityDetector(sessionsDirectory: root).activeTasks()

        #expect(tasks.map(\.id) == [CodexSessionActivityDetector.taskID(forTurnID: "turn-long-running")])
    }

    @Test
    func detectsLongRunningTurnAfterManyCompletedLifecycleEvents() throws {
        let root = makeSessionsRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let completedLines = (0..<300).flatMap { index in
            [
                eventLine(
                    timestamp: "2026-07-19T01:00:01.000Z",
                    payloadType: "task_started",
                    turnID: "turn-completed-\(index)"
                ),
                eventLine(
                    timestamp: "2026-07-19T01:00:02.000Z",
                    payloadType: "task_complete",
                    turnID: "turn-completed-\(index)"
                ),
            ]
        }
        try writeRollout(
            under: root,
            relativePath: "2026/07/19/rollout-many-lifecycle-events.jsonl",
            lines: [
                eventLine(
                    timestamp: "2026-07-19T01:00:00.000Z",
                    payloadType: "task_started",
                    turnID: "turn-still-running"
                ),
            ] + completedLines,
            modifiedAt: Date(timeIntervalSince1970: 1_800_002_150)
        )
        let detector = CodexSessionActivityDetector(sessionsDirectory: root)

        #expect(try detector.activeTasks().map(\.id) == [
            CodexSessionActivityDetector.taskID(forTurnID: "turn-still-running"),
        ])
        #expect(try detector.activeTasks().map(\.id) == [
            CodexSessionActivityDetector.taskID(forTurnID: "turn-still-running"),
        ])
    }

    @Test
    func turnContextInDifferentFileStillMapsProviderCorrectly() throws {
        let root = makeSessionsRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        try writeRollout(
            under: root,
            relativePath: "2026/07/19/rollout-context.jsonl",
            lines: [
                turnContextLine(
                    timestamp: "2026-07-19T01:00:00.000Z",
                    turnID: "turn-gpt-split",
                    model: "gpt-5.6-sol",
                    effort: "high"
                ),
            ],
            modifiedAt: Date(timeIntervalSince1970: 1_800_001_200)
        )
        try writeRollout(
            under: root,
            relativePath: "2026/07/19/rollout-event.jsonl",
            lines: [
                eventLine(
                    timestamp: "2026-07-19T01:00:01.000Z",
                    payloadType: "task_started",
                    turnID: "turn-gpt-split"
                ),
            ],
            modifiedAt: Date(timeIntervalSince1970: 1_800_001_250)
        )

        let tasks = try CodexSessionActivityDetector(sessionsDirectory: root).activeTasks()
        let task = try #require(tasks.first)

        #expect(tasks.count == 1)
        #expect(task.id == CodexSessionActivityDetector.taskID(forTurnID: "turn-gpt-split"))
        #expect(task.provider == .gpt)
        #expect(task.title == "ChatGPT")
        #expect(task.detail == "gpt-5.6-sol")
        #expect(task.effort == "high")
        #expect(task.status == .running)
    }

    @Test
    func extractsAndTruncatesFailureReasonFromToolOutput() throws {
        let root = makeSessionsRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let longMessage = String(repeating: "error ", count: 50)
        try writeRollout(
            under: root,
            relativePath: "2026/07/19/rollout-reason.jsonl",
            lines: [
                eventLine(timestamp: "2026-07-19T01:00:00.000Z", payloadType: "task_started", turnID: "turn-reason"),
                try responseItemLine(
                    timestamp: "2026-07-19T01:00:01.000Z",
                    turnID: "turn-reason",
                    payload: [
                        "type": "function_call_output",
                        "call_id": "call-reason",
                        "output": [[
                            "type": "input_text",
                            "text": #"{"exit_code":1,"output":"\#(longMessage)"}"#,
                        ]],
                    ]
                ),
            ],
            modifiedAt: Date(timeIntervalSince1970: 1_800_000_140)
        )

        let task = try #require(CodexSessionActivityDetector(sessionsDirectory: root).activeTasks().first)
        #expect(task.status == .error)
        #expect(task.failureReason != nil)
        #expect((task.failureReason?.count ?? 0) <= 201)
        #expect(task.failureReason?.hasSuffix("…") == true)
    }

    @Test
    func normalizesWhitespaceInFailureReason() throws {
        let root = makeSessionsRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        try writeRollout(
            under: root,
            relativePath: "2026/07/19/rollout-whitespace.jsonl",
            lines: [
                eventLine(timestamp: "2026-07-19T01:00:00.000Z", payloadType: "task_started", turnID: "turn-ws"),
                try responseItemLine(
                    timestamp: "2026-07-19T01:00:01.000Z",
                    turnID: "turn-ws",
                    payload: [
                        "type": "custom_tool_call_output",
                        "call_id": "call-ws",
                        "output": [[
                            "type": "input_text",
                            "text": #"{"exit_code":1,"output":"build  failed\n\ndue   to\tsyntax error"}"#,
                        ]],
                    ]
                ),
            ],
            modifiedAt: Date(timeIntervalSince1970: 1_800_000_145)
        )

        let task = try #require(CodexSessionActivityDetector(sessionsDirectory: root).activeTasks().first)
        #expect(task.status == .error)
        #expect(task.failureReason == "build failed due to syntax error")
    }


// MARK: - Fixtures

private func makeSessionsRoot() -> URL {
    FileManager.default.temporaryDirectory
        .appendingPathComponent("Zisla-codex-sessions-\(UUID().uuidString)", isDirectory: true)
}

private func writeRollout(
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
    let body = lines.joined(separator: "\n") + "\n"
    try Data(body.utf8).write(to: url)
    try FileManager.default.setAttributes(
        [.modificationDate: modifiedAt],
        ofItemAtPath: url.path
    )
}

private func eventLine(timestamp: String, payloadType: String, turnID: String) -> String {
    """
    {"timestamp":"\(timestamp)","type":"event_msg","payload":{"type":"\(payloadType)","turn_id":"\(turnID)"}}
    """
}

private func responseItemLine(
    timestamp: String,
    turnID: String? = nil,
    payload: [String: Any]
) throws -> String {
    var payload = payload
    if let turnID {
        payload["internal_chat_message_metadata_passthrough"] = ["turn_id": turnID]
    }
    let root: [String: Any] = [
        "timestamp": timestamp,
        "type": "response_item",
        "payload": payload,
    ]
    let data = try JSONSerialization.data(withJSONObject: root, options: [.sortedKeys])
    return String(decoding: data, as: UTF8.self)
}

private func appendLine(_ line: String, to url: URL) throws {
    let handle = try FileHandle(forWritingTo: url)
    defer { try? handle.close() }
    try handle.seekToEnd()
    try handle.write(contentsOf: Data((line + "\n").utf8))
}

private func turnContextLine(
    timestamp: String,
    turnID: String,
    model: String,
    effort: String? = nil
) -> String {
    let effortField = effort.map { ",\"effort\":\"\($0)\"" } ?? ""
    return """
    {"timestamp":"\(timestamp)","type":"turn_context","payload":{"turn_id":"\(turnID)","model":"\(model)"\(effortField)}}
    """
}

private func sessionMetadataLine(sessionID: String) -> String {
    """
    {"type":"session_meta","payload":{"id":"\(sessionID)"}}
    """
}

private struct SessionIndexFixture: Encodable {
    var id: String
    var threadName: String

    private enum CodingKeys: String, CodingKey {
        case id
        case threadName = "thread_name"
    }
}

private func writeSessionIndex(to url: URL, entries: [SessionIndexFixture]) throws {
    let encoder = JSONEncoder()
    let lines = try entries.map { entry in
        String(decoding: try encoder.encode(entry), as: UTF8.self)
    }
    try Data((lines.joined(separator: "\n") + "\n").utf8).write(to: url)
}

private func iso8601Date(_ value: String) -> Date {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return formatter.date(from: value) ?? .distantPast
}
