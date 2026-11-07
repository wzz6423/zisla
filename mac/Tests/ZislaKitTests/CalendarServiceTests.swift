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
    func agendaDateIntervalCoversBothVisibleWeeks() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "Asia/Shanghai"))
        calendar.firstWeekday = 1
        let friday = try #require(calendar.date(
            from: DateComponents(year: 2026, month: 8, day: 7, hour: 15)
        ))

        let interval = try #require(CalendarService.agendaDateInterval(
            containing: friday,
            calendar: calendar
        ))
        let expectedStart = try #require(calendar.date(
            from: DateComponents(year: 2026, month: 8, day: 2)
        ))
        let expectedEnd = try #require(calendar.date(
            from: DateComponents(year: 2026, month: 8, day: 16)
        ))

        #expect(interval.start == expectedStart)
        #expect(interval.end == expectedEnd)
    }

    @Test
    func twoWeekRangeCoversFourteenConsecutiveCalendarDays() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "Asia/Shanghai"))
        calendar.firstWeekday = 2
        let wednesday = try #require(calendar.date(
            from: DateComponents(year: 2026, month: 7, day: 22, hour: 15)
        ))

        let days = CalendarService.daysOfWeeks(
            containing: wednesday,
            count: 2,
            calendar: calendar
        )

        #expect(days.count == 14)
        #expect(calendar.isDate(
            days[0],
            inSameDayAs: try #require(calendar.date(from: DateComponents(year: 2026, month: 7, day: 20)))
        ))
        #expect(calendar.isDate(
            days[13],
            inSameDayAs: try #require(calendar.date(from: DateComponents(year: 2026, month: 8, day: 2)))
        ))
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
        #expect(recorder.deletedItems.map(\.startDate) == [now, now])
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
        store.identifierEvent = try store.makeEvent(startDate: Date(timeIntervalSince1970: 1_000))
        let commands = CalendarMutationCommands.live(store: store)

        try commands.delete(.event, "event-source", Date(timeIntervalSince1970: 1_000))

        #expect(store.requestedEventIdentifier == "event-source")
        #expect(store.requestedCalendarItemIdentifier == nil)
        #expect(store.removedEvent === store.identifierEvent)
    }

    @Test @MainActor
    func deletingRepeatedEventDeletesSelectedOccurrence() throws {
        let store = EventStoreDeletionSpy()
        let firstDate = Date(timeIntervalSince1970: 1_000_000)
        let first = try store.makeEvent(startDate: firstDate)
        let selectedDate = firstDate.addingTimeInterval(86_400)
        let selected = try store.makeEvent(startDate: selectedDate)
        store.identifierEvent = first
        store.matchingEvents = [first, selected]
        let service = CalendarService(store: store, mutations: .live(store: store))
        let item = CalendarEventSnapshot(
            id: "event-row-second-day",
            title: "Daily meeting",
            startDate: selectedDate,
            endDate: selected.endDate,
            isAllDay: false,
            calendarTitle: "Work",
            sourceIdentifier: "event-source"
        )

        try service.delete(item)

        #expect(store.removedEvent === selected, "Deleting tomorrow's occurrence must preserve today's occurrence")
        #expect(store.removedEvent?.startDate == selectedDate)
        #expect(store.removedEventSpan == .thisEvent)
        #expect(store.removalCommitted == true)
    }

    @Test @MainActor
    func deletingMissingOccurrenceNeverDeletesNearbyOrUnrelatedEvents() throws {
        let store = EventStoreDeletionSpy()
        let selectedDate = Date(timeIntervalSince1970: 1_000_000)
        store.identifierEvent = try store.makeEvent(startDate: selectedDate.addingTimeInterval(-86_400))
        store.matchingEvents = [
            try store.makeEvent(startDate: selectedDate, identifier: "other-series"),
            try store.makeEvent(startDate: selectedDate.addingTimeInterval(-60)),
        ]
        let commands = CalendarMutationCommands.live(store: store)

        #expect(throws: CalendarMutationError.itemNotFound) {
            try commands.delete(.event, "event-source", selectedDate)
        }
        #expect(store.removedEvent == nil, "A stale selection must not delete a nearby occurrence or another series")
    }

    @Test @MainActor
    func deletingEventRejectsWrongIdentifierFromDirectLookup() throws {
        let store = EventStoreDeletionSpy()
        let selectedDate = Date(timeIntervalSince1970: 1_000_000)
        store.identifierEvent = try store.makeEvent(startDate: selectedDate, identifier: "other-series")
        let commands = CalendarMutationCommands.live(store: store)

        #expect(throws: CalendarMutationError.itemNotFound) {
            try commands.delete(.event, "event-source", selectedDate)
        }
        #expect(store.removedEvent == nil)
    }

    @Test @MainActor
    func deletingEventWithNoMatchesFailsWithoutMutation() {
        let store = EventStoreDeletionSpy()
        let commands = CalendarMutationCommands.live(store: store)

        #expect(throws: CalendarMutationError.itemNotFound) {
            try commands.delete(.event, "missing-event", Date(timeIntervalSince1970: 1_000_000))
        }
        #expect(store.removedEvent == nil)
    }

    @Test(arguments: [false, true]) @MainActor
    func deletingMovedOccurrenceUsesCurrentStartDate(hasDetachedIdentifier: Bool) throws {
        let store = EventStoreDeletionSpy()
        let firstDate = Date(timeIntervalSince1970: 1_000_000)
        let originalDate = firstDate.addingTimeInterval(86_400)
        let movedDate = originalDate.addingTimeInterval(7_200)
        let identifier = hasDetachedIdentifier ? "detached-event" : "event-source"
        let selected = try store.makeEvent(startDate: movedDate, identifier: identifier)
        selected.fixtureOccurrenceDate = originalDate
        selected.fixtureIsDetached = true
        store.identifierEvent = try store.makeEvent(startDate: firstDate)
        store.matchingEvents = [
            try store.makeEvent(startDate: movedDate, identifier: "unrelated-event"),
            selected,
        ]
        let commands = CalendarMutationCommands.live(store: store)

        try commands.delete(.event, identifier, movedDate)

        #expect(store.removedEvent === selected)
        #expect(store.removedEvent?.startDate == movedDate)
        #expect(store.removedEventSpan == .thisEvent)
    }

    @Test @MainActor
    func deletingRepeatedAllDayEventIncludesMidnightOccurrence() throws {
        let store = EventStoreDeletionSpy()
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "Asia/Shanghai"))
        let selectedDate = try #require(calendar.date(from: DateComponents(year: 2026, month: 11, day: 7)))
        let first = try store.makeEvent(startDate: selectedDate.addingTimeInterval(-86_400))
        first.isAllDay = true
        first.endDate = selectedDate
        let selected = try store.makeEvent(startDate: selectedDate)
        selected.isAllDay = true
        selected.endDate = selectedDate.addingTimeInterval(86_400)
        store.identifierEvent = first
        store.matchingEvents = [first, selected]
        let commands = CalendarMutationCommands.live(store: store)

        try commands.delete(.event, "event-source", selectedDate)

        #expect(store.removedEvent === selected)
        #expect(store.removedEvent?.isAllDay == true)
    }

    @Test @MainActor
    func deletingRepeatedPointEventIncludesExactOccurrence() throws {
        let store = EventStoreDeletionSpy()
        let selectedDate = Date(timeIntervalSince1970: 1_000_000)
        let selected = try store.makeEvent(startDate: selectedDate)
        selected.endDate = selectedDate
        store.identifierEvent = try store.makeEvent(startDate: selectedDate.addingTimeInterval(-86_400))
        store.matchingEvents = [selected]
        let commands = CalendarMutationCommands.live(store: store)

        try commands.delete(.event, "event-source", selectedDate)

        #expect(store.removedEvent === selected)
    }

    @Test @MainActor
    func deletingEventCanResolveOccurrenceWithoutIdentifierLookup() throws {
        let store = EventStoreDeletionSpy()
        let selectedDate = Date(timeIntervalSince1970: 1_000_000)
        let selected = try store.makeEvent(startDate: selectedDate)
        store.matchingEvents = [selected]
        let commands = CalendarMutationCommands.live(store: store)

        try commands.delete(.event, "event-source", selectedDate)

        #expect(store.removedEvent === selected)
    }

    @Test @MainActor
    func deletingEventRetainsCalendarItemLookupFallback() throws {
        let store = EventStoreDeletionSpy()
        let selectedDate = Date(timeIntervalSince1970: 1_000_000)
        let selected = try store.makeEvent(startDate: selectedDate)
        store.identifierCalendarItem = selected
        let commands = CalendarMutationCommands.live(store: store)

        try commands.delete(.event, "event-source", selectedDate)

        #expect(store.removedEvent === selected)
    }

    @Test @MainActor
    func deletingEventPropagatesStoreFailureWithoutMutation() throws {
        let store = EventStoreDeletionSpy()
        let selectedDate = Date(timeIntervalSince1970: 1_000_000)
        store.identifierEvent = try store.makeEvent(startDate: selectedDate)
        store.removalError = CalendarMutationError.calendarUnavailable
        let service = CalendarService(store: store, mutations: .live(store: store))
        let item = CalendarEventSnapshot(
            id: "event-row",
            title: "Meeting",
            startDate: selectedDate,
            endDate: selectedDate.addingTimeInterval(3_600),
            isAllDay: false,
            calendarTitle: "Work",
            sourceIdentifier: "event-source"
        )

        #expect(throws: CalendarMutationError.calendarUnavailable) { try service.delete(item) }
        #expect(store.removedEvent == nil)
    }

    @Test @MainActor
    func deletingReminderKeepsIdentifierBasedBehavior() throws {
        let store = EventStoreDeletionSpy()
        let reminder = EKReminder(eventStore: store)
        reminder.dueDateComponents = DateComponents(year: 2026, month: 11, day: 8)
        store.identifierCalendarItem = reminder
        let commands = CalendarMutationCommands.live(store: store)

        try commands.delete(.reminder, "reminder-source", Date(timeIntervalSince1970: 1_000_000))

        #expect(store.removedReminder === reminder)
        #expect(store.requestedEventIdentifier == nil)
        #expect(store.removedEvent == nil)
        #expect(store.removalCommitted == true)
    }

    @Test(arguments: [nil, ""]) @MainActor
    func deletingItemWithoutSourceIdentifierRejectsMutation(identifier: String?) {
        let recorder = CalendarMutationRecorder()
        let service = CalendarService(store: EKEventStore(), mutations: recorder.commands)
        let selectedDate = Date(timeIntervalSince1970: 1_000_000)
        let item = CalendarEventSnapshot(
            id: "event-row",
            title: "Meeting",
            startDate: selectedDate,
            endDate: selectedDate.addingTimeInterval(3_600),
            isAllDay: false,
            calendarTitle: "Work",
            sourceIdentifier: identifier
        )

        #expect(throws: CalendarMutationError.missingSourceIdentifier) { try service.delete(item) }
        #expect(recorder.deletedItems.isEmpty)
    }

}

@MainActor
private final class CalendarMutationRecorder {
    var createdEvent: (title: String, start: Date, end: Date, isAllDay: Bool)?
    var createdReminder: (title: String, dueDate: Date, isAllDay: Bool)?
    var reminderCompletionUpdates: [(identifier: String, isCompleted: Bool)] = []
    var deletedItems: [(kind: CalendarItemKind, identifier: String, startDate: Date)] = []

    var commands: CalendarMutationCommands {
        CalendarMutationCommands(
            createEvent: { [weak self] title, start, end, isAllDay, _, _ in
                self?.createdEvent = (title, start, end, isAllDay)
            },
            createReminder: { [weak self] title, dueDate, isAllDay in
                self?.createdReminder = (title, dueDate, isAllDay)
            },
            delete: { [weak self] kind, identifier, startDate in
                self?.deletedItems.append((kind, identifier, startDate))
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
    var identifierEvent: EKEvent?
    var identifierCalendarItem: EKCalendarItem?
    var matchingEvents: [EKEvent] = []
    var removalError: Error?
    var removedEvent: EKEvent?
    var removedEventSpan: EKSpan?
    var removedReminder: EKReminder?
    var removalCommitted: Bool?

    func makeEvent(startDate: Date, identifier: String = "event-source") throws -> DeletionEvent {
        // Swift does not inherit EventKit's factory initializer for subclasses.
        let event = try #require(DeletionEvent.perform(
            NSSelectorFromString("eventWithEventStore:"), with: self
        )?.takeUnretainedValue() as? DeletionEvent)
        event.fixtureIdentifier = identifier
        event.fixtureOccurrenceDate = nil
        event.fixtureIsDetached = false
        event.startDate = startDate
        event.endDate = startDate.addingTimeInterval(3_600)
        return event
    }

    override func event(withIdentifier identifier: String) -> EKEvent? {
        requestedEventIdentifier = identifier
        return identifierEvent
    }

    override func calendarItem(withIdentifier identifier: String) -> EKCalendarItem? {
        requestedCalendarItemIdentifier = identifier
        return identifierCalendarItem
    }

    override func predicateForEvents(withStart start: Date, end: Date, calendars: [EKCalendar]?) -> NSPredicate {
        NSPredicate { item, _ in
            guard let event = item as? EKEvent else { return false }
            return event.startDate < end && event.endDate > start
        }
    }

    override func events(matching predicate: NSPredicate) -> [EKEvent] {
        matchingEvents.filter { predicate.evaluate(with: $0) }
    }

    override func remove(_ event: EKEvent, span: EKSpan, commit: Bool) throws {
        if let removalError { throw removalError }
        removedEvent = event
        removedEventSpan = span
        removalCommitted = commit
    }

    override func remove(_ reminder: EKReminder, commit: Bool) throws {
        removedReminder = reminder
        removalCommitted = commit
    }
}

private final class DeletionEvent: EKEvent {
    var fixtureIdentifier = "event-source"
    var fixtureOccurrenceDate: Date?
    var fixtureIsDetached = false

    override var eventIdentifier: String! { fixtureIdentifier }
    override var occurrenceDate: Date! { fixtureOccurrenceDate ?? startDate }
    override var isDetached: Bool { fixtureIsDetached }
}
