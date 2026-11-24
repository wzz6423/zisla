import AppKit
import CoreAudio
import Foundation

final class ApplicationVolumeGraphStore: @unchecked Sendable {
    private struct Context: Equatable {
        let identifiers: [pid_t]
        var processObjects: [AudioObjectID]?
        let output: ApplicationVolumeOutput
    }

    private struct PlaybackEvidence {
        var progress: Int32
        var lastSignalTime: TimeInterval?
    }

    private struct GraphFailure {
        let reason: ApplicationVolumeFailure
        let isMonitoring: Bool
    }

    private let hardware: any ApplicationVolumeAudioHardware
    private let dispose: @Sendable (@escaping @Sendable () -> Void) -> Void
    private var graphs: [String: ApplicationVolumeAudioGraph] = [:]
    private var failures: [String: GraphFailure] = [:]
    private var contexts: [String: Context] = [:]
    private var progress: [String: Int32] = [:]
    private var playbackEvidence: [String: PlaybackEvidence] = [:]

    var hasGraphs: Bool { !graphs.isEmpty }
    var hasControls: Bool { graphs.values.contains { !$0.isMonitoring } }
    var output: AudioObjectID? { graphs.values.first?.output.id }
    var processObjects: Set<AudioObjectID> { Set(graphs.values.flatMap(\.processObjects)) }

    init(
        hardware: any ApplicationVolumeAudioHardware,
        dispose: @escaping @Sendable (@escaping @Sendable () -> Void) -> Void = {
            DispatchQueue.global(qos: .utility).async(execute: $0)
        }
    ) {
        self.hardware = hardware
        self.dispose = dispose
    }

    func apply(
        _ requests: [ApplicationVolumeRequest], retryingApplication: String?, rebuild: Bool
    ) -> [String: ApplicationVolumeFailure] {
        let ids = Set(requests.map(\.id))
        for id in Array(graphs.keys) where !ids.contains(id) { remove(id) }
        failures = failures.filter { ids.contains($0.key) }
        contexts = contexts.filter { ids.contains($0.key) }
        if rebuild {
            stop()
        } else if let retryingApplication {
            failures[retryingApplication] = nil
        }
        guard !requests.isEmpty else { return [:] }
        let output: ApplicationVolumeOutput
        do {
            output = try hardware.defaultOutput()
        } catch {
            stop()
            let failure = error as? ApplicationVolumeFailure ?? .hardware(kAudioHardwareUnspecifiedError)
            failures = Dictionary(uniqueKeysWithValues: requests.map {
                ($0.id, GraphFailure(reason: failure, isMonitoring: $0.gain == 1))
            })
            return failures.mapValues(\.reason)
        }
        for request in requests {
            var context = Context(
                identifiers: request.processIdentifiers, processObjects: nil, output: output
            )
            var keepMonitoringGraph = false
            do {
                let objects = try hardware.processObjects(for: request.processIdentifiers)
                context.processObjects = objects
                let unchanged = contexts[request.id] == context
                contexts[request.id] = context
                keepMonitoringGraph = unchanged && graphs[request.id]?.isMonitoring == true
                if unchanged, failures[request.id]?.isMonitoring == (request.gain == 1) {
                    continue
                }
                failures[request.id] = nil
                if unchanged, let graph = graphs[request.id], graph.processObjects == objects, graph.output == output,
                   graph.isMonitoring == (request.gain == 1) {
                    graph.gain = request.gain
                } else {
                    let lastSignalTime = unchanged ? playbackEvidence[request.id]?.lastSignalTime : nil
                    if !keepMonitoringGraph { remove(request.id) }
                    let graph = try ApplicationVolumeAudioGraph(
                        processObjects: objects, output: output, gain: request.gain, hardware: hardware, dispose: dispose
                    )
                    graphs[request.id] = graph
                    progress[request.id] = graph.renderProgress
                    playbackEvidence[request.id] = PlaybackEvidence(
                        progress: 0, lastSignalTime: lastSignalTime
                    )
                }
            } catch {
                if !keepMonitoringGraph { remove(request.id) }
                contexts[request.id] = context
                failures[request.id] = GraphFailure(
                    reason: error as? ApplicationVolumeFailure ?? .hardware(kAudioHardwareUnspecifiedError),
                    isMonitoring: request.gain == 1
                )
            }
        }
        return failures.mapValues(\.reason)
    }

    func releaseStalledGraphs() -> [String: ApplicationVolumeFailure] {
        var stalled: [String: ApplicationVolumeFailure] = [:]
        for (id, graph) in graphs where !graph.isMonitoring {
            let current = graph.renderProgress
            if progress[id] == current {
                stalled[id] = .hardware(kAudioHardwareNotRunningError)
            } else {
                progress[id] = current
            }
        }
        for (id, failure) in stalled {
            remove(id)
            failures[id] = GraphFailure(reason: failure, isMonitoring: false)
        }
        return stalled
    }

    func playingApplications(at now: TimeInterval) -> Set<String> {
        var playing: Set<String> = []
        for (id, graph) in graphs {
            let current = graph.inputSignalProgress
            var evidence = playbackEvidence[id]!
            if evidence.progress != current {
                evidence.progress = current
                evidence.lastSignalTime = now
            }
            playbackEvidence[id] = evidence
            if let lastSignalTime = evidence.lastSignalTime, now - lastSignalTime < 1 {
                playing.insert(id)
            }
        }
        return playing
    }

    func stop() {
        for id in Array(graphs.keys) { remove(id) }
        graphs.removeAll()
        failures.removeAll()
        contexts.removeAll()
        progress.removeAll()
    }

    private func remove(_ id: String) {
        graphs.removeValue(forKey: id)?.stop()
        progress[id] = nil
        playbackEvidence[id] = nil
    }
}

@MainActor
final class CoreAudioApplicationVolumeBackend: ApplicationVolumeMixing {
    typealias PropertyRegistration = @MainActor (
        AudioObjectID, AudioObjectPropertyAddress, @escaping AudioObjectPropertyListenerBlock, Bool
    ) -> OSStatus
    typealias WatchdogScheduling = @MainActor (
        DispatchQueue, @escaping @Sendable () -> Void
    ) -> @MainActor () -> Void
    typealias EventDelivery = @Sendable (@escaping @MainActor @Sendable () -> Void) -> Void

    var isSupported: Bool {
        if #available(macOS 14.4, *) { return true }
        return false
    }
    var onOutputChanged: (@MainActor () -> Void)?
    var onControlFailure: (@MainActor (String, ApplicationVolumeFailure) -> Void)?
    var onPlaybackChanged: (@MainActor (Set<String>) -> Void)?
    private(set) var playingApplications: Set<String> = []

    private let queue: DispatchQueue
    private let store: ApplicationVolumeGraphStore
    private let registerProperty: PropertyRegistration
    private let wakeNotifications: NotificationCenter
    private let scheduleWatchdog: WatchdogScheduling
    private let schedulePlaybackCheck: WatchdogScheduling
    private let now: @Sendable () -> TimeInterval
    private let deliver: EventDelivery
    private var isRunning = false
    private var generation: UInt64 = 0
    private var session: UInt64 = 0
    private var rebuildRequested = false
    private var listeners: [(AudioObjectID, AudioObjectPropertyAddress, AudioObjectPropertyListenerBlock)] = []
    private var observedOutput: AudioObjectID?
    private var observedProcesses: Set<AudioObjectID> = []
    private var wakeObserver: NSObjectProtocol?
    private var cancelWatchdog: (@MainActor () -> Void)?
    private var cancelPlaybackCheck: (@MainActor () -> Void)?

    init(
        hardware: any ApplicationVolumeAudioHardware = CoreAudioVolumeHardware(),
        queue: DispatchQueue = DispatchQueue(label: "dev.wzz.zisla.application-volume", qos: .userInitiated),
        dispose: @escaping @Sendable (@escaping @Sendable () -> Void) -> Void = {
            DispatchQueue.global(qos: .utility).async(execute: $0)
        },
        registerProperty: @escaping PropertyRegistration = { object, address, listener, adding in
            var address = address
            if adding { return AudioObjectAddPropertyListenerBlock(object, &address, .main, listener) }
            return AudioObjectRemovePropertyListenerBlock(object, &address, .main, listener)
        },
        wakeNotifications: NotificationCenter = NSWorkspace.shared.notificationCenter,
        scheduleWatchdog: @escaping WatchdogScheduling = { queue, event in
            let timer = DispatchSource.makeTimerSource(queue: queue)
            timer.schedule(deadline: .now() + 3, repeating: 3, leeway: .milliseconds(250))
            timer.setEventHandler(handler: event)
            timer.resume()
            return { timer.cancel() }
        },
        schedulePlaybackCheck: @escaping WatchdogScheduling = { queue, event in
            let timer = DispatchSource.makeTimerSource(queue: queue)
            timer.schedule(deadline: .now() + .milliseconds(200), repeating: .milliseconds(200),
                           leeway: .milliseconds(25))
            timer.setEventHandler(handler: event)
            timer.resume()
            return { timer.cancel() }
        },
        now: @escaping @Sendable () -> TimeInterval = { ProcessInfo.processInfo.systemUptime },
        deliver: @escaping EventDelivery = { event in Task { @MainActor in event() } }
    ) {
        self.queue = queue
        store = ApplicationVolumeGraphStore(hardware: hardware, dispose: dispose)
        self.registerProperty = registerProperty
        self.wakeNotifications = wakeNotifications
        self.scheduleWatchdog = scheduleWatchdog
        self.schedulePlaybackCheck = schedulePlaybackCheck
        self.now = now
        self.deliver = deliver
    }

    func start() {
        guard !isRunning, isSupported else { return }
        isRunning = true
        session &+= 1
        let currentSession = session
        for selector in [kAudioHardwarePropertyDefaultOutputDevice, kAudioHardwarePropertyServiceRestarted] {
            installListener(object: AudioObjectID(kAudioObjectSystemObject), selector: selector)
        }
        wakeObserver = wakeNotifications.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.outputChanged(session: currentSession) }
        }
    }

    func stop() {
        guard isRunning else { return }
        isRunning = false
        generation &+= 1
        cancelWatchdog?()
        cancelWatchdog = nil
        cancelPlaybackCheck?()
        cancelPlaybackCheck = nil
        for (object, address, listener) in listeners {
            _ = registerProperty(object, address, listener, false)
        }
        listeners.removeAll()
        observedOutput = nil
        observedProcesses.removeAll()
        if let wakeObserver { wakeNotifications.removeObserver(wakeObserver) }
        wakeObserver = nil
        rebuildRequested = false
        let store = self.store
        // This dedicated serial queue drains pending controls before playback is restored.
        queue.sync { store.stop() }
        playingApplications = []
    }

    func apply(
        _ requests: [ApplicationVolumeRequest], retryingApplication: String?,
        completion: @escaping @MainActor ([String: ApplicationVolumeFailure]) -> Void
    ) {
        guard isRunning else { return }
        generation &+= 1
        let currentGeneration = generation
        setWatchdogEnabled(false)
        setPlaybackCheckEnabled(false)
        let rebuild = rebuildRequested
        rebuildRequested = false
        let store = self.store
        let deliver = self.deliver
        let now = self.now
        queue.async { [weak self] in
            let failures = store.apply(requests, retryingApplication: retryingApplication, rebuild: rebuild)
            let hasGraphs = store.hasGraphs
            let hasControls = store.hasControls
            let output = store.output
            let processes = store.processObjects
            let playing = store.playingApplications(at: now())
            deliver {
                guard let self, self.isRunning, self.generation == currentGeneration else { return }
                self.observeOutput(output)
                self.observeProcesses(processes)
                self.setWatchdogEnabled(hasControls)
                self.setPlaybackCheckEnabled(hasGraphs)
                completion(failures)
                guard self.isRunning, self.generation == currentGeneration else { return }
                self.updatePlayback(playing)
            }
        }
    }

    private func outputChanged(session currentSession: UInt64) {
        guard isRunning, session == currentSession else { return }
        rebuildRequested = true
        onOutputChanged?()
    }

    private func observeOutput(_ output: AudioObjectID?) {
        guard output != observedOutput else { return }
        if let observedOutput {
            for (object, address, listener) in listeners where object == observedOutput {
                _ = registerProperty(object, address, listener, false)
            }
            listeners.removeAll { $0.0 == observedOutput }
        }
        observedOutput = output
        if let output {
            installListener(object: output, selector: kAudioDevicePropertyNominalSampleRate)
            installListener(object: output, selector: kAudioDevicePropertyDeviceIsAlive)
            installListener(object: output, selector: kAudioDevicePropertyStreams, scope: kAudioObjectPropertyScopeOutput)
            installListener(object: output, selector: kAudioDevicePropertyPreferredChannelsForStereo,
                            scope: kAudioObjectPropertyScopeOutput)
            installListener(object: output, selector: kAudioDevicePropertyStreamConfiguration,
                            scope: kAudioObjectPropertyScopeOutput)
        }
    }

    private func observeProcesses(_ processes: Set<AudioObjectID>) {
        let removed = observedProcesses.subtracting(processes)
        for (object, address, listener) in listeners where removed.contains(object) {
            _ = registerProperty(object, address, listener, false)
        }
        listeners.removeAll { removed.contains($0.0) }
        for process in processes.subtracting(observedProcesses) {
            installListener(object: process, selector: kAudioProcessPropertyDevices, scope: kAudioObjectPropertyScopeOutput)
        }
        observedProcesses = processes
    }

    private func installListener(
        object: AudioObjectID, selector: AudioObjectPropertySelector,
        scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal
    ) {
        let currentSession = session
        let listener: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            MainActor.assumeIsolated { self?.outputChanged(session: currentSession) }
        }
        let address = CoreAudioVolumeHardware.address(selector, scope: scope)
        if registerProperty(object, address, listener, true) == noErr {
            listeners.append((object, address, listener))
        }
    }

    private func setWatchdogEnabled(_ enabled: Bool) {
        guard enabled else {
            cancelWatchdog?()
            cancelWatchdog = nil
            return
        }
        guard cancelWatchdog == nil else { return }
        let store = self.store
        let deliver = self.deliver
        let currentGeneration = generation
        cancelWatchdog = scheduleWatchdog(queue) { [weak self] in
            deliver {
                guard let self, self.isRunning, self.generation == currentGeneration else { return }
                self.queue.async { [weak self] in
                    let stalled = store.releaseStalledGraphs()
                    let hasControls = store.hasControls
                    deliver {
                        guard let self, self.isRunning, self.generation == currentGeneration else { return }
                        for (id, failure) in stalled { self.onControlFailure?(id, failure) }
                        if !hasControls { self.setWatchdogEnabled(false) }
                    }
                }
            }
        }
    }

    private func updatePlayback(_ playing: Set<String>) {
        guard playing != playingApplications else { return }
        playingApplications = playing
        onPlaybackChanged?(playing)
    }

    private func setPlaybackCheckEnabled(_ enabled: Bool) {
        guard enabled else {
            cancelPlaybackCheck?()
            cancelPlaybackCheck = nil
            return
        }
        let store = self.store
        let deliver = self.deliver
        let now = self.now
        let currentGeneration = generation
        cancelPlaybackCheck = schedulePlaybackCheck(queue) { [weak self] in
            deliver {
                guard let self, self.isRunning, self.generation == currentGeneration else { return }
                self.queue.async { [weak self] in
                    let playing = store.playingApplications(at: now())
                    let hasGraphs = store.hasGraphs
                    deliver {
                        guard let self, self.isRunning, self.generation == currentGeneration else { return }
                        if !hasGraphs { self.setPlaybackCheckEnabled(false) }
                        self.updatePlayback(playing)
                    }
                }
            }
        }
    }
}
