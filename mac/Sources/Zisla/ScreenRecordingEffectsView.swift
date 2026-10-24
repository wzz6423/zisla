import SwiftUI
import ZislaCore

struct ScreenRecordingEffectsView: View {
    @ObservedObject var model: ScreenRecordingStudioModel
    @State private var expandedZoomID: UUID?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ScreenRecordingInspectorSection(AppLocalization.text("画布"), symbol: "rectangle.on.rectangle") {
                Picker(AppLocalization.text("画布比例"), selection: optionalEditBinding(\.canvasAspectRatio, default: .original)) {
                    ForEach(RecordingCanvasAspectRatio.allCases, id: \.self) { value in
                        Text(AppLocalization.text(value.title)).tag(value)
                    }
                }
                Picker(AppLocalization.text("背景"), selection: editBinding(\.background, default: .gradient)) {
                    ForEach(RecordingBackground.allCases, id: \.self) { value in
                        Text(AppLocalization.text(value.title)).tag(value)
                    }
                }
                Toggle(AppLocalization.text("自定义背景颜色"), isOn: Binding(get: { model.project?.edits.backgroundColor != nil },
                    set: { enabled in model.update { $0.edits.backgroundColor = enabled ? .background : nil } }))
                if model.project?.edits.backgroundColor != nil {
                    ScreenRecordingColorPicker(title: "背景颜色", selection: optionalEditBinding(\.backgroundColor, default: .background))
                }
                parameter("留白", value: editBinding(\.padding, default: 0.06), in: 0...0.3)
                parameter("圆角", value: editBinding(\.cornerRadius, default: 0.02), in: 0...0.2)
                parameter("阴影", value: editBinding(\.shadow, default: 0.3), in: 0...1)
            }
            ScreenRecordingInspectorSection(AppLocalization.text("光标"), symbol: "cursorarrow", expanded: false) {
                Toggle(AppLocalization.text("显示鼠标"), isOn: editBinding(\.showCursor, default: true))
                parameter("鼠标大小", value: editBinding(\.cursorSize, default: 1.5), in: 0.5...4)
                Toggle(AppLocalization.text("点击效果"), isOn: editBinding(\.clickEffects, default: true))
                Toggle(AppLocalization.text("自动缩放"), isOn: editBinding(\.autoZoom, default: false))
            }
            ScreenRecordingInspectorSection(AppLocalization.text("裁切画面"), symbol: "crop", expanded: false) {
                Toggle(AppLocalization.text("启用裁切"), isOn: Binding(get: { model.project?.edits.crop != nil }, set: { value in
                    model.update { $0.edits.crop = value ? .init(x: 0, y: 0, width: 1, height: 1) : nil }
                }))
                if model.project?.edits.crop != nil {
                    cropField("左边距", keyPath: \.x)
                    cropField("上边距", keyPath: \.y)
                    cropField("宽度比例", keyPath: \.width)
                    cropField("高度比例", keyPath: \.height)
                }
            }
            ScreenRecordingInspectorSection(AppLocalization.text("手动缩放"), symbol: "plus.magnifyingglass", expanded: false) {
                Button(AppLocalization.text("添加缩放")) {
                    model.update { project in
                        guard model.currentTime < project.duration else { return }
                        let zoom = RecordingZoom(time: model.currentTime, duration: min(2, project.duration - model.currentTime))
                        project.edits.zoomClips.append(zoom)
                        expandedZoomID = zoom.id
                    }
                }.buttonStyle(SettingsTintedButtonStyle())
                LazyVStack(alignment: .leading, spacing: 12) {
                    ForEach(model.project?.edits.zoomClips ?? []) { zoom in
                        DisclosureGroup(isExpanded: Binding(get: { expandedZoomID == zoom.id }, set: {
                            expandedZoomID = $0 ? zoom.id : nil
                        })) {
                            VStack(alignment: .leading, spacing: 10) {
                                zoomField("起点（秒）", id: zoom.id, keyPath: \.time)
                                zoomField("时长（秒）", id: zoom.id, keyPath: \.duration)
                                parameter("缩放倍率", value: zoomBinding(zoom.id, keyPath: \.scale), in: 1...5)
                                parameter("焦点水平位置", value: zoomBinding(zoom.id, keyPath: \.x), in: 0...1)
                                parameter("焦点垂直位置", value: zoomBinding(zoom.id, keyPath: \.y), in: 0...1)
                                HStack {
                                    Button(ScreenRecordingStudioView.clock(zoom.time)) { model.seek(to: zoom.time) }
                                    Spacer()
                                    Button(role: .destructive) {
                                        model.update { $0.edits.zoomClips.removeAll { $0.id == zoom.id } }
                                    } label: { Image(systemName: "trash") }.help(AppLocalization.text("删除缩放"))
                                }.buttonStyle(.borderless)
                            }.padding(.top, 10)
                        } label: {
                            Text(ScreenRecordingStudioView.clock(zoom.time) + " · " + zoom.scale.formatted() + "×")
                                .font(.system(size: 11, design: .monospaced))
                        }
                        .accessibilityIdentifier("screenRecording.zoom." + zoom.id.uuidString)
                    }
                }
            }
            ScreenRecordingInspectorSection(AppLocalization.text("音频"), symbol: "speaker.wave.2", expanded: false) {
                audioParameter("系统声音音量", value: optionalEditBinding(\.screenAudioVolume, default: 1))
                if model.project?.microphoneFile != nil {
                    audioParameter("麦克风音量", value: optionalEditBinding(\.microphoneVolume, default: 1))
                }
            }
            if let project = model.project, project.cameraFile != nil {
                ScreenRecordingInspectorSection(AppLocalization.text("摄像头叠加"), symbol: "web.camera", expanded: false) {
                    Toggle(AppLocalization.text("显示摄像头"), isOn: optionalEditBinding(\.showCamera, default: true))
                    Picker(AppLocalization.text("摄像头位置"), selection: editBinding(\.cameraPosition, default: .bottomRight)) {
                        ForEach(RecordingCameraPosition.allCases, id: \.self) { position in
                            Text(AppLocalization.text(position.title)).tag(position)
                        }
                    }
                    parameter("摄像头大小", value: editBinding(\.cameraSize, default: 0.25), in: 0.1...0.5)
                    Toggle(AppLocalization.text("镜像摄像头"), isOn: editBinding(\.cameraMirrored, default: true))
                    Toggle(AppLocalization.text("圆形摄像头"), isOn: editBinding(\.cameraRound, default: true))
                    if !project.edits.cameraRound {
                        parameter("圆角", value: Binding(get: { model.project?.edits.cameraCornerRadius ?? 0.1 },
                            set: { value in model.update { $0.edits.cameraCornerRadius = value } }), in: 0...0.5)
                    }
                }
            }
            ScreenRecordingAnnotationsView(model: model)
        }.disabled(!model.canEdit)
    }

    private func editBinding<Value>(_ path: WritableKeyPath<RecordingEdits, Value>, default value: Value) -> Binding<Value> {
        Binding(get: { model.project?.edits[keyPath: path] ?? value },
                set: { value in model.update { $0.edits[keyPath: path] = value } })
    }

    private func optionalEditBinding<Value>(_ path: WritableKeyPath<RecordingEdits, Value?>, default value: Value) -> Binding<Value> {
        Binding(get: { model.project?.edits[keyPath: path] ?? value },
                set: { value in model.update { $0.edits[keyPath: path] = value } })
    }

    private func audioParameter(_ title: String, value: Binding<Double>) -> some View {
        HStack {
            parameter(title, value: value, in: 0...1)
            Button {
                value.wrappedValue = value.wrappedValue == 0 ? 1 : 0
            } label: {
                Image(systemName: value.wrappedValue == 0 ? "speaker.slash.fill" : "speaker.wave.2.fill")
            }
            .help(AppLocalization.text(value.wrappedValue == 0 ? "取消静音" : "静音"))
            .accessibilityLabel(AppLocalization.text(title) + " · "
                + AppLocalization.text(value.wrappedValue == 0 ? "取消静音" : "静音"))
        }
    }

    private func parameter(_ title: String, value: Binding<Double>, in range: ClosedRange<Double>) -> some View {
        ScreenRecordingParameterRow(title: AppLocalization.text(title), value: value, range: range,
            identifier: "screenRecording.effect." + title)
    }

    private func cropField(_ title: String, keyPath: WritableKeyPath<RecordingRect, Double>) -> some View {
        ScreenRecordingNumberField(title: AppLocalization.text(title), value: Binding(get: {
            model.project?.edits.crop?[keyPath: keyPath] ?? 0
        }, set: { value in model.update { $0.edits.crop?[keyPath: keyPath] = value } }),
            identifier: "screenRecording.crop." + title)
    }

    private func zoomBinding(_ id: UUID, keyPath: WritableKeyPath<RecordingZoom, Double>) -> Binding<Double> {
        Binding(get: { model.project?.edits.zoomClips.first(where: { $0.id == id })?[keyPath: keyPath] ?? 0 },
                set: { value in model.update { project in
                    if let index = project.edits.zoomClips.firstIndex(where: { $0.id == id }) {
                        project.edits.zoomClips[index][keyPath: keyPath] = value
                    }
                } })
    }

    private func zoomField(_ title: String, id: UUID, keyPath: WritableKeyPath<RecordingZoom, Double>) -> some View {
        ScreenRecordingNumberField(title: AppLocalization.text(title), value: zoomBinding(id, keyPath: keyPath),
            identifier: "screenRecording.zoomField." + id.uuidString + "." + title)
    }
}
