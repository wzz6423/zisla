import AppKit
import Combine
import SwiftUI
import ZislaCore
import ZislaKit

enum ScreenRecordingCaptureBarGeometry {
    static let setupWidth: CGFloat = 604
    static let recordingWidth: CGFloat = 256
    static let dragHandleWidth: CGFloat = 24
    static let closeButtonWidth: CGFloat = 24
    static let separatorHorizontalPadding: CGFloat = 1
    static let fixedSetupWidth: CGFloat = 440

    static func sourceWidth(availableWidth: CGFloat) -> CGFloat {
        min(152, max(32, availableWidth - fixedSetupWidth))
    }

    static func canSelectRegion(configuration: RecordingCaptureConfiguration, sources: [RecordingCaptureSource],
                                displayIDs: [UInt32]) -> Bool {
        guard !displayIDs.isEmpty else { return false }
        if configuration.mode == .window {
            return sources.contains {
                $0.id == configuration.sourceID && $0.mode == .window && $0.frame.isValid
            }
        }
        return displayIDs.contains(configuration.sourceID)
    }

    static func panelFrame(size: CGSize, in visibleFrame: CGRect, center: CGPoint? = nil) -> CGRect {
        let size = CGSize(width: min(size.width, visibleFrame.width), height: min(size.height, visibleFrame.height))
        let center = ScreenshotToolbarLayout.clampedCenter(
            center ?? CGPoint(x: visibleFrame.midX, y: visibleFrame.minY + 80 + size.height / 2),
            toolbarSize: size, in: visibleFrame)
        return CGRect(x: center.x - size.width / 2, y: center.y - size.height / 2,
            width: size.width, height: size.height)
    }

    static func targetFrame(configuration: RecordingCaptureConfiguration, sources: [RecordingCaptureSource],
                            screenFrames: [UInt32: CGRect], primaryScreenFrame: CGRect) -> CGRect? {
        guard let source = sources.first(where: { $0.id == configuration.sourceID
            && $0.mode == (configuration.mode == .region ? .display : configuration.mode) }) else { return nil }
        if configuration.mode == .window {
            guard source.frame.isValid else { return nil }
            return CGRect(x: source.frame.x, y: primaryScreenFrame.maxY - source.frame.y - source.frame.height,
                width: source.frame.width, height: source.frame.height)
        }
        guard let screen = screenFrames[source.id] else { return nil }
        if configuration.mode == .display { return screen }
        guard let region = configuration.region, region.isValid else { return nil }
        return CGRect(x: screen.minX + region.x, y: screen.maxY - region.y - region.height,
            width: region.width, height: region.height).intersection(screen)
    }
}

@MainActor
final class ScreenRecordingCaptureBarController {
    private let model: ScreenRecordingStudioModel
    private let panel: ScreenRecordingCapturePanel
    private let outline: NSPanel
    private let outlineView = ScreenRecordingTargetOutlineView()
    let hostingView: NSHostingView<ScreenRecordingCaptureBar>
    private var subscriptions: Set<AnyCancellable> = []
    private var isPresented = false

    init(model: ScreenRecordingStudioModel, languageStore: AppLanguageStore,
         selectRegion: @escaping () -> Void, start: @escaping () -> Void,
         chooseDirectory: @escaping () -> Void, openStudio: @escaping () -> Void,
         cancel: @escaping () -> Void,
         displaySaveDirectory: @escaping () -> String = {
             FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first?.path ?? ""
         }) {
        self.model = model
        panel = ScreenRecordingCapturePanel(contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        outline = NSPanel(contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        hostingView = NSHostingView(rootView: ScreenRecordingCaptureBar(model: model,
            languageStore: languageStore, selectRegion: selectRegion, start: start,
            chooseDirectory: chooseDirectory, openStudio: openStudio, cancel: cancel,
            displaySaveDirectory: displaySaveDirectory))
        panel.isReleasedWhenClosed = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .screenSaver
        panel.hidesOnDeactivate = false
        panel.isMovableByWindowBackground = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.contentView = hostingView
        panel.setAccessibilityIdentifier("screenRecording.captureBar")
        panel.onCancel = { [weak model] in
            if model?.isRecording == false { cancel() }
        }
        outline.isReleasedWhenClosed = false
        outline.isOpaque = false
        outline.backgroundColor = .clear
        outline.hasShadow = false
        outline.level = .screenSaver
        outline.hidesOnDeactivate = false
        outline.ignoresMouseEvents = true
        outline.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        outline.contentView = outlineView
        outline.setAccessibilityIdentifier("screenRecording.targetOutline")
        model.objectWillChange.receive(on: RunLoop.main).sink { [weak self] _ in self?.refresh() }
            .store(in: &subscriptions)
        model.capture.$sources.receive(on: RunLoop.main).sink { [weak self] _ in self?.refreshTargetOutline() }
            .store(in: &subscriptions)
        languageStore.$language.receive(on: RunLoop.main).sink { [weak self] _ in
            self?.panel.title = AppLocalization.text("录屏控制条")
        }.store(in: &subscriptions)
        panel.title = AppLocalization.text("录屏控制条")
    }

    func present(on screen: NSScreen? = nil) {
        isPresented = true
        let target = screen ?? panel.screen ?? NSScreen.main
        if let target {
            panel.setFrame(ScreenRecordingCaptureBarGeometry.panelFrame(size: preferredSize,
                in: target.visibleFrame.insetBy(dx: 12, dy: 12)), display: false)
        }
        refreshTargetOutline()
        panel.makeKeyAndOrderFront(nil)
    }

    func hide() {
        isPresented = false
        panel.orderOut(nil)
        outline.orderOut(nil)
    }

    func shutdown() {
        hide()
        subscriptions.removeAll()
        panel.close()
        outline.close()
    }

    func refreshTargetOutline() {
        guard isPresented, !model.isRecording, let primary = NSScreen.screens.first else {
            outline.orderOut(nil)
            return
        }
        let screens = Dictionary(uniqueKeysWithValues: NSScreen.screens.compactMap { screen in
            ScreenshotCaptureService.displayID(for: screen).map { ($0, screen.frame) }
        })
        guard let frame = ScreenRecordingCaptureBarGeometry.targetFrame(configuration: model.configuration,
            sources: model.capture.sources, screenFrames: screens, primaryScreenFrame: primary.frame),
              !frame.isNull, !frame.isEmpty else {
            outline.orderOut(nil)
            return
        }
        outline.setFrame(frame.insetBy(dx: -3, dy: -3), display: true)
        outline.orderFrontRegardless()
        if panel.isVisible { panel.orderFrontRegardless() }
    }

    var preferredSize: CGSize {
        CGSize(width: model.isRecording ? ScreenRecordingCaptureBarGeometry.recordingWidth + (model.configuration.camera ? 64 : 0)
            : hostingView.fittingSize.width,
            height: ScreenshotToolbarLayout.height)
    }

    private func refresh() {
        guard isPresented else { return }
        if let screen = panel.screen ?? NSScreen.main {
            let frame = ScreenRecordingCaptureBarGeometry.panelFrame(size: preferredSize,
                in: screen.visibleFrame.insetBy(dx: 12, dy: 12),
                center: CGPoint(x: panel.frame.midX, y: panel.frame.midY))
            if frame != panel.frame { panel.setFrame(frame, display: true) }
        }
        refreshTargetOutline()
    }
}

private final class ScreenRecordingCapturePanel: NSPanel {
    var onCancel: (() -> Void)?
    override var canBecomeKey: Bool { true }
    override func cancelOperation(_ sender: Any?) { onCancel?() }
}

private final class ScreenRecordingTargetOutlineView: NSView {
    override func draw(_ dirtyRect: NSRect) {
        NSColor.systemRed.withAlphaComponent(0.9).setStroke()
        let border = NSBezierPath(roundedRect: bounds.insetBy(dx: 3, dy: 3), xRadius: 4, yRadius: 4)
        border.lineWidth = 2
        border.stroke()
    }
}

struct ScreenRecordingCaptureBar: View {
    @ObservedObject var model: ScreenRecordingStudioModel
    @ObservedObject var languageStore: AppLanguageStore
    let selectRegion: () -> Void
    let start: () -> Void
    let chooseDirectory: () -> Void
    let openStudio: () -> Void
    let cancel: () -> Void
    let displaySaveDirectory: () -> String
    @State private var showsCameraCornerRadius = false

    var body: some View {
        HStack(spacing: ScreenshotToolbarLayout.spacing) {
            if model.isRecording { recordingControls }
            else { setupControls }
        }
        .frame(height: ScreenshotToolbarLayout.height)
        .background(.ultraThinMaterial, in: RoundedRectangle(
            cornerRadius: ScreenshotToolbarLayout.cornerRadius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: ScreenshotToolbarLayout.cornerRadius, style: .continuous)
            .stroke(.white.opacity(ScreenshotToolbarLayout.borderOpacity), lineWidth: 1))
        .shadow(color: .black.opacity(0.12), radius: 4, y: 1)
        .environment(\.locale, languageStore.language.locale)
        .environment(\.layoutDirection, languageStore.language.isRightToLeft ? .rightToLeft : .leftToRight)
    }

    private var setupControls: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: ScreenshotToolbarLayout.spacing) {
                dragHandle
                Button(action: cancel) { Image(systemName: "xmark") }
                    .buttonStyle(.plain).frame(width: ScreenRecordingCaptureBarGeometry.closeButtonWidth,
                        height: ScreenshotToolbarLayout.controlHeight)
                    .help(AppLocalization.text("关闭"))
                    .accessibilityLabel(AppLocalization.text("关闭"))
                    .accessibilityIdentifier("screenRecording.closeCaptureBar")
                separator
                ForEach(RecordingCaptureMode.allCases, id: \.self) { mode in modeButton(mode) }
                if model.configuration.mode == .region {
                    Button(action: selectRegion) {
                        Image(systemName: "viewfinder").frame(width: 28, height: ScreenshotToolbarLayout.controlHeight)
                    }
                    .buttonStyle(.plain).help(AppLocalization.text("选择录制区域"))
                    .accessibilityLabel(AppLocalization.text("选择录制区域"))
                    .accessibilityIdentifier("screenRecording.selectRegion")
                    .disabled(!canSelectRegion)
                }
                sourcePicker(width: ScreenRecordingCaptureBarGeometry.sourceWidth(
                    availableWidth: ScreenRecordingCaptureBarGeometry.setupWidth))
                separator
                inputButton("speaker.wave.2", disabledSymbol: "speaker.slash", title: "系统音频",
                    value: $model.configuration.systemAudio, identifier: "systemAudio")
                inputButton("mic", disabledSymbol: "mic.slash", title: "麦克风",
                    value: $model.configuration.microphone, identifier: "microphone")
                inputButton("video", disabledSymbol: "video.slash", title: "摄像头",
                    value: $model.configuration.camera, identifier: "camera")
                cameraShapeControls
                optionsMenu
                Button(action: start) {
                    Image(systemName: "record.circle.fill")
                        .font(.system(size: 15, weight: .semibold)).foregroundStyle(.white)
                        .frame(width: 34, height: ScreenshotToolbarLayout.controlHeight)
                        .background(.red, in: RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain).help(AppLocalization.text("开始录制"))
                .accessibilityLabel(AppLocalization.text("开始录制"))
                .disabled(model.availableSources.isEmpty || model.isBusy || model.isChoosingFile
                    || model.exporter.isExporting
                    || (model.configuration.mode == .region && model.configuration.region?.isValid != true))
                .accessibilityIdentifier("screenRecording.startCapture")
            }
            .padding(.horizontal, ScreenshotToolbarLayout.horizontalPadding)
            .frame(height: ScreenshotToolbarLayout.height)
            .fixedSize(horizontal: true, vertical: false)
        }
        .frame(height: ScreenshotToolbarLayout.height)
        .disabled(model.isBusy || model.isChoosingFile)
    }

    private func modeButton(_ mode: RecordingCaptureMode) -> some View {
        Button {
            if model.configuration.mode != mode { model.selectMode(mode) }
        } label: {
            Image(systemName: symbol(for: mode))
                .font(.system(size: 14, weight: .semibold)).frame(width: 34, height: ScreenshotToolbarLayout.controlHeight)
                .foregroundStyle(model.configuration.mode == mode ? Color.accentColor : Color.primary)
                .background(model.configuration.mode == mode ? Color.accentColor.opacity(0.16) : Color.clear,
                    in: RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain).help(AppLocalization.text(mode.title))
        .accessibilityLabel(AppLocalization.text(mode.title))
        .accessibilityAddTraits(model.configuration.mode == mode ? [.isSelected] : [])
        .accessibilityIdentifier("screenRecording.mode." + mode.rawValue)
    }

    @ViewBuilder private func sourcePicker(width: CGFloat) -> some View {
        if model.availableSources.isEmpty {
            Button(action: model.requestScreenAccess) {
                Image(systemName: "lock.shield").frame(width: width, height: ScreenshotToolbarLayout.controlHeight)
            }
            .buttonStyle(.plain).help(AppLocalization.text("授权屏幕录制"))
            .accessibilityLabel(AppLocalization.text("授权屏幕录制"))
            .accessibilityIdentifier("screenRecording.requestScreenAccess")
        } else {
            Menu {
                ForEach(model.availableSources) { source in
                    Button {
                        if model.configuration.sourceID != source.id {
                            model.configuration.sourceID = source.id
                            model.configuration.region = nil
                        }
                    } label: {
                        if model.configuration.sourceID == source.id {
                            Label(source.name, systemImage: "checkmark")
                        } else { Text(source.name) }
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    if width >= 64 {
                        Text(model.availableSources.first(where: { $0.id == model.configuration.sourceID })?.name
                            ?? AppLocalization.text("录制来源"))
                            .font(.system(size: 11)).lineLimit(1).truncationMode(.middle)
                    } else { Image(systemName: symbol(for: model.configuration.mode)).font(.system(size: 12)) }
                    Image(systemName: "chevron.down").font(.system(size: 8, weight: .semibold))
                }.frame(height: ScreenshotToolbarLayout.controlHeight)
            }
            .menuStyle(.borderlessButton).menuIndicator(.hidden)
            .frame(maxWidth: width).fixedSize(horizontal: true, vertical: false)
            .accessibilityIdentifier("screenRecording.captureSource")
            .accessibilityLabel(AppLocalization.text("录制来源"))
            .accessibilityValue(model.availableSources.first(where: { $0.id == model.configuration.sourceID })?.name ?? "")
            .help(model.availableSources.first(where: { $0.id == model.configuration.sourceID })?.name
                ?? AppLocalization.text("录制来源"))
        }
    }

    private func inputButton(_ symbol: String, disabledSymbol: String, title: String,
                             value: Binding<Bool>, identifier: String) -> some View {
        Button { value.wrappedValue.toggle() } label: {
            Image(systemName: value.wrappedValue ? symbol : disabledSymbol)
                .font(.system(size: 13, weight: .semibold)).frame(width: 32, height: ScreenshotToolbarLayout.controlHeight)
                .foregroundStyle(value.wrappedValue ? Color.accentColor : Color.secondary)
                .background(value.wrappedValue ? Color.accentColor.opacity(0.12) : Color.clear,
                    in: RoundedRectangle(cornerRadius: 5))
        }
        .buttonStyle(.plain).help(AppLocalization.text(title))
        .accessibilityLabel(AppLocalization.text(title))
        .accessibilityValue(value.wrappedValue ? AppLocalization.text("开启") : AppLocalization.text("关闭"))
        .accessibilityAddTraits(value.wrappedValue ? [.isSelected] : [])
        .accessibilityIdentifier("screenRecording.input." + identifier)
    }

    private func cameraShapeButton(round: Bool) -> some View {
        let title = AppLocalization.text(round ? "圆形摄像头" : "矩形")
        return Button {
            if round, model.recordingCameraAspectRatio != .square {
                model.setRecordingCameraAspectRatio(.square)
            }
            model.recordingCameraRound = round
            showsCameraCornerRadius = !round
        } label: {
            Image(systemName: round ? "circle" : "rectangle")
                .font(.system(size: 14, weight: .medium))
                .frame(width: 28, height: ScreenshotToolbarLayout.controlHeight)
                .foregroundStyle(model.recordingCameraRound == round ? Color.accentColor : Color.secondary)
                .background(model.recordingCameraRound == round ? Color.accentColor.opacity(0.12) : Color.clear,
                    in: RoundedRectangle(cornerRadius: 5))
        }
        .buttonStyle(.plain).help(title).accessibilityLabel(title)
        .accessibilityAddTraits(model.recordingCameraRound == round ? [.isSelected] : [])
        .accessibilityIdentifier("screenRecording.cameraShape." + (round ? "circle" : "rectangle"))
        .popover(isPresented: Binding(get: { !round && showsCameraCornerRadius }, set: { showsCameraCornerRadius = $0 })) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text(AppLocalization.text("圆角"))
                    Spacer()
                    Text(model.recordingCameraCornerRadius, format: .percent.precision(.fractionLength(0)))
                        .monospacedDigit()
                }.font(.caption)
                Slider(value: $model.recordingCameraCornerRadius, in: 0...0.5)
                    .accessibilityLabel(AppLocalization.text("圆角"))
                    .accessibilityValue(Text(model.recordingCameraCornerRadius, format: .percent.precision(.fractionLength(0))))
                    .accessibilityIdentifier("screenRecording.cameraCornerRadius")
            }.padding(14).frame(width: 240)
        }
    }

    private var cameraShapeControls: some View {
        HStack(spacing: 0) {
            cameraShapeButton(round: true)
            cameraShapeButton(round: false)
        }
    }

    private var cameraAspectRatioPicker: some View {
        Picker(AppLocalization.text("摄像头比例"), selection: Binding(
            get: { model.recordingCameraAspectRatio },
            set: { model.setRecordingCameraAspectRatio($0) }
        )) {
            ForEach(RecordingCameraAspectRatio.allCases, id: \.self) { ratio in
                Text(AppLocalization.text(ratio.title)).tag(ratio)
            }
        }
        .accessibilityValue(AppLocalization.text(model.recordingCameraAspectRatio.title))
        .accessibilityIdentifier("screenRecording.cameraAspectRatio")
    }

    private var recordingCameraOptionsMenu: some View {
        Menu { cameraAspectRatioPicker } label: {
            Image(systemName: "ellipsis.circle").font(.system(size: 14))
                .frame(width: 28, height: ScreenshotToolbarLayout.controlHeight)
        }
        .menuStyle(.borderlessButton).menuIndicator(.hidden).frame(width: 28)
        .help(AppLocalization.text("更多操作"))
        .accessibilityLabel(AppLocalization.text("更多操作"))
        .accessibilityIdentifier("screenRecording.captureOptions")
    }

    private var optionsMenu: some View {
        Menu {
            Picker(AppLocalization.text("麦克风"), selection: $model.configuration.microphoneID) {
                Text(AppLocalization.text("系统默认")).tag(Optional<String>.none)
                ForEach(model.capture.microphones) { device in Text(device.name).tag(Optional(device.id)) }
            }
            Picker(AppLocalization.text("摄像头"), selection: $model.configuration.cameraID) {
                Text(AppLocalization.text("系统默认")).tag(Optional<String>.none)
                ForEach(model.capture.cameras) { device in Text(device.name).tag(Optional(device.id)) }
            }
            cameraAspectRatioPicker
            Picker(AppLocalization.text("帧率"), selection: $model.configuration.frameRate) {
                ForEach([30, 60], id: \.self) { rate in Text("\(rate) FPS").tag(rate) }
            }
            Divider()
            Button(AppLocalization.text("刷新来源")) { Task { await model.loadSources() } }
                .accessibilityIdentifier("screenRecording.refreshCaptureSources")
            Button(AppLocalization.text("更改保存位置"), action: chooseDirectory)
                .help(AppLocalization.text("保存位置") + ": " + displaySaveDirectory())
                .accessibilityValue(displaySaveDirectory())
                .accessibilityIdentifier("screenRecording.captureSaveDirectory")
            Button(AppLocalization.text("录屏工作室"), action: openStudio)
                .accessibilityIdentifier("screenRecording.openStudio")
            Button(AppLocalization.text("打开录屏项目")) { openStudio(); model.openProject() }
            Button(AppLocalization.text("导入视频")) { openStudio(); model.importVideo() }
        } label: {
            Image(systemName: "ellipsis.circle").font(.system(size: 14))
                .frame(width: 28, height: ScreenshotToolbarLayout.controlHeight)
        }
        .menuStyle(.borderlessButton).menuIndicator(.hidden).frame(width: 28)
        .help(AppLocalization.text("更多操作"))
        .accessibilityLabel(AppLocalization.text("更多操作"))
        .accessibilityIdentifier("screenRecording.captureOptions")
    }

    private var recordingControls: some View {
        HStack(spacing: 8) {
            dragHandle
            if model.capture.phase == .recording || model.capture.phase == .paused,
               !model.isStopping, !model.isCancelling {
                Circle().fill(model.capture.phase == .paused ? Color.orange : Color.red).frame(width: 8, height: 8)
                Text(ScreenRecordingStudioView.clock(model.capture.elapsed))
                    .font(.system(size: 13, weight: .medium, design: .monospaced)).monospacedDigit()
                    .accessibilityIdentifier("screenRecording.captureElapsed")
                Spacer(minLength: 0)
                if model.configuration.camera {
                    HStack(spacing: 0) {
                        cameraShapeControls
                        recordingCameraOptionsMenu
                    }
                }
                Button(action: model.pause) {
                    Image(systemName: model.capture.phase == .paused ? "play.fill" : "pause.fill")
                        .frame(width: 28, height: ScreenshotToolbarLayout.controlHeight)
                }
                .buttonStyle(.plain)
                .help(AppLocalization.text(model.capture.phase == .paused ? "继续录制" : "暂停录制"))
                .accessibilityLabel(AppLocalization.text(model.capture.phase == .paused ? "继续录制" : "暂停录制"))
                .accessibilityIdentifier("screenRecording.pauseCapture")
                Button(action: model.stop) {
                    Image(systemName: "stop.fill").foregroundStyle(.red)
                        .frame(width: 28, height: ScreenshotToolbarLayout.controlHeight)
                }
                .buttonStyle(.plain).help(AppLocalization.text("停止录制"))
                .accessibilityLabel(AppLocalization.text("停止录制"))
                .accessibilityIdentifier("screenRecording.stopCapture")
            } else {
                ProgressView().controlSize(.small)
                Text(model.captureProgressMessage)
                    .font(.caption).lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityIdentifier("screenRecording.captureProgress")
                if !model.isStopping, !model.isCancelling {
                    Button(action: model.cancelOperation) {
                        Image(systemName: "xmark").frame(width: 28, height: ScreenshotToolbarLayout.controlHeight)
                    }
                        .buttonStyle(.plain)
                        .help(AppLocalization.text("取消"))
                        .accessibilityLabel(AppLocalization.text("取消"))
                        .accessibilityIdentifier("screenRecording.cancelCapture")
                }
            }
        }.padding(.horizontal, ScreenshotToolbarLayout.horizontalPadding).frame(height: ScreenshotToolbarLayout.height)
    }

    private var dragHandle: some View {
        ScreenRecordingCaptureBarDragHandle().frame(width: ScreenRecordingCaptureBarGeometry.dragHandleWidth,
            height: ScreenshotToolbarLayout.controlHeight)
            .help(AppLocalization.text("拖动工具栏"))
            .accessibilityLabel(AppLocalization.text("拖动工具栏"))
            .accessibilityIdentifier("screenRecording.captureBarDragHandle")
    }

    private var separator: some View {
        Divider().frame(width: 1, height: 20)
            .padding(.horizontal, ScreenRecordingCaptureBarGeometry.separatorHorizontalPadding)
    }

    private var canSelectRegion: Bool {
        ScreenRecordingCaptureBarGeometry.canSelectRegion(configuration: model.configuration,
            sources: model.capture.sources,
            displayIDs: NSScreen.screens.compactMap { ScreenshotCaptureService.displayID(for: $0) }
        )
    }

    private func symbol(for mode: RecordingCaptureMode) -> String {
        switch mode {
        case .display: "display"
        case .window: "macwindow"
        case .region: "rectangle.dashed"
        }
    }
}

private struct ScreenRecordingCaptureBarDragHandle: NSViewRepresentable {
    func makeNSView(context: Context) -> ScreenshotToolbarDragHandleView {
        let view = ScreenshotToolbarDragHandleView()
        let dots = ScreenRecordingDragDotsHostingView(rootView: ScreenshotToolbarDragDots())
        dots.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(dots)
        NSLayoutConstraint.activate([
            dots.leadingAnchor.constraint(equalTo: view.leadingAnchor), dots.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            dots.topAnchor.constraint(equalTo: view.topAnchor), dots.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        view.onMouseDown = { [weak view] event in view?.window?.performDrag(with: event) }
        return view
    }

    func updateNSView(_ nsView: ScreenshotToolbarDragHandleView, context: Context) {}
}

private final class ScreenRecordingDragDotsHostingView: NSHostingView<ScreenshotToolbarDragDots> {
    // Keep the decorative SwiftUI view from intercepting the AppKit handle's drag events.
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}
