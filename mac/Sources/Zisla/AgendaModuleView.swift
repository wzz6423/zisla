import AppKit
import EventKit
import ZislaCore
import ZislaKit
import SwiftUI

struct AgendaModuleView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var calendar: CalendarService
    @StateObject private var selection = AgendaSelectionState()

    init(model: AppModel, calendar: CalendarService) {
        self.model = model
        self.calendar = calendar
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            if model.settingsStore.settings.weatherEnabled {
                weatherColumn
                    .frame(width: 184, height: 160)
                if model.settingsStore.settings.calendarEnabled {
                    Hairline()
                }
            }

            if model.settingsStore.settings.calendarEnabled {
                calendarColumn
                    .frame(maxWidth: .infinity, minHeight: 160, maxHeight: 160)
            }
        }
    }

    private var weatherColumn: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("天气")
                    .font(.system(size: 12, weight: .semibold))
                Spacer()
                IconButton(symbol: "arrow.clockwise", help: "刷新天气") {
                    model.refreshWeather()
                }
            }
            if !model.weatherSnapshots.isEmpty {
                ScrollView(.vertical) {
                    LazyVStack(spacing: 2) {
                        ForEach(model.weatherLocations.locations) { location in
                            if let weather = model.weatherSnapshot(for: location.id) {
                                weatherRow(weather)
                            }
                        }
                    }
                }
                .scrollIndicators(.visible)
                .thinScrollChrome()
            } else {
                weatherPlaceholder
            }
        }
    }

    private func weatherRow(_ weather: WeatherSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 7) {
                Image(systemName: weather.condition.symbolName)
                    .symbolRenderingMode(.multicolor)
                    .font(.system(size: 17))
                    .frame(width: 22)
                VStack(alignment: .leading, spacing: 1) {
                    Text(weather.locationName ?? "当前位置")
                        .font(.system(size: 9.5, weight: .semibold))
                        .lineLimit(1)
                    Text("\(weather.condition.summary) · 体感 \(weather.apparentTemperature, specifier: "%.0f")°")
                        .font(.system(size: 8.5))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 3)
                Text("\(weather.temperature, specifier: "%.0f")°")
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .monospacedDigit()
            }

            HStack(spacing: 7) {
                weatherMetric(symbol: "sunrise.fill", value: displayTime(weather.sunrise))
                weatherMetric(symbol: "sunset.fill", value: displayTime(weather.sunset))
            }

            HStack(spacing: 7) {
                weatherMetric(
                    symbol: "cloud.rain.fill",
                    value: "当前 \(weather.currentPrecipitation.formatted(.number.precision(.fractionLength(1)))) mm"
                )
                weatherMetric(
                    symbol: "calendar",
                    value: "今日 \(weather.precipitationProbability)% / \(weather.precipitationSum.formatted(.number.precision(.fractionLength(1)))) mm"
                )
            }

            if !weather.officialAlerts.isEmpty {
                ForEach(weather.officialAlerts) { alert in
                    Link(destination: alert.detailsURL) {
                        Label(
                            "\(alert.severity.localizedTitle) · \(alert.summary)",
                            systemImage: alert.severity.symbolName
                        )
                        .font(.system(size: 8.5, weight: .semibold))
                        .foregroundStyle(weatherAlertColor(alert.severity))
                        .lineLimit(1)
                    }
                    .help(weatherAlertDetail(alert))
                }
            } else if let error = weather.alertErrorDescription {
                Label("官方预警不可用", systemImage: "exclamationmark.triangle")
                    .font(.system(size: 8.5, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .help(error)
            }
        }
        .padding(.vertical, 3)
    }

    private func weatherMetric(symbol: String, value: String) -> some View {
        Label(value, systemImage: symbol)
            .font(.system(size: 8, weight: .medium))
            .foregroundStyle(.secondary)
            .lineLimit(1)
    }

    private func displayTime(_ value: String) -> String {
        String(value.split(separator: "T").last ?? Substring(value))
    }

    private func weatherAlertColor(_ severity: WeatherAlert.Severity) -> Color {
        switch severity {
        case .minor: .yellow
        case .moderate: .orange
        case .severe, .extreme: .red
        }
    }

    private func weatherAlertDetail(_ alert: WeatherAlert) -> String {
        let updatedAt = alert.updatedAt.formatted(date: .omitted, time: .shortened)
        var details = [
            alert.source,
            alert.region,
            "更新 \(updatedAt)",
        ]
        if let expiresAt = alert.expiresAt {
            details.append("有效至 \(expiresAt.formatted(date: .omitted, time: .shortened))")
        }
        return details.compactMap { $0 }.joined(separator: " · ")
    }

    @ViewBuilder
    private var weatherPlaceholder: some View {
        switch model.weatherLocationState {
        case .locating, .searching:
            ProgressView()
                .controlSize(.small)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case let .failed(message):
            VStack(alignment: .leading, spacing: 7) {
                Label("无法获取天气", systemImage: "location.slash.fill")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Color.zislaWarning)
                Text(message)
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                Button("定位设置") {
                    NSWorkspace.shared.open(URL(
                        string: "x-apple.systempreferences:com.apple.preference.security?Privacy_LocationServices"
                    )!)
                }
                .buttonStyle(.bordered)
                .controlSize(.mini)
            }
        case .idle, .ready:
            Label("等待刷新", systemImage: "cloud.sun")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var calendarColumn: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text("日历与待办")
                    .font(.system(size: 12, weight: .semibold))
                Spacer()
                if calendar.hasAnyReadAccess {
                    Button(action: presentNewItemEditor) {
                        Image(systemName: "plus")
                            .font(.system(size: 9, weight: .bold))
                            .frame(width: 20, height: 20)
                    }
                    .buttonStyle(.plain)
                    .help("新增日程或提醒")
                }
                if !calendar.hasFullAgendaAccess {
                    Button(action: handleAuthorizationAction) {
                        Image(systemName: "lock.open.fill")
                            .font(.system(size: 9, weight: .semibold))
                            .frame(width: 20, height: 20)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Color.zislaWarning)
                    .help("授权日历与提醒事项")
                }
                Text(selection.selectedDay, format: .dateTime.month(.abbreviated).day())
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            .frame(height: 24)

            weekDayPicker
                .frame(height: 28)

            if !calendar.hasAnyReadAccess {
                calendarAuthorizationView
            } else if calendar.isLoading && calendar.events.isEmpty {
                ProgressView()
                    .controlSize(.small)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error = calendar.errorDescription, calendar.events.isEmpty {
                VStack(spacing: 7) {
                    Label("无法读取日程", systemImage: "calendar.badge.exclamationmark")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Color.zislaWarning)
                    Text(error)
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                    Button("重新读取") {
                        Task { await calendar.refresh(referenceDate: selection.selectedDay) }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.mini)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if dayEvents.isEmpty {
                EmptyState(symbol: "calendar.badge.checkmark", title: "当天暂无事项")
            } else {
                ScrollView(.vertical) {
                    LazyVStack(spacing: 0) {
                        ForEach(dayEvents) { event in
                            agendaRow(event)
                        }
                    }
                }
                .scrollIndicators(.visible)
                .thinScrollChrome()
            }
        }
    }

    private var weekDayPicker: some View {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let days = CalendarService.daysOfWeeks(
            containing: today,
            count: CalendarService.agendaWeekCount,
            calendar: calendar
        )
        return HStack(spacing: 2) {
            ForEach(days, id: \.timeIntervalSince1970) { day in
                let isSelected = calendar.isDate(day, inSameDayAs: selection.selectedDay)
                let isToday = calendar.isDate(day, inSameDayAs: today)
                Button {
                    selection.selectedDay = calendar.startOfDay(for: day)
                } label: {
                    VStack(spacing: 1) {
                        Text(weekdayLabel(day, calendar: calendar))
                            .font(.islandMicro())
                            .foregroundStyle(isToday ? Color.blue : isSelected ? Color.primary : Color.secondary)
                        Text("\(calendar.component(.day, from: day))")
                            .font(.system(size: 11, weight: isSelected || isToday ? .bold : .semibold, design: .rounded))
                            .foregroundStyle(isToday ? Color.blue : Color.primary)
                            .monospacedDigit()
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 26)
                    .background(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(dayBackground(isSelected: isSelected, isToday: isToday))
                    )
                    .overlay {
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .strokeBorder(
                                isToday && !isSelected
                                    ? Color.primary.opacity(0.28)
                                    : Color.clear,
                                lineWidth: 1
                            )
                    }
                    .contentShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(dayAccessibilityLabel(day, isToday: isToday, calendar: calendar))
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
    }

    private var dayEvents: [CalendarEventSnapshot] {
        calendar.events(on: selection.selectedDay)
    }

    private func agendaRow(_ event: CalendarEventSnapshot) -> some View {
        HStack(spacing: 8) {
            RoundedRectangle(cornerRadius: 1.5)
                .fill(eventColor(event).opacity(event.isCompleted ? 0.5 : 1))
                .frame(width: 3, height: 25)
            VStack(alignment: .leading, spacing: 1) {
                Text(event.title)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(event.isCompleted ? .secondary : .primary)
                    .strikethrough(event.isCompleted, color: .secondary)
                    .lineLimit(1)
                Text(eventDetail(event))
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 4)
            if event.kind == .reminder && !event.isProjectedOccurrence {
                Button {
                    toggleCompletion(event)
                } label: {
                    Image(systemName: event.isCompleted
                        ? "checkmark.circle.fill"
                        : "checkmark.circle")
                        .font(.system(size: 11, weight: .semibold))
                        .frame(width: 20, height: 20)
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.zislaSuccess)
                .help(event.isCompleted ? "标记未完成" : "标记完成")
            }
            if !event.isProjectedOccurrence {
                Button {
                    confirmDelete(event)
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 10, weight: .semibold))
                        .frame(width: 20, height: 20)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("删除")
            }
        }
        .frame(height: 34)
    }

    private func dayBackground(isSelected: Bool, isToday: Bool) -> Color {
        if isSelected {
            return Color.white.opacity(0.16)
        }
        if isToday {
            return Color.white.opacity(0.06)
        }
        return .clear
    }

    private func weekdayLabel(_ day: Date, calendar: Calendar) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = .current
        formatter.setLocalizedDateFormatFromTemplate("EEEEE")
        return formatter.string(from: day)
    }

    private func dayAccessibilityLabel(_ day: Date, isToday: Bool, calendar: Calendar) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = .current
        formatter.dateStyle = .full
        formatter.timeStyle = .none
        let base = formatter.string(from: day)
        return isToday ? "\(base)，今天" : base
    }

    private var calendarAuthorizationView: some View {
        VStack(spacing: 7) {
            Label("需要日历权限", systemImage: "calendar.badge.exclamationmark")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Color.zislaWarning)
            Text(calendar.authorizationStatus == .notDetermined
                || calendar.reminderAuthorizationStatus == .notDetermined
                ? "允许后即可显示日历事件与计划提醒"
                : "请在系统设置中允许访问日历和提醒事项")
                .font(.system(size: 9))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .lineLimit(2)
            Button(calendar.hasUndeterminedAccess ? "授权日历" : "打开系统设置") {
                handleAuthorizationAction()
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func handleAuthorizationAction() {
        if calendar.hasUndeterminedAccess {
            Task { await calendar.requestAccess() }
        } else {
            openCalendarSettings()
        }
    }

    private func openCalendarSettings() {
        let pane = calendar.hasEventAccess ? "Privacy_Reminders" : "Privacy_Calendars"
        guard let url = URL(
            string: "x-apple.systempreferences:com.apple.preference.security?\(pane)"
        ) else { return }
        NSWorkspace.shared.open(url)
    }

    private func eventColor(_ event: CalendarEventSnapshot) -> Color {
        if event.kind == .reminder { return .purple }
        return event.isAllDay ? .orange : .blue
    }

    private func eventDetail(_ event: CalendarEventSnapshot) -> String {
        let time = event.isAllDay
            ? "全天"
            : event.startDate.formatted(date: .omitted, time: .shortened)
        if event.kind == .reminder {
            if event.isProjectedOccurrence {
                return "重复提醒 · \(time)"
            }
            return event.isCompleted ? "提醒 · 已完成 · \(time)" : "提醒 · \(time)"
        }
        return time
    }

    private func presentNewItemEditor() {
        var availableKinds: [(title: String, kind: CalendarItemKind)] = []
        if calendar.hasEventAccess { availableKinds.append(("日历事件", .event)) }
        if calendar.hasReminderAccess { availableKinds.append(("提醒事项", .reminder)) }
        guard !availableKinds.isEmpty else {
            handleAuthorizationAction()
            return
        }

        let kindPicker = NSPopUpButton(frame: .zero, pullsDown: false)
        kindPicker.addItems(withTitles: availableKinds.map(\.title))
        let titleField = NSTextField(string: "")
        titleField.placeholderString = "标题"
        let datePicker = NSDatePicker()
        datePicker.datePickerStyle = .textFieldAndStepper
        datePicker.datePickerElements = [.yearMonthDay, .hourMinute]
        datePicker.dateValue = defaultNewItemDate
        let allDay = NSButton(checkboxWithTitle: "全天", target: nil, action: nil)

        let grid = NSGridView(views: [
            [NSTextField(labelWithString: "类型"), kindPicker],
            [NSTextField(labelWithString: "标题"), titleField],
            [NSTextField(labelWithString: "时间"), datePicker],
            [NSView(), allDay],
        ])
        grid.rowSpacing = 8
        grid.columnSpacing = 10
        grid.column(at: 0).xPlacement = .trailing
        grid.column(at: 1).width = 230
        grid.frame = CGRect(x: 0, y: 0, width: 300, height: 126)

        let alert = NSAlert()
        alert.messageText = "新增日程"
        alert.informativeText = "保存到系统日历或提醒事项。"
        alert.accessoryView = grid
        alert.addButton(withTitle: "新增")
        alert.addButton(withTitle: "取消")
        NSApp.activate(ignoringOtherApps: true)
        WindowPlacement.prepareModal(alert.window, on: WindowPlacement.screenUnderMouse())
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        do {
            let kind = availableKinds[kindPicker.indexOfSelectedItem].kind
            let isAllDay = allDay.state == .on
            switch kind {
            case .event:
                let duration: TimeInterval = isAllDay ? 86_400 : 3_600
                try calendar.createEvent(
                    title: titleField.stringValue,
                    startDate: datePicker.dateValue,
                    endDate: datePicker.dateValue.addingTimeInterval(duration),
                    isAllDay: isAllDay
                )
            case .reminder:
                try calendar.createReminder(
                    title: titleField.stringValue,
                    dueDate: datePicker.dateValue,
                    isAllDay: isAllDay
                )
            }
        } catch {
            model.transientMessage = error.localizedDescription
        }
    }

    private func toggleCompletion(_ item: CalendarEventSnapshot) {
        do {
            try calendar.setReminderCompleted(item, isCompleted: !item.isCompleted)
        } catch {
            model.transientMessage = error.localizedDescription
        }
    }

    private var defaultNewItemDate: Date {
        let calendar = Calendar.current
        if calendar.isDateInToday(selection.selectedDay) {
            return Date().addingTimeInterval(3_600)
        }
        return calendar.date(
            bySettingHour: 9,
            minute: 0,
            second: 0,
            of: selection.selectedDay
        ) ?? selection.selectedDay
    }

    private func confirmDelete(_ item: CalendarEventSnapshot) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "删除“\(item.title)”？"
        alert.informativeText = item.kind == .reminder
            ? "该提醒事项会从系统提醒中删除。"
            : "该事件会从系统日历中删除。"
        alert.addButton(withTitle: "删除")
        alert.addButton(withTitle: "取消")
        WindowPlacement.prepareModal(alert.window, on: WindowPlacement.screenUnderMouse())
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        do {
            try calendar.delete(item)
        } catch {
            model.transientMessage = error.localizedDescription
        }
    }
}

@MainActor
private final class AgendaSelectionState: ObservableObject {
    @Published var selectedDay = Calendar.current.startOfDay(for: Date())
}
