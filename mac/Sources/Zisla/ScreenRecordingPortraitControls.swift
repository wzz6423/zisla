import SwiftUI
import ZislaCore

struct ScreenRecordingPortraitControls: View {
    enum Target {
        case capture, recording, clip(String)
    }

    @ObservedObject var model: ScreenRecordingStudioModel
    let target: Target
    let showsPortrait: Bool
    let showsVoice: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if showsPortrait {
                parameter("磨皮", path: \.smoothing, identifier: "smoothing")
                parameter("提亮", path: \.brightening, identifier: "brightening")
                parameter("瘦脸", path: \.faceSlimming, identifier: "faceSlimming")
                parameter("瘦身", path: \.bodySlimming, identifier: "bodySlimming")
            }
            if showsVoice {
                Picker(AppLocalization.text("美声"), selection: Binding(get: { voice.preset }, set: { preset in
                    var effects = voice
                    effects.preset = preset
                    setVoice(effects)
                })) {
                    ForEach(RecordingVoicePreset.allCases, id: \.self) { preset in
                        Text(AppLocalization.text(preset.title)).tag(preset)
                    }
                }
                .accessibilityIdentifier("screenRecording.voicePreset")
                if voice.preset != .original {
                    ScreenRecordingParameterRow(title: AppLocalization.text("效果强度"), value: Binding(
                        get: { voice.amount }, set: { amount in
                            var effects = voice
                            effects.amount = amount
                            setVoice(effects)
                        }), range: 0...1, identifier: "screenRecording.voiceAmount")
                }
                if case .capture = target {
                    Toggle(AppLocalization.text("监听麦克风"), isOn: $model.configuration.monitorMicrophone)
                        .help(AppLocalization.text("使用耳机监听以避免回声"))
                        .accessibilityIdentifier("screenRecording.monitorMicrophone")
                }
            }
            Button(AppLocalization.text("恢复原始效果")) {
                if showsPortrait { setPortrait(.init()) }
                if showsVoice { setVoice(.init()) }
            }
            .accessibilityIdentifier("screenRecording.resetPortraitEffects")
            .disabled(!(showsPortrait && portrait.isEnabled) && !(showsVoice && voice.isEnabled))
        }
        .disabled(isDisabled)
    }

    var portrait: RecordingPortraitEffects {
        switch target {
        case .capture: model.configuration.portraitEffects
        case .recording: model.project?.edits.portraitEffects ?? .init()
        case let .clip(id): model.timeline?.clips.first { $0.id == id }?.portraitEffects
            ?? (isRecordingClip(id) ? model.project?.edits.portraitEffects : nil) ?? .init()
        }
    }

    var voice: RecordingVoiceEffects {
        switch target {
        case .capture: model.configuration.voiceEffects
        case .recording: model.project?.edits.voiceEffects ?? .init()
        case let .clip(id): model.timeline?.clips.first { $0.id == id }?.voiceEffects
            ?? (isRecordingClip(id) ? model.project?.edits.voiceEffects : nil) ?? .init()
        }
    }

    func setPortrait(_ effects: RecordingPortraitEffects) {
        switch target {
        case .capture:
            guard !isDisabled, effects.isValid else { return }
            model.configuration.portraitEffects = effects
            model.capture.setPortraitEffects(effects)
        case .recording: model.update { $0.edits.portraitEffects = effects }
        case let .clip(id): model.updateTimelineClip(id) { $0.portraitEffects = effects }
        }
    }

    func setVoice(_ effects: RecordingVoiceEffects) {
        switch target {
        case .capture:
            guard !isDisabled, effects.isValid else { return }
            model.configuration.voiceEffects = effects
        case .recording: model.update { $0.edits.voiceEffects = effects }
        case let .clip(id): model.updateTimelineClip(id) { $0.voiceEffects = effects }
        }
    }

    private var isDisabled: Bool {
        switch target {
        case .capture: model.isRecording || model.isBusy || model.isChoosingFile || model.exporter.isExporting
        default: !model.canEdit
        }
    }

    private func isRecordingClip(_ id: String) -> Bool {
        if case .recording = model.timeline?.clips.first(where: { $0.id == id })?.content { return true }
        return false
    }

    private func parameter(_ title: String, path: WritableKeyPath<RecordingPortraitEffects, Double>, identifier: String) -> some View {
        ScreenRecordingParameterRow(title: AppLocalization.text(title), value: Binding(get: { portrait[keyPath: path] },
            set: { value in
                var effects = portrait
                effects[keyPath: path] = value
                setPortrait(effects)
            }), range: 0...1, identifier: "screenRecording.portrait." + identifier)
    }
}
