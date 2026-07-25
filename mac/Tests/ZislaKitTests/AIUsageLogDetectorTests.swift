import Foundation
import Testing

@testable import ZislaCore
@testable import ZislaKit

struct AIUsageLogDetectorTests {
    @Test
    func defaultScanLimitsBoundIdleResourceUsage() {
        let detector = AIUsageLogDetector()

        #expect(detector.maxFilesPerProvider == 4)
        #expect(detector.maxBytesPerFile == 256 * 1_024)
        #expect(detector.maxSamplesPerFile == 256)
    }

    @Test
    func parsesProviderLogsAndDeduplicatesRepeatedClaudeMessages() throws {
        let root = temporaryDirectory(named: "usage-log-detector")
        defer { try? FileManager.default.removeItem(at: root) }
        let codex = root.appendingPathComponent("codex", isDirectory: true)
        let claude = root.appendingPathComponent("claude", isDirectory: true)
        let grok = root.appendingPathComponent("grok", isDirectory: true)
        let empty = root.appendingPathComponent("empty", isDirectory: true)

        try writeJSONL([
            """
            {"timestamp":"2026-07-23T00:00:00.000Z","type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":1000,"cached_input_tokens":900,"output_tokens":50},"last_token_usage":{"input_tokens":120,"output_tokens":30}}}}
            """,
            """
            {"timestamp":"2026-07-23T00:00:00.000Z","type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":1000,"cached_input_tokens":900,"output_tokens":50},"last_token_usage":{"input_tokens":120,"output_tokens":30}}}}
            """,
            """
            {"timestamp":"2026-07-23T00:02:00.000Z","type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":1200,"cached_input_tokens":1050,"output_tokens":75},"last_token_usage":{"input_tokens":80,"output_tokens":25}}}}
            """,
        ], to: codex.appendingPathComponent("2026/07/23/rollout.jsonl"))
        try writeJSONL([
            """
            {"type":"assistant","timestamp":"2026-07-23T00:01:00.000Z","message":{"id":"msg-one","model":"claude-opus","usage":{"input_tokens":10,"output_tokens":5,"cache_creation_input_tokens":20,"cache_read_input_tokens":30}}}
            """,
            """
            {"type":"assistant","timestamp":"2026-07-23T00:01:01.000Z","message":{"id":"msg-one","model":"claude-opus","usage":{"input_tokens":10,"output_tokens":5,"cache_creation_input_tokens":20,"cache_read_input_tokens":30}}}
            """,
        ], to: claude.appendingPathComponent("session.jsonl"))
        try writeJSONL([
            """
            {"timestamp":1784764920,"method":"_x.ai/session/update","params":{"sessionId":"session-one","update":{"prompt_id":"prompt-one","usage":{"inputTokens":100,"outputTokens":20,"modelUsage":{"grok-4.5":{}}}}}}
            """,
            """
            {"timestamp":1784764980,"method":"_x.ai/session/update","params":{"sessionId":"session-one","update":{"prompt_id":"prompt-two","usage":{"inputTokens":160,"outputTokens":50,"modelUsage":{"grok-4.5":{}}}}}}
            """,
        ], to: grok.appendingPathComponent("session/updates.jsonl"))

        let detector = AIUsageLogDetector(
            codexSessionsDirectory: codex,
            claudeProjectsDirectory: claude,
            geminiSessionsDirectory: empty,
            grokSessionsDirectory: grok,
            qwenProjectsDirectory: empty,
            qoderRoots: [],
            maxFilesPerProvider: 12
        )

        let samples = try detector.usageSamples()
        #expect(samples.count == 5)
        #expect(samples.filter { $0.provider == .codex }.map(\.inputTokens) == [100, 50])
        #expect(samples.filter { $0.provider == .codex }.map(\.outputTokens) == [50, 25])
        #expect(samples.first(where: { $0.provider == .claude })?.inputTokens == 60)
        #expect(samples.filter { $0.provider == .grok }.map(\.inputTokens) == [100, 60])
        #expect(samples.filter { $0.provider == .grok }.map(\.outputTokens) == [20, 30])
        #expect(samples.allSatisfy { $0.sourceID != nil })
        #expect(try detector.usageSamples() == samples)
    }

    @Test
    func readsRecentJSONLTailWithoutLoadingTheWholeSession() throws {
        let root = temporaryDirectory(named: "usage-log-tail")
        defer { try? FileManager.default.removeItem(at: root) }
        let codex = root.appendingPathComponent("codex", isDirectory: true)
        let empty = root.appendingPathComponent("empty", isDirectory: true)
        let log = codex.appendingPathComponent("2026/07/24/rollout.jsonl")
        let ignoredPayload = String(repeating: "x", count: 6_000)

        try writeJSONL([
            "{\"type\":\"ignored\",\"payload\":\"\(ignoredPayload)\"}",
            """
            {"timestamp":"2026-07-24T00:00:00.000Z","type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":240,"output_tokens":60},"last_token_usage":{"input_tokens":240,"output_tokens":60}}}}
            """,
        ], to: log)

        let detector = AIUsageLogDetector(
            codexSessionsDirectory: codex,
            claudeProjectsDirectory: empty,
            geminiSessionsDirectory: empty,
            grokSessionsDirectory: empty,
            qwenProjectsDirectory: empty,
            qoderRoots: [],
            maxBytesPerFile: 4_096
        )

        let samples = try detector.usageSamples()
        #expect(samples.count == 1)
        #expect(samples[0].provider == .codex)
        #expect(samples[0].inputTokens == 240)
        #expect(samples[0].outputTokens == 60)
    }

    @Test
    func truncatedCodexLogUsesLastUsageForItsInitialTokenSample() throws {
        let root = temporaryDirectory(named: "usage-log-truncated-cumulative")
        defer { try? FileManager.default.removeItem(at: root) }
        let codex = root.appendingPathComponent("codex", isDirectory: true)
        let empty = root.appendingPathComponent("empty", isDirectory: true)
        let log = codex.appendingPathComponent("2026/07/24/rollout.jsonl")
        let ignoredPayload = String(repeating: "x", count: 6_000)

        try writeJSONL([
            "{\"type\":\"ignored\",\"payload\":\"\(ignoredPayload)\"}",
            """
            {"timestamp":"2026-07-24T00:00:00.000Z","type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":1000000,"output_tokens":200},"last_token_usage":{"input_tokens":120,"output_tokens":20}}}}
            """,
            """
            {"timestamp":"2026-07-24T00:01:00.000Z","type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":1000050,"output_tokens":220},"last_token_usage":{"input_tokens":50,"output_tokens":20}}}}
            """,
        ], to: log)

        let detector = AIUsageLogDetector(
            codexSessionsDirectory: codex,
            claudeProjectsDirectory: empty,
            geminiSessionsDirectory: empty,
            grokSessionsDirectory: empty,
            qwenProjectsDirectory: empty,
            qoderRoots: [],
            maxBytesPerFile: 4_096
        )

        let samples = try detector.usageSamples()
        #expect(samples.map(\.inputTokens) == [120, 50])
        #expect(samples.map(\.outputTokens) == [20, 20])
    }

    @Test
    func retainsOnlyTheNewestSamplesFromEachActiveLog() throws {
        let root = temporaryDirectory(named: "usage-log-sample-limit")
        defer { try? FileManager.default.removeItem(at: root) }
        let codex = root.appendingPathComponent("codex", isDirectory: true)
        let empty = root.appendingPathComponent("empty", isDirectory: true)
        try writeJSONL([
            """
            {"timestamp":"2026-07-24T00:00:00.000Z","type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":100,"output_tokens":10},"last_token_usage":{"input_tokens":100,"output_tokens":10}}}}
            """,
            """
            {"timestamp":"2026-07-24T00:01:00.000Z","type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":180,"output_tokens":30},"last_token_usage":{"input_tokens":80,"output_tokens":20}}}}
            """,
        ], to: codex.appendingPathComponent("2026/07/24/rollout.jsonl"))

        let detector = AIUsageLogDetector(
            codexSessionsDirectory: codex,
            claudeProjectsDirectory: empty,
            geminiSessionsDirectory: empty,
            grokSessionsDirectory: empty,
            qwenProjectsDirectory: empty,
            qoderRoots: [],
            maxSamplesPerFile: 1
        )

        let samples = try detector.usageSamples()
        #expect(samples.count == 1)
        #expect(samples[0].inputTokens == 80)
        #expect(samples[0].outputTokens == 20)
    }

    @Test @MainActor
    func monitorRecordsDetectedUsageOnlyOnceAcrossReloads() throws {
        let directory = temporaryDirectory(named: "usage-monitor")
        defer { try? FileManager.default.removeItem(at: directory) }
        let sample = AIUsageSample(
            sourceID: "codex-log-event",
            provider: .codex,
            timestamp: Date(timeIntervalSince1970: 100),
            inputTokens: 80,
            outputTokens: 20
        )
        let monitor = AIStateMonitor(
            directoryURL: directory,
            activityDetectors: [],
            usageDetectors: [StaticUsageDetector(samples: [sample])]
        )

        monitor.reload()
        monitor.reload()

        #expect(monitor.state.usageSamples == [sample])
        #expect(try AIStateRepository(directoryURL: directory).load().usageSamples == [sample])
    }

    @Test @MainActor
    func monitorPersistsUsageWithoutRetainingHistory() throws {
        let directory = temporaryDirectory(named: "usage-monitor-on-demand")
        defer { try? FileManager.default.removeItem(at: directory) }
        let sample = AIUsageSample(
            sourceID: "codex-log-event",
            provider: .codex,
            timestamp: Date(timeIntervalSince1970: 100),
            inputTokens: 80,
            outputTokens: 20
        )
        let monitor = AIStateMonitor(
            directoryURL: directory,
            activityDetectors: [],
            usageDetectors: [StaticUsageDetector(samples: [sample])]
        )

        monitor.reload(includeUsageSamples: false)

        #expect(monitor.state.usageSamples.isEmpty)
        #expect(try AIStateRepository(directoryURL: directory).load().usageSamples == [sample])

        monitor.reload()

        #expect(monitor.state.usageSamples == [sample])
        monitor.unloadUsageHistory()
        #expect(monitor.state.usageSamples.isEmpty)
        #expect(try AIStateRepository(directoryURL: directory).load().usageSamples == [sample])
    }

    @Test @MainActor
    func monitorRunsActivityDetectionOnceWhenRecordingNewUsage() {
        let directory = temporaryDirectory(named: "usage-single-activity-scan")
        defer { try? FileManager.default.removeItem(at: directory) }
        let activityDetector = CountingActivityDetector()
        let sample = AIUsageSample(
            sourceID: "codex-log-event",
            provider: .codex,
            timestamp: Date(timeIntervalSince1970: 100),
            inputTokens: 80,
            outputTokens: 20
        )
        let monitor = AIStateMonitor(
            directoryURL: directory,
            activityDetectors: [activityDetector],
            usageDetectors: [StaticUsageDetector(samples: [sample])]
        )

        monitor.reload()

        #expect(activityDetector.callCount == 1)
    }

    @Test
    func repositoryRevisesExistingLogSampleWhenParserCorrectsIt() throws {
        let directory = temporaryDirectory(named: "usage-correction")
        defer { try? FileManager.default.removeItem(at: directory) }
        let repository = AIStateRepository(directoryURL: directory)
        let original = AIUsageSample(
            sourceID: "codex-log-event",
            provider: .codex,
            timestamp: Date(timeIntervalSince1970: 100),
            inputTokens: 1_000,
            outputTokens: 20
        )
        let corrected = AIUsageSample(
            sourceID: "codex-log-event",
            provider: .codex,
            timestamp: Date(timeIntervalSince1970: 100),
            inputTokens: 80,
            outputTokens: 20
        )

        #expect(try repository.recordUsage([original]) == 1)
        #expect(try repository.recordUsage([corrected]) == 0)
        #expect(try repository.load().usageSamples == [corrected])
    }

    @Test
    func repositoryReturnsMergedStateWhenRecordingUsage() throws {
        let directory = temporaryDirectory(named: "usage-recorded-state")
        defer { try? FileManager.default.removeItem(at: directory) }
        let repository = AIStateRepository(directoryURL: directory)
        let sample = AIUsageSample(
            sourceID: "codex-log-event",
            provider: .codex,
            timestamp: Date(timeIntervalSince1970: 100),
            inputTokens: 80,
            outputTokens: 20
        )

        let state = try repository.stateRecordingUsage([sample])

        #expect(state.usageSamples == [sample])
        #expect(try repository.load().usageSamples == [sample])
    }
}

private struct StaticUsageDetector: AIUsageDetecting {
    var samples: [AIUsageSample]

    func usageSamples() throws -> [AIUsageSample] { samples }
}

private final class CountingActivityDetector: AIActivityDetecting {
    private let lock = NSLock()
    private var calls = 0

    var callCount: Int {
        lock.withLock { calls }
    }

    func activeTasks() throws -> [AIProgressTask] {
        lock.withLock { calls += 1 }
        return []
    }
}

private func writeJSONL(_ lines: [String], to url: URL) throws {
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try Data((lines.joined(separator: "\n") + "\n").utf8).write(to: url)
}

private func temporaryDirectory(named name: String) -> URL {
    FileManager.default.temporaryDirectory
        .appendingPathComponent("Zisla-\(name)-\(UUID().uuidString)", isDirectory: true)
}
