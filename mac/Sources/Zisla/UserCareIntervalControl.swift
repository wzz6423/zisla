import SwiftUI
import ZislaCore
import ZislaKit

struct UserCareIntervalDraft: Equatable {
    var hours: String
    var minutes: String
    var seconds: String

    init(interval: TimeInterval) {
        let total = Int(UserCareInterval.normalized(interval))
        hours = String(total / 3_600)
        minutes = String(total / 60 % 60)
        seconds = String(total % 60)
    }

    var interval: TimeInterval? {
        guard let hours = Self.component(hours),
              let minutes = Self.component(minutes),
              let seconds = Self.component(seconds) else { return nil }
        return UserCareInterval.seconds(hours: hours, minutes: minutes, seconds: seconds)
    }

    private static func component(_ text: String) -> Int? {
        var digits = ""
        for character in text {
            guard let digit = character.wholeNumberValue, (0...9).contains(digit) else { return nil }
            digits.append(String(digit))
        }
        return Int(digits)
    }
}

struct UserCareIntervalControl: View {
    @Binding private var interval: TimeInterval
    @State private var draft: UserCareIntervalDraft
    @Environment(\.locale) private var locale

    init(interval: Binding<TimeInterval>) {
        _interval = interval
        _draft = State(initialValue: UserCareIntervalDraft(interval: interval.wrappedValue))
    }

    var body: some View {
        HStack(spacing: 8) {
            durationInput("小时", text: $draft.hours, identifier: "user-care-hours")
            durationInput("分钟", text: $draft.minutes, identifier: "user-care-minutes")
            durationInput("秒", text: $draft.seconds, identifier: "user-care-seconds")
            Button(action: save) {
                AppLocalizedText("保存")
            }
            .controlSize(.small)
            .disabled(draft.interval == nil || draft.interval == interval)
            .accessibilityIdentifier("user-care-save")
        }
        .font(.system(size: 11))
        .onChange(of: interval) { _, value in
            draft = UserCareIntervalDraft(interval: value)
        }
    }

    private func durationInput(_ title: String, text: Binding<String>, identifier: String) -> some View {
        HStack(spacing: 4) {
            TextField("", text: text)
                .textFieldStyle(.roundedBorder)
                .multilineTextAlignment(.trailing)
                .frame(width: 44)
                .accessibilityLabel(AppLocalization.string(title, locale: locale))
                .accessibilityIdentifier(identifier)
                .onSubmit(save)
            AppLocalizedText(title)
                .foregroundStyle(.secondary)
        }
    }

    private func save() {
        guard let value = draft.interval, value != interval else { return }
        interval = value
    }
}
