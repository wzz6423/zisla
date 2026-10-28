import SwiftUI
import ZislaCore

struct ScreenRecordingMediaLibraryView: View {
    @ObservedObject var model: ScreenRecordingStudioModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(AppLocalization.text("素材库")).font(.headline)
                Spacer()
                Button(action: model.importVideo) { Image(systemName: "plus") }
                    .buttonStyle(.borderless)
                    .help(AppLocalization.text("导入素材"))
                    .accessibilityLabel(AppLocalization.text("导入素材"))
                    .accessibilityIdentifier("screenRecording.importMedia")
                    .disabled(model.isBusy || model.isChoosingFile || model.isRecording || model.exporter.isExporting)
            }
            ScrollView {
                LazyVStack(spacing: 6) {
                    ForEach(model.mediaAssets) { asset in mediaRow(asset) }
                }
            }
            if model.mediaAssets.isEmpty {
                Button(AppLocalization.text("导入素材"), action: model.importVideo)
                    .frame(maxWidth: .infinity)
                    .disabled(model.isBusy || model.isChoosingFile || model.isRecording || model.exporter.isExporting)
            }
            Text(AppLocalization.text("将素材拖到轨道中开始剪辑"))
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .background(Color(nsColor: .windowBackgroundColor))
        .accessibilityIdentifier("screenRecording.mediaLibrary")
    }

    private func mediaRow(_ asset: RecordingMediaAsset) -> some View {
        HStack(spacing: 8) {
            Button { model.selectMediaAsset(asset.id) } label: {
                HStack(spacing: 8) {
                    Image(systemName: symbol(asset.kind)).font(.system(size: 20))
                        .frame(width: 30, height: 36).foregroundStyle(Color.accentColor)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(asset.name).font(.system(size: 11, weight: .medium))
                            .lineLimit(2).truncationMode(.middle)
                        Text(asset.kind == .image ? "\(asset.width) × \(asset.height)" : ScreenRecordingStudioView.clock(asset.duration))
                            .font(.system(size: 10, design: .monospaced)).foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(!model.canEdit)
            .draggable(asset.id.uuidString)
            .accessibilityIdentifier("screenRecording.mediaAsset." + asset.id.uuidString)
            Button { _ = model.addAssetToTimeline(asset.id, trackID: model.selectedTimelineClip?.trackID) } label: {
                Image(systemName: "plus.circle")
            }
            .buttonStyle(.borderless)
            .disabled(!model.canEdit)
            .help(AppLocalization.text("添加到时间线"))
            .accessibilityLabel(AppLocalization.text("添加到时间线"))
            .accessibilityIdentifier("screenRecording.addMedia." + asset.id.uuidString)
        }
        .padding(7)
        .background(Color.accentColor.opacity(model.selectedMediaAssetID == asset.id ? 0.12 : 0.03),
                    in: RoundedRectangle(cornerRadius: 7))
    }

    private func symbol(_ kind: RecordingMediaKind) -> String {
        switch kind {
        case .video: "film"
        case .image: "photo"
        case .audio: "waveform"
        }
    }
}
