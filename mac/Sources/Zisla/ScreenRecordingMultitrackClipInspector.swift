import SwiftUI
import ZislaCore

struct ScreenRecordingMultitrackClipInspector: View {
    @ObservedObject var model: ScreenRecordingStudioModel
    @Environment(\.recordingCanvasSelection) private var canvasSelection

    var body: some View {
        Text(AppLocalization.text("输出时长：%@", ScreenRecordingStudioView.clock(model.project?.outputDuration ?? 0)))
            .font(.caption).foregroundStyle(.secondary)
        if let clip = model.selectedTimelineClip {
            ScreenRecordingInspectorSection(AppLocalization.text("片段"), symbol: clip.content.trackKind.symbol) {
                if let asset = model.selectedRemovedMediaAsset, let directory = model.directory {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(AppLocalization.text("素材已从素材库移除"))
                            .font(.system(size: 11, weight: .medium))
                            .accessibilityIdentifier("screenRecording.removedMediaNotice")
                        Text(AppLocalization.text("文件名：%@", URL(fileURLWithPath: asset.file).lastPathComponent))
                            .accessibilityIdentifier("screenRecording.removedMediaName")
                        Text(AppLocalization.text("文件路径：%@",
                            directory.appendingPathComponent(asset.file).path))
                            .textSelection(.enabled)
                            .accessibilityIdentifier("screenRecording.removedMediaPath")
                        Button(AppLocalization.text("重新导入")) { model.restoreMediaAsset(asset.id) }
                            .disabled(!model.canEdit)
                            .accessibilityIdentifier("screenRecording.restoreMedia." + asset.id.uuidString)
                    }
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
                }
                Text(model.timelineClipTitle(clip)).font(.system(size: 12, weight: .medium)).lineLimit(3)
                ScreenRecordingNumberField(title: AppLocalization.text("片段位置"), value: number(clip, \.start),
                    identifier: "screenRecording.clipStart")
                ScreenRecordingNumberField(title: AppLocalization.text("起点（秒）"), value: number(clip, \.sourceStart),
                    identifier: "screenRecording.clipSourceStart")
                ScreenRecordingNumberField(title: AppLocalization.text("终点（秒）"), value: number(clip, \.sourceEnd),
                    identifier: "screenRecording.clipSourceEnd")
                Text(AppLocalization.text("片段时长") + ": " + ScreenRecordingStudioView.clock(clip.duration))
                    .font(.caption).foregroundStyle(.secondary)
                if clip.content.trackKind == .video || clip.content.trackKind == .audio {
                    Picker(AppLocalization.text("播放速度"), selection: number(clip, \.speed)) {
                        ForEach([0.25, 0.5, 0.75, 1, 1.25, 1.5, 2, 4, 8], id: \.self) { speed in
                            Text(speed.formatted() + "×").tag(speed)
                        }
                    }
                    Toggle(AppLocalization.text("音频"), isOn: Binding(get: { model.selectedTimelineClip?.audioEnabled ?? clip.audioEnabled },
                        set: { enabled in model.updateTimelineClip(clip.id) { $0.audioEnabled = enabled } }))
                    ScreenRecordingParameterRow(title: AppLocalization.text("音量"), value: number(clip, \.volume),
                        range: 0...1, identifier: "screenRecording.clipVolume")
                    if clip.content.trackKind == .video {
                        Button(AppLocalization.text("分离音频")) { model.detachTimelineAudio(clip.id) }
                            .disabled(!clip.audioEnabled)
                            .accessibilityIdentifier("screenRecording.detachAudio")
                    }
                }
                Picker(AppLocalization.text("轨道"), selection: Binding(get: { clip.trackID },
                    set: { trackID in model.updateTimelineClip(clip.id) { $0.trackID = trackID } })) {
                    ForEach(Array((model.timeline?.tracks ?? []).enumerated()), id: \.element.id) { index, track in
                        Text(track.title(at: index)).tag(track.id)
                    }
                }
                .accessibilityIdentifier("screenRecording.clipTrack")
                if case let .annotation(id) = clip.content {
                    Button(AppLocalization.text("标注内容")) { canvasSelection.wrappedValue = .annotation(id) }
                } else if case let .caption(id) = clip.content {
                    Button(AppLocalization.text("字幕")) { canvasSelection.wrappedValue = .caption(id) }
                }
                Divider()
                HStack {
                    Button(AppLocalization.text("复制片段")) {
                        if let id = model.duplicateTimelineClip(clip.id) { model.selectTimelineClip(id) }
                    }
                    Spacer()
                    Button(AppLocalization.text("删除片段"), role: .destructive) { model.deleteTimelineClip(clip.id) }
                }
                .buttonStyle(.borderless)
                Button(AppLocalization.text("预览片段起点")) { model.selectTimelineClip(clip.id) }
                    .font(.caption)
            }
        }
    }

    private func number(_ clip: RecordingTimelineClip, _ keyPath: WritableKeyPath<RecordingTimelineClip, Double>) -> Binding<Double> {
        Binding(get: { model.timeline?.clips.first { $0.id == clip.id }?[keyPath: keyPath] ?? clip[keyPath: keyPath] },
            set: { value in model.updateTimelineClip(clip.id) { $0[keyPath: keyPath] = value } })
    }
}
