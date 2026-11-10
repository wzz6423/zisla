import AppKit
import SwiftUI
import ZislaCore
import ZislaKit

struct NotificationScenarioSettingsView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var settingsStore: FeatureSettingsStore
    @Environment(\.locale) private var locale
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            AppLocalizedText("场景通知策略").font(.system(size: 13, weight: .semibold))
            VStack(spacing: 0) {
                row("启用场景通知策略", symbol: "bell.badge", detail: "仅管理 Zisla 提示，不更改系统专注模式") {
                    Toggle("", isOn: binding(\.enabled)).labelsHidden().toggleStyle(.switch)
                        .accessibilityLabel(AppLocalization.string("启用场景通知策略", locale: locale))
                }
                if settings.enabled {
                    Divider()
                    row("按日历自动开启会议场景", symbol: "calendar",
                        detail: "以含会议链接的日程时间为准，不代表实际参会") {
                        Toggle("", isOn: binding(\.automaticallyDetectsMeetings)).labelsHidden().toggleStyle(.switch)
                            .accessibilityLabel(AppLocalization.string("按日历自动开启会议场景", locale: locale))
                    }
                    Divider()
                    row("手动开启会议场景", symbol: "video.fill",
                        detail: model.isCalendarMeetingScenarioActive ? "日历会议场景已生效" : "仅本次运行有效，退出后关闭") {
                        Toggle("", isOn: $model.isManualMeetingScenarioActive).labelsHidden().toggleStyle(.switch)
                            .accessibilityLabel(AppLocalization.string("手动开启会议场景", locale: locale))
                    }
                    policyRows(displayIdentifier: nil, scopeName: AppLocalization.string("场景通知策略", locale: locale))
                    ForEach(displays) { display in
                        Divider()
                        row(display.name, symbol: "display", detail: "为此显示器单独设置") {
                            Toggle("", isOn: overrideBinding(display.identifier)).labelsHidden().toggleStyle(.switch)
                                .accessibilityLabel(display.name + " · " + AppLocalization.string("为此显示器单独设置", locale: locale))
                        }
                        if settings.displayOverrides[display.identifier] != nil {
                            policyRows(displayIdentifier: display.identifier, scopeName: display.name)
                        }
                    }
                }
            }
        }
        .padding(16)
        .background(Color.primary.opacity(colorScheme == .dark ? 0.045 : 0.025),
            in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .settingsSearchAnchor(SettingsSearchAnchor.group(AppLocalization.string("场景通知策略", locale: locale)))
    }

    private var settings: NotificationScenarioSettings { settingsStore.settings.notificationScenarios }

    private func binding<Value>(_ keyPath: WritableKeyPath<NotificationScenarioSettings, Value>) -> Binding<Value> {
        Binding(get: { settings[keyPath: keyPath] }, set: { settingsStore.settings.notificationScenarios[keyPath: keyPath] = $0 })
    }

    @ViewBuilder
    private func policyRows(displayIdentifier: String?, scopeName: String) -> some View {
        ForEach(NotificationScenario.allCases, id: \.self) { scenario in
            Divider()
            row(scenario.title, symbol: scenario.symbolName) {
                Picker("", selection: policyBinding(scenario, displayIdentifier: displayIdentifier, keyPath: \.ordinary)) {
                    ForEach(ScenarioNotificationBehavior.allCases, id: \.self) { behavior in
                        AppLocalizedText(behavior.title).tag(behavior)
                    }
                }
                .labelsHidden().pickerStyle(.menu).keepsIntrinsicWidth()
                .accessibilityLabel(scopeName + " · " + AppLocalization.string(scenario.title, locale: locale))
            }
            row("保留重要提示", symbol: "exclamationmark.triangle", detail: "等待操作、失败、安全与低电量") {
                Toggle("", isOn: policyBinding(scenario, displayIdentifier: displayIdentifier, keyPath: \.keepsImportant))
                    .labelsHidden().toggleStyle(.switch)
                    .accessibilityLabel(scopeName + " · " + AppLocalization.string(scenario.title, locale: locale)
                        + " · " + AppLocalization.string("保留重要提示", locale: locale))
                    .disabled(currentRules(displayIdentifier)[scenario].ordinary == .show)
            }
        }
    }

    private func currentRules(_ displayIdentifier: String?) -> NotificationScenarioRules {
        displayIdentifier.flatMap { settings.displayOverrides[$0] } ?? settings.rules
    }

    private func policyBinding<Value>(_ scenario: NotificationScenario, displayIdentifier: String?,
                                      keyPath: WritableKeyPath<NotificationScenarioPolicy, Value>) -> Binding<Value> {
        Binding(get: { currentRules(displayIdentifier)[scenario][keyPath: keyPath] }, set: { value in
            var rules = currentRules(displayIdentifier)
            rules[scenario][keyPath: keyPath] = value
            if let displayIdentifier { settingsStore.settings.notificationScenarios.displayOverrides[displayIdentifier] = rules }
            else { settingsStore.settings.notificationScenarios.rules = rules }
        })
    }

    private func overrideBinding(_ identifier: String) -> Binding<Bool> {
        Binding(get: { settings.displayOverrides[identifier] != nil }, set: { enabled in
            settingsStore.settings.notificationScenarios.displayOverrides[identifier] = enabled ? settings.rules : nil
        })
    }

    private func row<Trailing: View>(_ title: String, symbol: String, detail: String = "",
                                    @ViewBuilder trailing: () -> Trailing) -> some View {
        HStack(spacing: 10) {
            Image(systemName: symbol).font(.system(size: 15)).foregroundStyle(.secondary).frame(width: 32, height: 32)
            VStack(alignment: .leading, spacing: 2) {
                AppLocalizedText(title).font(.system(size: 13, weight: .medium)).fitsLines(2)
                if !detail.isEmpty { AppLocalizedText(detail).font(.system(size: 11)).foregroundStyle(.secondary) }
            }
            .layoutPriority(1)
            Spacer(minLength: 8)
            trailing()
        }
        .padding(.horizontal, 4).frame(maxWidth: .infinity, minHeight: 56)
        .settingsSearchAnchor(SettingsSearchAnchor.row(AppLocalization.string(title, locale: locale)))
    }

    private struct Display: Identifiable {
        let identifier: String
        let name: String
        var id: String { identifier }
    }

    private var displays: [Display] {
        NSScreen.screens.enumerated().compactMap { index, screen in
            guard let snapshot = ScreenSnapshot(screen: screen), let identifier = snapshot.notificationPolicyIdentifier else { return nil }
            let name = screen.localizedName.isEmpty ? AppLocalization.text("显示器 %ld", index + 1) : screen.localizedName
            return Display(identifier: identifier, name: name)
        }
    }
}
