import Foundation

public enum DailyBriefingTemplate: String, Codable, CaseIterable, Identifiable, Sendable {
    case minimal, paper, midnight, forest, sunrise, terminal

    public var id: Self { self }

    public var title: String {
        switch self {
        case .minimal: "极简"
        case .paper: "纸笺"
        case .midnight: "午夜"
        case .forest: "森林"
        case .sunrise: "暖阳"
        case .terminal: "终端"
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

    public init(
        enabled: Bool = false,
        minuteOfDay: Int = 22 * 60,
        template: DailyBriefingTemplate = .minimal,
        readsSystemScreenTime: Bool = true
    ) {
        self.enabled = enabled
        self.minuteOfDay = min(1439, max(0, minuteOfDay))
        self.template = template
        self.readsSystemScreenTime = readsSystemScreenTime
    }

    private enum CodingKeys: String, CodingKey {
        case enabled, minuteOfDay, template, readsSystemScreenTime
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            enabled: try values.decodeIfPresent(Bool.self, forKey: .enabled) ?? false,
            minuteOfDay: try values.decodeIfPresent(Int.self, forKey: .minuteOfDay) ?? 22 * 60,
            template: try values.decodeIfPresent(DailyBriefingTemplate.self, forKey: .template) ?? .minimal,
            readsSystemScreenTime: try values.decodeIfPresent(Bool.self, forKey: .readsSystemScreenTime) ?? true
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

    public init(
        date: Date, applicationID: String, applicationName: String,
        category: DailyBriefingCategory, isActive: Bool, isListening: Bool?,
        hardware: DailyBriefingHardware? = nil
    ) {
        self.date = date
        self.applicationID = applicationID
        self.applicationName = applicationName
        self.category = category
        self.isActive = isActive
        self.isListening = isListening
        self.hardware = hardware
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

    public mutating func record(hardware: DailyBriefingHardware) {
        if let watts = hardware.powerWatts, watts.isFinite, watts >= 0,
           watts > (peakPower?.value ?? -1) {
            peakPower = .init(value: watts, date: hardware.date)
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
