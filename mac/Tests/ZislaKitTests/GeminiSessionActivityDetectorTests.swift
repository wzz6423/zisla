import Foundation
import Testing
@testable import ZislaCore
@testable import ZislaKit

struct GeminiSessionActivityDetectorTests {
    @Test
    func detectsUserTurnAsRunning() throws {
        let root = makeGeminiTempRoot("running")
        defer { try? FileManager.default.removeItem(at: root) }

        try writeGeminiJSONL(
            under: root,
            relativePath: "project/chats/session-running.jsonl",
            lines: [
                #"{"sessionId":"gem-1","startTime":"2026-07-19T01:00:00.000Z","kind":"main"}"#,
                #"{"id":"user-1","type":"user","timestamp":"2026-07-19T01:00:01.000Z","content":"hello"}"#,
            ]
        )

        let task = try #require(GeminiSessionActivityDetector(
            sessionsRoot: root
        ).activeTasks().first)
        #expect(task.id == GeminiSessionActivityDetector.taskID(forSessionID: "gem-1"))
        #expect(task.provider == .gemini)
        #expect(task.title == "Gemini")
        #expect(task.status == .running)
    }

    @Test
    func awaitingApprovalBlocksAndExecutingResumes() throws {
        let root = makeGeminiTempRoot("blocked")
        defer { try? FileManager.default.removeItem(at: root) }
        let url = try writeGeminiJSONL(
            under: root,
            relativePath: "project/chats/session-blocked.jsonl",
            lines: [
                #"{"sessionId":"gem-2","startTime":"2026-07-19T01:00:00.000Z"}"#,
                #"{"id":"user-1","type":"user","timestamp":"2026-07-19T01:00:01.000Z","content":"run"}"#,
                #"{"id":"model-1","type":"gemini","timestamp":"2026-07-19T01:00:02.000Z","model":"gemini-2.5-pro","content":"","toolCalls":[{"id":"call-1","name":"run_shell","status":"awaiting_approval"}]}"#,
            ]
        )
        let detector = GeminiSessionActivityDetector(sessionsRoot: root)
        #expect(try detector.activeTasks().first?.status == .blocked)

        try appendGeminiJSONLLine(
            #"{"id":"model-1","type":"gemini","timestamp":"2026-07-19T01:00:03.000Z","model":"gemini-2.5-pro","content":"","toolCalls":[{"id":"call-1","name":"run_shell","status":"executing"}]}"#,
            to: url
        )
        let task = try #require(detector.activeTasks().first)
        #expect(task.status == .running)
        #expect(task.detail == "gemini-2.5-pro")
    }

    @Test
    func toolErrorIsRedAndLaterSuccessRecovers() throws {
        let root = makeGeminiTempRoot("error")
        defer { try? FileManager.default.removeItem(at: root) }
        let url = try writeGeminiJSONL(
            under: root,
            relativePath: "project/chats/session-error.jsonl",
            lines: [
                #"{"sessionId":"gem-3","startTime":"2026-07-19T01:00:00.000Z"}"#,
                #"{"id":"user-1","type":"user","timestamp":"2026-07-19T01:00:01.000Z","content":"run"}"#,
                #"{"id":"model-1","type":"gemini","timestamp":"2026-07-19T01:00:02.000Z","content":"","toolCalls":[{"id":"call-1","status":"error"}]}"#,
            ]
        )
        let detector = GeminiSessionActivityDetector(sessionsRoot: root)
        #expect(try detector.activeTasks().first?.status == .error)

        try appendGeminiJSONLLine(
            #"{"id":"model-1","type":"gemini","timestamp":"2026-07-19T01:00:03.000Z","content":"","toolCalls":[{"id":"call-1","status":"success"}]}"#,
            to: url
        )
        #expect(try detector.activeTasks().first?.status == .running)
    }

    @Test
    func finalGeminiMessageCompletesTurn() throws {
        let root = makeGeminiTempRoot("complete")
        defer { try? FileManager.default.removeItem(at: root) }

        try writeGeminiJSONL(
            under: root,
            relativePath: "project/chats/session-complete.jsonl",
            lines: [
                #"{"sessionId":"gem-4","startTime":"2026-07-19T01:00:00.000Z"}"#,
                #"{"id":"user-1","type":"user","timestamp":"2026-07-19T01:00:01.000Z","content":"hello"}"#,
                #"{"id":"model-1","type":"gemini","timestamp":"2026-07-19T01:00:02.000Z","content":"done","model":"gemini-2.5-flash"}"#,
            ]
        )

        #expect(try GeminiSessionActivityDetector(sessionsRoot: root).activeTasks().isEmpty)
    }

    @Test
    func supportsLegacyJSONAndExplicitErrorMessages() throws {
        let root = makeGeminiTempRoot("legacy")
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("project/chats/session-legacy.json")
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let object: [String: Any] = [
            "sessionId": "gem-legacy",
            "startTime": "2026-07-19T01:00:00.000Z",
            "messages": [
                [
                    "id": "user-1",
                    "type": "user",
                    "timestamp": "2026-07-19T01:00:01.000Z",
                    "content": "hello",
                ],
                [
                    "id": "error-1",
                    "type": "error",
                    "timestamp": "2026-07-19T01:00:02.000Z",
                    "content": "request failed",
                ],
            ],
        ]
        try JSONSerialization.data(withJSONObject: object).write(to: url)

        let task = try #require(GeminiSessionActivityDetector(
            sessionsRoot: root
        ).activeTasks().first)
        #expect(task.id == GeminiSessionActivityDetector.taskID(forSessionID: "gem-legacy"))
        #expect(task.status == .error)
    }

    @Test
    func ignoresCorruptLinesPartialTailAndMissingDirectory() throws {
        let root = makeGeminiTempRoot("noisy")
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("project/chats/session-noisy.jsonl")
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let body = [
            #"{"sessionId":"gem-noisy","startTime":"2026-07-19T01:00:00.000Z"}"#,
            "{bad",
            #"{"id":"user-1","type":"user","timestamp":"2026-07-19T01:00:01.000Z","content":"hello"}"#,
            #"{"id":"partial""#,
        ].joined(separator: "\n")
        try Data(body.utf8).write(to: url)

        let tasks = try GeminiSessionActivityDetector(sessionsRoot: root).activeTasks()
        #expect(tasks.count == 1)
        #expect(tasks[0].status == .running)

        let missing = FileManager.default.temporaryDirectory
            .appendingPathComponent("Zisla-gemini-missing-\(UUID().uuidString)")
        #expect(try GeminiSessionActivityDetector(sessionsRoot: missing).activeTasks().isEmpty)
    }

    @Test
    func coldStartIgnoresStateOutsideTheBoundedTail() throws {
        let root = makeGeminiTempRoot("bounded-tail")
        defer { try? FileManager.default.removeItem(at: root) }
        let padding = String(repeating: "x", count: 1_100_000)

        try writeGeminiJSONL(
            under: root,
            relativePath: "project/chats/session-old.jsonl",
            lines: [
                #"{"sessionId":"gem-old","type":"user","timestamp":"2026-07-19T01:00:00.000Z"}"#,
                #"{"type":"metadata","padding":""# + padding + #""}"#,
            ]
        )

        #expect(try GeminiSessionActivityDetector(sessionsRoot: root).activeTasks().isEmpty)
    }
}

private func makeGeminiTempRoot(_ label: String) -> URL {
    FileManager.default.temporaryDirectory
        .appendingPathComponent("Zisla-gemini-\(label)-\(UUID().uuidString)", isDirectory: true)
}

@discardableResult
private func writeGeminiJSONL(
    under root: URL,
    relativePath: String,
    lines: [String]
) throws -> URL {
    let url = root.appendingPathComponent(relativePath)
    try FileManager.default.createDirectory(
        at: url.deletingLastPathComponent(),
        withIntermediateDirectories: true
    )
    try Data((lines.joined(separator: "\n") + "\n").utf8).write(to: url)
    return url
}

private func appendGeminiJSONLLine(_ line: String, to url: URL) throws {
    let handle = try FileHandle(forWritingTo: url)
    defer { try? handle.close() }
    try handle.seekToEnd()
    try handle.write(contentsOf: Data((line + "\n").utf8))
}
