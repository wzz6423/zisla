import SwiftUI
import ZislaCore
import ZislaKit

struct SignificantEnergyView: View {
    @StateObject private var monitor = SignificantEnergyMonitor()
    @Environment(\.locale) private var locale

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label(localized("使用大量能耗"), systemImage: "bolt.fill")
                    .font(.system(size: 12, weight: .semibold))
                Spacer()
                if monitor.state == .loading {
                    ProgressView()
                        .controlSize(.mini)
                        .frame(width: 24, height: 24)
                } else {
                    Button {
                        monitor.refresh()
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 11, weight: .semibold))
                            .frame(width: 24, height: 24)
                    }
                    .buttonStyle(.plain)
                    .help(localized("刷新"))
                    .accessibilityLabel(localized("刷新"))
                }
            }

            if let key = Self.messageKey(for: monitor.state) {
                Text(localized(key))
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else if case .available(let processes) = monitor.state {
                Self.processRow(Self.presentations(for: processes))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onAppear { monitor.start() }
        .onDisappear { monitor.stop() }
    }

    struct ProcessPresentation {
        let name: String
        let icon: NSImage?
    }

    static func presentations(
        for processes: [SignificantEnergyProcess],
        application: (String) -> ProcessPresentation? = { installedApplication($0) }
    ) -> [ProcessPresentation] {
        processes.prefix(3).map { process in
            application(process.bundleIdentifier)
                ?? application(process.responsibleBundleIdentifier)
                ?? ProcessPresentation(name: process.displayName, icon: nil)
        }
    }

    static func installedApplication(
        _ bundleIdentifier: String,
        resolve: (String) -> URL? = { NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0) },
        icon: (URL) -> NSImage = { NSWorkspace.shared.icon(forFile: $0.path) }
    ) -> ProcessPresentation? {
        guard let url = resolve(bundleIdentifier) else { return nil }
        let bundle = Bundle(url: url)
        let name = ["CFBundleDisplayName", kCFBundleNameKey as String]
            .compactMap { bundle?.object(forInfoDictionaryKey: $0) as? String }
            .first { !$0.isEmpty }
        return ProcessPresentation(
            name: name ?? url.deletingPathExtension().lastPathComponent,
            icon: icon(url)
        )
    }

    static func processRow(_ processes: [ProcessPresentation]) -> some View {
        HStack(spacing: 12) {
            ForEach(Array(processes.enumerated()), id: \.offset) { _, process in
                HStack(spacing: 6) {
                    Group {
                        if let icon = process.icon {
                            Image(nsImage: icon).resizable()
                        } else {
                            Image(systemName: "app").resizable()
                                .foregroundStyle(.secondary)
                        }
                    }
                    .frame(width: 18, height: 18)
                    .accessibilityHidden(true)
                    Text(process.name)
                        .font(.system(size: 11, weight: .medium))
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .help(process.name)
                .accessibilityElement(children: .combine)
            }
        }
    }

    static func messageKey(for state: SignificantEnergyState) -> String? {
        switch state {
        case .idle, .loading:
            "正在读取能耗信息…"
        case .available(let processes):
            processes.isEmpty ? "当前没有使用大量能耗的 App" : nil
        case .unavailable(.unsupported):
            "当前系统不支持读取能耗信息"
        case .unavailable(.permissionDenied):
            "系统限制了能耗信息访问"
        case .unavailable(.invalidResponse), .unavailable(.readFailed):
            "无法读取能耗信息，请重试"
        }
    }

    private func localized(_ key: String) -> String {
        AppLocalization.string(key, locale: locale)
    }
}
