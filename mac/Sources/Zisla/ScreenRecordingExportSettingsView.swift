import AppKit
import SwiftUI
import UniformTypeIdentifiers
import ZislaCore

enum RecordingExportContent: CaseIterable {
    case video, livePhoto, audioOnly

    var title: String {
        switch self {
        case .video: "视频"
        case .livePhoto: "Live Photo"
        case .audioOnly: "仅音频"
        }
    }
}

@MainActor
final class ScreenRecordingExportSettings: NSObject, ObservableObject, NSOpenSavePanelDelegate {
    @Published var configuration: RecordingExportConfiguration {
        didSet {
            if configuration.format != oldValue.format { synchronizeFormat() }
        }
    }
    var content: RecordingExportContent {
        get { configuration.format.isAudioOnly ? .audioOnly : configuration.format == .livePhoto ? .livePhoto : .video }
        set {
            switch newValue {
            case .video: configuration.format = .mp4
            case .livePhoto: configuration.format = .livePhoto
            case .audioOnly: configuration.format = .m4a
            }
        }
    }
    var formats: [RecordingExportFormat] {
        RecordingExportFormat.allCases.filter {
            content == .audioOnly ? $0.isAudioOnly : !$0.isAudioOnly && $0 != .livePhoto
        }
    }
    var frameRates: [Int] { configuration.format == .gif ? [10, 15, 30] : [30, 60] }
    var showsVideoSettings: Bool { !configuration.format.isAudioOnly }
    var validationMessage: String? {
        configuration.format == .livePhoto && !canSelect(.livePhoto)
            ? RecordingLivePhotoExportError.durationExceeded.localizedDescription : nil
    }
    var canConfirm: Bool { validationMessage == nil }
    private let duration: Double
    private unowned let panel: NSSavePanel

    init(configuration: RecordingExportConfiguration, panel: NSSavePanel, duration: Double) {
        self.configuration = configuration
        self.panel = panel
        self.duration = duration
        super.init()
        panel.delegate = self
        synchronizeFormat()
    }

    func canSelect(_ content: RecordingExportContent) -> Bool {
        content != .livePhoto || RecordingLivePhotoPolicy.supports(duration: duration)
    }

    func panel(_ sender: Any, validate url: URL) throws {
        if !canConfirm { throw RecordingLivePhotoExportError.durationExceeded }
    }

    private func synchronizeFormat() {
        if !frameRates.contains(configuration.frameRate) { configuration.frameRate = 30 }
        panel.prompt = AppLocalization.text(configuration.format.isAudioOnly ? "导出音频" : "导出录屏")
        panel.allowedContentTypes = [configuration.format.contentType]
        let name = panel.nameFieldStringValue as NSString
        let stem = RecordingExportFormat.allCases.contains { $0.fileExtension == name.pathExtension.lowercased() }
            ? name.deletingPathExtension : name as String
        panel.nameFieldStringValue = ScreenRecordingStudioModel.fileName(stem, extension: configuration.format.fileExtension)
    }
}

extension RecordingExportFormat {
    var contentType: UTType {
        if self == .gif { return .gif }
        if self == .mp4 { return .mpeg4Movie }
        return UTType(tag: fileExtension, tagClass: .filenameExtension,
            conformingTo: self == .livePhoto ? .package : isAudioOnly ? .audio : .movie)!
    }
}

struct ScreenRecordingExportSettingsView: View {
    @ObservedObject var settings: ScreenRecordingExportSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Text(AppLocalization.text("导出内容"))
                ForEach(RecordingExportContent.allCases, id: \.self) { content in
                    Button { settings.content = content } label: {
                        Text(AppLocalization.text(content.title))
                    }
                    .buttonStyle(.bordered)
                    .tint(settings.content == content ? .accentColor : .secondary)
                    .disabled(!settings.canSelect(content))
                    .accessibilityIdentifier("screenRecording.exportContent." + String(describing: content))
                }
            }
            if !settings.canSelect(.livePhoto) {
                Text(AppLocalization.text("Live Photo 最长支持 3 秒，请缩短时间线"))
                    .font(.caption).foregroundStyle(.secondary)
                    .accessibilityIdentifier("screenRecording.livePhotoDurationLimit")
            }
            if settings.content != .livePhoto {
                Picker(AppLocalization.text("格式"), selection: $settings.configuration.format) {
                    ForEach(settings.formats, id: \.self) { format in
                        Text(format.title).tag(format)
                    }
                }.accessibilityIdentifier("screenRecording.exportFormat")
            }
            if settings.showsVideoSettings {
                Picker(AppLocalization.text("分辨率"), selection: $settings.configuration.resolution) {
                    ForEach(RecordingExportResolution.allCases, id: \.self) { resolution in
                        Text(AppLocalization.text(resolution.title)).tag(resolution)
                    }
                }.accessibilityIdentifier("screenRecording.exportResolution")
                Picker(AppLocalization.text("帧率"), selection: $settings.configuration.frameRate) {
                    ForEach(settings.frameRates, id: \.self) { rate in
                        Text("\(rate) FPS").tag(rate)
                    }
                }
                .accessibilityIdentifier("screenRecording.exportFrameRate")
            }
        }
        .pickerStyle(.menu)
        .padding(12)
        .frame(width: 380)
        .environment(\.locale, AppLocalization.currentLanguage.locale)
        .environment(\.layoutDirection, AppLocalization.currentLanguage.isRightToLeft ? .rightToLeft : .leftToRight)
    }
}
