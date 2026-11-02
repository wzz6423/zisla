import SwiftUI
import ZislaCore

struct ScreenRecordingCaptionsView: View {
    @ObservedObject var model: ScreenRecordingStudioModel
    @Environment(\.recordingCanvasSelection) private var canvasSelection
    @State private var expandedCaptionID: UUID?
    @State private var sectionExpanded = true

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ScreenRecordingInspectorSection(AppLocalization.text("生成字幕"), symbol: "waveform") {
                Picker(AppLocalization.text("识别语言"), selection: $model.subtitleLanguage) {
                    ForEach(AppLanguage.allCases, id: \.self) { language in
                        Text(language.nativeDisplayName).tag(language)
                    }
                }
                .controlSize(.regular)
            } actions: {
                ViewThatFits(in: .horizontal) {
                    HStack { generateButton; exportButton }
                    VStack(alignment: .leading, spacing: 6) { generateButton; exportButton }
                }
            }
            ScreenRecordingInspectorSection(AppLocalization.text("字幕"), symbol: "captions.bubble", isExpanded: $sectionExpanded) {
                Toggle(AppLocalization.text("在视频中显示字幕"), isOn: Binding(get: {
                    model.project?.edits.showCaptions ?? true
                }, set: { value in model.update { $0.edits.showCaptions = value } }))
                LazyVStack(alignment: .leading, spacing: 12) {
                    ForEach(model.project?.captions ?? []) { caption in
                        DisclosureGroup(isExpanded: Binding(get: { expandedCaptionID == caption.id }, set: {
                            expandedCaptionID = $0 ? caption.id : nil
                            if $0 { canvasSelection.wrappedValue = .caption(caption.id); model.seekOverlay(.caption(caption.id), sourceStart: caption.start) }
                        })) {
                            VStack(alignment: .leading, spacing: 10) {
                                HStack {
                                    Button(ScreenRecordingStudioView.clock(caption.start)) { model.seekOverlay(.caption(caption.id), sourceStart: caption.start) }
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
                                    model.cutCaption(caption.id)
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
            } actions: {
                Button(AppLocalization.text("添加字幕")) {
                    if let id = model.addOverlayCaption() {
                        expandedCaptionID = id
                        canvasSelection.wrappedValue = .caption(id)
                    }
                }.buttonStyle(SettingsTintedButtonStyle())
                    .accessibilityIdentifier("screenRecording.addCaption")
            }
        }.disabled(!model.canEdit)
        .onChange(of: canvasSelection.wrappedValue, initial: true) { _, selection in
            if case let .caption(id) = selection { expandedCaptionID = id; sectionExpanded = true }
        }
    }

    private var generateButton: some View {
        Button(AppLocalization.text("生成字幕"), action: model.generateCaptions).buttonStyle(SettingsTintedButtonStyle())
            .disabled(!model.canGenerateCaptions)
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
