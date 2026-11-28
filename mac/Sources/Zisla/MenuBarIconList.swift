import AppKit
import SwiftUI
import ZislaCore
import ZislaKit

struct MenuBarIconList: View {
    let manager: MenuBarManager
    @Environment(\.locale) private var locale
    @State private var icons: [MenuBarIcon] = []
    @State private var layout: MenuBarManager.Layout?
    @State private var revision = 0
    @State private var loading = true
    @State private var movement: Task<Void, Never>?
    @State private var failed: AXUIElement?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                AppLocalizedText("收起时隐藏")
                    .font(.headline)
                Spacer()
                if loading { ProgressView().controlSize(.small) }
                Button(AppLocalization.string("刷新", locale: locale)) { revision += 1 }
                    .disabled(loading || movement != nil)
            }
            ForEach(icons) { icon in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(verbatim: icon.title)
                        if icon.title != icon.app {
                            Text(verbatim: icon.app).font(.caption).foregroundStyle(.secondary)
                        }
                        if failed == icon.id {
                            AppLocalizedText("未能移动图标。按住 ⌘，将分隔线拖过这个图标。")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    if icon.isFixed {
                        AppLocalizedText("系统固定").foregroundStyle(.secondary)
                    } else if let hidden = layout?.onHiddenSide(icon.frame) {
                        Toggle(isOn: Binding(get: { hidden }, set: { wanted in
                            failed = nil
                            movement = Task {
                                if !(await manager.move(icon, hidden: wanted)) { failed = icon.id }
                                movement = nil
                                revision += 1
                            }
                        })) {
                            Text(verbatim: icon.title)
                        }
                        .labelsHidden().toggleStyle(.switch)
                        .disabled(movement != nil || loading)
                    } else {
                        AppLocalizedText("当前无法移动").foregroundStyle(.secondary)
                    }
                }
                .frame(minHeight: 32)
            }
            if icons.isEmpty && !loading {
                AppLocalizedText("暂未找到菜单栏图标").foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 10)
        .task(id: revision) {
            loading = true
            let snapshot = await MenuBarIcon.inventory()
            let boundary = await manager.layout()
            guard !Task.isCancelled else { return }
            layout = boundary
            icons = snapshot.sorted { $0.frame.midX < $1.frame.midX }
            loading = false
        }
        .onDisappear { movement?.cancel() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            if movement == nil { revision += 1 }
        }
    }
}
