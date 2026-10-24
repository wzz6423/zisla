import AppKit
import Combine
import CoreAudio
import Foundation
import ZislaCore

public struct ApplicationVolumeApplication: Identifiable, Equatable, Sendable {
    public let id: String
    public let name: String
    public let bundleIdentifier: String?
    public let iconData: Data?
    public var volume: Double
    public var isMuted: Bool
    public var isControlled: Bool

    public init(
        id: String, name: String, bundleIdentifier: String?, iconData: Data?,
        volume: Double, isMuted: Bool, isControlled: Bool
    ) {
        self.id = id
        self.name = name
        self.bundleIdentifier = bundleIdentifier
        self.iconData = iconData
        self.volume = volume
        self.isMuted = isMuted
        self.isControlled = isControlled
    }
}

struct ApplicationVolumeRequest: Equatable, Sendable {
    let id: String
    let processIdentifiers: [pid_t]
    let gain: Float
}

enum ApplicationVolumeFailure: Error, Equatable, Sendable {
    case permissionDenied
    case outputUnavailable
    case unsupportedFormat
    case hardware(OSStatus)

    var messageKey: String {
        switch self {
        case .permissionDenied: "请允许音频录制以调整应用音量"
        case .outputUnavailable: "当前音频输出设备不可用"
        case .unsupportedFormat: "当前音频输出格式不支持应用音量调整"
        case .hardware: "无法调整应用音量，已恢复原始输出"
        }
    }
}

@MainActor
protocol ApplicationVolumeSourceMonitoring: AnyObject {
    var sources: [AudioPlaybackSource] { get }
    var onSourcesChanged: (@MainActor ([AudioPlaybackSource]) -> Void)? { get set }
    func start()
    func stop()
}

extension AudioPlaybackMonitor: ApplicationVolumeSourceMonitoring {}

@MainActor
protocol ApplicationVolumeMixing: AnyObject {
    var isSupported: Bool { get }
    var onOutputChanged: (@MainActor () -> Void)? { get set }
    var onControlFailure: (@MainActor (String, ApplicationVolumeFailure) -> Void)? { get set }
    func start()
    func stop()
    func apply(
        _ requests: [ApplicationVolumeRequest], retryingApplication: String?,
        completion: @escaping @MainActor ([String: ApplicationVolumeFailure]) -> Void
    )
}

@MainActor
public final class ApplicationVolumeMixerService: ObservableObject {
    @Published public private(set) var applications: [ApplicationVolumeApplication] = []
    @Published public private(set) var errorMessage: String?

    public var isSupported: Bool { backend.isSupported }

    private struct Preference {
        var volume = 1.0
        var isMuted = false
    }

    private let monitor: any ApplicationVolumeSourceMonitoring
    private let backend: any ApplicationVolumeMixing
    private let ownProcessIdentifier: pid_t
    private let ownBundleIdentifier: String?
    private var preferences: [String: Preference] = [:]
    private var sources: [AudioPlaybackSource] = []
    private var isRunning = false
    private var generation: UInt64 = 0

    public convenience init() {
        self.init(
            monitor: AudioPlaybackMonitor(), backend: CoreAudioApplicationVolumeBackend(),
            ownProcessIdentifier: ProcessInfo.processInfo.processIdentifier,
            ownBundleIdentifier: Bundle.main.bundleIdentifier
        )
    }

    init(
        monitor: any ApplicationVolumeSourceMonitoring, backend: any ApplicationVolumeMixing,
        ownProcessIdentifier: pid_t, ownBundleIdentifier: String?
    ) {
        self.monitor = monitor
        self.backend = backend
        self.ownProcessIdentifier = ownProcessIdentifier
        self.ownBundleIdentifier = ownBundleIdentifier
        monitor.onSourcesChanged = { [weak self] in self?.updateSources($0) }
        backend.onOutputChanged = { [weak self] in self?.reconcile() }
        backend.onControlFailure = { [weak self] id, failure in
            guard let self, self.isRunning else { return }
            if let index = self.applications.firstIndex(where: { $0.id == id }) {
                self.applications[index].isControlled = false
                self.errorMessage = AppLocalization.text(failure.messageKey)
            }
        }
    }

    public func start() {
        guard !isRunning, isSupported else { return }
        isRunning = true
        backend.start()
        monitor.start()
        updateSources(monitor.sources)
    }

    public func stop() {
        guard isRunning else { return }
        isRunning = false
        generation &+= 1
        monitor.stop()
        backend.stop()
        preferences.removeAll()
        sources = []
        applications = []
        errorMessage = nil
    }

    public func setVolume(_ value: Double, for id: String) {
        guard isRunning, value.isFinite, applications.contains(where: { $0.id == id }) else { return }
        var preference = preferences[id] ?? Preference()
        preference.volume = min(1, max(0, value))
        preference.isMuted = false
        preferences[id] = preference
        reconcile(retryingApplication: id)
    }

    public func toggleMute(for id: String) {
        guard isRunning, applications.contains(where: { $0.id == id }) else { return }
        var preference = preferences[id] ?? Preference()
        preference.isMuted.toggle()
        preferences[id] = preference
        reconcile(retryingApplication: id)
    }

    private func updateSources(_ next: [AudioPlaybackSource]) {
        guard isRunning else { return }
        sources = next.compactMap { source in
            guard ownBundleIdentifier == nil || source.bundleIdentifier != ownBundleIdentifier else { return nil }
            var external = source
            external.processIdentifiers = source.processIdentifiers.filter { $0 != ownProcessIdentifier }
            return external.processIdentifiers.isEmpty ? nil : external
        }
        reconcile()
    }

    private func reconcile(retryingApplication: String? = nil) {
        guard isRunning else { return }
        generation &+= 1
        let currentGeneration = generation
        let controlled = Set(applications.filter(\.isControlled).map(\.id))
        applications = sources.map { source in
            let preference = preferences[source.id] ?? Preference()
            return ApplicationVolumeApplication(
                id: source.id, name: source.applicationName, bundleIdentifier: source.bundleIdentifier,
                iconData: source.iconData, volume: preference.volume, isMuted: preference.isMuted,
                isControlled: controlled.contains(source.id)
            )
        }
        let requests = sources.compactMap { source -> ApplicationVolumeRequest? in
            let preference = preferences[source.id] ?? Preference()
            guard preference.isMuted || preference.volume != 1 else { return nil }
            return ApplicationVolumeRequest(
                id: source.id, processIdentifiers: source.processIdentifiers,
                gain: preference.isMuted ? 0 : Float(preference.volume)
            )
        }
        let requestedIDs = Set(requests.map(\.id))
        backend.apply(requests, retryingApplication: retryingApplication) { [weak self] failures in
            guard let self, self.isRunning, self.generation == currentGeneration else { return }
            for index in self.applications.indices {
                let id = self.applications[index].id
                self.applications[index].isControlled = requestedIDs.contains(id) && failures[id] == nil
            }
            self.errorMessage = requests.lazy.compactMap { failures[$0.id] }.first.map {
                AppLocalization.text($0.messageKey)
            }
        }
    }
}
