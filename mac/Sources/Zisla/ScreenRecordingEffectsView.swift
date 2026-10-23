import SwiftUI
import ZislaCore

struct ScreenRecordingEffectsView: View {
    @ObservedObject var model: ScreenRecordingStudioModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Picker(AppLocalization.text("背景"), selection: editBinding(\.background, default: .gradient)) {
                ForEach(RecordingBackground.allCases, id: \.self) { value in
                    Text(AppLocalization.text(value.title)).tag(value)
                }
            }
            parameter("留白", value: editBinding(\.padding, default: 0.06), in: 0...0.3)
            parameter("圆角", value: editBinding(\.cornerRadius, default: 0.02), in: 0...0.2)
            parameter("阴影", value: editBinding(\.shadow, default: 0.3), in: 0...1)
            Toggle(AppLocalization.text("显示鼠标"), isOn: editBinding(\.showCursor, default: true))
            parameter("鼠标大小", value: editBinding(\.cursorSize, default: 1.5), in: 0.5...4)
            Toggle(AppLocalization.text("点击效果"), isOn: editBinding(\.clickEffects, default: true))
            Toggle(AppLocalization.text("自动缩放"), isOn: editBinding(\.autoZoom, default: false))
            Divider()
            Text(AppLocalization.text("裁切画面")).font(.headline)
            Toggle(AppLocalization.text("启用裁切"), isOn: Binding(get: { model.project?.edits.crop != nil }, set: { value in
                model.update { $0.edits.crop = value ? .init(x: 0, y: 0, width: 1, height: 1) : nil }
            }))
            if model.project?.edits.crop != nil {
                HStack {
                    cropField("左边距", keyPath: \.x)
                    cropField("上边距", keyPath: \.y)
                }
                HStack {
                    cropField("宽度比例", keyPath: \.width)
                    cropField("高度比例", keyPath: \.height)
                }
            }
            Divider()
            HStack {
                Text(AppLocalization.text("手动缩放")).font(.headline)
                Spacer()
                Button(AppLocalization.text("添加缩放")) {
                    model.update { project in
                        guard model.currentTime < project.duration else { return }
                        project.edits.zoomClips.append(.init(time: model.currentTime,
                            duration: min(2, project.duration - model.currentTime)))
                    }
                }
            }
            if let project = model.project {
                ForEach(project.edits.zoomClips) { zoom in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Button(ScreenRecordingStudioView.clock(zoom.time)) { model.seek(to: zoom.time) }
                            Spacer()
                            Button(role: .destructive) {
                                model.update { $0.edits.zoomClips.removeAll { $0.id == zoom.id } }
                            } label: { Image(systemName: "trash") }.help(AppLocalization.text("删除缩放"))
                        }
                        HStack {
                            zoomField("起点（秒）", id: zoom.id, keyPath: \.time)
                            zoomField("时长（秒）", id: zoom.id, keyPath: \.duration)
                        }
                        parameter("缩放倍率", value: zoomBinding(zoom.id, keyPath: \.scale), in: 1...5)
                        parameter("焦点水平位置", value: zoomBinding(zoom.id, keyPath: \.x), in: 0...1)
                        parameter("焦点垂直位置", value: zoomBinding(zoom.id, keyPath: \.y), in: 0...1)
                    }.padding(10).background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
                }
                if project.cameraFile != nil {
                    Divider()
                    Text(AppLocalization.text("摄像头叠加")).font(.headline)
                    Picker(AppLocalization.text("摄像头位置"), selection: editBinding(\.cameraPosition, default: .bottomRight)) {
                        ForEach(RecordingCameraPosition.allCases, id: \.self) { position in
                            Text(AppLocalization.text(position.title)).tag(position)
                        }
                    }
                    parameter("摄像头大小", value: editBinding(\.cameraSize, default: 0.25), in: 0.1...0.5)
                    Toggle(AppLocalization.text("镜像摄像头"), isOn: editBinding(\.cameraMirrored, default: true))
                    Toggle(AppLocalization.text("圆形摄像头"), isOn: editBinding(\.cameraRound, default: true))
                }
            }
        }.disabled(!model.canEdit)
    }

    private func editBinding<Value>(_ path: WritableKeyPath<RecordingEdits, Value>, default value: Value) -> Binding<Value> {
        Binding(get: { model.project?.edits[keyPath: path] ?? value },
                set: { value in model.update { $0.edits[keyPath: path] = value } })
    }

    private func parameter(_ title: String, value: Binding<Double>, in range: ClosedRange<Double>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(AppLocalization.text(title)).font(.caption)
                Spacer()
                Text(value.wrappedValue.formatted(.number.precision(.fractionLength(2)))).font(.caption.monospacedDigit())
            }
            Slider(value: value, in: range)
        }
    }

    private func cropField(_ title: String, keyPath: WritableKeyPath<RecordingRect, Double>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(AppLocalization.text(title)).font(.caption)
            TextField(AppLocalization.text(title), value: Binding(get: {
                model.project?.edits.crop?[keyPath: keyPath] ?? 0
            }, set: { value in model.update { $0.edits.crop?[keyPath: keyPath] = value } }),
                      format: .number.precision(.fractionLength(0...3))).textFieldStyle(.roundedBorder)
        }
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
        VStack(alignment: .leading, spacing: 4) {
            Text(AppLocalization.text(title)).font(.caption)
            TextField(AppLocalization.text(title), value: zoomBinding(id, keyPath: keyPath),
                      format: .number.precision(.fractionLength(0...3))).textFieldStyle(.roundedBorder)
        }
    }
}
