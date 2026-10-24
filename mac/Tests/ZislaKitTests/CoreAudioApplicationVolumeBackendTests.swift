import AppKit
import CoreAudio
import Foundation
import Testing

@testable import ZislaKit

@MainActor
struct CoreAudioApplicationVolumeBackendTests {
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
}

@MainActor
private final class ApplicationVolumeBackendFixture {
    let hardware: ApplicationVolumeHardwareStub
    let queue: DispatchQueue
    let events: ApplicationVolumeBackendEvents
    let properties: ApplicationVolumePropertyStub
    let watchdog: ApplicationVolumeWatchdogStub
    let notifications: NotificationCenter
    let backend: CoreAudioApplicationVolumeBackend

    init() {
        let hardware = ApplicationVolumeHardwareStub()
        let queue = DispatchQueue(label: "fixture.application-volume-backend")
        let properties = ApplicationVolumePropertyStub()
        let watchdog = ApplicationVolumeWatchdogStub()
        let events = ApplicationVolumeBackendEvents()
        let notifications = NotificationCenter()
        self.hardware = hardware
        self.queue = queue
        self.properties = properties
        self.watchdog = watchdog
        self.events = events
        self.notifications = notifications
        backend = CoreAudioApplicationVolumeBackend(
            hardware: hardware, queue: queue, dispose: { $0() },
            registerProperty: { properties.register($0, address: $1, callback: $2, adding: $3) },
            wakeNotifications: notifications,
            scheduleWatchdog: { watchdog.schedule(queue: $0, event: $1) },
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

    func stop() {
        backend.stop()
        flush()
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
