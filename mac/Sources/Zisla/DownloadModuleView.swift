import AppKit
import ZislaCore
import ZislaKit
import SwiftUI

struct DownloadModuleView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "link")
                    .foregroundStyle(.secondary)
                TextField(AppLocalization.text("视频或音频链接"), text: $model.downloadURL)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                    .onSubmit { model.startDownload() }
                    .onChange(of: model.downloadURL) { _, _ in
                        model.downloadURLChangedByUser()
                    }

                IconButton(symbol: "doc.on.clipboard", help: AppLocalization.text("粘贴")) {
                    if let value = NSPasteboard.general.string(forType: .string) {
                        model.setDownloadURL(value)
                    }
                }
                if !model.downloadURL.isEmpty {
                    IconButton(symbol: "xmark", help: AppLocalization.text("清空")) {
                        model.clearDownloadURL()
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
                    width: 140,
                    height: 28,
                    usesGlassSelection: false
                )

                formatPicker

                browserCookiePicker

                IconButton(
                    symbol: "arrow.clockwise",
                    help: AppLocalization.text("刷新格式"),
                    size: .compact
                ) {
                    model.refreshDownloadFormats()
                }
                .disabled(model.isLoadingDownloadFormats)
            }

            HStack(spacing: 10) {

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
        .frame(height: 170)
    }

    private var formatPicker: some View {
        Menu {
            Button(AppLocalization.text("自动选择")) {
                model.selectDownloadFormat(nil)
            }
            Divider()
            ForEach(model.downloadFormatOptions) { option in
                Button {
                    model.selectDownloadFormat(option)
                } label: {
                    HStack(spacing: 6) {
                        if model.selectedDownloadFormat == option.selection {
                            Image(systemName: "checkmark")
                        }
                        Text(downloadFormatText(option))
                    }
                }
            }
        } label: {
            Label(downloadFormatPickerTitle, systemImage: "slider.horizontal.3")
                .font(.system(size: 10, weight: .medium))
                .fitsSingleLine()
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .frame(width: 292, height: 28)
        .disabled(!model.canSelectDownloadFormats)
        .help(
            model.downloadFormatSelectionNeedsFFmpeg
                ? AppLocalization.text("需要 FFmpeg 才能选择格式")
                : AppLocalization.text("选择格式")
        )
    }

    private var browserCookiePicker: some View {
        Menu {
            Button(AppLocalization.text("不使用浏览器 Cookies")) {
                model.downloadBrowserCookieSource = nil
            }
            Divider()
            ForEach(DownloadBrowserCookieSource.allCases, id: \.self) { source in
                Button(browserName(source)) {
                    model.downloadBrowserCookieSource = source
                }
            }
        } label: {
            Label(browserCookiePickerTitle, systemImage: "lock.shield")
                .font(.system(size: 10, weight: .medium))
                .fitsSingleLine()
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .frame(width: 156, height: 28)
    }

    private var downloadFormatPickerTitle: String {
        if model.isLoadingDownloadFormats {
            return AppLocalization.text("正在读取格式")
        }
        if let option = model.selectedDownloadFormatOption {
            return downloadFormatText(option)
        }
        if model.downloadFormatError != nil, model.downloadFormats.isEmpty {
            return AppLocalization.text("未找到可用格式")
        }
        return AppLocalization.text("自动选择")
    }

    private var browserCookiePickerTitle: String {
        guard let source = model.downloadBrowserCookieSource else {
            return AppLocalization.text("浏览器 Cookies")
        }
        return AppLocalization.text("使用 %@ Cookies", browserName(source))
    }

    private func browserName(_ source: DownloadBrowserCookieSource) -> String {
        switch source {
        case .safari: "Safari"
        case .chrome: "Chrome"
        case .firefox: "Firefox"
        }
    }

    private func downloadFormatText(_ option: DownloadFormatOption) -> String {
        let format = option.format
        var parts = [format.formatID]
        if let resolution = format.resolution { parts.append(resolution) }
        if let fps = format.fps, fps > 0 {
            parts.append(AppLocalization.text("%.0f FPS", fps))
        }
        if let videoCodec = format.videoCodec, format.hasVideo { parts.append(videoCodec) }
        if let audioCodec = format.audioCodec, format.hasAudio { parts.append(audioCodec) }
        if let audioCompanion = option.audioCompanion {
            parts.append("+ \(audioCompanion.formatID)")
            if let audioCodec = audioCompanion.audioCodec, audioCompanion.hasAudio {
                parts.append(audioCodec)
            }
        }
        if let fileExtension = format.fileExtension { parts.append(fileExtension.uppercased()) }
        if let dynamicRange = format.dynamicRange,
           dynamicRange.caseInsensitiveCompare("SDR") != .orderedSame {
            parts.append(dynamicRange)
        }
        if let fileSize = format.estimatedFileSize, fileSize > 0 {
            parts.append(ByteCountFormatter.string(fromByteCount: Int64(fileSize), countStyle: .file))
        }
        return parts.joined(separator: " · ")
    }

    @ViewBuilder
    private var downloadStatus: some View {
        if !model.activeDownloads.isEmpty {
            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(alignment: .leading, spacing: 5) {
                    ForEach(model.activeDownloads) { task in
                        downloadTaskRow(task)
                    }
                }
                .padding(.vertical, 1)
            }
        } else if model.isLoadingDownloadFormats {
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text(AppLocalization.text("正在读取格式"))
                    .font(.system(size: 10, weight: .medium))
                Spacer()
            }
        } else {
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
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(Color.zislaError)
                        Text(message)
                            .font(.system(size: 10))
                            .lineLimit(2)
                        Spacer()
                    }
                    if model.downloadNeedsBrowserCookies {
                        Button {
                            model.retryDownloadWithBrowserCookies()
                        } label: {
                            Label(
                                AppLocalization.text("选择浏览器 Cookies 后重试"),
                                systemImage: "arrow.clockwise"
                            )
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.mini)
                        .disabled(model.downloadBrowserCookieSource == nil)
                    }
                }
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
