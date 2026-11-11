import AppKit
import SwiftUI
import UniformTypeIdentifiers
import ZislaCore
import ZislaKit

struct AudioToolsModuleView: View {
    @ObservedObject var model: AppModel
    @StateObject private var controller = AudioToolsController()
    @State private var operation: AudioToolOperation
    @State private var options = AudioProcessingOptions()
    @State private var numberDrafts: [String: String] = [:]
    @Environment(\.locale) private var locale

    init(model: AppModel, initialOperation: AudioToolOperation = .convert) {
        self.model = model
        _operation = State(initialValue: initialOperation)
    }

    var body: some View {
        HStack(alignment: .top, spacing: 20) {
            operationList
                .frame(width: 184, height: 460)
            VStack(alignment: .leading, spacing: 18) {
                AppLocalizedText(operation.detail)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                component
                if !operation.generatesAudio { inputs }
                configuration
                exportOptions
                footer
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .textFieldStyle(.roundedBorder)
        .controlSize(.regular)
        .onChange(of: controller.summaries) { _, summaries in
            numberDrafts = [:]
            if let summary = summaries.first {
                options.startTime = 0
                options.endTime = summary.duration
                options.fadeInDuration = min(1, summary.duration / 3)
                options.fadeOutDuration = min(1, summary.duration / 3)
                options.metadata = Dictionary(uniqueKeysWithValues: ["title", "artist", "album", "comment"].map { key in
                    (key, summary.metadata.first { $0.key.lowercased() == key }?.value ?? "")
                })
            }
        }
        .onChange(of: operation) { _, value in
            if !value.exportFormats.contains(options.format) {
                options.format = value == .compress ? .mp3 : .wav
            }
        }
        .onChange(of: options.format) { _, format in
            if !format.sampleRates.contains(options.sampleRate) { options.sampleRate = 48_000 }
            if (format == .flac || format == .alac) && options.bitDepth == 32 { options.bitDepth = 24 }
            if format == .ogg { options.channelMode = .stereo }
        }
        .onDisappear { controller.cancel() }
    }

    private var operationList: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(AudioToolOperation.allCases) { item in
                    Button {
                        operation = item
                    } label: {
                        Label(AppLocalization.text(item.title), systemImage: item.symbol)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(operation == item ? Color.accentColor : Color.primary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 10)
                            .contentShape(RoundedRectangle(cornerRadius: 8))
                            .background {
                                if operation == item { SettingsTintedBackground(cornerRadius: 8) }
                            }
                    }
                    .buttonStyle(.plain)
                    .disabled(controller.isProcessing || controller.isInspecting)
                    .accessibilityAddTraits(operation == item ? .isSelected : [])
                    .settingsSearchAnchor(.audioOperation(item))
                    .help(AppLocalization.text(item.detail))
                }
            }
        }
    }

    private var component: some View {
        let state = model.managedTools.states[.ffmpeg] ?? ManagedToolState()
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Label("FFmpeg", systemImage: "waveform")
                    .font(.system(size: 12, weight: .medium))
                if toolsAvailable {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(Color.zislaSuccess)
                        .accessibilityLabel(AppLocalization.text("已安装"))
                }
                Spacer(minLength: 0)
                if state.isBusy { ProgressView().controlSize(.small) }
                Button(AppLocalization.text(toolsAvailable ? "更新" : "安装")) {
                    Task {
                        await model.managedTools.refreshInstalledVersions()
                        await model.managedTools.install(.ffmpeg)
                    }
                }
                .buttonStyle(.bordered)
                .disabled(state.isBusy || controller.isProcessing)
                .help(toolsAvailable ? ManagedTool.ffmpeg.updateHelp : ManagedTool.ffmpeg.installHelp)
            }
            if let error = state.errorMessage {
                Text(error).font(.system(size: 11)).foregroundStyle(Color.zislaError)
                    .fixedSize(horizontal: false, vertical: true)
            } else if !toolsAvailable {
                AppLocalizedText("需要 FFmpeg 与 ffprobe，请安装音频处理组件后重试")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var inputs: some View {
        VStack(alignment: .leading, spacing: 10) {
            if controller.inputURLs.isEmpty {
                AppLocalizedText("尚未选择文件").foregroundStyle(.secondary)
            } else {
                ForEach(Array(controller.inputURLs.enumerated()), id: \.offset) { index, url in
                    HStack(spacing: 8) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(url.lastPathComponent).font(.system(size: 12, weight: .medium)).lineLimit(2)
                            if controller.summaries.indices.contains(index) {
                                let summary = controller.summaries[index]
                                Text(AppLocalization.text("%.2f 秒 · %ld Hz · %ld 声道 · %@", summary.duration, summary.sampleRate, summary.channels, summary.codec))
                                    .font(.system(size: 11)).foregroundStyle(.secondary).monospacedDigit()
                            }
                        }
                        Spacer(minLength: 0)
                        if operation.requiresMultipleInputs {
                            IconButton(symbol: "chevron.up", help: AppLocalization.text("上移"), size: .compact) {
                                controller.moveInput(at: index, offset: -1)
                            }
                            .disabled(index == 0 || controller.isProcessing || controller.isInspecting)
                            IconButton(symbol: "chevron.down", help: AppLocalization.text("下移"), size: .compact) {
                                controller.moveInput(at: index, offset: 1)
                            }
                            .disabled(index == controller.inputURLs.count - 1 || controller.isProcessing || controller.isInspecting)
                        }
                    }
                }
            }
            HStack(spacing: 8) {
                Button(AppLocalization.text(controller.inputURLs.isEmpty ? "选择文件" : "重新选择")) { chooseInputs() }
                    .buttonStyle(.bordered).disabled(controller.isProcessing || !toolsAvailable)
                if controller.isInspecting { ProgressView().controlSize(.small) }
            }
        }
    }

    @ViewBuilder
    private var configuration: some View {
        VStack(alignment: .leading, spacing: 10) {
            switch operation {
            case .trim, .removeSegment:
                numberField("开始时间（秒）", value: $options.startTime)
                numberField("结束时间（秒）", value: Binding(get: { options.endTime ?? 0 }, set: { options.endTime = $0 }))
            case .split: numberField("分段时长（秒）", value: $options.segmentDuration)
            case .volume: numberField("音量（dB）", value: $options.volumeDB)
            case .normalize: numberField("目标响度（LUFS）", value: $options.targetLoudness)
            case .fade:
                numberField("淡入（秒）", value: $options.fadeInDuration)
                numberField("淡出（秒）", value: $options.fadeOutDuration)
            case .speed: numberField("速度倍数", value: $options.speed)
            case .pitch: numberField("音高（半音）", value: $options.pitchSemitones)
            case .denoise: numberField("降噪强度（dB）", value: $options.noiseReductionDB)
            case .removeSilence:
                numberField("静音阈值（dB）", value: $options.silenceThresholdDB)
                numberField("最短静音（秒）", value: $options.silenceDuration)
            case .equalizer:
                numberField("低频（dB）", value: $options.bassDB)
                numberField("中频（dB）", value: $options.midDB)
                numberField("高频（dB）", value: $options.trebleDB)
            case .dynamics:
                numberField("压缩阈值（dB）", value: $options.compressorThresholdDB)
                numberField("压缩比", value: $options.compressorRatio)
                numberField("峰值上限（dB）", value: $options.peakLimitDB)
            case .echo:
                numberField("回声延迟（秒）", value: $options.echoDelay)
                numberField("回声衰减", value: $options.echoDecay)
            case .metadata:
                Toggle(AppLocalization.text("清除全部标签"), isOn: $options.clearMetadata)
                if !options.clearMetadata {
                    ForEach([("title", "标题"), ("artist", "艺人"), ("album", "专辑"), ("comment", "备注")], id: \.0) { key, title in
                        LabeledContent(AppLocalization.text(title)) {
                            TextField("", text: Binding(get: { options.metadata[key] ?? "" }, set: { options.metadata[key] = $0 }))
                                .accessibilityLabel(AppLocalization.text(title))
                        }
                    }
                }
            case .repeatAudio:
                Stepper(AppLocalization.text("重复 %ld 次", options.repeatCount), value: $options.repeatCount, in: 2...100)
            case .insertSilence:
                numberField("插入时间（秒）", value: $options.startTime)
                numberField("静音时长（秒）", value: $options.generatedDuration)
            case .generateSilence, .generateTone:
                numberField("生成时长（秒）", value: $options.generatedDuration)
                if operation == .generateTone { numberField("频率（Hz）", value: $options.toneFrequency) }
            default: EmptyView()
            }
        }
        .disabled(controller.isProcessing)
    }

    private var exportOptions: some View {
        VStack(alignment: .leading, spacing: 10) {
            Picker(AppLocalization.text("输出格式"), selection: $options.format) {
                ForEach(operation.exportFormats) {
                    Text($0.title).tag($0)
                }
            }
            if options.format == .ogg {
                AppLocalizedText("OGG（Vorbis）仅支持立体声输出")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
            }
            if options.format.isLossless {
                Picker(AppLocalization.text("位深"), selection: $options.bitDepth) {
                    ForEach(options.format == .flac || options.format == .alac ? [16, 24] : [16, 24, 32], id: \.self) {
                        Text(AppLocalization.text("%ld 位", $0)).tag($0)
                    }
                }
            } else {
                Picker(AppLocalization.text("码率"), selection: $options.bitrateKbps) {
                    ForEach([32, 64, 96, 128, 160, 192, 256, 320], id: \.self) { Text("\($0) kbps").tag($0) }
                }
            }
            Picker(AppLocalization.text("采样率"), selection: $options.sampleRate) {
                ForEach(options.format.sampleRates, id: \.self) { Text("\($0) Hz").tag($0) }
            }
            if operation != .splitChannels && operation != .vocalReduction {
                Picker(AppLocalization.text("声道"), selection: $options.channelMode) {
                    ForEach(AudioChannelMode.allCases.filter {
                        if options.format == .ogg { return $0 == .stereo || (!operation.generatesAudio && $0 == .swap) }
                        return !operation.generatesAudio || [.preserve, .mono, .stereo].contains($0)
                    }) {
                        AppLocalizedText($0.title).tag($0)
                    }
                }
            }
        }
        .pickerStyle(.menu)
        .disabled(controller.isProcessing)
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 10) {
            if controller.isProcessing {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text(controller.total > 1 ? AppLocalization.text("已处理 %ld / %ld", controller.completed, controller.total)
                         : AppLocalization.text("正在处理…"))
                        .font(.system(size: 12)).monospacedDigit()
                    Spacer(minLength: 0)
                    Button(AppLocalization.text("取消")) { controller.cancel() }.buttonStyle(.bordered)
                }
            } else if let message = controller.message {
                Text(message).font(.system(size: 12)).foregroundStyle(controller.failed ? Color.zislaError : Color.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if !controller.outputURLs.isEmpty {
                HStack {
                    Button(AppLocalization.text("在 Finder 中显示")) {
                        NSWorkspace.shared.activateFileViewerSelecting(controller.outputURLs)
                    }
                    .buttonStyle(.bordered)
                    Button(AppLocalization.text("试听")) {
                        if let first = controller.outputURLs.first { NSWorkspace.shared.open(first) }
                    }
                    .buttonStyle(.bordered)
                }
            }
            Button(AppLocalization.text("导出音频")) { startProcessing() }
                .buttonStyle(SettingsTintedButtonStyle())
                .disabled(!canProcess)
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
    }

    private var toolsAvailable: Bool { (try? AudioProcessingService.resolveTools()) != nil }

    private var canProcess: Bool {
        guard toolsAvailable, !controller.isInspecting, !controller.isProcessing else { return false }
        if operation.generatesAudio { return true }
        guard controller.summaries.count == controller.inputURLs.count else { return false }
        let count = controller.inputURLs.count
        if operation.requiresMultipleInputs { return (2...32).contains(count) }
        return operation.allowsMultipleInputs ? (1...32).contains(count) : count == 1
    }

    private func numberField(_ title: String, value: Binding<Double>) -> some View {
        LabeledContent(AppLocalization.text(title)) {
            TextField("", text: Binding(
                get: { numberDrafts[title] ?? value.wrappedValue.formatted(.number.locale(locale)) },
                set: {
                    numberDrafts[title] = $0
                    value.wrappedValue = (try? FloatingPointFormatStyle<Double>.number.locale(locale).parseStrategy.parse($0)) ?? .nan
                }
            ))
                .frame(width: 112).monospacedDigit().accessibilityLabel(AppLocalization.text(title))
        }
    }

    private func chooseInputs() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = operation.allowsMultipleInputs
        panel.allowedContentTypes = operation == .extract ? [.movie] : [.audio]
        panel.allowsOtherFileTypes = true
        WindowPlacement.prepareModal(panel, on: WindowPlacement.screenUnderMouse())
        if panel.runModal() == .OK { controller.setInputs(panel.urls.map(\.standardizedFileURL)) }
    }

    private func startProcessing() {
        let output: URL?
        if operation.exportsToDirectory(inputCount: controller.inputURLs.count) {
            let panel = NSOpenPanel()
            panel.canChooseFiles = false
            panel.canChooseDirectories = true
            WindowPlacement.prepareModal(panel, on: WindowPlacement.screenUnderMouse())
            output = panel.runModal() == .OK ? panel.url : nil
        } else {
            let panel = NSSavePanel()
            if let type = UTType(filenameExtension: options.format.fileExtension) { panel.allowedContentTypes = [type] }
            let name = operation.generatesAudio ? AppLocalization.text(operation.title)
                : controller.inputURLs[0].deletingPathExtension().lastPathComponent
            panel.nameFieldStringValue = "\(name)-\(operation.rawValue).\(options.format.fileExtension)"
            WindowPlacement.prepareModal(panel, on: WindowPlacement.screenUnderMouse())
            output = panel.runModal() == .OK ? panel.url : nil
        }
        guard let output else { return }
        var configuration = options
        if operation == .splitChannels || operation == .vocalReduction { configuration.channelMode = .preserve }
        if operation.generatesAudio && [.left, .right, .swap].contains(configuration.channelMode) { configuration.channelMode = .preserve }
        let inputs = operation.generatesAudio ? [] : controller.inputURLs
        controller.start(.init(operation: operation, inputURLs: inputs, options: configuration), output: output)
    }
}
