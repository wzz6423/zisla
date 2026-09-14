import CoreFoundation
import Foundation

public struct SystemClockTimerSnapshot: Equatable, Sendable {
    public enum State: Equatable, Sendable {
        case running(deadline: Date)
        case paused(remaining: TimeInterval)
    }

    public let identifier: String
    public let state: State

    public init(identifier: String, state: State) {
        self.identifier = identifier
        self.state = state
    }

    fileprivate var sortKey: (Int, TimeInterval, String) {
        switch state {
        case .running(let deadline): (0, deadline.timeIntervalSinceReferenceDate, identifier)
        case .paused(let remaining): (1, remaining, identifier)
        }
    }
}

enum SystemClockTimerStore {
    static func readSnapshot() -> SystemClockTimerSnapshot? {
        let domain = "com.apple.mobiletimerd" as CFString
        // cfprefsd caches other apps' domains and can delay flushing changes to the plist file.
        guard CFPreferencesAppSynchronize(domain) else { return nil }
        return snapshot(from: CFPreferencesCopyAppValue("MTTimers" as CFString, domain))
    }

    static func snapshot(from value: Any?) -> SystemClockTimerSnapshot? {
        guard let store = value as? [String: Any],
              let timers = store["MTTimers"] as? [Any] else {
            return nil
        }
        return timers.compactMap(timer(from:)).min { $0.sortKey < $1.sortKey }
    }

    private static func timer(from value: Any) -> SystemClockTimerSnapshot? {
        guard let wrapper = value as? [String: Any],
              let timer = wrapper["$MTTimer"] as? [String: Any],
              let identifier = timer["MTTimerID"] as? String, !identifier.isEmpty,
              let state = timer["MTTimerState"] as? Int else {
            return nil
        }

        let snapshotState: SystemClockTimerSnapshot.State
        switch state {
        case 1:
            // Clock stores ringing timers as stopped; dismissal is tracked separately.
            guard let firedDate = timer["MTTimerFiredDate"] as? Date,
                  firedDate.timeIntervalSinceReferenceDate.isFinite else {
                return nil
            }
            if let value = timer["MTTimerDismissedDate"] {
                guard let dismissedDate = value as? Date,
                      dismissedDate.timeIntervalSinceReferenceDate.isFinite,
                      dismissedDate < firedDate else {
                    return nil
                }
            }
            snapshotState = .running(deadline: firedDate)
        case 2:
            guard let fireTime = timer["MTTimerFireTime"] as? [String: Any],
                  let interval = fireTime["$MTTimerTimeInterval"] as? [String: Any],
                  let remaining = interval["MTTimerTimeInterval"] as? TimeInterval,
                  remaining.isFinite, remaining > 0 else {
                return nil
            }
            snapshotState = .paused(remaining: remaining)
        case 3:
            guard let fireTime = timer["MTTimerFireTime"] as? [String: Any],
                  let absolute = fireTime["$MTTimerDate"] as? [String: Any],
                  let deadline = absolute["MTTimerTimeDate"] as? Date,
                  deadline.timeIntervalSinceReferenceDate.isFinite else {
                return nil
            }
            snapshotState = .running(deadline: deadline)
        default:
            return nil
        }
        return SystemClockTimerSnapshot(identifier: identifier, state: snapshotState)
    }
}
