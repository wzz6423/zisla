import ZislaCore
import ZislaKit
import SwiftUI

/// Alarm management panel: list + add/edit form.
///
/// The system Clock app's alarm library requires the `com.apple.private.mobiletimerd` entitlement,
/// which third-party apps cannot access. Zisla therefore manages its own alarms and fires them via
/// local notifications; the "Open Clock" button lets users jump to the system app when needed.
struct AlarmEditorView: View {
    @ObservedObject var service: AlarmService
    @State private var editingID: UUID?
    @State private var hour = 8
    @State private var minute = 0
    @State private var label = ""
    @State private var weekdays: Set<Int> = []

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header

            if service.alarms.isEmpty {
                Text(AppLocalization.text("还没有闹钟，在下方添加"))
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 14)
            } else {
                ScrollView {
                    VStack(spacing: 6) {
                        ForEach(service.alarms) { alarm in
                            row(alarm)
                        }
                    }
                }
                .thinScrollChrome()
                .frame(maxHeight: 148)
            }

            Divider().opacity(0.5)

            editor

            if let message = service.errorMessage {
                Text(message)
                    .font(.islandMicro())
                    .foregroundStyle(.orange)
                    .lineLimit(2)
            }
        }
        .padding(12)
        .frame(width: 320)
        .environment(\.colorScheme, .dark)
    }

    private var header: some View {
        HStack(spacing: 8) {
            Label(AppLocalization.text("闹钟"), systemImage: "alarm")
                .font(.system(size: 13, weight: .semibold))
            Spacer(minLength: 8)
            Button {
                service.openSystemClock()
            } label: {
                Text(AppLocalization.text("打开时钟"))
                    .font(.islandMicro(weight: .semibold))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help(AppLocalization.text("打开系统「时钟」App"))
        }
    }

    private func row(_ alarm: AlarmItem) -> some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 1) {
                Text(alarm.timeText)
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(alarm.isEnabled ? .primary : .tertiary)
                HStack(spacing: 4) {
                    Text(alarm.repeatText)
                    if !alarm.label.isEmpty {
                        Text("·")
                        Text(alarm.label).lineLimit(1)
                    }
                }
                .font(.islandMicro())
                .foregroundStyle(.secondary)
            }

            Spacer(minLength: 4)

            Toggle("", isOn: Binding(
                get: { alarm.isEnabled },
                set: { _ in service.toggle(id: alarm.id) }
            ))
            .labelsHidden()
            .toggleStyle(.switch)
            .controlSize(.mini)
            .help(alarm.isEnabled ? AppLocalization.text("停用") : AppLocalization.text("启用"))

            Button {
                beginEditing(alarm)
            } label: {
                Image(systemName: "pencil")
                    .font(.system(size: 10, weight: .semibold))
                    .frame(width: 20, height: 20)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help(AppLocalization.text("编辑"))

            Button {
                if editingID == alarm.id { resetForm() }
                service.remove(id: alarm.id)
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 10, weight: .semibold))
                    .frame(width: 20, height: 20)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help(AppLocalization.text("删除"))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(editingID == alarm.id ? Color.accentColor.opacity(0.16) : Color.fillCard)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private var editor: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                timeField("时", value: $hour, range: 0...23)
                Text(":").foregroundStyle(.secondary)
                timeField("分", value: $minute, range: 0...59)

                TextField(AppLocalization.text("备注"), text: $label)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 11))
            }

            HStack(spacing: 4) {
                ForEach(1...7, id: \.self) { weekday in
                    weekdayChip(weekday)
                }
            }

            HStack(spacing: 8) {
                Button(editingID == nil ? AppLocalization.text("添加") : AppLocalization.text("保存")) {
                    commit()
                }
                .keyboardShortcut(.defaultAction)
                .font(.system(size: 11, weight: .semibold))

                if editingID != nil {
                    Button(AppLocalization.text("取消")) { resetForm() }
                        .font(.system(size: 11))
                }

                Spacer(minLength: 4)

                Text(weekdays.isEmpty ? AppLocalization.text("仅响一次") : AppLocalization.text("每周重复"))
                    .font(.islandMicro())
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func timeField(_ title: String, value: Binding<Int>, range: ClosedRange<Int>) -> some View {
        TextField(title, value: value, format: .number)
            .textFieldStyle(.roundedBorder)
            .multilineTextAlignment(.trailing)
            .monospacedDigit()
            .frame(width: 40)
            .onChange(of: value.wrappedValue) { _, newValue in
                let clamped = min(max(newValue, range.lowerBound), range.upperBound)
                if clamped != newValue { value.wrappedValue = clamped }
            }
    }

    private func weekdayChip(_ weekday: Int) -> some View {
        let isOn = weekdays.contains(weekday)
        return Button {
            if isOn { weekdays.remove(weekday) } else { weekdays.insert(weekday) }
        } label: {
            Text(AlarmItem.weekdaySymbols[weekday - 1].suffix(1))
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(isOn ? Color.primary : Color.secondary)
                .frame(width: 24, height: 22)
                .background(isOn ? Color.accentColor.opacity(0.24) : Color.fillControl)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                .contentShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
        .buttonStyle(.plain)
        .help(AlarmItem.weekdaySymbols[weekday - 1])
    }

    private func beginEditing(_ alarm: AlarmItem) {
        editingID = alarm.id
        hour = alarm.hour
        minute = alarm.minute
        label = alarm.label
        weekdays = alarm.weekdays
    }

    private func commit() {
        if let editingID, let existing = service.alarms.first(where: { $0.id == editingID }) {
            // Use init rather than field-by-field assignment so hour/minute/weekdays go through its clamping logic.
            service.update(AlarmItem(
                id: existing.id,
                hour: hour,
                minute: minute,
                label: label,
                weekdays: weekdays,
                isEnabled: existing.isEnabled
            ))
        } else {
            service.add(hour: hour, minute: minute, label: label, weekdays: weekdays)
        }
        resetForm()
    }

    private func resetForm() {
        editingID = nil
        label = ""
        weekdays = []
    }
}
