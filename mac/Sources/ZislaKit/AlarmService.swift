import AppKit
import Combine
import Foundation
import UserNotifications

/// An alarm item. An empty `weekdays` set means it fires only once (auto-dismissed after firing).
public struct AlarmItem: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID
    /// 0...23
    public var hour: Int
    /// 0...59
    public var minute: Int
    public var label: String
    /// 1 = Sunday … 7 = Saturday, matching `Calendar`'s `weekday` component.
    public var weekdays: Set<Int>
    public var isEnabled: Bool

    public init(
        id: UUID = UUID(),
        hour: Int,
        minute: Int,
        label: String = "",
        weekdays: Set<Int> = [],
        isEnabled: Bool = true
    ) {
        self.id = id
        self.hour = min(23, max(0, hour))
        self.minute = min(59, max(0, minute))
        self.label = label
        self.weekdays = weekdays.filter { (1...7).contains($0) }
        self.isEnabled = isEnabled
    }

    public var isRepeating: Bool { !weekdays.isEmpty }

    public var timeText: String {
        String(format: "%02d:%02d", hour, minute)
    }

    /// Repeat description such as "Every day", "Weekdays", or "Mon Wed".
    public var repeatText: String {
        if weekdays.isEmpty { return "仅一次" }
        if weekdays == Set(1...7) { return "每天" }
        if weekdays == Set(2...6) { return "工作日" }
        if weekdays == [1, 7] { return "周末" }
        return weekdays.sorted().map { Self.weekdaySymbols[$0 - 1] }.joined(separator: " ")
    }

    public static let weekdaySymbols = ["周日", "周一", "周二", "周三", "周四", "周五", "周六"]

    /// Next fire date; nil when the alarm is disabled.
    public func nextTriggerDate(
        after now: Date = Date(),
        calendar: Calendar = .current
    ) -> Date? {
        guard isEnabled else { return nil }
        if weekdays.isEmpty {
            var components = DateComponents()
            components.hour = hour
            components.minute = minute
            return calendar.nextDate(
                after: now,
                matching: components,
                matchingPolicy: .nextTimePreservingSmallerComponents
            )
        }
        return weekdays.compactMap { weekday -> Date? in
            var components = DateComponents()
            components.hour = hour
            components.minute = minute
            components.weekday = weekday
            return calendar.nextDate(
                after: now,
                matching: components,
                matchingPolicy: .nextTimePreservingSmallerComponents
            )
        }.min()
    }
}

/// Alarm service.
///
/// macOS has no usable system alarm API: `MobileTimer.framework`'s `MTAlarmManager` has
/// a full CRUD interface, but its mach service `com.apple.MobileTimer.alarmserver` requires
/// the `com.apple.private.mobiletimerd` entitlement — third-party processes carrying that
/// entitlement are hard-killed by AMFI, and the Core Data store for alarms lives in a
/// TCC-protected Group Container; AlarmKit only exists in the iPhoneOS SDK.
///
/// Alarms are therefore managed by Zisla itself: JSON persistence + `UNUserNotificationCenter`
/// calendar triggers. `openSystemClock` provides a jump to the system Clock app.
@MainActor
public final class AlarmService: ObservableObject {
    @Published public private(set) var alarms: [AlarmItem] = []
    @Published public var errorMessage: String?

    private let storageURL: URL
    private let notificationCenter: UNUserNotificationCenter
    private let notificationRequestHandler: (UNNotificationRequest) -> Void
    private let cancelHandler: ([String]) -> Void
    private var schedulingEnabled = true
    /// Alarm notifications are always delivered regardless of Do Not Disturb — a time explicitly set by the user must not be silenced.
    private var authorizationPromptHost: NSWindow?

    public init(
        storageURL: URL = AppPaths.alarms,
        notificationCenter: UNUserNotificationCenter = .current(),
        notificationRequestHandler: ((UNNotificationRequest) -> Void)? = nil,
        cancelHandler: (([String]) -> Void)? = nil
    ) {
        self.storageURL = storageURL
        self.notificationCenter = notificationCenter
        self.notificationRequestHandler = notificationRequestHandler ?? { [notificationCenter] request in
            notificationCenter.add(request, withCompletionHandler: nil)
        }
        self.cancelHandler = cancelHandler ?? { [notificationCenter] identifiers in
            notificationCenter.removePendingNotificationRequests(withIdentifiers: identifiers)
        }
        load()
    }

    public var enabledAlarms: [AlarmItem] {
        alarms.filter(\.isEnabled)
    }

    /// The alarm whose next ring is closest; used for the collapsed-state reminder.
    public var nextAlarm: AlarmItem? {
        alarms
            .compactMap { alarm -> (AlarmItem, Date)? in
                guard let date = alarm.nextTriggerDate() else { return nil }
                return (alarm, date)
            }
            .min { $0.1 < $1.1 }?
            .0
    }

    // MARK: - CRUD

    @discardableResult
    public func add(
        hour: Int,
        minute: Int,
        label: String = "",
        weekdays: Set<Int> = []
    ) -> AlarmItem {
        let alarm = AlarmItem(hour: hour, minute: minute, label: label, weekdays: weekdays)
        alarms.append(alarm)
        sortAlarms()
        persist()
        if schedulingEnabled {
            requestAuthorizationIfNeeded()
            schedule(alarm)
        }
        return alarm
    }

    public func update(_ alarm: AlarmItem) {
        guard let index = alarms.firstIndex(where: { $0.id == alarm.id }) else { return }
        cancelNotifications(for: alarms[index])
        alarms[index] = alarm
        sortAlarms()
        persist()
        schedule(alarm)
    }

    public func remove(id: UUID) {
        guard let index = alarms.firstIndex(where: { $0.id == id }) else { return }
        cancelNotifications(for: alarms[index])
        alarms.remove(at: index)
        persist()
    }

    public func toggle(id: UUID) {
        guard let index = alarms.firstIndex(where: { $0.id == id }) else { return }
        var alarm = alarms[index]
        alarm.isEnabled.toggle()
        if alarm.isEnabled { requestAuthorizationIfNeeded() }
        update(alarm)
    }

    /// Re-registers all alarm notifications; called on app launch to keep pending system notifications in sync with local data.
    public func rescheduleAll() {
        cancelNotifications(for: alarms)
        guard schedulingEnabled, !enabledAlarms.isEmpty else { return }
        requestAuthorizationIfNeeded()
        for alarm in enabledAlarms { schedule(alarm) }
    }

    public func suspend() {
        schedulingEnabled = false
        cancelNotifications(for: alarms)
    }

    public func resume() {
        schedulingEnabled = true
        rescheduleAll()
    }

    public func openSystemClock() {
        let clock = URL(fileURLWithPath: "/System/Applications/Clock.app")
        guard FileManager.default.fileExists(atPath: clock.path) else {
            errorMessage = "未找到系统「时钟」App"
            return
        }
        NSWorkspace.shared.open(clock)
    }

    // MARK: - Notification registration

    /// Notification identifiers for an alarm: one for a non-repeating alarm, one per weekday for a repeating one.
    static func notificationIdentifiers(for alarm: AlarmItem) -> [String] {
        if alarm.weekdays.isEmpty { return ["zisla.alarm.\(alarm.id.uuidString)"] }
        return alarm.weekdays.sorted().map { "zisla.alarm.\(alarm.id.uuidString).\($0)" }
    }

    private func schedule(_ alarm: AlarmItem) {
        guard schedulingEnabled, alarm.isEnabled else { return }
        let content = UNMutableNotificationContent()
        content.title = alarm.label.isEmpty ? "闹钟" : alarm.label
        content.body = "\(alarm.timeText) · \(alarm.repeatText)"
        content.sound = .default

        if alarm.weekdays.isEmpty {
            var components = DateComponents()
            components.hour = alarm.hour
            components.minute = alarm.minute
            notificationRequestHandler(UNNotificationRequest(
                identifier: "zisla.alarm.\(alarm.id.uuidString)",
                content: content,
                trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
            ))
            return
        }

        for weekday in alarm.weekdays.sorted() {
            var components = DateComponents()
            components.hour = alarm.hour
            components.minute = alarm.minute
            components.weekday = weekday
            notificationRequestHandler(UNNotificationRequest(
                identifier: "zisla.alarm.\(alarm.id.uuidString).\(weekday)",
                content: content,
                trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
            ))
        }
    }

    private func cancelNotifications(for alarm: AlarmItem) {
        cancelHandler(Self.notificationIdentifiers(for: alarm))
    }

    private func cancelNotifications(for alarms: [AlarmItem]) {
        let identifiers = alarms.flatMap { Self.notificationIdentifiers(for: $0) }
        guard !identifiers.isEmpty else { return }
        cancelHandler(identifiers)
    }

    private func requestAuthorizationIfNeeded() {
        notificationCenter.getNotificationSettings { [weak self] settings in
            guard settings.authorizationStatus == .notDetermined else { return }
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.dismissAuthorizationPromptHost()
                self.authorizationPromptHost = WindowPlacement.authorizationPromptHost()
                _ = try? await self.notificationCenter.requestAuthorization(options: [.alert, .sound])
                self.dismissAuthorizationPromptHost()
            }
        }
    }

    private func dismissAuthorizationPromptHost() {
        authorizationPromptHost?.orderOut(nil)
        authorizationPromptHost?.close()
        authorizationPromptHost = nil
    }

    // MARK: - Persistence

    private func sortAlarms() {
        alarms.sort { ($0.hour, $0.minute) < ($1.hour, $1.minute) }
    }

    private func load() {
        guard let data = try? Data(contentsOf: storageURL) else { return }
        do {
            alarms = try JSONDecoder().decode([AlarmItem].self, from: data)
            sortAlarms()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func persist() {
        do {
            try FileManager.default.createDirectory(
                at: storageURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let data = try JSONEncoder().encode(alarms)
            try data.write(to: storageURL, options: .atomic)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
