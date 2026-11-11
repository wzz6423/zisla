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
                Text(AppLocalization.text("天气"))
                    .font(.system(size: 12, weight: .semibold))
                Spacer()
                IconButton(symbol: "arrow.clockwise", help: AppLocalization.text("刷新天气")) {
                    model.refreshWeather()
                }
            }
            TimelineView(.periodic(from: .now, by: 60)) { context in
                Self.weatherContent(
                    locations: model.weatherLocations,
                    snapshotsByLocationID: model.weatherSnapshotsByLocationID,
                    state: model.weatherLocationState,
                    at: context.date
                )
            }
        }
    }

    @ViewBuilder
    static func weatherContent(
        locations: WeatherLocationStore,
        snapshotsByLocationID: [String: WeatherSnapshot],
        state: WeatherLocationUIState,
        at date: Date
    ) -> some View {
        let snapshots = locations.orderedSnapshots(snapshotsByLocationID, at: date)
        if snapshots.isEmpty {
            weatherPlaceholder(state: state, hasExpiredWeather: !snapshotsByLocationID.isEmpty)
        } else {
            ScrollView(.vertical) {
                LazyVStack(spacing: 2) {
                    ForEach(Array(snapshots.enumerated()), id: \.offset) { _, weather in
                        weatherRow(weather, at: date)
                    }
                }
            }
            .scrollIndicators(.visible)
            .thinScrollChrome(scrollerStyle: .overlay)
        }
    }

    static func weatherRow(_ weather: WeatherSnapshot, at date: Date = Date()) -> some View {
        let activeAlerts = weather.officialAlerts.filter { $0.expiresAt.map { $0 > date } ?? true }
        return VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 7) {
                Image(systemName: weather.condition.symbolName)
                    .symbolRenderingMode(.multicolor)
                    .font(.system(size: 17))
                    .frame(width: 22)
                VStack(alignment: .leading, spacing: 1) {
                    Text(weather.locationName ?? AppLocalization.text("当前位置"))
                        .font(.system(size: 9.5, weight: .semibold))
                        .fitsSingleLine()
                    Text(weather.apparentTemperature.map {
                        AppLocalization.text("%@ · 体感 %.0f°", weather.condition.summary, $0)
                    } ?? weather.condition.summary)
                        .font(.system(size: 8.5))
                        .foregroundStyle(.secondary)
                        .fitsSingleLine()
                }
                Spacer(minLength: 3)
                VStack(alignment: .trailing, spacing: 1) {
                    Text("\(weather.temperature, specifier: "%.0f")°")
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .monospacedDigit()
                    if let range = temperatureRange(for: weather) {
                        Text(range)
                            .font(.system(size: 8.5, weight: .medium, design: .rounded))
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                            .fitsSingleLine()
                    }
                }
            }

            if !weather.sunrise.isEmpty || !weather.sunset.isEmpty {
                HStack(spacing: 7) {
                    if !weather.sunrise.isEmpty {
                        weatherMetric(symbol: "sunrise.fill", value: displayTime(weather.sunrise))
                    }
                    if !weather.sunset.isEmpty {
                        weatherMetric(symbol: "sunset.fill", value: displayTime(weather.sunset))
                    }
                }
            }

            HStack(spacing: 7) {
                if let precipitation = weather.currentPrecipitation {
                    weatherMetric(
                        symbol: "cloud.rain.fill",
                        value: AppLocalization.text("当前 %@ mm", precipitation.formatted(.number.precision(.fractionLength(1))))
                    )
                }
                if let probability = weather.precipitationProbability, let sum = weather.precipitationSum {
                    weatherMetric(
                        symbol: "calendar",
                        value: AppLocalization.text("今日 %ld%% / %@ mm", probability, sum.formatted(.number.precision(.fractionLength(1))))
                    )
                }
            }

            if let source = weather.source, let sourceURL = weather.sourceURL {
                HStack(spacing: 4) {
                    Link(source, destination: sourceURL)
                    if let licenseURL = weather.licenseURL {
                        Link("CC BY 4.0", destination: licenseURL)
                    }
                }
                .font(.system(size: 8))
                .foregroundStyle(.secondary)
            }

            Text(AppLocalization.text("更新于 %@", weather.fetchedAt.formatted(date: .numeric, time: .shortened)))
                .font(.system(size: 8))
                .foregroundStyle(.secondary)
                .fitsSingleLine()

            if !activeAlerts.isEmpty {
                ForEach(activeAlerts) { alert in
                    Link(destination: alert.detailsURL) {
                        Label(
                            "\(alert.severity.localizedTitle) · \(alert.summary)",
                            systemImage: alert.severity.symbolName
                        )
                        .font(.system(size: 8.5, weight: .semibold))
                        .foregroundStyle(weatherAlertColor(alert.severity))
                        .fitsSingleLine()
                    }
                    .help(weatherAlertDetail(alert))
                }
            } else if let error = weather.alertErrorDescription {
                Label(AppLocalization.text("官方预警不可用"), systemImage: "exclamationmark.triangle")
                    .font(.system(size: 8.5, weight: .medium))
                    .foregroundStyle(.secondary)
                    .fitsSingleLine()
                    .help(error)
            }
        }
        .padding(.vertical, 3)
    }

    private static func weatherMetric(symbol: String, value: String) -> some View {
        Label(value, systemImage: symbol)
            .font(.system(size: 8, weight: .medium))
            .foregroundStyle(.secondary)
            .fitsSingleLine()
    }

    private static func temperatureRange(for weather: WeatherSnapshot) -> String? {
        guard let minimum = weather.temperatureMin, let maximum = weather.temperatureMax else { return nil }
        return String(format: "%.0f°–%.0f°", minimum, maximum)
    }

    private static func displayTime(_ value: String) -> String {
        String(value.split(separator: "T").last ?? Substring(value))
    }

    private static func weatherAlertColor(_ severity: WeatherAlert.Severity) -> Color {
        switch severity {
        case .minor: .yellow
        case .moderate: .orange
        case .severe, .extreme: .red
        }
    }

    private static func weatherAlertDetail(_ alert: WeatherAlert) -> String {
        let updatedAt = alert.updatedAt.formatted(date: .omitted, time: .shortened)
        var details = [
            alert.source,
            alert.region,
            AppLocalization.text("更新于 %@", updatedAt),
        ]
        if let expiresAt = alert.expiresAt {
            details.append(AppLocalization.text("有效至 %@", expiresAt.formatted(date: .omitted, time: .shortened)))
        }
        return details.compactMap { $0 }.joined(separator: " · ")
    }

    @ViewBuilder
    private static func weatherPlaceholder(state: WeatherLocationUIState, hasExpiredWeather: Bool) -> some View {
        switch state {
        case .locating, .searching:
            ProgressView()
                .controlSize(.small)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case let .failed(message):
            VStack(alignment: .leading, spacing: 7) {
                Label(AppLocalization.text("无法获取天气"), systemImage: "location.slash.fill")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Color.zislaWarning)
                Text(message)
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                AppLocalizedText("请在设置的“权限”页面管理授权。")
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
            }
        case .idle, .ready:
            Label(
                AppLocalization.text(hasExpiredWeather ? "无法获取天气" : "等待刷新"),
                systemImage: hasExpiredWeather ? "cloud.slash" : "cloud.sun"
            )
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var calendarColumn: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(AppLocalization.text("日历与待办"))
                    .font(.system(size: 12, weight: .semibold))
                Spacer()
                if calendar.hasAnyReadAccess {
                    Button(action: presentNewItemEditor) {
                        Image(systemName: "plus")
                            .font(.system(size: 9, weight: .bold))
                            .frame(width: 20, height: 20)
                    }
                    .buttonStyle(.plain)
                    .help(AppLocalization.text("新增日程或提醒"))
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
                    Label(AppLocalization.text("无法读取日程"), systemImage: "calendar.badge.exclamationmark")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Color.zislaWarning)
                    Text(error)
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                    Button(AppLocalization.text("重新读取")) {
                        Task { await calendar.refresh(referenceDate: selection.selectedDay) }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.mini)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if dayEvents.isEmpty {
                EmptyState(symbol: "calendar.badge.checkmark", title: AppLocalization.text("当天暂无事项"))
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
                    .fitsSingleLine()
                Text(eventDetail(event))
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 4)
            if Self.isJoinableMeeting(event, at: Date()) {
                Button { model.joinMeeting(event) } label: {
                    Image(systemName: "video.fill")
                        .font(.system(size: 11, weight: .semibold))
                        .frame(width: 20, height: 20)
                }
                .buttonStyle(.plain)
                .help(AppLocalization.text("加入会议"))
                .accessibilityLabel(AppLocalization.text("加入会议"))
                if model.settingsStore.settings.contextNotesEnabled, let identity = event.eventIdentity {
                    meetingNoteMenu(event, identity: identity)
                }
            }
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
                .help(event.isCompleted ? AppLocalization.text("标记未完成") : AppLocalization.text("标记完成"))
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
                .help(AppLocalization.text("删除"))
            }
        }
        .frame(height: 34)
    }

    static func isJoinableMeeting(_ event: CalendarEventSnapshot, at date: Date) -> Bool {
        !MeetingWorkflow.meetings(in: [event], at: date).isEmpty
    }

    private func meetingNoteMenu(_ event: CalendarEventSnapshot, identity: CalendarEventIdentity) -> some View {
        let notes = model.shelf.items.filter { $0.noteLocation != nil }
        let associated = notes.filter { $0.noteMeetingIDs.contains(identity) }
        return Menu {
            ForEach(associated) { note in
                Button(note.displayName) { model.openMeetingNote(note) }
            }
            if !associated.isEmpty { Divider() }
            Button(AppLocalization.text("新建会议便签")) { model.createMeetingNote(event) }
            let available = notes.filter { !$0.noteMeetingIDs.contains(identity) }
            if !available.isEmpty {
                Menu(AppLocalization.text("关联现有便签")) {
                    ForEach(available) { note in
                        Button(note.displayName) { model.setMeeting(event, associated: true, with: note) }
                    }
                }
            }
            if !associated.isEmpty {
                Menu(AppLocalization.text("取消便签关联")) {
                    ForEach(associated) { note in
                        Button(note.displayName) { model.setMeeting(event, associated: false, with: note) }
                    }
                }
            }
        } label: {
            Image(systemName: associated.isEmpty ? "note.text" : "note.text.badge.plus")
                .font(.system(size: 10, weight: .semibold))
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .frame(width: 20, height: 20)
        .help(AppLocalization.text("会议便签"))
        .accessibilityLabel(AppLocalization.text("会议便签"))
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
        return isToday ? AppLocalization.text("%@，今天", base) : base
    }

    private var calendarAuthorizationView: some View {
        VStack(spacing: 7) {
            Label(AppLocalization.text("需要日历权限"), systemImage: "calendar.badge.exclamationmark")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Color.zislaWarning)
            AppLocalizedText("请在设置的“权限”页面管理授权。")
                .font(.system(size: 9))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func eventColor(_ event: CalendarEventSnapshot) -> Color {
        if event.kind == .reminder { return .purple }
        return event.isAllDay ? .orange : .blue
    }

    private func eventDetail(_ event: CalendarEventSnapshot) -> String {
        let time = event.isAllDay
            ? AppLocalization.text("全天")
            : event.startDate.formatted(date: .omitted, time: .shortened)
        if event.kind == .reminder {
            if event.isProjectedOccurrence {
                return AppLocalization.text("重复提醒 · %@", time)
            }
            return event.isCompleted
                ? AppLocalization.text("提醒 · 已完成 · %@", time)
                : AppLocalization.text("提醒 · %@", time)
        }
        return time
    }

    private func presentNewItemEditor() {
        let start = defaultNewItemDate
        Task {
            await CalendarItemEditor.present(
                calendar: calendar,
                draft: ClipboardCalendarDraft(title: "", startDate: start, endDate: start.addingTimeInterval(3_600))
            ) { model.transientMessage = $0 }
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
        alert.messageText = AppLocalization.text("删除“%@”？", item.title)
        alert.informativeText = item.kind == .reminder
            ? AppLocalization.text("该提醒事项会从系统提醒中删除。")
            : AppLocalization.text("该事件会从系统日历中删除。")
        alert.addButton(withTitle: AppLocalization.text("删除"))
        alert.addButton(withTitle: AppLocalization.text("取消"))
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
