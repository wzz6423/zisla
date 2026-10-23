import SwiftUI
import ZislaCore

struct ScreenRecordingTimelineView: View {
    @ObservedObject var model: ScreenRecordingStudioModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let project = model.project {
                Text(AppLocalization.text("输出时长：%@", ScreenRecordingStudioView.clock(project.outputDuration)))
                    .font(.headline)
                HStack {
                    Button(AppLocalization.text("在播放头处分割")) { model.split(at: model.currentTime) }
                    Button(AppLocalization.text("恢复完整素材")) {
                        model.update { $0.edits.segments = [.init(start: 0, end: $0.duration)] }
                    }
                }
                if project.edits.segments.isEmpty {
                    Text(AppLocalization.text("所有片段已删除，请恢复素材后导出"))
                        .font(.caption).foregroundStyle(.secondary)
                }
                ForEach(Array(project.edits.segments.enumerated()), id: \.element.id) { index, segment in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text(AppLocalization.text("片段 %d", index + 1)).font(.subheadline.bold())
                            Spacer()
                            Button { move(segment.id, by: -1) } label: { Image(systemName: "arrow.up") }
                                .help(AppLocalization.text("上移")).disabled(index == 0)
                            Button { move(segment.id, by: 1) } label: { Image(systemName: "arrow.down") }
                                .help(AppLocalization.text("下移")).disabled(index == project.edits.segments.count - 1)
                            Button { duplicate(segment.id) } label: { Image(systemName: "plus.square.on.square") }
                                .help(AppLocalization.text("复制片段"))
                            Button(role: .destructive) { remove(segment.id) } label: { Image(systemName: "trash") }
                                .help(AppLocalization.text("删除片段"))
                        }
                        HStack {
                            timeField("起点（秒）", value: segmentBinding(segment.id, keyPath: \.start))
                            timeField("终点（秒）", value: segmentBinding(segment.id, keyPath: \.end))
                        }
                        Picker(AppLocalization.text("播放速度"), selection: segmentBinding(segment.id, keyPath: \.speed)) {
                            ForEach([0.25, 0.5, 0.75, 1, 1.25, 1.5, 2, 4, 8], id: \.self) { speed in
                                Text(speed.formatted() + "×").tag(speed)
                            }
                        }
                        Button(AppLocalization.text("预览片段起点")) { model.seek(to: segment.start) }
                            .font(.caption)
                    }
                    .padding(10).background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
                }
                Text(AppLocalization.text("时间均对应原始素材，片段按列表顺序导出"))
                    .font(.caption).foregroundStyle(.secondary)
                Divider()
                Text(AppLocalization.text("导出设置")).font(.headline)
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
        }.disabled(!model.canEdit)
    }

    private func timeField(_ title: String, value: Binding<Double>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(AppLocalization.text(title)).font(.caption).foregroundStyle(.secondary)
            TextField(AppLocalization.text(title), value: value, format: .number.precision(.fractionLength(0...3)))
                .textFieldStyle(.roundedBorder)
        }
    }

    private func segmentBinding(_ id: UUID, keyPath: WritableKeyPath<RecordingSegment, Double>) -> Binding<Double> {
        Binding(get: { model.project?.edits.segments.first(where: { $0.id == id })?[keyPath: keyPath] ?? 0 },
                set: { value in model.update { project in
                    if let index = project.edits.segments.firstIndex(where: { $0.id == id }) {
                        project.edits.segments[index][keyPath: keyPath] = value
                    }
                } })
    }

    private func move(_ id: UUID, by offset: Int) {
        model.update { project in
            guard let index = project.edits.segments.firstIndex(where: { $0.id == id }),
                  project.edits.segments.indices.contains(index + offset) else { return }
            project.edits.segments.swapAt(index, index + offset)
        }
    }

    private func duplicate(_ id: UUID) {
        model.update { project in
            guard let index = project.edits.segments.firstIndex(where: { $0.id == id }) else { return }
            var segment = project.edits.segments[index]
            segment.id = UUID()
            project.edits.segments.insert(segment, at: index + 1)
        }
    }

    private func remove(_ id: UUID) {
        model.update { $0.edits.segments.removeAll { $0.id == id } }
    }
}
