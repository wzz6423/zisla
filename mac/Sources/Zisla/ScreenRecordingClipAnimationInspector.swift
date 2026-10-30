import SwiftUI
import ZislaCore

struct ScreenRecordingClipAnimationInspector: View {
    @ObservedObject var model: ScreenRecordingStudioModel
    let clip: RecordingTimelineClip

    var body: some View {
        ScreenRecordingInspectorSection(AppLocalization.text("动画"), symbol: "rectangle.stack") {
            animationPicker(title: AppLocalization.text("入场动画"), keyPath: \.entranceAnimation,
                kinds: RecordingClipAnimationKind.allCases.filter { $0 != .typewriter || isText },
                identifier: "screenRecording.entranceAnimation", entrance: true)
            animationPicker(title: AppLocalization.text("出场动画"), keyPath: \.exitAnimation,
                kinds: RecordingClipAnimationKind.allCases.filter { $0 != .typewriter },
                identifier: "screenRecording.exitAnimation", entrance: false)
            Picker(AppLocalization.text("转场"), selection: transitionKind) {
                Text(AppLocalization.text("无")).tag(nil as RecordingClipTransitionKind?)
                ForEach(RecordingClipTransitionKind.allCases, id: \.self) { kind in
                    Text(AppLocalization.text(kind.title)).tag(Optional(kind))
                }
            }
            .accessibilityIdentifier("screenRecording.clipTransition")
            .disabled(transitionSource == nil && currentClip.transition == nil)
            if let transition = currentClip.transition {
                ScreenRecordingParameterRow(title: AppLocalization.text("转场时长（秒）"), value: Binding(
                    get: { currentClip.transition?.duration ?? transition.duration },
                    set: { duration in model.updateTimelineClip(clip.id) { $0.transition?.duration = duration } }),
                    range: 0.01...30, identifier: "screenRecording.transitionDuration")
            }
            if transitionSource == nil {
                Text(AppLocalization.text("转场需要与同轨前一片段重叠"))
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("screenRecording.transitionOverlapNotice")
            }
        }
    }

    private var currentClip: RecordingTimelineClip {
        model.timeline?.clips.first { $0.id == clip.id } ?? clip
    }

    private var isText: Bool {
        switch clip.content {
        case let .annotation(id): model.project?.edits.annotations?.first { $0.id == id }?.kind == .text
        case .caption: true
        default: false
        }
    }

    private var transitionSource: RecordingTimelineClip? { model.timeline?.transitionSources()[clip.id] }

    var transitionKind: Binding<RecordingClipTransitionKind?> {
        Binding(get: { currentClip.transition?.kind },
            set: { kind in model.updateTimelineClip(clip.id) { value in
                value.transition = kind.map { .init(kind: $0, duration: value.transition?.duration ?? 0.5) }
            } })
    }

    func animationKind(_ keyPath: WritableKeyPath<RecordingTimelineClip, RecordingClipAnimation?>)
        -> Binding<RecordingClipAnimationKind?> {
        Binding(get: { currentClip[keyPath: keyPath]?.kind },
            set: { kind in model.updateTimelineClip(clip.id) { value in
                value[keyPath: keyPath] = kind.map { .init(kind: $0, duration: value[keyPath: keyPath]?.duration ?? 0.5) }
            } })
    }

    func animationDuration(_ keyPath: WritableKeyPath<RecordingTimelineClip, RecordingClipAnimation?>,
                           current: RecordingClipAnimation) -> Binding<Double> {
        Binding(get: { currentClip[keyPath: keyPath]?.duration ?? current.duration },
            set: { duration in model.updateTimelineClip(clip.id) { $0[keyPath: keyPath]?.duration = duration } })
    }

    @ViewBuilder
    private func animationPicker(title: String, keyPath: WritableKeyPath<RecordingTimelineClip, RecordingClipAnimation?>,
                                 kinds: [RecordingClipAnimationKind], identifier: String, entrance: Bool) -> some View {
        Picker(title, selection: animationKind(keyPath)) {
            Text(AppLocalization.text("无")).tag(nil as RecordingClipAnimationKind?)
            ForEach(kinds, id: \.self) { kind in
                Text(AppLocalization.text(entrance ? kind.entranceTitle : kind.exitTitle)).tag(Optional(kind))
            }
        }
        .accessibilityIdentifier(identifier)
        if let animation = currentClip[keyPath: keyPath] {
            ScreenRecordingParameterRow(title: AppLocalization.text(entrance ? "入场时长（秒）" : "出场时长（秒）"),
                value: animationDuration(keyPath, current: animation),
                range: 0.01...30, identifier: identifier + ".duration")
        }
    }
}
