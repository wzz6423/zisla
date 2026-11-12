import AppKit
import Combine
import EventKit
import Foundation
import ZislaCore

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
    public var eventURL: URL?
    public var notes: String?
    public var location: String?
    public var isCancelled: Bool
    public var isDeclined: Bool
    public var eventIdentity: CalendarEventIdentity?

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
        isProjectedOccurrence: Bool = false,
        eventURL: URL? = nil,
        notes: String? = nil,
        location: String? = nil,
        isCancelled: Bool = false,
        isDeclined: Bool = false,
        eventIdentity: CalendarEventIdentity? = nil
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
        self.eventURL = eventURL
        self.notes = notes
        self.location = location
        self.isCancelled = isCancelled
        self.isDeclined = isDeclined
        self.eventIdentity = eventIdentity
    }

    public var meetingURL: URL? {
        MeetingLink.extract(eventURL: eventURL, notes: notes, location: location)
    }
}

@MainActor
struct CalendarMutationCommands {
    var createEvent: (String, Date, Date, Bool, String?, String?) throws -> Void
    var createReminder: (String, Date, Bool) throws -> Void
    var delete: (CalendarItemKind, String, Date) throws -> Void
    var setReminderCompleted: (String, Bool) throws -> Void

    static func live(store: EKEventStore) -> CalendarMutationCommands {
        CalendarMutationCommands(
            createEvent: { title, startDate, endDate, isAllDay, location, notes in
                guard let calendar = store.defaultCalendarForNewEvents else {
                    throw CalendarMutationError.calendarUnavailable
                }
                let event = EKEvent(eventStore: store)
                event.title = title
                event.startDate = startDate
                event.endDate = endDate
                event.isAllDay = isAllDay
                event.location = location
                event.notes = notes
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
            delete: { kind, identifier, startDate in
                switch kind {
                case .event:
                    let sourceEvent = store.event(withIdentifier: identifier)
                        ?? store.calendarItem(withIdentifier: identifier) as? EKEvent
                    let event: EKEvent
                    if let sourceEvent,
                       sourceEvent.eventIdentifier == identifier,
                       sourceEvent.startDate == startDate {
                        event = sourceEvent
                    } else {
                        // Identifier lookup returns the first occurrence, so resolve the selected date before deleting.
                        let predicate = store.predicateForEvents(
                            withStart: startDate.addingTimeInterval(-1),
                            end: startDate.addingTimeInterval(1),
                            calendars: nil
                        )
                        guard let occurrence = store.events(matching: predicate).first(where: {
                            $0.eventIdentifier == identifier && $0.startDate == startDate
                        }) else {
                            throw CalendarMutationError.itemNotFound
                        }
                        event = occurrence
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
struct CalendarServiceEnvironment {
    var authorizationStatus: (EKEntityType) -> EKAuthorizationStatus
    var now: () -> Date
    var notificationCenter: NotificationCenter
    var workspaceNotificationCenter: NotificationCenter
    var enqueue: @Sendable (@escaping @MainActor @Sendable () -> Void) -> Void = { action in
        Task { @MainActor in action() }
    }
    var makeTimer: (@escaping @Sendable () -> Void) -> Timer = { action in
        Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { _ in action() }
    }
    var sleep: @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) }
    var authorizationPromptHost: () -> NSWindow? = { WindowPlacement.authorizationPromptHost() }

    static var live: Self {
        Self(authorizationStatus: EKEventStore.authorizationStatus(for:), now: Date.init,
             notificationCenter: .default, workspaceNotificationCenter: NSWorkspace.shared.notificationCenter)
    }
}

@MainActor
public final class CalendarService: ObservableObject {
    public nonisolated static let weekDayCount = 7
    public nonisolated static let agendaWeekCount = 2
    private static let refreshDebounce: Duration = .milliseconds(180)

    @Published public private(set) var events: [CalendarEventSnapshot] = []
    @Published public private(set) var meetingEvents: [CalendarEventSnapshot] = []
    @Published public private(set) var authorizationStatus: EKAuthorizationStatus
    @Published public private(set) var reminderAuthorizationStatus: EKAuthorizationStatus
    @Published public private(set) var errorDescription: String?
    @Published public private(set) var isLoading = false
    @Published public private(set) var lastRefreshedAt: Date?

    private let store: EKEventStore
    private var lastRefreshFinishedAt: Date?
    private let mutations: CalendarMutationCommands
    private let environment: CalendarServiceEnvironment
    private var storeChangedObserver: NSObjectProtocol?
    private var meetingObservers: [(NotificationCenter, NSObjectProtocol)] = []
    private var meetingRefreshTimer: Timer?
    private var monitoringGeneration: UInt64 = 0
    private(set) var scheduledRefresh: Task<Void, Never>?
    private var refreshGeneration: UInt64 = 0
    private var agendaLifecycleGeneration: UInt64 = 0
    private var isRefreshing = false
    private var monitorsAgenda = true
    /// Delayed refresh triggered by calendar changes continues querying the week the user is currently viewing.
    private var queryAnchorDate = Date()

    public convenience init() {
        let store = EKEventStore()
        self.init(store: store, mutations: .live(store: store))
    }

    init(store: EKEventStore, mutations: CalendarMutationCommands, environment: CalendarServiceEnvironment = .live) {
        self.store = store
        self.mutations = mutations
        self.environment = environment
        authorizationStatus = environment.authorizationStatus(.event)
        reminderAuthorizationStatus = environment.authorizationStatus(.reminder)
        queryAnchorDate = environment.now()
    }

    isolated deinit {
        stop()
    }

    public func start(monitorAgenda: Bool = true) {
        monitorsAgenda = monitorAgenda
        if !monitorAgenda {
            agendaLifecycleGeneration &+= 1
            refreshGeneration &+= 1
            scheduledRefresh?.cancel()
            scheduledRefresh = nil
        }
        guard storeChangedObserver == nil else { return }
        let generation = monitoringGeneration
        let enqueue = environment.enqueue
        storeChangedObserver = environment.notificationCenter.addObserver(
            forName: .EKEventStoreChanged,
            object: store,
            queue: .main
        ) { [weak self] _ in
            enqueue { @MainActor [weak self] in
                guard let self, self.monitoringGeneration == generation else { return }
                self.refreshMeetings()
                if self.monitorsAgenda { self.scheduleRefresh() }
            }
        }
        for (center, name) in [
            (environment.workspaceNotificationCenter, NSWorkspace.didWakeNotification),
            (environment.notificationCenter, NSNotification.Name.NSSystemClockDidChange),
            (environment.notificationCenter, NSNotification.Name.NSSystemTimeZoneDidChange),
            (environment.notificationCenter, NSNotification.Name.NSCalendarDayChanged),
        ] {
            let observer = center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                enqueue { @MainActor [weak self] in
                    guard let self, self.monitoringGeneration == generation else { return }
                    self.refreshMeetings()
                }
            }
            meetingObservers.append((center, observer))
        }
        meetingRefreshTimer = environment.makeTimer { [weak self] in
            enqueue { @MainActor [weak self] in
                guard let self, self.monitoringGeneration == generation else { return }
                self.refreshMeetings()
            }
        }
        meetingRefreshTimer?.tolerance = 10
        refreshMeetings()
    }

    public func stop() {
        monitoringGeneration &+= 1
        agendaLifecycleGeneration &+= 1
        refreshGeneration &+= 1
        scheduledRefresh?.cancel()
        scheduledRefresh = nil
        meetingRefreshTimer?.invalidate()
        meetingRefreshTimer = nil
        for (center, observer) in meetingObservers { center.removeObserver(observer) }
        meetingObservers.removeAll()
        if let storeChangedObserver {
            environment.notificationCenter.removeObserver(storeChangedObserver)
            self.storeChangedObserver = nil
        }
        meetingEvents = []
    }

    public func refreshMeetings() {
        updateAuthorizationStatuses()
        guard hasEventAccess else {
            meetingEvents = []
            return
        }
        let date = environment.now()
        let predicate = store.predicateForEvents(withStart: date, end: date.addingTimeInterval(86_400), calendars: nil)
        meetingEvents = MeetingWorkflow.meetings(in: store.events(matching: predicate).map(Self.makeEventSnapshot), at: date)
    }

    public func resolveMeeting(_ snapshot: CalendarEventSnapshot) -> CalendarEventSnapshot? {
        updateAuthorizationStatuses()
        guard hasEventAccess, let identity = snapshot.eventIdentity, let identifier = snapshot.sourceIdentifier else { return nil }
        let date = environment.now()
        if let event = store.event(withIdentifier: identifier) {
            let current = Self.makeEventSnapshot(event)
            if current.eventIdentity == identity {
                return MeetingWorkflow.meetings(in: [current], at: date).first
            }
        }
        let predicate = store.predicateForEvents(withStart: snapshot.startDate.addingTimeInterval(-1),
            end: snapshot.endDate.addingTimeInterval(1), calendars: nil)
        return MeetingWorkflow.meetings(in: store.events(matching: predicate).map(Self.makeEventSnapshot), at: date)
            .first { $0.eventIdentity == identity }
    }

    public func refresh(referenceDate: Date = Date()) async {
        queryAnchorDate = referenceDate
        refreshGeneration &+= 1
        let generation = refreshGeneration
        guard !isRefreshing else { return }
        let lifecycleGeneration = agendaLifecycleGeneration

        isRefreshing = true
        isLoading = true
        do {
            updateAuthorizationStatuses()
            try await requestUndeterminedAccess(lifecycleGeneration: lifecycleGeneration)
            try checkAgendaLifecycle(lifecycleGeneration)
            refreshMeetings()

            let readsEvents = Self.canReadEvents(authorizationStatus)
            let readsReminders = Self.canReadReminders(reminderAuthorizationStatus)
            guard readsEvents || readsReminders else {
                completeRefresh(
                    with: [],
                    generation: generation,
                    lifecycleGeneration: lifecycleGeneration,
                    errorDescription: AppLocalization.text("未授予日历或提醒事项访问权限")
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
                    lifecycleGeneration: lifecycleGeneration,
                    errorDescription: AppLocalization.text("无法计算日程查询范围")
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
                nextItems += store.events(matching: predicate).map(Self.makeEventSnapshot)
            }
            if readsReminders {
                fetchReminderSnapshots(
                    appending: nextItems,
                    from: start,
                    to: end,
                    calendar: calendar,
                    generation: generation,
                    lifecycleGeneration: lifecycleGeneration
                )
                return
            }

            completeRefresh(with: nextItems, generation: generation, lifecycleGeneration: lifecycleGeneration)
        } catch {
            completeRefresh(
                with: [],
                generation: generation,
                lifecycleGeneration: lifecycleGeneration,
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
        let lifecycleGeneration = agendaLifecycleGeneration
        updateAuthorizationStatuses()
        do {
            try await requestUndeterminedAccess(lifecycleGeneration: lifecycleGeneration)
            try checkAgendaLifecycle(lifecycleGeneration)
            await refresh(referenceDate: queryAnchorDate)
        } catch is CancellationError {
            return
        } catch {
            updateAuthorizationStatuses()
            errorDescription = error.localizedDescription
        }
    }

    public func createEvent(
        title: String,
        startDate: Date,
        endDate: Date,
        isAllDay: Bool,
        location: String? = nil,
        notes: String? = nil
    ) throws {
        let title = try normalizedTitle(title)
        guard endDate > startDate else { throw CalendarMutationError.invalidDateRange }
        try mutations.createEvent(title, startDate, endDate, isAllDay, location, notes)
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
        try mutations.delete(item.kind, identifier, item.startDate)
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

    private func checkAgendaLifecycle(_ generation: UInt64) throws {
        try Task.checkCancellation()
        guard generation == agendaLifecycleGeneration else { throw CancellationError() }
    }

    private func requestUndeterminedAccess(lifecycleGeneration: UInt64) async throws {
        try checkAgendaLifecycle(lifecycleGeneration)
        guard authorizationStatus == .notDetermined
            || reminderAuthorizationStatus == .notDetermined
        else { return }

        let authorizationHost = environment.authorizationPromptHost()
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
            try checkAgendaLifecycle(lifecycleGeneration)
            authorizationStatus = environment.authorizationStatus(.event)
        }
        if reminderAuthorizationStatus == .notDetermined {
            do {
                _ = try await store.requestFullAccessToReminders()
            } catch {
                if firstError == nil { firstError = error }
            }
            try checkAgendaLifecycle(lifecycleGeneration)
            reminderAuthorizationStatus = environment.authorizationStatus(.reminder)
        }
        if let firstError { throw firstError }
    }

    private func fetchReminderSnapshots(
        appending baseItems: [CalendarEventSnapshot],
        from start: Date,
        to end: Date,
        calendar: Calendar,
        generation: UInt64,
        lifecycleGeneration: UInt64
    ) {
        let enqueue = environment.enqueue
        let predicate = store.predicateForReminders(in: nil)
        store.fetchReminders(matching: predicate) { [weak self] reminders in
            enqueue { @MainActor [weak self] in
                guard let self else { return }
                let items = baseItems + Self.makeReminderSnapshots(
                    from: reminders ?? [],
                    calendar: calendar,
                    dueWithin: DateInterval(start: start, end: end)
                )
                self.completeRefresh(with: items, generation: generation, lifecycleGeneration: lifecycleGeneration)
            }
        }
    }

    private func completeRefresh(
        with items: [CalendarEventSnapshot],
        generation: UInt64,
        lifecycleGeneration: UInt64,
        errorDescription: String? = nil
    ) {
        defer {
            isRefreshing = false
            if generation == refreshGeneration {
                isLoading = false
            } else if lifecycleGeneration == agendaLifecycleGeneration, monitorsAgenda {
                scheduledRefresh = Task { @MainActor [weak self] in
                    guard let self, self.agendaLifecycleGeneration == lifecycleGeneration,
                          self.monitorsAgenda else { return }
                    await self.refresh(referenceDate: self.queryAnchorDate)
                }
            } else {
                isLoading = false
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
                    title: reminder.title?.isEmpty == false ? reminder.title : AppLocalization.text("未命名提醒"),
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

    nonisolated static func makeEventSnapshot(_ event: EKEvent) -> CalendarEventSnapshot {
        let identifier = event.eventIdentifier ?? event.calendarItemIdentifier
        let externalIdentifier = event.calendarItemExternalIdentifier ?? event.calendarItemIdentifier
        let identity = CalendarEventIdentity(
            calendarIdentifier: event.calendar.calendarIdentifier,
            eventIdentifier: externalIdentifier,
            occurrenceDate: event.hasRecurrenceRules || event.isDetached ? event.occurrenceDate : nil
        )
        return CalendarEventSnapshot(
            id: "event:\(identifier):\(event.startDate.timeIntervalSince1970)",
            title: event.title?.isEmpty == false ? event.title : AppLocalization.text("未命名日程"),
            startDate: event.startDate,
            endDate: event.endDate,
            isAllDay: event.isAllDay,
            calendarTitle: event.calendar.title,
            sourceIdentifier: identifier,
            eventURL: event.url,
            notes: event.notes,
            location: event.location,
            isCancelled: event.status == .canceled,
            isDeclined: isDeclined(participants: event.attendees?.map { ($0.isCurrentUser, $0.participantStatus) } ?? []),
            eventIdentity: identity
        )
    }

    nonisolated static func isDeclined(participants: [(isCurrentUser: Bool, status: EKParticipantStatus)]) -> Bool {
        participants.contains { $0.isCurrentUser && $0.status == .declined }
    }

    private func updateAuthorizationStatuses() {
        authorizationStatus = environment.authorizationStatus(.event)
        reminderAuthorizationStatus = environment.authorizationStatus(.reminder)
    }

    private func normalizedTitle(_ title: String) throws -> String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw CalendarMutationError.emptyTitle }
        return trimmed
    }

    private func scheduleRefresh() {
        guard storeChangedObserver != nil, monitorsAgenda else { return }
        scheduledRefresh?.cancel()
        let sleep = environment.sleep
        let monitoringGeneration = monitoringGeneration
        scheduledRefresh = Task { @MainActor [weak self] in
            do {
                try await sleep(Self.refreshDebounce)
            } catch {
                return
            }
            guard !Task.isCancelled, let self, self.monitoringGeneration == monitoringGeneration,
                  self.monitorsAgenda, self.storeChangedObserver != nil else { return }
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
