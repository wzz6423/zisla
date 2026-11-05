import Foundation

public enum DailyBriefingTemplate: String, Codable, CaseIterable, Identifiable, Sendable {
    case minimal, paper, forest, sunrise, coastal, blossom, midnight, terminal

    public var id: Self { self }

    public var title: String {
        switch self {
        case .minimal: "极简"
        case .paper: "纸笺"
        case .midnight: "午夜"
        case .forest: "森林"
        case .sunrise: "暖阳"
        case .terminal: "终端"
        case .coastal: "海盐"
        case .blossom: "樱花"
        }
    }
}

public struct DailyBriefingSettings: Codable, Equatable, Sendable {
    public var enabled: Bool
    public var minuteOfDay: Int {
        didSet { minuteOfDay = min(1439, max(0, minuteOfDay)) }
    }
    public var template: DailyBriefingTemplate
    public var readsSystemScreenTime: Bool
    public var selectedContent: Set<DailyBriefingContent>

    public init(
        enabled: Bool = false,
        minuteOfDay: Int = 22 * 60,
        template: DailyBriefingTemplate = .minimal,
        readsSystemScreenTime: Bool = true,
        selectedContent: Set<DailyBriefingContent> = DailyBriefingContent.defaultSelection
    ) {
        self.enabled = enabled
        self.minuteOfDay = min(1439, max(0, minuteOfDay))
        self.template = template
        self.readsSystemScreenTime = readsSystemScreenTime
        self.selectedContent = selectedContent
    }

    private enum CodingKeys: String, CodingKey {
        case enabled, minuteOfDay, template, readsSystemScreenTime, selectedContent
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            enabled: try values.decodeIfPresent(Bool.self, forKey: .enabled) ?? false,
            minuteOfDay: try values.decodeIfPresent(Int.self, forKey: .minuteOfDay) ?? 22 * 60,
            template: try values.decodeIfPresent(DailyBriefingTemplate.self, forKey: .template) ?? .minimal,
            readsSystemScreenTime: try values.decodeIfPresent(Bool.self, forKey: .readsSystemScreenTime) ?? true,
            selectedContent: DailyBriefingContent.selection(from: try values.decodeIfPresent([String].self, forKey: .selectedContent))
        )
    }

    public func exportDate(on day: Date, calendar: Calendar) -> Date {
        // Calendar matching preserves wall-clock scheduling on 23/25-hour days.
        calendar.date(
            bySettingHour: minuteOfDay / 60,
            minute: minuteOfDay % 60,
            second: 0,
            of: day,
            matchingPolicy: .nextTime,
            repeatedTimePolicy: .first
        )!
    }
}

public enum DailyBriefingCategory: String, Codable, Sendable {
    case work, leisure, other

    public init(applicationCategory: String?) {
        switch applicationCategory {
        case "public.app-category.business", "public.app-category.developer-tools",
             "public.app-category.productivity", "public.app-category.finance",
             "public.app-category.education": self = .work
        case let category? where category.contains("games"):
            self = .leisure
        case "public.app-category.entertainment", "public.app-category.music",
             "public.app-category.video", "public.app-category.social-networking": self = .leisure
        default: self = .other
        }
    }
}

public struct DailyBriefingApplication: Codable, Equatable, Sendable {
    public var name: String
    public var category: DailyBriefingCategory
    public var seconds: TimeInterval

    public init(name: String, category: DailyBriefingCategory, seconds: TimeInterval = 0) {
        self.name = name
        self.category = category
        self.seconds = seconds
    }
}

public struct DailyBriefingPeak: Codable, Equatable, Sendable {
    public var value: Double
    public var date: Date

    public init(value: Double, date: Date) {
        self.value = value
        self.date = date
    }
}

public struct DailyBriefingHardware: Sendable {
    public var date: Date
    public var powerWatts: Double?
    public var batteryLevel: Double?
    public var fanRPM: Double?

    public init(date: Date, powerWatts: Double? = nil, batteryLevel: Double? = nil, fanRPM: Double? = nil) {
        self.date = date
        self.powerWatts = powerWatts
        self.batteryLevel = batteryLevel
        self.fanRPM = fanRPM
    }
}

public struct DailyBriefingObservation: Sendable {
    public var date: Date
    public var applicationID: String
    public var applicationName: String
    public var category: DailyBriefingCategory
    public var isActive: Bool
    public var isListening: Bool?
    public var hardware: DailyBriefingHardware?
    public var recordsKeyPresses: Bool

    public init(
        date: Date, applicationID: String, applicationName: String,
        category: DailyBriefingCategory, isActive: Bool, isListening: Bool?,
        hardware: DailyBriefingHardware? = nil,
        recordsKeyPresses: Bool = false
    ) {
        self.date = date
        self.applicationID = applicationID
        self.applicationName = applicationName
        self.category = category
        self.isActive = isActive
        self.isListening = isListening
        self.hardware = hardware
        self.recordsKeyPresses = recordsKeyPresses
    }
}

public enum DailyBriefingActivity: String, Codable, CaseIterable, Sendable {
    case clipboardCaptured, clipboardReused, shelfItemsAdded, shelfItemsCopied
    case pomodoroStarted, pomodoroCompleted
    case noteCreated, noteSaved, noteDeleted
    case quickNoteCreated, quickNoteSaved, quickNoteDeleted
    case unlocked
}

public typealias DailyBriefingActivityHandler = @MainActor (DailyBriefingActivity, Int, TimeInterval, Date) -> Void

public struct DailyBriefingActivityTotals: Codable, Equatable, Sendable {
    public private(set) var counts: [String: Int64] = [:]
    public private(set) var completedFocusSeconds: TimeInterval = 0

    public init() {}

    public func count(for activity: DailyBriefingActivity) -> Int64 {
        counts[activity.rawValue, default: 0]
    }

    @discardableResult
    public mutating func record(_ activity: DailyBriefingActivity, count: Int = 1, focusSeconds: TimeInterval = 0) -> Bool {
        guard count > 0, focusSeconds.isFinite, focusSeconds >= 0,
              activity == .pomodoroCompleted || focusSeconds == 0 else { return false }
        let total = self.count(for: activity).addingReportingOverflow(Int64(count))
        let seconds = completedFocusSeconds + focusSeconds
        guard !total.overflow, seconds.isFinite else { return false }
        counts[activity.rawValue] = total.partialValue
        completedFocusSeconds = seconds
        return true
    }

    public mutating func merge(_ other: Self) throws {
        var result = self
        for (key, count) in other.counts {
            let total = result.counts[key, default: 0].addingReportingOverflow(count)
            guard !total.overflow else { throw CocoaError(.fileReadCorruptFile) }
            result.counts[key] = total.partialValue
        }
        result.completedFocusSeconds += other.completedFocusSeconds
        guard result.completedFocusSeconds.isFinite else { throw CocoaError(.fileReadCorruptFile) }
        self = result
    }

    private enum CodingKeys: String, CodingKey { case counts, completedFocusSeconds }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        counts = try values.decodeIfPresent([String: Int64].self, forKey: .counts) ?? [:]
        completedFocusSeconds = try values.decodeIfPresent(TimeInterval.self, forKey: .completedFocusSeconds) ?? 0
        guard counts.values.allSatisfy({ $0 >= 0 }), completedFocusSeconds.isFinite, completedFocusSeconds >= 0 else {
            throw DecodingError.dataCorruptedError(forKey: .counts, in: values, debugDescription: "Invalid activity totals")
        }
    }
}

public struct DailyBriefingActivityBatch: Equatable, Sendable {
    public private(set) var date: Date
    public private(set) var lastDate: Date
    public let key: String
    public var activity = DailyBriefingActivityTotals()
    public fileprivate(set) var hourlyKeyPresses: [Int64?]?

    public init(date: Date, calendar: Calendar) {
        self.date = date
        lastDate = date
        key = DailyBriefingDay.dateKey(date, calendar: calendar)
    }

    public mutating func recordKeyPress(hour: Int) {
        guard (0..<24).contains(hour) else { return }
        var counts = hourlyKeyPresses ?? Array(repeating: nil, count: 24)
        let total = (counts[hour] ?? 0).addingReportingOverflow(1)
        guard !total.overflow else { return }
        counts[hour] = total.partialValue
        hourlyKeyPresses = counts
    }

    public mutating func merge(_ other: Self) throws {
        guard key == other.key else { throw CocoaError(.fileReadCorruptFile) }
        var result = self
        result.date = min(date, other.date)
        result.lastDate = max(lastDate, other.lastDate)
        try result.activity.merge(other.activity)
        if let incoming = other.hourlyKeyPresses {
            var counts = result.hourlyKeyPresses ?? Array(repeating: nil, count: 24)
            for hour in 0..<24 {
                guard let incomingCount = incoming[hour] else { continue }
                let total = (counts[hour] ?? 0).addingReportingOverflow(incomingCount)
                guard !total.overflow else { throw CocoaError(.fileReadCorruptFile) }
                counts[hour] = total.partialValue
            }
            result.hourlyKeyPresses = counts
        }
        self = result
    }
}

public struct DailyBriefingPowerSample: Codable, Equatable, Sendable, Identifiable {
    public let date: Date
    public private(set) var averageWatts: Double
    public private(set) var sampleCount: Int
    fileprivate var lastSampleDate: Date
    public var id: Date { date }

    public init(date: Date, averageWatts: Double) {
        self.date = date
        self.averageWatts = averageWatts
        sampleCount = 1
        lastSampleDate = date
    }

    mutating func record(watts: Double, at date: Date) {
        guard date > lastSampleDate, sampleCount < Int.max else { return }
        sampleCount += 1
        averageWatts += (watts - averageWatts) / Double(sampleCount)
        lastSampleDate = date
    }

    var isValid: Bool {
        averageWatts.isFinite && averageWatts >= 0 && sampleCount > 0
            && lastSampleDate >= date && lastSampleDate < date.addingTimeInterval(300)
    }
}

public struct DailyBriefingDay: Codable, Equatable, Sendable {
    public var date: Date
    public var key: String
    public var observedFrom: Date?
    public var observedThrough: Date?
    public var firstActivity: Date?
    public var lastActivity: Date?
    public var hourlySeconds: [Double] = Array(repeating: 0, count: 24)
    public var applications: [String: DailyBriefingApplication] = [:]
    public var listeningSeconds: TimeInterval?
    public var expansionCount = 0
    public var peakPower: DailyBriefingPeak?
    public var peakFan: DailyBriefingPeak?
    public var minimumBattery: Double?
    public var maximumBattery: Double?
    public var activity: DailyBriefingActivityTotals? = .init()
    public var hourlyKeyPresses: [Int64?]?
    public var powerSamples: [DailyBriefingPowerSample]?

    public init(date: Date, calendar: Calendar) {
        self.date = calendar.startOfDay(for: date)
        self.key = Self.dateKey(date, calendar: calendar)
    }

    public var activeSeconds: TimeInterval { hourlySeconds.reduce(0, +) }

    public func seconds(in category: DailyBriefingCategory) -> TimeInterval {
        applications.values.filter { $0.category == category }.reduce(0) { $0 + $1.seconds }
    }

    public static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        return calendar
    }

    public static func dateKey(_ date: Date, calendar: Calendar) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year!, parts.month!, parts.day!)
    }

    public mutating func record(from start: Date, to end: Date, observation: DailyBriefingObservation, calendar: Calendar) {
        let seconds = end.timeIntervalSince(start)
        guard seconds > 0, seconds <= 90 else { return }
        observedFrom = min(observedFrom ?? start, start)
        observedThrough = max(observedThrough ?? end, end)
        if observation.recordsKeyPresses {
            recordKeyPressAvailability(hour: calendar.component(.hour, from: start))
        }
        if observation.isActive {
            firstActivity = min(firstActivity ?? start, start)
            lastActivity = max(lastActivity ?? end, end)
            hourlySeconds[calendar.component(.hour, from: start)] += seconds
            var application = applications[observation.applicationID] ?? DailyBriefingApplication(
                name: observation.applicationName, category: observation.category
            )
            application.seconds += seconds
            applications[observation.applicationID] = application
        }
        if let isListening = observation.isListening {
            listeningSeconds = (listeningSeconds ?? 0) + (isListening ? seconds : 0)
        }
    }

    public mutating func record(hardware: DailyBriefingHardware, calendar: Calendar = DailyBriefingDay.calendar) {
        if let watts = hardware.powerWatts, watts.isFinite, watts >= 0,
           watts > (peakPower?.value ?? -1) {
            peakPower = .init(value: watts, date: hardware.date)
        }
        if let watts = hardware.powerWatts, watts.isFinite, watts >= 0,
           calendar.isDate(hardware.date, inSameDayAs: date) {
            let offset = floor(hardware.date.timeIntervalSince(date) / 300)
            let bucketDate = date.addingTimeInterval(offset * 300)
            var samples = powerSamples ?? []
            if let index = samples.firstIndex(where: { $0.date == bucketDate }) {
                samples[index].record(watts: watts, at: hardware.date)
            } else {
                var sample = DailyBriefingPowerSample(date: bucketDate, averageWatts: watts)
                sample.lastSampleDate = hardware.date
                samples.append(sample)
                samples.sort { $0.date < $1.date }
            }
            powerSamples = samples
        }
        if let rpm = hardware.fanRPM, rpm.isFinite, rpm >= 0,
           rpm > (peakFan?.value ?? -1) {
            peakFan = .init(value: rpm, date: hardware.date)
        }
        if let level = hardware.batteryLevel, level.isFinite, (0...1).contains(level) {
            minimumBattery = min(minimumBattery ?? level, level)
            maximumBattery = max(maximumBattery ?? level, level)
        }
    }

    public mutating func merge(_ batch: DailyBriefingActivityBatch) throws {
        var combined = batch
        combined.activity = activity ?? .init()
        combined.hourlyKeyPresses = hourlyKeyPresses
        try combined.merge(batch)
        activity = combined.activity
        hourlyKeyPresses = combined.hourlyKeyPresses
    }

    public mutating func recordKeyPressAvailability(hour: Int) {
        guard (0..<24).contains(hour) else { return }
        var counts = hourlyKeyPresses ?? Array(repeating: nil, count: 24)
        if counts[hour] == nil { counts[hour] = 0 }
        hourlyKeyPresses = counts
    }

    public var hasValidTimeSeries: Bool {
        let validKeys = hourlyKeyPresses.map { counts in
            counts.count == 24 && counts.allSatisfy { value in value.map { $0 >= 0 } ?? true }
        } ?? true
        let validPower = powerSamples.map { samples in
            samples.allSatisfy { sample in
                sample.isValid && sample.date >= date && sample.date < date.addingTimeInterval(25 * 3600)
                    && sample.date.timeIntervalSince(date).truncatingRemainder(dividingBy: 300) == 0
            } && zip(samples, samples.dropFirst()).allSatisfy { pair in pair.0.date < pair.1.date }
        } ?? true
        return validKeys && validPower
    }
}

public struct DailyBriefingTyping: Equatable, Sendable {
    public var characters: Int64
    public var topApplication: String?
    public var peakHour: Int?

    public init(characters: Int64, topApplication: String?, peakHour: Int?) {
        self.characters = characters
        self.topApplication = topApplication
        self.peakHour = peakHour
    }
}
