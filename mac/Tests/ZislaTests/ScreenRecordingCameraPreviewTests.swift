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
    func cameraPermissionFailuresNotifyOnEachRetryWithoutAllocatingAnInput() async {
        let system = CameraPreviewTestSystem()
        system.denied = .camera
        let service = ScreenRecordingService(dependencies: system.dependencies())
        var notices: [String] = []
        let model = ScreenRecordingStudioModel(capture: service, onError: { notices.append($0) })
        defer { model.shutdown() }
        for _ in 0..<2 {
            await #expect(throws: ScreenRecordingCaptureError.permission(.camera)) {
                try await service.prepareCameraPreview(configuration: .init(camera: true))
            }
        }
        let message = ScreenRecordingCaptureError.permission(.camera).localizedDescription
        #expect(notices == [message, message])
        #expect(model.errorMessage == message)
        #expect(system.cameras.isEmpty)
        await service.stopCameraPreview()
    }

    @Test
    func cameraRuntimeFailureUsesTheIslandNoticeWithoutOpeningTheStudio() async throws {
        let system = CameraPreviewTestSystem()
        let service = ScreenRecordingService(dependencies: system.dependencies())
        var notices: [String] = []
        let model = ScreenRecordingStudioModel(capture: service, onError: { notices.append($0) })
        defer { model.shutdown() }
        var showsWindow = false
        model.showWindow = { showsWindow = true }
        try await service.prepareCameraPreview(configuration: .init(camera: true))
        let camera = try #require(system.cameras.first)
        await camera.onFailure(CameraPreviewTestError.unavailable)
        #expect(notices == [CameraPreviewTestError.unavailable.localizedDescription])
        #expect(model.errorMessage == notices.first)
        #expect(!showsWindow)
        #expect(camera.released && service.cameraPreviewSession == nil)
    }

    @Test
    func closingSetupDuringAuthorizationPreventsALateCameraActivation() async throws {
        let system = CameraPreviewTestSystem()
        let permission = CameraPreviewTestLatch<Bool>()
        let entered = CameraPreviewTestSignal()
        var dependencies = system.dependencies()
        dependencies.requestPermission = { _ in entered.signal(); return try! await permission.wait() }
        let service = ScreenRecordingService(dependencies: dependencies)
        var notices: [String] = []
        let model = ScreenRecordingStudioModel(capture: service, onError: { notices.append($0) })
        defer { model.shutdown() }
        let task = Task { try await service.prepareCameraPreview(configuration: .init(camera: true)) }
        await entered.wait()
        await service.stopCameraPreview()
        permission.resolve(.success(true))
        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(system.cameras.isEmpty)
        #expect(service.cameraPreviewState == .idle)
        #expect(service.cameraPreviewSession == nil)
        #expect(notices.isEmpty)
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

    @Test(arguments: RecordingCameraAspectRatio.allCases)
    func previewUsesTheSelectedCameraAspectRatio(_ ratio: RecordingCameraAspectRatio) {
        let configuration = RecordingEdits(cameraRound: false, cameraAspectRatio: ratio)
        let frame = ScreenRecordingCameraPreviewLayout.frame(configuration: configuration,
                                                              visibleFrame: CGRect(x: 0, y: 0, width: 1440, height: 900))
        #expect(abs(frame.width / frame.height - ratio.ratio) < 0.000_001)
        #expect(CGRect(x: 0, y: 0, width: 1440, height: 900).contains(frame))
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

    @Test(arguments: RecordingCameraAspectRatio.allCases, [0.0, 0.125, 0.5])
    func explicitRadiusControlsPreviewMaskWhileKeepingItsSizeAndLegacyFlag(
        ratio: RecordingCameraAspectRatio, radius: Double
    ) throws {
        let frame = CGRect(x: 0, y: 0, width: 200, height: 200 / ratio.ratio)
        let view = ScreenRecordingCameraPreviewView(frame: frame)
        defer { view.detach() }
        let layer = try #require(view.layer?.sublayers?.first)
        let configuration = RecordingEdits(cameraRound: true, cameraAspectRatio: ratio,
                                           cameraCornerRadius: radius, cameraBorder: true)
        view.update(session: nil, state: .running, configuration: configuration)
        view.layoutSubtreeIfNeeded()
        #expect(abs(layer.cornerRadius - min(frame.width, frame.height) * radius) < 0.000_001,
                "A saved circular flag must not override the radius shown in the camera controls")
        #expect(view.frame == frame)
        #expect(layer.borderWidth == min(frame.width, frame.height) * 0.01)
        view.update(session: nil, state: .idle, configuration: configuration)
        view.layoutSubtreeIfNeeded()
        #expect(view.frame == frame)
        #expect(abs(layer.cornerRadius - min(frame.width, frame.height) * radius) < 0.000_001)
    }

    @Test(arguments: ScreenRecordingCameraPreviewLayout.Corner.allCases, RecordingCameraAspectRatio.allCases)
    func draggingEachCornerPreservesAspectRatioAndTheOppositeAnchor(
        corner: ScreenRecordingCameraPreviewLayout.Corner, ratio: RecordingCameraAspectRatio
    ) {
        let visible = CGRect(x: -1440, y: -200, width: 1440, height: 900)
        let original = CGRect(x: -900, y: 100, width: 200, height: 200 / ratio.ratio)
        let resized = ScreenRecordingCameraPreviewLayout.resize(frame: original, corner: corner,
            translation: CGSize(width: corner.isLeft ? -30 : 30, height: (corner.isTop ? 30 : -30) / ratio.ratio),
            visibleFrame: visible)
        #expect(abs(resized.frame.width - 230) < 0.000_001)
        #expect(abs(resized.frame.width / resized.frame.height - ratio.ratio) < 0.000_001)
        #expect(corner.isLeft ? resized.frame.maxX == original.maxX : resized.frame.minX == original.minX)
        #expect(corner.isTop ? resized.frame.minY == original.minY : resized.frame.maxY == original.maxY)
        #expect(visible.contains(resized.frame))
        #expect(abs(resized.size - 230 / 900) < 0.000_001)
    }

    @Test(arguments: ScreenRecordingCameraPreviewLayout.Corner.allCases, [false, true])
    func resizeClampsExtremeDragsToScreenAndSupportedSize(corner: ScreenRecordingCameraPreviewLayout.Corner, smallScreen: Bool) {
        let visible = smallScreen ? CGRect(x: 50, y: 60, width: 90, height: 70)
            : CGRect(x: -1920, y: -200, width: 1920, height: 1080)
        let original = ScreenRecordingCameraPreviewLayout.frame(configuration: .init(), visibleFrame: visible)
        for direction in [-1.0, 1.0] {
            let resized = ScreenRecordingCameraPreviewLayout.resize(frame: original, corner: corner,
                translation: CGSize(width: direction * 100_000, height: direction * 100_000), visibleFrame: visible)
            #expect(visible.contains(resized.frame))
            #expect(resized.frame.width > 0 && resized.frame.height > 0)
            #expect(resized.frame.width == resized.frame.height)
            #expect((0.1...0.5).contains(resized.size))
        }
    }

    @Test
    func changingSizeOrAspectRatioKeepsTheDraggedPreviewCenter() {
        let visible = CGRect(x: -1440, y: -200, width: 1440, height: 900)
        let center = CGPoint(x: -750, y: 300)
        let resized = ScreenRecordingCameraPreviewLayout.frame(
            configuration: .init(cameraSize: 0.3, cameraRound: false, cameraAspectRatio: .widescreen),
            visibleFrame: visible, center: center)
        #expect(resized.midX == center.x)
        #expect(resized.midY == center.y)
        #expect(visible.contains(resized))
        let outside = ScreenRecordingCameraPreviewLayout.frame(configuration: .init(), visibleFrame: visible,
            center: CGPoint(x: 10_000, y: -10_000))
        #expect(visible.contains(outside))
    }

    @Test
    func draggingTheRadiusHandleSupportsSquareRoundedAndCircularMasks() {
        #expect(abs(ScreenRecordingCameraPreviewLayout.cornerRadius(start: 0.5, translation: -80, side: 200) - 0.1) < 0.000_001)
        #expect(ScreenRecordingCameraPreviewLayout.cornerRadius(start: 0.1, translation: -1000, side: 200) == 0)
        #expect(ScreenRecordingCameraPreviewLayout.cornerRadius(start: 0.1, translation: 1000, side: 200) == 0.5)
        for radius in [0.0, 0.1, 0.5] {
            let bounds = CGRect(x: 0, y: 0, width: 200, height: 150)
            let handle = ScreenRecordingCameraPreviewLayout.radiusHandle(in: bounds, radius: radius)
            #expect(bounds.contains(handle))
            #expect(handle.x > bounds.minX + 6)
            #expect(handle.y + 4 == bounds.maxY)
        }
    }

    @Test(arguments: [CGRect(x: 0, y: 0, width: 56, height: 56),
                      CGRect(x: -140, y: 75, width: 200, height: 200),
                      CGRect(x: 30, y: -200, width: 320, height: 320)])
    func circularRadiusHandleIsCenteredAndItsTopEdgeAlignsWithThePreview(bounds: CGRect) {
        let handle = ScreenRecordingCameraPreviewLayout.radiusHandle(in: bounds, radius: 0.5)
        #expect(abs(handle.x - bounds.midX) < 0.000_001,
                "The circular camera's radius handle must align horizontally with its center")
        #expect(handle.y + 4 == bounds.maxY,
                "The complete 8pt radius handle must sit inside the preview with its top edge flush")
        #expect(bounds.contains(CGRect(x: handle.x - 4, y: handle.y - 4, width: 8, height: 8)))
    }

    @Test(arguments: RecordingCameraAspectRatio.allCases, [76.0, 200.0, 320.0])
    func radiusHandleKeepsContinuousShortEdgeGeometry(ratio: RecordingCameraAspectRatio, width: Double) {
        let bounds = CGRect(x: -130, y: 45, width: width, height: width / ratio.ratio)
        let minimum = ScreenRecordingCameraPreviewLayout.radiusHandle(in: bounds, radius: 0)
        let maximum = ScreenRecordingCameraPreviewLayout.radiusHandle(in: bounds, radius: 0.5)
        #expect(minimum.x == bounds.minX + 18)
        #expect(abs(maximum.x - (bounds.minX + min(bounds.width, bounds.height) / 2)) < 0.000_001)
        for radius in [0.0, 0.01, 0.1, 0.25, 0.49, 0.5] {
            let handle = ScreenRecordingCameraPreviewLayout.radiusHandle(in: bounds, radius: radius)
            #expect(abs(handle.x - (minimum.x + (maximum.x - minimum.x) * radius * 2)) < 0.000_001,
                    "The radius handle must move continuously between its visible endpoints")
            #expect(handle.y + 4 == bounds.maxY)
            #expect(bounds.contains(CGRect(x: handle.x - 4, y: handle.y - 4, width: 8, height: 8)))
        }
    }

    @Test(arguments: [CGSize(width: 56, height: 56), CGSize(width: 200, height: 200),
                      CGSize(width: 200, height: 150), CGSize(width: 320, height: 180),
                      CGSize(width: 76, height: 42.75)])
    func radiusHandleTracksPointerTranslationAndClampsWithoutResizing(size: CGSize) throws {
        let window = NSWindow(contentRect: CGRect(origin: CGPoint(x: 100, y: 100), size: size),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        let view = ScreenRecordingCameraPreviewView(frame: CGRect(origin: .zero, size: size))
        window.contentView = view
        defer { view.detach() }
        let handles = try #require(view.layer?.sublayers?.last as? CAShapeLayer)
        let minimum = ScreenRecordingCameraPreviewLayout.radiusHandle(in: view.bounds, radius: 0)
        let maximum = ScreenRecordingCameraPreviewLayout.radiusHandle(in: view.bounds, radius: 0.5)
        let travel = maximum.x - minimum.x
        let original = window.frame
        var radius: Double?
        var resized = false
        view.onCornerRadiusChange = { radius = $0 }
        view.onResize = { _, _, _ in resized = true }
        func event(_ type: NSEvent.EventType, _ location: CGPoint) throws -> NSEvent {
            try #require(NSEvent.mouseEvent(with: type, location: view.convert(location, to: nil), modifierFlags: [],
                timestamp: 0, windowNumber: window.windowNumber, context: nil, eventNumber: 1, clickCount: 1, pressure: 1))
        }
        for start in [0.0, 0.25, 0.5] {
            view.update(session: nil, state: .running, configuration: .init(cameraCornerRadius: start))
            let origin = ScreenRecordingCameraPreviewLayout.radiusHandle(in: view.bounds, radius: start)
            let down = CGPoint(x: origin.x + 8, y: origin.y)
            view.mouseEntered(with: try event(.leftMouseDown, down))
            view.mouseDown(with: try event(.leftMouseDown, down))
            for target in [0.0, 0.01, 0.1, 0.25, 0.49, 0.5, -10.0, 10.0, 0.25] {
                let translation = travel * (target - start) * 2
                let expected = min(0.5, max(0, target))
                let dragged = CGPoint(x: down.x + translation, y: down.y + 20)
                radius = nil
                view.mouseDragged(with: try event(.leftMouseDragged, dragged))
                let published = try #require(radius)
                #expect(abs(published - expected) < 0.000_001,
                        "Horizontal pointer movement must match the handle's visible travel, including both clamps")
                view.update(session: nil, state: .running, configuration: .init(cameraCornerRadius: published))
                view.layout()
                let expectedPoint = CGPoint(x: minimum.x + travel * expected * 2, y: view.bounds.maxY - 4)
                #expect(try #require(handles.path).contains(expectedPoint),
                        "The rendered radius handle must follow the pointer and ignore vertical movement")
                #expect(window.frame == original)
                #expect(!resized, "Radius handle hits must not invoke a corner resize")
            }
            view.mouseUp(with: try event(.leftMouseUp, down))
            radius = nil
            view.mouseDragged(with: try event(.leftMouseDragged, down))
            #expect(radius == nil, "Releasing the radius handle must end the drag")
        }
    }

    @Test(arguments: ScreenRecordingCameraPreviewLayout.Corner.allCases)
    func hoverRevealsHandlesAndCornerEventsResizeWithoutMovingTheWindow(
        corner: ScreenRecordingCameraPreviewLayout.Corner
    ) throws {
        let window = NSWindow(contentRect: CGRect(x: 100, y: 100, width: 200, height: 150),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        let view = ScreenRecordingCameraPreviewView(frame: CGRect(origin: .zero, size: window.frame.size))
        window.contentView = view
        #expect(view.acceptsFirstMouse(for: nil))
        let handles = try #require(view.layer?.sublayers?.last as? CAShapeLayer)
        #expect(handles.isHidden)
        let point = corner.point(in: view.bounds.insetBy(dx: 6, dy: 6))
        func event(_ type: NSEvent.EventType, _ location: CGPoint) throws -> NSEvent {
            try #require(NSEvent.mouseEvent(with: type, location: view.convert(location, to: nil), modifierFlags: [],
                timestamp: 0, windowNumber: window.windowNumber, context: nil, eventNumber: 1, clickCount: 1, pressure: 1))
        }
        let down = try event(.leftMouseDown, point)
        view.mouseEntered(with: down)
        view.layout()
        #expect(!handles.isHidden)
        let original = window.frame
        var drag: (ScreenRecordingCameraPreviewLayout.Corner, CGRect, CGSize)?
        view.onResize = { drag = ($0, $1, $2) }
        view.mouseDown(with: down)
        view.mouseDragged(with: try event(.leftMouseDragged, CGPoint(x: point.x + 30, y: point.y + 20)))
        #expect(drag?.0 == corner)
        #expect(drag?.1 == original)
        #expect(drag?.2 == CGSize(width: 30, height: 20))
        #expect(window.frame == original)
        view.mouseExited(with: down)
        view.layout()
        #expect(!handles.isHidden, "Resize handles must remain visible while a drag leaves the preview")
        view.mouseUp(with: try event(.leftMouseUp, point))
        view.mouseExited(with: down)
        view.layout()
        #expect(handles.isHidden)
    }

    @Test
    func circularPreviewRadiusHandlePublishesCustomRoundingAndStopsAfterMouseUp() throws {
        let window = NSWindow(contentRect: CGRect(x: 100, y: 100, width: 200, height: 200),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        let view = ScreenRecordingCameraPreviewView(frame: CGRect(origin: .zero, size: window.frame.size))
        window.contentView = view
        view.update(session: nil, state: .running, configuration: .init(cameraRound: true))
        let point = ScreenRecordingCameraPreviewLayout.radiusHandle(in: view.bounds, radius: 0.5)
        func event(_ type: NSEvent.EventType, _ location: CGPoint) throws -> NSEvent {
            try #require(NSEvent.mouseEvent(with: type, location: view.convert(location, to: nil), modifierFlags: [],
                timestamp: 0, windowNumber: window.windowNumber, context: nil, eventNumber: 1, clickCount: 1, pressure: 1))
        }
        var radius: Double?
        view.onCornerRadiusChange = { radius = $0 }
        view.mouseDown(with: try event(.leftMouseDown, point))
        let target = ScreenRecordingCameraPreviewLayout.radiusHandle(in: view.bounds, radius: 0.1)
        let dragged = try event(.leftMouseDragged, target)
        view.mouseDragged(with: dragged)
        #expect(abs(try #require(radius) - 0.1) < 0.000_001)
        view.mouseUp(with: try event(.leftMouseUp, point))
        radius = nil
        view.mouseDragged(with: dragged)
        #expect(radius == nil)
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
