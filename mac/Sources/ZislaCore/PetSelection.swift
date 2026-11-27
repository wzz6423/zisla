import Foundation

public enum PetSelectionMode: String, Codable, Sendable {
    case fixed
    case randomRotation
}

public struct PetRotationSelection: Codable, Equatable, Sendable {
    public let petID: String
    private let day: String
    private let selectedAt: Date
    private let interval: TimeInterval?

    public static func resolve(
        previous: Self?, candidates: Set<String>, interval: TimeInterval?, at date: Date,
        calendar: Calendar = DailyBriefingDay.calendar
    ) -> Self? {
        let day = DailyBriefingDay.dateKey(date, calendar: calendar)
        var choices = candidates
        if let previous, candidates.contains(previous.petID) {
            // Changing the schedule starts its new period with the pet already on screen.
            if previous.interval != interval || (interval != nil && date < previous.selectedAt) {
                return Self(petID: previous.petID, day: day, selectedAt: date, interval: interval)
            }
            if let interval {
                if date.timeIntervalSince(previous.selectedAt) < interval { return previous }
            } else if day == previous.day {
                return previous
            }
            if choices.count > 1 { choices.remove(previous.petID) }
        }
        return choices.randomElement().map { Self(petID: $0, day: day, selectedAt: date, interval: interval) }
    }

    public func nextRotation(after date: Date, calendar: Calendar = DailyBriefingDay.calendar) -> Date? {
        if let interval { return selectedAt.addingTimeInterval(interval) }
        return calendar.dateInterval(of: .day, for: date)?.end
    }
}

extension FeatureSettings {
    public mutating func petRotationCandidates(availableIDs: [String]) -> Set<String> {
        guard let firstID = availableIDs.first else { return [] }
        let available = Set(availableIDs)
        guard let pool = petRandomPool else { return available }
        var candidates = available.intersection(pool)
        if candidates.isEmpty {
            candidates.insert(available.contains(Self.default.petID) ? Self.default.petID : firstID)
        }
        petRandomPool = candidates
        return candidates
    }
}
