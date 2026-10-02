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

    private func setRows(_ selection: [[SystemMonitorMenuBarMetric]]) {
        var settings = settingsStore.settings
        settings.systemMonitorMenuBarTopRow = selection[0]
        settings.systemMonitorMenuBarBottomRow = selection[1]
        settingsStore.settings = settings
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Toggle(isOn: $settingsStore.settings.systemMonitorMenuBarLayout.stackedEnabled) {
                AppLocalizedText("合并")
            }
            .toggleStyle(.switch)
            if settingsStore.settings.systemMonitorMenuBarLayout.stackedEnabled {
                VStack(alignment: .leading, spacing: 12) {
                    let selection = rows
                    HStack {
                        AppLocalizedText("显示数量")
                        Spacer()
                        Picker(AppLocalization.text("显示数量"), selection: Binding(
                            get: { selection.joined().count },
                            set: { count in
                                setRows(SystemMonitorMenuBarRows.adjusted(top: selection[0], bottom: selection[1], count: count))
                            }
                        )) {
                            ForEach(SystemMonitorMenuBarRows.availableCounts(top: selection[0], bottom: selection[1]), id: \.self) { count in
                                AppLocalizedFormatText("%ld项", count).tag(count)
                            }
                        }
                        .labelsHidden()
                        .fixedSize()
                    }
                    AppLocalizedText("普通指标可选2或4项；网络或风扇可选2或3项；两者同时显示时仅可选2项")
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                    ForEach(selection.indices, id: \.self) { rowIndex in
                        HStack {
                            AppLocalizedText(rowIndex == 0 ? "上行" : "下行")
                            Spacer()
                            ForEach(selection[rowIndex].indices, id: \.self) { metricIndex in
                                Picker("\(AppLocalization.text(rowIndex == 0 ? "上行" : "下行")) \(metricIndex + 1)", selection: Binding(
                                    get: { selection[rowIndex][metricIndex] },
                                    set: { metric in
                                        setRows(SystemMonitorMenuBarRows.selecting(
                                            metric,
                                            atRow: rowIndex,
                                            slot: metricIndex,
                                            in: selection
                                        ))
                                    }
                                )) {
                                    ForEach(SystemMonitorMenuBarMetric.allCases, id: \.self) { metric in
                                        AppLocalizedText(metric.menuTitle).tag(metric)
                                    }
                                }
                                .accessibilityIdentifier("system-monitor-row-\(rowIndex)-metric-\(metricIndex)")
                            }
                        }
                        .labelsHidden()
                    }
                }
                .padding(.leading, 20)
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
                VStack(alignment: .leading, spacing: 12) {
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
                    Toggle(isOn: $settingsStore.settings.systemMonitorMenuBarCombinedIconAppearance.showsBatteryPercentage) {
                        AppLocalizedText("显示电池百分比")
                    }
                    .toggleStyle(.switch)
                    Toggle(isOn: $settingsStore.settings.systemMonitorMenuBarCombinedIconAppearance.showsChargingIndicator) {
                        AppLocalizedText("显示充电标记")
                    }
                    .toggleStyle(.switch)
                    Toggle(isOn: $settingsStore.settings.systemMonitorMenuBarCombinedIconAppearance.showsPercentageWhenConnected) {
                        AppLocalizedText("接通电源时显示百分比")
                    }
                    .toggleStyle(.switch)
                    Toggle(isOn: $settingsStore.settings.systemMonitorMenuBarCombinedIconAppearance.usesStatusColors) {
                        AppLocalizedText("电量状态颜色")
                    }
                    .toggleStyle(.switch)
                    HStack {
                        AppLocalizedText("底部指示样式")
                        Spacer()
                        Picker(AppLocalization.text("底部指示样式"), selection: $settingsStore.settings.systemMonitorMenuBarCombinedIconAppearance.indicatorStyle) {
                            ForEach(SystemMonitorMenuBarIndicatorStyle.allCases) { style in
                                AppLocalizedText(style.menuTitle).tag(style)
                            }
                        }
                        .labelsHidden()
                    }
                    HStack {
                        AppLocalizedText("电量环粗细")
                        Spacer()
                        Picker(AppLocalization.text("电量环粗细"), selection: $settingsStore.settings.systemMonitorMenuBarCombinedIconAppearance.ringStrokeStyle) {
                            ForEach(SystemMonitorMenuBarRingStrokeStyle.allCases) { style in
                                AppLocalizedText(style.menuTitle).tag(style)
                            }
                        }
                        .labelsHidden()
                    }
                    HStack {
                        AppLocalizedText("图标大小")
                        Spacer()
                        Slider(value: $settingsStore.settings.systemMonitorMenuBarCombinedIconAppearance.iconSize,
                               in: SystemMonitorCombinedIconAppearance.iconSizeRange, step: 1)
                            .frame(width: 150)
                            .accessibilityLabel(AppLocalization.text("图标大小"))
                    }
                    HStack {
                        AppLocalizedText("Wi-Fi 大小")
                        Spacer()
                        Slider(value: $settingsStore.settings.systemMonitorMenuBarCombinedIconAppearance.wifiScale,
                               in: SystemMonitorCombinedIconAppearance.wifiScaleRange, step: 0.05)
                            .frame(width: 150)
                            .accessibilityLabel(AppLocalization.text("Wi-Fi 大小"))
                    }
                    HStack {
                        AppLocalizedText("电量文字大小")
                        Spacer()
                        Slider(value: $settingsStore.settings.systemMonitorMenuBarCombinedIconAppearance.batteryTextScale,
                               in: SystemMonitorCombinedIconAppearance.batteryTextScaleRange, step: 0.02)
                            .frame(width: 150)
                            .accessibilityLabel(AppLocalization.text("电量文字大小"))
                    }
                    Divider()
                    Toggle(isOn: $settingsStore.settings.systemMonitorMenuBarHeadphoneOptions.replacesNetworkIcon) {
                        AppLocalizedText("连接时短暂显示耳机图标")
                    }
                    .toggleStyle(.switch)
                    if settingsStore.settings.systemMonitorMenuBarHeadphoneOptions.replacesNetworkIcon {
                        VStack(alignment: .leading, spacing: 12) {
                            Toggle(isOn: $settingsStore.settings.systemMonitorMenuBarHeadphoneOptions.prioritizesNetworkErrors) {
                                AppLocalizedText("优先显示网络错误")
                            }
                            .toggleStyle(.switch)
                            HStack {
                                AppLocalizedText("耳机图标大小")
                                Spacer()
                                Slider(value: $settingsStore.settings.systemMonitorMenuBarHeadphoneOptions.symbolScale,
                                       in: SystemMonitorHeadphoneOptions.symbolScaleRange, step: 0.05)
                                    .frame(width: 150)
                                    .accessibilityLabel(AppLocalization.text("耳机图标大小"))
                            }
                        }
                        .padding(.leading, 20)
                    }
                    if settingsStore.settings.systemMonitorMenuBarCombinedIconMetric == .volume {
                        Toggle(isOn: $settingsStore.settings.systemMonitorMenuBarHeadphoneOptions.usesVolumeColor) {
                            AppLocalizedText("蓝牙音量颜色")
                        }
                        .toggleStyle(.switch)
                        AppLocalizedText("仅底部指标选择音量时生效")
                            .font(.system(size: 9))
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.leading, 20)
            }
        }
        .font(.system(size: 10))
        .controlSize(.small)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.leading, 4)
        .padding(.vertical, 6)
    }
}
