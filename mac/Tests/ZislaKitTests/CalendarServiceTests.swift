import EventKit
import Foundation
import Testing

@testable import ZislaKit

struct CalendarServiceTests {
    @Test
    func legacyAuthorizedAndFullAccessStatusesCanReadEvents() throws {
        let legacyAuthorized = try #require(EKAuthorizationStatus(rawValue: 3))
        #expect(CalendarService.canReadEvents(legacyAuthorized))
        #expect(CalendarService.canReadEvents(.fullAccess))
        #expect(CalendarService.canReadReminders(legacyAuthorized))
        #expect(CalendarService.canReadReminders(.fullAccess))
        #expect(!CalendarService.canReadEvents(.writeOnly))
        #expect(!CalendarService.canReadEvents(.denied))
        #expect(!CalendarService.canReadReminders(.denied))
    }

    @Test
    func weekDateIntervalCoversSevenCalendarDays() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "Asia/Shanghai"))
        calendar.firstWeekday = 2 // Monday-start week

        let wednesday = try #require(calendar.date(
            from: DateComponents(year: 2026, month: 7, day: 22, hour: 15)
        ))
        let week = try #require(CalendarService.weekDateInterval(
            containing: wednesday,
            calendar: calendar
        ))
        let days = CalendarService.daysOfWeek(containing: wednesday, calendar: calendar)

        #expect(CalendarService.weekDayCount == 7)
        #expect(days.count == 7)
        #expect(calendar.component(.weekday, from: days[0]) == 2)
        #expect(calendar.isDate(
            days[0],
            inSameDayAs: try #require(calendar.date(from: DateComponents(year: 2026, month: 7, day: 20)))
        ))
        #expect(calendar.isDate(
            days[6],
            inSameDayAs: try #require(calendar.date(from: DateComponents(year: 2026, month: 7, day: 26)))
        ))
        #expect(week.duration == 7 * 24 * 60 * 60)
    }

    @Test
    func itemOccursOnMatchesCrossMidnightAndPointReminders() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "Asia/Shanghai"))

        let day20 = try #require(calendar.date(from: DateComponents(year: 2026, month: 7, day: 20)))
        let day21 = try #require(calendar.date(from: DateComponents(year: 2026, month: 7, day: 21)))
        let day22 = try #require(calendar.date(from: DateComponents(year: 2026, month: 7, day: 22)))

        let overnightStart = try #require(calendar.date(
            from: DateComponents(year: 2026, month: 7, day: 20, hour: 22)
        ))
        let overnightEnd = try #require(calendar.date(
            from: DateComponents(year: 2026, month: 7, day: 21, hour: 2)
        ))
        let overnight = CalendarEventSnapshot(
            id: "overnight",
            title: "跨夜",
            startDate: overnightStart,
            endDate: overnightEnd,
            isAllDay: false,
            calendarTitle: "工作"
        )

        let multiDayStart = try #require(calendar.date(
            from: DateComponents(year: 2026, month: 7, day: 20)
        ))
        let multiDayEnd = try #require(calendar.date(
            from: DateComponents(year: 2026, month: 7, day: 22)
        ))
        let multiDay = CalendarEventSnapshot(
            id: "multi",
            title: "出差",
            startDate: multiDayStart,
            endDate: multiDayEnd,
            isAllDay: true,
            calendarTitle: "工作"
        )

        let reminderDue = try #require(calendar.date(
            from: DateComponents(year: 2026, month: 7, day: 21, hour: 9, minute: 30)
        ))
        let reminder = CalendarEventSnapshot(
            id: "reminder",
            title: "打卡",
            startDate: reminderDue,
            endDate: reminderDue,
            isAllDay: false,
            calendarTitle: "提醒",
            kind: .reminder
        )

        #expect(CalendarService.item(overnight, occursOn: day20, calendar: calendar))
        #expect(CalendarService.item(overnight, occursOn: day21, calendar: calendar))
        #expect(!CalendarService.item(overnight, occursOn: day22, calendar: calendar))

        #expect(CalendarService.item(multiDay, occursOn: day20, calendar: calendar))
        #expect(CalendarService.item(multiDay, occursOn: day21, calendar: calendar))
        #expect(!CalendarService.item(multiDay, occursOn: day22, calendar: calendar))

        #expect(!CalendarService.item(reminder, occursOn: day20, calendar: calendar))
        #expect(CalendarService.item(reminder, occursOn: day21, calendar: calendar))
    }

    @Test
    func preparedAgendaItemsKeepsFullSortedListWithoutTruncation() {
        let base = Date(timeIntervalSince1970: 1_000_000)
        let items = (0..<12).map { index in
            CalendarEventSnapshot(
                id: "item-\(index)",
                title: "事项 \(index)",
                startDate: base.addingTimeInterval(TimeInterval(12 - index) * 60),
                endDate: base.addingTimeInterval(TimeInterval(12 - index) * 60 + 30),
                isAllDay: false,
                calendarTitle: "工作"
            )
        }

        let prepared = CalendarService.preparedAgendaItems(items)
        #expect(prepared.count == 12)
        #expect(prepared.map(\.id) == (0..<12).reversed().map { "item-\($0)" })
    }

    @Test
    func reminderDatePreservesTimedAndAllDaySemantics() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "Asia/Shanghai"))
        let timed = try #require(CalendarService.reminderDate(
            from: DateComponents(year: 2026, month: 7, day: 20, hour: 19, minute: 5),
            defaultCalendar: calendar
        ))
        let allDay = try #require(CalendarService.reminderDate(
            from: DateComponents(year: 2026, month: 7, day: 21),
            defaultCalendar: calendar
        ))

        #expect(!timed.isAllDay)
        #expect(calendar.component(.hour, from: timed.date) == 19)
        #expect(allDay.isAllDay)
        #expect(allDay.date == calendar.startOfDay(for: allDay.date))
    }

    @Test
    func reminderSnapshotsKeepBothCompletionStatesInsideDateRange() async throws {
        let snapshots = await Task.detached { () -> [CalendarEventSnapshot] in
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = TimeZone(secondsFromGMT: 0)!
            let store = EKEventStore()
            let reminderCalendar = EKCalendar(for: .reminder, eventStore: store)
            let pending = EKReminder(eventStore: store)
            pending.title = "未完成提醒"
            pending.calendar = reminderCalendar
            pending.dueDateComponents = DateComponents(
                calendar: calendar,
                timeZone: calendar.timeZone,
                year: 2026,
                month: 7,
                day: 21,
                hour: 9,
                minute: 30
            )
            let completed = EKReminder(eventStore: store)
            completed.title = "已完成提醒"
            completed.calendar = reminderCalendar
            completed.dueDateComponents = DateComponents(
                calendar: calendar,
                timeZone: calendar.timeZone,
                year: 2026,
                month: 7,
                day: 22
            )
            completed.isCompleted = true
            completed.completionDate = Date(timeIntervalSince1970: 1_000)
            let outsideRange = EKReminder(eventStore: store)
            outsideRange.title = "下周提醒"
            outsideRange.calendar = reminderCalendar
            outsideRange.dueDateComponents = DateComponents(
                calendar: calendar,
                timeZone: calendar.timeZone,
                year: 2026,
                month: 7,
                day: 27
            )
            let rangeStart = calendar.date(
                from: DateComponents(year: 2026, month: 7, day: 19)
            )!
            let rangeEnd = calendar.date(
                from: DateComponents(year: 2026, month: 7, day: 26)
            )!
            return CalendarService.makeReminderSnapshots(
                from: [pending, completed, outsideRange],
                calendar: calendar,
                dueWithin: DateInterval(start: rangeStart, end: rangeEnd)
            )
        }.value

        #expect(snapshots.map(\.title) == ["未完成提醒", "已完成提醒"])
        #expect(snapshots.map(\.isCompleted) == [false, true])
        #expect(snapshots.allSatisfy { $0.kind == .reminder })
    }

    @Test
    func recurringReminderSnapshotsExpandOccurrencesInsideDateRange() async throws {
        let snapshots = await Task.detached { () -> [CalendarEventSnapshot] in
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
            let store = EKEventStore()
            let reminderCalendar = EKCalendar(for: .reminder, eventStore: store)
            let reminder = EKReminder(eventStore: store)
            reminder.title = "工作日打卡"
            reminder.calendar = reminderCalendar
            reminder.dueDateComponents = DateComponents(
                calendar: calendar,
                timeZone: calendar.timeZone,
                year: 2026,
                month: 7,
                day: 22,
                hour: 9,
                minute: 5
            )
            reminder.addRecurrenceRule(EKRecurrenceRule(
                recurrenceWith: .weekly,
                interval: 1,
                daysOfTheWeek: [
                    EKRecurrenceDayOfWeek(.wednesday),
                    EKRecurrenceDayOfWeek(.thursday),
                    EKRecurrenceDayOfWeek(.friday),
                ],
                daysOfTheMonth: nil,
                monthsOfTheYear: nil,
                weeksOfTheYear: nil,
                daysOfTheYear: nil,
                setPositions: nil,
                end: nil
            ))
            let rangeStart = calendar.date(
                from: DateComponents(year: 2026, month: 7, day: 19)
            )!
            let rangeEnd = calendar.date(
                from: DateComponents(year: 2026, month: 7, day: 26)
            )!
            return CalendarService.makeReminderSnapshots(
                from: [reminder],
                calendar: calendar,
                dueWithin: DateInterval(start: rangeStart, end: rangeEnd)
            )
        }.value

        let occurrenceDays = snapshots.map {
            Calendar(identifier: .gregorian).component(.day, from: $0.startDate)
        }
        #expect(occurrenceDays == [22, 23, 24])
        #expect(Set(snapshots.map(\.id)).count == 3)
        #expect(snapshots.map(\.isProjectedOccurrence) == [false, true, true])
    }

    @Test @MainActor
    func createEventTrimsTitleAndForwardsValidatedDates() throws {
        let recorder = CalendarMutationRecorder()
        let service = CalendarService(
            store: EKEventStore(),
            mutations: recorder.commands
        )
        let start = Date(timeIntervalSince1970: 1_000)
        let end = start.addingTimeInterval(3_600)

        try service.createEvent(
            title: "  周会  ",
            startDate: start,
            endDate: end,
            isAllDay: false
        )

        #expect(recorder.createdEvent?.title == "周会")
        #expect(recorder.createdEvent?.start == start)
        #expect(recorder.createdEvent?.end == end)
        #expect(recorder.createdEvent?.isAllDay == false)
    }

    @Test @MainActor
    func invalidEventInputNeverReachesEventKitMutation() {
        let recorder = CalendarMutationRecorder()
        let service = CalendarService(
            store: EKEventStore(),
            mutations: recorder.commands
        )
        let start = Date(timeIntervalSince1970: 1_000)

        #expect(throws: CalendarMutationError.emptyTitle) {
            try service.createEvent(
                title: "   ",
                startDate: start,
                endDate: start.addingTimeInterval(60),
                isAllDay: false
            )
        }
        #expect(throws: CalendarMutationError.invalidDateRange) {
            try service.createEvent(
                title: "无效",
                startDate: start,
                endDate: start,
                isAllDay: false
            )
        }
        #expect(recorder.createdEvent == nil)
    }

    @Test @MainActor
    func createReminderTrimsTitleAndForwardsDueDate() throws {
        let recorder = CalendarMutationRecorder()
        let service = CalendarService(
            store: EKEventStore(),
            mutations: recorder.commands
        )
        let dueDate = Date(timeIntervalSince1970: 4_000)

        try service.createReminder(
            title: "  下班打卡  ",
            dueDate: dueDate,
            isAllDay: false
        )

        #expect(recorder.createdReminder?.title == "下班打卡")
        #expect(recorder.createdReminder?.dueDate == dueDate)
        #expect(recorder.createdReminder?.isAllDay == false)
    }

    @Test @MainActor
    func reminderCompletionCanBeToggledAndBothKindsCanBeDeletedBySourceIdentifier() throws {
        let recorder = CalendarMutationRecorder()
        let service = CalendarService(
            store: EKEventStore(),
            mutations: recorder.commands
        )
        let now = Date(timeIntervalSince1970: 2_000)
        let event = CalendarEventSnapshot(
            id: "event-row",
            title: "会议",
            startDate: now,
            endDate: now.addingTimeInterval(60),
            isAllDay: false,
            calendarTitle: "工作",
            kind: .event,
            sourceIdentifier: "event-source"
        )
        let reminder = CalendarEventSnapshot(
            id: "reminder-row",
            title: "打卡",
            startDate: now,
            endDate: now,
            isAllDay: false,
            calendarTitle: "提醒",
            kind: .reminder,
            sourceIdentifier: "reminder-source"
        )

        try service.setReminderCompleted(reminder, isCompleted: true)
        try service.setReminderCompleted(reminder, isCompleted: false)
        try service.delete(event)
        try service.delete(reminder)

        #expect(recorder.reminderCompletionUpdates.map(\.identifier) == [
            "reminder-source",
            "reminder-source",
        ])
        #expect(recorder.reminderCompletionUpdates.map(\.isCompleted) == [true, false])
        #expect(recorder.deletedItems.map(\.kind) == [.event, .reminder])
        #expect(recorder.deletedItems.map(\.identifier) == ["event-source", "reminder-source"])
    }

    @Test @MainActor
    func projectedReminderOccurrencesRejectMutations() {
        let recorder = CalendarMutationRecorder()
        let service = CalendarService(
            store: EKEventStore(),
            mutations: recorder.commands
        )
        let projected = CalendarEventSnapshot(
            id: "projected-reminder",
            title: "明天打卡",
            startDate: Date(timeIntervalSince1970: 3_000),
            endDate: Date(timeIntervalSince1970: 3_000),
            isAllDay: false,
            calendarTitle: "提醒",
            kind: .reminder,
            sourceIdentifier: "current-reminder-source",
            isProjectedOccurrence: true
        )

        #expect(throws: CalendarMutationError.actionNotSupported) {
            try service.setReminderCompleted(projected, isCompleted: true)
        }
        #expect(throws: CalendarMutationError.actionNotSupported) {
            try service.delete(projected)
        }
        #expect(recorder.reminderCompletionUpdates.isEmpty)
        #expect(recorder.deletedItems.isEmpty)
    }

    @Test @MainActor
    func deletingEventUsesEventIdentifierLookup() throws {
        let store = EventStoreDeletionSpy()
        let commands = CalendarMutationCommands.live(store: store)

        try commands.delete(.event, "event-source")

        #expect(store.requestedEventIdentifier == "event-source")
        #expect(store.requestedCalendarItemIdentifier == nil)
        #expect(store.removedEvent != nil)
    }

}

@MainActor
private final class CalendarMutationRecorder {
    var createdEvent: (title: String, start: Date, end: Date, isAllDay: Bool)?
    var createdReminder: (title: String, dueDate: Date, isAllDay: Bool)?
    var reminderCompletionUpdates: [(identifier: String, isCompleted: Bool)] = []
    var deletedItems: [(kind: CalendarItemKind, identifier: String)] = []

    var commands: CalendarMutationCommands {
        CalendarMutationCommands(
            createEvent: { [weak self] title, start, end, isAllDay in
                self?.createdEvent = (title, start, end, isAllDay)
            },
            createReminder: { [weak self] title, dueDate, isAllDay in
                self?.createdReminder = (title, dueDate, isAllDay)
            },
            delete: { [weak self] kind, identifier in
                self?.deletedItems.append((kind, identifier))
            },
            setReminderCompleted: { [weak self] identifier, isCompleted in
                self?.reminderCompletionUpdates.append((identifier, isCompleted))
            }
        )
    }
}

private final class EventStoreDeletionSpy: EKEventStore {
    var requestedEventIdentifier: String?
    var requestedCalendarItemIdentifier: String?
    var removedEvent: EKEvent?

    override func event(withIdentifier identifier: String) -> EKEvent? {
        requestedEventIdentifier = identifier
        return EKEvent(eventStore: self)
    }

    override func calendarItem(withIdentifier identifier: String) -> EKCalendarItem? {
        requestedCalendarItemIdentifier = identifier
        return nil
    }

    override func remove(_ event: EKEvent, span: EKSpan, commit: Bool) throws {
        removedEvent = event
    }
}
