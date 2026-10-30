import AppKit
import AVFoundation
import Combine
import ZislaCore

enum ScreenRecordingCameraPreviewLayout {
    static let controlsInset: CGFloat = 10

    enum Corner: CaseIterable {
        case topLeft, topRight, bottomLeft, bottomRight

        var isLeft: Bool { self == .topLeft || self == .bottomLeft }
        var isTop: Bool { self == .topLeft || self == .topRight }

        func point(in frame: CGRect) -> CGPoint {
            CGPoint(x: isLeft ? frame.minX : frame.maxX, y: isTop ? frame.maxY : frame.minY)
        }
    }

    static func frame(configuration: RecordingEdits, visibleFrame: CGRect, center: CGPoint? = nil) -> CGRect {
        let inset = min(24, min(visibleFrame.width, visibleFrame.height) / 10)
        let available = visibleFrame.insetBy(dx: inset, dy: inset)
        let ratio = CGFloat(configuration.effectiveCameraAspectRatio.ratio)
        let preferredWidth = min(320, max(120, min(visibleFrame.width, visibleFrame.height) * configuration.cameraSize))
        let width = min(preferredWidth, available.width, available.height * ratio)
        let height = min(width / ratio, available.height)
        if let center {
            return CGRect(x: min(max(available.minX, center.x - width / 2), available.maxX - width),
                          y: min(max(available.minY, center.y - height / 2), available.maxY - height),
                          width: width, height: height)
        }
        let left = configuration.cameraPosition == .topLeft || configuration.cameraPosition == .bottomLeft
        let top = configuration.cameraPosition == .topLeft || configuration.cameraPosition == .topRight
        return CGRect(x: left ? available.minX : available.maxX - width,
                      y: top ? available.maxY - height : available.minY,
                      width: width, height: height)
    }

    static func resize(frame: CGRect, corner: Corner, translation: CGSize, visibleFrame: CGRect) -> (frame: CGRect, size: Double) {
        let ratio = frame.width / frame.height
        let inset = min(24, min(visibleFrame.width, visibleFrame.height) / 10)
        let available = visibleFrame.insetBy(dx: inset, dy: inset)
        let anchor = CGPoint(x: corner.isLeft ? frame.maxX : frame.minX,
                             y: corner.isTop ? frame.minY : frame.maxY)
        let maximumWidth = min(320, max(120, min(visibleFrame.width, visibleFrame.height) * 0.5),
                               corner.isLeft ? anchor.x - available.minX : available.maxX - anchor.x,
                               (corner.isTop ? available.maxY - anchor.y : anchor.y - available.minY) * ratio)
        let minimumWidth = min(maximumWidth, max(120, min(visibleFrame.width, visibleFrame.height) * 0.1))
        let dx = corner.isLeft ? -translation.width : translation.width
        let dy = corner.isTop ? translation.height : -translation.height
        let width = min(maximumWidth, max(minimumWidth, frame.width + (dx + dy / ratio) / (1 + 1 / (ratio * ratio))))
        let height = width / ratio
        return (CGRect(x: corner.isLeft ? anchor.x - width : anchor.x,
                       y: corner.isTop ? anchor.y : anchor.y - height, width: width, height: height),
                min(0.5, max(0.1, Double(width / min(visibleFrame.width, visibleFrame.height)))))
    }

    static func cornerRadius(start: Double, translation: CGFloat, side: CGFloat) -> Double {
        min(0.5, max(0, start + Double(translation / side)))
    }

    static func radiusHandle(in bounds: CGRect, radius: Double) -> CGPoint {
        CGPoint(x: min(bounds.maxX - 18, bounds.minX + 18 + (min(bounds.width, bounds.height) - 36) * radius),
                y: bounds.maxY - 4)
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

    init(capture: ScreenRecordingService, changeSize: @escaping (Double) -> Void,
         changeCornerRadius: @escaping (Double) -> Void) {
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
        panel.isMovableByWindowBackground = false
        panel.sharingType = .none
        preview = ScreenRecordingCameraPreviewView(frame: CGRect(origin: .zero, size: panel.frame.size))
        panel.contentView = preview
        preview.onResize = { [weak self] corner, frame, translation in
            guard let self, let screen = NSScreen.screens.first(where: {
                $0.frame.contains(CGPoint(x: frame.midX, y: frame.midY))
            }) ?? panel.screen ?? NSScreen.main else { return }
            let resized = ScreenRecordingCameraPreviewLayout.resize(frame: frame, corner: corner,
                translation: translation, visibleFrame: screen.visibleFrame)
            configuration.cameraSize = resized.size
            panel.setFrame(resized.frame.insetBy(dx: -ScreenRecordingCameraPreviewLayout.controlsInset,
                                                dy: -ScreenRecordingCameraPreviewLayout.controlsInset).integral, display: true)
            changeSize(resized.size)
        }
        preview.onCornerRadiusChange = { [weak self] radius in
            guard let self else { return }
            configuration.cameraCornerRadius = radius
            refresh(session: capture.cameraPreviewSession, state: capture.cameraPreviewState)
            changeCornerRadius(radius)
        }
        capture.$cameraPreviewSession.combineLatest(capture.$cameraPreviewState).sink { [weak self] session, state in
            self?.refresh(session: session, state: state)
        }.store(in: &subscriptions)
    }

    func present(configuration: RecordingEdits = .init(), screen: NSScreen? = nil) {
        isPresented = true
        if !placed, let screen = screen ?? NSScreen.screens.first(where: { $0.frame.contains(NSEvent.mouseLocation) }) ?? NSScreen.main {
            let frame = ScreenRecordingCameraPreviewLayout.frame(configuration: configuration, visibleFrame: screen.visibleFrame)
            panel.setFrame(frame.insetBy(dx: -ScreenRecordingCameraPreviewLayout.controlsInset,
                                        dy: -ScreenRecordingCameraPreviewLayout.controlsInset).integral, display: false)
            placed = true
        }
        update(configuration: configuration)
    }

    func update(configuration: RecordingEdits) {
        let layoutChanged = self.configuration.cameraPosition != configuration.cameraPosition
            || self.configuration.effectiveCameraAspectRatio != configuration.effectiveCameraAspectRatio
            || self.configuration.cameraSize != configuration.cameraSize
        let positionChanged = self.configuration.cameraPosition != configuration.cameraPosition
        self.configuration = configuration
        if layoutChanged, let screen = panel.screen ?? NSScreen.main {
            let frame = ScreenRecordingCameraPreviewLayout.frame(configuration: configuration,
                visibleFrame: screen.visibleFrame,
                center: positionChanged ? nil : CGPoint(x: panel.frame.midX, y: panel.frame.midY))
            panel.setFrame(frame.insetBy(dx: -ScreenRecordingCameraPreviewLayout.controlsInset,
                                        dy: -ScreenRecordingCameraPreviewLayout.controlsInset).integral, display: true)
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

final class ScreenRecordingCameraPreviewView: NSView {
    private enum Drag {
        case resize(ScreenRecordingCameraPreviewLayout.Corner, CGRect, CGPoint)
        case cornerRadius(Double, CGFloat, CGPoint)
    }

    private let previewLayer = AVCaptureVideoPreviewLayer()
    private let cameraLayer = CALayer()
    private let handlesLayer = CAShapeLayer()
    private let status = NSTextField(wrappingLabelWithString: "")
    private let spinner = NSProgressIndicator()
    private var cornerRadiusRatio: CGFloat = 0.5
    private var showsBorder = false
    private var tracking: NSTrackingArea?
    private var hovered = false
    private var drag: Drag?
    var onResize: ((ScreenRecordingCameraPreviewLayout.Corner, CGRect, CGSize) -> Void)?
    var onCornerRadiusChange: ((Double) -> Void)?

    override var mouseDownCanMoveWindow: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { super.hitTest(point).map { _ in self } }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        cameraLayer.backgroundColor = NSColor.black.cgColor
        cameraLayer.borderColor = NSColor.white.withAlphaComponent(0.8).cgColor
        cameraLayer.masksToBounds = true
        layer?.addSublayer(cameraLayer)
        previewLayer.videoGravity = .resizeAspectFill
        cameraLayer.addSublayer(previewLayer)
        handlesLayer.fillColor = NSColor.white.cgColor
        handlesLayer.strokeColor = NSColor.black.withAlphaComponent(0.65).cgColor
        handlesLayer.lineWidth = 1
        handlesLayer.isHidden = true
        layer?.addSublayer(handlesLayer)
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
        let inset = ScreenRecordingCameraPreviewLayout.controlsInset
        let cameraFrame = bounds.insetBy(dx: inset, dy: inset)
        cameraLayer.frame = cameraFrame
        previewLayer.frame = cameraLayer.bounds
        handlesLayer.frame = bounds
        cameraLayer.cornerRadius = min(cameraFrame.width, cameraFrame.height) * cornerRadiusRatio
        cameraLayer.borderWidth = showsBorder ? min(cameraFrame.width, cameraFrame.height) * 0.01 : 0
        let handles = CGMutablePath()
        for corner in ScreenRecordingCameraPreviewLayout.Corner.allCases {
            let point = corner.point(in: bounds.insetBy(dx: 6, dy: 6))
            handles.addEllipse(in: CGRect(x: point.x - 4, y: point.y - 4, width: 8, height: 8))
        }
        let radius = ScreenRecordingCameraPreviewLayout.radiusHandle(in: cameraFrame, radius: Double(cornerRadiusRatio))
        handles.addEllipse(in: CGRect(x: radius.x - 4, y: radius.y - 4, width: 8, height: 8))
        handlesLayer.path = handles
        handlesLayer.isHidden = !hovered && drag == nil
        CATransaction.commit()
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let tracking = NSTrackingArea(rect: .zero, options: [.activeAlways, .mouseEnteredAndExited, .inVisibleRect],
                                      owner: self, userInfo: nil)
        addTrackingArea(tracking)
        self.tracking = tracking
    }

    override func mouseEntered(with event: NSEvent) { hovered = true; needsLayout = true }
    override func mouseExited(with event: NSEvent) { hovered = false; needsLayout = true }

    override func mouseDown(with event: NSEvent) {
        guard let window else { return }
        let point = convert(event.locationInWindow, from: nil)
        let origin = window.convertPoint(toScreen: event.locationInWindow)
        let inset = ScreenRecordingCameraPreviewLayout.controlsInset
        let cameraFrame = bounds.insetBy(dx: inset, dy: inset)
        let radius = ScreenRecordingCameraPreviewLayout.radiusHandle(in: cameraFrame, radius: Double(cornerRadiusRatio))
        if hypot(point.x - radius.x, point.y - radius.y) <= 9 {
            drag = .cornerRadius(Double(cornerRadiusRatio), min(cameraFrame.width, cameraFrame.height) - 36, origin)
        } else if let corner = ScreenRecordingCameraPreviewLayout.Corner.allCases.first(where: {
            let handle = $0.point(in: bounds.insetBy(dx: 6, dy: 6))
            return hypot(point.x - handle.x, point.y - handle.y) <= 9
        }) {
            drag = .resize(corner, window.frame.insetBy(dx: inset, dy: inset), origin)
        } else { window.performDrag(with: event) }
        needsLayout = true
    }

    override func mouseDragged(with event: NSEvent) {
        guard let window, let drag else { return }
        let point = window.convertPoint(toScreen: event.locationInWindow)
        switch drag {
        case let .resize(corner, frame, origin):
            onResize?(corner, frame, CGSize(width: point.x - origin.x, height: point.y - origin.y))
        case let .cornerRadius(radius, side, origin):
            onCornerRadiusChange?(ScreenRecordingCameraPreviewLayout.cornerRadius(start: radius,
                translation: point.x - origin.x, side: side))
        }
    }

    override func mouseUp(with event: NSEvent) { drag = nil; needsLayout = true }

    func update(session: AVCaptureSession?, state: ScreenRecordingCameraPreviewState, configuration: RecordingEdits) {
        if previewLayer.session !== session { previewLayer.session = session }
        if let connection = previewLayer.connection, connection.isVideoMirroringSupported {
            connection.automaticallyAdjustsVideoMirroring = false
            connection.isVideoMirrored = configuration.cameraMirrored
        }
        cornerRadiusRatio = configuration.effectiveCameraCornerRadius
        showsBorder = configuration.effectiveCameraBorder
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
