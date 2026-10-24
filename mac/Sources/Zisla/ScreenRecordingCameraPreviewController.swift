import AppKit
import AVFoundation
import Combine
import ZislaCore

enum ScreenRecordingCameraPreviewLayout {
    static func frame(configuration: RecordingEdits, visibleFrame: CGRect) -> CGRect {
        let inset = min(24, min(visibleFrame.width, visibleFrame.height) / 10)
        let available = visibleFrame.insetBy(dx: inset, dy: inset)
        let width = min(320, max(120, min(visibleFrame.width, visibleFrame.height) * configuration.cameraSize),
                        available.width, configuration.cameraRound ? available.height : .greatestFiniteMagnitude)
        let height = min(configuration.cameraRound ? width : width * 0.75, available.height)
        let left = configuration.cameraPosition == .topLeft || configuration.cameraPosition == .bottomLeft
        let top = configuration.cameraPosition == .topLeft || configuration.cameraPosition == .topRight
        return CGRect(x: left ? available.minX : available.maxX - width,
                      y: top ? available.maxY - height : available.minY,
                      width: width, height: height)
    }
}

@MainActor
final class ScreenRecordingCameraPreviewController {
    private let capture: ScreenRecordingService
    private let panel: NSPanel
    private let preview: ScreenRecordingCameraPreviewView
    private var subscriptions: Set<AnyCancellable> = []
    private var configuration = RecordingEdits()
    private var isPresented = false
    private var placed = false

    init(capture: ScreenRecordingService) {
        self.capture = capture
        panel = NSPanel(contentRect: CGRect(x: 0, y: 0, width: 200, height: 200),
                        styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isReleasedWhenClosed = false
        panel.title = AppLocalization.text("摄像头叠加")
        panel.setAccessibilityIdentifier("screenRecording.cameraPreview")
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isMovableByWindowBackground = true
        panel.sharingType = .none
        preview = ScreenRecordingCameraPreviewView(frame: CGRect(origin: .zero, size: panel.frame.size))
        panel.contentView = preview
        capture.$cameraPreviewSession.combineLatest(capture.$cameraPreviewState).sink { [weak self] session, state in
            self?.refresh(session: session, state: state)
        }.store(in: &subscriptions)
    }

    func present(configuration: RecordingEdits = .init(), screen: NSScreen? = nil) {
        isPresented = true
        if !placed, let screen = screen ?? NSScreen.screens.first(where: { $0.frame.contains(NSEvent.mouseLocation) }) ?? NSScreen.main {
            panel.setFrame(ScreenRecordingCameraPreviewLayout.frame(configuration: configuration, visibleFrame: screen.visibleFrame), display: false)
            placed = true
        }
        update(configuration: configuration)
    }

    func update(configuration: RecordingEdits) {
        let layoutChanged = self.configuration.cameraPosition != configuration.cameraPosition
            || self.configuration.cameraRound != configuration.cameraRound
            || self.configuration.cameraSize != configuration.cameraSize
        self.configuration = configuration
        if layoutChanged, let screen = panel.screen ?? NSScreen.main {
            panel.setFrame(ScreenRecordingCameraPreviewLayout.frame(configuration: configuration, visibleFrame: screen.visibleFrame), display: true)
        }
        refresh(session: capture.cameraPreviewSession, state: capture.cameraPreviewState)
    }

    func hide() {
        isPresented = false
        panel.orderOut(nil)
    }

    func shutdown() {
        hide()
        subscriptions.removeAll()
        preview.detach()
        Task { [capture] in await capture.stopCameraPreview() }
    }

    private func refresh(session: AVCaptureSession?, state: ScreenRecordingCameraPreviewState) {
        preview.update(session: session, state: state, configuration: configuration)
        if isPresented, state != .idle { panel.orderFrontRegardless() }
        else { panel.orderOut(nil) }
    }
}

private final class ScreenRecordingCameraPreviewView: NSView {
    private let previewLayer = AVCaptureVideoPreviewLayer()
    private let status = NSTextField(wrappingLabelWithString: "")
    private let spinner = NSProgressIndicator()
    private var cornerRadiusRatio: CGFloat = 0.5

    override var mouseDownCanMoveWindow: Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor
        layer?.borderWidth = 2
        layer?.borderColor = NSColor.white.withAlphaComponent(0.8).cgColor
        layer?.masksToBounds = true
        previewLayer.videoGravity = .resizeAspectFill
        layer?.addSublayer(previewLayer)
        status.alignment = .center
        status.textColor = .white
        status.font = .systemFont(ofSize: 12, weight: .medium)
        status.isSelectable = false
        status.translatesAutoresizingMaskIntoConstraints = false
        addSubview(status)
        spinner.style = .spinning
        spinner.controlSize = .small
        spinner.isDisplayedWhenStopped = false
        spinner.translatesAutoresizingMaskIntoConstraints = false
        addSubview(spinner)
        NSLayoutConstraint.activate([
            status.centerXAnchor.constraint(equalTo: centerXAnchor),
            status.centerYAnchor.constraint(equalTo: centerYAnchor, constant: 14),
            status.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: 18),
            status.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -18),
            spinner.centerXAnchor.constraint(equalTo: centerXAnchor),
            spinner.bottomAnchor.constraint(equalTo: status.topAnchor, constant: -10),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        previewLayer.frame = bounds
        layer?.cornerRadius = min(bounds.width, bounds.height) * cornerRadiusRatio
        CATransaction.commit()
    }

    func update(session: AVCaptureSession?, state: ScreenRecordingCameraPreviewState, configuration: RecordingEdits) {
        if previewLayer.session !== session { previewLayer.session = session }
        if let connection = previewLayer.connection, connection.isVideoMirroringSupported {
            connection.automaticallyAdjustsVideoMirroring = false
            connection.isVideoMirrored = configuration.cameraMirrored
        }
        cornerRadiusRatio = configuration.effectiveCameraCornerRadius
        switch state {
        case .idle:
            spinner.stopAnimation(nil)
            status.isHidden = true
        case .preparing:
            spinner.startAnimation(nil)
            status.stringValue = AppLocalization.text("正在开启摄像头…")
            status.isHidden = false
        case .running:
            spinner.stopAnimation(nil)
            status.isHidden = true
        case let .failed(message):
            spinner.stopAnimation(nil)
            status.stringValue = message
            status.isHidden = false
        }
        needsLayout = true
    }

    func detach() { previewLayer.session = nil }
}
