import AppKit
import AVFoundation
import CoreMedia
import CoreVideo
import Foundation
import Testing
import ZislaCore

@testable import Zisla

@Suite @MainActor
struct ScreenRecordingCaptureTests {
    @Test
    func listingSourcesDoesNotRequestCameraOrMicrophoneAccess() async throws {
        let system = CaptureTestSystem()
        let service = ScreenRecordingService(dependencies: system.dependencies())
        #expect(system.permissions.isEmpty)
        try await service.loadSources()
        #expect(service.sources.count == 1)
        #expect(service.cameras == [.init(id: "synthetic-camera", name: "Camera")])
        #expect(service.microphones == [.init(id: "synthetic-mic", name: "Microphone")])
        #expect(system.permissions.isEmpty, "枚举来源不应触发输入设备授权")
    }

    @Test
    func staysPreparingUntilFirstScreenFrameAndPreservesLateTrackOffset() async throws {
        let system = CaptureTestSystem()
        let service = ScreenRecordingService(dependencies: system.dependencies())
        let task = Task { try await service.start(configuration: .init(microphone: true, camera: true), directory: system.directory) }
        await system.session.startEntered.wait()
        #expect(service.phase == .preparing)
        #expect(system.permissions == [.screen, .microphone, .camera])
        system.session.firstFrame.resolve(.success(100))
        try await task.value
        #expect(service.phase == .recording)
        system.now = 104
        system.tick?()
        #expect(service.elapsed == 4)
        await service.cancel()
        #expect(service.phase == .idle)
        #expect(system.session.released)
    }

    @Test(arguments: [ScreenRecordingPermission.screen, .microphone, .camera])
    func deniedPermissionsLeaveNoActiveCapture(permission: ScreenRecordingPermission) async throws {
        let system = CaptureTestSystem()
        system.denied = permission
        let service = ScreenRecordingService(dependencies: system.dependencies())
        await #expect(throws: ScreenRecordingCaptureError.permission(permission)) {
            try await service.start(configuration: .init(microphone: true, camera: true), directory: system.directory)
        }
        #expect(service.phase == .idle)
        #expect(service.errorMessage == ScreenRecordingCaptureError.permission(permission).localizedDescription)
        #expect(!system.session.started)
    }

    @Test
    func duplicateStartIsRejectedAndConcurrentStopsShareTheFinishedResult() async throws {
        let system = CaptureTestSystem()
        system.session.firstFrame.resolve(.success(100))
        system.session.finishHeld = true
        let service = ScreenRecordingService(dependencies: system.dependencies())
        try await service.start(configuration: .init(), directory: system.directory)
        await #expect(throws: ScreenRecordingCaptureError.alreadyRecording) {
            try await service.start(configuration: .init(), directory: system.directory)
        }
        let first = Task { try await service.stop() }
        await system.session.stopEntered.wait()
        let second = Task { try await service.stop() }
        #expect(service.phase == .finishing)
        system.session.finish.resolve(.success(system.session.result))
        let firstResult = try await first.value
        let secondResult = try await second.value
        #expect(firstResult == secondResult)
        #expect(service.phase == .idle)
        #expect(try await service.stop() == firstResult)
    }

    @Test
    func cancellationDuringFirstFrameWaitReleasesResourcesAndAllowsRestart() async throws {
        let system = CaptureTestSystem()
        let service = ScreenRecordingService(dependencies: system.dependencies())
        let task = Task { try await service.start(configuration: .init(), directory: system.directory) }
        await system.session.startEntered.wait()
        await service.cancel()
        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(service.phase == .idle)
        #expect(service.errorMessage == nil)
        #expect(system.session.released)
        system.session = CaptureTestSession()
        system.session.firstFrame.resolve(.success(200))
        try await service.start(configuration: .init(), directory: system.directory)
        #expect(service.phase == .recording)
        await service.cancel()
    }

    @Test
    func stopBeforeFirstFrameCancelsRatherThanPublishingAnEmptyRecording() async throws {
        let system = CaptureTestSystem()
        let service = ScreenRecordingService(dependencies: system.dependencies())
        let task = Task { try await service.start(configuration: .init(), directory: system.directory) }
        await system.session.startEntered.wait()
        await #expect(throws: ScreenRecordingCaptureError.noScreenFrames) { try await service.stop() }
        _ = await task.result
        #expect(service.phase == .idle)
        #expect(system.session.released)
    }

    @Test
    func pauseFreezesElapsedAndAllTracksUseTheSameResumeOffset() async throws {
        let system = CaptureTestSystem()
        system.session.firstFrame.resolve(.success(100))
        let service = ScreenRecordingService(dependencies: system.dependencies())
        try await service.start(configuration: .init(), directory: system.directory)
        system.now = 102
        await service.togglePause()
        system.now = 110
        system.tick?()
        #expect(service.phase == .paused)
        #expect(service.elapsed == 2)
        await service.togglePause()
        system.now = 112
        system.tick?()
        #expect(service.phase == .recording)
        #expect(service.elapsed == 4)
        #expect(system.session.pauseEvents.map(\.time) == [102, 110])
        await service.cancel()
    }

    @Test
    func writerFailureCleansUpAndRetainsItsOriginalError() async throws {
        let system = CaptureTestSystem()
        system.session.firstFrame.resolve(.success(100))
        system.session.finishError = CaptureTestError.diskFull
        let service = ScreenRecordingService(dependencies: system.dependencies())
        try await service.start(configuration: .init(), directory: system.directory)
        await #expect(throws: CaptureTestError.diskFull) { try await service.stop() }
        #expect(service.phase == .idle)
        #expect(service.elapsed == 0)
        #expect(system.session.released)
        #expect(service.errorMessage == CaptureTestError.diskFull.localizedDescription)
    }

    @Test
    func cancellationAfterSessionProducesResultRollsBackBeforeServiceAcceptsIt() async throws {
        let system = CaptureTestSystem()
        system.session.firstFrame.resolve(.success(100))
        system.session.finishHeld = true
        system.session.returnsResultAfterCancellation = true
        let service = ScreenRecordingService(dependencies: system.dependencies())
        try await service.start(configuration: .init(), directory: system.directory)
        let task = Task { try await service.stop() }
        await system.session.stopEntered.wait()
        await service.cancel()
        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(service.phase == .idle)
        #expect(service.errorMessage == nil)
        #expect(system.session.released)
        await #expect(throws: ScreenRecordingCaptureError.cancelled) { try await service.stop() }
    }

    @Test
    func cancellingWhilePermissionsArePendingNeverStartsTheReturnedSession() async throws {
        let system = CaptureTestSystem()
        let permission = CaptureTestLatch<Bool>()
        let entered = CaptureTestSignal()
        var dependencies = system.dependencies()
        dependencies.requestPermission = { _ in
            entered.signal()
            return try! await permission.wait()
        }
        let service = ScreenRecordingService(dependencies: dependencies)
        let task = Task { try await service.start(configuration: .init(), directory: system.directory) }
        await entered.wait()
        await service.cancel()
        permission.resolve(.success(true))
        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(service.phase == .idle)
        #expect(!system.session.started)
    }

    @Test
    func invalidConfigurationIsRejectedBeforeAnyPermissionRequest() async throws {
        let system = CaptureTestSystem()
        let service = ScreenRecordingService(dependencies: system.dependencies())
        await #expect(throws: ScreenRecordingCaptureError.invalidFrameRate) {
            try await service.start(configuration: .init(frameRate: 0), directory: system.directory)
        }
        await #expect(throws: ScreenRecordingCaptureError.invalidRegion) {
            try await service.start(configuration: .init(mode: .region), directory: system.directory)
        }
        #expect(system.permissions.isEmpty)
        #expect(service.phase == .idle)
    }

    @Test
    func sourceLoadFailureIsVisibleAndDoesNotStartCapture() async throws {
        let system = CaptureTestSystem()
        var dependencies = system.dependencies()
        dependencies.loadSources = { throw CaptureTestError.unavailable }
        let service = ScreenRecordingService(dependencies: dependencies)
        await #expect(throws: CaptureTestError.unavailable) { try await service.loadSources() }
        #expect(service.sources.isEmpty)
        #expect(service.errorMessage == CaptureTestError.unavailable.localizedDescription)
        #expect(system.permissions.isEmpty)
    }

    @Test
    func regionAndPointerCoordinatesStayLocalOnDisplaysWithNegativeOrigins() throws {
        let frame = try ScreenRecordingCaptureGeometry.region(.init(x: 120, y: 80, width: 640, height: 360),
                                                               in: CGRect(x: -1920, y: -200, width: 1920, height: 1080))
        #expect(frame == CGRect(x: -1800, y: -120, width: 640, height: 360))
        #expect(ScreenRecordingCaptureGeometry.normalizedPointer(CGPoint(x: -1480, y: 60), in: frame) == CGPoint(x: 0.5, y: 0.5))
        #expect(ScreenRecordingCaptureGeometry.normalizedPointer(CGPoint(x: -1800, y: -120), in: frame) == .zero)
        #expect(ScreenRecordingCaptureGeometry.normalizedPointer(CGPoint(x: 0, y: 0), in: frame) == nil)
        #expect(throws: ScreenRecordingCaptureError.invalidRegion) {
            try ScreenRecordingCaptureGeometry.region(.init(x: 1800, y: 0, width: 400, height: 300),
                                                       in: CGRect(x: -1920, y: 0, width: 1920, height: 1080))
        }
    }

    @Test
    func unavailableGlobalPointerMonitorKeepsButtonPollingEnabled() {
        let unavailable = ScreenRecordingCapturePointer.installEventMonitors(global: { nil }, local: { "local" })
        #expect(unavailable.isEmpty, "全局监听失败时，本地监听不得阻止按钮轮询回退")
        let complete = ScreenRecordingCapturePointer.installEventMonitors(global: { "global" }, local: { "local" })
        #expect(complete.compactMap { $0 as? String } == ["global", "local"])
        let globalOnly = ScreenRecordingCapturePointer.installEventMonitors(global: { "global" }, local: { nil })
        #expect(globalOnly.compactMap { $0 as? String } == ["global"])
    }

    @Test
    func pauseMappingHandlesSamplesDeliveredAfterResumeInTheirOriginalOrder() {
        var timeline = ScreenRecordingCaptureTimeline()
        timeline.begin(at: 100)
        timeline.pause(at: 102)
        #expect(timeline.time(for: 103) == nil)
        timeline.resume(at: 110)
        #expect(timeline.time(for: 103) == nil, "迟到的暂停样本不能进入媒体文件")
        #expect(timeline.time(for: 101) == 1, "迟到的暂停前样本不应扣除未来暂停")
        #expect(timeline.time(for: 111) == 3)
        #expect(timeline.time(for: 99) == nil)
        timeline.pause(at: 112)
        timeline.resume(at: 114)
        #expect(timeline.time(for: 115) == 5)
    }

    @Test
    func deterministicPauseScheduleAlwaysProducesMonotonicTime() {
        var timeline = ScreenRecordingCaptureTimeline()
        timeline.begin(at: 0)
        var seed: UInt64 = 0x19A8
        var host: Double = 0
        var active: Double = 0
        for _ in 0..<128 {
            seed = seed &* 6_364_136_223_846_793_005 &+ 1
            let gap = Double(seed % 1_000 + 1) / 1_000
            host += gap
            active += gap
            #expect(abs(timeline.time(for: host)! - active) < 0.000_001)
            timeline.pause(at: host)
            seed = seed &* 6_364_136_223_846_793_005 &+ 1
            let pause = Double(seed % 1_000 + 1) / 1_000
            #expect(timeline.time(for: host + pause / 2) == nil)
            host += pause
            timeline.resume(at: host)
        }
    }

    @Test
    func highResolutionSourcesUseHEVCAndEvenPixelDimensions() throws {
        #expect(ScreenRecordingCaptureEncoding.codec(width: 5120, height: 2880) == .hevc)
        #expect(ScreenRecordingCaptureEncoding.codec(width: 3840, height: 2160) == .h264)
        let dimensions = try ScreenRecordingCaptureGeometry.pixelDimensions(size: CGSize(width: 801, height: 601), scale: 1)
        #expect(dimensions.width == 800)
        #expect(dimensions.height == 600)
        #expect(throws: ScreenRecordingCaptureError.invalidSource) {
            try ScreenRecordingCaptureGeometry.pixelDimensions(size: CGSize(width: CGFloat.infinity, height: 100), scale: 2)
        }
    }

    @Test
    func syntheticTracksUseScreenEpochKeepLateStartsAndIgnorePauseAndDuplicateFrames() async throws {
        let disk = try CaptureTestDisk()
        defer { disk.remove() }
        let configuration = RecordingCaptureConfiguration(systemAudio: true, microphone: true, camera: true)
        let files = try ScreenRecordingCaptureFiles(directory: disk.url)
        let assets = CaptureTestAssets()
        let writer = ScreenRecordingCaptureWriter(files: files, configuration: configuration, width: 16, height: 16,
                                                  onFailure: { _ in }, factory: assets.make)
        writer.receive(try syntheticVideo(time: 100.2, kind: .camera))
        writer.receive(try syntheticAudio(time: 100.4, kind: .microphone))
        writer.receive(try syntheticVideo(time: 100, kind: .screen))
        await writer.flush()
        #expect(try await writer.waitForFirstFrame() == 100)
        #expect(assets.times(.screen) == [0])
        #expect(assets.times(.camera) == [0.2])
        #expect(assets.times(.microphone) == [0.4])
        writer.receive(try syntheticAudio(time: 100.5, kind: .systemAudio))
        await writer.setPaused(true, at: 101)
        writer.receive(try syntheticVideo(time: 102, kind: .screen))
        await writer.setPaused(false, at: 105)
        writer.receive(try syntheticVideo(time: 102, kind: .camera))
        writer.receive(try syntheticVideo(time: 105.5, kind: .screen))
        writer.receive(try syntheticVideo(time: 105.5, kind: .screen))
        writer.receive(try syntheticVideo(time: 105.4, kind: .screen))
        writer.receive(try syntheticAudio(time: 105.7, kind: .microphone))
        writer.receive(try syntheticVideo(time: 105.8, kind: .camera))
        await writer.seal(at: 106)
        let duration = try await writer.finish()
        #expect(duration == 2)
        #expect(assets.times(.screen) == [0, 1.5])
        let cameraTimes = assets.times(.camera)
        #expect(cameraTimes.count == 2 && zip(cameraTimes, [0.2, 1.8]).allSatisfy { abs($0 - $1) < 0.000_002 })
        #expect(assets.times(.microphone) == [0.4, 1.7])
        #expect(assets.times(.systemAudio) == [0.5])
        #expect(assets.finishTimes == [2, 2, 2])
        #expect(files.discard() == nil)
    }

    @Test
    func backpressureDoesNotAdvanceTheTrackTimestampGate() async throws {
        let disk = try CaptureTestDisk()
        defer { disk.remove() }
        let files = try ScreenRecordingCaptureFiles(directory: disk.url)
        let assets = CaptureTestAssets()
        assets.ready = false
        let writer = ScreenRecordingCaptureWriter(files: files, configuration: .init(systemAudio: false), width: 16, height: 16,
                                                  onFailure: { _ in }, factory: assets.make)
        writer.receive(try syntheticVideo(time: 100, kind: .screen))
        await writer.flush()
        assets.ready = true
        writer.receive(try syntheticVideo(time: 100, kind: .screen))
        await writer.flush()
        #expect(try await writer.waitForFirstFrame() == 100)
        #expect(assets.times(.screen) == [0])
        await writer.cancel()
        #expect(assets.released)
        #expect(files.discard() == nil)
    }

    @Test
    func firstAcceptedScreenFrameAnchorsEveryTrackAfterInitialBackpressure() async throws {
        let disk = try CaptureTestDisk()
        defer { disk.remove() }
        let files = try ScreenRecordingCaptureFiles(directory: disk.url)
        let assets = CaptureTestAssets()
        assets.ready = false
        let writer = ScreenRecordingCaptureWriter(files: files, configuration: .init(systemAudio: false, camera: true),
                                                  width: 16, height: 16, onFailure: { _ in }, factory: assets.make)
        writer.receive(try syntheticVideo(time: 100, kind: .screen))
        writer.receive(try syntheticVideo(time: 100.5, kind: .camera))
        await writer.flush()
        assets.ready = true
        writer.receive(try syntheticVideo(time: 101, kind: .screen))
        await writer.flush()
        #expect(try await writer.waitForFirstFrame() == 101)
        writer.receive(try syntheticVideo(time: 101.5, kind: .camera))
        await writer.seal(at: 102)
        #expect(try await writer.finish() == 1)
        #expect(assets.times(.screen) == [0])
        #expect(assets.times(.camera) == [0.5])
        #expect(files.discard() == nil)
    }

    @Test
    func writerAppendFailureUnblocksFirstFrameWaitAndCannotPublish() async throws {
        let disk = try CaptureTestDisk()
        defer { disk.remove() }
        let files = try ScreenRecordingCaptureFiles(directory: disk.url)
        let assets = CaptureTestAssets()
        assets.appendError = .diskFull
        let failures = CaptureTestErrors()
        let writer = ScreenRecordingCaptureWriter(files: files, configuration: .init(), width: 16, height: 16,
                                                  onFailure: failures.append, factory: assets.make)
        writer.receive(try syntheticVideo(time: 100, kind: .screen))
        await writer.flush()
        await #expect(throws: CaptureTestError.diskFull) { try await writer.waitForFirstFrame() }
        #expect(failures.values == [.diskFull])
        await writer.seal(at: 101)
        await #expect(throws: CaptureTestError.diskFull) { try await writer.finish() }
        await writer.cancel()
        #expect(assets.released)
        #expect(files.discard() == nil)
    }

    @Test
    func missingCameraIsAnExplicitFailureAndLateCallbacksAfterSealAreIgnored() async throws {
        let disk = try CaptureTestDisk()
        defer { disk.remove() }
        let files = try ScreenRecordingCaptureFiles(directory: disk.url)
        let assets = CaptureTestAssets()
        let writer = ScreenRecordingCaptureWriter(files: files, configuration: .init(camera: true), width: 16, height: 16,
                                                  onFailure: { _ in }, factory: assets.make)
        writer.receive(try syntheticVideo(time: 100, kind: .screen))
        await writer.seal(at: 101)
        writer.receive(try syntheticVideo(time: 101, kind: .camera))
        await writer.flush()
        await #expect(throws: ScreenRecordingCaptureError.noCameraFrames) { try await writer.finish() }
        #expect(assets.times(.camera).isEmpty)
        await writer.cancel()
        #expect(files.discard() == nil)
    }

    @Test
    func finishFailureCancelsEveryAllocatedWriter() async throws {
        let disk = try CaptureTestDisk()
        defer { disk.remove() }
        let files = try ScreenRecordingCaptureFiles(directory: disk.url)
        let assets = CaptureTestAssets()
        assets.finishError = .diskFull
        let writer = ScreenRecordingCaptureWriter(files: files, configuration: .init(microphone: true), width: 16, height: 16,
                                                  onFailure: { _ in }, factory: assets.make)
        writer.receive(try syntheticVideo(time: 100, kind: .screen))
        writer.receive(try syntheticAudio(time: 100.2, kind: .microphone))
        await writer.seal(at: 101)
        await #expect(throws: CaptureTestError.diskFull) { try await writer.finish() }
        await writer.cancel()
        #expect(assets.released)
        #expect(files.discard() == nil)
    }

    @Test
    func microphoneFinishFailureImmediatelyCancelsAStalledScreenWriter() async throws {
        let disk = try CaptureTestDisk()
        defer { disk.remove() }
        let files = try ScreenRecordingCaptureFiles(directory: disk.url)
        let screen = CaptureTestAssets()
        screen.finishHeld = true
        let microphone = CaptureTestAssets()
        microphone.finishError = .diskFull
        let failures = CaptureTestErrors()
        let writer = ScreenRecordingCaptureWriter(files: files, configuration: .init(systemAudio: false, microphone: true),
                                                  width: 16, height: 16, finishTimeout: 0, onFailure: failures.append,
                                                  factory: { _, kind, _ in
            CaptureTestAssetWriter(assets: kind == .microphone ? microphone : screen)
        })
        writer.receive(try syntheticVideo(time: 100, kind: .screen))
        writer.receive(try syntheticAudio(time: 100, kind: .microphone))
        await writer.seal(at: 101)
        await #expect(throws: CaptureTestError.diskFull) { try await writer.finish() }
        #expect(failures.values == [.diskFull], "The stalled screen must not replace the microphone failure with a timeout")
        #expect(screen.released && microphone.released)
        screen.releaseFinishes(.success(()))
        await writer.flush()
        await #expect(throws: CaptureTestError.diskFull) { try await writer.finish() }
        #expect(files.discard() == nil)
    }

    @Test
    func syntheticNativeWriterPublishesReadableVideoWithoutCapturingTheScreen() async throws {
        let disk = try CaptureTestDisk()
        defer { disk.remove() }
        let files = try ScreenRecordingCaptureFiles(directory: disk.url)
        let writer = ScreenRecordingCaptureWriter(files: files, configuration: .init(systemAudio: false), width: 16, height: 16,
                                                  onFailure: { _ in })
        writer.receive(try syntheticVideo(time: 100, kind: .screen))
        await writer.flush()
        _ = try await writer.waitForFirstFrame()
        for frame in 1...5 {
            writer.receive(try syntheticVideo(time: 100 + Double(frame) / 30, kind: .screen))
            await writer.flush()
        }
        await writer.seal(at: 102)
        let duration = try await writer.finish()
        try files.publish([files.screenName])
        let asset = AVURLAsset(url: disk.url.appendingPathComponent(files.screenName))
        let tracks = try await asset.loadTracks(withMediaType: .video)
        #expect(tracks.count == 1)
        #expect(abs(try await asset.load(.duration).seconds - 2) < 0.05, "静止桌面末尾的时长应保留")
        #expect(duration == 2)
        #expect(!FileManager.default.fileExists(atPath: files.staging.path))
    }

    @Test
    func syntheticCameraAndMicrophoneFilesRetainTheirEmptyLeadingEdit() async throws {
        let disk = try CaptureTestDisk()
        defer { disk.remove() }
        let files = try ScreenRecordingCaptureFiles(directory: disk.url)
        let writer = ScreenRecordingCaptureWriter(files: files, configuration: .init(systemAudio: false, microphone: true, camera: true),
                                                  width: 16, height: 16, onFailure: { _ in })
        writer.receive(try syntheticVideo(time: 100, kind: .screen))
        await writer.flush()
        writer.receive(try syntheticVideo(time: 100.5, kind: .camera))
        await writer.flush()
        writer.receive(try syntheticAudio(time: 100.25, kind: .microphone))
        await writer.flush()
        await writer.seal(at: 102)
        #expect(try await writer.finish() == 2)
        try files.publish([files.screenName, files.cameraName, files.microphoneName])
        let camera = AVURLAsset(url: disk.url.appendingPathComponent(files.cameraName))
        let microphone = AVURLAsset(url: disk.url.appendingPathComponent(files.microphoneName))
        let cameraTrack = try #require(try await camera.loadTracks(withMediaType: .video).first)
        let microphoneTrack = try #require(try await microphone.loadTracks(withMediaType: .audio).first)
        #expect(try await microphone.loadTracks(withMediaType: .video).isEmpty)
        #expect(abs(try await camera.load(.duration).seconds - 2) < 0.05)
        let cameraSegments = try await cameraTrack.load(.segments)
        let microphoneSegments = try await microphoneTrack.load(.segments)
        #expect(cameraSegments.first?.isEmpty == true)
        #expect(microphoneSegments.first?.isEmpty == true)
        #expect(abs((cameraSegments.first?.timeMapping.target.duration.seconds ?? 0) - 0.5) < 0.01)
        #expect(abs((microphoneSegments.first?.timeMapping.target.duration.seconds ?? 0) - 0.25) < 0.03)
    }

    @Test
    func completedCaptureUsesTheActualScreenEndAndCanImmediatelyPreviewAndExport() async throws {
        let disk = try CaptureTestDisk()
        defer { disk.remove() }
        let directory = disk.url.appendingPathComponent("project", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        let files = try ScreenRecordingCaptureFiles(directory: directory)
        let writer = ScreenRecordingCaptureWriter(files: files, configuration: .init(systemAudio: true, microphone: true, camera: true),
                                                  width: 16, height: 16, onFailure: { _ in })
        writer.receive(try syntheticVideo(time: 100, kind: .screen, duration: CMTime(value: 1, timescale: 300)))
        await writer.flush()
        writer.receive(try syntheticVideo(time: 100.003333, kind: .camera))
        await writer.flush()
        writer.receive(try syntheticVideo(time: 100.04, kind: .screen, duration: CMTime(value: 1, timescale: 300)))
        await writer.flush()
        for time in stride(from: 100.001, through: 100.091, by: 0.01) {
            writer.receive(try syntheticAudio(time: time, kind: .systemAudio))
            await writer.flush()
            writer.receive(try syntheticAudio(time: time, kind: .microphone))
            await writer.flush()
        }
        await writer.seal(at: 100.103357)
        let requestedDuration = try await writer.finish()
        let screenAsset = AVURLAsset(url: files.url(for: files.screenName))
        let screenTrack = try #require(try await screenAsset.loadTracks(withMediaType: .video).first)
        let screenEnd = try await screenTrack.load(.timeRange).end.seconds
        #expect(requestedDuration > screenEnd + 0.001, "短屏幕 sample 的最后一帧不会被 endSession 延长到停止时刻")
        #expect(try await screenAsset.load(.duration).seconds > screenEnd, "音频尾部不能用作屏幕有效时长")
        let provisional = ScreenRecordingResult(videoFile: files.screenName, cameraFile: files.cameraName,
                                                microphoneFile: files.microphoneName, duration: requestedDuration,
                                                width: 16, height: 16, pointers: [
                                                    .init(time: 0, x: 0.5, y: 0.5),
                                                    .init(time: screenEnd, x: 0.5, y: 0.5),
                                                    .init(time: screenEnd + 0.002, x: 0.5, y: 0.5),
                                                    .init(time: requestedDuration, x: 0.5, y: 0.5),
                                                ])
        let result = try await ScreenRecordingCaptureMedia.finalizedResult(provisional, videoURL: files.url(for: files.screenName))
        #expect(result.duration == screenEnd)
        #expect(result.pointers.map(\.time) == [0, screenEnd])
        try files.publish([files.screenName, files.cameraName, files.microphoneName])

        let oversized = ScreenRecordingProject(result: provisional, name: "Uncorrected capture")
        let oversizedTimeline = try RecordingExportTimeline(project: oversized)
        await #expect(throws: ScreenRecordingExportError.timelineOutsideMedia) {
            try await RecordingExportMedia.prepare(project: oversized, directory: directory, timeline: oversizedTimeline)
        }
        let project = ScreenRecordingProject(result: result, name: "Completed capture")
        try project.validate()
        let timeline = try RecordingExportTimeline(project: project)
        let media = try await RecordingExportMedia.prepare(project: project, directory: directory, timeline: timeline)
        #expect(media.timeline.duration == screenEnd)
        let exporter = ScreenRecordingExporter()
        let preview = try await exporter.preview(project: project, directory: directory, sourceTime: result.duration,
                                                 maximumSize: CGSize(width: 32, height: 32))
        #expect(preview.width > 0 && preview.height > 0, "最后一帧边界仍须可预览")
        let output = disk.url.appendingPathComponent("completed.mp4")
        try await exporter.export(project: project, directory: directory, to: output,
                                  configuration: .init(resolution: .source, frameRate: 30))
        let exported = AVURLAsset(url: output)
        #expect(try await exported.loadTracks(withMediaType: .video).count == 1)
        #expect(try await exported.load(.duration).seconds > 0)

        var shorter = provisional
        shorter.duration = screenEnd / 2
        let bounded = try await ScreenRecordingCaptureMedia.finalizedResult(shorter, videoURL: directory.appendingPathComponent(files.screenName))
        #expect(bounded.duration == shorter.duration, "读取媒体元数据不得延长实际录制的停止时长")
        #expect(bounded.pointers.map(\.time) == [0])
        withExtendedLifetime(screenAsset) {}
    }

    @Test
    func completedCaptureRejectsMissingCorruptAndAudioOnlyScreenMedia() async throws {
        let disk = try CaptureTestDisk()
        defer { disk.remove() }
        let provisional = ScreenRecordingResult(videoFile: "screen.mp4", duration: 1, width: 16, height: 16)
        let missing = disk.url.appendingPathComponent("missing.mp4")
        await #expect(throws: (any Error).self) {
            try await ScreenRecordingCaptureMedia.finalizedResult(provisional, videoURL: missing)
        }
        #expect(!FileManager.default.fileExists(atPath: missing.path))
        let corrupt = disk.url.appendingPathComponent("corrupt.mp4")
        let invalidBytes = Data([0, 1, 2, 3])
        try invalidBytes.write(to: corrupt)
        await #expect(throws: (any Error).self) {
            try await ScreenRecordingCaptureMedia.finalizedResult(provisional, videoURL: corrupt)
        }
        #expect(try Data(contentsOf: corrupt) == invalidBytes)

        let files = try ScreenRecordingCaptureFiles(directory: disk.url)
        let writer = ScreenRecordingCaptureWriter(files: files, configuration: .init(systemAudio: false, microphone: true),
                                                  width: 16, height: 16, onFailure: { _ in })
        writer.receive(try syntheticVideo(time: 100, kind: .screen))
        await writer.flush()
        writer.receive(try syntheticAudio(time: 100.1, kind: .microphone))
        await writer.flush()
        await writer.seal(at: 101)
        _ = try await writer.finish()
        await #expect(throws: ScreenRecordingCaptureError.noScreenFrames) {
            try await ScreenRecordingCaptureMedia.finalizedResult(provisional, videoURL: files.url(for: files.microphoneName))
        }
        #expect(FileManager.default.fileExists(atPath: files.url(for: files.microphoneName).path))
    }

    @Test
    func finishTimeoutCancelsAStalledWriterAndUnblocksTheCaller() async throws {
        let disk = try CaptureTestDisk()
        defer { disk.remove() }
        let files = try ScreenRecordingCaptureFiles(directory: disk.url)
        let assets = CaptureTestAssets()
        assets.finishHeld = true
        let writer = ScreenRecordingCaptureWriter(files: files, configuration: .init(systemAudio: false), width: 16, height: 16,
                                                  finishTimeout: 0, onFailure: { _ in }, factory: assets.make)
        writer.receive(try syntheticVideo(time: 100, kind: .screen))
        await writer.seal(at: 101)
        await #expect(throws: ScreenRecordingCaptureError.saveFailed(AppLocalization.text("录屏文件写入超时"))) {
            try await writer.finish()
        }
        #expect(assets.released)
        await writer.cancel()
        #expect(files.discard() == nil)
    }

    @Test
    func partialPublishingRollsBackOnlyThisRecordingAndPreservesExistingFiles() throws {
        let disk = try CaptureTestDisk()
        defer { disk.remove() }
        let existing = disk.url.appendingPathComponent("existing.txt")
        try Data("keep".utf8).write(to: existing)
        var operations = ScreenRecordingCaptureFileOperations.live
        let move = operations.move
        var moves = 0
        operations.move = { source, destination in
            moves += 1
            if moves == 2 { throw CaptureTestError.diskFull }
            try move(source, destination)
        }
        let files = try ScreenRecordingCaptureFiles(directory: disk.url, operations: operations)
        try Data([1]).write(to: files.url(for: files.screenName))
        try Data([2]).write(to: files.url(for: files.cameraName))
        #expect(throws: CaptureTestError.diskFull) { try files.publish([files.screenName, files.cameraName]) }
        #expect(files.discard() == nil)
        #expect(try FileManager.default.contentsOfDirectory(atPath: disk.url.path) == ["existing.txt"])
        #expect(try Data(contentsOf: existing) == Data("keep".utf8))
    }

    @Test
    func nonFileAndSymlinkDirectoriesAreRejectedWithoutCreatingStaging() throws {
        let disk = try CaptureTestDisk()
        defer { disk.remove() }
        #expect(throws: ScreenRecordingCaptureError.invalidDirectory) {
            try ScreenRecordingCaptureFiles(directory: URL(string: "https://synthetic.invalid")!)
        }
        let link = disk.url.appendingPathComponent("link")
        let target = disk.url.appendingPathComponent("target")
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: false)
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)
        #expect(throws: ScreenRecordingCaptureError.invalidDirectory) { try ScreenRecordingCaptureFiles(directory: link) }
        #expect(try FileManager.default.contentsOfDirectory(atPath: target.path).isEmpty)
    }

    @Test
    func cancelledStartGateCannotBeRevivedByALateFirstFrame() async throws {
        let gate = ScreenRecordingCaptureStartGate()
        gate.resolve(.failure(CancellationError()))
        gate.resolve(.success(100))
        await #expect(throws: CancellationError.self) { try await gate.wait(timeout: 10) }
    }

    @Test
    func noFirstFrameTimeoutIsDeterministicAndLaterFramesCannotResolveIt() async throws {
        let gate = ScreenRecordingCaptureStartGate()
        await #expect(throws: ScreenRecordingCaptureError.noScreenFrames) { try await gate.wait(timeout: 0) }
        gate.resolve(.success(100))
        await #expect(throws: ScreenRecordingCaptureError.noScreenFrames) { try await gate.wait(timeout: 0) }
    }

    @Test
    func staleSourceEnumerationCannotOverwriteTheNewerList() async throws {
        let system = CaptureTestSystem()
        let first = CaptureTestLatch<[RecordingCaptureSource]>()
        let entered = CaptureTestSignal()
        var loads = 0
        var dependencies = system.dependencies()
        dependencies.loadSources = {
            loads += 1
            if loads == 1 { entered.signal(); return try await first.wait() }
            return [.init(id: 2, name: "Latest", mode: .display, frame: .init(x: 0, y: 0, width: 10, height: 10))]
        }
        let service = ScreenRecordingService(dependencies: dependencies)
        let old = Task { try await service.loadSources() }
        await entered.wait()
        try await service.loadSources()
        first.resolve(.success([.init(id: 1, name: "Old", mode: .display, frame: .init(x: 0, y: 0, width: 10, height: 10))]))
        try await old.value
        #expect(service.sources.map(\.id) == [2])
    }

    @Test
    func cancellationReportsCleanupFailureAndReleasesTheService() async throws {
        let system = CaptureTestSystem()
        system.session.firstFrame.resolve(.success(100))
        system.session.cancelError = .unavailable
        var service: ScreenRecordingService? = ScreenRecordingService(dependencies: system.dependencies())
        weak var released = service
        try await service!.start(configuration: .init(), directory: system.directory)
        await service!.cancel()
        #expect(service!.phase == .idle)
        #expect(service!.errorMessage == CaptureTestError.unavailable.localizedDescription)
        #expect(system.tick == nil)
        service = nil
        #expect(released == nil)
    }

    @Test
    func pauseStopsTheSharedMediaDurationAtThePauseBoundary() async throws {
        let disk = try CaptureTestDisk()
        defer { disk.remove() }
        let files = try ScreenRecordingCaptureFiles(directory: disk.url)
        let assets = CaptureTestAssets()
        let writer = ScreenRecordingCaptureWriter(files: files, configuration: .init(systemAudio: false), width: 16, height: 16,
                                                  onFailure: { _ in }, factory: assets.make)
        writer.receive(try syntheticVideo(time: 100, kind: .screen))
        await writer.setPaused(true, at: 101)
        await writer.seal(at: 105)
        #expect(try await writer.finish() == 1)
        #expect(assets.finishTimes == [1])
        #expect(files.discard() == nil)
    }

    @Test
    func disabledInputTracksNeverReachTheMediaFilesAndInvalidSamplesAreIgnored() async throws {
        let disk = try CaptureTestDisk()
        defer { disk.remove() }
        let files = try ScreenRecordingCaptureFiles(directory: disk.url)
        let assets = CaptureTestAssets()
        let writer = ScreenRecordingCaptureWriter(files: files, configuration: .init(systemAudio: false), width: 16, height: 16,
                                                  onFailure: { _ in }, factory: assets.make)
        let invalid = try syntheticVideo(time: 100, kind: .screen)
        writer.receive(.init(buffer: invalid.buffer, kind: .screen, hostTime: .nan))
        await writer.flush()
        CMSampleBufferInvalidate(invalid.buffer)
        writer.receive(invalid)
        await writer.flush()
        writer.receive(try syntheticVideo(time: 101, kind: .screen))
        writer.receive(try syntheticVideo(time: 101.1, kind: .camera))
        writer.receive(try syntheticAudio(time: 101.1, kind: .microphone))
        writer.receive(try syntheticAudio(time: 101.1, kind: .systemAudio))
        await writer.seal(at: 102)
        #expect(try await writer.waitForFirstFrame() == 101)
        #expect(try await writer.finish() == 1)
        #expect(assets.times(.screen) == [0])
        #expect(assets.times(.camera).isEmpty)
        #expect(assets.times(.microphone).isEmpty)
        #expect(assets.times(.systemAudio).isEmpty)
        #expect(files.discard() == nil)
    }

    @Test
    func enabledMicrophoneWithoutSamplesCannotProduceASuccessfulRecording() async throws {
        let disk = try CaptureTestDisk()
        defer { disk.remove() }
        let files = try ScreenRecordingCaptureFiles(directory: disk.url)
        let assets = CaptureTestAssets()
        let writer = ScreenRecordingCaptureWriter(files: files, configuration: .init(systemAudio: false, microphone: true),
                                                  width: 16, height: 16, onFailure: { _ in }, factory: assets.make)
        writer.receive(try syntheticVideo(time: 100, kind: .screen))
        await writer.seal(at: 101)
        await #expect(throws: ScreenRecordingCaptureError.noMicrophoneSamples) { try await writer.finish() }
        await writer.cancel()
        #expect(assets.released)
        #expect(files.discard() == nil)
    }

    @Test
    func boundedPreEpochBufferKeepsOnlyTheLatestSixteenSamples() async throws {
        let disk = try CaptureTestDisk()
        defer { disk.remove() }
        let files = try ScreenRecordingCaptureFiles(directory: disk.url)
        let assets = CaptureTestAssets()
        let writer = ScreenRecordingCaptureWriter(files: files, configuration: .init(systemAudio: false, camera: true),
                                                  width: 16, height: 16, onFailure: { _ in }, factory: assets.make)
        for index in 1...64 {
            writer.receive(try syntheticVideo(time: 100 + Double(index) / 100, kind: .camera))
            await writer.flush()
        }
        writer.receive(try syntheticVideo(time: 100, kind: .screen))
        await writer.seal(at: 101)
        #expect(try await writer.finish() == 1)
        let values = assets.times(.camera)
        #expect(values.count == 16)
        #expect(abs((values.first ?? 0) - 0.49) < 0.000_002)
        #expect(files.discard() == nil)
    }

    @Test
    func ingressStaysBoundedWhileTheAssetWriterIsBlocked() async throws {
        let disk = try CaptureTestDisk()
        defer { disk.remove() }
        let files = try ScreenRecordingCaptureFiles(directory: disk.url)
        let assets = CaptureTestAssets()
        let entered = ScreenRecordingCaptureStartGate()
        let release = DispatchSemaphore(value: 0)
        assets.appendBlock = (entered, release)
        let writer = ScreenRecordingCaptureWriter(files: files, configuration: .init(systemAudio: false),
                                                  width: 16, height: 16, onFailure: { _ in }, factory: assets.make)
        writer.receive(try syntheticVideo(time: 100, kind: .screen))
        _ = try await entered.wait(timeout: 2)
        let frame = try syntheticVideo(time: 101, kind: .screen)
        for index in 1...256 {
            writer.receive(.init(buffer: frame.buffer, kind: .screen, hostTime: 100 + Double(index) / 30))
        }
        release.signal()
        await writer.seal(at: 110)
        #expect(try await writer.finish() == 10)
        #expect(assets.times(.screen).count <= 33)
        #expect(assets.times(.screen).count > 1)
        #expect(files.discard() == nil)
    }

    @Test
    func saturatedVideoIngressKeepsEverySystemAndMicrophonePacket() async throws {
        let disk = try CaptureTestDisk()
        defer { disk.remove() }
        let files = try ScreenRecordingCaptureFiles(directory: disk.url)
        let assets = CaptureTestAssets()
        let entered = ScreenRecordingCaptureStartGate()
        let release = DispatchSemaphore(value: 0)
        assets.appendBlock = (entered, release)
        let writer = ScreenRecordingCaptureWriter(files: files, configuration: .init(systemAudio: true, microphone: true),
                                                  width: 16, height: 16, onFailure: { _ in }, factory: assets.make)
        writer.receive(try syntheticVideo(time: 100, kind: .screen))
        _ = try await entered.wait(timeout: 2)
        let frame = try syntheticVideo(time: 101, kind: .screen)
        let system = try syntheticAudio(time: 100, kind: .systemAudio)
        let microphone = try syntheticAudio(time: 100, kind: .microphone)
        for index in 0..<100 {
            let time = 100 + Double(index) / 64
            writer.receive(.init(buffer: frame.buffer, kind: .screen, hostTime: time + 0.001))
            writer.receive(.init(buffer: system.buffer, kind: .systemAudio, hostTime: time))
            writer.receive(.init(buffer: microphone.buffer, kind: .microphone, hostTime: time))
        }
        release.signal()
        await writer.seal(at: 102)
        #expect(try await writer.finish() == 2)
        let expected = (0..<100).map { Double($0) / 64 }
        #expect(assets.times(.systemAudio) == expected, "Video saturation must preserve all system audio timestamps")
        #expect(assets.times(.microphone) == expected, "Video saturation must preserve all microphone timestamps")
        #expect(assets.times(.screen).count <= 33)
        #expect(files.discard() == nil)
    }

    @Test
    func ingressAndPreEpochAudioShareOneBoundedReservation() async throws {
        let disk = try CaptureTestDisk()
        defer { disk.remove() }
        let files = try ScreenRecordingCaptureFiles(directory: disk.url)
        let assets = CaptureTestAssets()
        let failure = ScreenRecordingCaptureStartGate()
        let writer = ScreenRecordingCaptureWriter(files: files, configuration: .init(systemAudio: true, microphone: true),
                                                  width: 16, height: 16, onFailure: { failure.resolve(.failure($0)) }, factory: assets.make)
        let packet = try syntheticAudio(time: 100, kind: .microphone)
        for index in 0..<ScreenRecordingCaptureAudioBacklog.sampleLimit {
            writer.receive(.init(buffer: packet.buffer, kind: .microphone, hostTime: 100 + Double(index) / 100))
            await writer.flush()
        }
        writer.receive(.init(buffer: packet.buffer, kind: .systemAudio, hostTime: 110))
        await writer.flush()
        await #expect(throws: ScreenRecordingCaptureError.writerUnavailable) { try await failure.wait(timeout: 2) }
        writer.receive(try syntheticVideo(time: 100, kind: .screen))
        await writer.seal(at: 110)
        await #expect(throws: ScreenRecordingCaptureError.writerUnavailable) { try await writer.finish() }
        #expect(assets.times(.microphone).isEmpty)
        #expect(assets.times(.systemAudio).isEmpty)
        #expect(files.discard() == nil)
    }

    @Test
    func preEpochAudioByteBudgetIncludesAllRetainedPayload() async throws {
        let disk = try CaptureTestDisk()
        defer { disk.remove() }
        let files = try ScreenRecordingCaptureFiles(directory: disk.url)
        let assets = CaptureTestAssets()
        let failures = ScreenRecordingCaptureStartGate()
        let writer = ScreenRecordingCaptureWriter(files: files, configuration: .init(systemAudio: false, microphone: true),
                                                  width: 16, height: 16, onFailure: { failures.resolve(.failure($0)) }, factory: assets.make)
        let packet = try syntheticAudio(time: 100, kind: .microphone)
        var block: CMBlockBuffer?
        let length = ScreenRecordingCaptureAudioBacklog.byteLimit
        #expect(CMBlockBufferCreateWithMemoryBlock(allocator: kCFAllocatorDefault, memoryBlock: nil, blockLength: length,
                                                  blockAllocator: kCFAllocatorDefault, customBlockSource: nil,
                                                  offsetToData: 0, dataLength: length, flags: 0, blockBufferOut: &block) == noErr)
        var timing = CMSampleTimingInfo(duration: CMTime(value: 1, timescale: 48_000),
                                        presentationTimeStamp: CMTime(value: 100, timescale: 1), decodeTimeStamp: .invalid)
        var size = 2
        var sample: CMSampleBuffer?
        #expect(CMSampleBufferCreateReady(allocator: kCFAllocatorDefault, dataBuffer: try #require(block),
                                          formatDescription: packet.buffer.formatDescription, sampleCount: 480,
                                          sampleTimingEntryCount: 1, sampleTimingArray: &timing,
                                          sampleSizeEntryCount: 1, sampleSizeArray: &size, sampleBufferOut: &sample) == noErr)
        writer.receive(.init(buffer: try #require(sample), kind: .microphone, hostTime: 100))
        await writer.flush()
        writer.receive(try syntheticAudio(time: 100.01, kind: .microphone))
        await writer.flush()
        await #expect(throws: ScreenRecordingCaptureError.writerUnavailable) { try await failures.wait(timeout: 2) }
        await writer.seal(at: 101)
        await #expect(throws: ScreenRecordingCaptureError.writerUnavailable) { try await writer.finish() }
        #expect(files.discard() == nil)
    }

    @Test
    func preEpochAudioIsNotEvictedByTheCameraRingBuffer() async throws {
        let disk = try CaptureTestDisk()
        defer { disk.remove() }
        let files = try ScreenRecordingCaptureFiles(directory: disk.url)
        let assets = CaptureTestAssets()
        let writer = ScreenRecordingCaptureWriter(files: files, configuration: .init(systemAudio: true, microphone: true, camera: true),
                                                  width: 16, height: 16, onFailure: { _ in }, factory: assets.make)
        for index in 0..<32 {
            let time = 100 + Double(index) / 64
            writer.receive(try syntheticAudio(time: time, kind: .systemAudio))
            writer.receive(try syntheticAudio(time: time, kind: .microphone))
            writer.receive(try syntheticVideo(time: time, kind: .camera))
            await writer.flush()
        }
        writer.receive(try syntheticVideo(time: 100, kind: .screen))
        await writer.seal(at: 101)
        #expect(try await writer.finish() == 1)
        let expected = (0..<32).map { Double($0) / 64 }
        #expect(assets.times(.systemAudio) == expected)
        #expect(assets.times(.microphone) == expected)
        #expect(assets.times(.camera).count == 16)
        #expect(files.discard() == nil)
    }

    @Test(arguments: [ScreenRecordingSampleKind.systemAudio, .microphone])
    func rejectedAudioCannotSilentlyPublishAMissingPacket(kind: ScreenRecordingSampleKind) async throws {
        let disk = try CaptureTestDisk()
        defer { disk.remove() }
        let files = try ScreenRecordingCaptureFiles(directory: disk.url)
        let assets = CaptureTestAssets()
        let failures = ScreenRecordingCaptureStartGate()
        let writer = ScreenRecordingCaptureWriter(files: files, configuration: .init(systemAudio: true, microphone: true),
                                                  width: 16, height: 16, onFailure: { failures.resolve(.failure($0)) }, factory: assets.make)
        writer.receive(try syntheticVideo(time: 100, kind: .screen))
        await writer.flush()
        assets.ready = false
        writer.receive(try syntheticAudio(time: 100, kind: kind))
        await writer.flush()
        await #expect(throws: ScreenRecordingCaptureError.writerUnavailable) { try await failures.wait(timeout: 2) }
        await writer.seal(at: 101)
        await #expect(throws: ScreenRecordingCaptureError.writerUnavailable) { try await writer.finish() }
        #expect(assets.released)
        #expect(assets.times(kind).isEmpty)
        #expect(files.discard() == nil)
    }

    @Test
    func nativeStopReleasesVideoInterleavingBeforeDrainingAcceptedAudio() async throws {
        let disk = try CaptureTestDisk()
        defer { disk.remove() }
        let files = try ScreenRecordingCaptureFiles(directory: disk.url)
        let readiness = CaptureTestNativeReadiness()
        let writer = try await readiness.makeWriter(files: files, firstSample: syntheticVideo(time: 0, kind: .screen))
        try await readiness.append(syntheticVideo(time: 0, kind: .screen), to: writer)
        for index in 0..<3 {
            try await readiness.append(syntheticAudio(time: Double(index) / 100, kind: .systemAudio), to: writer)
        }
        try await readiness.finish(writer, at: 1.0 / 30)
        try files.publish([files.screenName])
        let asset = AVURLAsset(url: disk.url.appendingPathComponent(files.screenName))
        let track = try #require(try await asset.loadTracks(withMediaType: .audio).first)
        #expect(readiness.marked == [.screen, .systemAudio])
        let reader = try AVAssetReader(asset: asset)
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: [AVFormatIDKey: kAudioFormatLinearPCM,
                                                                           AVLinearPCMIsFloatKey: true,
                                                                           AVLinearPCMBitDepthKey: 32,
                                                                           AVLinearPCMIsNonInterleaved: false])
        reader.add(output)
        #expect(reader.startReading())
        var frames = 0
        while let sample = output.copyNextSampleBuffer() { frames += sample.numSamples }
        #expect(reader.status == .completed)
        #expect(frames >= 1_440, "All three accepted 480-frame packets must survive the stop-time interleaving drain: \(frames)")
    }

    @Test
    func nativeReadinessEventReleasesAFullAudioQueueBeforeAnotherPacketArrives() async throws {
        let disk = try CaptureTestDisk()
        defer { disk.remove() }
        let files = try ScreenRecordingCaptureFiles(directory: disk.url)
        let readiness = CaptureTestNativeReadiness()
        readiness.waitsForVideoFinish = false
        readiness.audioReady = false
        let writer = try await readiness.makeWriter(files: files, firstSample: syntheticVideo(time: 0, kind: .screen))
        try await readiness.append(syntheticVideo(time: 0, kind: .screen), to: writer)
        for index in 0..<ScreenRecordingCaptureAudioBacklog.sampleLimit {
            try await readiness.append(syntheticAudio(time: Double(index) / 100, kind: .systemAudio), to: writer)
        }
        try await readiness.resumeAudioOnReadinessEvent()
        try await readiness.append(syntheticAudio(time: 5.12, kind: .systemAudio), to: writer)
        try await readiness.finish(writer, at: 5.13)
        try files.publish([files.screenName])
        let asset = AVURLAsset(url: disk.url.appendingPathComponent(files.screenName))
        #expect(try await asset.loadTracks(withMediaType: .audio).count == 1)
        #expect(abs(try await asset.load(.duration).seconds - 5.13) < 0.05)
    }

    @Test
    func nativeAudioTimeoutRetainsItsOriginalErrorAndReleasesTheWriter() async throws {
        let disk = try CaptureTestDisk()
        defer { disk.remove() }
        let files = try ScreenRecordingCaptureFiles(directory: disk.url)
        let readiness = CaptureTestNativeReadiness()
        readiness.waitsForVideoFinish = false
        readiness.audioReady = false
        let writer = try await readiness.makeWriter(files: files, firstSample: syntheticVideo(time: 0, kind: .screen), timeout: 0)
        try await readiness.append(syntheticVideo(time: 0, kind: .screen), to: writer)
        try await readiness.append(syntheticAudio(time: 0, kind: .systemAudio), to: writer)
        await #expect(throws: ScreenRecordingCaptureError.saveFailed(AppLocalization.text("录屏文件写入超时"))) {
            try await readiness.failure.wait(timeout: 2)
        }
        await #expect(throws: ScreenRecordingCaptureError.writerUnavailable) {
            try await readiness.append(syntheticAudio(time: 0.01, kind: .systemAudio), to: writer)
        }
        await readiness.cancel(writer)
        #expect(!FileManager.default.fileExists(atPath: files.url(for: files.screenName).path))
        #expect(files.discard() == nil)
    }

    @Test
    func cancellationDuringNativeAudioDrainPreventsLaterWrites() async throws {
        let disk = try CaptureTestDisk()
        defer { disk.remove() }
        let files = try ScreenRecordingCaptureFiles(directory: disk.url)
        let readiness = CaptureTestNativeReadiness()
        readiness.waitsForVideoFinish = false
        readiness.audioReady = false
        let native = try await readiness.makeWriter(files: files, firstSample: syntheticVideo(time: 0, kind: .screen))
        try await readiness.append(syntheticVideo(time: 0, kind: .screen), to: native)
        try await readiness.append(syntheticAudio(time: 0, kind: .systemAudio), to: native)
        await readiness.beginFinish(native, at: 1.0 / 30)
        await readiness.cancel(native)
        await #expect(throws: ScreenRecordingCaptureError.writerUnavailable) {
            try await readiness.append(syntheticAudio(time: 0.01, kind: .systemAudio), to: native)
        }
        #expect(!FileManager.default.fileExists(atPath: files.url(for: files.screenName).path))
        #expect(files.discard() == nil)
    }

    @Test
    func cancellationInsideNativeAudioDrainDoesNotFinishRemainingInputs() async throws {
        let disk = try CaptureTestDisk()
        defer { disk.remove() }
        let files = try ScreenRecordingCaptureFiles(directory: disk.url)
        let readiness = CaptureTestNativeReadiness()
        readiness.waitsForVideoFinish = false
        readiness.audioReady = false
        let writer = try await readiness.makeWriter(files: files, firstSample: syntheticVideo(time: 0, kind: .screen))
        try await readiness.append(syntheticVideo(time: 0, kind: .screen), to: writer)
        try await readiness.append(syntheticAudio(time: 0, kind: .systemAudio), to: writer)
        await readiness.cancelDuringNextDrain(writer, at: 1.0 / 30)
        #expect(readiness.marked.isEmpty, "Cancellation while draining must not mark the remaining video input as finished")
        await #expect(throws: ScreenRecordingCaptureError.writerUnavailable) {
            try await readiness.append(syntheticAudio(time: 0.01, kind: .systemAudio), to: writer)
        }
        #expect(!FileManager.default.fileExists(atPath: files.url(for: files.screenName).path))
        #expect(files.discard() == nil)
    }

    @Test
    func cancellingAWriterUnblocksEveryConcurrentFinishAndKeepsLateCallbacksIgnored() async throws {
        let disk = try CaptureTestDisk()
        defer { disk.remove() }
        let files = try ScreenRecordingCaptureFiles(directory: disk.url)
        let assets = CaptureTestAssets()
        assets.finishHeld = true
        let entered = ScreenRecordingCaptureStartGate()
        assets.finishEntered = entered
        let writer = ScreenRecordingCaptureWriter(files: files, configuration: .init(systemAudio: false), width: 16, height: 16,
                                                  onFailure: { _ in }, factory: assets.make)
        writer.receive(try syntheticVideo(time: 100, kind: .screen))
        await writer.seal(at: 101)
        let first = Task { try await writer.finish() }
        _ = try await entered.wait(timeout: 2)
        let second = Task { try await writer.finish() }
        await writer.cancel()
        await #expect(throws: CancellationError.self) { try await first.value }
        await #expect(throws: CancellationError.self) { try await second.value }
        assets.releaseFinishes(.success(()))
        await writer.cancel()
        writer.receive(try syntheticVideo(time: 101, kind: .screen))
        await writer.flush()
        #expect(assets.times(.screen) == [0])
        #expect(assets.released)
        #expect(files.discard() == nil)
    }

    @Test
    func concurrentWriterFinishesReturnOneResultWithoutFinishingAssetsTwice() async throws {
        let disk = try CaptureTestDisk()
        defer { disk.remove() }
        let files = try ScreenRecordingCaptureFiles(directory: disk.url)
        let assets = CaptureTestAssets()
        assets.finishHeld = true
        let entered = ScreenRecordingCaptureStartGate()
        assets.finishEntered = entered
        let writer = ScreenRecordingCaptureWriter(files: files, configuration: .init(systemAudio: false), width: 16, height: 16,
                                                  onFailure: { _ in }, factory: assets.make)
        writer.receive(try syntheticVideo(time: 100, kind: .screen))
        await writer.seal(at: 101)
        let first = Task { try await writer.finish() }
        _ = try await entered.wait(timeout: 2)
        let second = Task { try await writer.finish() }
        await writer.flush()
        assets.releaseFinishes(.success(()))
        #expect(try await first.value == 1)
        #expect(try await second.value == 1)
        #expect(try await writer.finish() == 1)
        #expect(assets.finishTimes == [1])
        #expect(files.discard() == nil)
    }

    @Test
    func fileCleanupFailureIsVisibleAndCanBeRetriedWithoutTouchingExistingData() throws {
        let disk = try CaptureTestDisk()
        defer { disk.remove() }
        let existing = disk.url.appendingPathComponent("existing.txt")
        try Data("keep".utf8).write(to: existing)
        var operations = ScreenRecordingCaptureFileOperations.live
        let remove = operations.remove
        var denied = true
        operations.remove = { url in
            if denied { throw CaptureTestError.diskFull }
            try remove(url)
        }
        let files = try ScreenRecordingCaptureFiles(directory: disk.url, operations: operations)
        #expect(files.discard() != nil)
        #expect(FileManager.default.fileExists(atPath: files.staging.path))
        denied = false
        #expect(files.discard() == nil)
        #expect(try FileManager.default.contentsOfDirectory(atPath: disk.url.path) == ["existing.txt"])
        #expect(try Data(contentsOf: existing) == Data("keep".utf8))
    }

    @Test
    func silenceFromEnabledSystemAudioStillProducesAReadableScreenVideo() async throws {
        for enabled in [false, true] {
            for extraFrames in [0, 5] {
                let disk = try CaptureTestDisk()
                defer { disk.remove() }
                let files = try ScreenRecordingCaptureFiles(directory: disk.url)
                let writer = ScreenRecordingCaptureWriter(files: files, configuration: .init(systemAudio: enabled), width: 16, height: 16,
                                                          onFailure: { _ in })
                writer.receive(try syntheticVideo(time: 100, kind: .screen))
                await writer.flush()
                if extraFrames > 0 {
                    for frame in 1...extraFrames {
                        writer.receive(try syntheticVideo(time: 100 + Double(frame) / 30, kind: .screen))
                        await writer.flush()
                    }
                }
                await writer.seal(at: 101)
                #expect(try await writer.finish() == 1)
                try files.publish([files.screenName])
                let asset = AVURLAsset(url: disk.url.appendingPathComponent(files.screenName))
                #expect(try await asset.loadTracks(withMediaType: .video).count == 1)
                let savedDuration = try await asset.load(.duration).seconds
                #expect(abs(savedDuration - 1) < 0.05, "systemAudio=\(enabled) extraFrames=\(extraFrames) saved=\(savedDuration)")
            }
        }
    }

    private func syntheticVideo(time: Double, kind: ScreenRecordingSampleKind,
                                duration: CMTime = CMTime(value: 1, timescale: 30)) throws -> ScreenRecordingCaptureSample {
        var pixel: CVPixelBuffer?
        let status = CVPixelBufferCreate(kCFAllocatorDefault, 16, 16, kCVPixelFormatType_32BGRA,
                                         [kCVPixelBufferIOSurfacePropertiesKey: [:]] as CFDictionary, &pixel)
        #expect(status == kCVReturnSuccess)
        let buffer = try #require(pixel)
        CVPixelBufferLockBaseAddress(buffer, [])
        if let base = CVPixelBufferGetBaseAddress(buffer) {
            memset(base, 127, CVPixelBufferGetBytesPerRow(buffer) * 16)
        }
        CVPixelBufferUnlockBaseAddress(buffer, [])
        var format: CMVideoFormatDescription?
        #expect(CMVideoFormatDescriptionCreateForImageBuffer(allocator: kCFAllocatorDefault, imageBuffer: buffer,
                                                            formatDescriptionOut: &format) == noErr)
        var timing = CMSampleTimingInfo(duration: duration,
                                        presentationTimeStamp: CMTime(seconds: time, preferredTimescale: 1_000_000), decodeTimeStamp: .invalid)
        var sample: CMSampleBuffer?
        #expect(CMSampleBufferCreateReadyWithImageBuffer(allocator: kCFAllocatorDefault, imageBuffer: buffer,
                                                        formatDescription: try #require(format), sampleTiming: &timing,
                                                        sampleBufferOut: &sample) == noErr)
        return ScreenRecordingCaptureSample(buffer: try #require(sample), kind: kind, hostTime: time)
    }

    private func syntheticAudio(time: Double, kind: ScreenRecordingSampleKind) throws -> ScreenRecordingCaptureSample {
        var description = AudioStreamBasicDescription(mSampleRate: 48_000, mFormatID: kAudioFormatLinearPCM,
                                                      mFormatFlags: kAudioFormatFlagIsSignedInteger | kAudioFormatFlagIsPacked,
                                                      mBytesPerPacket: 2, mFramesPerPacket: 1, mBytesPerFrame: 2,
                                                      mChannelsPerFrame: 1, mBitsPerChannel: 16, mReserved: 0)
        var format: CMAudioFormatDescription?
        #expect(CMAudioFormatDescriptionCreate(allocator: kCFAllocatorDefault, asbd: &description, layoutSize: 0,
                                              layout: nil, magicCookieSize: 0, magicCookie: nil,
                                              extensions: nil, formatDescriptionOut: &format) == noErr)
        var block: CMBlockBuffer?
        #expect(CMBlockBufferCreateWithMemoryBlock(allocator: kCFAllocatorDefault, memoryBlock: nil, blockLength: 960,
                                                   blockAllocator: kCFAllocatorDefault, customBlockSource: nil,
                                                   offsetToData: 0, dataLength: 960, flags: 0, blockBufferOut: &block) == noErr)
        let data = try #require(block)
        #expect(CMBlockBufferFillDataBytes(with: 0, blockBuffer: data, offsetIntoDestination: 0, dataLength: 960) == noErr)
        var timing = CMSampleTimingInfo(duration: CMTime(value: 1, timescale: 48_000),
                                        presentationTimeStamp: CMTime(seconds: time, preferredTimescale: 1_000_000), decodeTimeStamp: .invalid)
        var sampleSize = 2
        var sample: CMSampleBuffer?
        #expect(CMSampleBufferCreateReady(allocator: kCFAllocatorDefault, dataBuffer: data, formatDescription: format,
                                          sampleCount: 480, sampleTimingEntryCount: 1, sampleTimingArray: &timing,
                                          sampleSizeEntryCount: 1, sampleSizeArray: &sampleSize, sampleBufferOut: &sample) == noErr)
        return ScreenRecordingCaptureSample(buffer: try #require(sample), kind: kind, hostTime: time)
    }
}

private enum CaptureTestError: Error, Equatable { case diskFull, unavailable }

@MainActor
private final class CaptureTestSystem {
    let directory = URL(fileURLWithPath: "/synthetic-recording-directory", isDirectory: true)
    var session = CaptureTestSession()
    var permissions: [ScreenRecordingPermission] = []
    var denied: ScreenRecordingPermission?
    var now: Double = 100
    var tick: (@MainActor () -> Void)?

    func dependencies() -> ScreenRecordingCaptureDependencies {
        ScreenRecordingCaptureDependencies(
            loadSources: { [.init(id: 1, name: "Synthetic", mode: .display, frame: .init(x: 0, y: 0, width: 1920, height: 1080))] },
            loadDevices: { .init(cameras: [.init(id: "synthetic-camera", name: "Camera")],
                                 microphones: [.init(id: "synthetic-mic", name: "Microphone")]) },
            requestPermission: { [self] permission in permissions.append(permission); return denied != permission },
            makeSession: { [self] _, _, _ in session },
            makeCameraPreview: { _, _ in CaptureTestCameraPreview() },
            now: { [self] in now },
            scheduleTick: { [self] callback in tick = callback; return { [self] in tick = nil } }
        )
    }
}

@MainActor
private final class CaptureTestSession: ScreenRecordingCaptureSession {
    let startEntered = CaptureTestSignal()
    let stopEntered = CaptureTestSignal()
    let firstFrame = CaptureTestLatch<Double>()
    let finish = CaptureTestLatch<ScreenRecordingResult>()
    var result = ScreenRecordingResult(videoFile: "synthetic.mp4", duration: 2, width: 16, height: 16)
    var started = false
    var released = false
    var finishHeld = false
    var finishError: CaptureTestError?
    var returnsResultAfterCancellation = false
    var cancelError: CaptureTestError?
    var pauseEvents: [(paused: Bool, time: Double)] = []

    func useCameraPreview(_ preview: any ScreenRecordingCameraPreviewSession) {}

    func start() async throws -> Double {
        started = true
        startEntered.signal()
        return try await firstFrame.wait()
    }
    func setPaused(_ paused: Bool, atHostTime time: Double) async { pauseEvents.append((paused, time)) }
    func stop(atHostTime time: Double) async throws -> ScreenRecordingResult {
        stopEntered.signal()
        if let finishError { throw finishError }
        return finishHeld ? try await finish.wait() : result
    }
    func cancel() async -> Error? {
        released = true
        firstFrame.resolve(.failure(CancellationError()))
        finish.resolve(returnsResultAfterCancellation ? .success(result) : .failure(CancellationError()))
        return cancelError
    }
}

@MainActor
private final class CaptureTestCameraPreview: ScreenRecordingCameraPreviewSession {
    let previewSession = AVCaptureSession()
    func start() async throws {}
    func attach(to bridge: ScreenRecordingCaptureBridge) {}
    func stop() async {}
}

@MainActor
private final class CaptureTestSignal {
    private var fired = false
    private var waiters: [CheckedContinuation<Void, Never>] = []
    func signal() { fired = true; let waiters = waiters; self.waiters.removeAll(); waiters.forEach { $0.resume() } }
    func wait() async { if !fired { await withCheckedContinuation { waiters.append($0) } } }
}

@MainActor
private final class CaptureTestLatch<Value: Sendable> {
    private var result: Result<Value, Error>?
    private var waiters: [CheckedContinuation<Value, Error>] = []
    func resolve(_ result: Result<Value, Error>) {
        guard self.result == nil else { return }
        self.result = result
        let waiters = waiters
        self.waiters.removeAll()
        for waiter in waiters { waiter.resume(with: result) }
    }
    func wait() async throws -> Value {
        if let result { return try result.get() }
        return try await withCheckedThrowingContinuation { waiters.append($0) }
    }
}

private final class CaptureTestDisk {
    let url: URL
    init() throws {
        url = FileManager.default.temporaryDirectory.appendingPathComponent("zisla-capture-test-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
    }
    func remove() {
        do { try FileManager.default.removeItem(at: url) }
        catch { Issue.record("合成录屏测试目录未清理：\(error)") }
    }
}

private final class CaptureTestErrors: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [CaptureTestError] = []
    var values: [CaptureTestError] { lock.lock(); defer { lock.unlock() }; return storage }
    func append(_ error: Error) { lock.lock(); defer { lock.unlock() }; if let error = error as? CaptureTestError { storage.append(error) } }
}

private final class CaptureTestAssets: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [ScreenRecordingSampleKind: [Double]] = [:]
    private var finishes: [Double] = []
    private var finishCallbacks: [@Sendable (Result<Void, Error>) -> Void] = []
    private var cancelled = false
    var appendError: CaptureTestError?
    var finishError: CaptureTestError?
    var finishHeld = false
    var finishEntered: ScreenRecordingCaptureStartGate?
    var ready = true
    var appendBlock: (ScreenRecordingCaptureStartGate, DispatchSemaphore)?

    var finishTimes: [Double] { lock.lock(); defer { lock.unlock() }; return finishes }
    var released: Bool { lock.lock(); defer { lock.unlock() }; return cancelled }
    func times(_ kind: ScreenRecordingSampleKind) -> [Double] { lock.lock(); defer { lock.unlock() }; return storage[kind] ?? [] }
    func make(_ url: URL, _ kind: ScreenRecordingSampleKind, _ sample: CMSampleBuffer) throws -> any ScreenRecordingCaptureAssetWriter {
        CaptureTestAssetWriter(assets: self)
    }
    func append(_ sample: CMSampleBuffer, kind: ScreenRecordingSampleKind) throws -> Bool {
        lock.lock()
        defer { lock.unlock() }
        if let appendBlock {
            self.appendBlock = nil
            appendBlock.0.resolve(.success(0))
            appendBlock.1.wait()
        }
        if let appendError { throw appendError }
        guard ready else { return false }
        storage[kind, default: []].append(CMSampleBufferGetPresentationTimeStamp(sample).seconds)
        return true
    }
    func finish(at time: Double) -> Result<Void, Error> {
        lock.lock()
        defer { lock.unlock() }
        finishes.append(time)
        return finishError.map { .failure($0) } ?? .success(())
    }
    func finish(at time: Double, completion: @escaping @Sendable (Result<Void, Error>) -> Void) {
        if finishHeld {
            lock.lock()
            finishes.append(time)
            finishCallbacks.append(completion)
            lock.unlock()
        } else { completion(finish(at: time)) }
        finishEntered?.resolve(.success(time))
    }
    func releaseFinishes(_ result: Result<Void, Error>) {
        lock.lock()
        let callbacks = finishCallbacks
        finishCallbacks.removeAll()
        lock.unlock()
        for callback in callbacks { callback(result) }
    }
    func cancel() { lock.lock(); cancelled = true; lock.unlock() }
}

private final class CaptureTestAssetWriter: ScreenRecordingCaptureAssetWriter {
    private let assets: CaptureTestAssets
    init(assets: CaptureTestAssets) { self.assets = assets }
    func append(_ sample: CMSampleBuffer, kind: ScreenRecordingSampleKind) throws -> Bool { try assets.append(sample, kind: kind) }
    func finish(at time: Double, completion: @escaping @Sendable (Result<Void, Error>) -> Void) {
        assets.finish(at: time, completion: completion)
    }
    func cancel() { assets.cancel() }
}

private final class CaptureTestNativeReadiness: @unchecked Sendable {
    let queue = DispatchQueue(label: "dev.wzz.zisla.tests.capture-readiness")
    private let lock = NSLock()
    private var finished: [ScreenRecordingSampleKind] = []
    var waitsForVideoFinish = true
    var audioReady = true
    var onAudioReady: (() -> Void)?
    weak var audioInput: AVAssetWriterInput?
    let failure = ScreenRecordingCaptureStartGate()
    var marked: [ScreenRecordingSampleKind] { lock.lock(); defer { lock.unlock() }; return finished }

    func ready(_ kind: ScreenRecordingSampleKind, _ input: AVAssetWriterInput) -> Bool {
        lock.lock()
        if kind.isAudio { audioInput = input }
        let unblocked = !kind.isAudio || audioReady && (!waitsForVideoFinish || finished.contains(.screen))
        lock.unlock()
        if kind.isAudio, unblocked, let onAudioReady {
            self.onAudioReady = nil
            onAudioReady()
            return true
        }
        return unblocked && input.isReadyForMoreMediaData
    }

    func markFinished(_ kind: ScreenRecordingSampleKind, _ input: AVAssetWriterInput) {
        input.markAsFinished()
        lock.lock()
        finished.append(kind)
        lock.unlock()
    }

    func makeWriter(files: ScreenRecordingCaptureFiles, firstSample: ScreenRecordingCaptureSample,
                    timeout: Double = 2) async throws -> ScreenRecordingNativeAssetWriter {
        try await withCheckedThrowingContinuation { continuation in
            queue.async {
                do {
                    let native = try ScreenRecordingNativeAssetWriter(url: files.url(for: files.screenName), kind: .screen,
                                                                       firstSample: firstSample.buffer, width: 16, height: 16,
                                                                       systemAudio: true, frameRate: 30, finishQueue: self.queue,
                                                                       finishTimeout: timeout, onFailure: { self.failure.resolve(.failure($0)) },
                                                                       ready: self.ready, markFinished: self.markFinished)
                    continuation.resume(returning: native)
                } catch { continuation.resume(throwing: error) }
            }
        }
    }

    func append(_ sample: ScreenRecordingCaptureSample, to writer: ScreenRecordingNativeAssetWriter) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            queue.async {
                do {
                    guard try writer.append(sample.buffer, kind: sample.kind) else { throw ScreenRecordingCaptureError.writerUnavailable }
                    continuation.resume()
                } catch { continuation.resume(throwing: error) }
            }
        }
    }

    func finish(_ writer: ScreenRecordingNativeAssetWriter, at time: Double) async throws {
        let result = ScreenRecordingCaptureStartGate()
        queue.async { writer.finish(at: time) { result.resolve($0.map { 0 }) } }
        _ = try await result.wait(timeout: 2)
    }

    func resumeAudioOnReadinessEvent() async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            queue.async {
                do {
                    let input = try #require(self.audioInput)
                    // Emit the SDK's readiness notification without creating real disk or CPU contention.
                    input.willChangeValue(forKey: "readyForMoreMediaData")
                    self.audioReady = true
                    input.didChangeValue(forKey: "readyForMoreMediaData")
                    continuation.resume()
                } catch { continuation.resume(throwing: error) }
            }
        }
    }

    func cancelDuringNextDrain(_ writer: ScreenRecordingNativeAssetWriter, at time: Double) async {
        await withCheckedContinuation { continuation in
            queue.async {
                self.audioReady = true
                self.onAudioReady = { writer.cancel() }
                writer.finish(at: time) { _ in Issue.record("Cancelled native finish must not produce a late result") }
                continuation.resume()
            }
        }
    }

    func beginFinish(_ writer: ScreenRecordingNativeAssetWriter, at time: Double) async {
        await withCheckedContinuation { continuation in
            queue.async {
                writer.finish(at: time) { _ in }
                continuation.resume()
            }
        }
    }

    func cancel(_ writer: ScreenRecordingNativeAssetWriter) async {
        await withCheckedContinuation { continuation in queue.async { writer.cancel(); continuation.resume() } }
    }
}
