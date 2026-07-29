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
                TextField("视频或音频链接", text: $model.downloadURL)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                    .onSubmit { model.startDownload() }

                IconButton(symbol: "doc.on.clipboard", help: "粘贴") {
                    if let value = NSPasteboard.general.string(forType: .string) {
                        model.downloadURL = value.trimmingCharacters(in: .whitespacesAndNewlines)
                    }
                }
                if !model.downloadURL.isEmpty {
                    IconButton(symbol: "xmark", help: "清空") {
                        model.downloadURL = ""
                        if !model.downloadState.isRunning { model.downloadState = .idle }
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
                    title: { $0 == .video ? "视频" : "音频" },
                    selectionID: "download-mode-selection",
                    symbol: { $0 == .video ? "film.fill" : "waveform" },
                    fontSize: 11,
                    width: 178,
                    height: 28
                )
                .disabled(model.downloadState.isRunning)
                .opacity(model.downloadState.isRunning ? 0.45 : 1)

                Button {
                    chooseDirectory()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "folder.fill")
                            .foregroundStyle(Color.cyan)
                        Text(model.downloadDirectory.lastPathComponent)
                            .lineLimit(1)
                        Image(systemName: "chevron.down")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)
                .disabled(model.downloadState.isRunning)

                if model.downloadState.isRunning {
                    Button(role: .destructive) {
                        model.cancelDownload()
                    } label: {
                        Label("取消", systemImage: "stop.fill")
                            .frame(width: 76, height: 28)
                    }
                    .buttonStyle(.bordered)
                } else {
                    Button {
                        model.startDownload()
                    } label: {
                        Label("下载", systemImage: "arrow.down")
                            .frame(width: 76, height: 28)
                    }
                    .buttonStyle(.bordered)
                    .disabled(model.downloadURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }

            downloadStatus
                .frame(maxWidth: .infinity, minHeight: 52, maxHeight: 52)
        }
        .frame(height: 138)
    }

    @ViewBuilder
    private var downloadStatus: some View {
        switch model.downloadState {
        case .idle:
            HStack(spacing: 8) {
                Label("准备就绪", systemImage: "arrow.down.circle.fill")
                Spacer()
                if model.settingsStore.settings.clipboardDetectionEnabled {
                    Label("剪贴板检测已开启", systemImage: "clipboard.fill")
                        .foregroundStyle(Color.zislaSuccess)
                }
            }
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(.secondary)
        case .preparing:
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("正在准备下载")
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
                    .lineLimit(1)
                Spacer()
                Button("在 Finder 中显示") {
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
