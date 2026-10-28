import SwiftUI
import ZislaCore

struct ScreenRecordingOutputDirectorySettingsView: View {
    @ObservedObject var model: ScreenRecordingStudioModel

    var body: some View {
        let path = model.recordingOutputDirectory.path(percentEncoded: false)
        VStack(alignment: .trailing, spacing: 4) {
            Text(path)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
                .help(path)
                .accessibilityIdentifier("screenRecording.settingsSaveDirectory")
            Button(AppLocalization.text("更改保存位置"), action: model.chooseRecordingOutputDirectory)
                .controlSize(.small)
                .disabled(model.isRecording || model.isBusy || model.isChoosingFile || model.exporter.isExporting)
                .accessibilityIdentifier("screenRecording.chooseSaveDirectory")
        }
    }
}
