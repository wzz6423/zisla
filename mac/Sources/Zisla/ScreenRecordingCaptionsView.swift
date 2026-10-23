import SwiftUI
import ZislaCore

struct ScreenRecordingCaptionsView: View {
    @ObservedObject var model: ScreenRecordingStudioModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(AppLocalization.text("字幕在本机转写，不上传录音"))
                .font(.caption).foregroundStyle(.secondary)
            Picker(AppLocalization.text("识别语言"), selection: $model.subtitleLanguage) {
                ForEach(AppLanguage.allCases, id: \.self) { language in
                    Text(language.nativeDisplayName).tag(language)
                }
            }
            HStack {
                Button(AppLocalization.text("生成字幕"), action: model.generateCaptions)
                Button(AppLocalization.text("导出 SRT"), action: model.exportSubtitles)
            }
            Toggle(AppLocalization.text("在视频中显示字幕"), isOn: Binding(get: {
                model.project?.edits.showCaptions ?? true
            }, set: { value in model.update { $0.edits.showCaptions = value } }))
            Button(AppLocalization.text("添加字幕")) {
                model.update { project in
                    guard model.currentTime < project.duration else { return }
                    project.captions.append(.init(start: model.currentTime,
                        end: min(project.duration, model.currentTime + 2), text: AppLocalization.text("新字幕")))
                }
            }
            if let project = model.project {
                ForEach(project.captions) { caption in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Button(ScreenRecordingStudioView.clock(caption.start)) { model.seek(to: caption.start) }
                            Spacer()
                            Button(role: .destructive) {
                                model.update { $0.captions.removeAll { $0.id == caption.id } }
                            } label: { Image(systemName: "trash") }.help(AppLocalization.text("删除字幕"))
                        }
                        HStack {
                            timeField("起点（秒）", id: caption.id, keyPath: \.start)
                            timeField("终点（秒）", id: caption.id, keyPath: \.end)
                        }
                        TextField(AppLocalization.text("字幕内容"), text: captionBinding(caption.id, keyPath: \.text, default: ""), axis: .vertical)
                            .textFieldStyle(.roundedBorder).lineLimit(2...5)
                        Button(AppLocalization.text("删除字幕对应片段")) {
                            model.cut(start: caption.start, end: caption.end)
                        }.font(.caption)
                    }.padding(10).background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
                }
            }
            Text(AppLocalization.text("转写时间可能需要校正，可编辑字幕内容和起止时间"))
                .font(.caption).foregroundStyle(.secondary)
        }.disabled(!model.canEdit)
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
        VStack(alignment: .leading, spacing: 4) {
            Text(AppLocalization.text(title)).font(.caption)
            TextField(AppLocalization.text(title), value: captionBinding(id, keyPath: keyPath, default: 0),
                      format: .number.precision(.fractionLength(0...3))).textFieldStyle(.roundedBorder)
        }
    }
}
