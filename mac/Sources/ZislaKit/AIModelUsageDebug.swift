import Foundation
import ZislaCore

#if DEBUG
enum AIModelUsageDebug {
    /// Fixtures replace in-memory history without creating cumulative events or entering exported reports.
    /// Invalid nonempty input stays isolated instead of silently displaying the user's real usage.
    static func history(environment: [String: String], now: Date) -> AIUsageHistory? {
        guard let raw = environment["ZISLA_DEBUG_AI_MODEL_USAGE"], !raw.isEmpty else { return nil }
        guard raw.utf8.count <= 65_536 else { return AIUsageHistory() }
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: now)
        var samples: [AIUsageSample] = []
        for entry in raw.split(separator: ",", omittingEmptySubsequences: false) {
            let parts = entry.split(separator: ":", omittingEmptySubsequences: false)
            guard (4...5).contains(parts.count), let provider = AIProvider(rawValue: String(parts[0])),
                  let model = AIUsageAnalytics.normalizedModel(String(parts[1])),
                  let input = Int(parts[2]), input >= 0,
                  let output = Int(parts[3]), output >= 0,
                  let daysAgo = parts.count == 5 ? Int(parts[4]) : 0, (0...167).contains(daysAgo),
                  let date = calendar.date(byAdding: .day, value: -daysAgo, to: today) else {
                return AIUsageHistory()
            }
            samples.append(AIUsageSample(provider: provider, timestamp: date,
                inputTokens: input, outputTokens: output, model: model))
        }
        return AIUsageHistory(
            usageSamples: AIUsageAnalytics.dailyUsageSamples(samples: samples, calendar: calendar),
            modelUsageSamples: AIUsageAnalytics.dailyModelUsageSamples(samples: samples, calendar: calendar))
    }
}
#endif
