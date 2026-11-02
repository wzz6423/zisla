import CoreFoundation
import Foundation
import ZislaCore

/// Adapted from CodexBar's MuseLocalUsageReader at d253dd1137242889804326a89972dfa21cda4722 (MIT).
enum MuseUsageParser {
    static func defaultSessionsDirectory(
        home: URL = FileManager.default.homeDirectoryForCurrentUser,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> URL {
        if let override = environment["MUSE_SESSIONS_DIR"], override.hasPrefix("/") {
            return URL(fileURLWithPath: override, isDirectory: true)
        }
        let dataHome = environment["XDG_DATA_HOME"].flatMap { $0.hasPrefix("/") ? URL(fileURLWithPath: $0) : nil }
            ?? home.appendingPathComponent(".local/share", isDirectory: true)
        return dataHome.appendingPathComponent("muse/sessions", isDirectory: true)
    }

    static func sample(from object: [String: Any]) -> AIUsageSample? {
        guard integer(object["schema_version"]) == 1,
              object["record_type"] as? String == "event",
              object["payload_type"] as? String == "runtime.session",
              integer(object["payload_schema_version"]) == 1,
              let payload = object["payload"] as? [String: Any],
              let event = payload["event"] as? [String: Any],
              let kind = event["kind"] as? String,
              ["model_completed", "automated_review_completed"].contains(kind),
              let usage = event["usage"] as? [String: Any],
              let id = object["id"] as? String, !id.isEmpty,
              let recordedAt = integer(object["recorded_at"]),
              recordedAt > 0, recordedAt <= 253_402_300_799_999_999,
              let input = integer(usage["input_tokens"]),
              let output = integer(usage["output_tokens"]),
              let cacheRead = counter(usage, keys: ["cache_read_tokens", "cached_input_tokens", "cached_tokens"]),
              let cacheWrite = counter(usage, keys: ["cache_write_tokens"]),
              let reasoning = counter(usage, keys: ["reasoning_tokens"]),
              cacheRead <= input, cacheWrite <= input, reasoning <= output
        else { return nil }
        let total = input.addingReportingOverflow(output)
        guard !total.overflow,
              usage["total_tokens"] == nil || integer(usage["total_tokens"]) == total.partialValue else { return nil }
        let model = event["model"] as? String ?? (event["model"] as? [String: Any])?["model_id"] as? String
        // Cache and reasoning counters are subsets of Muse's input/output, not additional tokens.
        return AIUsageSample(
            sourceID: "muse-event-" + DesktopAIStorage.identity([id]), provider: .muse,
            timestamp: Date(timeIntervalSince1970: Double(recordedAt) / 1_000_000),
            inputTokens: input, outputTokens: output, model: model
        )
    }

    private static func integer(_ value: Any?) -> Int? {
        guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID(),
              number.doubleValue.isFinite, number.doubleValue >= 0,
              number.doubleValue.rounded(.towardZero) == number.doubleValue,
              number.doubleValue < Double(Int.max) else { return nil }
        return number.intValue
    }

    private static func counter(_ usage: [String: Any], keys: [String]) -> Int? {
        var counter: Int?
        for key in keys where usage[key] != nil {
            guard let value = integer(usage[key]), counter == nil || counter == value else { return nil }
            counter = value
        }
        return counter ?? 0
    }
}
