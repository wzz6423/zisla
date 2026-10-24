import AppKit
import AVFoundation
import Combine
import Testing
import ZislaCore

@testable import Zisla

@Suite @MainActor
struct ScreenRecordingCameraPreviewTests {
    @Test
    func preparedCameraRemainsTheRecordingCameraAndReleasesAfterStop() async throws {
        let system = CameraPreviewTestSystem()
        let service = ScreenRecordingService(dependencies: system.dependencies())
        let configuration = RecordingCaptureConfiguration(camera: true, cameraID: "camera-a")
        try await service.prepareCameraPreview(configuration: configuration)
        let camera = try #require(system.cameras.first)
        #expect(service.phase == .idle)
        #expect(service.cameraPreviewState == .running)
        #expect(service.cameraPreviewSession === camera.previewSession)

        try await service.start(configuration: configuration, directory: system.directory)
        #expect(system.capture.camera === camera)
        #expect(system.cameras.count == 1, "准备和录制必须共享同一个摄像头会话，防止设备争用")
        #expect(service.cameraPreviewSession === camera.previewSession)
        #expect(camera.running)
        _ = try await service.stop()
        #expect(service.cameraPreviewSession == nil)
        #expect(service.cameraPreviewState == .idle)
        #expect(!camera.running)
        #expect(camera.released)
    }

    @Test
    func enablingCameraOnlyRequestsCameraPermission() async throws {
        let system = CameraPreviewTestSystem()
        let service = ScreenRecordingService(dependencies: system.dependencies())
        try await service.prepareCameraPreview(configuration: .init(microphone: true, camera: true))
        #expect(system.permissions == [.camera])
        #expect(!system.capture.started)
        await service.stopCameraPreview()
        #expect(system.cameras.allSatisfy { $0.released })
    }

    @Test
    func deniedCameraPermissionIsVisibleWithoutAllocatingAnInput() async {
        let system = CameraPreviewTestSystem()
        system.denied = .camera
        let service = ScreenRecordingService(dependencies: system.dependencies())
        await #expect(throws: ScreenRecordingCaptureError.permission(.camera)) {
            try await service.prepareCameraPreview(configuration: .init(camera: true))
        }
        #expect(service.phase == .idle)
        #expect(service.cameraPreviewSession == nil)
        #expect(service.cameraPreviewState == .failed(ScreenRecordingCaptureError.permission(.camera).localizedDescription))
        #expect(system.cameras.isEmpty)
        await service.stopCameraPreview()
        #expect(service.cameraPreviewState == .idle)
    }

    @Test
    func unavailableCameraReleasesPartialSetupAndCanRecover() async throws {
        let system = CameraPreviewTestSystem()
        system.cameraStartError = CameraPreviewTestError.unavailable
        let service = ScreenRecordingService(dependencies: system.dependencies())
        await #expect(throws: CameraPreviewTestError.unavailable) {
            try await service.prepareCameraPreview(configuration: .init(camera: true))
        }
        #expect(system.cameras.first?.released == true)
        #expect(service.cameraPreviewSession == nil)
        #expect(service.cameraPreviewState == .failed(CameraPreviewTestError.unavailable.localizedDescription))

        system.cameraStartError = nil
        try await service.prepareCameraPreview(configuration: .init(camera: true))
        #expect(service.cameraPreviewSession === system.cameras.last?.previewSession)
        #expect(service.cameraPreviewState == .running)
        await service.stopCameraPreview()
        #expect(system.cameras.allSatisfy { $0.released })
    }

    @Test
    func closingSetupDuringAuthorizationPreventsALateCameraActivation() async throws {
        let system = CameraPreviewTestSystem()
        let permission = CameraPreviewTestLatch<Bool>()
        let entered = CameraPreviewTestSignal()
        var dependencies = system.dependencies()
        dependencies.requestPermission = { _ in entered.signal(); return try! await permission.wait() }
        let service = ScreenRecordingService(dependencies: dependencies)
        let task = Task { try await service.prepareCameraPreview(configuration: .init(camera: true)) }
        await entered.wait()
        await service.stopCameraPreview()
        permission.resolve(.success(true))
        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(system.cameras.isEmpty)
        #expect(service.cameraPreviewState == .idle)
        #expect(service.cameraPreviewSession == nil)
    }

    @Test
    func disablingCameraDuringDeviceStartupPreventsLatePreviewPublication() async throws {
        let system = CameraPreviewTestSystem()
        let gate = CameraPreviewTestLatch<Void>()
        system.cameraStartGate = gate
        let service = ScreenRecordingService(dependencies: system.dependencies())
        let task = Task { try await service.prepareCameraPreview(configuration: .init(camera: true)) }
        await system.cameraCreated.wait()
        let camera = try #require(system.cameras.first)
        await camera.entered.wait()
        let closed = CameraPreviewTestSignal()
        let subscription = service.$cameraPreviewState.dropFirst().sink { state in
            if state == .idle { closed.signal() }
        }
        let closing = Task { try await service.prepareCameraPreview(configuration: .init(camera: false)) }
        await closed.wait()
        gate.resolve(.success(()))
        try await closing.value
        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(camera.released)
        #expect(!camera.running)
        #expect(service.cameraPreviewState == .idle)
        #expect(service.cameraPreviewSession == nil)
        withExtendedLifetime(subscription) {}
    }

    @Test
    func changingDeviceDuringStartupReleasesTheLateStartingCameraBeforeOpeningItsReplacement() async throws {
        let system = CameraPreviewTestSystem()
        let gate = CameraPreviewTestLatch<Void>()
        system.cameraStartGate = gate
        let service = ScreenRecordingService(dependencies: system.dependencies())
        let starting = Task { try await service.prepareCameraPreview(configuration: .init(camera: true, cameraID: "camera-a")) }
        await system.cameraCreated.wait()
        let old = try #require(system.cameras.first)
        await old.entered.wait()
        let replacing = CameraPreviewTestSignal()
        let subscription = service.$cameraPreviewState.dropFirst().sink { state in
            if state == .preparing { replacing.signal() }
        }
        let switching = Task { try await service.prepareCameraPreview(configuration: .init(camera: true, cameraID: "camera-b")) }
        await replacing.wait()
        #expect(system.cameras.count == 1)
        gate.resolve(.success(()))
        await #expect(throws: CancellationError.self) { try await starting.value }
        try await switching.value
        #expect(old.released && !old.running, "迟到的旧会话必须停止，才能把摄像头交给新会话")
        #expect(system.cameras.map(\.identifier) == ["camera-a", "camera-b"])
        #expect(service.cameraPreviewSession === system.cameras.last?.previewSession)
        #expect(system.cameras.last?.running == true)
        await service.stopCameraPreview()
        #expect(system.cameras.allSatisfy { $0.released && !$0.running })
        withExtendedLifetime(subscription) {}
    }

    @Test
    func recordingWaitsForPendingPreviewInsteadOfOpeningASecondCamera() async throws {
        let system = CameraPreviewTestSystem()
        let gate = CameraPreviewTestLatch<Void>()
        system.cameraStartGate = gate
        let service = ScreenRecordingService(dependencies: system.dependencies())
        let configuration = RecordingCaptureConfiguration(camera: true)
        let previewTask = Task { try await service.prepareCameraPreview(configuration: configuration) }
        await system.cameraCreated.wait()
        let preparing = CameraPreviewTestSignal()
        let subscription = service.$phase.sink { phase in if phase == .preparing { preparing.signal() } }
        let recordingTask = Task { try await service.start(configuration: configuration, directory: system.directory) }
        await preparing.wait()
        #expect(!system.capture.started)
        gate.resolve(.success(()))
        try await previewTask.value
        try await recordingTask.value
        #expect(system.cameras.count == 1)
        #expect(system.capture.camera === system.cameras.first)
        #expect(service.phase == .recording)
        await service.cancel()
        #expect(system.cameras.allSatisfy { $0.released })
        withExtendedLifetime(subscription) {}
    }

    @Test
    func changingCameraIgnoresFailuresFromTheReleasedDevice() async throws {
        let system = CameraPreviewTestSystem()
        let service = ScreenRecordingService(dependencies: system.dependencies())
        try await service.prepareCameraPreview(configuration: .init(camera: true, cameraID: "camera-a"))
        try await service.prepareCameraPreview(configuration: .init(camera: true, cameraID: "camera-b"))
        let old = try #require(system.cameras.first)
        let current = try #require(system.cameras.last)
        #expect(old.released)
        #expect(current.identifier == "camera-b")
        await old.onFailure(CameraPreviewTestError.unavailable)
        #expect(service.cameraPreviewSession === current.previewSession)
        #expect(service.cameraPreviewState == .running)
        #expect(current.running)
        await service.stopCameraPreview()
    }

    @Test
    func rapidDeviceChangesWaitForThePreviousCameraToClose() async throws {
        let system = CameraPreviewTestSystem()
        let service = ScreenRecordingService(dependencies: system.dependencies())
        try await service.prepareCameraPreview(configuration: .init(camera: true, cameraID: "camera-a"))
        let previous = try #require(system.cameras.first)
        let stop = CameraPreviewTestLatch<Void>()
        previous.stopGate = stop
        let firstSwitch = Task { try await service.prepareCameraPreview(configuration: .init(camera: true, cameraID: "camera-b")) }
        await previous.stopping.wait()
        let preparing = CameraPreviewTestSignal()
        let subscription = service.$cameraPreviewState.dropFirst().sink { state in
            if state == .preparing { preparing.signal() }
        }
        let finalSwitch = Task { try await service.prepareCameraPreview(configuration: .init(camera: true, cameraID: "camera-c")) }
        await preparing.wait()
        #expect(system.cameras.count == 1, "旧设备尚未停止时不得打开另一摄像头")
        stop.resolve(.success(()))
        await #expect(throws: CancellationError.self) { try await firstSwitch.value }
        try await finalSwitch.value
        #expect(system.cameras.map(\.identifier) == ["camera-a", "camera-c"])
        #expect(previous.released)
        #expect(service.cameraPreviewSession === system.cameras.last?.previewSession)
        await service.stopCameraPreview()
        withExtendedLifetime(subscription) {}
    }

    @Test
    func runtimeDeviceFailureStopsPreviewAndExposesTheReason() async throws {
        let system = CameraPreviewTestSystem()
        let service = ScreenRecordingService(dependencies: system.dependencies())
        try await service.prepareCameraPreview(configuration: .init(camera: true))
        let camera = try #require(system.cameras.first)
        let failed = CameraPreviewTestSignal()
        let subscription = service.$cameraPreviewState.sink { state in
            if case .failed = state { failed.signal() }
        }
        await camera.onFailure(CameraPreviewTestError.unavailable)
        await failed.wait()
        #expect(service.cameraPreviewState == .failed(CameraPreviewTestError.unavailable.localizedDescription))
        #expect(service.cameraPreviewSession == nil)
        #expect(camera.released)
        #expect(!camera.running)
        withExtendedLifetime(subscription) {}
    }

    @Test
    func screenPermissionFailureReleasesAnAlreadyVisibleCamera() async throws {
        let system = CameraPreviewTestSystem()
        let service = ScreenRecordingService(dependencies: system.dependencies())
        let configuration = RecordingCaptureConfiguration(camera: true)
        try await service.prepareCameraPreview(configuration: configuration)
        system.denied = .screen
        await #expect(throws: ScreenRecordingCaptureError.permission(.screen)) {
            try await service.start(configuration: configuration, directory: system.directory)
        }
        #expect(service.phase == .idle)
        #expect(service.cameraPreviewSession == nil)
        #expect(system.cameras.allSatisfy { $0.released })
        #expect(!system.capture.started)
    }

    @Test
    func hidingSetupCannotStopTheCameraOwnedByAnActiveRecording() async throws {
        let system = CameraPreviewTestSystem()
        let service = ScreenRecordingService(dependencies: system.dependencies())
        try await service.start(configuration: .init(camera: true), directory: system.directory)
        await service.stopCameraPreview()
        #expect(service.phase == .recording)
        #expect(service.cameraPreviewState == .running)
        #expect(system.cameras.first?.running == true)
        await service.cancel()
        #expect(system.capture.cancelled)
        #expect(system.cameras.allSatisfy { $0.released })
        #expect(service.cameraPreviewSession == nil)
    }

    @Test
    func cancelAlsoReleasesAStandbyCameraBeforeRecordingStarts() async throws {
        let system = CameraPreviewTestSystem()
        let service = ScreenRecordingService(dependencies: system.dependencies())
        try await service.prepareCameraPreview(configuration: .init(camera: true))
        await service.cancel()
        #expect(service.phase == .idle)
        #expect(service.cameraPreviewState == .idle)
        #expect(service.cameraPreviewSession == nil)
        #expect(system.cameras.allSatisfy { $0.released })
    }

    @Test
    func runtimeCameraFailureCancelsTheActiveRecordingAndReleasesAllInputs() async throws {
        let system = CameraPreviewTestSystem()
        let service = ScreenRecordingService(dependencies: system.dependencies())
        try await service.start(configuration: .init(camera: true), directory: system.directory)
        let camera = try #require(system.cameras.first)
        await camera.onFailure(CameraPreviewTestError.unavailable)
        #expect(service.phase == .idle)
        #expect(service.errorMessage == CameraPreviewTestError.unavailable.localizedDescription)
        #expect(service.cameraPreviewState == .failed(CameraPreviewTestError.unavailable.localizedDescription))
        #expect(service.cameraPreviewSession == nil)
        #expect(system.capture.cancelled)
        #expect(camera.released)
        #expect(!camera.running)
    }

    @Test
    func cameraDisabledLeavesInputsAndPermissionStateUntouched() async throws {
        let system = CameraPreviewTestSystem()
        let service = ScreenRecordingService(dependencies: system.dependencies())
        try await service.prepareCameraPreview(configuration: .init())
        #expect(system.permissions.isEmpty)
        #expect(system.cameras.isEmpty)
        #expect(service.cameraPreviewState == .idle)
    }

    @Test(arguments: RecordingCameraPosition.allCases)
    func previewFitsSmallDisplaysAndNegativeScreenOrigins(position: RecordingCameraPosition) {
        for visibleFrame in [CGRect(x: -1920, y: -200, width: 1920, height: 1080),
                             CGRect(x: 50, y: 60, width: 90, height: 70)] {
            let configuration = RecordingEdits(cameraPosition: position, cameraSize: 0.5, cameraRound: true)
            let frame = ScreenRecordingCameraPreviewLayout.frame(configuration: configuration, visibleFrame: visibleFrame)
            #expect(visibleFrame.contains(frame))
            #expect(frame.width == frame.height)
            #expect(frame.width > 0 && frame.width <= 320)
        }
    }

    @Test
    func rectangularPreviewKeepsItsLandscapeRatio() {
        let frame = ScreenRecordingCameraPreviewLayout.frame(configuration: .init(cameraRound: false),
                                                              visibleFrame: CGRect(x: 0, y: 0, width: 1440, height: 900))
        #expect(frame.width > frame.height)
        #expect(frame.height == frame.width * 0.75)
    }

    @Test(arguments: [0.0, 0.1, 0.5])
    func customCameraRoundingDoesNotResizeOrMoveTheRectangularPreview(_ radius: Double) {
        let visible = CGRect(x: -1440, y: 100, width: 1440, height: 900)
        let configuration = RecordingEdits(cameraPosition: .topLeft, cameraRound: false, cameraCornerRadius: radius)
        let frame = ScreenRecordingCameraPreviewLayout.frame(configuration: configuration, visibleFrame: visible)
        let baseline = ScreenRecordingCameraPreviewLayout.frame(configuration: .init(cameraPosition: .topLeft, cameraRound: false),
                                                                 visibleFrame: visible)
        #expect(frame == baseline)
        #expect(frame.height == frame.width * 0.75)
        #expect(visible.contains(frame))
    }

    @Test
    func sourceFilterKeepsOtherApplicationWindowsAndExcludesOverlayAndUtilityWindows() {
        let frame = CGRect(x: -1200, y: -300, width: 600, height: 400)
        #expect(ScreenRecordingNativeCapture.includesWindow(frame: frame, layer: 0, processIdentifier: getpid() + 1,
                                                           isRegularApplication: true, isOnScreen: true, isActive: true, alpha: 1))
        #expect(!ScreenRecordingNativeCapture.includesWindow(frame: frame, layer: 0, processIdentifier: getpid(),
                                                            isRegularApplication: true, isOnScreen: true, isActive: true, alpha: 1))
        #expect(!ScreenRecordingNativeCapture.includesWindow(frame: frame, layer: 24, processIdentifier: getpid() + 1,
                                                            isRegularApplication: true, isOnScreen: true, isActive: true, alpha: 1))
        #expect(!ScreenRecordingNativeCapture.includesWindow(frame: CGRect(x: 0, y: 0, width: 1, height: 100),
                                                            layer: 0, processIdentifier: getpid() + 1, isRegularApplication: true,
                                                            isOnScreen: true, isActive: true, alpha: 1))
    }

    @Test
    func regularUntitledDocumentsRemainSelectableButCursorAndAutofillHelpersAreRejected() {
        let documentFrame = CGRect(x: -1200, y: -300, width: 600, height: 400)
        #expect(ScreenRecordingNativeCapture.includesWindow(frame: documentFrame, layer: 0, processIdentifier: getpid() + 1,
                                                           isRegularApplication: true, isOnScreen: true, isActive: true, alpha: 1),
                "TextEdit 等 regular 应用的未命名或被遮挡文稿仍应可选，过滤不得要求窗口标题")
        #expect(!ScreenRecordingNativeCapture.includesWindow(frame: documentFrame, layer: 0, processIdentifier: getpid() + 2,
                                                            isRegularApplication: false, isOnScreen: true, isActive: true, alpha: 1),
                "CursorUIViewService 和自动填充等 accessory/prohibited 辅助窗口不可成为录制来源")
        #expect(!ScreenRecordingNativeCapture.includesWindow(frame: documentFrame, layer: 0, processIdentifier: nil,
                                                            isRegularApplication: false, isOnScreen: true, isActive: true, alpha: 1))
    }

    @Test(arguments: [(onScreen: true, active: true, selectable: true),
                      (onScreen: true, active: false, selectable: true),
                      (onScreen: false, active: true, selectable: true),
                      (onScreen: false, active: false, selectable: false)])
    func sourceFilterKeepsVisibleAndStageManagerWindows(sample: (onScreen: Bool, active: Bool, selectable: Bool)) {
        let frame = CGRect(x: -1200, y: -300, width: 600, height: 400)
        #expect(ScreenRecordingNativeCapture.includesWindow(frame: frame, layer: 0, processIdentifier: getpid() + 1,
                                                           isRegularApplication: true, isOnScreen: sample.onScreen,
                                                           isActive: sample.active, alpha: 1) == sample.selectable)
    }

    @Test(arguments: [(alpha: 0.0, selectable: false), (alpha: 0.01, selectable: false),
                      (alpha: 0.010001, selectable: true), (alpha: 1.0, selectable: true)])
    func sourceFilterRejectsTransparentWindows(sample: (alpha: Double, selectable: Bool)) {
        let frame = CGRect(x: 0, y: 0, width: 600, height: 400)
        #expect(ScreenRecordingNativeCapture.includesWindow(frame: frame, layer: 0, processIdentifier: getpid() + 1,
                                                           isRegularApplication: true, isOnScreen: true,
                                                           isActive: true, alpha: sample.alpha) == sample.selectable)
    }

    @Test(arguments: [(onScreen: true, active: false), (onScreen: false, active: true)])
    func sourceFilterKeepsValidWindowsWhenOpacityMetadataIsUnavailable(sample: (onScreen: Bool, active: Bool)) {
        let frame = CGRect(x: 0, y: 0, width: 600, height: 400)
        #expect(ScreenRecordingNativeCapture.includesWindow(frame: frame, layer: 0, processIdentifier: getpid() + 1,
                                                           isRegularApplication: true, isOnScreen: sample.onScreen,
                                                           isActive: sample.active, alpha: nil))
    }
}

private enum CameraPreviewTestError: Error { case unavailable }

@MainActor
private final class CameraPreviewTestSystem {
    let directory = URL(fileURLWithPath: "/synthetic-camera-preview", isDirectory: true)
    let capture = CameraPreviewTestCapture()
    let cameraCreated = CameraPreviewTestSignal()
    var cameras: [CameraPreviewTestCamera] = []
    var permissions: [ScreenRecordingPermission] = []
    var denied: ScreenRecordingPermission?
    var cameraStartError: CameraPreviewTestError?
    var cameraStartGate: CameraPreviewTestLatch<Void>?

    func dependencies() -> ScreenRecordingCaptureDependencies {
        ScreenRecordingCaptureDependencies(
            loadSources: { [] }, loadDevices: { .init() },
            requestPermission: { [self] permission in permissions.append(permission); return denied != permission },
            makeSession: { [self] _, _, _ in capture },
            makeCameraPreview: { [self] identifier, onFailure in
                let camera = CameraPreviewTestCamera(identifier: identifier, onFailure: onFailure,
                                                     error: cameraStartError, gate: cameraStartGate)
                cameras.append(camera)
                cameraCreated.signal()
                return camera
            },
            now: { 100 }, scheduleTick: { _ in {} }
        )
    }
}

@MainActor
private final class CameraPreviewTestCapture: ScreenRecordingCaptureSession {
    var camera: (any ScreenRecordingCameraPreviewSession)?
    var started = false
    var cancelled = false
    func useCameraPreview(_ preview: any ScreenRecordingCameraPreviewSession) { camera = preview }
    func start() async throws -> Double { started = true; return 100 }
    func setPaused(_ paused: Bool, atHostTime time: Double) async {}
    func stop(atHostTime time: Double) async throws -> ScreenRecordingResult {
        .init(videoFile: "screen.mp4", cameraFile: "camera.mp4", duration: 2, width: 16, height: 16)
    }
    func cancel() async -> Error? { cancelled = true; return nil }
}

@MainActor
private final class CameraPreviewTestCamera: ScreenRecordingCameraPreviewSession {
    let previewSession = AVCaptureSession()
    let identifier: String?
    let onFailure: ScreenRecordingCameraFailureHandler
    let entered = CameraPreviewTestSignal()
    let stopping = CameraPreviewTestSignal()
    let error: CameraPreviewTestError?
    let gate: CameraPreviewTestLatch<Void>?
    var running = false
    var released = false
    var stopGate: CameraPreviewTestLatch<Void>?

    init(identifier: String?, onFailure: @escaping ScreenRecordingCameraFailureHandler,
         error: CameraPreviewTestError?, gate: CameraPreviewTestLatch<Void>?) {
        self.identifier = identifier
        self.onFailure = onFailure
        self.error = error
        self.gate = gate
    }

    func start() async throws {
        entered.signal()
        if let error { throw error }
        if let gate { try await gate.wait() }
        running = true
    }
    func attach(to bridge: ScreenRecordingCaptureBridge) {}
    func stop() async {
        stopping.signal()
        if let stopGate { try! await stopGate.wait() }
        running = false
        released = true
    }
}

@MainActor
private final class CameraPreviewTestSignal {
    private var fired = false
    private var waiters: [CheckedContinuation<Void, Never>] = []
    func signal() { fired = true; let pending = waiters; waiters.removeAll(); pending.forEach { $0.resume() } }
    func wait() async { if !fired { await withCheckedContinuation { waiters.append($0) } } }
}

@MainActor
private final class CameraPreviewTestLatch<Value: Sendable> {
    private var result: Result<Value, Error>?
    private var waiters: [CheckedContinuation<Value, Error>] = []
    func resolve(_ result: Result<Value, Error>) {
        self.result = result
        let pending = waiters
        waiters.removeAll()
        pending.forEach { $0.resume(with: result) }
    }
    func wait() async throws -> Value {
        if let result { return try result.get() }
        return try await withCheckedThrowingContinuation { waiters.append($0) }
    }
}
