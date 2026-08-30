import Foundation
import Testing

@testable import ZislaCore
@testable import ZislaKit

struct AIUsageLogDetectorTests {
    @Test
    func incrementalVerificationStaysBoundedForLargeUsageLogs() {
        let largeLogBytes = UInt64(80 * 1_024 * 1_024)
        #expect(AIUsageLogDetector.incrementalVerificationByteCount(
            for: largeLogBytes
        ) == 8 * 1_024)
    }

    @Test
    func defaultScanKeepsEveryUsageSample() {
        let detector = AIUsageLogDetector()

        #expect(detector.maxFilesPerProvider == .max)
        #expect(detector.maxBytesPerFile == .max)
        #expect(detector.maxSamplesPerFile == .max)
    }

    @Test
    func defaultScanReadsStructuredJSONLargerThanFormerLimit() throws {
        let root = temporaryDirectory(named: "usage-log-large-json")
        defer { try? FileManager.default.removeItem(at: root) }
        let gemini = root.appendingPathComponent("gemini", isDirectory: true)
        let empty = root.appendingPathComponent("empty", isDirectory: true)
        let padding = String(repeating: "x", count: 4 * 1_024 * 1_024)
        try writeJSON(
            """
            [{"timestamp":"2026-07-26T00:02:00.000Z","padding":"\(padding)","model":"gemini-2.5-pro","usageMetadata":{"promptTokenCount":90,"candidatesTokenCount":12}}]
            """,
            to: gemini.appendingPathComponent("session-2026-07-26.json")
        )

        let detector = AIUsageLogDetector(
            codexSessionsDirectory: empty,
            claudeProjectsDirectory: empty,
            geminiSessionsDirectory: gemini,
            grokSessionsDirectory: empty,
            qwenProjectsDirectory: empty,
            piSessionsDirectory: empty,
            qoderRoots: [],
            doubaoRoots: [],
            copilotUsageLogRoots: []
        )

        let sample = try #require(detector.usageSamples().first)
        #expect(sample.provider == .gemini)
        #expect(sample.inputTokens == 90)
        #expect(sample.outputTokens == 12)
    }

    @Test
    func preservesLargeTokenValuesWithoutOverflowingOrDroppingUsage() throws {
        let root = temporaryDirectory(named: "usage-log-large-token-values")
        defer { try? FileManager.default.removeItem(at: root) }
        let qwen = root.appendingPathComponent("qwen", isDirectory: true)
        let empty = root.appendingPathComponent("empty", isDirectory: true)
        try writeJSONL([
            """
            {"timestamp":"2026-07-26T00:02:00.000Z","model":"qwen3-coder","usage":{"input_tokens":\(UInt64.max),"output_tokens":1}}
            """,
            """
            {"timestamp":"2026-07-26T00:03:00.000Z","model":"qwen3-coder","usage":{"input_tokens":\(Int.max - 1),"output_tokens":2,"cache_creation_input_tokens":2}}
            """,
        ], to: qwen.appendingPathComponent("project/session.jsonl"))

        let detector = AIUsageLogDetector(
            codexSessionsDirectory: empty,
            claudeProjectsDirectory: empty,
            geminiSessionsDirectory: empty,
            grokSessionsDirectory: empty,
            qwenProjectsDirectory: qwen,
            piSessionsDirectory: empty,
            qoderRoots: [],
            doubaoRoots: [],
            copilotUsageLogRoots: []
        )

        let samples = try detector.usageSamples()
        #expect(samples.map(\.inputTokens) == [Int.max, Int.max])
        #expect(samples.map(\.outputTokens) == [1, 2])
    }

    @Test
    func preservesGrokUsageWhenTheTokenTotalWouldOverflow() throws {
        let root = temporaryDirectory(named: "usage-log-grok-overflow")
        defer { try? FileManager.default.removeItem(at: root) }
        let grok = root.appendingPathComponent("grok", isDirectory: true)
        let empty = root.appendingPathComponent("empty", isDirectory: true)
        try writeJSONL([
            """
            {"timestamp":1785024180,"method":"_x.ai/session/update","params":{"sessionId":"grok-session","update":{"prompt_id":"grok-overflow","usage":{"inputTokens":\(Int.max),"outputTokens":1}}}}
            """,
        ], to: grok.appendingPathComponent("session/updates.jsonl"))

        let detector = AIUsageLogDetector(
            codexSessionsDirectory: empty,
            claudeProjectsDirectory: empty,
            geminiSessionsDirectory: empty,
            grokSessionsDirectory: grok,
            qwenProjectsDirectory: empty,
            piSessionsDirectory: empty,
            qoderRoots: [],
            doubaoRoots: [],
            copilotUsageLogRoots: []
        )

        let sample = try #require(detector.usageSamples().first)
        #expect(sample.inputTokens == Int.max)
        #expect(sample.outputTokens == 1)
        #expect(sample.totalTokens == Int.max)
    }

    @Test
    func defaultScanReadsUsageInsideLongJSONLRecord() throws {
        let root = temporaryDirectory(named: "usage-log-long-jsonl")
        defer { try? FileManager.default.removeItem(at: root) }
        let codex = root.appendingPathComponent("codex", isDirectory: true)
        let empty = root.appendingPathComponent("empty", isDirectory: true)
        let padding = String(repeating: "x", count: 256 * 1_024)
        try writeJSONL([
            """
            {"timestamp":"2026-07-24T00:00:00.000Z","padding":"\(padding)","type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":240,"output_tokens":60},"last_token_usage":{"input_tokens":240,"output_tokens":60}}}}
            """,
        ], to: codex.appendingPathComponent("2026/07/24/rollout.jsonl"))

        let detector = AIUsageLogDetector(
            codexSessionsDirectory: codex,
            claudeProjectsDirectory: empty,
            geminiSessionsDirectory: empty,
            grokSessionsDirectory: empty,
            qwenProjectsDirectory: empty,
            piSessionsDirectory: empty,
            qoderRoots: [],
            doubaoRoots: [],
            copilotUsageLogRoots: []
        )

        let sample = try #require(detector.usageSamples().first)
        #expect(sample.provider == .codex)
        #expect(sample.inputTokens == 240)
        #expect(sample.outputTokens == 60)
    }

    @Test
    func parsesAllStructuredProvidersAfterOversizedLogEntries() throws {
        let root = temporaryDirectory(named: "usage-log-all-providers")
        defer { try? FileManager.default.removeItem(at: root) }
        let codex = root.appendingPathComponent("codex", isDirectory: true)
        let claude = root.appendingPathComponent("claude", isDirectory: true)
        let gemini = root.appendingPathComponent("gemini", isDirectory: true)
        let grok = root.appendingPathComponent("grok", isDirectory: true)
        let qwen = root.appendingPathComponent("qwen", isDirectory: true)
        let empty = root.appendingPathComponent("empty", isDirectory: true)
        let qoder = root.appendingPathComponent("qoder", isDirectory: true)
        let doubao = root.appendingPathComponent("doubao", isDirectory: true)
        let ignoredPayload = String(repeating: "x", count: 6_000)

        try writeJSONL([
            "{\"type\":\"ignored\",\"payload\":\"\(ignoredPayload)\"}",
            """
            {"type":"assistant","timestamp":"2026-07-26T00:01:00.000Z","message":{"id":"claude-one","model":"claude-opus","usage":{"input_tokens":10,"output_tokens":5,"cache_creation_input_tokens":20,"cache_read_input_tokens":30}}}
            """,
        ], to: claude.appendingPathComponent("session.jsonl"))
        try writeJSON(
            """
            [{"timestamp":"2026-07-26T00:02:00.000Z","ignored":"\(ignoredPayload)","model":"gemini-2.5-pro","usageMetadata":{"promptTokenCount":90,"candidatesTokenCount":12}}]
            """,
            to: gemini.appendingPathComponent("session-2026-07-26.json")
        )
        try writeJSONL([
            "{\"type\":\"ignored\",\"payload\":\"\(ignoredPayload)\"}",
            """
            {"timestamp":1785024180,"method":"_x.ai/session/update","params":{"sessionId":"grok-session","update":{"prompt_id":"grok-one","usage":{"inputTokens":100,"outputTokens":20,"modelUsage":{"grok-4.5":{}}}}}}
            """,
            """
            {"timestamp":1785024240,"method":"_x.ai/session/update","params":{"sessionId":"grok-session","update":{"prompt_id":"grok-two","usage":{"inputTokens":160,"outputTokens":50,"modelUsage":{"grok-4.5":{}}}}}}
            """,
        ], to: grok.appendingPathComponent("session/updates.jsonl"))
        try writeJSONL([
            "{\"type\":\"ignored\",\"payload\":\"\(ignoredPayload)\"}",
            """
            {"timestamp":"2026-07-26T00:04:00.000Z","model":"qwen3-coder","usage":{"prompt_tokens":15,"completion_tokens":3}}
            """,
        ], to: qwen.appendingPathComponent("project/session.jsonl"))
        try writeJSONL([
            "{\"type\":\"ignored\",\"payload\":\"\(ignoredPayload)\"}",
            """
            {"timestamp":"2026-07-26T00:05:00.000Z","model":"qoder-max","usage":{"input_tokens":6,"output_tokens":4,"cache_creation_input_tokens":7,"cache_read_input_tokens":8}}
            """,
        ], to: qoder.appendingPathComponent("logs/sessions/session-one/segments/one.jsonl"))
        try writeJSONL([
            "{\"type\":\"ignored\",\"payload\":\"\(ignoredPayload)\"}",
            """
            {"timestamp":"2026-07-26T00:06:00.000Z","model":"doubao-seed","usage":{"input_tokens":11,"output_tokens":2}}
            """,
        ], to: doubao.appendingPathComponent("history/session.jsonl"))

        let detector = AIUsageLogDetector(
            codexSessionsDirectory: codex,
            claudeProjectsDirectory: claude,
            geminiSessionsDirectory: gemini,
            grokSessionsDirectory: grok,
            qwenProjectsDirectory: qwen,
            piSessionsDirectory: empty,
            qoderRoots: [qoder],
            doubaoRoots: [doubao],
            maxBytesPerFile: 4_096
        )

        let samples = try detector.usageSamples()
        #expect(samples.filter { $0.provider == .claude }.map(\.inputTokens) == [60])
        #expect(samples.filter { $0.provider == .gemini }.map(\.inputTokens) == [90])
        #expect(samples.filter { $0.provider == .gemini }.map(\.outputTokens) == [12])
        #expect(samples.filter { $0.provider == .grok }.map(\.inputTokens) == [100, 60])
        #expect(samples.filter { $0.provider == .grok }.map(\.outputTokens) == [20, 30])
        #expect(samples.filter { $0.provider == .qwen }.map(\.inputTokens) == [15])
        #expect(samples.filter { $0.provider == .coder }.map(\.inputTokens) == [21])
        #expect(samples.filter { $0.provider == .coder }.map(\.outputTokens) == [4])
        #expect(samples.filter { $0.provider == .doubao }.map(\.inputTokens) == [11])
    }

    @Test
    func appendingGrokUsageRetainsCumulativeSessionState() throws {
        let root = temporaryDirectory(named: "usage-log-grok-append")
        defer { try? FileManager.default.removeItem(at: root) }
        let grok = root.appendingPathComponent("grok", isDirectory: true)
        let empty = root.appendingPathComponent("empty", isDirectory: true)
        let log = grok.appendingPathComponent("session/updates.jsonl")

        try writeJSONL([
            """
            {"timestamp":1785024180,"method":"_x.ai/session/update","params":{"sessionId":"grok-session","update":{"prompt_id":"grok-one","usage":{"inputTokens":100,"outputTokens":20}}}}
            """,
        ], to: log)

        let detector = AIUsageLogDetector(
            codexSessionsDirectory: empty,
            claudeProjectsDirectory: empty,
            geminiSessionsDirectory: empty,
            grokSessionsDirectory: grok,
            qwenProjectsDirectory: empty,
            piSessionsDirectory: empty,
            qoderRoots: [],
            doubaoRoots: [],
            scanInterval: 0
        )
        #expect(try detector.usageSamples().map(\.inputTokens) == [100])

        try appendJSONL(
            """
            {"timestamp":1785024240,"method":"_x.ai/session/update","params":{"sessionId":"grok-session","update":{"prompt_id":"grok-two","usage":{"inputTokens":160,"outputTokens":50}}}}
            """,
            to: log
        )

        let samples = try detector.usageSamples()
        #expect(samples.map(\.inputTokens) == [100, 60])
        #expect(samples.map(\.outputTokens) == [20, 30])
    }

    @Test @MainActor
    func monitorKeepsGrokPromptDeltasAcrossRepeatedScansAndRestart() throws {
        let root = temporaryDirectory(named: "usage-monitor-grok-cumulative")
        defer { try? FileManager.default.removeItem(at: root) }
        let stateDirectory = root.appendingPathComponent("state", isDirectory: true)
        let grok = root.appendingPathComponent("grok", isDirectory: true)
        let empty = root.appendingPathComponent("empty", isDirectory: true)
        let log = grok.appendingPathComponent("session/updates.jsonl")
        try writeJSONL([
            """
            {"timestamp":1785024180,"method":"_x.ai/session/update","params":{"sessionId":"grok-session","update":{"prompt_id":"grok-one","usage":{"inputTokens":100,"outputTokens":0}}}}
            """,
        ], to: log)

        func makeDetector() -> AIUsageLogDetector {
            AIUsageLogDetector(
                codexSessionsDirectory: empty,
                claudeProjectsDirectory: empty,
                geminiSessionsDirectory: empty,
                grokSessionsDirectory: grok,
                qwenProjectsDirectory: empty,
                piSessionsDirectory: empty,
                qoderRoots: [],
                doubaoRoots: [],
                copilotUsageLogRoots: [],
                scanInterval: 0
            )
        }

        let monitor = AIStateMonitor(
            directoryURL: stateDirectory,
            activityDetectors: [],
            usageDetectors: [makeDetector()]
        )
        monitor.reload()
        #expect(try AIStateRepository(directoryURL: stateDirectory).load().usageSamples.first?.totalTokens == 100)

        try appendJSONL(
            """
            {"timestamp":1785024240,"method":"_x.ai/session/update","params":{"sessionId":"grok-session","update":{"prompt_id":"grok-one","usage":{"inputTokens":160,"outputTokens":0}}}}
            """,
            to: log
        )
        monitor.reload()
        #expect(try AIStateRepository(directoryURL: stateDirectory).load().usageSamples.first?.totalTokens == 160)

        monitor.reload()
        #expect(try AIStateRepository(directoryURL: stateDirectory).load().usageSamples.first?.totalTokens == 160)

        let restartedMonitor = AIStateMonitor(
            directoryURL: stateDirectory,
            activityDetectors: [],
            usageDetectors: [makeDetector()]
        )
        restartedMonitor.reload()
        #expect(try AIStateRepository(directoryURL: stateDirectory).load().usageSamples.first?.totalTokens == 160)
    }

    @Test
    func parsesCopilotCLIUsageEventsIncludingCacheTokens() throws {
        let root = temporaryDirectory(named: "usage-log-copilot-cli")
        defer { try? FileManager.default.removeItem(at: root) }
        let copilot = root.appendingPathComponent("copilot", isDirectory: true)
        let empty = root.appendingPathComponent("empty", isDirectory: true)
        try writeJSONL([
            """
            {"id":"usage-one","timestamp":"2026-07-26T00:07:00.000Z","type":"assistant.usage","data":{"model":"gpt-5","inputTokens":100,"outputTokens":20,"cacheReadTokens":30,"cacheWriteTokens":40}}
            """,
        ], to: copilot.appendingPathComponent("events.jsonl"))

        let detector = AIUsageLogDetector(
            codexSessionsDirectory: empty,
            claudeProjectsDirectory: empty,
            geminiSessionsDirectory: empty,
            grokSessionsDirectory: empty,
            qwenProjectsDirectory: empty,
            piSessionsDirectory: empty,
            qoderRoots: [],
            doubaoRoots: [],
            copilotUsageLogRoots: [copilot]
        )

        let samples = try detector.usageSamples()
        #expect(samples.count == 1)
        #expect(samples[0].provider == .copilot)
        #expect(samples[0].inputTokens == 170)
        #expect(samples[0].outputTokens == 20)
        #expect(samples[0].model == "gpt-5")
    }

    @Test
    func parsesCopilotVSCodeDiagnosticUsageAndShutdownSummary() throws {
        let root = temporaryDirectory(named: "usage-log-copilot-vscode")
        defer { try? FileManager.default.removeItem(at: root) }
        let copilot = root.appendingPathComponent("copilot-diagnostics", isDirectory: true)
        let empty = root.appendingPathComponent("empty", isDirectory: true)
        try writeJSONL([
            """
            {"id":"diagnostic-one","timestamp":"2026-07-26T00:08:00.000Z","llm_request":{"attrs":{"model":"gpt-4.1","inputTokens":12,"outputTokens":4,"cacheReadTokens":6,"cacheWriteTokens":8}}}
            """,
        ], to: copilot.appendingPathComponent("vscode.jsonl"))
        try writeJSONL([
            """
            {"id":"shutdown-one","timestamp":"2026-07-26T00:09:00.000Z","type":"session.shutdown","data":{"modelMetrics":{"claude-sonnet":{"usage":{"inputTokens":120,"outputTokens":15,"cacheReadTokens":20,"cacheWriteTokens":30}}}}}
            """,
        ], to: copilot.appendingPathComponent("summary.jsonl"))

        let detector = AIUsageLogDetector(
            codexSessionsDirectory: empty,
            claudeProjectsDirectory: empty,
            geminiSessionsDirectory: empty,
            grokSessionsDirectory: empty,
            qwenProjectsDirectory: empty,
            piSessionsDirectory: empty,
            qoderRoots: [],
            doubaoRoots: [],
            copilotUsageLogRoots: [copilot]
        )

        let samples = try detector.usageSamples()
        #expect(samples.map(\.inputTokens) == [26, 170])
        #expect(samples.map(\.outputTokens) == [4, 15])
        #expect(samples.map(\.model) == ["gpt-4.1", "claude-sonnet"])
    }

    @Test
    func prefersCopilotDetailedUsageOverSessionShutdownSummary() throws {
        let root = temporaryDirectory(named: "usage-log-copilot-deduplication")
        defer { try? FileManager.default.removeItem(at: root) }
        let copilot = root.appendingPathComponent("copilot", isDirectory: true)
        let empty = root.appendingPathComponent("empty", isDirectory: true)
        try writeJSONL([
            """
            {"id":"usage-one","timestamp":"2026-07-26T00:10:00.000Z","type":"assistant.usage","data":{"model":"gpt-5","inputTokens":100,"outputTokens":20}}
            """,
            """
            {"id":"shutdown-one","timestamp":"2026-07-26T00:11:00.000Z","type":"session.shutdown","data":{"modelMetrics":{"gpt-5":{"usage":{"inputTokens":100,"outputTokens":20,"cacheReadTokens":0,"cacheWriteTokens":0}}}}}
            """,
        ], to: copilot.appendingPathComponent("events.jsonl"))

        let detector = AIUsageLogDetector(
            codexSessionsDirectory: empty,
            claudeProjectsDirectory: empty,
            geminiSessionsDirectory: empty,
            grokSessionsDirectory: empty,
            qwenProjectsDirectory: empty,
            piSessionsDirectory: empty,
            qoderRoots: [],
            doubaoRoots: [],
            copilotUsageLogRoots: [copilot]
        )

        let samples = try detector.usageSamples()
        #expect(samples.count == 1)
        #expect(samples[0].inputTokens == 100)
        #expect(samples[0].outputTokens == 20)
    }

    @Test
    func replacingACopilotShutdownSummaryWithLaterDetailedUsageDoesNotDoubleCount() throws {
        let root = temporaryDirectory(named: "usage-log-copilot-incremental")
        defer { try? FileManager.default.removeItem(at: root) }
        let copilot = root.appendingPathComponent("copilot", isDirectory: true)
        let empty = root.appendingPathComponent("empty", isDirectory: true)
        let log = copilot.appendingPathComponent("events.jsonl")
        try writeJSONL([
            """
            {"id":"shutdown-one","timestamp":"2026-07-26T00:12:00.000Z","type":"session.shutdown","data":{"modelMetrics":{"gpt-5":{"usage":{"inputTokens":140,"outputTokens":30,"cacheReadTokens":0,"cacheWriteTokens":0}}}}}
            """,
        ], to: log)

        let detector = AIUsageLogDetector(
            codexSessionsDirectory: empty,
            claudeProjectsDirectory: empty,
            geminiSessionsDirectory: empty,
            grokSessionsDirectory: empty,
            qwenProjectsDirectory: empty,
            piSessionsDirectory: empty,
            qoderRoots: [],
            doubaoRoots: [],
            copilotUsageLogRoots: [copilot],
            scanInterval: 0
        )
        #expect(try detector.usageSamples().map(\.inputTokens) == [140])

        try appendJSONL(
            """
            {"id":"usage-one","timestamp":"2026-07-26T00:13:00.000Z","type":"assistant.usage","data":{"model":"gpt-5","inputTokens":100,"outputTokens":20}}
            """,
            to: log
        )

        let samples = try detector.usageSamples()
        #expect(samples.map(\.inputTokens) == [100])
        #expect(samples.map(\.outputTokens) == [20])
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
            piSessionsDirectory: empty,
            qoderRoots: [],
            maxFilesPerProvider: 12
        )

        let samples = try detector.usageSamples()
        #expect(samples.count == 5)
        #expect(samples.filter { $0.provider == .codex }.map(\.inputTokens) == [1_000, 200])
        #expect(samples.filter { $0.provider == .codex }.map(\.outputTokens) == [50, 25])
        #expect(samples.first(where: { $0.provider == .claude })?.inputTokens == 60)
        #expect(samples.filter { $0.provider == .grok }.map(\.inputTokens) == [100, 60])
        #expect(samples.filter { $0.provider == .grok }.map(\.outputTokens) == [20, 30])
        #expect(samples.allSatisfy { $0.sourceID != nil })
        #expect(try detector.usageSamples() == samples)
    }

    @Test
    func skipsOversizedNonUsageLinesWithoutSkippingLaterCodexUsage() throws {
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
            piSessionsDirectory: empty,
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
    func readsTheFullCodexLogBeforeDifferencingCumulativeUsage() throws {
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
            piSessionsDirectory: empty,
            qoderRoots: [],
            maxBytesPerFile: 4_096
        )

        let samples = try detector.usageSamples()
        #expect(samples.map(\.inputTokens) == [1_000_000, 50])
        #expect(samples.map(\.outputTokens) == [200, 20])
    }

    @Test
    func defaultScanCountsEveryCodexSessionInsteadOfOnlyTheFourMostRecent() throws {
        let root = temporaryDirectory(named: "usage-log-all-codex-sessions")
        defer { try? FileManager.default.removeItem(at: root) }
        let codex = root.appendingPathComponent("codex", isDirectory: true)
        let empty = root.appendingPathComponent("empty", isDirectory: true)

        for index in 1...5 {
            try writeJSONL([
                """
                {"timestamp":"2026-07-25T00:0\(index):00.000Z","type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":\(index * 100),"output_tokens":\(index * 10)},"last_token_usage":{"input_tokens":\(index * 100),"output_tokens":\(index * 10)}}}}
                """,
            ], to: codex.appendingPathComponent("2026/07/25/rollout-\(index).jsonl"))
        }

        let detector = AIUsageLogDetector(
            codexSessionsDirectory: codex,
            claudeProjectsDirectory: empty,
            geminiSessionsDirectory: empty,
            grokSessionsDirectory: empty,
            qwenProjectsDirectory: empty,
            piSessionsDirectory: empty,
            qoderRoots: [],
            doubaoRoots: [],
            copilotUsageLogRoots: []
        )

        let samples = try detector.usageSamples()
        #expect(samples.count == 5)
        #expect(samples.map(\.inputTokens).reduce(0, +) == 1_500)
        #expect(samples.map(\.outputTokens).reduce(0, +) == 150)
    }

    @Test
    func appendingCodexUsageReadsOnlyTheNewEventAndKeepsItsPriorTotal() throws {
        let root = temporaryDirectory(named: "usage-log-codex-append")
        defer { try? FileManager.default.removeItem(at: root) }
        let codex = root.appendingPathComponent("codex", isDirectory: true)
        let empty = root.appendingPathComponent("empty", isDirectory: true)
        let log = codex.appendingPathComponent("2026/07/25/rollout.jsonl")
        try writeJSONL([
            """
            {"timestamp":"2026-07-25T00:00:00.000Z","type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":100,"output_tokens":10},"last_token_usage":{"input_tokens":100,"output_tokens":10}}}}
            """,
        ], to: log)

        let detector = AIUsageLogDetector(
            codexSessionsDirectory: codex,
            claudeProjectsDirectory: empty,
            geminiSessionsDirectory: empty,
            grokSessionsDirectory: empty,
            qwenProjectsDirectory: empty,
            piSessionsDirectory: empty,
            qoderRoots: [],
            scanInterval: 0
        )
        #expect(try detector.usageSamples().map(\.inputTokens) == [100])

        try appendJSONL(
            """
            {"timestamp":"2026-07-25T00:01:00.000Z","type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":180,"output_tokens":30},"last_token_usage":{"input_tokens":80,"output_tokens":20}}}}
            """,
            to: log
        )

        let samples = try detector.usageSamples()
        #expect(samples.map(\.inputTokens) == [100, 80])
        #expect(samples.map(\.outputTokens) == [10, 20])
    }

    @Test
    func readsCompleteUnterminatedJSONLUsageAndContinuesAfterTheNextAppend() throws {
        let root = temporaryDirectory(named: "usage-log-unterminated-jsonl")
        defer { try? FileManager.default.removeItem(at: root) }
        let codex = root.appendingPathComponent("codex", isDirectory: true)
        let empty = root.appendingPathComponent("empty", isDirectory: true)
        let log = codex.appendingPathComponent("2026/07/25/rollout.jsonl")
        try writeJSON(
            """
            {"timestamp":"2026-07-25T00:00:00.000Z","type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":100,"output_tokens":10},"last_token_usage":{"input_tokens":100,"output_tokens":10}}}}
            """,
            to: log
        )

        let detector = AIUsageLogDetector(
            codexSessionsDirectory: codex,
            claudeProjectsDirectory: empty,
            geminiSessionsDirectory: empty,
            grokSessionsDirectory: empty,
            qwenProjectsDirectory: empty,
            piSessionsDirectory: empty,
            qoderRoots: [],
            scanInterval: 0
        )
        #expect(try detector.usageSamples().map(\.inputTokens) == [100])

        try appendJSONL(
            """
            {"timestamp":"2026-07-25T00:01:00.000Z","type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":180,"output_tokens":30},"last_token_usage":{"input_tokens":80,"output_tokens":20}}}}
            """,
            to: log
        )

        let samples = try detector.usageSamples()
        #expect(samples.map(\.inputTokens) == [100, 80])
        #expect(samples.map(\.outputTokens) == [10, 20])
    }

    @Test
    func rewritingCodexLogWithLargerSizeReparsesFromStart() throws {
        let root = temporaryDirectory(named: "usage-log-codex-rewrite")
        defer { try? FileManager.default.removeItem(at: root) }
        let codex = root.appendingPathComponent("codex", isDirectory: true)
        let empty = root.appendingPathComponent("empty", isDirectory: true)
        let log = codex.appendingPathComponent("2026/07/25/rollout.jsonl")
        let padding = String(repeating: "x", count: 512)

        try writeJSONL([
            """
            {"timestamp":"2026-07-25T00:00:00.000Z","type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":100,"output_tokens":10},"last_token_usage":{"input_tokens":100,"output_tokens":10}}}}
            """,
        ], to: log)

        let detector = AIUsageLogDetector(
            codexSessionsDirectory: codex,
            claudeProjectsDirectory: empty,
            geminiSessionsDirectory: empty,
            grokSessionsDirectory: empty,
            qwenProjectsDirectory: empty,
            piSessionsDirectory: empty,
            qoderRoots: [],
            scanInterval: 0
        )
        #expect(try detector.usageSamples().map(\.inputTokens) == [100])

        try writeJSONL([
            "{\"type\":\"rewritten\",\"padding\":\"\(padding)\"}",
            """
            {"timestamp":"2026-07-25T00:01:00.000Z","type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":300,"output_tokens":30},"last_token_usage":{"input_tokens":300,"output_tokens":30}}}}
            """,
        ], to: log)

        let samples = try detector.usageSamples()
        #expect(samples.map(\.inputTokens) == [300])
        #expect(samples.map(\.outputTokens) == [30])
    }

    @Test @MainActor
    func monitorReconcilesAtomicallyReplacedCodexUsageAcrossRestart() throws {
        let root = temporaryDirectory(named: "usage-monitor-codex-atomic-replace")
        defer { try? FileManager.default.removeItem(at: root) }
        let stateDirectory = root.appendingPathComponent("state", isDirectory: true)
        let codex = root.appendingPathComponent("codex", isDirectory: true)
        let empty = root.appendingPathComponent("empty", isDirectory: true)
        let log = codex.appendingPathComponent("2026/07/25/rollout.jsonl")
        try writeJSONL([
            """
            {"timestamp":"2026-07-25T00:00:00.000Z","type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":100,"output_tokens":0},"last_token_usage":{"input_tokens":100,"output_tokens":0}}}}
            """,
        ], to: log)

        func makeDetector() -> AIUsageLogDetector {
            AIUsageLogDetector(
                codexSessionsDirectory: codex,
                claudeProjectsDirectory: empty,
                geminiSessionsDirectory: empty,
                grokSessionsDirectory: empty,
                qwenProjectsDirectory: empty,
                piSessionsDirectory: empty,
                qoderRoots: [],
                doubaoRoots: [],
                copilotUsageLogRoots: [],
                scanInterval: 0
            )
        }

        let monitor = AIStateMonitor(
            directoryURL: stateDirectory,
            activityDetectors: [],
            usageDetectors: [makeDetector()]
        )
        monitor.reload()
        #expect(try AIStateRepository(directoryURL: stateDirectory).load().usageSamples.first?.totalTokens == 100)

        try replaceJSONLAtomically([
            """
            {"timestamp":"2026-07-25T00:00:00.000Z","type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":300,"output_tokens":0},"last_token_usage":{"input_tokens":300,"output_tokens":0}}}}
            """,
        ], at: log)
        monitor.reload()
        #expect(try AIStateRepository(directoryURL: stateDirectory).load().usageSamples.first?.totalTokens == 300)

        monitor.reload()
        #expect(try AIStateRepository(directoryURL: stateDirectory).load().usageSamples.first?.totalTokens == 300)

        let restartedMonitor = AIStateMonitor(
            directoryURL: stateDirectory,
            activityDetectors: [],
            usageDetectors: [makeDetector()]
        )
        restartedMonitor.reload()
        #expect(try AIStateRepository(directoryURL: stateDirectory).load().usageSamples.first?.totalTokens == 300)
    }

    @Test
    func contentChangesWithSameSizeAndModificationDateAreRescanned() throws {
        let root = temporaryDirectory(named: "usage-log-codex-same-metadata")
        defer { try? FileManager.default.removeItem(at: root) }
        let codex = root.appendingPathComponent("codex", isDirectory: true)
        let empty = root.appendingPathComponent("empty", isDirectory: true)
        let log = codex.appendingPathComponent("2026/07/25/rollout.jsonl")
        let fixedDate = Date(timeIntervalSince1970: 1_800_000_000)

        try writeJSONL([
            """
            {"timestamp":"2026-07-25T00:00:00.000Z","type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":100,"output_tokens":10},"last_token_usage":{"input_tokens":100,"output_tokens":10}}}}
            """,
        ], to: log)
        try FileManager.default.setAttributes(
            [.modificationDate: fixedDate],
            ofItemAtPath: log.path
        )

        let detector = AIUsageLogDetector(
            codexSessionsDirectory: codex,
            claudeProjectsDirectory: empty,
            geminiSessionsDirectory: empty,
            grokSessionsDirectory: empty,
            qwenProjectsDirectory: empty,
            piSessionsDirectory: empty,
            qoderRoots: [],
            scanInterval: 0
        )
        #expect(try detector.usageSamples().map(\.inputTokens) == [100])

        try writeJSONL([
            """
            {"timestamp":"2026-07-25T00:00:00.000Z","type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":900,"output_tokens":90},"last_token_usage":{"input_tokens":900,"output_tokens":90}}}}
            """,
        ], to: log)
        try FileManager.default.setAttributes(
            [.modificationDate: fixedDate],
            ofItemAtPath: log.path
        )

        let samples = try detector.usageSamples()
        #expect(samples.map(\.inputTokens) == [900])
        #expect(samples.map(\.outputTokens) == [90])
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
            piSessionsDirectory: empty,
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

        let summaries = AIUsageAnalytics.dailyAutomaticUsageSamples(samples: [sample])
        #expect(monitor.state.usageSamples == summaries)
        #expect(try AIStateRepository(directoryURL: directory).load().usageSamples == summaries)
    }

    @Test @MainActor
    func monitorAppendsNewDetectedUsageWhenOlderSessionIsNoLongerScanned() throws {
        let directory = temporaryDirectory(named: "usage-monitor-append")
        defer { try? FileManager.default.removeItem(at: directory) }
        let timestamp = Date(timeIntervalSince1970: 100)
        let original = AIUsageSample(
            sourceID: "codex-log-event-a",
            provider: .codex,
            timestamp: timestamp,
            inputTokens: 100,
            outputTokens: 20
        )
        let new = AIUsageSample(
            sourceID: "codex-log-event-b",
            provider: .codex,
            timestamp: timestamp.addingTimeInterval(60),
            inputTokens: 30,
            outputTokens: 5
        )
        let detector = MutableUsageDetector(samples: [original])
        let monitor = AIStateMonitor(
            directoryURL: directory,
            activityDetectors: [],
            usageDetectors: [detector]
        )

        monitor.reload()
        detector.samples = [new]
        monitor.reload()

        #expect(monitor.state.usageSamples == AIUsageAnalytics.dailyUsageSamples(
            samples: [original, new],
            calendar: .current
        ))
    }

    @Test @MainActor
    func monitorKeepsDailyTotalWhenAUsageDetectorFails() throws {
        let directory = temporaryDirectory(named: "usage-incomplete-scan")
        defer { try? FileManager.default.removeItem(at: directory) }
        let repository = AIStateRepository(directoryURL: directory)
        let original = AIUsageSample(
            provider: .codex,
            timestamp: Date(timeIntervalSince1970: 100),
            inputTokens: 100,
            outputTokens: 20
        )
        try repository.recordDetectedUsage([original])
        let monitor = AIStateMonitor(
            directoryURL: directory,
            activityDetectors: [],
            usageDetectors: [
                StaticUsageDetector(samples: [AIUsageSample(
                    provider: .codex,
                    timestamp: original.timestamp,
                    inputTokens: 80,
                    outputTokens: 20
                )]),
                FailingUsageDetector(),
            ]
        )

        monitor.reload()

        #expect(try repository.load().usageSamples == AIUsageAnalytics.dailyUsageSamples(
            samples: [original],
            calendar: .current
        ))
    }

    @Test @MainActor
    func monitorPersistsUsageWithoutRetainingHistory() async throws {
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
            usageDetectors: [StaticUsageDetector(samples: [sample])],
            now: { sample.timestamp }
        )

        monitor.reload(includeUsageSamples: false)

        #expect(monitor.state.usageSamples.isEmpty)
        let summaries = AIUsageAnalytics.dailyAutomaticUsageSamples(samples: [sample])
        #expect(try AIStateRepository(directoryURL: directory).load().usageSamples == summaries)

        monitor.loadUsageHistory()
        for _ in 0..<100 where monitor.state.usageSamples != summaries {
            try await Task.sleep(for: .milliseconds(10))
        }

        #expect(monitor.state.usageSamples == summaries)
        monitor.unloadUsageHistory()
        #expect(monitor.state.usageSamples.isEmpty)
        #expect(try AIStateRepository(directoryURL: directory).load().usageSamples == summaries)
    }

    @Test @MainActor
    func loadingUsageHistoryDoesNotRescanUsageLogs() async throws {
        let directory = temporaryDirectory(named: "usage-history-no-rescan")
        defer { try? FileManager.default.removeItem(at: directory) }
        let detector = CountingUsageDetector()
        let sample = AIUsageSample(
            sourceID: "history-sample",
            provider: .codex,
            timestamp: Date(timeIntervalSince1970: 100),
            inputTokens: 10,
            outputTokens: 2
        )
        let expiredSample = AIUsageSample(
            sourceID: "expired-history-sample",
            provider: .claude,
            timestamp: sample.timestamp.addingTimeInterval(-200 * 24 * 60 * 60),
            inputTokens: 20,
            outputTokens: 4
        )
        try AIStateRepository(directoryURL: directory).recordUsage([expiredSample, sample])
        let monitor = AIStateMonitor(
            directoryURL: directory,
            activityDetectors: [],
            usageDetectors: [detector],
            usageRefreshInterval: 1,
            now: { sample.timestamp }
        )

        monitor.loadUsageHistory()

        for _ in 0..<100 where monitor.state.usageSamples.isEmpty {
            try await Task.sleep(for: .milliseconds(10))
        }

        #expect(monitor.state.usageSamples.count == 1)
        #expect(monitor.state.usageSamples.first?.sourceID != expiredSample.sourceID)
        #expect(detector.callCount == 0)
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
    func repositoryDoesNotReduceDetectedDailyTotalWhenARescanFindsLessUsage() throws {
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

        #expect(try repository.recordDetectedUsage([original]) == 1)
        #expect(try repository.recordDetectedUsage([corrected]) == 0)
        #expect(
            try repository.load().usageSamples
                == AIUsageAnalytics.dailyUsageSamples(samples: [original], calendar: .current)
        )
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

        let summaries = AIUsageAnalytics.dailyManualUsageSamples(samples: [sample])
        #expect(state.usageSamples == summaries)
        #expect(try repository.load().usageSamples == summaries)
    }
}

private struct StaticUsageDetector: AIUsageDetecting {
    var samples: [AIUsageSample]

    func usageSamples() throws -> [AIUsageSample] { samples }
}

private final class MutableUsageDetector: AIUsageDetecting {
    var samples: [AIUsageSample]

    init(samples: [AIUsageSample]) {
        self.samples = samples
    }

    func usageSamples() throws -> [AIUsageSample] { samples }
}

private struct FailingUsageDetector: AIUsageDetecting {
    func usageSamples() throws -> [AIUsageSample] { throw UsageDetectorTestError.failed }
}

private enum UsageDetectorTestError: Error {
    case failed
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

private func replaceJSONLAtomically(_ lines: [String], at url: URL) throws {
    try Data((lines.joined(separator: "\n") + "\n").utf8).write(to: url, options: .atomic)
}

private func writeJSON(_ string: String, to url: URL) throws {
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try Data(string.utf8).write(to: url)
}

private func appendJSONL(_ line: String, to url: URL) throws {
    let handle = try FileHandle(forWritingTo: url)
    defer { try? handle.close() }
    try handle.seekToEnd()
    try handle.write(contentsOf: Data((line + "\n").utf8))
}

private func temporaryDirectory(named name: String) -> URL {
    FileManager.default.temporaryDirectory
        .appendingPathComponent("Zisla-\(name)-\(UUID().uuidString)", isDirectory: true)
}
