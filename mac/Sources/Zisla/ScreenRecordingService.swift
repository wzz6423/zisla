import AppKit
import AVFoundation
import Combine
import CoreMedia
import ZislaCore

enum ScreenRecordingCaptureError: LocalizedError, Equatable {
    case alreadyRecording, notRecording, invalidSource, invalidRegion, invalidFrameRate
    case permission(ScreenRecordingPermission)
    case invalidDirectory, writerUnavailable, noScreenFrames, noMicrophoneSamples, noCameraFrames
    case deviceUnavailable, cancelled
    case captureFailed(String), saveFailed(String)

    var errorDescription: String? {
        switch self {
        case .alreadyRecording: AppLocalization.text("录屏正在进行，请先停止当前录制")
        case .notRecording: AppLocalization.text("当前没有正在进行的录制")
        case .invalidSource: AppLocalization.text("录制来源已不可用，请重新选择")
        case .invalidRegion: AppLocalization.text("录制区域无效，请重新选择")
        case .invalidFrameRate: AppLocalization.text("录制帧率无效")
        case .permission(.screen): AppLocalization.text("请在系统设置的“隐私与安全性 > 屏幕录制”中允许 Zisla")
        case .permission(.microphone): AppLocalization.text("请在系统设置的“隐私与安全性 > 麦克风”中允许 Zisla")
        case .permission(.camera): AppLocalization.text("请在系统设置的“隐私与安全性 > 摄像头”中允许 Zisla")
        case .invalidDirectory: AppLocalization.text("录制目录无效")
        case .writerUnavailable: AppLocalization.text("无法创建录屏写入器")
        case .noScreenFrames: AppLocalization.text("未收到可用的屏幕画面")
        case .noMicrophoneSamples: AppLocalization.text("未收到可用的麦克风音频")
        case .noCameraFrames: AppLocalization.text("未收到可用的摄像头画面")
        case .deviceUnavailable: AppLocalization.text("输入设备已断开或被占用")
        case .cancelled: AppLocalization.text("录屏已取消")
        case let .captureFailed(reason): AppLocalization.text("录屏失败：%@", reason)
        case let .saveFailed(reason): AppLocalization.text("录屏文件保存失败：%@", reason)
        }
    }
}

enum ScreenRecordingPermission: Equatable, Sendable {
    case screen, microphone, camera
}

struct ScreenRecordingDeviceCatalog: Sendable {
    var cameras: [RecordingDevice] = []
    var microphones: [RecordingDevice] = []
}

@MainActor
protocol ScreenRecordingCaptureSession: AnyObject {
    func start() async throws -> Double
    func setPaused(_ paused: Bool, atHostTime time: Double) async
    func stop(atHostTime time: Double) async throws -> ScreenRecordingResult
    func cancel() async -> Error?
}

@MainActor
struct ScreenRecordingCaptureDependencies {
    var loadSources: () async throws -> [RecordingCaptureSource]
    var loadDevices: () -> ScreenRecordingDeviceCatalog
    var requestPermission: (ScreenRecordingPermission) async -> Bool
    var makeSession: (RecordingCaptureConfiguration, URL, @escaping @Sendable (Error) -> Void) throws -> any ScreenRecordingCaptureSession
    var now: () -> Double
    var scheduleTick: (@escaping @MainActor () -> Void) -> (() -> Void)

    static var live: Self {
        Self(
            loadSources: { try await ScreenRecordingNativeCapture.sources() },
            loadDevices: { ScreenRecordingNativeCapture.devices() },
            requestPermission: { permission in
                switch permission {
                case .screen:
                    return CGPreflightScreenCaptureAccess() || CGRequestScreenCaptureAccess()
                case .microphone:
                    return await ScreenRecordingNativeCapture.requestAccess(for: .audio)
                case .camera:
                    return await ScreenRecordingNativeCapture.requestAccess(for: .video)
                }
            },
            makeSession: { configuration, directory, onFailure in
                ScreenRecordingNativeCapture(configuration: configuration, directory: directory, onFailure: onFailure)
            },
            now: { CMClockGetTime(CMClockGetHostTimeClock()).seconds },
            scheduleTick: { tick in
                let timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
                    Task { @MainActor in tick() }
                }
                return { timer.invalidate() }
            }
        )
    }
}

@MainActor
final class ScreenRecordingService: ObservableObject {
    @Published private(set) var phase: RecordingPhase = .idle
    @Published private(set) var elapsed: Double = 0
    @Published private(set) var errorMessage: String?
    @Published private(set) var sources: [RecordingCaptureSource] = []
    @Published private(set) var cameras: [RecordingDevice] = []
    @Published private(set) var microphones: [RecordingDevice] = []

    @MainActor private final class Run {
        var session: (any ScreenRecordingCaptureSession)?
        var startTask: Task<Void, Error>?
        var stopTask: Task<ScreenRecordingResult, Error>?
        var cleanupTask: Task<Error?, Never>?
        var timeline = ScreenRecordingCaptureTimeline()
        var cancelTick: (() -> Void)?
        var invalidated = false
        var failure: Error?
        var cancelled = false
    }

    private let dependencies: ScreenRecordingCaptureDependencies
    private var run: Run?
    private var lastStopResult: Result<ScreenRecordingResult, Error>?
    private var sourceRevision: UInt64 = 0

    init(dependencies: ScreenRecordingCaptureDependencies = .live) {
        self.dependencies = dependencies
    }

    func loadSources() async throws {
        sourceRevision &+= 1
        let revision = sourceRevision
        do {
            let loaded = try await dependencies.loadSources()
            try Task.checkCancellation()
            guard revision == sourceRevision else { return }
            let devices = dependencies.loadDevices()
            sources = loaded
            cameras = devices.cameras
            microphones = devices.microphones
            if phase == .idle { errorMessage = nil }
        } catch {
            if revision == sourceRevision, !(error is CancellationError) {
                errorMessage = error.localizedDescription
            }
            throw error
        }
    }

    func start(configuration: RecordingCaptureConfiguration, directory: URL) async throws {
        guard phase == .idle, run == nil else { throw ScreenRecordingCaptureError.alreadyRecording }
        guard (1...120).contains(configuration.frameRate) else { throw ScreenRecordingCaptureError.invalidFrameRate }
        if configuration.mode == .region, configuration.region?.isValid != true {
            throw ScreenRecordingCaptureError.invalidRegion
        }

        let current = Run()
        run = current
        lastStopResult = nil
        errorMessage = nil
        elapsed = 0
        phase = .preparing
        let task = Task { [weak self, current] in
            guard let self else { throw CancellationError() }
            var permissions: [ScreenRecordingPermission] = [.screen]
            if configuration.microphone { permissions.append(.microphone) }
            if configuration.camera { permissions.append(.camera) }
            for permission in permissions {
                try self.requireCurrent(current)
                let granted = await self.dependencies.requestPermission(permission)
                try self.requireCurrent(current)
                guard granted else { throw ScreenRecordingCaptureError.permission(permission) }
            }
            current.session = try self.dependencies.makeSession(configuration, directory) { [weak self, weak current] error in
                Task { @MainActor [weak self, weak current] in
                    guard let self, let current, self.run === current, !current.invalidated else { return }
                    await self.fail(current, with: error)
                }
            }
            let epoch = try await current.session!.start()
            try self.requireCurrent(current)
            current.timeline.begin(at: epoch)
            self.phase = .recording
            current.cancelTick = self.dependencies.scheduleTick { [weak self, weak current] in
                guard let self, let current, self.run === current, self.phase == .recording else { return }
                self.elapsed = current.timeline.elapsed(at: self.dependencies.now())
            }
        }
        current.startTask = task
        do {
            try await withTaskCancellationHandler {
                try await task.value
            } onCancel: { [weak self, weak current] in
                task.cancel()
                Task { @MainActor [weak self, weak current] in
                    guard let self, let current else { return }
                    await self.cancel(current)
                }
            }
            current.startTask = nil
            try requireCurrent(current)
        } catch {
            current.startTask = nil
            if run === current { await fail(current, with: error) }
            throw error
        }
    }

    func togglePause() async {
        guard let current = run, !current.invalidated,
              phase == .recording || phase == .paused else { return }
        let time = dependencies.now()
        let paused = phase == .recording
        if paused {
            current.timeline.pause(at: time)
            elapsed = current.timeline.elapsed(at: time)
            phase = .paused
        } else {
            current.timeline.resume(at: time)
            phase = .recording
        }
        await current.session?.setPaused(paused, atHostTime: time)
    }

    func stop() async throws -> ScreenRecordingResult {
        guard let current = run else {
            if let lastStopResult { return try lastStopResult.get() }
            throw ScreenRecordingCaptureError.notRecording
        }
        if let task = current.stopTask { return try await task.value }
        if phase == .preparing {
            await cancel(current)
            throw ScreenRecordingCaptureError.noScreenFrames
        }
        guard !current.invalidated, let session = current.session else {
            throw ScreenRecordingCaptureError.notRecording
        }
        let time = dependencies.now()
        phase = .finishing
        current.cancelTick?()
        current.cancelTick = nil
        let task = Task { [weak self] in
            guard let self else { throw CancellationError() }
            do {
                let result = try await session.stop(atHostTime: time)
                try self.requireCurrent(current)
                self.elapsed = result.duration
                self.lastStopResult = .success(result)
                self.run = nil
                self.phase = .idle
                return result
            } catch {
                if self.run === current { await self.fail(current, with: error) }
                throw error
            }
        }
        current.stopTask = task
        return try await task.value
    }

    func cancel() async {
        guard let current = run else { return }
        await cancel(current)
    }

    private func requireCurrent(_ current: Run) throws {
        try Task.checkCancellation()
        guard run === current, !current.invalidated else { throw CancellationError() }
    }

    private func cleanup(_ current: Run) async -> Error? {
        if let task = current.cleanupTask { return await task.value }
        current.invalidated = true
        current.cancelTick?()
        current.cancelTick = nil
        current.startTask?.cancel()
        current.stopTask?.cancel()
        phase = .finishing
        let session = current.session
        let task = Task { await session?.cancel() }
        current.cleanupTask = task
        return await task.value
    }

    private func cancel(_ current: Run) async {
        guard run === current else { return }
        current.cancelled = true
        let cleanupError = await cleanup(current)
        guard run === current else { return }
        run = nil
        phase = .idle
        elapsed = 0
        lastStopResult = .failure(ScreenRecordingCaptureError.cancelled)
        errorMessage = cleanupError?.localizedDescription
    }

    private func fail(_ current: Run, with error: Error) async {
        if current.failure == nil { current.failure = error }
        let cleanupError = await cleanup(current)
        guard run === current else { return }
        run = nil
        phase = .idle
        elapsed = 0
        let failure = cleanupError ?? current.failure ?? error
        lastStopResult = .failure(current.cancelled ? ScreenRecordingCaptureError.cancelled : failure)
        errorMessage = current.cancelled && cleanupError == nil || error is CancellationError && cleanupError == nil
            ? nil : failure.localizedDescription
    }
}
