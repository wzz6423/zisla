import AppKit
import CoreAudio
import Foundation
import Testing
import ZislaCore

@testable import ZislaKit

@MainActor
struct CoreAudioApplicationVolumeBackendTests {
    @Test(arguments: [Float(0), 0.25])
    func aHiddenCandidateReportsControlFailureAndCanRetryItsSavedGain(gain: Float) {
        let fixture = ApplicationVolumeBackendFixture()
        let defaults = ApplicationVolumePlaybackDefaultsFixture()
        defaults.store.set(["music": ["volume": gain == 0 ? 0.35 : Double(gain), "isMuted": gain == 0]],
                           forKey: ApplicationVolumeMixerService.preferencesKey)
        let service = Self.service(fixture, sources: [Self.source("music", pids: [101])], defaults: defaults.store)
        defer { service.stop(); fixture.flush() }
        service.start()
        fixture.flush()
        #expect(service.applications.isEmpty)
        #expect(service.errorMessage == nil)
        let silence = ApplicationVolumeBufferFixture(channels: [2], samples: [[0, 0]])
        let output = ApplicationVolumeBufferFixture(channels: [2], samples: [[9, 9]])
        fixture.hardware.emit(input: silence, output: output)
        fixture.watchdog.fire(at: fixture.watchdog.entries.count - 1)
        fixture.flush()
        fixture.clock.time = 3

        fixture.watchdog.fire(at: fixture.watchdog.entries.count - 1)
        fixture.flush()
        fixture.checkPlayback()

        #expect(service.applications.isEmpty)
        #expect(fixture.hardware.liveIO.isEmpty)
        #expect(fixture.playback.entries.allSatisfy { $0.cancelled },
                "最后一个控音图释放后，即使播放集合原本为空也必须取消检测轮询")
        #expect(service.errorMessage == AppLocalization.text(
            ApplicationVolumeFailure.hardware(kAudioHardwareNotRunningError).messageKey
        ), "隐藏的候选控音故障也必须显示错误，保留重试入口")
        service.retry()
        fixture.flush()
        #expect(fixture.hardware.liveIO.count == 1, "隐藏候选的重试必须恢复已保存静音或低音量")
        #expect(fixture.playback.entries.last?.cancelled == false, "重试恢复音频图后必须恢复播放检测")
        guard !fixture.hardware.liveIO.isEmpty else { return }
        let input = ApplicationVolumeBufferFixture(channels: [2], samples: [[1, -1]])
        fixture.hardware.emit(input: input, output: output, at: fixture.hardware.callbacks.count - 1)
        #expect(output.samples(at: 0) == [gain, -gain])
        fixture.checkPlayback()
        #expect(service.applications.first?.isControlled == true)
        #expect(service.applications.first?.isMuted == (gain == 0))
        #expect(service.errorMessage == nil)
    }

    @Test(arguments: [Float(0), 0.25])
    func savedGainStillAppliesToTheFirstBufferAfterIdlePlaybackResumes(gain: Float) {
        let fixture = ApplicationVolumeBackendFixture()
        let defaults = ApplicationVolumePlaybackDefaultsFixture()
        defaults.store.set(["music": ["volume": gain == 0 ? 0.35 : Double(gain), "isMuted": gain == 0]],
                           forKey: ApplicationVolumeMixerService.preferencesKey)
        let service = Self.service(fixture, sources: [Self.source("music", pids: [101])], defaults: defaults.store)
        defer { service.stop(); fixture.flush() }
        service.start()
        fixture.flush()
        let input = ApplicationVolumeBufferFixture(channels: [2], samples: [[1, -1]])
        let silence = ApplicationVolumeBufferFixture(channels: [2], samples: [[0, 0]])
        let output = ApplicationVolumeBufferFixture(channels: [2], samples: [[9, 9]])
        fixture.hardware.emit(input: input, output: output, at: 0)
        fixture.checkPlayback()
        fixture.hardware.emit(input: silence, output: output, at: fixture.hardware.callbacks.count - 1)
        fixture.clock.time = 1
        fixture.checkPlayback()
        #expect(service.applications.isEmpty)

        fixture.hardware.emit(input: input, output: output, at: fixture.hardware.callbacks.count - 1)

        #expect(output.samples(at: 0) == [gain, -gain],
                "同一进程恢复的首批音频必须保持已保存静音或音量，不能等待检测后再恢复控制")
        #expect(fixture.hardware.tapDescriptions.last?.muteBehavior == .mutedWhenTapped)
    }

    @Test(arguments: [ApplicationVolumeHardwareStub.Stage.tap, .start], [Float(1), 0, 0.25])
    func retryingUnchangedCandidatesRecoversFromTheFirstMonitoringFailure(
        stage: ApplicationVolumeHardwareStub.Stage, gain: Float
    ) {
        let fixture = ApplicationVolumeBackendFixture()
        fixture.hardware.failAt = stage
        let defaults = ApplicationVolumePlaybackDefaultsFixture()
        defaults.store.set(["music": ["volume": Double(gain), "isMuted": false]],
                           forKey: ApplicationVolumeMixerService.preferencesKey)
        let service = Self.service(fixture, sources: [Self.source("music", pids: [101])], defaults: defaults.store)
        defer { service.stop(); fixture.flush() }
        service.start()
        fixture.flush()
        #expect(service.applications.isEmpty)
        #expect(service.errorMessage != nil)
        fixture.hardware.failAt = nil
        fixture.clock.time = 1

        service.retry()
        fixture.flush()

        #expect(fixture.hardware.liveIO.count == 1,
                "首次监测失败后同源没有新通知，点击重试必须恢复探测")
        guard !fixture.hardware.liveIO.isEmpty else { return }
        let input = ApplicationVolumeBufferFixture(channels: [2], samples: [[1, -1]])
        let output = ApplicationVolumeBufferFixture(channels: [2], samples: [[9, 9]])
        fixture.hardware.emit(input: input, output: output, at: fixture.hardware.callbacks.count - 1)
        fixture.checkPlayback()
        #expect(service.applications.map(\.id) == ["music"])
        #expect(service.errorMessage == nil)
        #expect(service.applications.first?.volume == Double(gain))
    }

    @Test
    func oneRetryRecoversAllFailedCandidatesAfterPermissionIsGranted() {
        let fixture = ApplicationVolumeBackendFixture()
        fixture.hardware.failAt = .tap
        fixture.hardware.failure = .permissionDenied
        let defaults = ApplicationVolumePlaybackDefaultsFixture()
        defaults.store.set(["music": ["volume": 0.35, "isMuted": true]],
                           forKey: ApplicationVolumeMixerService.preferencesKey)
        let service = Self.service(fixture, sources: [Self.source("music", pids: [101]),
                                                      Self.source("video", pids: [201])], defaults: defaults.store)
        defer { service.stop(); fixture.flush() }
        service.start()
        fixture.flush()
        #expect(service.errorMessage != nil)
        #expect(service.applications.isEmpty)
        fixture.hardware.failAt = nil

        service.retry()
        fixture.flush()

        #expect(fixture.hardware.liveIO.count == 2,
                "一次错误提示重试必须清除每个候选来源的创建失败缓存")
        let input = ApplicationVolumeBufferFixture(channels: [2], samples: [[1, -1]])
        let output = ApplicationVolumeBufferFixture(channels: [2], samples: [[9, 9]])
        fixture.hardware.emit(input: input, output: output, at: 0)
        #expect(output.samples(at: 0) == [0, 0])
        fixture.hardware.emit(input: input, output: output, at: 1)
        fixture.checkPlayback()
        #expect(service.applications.map(\.id) == ["music", "video"])
        #expect(service.applications.first?.isMuted == true)
        #expect(service.applications.first?.isControlled == true)
        #expect(service.errorMessage == nil)
    }

    @Test
    func idleOutputNeverFlashesAndSameProcessPlaybackResumesWithSavedMute() {
        let fixture = ApplicationVolumeBackendFixture()
        let source = Self.source("youku", pids: [101])
        let defaults = ApplicationVolumePlaybackDefaultsFixture()
        defaults.store.set([source.id: ["volume": 0.35, "isMuted": true]],
                           forKey: ApplicationVolumeMixerService.preferencesKey)
        let service = Self.service(fixture, sources: [source], defaults: defaults.store)
        defer { service.stop(); fixture.flush() }
        var snapshots: [[ApplicationVolumeApplication]] = []
        let observation = service.$applications.sink { snapshots.append($0) }
        defer { observation.cancel() }
        service.start()
        fixture.flush()

        #expect(snapshots.allSatisfy { $0.isEmpty }, "没有输入证据的首次空闲来源不能闪现音量行")
        #expect(fixture.hardware.tapDescriptions.last?.muteBehavior == .mutedWhenTapped,
                "首次空闲监测也必须保留已保存静音")
        let input = ApplicationVolumeBufferFixture(channels: [2], samples: [[0.000_001, -0.000_001]])
        let silence = ApplicationVolumeBufferFixture(channels: [2], samples: [[0, 0]])
        let output = ApplicationVolumeBufferFixture(channels: [2], samples: [[9, 9]])
        fixture.hardware.emit(input: input, output: output)
        fixture.checkPlayback()

        #expect(service.applications.first?.isMuted == true)
        #expect(service.applications.first?.volume == 0.35)
        #expect(service.applications.first?.isControlled == true)
        #expect(fixture.hardware.tapDescriptions.last?.muteBehavior == .mutedWhenTapped)
        fixture.hardware.emit(input: input, output: output, at: 0)
        #expect(output.samples(at: 0) == [0, 0])
        fixture.clock.time = 0.2
        fixture.checkPlayback()
        fixture.hardware.emit(input: silence, output: output, at: 0)
        fixture.clock.time = 1.2
        fixture.checkPlayback()

        #expect(service.applications.isEmpty, "持续静默满保持窗口后必须移除音量行")
        #expect(fixture.hardware.liveIO.count == 1, "候选输出仍运行时必须继续探测恢复")
        #expect(fixture.hardware.tapDescriptions.last?.muteBehavior == .mutedWhenTapped)
        fixture.hardware.emit(input: input, output: output, at: 0)
        fixture.clock.time = 1.4
        fixture.checkPlayback()
        #expect(output.samples(at: 0) == [0, 0], "恢复检测前首帧也必须保持静音")
        #expect(service.applications.first?.isMuted == true)
        #expect(service.applications.first?.isControlled == true)
        #expect(fixture.hardware.liveIO.count == 1)
    }

    @Test
    func concurrentApplicationsAreFilteredByTheirOwnInputEvidence() {
        let fixture = ApplicationVolumeBackendFixture()
        let defaults = ApplicationVolumePlaybackDefaultsFixture()
        let service = Self.service(fixture, sources: [Self.source("music", pids: [101]),
                                                      Self.source("youku", pids: [201])], defaults: defaults.store)
        defer { service.stop(); fixture.flush() }
        service.start()
        fixture.flush()
        let input = ApplicationVolumeBufferFixture(channels: [2], samples: [[0.000_001, -0.000_001]])
        let silence = ApplicationVolumeBufferFixture(channels: [2], samples: [[0, 0]])
        let output = ApplicationVolumeBufferFixture(channels: [2], samples: [[9, 9]])
        fixture.hardware.emit(input: input, output: output, at: 0)
        fixture.hardware.emit(input: silence, output: output, at: 1)
        fixture.checkPlayback()
        #expect(service.applications.map(\.id) == ["music"], "其它应用有声不能让空闲应用出现在混音器")
        fixture.hardware.emit(input: input, output: output, at: 1)
        fixture.checkPlayback()
        #expect(service.applications.map(\.id) == ["music", "youku"])
        service.setVolume(0.000_001, for: "music")
        fixture.flush()
        fixture.hardware.emit(input: input, output: output, at: 2)
        fixture.clock.time = 1
        fixture.checkPlayback()
        #expect(service.applications.map(\.id) == ["music"])
        #expect(service.applications.first?.volume == 0.000_001)
        #expect(service.applications.first?.isControlled == true)
    }

    @Test
    func monitoringPermissionFailureDoesNotPublishAnUnverifiedApplication() {
        let fixture = ApplicationVolumeBackendFixture()
        fixture.hardware.failAt = .tap
        fixture.hardware.failure = .permissionDenied
        let defaults = ApplicationVolumePlaybackDefaultsFixture()
        let service = Self.service(fixture, sources: [Self.source("youku", pids: [101])], defaults: defaults.store)
        defer { service.stop(); fixture.flush() }
        service.start()
        fixture.flush()

        #expect(service.applications.isEmpty)
        #expect(service.errorMessage == AppLocalization.text(ApplicationVolumeFailure.permissionDenied.messageKey))
        #expect(fixture.hardware.liveTaps.isEmpty && fixture.hardware.liveAggregates.isEmpty
            && fixture.hardware.liveIO.isEmpty)
        #expect(fixture.playback.entries.isEmpty)
    }

    @Test
    func failedControlKeepsItsVerifiedMonitorAndRecoversOnUserRetry() {
        let fixture = ApplicationVolumeBackendFixture()
        let defaults = ApplicationVolumePlaybackDefaultsFixture()
        let service = Self.service(fixture, sources: [Self.source("music", pids: [101])], defaults: defaults.store)
        defer { service.stop(); fixture.flush() }
        service.start()
        fixture.flush()
        let input = ApplicationVolumeBufferFixture(channels: [2], samples: [[1, -1]])
        let output = ApplicationVolumeBufferFixture(channels: [2], samples: [[9, 9]])
        fixture.hardware.emit(input: input, output: output)
        fixture.checkPlayback()
        fixture.hardware.failAt = .start

        service.setVolume(0.5, for: "music")
        fixture.flush()

        #expect(service.applications.first?.isControlled == false)
        #expect(service.errorMessage != nil)
        #expect(fixture.hardware.liveIO.count == 1)
        fixture.hardware.emit(input: input, output: output, at: 0)
        fixture.clock.time = 2
        fixture.checkPlayback()
        #expect(service.applications.map(\.id) == ["music"], "控制失败不能丢掉仍有真实输入的监测图")
        fixture.hardware.failAt = nil
        service.setVolume(0.5, for: "music")
        fixture.flush()
        #expect(service.applications.first?.isControlled == true)
        #expect(service.errorMessage == nil)
        #expect(fixture.hardware.liveIO.count == 1)
    }

    @Test
    func oldPlaybackChecksCannotConsumeOrPublishTheRestartedSessionEvidence() {
        let fixture = ApplicationVolumeBackendFixture()
        defer { fixture.stop() }
        fixture.backend.start()
        fixture.apply([Self.request(gain: 1)])
        fixture.backend.stop()
        fixture.backend.start()
        fixture.apply([Self.request(pids: [102], gain: 1)])
        let input = ApplicationVolumeBufferFixture(channels: [2], samples: [[1, -1]])
        let output = ApplicationVolumeBufferFixture(channels: [2], samples: [[9, 9]])
        fixture.hardware.emit(input: input, output: output, at: 1)

        fixture.playback.fire(at: 0)
        fixture.flush()
        #expect(fixture.backend.playingApplications.isEmpty)
        fixture.clock.time = 2
        fixture.checkPlayback()
        #expect(fixture.backend.playingApplications == ["music"],
                "旧检测事件不能提前消耗新图的非零输入进展")
        fixture.backend.stop()
        fixture.hardware.emit(input: input, output: output, at: 1)
        fixture.playback.fire(at: fixture.playback.entries.count - 1)
        fixture.flush()
        #expect(fixture.backend.playingApplications.isEmpty)
        #expect(fixture.hardware.liveTaps.isEmpty && fixture.hardware.liveAggregates.isEmpty
            && fixture.hardware.liveIO.isEmpty)
        #expect(fixture.playback.entries.allSatisfy { $0.cancelled })
    }

    @Test
    func stoppingFromAnApplyCompletionCannotRepublishCapturedPlayback() {
        let fixture = ApplicationVolumeBackendFixture()
        defer { fixture.stop() }
        fixture.backend.start()
        fixture.apply([Self.request(gain: 1)])
        let input = ApplicationVolumeBufferFixture(channels: [2], samples: [[1, -1]])
        let output = ApplicationVolumeBufferFixture(channels: [2], samples: [[9, 9]])
        fixture.hardware.emit(input: input, output: output)
        var updates: [Set<String>] = []
        fixture.backend.onPlaybackChanged = { updates.append($0) }

        fixture.backend.apply([Self.request(gain: 1)], retryingApplication: nil) { _ in
            fixture.backend.stop()
        }
        fixture.flush()

        #expect(fixture.backend.playingApplications.isEmpty,
                "完成回调停止后不能重新发布递交前捕获的播放证据")
        #expect(updates.isEmpty)
        #expect(fixture.hardware.liveIO.isEmpty)
    }

    @Test
    func replacingAProcessFromCompletionRejectsCapturedPlaybackForTheOldContext() {
        let fixture = ApplicationVolumeBackendFixture()
        defer { fixture.stop() }
        fixture.backend.start()
        fixture.apply([Self.request(gain: 1)])
        let input = ApplicationVolumeBufferFixture(channels: [2], samples: [[1, -1]])
        let output = ApplicationVolumeBufferFixture(channels: [2], samples: [[9, 9]])
        fixture.hardware.emit(input: input, output: output)
        var updates: [Set<String>] = []
        fixture.backend.onPlaybackChanged = { updates.append($0) }

        fixture.backend.apply([Self.request(gain: 1)], retryingApplication: nil) { _ in
            fixture.backend.apply([Self.request(pids: [102], gain: 1)], retryingApplication: nil) { _ in }
        }
        fixture.flush()

        #expect(fixture.backend.playingApplications.isEmpty)
        #expect(updates.isEmpty, "下一次应用进程替换不能短暂继承上次递交的非零输入证据")
        fixture.hardware.emit(input: input, output: output, at: 1)
        fixture.checkPlayback()
        #expect(fixture.backend.playingApplications == ["music"])
    }

    @Test
    func replacingOutputClearsTheMixerRowUntilTheNewGraphProvidesInput() {
        let fixture = ApplicationVolumeBackendFixture()
        let defaults = ApplicationVolumePlaybackDefaultsFixture()
        let service = Self.service(fixture, sources: [Self.source("music", pids: [101])], defaults: defaults.store)
        defer { service.stop(); fixture.flush() }
        service.start()
        fixture.flush()
        let input = ApplicationVolumeBufferFixture(channels: [2], samples: [[1, -1]])
        let output = ApplicationVolumeBufferFixture(channels: [2], samples: [[9, 9]])
        fixture.hardware.emit(input: input, output: output)
        fixture.checkPlayback()
        #expect(service.applications.map(\.id) == ["music"])
        fixture.hardware.output = ApplicationVolumeOutput(id: 70, uid: "fixture.replacement-output")

        fixture.properties.emit(.init(object: AudioObjectID(kAudioObjectSystemObject),
                                      selector: kAudioHardwarePropertyDefaultOutputDevice))
        fixture.flush()

        #expect(service.applications.isEmpty, "更换输出的图不能继承此前设备的播放证据")
        fixture.hardware.emit(input: input, output: output, at: 0)
        fixture.checkPlayback()
        #expect(service.applications.isEmpty)
        fixture.hardware.emit(input: input, output: output, at: 1)
        fixture.checkPlayback()
        #expect(service.applications.map(\.id) == ["music"])
        #expect(fixture.hardware.liveIO.count == 1)
    }

    @Test
    func aStalledControlCanBeRetriedWithoutChangingItsSavedGain() {
        let fixture = ApplicationVolumeBackendFixture()
        let defaults = ApplicationVolumePlaybackDefaultsFixture()
        let service = Self.service(fixture, sources: [Self.source("music", pids: [101])], defaults: defaults.store)
        defer { service.stop(); fixture.flush() }
        service.start()
        fixture.flush()
        let input = ApplicationVolumeBufferFixture(channels: [2], samples: [[1, -1]])
        let output = ApplicationVolumeBufferFixture(channels: [2], samples: [[9, 9]])
        fixture.hardware.emit(input: input, output: output)
        fixture.checkPlayback()
        service.setVolume(0.5, for: "music")
        fixture.flush()

        fixture.watchdog.fire(at: fixture.watchdog.entries.count - 1)
        fixture.flush()
        #expect(service.applications.first?.isControlled == false)
        fixture.checkPlayback()
        #expect(service.applications.isEmpty)
        #expect(fixture.hardware.liveIO.isEmpty, "失效控音图必须沿用原有故障回退释放")
        service.retry()
        fixture.flush()
        #expect(fixture.hardware.liveIO.count == 1)
        #expect(fixture.hardware.tapDescriptions.last?.muteBehavior == .mutedWhenTapped)
        fixture.hardware.emit(input: input, output: output, at: 2)
        #expect(output.samples(at: 0) == [0.5, -0.5])
        fixture.checkPlayback()
        #expect(service.applications.first?.isControlled == true)
        #expect(fixture.hardware.liveIO.count == 1)
    }

    @Test
    func unchangedPlaybackChecksDoNotRepublishTheSameEvidence() {
        let fixture = ApplicationVolumeBackendFixture()
        defer { fixture.stop() }
        fixture.backend.start()
        fixture.apply([Self.request(gain: 1)])
        var updates: [Set<String>] = []
        fixture.backend.onPlaybackChanged = { updates.append($0) }
        let input = ApplicationVolumeBufferFixture(channels: [2], samples: [[1, -1]])
        let output = ApplicationVolumeBufferFixture(channels: [2], samples: [[9, 9]])
        fixture.hardware.emit(input: input, output: output)

        fixture.checkPlayback()
        fixture.clock.time = 0.2
        fixture.checkPlayback()

        #expect(updates == [["music"]], "未变化的播放集合不能重复发布和重建检测任务")
    }

    @Test
    func removingTheLastCandidateCancelsBackgroundPlaybackChecks() {
        let fixture = ApplicationVolumeBackendFixture()
        defer { fixture.stop() }
        fixture.backend.start()
        fixture.apply([Self.request(gain: 1)])
        #expect(fixture.playback.entries.count == 1, "创建候选图后必须安装后台播放检测任务")
        fixture.apply([Self.request(gain: 1)])
        #expect(fixture.playback.entries.filter { !$0.cancelled }.count == 1,
                "反复协调同一候选集合只能保留一个后台检测任务")
        fixture.apply([])

        #expect(fixture.playback.entries.count == 2, "空候选集合不能安装新的检测任务")
        #expect(fixture.playback.entries.allSatisfy { $0.cancelled }, "最后一个候选移除后必须取消检测任务")
        #expect(fixture.hardware.liveIO.isEmpty)
    }

    @Test
    func queuedPlaybackDeliveryCannotOverwriteANewerSession() {
        let fixture = ApplicationVolumeBackendFixture()
        defer { fixture.stop() }
        fixture.backend.start()
        fixture.apply([Self.request(gain: 1)])
        let input = ApplicationVolumeBufferFixture(channels: [2], samples: [[1, -1]])
        let output = ApplicationVolumeBufferFixture(channels: [2], samples: [[9, 9]])
        fixture.hardware.emit(input: input, output: output)
        fixture.playback.fire(at: 0)
        fixture.events.runNext()
        fixture.queue.sync {}
        fixture.backend.stop()
        fixture.backend.start()
        fixture.apply([Self.request(pids: [102], gain: 1)])

        fixture.flush()

        #expect(fixture.backend.playingApplications.isEmpty,
                "排队中的旧检测结果不能覆盖停止后重新创建的播放会话")
        #expect(fixture.hardware.liveIO.count == 1)
    }

    @Test
    func anOutputStreamSendingOnlySilenceDoesNotRemainInTheMixer() throws {
        let fixture = ApplicationVolumeBackendFixture()
        let source = AudioPlaybackSource(
            id: "youku", processIdentifiers: [101], bundleIdentifier: "com.example.youku",
            applicationName: "Youku", iconData: nil, isFrontmost: false
        )
        let monitor = AudioPlaybackMonitor(
            readSources: { ([11], [source]) },
            registerProperty: { _, _, _, _ in noErr },
            applicationNotifications: NotificationCenter(),
            scheduleRefresh: { _ in {} }
        )
        let suite = "Zisla.ApplicationVolumeSilence.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let service = ApplicationVolumeMixerService(
            monitor: monitor, backend: fixture.backend,
            ownProcessIdentifier: -1, ownBundleIdentifier: "fixture.zisla", defaults: defaults
        )
        defer { service.stop(); fixture.flush() }
        service.start()
        fixture.flush()
        let input = ApplicationVolumeBufferFixture(channels: [2], samples: [[0, 0]])
        let output = ApplicationVolumeBufferFixture(channels: [2], samples: [[9, 9]])

        for _ in 0..<2 {
            fixture.hardware.emit(input: input, output: output)
            fixture.checkPlayback()
        }

        #expect(service.applications.isEmpty,
                "保持输出 I/O 但持续发送全零音频的空闲应用不能保留在混音器中")
    }

    @Test
    func stopReturnsAfterStoppingQueuedControlsAndOriginalPlaybackIsRestored() {
        let fixture = ApplicationVolumeBackendFixture()
        defer { fixture.stop() }
        fixture.backend.start()
        fixture.apply([Self.request()])
        let input = ApplicationVolumeBufferFixture(channels: [2], samples: [[1, -1]])
        let output = ApplicationVolumeBufferFixture(channels: [2], samples: [[9, 9]])
        let entered = DispatchSemaphore(value: 0)
        let release = DispatchSemaphore(value: 0)
        fixture.queue.async {
            entered.signal()
            _ = release.wait(timeout: .now() + .milliseconds(300))
        }
        #expect(entered.wait(timeout: .now() + .seconds(2)) == .success)
        var completions = 0
        fixture.backend.apply([Self.request(pids: [201])], retryingApplication: nil) { _ in completions += 1 }

        fixture.backend.stop()
        let stoppedReading = fixture.hardware.events.contains { $0.hasPrefix("stopIO:") }
        let resourcesReleased = fixture.hardware.liveTaps.isEmpty
            && fixture.hardware.liveAggregates.isEmpty && fixture.hardware.liveIO.isEmpty
        fixture.hardware.emit(input: input, output: output)
        let stoppedSamples = output.samples(at: 0)
        release.signal()
        fixture.flush()
        fixture.backend.stop()

        #expect(stoppedReading, "停止返回前必须先恢复原始播放")
        #expect(resourcesReleased, "队列中已有的控制请求必须在停止返回前释放")
        #expect(stoppedSamples == [0, 0], "停止后保留的回调不能继续播放")
        #expect(completions == 0)
        #expect(fixture.properties.active.isEmpty)
        #expect(fixture.watchdog.entries.allSatisfy { $0.cancelled })
    }

    @Test
    func anOldWatchdogFailureCannotCrossStopAndStart() {
        let fixture = ApplicationVolumeBackendFixture()
        defer { fixture.stop() }
        var failures: [ApplicationVolumeFailure] = []
        fixture.backend.onControlFailure = { _, failure in failures.append(failure) }
        fixture.backend.start()
        fixture.apply([Self.request()])
        fixture.holdWatchdogFailure()
        fixture.backend.stop()
        fixture.queue.sync {}
        fixture.backend.start()
        fixture.apply([Self.request(pids: [102])])

        fixture.flush()

        #expect(failures.isEmpty, "前一会话的失败不能覆盖重新启用后的成功")
        #expect(fixture.hardware.liveIO.count == 1)
        #expect(fixture.watchdog.entries.last?.cancelled == false)
    }

    @Test
    func anOldWatchdogFailureCannotOverwriteASuccessfulUserRetry() {
        let fixture = ApplicationVolumeBackendFixture()
        defer { fixture.stop() }
        var failures: [ApplicationVolumeFailure] = []
        fixture.backend.onControlFailure = { _, failure in failures.append(failure) }
        fixture.backend.start()
        fixture.apply([Self.request()])
        fixture.holdWatchdogFailure()

        fixture.apply([Self.request(gain: 0.7)], retryingApplication: "music")
        fixture.flush()

        #expect(failures.isEmpty, "用户重试成功后不应再收到旧停滞事件")
        #expect(fixture.hardware.liveIO.count == 1)
        #expect(fixture.watchdog.entries.last?.cancelled == false)
    }

    @Test
    func theCurrentWatchdogReportsOnlyAStalledApplicationAndWorksAfterRetry() {
        let fixture = ApplicationVolumeBackendFixture()
        defer { fixture.stop() }
        fixture.backend.start()
        let requests = [Self.request(), ApplicationVolumeRequest(id: "video", processIdentifiers: [201], gain: 0.75)]
        fixture.apply(requests)
        var failures: [String: ApplicationVolumeFailure] = [:]
        fixture.backend.onControlFailure = { failures[$0] = $1 }
        let input = ApplicationVolumeBufferFixture(channels: [2], samples: [[1, -1]])
        let output = ApplicationVolumeBufferFixture(channels: [2], samples: [[9, 9]])
        fixture.hardware.emit(input: input, output: output, at: 0)

        fixture.watchdog.fire(at: fixture.watchdog.entries.count - 1)
        fixture.flush()

        #expect(failures == ["video": .hardware(kAudioHardwareNotRunningError)])
        #expect(fixture.hardware.liveIO.count == 1)
        #expect(fixture.watchdog.entries.last?.cancelled == false)
        fixture.hardware.emit(input: input, output: output, at: 1)
        #expect(output.samples(at: 0) == [0, 0])
        fixture.apply(requests, retryingApplication: "video")
        failures = [:]
        fixture.hardware.emit(input: input, output: output, at: 0)
        fixture.hardware.emit(input: input, output: output, at: 2)
        fixture.watchdog.fire(at: fixture.watchdog.entries.count - 1)
        fixture.flush()
        #expect(failures.isEmpty)
        #expect(fixture.hardware.liveIO.count == 2)

        fixture.watchdog.fire(at: fixture.watchdog.entries.count - 1)
        fixture.flush()
        #expect(failures == ["music": .hardware(kAudioHardwareNotRunningError),
                             "video": .hardware(kAudioHardwareNotRunningError)])
        #expect(fixture.hardware.liveIO.isEmpty && fixture.hardware.liveTaps.isEmpty)
        #expect(fixture.watchdog.entries.last?.cancelled == true)
    }

    @Test
    func anOldWatchdogTickCannotStopTheNewSessionGraph() {
        let fixture = ApplicationVolumeBackendFixture()
        defer { fixture.stop() }
        fixture.backend.start()
        fixture.apply([Self.request()])
        fixture.backend.stop()
        fixture.queue.sync {}
        fixture.backend.start()
        fixture.apply([Self.request(pids: [102])])

        fixture.watchdog.fire(at: 0)
        fixture.flush()

        #expect(fixture.hardware.liveIO.count == 1, "已取消的旧事件不能停止新会话的音频链路")
        #expect(fixture.watchdog.entries.last?.cancelled == false)
    }

    @Test
    func aPreviousPropertyCallbackCannotRebuildTheRestartedSession() throws {
        let fixture = ApplicationVolumeBackendFixture()
        defer { fixture.stop() }
        fixture.backend.start()
        let old = try #require(fixture.properties.retained.first?.1)
        fixture.backend.stop()
        fixture.queue.sync {}
        fixture.backend.start()
        var changes = 0
        fixture.backend.onOutputChanged = { changes += 1 }

        var address = CoreAudioVolumeHardware.address(kAudioHardwarePropertyDefaultOutputDevice)
        withUnsafePointer(to: &address) { old(1, $0) }

        #expect(changes == 0, "移除监听后已排队的旧事件不能重建新会话")
    }

    @Test
    func changingProcessOutputRefreshesCompensationAndTracksReplacedHelpers() {
        let fixture = ApplicationVolumeBackendFixture()
        defer { fixture.stop() }
        fixture.backend.start()
        let requests = [Self.request()]
        fixture.apply(requests)
        fixture.backend.onOutputChanged = { [weak backend = fixture.backend] in
            backend?.apply(requests, retryingApplication: nil) { _ in }
        }
        let input = ApplicationVolumeBufferFixture(channels: [2], samples: [[1, -1]])
        let output = ApplicationVolumeBufferFixture(channels: [2], samples: [[9, 9]])
        let processKey = ApplicationVolumePropertyKey(
            object: 101, selector: kAudioProcessPropertyDevices, scope: kAudioObjectPropertyScopeOutput
        )

        fixture.hardware.compensation = 3
        fixture.properties.emit(processKey)
        fixture.flush()
        fixture.hardware.emit(input: input, output: output, at: fixture.hardware.callbacks.count - 1)

        #expect(output.samples(at: 0) == [1.5, -1.5], "应用自己切换输出后必须重新读取 mixdown 补偿")
        #expect(fixture.hardware.liveIO.count == 1)
        fixture.apply([Self.request(pids: [102, 103])])
        #expect(fixture.properties.active[processKey] == nil)
        #expect(fixture.properties.active[.init(object: 102, selector: kAudioProcessPropertyDevices,
                                                scope: kAudioObjectPropertyScopeOutput)] != nil)
        #expect(fixture.properties.active[.init(object: 103, selector: kAudioProcessPropertyDevices,
                                                scope: kAudioObjectPropertyScopeOutput)] != nil)
    }

    @Test(arguments: [kAudioDevicePropertyPreferredChannelsForStereo, kAudioDevicePropertyStreamConfiguration])
    func changingOutputChannelConfigurationRebuildsTheChannelMap(selector: AudioObjectPropertySelector) {
        let fixture = ApplicationVolumeBackendFixture()
        defer { fixture.stop() }
        fixture.backend.start()
        let requests = [Self.request()]
        fixture.apply(requests)
        fixture.backend.onOutputChanged = { [weak backend = fixture.backend] in
            backend?.apply(requests, retryingApplication: nil) { _ in }
        }
        fixture.hardware.preferredStereoChannels = ApplicationVolumeStereoChannels(left: 1, right: 0)
        let input = ApplicationVolumeBufferFixture(channels: [2], samples: [[1, 0.25]])
        let output = ApplicationVolumeBufferFixture(channels: [2], samples: [[9, 9]])

        fixture.properties.emit(.init(object: fixture.hardware.output.id, selector: selector,
                                      scope: kAudioObjectPropertyScopeOutput))
        fixture.flush()
        fixture.hardware.emit(input: input, output: output, at: fixture.hardware.callbacks.count - 1)

        #expect(output.samples(at: 0) == [0.125, 0.5], "立体声首选通道或输出布局变化必须更新路由")
        #expect(fixture.hardware.liveIO.count == 1)
    }

    @Test
    func outputRebuildFailureRestoresPlaybackAndAllowsAUserRetry() {
        let fixture = ApplicationVolumeBackendFixture()
        defer { fixture.stop() }
        fixture.backend.start()
        let requests = [Self.request()]
        fixture.apply(requests)
        var failures: [String: ApplicationVolumeFailure] = [:]
        fixture.backend.onOutputChanged = { [weak backend = fixture.backend] in
            backend?.apply(requests, retryingApplication: nil) { failures = $0 }
        }
        fixture.hardware.failAt = .compensation

        fixture.properties.emit(.init(object: 101, selector: kAudioProcessPropertyDevices,
                                      scope: kAudioObjectPropertyScopeOutput))
        fixture.flush()

        #expect(failures["music"] == fixture.hardware.failure)
        #expect(fixture.hardware.liveIO.isEmpty && fixture.hardware.liveTaps.isEmpty)
        fixture.hardware.failAt = nil
        fixture.apply(requests, retryingApplication: "music")
        #expect(fixture.hardware.liveIO.count == 1)
    }

    @Test
    func aWakeNotificationRebuildsAndStopRemovesTheObserver() {
        let fixture = ApplicationVolumeBackendFixture()
        defer { fixture.stop() }
        fixture.backend.start()
        let requests = [Self.request()]
        fixture.apply(requests)
        var changes = 0
        fixture.backend.onOutputChanged = { [weak backend = fixture.backend] in
            changes += 1
            backend?.apply(requests, retryingApplication: nil) { _ in }
        }
        fixture.hardware.compensation = 2

        fixture.notifications.post(name: NSWorkspace.didWakeNotification, object: nil)
        fixture.flush()

        let input = ApplicationVolumeBufferFixture(channels: [2], samples: [[1, -1]])
        let output = ApplicationVolumeBufferFixture(channels: [2], samples: [[9, 9]])
        fixture.hardware.emit(input: input, output: output, at: fixture.hardware.callbacks.count - 1)
        #expect(output.samples(at: 0) == [1, -1])
        #expect(changes == 1)
        fixture.backend.stop()
        fixture.notifications.post(name: NSWorkspace.didWakeNotification, object: nil)
        #expect(changes == 1)
    }

    @Test
    func failedListenerRegistrationDoesNotLeaveAnUnremovableSubscription() {
        let fixture = ApplicationVolumeBackendFixture()
        defer { fixture.stop() }
        let refused = ApplicationVolumePropertyKey(
            object: fixture.hardware.output.id, selector: kAudioDevicePropertyNominalSampleRate
        )
        fixture.properties.refused = [refused]
        fixture.backend.start()
        fixture.apply([Self.request()])

        fixture.backend.stop()
        fixture.flush()

        #expect(!fixture.properties.removed.contains(refused))
        #expect(fixture.properties.active.isEmpty)
        #expect(fixture.hardware.liveIO.isEmpty)
    }

    private static func request(pids: [pid_t] = [101], gain: Float = 0.5) -> ApplicationVolumeRequest {
        ApplicationVolumeRequest(id: "music", processIdentifiers: pids, gain: gain)
    }

    private static func source(_ id: String, pids: [pid_t]) -> AudioPlaybackSource {
        AudioPlaybackSource(id: id, processIdentifiers: pids, bundleIdentifier: "fixture.\(id)",
                            applicationName: id, iconData: nil, isFrontmost: false)
    }

    private static func service(
        _ fixture: ApplicationVolumeBackendFixture, sources: [AudioPlaybackSource], defaults: UserDefaults
    ) -> ApplicationVolumeMixerService {
        let monitor = AudioPlaybackMonitor(
            readSources: { (sources.flatMap(\.processIdentifiers).map { AudioObjectID($0) }, sources) },
            registerProperty: { _, _, _, _ in noErr }, applicationNotifications: NotificationCenter(),
            scheduleRefresh: { _ in {} }
        )
        return ApplicationVolumeMixerService(
            monitor: monitor, backend: fixture.backend,
            ownProcessIdentifier: -1, ownBundleIdentifier: "fixture.zisla", defaults: defaults
        )
    }
}

@MainActor
private final class ApplicationVolumePlaybackDefaultsFixture {
    private let suite = "Zisla.ApplicationVolumePlayback.\(UUID().uuidString)"
    let store: UserDefaults

    init() { store = UserDefaults(suiteName: suite)! }
    isolated deinit { store.removePersistentDomain(forName: suite) }
}

@MainActor
private final class ApplicationVolumeBackendFixture {
    let hardware: ApplicationVolumeHardwareStub
    let queue: DispatchQueue
    let events: ApplicationVolumeBackendEvents
    let properties: ApplicationVolumePropertyStub
    let watchdog: ApplicationVolumeWatchdogStub
    let playback: ApplicationVolumeWatchdogStub
    let clock: ApplicationVolumeClockStub
    let notifications: NotificationCenter
    let backend: CoreAudioApplicationVolumeBackend

    init() {
        let hardware = ApplicationVolumeHardwareStub()
        let queue = DispatchQueue(label: "fixture.application-volume-backend")
        let properties = ApplicationVolumePropertyStub()
        let watchdog = ApplicationVolumeWatchdogStub()
        let playback = ApplicationVolumeWatchdogStub()
        let clock = ApplicationVolumeClockStub()
        let events = ApplicationVolumeBackendEvents()
        let notifications = NotificationCenter()
        self.hardware = hardware
        self.queue = queue
        self.properties = properties
        self.watchdog = watchdog
        self.playback = playback
        self.clock = clock
        self.events = events
        self.notifications = notifications
        backend = CoreAudioApplicationVolumeBackend(
            hardware: hardware, queue: queue, dispose: { $0() },
            registerProperty: { properties.register($0, address: $1, callback: $2, adding: $3) },
            wakeNotifications: notifications,
            scheduleWatchdog: { watchdog.schedule(queue: $0, event: $1) },
            schedulePlaybackCheck: { playback.schedule(queue: $0, event: $1) },
            now: { clock.time },
            deliver: { events.enqueue($0) }
        )
    }

    func apply(_ requests: [ApplicationVolumeRequest], retryingApplication: String? = nil) {
        backend.apply(requests, retryingApplication: retryingApplication) { _ in }
        queue.sync {}
        events.runLast()
    }

    func holdWatchdogFailure() {
        watchdog.fire(at: watchdog.entries.count - 1)
        if !hardware.liveIO.isEmpty {
            events.runNext()
            queue.sync {}
        }
        #expect(hardware.liveIO.isEmpty, "停滞必须恢复原始播放后再递交失败结果")
        #expect(events.count > 0)
    }

    func flush() {
        queue.sync {}
        while events.count > 0 {
            events.runNext()
            queue.sync {}
        }
    }

    func checkPlayback() {
        guard !playback.entries.isEmpty else {
            Issue.record("后台播放检测任务缺失，无法识别或恢复候选源")
            return
        }
        playback.fire(at: playback.entries.count - 1)
        flush()
    }

    func stop() {
        backend.stop()
        flush()
    }
}

private final class ApplicationVolumeClockStub: @unchecked Sendable {
    private let lock = NSLock()
    private var value: TimeInterval = 0
    var time: TimeInterval {
        get { lock.withLock { value } }
        set { lock.withLock { value = newValue } }
    }
}

private final class ApplicationVolumeBackendEvents: @unchecked Sendable {
    private let lock = NSLock()
    private var events: [@MainActor @Sendable () -> Void] = []

    var count: Int { lock.withLock { events.count } }
    func enqueue(_ event: @escaping @MainActor @Sendable () -> Void) { lock.withLock { events.append(event) } }
    @MainActor func runNext() { lock.withLock { events.removeFirst() }() }
    @MainActor func runLast() { lock.withLock { events.removeLast() }() }
}

private struct ApplicationVolumePropertyKey: Hashable {
    let object: AudioObjectID
    let selector: AudioObjectPropertySelector
    var scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal
}

@MainActor
private final class ApplicationVolumePropertyStub {
    var refused: Set<ApplicationVolumePropertyKey> = []
    private(set) var active: [ApplicationVolumePropertyKey: AudioObjectPropertyListenerBlock] = [:]
    private(set) var retained: [(ApplicationVolumePropertyKey, AudioObjectPropertyListenerBlock)] = []
    private(set) var removed: [ApplicationVolumePropertyKey] = []

    func register(_ object: AudioObjectID, address: AudioObjectPropertyAddress,
                  callback: @escaping AudioObjectPropertyListenerBlock, adding: Bool) -> OSStatus {
        let key = ApplicationVolumePropertyKey(object: object, selector: address.mSelector, scope: address.mScope)
        if adding {
            if refused.contains(key) { return kAudioHardwareBadObjectError }
            active[key] = callback
            retained.append((key, callback))
        } else {
            active[key] = nil
            removed.append(key)
        }
        return noErr
    }

    func emit(_ key: ApplicationVolumePropertyKey) {
        var address = CoreAudioVolumeHardware.address(key.selector, scope: key.scope)
        withUnsafePointer(to: &address) { active[key]?(1, $0) }
    }
}

@MainActor
private final class ApplicationVolumeWatchdogStub {
    struct Entry {
        let queue: DispatchQueue
        let event: @Sendable () -> Void
        var cancelled = false
    }

    private(set) var entries: [Entry] = []

    func schedule(queue: DispatchQueue, event: @escaping @Sendable () -> Void) -> @MainActor () -> Void {
        let index = entries.count
        entries.append(Entry(queue: queue, event: event))
        return { [weak self] in self?.entries[index].cancelled = true }
    }

    func fire(at index: Int) {
        let entry = entries[index]
        entry.queue.sync(execute: entry.event)
    }
}
