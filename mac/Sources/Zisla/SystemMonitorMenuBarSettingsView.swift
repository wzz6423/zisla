import SwiftUI
import ZislaCore
import ZislaKit

struct SystemMonitorMenuBarSettingsView: View {
    @ObservedObject var settingsStore: FeatureSettingsStore

    private var rows: [[SystemMonitorMenuBarMetric]] {
        SystemMonitorMenuBarRows.normalized(
            top: settingsStore.settings.systemMonitorMenuBarTopRow,
            bottom: settingsStore.settings.systemMonitorMenuBarBottomRow
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                AppLocalizedText("菜单栏布局")
                Spacer()
                Picker(AppLocalization.text("菜单栏布局"), selection: $settingsStore.settings.systemMonitorMenuBarLayout) {
                    ForEach(SystemMonitorMenuBarLayout.allCases, id: \.self) { layout in
                        AppLocalizedText(layout.menuTitle).tag(layout)
                    }
                }
                .labelsHidden()
                .fixedSize()
            }
            if settingsStore.settings.systemMonitorMenuBarLayout == .stacked {
                AppLocalizedText("上下两行显示自选指标，最多三个；上行可放两个")
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
                HStack {
                    AppLocalizedText("上行")
                    Spacer()
                    Picker(AppLocalization.text("上行"), selection: Binding(
                        get: { rows[0][0] },
                        set: { settingsStore.settings.systemMonitorMenuBarTopRow = [$0] + Array(rows[0].dropFirst()) }
                    )) {
                        ForEach(SystemMonitorMenuBarMetric.allCases.filter { !rows[1].contains($0) && !rows[0].dropFirst().contains($0) }, id: \.self) { metric in
                            AppLocalizedText(metric.menuTitle).tag(metric)
                        }
                    }
                    Picker("\(AppLocalization.text("上行")) 2", selection: Binding<SystemMonitorMenuBarMetric?>(
                        get: { rows[0].dropFirst().first },
                        set: { settingsStore.settings.systemMonitorMenuBarTopRow = [rows[0][0]] + ($0.map { [$0] } ?? []) }
                    )) {
                        AppLocalizedText("无").tag(SystemMonitorMenuBarMetric?.none)
                        ForEach(SystemMonitorMenuBarMetric.allCases.filter { !rows[1].contains($0) && $0 != rows[0][0] }, id: \.self) { metric in
                            AppLocalizedText(metric.menuTitle).tag(Optional(metric))
                        }
                    }
                }
                .labelsHidden()
                HStack {
                    AppLocalizedText("下行")
                    Spacer()
                    Picker(AppLocalization.text("下行"), selection: Binding(
                        get: { rows[1][0] },
                        set: { settingsStore.settings.systemMonitorMenuBarBottomRow = [$0] }
                    )) {
                        ForEach(SystemMonitorMenuBarMetric.allCases.filter { !rows[0].contains($0) }, id: \.self) { metric in
                            AppLocalizedText(metric.menuTitle).tag(metric)
                        }
                    }
                }
                .labelsHidden()
            }
            Divider()
            Toggle(isOn: $settingsStore.settings.systemMonitorMenuBarCombinedIconEnabled) {
                AppLocalizedText("合并状态图标")
            }
            .toggleStyle(.switch)
            AppLocalizedText("电量环、Wi-Fi 与实时指标合并显示；点击打开系统监控")
                .font(.system(size: 9))
                .foregroundStyle(.secondary)
            if settingsStore.settings.systemMonitorMenuBarCombinedIconEnabled {
                HStack {
                    AppLocalizedText("底部指标")
                    Spacer()
                    Picker(AppLocalization.text("底部指标"), selection: $settingsStore.settings.systemMonitorMenuBarCombinedIconMetric) {
                        ForEach(SystemMonitorCombinedIconMetric.allCases, id: \.self) { metric in
                            AppLocalizedText(metric.menuTitle).tag(metric)
                        }
                    }
                    .labelsHidden()
                }
            }
        }
        .font(.system(size: 10))
        .controlSize(.small)
        .padding(.leading, 28)
        .padding(.vertical, 6)
    }
}
