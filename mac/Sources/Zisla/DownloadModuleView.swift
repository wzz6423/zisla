import AppKit
import ZislaCore
import ZislaKit
import SwiftUI

struct DownloadModuleView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "link")
                    .foregroundStyle(.secondary)
                TextField(AppLocalization.text("视频或音频链接"), text: $model.downloadURL)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                    .onSubmit { model.startDownload() }

                IconButton(symbol: "doc.on.clipboard", help: AppLocalization.text("粘贴")) {
                    if let value = NSPasteboard.general.string(forType: .string) {
                        model.downloadURL = value.trimmingCharacters(in: .whitespacesAndNewlines)
                    }
                }
                if !model.downloadURL.isEmpty {
                    IconButton(symbol: "xmark", help: AppLocalization.text("清空")) {
                        model.downloadURL = ""
                        if !model.hasActiveDownloads { model.downloadState = .idle }
                    }
                }
            }
            .padding(.horizontal, 10)
            .frame(height: 38)
            .background(Color.fillCard)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(Color.strokeCard, lineWidth: 1)
            }

            HStack(spacing: 10) {
                IslandOutlinedPicker(
                    selection: $model.downloadMode,
                    options: [.video, .audio],
                    title: { $0 == .video ? "视频" : AppLocalization.text("音频") },
                    selectionID: "download-mode-selection",
                    symbol: { $0 == .video ? "film.fill" : "waveform" },
                    fontSize: 11,
                    width: 178,
                    height: 28,
                    usesGlassSelection: false
                )

                Button {
                    chooseDirectory()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "folder.fill")
                            .foregroundStyle(Color.cyan)
                        Text(model.downloadDirectory.lastPathComponent)
                            .fitsSingleLine()
                        Image(systemName: "chevron.down")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)

                Button {
                    model.startDownload()
                } label: {
                    Label(AppLocalization.text("下载"), systemImage: "arrow.down")
                        .fitsSingleLine()
                        .frame(minWidth: 76)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .frame(height: 28)
                .disabled(model.downloadURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                if model.hasActiveDownloads {
                    IconButton(symbol: "stop.fill", help: AppLocalization.text("取消全部下载"), size: .compact) {
                        model.cancelAllDownloads()
                    }
                    .foregroundStyle(Color.zislaError)
                }
            }

            downloadStatus
                .frame(maxWidth: .infinity, minHeight: 52, maxHeight: 52)
        }
        .frame(height: 138)
    }

    @ViewBuilder
    private var downloadStatus: some View {
        if model.activeDownloads.isEmpty {
            switch model.downloadState {
            case .idle:
                HStack(spacing: 8) {
                    Label(AppLocalization.text("准备就绪"), systemImage: "arrow.down.circle.fill")
                    Spacer()
                    if model.settingsStore.settings.clipboardDetectionEnabled {
                        Label(AppLocalization.text("剪贴板检测已开启"), systemImage: "clipboard.fill")
                            .foregroundStyle(Color.zislaSuccess)
                    }
                }
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.secondary)
            case .preparing:
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text(AppLocalization.text("正在准备下载"))
                        .font(.system(size: 10, weight: .medium))
                }
            case let .downloading(fraction, speed, eta):
                VStack(spacing: 5) {
                    HStack {
                        Text("\(fraction * 100, specifier: "%.1f")%")
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                        Spacer()
                        Text([speed, eta.isEmpty ? "" : "ETA \(eta)"].filter { !$0.isEmpty }.joined(separator: "  "))
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                    ProgressView(value: fraction)
                        .tint(Color(red: 0.36, green: 0.82, blue: 0.98))
                }
            case let .completed(url):
                HStack {
                    Label(url.lastPathComponent, systemImage: "checkmark.circle.fill")
                        .foregroundStyle(Color.zislaSuccess)
                        .fitsSingleLine()
                    Spacer()
                    Button(AppLocalization.text("在 Finder 中显示")) {
                        NSWorkspace.shared.activateFileViewerSelecting([url])
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
                .font(.system(size: 10, weight: .medium))
            case let .failed(message):
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(Color.zislaError)
                    Text(message)
                        .font(.system(size: 10))
                        .lineLimit(2)
                    Spacer()
                }
            }
        } else {
            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(alignment: .leading, spacing: 5) {
                    ForEach(model.activeDownloads) { task in
                        downloadTaskRow(task)
                    }
                }
                .padding(.vertical, 1)
            }
        }
    }

    private func downloadTaskRow(_ task: DownloadTaskSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                Image(systemName: "arrow.down.circle.fill")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Color.zislaInfo)
                Text(downloadSourceLabel(task.urlString))
                    .font(.system(size: 9, weight: .medium))
                    .fitsSingleLine()
                    .truncationMode(.middle)
                Spacer(minLength: 4)
                downloadTaskSummary(task.state)
                IconButton(symbol: "xmark", help: AppLocalization.text("取消此下载"), size: .compact) {
                    model.cancelDownload(taskID: task.id)
                }
                .foregroundStyle(Color.zislaError)
            }

            if case let .downloading(fraction, _, _) = task.state {
                ProgressView(value: fraction)
                    .tint(Color(red: 0.36, green: 0.82, blue: 0.98))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func downloadTaskSummary(_ state: DownloadUIState) -> some View {
        Group {
            switch state {
            case .preparing:
                HStack(spacing: 4) {
                    ProgressView().controlSize(.mini)
                    Text(AppLocalization.text("准备中"))
                }
                .foregroundStyle(.secondary)
            case let .downloading(fraction, speed, eta):
                HStack(spacing: 5) {
                    Text("\(fraction * 100, specifier: "%.1f")%")
                    if !speed.isEmpty { Text(speed) }
                    if !eta.isEmpty { Text("ETA \(eta)") }
                }
                .foregroundStyle(.secondary)
            case .idle:
                Text(AppLocalization.text("已停止"))
            case .completed:
                Text(AppLocalization.text("已完成"))
            case .failed:
                Text(AppLocalization.text("失败"))
            }
        }
        .font(.system(size: 9, design: .monospaced))
        .lineLimit(1)
        .fixedSize(horizontal: true, vertical: false)
    }

    private func downloadSourceLabel(_ urlString: String) -> String {
        guard let url = URL(string: urlString), let host = url.host else { return urlString }
        let path = url.path == "/" ? "" : url.path
        return host + path
    }

    private func chooseDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = model.downloadDirectory
        WindowPlacement.prepareModal(panel, on: WindowPlacement.screenUnderMouse())
        guard panel.runModal() == .OK, let url = panel.url else { return }
        model.downloadDirectory = url
        if let bookmark = try? url.bookmarkData(
            options: .withSecurityScope,
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        ) {
            UserDefaults.standard.set(bookmark, forKey: "download-directory-bookmark")
        }
    }
}
