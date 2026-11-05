import Foundation
import ZislaCore

public actor DailyBriefingStore {
    private struct Archive: Codable {
        var days: [DailyBriefingDay] = []
        var exportedDays: Set<String> = []
    }

    private let fileURL: URL
    private var archive: Archive?
    private var previousObservation: DailyBriefingObservation?
    private var lastSavedAt: Date?

    public init(fileURL: URL = AppPaths.applicationSupport.appendingPathComponent("daily-briefing.json")) {
        self.fileURL = fileURL
    }

    public func observe(_ observation: DailyBriefingObservation, calendar: Calendar) throws {
        try load()
        if let previousObservation, observation.date <= previousObservation.date { return }
        guard let index = dayIndex(for: observation.date, calendar: calendar) else { return }
        if observation.recordsKeyPresses {
            archive!.days[index].recordKeyPressAvailability(hour: calendar.component(.hour, from: observation.date))
        }
        if let previous = previousObservation,
           observation.date.timeIntervalSince(previous.date) <= 90 {
            var cursor = previous.date
            while cursor < observation.date {
                let end = min(calendar.dateInterval(of: .hour, for: cursor)!.end, observation.date)
                var interval = previous
                interval.isActive = previous.isActive && observation.isActive
                interval.recordsKeyPresses = previous.recordsKeyPresses && observation.recordsKeyPresses
                if let target = dayIndex(for: cursor, calendar: calendar) {
                    archive!.days[target].record(from: cursor, to: end, observation: interval, calendar: calendar)
                }
                cursor = end
            }
        }
        if let hardware = observation.hardware,
           (0...90).contains(observation.date.timeIntervalSince(hardware.date)),
           calendar.isDate(hardware.date, inSameDayAs: observation.date) {
            archive!.days[index].record(hardware: hardware, calendar: calendar)
        }
        previousObservation = observation
        if lastSavedAt == nil || observation.date.timeIntervalSince(lastSavedAt!) >= 60 {
            try flush()
            lastSavedAt = observation.date
        }
    }

    public func suspend() throws {
        previousObservation = nil
        if archive != nil { try flush() }
    }

    public func recordExpansion(at date: Date, calendar: Calendar) throws {
        try load()
        guard let index = dayIndex(for: date, calendar: calendar) else { return }
        archive!.days[index].expansionCount += 1
        try flush()
    }

    public func recordActivities(_ batches: [DailyBriefingActivityBatch], calendar: Calendar) throws {
        guard !batches.isEmpty else { return }
        try load()
        let previous = archive!
        do {
            for batch in batches.sorted(by: { $0.date < $1.date }) {
                guard let index = dayIndex(for: batch.date, calendar: calendar) else { continue }
                try archive!.days[index].merge(batch)
                archive!.days[index].observedFrom = min(archive!.days[index].observedFrom ?? batch.date, batch.date)
                archive!.days[index].observedThrough = max(archive!.days[index].observedThrough ?? batch.lastDate, batch.lastDate)
            }
            try flush()
        } catch {
            archive = previous
            throw error
        }
    }

    public func day(at date: Date, calendar: Calendar) throws -> DailyBriefingDay {
        try load()
        if let day = archive!.days.first(where: { $0.key == DailyBriefingDay.dateKey(date, calendar: calendar) }) {
            return day
        }
        var day = DailyBriefingDay(date: date, calendar: calendar)
        day.activity = nil
        return day
    }

    public func pendingExports(at now: Date, settings: DailyBriefingSettings, calendar: Calendar) throws -> [DailyBriefingDay] {
        try load()
        guard settings.enabled else { return [] }
        return archive!.days.filter {
            !archive!.exportedDays.contains($0.key)
                && settings.exportDate(on: $0.date, calendar: calendar) <= now
                && ($0.observedFrom ?? $0.date) <= settings.exportDate(on: $0.date, calendar: calendar)
        }.sorted { $0.date < $1.date }
    }

    public func markExported(_ day: DailyBriefingDay) throws {
        try load()
        let previous = archive!.exportedDays
        archive!.exportedDays.insert(day.key)
        do {
            try flush()
        } catch {
            archive!.exportedDays = previous
            throw error
        }
    }

    public func flush() throws {
        guard let archive else { return }
        let data = try JSONEncoder().encode(archive)
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: fileURL, options: .atomic)
    }

    private func load() throws {
        guard archive == nil else { return }
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            archive = Archive()
            return
        }
        let decoded = try JSONDecoder().decode(Archive.self, from: Data(contentsOf: fileURL))
        guard decoded.days.allSatisfy({ day in
            day.hourlySeconds.count == 24 && day.hourlySeconds.allSatisfy { $0.isFinite && $0 >= 0 }
                && day.hasValidTimeSeries
        }) else { throw CocoaError(.fileReadCorruptFile) }
        archive = decoded
    }

    private func dayIndex(for date: Date, calendar: Calendar) -> Int? {
        let key = DailyBriefingDay.dateKey(date, calendar: calendar)
        if let index = archive!.days.firstIndex(where: { $0.key == key }) { return index }
        var day = DailyBriefingDay(date: date, calendar: calendar)
        day.observedFrom = date
        day.observedThrough = date
        archive!.days.append(day)
        archive!.days.sort { $0.date < $1.date }
        // A month of daily aggregates bounds disk use without retaining raw activity events.
        archive!.days = Array(archive!.days.suffix(35))
        archive!.exportedDays.formIntersection(Set(archive!.days.map(\.key)))
        return archive!.days.firstIndex { $0.key == key }
    }
}
