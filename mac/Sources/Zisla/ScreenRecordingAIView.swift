import SwiftUI
import ZislaCore
import ZislaKit

struct ScreenRecordingAIView: View {
    @ObservedObject var model: ScreenRecordingStudioModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ScreenRecordingInspectorSection(AppLocalization.text("剪辑指令"), symbol: "sparkles") {
                Picker(AppLocalization.text("使用模型"), selection: $model.selectedAIModel) {
                    Text(AppLocalization.text("选择 AI 模型")).tag(Optional<AIModelConfigurationReference>.none)
                    ForEach(model.aiModels, id: \.reference) { entry in
                        Text(entry.title).tag(Optional(entry.reference))
                    }
                }
                .controlSize(.regular)
                TextEditor(text: $model.aiInstruction)
                    .font(.system(size: 12)).scrollContentBackground(.hidden)
                    .padding(6).frame(height: 110)
                    .background(Color.fillControl, in: RoundedRectangle(cornerRadius: 6))
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.dividerSubtle, lineWidth: 1))
                    .accessibilityLabel(AppLocalization.text("剪辑指令"))
                    .accessibilityIdentifier("screenRecording.aiInstruction")
            } actions: {
                Button(AppLocalization.text("生成剪辑方案"), action: model.requestAIEdit)
                    .buttonStyle(SettingsTintedButtonStyle())
                    .accessibilityIdentifier("screenRecording.generateAIEdit")
                    .disabled(!model.canEdit || model.selectedAIModel == nil || model.aiInstruction.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            if let pending = model.pendingAIProject {
                ScreenRecordingInspectorSection(AppLocalization.text("方案预览"), symbol: "checkmark.rectangle") {
                    Text(AppLocalization.text("输出时长：%@", ScreenRecordingStudioView.clock(pending.outputDuration)))
                        .font(.system(size: 12, weight: .medium))
                    Text(AppLocalization.text("片段 %d · 缩放 %d · 字幕 %d", pending.edits.segments.count,
                        pending.edits.zoomClips.count, pending.captions.count)).font(.caption)
                    Text(AppLocalization.text(pending.edits.background.title)).font(.caption).foregroundStyle(.secondary)
                } actions: {
                    ViewThatFits(in: .horizontal) {
                        HStack { applyButton; dismissButton }
                        VStack(alignment: .leading, spacing: 6) { applyButton; dismissButton }
                    }.disabled(!model.canEdit)
                }
            }
        }
    }

    private var applyButton: some View {
        Button(AppLocalization.text("应用方案"), action: model.applyAIEdit).buttonStyle(SettingsTintedButtonStyle())
    }

    private var dismissButton: some View {
        Button(AppLocalization.text("放弃方案"), action: model.dismissAIEdit)
    }
}
