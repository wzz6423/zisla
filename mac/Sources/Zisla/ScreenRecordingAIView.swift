import SwiftUI
import ZislaCore
import ZislaKit

struct ScreenRecordingAIView: View {
    @ObservedObject var model: ScreenRecordingStudioModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(AppLocalization.text("仅在生成方案时发送指令和部分字幕，原始视频留在本机"))
                .font(.caption).foregroundStyle(.secondary)
            Picker(AppLocalization.text("使用模型"), selection: $model.selectedAIModel) {
                Text(AppLocalization.text("选择 AI 模型")).tag(Optional<AIModelConfigurationReference>.none)
                ForEach(model.aiModels, id: \.reference) { entry in
                    Text(entry.title).tag(Optional(entry.reference))
                }
            }
            TextEditor(text: $model.aiInstruction)
                .font(.body).frame(minHeight: 100).border(.quaternary)
                .accessibilityLabel(AppLocalization.text("剪辑指令"))
            Text(AppLocalization.text("例如：删除 2 到 4 秒，将开场加速，并添加缩放"))
                .font(.caption).foregroundStyle(.secondary)
            Button(AppLocalization.text("生成剪辑方案"), action: model.requestAIEdit)
                .disabled(!model.canEdit || model.selectedAIModel == nil || model.aiInstruction.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            if let pending = model.pendingAIProject {
                Divider()
                Text(AppLocalization.text("方案预览")).font(.headline)
                Text(AppLocalization.text("输出时长：%@", ScreenRecordingStudioView.clock(pending.outputDuration)))
                Text(AppLocalization.text("片段 %d · 缩放 %d · 字幕 %d", pending.edits.segments.count,
                    pending.edits.zoomClips.count, pending.captions.count)).font(.caption)
                Text(AppLocalization.text(pending.edits.background.title)).font(.caption)
                HStack {
                    Button(AppLocalization.text("应用方案"), action: model.applyAIEdit).buttonStyle(.borderedProminent)
                    Button(AppLocalization.text("放弃方案"), action: model.dismissAIEdit)
                }.disabled(!model.canEdit)
            }
        }
    }
}
