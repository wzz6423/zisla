import Foundation

/// Usage aggregate for a one-hour window.
public struct HourlyBucket: Equatable, Sendable {
    public var start: Date
    public var tokens: Int

    public init(start: Date, tokens: Int) {
        self.start = start
        self.tokens = tokens
    }
}

/// A single sample point on the usage trend chart (timestamp + token count).
public struct UsagePoint: Equatable, Sendable {
    public var timestamp: Date
    public var tokens: Int

    public init(timestamp: Date, tokens: Int) {
        self.timestamp = timestamp
        self.tokens = tokens
    }
}

/// Input, output, and total token breakdown for a single calendar day on the trend chart.
public struct UsageBreakdownPoint: Equatable, Sendable {
    public var timestamp: Date
    public var inputTokens: Int
    public var outputTokens: Int

    public init(timestamp: Date, inputTokens: Int, outputTokens: Int) {
        self.timestamp = timestamp
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
    }

    public var totalTokens: Int { inputTokens + outputTokens }
}

/// A sample point on the cumulative usage multi-series chart (total / input / output).
public struct CumulativeUsagePoint: Equatable, Sendable {
    public var timestamp: Date
    public var totalTokens: Int
    public var inputTokens: Int
    public var outputTokens: Int

    public init(
        timestamp: Date,
        totalTokens: Int,
        inputTokens: Int,
        outputTokens: Int
    ) {
        self.timestamp = timestamp
        self.totalTokens = totalTokens
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
    }
}

/// A single-day cell in the contribution calendar (date + total tokens for the day).
public struct ContributionDay: Equatable, Sendable {
    public var date: Date
    public var tokens: Int

    public init(date: Date, tokens: Int) {
        self.date = date
        self.tokens = tokens
    }
}

/// Token usage intensity bucketed in GitHub-style contribution graph steps (for SwiftUI coloring).
///
/// Thresholds: 0 / 50M / 100M / 150M / 200M.
/// `none` means no usage; `level4` is 200M and above, the darkest shade.
public enum ContributionIntensity: Int, Equatable, Sendable, CaseIterable, Comparable {
    case none = 0
    case level1 = 1
    case level2 = 2
    case level3 = 3
    case level4 = 4

    public static let thresholds: [Int] = [
        0,
        50_000_000,
        100_000_000,
        150_000_000,
        200_000_000,
    ]

    public static func < (lhs: ContributionIntensity, rhs: ContributionIntensity) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    /// Maps a token total to the corresponding intensity level.
    /// - 0: no usage
    /// - (0, 50M]: level1
    /// - (50M, 100M]: level2
    /// - (100M, 150M]: level3
    /// - (150M, +∞) (including 200M and above): level4, darkest
    public static func classify(tokens: Int) -> ContributionIntensity {
        if tokens <= 0 { return .none }
        if tokens <= thresholds[1] { return .level1 }
        if tokens <= thresholds[2] { return .level2 }
        if tokens <= thresholds[3] { return .level3 }
        return .level4
    }
}

public enum AIUsageAnalytics {
    /// Prefix used by the provider-level automatic summaries written before schema version 3.
    public static let automaticUsageSummaryPrefix = "zisla-daily-usage:"
    /// Prefix used by the provider-level manual summaries written before schema version 3.
    public static let manualUsageSummaryPrefix = "zisla-daily-manual-usage:"
    /// Prefix reserved for the sole daily total record retained by the current schema.
    public static let dailyUsageSummaryPrefix = "zisla-daily-total:"

    /// Compacts automatically detected log events into one stable record per calendar day.
    ///
    /// Session logs can emit thousands of token events each day. The progress UI only presents daily
    /// totals, so persisting these summaries preserves the visible history without allowing event volume
    /// to evict older days from the bounded state store.
    public static func dailyAutomaticUsageSamples(
        samples: [AIUsageSample],
        calendar: Calendar = .current
    ) -> [AIUsageSample] {
        dailyUsageSamples(samples: samples, calendar: calendar)
    }

    /// Compacts manually reported usage into one incrementable record per calendar day.
    public static func dailyManualUsageSamples(
        samples: [AIUsageSample],
        calendar: Calendar = .current
    ) -> [AIUsageSample] {
        dailyUsageSamples(samples: samples, calendar: calendar)
    }

    /// Whether a record uses the provider-level automatic-log identifier from the previous schema.
    public static func isAutomaticUsageSummary(_ sample: AIUsageSample) -> Bool {
        sample.sourceID?.hasPrefix(automaticUsageSummaryPrefix) ?? false
    }

    /// Whether a record uses the provider-level manual identifier from the previous schema.
    public static func isManualUsageSummary(_ sample: AIUsageSample) -> Bool {
        sample.sourceID?.hasPrefix(manualUsageSummaryPrefix) ?? false
    }

    public static func isDailyUsageSummary(_ sample: AIUsageSample) -> Bool {
        sample.sourceID?.hasPrefix(dailyUsageSummaryPrefix) ?? false
    }

    /// Whether a pre-summary source identifier was produced by a built-in log detector.
    public static func isLegacyAutomaticUsageSample(_ sample: AIUsageSample) -> Bool {
        guard let sourceID = sample.sourceID else { return false }
        return AIProvider.allCases.contains { sourceID.hasPrefix("\($0.rawValue)-") }
    }

    /// Whether a pre-v3 record originated from automatic log detection.
    public static func isLegacyDetectedUsageSample(_ sample: AIUsageSample) -> Bool {
        isLegacyAutomaticUsageSample(sample) || isAutomaticUsageSummary(sample)
    }

    /// Total, input, and output token trends for the most recent `days` calendar days (inclusive of `end`).
    ///
    /// Days with zero usage are still included so the time axis is continuous and the curve can drop to the zero baseline.
    /// Each aggregate is positioned at the midpoint of its calendar day so it aligns with the center of that day on a time axis.
    public static func dailyUsageSeries(
        samples: [AIUsageSample],
        endingAt end: Date,
        days: Int = 7,
        calendar: Calendar = .current
    ) -> [UsageBreakdownPoint] {
        guard days > 0 else { return [] }
        let endDay = calendar.startOfDay(for: end)
        guard let startDay = calendar.date(byAdding: .day, value: -(days - 1), to: endDay) else {
            return []
        }

        var inputByDay: [Date: Int] = [:]
        var outputByDay: [Date: Int] = [:]
        for sample in samples where sample.timestamp <= end {
            let day = calendar.startOfDay(for: sample.timestamp)
            guard day >= startDay, day <= endDay else { continue }
            inputByDay[day, default: 0] += sample.inputTokens
            outputByDay[day, default: 0] += sample.outputTokens
        }

        return (0..<days).compactMap { offset in
            guard
                let day = calendar.date(byAdding: .day, value: offset, to: startDay),
                let nextDay = calendar.date(byAdding: .day, value: 1, to: day)
            else {
                return nil
            }
            return UsageBreakdownPoint(
                timestamp: day.addingTimeInterval(nextDay.timeIntervalSince(day) / 2),
                inputTokens: inputByDay[day, default: 0],
                outputTokens: outputByDay[day, default: 0]
            )
        }
    }

    /// Compacts all usage into the single visible aggregate for each calendar day.
    public static func dailyUsageSamples(
        samples: [AIUsageSample],
        calendar: Calendar
    ) -> [AIUsageSample] {
        var summaries: [Date: AIUsageSample] = [:]

        for sample in samples {
            let day = calendar.startOfDay(for: sample.timestamp)
            if var summary = summaries[day] {
                summary.inputTokens += sample.inputTokens
                summary.outputTokens += sample.outputTokens
                summaries[day] = summary
            } else {
                summaries[day] = AIUsageSample(
                    sourceID: dailyUsageSummarySourceID(day: day),
                    provider: sample.provider,
                    timestamp: day,
                    inputTokens: sample.inputTokens,
                    outputTokens: sample.outputTokens
                )
            }
        }

        return summaries.values.sorted {
            $0.timestamp < $1.timestamp
        }
    }

    private static func dailyUsageSummarySourceID(day: Date) -> String {
        "\(dailyUsageSummaryPrefix)\(day.timeIntervalSinceReferenceDate)"
    }

    /// Smooths daily usage with a 5-day binomial kernel [1,4,6,4,1] for trend curve display.
    /// This gives the line a smooth, flowing appearance and avoids sharp spikes or zero-value dips.
    /// Raw daily totals are still used for the heatmap to avoid unnatural drops from single-day cache backfill.
    public static func smoothedDailyUsageSeries(
        samples: [AIUsageSample],
        endingAt end: Date,
        days: Int = 7,
        calendar: Calendar = .current
    ) -> [UsageBreakdownPoint] {
        let daily = dailyUsageSeries(
            samples: samples,
            endingAt: end,
            days: days,
            calendar: calendar
        )
        guard daily.count > 2 else { return daily }

        let weights = [1.0, 4.0, 6.0, 4.0, 1.0]
        let totalWeight = weights.reduce(0, +)
        let radius = weights.count / 2

        return daily.indices.map { index in
            var input = 0.0
            var output = 0.0
            for offset in -radius...radius {
                let sourceIndex = max(0, min(daily.count - 1, index + offset))
                let weight = weights[offset + radius]
                input += Double(daily[sourceIndex].inputTokens) * weight
                output += Double(daily[sourceIndex].outputTokens) * weight
            }
            return UsageBreakdownPoint(
                timestamp: daily[index].timestamp,
                inputTokens: Int((input / totalWeight).rounded()),
                outputTokens: Int((output / totalWeight).rounded())
            )
        }
    }

    /// The most recent `hours` rolling one-hour buckets up to `end`, oldest first.
    /// Each bucket is a half-open interval [start, start+1h).
    public static func hourlySeries(
        samples: [AIUsageSample],
        endingAt end: Date,
        hours: Int,
        calendar: Calendar = .current
    ) -> [HourlyBucket] {
        guard hours > 0 else { return [] }
        let start = end.addingTimeInterval(-Double(hours) * 3_600)
        var tokens = Array(repeating: 0, count: hours)

        for sample in samples where sample.timestamp >= start && sample.timestamp < end {
            let index = Int(sample.timestamp.timeIntervalSince(start) / 3_600)
            guard index < hours else { continue }
            tokens[index] += sample.totalTokens
        }

        return tokens.enumerated().map { index, value in
            HourlyBucket(
                start: start.addingTimeInterval(Double(index) * 3_600),
                tokens: value
            )
        }
    }

    /// The most recent historical usage samples up to `end`, in ascending order, capped at `limit`.
    ///
    /// - Only samples with a timestamp not later than `end` and a positive token count are included; future and zero-value samples are ignored.
    /// - When the result exceeds `limit`, the most recent `limit` samples are kept (older ones are dropped).
    /// - A baseline point with `tokens == 0` is prepended before the first real sample (timestamp one second earlier),
    ///   so that a chart with only one data point still draws an upward trend from zero. The baseline does not count toward `limit`.
    /// - Returns an empty array when there are no valid samples.
    public static func recentUsageSeries(
        samples: [AIUsageSample],
        endingAt end: Date,
        limit: Int
    ) -> [UsagePoint] {
        guard limit > 0 else { return [] }

        let recent = samples
            .filter { $0.timestamp <= end && $0.totalTokens > 0 }
            .sorted { $0.timestamp < $1.timestamp }
            .suffix(limit)

        guard let first = recent.first else { return [] }

        // The baseline point only needs to be 1 second before the first sample to keep the x-axis strictly increasing and draw an upward trend.
        var points: [UsagePoint] = [UsagePoint(timestamp: first.timestamp.addingTimeInterval(-1), tokens: 0)]
        points.append(contentsOf: recent.map { UsagePoint(timestamp: $0.timestamp, tokens: $0.totalTokens) })
        return points
    }

    /// Cumulative usage series up to `end`: each point's `tokens` is the running total up to that timestamp,
    /// expressing the growth of all-time usage (unlike `recentUsageSeries` which shows per-sample tokens).
    ///
    /// - Only samples with a timestamp not later than `end` and a positive token count are included; future and zero-value samples are ignored.
    /// - Sorted in ascending order; multiple samples at the same timestamp are merged into one point (tokens summed), producing no duplicate timestamps.
    /// - A zero baseline point is prepended before the first sample (timestamp 1 second earlier),
    ///   so a chart with a single data point still draws an upward trend from zero.
    /// - Each real point's `tokens` is the cumulative total (prefix sum) up to that timestamp.
    /// - If `end` is later than the last sample, a terminal point at `end` with the cumulative total is appended,
    ///   extending the curve to the current moment at the total height; not appended if `end` equals the last point.
    /// - Returns an empty array when there are no valid samples.
    public static func cumulativeUsageSeries(
        samples: [AIUsageSample],
        endingAt end: Date
    ) -> [UsagePoint] {
        let valid = samples
            .filter { $0.timestamp <= end && $0.totalTokens > 0 }
            .sorted { $0.timestamp < $1.timestamp }

        guard let first = valid.first else { return [] }

        var points: [UsagePoint] = [UsagePoint(timestamp: first.timestamp.addingTimeInterval(-1), tokens: 0)]
        var cumulative = 0
        var index = 0
        while index < valid.count {
            // After sorting, samples at the same timestamp are adjacent; merge them into a single point via prefix sum.
            let timestamp = valid[index].timestamp
            while index < valid.count, valid[index].timestamp == timestamp {
                cumulative += valid[index].totalTokens
                index += 1
            }
            points.append(UsagePoint(timestamp: timestamp, tokens: cumulative))
        }

        if let last = points.last, end > last.timestamp {
            points.append(UsagePoint(timestamp: end, tokens: cumulative))
        }
        return points
    }

    /// Cumulative multi-series up to `end`: each point carries the running total for total / input / output tokens.
    ///
    /// - Only samples with a timestamp not later than `end` and a positive token count are included; future and zero-value samples are ignored.
    /// - Sorted in ascending order; samples at the same timestamp are merged (input/output summed separately).
    /// - A zero baseline point is prepended before the first sample (timestamp 1 second earlier).
    /// - If `end` is later than the last point, a terminal point is appended at the cumulative height.
    /// - Returns an empty array when there are no valid samples.
    public static func cumulativeDetailSeries(
        samples: [AIUsageSample],
        endingAt end: Date
    ) -> [CumulativeUsagePoint] {
        let valid = samples
            .filter { $0.timestamp <= end && $0.totalTokens > 0 }
            .sorted { $0.timestamp < $1.timestamp }

        guard let first = valid.first else { return [] }

        var points: [CumulativeUsagePoint] = [
            CumulativeUsagePoint(
                timestamp: first.timestamp.addingTimeInterval(-1),
                totalTokens: 0,
                inputTokens: 0,
                outputTokens: 0
            )
        ]
        var cumulativeInput = 0
        var cumulativeOutput = 0
        var index = 0
        while index < valid.count {
            let timestamp = valid[index].timestamp
            while index < valid.count, valid[index].timestamp == timestamp {
                cumulativeInput += max(0, valid[index].inputTokens)
                cumulativeOutput += max(0, valid[index].outputTokens)
                index += 1
            }
            points.append(
                CumulativeUsagePoint(
                    timestamp: timestamp,
                    totalTokens: cumulativeInput + cumulativeOutput,
                    inputTokens: cumulativeInput,
                    outputTokens: cumulativeOutput
                )
            )
        }

        if let last = points.last, end > last.timestamp {
            points.append(
                CumulativeUsagePoint(
                    timestamp: end,
                    totalTokens: cumulativeInput + cumulativeOutput,
                    inputTokens: cumulativeInput,
                    outputTokens: cumulativeOutput
                )
            )
        }
        return points
    }

    /// Generates power-of-ten tick marks for the symmetric-log trend axis.
    ///
    /// - Returns `[0, 1]` when `maximum <= 0` to ensure Chart has a valid domain.
    /// - `desiredCount` controls the desired number of ticks (including both ends), clamped to 2...6.
    /// - The final tick is the first power of ten that covers `maximum`.
    public static func tokenAxisTicks(maximum: Int, desiredCount: Int = 3) -> [Int] {
        let count = min(6, max(2, desiredCount))
        guard maximum > 0 else { return [0, 1] }

        let upperExponent = max(0, Int(ceil(log10(Double(maximum)))))
        let lowerExponent = max(0, upperExponent - (count - 2))
        var ticks = [0]
        for exponent in lowerExponent...upperExponent {
            let value = pow(10.0, Double(exponent))
            guard value <= Double(Int.max) else {
                ticks.append(Int.max)
                break
            }
            ticks.append(Int(value.rounded()))
        }
        return ticks
    }

    /// Compact token Y-axis label (K / M / B), shared between Chart and tests.
    public static func formatTokenAxisValue(_ tokens: Int) -> String {
        let value = abs(tokens)
        let sign = tokens < 0 ? "-" : ""
        switch value {
        case 1_000_000_000...:
            let n = Double(value) / 1_000_000_000
            return sign + formatCompact(n) + "B"
        case 1_000_000...:
            let n = Double(value) / 1_000_000
            return sign + formatCompact(n) + "M"
        case 1_000...:
            let n = Double(value) / 1_000
            return sign + formatCompact(n) + "K"
        default:
            return sign + "\(value)"
        }
    }

    private static func formatCompact(_ n: Double) -> String {
        if n >= 100 {
            return "\(Int(n.rounded()))"
        }
        let tenths = (n * 10).rounded() / 10
        if tenths.rounded() == tenths {
            return "\(Int(tenths))"
        }
        return String(format: "%.1f", tenths)
    }

    /// 7-day × 24-hour token heatmap up to `end`. Outer index 0 is the oldest day, 6 is today.
    public static func weekHeatmap(
        samples: [AIUsageSample],
        endingAt end: Date,
        calendar: Calendar = .current
    ) -> [[Int]] {
        var grid = Array(repeating: Array(repeating: 0, count: 24), count: 7)
        let startOfToday = calendar.startOfDay(for: end)
        for sample in samples where sample.timestamp <= end {
            let startOfSampleDay = calendar.startOfDay(for: sample.timestamp)
            guard
                let days = calendar.dateComponents([.day], from: startOfSampleDay, to: startOfToday).day,
                days >= 0, days < 7
            else { continue }
            let hour = calendar.component(.hour, from: sample.timestamp)
            guard hour >= 0, hour < 24 else { continue }
            grid[6 - days][hour] += sample.totalTokens
        }
        return grid
    }

    /// Contribution calendar with 26 columns (calendar weeks) of 7 days each.
    ///
    /// - Column order: oldest week first, most recent week last.
    /// - Row order: aligned to `Calendar.firstWeekday` (row 0 is the first day of the week).
    /// - Range includes the day of `endingAt`; future dates do not appear (their cells are `nil`).
    /// - Each cell contains the date (00:00 of that day) and the total tokens for that day.
    public static func contributionCalendar(
        samples: [AIUsageSample],
        endingAt end: Date,
        weeks: Int = 26,
        calendar: Calendar = .current
    ) -> [[ContributionDay?]] {
        guard weeks > 0 else { return [] }

        let endDay = calendar.startOfDay(for: end)
        // Find the start of the week containing endingAt, to use as the last column
        let weekday = calendar.component(.weekday, from: endDay)
        let daysFromWeekStart = (weekday - calendar.firstWeekday + 7) % 7
        guard let lastWeekStart = calendar.date(byAdding: .day, value: -daysFromWeekStart, to: endDay) else {
            return []
        }
        guard let gridStart = calendar.date(byAdding: .day, value: -(weeks - 1) * 7, to: lastWeekStart) else {
            return []
        }

        var tokensByDay: [Date: Int] = [:]
        for sample in samples where sample.timestamp <= end {
            let day = calendar.startOfDay(for: sample.timestamp)
            guard day <= endDay else { continue }
            tokensByDay[day, default: 0] += sample.totalTokens
        }

        var grid: [[ContributionDay?]] = []
        grid.reserveCapacity(weeks)
        for week in 0..<weeks {
            var column: [ContributionDay?] = []
            column.reserveCapacity(7)
            for dayOffset in 0..<7 {
                let offset = week * 7 + dayOffset
                guard let date = calendar.date(byAdding: .day, value: offset, to: gridStart) else {
                    column.append(nil)
                    continue
                }
                // Do not show future dates (strictly after the endingAt day)
                if date > endDay {
                    column.append(nil)
                } else {
                    column.append(ContributionDay(date: date, tokens: tokensByDay[date] ?? 0))
                }
            }
            grid.append(column)
        }
        return grid
    }
}
