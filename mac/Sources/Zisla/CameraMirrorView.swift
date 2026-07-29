import AppKit
@preconcurrency import AVFoundation
import SwiftUI

/// Camera "mirror" preview: fills the available space with a live mirrored feed, for the Dynamic Island as a grooming aid.
///
/// Lifecycle is driven by SwiftUI — on appear it checks/requests .video permission and starts the session on a background queue;
/// on disappear or close it stops the session and removes inputs (turning off the camera indicator light).
/// Permission denied/restricted, no device, and configuration failures all fall through to a concise error state; the normal state shows no extra UI.
struct CameraMirrorView: View {
    var onClose: () -> Void

    @StateObject private var controller = CameraMirrorController()
    @State private var isHovering = false

    init(onClose: @escaping () -> Void) {
        self.onClose = onClose
    }

    var body: some View {
        ZStack {
            Color.black
            content
        }
        .overlay(alignment: .topTrailing) {
            closeButton
                .opacity(isHovering ? 1 : 0)
                .allowsHitTesting(isHovering)
                .animation(.easeInOut(duration: 0.15), value: isHovering)
        }
        .contentShape(Rectangle())
        .onHover { isHovering = $0 }
        .onAppear { controller.start() }
        .onDisappear { controller.stop() }
    }

    @ViewBuilder
    private var content: some View {
        switch controller.status {
        case .idle, .preparing:
            VStack(spacing: 9) {
                ProgressView()
                    .controlSize(.small)
                    .tint(.white)
                Text("正在开启摄像头…")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.white.opacity(0.85))
            }
        case .running:
            CameraPreview(session: controller.session)
                .ignoresSafeArea()
        case let .failed(reason):
            EmptyState(
                symbol: reason.symbol,
                title: reason.title,
                detail: reason.detail,
                tint: .zislaError
            )
            .padding(.horizontal, 12)
        }
    }

    private var closeButton: some View {
        Button(action: onClose) {
            Image(systemName: "xmark")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 24, height: 24)
                .background(.black.opacity(0.55), in: Circle())
        }
        .buttonStyle(.plain)
        .help("关闭镜子")
        .padding(8)
    }
}

// MARK: - AVCaptureVideoPreviewLayer host view

/// Fills the view with the session's live feed via `AVCaptureVideoPreviewLayer`, and sets the connection to mirror horizontally.
private struct CameraPreview: NSViewRepresentable {
    let session: AVCaptureSession

    func makeNSView(context: Context) -> CameraPreviewNSView {
        let view = CameraPreviewNSView()
        view.attach(session: session)
        return view
    }

    func updateNSView(_ nsView: CameraPreviewNSView, context: Context) {
        nsView.attach(session: session)
    }
}

/// Layer-hosting `NSView`: fill-mode video + mirrored connection. Uses a layer-backed view;
/// the preview layer resizes with the view automatically.
private final class CameraPreviewNSView: NSView {
    private let previewLayer = AVCaptureVideoPreviewLayer()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        // Layer-hosting: assign the custom layer before setting wantsLayer, to prevent AppKit from creating a default layer that then gets replaced.
        previewLayer.videoGravity = .resizeAspectFill
        previewLayer.backgroundColor = NSColor.black.cgColor
        layer = previewLayer
        wantsLayer = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func attach(session: AVCaptureSession) {
        guard previewLayer.session !== session else { return }
        previewLayer.session = session
        if let connection = previewLayer.connection, connection.isVideoMirroringSupported {
            connection.automaticallyAdjustsVideoMirroring = false
            connection.isVideoMirrored = true
        }
    }
}

// MARK: - Session controller

/// Main-actor controller that owns the `AVCaptureSession`. Session configuration and start/stop always happen on a serial background queue
/// to avoid blocking the main thread; only status writes are dispatched back to the main actor for SwiftUI observation.
@MainActor
private final class CameraMirrorController: ObservableObject {
    enum FailureReason: Equatable {
        case denied      // user denied, or previously denied
        case restricted  // parental controls / MDM policy
        case unavailable // no camera found
        case configuration // failed to open device or configure session

        var symbol: String {
            switch self {
            case .denied: "video.slash"
            case .restricted: "lock.shield"
            case .unavailable: "video.slash"
            case .configuration: "exclamationmark.triangle"
            }
        }

        var title: String {
            switch self {
            case .denied: "未获得摄像头权限"
            case .restricted: "摄像头访问受限"
            case .unavailable: "未检测到摄像头"
            case .configuration: "无法开启摄像头"
            }
        }

        var detail: String? {
            switch self {
            case .denied: "请在系统设置 › 隐私与安全性 › 摄像头中允许 Zisla"
            case .restricted: "当前系统策略禁止访问摄像头"
            case .unavailable: "没有可用的视频输入设备"
            case .configuration: "请稍后重试或检查是否被其他应用占用"
            }
        }
    }

    enum Status: Equatable {
        case idle
        case preparing
        case running
        case failed(FailureReason)
    }

    @Published private(set) var status: Status = .idle

    // Session and input are accessed only on sessionQueue; nonisolated(unsafe) lets background queue closures capture them directly,
    // with mutual exclusion guaranteed by the serial queue rather than the actor. Reading the session reference from the main thread for the preview layer is permitted by AVFoundation.
    nonisolated(unsafe) let session = AVCaptureSession()
    nonisolated(unsafe) private var deviceInput: AVCaptureDeviceInput?
    private let sessionQueue = DispatchQueue(label: "com.zisla.camera-mirror.session")

    func start() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            status = .preparing
            configureAndStart()
        case .notDetermined:
            status = .preparing
            Self.requestVideoAccess { [weak self] granted in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    if granted {
                        self.configureAndStart()
                    } else {
                        self.status = .failed(.denied)
                    }
                }
            }
        case .restricted:
            status = .failed(.restricted)
        case .denied:
            status = .failed(.denied)
        @unknown default:
            status = .failed(.denied)
        }
    }

    func stop() {
        sessionQueue.async { [session] in
            if session.isRunning {
                session.stopRunning()
            }
            for input in session.inputs {
                session.removeInput(input)
            }
        }
        deviceInput = nil
        if status != .idle {
            status = .idle
        }
    }

    private func configureAndStart() {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            let result = self.configureSession()
            Task { @MainActor [weak self] in
                guard let self else { return }
                switch result {
                case .success:
                    self.status = .running
                case let .failure(error):
                    if case let .reason(reason) = error {
                        self.status = .failed(reason)
                    }
                }
            }
        }
    }

    /// Configures and starts the session on sessionQueue. Returns the result for the main actor to update state.
    nonisolated private func configureSession() -> Result<Void, ConfigurationError> {
        guard let device = AVCaptureDevice.default(for: .video) else {
            return .failure(.reason(.unavailable))
        }
        guard let input = try? AVCaptureDeviceInput(device: device) else {
            return .failure(.reason(.configuration))
        }

        session.beginConfiguration()
        if session.canSetSessionPreset(.high) {
            session.sessionPreset = .high
        }
        for existing in session.inputs {
            session.removeInput(existing)
        }
        guard session.canAddInput(input) else {
            session.commitConfiguration()
            return .failure(.reason(.configuration))
        }
        session.addInput(input)
        deviceInput = input
        session.commitConfiguration()

        if !session.isRunning {
            session.startRunning()
        }
        return .success(())
    }

    /// Wraps a failure reason for passing across sessionQueue → main actor (FailureReason is itself Sendable).
    fileprivate enum ConfigurationError: Error {
        case reason(FailureReason)
    }

    // The system authorization callback runs on an arbitrary queue and cannot inherit the controller's main-actor isolation.
    nonisolated private static func requestVideoAccess(
        _ completion: @escaping @Sendable (Bool) -> Void
    ) {
        AVCaptureDevice.requestAccess(for: .video, completionHandler: completion)
    }
}
