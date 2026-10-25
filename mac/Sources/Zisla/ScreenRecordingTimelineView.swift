import SwiftUI
import ZislaCore

struct ScreenRecordingTimelineView: View {
    @ObservedObject var model: ScreenRecordingStudioModel
    @Binding var selectedSegmentID: UUID?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let project = model.project {
                Text(AppLocalization.text("输出时长：%@", ScreenRecordingStudioView.clock(project.outputDuration)))
                    .font(.caption).foregroundStyle(.secondary)
                ViewThatFits(in: .horizontal) {
                    HStack { splitButton; restoreButton }
                    VStack(alignment: .leading, spacing: 6) { splitButton; restoreButton }
                }
                if project.edits.segments.isEmpty {
                    Text(AppLocalization.text("所有片段已删除，请恢复素材后导出"))
                        .font(.caption).foregroundStyle(.secondary)
                } else {
                    ScreenRecordingInspectorSection(AppLocalization.text("片段"), symbol: "scissors") {
                        Picker(AppLocalization.text("片段"), selection: segmentSelection) {
                            ForEach(Array(project.edits.segments.enumerated()), id: \.element.id) { index, segment in
                                Text(AppLocalization.text("片段 %d", index + 1)).tag(Optional(segment.id))
                            }
                        }.labelsHidden().frame(maxWidth: .infinity)
                            .accessibilityIdentifier("screenRecording.selectedSegment")
                        if let index = project.edits.segments.firstIndex(where: {
                            $0.id == (selectedSegmentID ?? project.edits.segments.first?.id)
                        }) {
                            let segment = project.edits.segments[index]
                            timeField("起点（秒）", value: segmentBinding(segment.id, keyPath: \.start))
                            timeField("终点（秒）", value: segmentBinding(segment.id, keyPath: \.end))
                            HStack {
                                Text(AppLocalization.text("播放速度")).font(.system(size: 11)).foregroundStyle(.secondary)
                                Spacer()
                                Picker(AppLocalization.text("播放速度"), selection: segmentBinding(segment.id, keyPath: \.speed)) {
                                    ForEach([0.25, 0.5, 0.75, 1, 1.25, 1.5, 2, 4, 8], id: \.self) { speed in
                                        Text(speed.formatted() + "×").tag(speed)
                                    }
                                }.labelsHidden().frame(width: 100)
                            }
                            Divider()
                            HStack(spacing: 14) {
                                Button { model.moveSegment(segment.id, to: index - 1); selectSegment(segment.id) } label: { Image(systemName: "arrow.up") }
                                    .help(AppLocalization.text("上移")).disabled(index == 0)
                                Button { model.moveSegment(segment.id, to: index + 1); selectSegment(segment.id) } label: { Image(systemName: "arrow.down") }
                                    .help(AppLocalization.text("下移")).disabled(index == project.edits.segments.count - 1)
                                Button { duplicate(segment.id) } label: { Image(systemName: "plus.square.on.square") }
                                    .help(AppLocalization.text("复制片段"))
                                Spacer()
                                Button(role: .destructive) { remove(segment.id) } label: { Image(systemName: "trash") }
                                    .help(AppLocalization.text("删除片段"))
                            }.buttonStyle(.borderless)
                            Button(AppLocalization.text("预览片段起点")) { selectSegment(segment.id) }
                                .font(.caption)
                                .accessibilityIdentifier("screenRecording.timelineFormSegment." + segment.id.uuidString)
                        }
                    }
                }
                ScreenRecordingInspectorSection(AppLocalization.text("导出设置"), symbol: "square.and.arrow.up", expanded: false) {
                    Picker(AppLocalization.text("格式"), selection: $model.exportConfiguration.format) {
                        ForEach(RecordingExportFormat.allCases, id: \.self) { format in
                            Text(format.rawValue.uppercased()).tag(format)
                        }
                    }
                    Picker(AppLocalization.text("分辨率"), selection: $model.exportConfiguration.resolution) {
                        ForEach(RecordingExportResolution.allCases, id: \.self) { resolution in
                            Text(AppLocalization.text(resolution.title)).tag(resolution)
                        }
                    }
                    Picker(AppLocalization.text("帧率"), selection: $model.exportConfiguration.frameRate) {
                        ForEach(model.exportConfiguration.format == .gif ? [10, 15, 30] : [30, 60], id: \.self) { rate in
                            Text("\(rate) FPS").tag(rate)
                        }
                    }
                    .onChange(of: model.exportConfiguration.format) { _, format in
                        if format == .gif && model.exportConfiguration.frameRate > 30 { model.exportConfiguration.frameRate = 30 }
                    }
                }
            }
        }.disabled(!model.canEdit)
    }

    private var splitButton: some View {
        Button(AppLocalization.text("在播放头处分割"), action: splitAtPlayhead)
            .buttonStyle(SettingsTintedButtonStyle())
            .disabled(model.timelineSplitTarget(at: model.playbackTime) == nil)
    }

    private var restoreButton: some View {
        Button(AppLocalization.text("恢复完整素材")) {
            model.update { $0.edits.segments = [.init(start: 0, end: $0.duration)] }
        }.controlSize(.small)
    }

    private var segmentSelection: Binding<UUID?> {
        Binding(get: { selectedSegmentID ?? model.project?.edits.segments.first?.id }, set: { id in
            if let id { selectSegment(id) }
        })
    }

    private func selectSegment(_ id: UUID) {
        guard let project = model.project, let index = project.edits.segments.firstIndex(where: { $0.id == id }) else { return }
        selectedSegmentID = id
        model.seekTimeline(to: project.edits.segments.prefix(index).reduce(0) { $0 + $1.outputDuration })
    }

    private func timeField(_ title: String, value: Binding<Double>) -> some View {
        ScreenRecordingNumberField(title: AppLocalization.text(title), value: value,
            identifier: "screenRecording.segmentField." + title)
    }

    private func segmentBinding(_ id: UUID, keyPath: WritableKeyPath<RecordingSegment, Double>) -> Binding<Double> {
        Binding(get: { model.project?.edits.segments.first(where: { $0.id == id })?[keyPath: keyPath] ?? 0 },
                set: { value in model.update { project in
                    if let index = project.edits.segments.firstIndex(where: { $0.id == id }) {
                        project.edits.segments[index][keyPath: keyPath] = value
                    }
                } })
    }

    private func splitAtPlayhead() {
        if let id = model.splitTimeline(at: model.playbackTime) { selectedSegmentID = id }
    }

    private func duplicate(_ id: UUID) {
        if let copyID = model.duplicateSegment(id) { selectSegment(copyID) }
    }

    private func remove(_ id: UUID) {
        selectedSegmentID = model.deleteSegment(id)
        if let selectedSegmentID { selectSegment(selectedSegmentID) }
    }
}
