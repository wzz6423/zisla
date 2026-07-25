import Foundation
import Testing
@testable import ZislaCore
@testable import ZislaKit

struct GrokSessionActivityDetectorTests {
    @Test
    func testDetectsTurnStartedAsRunning() throws {
        let root = makeTempRoot("grok-running")
        defer { try? FileManager.default.removeItem(at: root) }

        try writeJSONL(
            under: root,
            relativePath: "abc123/events.jsonl",
            lines: [
                #"{"type":"turn_started","ts":"2026-07-19T01:00:00.000Z"}"#,
            ],
            modifiedAt: Date(timeIntervalSince1970: 1_910_000_100)
        )

        let tasks = try GrokSessionActivityDetector(sessionsDirectory: root).activeTasks()
        #expect(tasks.count == 1)
        let task = try #require(tasks.first)
        #expect(task.id == GrokSessionActivityDetector.taskID(forSessionID: "abc123"))
        #expect(task.provider == .grok)
        #expect(task.title == "Grok")
        #expect(task.status == .running)
    }

    @Test
    func testPermissionRequestedBlocksUntilResolvedWithAndWithoutRequestID() throws {
        let root = makeTempRoot("grok-blocked")
        defer { try? FileManager.default.removeItem(at: root) }
        let relative = "sess-p/events.jsonl"

        try writeJSONL(
            under: root,
            relativePath: relative,
            lines: [
                #"{"type":"turn_started","ts":"2026-07-19T01:00:00.000Z"}"#,
                #"{"type":"permission_requested","ts":"2026-07-19T01:00:01.000Z","request_id":"r1"}"#,
            ],
            modifiedAt: Date(timeIntervalSince1970: 1_910_000_110)
        )
        let detector = GrokSessionActivityDetector(sessionsDirectory: root)
        #expect(try detector.activeTasks().first?.status == .blocked)

        try appendJSONLLine(
            #"{"type":"permission_resolved","ts":"2026-07-19T01:00:02.000Z","request_id":"r1"}"#,
            to: root.appendingPathComponent(relative)
        )
        #expect(try detector.activeTasks().first?.status == .running)

        try appendJSONLLine(
            #"{"type":"permission_requested","ts":"2026-07-19T01:00:03.000Z"}"#,
            to: root.appendingPathComponent(relative)
        )
        #expect(try detector.activeTasks().first?.status == .blocked)

        try appendJSONLLine(
            #"{"type":"permission_resolved","ts":"2026-07-19T01:00:04.000Z"}"#,
            to: root.appendingPathComponent(relative)
        )
        #expect(try detector.activeTasks().first?.status == .running)
    }

    @Test
    func testToolCompletedErrorThenSuccessRecovers() throws {
        let root = makeTempRoot("grok-error")
        defer { try? FileManager.default.removeItem(at: root) }
        let relative = "sess-e/events.jsonl"

        try writeJSONL(
            under: root,
            relativePath: relative,
            lines: [
                #"{"type":"turn_started","ts":"2026-07-19T01:00:00.000Z"}"#,
                #"{"type":"tool_completed","ts":"2026-07-19T01:00:01.000Z","outcome":"error"}"#,
            ],
            modifiedAt: Date(timeIntervalSince1970: 1_910_000_120)
        )
        let detector = GrokSessionActivityDetector(sessionsDirectory: root)
        #expect(try detector.activeTasks().first?.status == .error)

        try appendJSONLLine(
            #"{"type":"tool_completed","ts":"2026-07-19T01:00:02.000Z","outcome":"success"}"#,
            to: root.appendingPathComponent(relative)
        )
        #expect(try detector.activeTasks().first?.status == .running)
    }

    @Test
    func testTurnEndedCompletedClearsTaskAndErrorOutcomeKeepsErrorUntilNextStart() throws {
        let root = makeTempRoot("grok-complete")
        defer { try? FileManager.default.removeItem(at: root) }
        let relative = "sess-c/events.jsonl"

        try writeJSONL(
            under: root,
            relativePath: relative,
            lines: [
                #"{"type":"turn_started","ts":"2026-07-19T01:00:00.000Z"}"#,
                #"{"type":"turn_ended","ts":"2026-07-19T01:00:05.000Z","outcome":"completed"}"#,
            ],
            modifiedAt: Date(timeIntervalSince1970: 1_910_000_130)
        )
        let detector = GrokSessionActivityDetector(sessionsDirectory: root)
        #expect(try detector.activeTasks().isEmpty)

        try writeJSONL(
            under: root,
            relativePath: relative,
            lines: [
                #"{"type":"turn_started","ts":"2026-07-19T02:00:00.000Z"}"#,
                #"{"type":"turn_ended","ts":"2026-07-19T02:00:05.000Z","outcome":"error"}"#,
            ],
            modifiedAt: Date(timeIntervalSince1970: 1_910_000_140)
        )
        #expect(try detector.activeTasks().first?.status == .error)

        try appendJSONLLine(
            #"{"type":"turn_started","ts":"2026-07-19T02:01:00.000Z"}"#,
            to: root.appendingPathComponent(relative)
        )
        #expect(try detector.activeTasks().first?.status == .running)
    }

    @Test
    func testIgnoresCorruptLinesPartialTailAndMissingDirectory() throws {
        let root = makeTempRoot("grok-noisy")
        defer { try? FileManager.default.removeItem(at: root) }

        let url = root.appendingPathComponent("sess-n/events.jsonl")
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let body = [
            "{bad",
            #"{"type":"turn_started","ts":"2026-07-19T01:00:00.000Z"}"#,
            #"{"type":"turn_started","ts":"#,
        ].joined(separator: "\n")
        try Data(body.utf8).write(to: url)

        let tasks = try GrokSessionActivityDetector(sessionsDirectory: root).activeTasks()
        #expect(tasks.count == 1)
        #expect(tasks[0].status == .running)

        let missing = FileManager.default.temporaryDirectory
            .appendingPathComponent("Zisla-grok-missing-\(UUID().uuidString)", isDirectory: true)
        #expect(try GrokSessionActivityDetector(sessionsDirectory: missing).activeTasks().isEmpty)
    }

    @Test
    func testUsesStructuredSessionAndModelFields() throws {
        let root = makeTempRoot("grok-metadata")
        defer { try? FileManager.default.removeItem(at: root) }

        try writeJSONL(
            under: root,
            relativePath: "directory-id/events.jsonl",
            lines: [
                #"{"type":"turn_started","ts":"2026-07-19T01:00:00.000Z","session_id":"event-session","model_id":"grok-4.5"}"#,
            ],
            modifiedAt: Date(timeIntervalSince1970: 1_910_000_200)
        )

        let task = try #require(GrokSessionActivityDetector(
            sessionsDirectory: root
        ).activeTasks().first)
        #expect(task.id == GrokSessionActivityDetector.taskID(forSessionID: "event-session"))
        #expect(task.detail == "grok-4.5")
    }

    @Test
    func testColdStartIgnoresActivityOutsideTheBoundedTail() throws {
        let root = makeTempRoot("grok-bounded")
        defer { try? FileManager.default.removeItem(at: root) }
        let filler = (0..<80).map { index in
            #"{"type":"progress","ts":"2026-07-19T01:00:01.000Z","index":\#(index)}"#
        }
        try writeJSONL(
            under: root,
            relativePath: "bounded/events.jsonl",
            lines: [
                #"{"type":"turn_started","ts":"2026-07-19T01:00:00.000Z"}"#,
            ] + filler,
            modifiedAt: Date(timeIntervalSince1970: 1_910_000_300)
        )

        let tasks = try GrokSessionActivityDetector(
            sessionsDirectory: root,
            initialTailBytes: 256
        ).activeTasks()

        #expect(tasks.isEmpty)
    }
}

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
