import AVKit
import SwiftUI
import ZislaCore
import ZislaKit

struct ScreenRecordingStudioView: View {
    @ObservedObject var model: ScreenRecordingStudioModel
    @ObservedObject var languageStore: AppLanguageStore
    let selectRegion: () -> Void
    @State private var inspector = 0

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            HSplitView {
                VStack(spacing: 12) {
                    preview
                    if let project = model.project {
                        HStack(spacing: 10) {
                            Button(action: model.playTimeline) {
                                Label(AppLocalization.text(model.isShowingTimelinePlayback ? "暂停预览" : "播放剪辑"),
                                    systemImage: model.isShowingTimelinePlayback ? "pause.fill" : "play.fill")
                            }
                            Button(action: model.playSource) {
                                Image(systemName: model.isShowingSourcePlayback ? "pause.fill" : "play.fill")
                            }
                            .help(AppLocalization.text("播放原始素材"))
                            Slider(value: Binding(get: { model.currentTime }, set: { model.seek(to: $0) }),
                                   in: 0...max(0.001, project.duration))
                            Text(Self.clock(model.currentTime) + " / " + Self.clock(project.duration))
                                .font(.system(.caption, design: .monospaced))
                        }
                        .disabled(!model.canEdit)
                        Text(AppLocalization.text(model.isShowingTimelinePlayback ? "正在播放剪辑顺序与音频，画面效果请暂停预览或导出查看"
                            : model.isShowingSourcePlayback ? "正在播放原始素材" : "预览与导出使用相同的画面效果"))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                .padding(20)
                .frame(minWidth: 460, maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.black.opacity(0.05))
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        if model.isRecording || model.project == nil || model.showCaptureSetup { captureSettings }
                        if model.project != nil {
                            Picker("", selection: $inspector) {
                                Text(AppLocalization.text("时间线")).tag(0)
                                Text(AppLocalization.text("画面效果")).tag(1)
                                Text(AppLocalization.text("字幕")).tag(2)
                                Text(AppLocalization.text("AI 剪辑")).tag(3)
                            }.pickerStyle(.segmented)
                            switch inspector {
                            case 0: ScreenRecordingTimelineView(model: model)
                            case 1: ScreenRecordingEffectsView(model: model)
                            case 2: ScreenRecordingCaptionsView(model: model)
                            default: ScreenRecordingAIView(model: model)
                            }
                        }
                        if model.exporter.isExporting {
                            ProgressView(value: model.exporter.progress)
                            Text(AppLocalization.text("正在导出录屏"))
                        }
                        if model.isBusy || model.isRecording || model.exporter.isExporting {
                            Button(AppLocalization.text("取消"), role: .cancel, action: model.cancelOperation)
                        }
                    }
                    .padding(16)
                }
                .frame(minWidth: 310, idealWidth: 350, maxWidth: 440)
            }
            if let error = model.errorMessage ?? model.capture.errorMessage {
                Divider()
                Label(error, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.red).font(.caption)
                    .textSelection(.enabled).padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(minWidth: 860, minHeight: 560)
        .environment(\.locale, languageStore.language.locale)
        .environment(\.layoutDirection, languageStore.language.isRightToLeft ? .rightToLeft : .leftToRight)
        .task { await model.loadSources() }
        .onChange(of: languageStore.language) { _, _ in model.objectWillChange.send() }
    }

    private var toolbar: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(AppLocalization.text("录屏工作室")).font(.headline)
                if let project = model.project {
                    Text(project.name + (model.isDirty ? " •" : "")).font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
            if model.capture.phase == .recording || model.capture.phase == .paused {
                Text(Self.clock(model.capture.elapsed)).monospacedDigit()
                Button(AppLocalization.text(model.capture.phase == .paused ? "继续录制" : "暂停录制"), action: model.pause)
                Button(AppLocalization.text("停止录制"), action: model.stop).tint(.red)
            } else if model.isStarting || model.isStopping {
                ProgressView().controlSize(.small)
                Text(AppLocalization.text(model.isStopping ? "正在保存录屏" : "正在准备录制"))
            } else {
                Menu {
                    Button(AppLocalization.text("打开录屏项目"), action: model.openProject)
                    Button(AppLocalization.text("导入视频"), action: model.importVideo)
                    Button(AppLocalization.text("保存录屏项目"), action: model.saveProject).disabled(model.project == nil)
                    Button(AppLocalization.text("项目另存为"), action: model.saveCopy).disabled(!model.canEdit)
                } label: { Label(AppLocalization.text("项目"), systemImage: "folder") }
                .disabled(model.isBusy)
                Button(action: model.undo) { Image(systemName: "arrow.uturn.backward") }
                    .help(AppLocalization.text("撤销")).disabled(!model.canUndo)
                Button(action: model.redo) { Image(systemName: "arrow.uturn.forward") }
                    .help(AppLocalization.text("重做")).disabled(!model.canRedo)
                Button(AppLocalization.text("录制设置")) {
                    inspector = 0
                    model.showCaptureSetup.toggle()
                }.disabled(!model.canEdit)
                Button(AppLocalization.text("导出录屏"), action: model.export).disabled(!model.canEdit)
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
    }

    @ViewBuilder private var preview: some View {
        if let player = model.activePlayer, model.isShowingSourcePlayback || model.isShowingTimelinePlayback {
            VideoPlayer(player: player).frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let preview = model.preview {
            Image(nsImage: preview).resizable().scaledToFit()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            VStack(spacing: 16) {
                Image(systemName: model.isRecording ? "record.circle" : "rectangle.inset.filled.and.person.filled")
                    .font(.system(size: 52)).foregroundStyle(model.isRecording ? .red : .secondary)
                Text(AppLocalization.text(model.isRecording ? "录制中，可使用快捷键暂停或停止" : "录制屏幕，制作演示视频"))
                    .font(.title3)
                Text(AppLocalization.text("全屏、窗口或区域录制，支持音频与摄像头"))
                    .font(.callout).foregroundStyle(.secondary)
                if model.isRecording { Text(Self.clock(model.capture.elapsed)).font(.largeTitle).monospacedDigit() }
                else { Button(AppLocalization.text("导入视频"), action: model.importVideo) }
            }.frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var captureSettings: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(AppLocalization.text("录制设置")).font(.headline)
            Picker(AppLocalization.text("录制方式"), selection: Binding(get: { model.configuration.mode }, set: { model.selectMode($0) })) {
                ForEach(RecordingCaptureMode.allCases, id: \.self) { mode in
                    Text(AppLocalization.text(mode.title)).tag(mode)
                }
            }
            Picker(AppLocalization.text("录制来源"), selection: $model.configuration.sourceID) {
                ForEach(model.availableSources) { source in Text(source.name).tag(source.id) }
            }
            if model.availableSources.isEmpty {
                Button(AppLocalization.text("授权屏幕录制"), action: model.requestScreenAccess)
            } else {
                Button(AppLocalization.text("刷新来源")) { Task { await model.loadSources() } }
            }
            if model.configuration.mode == .region {
                Button(AppLocalization.text("选择录制区域"), action: selectRegion)
                if let region = model.configuration.region {
                    Text(String(format: "%.0f × %.0f", region.width, region.height)).font(.caption).monospacedDigit()
                }
            }
            Toggle(AppLocalization.text("系统音频"), isOn: $model.configuration.systemAudio)
            Toggle(AppLocalization.text("麦克风"), isOn: $model.configuration.microphone)
            if model.configuration.microphone {
                Picker(AppLocalization.text("麦克风"), selection: $model.configuration.microphoneID) {
                    Text(AppLocalization.text("系统默认")).tag(Optional<String>.none)
                    ForEach(model.capture.microphones) { device in Text(device.name).tag(Optional(device.id)) }
                }
            }
            Toggle(AppLocalization.text("摄像头叠加"), isOn: $model.configuration.camera)
            if model.configuration.camera {
                Picker(AppLocalization.text("摄像头"), selection: $model.configuration.cameraID) {
                    Text(AppLocalization.text("系统默认")).tag(Optional<String>.none)
                    ForEach(model.capture.cameras) { device in Text(device.name).tag(Optional(device.id)) }
                }
            }
            Picker(AppLocalization.text("帧率"), selection: $model.configuration.frameRate) {
                ForEach([30, 60], id: \.self) { rate in Text("\(rate) FPS").tag(rate) }
            }
            Button(action: model.start) {
                Label(AppLocalization.text("开始录制"), systemImage: "record.circle")
                    .frame(maxWidth: .infinity)
            }.buttonStyle(.borderedProminent).tint(.red)
                .disabled(model.availableSources.isEmpty || (model.configuration.mode == .region && model.configuration.region == nil))
            Text(AppLocalization.text("录制素材和项目保存在本机"))
                .font(.caption).foregroundStyle(.secondary)
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
