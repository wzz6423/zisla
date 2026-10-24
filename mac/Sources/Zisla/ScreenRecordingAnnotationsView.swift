import AppKit
import SwiftUI
import ZislaCore

struct ScreenRecordingColorPicker: View {
    let title: String
    @Binding var selection: RecordingColor

    var body: some View {
        ColorPicker(AppLocalization.text(title), selection: Binding(get: {
            Color(red: selection.red, green: selection.green, blue: selection.blue)
        }, set: { color in
            if let components = Self.components(for: NSColor(color)) { selection = components }
        }), supportsOpacity: false)
    }

    static func components(for color: NSColor) -> RecordingColor? {
        guard let rgb = color.usingColorSpace(.sRGB) else { return nil }
        return RecordingColor(red: min(1, max(0, rgb.redComponent)),
                              green: min(1, max(0, rgb.greenComponent)),
                              blue: min(1, max(0, rgb.blueComponent)))
    }
}

struct ScreenRecordingAnnotationsView: View {
    @ObservedObject var model: ScreenRecordingStudioModel
    @State private var expandedAnnotationID: UUID?

    var body: some View {
        ScreenRecordingInspectorSection(AppLocalization.text("标注"), symbol: "pencil.tip.crop.circle", expanded: false) {
            Menu(AppLocalization.text("添加标注")) {
                ForEach(RecordingAnnotationKind.allCases, id: \.self) { kind in
                    Button { add(kind) } label: { Label(AppLocalization.text(kind.title), systemImage: kind.symbol) }
                }
            }.disabled(model.project.map { model.currentTime >= $0.duration
                || ($0.edits.annotations?.count ?? 0) >= RecordingAnnotation.maximumCount } ?? true)
            LazyVStack(alignment: .leading, spacing: 12) {
                ForEach(model.project?.edits.annotations ?? []) { annotation in
                    DisclosureGroup(isExpanded: Binding(get: { expandedAnnotationID == annotation.id }, set: {
                        expandedAnnotationID = $0 ? annotation.id : nil
                    })) {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                Button(ScreenRecordingStudioView.clock(annotation.start)) { model.seek(to: annotation.start) }
                                Spacer()
                                Button(role: .destructive) {
                                    model.update { $0.edits.annotations?.removeAll { $0.id == annotation.id } }
                                } label: { Image(systemName: "trash") }.help(AppLocalization.text("删除标注"))
                            }.buttonStyle(.borderless)
                            numberField("起点（秒）", id: annotation.id, path: \.start)
                            numberField("终点（秒）", id: annotation.id, path: \.end)
                            if annotation.kind == .text {
                                TextField(AppLocalization.text("标注内容"), text: binding(annotation.id, path: \.text, default: ""), axis: .vertical)
                                    .textFieldStyle(.roundedBorder).lineLimit(2...5)
                                    .accessibilityIdentifier("screenRecording.annotationText." + annotation.id.uuidString)
                                parameter("文字大小", id: annotation.id, path: \.fontSize, in: 0.01...0.3)
                            } else {
                                parameter("线条粗细", id: annotation.id, path: \.lineWidth, in: 0.001...0.05)
                            }
                            numberField("起点 X", id: annotation.id, path: \.x)
                            numberField("起点 Y", id: annotation.id, path: \.y)
                            numberField("终点 X", id: annotation.id, path: \.endX)
                            numberField("终点 Y", id: annotation.id, path: \.endY)
                            ScreenRecordingColorPicker(title: "颜色", selection: binding(annotation.id, path: \.color, default: .annotation))
                        }.padding(.top, 10)
                    } label: {
                        HStack(spacing: 6) {
                            Label(AppLocalization.text(annotation.kind.title), systemImage: annotation.kind.symbol).lineLimit(1)
                            Spacer(minLength: 4)
                            Text(ScreenRecordingStudioView.clock(annotation.start)).monospacedDigit()
                        }.font(.system(size: 11))
                    }
                    .accessibilityIdentifier("screenRecording.annotation." + annotation.id.uuidString)
                }
            }
            Text(AppLocalization.text("位置使用画布左上角为原点，时间对应原始素材"))
                .font(.system(size: 10)).foregroundStyle(.secondary)
        }.disabled(!model.canEdit)
    }

    private func add(_ kind: RecordingAnnotationKind) {
        model.update { project in
            guard model.currentTime < project.duration else { return }
            let annotation = RecordingAnnotation(kind: kind, start: model.currentTime,
                end: min(project.duration, model.currentTime + 2), text: kind == .text ? AppLocalization.text("文字标注") : "")
            project.edits.annotations = (project.edits.annotations ?? []) + [annotation]
            expandedAnnotationID = annotation.id
        }
    }

    private func binding<Value>(_ id: UUID, path: WritableKeyPath<RecordingAnnotation, Value>, default value: Value) -> Binding<Value> {
        Binding(get: { model.project?.edits.annotations?.first { $0.id == id }?[keyPath: path] ?? value },
                set: { value in model.update { project in
                    if let index = project.edits.annotations?.firstIndex(where: { $0.id == id }) {
                        project.edits.annotations?[index][keyPath: path] = value
                    }
                } })
    }

    private func numberField(_ title: String, id: UUID, path: WritableKeyPath<RecordingAnnotation, Double>) -> some View {
        ScreenRecordingNumberField(title: AppLocalization.text(title), value: binding(id, path: path, default: 0),
            identifier: "screenRecording.annotationField." + id.uuidString + "." + title)
    }

    private func parameter(_ title: String, id: UUID, path: WritableKeyPath<RecordingAnnotation, Double>,
                           in range: ClosedRange<Double>) -> some View {
        ScreenRecordingParameterRow(title: AppLocalization.text(title), value: binding(id, path: path, default: range.lowerBound),
            range: range, identifier: "screenRecording.annotationField." + id.uuidString + "." + title)
    }
}
