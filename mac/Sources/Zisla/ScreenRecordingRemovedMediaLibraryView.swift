import SwiftUI
import ZislaCore

struct ScreenRecordingRemovedMediaLibraryView: View {
    @ObservedObject var model: ScreenRecordingStudioModel
    @State private var isExpanded = false

    var body: some View {
        let removedAssets = model.timeline?.assets.filter { $0.isHiddenFromLibrary == true } ?? []
        Group {
            if !removedAssets.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    DisclosureGroup(AppLocalization.text("素材已从素材库移除"), isExpanded: $isExpanded) {}
                        .accessibilityIdentifier("screenRecording.removedMediaLibrary")
                    if isExpanded {
                        ForEach(removedAssets) { asset in
                            HStack(spacing: 8) {
                                Text(asset.name)
                                    .lineLimit(2).truncationMode(.middle)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                Button(AppLocalization.text("重新导入")) { model.restoreMediaAsset(asset.id) }
                                    .disabled(!model.canEdit)
                                    .accessibilityIdentifier("screenRecording.libraryRestoreMedia." + asset.id.uuidString)
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }
                .font(.system(size: 11)).foregroundStyle(.secondary)
                .controlSize(.small)
            }
        }
        .onChange(of: model.project?.id) { isExpanded = false }
    }
}
