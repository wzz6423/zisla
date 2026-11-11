import AppKit
import SwiftUI
import UniformTypeIdentifiers
import ZislaCore
import ZislaKit

struct ImageToolsModuleView: View {
    @ObservedObject private var tools: ManagedToolService
    private let saveLocations: SaveLocationStore
    private let settingsStore: FeatureSettingsStore
    @StateObject private var store = ImageToolsModel()
    @StateObject private var recognition = ImageToolsRecognitionModel()
    @State private var operation: ImageToolOperation
    @State private var formats = Set(ImageOutputFormat.conversionFormats)
    @State private var quality = 80.0
    @State private var resizeMethod: ImageResizeMethod = .fit
    @State private var width = ""
    @State private var height = ""
    @State private var preserveMetadata = false
    @State private var background = "#FFFFFF"
    @State private var dropTargeted = false
    @State private var comparisonItem: ImageProcessedItem?
    @State private var transform = ImageTransformOptions.identity
    @State private var watermark = ImageWatermarkOptions(content: .text(""))
    @State private var extractionMode: ScreenshotExtractionMode = .foreground
    @Environment(\.colorScheme) private var colorScheme

    init(model: AppModel, initialOperation: ImageToolOperation = .compress) {
        tools = model.managedTools
        saveLocations = model.saveLocations
        settingsStore = model.settingsStore
        _operation = State(initialValue: initialOperation)
    }

    var body: some View {
        HStack(alignment: .top, spacing: 20) {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(ImageToolOperation.allCases) { item in
                    Button { operation = item } label: {
                        Label(AppLocalization.text(item.title), systemImage: item.symbol)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(operation == item ? Color.accentColor : Color.primary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .frame(minHeight: 36)
                            .padding(.horizontal, 10)
                            .background {
                                if operation == item { SettingsTintedBackground(cornerRadius: 8) }
                            }
                    }
                    .buttonStyle(PressableStyle(hoverScale: 1.018, pressedScale: 0.965))
                    .accessibilityAddTraits(operation == item ? .isSelected : [])
                    .settingsSearchAnchor(.imageOperation(item))
                    .disabled(isProcessing)
                }
            }
            .frame(width: 176)

            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 6) {
                    Label(AppLocalization.text(operation.title), systemImage: operation.symbol)
                        .font(.system(size: 17, weight: .semibold))
                    AppLocalizedText(operation.detail)
                        .font(.system(size: 12)).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                inputSection
                configuration
                actions
                if operation == .recognize {
                    ImageToolsRecognitionResultsView(model: recognition, saveLocations: saveLocations)
                } else if let batch = store.batch {
                    results(batch)
                }
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .controlSize(.regular)
        .textFieldStyle(.roundedBorder)
        .onDisappear { store.cancel(); recognition.cancel() }
        .onChange(of: operation) { _, _ in
            store.discardResults()
            store.discardEdits()
            store.message = nil
            recognition.clear()
        }
        .onChange(of: extractionMode) { _, _ in
            store.discardResults()
            store.discardEdits()
            store.message = nil
        }
        .sheet(item: $comparisonItem) { item in
            ImageComparisonView(item: item, service: service)
        }
        .sheet(item: $store.editorInput) { input in
            ImageToolsEditorView(image: input.image, settingsStore: settingsStore, saveLocations: saveLocations,
                                 initialTool: operation == .extract ? .extraction : .mosaic) { image in
                store.recordEdit(image, for: input.inputURL)
            }
        }
        .task { await tools.refreshInstalledVersions() }
    }

    private var service: ImageProcessingService {
        ImageProcessingService(executableURL: tools.resolvedExecutable(for: .libvips)?.url,
                               avifExecutableURL: tools.resolvedExecutable(for: .libavif)?.url)
    }

    private var isProcessing: Bool { store.isProcessing || recognition.isProcessing }

    private var usesEditor: Bool { operation == .obscure || (operation == .extract && extractionMode == .lasso) }

    private var inputSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(store.inputs.isEmpty ? AppLocalization.text("拖入图片或文件夹") : AppLocalization.text("已选择 %ld 张图片", store.inputs.count))
                .font(.system(size: 13, weight: .medium))
            if !store.inputs.isEmpty {
                Text(store.inputs.prefix(3).map(\.lastPathComponent).joined(separator: " · "))
                    .font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(2)
            }
            HStack {
                Button(AppLocalization.text("选择图片")) { chooseInputs(folders: false) }
                Button(AppLocalization.text("选择文件夹")) { chooseInputs(folders: true) }
                if !store.inputs.isEmpty {
                    Button(AppLocalization.text("清空")) {
                        store.inputs = []
                        store.discardResults()
                        store.discardEdits()
                        recognition.clear()
                        store.message = nil
                    }
                }
            }
            .buttonStyle(.bordered)
            .disabled(isProcessing)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color.primary.opacity(colorScheme == .dark ? 0.045 : 0.025), in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(dropTargeted ? Color.accentColor : Color.clear))
        .onDrop(of: [UTType.fileURL.identifier], delegate: TransferDropDelegate(isTargeted: $dropTargeted) { items in
            guard !isProcessing else { return }
            store.addInputs(items.compactMap { if case .file(let url) = $0 { url } else { nil } })
        })
    }

    private var configuration: some View {
        VStack(alignment: .leading, spacing: 14) {
            if operation == .transform { ImageTransformControls(options: $transform) }
            if operation == .watermark { ImageWatermarkControls(options: $watermark) }
            if operation == .extract {
                Picker(AppLocalization.text("提取方式"), selection: $extractionMode) {
                    ForEach(ScreenshotExtractionMode.allCases) { mode in AppLocalizedText(mode.title).tag(mode) }
                }
                .pickerStyle(.menu)
            }
            if usesEditor {
                ForEach(store.inputs, id: \.self) { input in
                    HStack(spacing: 8) {
                        Text(input.lastPathComponent).lineLimit(2)
                        Spacer()
                        if store.editedImageURLs[input] != nil {
                            Image(systemName: "checkmark.circle.fill").foregroundStyle(Color.zislaSuccess)
                                .accessibilityLabel(AppLocalization.text("已编辑"))
                        }
                        Button(AppLocalization.text("编辑")) { store.prepareEditor(input, service: service) }
                            .buttonStyle(.bordered)
                    }
                }
            }
            if operation != .recognize && !operation.requiresRasterEditing {
                if operation == .convert || operation == .smallest {
                    VStack(alignment: .leading, spacing: 8) {
                        AppLocalizedText("输出格式").font(.system(size: 12, weight: .medium))
                        HStack {
                            ForEach(ImageOutputFormat.conversionFormats) { format in
                                Toggle(format.displayName, isOn: Binding(
                                    get: { formats.contains(format) },
                                    set: { if $0 { formats.insert(format) } else { formats.remove(format) } }
                                ))
                                .toggleStyle(.checkbox)
                            }
                        }
                    }
                }
                HStack {
                    AppLocalizedText("图片质量")
                    Slider(value: $quality, in: 1...100, step: 1)
                        .accessibilityLabel(AppLocalization.text("图片质量"))
                    Text(Int(quality).formatted()).monospacedDigit().frame(width: 30)
                }
                if operation == .resize {
                    Picker(AppLocalization.text("缩放方式"), selection: $resizeMethod) {
                        ForEach(ImageResizeMethod.allCases) { method in AppLocalizedText(method.title).tag(method) }
                    }
                    .pickerStyle(.menu)
                    HStack {
                        TextField(AppLocalization.text("宽度（像素）"), text: $width)
                        TextField(AppLocalization.text("高度（像素）"), text: $height)
                    }
                    AppLocalizedText("仅缩小图片；按单边缩放时留空另一边")
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                }
                Toggle(AppLocalization.text("保留元数据"), isOn: $preserveMetadata)
                    .help(AppLocalization.text("包括版权、拍摄时间和 GPS 位置"))
                HStack {
                    AppLocalizedText("透明背景填充色")
                    TextField("#FFFFFF", text: $background).frame(maxWidth: 110)
                        .accessibilityLabel(AppLocalization.text("透明背景填充色"))
                }
                .help(AppLocalization.text("用于 JPEG 转换或缩略图留白"))
            }
        }
        .font(.system(size: 12))
        .disabled(isProcessing)
    }

    private var options: ImageProcessingOptions {
        ImageProcessingOptions(
            formats: operation == .smallest || operation == .convert ? Array(formats) : [],
            smallestOnly: operation == .smallest, quality: Int(quality),
            resize: operation == .resize ? ImageResizeOptions(method: resizeMethod, width: Int(width), height: Int(height)) : nil,
            preserveMetadata: preserveMetadata, background: background,
            transform: operation == .transform ? transform : .identity,
            watermark: operation == .watermark ? watermark : nil
        )
    }

    private var actions: some View {
        VStack(alignment: .leading, spacing: 10) {
            if isProcessing {
                let completed = recognition.isProcessing ? recognition.completed : store.completed
                let total = recognition.isProcessing ? recognition.total : store.total
                if total > 0 {
                    ProgressView(value: Double(completed), total: Double(total))
                    Text(AppLocalization.text("正在处理 %ld / %ld", completed, total)).font(.system(size: 12))
                } else { ProgressView() }
            } else if let message = operation == .recognize ? recognition.message ?? store.message : store.message {
                Text(message).font(.system(size: 12)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            HStack {
                Spacer()
                if isProcessing {
                    Button(AppLocalization.text("取消")) { store.cancel(); recognition.cancel() }.buttonStyle(.bordered)
                } else {
                    Button(AppLocalization.text("开始处理")) {
                        startProcessing()
                    }
                    .buttonStyle(SettingsTintedButtonStyle())
                    .disabled(!canProcess)
                }
            }
        }
    }

    private var canProcess: Bool {
        guard !store.inputs.isEmpty else { return false }
        if usesEditor { return !store.editedImageURLs.isEmpty }
        if operation == .recognize || operation == .extract { return true }
        return options.isValid
            && !(operation == .resize && ((!width.isEmpty && Int(width) == nil) || (!height.isEmpty && Int(height) == nil)))
            && !((operation == .convert || operation == .smallest) && formats.isEmpty)
            && !(operation == .transform && transform.isIdentity)
    }

    private func startProcessing() {
        if operation == .recognize {
            recognition.start(urls: store.inputs, service: service)
        } else if usesEditor {
            store.startEdited(service: service)
        } else if operation == .extract {
            store.startExtraction(service: service, mode: extractionMode)
        } else {
            store.start(service: service, options: options)
        }
    }

    private func results(_ batch: ImageProcessingBatch) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            if !batch.items.isEmpty {
                ViewThatFits(in: .horizontal) {
                    HStack {
                        exportButtons(batch.items)
                    }
                    VStack(alignment: .leading) {
                        exportButtons(batch.items)
                    }
                }
                .buttonStyle(.bordered)
                .disabled(store.isProcessing)
                ForEach(batch.items) { item in
                    resultItem(item)
                }
            }
            ForEach(Array(batch.failures.enumerated()), id: \.offset) { _, failure in
                Text(failureDescription(failure))
                    .font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    @ViewBuilder
    private func exportButtons(_ items: [ImageProcessedItem]) -> some View {
        Button(AppLocalization.text("导出全部")) { export(items, smallestOnly: false) }
        Button(AppLocalization.text("导出最小结果")) { export(items, smallestOnly: true) }
        Button(AppLocalization.text("导出 ZIP")) { exportZIP(items) }
    }

    private func resultItem(_ item: ImageProcessedItem) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(item.inputURL.lastPathComponent).font(.system(size: 12, weight: .medium)).lineLimit(2)
            ForEach(item.outputs) { output in outputRow(output, item: item) }
        }
        .padding(12)
        .background(Color.primary.opacity(0.025), in: RoundedRectangle(cornerRadius: 10))
    }

    private func outputRow(_ output: ImageProcessedOutput, item: ImageProcessedItem) -> some View {
        HStack(spacing: 8) {
            Text(output.format.displayName)
            Text("\(bytes(item.summary.fileSize)) → \(bytes(output.summary.fileSize))").foregroundStyle(.secondary)
            if output.url == item.smallest?.url {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(Color.zislaSuccess)
                    .accessibilityLabel(AppLocalization.text("最小结果"))
            }
            Spacer()
            Button(AppLocalization.text("对比")) {
                comparisonItem = ImageProcessedItem(inputURL: item.inputURL, sourceURL: item.sourceURL, summary: item.summary, outputs: [output])
            }
            Button(AppLocalization.text("导出")) { exportSingle(output, item: item) }
        }
        .font(.system(size: 11))
        .disabled(store.isProcessing)
    }

    private func failureDescription(_ failure: ImageProcessingFailure) -> String {
        let format = failure.format.map { " · " + $0.displayName } ?? ""
        return "\(failure.inputURL.lastPathComponent)\(format): \(failure.message)"
    }

    private func chooseInputs(folders: Bool) {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = folders
        panel.canChooseFiles = !folders
        if !folders { panel.allowedContentTypes = ImageProcessingService.supportedExtensions.compactMap { UTType(filenameExtension: $0) } }
        WindowPlacement.prepareModal(panel, on: WindowPlacement.screenUnderMouse())
        if panel.runModal() == .OK { store.addInputs(panel.urls) }
    }

    private func export(_ items: [ImageProcessedItem], smallestOnly: Bool) {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.directoryURL = saveLocations[.imageTools]
        WindowPlacement.prepareModal(panel, on: WindowPlacement.screenUnderMouse())
        guard panel.runModal() == .OK, let directory = panel.url else { return }
        store.exportImages(items, to: directory, smallestOnly: smallestOnly)
    }

    private func exportSingle(_ output: ImageProcessedOutput, item: ImageProcessedItem) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = UTType(filenameExtension: output.format.fileExtension).map { [$0] } ?? []
        panel.nameFieldStringValue = item.inputURL.deletingPathExtension().lastPathComponent + "-" + output.format.fileExtension + "." + output.format.fileExtension
        panel.directoryURL = saveLocations[.imageTools]
        WindowPlacement.prepareModal(panel, on: WindowPlacement.screenUnderMouse())
        guard panel.runModal() == .OK, let destination = panel.url else { return }
        do {
            guard !FileManager.default.fileExists(atPath: destination.path) else { throw ImageProcessingError.outputAlreadyExists(destination) }
            try FileManager.default.copyItem(at: output.url, to: destination)
            store.message = AppLocalization.text("已保存 %@", destination.lastPathComponent)
        } catch { store.message = error.localizedDescription }
    }

    private func exportZIP(_ items: [ImageProcessedItem]) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.zip]
        panel.nameFieldStringValue = "images.zip"
        panel.directoryURL = saveLocations[.imageTools]
        WindowPlacement.prepareModal(panel, on: WindowPlacement.screenUnderMouse())
        guard panel.runModal() == .OK, let destination = panel.url else { return }
        store.exportZIP(items, to: destination)
    }

    private func bytes(_ size: Int64) -> String { ByteCountFormatter.string(fromByteCount: size, countStyle: .file) }
}

private struct ImageComparisonView: View {
    let item: ImageProcessedItem
    let service: ImageProcessingService
    @State private var original: NSImage?
    @State private var processed: NSImage?
    @State private var fraction = 0.5
    @State private var error: String?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.layoutDirection) private var layoutDirection

    var body: some View {
        VStack(spacing: 16) {
            Text(item.inputURL.lastPathComponent).font(.headline).lineLimit(2)
            if let original, let processed {
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        image(original)
                        image(processed).mask(alignment: .leading) {
                            Rectangle().frame(width: geometry.size.width * fraction)
                        }
                        Rectangle().fill(Color.accentColor).frame(width: 2)
                            .offset(x: geometry.size.width * fraction * (layoutDirection == .rightToLeft ? -1 : 1))
                    }
                }
                .frame(height: 320)
                HStack { AppLocalizedText("处理后"); Spacer(); AppLocalizedText("原图") }
                Slider(value: $fraction, in: 0...1).accessibilityLabel(AppLocalization.text("图片对比"))
            } else if let error {
                Text(error).foregroundStyle(.secondary)
            } else { ProgressView() }
            Button(AppLocalization.text("完成")) { dismiss() }.keyboardShortcut(.defaultAction)
        }
        .padding(24)
        .frame(width: 600)
        .task {
            do {
                guard let original = NSImage(data: try await service.preview(item.sourceURL)),
                      let processed = NSImage(data: try await service.preview(item.outputs[0].url)) else {
                    throw ImageProcessingError.invalidOutput
                }
                self.original = original
                self.processed = processed
            } catch { self.error = error.localizedDescription }
        }
    }

    private func image(_ image: NSImage) -> some View {
        Image(nsImage: image).resizable().scaledToFit().frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
