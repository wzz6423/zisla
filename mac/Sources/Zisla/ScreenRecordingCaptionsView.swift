import SwiftUI
import ZislaCore

struct ScreenRecordingCaptionsView: View {
    @ObservedObject var model: ScreenRecordingStudioModel
    @State private var expandedCaptionID: UUID?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ScreenRecordingInspectorSection(AppLocalization.text("生成字幕"), symbol: "waveform") {
                Picker(AppLocalization.text("识别语言"), selection: $model.subtitleLanguage) {
                    ForEach(AppLanguage.allCases, id: \.self) { language in
                        Text(language.nativeDisplayName).tag(language)
                    }
                }
                ViewThatFits(in: .horizontal) {
                    HStack { generateButton; exportButton }
                    VStack(alignment: .leading, spacing: 6) { generateButton; exportButton }
                }
                Text(AppLocalization.text("字幕在本机转写，不上传录音"))
                    .font(.system(size: 10)).foregroundStyle(.secondary)
            }
            ScreenRecordingInspectorSection(AppLocalization.text("字幕"), symbol: "captions.bubble") {
                Toggle(AppLocalization.text("在视频中显示字幕"), isOn: Binding(get: {
                    model.project?.edits.showCaptions ?? true
                }, set: { value in model.update { $0.edits.showCaptions = value } }))
                Button(AppLocalization.text("添加字幕")) {
                    model.update { project in
                        guard model.currentTime < project.duration else { return }
                        let caption = RecordingCaption(start: model.currentTime,
                            end: min(project.duration, model.currentTime + 2), text: AppLocalization.text("新字幕"))
                        project.captions.append(caption)
                        expandedCaptionID = caption.id
                    }
                }.buttonStyle(SettingsTintedButtonStyle())
                LazyVStack(alignment: .leading, spacing: 12) {
                    ForEach(model.project?.captions ?? []) { caption in
                        DisclosureGroup(isExpanded: Binding(get: { expandedCaptionID == caption.id }, set: {
                            expandedCaptionID = $0 ? caption.id : nil
                        })) {
                            VStack(alignment: .leading, spacing: 10) {
                                HStack {
                                    Button(ScreenRecordingStudioView.clock(caption.start)) { model.seek(to: caption.start) }
                                    Spacer()
                                    Button(role: .destructive) {
                                        model.update { $0.captions.removeAll { $0.id == caption.id } }
                                    } label: { Image(systemName: "trash") }.help(AppLocalization.text("删除字幕"))
                                }.buttonStyle(.borderless)
                                timeField("起点（秒）", id: caption.id, keyPath: \.start)
                                timeField("终点（秒）", id: caption.id, keyPath: \.end)
                                TextField(AppLocalization.text("字幕内容"), text: captionBinding(caption.id, keyPath: \.text, default: ""), axis: .vertical)
                                    .textFieldStyle(.roundedBorder).lineLimit(2...5)
                                    .accessibilityIdentifier("screenRecording.captionText." + caption.id.uuidString)
                                Button(AppLocalization.text("删除字幕对应片段")) {
                                    model.cut(start: caption.start, end: caption.end)
                                }.font(.caption)
                            }.padding(.top, 10)
                        } label: {
                            HStack(spacing: 8) {
                                Text(ScreenRecordingStudioView.clock(caption.start)).monospacedDigit().fixedSize()
                                Text(caption.text).lineLimit(1).foregroundStyle(.secondary)
                            }.font(.system(size: 11))
                        }
                        .accessibilityIdentifier("screenRecording.caption." + caption.id.uuidString)
                    }
                }
                Text(AppLocalization.text("转写时间可能需要校正，可编辑字幕内容和起止时间"))
                    .font(.system(size: 10)).foregroundStyle(.secondary)
            }
        }.disabled(!model.canEdit)
    }

    private var generateButton: some View {
        Button(AppLocalization.text("生成字幕"), action: model.generateCaptions).buttonStyle(SettingsTintedButtonStyle())
    }

    private var exportButton: some View {
        Button(AppLocalization.text("导出 SRT"), action: model.exportSubtitles)
    }

    private func captionBinding<Value>(_ id: UUID, keyPath: WritableKeyPath<RecordingCaption, Value>, default value: Value) -> Binding<Value> {
        Binding(get: { model.project?.captions.first(where: { $0.id == id })?[keyPath: keyPath] ?? value },
                set: { value in model.update { project in
                    if let index = project.captions.firstIndex(where: { $0.id == id }) {
                        project.captions[index][keyPath: keyPath] = value
                    }
                } })
    }

    private func timeField(_ title: String, id: UUID, keyPath: WritableKeyPath<RecordingCaption, Double>) -> some View {
        ScreenRecordingNumberField(title: AppLocalization.text(title), value: captionBinding(id, keyPath: keyPath, default: 0),
            identifier: "screenRecording.captionField." + id.uuidString + "." + title)
    }
}
