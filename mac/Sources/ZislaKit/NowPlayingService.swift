import AppKit
import Combine
import Darwin
import Dispatch
import Foundation
import ZislaCore

public enum NowPlayingPlaybackMode: String, CaseIterable, Equatable, Sendable {
  case sequential
  case repeatOne
  case random

  var mediaRemoteRepeatMode: Int {
    self == .repeatOne ? 2 : 1
  }

  var mediaRemoteShuffleMode: Int {
    self == .random ? 3 : 1
  }
}

public enum NowPlayingFavoriteControl: Equatable, Sendable {
  case like
  case wishList
}

public struct NowPlayingSnapshot: Equatable, Sendable {
  public var title: String
  public var artist: String
  public var album: String?
  public var artworkData: Data?
  public var duration: Double?
  public var elapsedTime: Double?
  public var timestamp: Date?
  public var isPlaying: Bool
  public var isVideo: Bool
  public var sourceApplication: String?
  public var sourceBundleIdentifier: String?
  public var sourcePID: pid_t?
  public var sourceIconData: Data?
  public var supportsControls: Bool
  public var lyrics: SyncedLyrics?
  public var playbackMode: NowPlayingPlaybackMode?
  public var supportsPlaybackModeControl: Bool
  public var isFavorite: Bool?
  public var favoriteControl: NowPlayingFavoriteControl?
  /// Playback mode is approximate — filled in by app specialisation rather than reported precisely by MediaRemote,
  /// so the UI should show a cycle button rather than a precise selection menu.
  public var playbackModeIsApproximate: Bool

  public init(
    title: String,
    artist: String,
    album: String?,
    artworkData: Data?,
    duration: Double?,
    elapsedTime: Double?,
    timestamp: Date? = nil,
    isPlaying: Bool,
    isVideo: Bool = false,
    sourceApplication: String? = nil,
    sourceBundleIdentifier: String? = nil,
    sourcePID: pid_t? = nil,
    sourceIconData: Data? = nil,
    supportsControls: Bool = true,
    lyrics: SyncedLyrics? = nil,
    playbackMode: NowPlayingPlaybackMode? = nil,
    supportsPlaybackModeControl: Bool? = nil,
    isFavorite: Bool? = nil,
    favoriteControl: NowPlayingFavoriteControl? = nil,
    playbackModeIsApproximate: Bool = false
  ) {
    self.title = title
    self.artist = artist
    self.album = album
    self.artworkData = artworkData
    self.duration = duration
    self.elapsedTime = elapsedTime
    self.timestamp = timestamp
    self.isPlaying = isPlaying
    self.isVideo = isVideo
    self.sourceApplication = sourceApplication
    self.sourceBundleIdentifier = sourceBundleIdentifier
    self.sourcePID = sourcePID
    self.sourceIconData = sourceIconData
    self.supportsControls = supportsControls
    self.lyrics = lyrics
    self.playbackMode = playbackMode
    self.supportsPlaybackModeControl = supportsPlaybackModeControl ?? (playbackMode != nil)
    self.isFavorite = isFavorite
    self.favoriteControl = favoriteControl
    self.playbackModeIsApproximate = playbackModeIsApproximate
  }

  public func elapsedTime(at date: Date) -> Double? {
    guard let elapsedTime else { return nil }
    guard isPlaying, let timestamp else { return elapsedTime }
    let advanced = elapsedTime + max(0, date.timeIntervalSince(timestamp))
    if let duration, duration > 0 { return min(advanced, duration) }
    return advanced
  }
}

@MainActor
public final class NowPlayingService: ObservableObject {
  enum RemotePlaybackState: Equatable, Sendable {
    case unavailable
    case pending
    case playing
    case paused
  }

  private enum RemoteInfoState {
    case unavailable
    case pending
    case available
    case empty
  }

  private struct ControlIdentity: Equatable {
    var title: String
    var artist: String
    var duration: Double?
    var source: String?

    init(_ snapshot: NowPlayingSnapshot) {
      title = snapshot.title
      artist = snapshot.artist
      duration = snapshot.duration
      source =
        snapshot.sourcePID.map { "pid:\($0)" }
        ?? snapshot.sourceBundleIdentifier.map { "bundle:\($0)" }
    }
  }

  private struct ArtworkRefreshIdentity: Equatable {
    var title: String
    var artist: String
    var duration: Double?
    var source: String?

    init(_ snapshot: NowPlayingSnapshot) {
      title = LyricsService.normalized(snapshot.title)
      artist = LyricsService.normalized(snapshot.artist)
      duration = snapshot.duration
      source =
        snapshot.sourcePID.map { "pid:\($0)" }
        ?? snapshot.sourceBundleIdentifier.map { "bundle:\($0)" }
    }

    func matches(_ snapshot: NowPlayingSnapshot) -> Bool {
      guard title == LyricsService.normalized(snapshot.title),
        artist == LyricsService.normalized(snapshot.artist),
        Self.durationsMatch(duration, snapshot.duration)
      else { return false }
      let snapshotSource =
        snapshot.sourcePID.map { "pid:\($0)" }
        ?? snapshot.sourceBundleIdentifier.map { "bundle:\($0)" }
      return source == nil || snapshotSource == nil || source == snapshotSource
    }

    private static func durationsMatch(_ lhs: Double?, _ rhs: Double?) -> Bool {
      guard let lhs, let rhs, lhs > 0, rhs > 0 else { return true }
      return abs(lhs - rhs) <= 2
    }
  }

  private struct TimedControlOverride<Value: Equatable> {
    var identity: ControlIdentity
    var value: Value
    var expiresAt: Date
  }

  public enum Command: Int, Sendable {
    case play = 0
    case pause = 1
    case togglePlayPause = 2
    case next = 4
    case previous = 5
    case likeTrack = 21
    case addTrackToWishList = 107
    case removeTrackFromWishList = 108
  }

  @Published public private(set) var snapshot: NowPlayingSnapshot?
  @Published public private(set) var isAvailable = false

  private typealias InfoCallback = @convention(block) (NSDictionary?) -> Void
  private typealias BoolCallback = @convention(block) (Bool) -> Void
  private typealias PIDCallback = @convention(block) (pid_t) -> Void
  private typealias GetInfoFunction = @convention(c) (DispatchQueue, InfoCallback) -> Void
  private typealias GetPlayingFunction = @convention(c) (DispatchQueue, BoolCallback) -> Void
  private typealias GetPIDFunction = @convention(c) (DispatchQueue, PIDCallback) -> Void
  private typealias RegisterFunction = @convention(c) (DispatchQueue) -> Void
  private typealias SendCommandFunction = @convention(c) (Int, NSDictionary?) -> Bool
  private typealias SetModeFunction = @convention(c) (Int) -> Void
  private typealias SetElapsedTimeFunction = @convention(c) (Double) -> Void

  private let audioMonitor = AudioPlaybackMonitor()
  private let lyricsService = LyricsService()
  private let adapterClient = MediaRemoteAdapterClient()
  private let specialist = MediaAppSpecialist.shared
  private var activeProfile: MediaAppProfile?
  private var framework: UnsafeMutableRawPointer?
  private var getInfo: GetInfoFunction?
  private var getPlaying: GetPlayingFunction?
  private var getPID: GetPIDFunction?
  private var registerNotifications: RegisterFunction?
  private var sendCommandFunction: SendCommandFunction?
  private var setRepeatModeFunction: SetModeFunction?
  private var setShuffleModeFunction: SetModeFunction?
  private var setElapsedTimeFunction: SetElapsedTimeFunction?
  private var observers: [NSObjectProtocol] = []
  private var remoteSnapshot: NowPlayingSnapshot?
  private var remotePlaybackState: RemotePlaybackState = .unavailable
  private var remoteInfoState: RemoteInfoState = .unavailable
  private var remotePID: pid_t?
  private var remotePIDPending = false
  private var refreshStartingPID: pid_t?
  private var refreshGeneration: UInt64 = 0
  private var lyricsTask: Task<Void, Never>?
  private var artworkRefreshTask: Task<Void, Never>?
  private var artworkRefreshIdentity: ArtworkRefreshIdentity?
  private var lyricsIdentity: LyricsTrackIdentity?
  public private(set) var resolvedLyrics: SyncedLyrics?
  /// Full artist name resolved from the lyrics API (MediaRemote usually returns only the first artist).
  private var resolvedArtist: String?
  private var playbackModeOverride: TimedControlOverride<NowPlayingPlaybackMode>?
  private var playbackStateOverride: TimedControlOverride<Bool>?
  private var favoriteOverride: TimedControlOverride<Bool>?
  private var specialistFavoriteIdentity: ControlIdentity?
  private var specialistFavoriteState: Bool?
  private var playbackModeOverrideExpirationTask: Task<Void, Never>?
  private var playbackStateOverrideExpirationTask: Task<Void, Never>?
  private var favoriteOverrideExpirationTask: Task<Void, Never>?
  private var specialistFavoriteRefreshTask: Task<Void, Never>?
  private var usesAdapter = false
  private var isRunning = false
  private var spectrumMonitoringEnabled = false
  private var spectrumVisualizationEnabled = false
  private var spectrumCancellable: AnyCancellable?
  private var systemAudioIsAudible = false
  private var adapterPlaybackMode: NowPlayingPlaybackMode?
  private var playbackModeCommandGeneration: UInt64 = 0
  private var preferredSource: MediaSourcePreference = .automatic

  private let controlOverrideLifetime: TimeInterval = 2

  public init() {}

  public func setPreferredSource(_ preference: MediaSourcePreference) {
    guard preferredSource != preference else { return }
    preferredSource = preference
    playbackModeOverride = nil
    playbackStateOverride = nil
    favoriteOverride = nil
    specialistFavoriteIdentity = nil
    specialistFavoriteState = nil
    playbackModeOverrideExpirationTask?.cancel()
    playbackModeOverrideExpirationTask = nil
    playbackStateOverrideExpirationTask?.cancel()
    playbackStateOverrideExpirationTask = nil
    favoriteOverrideExpirationTask?.cancel()
    favoriteOverrideExpirationTask = nil
    specialistFavoriteRefreshTask?.cancel()
    specialistFavoriteRefreshTask = nil
    activeProfile = nil
    resolveSnapshot()
  }

  public func start() {
    guard !isRunning else { return }
    isRunning = true
    if ProcessInfo.processInfo.environment["ZISLA_VISUAL_MEDIA_FIXTURE"] == "1" {
      let artwork = ProcessInfo.processInfo.environment["ZISLA_VISUAL_MEDIA_ARTWORK"]
        .flatMap { try? Data(contentsOf: URL(fileURLWithPath: $0)) }
      snapshot = NowPlayingSnapshot(
        title: "遇上你之前的我",
        artist: "Gareth.T",
        album: "遇上你之前的我",
        artworkData: artwork,
        duration: 215,
        elapsedTime: 73,
        timestamp: .now,
        isPlaying: true,
        supportsControls: true,
        lyrics: SyncedLyrics(lines: [
          .init(time: 0, text: "从不想太多 就简单的"),
          .init(time: 70, text: "总说无所谓的我"),
          .init(time: 80, text: "何谓窝囊 漂泊"),
        ]),
        playbackMode: .repeatOne,
        isFavorite: true,
        favoriteControl: .wishList
      )
      isAvailable = true
      return
    }
    guard framework == nil, !usesAdapter else { return }
    let path = "/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote"
    if let handle = dlopen(path, RTLD_LAZY | RTLD_LOCAL) {
      framework = handle
      getInfo = loadSymbol("MRMediaRemoteGetNowPlayingInfo", from: handle)
      getPlaying = loadSymbol("MRMediaRemoteGetNowPlayingApplicationIsPlaying", from: handle)
      getPID = loadSymbol("MRMediaRemoteGetNowPlayingApplicationPID", from: handle)
      registerNotifications = loadSymbol(
        "MRMediaRemoteRegisterForNowPlayingNotifications",
        from: handle
      )
      sendCommandFunction = loadSymbol("MRMediaRemoteSendCommand", from: handle)
      setRepeatModeFunction = loadSymbol("MRMediaRemoteSetRepeatMode", from: handle)
      setShuffleModeFunction = loadSymbol("MRMediaRemoteSetShuffleMode", from: handle)
      setElapsedTimeFunction = loadSymbol("MRMediaRemoteSetElapsedTime", from: handle)
      registerNotifications?(DispatchQueue.main)
      registerMediaRemoteObservers()
    }

    audioMonitor.onSourcesChanged = { [weak self] _ in
      if self?.usesAdapter != true { self?.refreshRemoteInfo() }
      self?.resolveSnapshot()
    }
    usesAdapter = adapterClient.start(
      onEvent: { [weak self] event in
        self?.consumeAdapterEvent(event)
      },
      onTermination: { [weak self] in
        self?.adapterDidTerminate()
      }
    )
    remotePlaybackState =
      usesAdapter
      ? .pending
      : (getPlaying == nil ? .unavailable : .pending)
    remoteInfoState = usesAdapter ? .pending : .unavailable
    remotePIDPending = usesAdapter ? false : getPID != nil
    audioMonitor.start()
    spectrumCancellable = AudioSpectrumService.shared.$isAudible
      .removeDuplicates()
      .sink { [weak self] audible in
        Task { @MainActor [weak self] in
          guard let self else { return }
          self.systemAudioIsAudible = audible
          self.audioMonitor.refresh()
          self.resolveSnapshot()
        }
      }
    updateSpectrumMonitoring()
    isAvailable = usesAdapter || getInfo != nil || audioMonitor.isSupported
    if usesAdapter {
      audioMonitor.refresh()
      resolveSnapshot()
    } else {
      refresh()
    }
  }

  public func setSpectrumMonitoringEnabled(_ enabled: Bool) {
    guard spectrumMonitoringEnabled != enabled else { return }
    spectrumMonitoringEnabled = enabled
    updateSpectrumMonitoring()
  }

  public func setSpectrumVisualizationEnabled(_ enabled: Bool) {
    guard spectrumVisualizationEnabled != enabled else { return }
    spectrumVisualizationEnabled = enabled
    updateSpectrumMonitoring()
  }

  public func stop() {
    isRunning = false
    spectrumMonitoringEnabled = false
    spectrumVisualizationEnabled = false
    for observer in observers {
      NotificationCenter.default.removeObserver(observer)
    }
    observers.removeAll()
    audioMonitor.onSourcesChanged = nil
    audioMonitor.stop()
    spectrumCancellable?.cancel()
    spectrumCancellable = nil
    systemAudioIsAudible = false
    AudioSpectrumService.shared.stop()
    usesAdapter = false
    adapterClient.stop()
    if let framework { dlclose(framework) }
    framework = nil
    getInfo = nil
    getPlaying = nil
    getPID = nil
    registerNotifications = nil
    sendCommandFunction = nil
    setRepeatModeFunction = nil
    setShuffleModeFunction = nil
    setElapsedTimeFunction = nil
    remoteSnapshot = nil
    remotePID = nil
    remotePlaybackState = .unavailable
    remoteInfoState = .unavailable
    remotePIDPending = false
    refreshStartingPID = nil
    lyricsTask?.cancel()
    lyricsTask = nil
    artworkRefreshTask?.cancel()
    artworkRefreshTask = nil
    artworkRefreshIdentity = nil
    lyricsIdentity = nil
    resolvedLyrics = nil
    resolvedArtist = nil
    playbackModeOverride = nil
    playbackStateOverride = nil
    favoriteOverride = nil
    specialistFavoriteIdentity = nil
    specialistFavoriteState = nil
    playbackModeOverrideExpirationTask?.cancel()
    playbackModeOverrideExpirationTask = nil
    playbackStateOverrideExpirationTask?.cancel()
    playbackStateOverrideExpirationTask = nil
    favoriteOverrideExpirationTask?.cancel()
    favoriteOverrideExpirationTask = nil
    specialistFavoriteRefreshTask?.cancel()
    specialistFavoriteRefreshTask = nil
    adapterPlaybackMode = nil
    playbackModeCommandGeneration &+= 1
    activeProfile = nil
    snapshot = nil
    isAvailable = false
  }

  private func updateSpectrumMonitoring() {
    guard isRunning,
      ProcessInfo.processInfo.environment["ZISLA_VISUAL_MEDIA_FIXTURE"] != "1"
    else { return }
    AudioSpectrumService.shared.setVisualizationEnabled(spectrumVisualizationEnabled)
    if spectrumMonitoringEnabled {
      AudioSpectrumService.shared.startMonitoring()
    } else {
      AudioSpectrumService.shared.stop()
    }
  }

  public func refresh() {
    audioMonitor.refresh()
    if !usesAdapter { refreshRemoteInfo() }
    resolveSnapshot()
  }

  @discardableResult
  public func send(_ command: Command) -> Bool {
    guard let current = snapshot, current.supportsControls else { return false }
    let sent =
      if let profile = activeProfile,
        profile.prefersAccessibilityControls,
        profile.supportsPlaybackControls,
        command.rawValue <= Command.previous.rawValue,
        specialist.sendPlaybackCommand(
          command,
          pid: current.sourcePID,
          bundleIdentifier: current.sourceBundleIdentifier
        ) == true {
        true
      } else if usesAdapter, command.rawValue <= Command.previous.rawValue {
        adapterClient.run(["send", "\(command.rawValue)"])
      } else if let direct = sendCommandFunction?(command.rawValue, nil), direct {
        direct
      } else if let profile = activeProfile,
        profile.supportsPlaybackControls,
        command.rawValue <= Command.previous.rawValue,
        let specialized = specialist.sendPlaybackCommand(
          command,
          pid: current.sourcePID,
          bundleIdentifier: current.sourceBundleIdentifier
        ) {
        specialized
      } else {
        false
      }
    guard sent else { return false }

    if let value = Self.optimisticPlaybackValue(after: command, current: current.isPlaying) {
      playbackStateOverride = TimedControlOverride(
        identity: ControlIdentity(current),
        value: value,
        expiresAt: .now.addingTimeInterval(controlOverrideLifetime)
      )
      schedulePlaybackStateOverrideExpiration()
      remotePlaybackState = value ? .playing : .paused
      if var remote = remoteSnapshot {
        remote.isPlaying = value
        remote.timestamp = .now
        remoteSnapshot = remote
      }
      resolveSnapshot()
    }
    return true
  }

  @discardableResult
  public func setPlaybackMode(_ mode: NowPlayingPlaybackMode) -> Bool {
    guard let current = snapshot, current.supportsControls else { return false }
    if usesAdapter {
      let commands = Self.playbackModeAdapterCommands(mode)
      playbackModeCommandGeneration &+= 1
      let generation = playbackModeCommandGeneration
      let enqueued = adapterClient.runSequence(commands) { [weak self] succeeded in
        guard let self,
          self.playbackModeCommandGeneration == generation,
          !succeeded
        else { return }
        self.adapterPlaybackMode = nil
        self.playbackModeOverride = nil
        self.resolveSnapshot()
      }
      guard enqueued else { return false }
      adapterPlaybackMode = mode
    } else if let setRepeatModeFunction, let setShuffleModeFunction {
      setRepeatModeFunction(mode.mediaRemoteRepeatMode)
      setShuffleModeFunction(mode.mediaRemoteShuffleMode)
    } else if specialist.setPlaybackMode(
      mode,
      pid: current.sourcePID,
      bundleIdentifier: current.sourceBundleIdentifier
    ) != true {
      return false
    }
    playbackModeOverride = TimedControlOverride(
      identity: ControlIdentity(current),
      value: mode,
      expiresAt: .now.addingTimeInterval(controlOverrideLifetime)
    )
    schedulePlaybackModeOverrideExpiration()
    resolveSnapshot()
    return true
  }

  /// Cycles to the next playback mode in sequence when the player does not report a precise mode.
  @discardableResult
  public func cyclePlaybackMode() -> Bool {
    guard let current = snapshot, current.supportsControls else { return false }
    let fallbackMode = activeProfile?.defaultPlaybackMode ?? .sequential
    let nextMode = Self.nextPlaybackMode(after: current.playbackMode ?? fallbackMode)
    if let profile = activeProfile,
      profile.prefersAccessibilityControls,
      profile.supportsPlaybackModeCycle,
      specialist.cyclePlaybackMode(
        pid: current.sourcePID,
        bundleIdentifier: current.sourceBundleIdentifier,
        currentMode: current.playbackMode ?? fallbackMode
      )
    {
      playbackModeOverride = TimedControlOverride(
        identity: ControlIdentity(current),
        value: nextMode,
        expiresAt: .now.addingTimeInterval(controlOverrideLifetime)
      )
      schedulePlaybackModeOverrideExpiration()
      resolveSnapshot()
      return true
    }
    return setPlaybackMode(nextMode)
  }

  @discardableResult
  public func toggleFavorite() -> Bool {
    guard let current = snapshot, current.supportsControls,
      let control = current.favoriteControl
    else { return false }

    let command = Self.favoriteCommand(
      isFavorite: current.isFavorite == true,
      control: control
    )
    let sent =
      if let profile = activeProfile,
        profile.prefersAccessibilityControls,
        profile.supportsFavorite,
        specialist.toggleFavorite(
          pid: current.sourcePID,
          bundleIdentifier: current.sourceBundleIdentifier
        ) {
        true
      } else if usesAdapter {
        adapterClient.run(["send", "\(command.rawValue)"])
      } else if let direct = sendCommandFunction?(command.rawValue, nil), direct {
        direct
      } else if let profile = activeProfile, profile.supportsFavorite {
        specialist.toggleFavorite(
          pid: current.sourcePID,
          bundleIdentifier: current.sourceBundleIdentifier
        )
      } else {
        false
      }
    guard sent else { return false }
    favoriteOverride = TimedControlOverride(
      identity: ControlIdentity(current),
      value: current.isFavorite != true,
      expiresAt: .now.addingTimeInterval(controlOverrideLifetime)
    )
    if activeProfile?.supportsFavoriteStateRead == true {
      specialistFavoriteIdentity = ControlIdentity(current)
      specialistFavoriteState = current.isFavorite != true
      scheduleSpecialistFavoriteRefresh(for: current)
    }
    scheduleFavoriteOverrideExpiration()
    resolveSnapshot()
    return true
  }

  @discardableResult
  public func seek(to seconds: Double) -> Bool {
    guard let current = snapshot,
      current.supportsControls,
      let duration = current.duration,
      duration > 0
    else { return false }

    let elapsedTime = Self.clampedSeekTime(seconds, duration: duration)
    if usesAdapter {
      let microseconds = Int64((elapsedTime * 1_000_000).rounded())
      guard adapterClient.run(["seek", "\(microseconds)"]) else { return false }
    } else {
      guard let setElapsedTimeFunction else { return false }
      setElapsedTimeFunction(elapsedTime)
    }
    if var remote = remoteSnapshot {
      remote.elapsedTime = elapsedTime
      remote.timestamp = .now
      remoteSnapshot = remote
    }
    resolveSnapshot()
    return true
  }

  @discardableResult
  public func openSourceApplication() -> Bool {
    guard let current = snapshot else { return false }
    let applications = NSWorkspace.shared.runningApplications
    guard
      let index = Self.sourceApplicationIndex(
        sourcePID: current.sourcePID,
        sourceBundleIdentifier: current.sourceBundleIdentifier,
        candidates: applications.map {
          (pid: $0.processIdentifier, bundleIdentifier: $0.bundleIdentifier)
        }
      )
    else { return false }
    let application = applications[index]
    application.unhide()
    guard let applicationURL = application.bundleURL else {
      return application.activate(options: [.activateAllWindows])
    }
    let configuration = NSWorkspace.OpenConfiguration()
    configuration.activates = true
    NSWorkspace.shared.openApplication(at: applicationURL, configuration: configuration)
    return true
  }

  nonisolated static func parse(_ dictionary: NSDictionary?) -> NowPlayingSnapshot? {
    guard let dictionary else { return nil }
    let title = text(dictionary["kMRMediaRemoteNowPlayingInfoTitle"])
    let album = text(dictionary["kMRMediaRemoteNowPlayingInfoAlbum"])
    let sourceBundleIdentifier =
      text(
        dictionary["kMRMediaRemoteNowPlayingInfoParentApplicationBundleIdentifier"]
      ) ?? text(dictionary["kMRMediaRemoteNowPlayingInfoApplicationBundleIdentifier"])
    let mediaType = text(dictionary["kMRMediaRemoteNowPlayingInfoMediaType"])
    let isVideo = isVideoMedia(
      mediaType: mediaType,
      isVideosApp: boolean(dictionary["kMRMediaRemoteNowPlayingInfoIsVideosApp"])
    )
    let artist =
      text(dictionary["kMRMediaRemoteNowPlayingInfoArtist"])
      ?? (isVideo ? nil : album)
    guard title != nil || artist != nil else { return nil }
    let rate = number(dictionary["kMRMediaRemoteNowPlayingInfoPlaybackRate"])
    let isInWishList = boolean(dictionary["kMRMediaRemoteNowPlayingInfoIsInWishList"])
    let isLiked = boolean(dictionary["kMRMediaRemoteNowPlayingInfoIsLiked"])
    let supportsWishList = boolean(
      dictionary["kMRMediaRemoteNowPlayingInfoSupportsWishlisting"]
    )
    let supportsLike = boolean(dictionary["kMRMediaRemoteNowPlayingInfoSupportsIsLiked"])
    let favoriteControl: NowPlayingFavoriteControl? =
      if isInWishList != nil {
        .wishList
      } else if isLiked != nil {
        .like
      } else if supportsWishList == true {
        .wishList
      } else if supportsLike == true {
        .like
      } else {
        nil
      }
    let isFavorite: Bool? =
      switch favoriteControl {
      case .wishList: isInWishList
      case .like: isLiked
      case nil: nil
      }
    return NowPlayingSnapshot(
      title: title ?? "未知媒体",
      artist: artist ?? "",
      album: album,
      artworkData: dictionary["kMRMediaRemoteNowPlayingInfoArtworkData"] as? Data,
      duration: number(dictionary["kMRMediaRemoteNowPlayingInfoDuration"]),
      elapsedTime: number(dictionary["kMRMediaRemoteNowPlayingInfoElapsedTime"]),
      timestamp: dictionary["kMRMediaRemoteNowPlayingInfoTimestamp"] as? Date,
      isPlaying: (rate ?? 0) > 0,
      isVideo: isVideo,
      sourceBundleIdentifier: sourceBundleIdentifier,
      supportsControls: true,
      lyrics: SyncedLyrics.parse(
        dictionary["kMRMediaRemoteNowPlayingInfoLyrics"] as? String
      ),
      playbackMode: playbackMode(
        repeatMode: integer(dictionary["kMRMediaRemoteNowPlayingInfoRepeatMode"]),
        shuffleMode: integer(dictionary["kMRMediaRemoteNowPlayingInfoShuffleMode"])
      ),
      isFavorite: isFavorite,
      favoriteControl: favoriteControl
    )
  }

  nonisolated static func parseAdapter(
    _ payload: MediaRemoteAdapterPayload
  ) -> NowPlayingSnapshot? {
    let title = text(payload.title)
    let album = text(payload.album)
    let sourceBundleIdentifier =
      payload.parentApplicationBundleIdentifier
      ?? payload.bundleIdentifier
    let isVideo = isVideoMedia(
      mediaType: payload.mediaType,
      isVideosApp: payload.isVideosApp
    )
    let artist = text(payload.artist) ?? (isVideo ? nil : album)
    guard title != nil || artist != nil else { return nil }
    let favoriteControl: NowPlayingFavoriteControl? =
      if payload.isInWishList != nil
        || payload.supportsWishlisting == true
      {
        .wishList
      } else if payload.isLiked != nil || payload.supportsIsLiked == true {
        .like
      } else {
        nil
      }
    let isFavorite: Bool? =
      switch favoriteControl {
      case .wishList: payload.isInWishList
      case .like: payload.isLiked
      case nil: nil
      }
    let timestamp = payload.timestamp.flatMap {
      ISO8601DateFormatter().date(from: $0)
    }
    return NowPlayingSnapshot(
      title: title ?? "未知媒体",
      artist: artist ?? "",
      album: album,
      artworkData: payload.artworkData.flatMap {
        Data(base64Encoded: $0, options: .ignoreUnknownCharacters)
      },
      duration: payload.duration,
      elapsedTime: payload.elapsedTime,
      timestamp: timestamp,
      isPlaying: payload.playing ?? ((payload.playbackRate ?? 0) > 0),
      isVideo: isVideo,
      sourceBundleIdentifier: sourceBundleIdentifier,
      sourcePID: payload.processIdentifier,
      supportsControls: true,
      playbackMode: playbackMode(
        repeatMode: payload.repeatMode,
        shuffleMode: payload.shuffleMode
      ),
      isFavorite: isFavorite,
      favoriteControl: favoriteControl
    )
  }

  nonisolated static func mergingMetadata(
    _ update: NowPlayingSnapshot,
    previous: NowPlayingSnapshot?
  ) -> NowPlayingSnapshot {
    guard let previous,
      LyricsService.normalized(update.title) == LyricsService.normalized(previous.title),
      LyricsService.normalized(update.artist) == LyricsService.normalized(previous.artist),
      durationsIdentifySameTrack(update.duration, previous.duration)
    else { return update }

    var merged = update
    merged.artworkData = update.artworkData ?? previous.artworkData
    merged.album = update.album ?? previous.album
    if !sourceChanged(update, previous) {
      merged.sourceIconData = update.sourceIconData ?? previous.sourceIconData
      merged.isVideo = update.isVideo || previous.isVideo
      merged.sourceApplication = update.sourceApplication ?? previous.sourceApplication
      merged.sourceBundleIdentifier =
        update.sourceBundleIdentifier
        ?? previous.sourceBundleIdentifier
    }
    return merged
  }

  /// Only trusts the system MediaRemote media-type field; does not infer video identity from the app's identity.
  nonisolated static func isVideoMedia(
    mediaType: String?,
    isVideosApp: Bool? = nil
  ) -> Bool {
    if isVideosApp == true { return true }
    guard let mediaType else { return false }
    let normalized =
      mediaType
      .trimmingCharacters(in: .whitespacesAndNewlines)
      .lowercased()
    guard !normalized.isEmpty else { return false }
    if normalized.contains("video") { return true }
    return false
  }

  nonisolated static func playbackMode(
    repeatMode: Int?,
    shuffleMode: Int?
  ) -> NowPlayingPlaybackMode? {
    if shuffleMode == 3 { return .random }
    if repeatMode == 2 { return .repeatOne }
    if repeatMode != nil || shuffleMode != nil { return .sequential }
    return nil
  }

  nonisolated static func favoriteCommand(
    isFavorite: Bool,
    control: NowPlayingFavoriteControl
  ) -> Command {
    switch control {
    case .like:
      return .likeTrack
    case .wishList:
      return isFavorite ? .removeTrackFromWishList : .addTrackToWishList
    }
  }

  nonisolated static func optimisticPlaybackValue(
    after command: Command,
    current: Bool
  ) -> Bool? {
    switch command {
    case .play: true
    case .pause: false
    case .togglePlayPause: !current
    case .next, .previous, .likeTrack, .addTrackToWishList, .removeTrackFromWishList: nil
    }
  }

  nonisolated static func clampedSeekTime(_ seconds: Double, duration: Double) -> Double {
    min(max(seconds, 0), max(duration, 0))
  }

  nonisolated static func nextPlaybackMode(
    after mode: NowPlayingPlaybackMode
  ) -> NowPlayingPlaybackMode {
    switch mode {
    case .sequential: .repeatOne
    case .repeatOne: .random
    case .random: .sequential
    }
  }

  nonisolated static func matchesPreferredSource(
    _ sourceBundleIdentifier: String?,
    preference: MediaSourcePreference
  ) -> Bool {
    preference.matches(bundleIdentifier: sourceBundleIdentifier)
  }

  nonisolated static func sourceApplicationIndex(
    sourcePID: pid_t?,
    sourceBundleIdentifier: String?,
    candidates: [(pid: pid_t, bundleIdentifier: String?)]
  ) -> Int? {
    if let sourcePID,
      let index = candidates.firstIndex(where: { $0.pid == sourcePID })
    {
      return index
    }
    guard let sourceBundleIdentifier else { return nil }
    return candidates.firstIndex { $0.bundleIdentifier == sourceBundleIdentifier }
  }

  nonisolated static func preferredSource(
    from sources: [AudioPlaybackSource],
    remotePID: pid_t?
  ) -> AudioPlaybackSource? {
    if let remotePID,
      let matched = sources.first(where: { $0.processIdentifiers.contains(remotePID) })
    {
      return matched
    }
    return sources.first(where: \.isFrontmost) ?? sources.first
  }

  /// Core Audio is authoritative for the app that is currently emitting sound when it reports one unambiguous source.
  nonisolated static func audioSourceCorrectingRemoteAttribution(
    from sources: [AudioPlaybackSource],
    remotePID: pid_t?,
    remoteBundleIdentifier: String?
  ) -> AudioPlaybackSource? {
    guard sources.count == 1, let source = sources.first else { return nil }

    if let remoteBundleIdentifier, let sourceBundleIdentifier = source.bundleIdentifier {
      return remoteBundleIdentifier == sourceBundleIdentifier ? nil : source
    }
    if let remotePID {
      return source.processIdentifiers.contains(remotePID) ? nil : source
    }
    return nil
  }

  /// When MediaRemote is stuck on a paused session, select the active source from other audible Core Audio sources.
  nonisolated static func preferredAudioFallbackSource(
    from sources: [AudioPlaybackSource],
    remotePID: pid_t?,
    playbackState: RemotePlaybackState,
    remotePIDPending: Bool
  ) -> AudioPlaybackSource? {
    let allowed = sources.filter {
      audioFallbackIsAllowed(
        source: $0,
        remotePID: remotePID,
        playbackState: playbackState,
        remotePIDPending: remotePIDPending
      )
    }
    return allowed.first(where: \.isFrontmost) ?? allowed.first
  }

  nonisolated static func playbackModeAdapterCommands(
    _ mode: NowPlayingPlaybackMode
  ) -> [[String]] {
    switch mode {
    case .sequential: [["shuffle", "1"], ["repeat", "1"]]
    case .repeatOne: [["shuffle", "1"], ["repeat", "2"]]
    case .random: [["repeat", "1"], ["shuffle", "3"]]
    }
  }

  /// When the app has published a MediaRemote state, use it as the source of truth; fall back to Core Audio only when no remote metadata is available.
  nonisolated static func remotePlaybackIsActive(
    snapshot: NowPlayingSnapshot?,
    playbackState: RemotePlaybackState
  ) -> Bool {
    guard let snapshot else { return false }
    return switch playbackState {
    case .playing: true
    case .unavailable: snapshot.isPlaying
    case .pending, .paused: false
    }
  }

  nonisolated static func audioFallbackIsAllowed(
    source: AudioPlaybackSource,
    remotePID: pid_t?,
    playbackState: RemotePlaybackState,
    remotePIDPending: Bool
  ) -> Bool {
    switch playbackState {
    case .unavailable:
      return true
    case .pending:
      return false
    case .playing:
      return true
    case .paused:
      guard !remotePIDPending, let remotePID else { return false }
      return !source.processIdentifiers.contains(remotePID)
    }
  }

  nonisolated static func shouldRetainSnapshotAfterEmptyRemoteInfo(
    playbackState: RemotePlaybackState,
    previousPID: pid_t?,
    currentPID: pid_t?,
    activeProcessIdentifiers: Set<pid_t> = [],
    previousBundleIdentifier: String? = nil,
    activeBundleIdentifiers: Set<String> = []
  ) -> Bool {
    guard playbackState == .paused else { return false }
    if let previousPID,
      previousPID == currentPID || activeProcessIdentifiers.contains(previousPID)
    {
      return true
    }
    if let previousBundleIdentifier,
      activeBundleIdentifiers.contains(previousBundleIdentifier)
    {
      return true
    }
    return false
  }

  private func registerMediaRemoteObservers() {
    let names = [
      "kMRMediaRemoteNowPlayingInfoDidChangeNotification",
      "kMRMediaRemoteNowPlayingApplicationDidChangeNotification",
      "kMRMediaRemoteNowPlayingApplicationIsPlayingDidChangeNotification",
    ]
    observers = names.map { name in
      NotificationCenter.default.addObserver(
        forName: Notification.Name(name),
        object: nil,
        queue: .main
      ) { [weak self] _ in
        Task { @MainActor [weak self] in self?.refresh() }
      }
    }
  }

  private func refreshRemoteInfo() {
    guard !usesAdapter else { return }
    refreshGeneration &+= 1
    let generation = refreshGeneration
    refreshStartingPID = remotePID
    remotePlaybackState = getPlaying == nil ? .unavailable : .pending
    remoteInfoState = getInfo == nil ? .unavailable : .pending
    remotePIDPending = getPID != nil

    if let getInfo {
      let callback: InfoCallback = { [weak self] dictionary in
        let value = Self.parse(dictionary)
        Task { @MainActor [weak self] in
          guard let self, self.refreshGeneration == generation else { return }
          self.remoteInfoState = value == nil ? .empty : .available
          if let value {
            self.remoteSnapshot = Self.mergingMetadata(
              value,
              previous: self.remoteSnapshot
            )
          }
          self.reconcileEmptyRemoteInfo()
          self.resolveSnapshot()
        }
      }
      getInfo(.main, callback)
    } else {
      remoteSnapshot = nil
    }

    if let getPlaying {
      let callback: BoolCallback = { [weak self] value in
        Task { @MainActor [weak self] in
          guard let self, self.refreshGeneration == generation else { return }
          self.remotePlaybackState = value ? .playing : .paused
          self.reconcileEmptyRemoteInfo()
          self.resolveSnapshot()
        }
      }
      getPlaying(.main, callback)
    }

    if let getPID {
      let callback: PIDCallback = { [weak self] value in
        Task { @MainActor [weak self] in
          guard let self, self.refreshGeneration == generation else { return }
          self.remotePID = value > 0 ? value : nil
          self.remotePIDPending = false
          self.reconcileEmptyRemoteInfo()
          self.resolveSnapshot()
        }
      }
      getPID(.main, callback)
    }
  }

  private func consumeAdapterEvent(_ event: MediaRemoteAdapterEvent) {
    remotePIDPending = false
    guard var value = Self.parseAdapter(event.payload) else {
      remoteInfoState = .empty
      remotePlaybackState = .paused
      remotePID = nil
      remoteSnapshot = nil
      resolveSnapshot()
      return
    }

    if let playbackMode = value.playbackMode {
      adapterPlaybackMode = playbackMode
    } else {
      value.playbackMode = adapterPlaybackMode
    }
    remoteInfoState = .available
    remotePlaybackState = value.isPlaying ? .playing : .paused
    remotePID = value.sourcePID
    remoteSnapshot = Self.mergingMetadata(value, previous: remoteSnapshot)
    scheduleArtworkRefreshIfNeeded()
    resolveSnapshot()
  }

  private func adapterDidTerminate() {
    guard usesAdapter else { return }
    artworkRefreshTask?.cancel()
    artworkRefreshTask = nil
    artworkRefreshIdentity = nil
    usesAdapter = false
    remotePlaybackState = getPlaying == nil ? .unavailable : .pending
    remoteInfoState = getInfo == nil ? .unavailable : .pending
    remotePIDPending = getPID != nil
    refreshRemoteInfo()
    resolveSnapshot()
  }

  private func scheduleArtworkRefreshIfNeeded() {
    guard usesAdapter,
      let remoteSnapshot,
      remoteSnapshot.artworkData == nil
    else {
      artworkRefreshTask?.cancel()
      artworkRefreshTask = nil
      artworkRefreshIdentity = nil
      return
    }

    let identity = ArtworkRefreshIdentity(remoteSnapshot)
    guard artworkRefreshIdentity != identity else { return }
    artworkRefreshTask?.cancel()
    artworkRefreshIdentity = identity
    artworkRefreshTask = Task { [weak self] in
      for delay in [Duration.milliseconds(250), .milliseconds(700), .seconds(1)] {
        try? await Task.sleep(for: delay)
        guard !Task.isCancelled, let self,
          self.usesAdapter,
          self.artworkRefreshIdentity == identity,
          let current = self.remoteSnapshot,
          current.artworkData == nil,
          identity.matches(current)
        else { return }
        _ = self.adapterClient.fetchNowPlayingInfo { [weak self] payload in
          self?.consumeArtworkRefresh(payload, expectedIdentity: identity)
        }
      }
      guard let self, self.artworkRefreshIdentity == identity else { return }
      self.artworkRefreshTask = nil
    }
  }

  private func consumeArtworkRefresh(
    _ payload: MediaRemoteAdapterPayload?,
    expectedIdentity: ArtworkRefreshIdentity
  ) {
    guard usesAdapter,
      let payload,
      let update = Self.parseAdapter(payload),
      expectedIdentity.matches(update),
      let previous = remoteSnapshot,
      expectedIdentity.matches(previous)
    else { return }
    remoteSnapshot = Self.mergingMetadata(update, previous: previous)
    scheduleArtworkRefreshIfNeeded()
    resolveSnapshot()
  }

  private func reconcileEmptyRemoteInfo() {
    guard remoteInfoState == .empty,
      remotePlaybackState != .pending,
      !remotePIDPending
    else { return }
    let activeProcessIdentifiers = Set(
      audioMonitor.sources.flatMap(\.processIdentifiers)
    )
    let activeBundleIdentifiers = Set(
      audioMonitor.sources.compactMap(\.bundleIdentifier)
    )
    guard
      Self.shouldRetainSnapshotAfterEmptyRemoteInfo(
        playbackState: remotePlaybackState,
        previousPID: refreshStartingPID ?? remoteSnapshot?.sourcePID,
        currentPID: remotePID,
        activeProcessIdentifiers: activeProcessIdentifiers,
        previousBundleIdentifier: remoteSnapshot?.sourceBundleIdentifier,
        activeBundleIdentifiers: activeBundleIdentifiers
      )
    else {
      remoteSnapshot = nil
      return
    }
  }

  private func resolveSnapshot() {
    let sources = audioMonitor.sources
    let remoteSource = Self.preferredSource(from: sources, remotePID: remotePID)
    let preferredSources = sources.filter {
      Self.matchesPreferredSource($0.bundleIdentifier, preference: preferredSource)
    }
    if var remote = remoteSnapshot {
      guard remotePlaybackState != .pending else {
        return
      }
      remote.isPlaying = Self.remotePlaybackIsActive(
        snapshot: remote,
        playbackState: remotePlaybackState
      )
      if let source = Self.audioSourceCorrectingRemoteAttribution(
        from: sources,
        remotePID: remotePID,
        remoteBundleIdentifier: remote.sourceBundleIdentifier
      ) {
        remote.sourceApplication = source.applicationName
        remote.sourceBundleIdentifier = source.bundleIdentifier
        remote.sourcePID = source.processIdentifiers.first
        remote.sourceIconData = Self.applicationIconData(
          source: source,
          bundleIdentifier: source.bundleIdentifier,
          processIdentifier: source.processIdentifiers.first
        )
      } else {
        remote.sourceApplication = remote.sourceApplication ?? remoteSource?.applicationName
        remote.sourceBundleIdentifier =
          remote.sourceBundleIdentifier
          ?? remoteSource?.bundleIdentifier
        remote.sourcePID = remote.sourcePID ?? remotePID ?? remoteSource?.processIdentifiers.first
        remote.sourceIconData =
          remote.sourceIconData
          ?? Self.applicationIconData(
            source: remoteSource,
            bundleIdentifier: remote.sourceBundleIdentifier,
            processIdentifier: remote.sourcePID
          )
      }
      guard Self.matchesPreferredSource(
        remote.sourceBundleIdentifier,
        preference: preferredSource
      ) else {
        activeProfile = nil
        snapshot = resolvedAudioFallbackSnapshot(from: preferredSources)
        return
      }
      applyControlOverrides(to: &remote)
      if !remote.isPlaying,
        systemAudioIsAudible,
        let activeSource = Self.preferredAudioFallbackSource(
          from: preferredSources,
          remotePID: remotePID,
          playbackState: remotePlaybackState,
          remotePIDPending: remotePIDPending
        )
      {
        activeProfile = nil
        snapshot = Self.audioFallbackSnapshot(for: activeSource)
        return
      }
      if var stored = remoteSnapshot {
        stored.sourceApplication = remote.sourceApplication
        stored.sourceBundleIdentifier = remote.sourceBundleIdentifier
        stored.sourcePID = remote.sourcePID
        stored.sourceIconData = remote.sourceIconData
        stored.isVideo = remote.isVideo
        remoteSnapshot = stored
      }
      applySpecialization(to: &remote)
      applyLyrics(to: &remote)
      snapshot = remote
      return
    }

    activeProfile = nil
    guard let fallback = resolvedAudioFallbackSnapshot(from: preferredSources) else {
      snapshot = nil
      return
    }
    snapshot = fallback
  }

  private func resolvedAudioFallbackSnapshot(
    from sources: [AudioPlaybackSource]
  ) -> NowPlayingSnapshot? {
    guard systemAudioIsAudible,
      let source = Self.preferredAudioFallbackSource(
        from: sources,
        remotePID: remotePID,
        playbackState: remotePlaybackState,
        remotePIDPending: remotePIDPending
      )
    else { return nil }
    return Self.audioFallbackSnapshot(for: source)
  }

  private static func applicationIconData(
    source: AudioPlaybackSource?,
    bundleIdentifier: String?,
    processIdentifier: pid_t?
  ) -> Data? {
    if let iconData = source?.iconData { return iconData }
    if let processIdentifier,
      let icon = NSRunningApplication(processIdentifier: processIdentifier)?.icon
    {
      let cacheKey = bundleIdentifier ?? "pid:\(processIdentifier)"
      return ApplicationIconDataCache.data(for: icon, cacheKey: cacheKey)
    }
    guard let bundleIdentifier,
      let applicationURL = NSWorkspace.shared.urlForApplication(
        withBundleIdentifier: bundleIdentifier
      )
    else { return nil }
    let icon = NSWorkspace.shared.icon(forFile: applicationURL.path)
    return ApplicationIconDataCache.data(for: icon, cacheKey: bundleIdentifier)
  }

  nonisolated private static func audioFallbackSnapshot(
    for source: AudioPlaybackSource
  ) -> NowPlayingSnapshot {
    // Core Audio can only confirm that the app is producing audio; do not fabricate a video identity from that alone.
    return NowPlayingSnapshot(
      title: source.applicationName,
      artist: "正在播放音频",
      album: nil,
      artworkData: nil,
      duration: nil,
      elapsedTime: nil,
      isPlaying: true,
      isVideo: false,
      sourceApplication: source.applicationName,
      sourceBundleIdentifier: source.bundleIdentifier,
      sourcePID: source.processIdentifiers.first,
      sourceIconData: source.iconData,
      supportsControls: false
    )
  }

  private func applyControlOverrides(to snapshot: inout NowPlayingSnapshot) {
    let identity = ControlIdentity(snapshot)
    let now = Date.now

    if let playbackStateOverride {
      if playbackStateOverride.identity != identity
        || playbackStateOverride.expiresAt <= now
        || snapshot.isPlaying == playbackStateOverride.value
      {
        self.playbackStateOverride = nil
        playbackStateOverrideExpirationTask?.cancel()
        playbackStateOverrideExpirationTask = nil
      } else {
        snapshot.isPlaying = playbackStateOverride.value
      }
    }
    if let playbackModeOverride {
      if playbackModeOverride.identity != identity
        || playbackModeOverride.expiresAt <= now
        || snapshot.playbackMode == playbackModeOverride.value
      {
        self.playbackModeOverride = nil
        playbackModeOverrideExpirationTask?.cancel()
        playbackModeOverrideExpirationTask = nil
      } else {
        snapshot.playbackMode = playbackModeOverride.value
      }
    }
    if let favoriteOverride {
      if favoriteOverride.identity != identity
        || favoriteOverride.expiresAt <= now
        || snapshot.isFavorite == favoriteOverride.value
      {
        self.favoriteOverride = nil
        favoriteOverrideExpirationTask?.cancel()
        favoriteOverrideExpirationTask = nil
      } else {
        snapshot.isFavorite = favoriteOverride.value
      }
    }
  }

  /// When MediaRemote does not report favorite/playback-mode capabilities,
  /// fill in the control-capability flags from the app specialisation profile so the UI can display the corresponding buttons.
  private func applySpecialization(to snapshot: inout NowPlayingSnapshot) {
    let profile = specialist.profile(for: snapshot.sourceBundleIdentifier)
    activeProfile = profile
    guard let profile else { return }

    if !profile.supportsFavorite {
      snapshot.favoriteControl = nil
      snapshot.isFavorite = nil
    } else {
      if profile.supportsFavoriteStateRead {
        let identity = ControlIdentity(snapshot)
        if specialistFavoriteIdentity != identity {
          specialistFavoriteIdentity = identity
          specialistFavoriteState = specialist.favoriteState(
            pid: snapshot.sourcePID,
            bundleIdentifier: snapshot.sourceBundleIdentifier
          )
        }
        if let specialistFavoriteState {
          snapshot.favoriteControl = profile.favoriteControl
          snapshot.isFavorite = specialistFavoriteState
        } else {
          snapshot.favoriteControl = profile.favoriteControl
        }
      } else {
        snapshot.favoriteControl = profile.favoriteControl
      }
    }
    if profile.supportsPlaybackModeSet, snapshot.playbackMode == nil {
      snapshot.playbackMode = profile.defaultPlaybackMode
      snapshot.supportsPlaybackModeControl = true
    }
    if profile.supportsPlaybackModeCycle {
      snapshot.playbackMode = snapshot.playbackMode ?? profile.defaultPlaybackMode
      snapshot.supportsPlaybackModeControl = true
      snapshot.playbackModeIsApproximate = true
    }
  }

  private func scheduleSpecialistFavoriteRefresh(for snapshot: NowPlayingSnapshot) {
    specialistFavoriteRefreshTask?.cancel()
    let identity = ControlIdentity(snapshot)
    specialistFavoriteRefreshTask = Task { @MainActor [weak self] in
      try? await Task.sleep(for: .milliseconds(350))
      guard !Task.isCancelled,
        let self,
        ControlIdentity(self.snapshot ?? snapshot) == identity,
        self.activeProfile?.supportsFavoriteStateRead == true
      else { return }
      self.specialistFavoriteState = self.specialist.favoriteState(
        pid: self.snapshot?.sourcePID,
        bundleIdentifier: self.snapshot?.sourceBundleIdentifier
      )
      self.resolveSnapshot()
    }
  }

  private func schedulePlaybackModeOverrideExpiration() {
    playbackModeOverrideExpirationTask?.cancel()
    let lifetime = controlOverrideLifetime
    playbackModeOverrideExpirationTask = Task { @MainActor [weak self] in
      try? await Task.sleep(for: .seconds(lifetime))
      guard !Task.isCancelled else { return }
      self?.resolveSnapshot()
    }
  }

  private func schedulePlaybackStateOverrideExpiration() {
    playbackStateOverrideExpirationTask?.cancel()
    let lifetime = controlOverrideLifetime
    playbackStateOverrideExpirationTask = Task { @MainActor [weak self] in
      try? await Task.sleep(for: .seconds(lifetime))
      guard !Task.isCancelled else { return }
      self?.resolveSnapshot()
    }
  }

  private func scheduleFavoriteOverrideExpiration() {
    favoriteOverrideExpirationTask?.cancel()
    let lifetime = controlOverrideLifetime
    favoriteOverrideExpirationTask = Task { @MainActor [weak self] in
      try? await Task.sleep(for: .seconds(lifetime))
      guard !Task.isCancelled else { return }
      self?.resolveSnapshot()
    }
  }

  func applyLyrics(to snapshot: inout NowPlayingSnapshot) {
    guard
      let identity = LyricsTrackIdentity(
        title: snapshot.title,
        artist: snapshot.artist,
        duration: snapshot.duration
      )
    else {
      lyricsTask?.cancel()
      lyricsTask = nil
      lyricsIdentity = nil
      resolvedLyrics = nil
      resolvedArtist = nil
      return
    }

    if let embedded = snapshot.lyrics {
      lyricsTask?.cancel()
      lyricsTask = nil
      lyricsIdentity = identity
      resolvedLyrics = embedded
      return
    }

    if lyricsIdentity == identity {
      snapshot.lyrics = resolvedLyrics
      if let resolvedArtist, !resolvedArtist.isEmpty {
        snapshot.artist = resolvedArtist
      }
      return
    }

    lyricsTask?.cancel()
    lyricsIdentity = identity
    resolvedLyrics = nil
    resolvedArtist = nil
    let title = snapshot.title
    let artist = snapshot.artist
    let duration = snapshot.duration
    lyricsTask = Task { [weak self, lyricsService] in
      let result = await lyricsService.lyrics(
        title: title,
        artist: artist,
        duration: duration
      )
      guard !Task.isCancelled, let self, self.lyricsIdentity == identity else { return }
      self.resolvedLyrics = result.lyrics
      self.resolvedArtist = result.artistName
      self.lyricsTask = nil
      self.resolveSnapshot()
    }
  }

  nonisolated private static func number(_ value: Any?) -> Double? {
    (value as? NSNumber)?.doubleValue
  }

  nonisolated private static func integer(_ value: Any?) -> Int? {
    (value as? NSNumber)?.intValue
  }

  nonisolated private static func boolean(_ value: Any?) -> Bool? {
    (value as? NSNumber)?.boolValue
  }

  nonisolated private static func text(_ value: Any?) -> String? {
    guard let value = value as? String else { return nil }
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? nil : trimmed
  }

  nonisolated private static func durationsIdentifySameTrack(
    _ lhs: Double?,
    _ rhs: Double?
  ) -> Bool {
    guard let lhs, let rhs, lhs > 0, rhs > 0 else { return true }
    return abs(lhs - rhs) <= 2
  }

  nonisolated private static func sourceChanged(
    _ update: NowPlayingSnapshot,
    _ previous: NowPlayingSnapshot
  ) -> Bool {
    if let updateBundleIdentifier = update.sourceBundleIdentifier,
      let previousBundleIdentifier = previous.sourceBundleIdentifier
    {
      return updateBundleIdentifier != previousBundleIdentifier
    }
    guard update.sourceBundleIdentifier == nil,
      previous.sourceBundleIdentifier == nil,
      let updatePID = update.sourcePID,
      let previousPID = previous.sourcePID
    else { return false }
    return updatePID != previousPID
  }

  private func loadSymbol<T>(_ name: String, from handle: UnsafeMutableRawPointer) -> T? {
    guard let symbol = dlsym(handle, name) else { return nil }
    return unsafeBitCast(symbol, to: T.self)
  }
}
