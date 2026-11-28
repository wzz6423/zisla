import AppKit
import SwiftUI
import ZislaCore
import ZislaKit

struct MenuBarIconList: View {
    @ObservedObject var manager: MenuBarManager
    @ObservedObject var store: FeatureSettingsStore
    let hasAccessibility: Bool
    let requestAccess: () -> Void
    @Environment(\.locale) private var locale

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if !hasAccessibility {
                HStack {
                    AppLocalizedText("管理其他应用的图标需要辅助功能权限。")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button(AppLocalization.string("去授权", locale: locale), action: requestAccess)
                }
                .padding(.vertical, 6)
            }
            ForEach(manager.rows) { row in
                if row != manager.rows.first { Divider() }
                HStack(spacing: 10) {
                    rowImage(row)
                        .frame(width: 20, height: 20)
                        .accessibilityHidden(true)
                    Text(verbatim: row.label(locale: locale))
                    Spacer()
                    Toggle(isOn: Binding(
                        get: { manager.isShown(row) },
                        set: { shown in Task { await manager.setVisible(shown, row: row) } }
                    )) { Text(verbatim: row.label(locale: locale)) }
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .accessibilityIdentifier("menu-bar-visibility-\(row.id)")
                        .disabled(manager.busy || (!row.isLocal && !hasAccessibility && store.settings.hiddenMenuBarIcons[row.id] == nil))
                }
                .frame(minHeight: 38)
                if manager.failedID == row.id {
                    AppLocalizedText("无法更改此图标的显示状态。")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            if manager.rows.isEmpty && hasAccessibility {
                if manager.loading { ProgressView().controlSize(.small) }
                else { AppLocalizedText("暂未找到菜单栏图标").foregroundStyle(.secondary) }
            }
        }
        .onAppear { manager.setPageOpen(true) }
        .onDisappear { manager.setPageOpen(false) }
        .task(id: hasAccessibility) { await manager.refresh() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            Task { await manager.refresh() }
        }
    }
    @ViewBuilder private func rowImage(_ row: MenuBarIconRow) -> some View {
        if row.isLocal {
            if let metric = SystemMonitorMenuBarMetric(rawValue: String(row.id.dropFirst("zisla:".count))) {
                Image(systemName: metric.symbolName)
            } else if row.id == MenuBarIconRow.localID("application") {
                Image(nsImage: NSApp.applicationIconImage).resizable().scaledToFit()
            } else {
                Image(systemName: "gauge.with.dots.needle.67percent")
            }
        } else if let owner = row.id.split(separator: "|", maxSplits: 1).first, row.id.contains("|"),
                  let image = SettingsView.appIcon(forBundleIdentifier: String(owner)) {
            Image(nsImage: image).resizable().scaledToFit()
        } else {
            Image(systemName: MenuBarIcon.symbol(for: row))
        }
    }

}
