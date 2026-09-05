import AppKit
@preconcurrency import AVFoundation
import Combine
import Foundation
import ZislaCore

/// Plays the locally installed macOS Accessibility Background Sounds without changing system settings.
@MainActor
public final class SystemBackgroundSoundService: ObservableObject {
    public enum DownloadState: Equatable, Sendable {
        case queued
        case downloading
        case failed(String)
    }

    @Published public private(set) var isPlaying = false
    /// The sound currently audible; nil while stopped. Drives the media header's label.
    @Published public private(set) var playingSound: SystemBackgroundSound?
    @Published public private(set) var installedSounds: [SystemBackgroundSoundCatalog.InstalledSound] = []
    @Published public private(set) var availableSounds: [SystemBackgroundSound] = SystemBackgroundSound.allCases
    @Published public private(set) var downloadingSounds: Set<SystemBackgroundSound> = []
    @Published public private(set) var downloadStates: [SystemBackgroundSound: DownloadState] = [:]
    public var onAutomaticStop: (@MainActor () -> Void)?

    private let assetRoots: [URL]
    private let downloadedAssetRoot: URL
    private let assetDownloader: SystemBackgroundSoundAssetDownloader
    private var playbackEngine: AVAudioEngine?
    private var playbackNode: AVAudioPlayerNode?
    private var playbackID: UUID?
    private var playbackFiles: [AVAudioFile] = []
    private var notificationObservers: [NSObjectProtocol] = []
    private var activeDownloadTask: Task<Void, Never>?
    private var downloadQueue: [SystemBackgroundSound] = []
    private var activeDownload: SystemBackgroundSound?
    private var pendingPlayback: Set<SystemBackgroundSound> = []
    private var selectedSound: SystemBackgroundSound = .rain
    private var stopsWhenUnused = true
    static let initialPlaybackCycleCount = 2

    public init(
        assetRoots: [URL] = SystemBackgroundSoundService.defaultAssetRoots,
        downloadedAssetRoot: URL = SystemBackgroundSoundService.defaultDownloadedAssetRoot,
        assetDownloader: SystemBackgroundSoundAssetDownloader = SystemBackgroundSoundAssetDownloader()
    ) {
        self.assetRoots = assetRoots
        self.downloadedAssetRoot = downloadedAssetRoot
        self.assetDownloader = assetDownloader
        refresh()
    }

    public static var defaultAssetRoots: [URL] {
        [
            URL(
                fileURLWithPath: "/System/Library/AssetsV2/com_apple_MobileAsset_ComfortSoundsAssets",
                isDirectory: true
            ),
            URL(fileURLWithPath: "/System/Library/Audio/ComfortSounds", isDirectory: true),
        ]
    }

    public static var defaultDownloadedAssetRoot: URL {
        AppPaths.applicationSupport.appendingPathComponent("BackgroundSounds", isDirectory: true)
    }

    public func refresh() {
        var sounds: [SystemBackgroundSoundCatalog.InstalledSound] = []
        for root in assetRoots + [downloadedAssetRoot] {
            for sound in SystemBackgroundSoundCatalog.installedSounds(in: root) {
                guard !sounds.contains(where: { $0.name == sound.name }) else { continue }
                sounds.append(sound)
            }
        }
        installedSounds = sounds

        let installedNames = Set(sounds.map(\.name))
        let manifestNames = SystemBackgroundSoundCatalog.manifestSoundNames()
        let availableNames = manifestNames.isEmpty
            ? installedNames
            : manifestNames.union(installedNames)
        availableSounds = availableNames.isEmpty
            ? SystemBackgroundSound.allCases
            : SystemBackgroundSound.allCases.filter { availableNames.contains($0.rawValue) }
    }

    public func isInstalled(_ sound: SystemBackgroundSound) -> Bool {
        installedSounds.contains { $0.name == sound.rawValue }
    }

    public func isDownloading(_ sound: SystemBackgroundSound) -> Bool {
        downloadingSounds.contains(sound)
    }

    public func downloadState(for sound: SystemBackgroundSound) -> DownloadState? {
        downloadStates[sound]
    }

    public func apply(
        sound: SystemBackgroundSound,
        enabled: Bool,
        stopsWhenUnused: Bool
    ) {
        let soundChanged = selectedSound != sound
        selectSound(sound)
        self.stopsWhenUnused = stopsWhenUnused

        guard enabled else {
            stop()
            return
        }

        if soundChanged, isPlaying {
            stop()
        }

        guard isInstalled(sound) else {
            playOrDownload(sound: sound)
            return
        }

        if !isPlaying {
            _ = play(sound: sound)
        }
    }

    /// Starts playback immediately when the asset exists; otherwise downloads it and starts playback when ready.
    public func playOrDownload(sound: SystemBackgroundSound) {
        selectSound(sound)
        refresh()
        if isInstalled(sound) {
            pendingPlayback.remove(sound)
            _ = play(sound: sound)
            return
        }
        requestDownload(sound: sound, playWhenReady: true)
    }

    /// Downloads a sound into the user cache without opening System Settings.
    public func requestDownload(sound: SystemBackgroundSound, playWhenReady: Bool = false) {
        selectSound(sound)
        refresh()
        if isInstalled(sound) {
            if playWhenReady { _ = play(sound: sound) }
            return
        }

        if playWhenReady {
            pendingPlayback.insert(sound)
        } else {
            pendingPlayback.remove(sound)
        }

        guard activeDownload != sound, !downloadQueue.contains(sound) else { return }

        if activeDownload != nil {
            downloadQueue.append(sound)
            downloadingSounds.insert(sound)
            downloadStates[sound] = .queued
            return
        }

        startDownload(sound)
    }

    private func startDownload(_ sound: SystemBackgroundSound) {
        activeDownload = sound
        downloadingSounds.insert(sound)
        downloadStates[sound] = .downloading
        let downloader = assetDownloader
        let destination = downloadedAssetRoot
        activeDownloadTask = Task { [weak self] in
            do {
                _ = try await downloader.download(soundName: sound.rawValue, to: destination)
                self?.finishDownload(sound, error: nil)
            } catch is CancellationError {
                self?.finishDownload(sound, error: nil)
            } catch {
                self?.finishDownload(sound, error: error.localizedDescription)
            }
        }
    }

    public func cancelDownload(sound: SystemBackgroundSound) {
        pendingPlayback.remove(sound)

        if let index = downloadQueue.firstIndex(of: sound) {
            downloadQueue.remove(at: index)
            downloadingSounds.remove(sound)
            downloadStates[sound] = nil
            return
        }

        guard activeDownload == sound else { return }

        activeDownloadTask?.cancel()
    }

    public func cancelAllDownloads() {
        activeDownloadTask?.cancel()
        activeDownloadTask = nil
        downloadQueue.removeAll()
        activeDownload = nil
        downloadingSounds.removeAll()
        downloadStates.removeAll()
        pendingPlayback.removeAll()
    }

    @discardableResult
    public func toggle() -> Bool {
        if isPlaying {
            stop()
            return false
        }
        return play(sound: selectedSound)
    }

    public func select(_ sound: SystemBackgroundSound) {
        let wasPlaying = isPlaying
        selectSound(sound)
        guard wasPlaying else { return }
        stop()
        _ = play(sound: sound)
    }

    @discardableResult
    public func play(sound: SystemBackgroundSound) -> Bool {
        guard let installed = installedSounds.first(where: { $0.name == sound.rawValue }),
              !installed.audioURLs.isEmpty else {
            playingSound = nil
            isPlaying = false
            return false
        }

        stop()
        do {
            let files = try installed.audioURLs.map(AVAudioFile.init(forReading:))
            guard let format = files.first?.processingFormat else { return false }

            let engine = AVAudioEngine()
            let node = AVAudioPlayerNode()
            engine.attach(node)
            engine.connect(node, to: engine.mainMixerNode, format: format)

            let playbackID = UUID()
            playbackEngine = engine
            playbackNode = node
            self.playbackID = playbackID
            playbackFiles = files
            for _ in 0..<Self.initialPlaybackCycleCount {
                schedulePlaybackCycle(playbackID: playbackID)
            }

            engine.prepare()
            try engine.start()
            // Playing before the engine sees an IO cycle throws an uncatchable ObjC exception that
            // aborts the process; the output node's lastRenderTime is the only signal that rendering
            // actually started.
            guard engine.isRunning, engine.outputNode.lastRenderTime != nil else {
                stop()
                return false
            }
            node.play()
        } catch {
            stop()
            return false
        }

        selectSound(sound)
        playingSound = sound
        isPlaying = true
        return true
    }

    private func schedulePlaybackCycle(playbackID: UUID) {
        guard self.playbackID == playbackID,
              let playbackNode,
              !playbackFiles.isEmpty else { return }

        for (index, file) in playbackFiles.enumerated() {
            let completesCycle = index == playbackFiles.count - 1
            playbackNode.scheduleFile(
                file,
                at: nil,
                completionCallbackType: .dataRendered,
                completionHandler: completesCycle ? { @Sendable [weak self] _ in
                    Task { @MainActor [weak self] in
                        self?.schedulePlaybackCycle(playbackID: playbackID)
                    }
                } : nil
            )
        }
    }

    public func stop() {
        playbackID = nil
        if playbackEngine?.outputNode.lastRenderTime != nil {
            playbackNode?.stop()
        }
        playbackEngine?.stop()
        playbackNode = nil
        playbackEngine = nil
        playbackFiles.removeAll()
        playingSound = nil
        isPlaying = false
    }

    private func finishDownload(_ sound: SystemBackgroundSound, error: String?) {
        guard activeDownload == sound else { return }

        activeDownloadTask = nil
        downloadingSounds.remove(sound)
        activeDownload = nil

        if let error {
            pendingPlayback.remove(sound)
            downloadStates[sound] = .failed(error)
            processNextInQueue()
            return
        }

        downloadStates[sound] = nil
        refresh()
        let shouldPlay = pendingPlayback.remove(sound) != nil

        processNextInQueue()

        if shouldPlay {
            _ = play(sound: sound)
        }
    }

    private func processNextInQueue() {
        guard activeDownload == nil, !downloadQueue.isEmpty else { return }
        let next = downloadQueue.removeFirst()
        startDownload(next)
    }

    private func selectSound(_ sound: SystemBackgroundSound) {
        guard selectedSound != sound else { return }
        selectedSound = sound
        pendingPlayback.removeAll()
    }

    public func startLifecycleMonitoring() {
        guard notificationObservers.isEmpty else { return }

        let distributedCenter = DistributedNotificationCenter.default()
        for name in [
            Notification.Name("com.apple.screenIsLocked"),
            Notification.Name("com.apple.screensaver.didstart"),
        ] {
            notificationObservers.append(
                distributedCenter.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                    Task { @MainActor [weak self] in
                        self?.stopForInactivity()
                    }
                }
            )
        }

        let workspaceCenter = NSWorkspace.shared.notificationCenter
        notificationObservers.append(
            workspaceCenter.addObserver(
                forName: NSWorkspace.willSleepNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.stopForInactivity()
                }
            }
        )
        notificationObservers.append(
            workspaceCenter.addObserver(
                forName: NSWorkspace.screensDidSleepNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.stopForInactivity()
                }
            }
        )
    }

    public func stopLifecycleMonitoring() {
        guard !notificationObservers.isEmpty else { return }
        let distributedCenter = DistributedNotificationCenter.default()
        let workspaceCenter = NSWorkspace.shared.notificationCenter
        for observer in notificationObservers {
            distributedCenter.removeObserver(observer)
            workspaceCenter.removeObserver(observer)
        }
        notificationObservers.removeAll()
    }

    private func stopForInactivity() {
        guard stopsWhenUnused else { return }
        let wasActive = isPlaying || activeDownload != nil || !downloadQueue.isEmpty
        cancelAllDownloads()
        if isPlaying { stop() }
        guard wasActive else { return }
        onAutomaticStop?()
    }

}
