import AppKit
import Darwin
import SwiftUI
import UniformTypeIdentifiers
import ZislaCore
import ZislaKit

struct ImageToolsRecognitionResultsView: View {
    @ObservedObject var model: ImageToolsRecognitionModel
    let saveLocations: SaveLocationStore

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if !model.results.isEmpty {
                Button(AppLocalization.text("导出全部文字")) { exportTexts() }
                    .buttonStyle(.bordered)
                    .disabled(model.isProcessing)
                ForEach(model.results) { result in
                    VStack(alignment: .leading, spacing: 10) {
                        Text(result.inputURL.lastPathComponent)
                            .font(.system(size: 12, weight: .medium))
                            .lineLimit(2)
                        ScrollView {
                            Text(result.text)
                                .font(.system(size: 12))
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .frame(maxHeight: 220)
                        ViewThatFits(in: .horizontal) {
                            HStack { exportButtons(result) }
                            VStack(alignment: .leading) { exportButtons(result) }
                        }
                        .buttonStyle(.bordered)
                        .disabled(model.isProcessing)
                    }
                    .padding(12)
                    .background(Color.primary.opacity(0.025), in: RoundedRectangle(cornerRadius: 10))
                }
            }
            ForEach(Array(model.failures.enumerated()), id: \.offset) { _, failure in
                Text("\(failure.inputURL.lastPathComponent): \(failure.message)")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    @ViewBuilder
    private func exportButtons(_ result: ImageToolsRecognitionResult) -> some View {
        Button(AppLocalization.text("复制")) { model.copyText(result) }
        Button(AppLocalization.text("导出文字")) { export(result, format: .text) }
        Button(AppLocalization.text("导出表格")) { export(result, format: .table) }
            .disabled(result.table.isEmpty)
    }

    @discardableResult
    func export(
        _ result: ImageToolsRecognitionResult,
        format: ImageToolsRecognitionDocument.Format,
        panel: NSSavePanel = NSSavePanel(),
        chooseDestination: @MainActor (NSSavePanel) -> URL? = {
            WindowPlacement.prepareModal($0, on: WindowPlacement.screenUnderMouse())
            return $0.runModal() == .OK ? $0.url : nil
        }
    ) -> Task<Void, Never>? {
        let fileExtension = format == .text ? "txt" : "xlsx"
        panel.allowedContentTypes = UTType(filenameExtension: fileExtension).map { [$0] } ?? []
        panel.nameFieldStringValue = result.inputURL.deletingPathExtension().lastPathComponent + "-ocr." + fileExtension
        panel.directoryURL = saveLocations[.imageTools]
        let previousDelegate = panel.delegate
        let validation = ImageToolsRecognitionSavePanelDelegate(protectedInputs: model.inputURLs + [result.inputURL])
        panel.delegate = validation
        defer { panel.delegate = previousDelegate }
        guard let destination = chooseDestination(panel) else { return nil }
        switch format {
        case .text: return model.exportText(result, to: destination)
        case .table: return model.exportTable(result, to: destination)
        }
    }

    @discardableResult
    func exportTexts(
        panel: NSOpenPanel = NSOpenPanel(),
        chooseDirectory: @MainActor (NSOpenPanel) -> URL? = {
            WindowPlacement.prepareModal($0, on: WindowPlacement.screenUnderMouse())
            return $0.runModal() == .OK ? $0.url : nil
        }
    ) -> Task<Void, Never>? {
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.directoryURL = saveLocations[.imageTools]
        guard let directory = chooseDirectory(panel) else { return nil }
        return model.exportTexts(to: directory)
    }
}

@MainActor
final class ImageToolsRecognitionSavePanelDelegate: NSObject, NSOpenSavePanelDelegate {
    private let protectedPaths: Set<String>

    init(protectedInputs: [URL]) {
        protectedPaths = Set(protectedInputs.map { $0.standardizedFileURL.path.lowercased() })
        super.init()
    }

    func panel(_ sender: Any, validate url: URL) throws {
        let path = url.standardizedFileURL.path.lowercased()
        guard !protectedPaths.contains(path) else { throw ImageProcessingError.outputAlreadyExists(url) }
        let directory = open(url.deletingLastPathComponent().path, O_RDONLY | O_NOFOLLOW)
        guard directory >= 0 else { throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno)) }
        defer { _ = close(directory) }
        var metadata = stat()
        if fstatat(directory, url.lastPathComponent, &metadata, AT_SYMLINK_NOFOLLOW) == 0 {
            throw ImageProcessingError.outputAlreadyExists(url)
        }
        guard errno == ENOENT else { throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno)) }
    }
}
