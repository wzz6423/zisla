import Foundation
import ZislaCore

public enum AIUsageHistoryPresentation {
    /// Daily aggregates use whole calendar days; a rolling 24-hour cutoff would discard today's midnight row.
    public static func domain(history: AIUsageHistory, range: SystemMetricsHistoryRange, now: Date,
        calendar: Calendar = .current) -> ClosedRange<Date> {
        let today = calendar.startOfDay(for: now)
        let days: Int? = switch range {
        case .day: 1
        case .week: 7
        case .month: 30
        case .all: nil
        }
        let first = days.flatMap { calendar.date(byAdding: .day, value: -($0 - 1), to: today) }
            ?? history.usageSamples.map { calendar.startOfDay(for: $0.timestamp) }.filter { $0 <= today }.min() ?? today
        let end = calendar.date(byAdding: .day, value: 1, to: today) ?? now
        return first...end
    }

    /// Selection never falls back to another day's usage when the requested calendar day has no samples.
    public static func selectedDay(in history: AIUsageHistory, date: Date, calendar: Calendar = .current) -> AIDailyModelUsage {
        let day = calendar.startOfDay(for: date)
        let next = calendar.date(byAdding: .day, value: 1, to: day) ?? day
        let selected = AIUsageHistory(
            usageSamples: history.usageSamples.filter { $0.timestamp >= day && $0.timestamp < next },
            modelUsageSamples: history.modelUsageSamples.filter { $0.timestamp >= day && $0.timestamp < next })
        return AIUsageAnalytics.dailyModelUsage(history: selected, endingAt: next, calendar: calendar).first
            ?? AIDailyModelUsage(date: day, inputTokens: 0, outputTokens: 0, models: [])
    }

    /// Retains endpoints and each bucket's busiest day so long archives stay bounded without hiding their peaks.
    public static func trend(history: AIUsageHistory, domain: ClosedRange<Date>, maximumPoints: Int = 240,
        calendar: Calendar = .current) -> [UsageBreakdownPoint] {
        let lastDay = calendar.date(byAdding: .day, value: -1, to: domain.upperBound) ?? domain.lowerBound
        let days = max(1, (calendar.dateComponents([.day], from: domain.lowerBound, to: lastDay).day ?? 0) + 1)
        let budget = max(3, maximumPoints)
        let samples = history.usageSamples.filter { $0.timestamp >= domain.lowerBound && $0.timestamp < domain.upperBound }
        if days <= budget {
            let end = Date(timeIntervalSinceReferenceDate: domain.upperBound.timeIntervalSinceReferenceDate.nextDown)
            return AIUsageAnalytics.dailyUsageSeries(samples: samples, endingAt: end,
                days: days, calendar: calendar)
        }

        let daily = AIUsageAnalytics.dailyUsageSamples(samples: samples, calendar: calendar)
        let totals = Dictionary(uniqueKeysWithValues: daily.map { ($0.timestamp, $0) })
        let bucketSize = max(1, Int(ceil(Double(days - 2) / Double(budget - 2))))
        var busiestByBucket: [Int: AIUsageSample] = [:]
        for sample in daily {
            guard let index = calendar.dateComponents([.day], from: domain.lowerBound, to: sample.timestamp).day,
                  index > 0, index < days - 1 else { continue }
            let bucket = (index - 1) / bucketSize
            if sample.totalTokens > (busiestByBucket[bucket]?.totalTokens ?? -1) {
                busiestByBucket[bucket] = sample
            }
        }
        func point(for day: Date, sample: AIUsageSample?) -> UsageBreakdownPoint {
            let next = calendar.date(byAdding: .day, value: 1, to: day) ?? day
            return UsageBreakdownPoint(timestamp: day.addingTimeInterval(next.timeIntervalSince(day) / 2),
                inputTokens: sample?.inputTokens ?? 0, outputTokens: sample?.outputTokens ?? 0)
        }
        var result = [point(for: domain.lowerBound, sample: totals[domain.lowerBound])]
        for offset in stride(from: 1, to: days - 1, by: bucketSize) {
            let sample = busiestByBucket[(offset - 1) / bucketSize]
            if let day = sample?.timestamp ?? calendar.date(byAdding: .day, value: offset, to: domain.lowerBound) {
                result.append(point(for: day, sample: sample))
            }
        }
        result.append(point(for: lastDay, sample: totals[lastDay]))
        return result
    }

    /// All-history heatmaps page by calendar year instead of shrinking decades of days into subpixel cells.
    public static func heatmap(history: AIUsageHistory, domain: ClosedRange<Date>, year: Date?, now: Date,
        calendar: Calendar = .current) -> [[ContributionDay?]] {
        var start = domain.lowerBound
        var end = calendar.date(byAdding: .day, value: -1, to: domain.upperBound) ?? now
        if let year, let interval = calendar.dateInterval(of: .year, for: year) {
            start = max(start, interval.start)
            end = min(end, calendar.date(byAdding: .day, value: -1, to: interval.end) ?? end)
        }
        guard start <= end else { return [] }
        let days = (calendar.dateComponents([.day], from: start, to: end).day ?? 0) + 1
        let weeks = min(54, max(1, Int(ceil(Double(days + 6) / 7))))
        let nextDay = calendar.date(byAdding: .day, value: 1, to: end) ?? domain.upperBound
        let cutoff = Date(timeIntervalSinceReferenceDate: nextDay.timeIntervalSinceReferenceDate.nextDown)
        return AIUsageAnalytics.contributionCalendar(samples: history.usageSamples, endingAt: cutoff,
            weeks: weeks, calendar: calendar).map { week in
                week.map { day in
                    guard let day, day.date >= start else { return nil }
                    return day
                }
            }
    }
}
