import AppKit
import SwiftUI
import UniformTypeIdentifiers
import ZislaKit

struct PDFToolsModuleView: View {
    @ObservedObject var model: AppModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var operation: PDFToolOperation = .merge
    @State private var inputURLs: [URL] = []
    @State private var inputSummary = ""
    @State private var watermarkImageURL: URL?
    @State private var pageSelection = ""
    @State private var watermarkText = "CONFIDENTIAL"
    @State private var pagePrefix = ""
    @State private var pageSuffix = ""
    @State private var rotationDegrees = 90
    @State private var cropX = "0"
    @State private var cropY = "0"
    @State private var cropWidth = ""
    @State private var cropHeight = ""
    @State private var password = ""
    @State private var ownerPassword = ""
    @State private var metadataTitle = ""
    @State private var metadataAuthor = ""
    @State private var isProcessing = false
    @State private var statusMessage: String?
    @State private var hoveredOperation: PDFToolOperation?
    @Namespace private var operationSelectionNamespace

    private let pdfService = PDFProcessingService()

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            operationList
                .frame(width: 152)

            VStack(alignment: .leading, spacing: 10) {
                header
                inputSection
                configuration
                Spacer(minLength: 0)
                footer
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .padding(10)
    }

    private var operationList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 4) {
                ForEach(PDFToolOperation.allCases) { item in
                    Button {
                        if reduceMotion {
                            operation = item
                        } else {
                            withAnimation(ZislaMotion.selection) {
                                operation = item
                            }
                        }
                        inputURLs = []
                        inputSummary = ""
                        watermarkImageURL = nil
                        statusMessage = nil
                        // A password typed for 加密 must not silently pre-fill 解除密码's field.
                        password = ""
                        ownerPassword = ""
                    } label: {
                        Label(item.title, systemImage: item.symbol)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(operation == item ? .primary : .secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .frame(height: 28)
                            .padding(.horizontal, 7)
                            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                            .background {
                                if operation == item {
                                    SelectionGlassBackground(cornerRadius: 6)
                                        .matchedGeometryEffect(
                                            id: "pdf-tool-operation-selection",
                                            in: operationSelectionNamespace
                                        )
                                }
                            }
                    }
                    .buttonStyle(PressableStyle(hoverScale: 1.018, pressedScale: 0.965))
                    .onHover { isHovering in
                        if isHovering {
                            hoveredOperation = item
                        } else if hoveredOperation == item {
                            hoveredOperation = nil
                        }
                    }
                    .zIndex(hoveredOperation == item ? 1 : 0)
                    .help(item.detail)
                }
            }
            .padding(.horizontal, 3)
            .animation(reduceMotion ? nil : ZislaMotion.selection, value: operation)
        }
        .thinScrollChrome()
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Label(operation.title, systemImage: operation.symbol)
                .font(.system(size: 14, weight: .semibold))
            Text(operation.detail)
                .font(.islandMicro())
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Spacer(minLength: 8)
        }
    }

    private var inputSection: some View {
        HStack(spacing: 8) {
            Button(inputURLs.isEmpty ? operation.inputButtonTitle : "重新选择") {
                chooseInputs()
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(isProcessing)

            VStack(alignment: .leading, spacing: 1) {
                Text(inputURLs.isEmpty ? "尚未选择文件" : inputDescription)
                    .font(.system(size: 11, weight: .medium))
                    .lineLimit(1)
                if !inputSummary.isEmpty {
                    Text(inputSummary)
                        .font(.islandMicro())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(8)
        .background(Color.fillCard)
        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
    }

    @ViewBuilder
    private var configuration: some View {
        switch operation {
        case .split, .rotate, .extractText, .crop:
            pageRangeField
        default:
            EmptyView()
        }

        switch operation {
        case .rotate:
            IslandOutlinedPicker(
                selection: $rotationDegrees,
                options: [90, 180, 270],
                title: { degrees in
                    switch degrees {
                    case 90: return "顺时针 90 度"
                    case 180: return "180 度"
                    case 270: return "逆时针 90 度"
                    default: return "\(degrees) 度"
                    }
                },
                selectionID: "pdf-rotation-degrees",
                fontSize: 9,
                width: 280,
                height: 34
            )
        case .textWatermark:
            TextField("水印文字", text: $watermarkText)
                .textFieldStyle(.roundedBorder)
        case .imageWatermark:
            HStack(spacing: 8) {
                Button(watermarkImageURL == nil ? "选择水印图片" : "更换水印图片") {
                    chooseWatermarkImage()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                Text(watermarkImageURL?.lastPathComponent ?? "未选择")
                    .font(.islandMicro())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        case .pageNumbers:
            HStack(spacing: 8) {
                TextField("前缀", text: $pagePrefix)
                    .textFieldStyle(.roundedBorder)
                TextField("后缀", text: $pageSuffix)
                    .textFieldStyle(.roundedBorder)
            }
        case .crop:
            HStack(spacing: 6) {
                cropField("X", value: $cropX)
                cropField("Y", value: $cropY)
                cropField("宽", value: $cropWidth)
                cropField("高", value: $cropHeight)
            }
        case .protect:
            HStack(spacing: 8) {
                SecureField("打开密码", text: $password)
                    .textFieldStyle(.roundedBorder)
                SecureField("所有者密码（可选）", text: $ownerPassword)
                    .textFieldStyle(.roundedBorder)
            }
        case .unlock:
            SecureField("当前密码", text: $password)
                .textFieldStyle(.roundedBorder)
        case .metadata:
            HStack(spacing: 8) {
                TextField("标题", text: $metadataTitle)
                    .textFieldStyle(.roundedBorder)
                TextField("作者", text: $metadataAuthor)
                    .textFieldStyle(.roundedBorder)
            }
        default:
            EmptyView()
        }
    }

    private var pageRangeField: some View {
        TextField("页码范围：留空表示全部，例如 1-3,5", text: $pageSelection)
            .textFieldStyle(.roundedBorder)
    }

    private var footer: some View {
        HStack(spacing: 8) {
            if isProcessing {
                ProgressView()
                    .controlSize(.small)
                Text("正在处理…")
                    .font(.islandMicro())
                    .foregroundStyle(.secondary)
            } else if let statusMessage {
                Text(statusMessage)
                    .font(.islandMicro())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            Button(operation.actionTitle) {
                startProcessing()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .disabled(inputURLs.isEmpty || isProcessing || !configurationIsValid)
        }
    }

    private var inputDescription: String {
        if inputURLs.count == 1 { return inputURLs[0].lastPathComponent }
        return "已选择 \(inputURLs.count) 个文件"
    }

    private var configurationIsValid: Bool {
        switch operation {
        case .textWatermark:
            !watermarkText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .imageWatermark:
            watermarkImageURL != nil
        case .crop:
            Double(cropX) != nil && Double(cropY) != nil && Double(cropWidth) != nil && Double(cropHeight) != nil
        case .protect:
            !password.isEmpty || !ownerPassword.isEmpty
        case .unlock:
            !password.isEmpty
        default:
            true
        }
    }

    private func cropField(_ title: String, value: Binding<String>) -> some View {
        TextField(title, text: value)
            .textFieldStyle(.roundedBorder)
            .frame(width: 72)
    }

    private func chooseInputs() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = operation.allowsMultipleInputs
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = operation.inputContentTypes
        panel.allowsOtherFileTypes = operation == .officeToPDF
        WindowPlacement.prepareModal(panel, on: WindowPlacement.screenUnderMouse())
        guard panel.runModal() == .OK else { return }
        inputURLs = panel.urls.map(\.standardizedFileURL)
        updateInputSummary()
    }

    private func chooseWatermarkImage() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.image]
        WindowPlacement.prepareModal(panel, on: WindowPlacement.screenUnderMouse())
        guard panel.runModal() == .OK, let url = panel.url else { return }
        watermarkImageURL = url.standardizedFileURL
    }

    private func updateInputSummary() {
        guard let input = inputURLs.first else { return }
        if operation.expectsPDF, let summary = try? pdfService.inspect(input) {
            inputSummary = "\(summary.pageCount) 页 · \(ByteCountFormatter.string(fromByteCount: Int64(summary.fileSize), countStyle: .file))"
        } else {
            inputSummary = "\(inputURLs.count) 个文件"
        }
    }

    private func startProcessing() {
        guard !inputURLs.isEmpty else { return }
        let service = pdfService
        switch operation {
        case .merge:
            guard let output = saveOutput(named: "合并-\(inputURLs[0].deletingPathExtension().lastPathComponent).pdf", type: .pdf) else { return }
            let inputs = inputURLs
            runTask { try service.merge(inputs, to: output); return "已合并为 \(output.lastPathComponent)" }
        case .split:
            guard let directory = chooseOutputDirectory(), let input = inputURLs.first else { return }
            do {
                let indexes = try selectedPageIndexes(for: input)
                let baseName = input.deletingPathExtension().lastPathComponent
                let outputs = indexes.map { directory.appendingPathComponent("\(baseName)-第\($0 + 1)页.pdf") }
                runTask { try service.split(input, pageGroups: indexes.map { [$0] }, outputURLs: outputs); return "已拆分为 \(outputs.count) 个 PDF" }
            } catch { presentFailure(error) }
        case .rotate:
            guard let input = inputURLs.first,
                  let output = saveOutput(for: input, suffix: "旋转", type: .pdf)
            else { return }
            do {
                let indexes = try selectedPageIndexes(for: input)
                let degrees = rotationDegrees
                runTask { try service.rotate(input, pageIndexes: indexes, degrees: degrees, to: output); return "已保存 \(output.lastPathComponent)" }
            } catch { presentFailure(error) }
        case .imagesToPDF:
            guard let output = saveOutput(named: "图片合成.pdf", type: .pdf) else { return }
            let inputs = inputURLs
            runTask { try service.convertImagesToPDF(inputs, to: output); return "已生成 \(output.lastPathComponent)" }
        case .officeToPDF:
            guard let input = inputURLs.first,
                  let output = saveOutput(for: input, suffix: "转换", type: .pdf)
            else { return }
            runTask { try LocalOfficeConverter().convertToPDF(input, outputURL: output); return "已生成 \(output.lastPathComponent)" }
        case .render:
            guard let directory = chooseOutputDirectory(), let input = inputURLs.first else { return }
            runTask { let outputs = try service.renderPages(from: input, to: directory); return "已导出 \(outputs.count) 张图片" }
        case .extractText:
            guard let input = inputURLs.first,
                  let output = saveOutput(for: input, suffix: "文字", type: .plainText)
            else { return }
            do {
                let indexes = try selectedPageIndexes(for: input)
                runTask { try service.exportText(from: input, pageIndexes: indexes, outputURL: output); return "已导出 \(output.lastPathComponent)" }
            } catch { presentFailure(error) }
        case .textWatermark:
            guard let input = inputURLs.first,
                  let output = saveOutput(for: input, suffix: "水印", type: .pdf)
            else { return }
            let text = watermarkText
            runTask { try service.addTextWatermark(to: input, watermark: PDFTextWatermark(text: text), outputURL: output); return "已保存 \(output.lastPathComponent)" }
        case .imageWatermark:
            guard let input = inputURLs.first, let image = watermarkImageURL,
                  let output = saveOutput(for: input, suffix: "图片水印", type: .pdf)
            else { return }
            runTask { try service.addImageWatermark(to: input, imageURL: image, outputURL: output); return "已保存 \(output.lastPathComponent)" }
        case .pageNumbers:
            guard let input = inputURLs.first,
                  let output = saveOutput(for: input, suffix: "页码", type: .pdf)
            else { return }
            let style = PDFPageNumberStyle(prefix: pagePrefix, suffix: pageSuffix)
            runTask { try service.addPageNumbers(to: input, style: style, outputURL: output); return "已保存 \(output.lastPathComponent)" }
        case .crop:
            guard let input = inputURLs.first,
                  let x = Double(cropX), let y = Double(cropY), let width = Double(cropWidth), let height = Double(cropHeight),
                  let output = saveOutput(for: input, suffix: "裁剪", type: .pdf)
            else { return }
            do {
                let indexes = try selectedPageIndexes(for: input)
                let cropBox = CGRect(x: x, y: y, width: width, height: height)
                runTask { try service.crop(input, pageIndexes: indexes, to: cropBox, outputURL: output); return "已保存 \(output.lastPathComponent)" }
            } catch { presentFailure(error) }
        case .protect:
            guard let input = inputURLs.first,
                  let output = saveOutput(for: input, suffix: "已加密", type: .pdf)
            else { return }
            let protection = PDFPasswordProtection(userPassword: password, ownerPassword: ownerPassword)
            runTask { try service.protect(input, with: protection, outputURL: output); return "已保存 \(output.lastPathComponent)" }
        case .unlock:
            guard let input = inputURLs.first,
                  let output = saveOutput(for: input, suffix: "已解锁", type: .pdf)
            else { return }
            let value = password
            runTask { try service.unlock(input, password: value, outputURL: output); return "已保存 \(output.lastPathComponent)" }
        case .metadata:
            guard let input = inputURLs.first,
                  let output = saveOutput(for: input, suffix: "信息", type: .pdf)
            else { return }
            let metadata = PDFDocumentMetadata(title: metadataTitle.nilIfEmpty, author: metadataAuthor.nilIfEmpty)
            runTask { try service.updateMetadata(of: input, metadata: metadata, outputURL: output); return "已保存 \(output.lastPathComponent)" }
        }
    }

    private func selectedPageIndexes(for input: URL) throws -> [Int] {
        if pageSelection.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return Array(0..<(try pdfService.inspect(input).pageCount))
        }
        return try pdfService.pageIndexes(in: input, matching: pageSelection)
    }

    private func saveOutput(named name: String, type: UTType) -> URL? {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [type]
        panel.nameFieldStringValue = name
        WindowPlacement.prepareModal(panel, on: WindowPlacement.screenUnderMouse())
        return panel.runModal() == .OK ? panel.url : nil
    }

    private func saveOutput(for input: URL, suffix: String, type: UTType) -> URL? {
        saveOutput(named: "\(input.deletingPathExtension().lastPathComponent)-\(suffix).\(type.preferredFilenameExtension ?? "pdf")", type: type)
    }

    private func chooseOutputDirectory() -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        WindowPlacement.prepareModal(panel, on: WindowPlacement.screenUnderMouse())
        return panel.runModal() == .OK ? panel.url : nil
    }

    private func runTask(_ work: @escaping @Sendable () throws -> String) {
        isProcessing = true
        statusMessage = nil
        Task.detached {
            do {
                let message = try work()
                await MainActor.run {
                    isProcessing = false
                    statusMessage = message
                    model.transientMessage = message
                }
            } catch {
                await MainActor.run {
                    isProcessing = false
                    presentFailure(error)
                }
            }
        }
    }

    private func presentFailure(_ error: Error) {
        let message = error.localizedDescription
        statusMessage = message
        model.transientMessage = message
    }
}

private enum PDFToolOperation: String, CaseIterable, Identifiable {
    case merge
    case split
    case rotate
    case imagesToPDF
    case officeToPDF
    case render
    case extractText
    case textWatermark
    case imageWatermark
    case pageNumbers
    case crop
    case protect
    case unlock
    case metadata

    var id: Self { self }

    var title: String {
        switch self {
        case .merge: "合并 PDF"
        case .split: "拆分页面"
        case .rotate: "旋转页面"
        case .imagesToPDF: "图片转 PDF"
        case .officeToPDF: "Office 转 PDF"
        case .render: "PDF 转图片"
        case .extractText: "导出文字"
        case .textWatermark: "文字水印"
        case .imageWatermark: "图片水印"
        case .pageNumbers: "添加页码"
        case .crop: "裁剪页面"
        case .protect: "加密 PDF"
        case .unlock: "解除密码"
        case .metadata: "文档信息"
        }
    }

    var symbol: String {
        switch self {
        case .merge: "rectangle.3.group"
        case .split: "rectangle.split.3x1"
        case .rotate: "rotate.right"
        case .imagesToPDF: "photo.on.rectangle"
        case .officeToPDF: "doc.richtext"
        case .render: "photo.stack"
        case .extractText: "text.page"
        case .textWatermark: "textformat"
        case .imageWatermark: "seal"
        case .pageNumbers: "number"
        case .crop: "crop"
        case .protect: "lock"
        case .unlock: "lock.open"
        case .metadata: "info.circle"
        }
    }

    var detail: String {
        switch self {
        case .merge: "按选择顺序合并多个 PDF"
        case .split: "将选定页面分别输出为独立 PDF"
        case .rotate: "旋转指定页面或全部页面"
        case .imagesToPDF: "每张图片生成一页 PDF"
        case .officeToPDF: "使用本机 LibreOffice 转换"
        case .render: "导出 PNG 页面图片"
        case .extractText: "导出可提取的文本层"
        case .textWatermark: "直接写入页面内容"
        case .imageWatermark: "在每页叠加图片"
        case .pageNumbers: "在每页底部写入页码"
        case .crop: "设置页面裁剪区域"
        case .protect: "写入本地 PDF 密码"
        case .unlock: "用密码生成未加密副本"
        case .metadata: "修改标题和作者"
        }
    }

    var actionTitle: String {
        switch self {
        case .render: "导出图片"
        case .extractText: "导出文本"
        default: "开始处理"
        }
    }

    var allowsMultipleInputs: Bool {
        self == .merge || self == .imagesToPDF
    }

    var expectsPDF: Bool {
        self != .imagesToPDF && self != .officeToPDF
    }

    var inputButtonTitle: String {
        allowsMultipleInputs ? "选择多个文件" : "选择文件"
    }

    var inputContentTypes: [UTType] {
        switch self {
        case .imagesToPDF:
            [.image]
        case .officeToPDF:
            []
        default:
            [.pdf]
        }
    }
}

private extension String {
    var nilIfEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
