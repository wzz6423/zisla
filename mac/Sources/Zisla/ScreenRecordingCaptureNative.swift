import AppKit
import AVFoundation
import CoreMedia
import CoreVideo
import ScreenCaptureKit
import ZislaCore

@MainActor
final class ScreenRecordingNativeCapture: ScreenRecordingCaptureSession {
    private let configuration: RecordingCaptureConfiguration
    private let directory: URL
    private let onFailure: @Sendable (Error) -> Void
    private var streams: [SCStream] = []
    private var runningStreams: [SCStream] = []
    private var bridge: ScreenRecordingCaptureBridge?
    private var hardware: ScreenRecordingCaptureHardware?
    private var writer: ScreenRecordingCaptureWriter?
    private var files: ScreenRecordingCaptureFiles?
    private var pointer: ScreenRecordingCapturePointer?
    private var startTask: Task<Double, Error>?
    private var stopTask: Task<ScreenRecordingResult, Error>?
    private var cancelTask: Task<Error?, Never>?
    private var cancelled = false
    private var width = 0
    private var height = 0

    init(configuration: RecordingCaptureConfiguration, directory: URL, onFailure: @escaping @Sendable (Error) -> Void) {
        self.configuration = configuration
        self.directory = directory
        self.onFailure = onFailure
    }

    static func sources() async throws -> [RecordingCaptureSource] {
        guard CGPreflightScreenCaptureAccess() else { throw ScreenRecordingCaptureError.permission(.screen) }
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        return content.displays.map { display in
            let screen = NSScreen.screens.first { ScreenshotCaptureService.displayID(for: $0) == display.displayID }
            return RecordingCaptureSource(id: display.displayID,
                                          name: screen?.localizedName ?? AppLocalization.text("显示器"),
                                          mode: .display, frame: recordRect(display.frame))
        } + content.windows.compactMap { window in
            guard window.windowLayer == 0, window.frame.width > 1, window.frame.height > 1,
                  window.owningApplication?.processID != getpid() else { return nil }
            let application = window.owningApplication?.applicationName ?? AppLocalization.text("窗口")
            let name = window.title.flatMap { $0.isEmpty ? nil : $0 }.map { "\(application) — \($0)" } ?? application
            return RecordingCaptureSource(id: window.windowID, name: name, mode: .window, frame: recordRect(window.frame))
        }
    }

    static func devices() -> ScreenRecordingDeviceCatalog {
        ScreenRecordingDeviceCatalog(cameras: devices(for: .video).map { RecordingDevice(id: $0.uniqueID, name: $0.localizedName) },
                                     microphones: devices(for: .audio).map { RecordingDevice(id: $0.uniqueID, name: $0.localizedName) })
    }

    nonisolated static func requestAccess(for mediaType: AVMediaType) async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: mediaType) {
        case .authorized: return true
        case .notDetermined:
            return await withCheckedContinuation { continuation in
                AVCaptureDevice.requestAccess(for: mediaType) { continuation.resume(returning: $0) }
            }
        case .denied, .restricted: return false
        @unknown default: return false
        }
    }

    func start() async throws -> Double {
        guard !cancelled else { throw CancellationError() }
        guard startTask == nil, writer == nil else { throw ScreenRecordingCaptureError.alreadyRecording }
        let task = Task { try await self.prepareAndStart() }
        startTask = task
        do {
            let epoch = try await task.value
            startTask = nil
            return epoch
        } catch {
            startTask = nil
            throw error
        }
    }

    func setPaused(_ paused: Bool, atHostTime time: Double) async {
        guard !cancelled, stopTask == nil else { return }
        pointer?.setPaused(paused, at: time)
        await writer?.setPaused(paused, at: time)
    }

    func stop(atHostTime time: Double) async throws -> ScreenRecordingResult {
        if let task = stopTask { return try await task.value }
        guard !cancelled, let writer, let files else { throw ScreenRecordingCaptureError.notRecording }
        let pointers = pointer?.stop(at: time) ?? []
        pointer = nil
        let task = Task {
            await writer.seal(at: time)
            if let failure = await self.stopInputs() { throw failure }
            try self.requireActive()
            let duration = try await writer.finish()
            try self.requireActive()
            var names = [files.screenName]
            if self.configuration.microphone { names.append(files.microphoneName) }
            if self.configuration.camera { names.append(files.cameraName) }
            do { try files.publish(names) } catch { throw ScreenRecordingCaptureError.saveFailed(error.localizedDescription) }
            self.writer = nil
            self.bridge = nil
            self.hardware = nil
            return ScreenRecordingResult(videoFile: files.screenName,
                                         cameraFile: self.configuration.camera ? files.cameraName : nil,
                                         microphoneFile: self.configuration.microphone ? files.microphoneName : nil,
                                         duration: duration, width: self.width, height: self.height, pointers: pointers)
        }
        stopTask = task
        return try await task.value
    }

    func cancel() async -> Error? {
        if let task = cancelTask { return await task.value }
        cancelled = true
        startTask?.cancel()
        stopTask?.cancel()
        _ = pointer?.stop(at: CMClockGetTime(CMClockGetHostTimeClock()).seconds)
        pointer = nil
        let task = Task {
            self.bridge?.deactivate()
            await self.writer?.cancel()
            if let task = self.startTask { _ = await task.result }
            if let task = self.stopTask { _ = await task.result }
            let inputError = await self.stopInputs()
            await self.writer?.cancel()
            let fileError = self.files?.discard()
            self.writer = nil
            self.bridge = nil
            self.hardware = nil
            self.files = nil
            return fileError ?? inputError
        }
        cancelTask = task
        return await task.value
    }

    private func prepareAndStart() async throws -> Double {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: configuration.mode != .window)
        try requireActive()
        let filter: SCContentFilter
        let captureFrame: CGRect
        let sourceRect: CGRect?
        let systemAudioDisplay: SCDisplay?
        switch configuration.mode {
        case .display, .region:
            guard let display = content.displays.first(where: { $0.displayID == configuration.sourceID }) else {
                throw ScreenRecordingCaptureError.invalidSource
            }
            filter = SCContentFilter(display: display,
                                     excludingApplications: content.applications.filter { $0.processID == getpid() },
                                     exceptingWindows: [])
            if configuration.mode == .region {
                guard let region = configuration.region else { throw ScreenRecordingCaptureError.invalidRegion }
                captureFrame = try ScreenRecordingCaptureGeometry.region(region, in: display.frame)
                sourceRect = CGRect(x: region.x, y: region.y, width: region.width, height: region.height)
            } else { captureFrame = display.frame; sourceRect = nil }
            systemAudioDisplay = nil
        case .window:
            guard let window = content.windows.first(where: { $0.windowID == configuration.sourceID }) else {
                throw ScreenRecordingCaptureError.invalidSource
            }
            filter = SCContentFilter(desktopIndependentWindow: window)
            captureFrame = window.frame
            sourceRect = nil
            systemAudioDisplay = configuration.systemAudio ? content.displays.max(by: {
                $0.frame.intersection(window.frame).size.area < $1.frame.intersection(window.frame).size.area
            }) : nil
            if configuration.systemAudio, systemAudioDisplay == nil { throw ScreenRecordingCaptureError.invalidSource }
        }
        let size = sourceRect?.size ?? filter.contentRect.size
        let dimensions = try ScreenRecordingCaptureGeometry.pixelDimensions(size: size, scale: CGFloat(filter.pointPixelScale))
        width = dimensions.width
        height = dimensions.height
        let files = try ScreenRecordingCaptureFiles(directory: directory)
        self.files = files
        let writer = ScreenRecordingCaptureWriter(files: files, configuration: configuration, width: width, height: height, onFailure: onFailure)
        self.writer = writer
        let bridge = ScreenRecordingCaptureBridge(writer: writer, onFailure: onFailure)
        self.bridge = bridge

        let streamConfiguration = Self.streamConfiguration(width: width, height: height, frameRate: configuration.frameRate)
        streamConfiguration.capturesAudio = configuration.systemAudio && systemAudioDisplay == nil
        if let sourceRect { streamConfiguration.sourceRect = sourceRect }
        let stream = SCStream(filter: filter, configuration: streamConfiguration, delegate: bridge)
        try stream.addStreamOutput(bridge, type: .screen, sampleHandlerQueue: bridge.sampleQueue)
        if streamConfiguration.capturesAudio {
            try stream.addStreamOutput(bridge, type: .audio, sampleHandlerQueue: bridge.sampleQueue)
        }
        streams.append(stream)
        if let display = systemAudioDisplay {
            let audioConfiguration = Self.streamConfiguration(width: 2, height: 2, frameRate: 1)
            audioConfiguration.capturesAudio = true
            let audioFilter = SCContentFilter(display: display, excludingApplications: [], exceptingWindows: [])
            let audioStream = SCStream(filter: audioFilter, configuration: audioConfiguration, delegate: bridge)
            try audioStream.addStreamOutput(bridge, type: .audio, sampleHandlerQueue: bridge.sampleQueue)
            streams.append(audioStream)
        }
        if configuration.microphone || configuration.camera {
            let hardware = ScreenRecordingCaptureHardware(configuration: configuration, bridge: bridge)
            self.hardware = hardware
            try await hardware.start()
            try requireActive()
        }
        for stream in streams {
            try requireActive()
            try await stream.startCapture()
            runningStreams.append(stream)
            try requireActive()
        }
        let epoch = try await writer.waitForFirstFrame()
        try requireActive()
        let pointer = ScreenRecordingCapturePointer(frame: captureFrame, windowID: configuration.mode == .window ? configuration.sourceID : nil,
                                                   frameRate: configuration.frameRate)
        self.pointer = pointer
        pointer.start(at: epoch)
        return epoch
    }

    private func requireActive() throws {
        try Task.checkCancellation()
        guard !cancelled else { throw CancellationError() }
    }

    private func stopInputs() async -> Error? {
        bridge?.deactivate()
        let inputs = runningStreams
        runningStreams.removeAll()
        streams.removeAll()
        var error: Error?
        for stream in inputs {
            do { try await stream.stopCapture() } catch let failure { error = failure }
        }
        await hardware?.stop()
        return error
    }

    private static func streamConfiguration(width: Int, height: Int, frameRate: Int) -> SCStreamConfiguration {
        let value = SCStreamConfiguration()
        value.width = width
        value.height = height
        value.minimumFrameInterval = CMTime(value: 1, timescale: Int32(frameRate))
        value.queueDepth = 5
        value.showsCursor = false
        value.captureResolution = .best
        value.pixelFormat = kCVPixelFormatType_32BGRA
        value.colorSpaceName = CGColorSpace.sRGB
        value.ignoreShadowsSingleWindow = true
        value.sampleRate = 48_000
        value.channelCount = 2
        value.excludesCurrentProcessAudio = true
        return value
    }

    nonisolated static func devices(for mediaType: AVMediaType) -> [AVCaptureDevice] {
        let types: [AVCaptureDevice.DeviceType] = mediaType == .audio
            ? [.microphone, .external] : [.builtInWideAngleCamera, .external, .continuityCamera]
        return AVCaptureDevice.DiscoverySession(deviceTypes: types, mediaType: mediaType, position: .unspecified).devices
    }

    private static func recordRect(_ rect: CGRect) -> RecordingRect {
        RecordingRect(x: rect.minX, y: rect.minY, width: rect.width, height: rect.height)
    }
}

private extension CGSize {
    var area: CGFloat { width * height }
}

final class ScreenRecordingCaptureBridge: NSObject, SCStreamOutput, SCStreamDelegate,
    AVCaptureAudioDataOutputSampleBufferDelegate, AVCaptureVideoDataOutputSampleBufferDelegate, @unchecked Sendable {
    let sampleQueue = DispatchQueue(label: "dev.wzz.zisla.recording.samples", qos: .userInitiated)
    private let writer: ScreenRecordingCaptureWriter
    private let onFailure: @Sendable (Error) -> Void
    private let lock = NSLock()
    private var active = true
    private var hardwareClock: CMClock?

    init(writer: ScreenRecordingCaptureWriter, onFailure: @escaping @Sendable (Error) -> Void) {
        self.writer = writer
        self.onFailure = onFailure
    }

    func setHardwareClock(_ clock: CMClock?) {
        lock.lock()
        hardwareClock = clock
        lock.unlock()
    }

    func deactivate() {
        lock.lock()
        active = false
        lock.unlock()
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        if type == .screen {
            guard let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]],
                  let status = attachments.first?[.status] as? Int, status == SCFrameStatus.complete.rawValue,
                  CMSampleBufferGetImageBuffer(sampleBuffer) != nil else { return }
        }
        guard type == .screen || type == .audio else { return }
        receive(sampleBuffer, kind: type == .screen ? .screen : .systemAudio, clock: nil)
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        lock.lock()
        let active = active
        lock.unlock()
        if active { onFailure(ScreenRecordingCaptureError.captureFailed(error.localizedDescription)) }
    }

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        lock.lock()
        let clock = hardwareClock
        lock.unlock()
        guard let clock else { return }
        receive(sampleBuffer, kind: output is AVCaptureVideoDataOutput ? .camera : .microphone, clock: clock)
    }

    private func receive(_ sample: CMSampleBuffer, kind: ScreenRecordingSampleKind, clock: CMClock?) {
        lock.lock()
        let active = active
        lock.unlock()
        guard active else { return }
        let timestamp = CMSampleBufferGetPresentationTimeStamp(sample)
        let hostTime = clock.map { CMSyncConvertTime(timestamp, from: $0, to: CMClockGetHostTimeClock()) } ?? timestamp
        writer.receive(ScreenRecordingCaptureSample(buffer: sample, kind: kind, hostTime: hostTime.seconds))
    }

    func reportHardwareFailure(_ error: Error) {
        lock.lock()
        let active = active
        lock.unlock()
        if active { onFailure(error) }
    }
}

final class ScreenRecordingCaptureHardware: @unchecked Sendable {
    private let queue = DispatchQueue(label: "dev.wzz.zisla.recording.devices", qos: .userInitiated)
    private let configuration: RecordingCaptureConfiguration
    private let bridge: ScreenRecordingCaptureBridge
    private let session = AVCaptureSession()
    private var observers: [NSObjectProtocol] = []
    private var cancelled = false

    init(configuration: RecordingCaptureConfiguration, bridge: ScreenRecordingCaptureBridge) {
        self.configuration = configuration
        self.bridge = bridge
    }

    func start() async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            queue.async { [self] in
                do {
                    guard !self.cancelled else { throw CancellationError() }
                    try self.configure()
                    self.session.startRunning()
                    self.bridge.setHardwareClock(self.session.synchronizationClock)
                    guard self.session.isRunning, self.session.synchronizationClock != nil else {
                        throw ScreenRecordingCaptureError.deviceUnavailable
                    }
                    for notification in [AVCaptureSession.runtimeErrorNotification, AVCaptureSession.wasInterruptedNotification] {
                        self.observers.append(NotificationCenter.default.addObserver(forName: notification, object: self.session, queue: nil) { [weak self] _ in
                            self?.bridge.reportHardwareFailure(ScreenRecordingCaptureError.deviceUnavailable)
                        })
                    }
                    continuation.resume()
                } catch { continuation.resume(throwing: error) }
            }
        }
    }

    func stop() async {
        await withCheckedContinuation { continuation in
            queue.async {
                self.cancelled = true
                for observer in self.observers { NotificationCenter.default.removeObserver(observer) }
                self.observers.removeAll()
                if self.session.isRunning { self.session.stopRunning() }
                for output in self.session.outputs {
                    (output as? AVCaptureVideoDataOutput)?.setSampleBufferDelegate(nil, queue: nil)
                    (output as? AVCaptureAudioDataOutput)?.setSampleBufferDelegate(nil, queue: nil)
                    self.session.removeOutput(output)
                }
                for input in self.session.inputs { self.session.removeInput(input) }
                self.bridge.setHardwareClock(nil)
                continuation.resume()
            }
        }
    }

    private func configure() throws {
        session.beginConfiguration()
        defer { session.commitConfiguration() }
        if configuration.camera {
            try addDevice(mediaType: .video, identifier: configuration.cameraID)
            let output = AVCaptureVideoDataOutput()
            output.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
            output.alwaysDiscardsLateVideoFrames = true
            output.setSampleBufferDelegate(bridge, queue: bridge.sampleQueue)
            guard session.canAddOutput(output) else { throw ScreenRecordingCaptureError.deviceUnavailable }
            session.addOutput(output)
        }
        if configuration.microphone {
            try addDevice(mediaType: .audio, identifier: configuration.microphoneID)
            let output = AVCaptureAudioDataOutput()
            output.setSampleBufferDelegate(bridge, queue: bridge.sampleQueue)
            guard session.canAddOutput(output) else { throw ScreenRecordingCaptureError.deviceUnavailable }
            session.addOutput(output)
        }
    }

    private func addDevice(mediaType: AVMediaType, identifier: String?) throws {
        let device: AVCaptureDevice?
        if let identifier { device = ScreenRecordingNativeCapture.devices(for: mediaType).first { $0.uniqueID == identifier } }
        else { device = AVCaptureDevice.default(for: mediaType) }
        guard let device else { throw ScreenRecordingCaptureError.deviceUnavailable }
        let input = try AVCaptureDeviceInput(device: device)
        guard session.canAddInput(input) else { throw ScreenRecordingCaptureError.deviceUnavailable }
        session.addInput(input)
    }
}

@MainActor
final class ScreenRecordingCapturePointer {
    private var frame: CGRect
    private let windowID: UInt32?
    private let frameRate: Int
    private var timeline = ScreenRecordingCaptureTimeline()
    private var records: [RecordingPointer] = []
    private var timer: Timer?
    private var monitors: [Any] = []
    private var lastButtons = 0
    private let geometryQueue = DispatchQueue(label: "dev.wzz.zisla.recording.pointer-geometry", qos: .utility)
    private var geometryGeneration = UUID()
    private var geometryPending = false
    private var nextGeometryTime: Double = 0

    init(frame: CGRect, windowID: UInt32?, frameRate: Int) {
        self.frame = frame
        self.windowID = windowID
        self.frameRate = frameRate
    }

    func start(at epoch: Double) {
        geometryGeneration = UUID()
        timeline.begin(at: epoch)
        sample()
        timer = Timer.scheduledTimer(withTimeInterval: 1 / Double(frameRate), repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.sample() }
        }
        let handler: @Sendable (NSEvent) -> Void = { [weak self] event in
            let point = event.cgEvent?.location
            let time = event.timestamp
            let kind: RecordingPointerKind = event.type == .rightMouseDown ? .rightClick : .leftClick
            Task { @MainActor [weak self] in
                if let point { self?.append(point: point, hostTime: time, kind: kind) }
            }
        }
        monitors = Self.installEventMonitors(
            global: { NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown], handler: handler) },
            local: { NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown], handler: { event in
                handler(event)
                return event
            }) }
        )
    }

    static func installEventMonitors(global: () -> Any?, local: () -> Any?) -> [Any] {
        // A local-only monitor cannot observe clicks in the application being recorded.
        guard let global = global() else { return [] }
        var monitors = [global]
        if let local = local() { monitors.append(local) }
        return monitors
    }

    func setPaused(_ paused: Bool, at time: Double) {
        if paused { timeline.pause(at: time) } else { timeline.resume(at: time) }
    }

    func stop(at time: Double) -> [RecordingPointer] {
        geometryGeneration = UUID()
        timer?.invalidate()
        timer = nil
        for monitor in monitors { NSEvent.removeMonitor(monitor) }
        monitors.removeAll()
        let duration = timeline.elapsed(at: time)
        timeline = ScreenRecordingCaptureTimeline()
        let result = records.filter { $0.time <= duration }.sorted { $0.time < $1.time }
        records.removeAll()
        return result
    }

    private func sample() {
        guard timeline.pausedAt == nil else { return }
        let now = CMClockGetTime(CMClockGetHostTimeClock()).seconds
        refreshWindowFrame(at: now)
        let point = WindowPreviewLayout.quartzPoint(for: NSEvent.mouseLocation,
                                                    mainScreenTop: CGDisplayBounds(CGMainDisplayID()).height)
        append(point: point, hostTime: now, kind: .move)
        let buttons = NSEvent.pressedMouseButtons
        if monitors.isEmpty {
            if buttons & 1 != 0, lastButtons & 1 == 0 { append(point: point, hostTime: now, kind: .leftClick) }
            if buttons & 2 != 0, lastButtons & 2 == 0 { append(point: point, hostTime: now, kind: .rightClick) }
        }
        lastButtons = buttons
    }

    private func refreshWindowFrame(at time: Double) {
        guard let windowID, !geometryPending, time >= nextGeometryTime else { return }
        geometryPending = true
        nextGeometryTime = time + 0.25
        let generation = geometryGeneration
        geometryQueue.async { [weak self] in
            let descriptions = CGWindowListCopyWindowInfo([.optionIncludingWindow], windowID) as? [[String: Any]]
            let bounds = descriptions?.first?[kCGWindowBounds as String] as? NSDictionary
            let current = bounds.flatMap { CGRect(dictionaryRepresentation: $0 as CFDictionary) }
            Task { @MainActor [weak self] in
                guard let self, self.geometryGeneration == generation else { return }
                self.geometryPending = false
                if let current { self.frame = current }
            }
        }
    }

    private func append(point: CGPoint, hostTime: Double, kind: RecordingPointerKind) {
        guard let time = timeline.time(for: hostTime), records.count < 4_000_000,
              let normalized = ScreenRecordingCaptureGeometry.normalizedPointer(point, in: frame) else { return }
        records.append(RecordingPointer(time: time, x: normalized.x, y: normalized.y, kind: kind))
    }
}
