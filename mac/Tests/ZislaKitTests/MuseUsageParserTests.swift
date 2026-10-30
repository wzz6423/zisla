import Foundation
import Testing
@testable import ZislaCore
@testable import ZislaKit

struct MuseUsageParserTests {
    @Test func cacheAndReasoningAreSubsetsAndCompletedEventIdentityIsStable() throws {
        let record = event("example", input: 100, output: 20,
            extra: ["cache_read_tokens": 30, "cache_write_tokens": 10, "reasoning_tokens": 5, "total_tokens": 120])
        let sample = try #require(MuseUsageParser.sample(from: record))
        #expect(sample.provider == .muse && sample.inputTokens == 100 && sample.outputTokens == 20)
        #expect(sample.totalTokens == 120)
        #expect(sample.timestamp == Date(timeIntervalSince1970: 1_909_999_990))
        #expect(sample.model == "fixture-model")
        #expect(sample.sourceID == MuseUsageParser.sample(from: record)?.sourceID)
        var review = record
        var payload = try #require(review["payload"] as? [String: Any])
        var body = try #require(payload["event"] as? [String: Any])
        body["kind"] = "automated_review_completed"
        body["model"] = ["model_id": "fixture-model"]
        payload["event"] = body
        review["payload"] = payload
        #expect(MuseUsageParser.sample(from: review) == sample)
    }

    @Test func rejectsInvalidSchemasCountersAliasesAndTotals() {
        for (key, value) in [("schema_version", 2 as Any), ("record_type", "checkpoint"),
                             ("payload_schema_version", 99), ("recorded_at", true), ("id", "")] {
            var record = event("example")
            record[key] = value
            #expect(MuseUsageParser.sample(from: record) == nil)
        }
        for usage in [
            ["input_tokens": -1], ["output_tokens": true], ["output_tokens": 1.5],
            ["cache_read_tokens": 101], ["cache_write_tokens": 101],
            ["reasoning_tokens": 21], ["total_tokens": 121],
            ["cache_read_tokens": 1, "cached_tokens": 2], ["output_tokens": NSNumber(value: Int.max)],
        ] as [[String: Any]] {
            #expect(MuseUsageParser.sample(from: event("invalid", extra: usage)) == nil)
        }
        var unknown = event("unknown")
        unknown["payload"] = ["event": ["kind": "model_started", "usage": ["input_tokens": 100, "output_tokens": 20]]]
        #expect(MuseUsageParser.sample(from: unknown) == nil)
    }

    @Test func honorsAbsoluteDirectoryOverridesWithoutInterpretingRelativePaths() {
        let home = URL(fileURLWithPath: "/fixture/home")
        #expect(MuseUsageParser.defaultSessionsDirectory(home: home, environment: [:]).path == "/fixture/home/.local/share/muse/sessions")
        #expect(MuseUsageParser.defaultSessionsDirectory(home: home,
            environment: ["MUSE_SESSIONS_DIR": "/fixture/sessions", "XDG_DATA_HOME": "/fixture/data"]).path == "/fixture/sessions")
        #expect(MuseUsageParser.defaultSessionsDirectory(home: home,
            environment: ["MUSE_SESSIONS_DIR": "relative", "XDG_DATA_HOME": "/fixture/data"]).path == "/fixture/data/muse/sessions")
        #expect(MuseUsageParser.defaultSessionsDirectory(home: home,
            environment: ["XDG_DATA_HOME": "relative"]).path == "/fixture/home/.local/share/muse/sessions")
    }

    @Test func incrementalReaderDeduplicatesCopiesAndRecoversFromTruncatedAppendAndReplacement() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("zisla-muse-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("original/session.jsonl")
        let copy = root.appendingPathComponent("copy/session.jsonl")
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: copy.deletingLastPathComponent(), withIntermediateDirectories: true)
        let first = try line(event("first"))
        let second = try line(event("second", input: 5, output: 3))
        let split = second.count / 2
        try (first + Data("{broken}\n".utf8) + second.prefix(split)).write(to: file)
        try first.write(to: copy)
        let detector = AIUsageLogDetector(museSessionsDirectory: root, scanInterval: 0, enabledProviders: [.muse])
        #expect(try detector.usageSamples().count == 1)
        let handle = try FileHandle(forWritingTo: file)
        try handle.seekToEnd()
        try handle.write(contentsOf: second.dropFirst(split))
        try handle.close()
        let samples = try detector.usageSamples()
        #expect(samples.count == 2)
        #expect(samples.reduce(0) { $0 + $1.totalTokens } == 128)
        let repository = AIStateRepository(directoryURL: root.appendingPathComponent("zisla"))
        #expect(try repository.recordDetectedUsage(samples) > 0)
        #expect(try repository.recordDetectedUsage(detector.usageSamples()) == 0)
        let replacement = root.appendingPathComponent("replacement")
        try line(event("replacement", input: 7, output: 1)).write(to: replacement)
        _ = try FileManager.default.replaceItemAt(file, withItemAt: replacement)
        let replaced = try detector.usageSamples()
        #expect(replaced.count == 2)
        #expect(replaced.contains { $0.totalTokens == 8 })
        #expect(!replaced.contains { $0.sourceID == MuseUsageParser.sample(from: event("second", input: 5, output: 3))?.sourceID })
    }

    @Test func seededCounterPropertiesRejectCorruptionWithinFixedBudget() {
        var seed: UInt64 = 0xC0DEC0DE
        for index in 0..<128 {
            seed = seed &* 6_364_136_223_846_793_005 &+ 1
            let input = Int(seed % 1_000)
            seed = seed &* 6_364_136_223_846_793_005 &+ 1
            let output = Int(seed % 1_000)
            let valid = event("fuzz-\(index)", input: input, output: output, extra: ["cached_tokens": input])
            #expect(MuseUsageParser.sample(from: valid)?.totalTokens == input + output)
            #expect(MuseUsageParser.sample(from: event("fuzz-\(index)", input: input, output: output,
                extra: ["cache_read_tokens": input + 1])) == nil)
        }
    }

    private func event(_ id: String, input: Int = 100, output: Int = 20, extra: [String: Any] = [:]) -> [String: Any] {
        ["schema_version": 1, "record_type": "event", "payload_type": "runtime.session",
         "payload_schema_version": 1, "recorded_at": 1_909_999_990_000_000, "id": id,
         "payload": ["event": ["kind": "model_completed", "model": "fixture-model",
            "usage": ["input_tokens": input, "output_tokens": output].merging(extra) { _, new in new }]]]
    }

    private func line(_ record: [String: Any]) throws -> Data {
        try JSONSerialization.data(withJSONObject: record) + Data([10])
    }
}
