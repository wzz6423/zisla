import Combine
import EventKit
import Foundation

public enum CalendarItemKind: Equatable, Sendable {
    case event
    case reminder
}

public enum CalendarMutationError: Error, LocalizedError, Equatable, Sendable {
    case emptyTitle
    case invalidDateRange
    case missingSourceIdentifier
    case actionNotSupported
    case calendarUnavailable
    case itemNotFound

    public var errorDescription: String? {
        switch self {
        case .emptyTitle: "请输入标题"
        case .invalidDateRange: "结束时间必须晚于开始时间"
        case .missingSourceIdentifier: "无法定位原日程"
        case .actionNotSupported: "该日程不支持此操作"
        case .calendarUnavailable: "没有可写入的日历"
        case .itemNotFound: "日程已不存在"
        }
    }
}

public struct CalendarEventSnapshot: Equatable, Identifiable, Sendable {
    public var id: String
    public var title: String
    public var startDate: Date
    public var endDate: Date
    public var isAllDay: Bool
    public var calendarTitle: String
    public var kind: CalendarItemKind
    public var isCompleted: Bool
    public var sourceIdentifier: String?
    public var isProjectedOccurrence: Bool

    public init(
        id: String,
        title: String,
        startDate: Date,
        endDate: Date,
        isAllDay: Bool,
        calendarTitle: String,
        kind: CalendarItemKind = .event,
        isCompleted: Bool = false,
        sourceIdentifier: String? = nil,
        isProjectedOccurrence: Bool = false
    ) {
        self.id = id
        self.title = title
        self.startDate = startDate
        self.endDate = endDate
        self.isAllDay = isAllDay
        self.calendarTitle = calendarTitle
        self.kind = kind
        self.isCompleted = isCompleted
        self.sourceIdentifier = sourceIdentifier
        self.isProjectedOccurrence = isProjectedOccurrence
    }
}

@MainActor
struct CalendarMutationCommands {
    var createEvent: (String, Date, Date, Bool) throws -> Void
    var createReminder: (String, Date, Bool) throws -> Void
    var delete: (CalendarItemKind, String) throws -> Void
    var setReminderCompleted: (String, Bool) throws -> Void

    static func live(store: EKEventStore) -> CalendarMutationCommands {
        CalendarMutationCommands(
            createEvent: { title, startDate, endDate, isAllDay in
                guard let calendar = store.defaultCalendarForNewEvents else {
                    throw CalendarMutationError.calendarUnavailable
                }
                let event = EKEvent(eventStore: store)
                event.title = title
                event.startDate = startDate
                event.endDate = endDate
                event.isAllDay = isAllDay
                event.calendar = calendar
                try store.save(event, span: .thisEvent, commit: true)
            },
            createReminder: { title, dueDate, isAllDay in
                guard let calendar = store.defaultCalendarForNewReminders() else {
                    throw CalendarMutationError.calendarUnavailable
                }
                let reminder = EKReminder(eventStore: store)
                reminder.title = title
                reminder.calendar = calendar
                let systemCalendar = Calendar.current
                var components = systemCalendar.dateComponents(
                    isAllDay
                        ? [.year, .month, .day]
                        : [.year, .month, .day, .hour, .minute],
                    from: dueDate
                )
                components.calendar = systemCalendar
                components.timeZone = systemCalendar.timeZone
                reminder.dueDateComponents = components
                try store.save(reminder, commit: true)
            },
            delete: { kind, identifier in
                switch kind {
                case .event:
                    guard let event = store.event(withIdentifier: identifier)
                        ?? store.calendarItem(withIdentifier: identifier) as? EKEvent
                    else {
                        throw CalendarMutationError.itemNotFound
                    }
                    try store.remove(event, span: .thisEvent, commit: true)
                case .reminder:
                    guard let reminder = store.calendarItem(withIdentifier: identifier) as? EKReminder else {
                        throw CalendarMutationError.itemNotFound
                    }
                    try store.remove(reminder, commit: true)
                }
            },
            setReminderCompleted: { identifier, isCompleted in
                guard let reminder = store.calendarItem(withIdentifier: identifier) as? EKReminder else {
                    throw CalendarMutationError.itemNotFound
                }
                reminder.isCompleted = isCompleted
                reminder.completionDate = isCompleted ? Date() : nil
                try store.save(reminder, commit: true)
            }
        )
    }
}

@MainActor
public final class CalendarService: ObservableObject {
    public nonisolated static let weekDayCount = 7
    public nonisolated static let agendaWeekCount = 2
    private static let refreshDebounce: Duration = .milliseconds(180)

    @Published public private(set) var events: [CalendarEventSnapshot] = []
    @Published public private(set) var authorizationStatus = EKEventStore.authorizationStatus(for: .event)
    @Published public private(set) var reminderAuthorizationStatus = EKEventStore.authorizationStatus(for: .reminder)
    @Published public private(set) var errorDescription: String?
    @Published public private(set) var isLoading = false
    @Published public private(set) var lastRefreshedAt: Date?

    private let store: EKEventStore
    private var lastRefreshFinishedAt: Date?
    private let mutations: CalendarMutationCommands
    private var storeChangedObserver: NSObjectProtocol?
    private var scheduledRefresh: Task<Void, Never>?
    private var refreshGeneration: UInt64 = 0
    private var isRefreshing = false
    /// Delayed refresh triggered by calendar changes continues querying the week the user is currently viewing.
    private var queryAnchorDate = Date()

    public convenience init() {
        let store = EKEventStore()
        self.init(store: store, mutations: .live(store: store))
    }

    init(store: EKEventStore, mutations: CalendarMutationCommands) {
        self.store = store
        self.mutations = mutations
    }

    isolated deinit {
        stop()
    }

    public func start() {
        guard storeChangedObserver == nil else { return }
        storeChangedObserver = NotificationCenter.default.addObserver(
            forName: .EKEventStoreChanged,
            object: store,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.scheduleRefresh()
            }
        }
    }

    public func stop() {
        refreshGeneration &+= 1
        scheduledRefresh?.cancel()
        scheduledRefresh = nil
        if let storeChangedObserver {
            NotificationCenter.default.removeObserver(storeChangedObserver)
            self.storeChangedObserver = nil
        }
    }

    public func refresh(referenceDate: Date = Date()) async {
        queryAnchorDate = referenceDate
        refreshGeneration &+= 1
        let generation = refreshGeneration
        guard !isRefreshing else { return }

        isRefreshing = true
        isLoading = true
        do {
            updateAuthorizationStatuses()
            try await requestUndeterminedAccess()

            let readsEvents = Self.canReadEvents(authorizationStatus)
            let readsReminders = Self.canReadReminders(reminderAuthorizationStatus)
            guard readsEvents || readsReminders else {
                completeRefresh(
                    with: [],
                    generation: generation,
                    errorDescription: "未授予日历或提醒事项访问权限"
                )
                return
            }

            // iCloud and subscribed calendars can finish syncing after the first
            // store is created. This call makes the initial query include those
            // sources, while the store-change observer covers later edits.
            store.refreshSourcesIfNecessary()

            let calendar = Calendar.current
            guard let interval = Self.agendaDateInterval(containing: referenceDate, calendar: calendar) else {
                completeRefresh(
                    with: [],
                    generation: generation,
                    errorDescription: "无法计算日程查询范围"
                )
                return
            }
            let start = interval.start
            let end = interval.end
            var nextItems: [CalendarEventSnapshot] = []
            if readsEvents {
                let predicate = store.predicateForEvents(
                    withStart: start,
                    end: end,
                    calendars: nil
                )
                nextItems += store.events(matching: predicate).map {
                    let identifier = $0.eventIdentifier ?? "untitled"
                    return CalendarEventSnapshot(
                        id: "event:\(identifier):\($0.startDate.timeIntervalSince1970)",
                        title: $0.title?.isEmpty == false ? $0.title : "未命名日程",
                        startDate: $0.startDate,
                        endDate: $0.endDate,
                        isAllDay: $0.isAllDay,
                        calendarTitle: $0.calendar.title,
                        sourceIdentifier: identifier
                    )
                }
            }
            if readsReminders {
                fetchReminderSnapshots(
                    appending: nextItems,
                    from: start,
                    to: end,
                    calendar: calendar,
                    generation: generation
                )
                return
            }

            completeRefresh(with: nextItems, generation: generation)
        } catch {
            completeRefresh(
                with: [],
                generation: generation,
                errorDescription: error.localizedDescription
            )
        }
    }

    /// Returns true if the calendar data is stale (older than 60 seconds or never loaded).
    public var isDataStale: Bool {
        guard let lastRefreshFinishedAt else { return true }
        return Date().timeIntervalSince(lastRefreshFinishedAt) > 60
    }

    public func events(on day: Date, calendar: Calendar = .current) -> [CalendarEventSnapshot] {
        events.filter { Self.item($0, occursOn: day, calendar: calendar) }
    }

    public func requestAccess() async {
        updateAuthorizationStatuses()
        do {
            try await requestUndeterminedAccess()
            await refresh(referenceDate: queryAnchorDate)
        } catch {
            updateAuthorizationStatuses()
            errorDescription = error.localizedDescription
        }
    }

    public func createEvent(
        title: String,
        startDate: Date,
        endDate: Date,
        isAllDay: Bool
    ) throws {
        let title = try normalizedTitle(title)
        guard endDate > startDate else { throw CalendarMutationError.invalidDateRange }
        try mutations.createEvent(title, startDate, endDate, isAllDay)
        scheduleRefresh()
    }

    public func createReminder(
        title: String,
        dueDate: Date,
        isAllDay: Bool
    ) throws {
        let title = try normalizedTitle(title)
        try mutations.createReminder(title, dueDate, isAllDay)
        scheduleRefresh()
    }

    public func delete(_ item: CalendarEventSnapshot) throws {
        guard !item.isProjectedOccurrence else {
            throw CalendarMutationError.actionNotSupported
        }
        guard let identifier = item.sourceIdentifier, !identifier.isEmpty else {
            throw CalendarMutationError.missingSourceIdentifier
        }
        try mutations.delete(item.kind, identifier)
        events.removeAll { $0.id == item.id }
        scheduleRefresh()
    }

    public func setReminderCompleted(
        _ item: CalendarEventSnapshot,
        isCompleted: Bool
    ) throws {
        guard item.kind == .reminder else { throw CalendarMutationError.actionNotSupported }
        guard !item.isProjectedOccurrence else {
            throw CalendarMutationError.actionNotSupported
        }
        guard let identifier = item.sourceIdentifier, !identifier.isEmpty else {
            throw CalendarMutationError.missingSourceIdentifier
        }
        try mutations.setReminderCompleted(identifier, isCompleted)
        if let index = events.firstIndex(where: { $0.id == item.id }) {
            events[index].isCompleted = isCompleted
        }
        scheduleRefresh()
    }

    public var hasEventAccess: Bool {
        Self.canReadEvents(authorizationStatus)
    }

    public var hasReminderAccess: Bool {
        Self.canReadReminders(reminderAuthorizationStatus)
    }

    public var hasAnyReadAccess: Bool {
        hasEventAccess || hasReminderAccess
    }

    public var hasFullAgendaAccess: Bool {
        hasEventAccess && hasReminderAccess
    }

    public var hasUndeterminedAccess: Bool {
        authorizationStatus == .notDetermined
            || reminderAuthorizationStatus == .notDetermined
    }

    private func requestUndeterminedAccess() async throws {
        guard authorizationStatus == .notDetermined
            || reminderAuthorizationStatus == .notDetermined
        else { return }

        let authorizationHost = WindowPlacement.authorizationPromptHost()
        defer {
            authorizationHost?.orderOut(nil)
            authorizationHost?.close()
        }

        var firstError: Error?
        if authorizationStatus == .notDetermined {
            do {
                _ = try await store.requestFullAccessToEvents()
            } catch {
                firstError = error
            }
            authorizationStatus = EKEventStore.authorizationStatus(for: .event)
        }
        if reminderAuthorizationStatus == .notDetermined {
            do {
                _ = try await store.requestFullAccessToReminders()
            } catch {
                if firstError == nil { firstError = error }
            }
            reminderAuthorizationStatus = EKEventStore.authorizationStatus(for: .reminder)
        }
        if let firstError { throw firstError }
    }

    private func fetchReminderSnapshots(
        appending baseItems: [CalendarEventSnapshot],
        from start: Date,
        to end: Date,
        calendar: Calendar,
        generation: UInt64
    ) {
        let predicate = store.predicateForReminders(in: nil)
        store.fetchReminders(matching: predicate) { [weak self] reminders in
            DispatchQueue.main.async {
                guard let self else { return }
                let items = baseItems + Self.makeReminderSnapshots(
                    from: reminders ?? [],
                    calendar: calendar,
                    dueWithin: DateInterval(start: start, end: end)
                )
                self.completeRefresh(with: items, generation: generation)
            }
        }
    }

    private func completeRefresh(
        with items: [CalendarEventSnapshot],
        generation: UInt64,
        errorDescription: String? = nil
    ) {
        defer {
            isRefreshing = false
            if generation == refreshGeneration {
                isLoading = false
            } else {
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    await self.refresh(referenceDate: self.queryAnchorDate)
                }
            }
        }
        guard generation == refreshGeneration else { return }

        events = Self.preparedAgendaItems(items)
        self.errorDescription = errorDescription
        if errorDescription == nil {
            lastRefreshFinishedAt = Date()
        }
    }

    nonisolated static func makeReminderSnapshots(
        from reminders: [EKReminder],
        calendar: Calendar,
        dueWithin interval: DateInterval? = nil
    ) -> [CalendarEventSnapshot] {
        reminders.flatMap { reminder -> [CalendarEventSnapshot] in
            guard let components = reminder.dueDateComponents,
                  let due = reminderDate(from: components, defaultCalendar: calendar)
            else { return [] }
            let recurrenceCalendar = resolvedCalendar(
                for: components,
                defaultCalendar: calendar
            )
            return reminderOccurrenceDates(
                for: reminder,
                startingAt: due.date,
                calendar: recurrenceCalendar,
                within: interval
            ).map { occurrenceDate in
                let endDate = due.isAllDay
                    ? recurrenceCalendar.date(byAdding: .day, value: 1, to: occurrenceDate)
                        ?? occurrenceDate
                    : occurrenceDate
                return CalendarEventSnapshot(
                    id: "reminder:\(reminder.calendarItemIdentifier):\(occurrenceDate.timeIntervalSince1970)",
                    title: reminder.title?.isEmpty == false ? reminder.title : "未命名提醒",
                    startDate: occurrenceDate,
                    endDate: endDate,
                    isAllDay: due.isAllDay,
                    calendarTitle: reminder.calendar.title,
                    kind: .reminder,
                    isCompleted: reminder.isCompleted,
                    sourceIdentifier: reminder.calendarItemIdentifier,
                    isProjectedOccurrence: occurrenceDate != due.date
                )
            }
        }
    }

    private nonisolated static func reminderOccurrenceDates(
        for reminder: EKReminder,
        startingAt startDate: Date,
        calendar: Calendar,
        within interval: DateInterval?
    ) -> [Date] {
        let actualOccurrence = interval.map {
            startDate >= $0.start && startDate < $0.end ? [startDate] : []
        } ?? [startDate]
        guard !reminder.isCompleted,
              let interval,
              let rules = reminder.recurrenceRules,
              !rules.isEmpty
        else { return actualOccurrence }
        guard #available(macOS 15.0, *) else { return actualOccurrence }

        var occurrences = Set(actualOccurrence)
        for rule in rules {
            guard let recurrenceRule = calendarRecurrenceRule(from: rule, calendar: calendar) else {
                continue
            }
            for occurrence in recurrenceRule.recurrences(
                of: startDate,
                in: interval.start..<interval.end
            ) {
                occurrences.insert(occurrence)
            }
        }
        return occurrences.sorted()
    }

    @available(macOS 15.0, *)
    private nonisolated static func calendarRecurrenceRule(
        from rule: EKRecurrenceRule,
        calendar defaultCalendar: Calendar
    ) -> Calendar.RecurrenceRule? {
        var calendar = defaultCalendar
        if rule.firstDayOfTheWeek != 0 {
            calendar.firstWeekday = rule.firstDayOfTheWeek
        }

        let frequency: Calendar.RecurrenceRule.Frequency
        switch rule.frequency {
        case .daily: frequency = .daily
        case .weekly: frequency = .weekly
        case .monthly: frequency = .monthly
        case .yearly: frequency = .yearly
        @unknown default: return nil
        }

        let end: Calendar.RecurrenceRule.End
        if let endDate = rule.recurrenceEnd?.endDate {
            end = .afterDate(endDate)
        } else if let occurrenceCount = rule.recurrenceEnd?.occurrenceCount,
                  occurrenceCount > 0 {
            end = .afterOccurrences(Int(occurrenceCount))
        } else {
            end = .never
        }

        let sourceWeekdays = rule.daysOfTheWeek ?? []
        let weekdays = sourceWeekdays.compactMap { day -> Calendar.RecurrenceRule.Weekday? in
            guard let weekday = localeWeekday(from: day.dayOfTheWeek) else { return nil }
            return day.weekNumber == 0
                ? .every(weekday)
                : .nth(day.weekNumber, weekday)
        }
        guard weekdays.count == sourceWeekdays.count else { return nil }

        return Calendar.RecurrenceRule(
            calendar: calendar,
            frequency: frequency,
            interval: rule.interval,
            end: end,
            months: (rule.monthsOfTheYear ?? []).map {
                Calendar.RecurrenceRule.Month($0.intValue)
            },
            daysOfTheYear: (rule.daysOfTheYear ?? []).map(\.intValue),
            daysOfTheMonth: (rule.daysOfTheMonth ?? []).map(\.intValue),
            weeks: (rule.weeksOfTheYear ?? []).map(\.intValue),
            weekdays: weekdays,
            setPositions: (rule.setPositions ?? []).map(\.intValue)
        )
    }

    @available(macOS 15.0, *)
    private nonisolated static func localeWeekday(from weekday: EKWeekday) -> Locale.Weekday? {
        switch weekday {
        case .sunday: .sunday
        case .monday: .monday
        case .tuesday: .tuesday
        case .wednesday: .wednesday
        case .thursday: .thursday
        case .friday: .friday
        case .saturday: .saturday
        @unknown default: nil
        }
    }

    private func updateAuthorizationStatuses() {
        authorizationStatus = EKEventStore.authorizationStatus(for: .event)
        reminderAuthorizationStatus = EKEventStore.authorizationStatus(for: .reminder)
    }

    private func normalizedTitle(_ title: String) throws -> String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw CalendarMutationError.emptyTitle }
        return trimmed
    }

    private func scheduleRefresh() {
        guard storeChangedObserver != nil else { return }
        scheduledRefresh?.cancel()
        scheduledRefresh = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(for: Self.refreshDebounce)
            } catch {
                return
            }
            guard let self else { return }
            await self.refresh(referenceDate: self.queryAnchorDate)
        }
    }

    nonisolated static func reminderDate(
        from components: DateComponents,
        defaultCalendar: Calendar
    ) -> (date: Date, isAllDay: Bool)? {
        let calendar = resolvedCalendar(for: components, defaultCalendar: defaultCalendar)
        guard let date = calendar.date(from: components) else { return nil }
        let isAllDay = components.hour == nil
            && components.minute == nil
            && components.second == nil
        return (isAllDay ? calendar.startOfDay(for: date) : date, isAllDay)
    }

    private nonisolated static func resolvedCalendar(
        for components: DateComponents,
        defaultCalendar: Calendar
    ) -> Calendar {
        var calendar = components.calendar ?? defaultCalendar
        if let timeZone = components.timeZone {
            calendar.timeZone = timeZone
        }
        return calendar
    }

    /// Returns the full week interval (half-open) as defined by the system calendar.
    public nonisolated static func weekDateInterval(
        containing date: Date,
        calendar: Calendar = .current
    ) -> DateInterval? {
        calendar.dateInterval(of: .weekOfYear, for: date)
    }

    public nonisolated static func agendaDateInterval(
        containing date: Date,
        calendar: Calendar = .current
    ) -> DateInterval? {
        guard let week = weekDateInterval(containing: date, calendar: calendar),
              let end = calendar.date(
                  byAdding: .day,
                  value: weekDayCount * agendaWeekCount,
                  to: week.start
              )
        else { return nil }
        return DateInterval(start: week.start, end: end)
    }

    public nonisolated static func daysOfWeek(
        containing date: Date,
        calendar: Calendar = .current
    ) -> [Date] {
        daysOfWeeks(containing: date, count: 1, calendar: calendar)
    }

    public nonisolated static func daysOfWeeks(
        containing date: Date,
        count: Int,
        calendar: Calendar = .current
    ) -> [Date] {
        guard count > 0 else { return [] }
        guard let week = weekDateInterval(containing: date, calendar: calendar) else { return [] }
        return (0..<(weekDayCount * count)).compactMap { offset in
            calendar.date(byAdding: .day, value: offset, to: week.start)
                .map { calendar.startOfDay(for: $0) }
        }
    }

    /// Matches timed, all-day, and multi-day items that overlap a given day.
    public nonisolated static func item(
        _ item: CalendarEventSnapshot,
        occursOn day: Date,
        calendar: Calendar = .current
    ) -> Bool {
        let dayStart = calendar.startOfDay(for: day)
        guard let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) else {
            return false
        }
        // Reminders with no duration should still be assigned to their due day.
        if item.endDate <= item.startDate {
            return item.startDate >= dayStart && item.startDate < dayEnd
        }
        return item.startDate < dayEnd && item.endDate > dayStart
    }

    /// Sorts only — does not truncate; date filtering is the caller's responsibility.
    public nonisolated static func preparedAgendaItems(
        _ items: [CalendarEventSnapshot]
    ) -> [CalendarEventSnapshot] {
        items.sorted(by: sortAgendaItems)
    }

    private nonisolated static func sortAgendaItems(
        _ lhs: CalendarEventSnapshot,
        _ rhs: CalendarEventSnapshot
    ) -> Bool {
        if lhs.startDate != rhs.startDate {
            return lhs.startDate < rhs.startDate
        }
        if lhs.kind != rhs.kind {
            return lhs.kind == .reminder
        }
        return lhs.id < rhs.id
    }

    public nonisolated static func canReadEvents(_ status: EKAuthorizationStatus) -> Bool {
        // macOS can retain the legacy read authorization value after an OS upgrade.
        status == .fullAccess || status.rawValue == 3
    }

    public nonisolated static func canReadReminders(_ status: EKAuthorizationStatus) -> Bool {
        canReadEvents(status)
    }
}
