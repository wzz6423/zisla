import SwiftUI
import ZislaCore
import ZislaKit

struct ScreenRecordingStudioView: View {
    @ObservedObject var model: ScreenRecordingStudioModel
    @ObservedObject var languageStore: AppLanguageStore
    let prepareCapture: () -> Void
    @State private var inspector = 0
    @State private var selectedSegmentID: UUID?
    @State private var canvasSelection: RecordingCanvasSelection?

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            HSplitView {
                ScreenRecordingMediaLibraryView(model: model)
                    .frame(minWidth: 180, idealWidth: 210, maxWidth: 260)
                VStack(spacing: 0) {
                    ZStack { preview }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Color.black.opacity(0.94), in: RoundedRectangle(cornerRadius: 10))
                        .clipped()
                        .padding(16)
                        .layoutPriority(1)
                    if let project = model.project {
                        transport(project)
                        Divider().padding(.top, 8)
                        ScreenRecordingMultitrackTimelineView(model: model)
                            .padding(12).disabled(!model.canEdit)
                    }
                }
                .frame(minWidth: 420, maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.black.opacity(0.05))
                VStack(spacing: 0) {
                    if model.project != nil {
                        Picker("", selection: $inspector) {
                            Label(AppLocalization.text("片段"), systemImage: "scissors").labelStyle(.iconOnly).tag(0)
                            Label(AppLocalization.text("画面效果"), systemImage: "slider.horizontal.3").labelStyle(.iconOnly).tag(1)
                            Label(AppLocalization.text("字幕"), systemImage: "captions.bubble").labelStyle(.iconOnly).tag(2)
                            Label(AppLocalization.text("AI 剪辑"), systemImage: "sparkles").labelStyle(.iconOnly).tag(3)
                        }.pickerStyle(.segmented).padding(12)
                            .accessibilityIdentifier("screenRecording.inspectorTabs")
                        Divider()
                    }
                    ScrollView {
                        VStack(alignment: .leading, spacing: 12) {
                            if model.project == nil { captureSettings }
                            if model.project != nil {
                                Text(AppLocalization.text(inspectorTitle)).font(.system(size: 15, weight: .semibold))
                                    .padding(.bottom, 2)
                                switch inspector {
                                case 0:
                                    ScreenRecordingMultitrackClipInspector(model: model)
                                    ScreenRecordingTimelineView(model: model, selectedSegmentID: $selectedSegmentID,
                                        showsClipInspector: false)
                                    if model.project?.timeline == nil {
                                        DisclosureGroup(AppLocalization.text("恢复完整素材")) {
                                            ScreenRecordingTimelineView(model: model, selectedSegmentID: $selectedSegmentID)
                                        }
                                    }
                                case 1: ScreenRecordingEffectsView(model: model)
                                case 2: ScreenRecordingCaptionsView(model: model)
                                default: ScreenRecordingAIView(model: model)
                                }
                            }
                            if model.isBusy || model.isRecording || model.exporter.isExporting {
                                Button(AppLocalization.text("取消"), role: .cancel, action: model.cancelOperation)
                            }
                        }
                        .padding(12).frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .frame(minWidth: 320, idealWidth: 340, maxWidth: 390)
                .background(Color(nsColor: .windowBackgroundColor))
            }
        }
        .frame(minWidth: 960, minHeight: 640)
        .environment(\.locale, languageStore.language.locale)
        .environment(\.layoutDirection, languageStore.language.isRightToLeft ? .rightToLeft : .leftToRight)
        .environment(\.recordingCanvasSelection, $canvasSelection)
        .onChange(of: languageStore.language) { _, _ in model.objectWillChange.send() }
        .onChange(of: model.project?.id) { _, _ in canvasSelection = nil }
        .onChange(of: canvasSelection) { _, selection in
            switch selection {
            case let .annotation(id):
                inspector = 1
                model.selectCanvasTimelineContent(.annotation(id))
            case let .caption(id):
                inspector = 2
                model.selectCanvasTimelineContent(.caption(id))
            case let .image(id): inspector = 0; model.selectedTimelineClipID = id
            case nil: break
            }
        }
        .onChange(of: model.selectedTimelineClipID, initial: true) { _, id in
            if model.project?.timeline == nil, let segmentID = id.flatMap(UUID.init(uuidString:)),
               model.project?.edits.segments.contains(where: { $0.id == segmentID }) == true {
                selectedSegmentID = segmentID
            }
            switch model.selectedTimelineClip?.content {
            case let .annotation(id): canvasSelection = .annotation(id)
            case let .caption(id): canvasSelection = .caption(id)
            case .image: canvasSelection = id.map(RecordingCanvasSelection.image)
            default: canvasSelection = nil
            }
        }
        .onChange(of: selectedSegmentID) { _, id in
            if model.project?.timeline == nil { model.selectedTimelineClipID = id?.uuidString }
        }
        .onChange(of: model.project?.edits.segments.map(\.id), initial: true) { _, ids in
            if !(ids ?? []).contains(where: { $0 == selectedSegmentID }) { selectedSegmentID = ids?.first }
        }
    }

    private var toolbar: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(AppLocalization.text("录屏工作室")).font(.headline)
                if let project = model.project {
                    Text(project.name + (model.isDirty ? " •" : "")).font(.caption).foregroundStyle(.secondary)
                        .lineLimit(1).truncationMode(.middle)
                }
            }
            .frame(maxWidth: 240, alignment: .leading)
            Menu {
                Button(AppLocalization.text("打开录屏项目"), action: model.openProject)
                Button(AppLocalization.text("导入素材"), action: model.importVideo)
                Button(AppLocalization.text("保存录屏项目"), action: model.saveProject).disabled(model.project == nil)
                Button(AppLocalization.text("项目另存为"), action: model.saveCopy).disabled(!model.canEdit)
            } label: { Label(AppLocalization.text("项目"), systemImage: "folder") }
            .disabled(model.isBusy || model.isChoosingFile || model.isRecording || model.exporter.isExporting)
            .accessibilityIdentifier("screenRecording.projectMenu")
            Spacer()
            HStack(spacing: 10) {
                Button(action: model.undo) { Image(systemName: "arrow.uturn.backward") }
                    .help(AppLocalization.text("撤销")).disabled(!model.canUndo)
                    .accessibilityIdentifier("screenRecording.undo")
                Button(action: model.redo) { Image(systemName: "arrow.uturn.forward") }
                    .help(AppLocalization.text("重做")).disabled(!model.canRedo)
                    .accessibilityIdentifier("screenRecording.redo")
                Button(AppLocalization.text("导出录屏"), action: model.export).disabled(!model.canExport)
                    .accessibilityIdentifier("screenRecording.export")
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
    }

    @ViewBuilder private var preview: some View {
        if let player = model.activePlayer, model.isShowingSourcePlayback || model.isShowingTimelinePlayback {
            ScreenRecordingPlayerView(player: player).frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if model.canvasPreview != nil {
            ScreenRecordingCanvasEditor(model: model, selection: $canvasSelection)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let preview = model.preview {
            Image(nsImage: preview).resizable().scaledToFit()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            VStack(spacing: 16) {
                Image(systemName: model.isRecording ? "record.circle" : "rectangle.inset.filled.and.person.filled")
                    .font(.system(size: 52)).foregroundStyle(model.isRecording ? Color.red : Color.white.opacity(0.6))
                Text(AppLocalization.text(model.isRecording ? "录制中，可使用快捷键暂停或停止" : "录制屏幕，制作演示视频"))
                    .font(.title3)
                if model.isRecording { Text(Self.clock(model.capture.elapsed)).font(.largeTitle).monospacedDigit() }
                else { Button(AppLocalization.text("导入素材"), action: model.importVideo) }
            }.foregroundStyle(.white.opacity(0.9)).padding(24)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var inspectorTitle: String { ["片段", "画面效果", "字幕", "AI 剪辑"][inspector] }

    private func transport(_ project: ScreenRecordingProject) -> some View {
        let original = model.isShowingSourcePlayback
        let time = original ? model.currentTime : model.playbackTime
        let duration = original ? model.sourceDuration : project.outputDuration
        return HStack(spacing: 10) {
            Button(action: model.playTimeline) {
                Image(systemName: model.isShowingTimelinePlayback ? "pause.circle.fill" : "play.circle.fill")
                    .font(.system(size: 27)).foregroundStyle(Color.accentColor)
            }
            .buttonStyle(.plain)
            .help(AppLocalization.text(model.isShowingTimelinePlayback ? "暂停预览" : "预览与导出使用相同的画面效果"))
            .accessibilityLabel(AppLocalization.text(model.isShowingTimelinePlayback ? "暂停预览" : "播放剪辑"))
            .accessibilityIdentifier("screenRecording.playTimeline")
            .disabled(!model.canExport)
            Button(action: model.playSource) { Image(systemName: "film").frame(width: 24, height: 26) }
                .buttonStyle(.plain)
                .help(AppLocalization.text(model.isShowingSourcePlayback ? "正在播放原始素材" : "播放原始素材"))
                .accessibilityLabel(AppLocalization.text("播放原始素材"))
                .disabled(model.player == nil)
            Slider(value: Binding(get: { time }, set: { original ? model.seekSource(to: $0) : model.seekTimeline(to: $0) }),
                   in: 0...max(0.001, duration))
                .accessibilityLabel(AppLocalization.text("时间线"))
                .accessibilityIdentifier("screenRecording.playbackPosition")
            Text(Self.clock(time) + " / " + Self.clock(duration))
                .font(.system(size: 11, design: .monospaced)).monospacedDigit().fixedSize()
        }
        .padding(.horizontal, 16).frame(height: 34).disabled(!model.canEdit)
    }

    private var captureSettings: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(AppLocalization.text("录制设置")).font(.headline)
            Button(action: prepareCapture) {
                Label(AppLocalization.text("开始录制"), systemImage: "record.circle")
                    .frame(maxWidth: .infinity)
            }.buttonStyle(.borderedProminent).tint(.red)
        }
        .disabled(model.isRecording || model.isBusy)
    }

    static func clock(_ value: Double) -> String {
        guard value.isFinite, value >= 0 else { return "00:00" }
        let seconds = Int(min(value, Double(Int.max / 2)))
        return seconds >= 3_600 ? String(format: "%d:%02d:%02d", seconds / 3_600, seconds / 60 % 60, seconds % 60)
            : String(format: "%02d:%02d", seconds / 60, seconds % 60)
    }
}
