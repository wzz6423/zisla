import Foundation
import CoreAudio
import Testing

@testable import ZislaKit

struct AudioPlaybackMonitorTests {
    @Test @MainActor
    func stoppedOutputDisappearsWithoutAPropertyNotification() {
        let fixture = AudioPlaybackMonitorFixture()
        defer { fixture.monitor.stop() }
        let youku = source(id: "youku", pids: [101], bundleIdentifier: "com.example.youku")
        fixture.sources = [youku]
        fixture.objects = [11]
        fixture.monitor.start()
        #expect(fixture.monitor.sources == [youku])

        fixture.sources = []
        fixture.objects = []
        fixture.fireRefresh()

        #expect(fixture.monitor.sources.isEmpty, "停止播放且没有 HAL 通知时，音量列表也必须移除应用")
        #expect(!fixture.observedObjects.contains(11), "退出的音频对象不能留下监听")
    }

    @Test @MainActor
    func resumedOutputAppearsWithoutAPropertyNotification() {
        let fixture = AudioPlaybackMonitorFixture()
        defer { fixture.monitor.stop() }
        fixture.monitor.start()
        let youku = source(id: "youku", pids: [102], bundleIdentifier: "com.example.youku")

        fixture.sources = [youku]
        fixture.objects = [12]
        fixture.fireRefresh()

        #expect(fixture.monitor.sources == [youku], "空列表仍须发现没有 HAL 通知的重新播放")
    }

    @Test @MainActor
    func unchangedRefreshesDoNotRepublishOrDuplicateMonitoring() {
        let fixture = AudioPlaybackMonitorFixture()
        defer { fixture.monitor.stop() }
        fixture.sources = [source(id: "youku", pids: [101], bundleIdentifier: "com.example.youku")]
        fixture.objects = [11]
        var changes: [[AudioPlaybackSource]] = []
        fixture.monitor.onSourcesChanged = { changes.append($0) }
        fixture.monitor.start()
        fixture.monitor.start()
        fixture.fireRefresh()
        fixture.fireRefresh()

        #expect(changes == [fixture.sources])
        #expect(fixture.refreshEvents.count == 1, "重复 start 不能创建第二个复核任务")
        #expect(fixture.observedObjects == [AudioObjectID(kAudioObjectSystemObject), 11])
    }

    @Test @MainActor
    func refusedPropertyListenersStillRecoverAndStopCleanly() {
        let fixture = AudioPlaybackMonitorFixture()
        fixture.refusesProperties = true
        fixture.sources = [source(id: "youku", pids: [101], bundleIdentifier: "com.example.youku")]
        fixture.objects = [11]
        fixture.monitor.start()
        fixture.sources = []
        fixture.fireRefresh()

        #expect(fixture.monitor.sources.isEmpty)
        fixture.monitor.stop()
        #expect(fixture.observedObjects.isEmpty)
        #expect(fixture.cancelledRefreshes == [0])
    }

    @Test @MainActor
    func callbacksQueuedBeforeStopCannotRepublishOrCrossAReplacedSession() {
        let fixture = AudioPlaybackMonitorFixture()
        defer { fixture.monitor.stop() }
        fixture.sources = [source(id: "youku", pids: [101], bundleIdentifier: "com.example.youku")]
        fixture.objects = [11]
        fixture.monitor.start()
        let oldProperty = fixture.propertyEvents.first?.1
        fixture.monitor.stop()
        fixture.fireRefresh(at: 0)
        fixture.fireProperty(oldProperty)

        #expect(fixture.monitor.sources.isEmpty, "已停止的监听回调不能重新发布应用")
        #expect(fixture.observedObjects.isEmpty)
        #expect(fixture.cancelledRefreshes == [0])

        fixture.sources = []
        fixture.objects = []
        fixture.monitor.start()
        fixture.sources = [source(id: "other", pids: [201], bundleIdentifier: "com.example.other")]
        fixture.objects = [21]
        fixture.fireRefresh(at: 0)
        fixture.fireProperty(oldProperty)
        #expect(fixture.monitor.sources.isEmpty, "上一会话的回调不能进入重新启动的会话")
        fixture.fireRefresh(at: 1)
        #expect(fixture.monitor.sources == fixture.sources)
    }

    @Test @MainActor
    func releasingTheMonitorCancelsRefreshAndRemovesListeners() {
        let fixture = AudioPlaybackMonitorFixture()
        fixture.objects = [11]
        var monitor: AudioPlaybackMonitor? = fixture.makeMonitor()
        monitor?.start()
        weak let released = monitor

        monitor = nil

        #expect(released == nil)
        #expect(fixture.cancelledRefreshes == [0], "释放监控对象也必须取消复核任务")
        #expect(fixture.observedObjects.isEmpty)
    }

    @Test @MainActor
    func refreshingStoppedOutputRemovesTheMixerRowAndResumingRestoresItsVolume() throws {
        let fixture = AudioPlaybackMonitorFixture()
        let youku = source(id: "youku", pids: [101], bundleIdentifier: "com.example.youku")
        fixture.sources = [youku]
        fixture.objects = [11]
        let suite = "Zisla.AudioPlaybackMixer.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let backend = AudioPlaybackMixerBackendStub()
        let service = ApplicationVolumeMixerService(
            monitor: fixture.monitor, backend: backend,
            ownProcessIdentifier: -1, ownBundleIdentifier: "fixture.zisla", defaults: defaults
        )
        defer { service.stop() }
        service.start()
        service.setVolume(0.35, for: "youku")

        fixture.sources = []
        fixture.objects = []
        fixture.fireRefresh()

        #expect(service.applications.isEmpty, "停止输出复核必须直接移除混音器中的旧应用")
        #expect(backend.requests.isEmpty, "移除应用也必须释放音频控制请求")
        fixture.sources = [youku]
        fixture.objects = [11]
        fixture.fireRefresh()
        #expect(service.applications.first?.volume == 0.35)
        #expect(service.applications.first?.isControlled == true)
        #expect(backend.requests == [ApplicationVolumeRequest(id: "youku", processIdentifiers: [101], gain: 0.35)])
    }

    @Test
    func activatedProcessWinsBeforeBundleFallback() {
        let sources = [
            source(id: "music", pids: [101], bundleIdentifier: "com.example.music"),
            source(id: "video", pids: [202], bundleIdentifier: "com.example.video"),
        ]

        #expect(
            AudioPlaybackMonitor.sourceID(
                processIdentifier: 202,
                bundleIdentifier: "com.example.music",
                sources: sources
            ) == "video"
        )
        #expect(
            AudioPlaybackMonitor.sourceID(
                processIdentifier: nil,
                bundleIdentifier: "com.example.video",
                sources: sources
            ) == "video"
        )
    }

    @Test
    func unknownActivatedProcessClearsThePreviousSourcePreference() {
        let sources = [
            source(id: "music", pids: [101], bundleIdentifier: "com.example.music"),
        ]

        #expect(
            AudioPlaybackMonitor.sourceID(
                processIdentifier: 404,
                bundleIdentifier: "com.example.unknown",
                sources: sources
            ) == nil
        )
    }

    private func source(
        id: String,
        pids: [pid_t],
        bundleIdentifier: String
    ) -> AudioPlaybackSource {
        AudioPlaybackSource(
            id: id,
            processIdentifiers: pids,
            bundleIdentifier: bundleIdentifier,
            applicationName: id,
            iconData: nil,
            isFrontmost: false
        )
    }
}

@MainActor
private final class AudioPlaybackMixerBackendStub: ApplicationVolumeMixing {
    var isSupported = true
    var onOutputChanged: (@MainActor () -> Void)?
    var onControlFailure: (@MainActor (String, ApplicationVolumeFailure) -> Void)?
    var requests: [ApplicationVolumeRequest] = []

    func start() {}
    func stop() { requests = [] }
    func apply(
        _ requests: [ApplicationVolumeRequest], retryingApplication: String?,
        completion: @escaping @MainActor ([String: ApplicationVolumeFailure]) -> Void
    ) {
        self.requests = requests
        completion([:])
    }
}

@MainActor
private final class AudioPlaybackMonitorFixture {
    var sources: [AudioPlaybackSource] = []
    var objects: [AudioObjectID] = []
    var refusesProperties = false
    var observedObjects: Set<AudioObjectID> = []
    var propertyEvents: [(AudioObjectPropertyAddress, AudioObjectPropertyListenerBlock)] = []
    var refreshEvents: [@MainActor @Sendable () -> Void] = []
    var cancelledRefreshes: Set<Int> = []

    lazy var monitor = makeMonitor()

    func makeMonitor() -> AudioPlaybackMonitor {
        AudioPlaybackMonitor(
            readSources: { [unowned self] in (objects, sources) },
            registerProperty: { [unowned self] object, address, event, adding in
                if adding {
                    guard !refusesProperties else { return kAudioHardwareBadObjectError }
                    observedObjects.insert(object)
                    propertyEvents.append((address, event))
                } else {
                    observedObjects.remove(object)
                }
                return noErr
            },
            applicationNotifications: NotificationCenter(),
            scheduleRefresh: { [unowned self] event in
                let index = refreshEvents.count
                refreshEvents.append(event)
                return { [unowned self] in cancelledRefreshes.insert(index) }
            }
        )
    }

    func fireRefresh(at index: Int = 0) {
        if refreshEvents.indices.contains(index) { refreshEvents[index]() }
    }

    func fireProperty(_ event: AudioObjectPropertyListenerBlock?) {
        var address = CoreAudioVolumeHardware.address(kAudioHardwarePropertyProcessObjectList)
        withUnsafePointer(to: &address) { event?(1, $0) }
    }
}
