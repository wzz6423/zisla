import AppKit
import ZislaCore
import ZislaKit

@MainActor
enum CalendarItemEditor {
    static func present(
        calendar: CalendarService,
        draft: ClipboardCalendarDraft,
        allowsReminders: Bool = true,
        onError: (String) -> Void
    ) async {
        var availableKinds: [(title: String, kind: CalendarItemKind)] = []
        if calendar.hasEventAccess { availableKinds.append((AppLocalization.text("日历事件"), .event)) }
        if allowsReminders, calendar.hasReminderAccess {
            availableKinds.append((AppLocalization.text("提醒事项"), .reminder))
        }
        guard !availableKinds.isEmpty else {
            guard requestAuthorization(calendar: calendar) else { return }
            if calendar.hasUndeterminedAccess {
                await calendar.requestAccess()
                if calendar.hasEventAccess || (allowsReminders && calendar.hasReminderAccess) {
                    await present(calendar: calendar, draft: draft, allowsReminders: allowsReminders, onError: onError)
                } else {
                    onError(calendar.errorDescription ?? AppLocalization.text("需要日历权限"))
                }
            } else {
                NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars")!)
            }
            return
        }
        presentAuthorized(calendar: calendar, draft: draft, availableKinds: availableKinds, onError: onError)
    }

    private static func requestAuthorization(calendar: CalendarService) -> Bool {
        let alert = NSAlert()
        alert.messageText = AppLocalization.text("需要日历权限")
        alert.informativeText = AppLocalization.text("请在系统设置中允许访问日历和提醒事项")
        alert.addButton(withTitle: AppLocalization.text(calendar.hasUndeterminedAccess ? "授权日历" : "打开系统设置"))
        alert.addButton(withTitle: AppLocalization.text("取消"))
        WindowPlacement.prepareModal(alert.window, on: WindowPlacement.screenUnderMouse())
        return alert.runModal() == .alertFirstButtonReturn
    }

    private static func presentAuthorized(
        calendar: CalendarService,
        draft: ClipboardCalendarDraft,
        availableKinds: [(title: String, kind: CalendarItemKind)],
        onError: (String) -> Void
    ) {
        let kindPicker = NSPopUpButton(frame: .zero, pullsDown: false)
        kindPicker.addItems(withTitles: availableKinds.map(\.title))
        let titleField = NSTextField(string: draft.title)
        titleField.placeholderString = AppLocalization.text("标题")
        let startPicker = datePicker(value: draft.startDate)
        let endPicker = datePicker(value: draft.endDate)
        let locationField = NSTextField(string: draft.location ?? "")
        let notesField = NSTextField(wrappingLabelWithString: draft.notes ?? "")
        notesField.isEditable = true
        notesField.isSelectable = true
        notesField.isBezeled = true
        notesField.drawsBackground = true
        notesField.maximumNumberOfLines = 3
        let allDay = NSButton(checkboxWithTitle: AppLocalization.text("全天"), target: nil, action: nil)
        allDay.state = draft.isAllDay ? .on : .off

        let grid = NSGridView(views: [
            [NSTextField(labelWithString: AppLocalization.text("类型")), kindPicker],
            [NSTextField(labelWithString: AppLocalization.text("标题")), titleField],
            [NSTextField(labelWithString: AppLocalization.text("时间")), startPicker],
            [NSTextField(labelWithString: AppLocalization.text("结束时间")), endPicker],
            [NSTextField(labelWithString: AppLocalization.text("会议地点")), locationField],
            [NSTextField(labelWithString: AppLocalization.text("日程备注")), notesField],
            [NSView(), allDay],
        ])
        grid.rowSpacing = 8
        grid.columnSpacing = 10
        grid.column(at: 0).xPlacement = .trailing
        grid.column(at: 1).width = 280
        grid.frame = CGRect(x: 0, y: 0, width: 380, height: 234)

        let alert = NSAlert()
        alert.messageText = AppLocalization.text("新增日程")
        alert.informativeText = AppLocalization.text("保存到系统日历或提醒事项。")
        alert.accessoryView = grid
        alert.addButton(withTitle: AppLocalization.text("新增"))
        alert.addButton(withTitle: AppLocalization.text("取消"))
        NSApp.activate(ignoringOtherApps: true)
        WindowPlacement.prepareModal(alert.window, on: WindowPlacement.screenUnderMouse())
        let response = alert.runModal()
        let edited = ClipboardCalendarDraft(
            title: titleField.stringValue,
            startDate: startPicker.dateValue,
            endDate: endPicker.dateValue,
            isAllDay: allDay.state == .on,
            location: locationField.stringValue,
            notes: notesField.stringValue
        )
        do {
            try complete(response: response, calendar: calendar, draft: edited,
                         kind: availableKinds[kindPicker.indexOfSelectedItem].kind)
        } catch {
            onError(error.localizedDescription)
        }
    }

    static func complete(
        response: NSApplication.ModalResponse,
        calendar: CalendarService,
        draft: ClipboardCalendarDraft,
        kind: CalendarItemKind
    ) throws {
        guard response == .alertFirstButtonReturn else { return }
        switch kind {
        case .event:
            let systemCalendar = Calendar.current
            let start = draft.isAllDay ? systemCalendar.startOfDay(for: draft.startDate) : draft.startDate
            let endDay = systemCalendar.startOfDay(for: draft.endDate)
            let end = draft.isAllDay
                ? (endDay > start ? endDay : systemCalendar.date(byAdding: .day, value: 1, to: start)!)
                : draft.endDate
            try calendar.createEvent(
                title: draft.title, startDate: start, endDate: end, isAllDay: draft.isAllDay,
                location: draft.location, notes: draft.notes
            )
        case .reminder:
            try calendar.createReminder(title: draft.title, dueDate: draft.startDate, isAllDay: draft.isAllDay)
        }
    }

    private static func datePicker(value: Date) -> NSDatePicker {
        let picker = NSDatePicker()
        picker.datePickerStyle = .textFieldAndStepper
        picker.datePickerElements = [.yearMonthDay, .hourMinute]
        picker.dateValue = value
        return picker
    }
}
