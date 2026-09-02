import Foundation
import Testing

@testable import ZislaCore
@testable import ZislaKit

struct PiSessionActivityDetectorTests {
    @Test
    func detectsActiveSessionWithoutReadingMessageContent() throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let session = root.appendingPathComponent("--project--/2026-08-21_session.jsonl")
        try writeJSONL([
            #"{"type":"session","version":3,"id":"session-1","timestamp":"2026-08-21T00:00:00Z","cwd":"/tmp/demo"}"#,
            #"{"type":"session_info","id":"a","parentId":null,"timestamp":"2026-08-21T00:00:01Z","name":"修复构建"}"#,
            #"{"type":"message","id":"b","parentId":"a","timestamp":"2026-08-21T00:00:02Z","message":{"role":"user","content":"不要读取我"}}"#,
            #"{"type":"message","id":"c","parentId":"b","timestamp":"2026-08-21T00:00:03Z","message":{"role":"assistant","model":"claude-sonnet","usage":{"input":10,"output":4},"stopReason":"toolUse"}}"#,
        ], to: session)

        let tasks = try PiSessionActivityDetector(
            sessionsDirectory: root,
            maximumSessionAge: .greatestFiniteMagnitude,
            processIdentifiersForSessions: { _ in [:] }
        ).activeTasks()

        #expect(tasks.count == 1)
        #expect(tasks[0].provider == .pi)
        #expect(tasks[0].id == "pi-session-session-1")
        #expect(tasks[0].title == "修复构建")
        #expect(tasks[0].detail == "claude-sonnet")
        #expect(tasks[0].status == .running)
    }

    @Test
    func omitsCompletedPiSessionAndRetainsErrorsAsVisibleTasks() throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let completed = root.appendingPathComponent("completed.jsonl")
        let failed = root.appendingPathComponent("failed.jsonl")
        try writeJSONL([
            #"{"type":"session","id":"done","cwd":"/tmp/done"}"#,
            #"{"type":"message","id":"u","timestamp":"2026-08-21T00:00:00Z","message":{"role":"user","content":"x"}}"#,
            #"{"type":"message","id":"a","timestamp":"2026-08-21T00:00:01Z","message":{"role":"assistant","stopReason":"stop"}}"#,
        ], to: completed)
        try writeJSONL([
            #"{"type":"session","id":"bad","cwd":"/tmp/bad"}"#,
            #"{"type":"message","id":"u","timestamp":"2026-08-21T00:00:00Z","message":{"role":"user","content":"x"}}"#,
            #"{"type":"message","id":"a","timestamp":"2026-08-21T00:00:01Z","message":{"role":"assistant","stopReason":"error","errorMessage":"network"}}"#,
        ], to: failed)

        let tasks = try PiSessionActivityDetector(
            sessionsDirectory: root,
            maximumSessionAge: .greatestFiniteMagnitude,
            processIdentifiersForSessions: { _ in [:] }
        ).activeTasks()

        #expect(tasks.map(\.id) == ["pi-session-bad"])
        #expect(tasks[0].status == .error)
        #expect(tasks[0].failureReason == "network")
    }

    @Test
    func collectsPiUsageIncludingCacheTokens() throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let session = root.appendingPathComponent("session.jsonl")
        try writeJSONL([
            #"{"type":"message","id":"assistant-1","timestamp":"2026-08-21T00:00:00Z","message":{"role":"assistant","model":"claude-sonnet","usage":{"input":100,"output":20,"cacheRead":30,"cacheWrite":10,"cost":{"total":0.12}},"stopReason":"stop"}}"#,
        ], to: session)

        let empty = root.appendingPathComponent("empty")
        let detector = AIUsageLogDetector(
            codexSessionsDirectory: empty,
            claudeProjectsDirectory: empty,
            geminiSessionsDirectory: empty,
            grokSessionsDirectory: empty,
            qwenProjectsDirectory: empty,
            piSessionsDirectory: root,
            qoderRoots: [],
            doubaoRoots: [],
            copilotUsageLogRoots: [],
            scanInterval: 0
        )

        let samples = try detector.usageSamples()
        #expect(samples.count == 1)
        #expect(samples[0].provider == .pi)
        #expect(samples[0].inputTokens == 140)
        #expect(samples[0].outputTokens == 20)
        #expect(samples[0].costUSD == 0.12)
    }

    @Test
    func attachesTheLivePiProcessIdentifierToTheLatestActiveSession() throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let session = root.appendingPathComponent("session.jsonl")
        try writeJSONL([
            #"{"type":"session","id":"live","cwd":"/tmp/live"}"#,
            #"{"type":"message","id":"user","timestamp":"2026-08-21T00:00:00Z","message":{"role":"user"}}"#,
        ], to: session)

        let task = try #require(PiSessionActivityDetector(
            sessionsDirectory: root,
            maximumSessionAge: .greatestFiniteMagnitude,
            processIdentifiersForSessions: { sessions in
                #expect(sessions[session.standardizedFileURL] == "live")
                return [session.standardizedFileURL: 54_321]
            }
        ).activeTasks().first)

        #expect(task.processIdentifier == 54_321)
    }

    @Test
    func reparsesAnInPlaceLargerSessionRewrite() throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let session = root.appendingPathComponent("session.jsonl")
        try writeJSONL([
            #"{"type":"session","id":"old","cwd":"/tmp/old"}"#,
            #"{"type":"message","timestamp":"2026-08-21T00:00:00Z","message":{"role":"user"}}"#,
        ], to: session)

        let detector = PiSessionActivityDetector(
            sessionsDirectory: root,
            maximumSessionAge: .greatestFiniteMagnitude,
            processIdentifiersForSessions: { _ in [:] }
        )
        #expect(try detector.activeTasks().first?.id == "pi-session-old")

        try writeJSONL([
            #"{"type":"session","id":"rewritten-session-with-a-longer-id","cwd":"/tmp/rewritten"}"#,
            #"{"type":"message","timestamp":"2026-08-21T00:00:01Z","message":{"role":"user"}}"#,
        ], to: session)
        #expect(try detector.activeTasks().first?.id == "pi-session-rewritten-session-with-a-longer-id")
    }

    @Test
    func doesNotPairSessionsAndProcessIdentifiersByUnrelatedSortOrder() throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        try writeJSONL([
            #"{"type":"session","id":"session-a","cwd":"/tmp/a"}"#,
            #"{"type":"message","id":"user-a","timestamp":"2026-08-21T00:00:00Z","message":{"role":"user"}}"#,
        ], to: root.appendingPathComponent("a.jsonl"))
        try writeJSONL([
            #"{"type":"session","id":"session-b","cwd":"/tmp/b"}"#,
            #"{"type":"message","id":"user-b","timestamp":"2026-08-21T00:00:01Z","message":{"role":"user"}}"#,
        ], to: root.appendingPathComponent("b.jsonl"))

        let tasks = try PiSessionActivityDetector(
            sessionsDirectory: root,
            maximumSessionAge: .greatestFiniteMagnitude,
            processIdentifiersForSessions: { _ in [:] }
        ).activeTasks()

        #expect(tasks.count == 2)
        #expect(tasks.allSatisfy { $0.processIdentifier == nil })
    }

    @Test
    func mapsOnlyExplicitPiSessionArgumentsToProcessIdentifiers() {
        let first = URL(fileURLWithPath: "/tmp/a.jsonl").standardizedFileURL
        let second = URL(fileURLWithPath: "/tmp/b.jsonl").standardizedFileURL
        let pathWithWhitespace = URL(fileURLWithPath: "/tmp/pi session.jsonl").standardizedFileURL
        let output = Data("""
          4321 /Users/wzz/.npm-global/bin/pi pi --session-id session-a
          5432 /opt/homebrew/bin/node /Users/wzz/.npm-global/lib/node_modules/@earendil-works/pi-coding-agent/dist/cli.js --session /tmp/b.jsonl
          6543 /usr/local/bin/node /tmp/other.js --session-id session-a
          7654 /bin/rg rg --session-id session-b /pi-coding-agent/
          8765 /Users/wzz/.npm-global/bin/pi pi --no-session --session-id session-b
          9876 /Users/wzz/.npm-global/bin/pi pi --session /tmp/pi session.jsonl
        """.utf8)

        #expect(PiSessionActivityDetector.parseRunningProcessIdentifiers(
            output,
            matching: [first: "session-a", second: "session-b", pathWithWhitespace: "session-c"]
        ) == [first: 4321, second: 5432, pathWithWhitespace: 9876])
    }

    @Test
    func omitsAmbiguousPiSessionReferences() {
        let first = URL(fileURLWithPath: "/tmp/a.jsonl").standardizedFileURL
        let second = URL(fileURLWithPath: "/tmp/b.jsonl").standardizedFileURL
        let output = Data("""
          4321 /Users/wzz/.npm-global/bin/pi pi --session session
          5432 /Users/wzz/.npm-global/bin/pi pi --session-id session-a
          6543 /Users/wzz/.npm-global/bin/pi pi --session-id session-a
        """.utf8)

        #expect(PiSessionActivityDetector.parseRunningProcessIdentifiers(
            output,
            matching: [first: "session-a", second: "session-b"]
        ).isEmpty)
    }
}

private func temporaryDirectory() -> URL {
    FileManager.default.temporaryDirectory
        .appendingPathComponent("zisla-pi-tests-\(UUID().uuidString)", isDirectory: true)
}

private func writeJSONL(_ lines: [String], to url: URL) throws {
    try FileManager.default.createDirectory(
        at: url.deletingLastPathComponent(),
        withIntermediateDirectories: true
    )
    try Data((lines.joined(separator: "\n") + "\n").utf8).write(to: url)
}
