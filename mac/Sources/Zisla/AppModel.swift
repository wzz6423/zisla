import AppKit
import Combine
import Foundation
import UniformTypeIdentifiers
import ZislaCore
import ZislaKit

enum IslandModule: String, CaseIterable, Identifiable {
  case dashboard
  case shelf
  case clipboard
  case aiMonitor
  case download
  case agenda
  case mail
  case quickNotes
  case pdf
  case toolbox
  case system
  case battery
  case lockScreen

  var id: Self { self }

  var title: String {
    switch self {
    case .dashboard: "首页"
    case .shelf: "中转"
    case .clipboard: "剪贴板"
    case .aiMonitor: "AI 监控"
    case .download: "下载"
    case .agenda: "日程"
    case .mail: "邮件"
    case .quickNotes: "随记"
    case .pdf: "PDF"
    case .toolbox: "小工具"
    case .system: "系统"
    case .battery: "电池"
    case .lockScreen: "锁屏"
    }
  }

  var symbol: String {
    switch self {
    case .dashboard: "rectangle.grid.2x2.fill"
    case .shelf: "tray.full.fill"
    case .clipboard: "clipboard"
    case .aiMonitor: "chart.xyaxis.line"
    case .download: "arrow.down.circle.fill"
    case .agenda: "calendar"
    case .mail: "envelope.fill"
    case .quickNotes: "note.text"
    case .pdf: "doc.viewfinder"
    case .toolbox: "wrench.and.screwdriver.fill"
    case .system: "gauge.with.dots.needle.67percent"
    case .battery: "battery.100percent"
    case .lockScreen: "lock.display"
    }
  }

  var layout: IslandModuleLayout {
    switch self {
    case .dashboard:
      .standard
    case .aiMonitor:
      .ai
    case .system:
      .system
    case .battery:
      .battery
    case .clipboard:
      .clipboard
    case .shelf:
      .shelf
    case .toolbox:
      .toolbox
    case .pdf:
      .pdf
    case .download:
      .download
    case .agenda:
      .agenda
    case .lockScreen:
      .standard
    case .mail:
      .mail
    case .quickNotes:
      .notes
    }
  }
}

extension IslandModule {
  /// Formerly a private IslandRootView extension; AppModel also needs it to fall back from a disabled selected module after settings changes.
  func isEnabled(in settings: FeatureSettings) -> Bool {
    switch self {
    case .dashboard: true
    case .shelf: settings.fileShelfEnabled
    case .clipboard: settings.clipboardHistoryEnabled
    case .aiMonitor: settings.aiProgressEnabled
    case .download: settings.downloaderEnabled
    case .agenda: settings.calendarEnabled || settings.weatherEnabled
    case .mail: settings.mailEnabled
    case .quickNotes: settings.quickNotesEnabled
    case .pdf: settings.pdfToolsEnabled
    case .toolbox: settings.toolboxEnabled
    case .system: settings.systemMonitorEnabled
    case .battery: settings.batteryMonitorEnabled
    case .lockScreen: settings.lockScreenInfoEnabled
    }
  }
}

struct IslandModuleLayout: Equatable {
  let islandSize: CGSize
  let panelSize: CGSize

  /// Returns the same layout with both widths replaced. Voice recording follows the collapsed
  /// pill's overflow width (notch + wings on notched screens) instead of a fixed constant.
  func matchingWidth(_ width: CGFloat) -> IslandModuleLayout {
    IslandModuleLayout(
      islandSize: CGSize(width: width, height: islandSize.height),
      panelSize: CGSize(width: width, height: panelSize.height)
    )
  }

  /// Standard island width must accommodate the full toolbar row (module icons + system monitor strip + action buttons).
  /// Too narrow causes the HStack to overflow at center and clips the first icon behind the island surface, so widened to 660.
  /// panelSize is widened in sync to preserve 200pt shoulder clearance for shelf/share.
  static let standard = IslandModuleLayout(
    islandSize: CGSize(width: 660, height: 340),
    panelSize: CGSize(width: 860, height: 344)
  )
  private static let expandedChromeHeight: CGFloat = 121
  private static let moduleVerticalInsets = IslandSurfaceGeometry.moduleInset * 2
  private static let panelHeightAllowance: CGFloat = 4
  private static let panelSideClearance: CGFloat = 200
  static let batteryMinimumContentHeight: CGFloat = 0
  static let batteryMaximumContentHeight: CGFloat = 430

  /// Fixed-height modules size the surface to their rendered content instead of inheriting
  /// the standard panel's unused vertical space.
  private static func compactModule(
    contentHeight: CGFloat,
    islandWidth: CGFloat = 660
  ) -> IslandModuleLayout {
    let islandHeight = expandedChromeHeight + contentHeight + moduleVerticalInsets
    return IslandModuleLayout(
      islandSize: CGSize(width: islandWidth, height: islandHeight),
      panelSize: CGSize(width: islandWidth + panelSideClearance, height: islandHeight + panelHeightAllowance)
    )
  }

  static let toolbox = compactModule(contentHeight: 136)
  static let download = compactModule(contentHeight: 138)
  static let agenda = compactModule(contentHeight: 160)
  /// PDF tools need the full-width toolbar plus enough vertical room for the operation list.
  static let pdf = IslandModuleLayout(
    islandSize: CGSize(width: 660, height: 600),
    panelSize: CGSize(width: 860, height: 604)
  )
  /// Shelf content is fixed at 320pt and scrolls internally when it contains more files.
  static let shelf = compactModule(contentHeight: 320)
  /// Clipboard: taller than standard so more items are visible at once, reducing scrolling.
  /// Width matches standard (panelSize keeps 200pt shoulder clearance); only the island body is taller.
  static let clipboard = IslandModuleLayout(
    islandSize: CGSize(width: 660, height: 500),
    panelSize: CGSize(width: 860, height: 504)
  )
  static let ai = IslandModuleLayout(
    islandSize: CGSize(width: 820, height: 470),
    panelSize: CGSize(width: 820, height: 474)
  )
  static let system = compactModule(contentHeight: 401, islandWidth: 720)
  static let battery = compactModule(contentHeight: batteryMaximumContentHeight)
  /// Quick Notes: needs a larger editing/preview area for rich content such as images and tables, so wider and taller than standard.
  static let notes = IslandModuleLayout(
    islandSize: CGSize(width: 720, height: 560),
    panelSize: CGSize(width: 720, height: 564)
  )
  /// Mail: wider and taller; list column expands to 232pt so sender/subject/preview are not truncated prematurely, and more messages are visible.
  static let mail = IslandModuleLayout(
    islandSize: CGSize(width: 860, height: 520),
    panelSize: CGSize(width: 1060, height: 524)
  )
  /// Dashboard height follows the fixed crown chrome and rendered activity-card grid.
  /// The arithmetic lives in `IslandDashboardLayout` (ZislaKit) so it is unit-testable and
  /// stays clamped above the crown's black → glass transition.
  /// Voice recording keeps the collapsed pill's width and only adds one transcript line below.
  static let voiceRecording = IslandModuleLayout(
    islandSize: CGSize(width: 240, height: 54),
    panelSize: CGSize(width: 240, height: 58)
  )
  /// Mirror uses a square panel so the camera preview maintains its natural aspect ratio without cropping.
  static let mirror = IslandModuleLayout(
    islandSize: CGSize(width: 640, height: 640),
    panelSize: CGSize(width: 640, height: 644)
  )
  static let teleprompter = IslandModuleLayout(
    islandSize: CGSize(width: 760, height: 640),
    panelSize: CGSize(width: 760, height: 644)
  )

  /// Resolves the current layout. Dashboard height follows its rendered activity-card rows.
  nonisolated static func resolved(
    for module: IslandModule,
    dashboardCardCount: Int,
    batteryDynamicHeight: CGFloat? = nil
  ) -> IslandModuleLayout {
    if module == .dashboard {
      // Empty and single-card dashboards are clamped to the crown floor instead of falling back
      // to `.standard`: a fixed 340pt left a large black gap under the toolbar, while shrinking to
      // pure content height (~129pt for one card) sank the whole island inside the 132pt black
      // crown, hiding the frosted glass and the bottom corner radius.
      let islandHeight = IslandDashboardLayout.contentHeight(
        cardCount: dashboardCardCount
      )
      return IslandModuleLayout(
        islandSize: CGSize(width: 660, height: islandHeight),
        panelSize: CGSize(width: 860, height: islandHeight + 4)
      )
    }
    if module == .battery, let dynamicHeight = batteryDynamicHeight {
      let contentHeight = min(
        batteryMaximumContentHeight,
        max(batteryMinimumContentHeight, dynamicHeight)
      )
      return compactModule(contentHeight: contentHeight)
    }
    return module.layout
  }
}

enum UpdateCheckState: Equatable {
  case idle
  case checking
  case current
  case available(GitHubRelease, source: ReleaseSource)
  case failed(String)
}

enum DownloadUIState: Equatable {
  case idle
  case preparing
  case downloading(fraction: Double, speed: String, eta: String)
  case completed(URL)
  case failed(String)

  var isRunning: Bool {
    switch self {
    case .preparing, .downloading: true
    default: false
    }
  }
}

struct DownloadTaskSnapshot: Identifiable, Equatable {
  let id: UUID
  let urlString: String
  let state: DownloadUIState
}

enum WeatherLocationUIState: Equatable {
  case idle
  case locating
  case searching
  case ready(String)
  case failed(String)

  var isBusy: Bool {
    self == .locating || self == .searching
  }
}

@MainActor
private final class SharingPickerDelegateProxy: NSObject,
  @preconcurrency NSSharingServicePickerDelegate
{
  var onCompletion: ((NSSharingServicePicker) -> Void)?

  func sharingServicePicker(
    _ sharingServicePicker: NSSharingServicePicker,
    didChoose service: NSSharingService?
  ) {
    onCompletion?(sharingServicePicker)
  }
}

struct MailComposeRequest: Equatable {
  let id = UUID()
  let recipient: String
}

@MainActor
final class AppModel: ObservableObject {
  private enum AIProcessingTarget {
    case http(
      endpoint: AIEndpoint,
      protocolKind: AgentChannelProtocol,
      model: String,
      apiKey: String?,
      effort: AgentModelEffort?
    )
    case cliProfile(accountID: UUID, model: String)
  }

  static let shared = AppModel()

  @Published var selectedModule: IslandModule = .dashboard {
    didSet {
      // Do not put teardown in default: named cases such as agenda and mail would skip it, leaving usage history resident in memory.
      if oldValue == .aiMonitor, selectedModule != .aiMonitor {
        aiMonitor.unloadUsageHistory()
      }
      switch selectedModule {
      case .agenda:
        refreshAgendaIfEnabled()
      case .mail:
        Task { await mail.refresh() }
      case .quickNotes:
        Task { await quickNotes.refresh() }
      case .aiMonitor:
        aiMonitor.loadUsageHistory()
      default:
        break
      }
    }
  }
  /// Module switch direction (+1 rightward in module order, -1 leftward) driving the
  /// directional page transition. Committed one run-loop turn before `selectedModule`
  /// changes so the outgoing view's removal transition also carries the fresh direction.
  @Published private(set) var moduleSwitchDirection: CGFloat = 1
  private var pendingModuleSelection: IslandModule?

  /// Preferred entry point for switching modules: records the navigation direction for
  /// the directional transition, then applies the switch on the next run-loop turn.
  func selectModule(_ module: IslandModule) {
    let current = pendingModuleSelection ?? selectedModule
    guard module != current else { return }
    let order = IslandModule.allCases
    if let from = order.firstIndex(of: current),
       let to = order.firstIndex(of: module) {
      moduleSwitchDirection = to > from ? 1 : -1
    }
    pendingModuleSelection = module
    DispatchQueue.main.async { [weak self] in
      guard let self, let target = self.pendingModuleSelection else { return }
      self.pendingModuleSelection = nil
      guard target != self.selectedModule else { return }
      self.selectedModule = target
    }
  }

  @Published var isPinned = false
  @Published private(set) var weatherSnapshotsByLocationID: [String: WeatherSnapshot] = [:]
  @Published var weatherLocationState: WeatherLocationUIState = .idle
  @Published var updateState: UpdateCheckState = .idle
  @Published private(set) var productUpdateAvailable = false
  @Published var downloadURL = ""
  @Published var downloadMode: DownloadMode = .video
  @Published var downloadDirectory = AppPaths.downloads
  @Published var downloadState: DownloadUIState = .idle
  @Published private(set) var activeDownloads: [DownloadTaskSnapshot] = []
  @Published var transientMessage: String?
  var hasActiveDownloads: Bool { !activeDownloadIDs.isEmpty }
  @Published private(set) var mailComposeRequest: MailComposeRequest?
  @Published var collapsedIslandSize = CGSize(width: 240, height: 34)
  @Published var isIslandOnPhysicalNotch = false

  /// Overflow width of the collapsed capsule. On notched displays, the compact bar extends one wing width past each side of the notch.
  /// On displays without a notch, it is the capsule width. Compact surfaces use it to align with the collapsed surface's visible edge.
  var collapsedOverflowWidth: CGFloat {
    collapsedIslandSize.width
      + (isIslandOnPhysicalNotch ? SideNoticeLayoutEngine.compactStatusWingWidth * 2 : 0)
  }
  /// Number of cards rendered below the dashboard summary.
  @Published private(set) var dashboardCardCount = 0
  /// Dynamic content height for the battery module.
  @Published private(set) var batteryModuleDynamicHeight = IslandModuleLayout.batteryMaximumContentHeight
  @Published private(set) var isMirrorPresented = false
  @Published private(set) var isTeleprompterPresented = false
  private(set) var teleprompterPresentationPoint: CGPoint?
  @Published var isIslandVisible = false {
    didSet {
      guard oldValue != isIslandVisible else { return }
      updateSpectrumMonitoring()
    }
  }
  @Published var isExternalDragging = false
  @Published var detectedLink: URL?
  @Published private(set) var isSharingPickerVisible = false

  /// Signal to request the island to collapse immediately when disk cleaning opens or completes.
  @Published var islandCollapseRequested = false

  /// Signal to expand the island from an entry point that fires while it is still collapsed, such
  /// as a clipboard assistant action that has to land the user inside an island module.
  @Published var islandExpansionRequested = false

  let settingsStore = FeatureSettingsStore()
  let languageStore = AppLanguageStore()
  let aiMonitor = AIStateMonitor()
  let notices = SideNoticeQueue()
  let media = NowPlayingService()
  let audioOutput = AudioOutputDeviceService()
  let calendar = CalendarService()
  let shelf = FileShelfStore()
  @Published var selectedShelfCategory: FileShelfCategory = .all
  let weatherLocations = WeatherLocationStore()
  let clipboardMonitor = ClipboardLinkMonitor()
  let clipboardHistory = ClipboardHistoryStore()
  let clipboardHistoryMonitor = ClipboardHistoryMonitor()
  /// Copy assistant: recognizes copied content and shows a toast with a next-step action.
  let clipboardAssistant = ClipboardAssistantController()
  let pomodoro = PomodoroService()
  let alarms = AlarmService()
  let managedTools = ManagedToolService()
  let powerAssertions = PowerAssertionController()
  let screenCleaning = ScreenCleaningController()
  let systemMonitor = SystemMonitorService()
  let backgroundSounds = SystemBackgroundSoundService()
  let battery = BatteryMonitor()
  let networkBattery = NetworkBatteryMonitor()
  let focusMode = FocusModeMonitor()
  let quickNotes = QuickNotesService()
  let browserDownloads = BrowserDownloadMonitor()
  private let videoDownloadFavicons = VideoDownloadFaviconStore()
  /// Cached favicon data for long-tail sites; reused on each progress refresh to avoid re-queuing and losing the image.
  private var videoDownloadFaviconData: Data?
  private var videoDownloadPlatform: VideoDownloadPlatform?
  private var videoDownloadHost: String?
  let mail = MailService()
  let voiceInput = VoiceInputController()
  let voiceHistory = VoiceHistoryStore()
  let aiAgent = AIAgentWorkspace()

  /// Model discovery state: used by the settings page to show connection test results and the available model list.
  @Published var voiceModelDiscoveryState: VoiceModelDiscoveryState = .idle
  @Published var discoveredModels: [AIDiscoveredModel] = []
  /// True while an AI model is cleaning up a recorded transcript; drives the collapsed-island processing indicator.
  @Published private(set) var isProcessingVoiceTranscript = false
  @Published private(set) var voiceInputInputMonitoringAccessGranted =
    GlobalHotkeyManager.hasInputMonitoringAccess
  /// Accessibility trust state for the clipboard assistant's quick-copy mouse gesture.
  @Published private(set) var assistantAccessibilityGranted = AccessibilityPermission.isTrusted
  private let weatherService = WeatherService()
  private let weatherLocationService = WeatherLocationService()
  private let releaseService = GitHubReleaseService()
  private let releasePackageDownloadService = ReleasePackageDownloadService()
  private let downloadService = DownloadService()
  private let hotkeyManager = GlobalHotkeyManager()
  private let voicePostProcessingQueue = VoicePostProcessingQueue()
  /// Serial voice-processing runs share one pair of wing notices; removed when the last run finishes.
  private var voiceProcessingOperationCount = 0
  private let voiceTranscriptDelivery = VoiceTranscriptDelivery()
  private let voiceRecordingPlayer = VoiceRecordingPlayer()
  private var cancellables: Set<AnyCancellable> = []
  private var weatherTask: Task<Void, Never>?
  private var releaseTask: Task<Void, Never>?
  private var releasePackageDownloadTask: Task<Void, Never>?
  private var updatePollingTask: Task<Void, Never>?
  private var voiceRecordingCleanupTask: Task<Void, Never>?
  private var appliedVoiceRecordingCleanupPolicy: VoiceRecordingCleanupPolicy?
  private var downloadTasks: [UUID: Task<Void, Never>] = [:]
  private var activeDownloadIDs: Set<UUID> = []
  private var downloadTaskStates: [UUID: DownloadUIState] = [:]
  private var downloadTaskURLs: [UUID: String] = [:]
  private var downloadTaskOrder: [UUID] = []
  private var detectedLinkTask: Task<Void, Never>?
  private var translationTask: Task<Void, Never>?
  private var activeDownloadID: UUID?
  private var knownNoticeIDs: Set<String> = []
  private var wasPinnedBeforeMirror = false
  private var wasPinnedBeforeTeleprompter = false
  private var taskStatuses: [String: AIProgressStatus] = [:]
  private var activeAINoticeIDs: Set<String> = []
  /// AI notices shown during the current activity; once hidden by timeout, they are not re-queued within the same activity cycle.
  private var activityNoticeShownIDs: Set<String> = []
  private var mediaActivityPresented = false
  private var hasLoadedMail = false
  private var knownMailMessageIDs: Set<String> = []
  private var lastActivityNoticeDisplayDuration: ActivityNoticeDisplayDuration?
  private var isUpdatePollingEnabled = false
  private let mediaNoticeIDs: Set<String> = [
    "media-active-left",
    "media-active-right",
  ]
  private let backgroundSoundNoticeIDs: Set<String> = [
    "background-sound-left",
    "background-sound-right",
  ]
  private let toolboxReminderIDs: Set<String> = [
    "toolbox-reminder-left",
    "toolbox-reminder-right",
  ]
  private let focusCountdownNoticeIDs: Set<String> = [
    "focus-countdown-left",
    "focus-countdown-right",
  ]
  private let focusModeNoticeIDs: Set<String> = [
    "focus-mode-left",
    "focus-mode-right",
  ]
  private let browserDownloadNoticeIDs: Set<String> = [
    "browser-download-left",
    "browser-download-right",
  ]
  private let videoDownloadNoticeIDs: Set<String> = [
    "video-download-left",
    "video-download-right",
  ]
  private let updateNoticePrefix = "update-available-"
  private var cleaningPowerState:
    (
      keepDisplayAwake: Bool,
      preventIdleSystemSleep: Bool
    )?
  private let launchDate = Date()
  private let sharingPickerDelegate = SharingPickerDelegateProxy()
  private var sharingPicker: NSSharingServicePicker?
  private var sharingPickerDismissesClipboardAssistant = false
  private var voiceInputTarget: VoiceTranscriptDeliveryTarget?
  private var voiceInputTargetProcessIdentifier: pid_t?
  private var voiceInputTargetMouseLocation: CGPoint?
  private var hasRequestedVoiceInputPostEventAccess = false

  private init() {
    let networkProxyURL = settingsStore.settings.networkProxyURL
    let networkProxyEnabled = settingsStore.settings.networkProxyEnabled
    aiAgent.setNetworkProxy(url: networkProxyURL, enabled: networkProxyEnabled)
    managedTools.setNetworkProxy(url: networkProxyURL, enabled: networkProxyEnabled)
    Task { await releaseService.setNetworkProxy(url: networkProxyURL, enabled: networkProxyEnabled) }
    Task { await releasePackageDownloadService.setNetworkProxy(url: networkProxyURL, enabled: networkProxyEnabled) }
    Task { await downloadService.setNetworkProxy(url: networkProxyURL, enabled: networkProxyEnabled) }
    sharingPickerDelegate.onCompletion = { [weak self] picker in
      self?.sharingPickerDidComplete(picker)
    }
    screenCleaning.onCleaningDidEnd = { [weak self] in
      self?.restorePowerAssertionsAfterCleaning()
    }
    backgroundSounds.onAutomaticStop = { [weak self] in
      guard let self, self.settingsStore.settings.systemBackgroundSoundEnabled else { return }
      var settings = self.settingsStore.settings
      settings.systemBackgroundSoundEnabled = false
      self.settingsStore.settings = settings
    }
    restoreDownloadDirectory()
    clipboardHistoryMonitor.onContentCaptured = { [weak self] content in
      guard let self else { return }
      if self.settingsStore.settings.clipboardHistoryEnabled {
        _ = self.clipboardHistory.record(content)
      }
      self.handleCapturedClipboardContent(content)
    }
    clipboardAssistant.onPerformAction = { [weak self] action in
      self?.performClipboardAssistantAction(action)
    }
    clipboardMonitor.onLinkDetected = { [weak self] url in
      guard let self else { return }
      routeCapturedClipboardContent(.text(url.absoluteString), downloadableURL: url)
    }
    voiceInput.onRecordingWillStart = { [weak self] in
      guard let self else { return }
      self.clipboardAssistant.dismiss(animated: false)
      let processIdentifier = Self.frontmostVoiceInputTargetProcessIdentifier()
      voiceInputTargetProcessIdentifier = processIdentifier
      voiceInputTarget = processIdentifier.flatMap(VoiceTranscriptDelivery.captureTarget(for:))
      voiceInputTargetMouseLocation = CGEvent(source: nil)?.location
      requestVoiceInputPostEventAccessIfNeeded()
    }
    voiceInput.onTranscriptCompleted = { [weak self] recording in
      self?.deliverVoiceRecording(recording)
    }
    // The in-island transcript HUD only exists while recording, so a permission or start-up failure
    // would otherwise leave the shortcut looking like it did nothing at all.
    voiceInput.$errorDescription
      .compactMap { $0 }
      .sink { [weak self] message in
        Task { @MainActor [weak self] in self?.transientMessage = message }
      }
      .store(in: &cancellables)

    // Disabling the open module in Settings falls the island back to the dashboard, but the panel sizing pipeline observes only
    // selectedModule; failing to reset selection leaves misaligned NSPanel geometry and stale icon highlighting.
    settingsStore.$settings
      .sink { [weak self] _ in
        Task { @MainActor [weak self] in
          guard let self else { return }
          // Read the live value rather than the emitted snapshot to avoid an incorrect fallback during rapid toggles.
          guard !self.selectedModule.isEnabled(in: self.settingsStore.settings) else { return }
          self.selectedModule = .dashboard
        }
      }
      .store(in: &cancellables)

    let childPublishers = [
      settingsStore.objectWillChange,
      notices.objectWillChange,
      audioOutput.objectWillChange,
      backgroundSounds.objectWillChange,
      calendar.objectWillChange,
      shelf.objectWillChange,
      clipboardHistory.objectWillChange,
      weatherLocations.objectWillChange,
      powerAssertions.objectWillChange,
      screenCleaning.objectWillChange,
      battery.objectWillChange,
      focusMode.objectWillChange,
      quickNotes.objectWillChange,
      mail.objectWillChange,
      voiceHistory.objectWillChange,
      aiAgent.objectWillChange,
      managedTools.objectWillChange,
    ]
    for publisher in childPublishers {
      publisher
        .sink { [weak self] in
          Task { @MainActor [weak self] in self?.objectWillChange.send() }
        }
        .store(in: &cancellables)
    }

    for publisher in [
      pomodoro.objectWillChange,
      powerAssertions.objectWillChange,
      screenCleaning.objectWillChange,
    ] {
      publisher
        .sink { [weak self] in
          Task { @MainActor [weak self] in
            self?.refreshFocusCountdownNotice()
            self?.refreshToolboxReminderNotice()
          }
        }
        .store(in: &cancellables)
    }

    settingsStore.$settings
      .dropFirst()
      .sink { [weak self] settings in
        Task { @MainActor [weak self] in self?.apply(settings: settings) }
        let networkProxyURL = settings.networkProxyURL
        let networkProxyEnabled = settings.networkProxyEnabled
        self?.aiAgent.setNetworkProxy(url: networkProxyURL, enabled: networkProxyEnabled)
        self?.managedTools.setNetworkProxy(url: networkProxyURL, enabled: networkProxyEnabled)
        Task { await self?.releaseService.setNetworkProxy(url: networkProxyURL, enabled: networkProxyEnabled) }
        Task { await self?.releasePackageDownloadService.setNetworkProxy(url: networkProxyURL, enabled: networkProxyEnabled) }
        Task { await self?.downloadService.setNetworkProxy(url: networkProxyURL, enabled: networkProxyEnabled) }
      }
      .store(in: &cancellables)

    aiMonitor.$state
      .dropFirst()
      .sink { [weak self] state in
        Task { @MainActor [weak self] in self?.consumeAIState(state) }
      }
      .store(in: &cancellables)

    media.$snapshot
      .sink { [weak self] snapshot in
        Task { @MainActor [weak self] in
          self?.consumeMediaSnapshot(snapshot)
          self?.refreshDashboardPresentation()
        }
      }
      .store(in: &cancellables)

    Publishers.CombineLatest(backgroundSounds.$isPlaying, backgroundSounds.$playingSound)
      .removeDuplicates { lhs, rhs in
        lhs.0 == rhs.0 && lhs.1 == rhs.1
      }
      .sink { [weak self] _ in
        Task { @MainActor [weak self] in
          self?.consumeBackgroundSoundPlayback()
          self?.updateSpectrumMonitoring()
        }
      }
      .store(in: &cancellables)

    Publishers.CombineLatest(notices.$left, notices.$right)
      .map { [weak self] left, right in
        guard let self else { return false }
        return left.contains {
          self.mediaNoticeIDs.contains($0.id) || self.backgroundSoundNoticeIDs.contains($0.id)
        } || right.contains {
          self.mediaNoticeIDs.contains($0.id) || self.backgroundSoundNoticeIDs.contains($0.id)
        }
      }
      .removeDuplicates()
      .sink { [weak self] _ in
        Task { @MainActor [weak self] in self?.updateSpectrumMonitoring() }
      }
      .store(in: &cancellables)

    audioOutput.$headphoneConnection
      .compactMap { $0 }
      .sink { [weak self] connection in
        Task { @MainActor [weak self] in self?.consumeHeadphoneConnection(connection) }
      }
      .store(in: &cancellables)

    browserDownloads.$snapshot
      .sink { [weak self] snapshot in
        Task { @MainActor [weak self] in self?.consumeBrowserDownloadSnapshot(snapshot) }
      }
      .store(in: &cancellables)

    focusMode.$status
      .dropFirst()
      .sink { [weak self] status in
        Task { @MainActor [weak self] in
          self?.consumeFocusModeStatus(status, showsTransition: false)
        }
      }
      .store(in: &cancellables)

    focusMode.$latestTransition
      .compactMap { $0 }
      .sink { [weak self] transition in
        Task { @MainActor [weak self] in
          self?.consumeFocusModeStatus(transition.status, showsTransition: true)
        }
      }
      .store(in: &cancellables)

    mail.$messages
      .dropFirst()
      .sink { [weak self] messages in
        Task { @MainActor [weak self] in self?.consumeMailMessages(messages) }
      }
      .store(in: &cancellables)

    aiAgent.$cliUpdates
      .dropFirst()
      .sink { [weak self] _ in
        Task { @MainActor [weak self] in self?.refreshUpdateNotices() }
      }
      .store(in: &cancellables)

    // Any source affecting the dashboard height. Pomodoro exposes `phase` as a computed property over
    // its engine, so it can only be observed via `objectWillChange`, which fires before the value lands.
    // Deferring to the next run-loop turn ensures the panel size matches the cards SwiftUI can render.
    Publishers.MergeMany(
      pomodoro.objectWillChange.eraseToAnyPublisher(),
      aiMonitor.$state.map { _ in () }.eraseToAnyPublisher(),
      settingsStore.$settings.map { _ in () }.eraseToAnyPublisher(),
      $downloadState.map { _ in () }.eraseToAnyPublisher(),
      browserDownloads.$snapshots.map { _ in () }.eraseToAnyPublisher()
    )
    .sink { [weak self] in
      DispatchQueue.main.async { [weak self] in
        self?.refreshDashboardPresentation()
      }
    }
    .store(in: &cancellables)

    refreshDashboardPresentation()
  }

  /// Mirrors the dashboard's rendered cards so the island height stays in sync.
  private func refreshDashboardPresentation() {
    let settings = settingsStore.settings
    let hasPomodoro = pomodoro.phase != .idle
    let hasAITask = settings.aiProgressEnabled
      && aiMonitor.state.tasks.contains { $0.status.isActive }
    let cardCount = [hasPomodoro, hasAITask, hasActiveDownloads].filter { $0 }.count
      + browserDownloads.snapshots.count
    if dashboardCardCount != cardCount {
      dashboardCardCount = cardCount
    }
  }

  func synchronizeDashboardCardCount(_ count: Int) {
    guard dashboardCardCount != count else { return }
    dashboardCardCount = count
  }

  func setBatteryModuleDynamicHeight(_ height: CGFloat) {
    let constrained = min(
      IslandModuleLayout.batteryMaximumContentHeight,
      max(IslandModuleLayout.batteryMinimumContentHeight, height)
    )
    guard abs(batteryModuleDynamicHeight - constrained) > 1 else { return }
    batteryModuleDynamicHeight = constrained
  }

  func start() {
    backgroundSounds.startLifecycleMonitoring()
    apply(settings: settingsStore.settings)
    alarms.rescheduleAll()
  }

  func toggleBackgroundSound() {
    var settings = settingsStore.settings
    let sound = settings.systemBackgroundSound
    if backgroundSounds.isPlaying || backgroundSounds.isDownloading(sound) {
      backgroundSounds.cancelDownload(sound: sound)
      backgroundSounds.stop()
      settings.systemBackgroundSoundEnabled = false
      settingsStore.settings = settings
      return
    }

    settings.systemBackgroundSoundEnabled = true
    settingsStore.settings = settings
    backgroundSounds.playOrDownload(sound: sound)
  }

  func selectBackgroundSound(_ sound: SystemBackgroundSound) {
    var settings = settingsStore.settings
    let previousSound = settings.systemBackgroundSound
    let wasPlaying = backgroundSounds.isPlaying
    backgroundSounds.refresh()
    settings.systemBackgroundSound = sound
    if !backgroundSounds.isInstalled(sound) {
      settings.systemBackgroundSoundEnabled = false
    }
    settingsStore.settings = settings
    if !backgroundSounds.isInstalled(sound) {
      if wasPlaying { backgroundSounds.stop() }
      backgroundSounds.requestDownload(sound: sound, playWhenReady: wasPlaying)
    } else if wasPlaying, previousSound != sound {
      _ = backgroundSounds.play(sound: sound)
    }
  }

  func openVoiceInputInputMonitoringSettings() {
    refreshVoiceInputInputMonitoringAccess()
    guard !voiceInputInputMonitoringAccessGranted else { return }

    _ = GlobalHotkeyManager.requestInputMonitoringAccess()
    guard let url = URL(
      string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent"
    ), NSWorkspace.shared.open(url) else {
      transientMessage = "无法打开系统设置的输入监控页面"
      return
    }
  }

  func refreshAssistantAccessibility() {
    guard assistantAccessibilityGranted != AccessibilityPermission.isTrusted else { return }
    assistantAccessibilityGranted = AccessibilityPermission.isTrusted
    // Re-apply the gesture when the permission flips to granted.
    if assistantAccessibilityGranted, settingsStore.settings.clipboardAssistantEnabled {
      applyAssistantMouseGesture()
    }
  }

  /// Opens System Settings at the accessibility pane (and fires the system grant prompt).
  func openAssistantAccessibilitySettings() {
    guard !assistantAccessibilityGranted else { return }
    _ = AccessibilityPermission.promptIfNeeded()
    guard let url = URL(
      string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
    ), NSWorkspace.shared.open(url) else {
      transientMessage = "无法打开系统设置的辅助功能页面"
      return
    }
  }

  func refreshVoiceInputInputMonitoringAccess() {
    let granted = GlobalHotkeyManager.hasInputMonitoringAccess
    guard voiceInputInputMonitoringAccessGranted != granted else { return }
    let wasGranted = voiceInputInputMonitoringAccessGranted
    voiceInputInputMonitoringAccessGranted = granted

    if granted, !wasGranted, settingsStore.settings.clipboardAssistantEnabled {
      clipboardAssistant.setTriggers(
        hotkey: settingsStore.settings.clipboardAssistantTriggerConfiguration.hotkey,
        mouseButton: settingsStore.settings.clipboardAssistantMouseButton
      )
      applyAssistantMouseGesture()
    }

    // Re-register the hotkey when permission changes from denied to granted.
    if granted, !wasGranted, settingsStore.settings.voiceInputEnabled {
      let preset = settingsStore.settings.voiceInputHotkeyPreset
      let mode = settingsStore.settings.voiceInputMode
      let registration = hotkeyManager.register(
        hotkey: preset,
        onKeyDown: { [weak self] in
          guard let self else { return }
          switch mode {
          case .toggle:
            self.voiceInput.toggle()
          case .pushToTalk:
            self.voiceInput.start()
          }
        },
        onKeyUp: { [weak self] in
          guard let self else { return }
          if mode == .pushToTalk {
            self.voiceInput.stop()
          }
        }
      )

      switch registration {
      case .registered:
        transientMessage = "语音输入快捷键已启用"
      case .inputMonitoringPermissionRequired:
        transientMessage = "快捷键需要输入监控权限，请在系统设置中授权后重启 App"
      case .registrationFailed:
        transientMessage = "无法注册语音输入快捷键"
      }
    }
  }

  func stop() {
    settingsStore.flushPendingChanges()
    clipboardHistory.flushPendingChanges()
    aiAgent.store.flushPendingChanges()
    weatherTask?.cancel()
    releaseTask?.cancel()
    releasePackageDownloadTask?.cancel()
    updatePollingTask?.cancel()
    voiceRecordingCleanupTask?.cancel()
    voiceRecordingCleanupTask = nil
    appliedVoiceRecordingCleanupPolicy = nil
    cancelAllDownloads()
    voicePostProcessingQueue.cancelAll()
    voiceProcessingOperationCount = 0
    isProcessingVoiceTranscript = false
    notices.remove(id: "voice-processing-left")
    notices.remove(id: "voice-processing-right")
    detectedLinkTask?.cancel()
    translationTask?.cancel()
    voiceInputTarget = nil
    voiceInputTargetProcessIdentifier = nil
    voiceInputTargetMouseLocation = nil
    voiceInput.cancel()
    backgroundSounds.cancelAllDownloads()
    backgroundSounds.stopLifecycleMonitoring()
    backgroundSounds.stop()
    hotkeyManager.unregister()
    clipboardMonitor.setEnabled(false)
    clipboardHistoryMonitor.setEnabled(false)
    clipboardAssistant.setTriggers(hotkey: nil, mouseButton: nil)
    clipboardAssistant.setMouseGesture(enabled: false, onQuickCopy: {})
    clipboardAssistant.dismiss()
    Task { [downloadService] in await downloadService.cancelAll() }
    aiMonitor.stop()
    aiAgent.stop()
    media.stop()
    audioOutput.stop()
    calendar.stop()
    pomodoro.stop()
    alarms.suspend()
    screenCleaning.stopAll()
    cleaningPowerState = nil
    powerAssertions.releaseAll()
    systemMonitor.stop()
    battery.stop()
    networkBattery.stop()
    focusMode.stop()
    browserDownloads.stop()
    mail.stop()
    hasLoadedMail = false
    knownMailMessageIDs.removeAll()
    clearMediaNotices()
    clearFocusModeNotices()
    notices.removeAll()
    detectedLink = nil
    let picker = sharingPicker
    sharingPicker = nil
    sharingPickerDismissesClipboardAssistant = false
    isSharingPickerVisible = false
    picker?.close()
  }

  func startScreenCleaning() {
    guard settingsStore.settings.toolboxEnabled else { return }
    enablePowerAssertionsForCleaning()
    screenCleaning.startScreenCleaning()
    refreshFocusCountdownNotice()
    refreshToolboxReminderNotice()
  }

  func startKeyboardCleaning() {
    guard settingsStore.settings.toolboxEnabled else { return }
    switch screenCleaning.startKeyboardCleaning() {
    case .started:
      enablePowerAssertionsForCleaning()
    case .accessibilityPermissionRequired:
      _ = ScreenCleaningController.requestAccessibilityAccess()
      transientMessage = "清洁键盘需要在系统设置中允许辅助功能"
    case .registrationFailed:
      transientMessage = "无法接管键盘输入"
    case .alreadyActive:
      break
    }
    refreshToolboxReminderNotice()
  }

  // MARK: - Desktop and Trash

  /// Snaps desktop icons to the grid in one click; does nothing if Stacks are enabled.
  func tidyDesktop() {
    Task { @MainActor [weak self] in
      guard let self else { return }
      switch await DesktopOrganizer.tidyDesktop() {
      case .success(let outcome):
        if outcome.skippedForStacks {
          transientMessage = "桌面已开启叠放，由系统自动排布"
        } else if outcome.arrangedCount == 0 {
          transientMessage = "桌面没有需要整理的项目"
        } else {
          transientMessage = "已按网格整理 \(outcome.arrangedCount) 个项目"
        }
      case .failure(let error):
        transientMessage = error.message
      }
    }
  }

  /// Empties the Trash. Irreversible — shows a confirmation dialog with the item count first.
  func emptyTrash() {
    Task { @MainActor [weak self] in
      guard let self else { return }
      let count: Int
      switch await DesktopOrganizer.trashItemCount() {
      case .success(let value):
        count = value
      case .failure(let error):
        transientMessage = error.message
        return
      }
      guard count > 0 else {
        transientMessage = "废纸篓已经是空的"
        return
      }

      let alert = NSAlert()
      alert.messageText = "清空废纸篓？"
      alert.informativeText = "将永久删除 \(count) 个项目，此操作无法撤销。"
      alert.alertStyle = .warning
      alert.addButton(withTitle: "清空")
      alert.addButton(withTitle: "取消")
      NSApp.activate(ignoringOtherApps: true)
      WindowPlacement.prepareModal(alert.window, on: WindowPlacement.screenUnderMouse())
      guard alert.runModal() == .alertFirstButtonReturn else { return }

      switch await DesktopOrganizer.emptyTrash() {
      case .success:
        transientMessage = "已清空废纸篓（\(count) 个项目）"
      case .failure(let error):
        transientMessage = error.message
      }
    }
  }

  func refreshForExpansion() {
    let settings = settingsStore.settings
    let module = selectedModule
    let weatherStale = isWeatherStale
    let calendarStale = calendar.isDataStale

    Task { @MainActor [weak self] in
      try? await Task.sleep(for: .milliseconds(250))
      guard let self, self.isIslandVisible else { return }
      if settings.mediaEnabled { self.media.refresh() }
      if settings.aiProgressEnabled { self.aiMonitor.refresh() }
      if settings.weatherEnabled, weatherStale { self.refreshWeather() }
      if settings.systemMonitorEnabled { await self.systemMonitor.sampleOnce() }
      if settings.lockScreenInfoEnabled || settings.batteryMonitorEnabled {
        self.battery.refresh()
      }
      if settings.mailEnabled, module == .mail { await self.mail.refresh() }
      if settings.quickNotesEnabled, module == .quickNotes {
        await self.quickNotes.refresh()
      }
      if settings.calendarEnabled, module == .agenda, calendarStale {
        await self.calendar.refresh()
      }
    }
  }

  func refreshWeather() {
    guard settingsStore.settings.weatherEnabled else {
      weatherTask?.cancel()
      weatherTask = nil
      return
    }
    weatherTask?.cancel()
    let configuredLocations = weatherLocations.locations
    weatherLocationState = .locating
    weatherTask = Task { [weak self, weatherService, weatherLocationService] in
      guard let self else { return }
      var requests: [(id: String, location: GeoLocation)] = []
      var firstError: String?

      for configured in configuredLocations {
        switch configured.kind {
        case .current:
          do {
            let current = try await weatherLocationService.currentLocation()
            try Task.checkCancellation()
            weatherLocations.updateCurrent(
              name: current.displayName,
              coordinate: GeoCoordinate(
                latitude: current.latitude,
                longitude: current.longitude
              )
            )
            requests.append((configured.id, current))
          } catch is CancellationError {
            return
          } catch {
            firstError = error.localizedDescription
            if let coordinate = configured.coordinate {
              requests.append(
                (
                  configured.id,
                  GeoLocation(
                    latitude: coordinate.latitude,
                    longitude: coordinate.longitude,
                    displayName: configured.displayName
                  )
                ))
            }
          }
        case .saved:
          guard let coordinate = configured.coordinate else { continue }
          requests.append(
            (
              configured.id,
              GeoLocation(
                latitude: coordinate.latitude,
                longitude: coordinate.longitude,
                displayName: configured.displayName
              )
            ))
        }
      }

      var snapshots: [String: WeatherSnapshot] = [:]
      await withTaskGroup(of: (String, WeatherSnapshot?, String?).self) { group in
        for request in requests {
          group.addTask {
            do {
              let snapshot = try await weatherService.fetch(
                latitude: request.location.latitude,
                longitude: request.location.longitude,
                locationName: request.location.displayName
              )
              return (request.id, snapshot, nil)
            } catch {
              return (request.id, nil, error.localizedDescription)
            }
          }
        }
        for await (id, snapshot, error) in group {
          if let snapshot { snapshots[id] = snapshot }
          if firstError == nil, let error { firstError = error }
        }
      }

      guard !Task.isCancelled else { return }
      weatherSnapshotsByLocationID = snapshots
      let ordered = weatherLocations.orderedSnapshots(snapshots)
      if ordered.isEmpty {
        let message = firstError ?? "没有可用的天气数据"
        weatherLocationState = .failed(message)
        transientMessage = message
      } else {
        weatherLocationState = .ready("\(ordered.count) 个地点")
      }
    }
  }

  var weatherSnapshots: [WeatherSnapshot] {
    weatherLocations.orderedSnapshots(weatherSnapshotsByLocationID)
  }

  var weather: WeatherSnapshot? {
    weatherSnapshots.first
  }

  private var isWeatherStale: Bool {
    weatherSnapshots.isEmpty
      || weatherSnapshots.contains { Date().timeIntervalSince($0.fetchedAt) > 900 }
  }

  func weatherSnapshot(for locationID: String) -> WeatherSnapshot? {
    weatherSnapshotsByLocationID[locationID]
  }

  func selectWeatherLocation(named query: String) {
    weatherTask?.cancel()
    weatherLocationState = .searching
    weatherTask = Task { [weak self, weatherLocationService] in
      do {
        let location = try await weatherLocationService.search(query)
        try Task.checkCancellation()
        self?.weatherLocations.addSaved(
          name: location.displayName,
          coordinate: GeoCoordinate(
            latitude: location.latitude,
            longitude: location.longitude
          )
        )
        guard !Task.isCancelled else { return }
        self?.weatherLocationState = .ready(location.displayName)
        self?.weatherTask = nil
        self?.refreshWeather()
      } catch is CancellationError {
        return
      } catch {
        self?.transientMessage = error.localizedDescription
        self?.weatherLocationState = .failed(error.localizedDescription)
      }
    }
  }

  func removeWeatherLocation(id: String) {
    weatherLocations.remove(id: id)
    weatherSnapshotsByLocationID.removeValue(forKey: id)
  }

  func moveWeatherLocation(id: String, to destinationID: String) -> Bool {
    weatherLocations.moveSaved(id: id, to: destinationID)
  }

  func refreshMail() async {
    guard settingsStore.settings.mailEnabled else { return }
    await mail.refresh()
  }

  func markMailRead(_ message: MailMessage) async {
    _ = reportMailOperation(await mail.markRead(message), successMessage: "已标记为已读")
  }

  func markMailJunk(_ message: MailMessage) async {
    _ = reportMailOperation(await mail.markJunk(message), successMessage: "已标记为垃圾邮件")
  }

  func deleteMail(_ message: MailMessage) async {
    _ = reportMailOperation(await mail.delete(message), successMessage: "已移到废纸篓")
  }

  func sendMail(
    fromAddress: String?,
    to recipients: String,
    subject: String,
    body: String
  ) async -> Bool {
    reportMailOperation(
      await mail.send(fromAddress: fromAddress, to: recipients, subject: subject, body: body),
      successMessage: "邮件已发送"
    )
  }

  func replyToMail(_ message: MailMessage, body: String) async -> Bool {
    reportMailOperation(await mail.reply(to: message, body: body), successMessage: "回复已发送")
  }

  func takeMailComposeRequest() -> MailComposeRequest? {
    defer { mailComposeRequest = nil }
    return mailComposeRequest
  }

  func checkForUpdates(manual: Bool, channel: UpdateChannel? = nil) {
    guard manual || settingsStore.settings.updateChecksEnabled else { return }
    let selectedChannel = channel ?? (manual ? settingsStore.settings.updateChannel : nil)
    let fallbackChannel = selectedChannel ?? FeatureSettingsStore.bundledDefaultUpdateChannel
    releaseTask?.cancel()
    updateState = .checking
    let version =
      Bundle.main.object(
        forInfoDictionaryKey: "CFBundleShortVersionString"
      ) as? String ?? "0.1.1"
    releaseTask = Task { [weak self, releaseService] in
      do {
        let result = try await releaseService.check(
          currentVersion: version,
          channel: fallbackChannel
        )
        guard !Task.isCancelled else { return }
        switch result {
        case .upToDate:
          self?.updateState = .current
          self?.productUpdateAvailable = false
          self?.refreshUpdateNotices()
          if manual { self?.transientMessage = "当前已是最新版本" }
        case .updateAvailable(let release, let source):
          guard let self else { return }
          self.updateState = .available(release, source: source)
          self.productUpdateAvailable = true
          self.refreshUpdateNotices()
          if manual {
            self.presentUpdateAlert(for: release, source: source)
          } else if self.settingsStore.settings.automaticDownloadEnabled {
            self.downloadUpdateInBackground(release: release)
          }
        }
      } catch is CancellationError {
        return
      } catch {
        self?.updateState = .failed(error.localizedDescription)
        if manual { self?.transientMessage = error.localizedDescription }
      }
    }
  }

  private func presentUpdateAlert(for release: GitHubRelease, source: ReleaseSource) {
    let alert = NSAlert()
    let diskImage = release.macDiskImage
    alert.messageText = "发现 \(source.displayName) 新版本 \(release.tagName)"
    if let diskImage {
      alert.informativeText = """
      更新包下载完成后，请先退出 zisla，再打开 DMG 并将 zisla 拖入 Applications 替换旧版本。

      可以下载到默认目录，或为本次下载选择其他目录。
      """
      alert.addButton(withTitle: "下载到默认目录")
      alert.addButton(withTitle: "选择目录…")
      alert.addButton(withTitle: "稍后")
      NSApp.activate(ignoringOtherApps: true)
      WindowPlacement.prepareModal(alert.window, on: WindowPlacement.screenUnderMouse())
      switch alert.runModal() {
      case .alertFirstButtonReturn:
        downloadUpdatePackage(diskImage, to: downloadDirectory, revealInFinder: true)
      case .alertSecondButtonReturn:
        guard let directory = selectUpdateDownloadDirectory() else { return }
        downloadUpdatePackage(diskImage, to: directory, revealInFinder: true)
      default:
        return
      }
      return
    }

    alert.informativeText = "此 Release 未提供可下载的 DMG。请在退出 zisla 后，从 Release 页面下载并手动安装。"
    alert.addButton(withTitle: "打开 Release")
    alert.addButton(withTitle: "稍后")
    NSApp.activate(ignoringOtherApps: true)
    WindowPlacement.prepareModal(alert.window, on: WindowPlacement.screenUnderMouse())
    guard alert.runModal() == .alertFirstButtonReturn else { return }
    guard let url = release.htmlURL else {
      transientMessage = "Release 未提供可用下载地址"
      return
    }
    NSWorkspace.shared.open(url)
  }

  private func downloadUpdateInBackground(release: GitHubRelease) {
    guard settingsStore.settings.updateChecksEnabled,
          settingsStore.settings.automaticDownloadEnabled else { return }
    guard let diskImage = release.macDiskImage else { return }
    downloadUpdatePackage(diskImage, to: downloadDirectory, revealInFinder: false)
  }

  private func selectUpdateDownloadDirectory() -> URL? {
    let panel = NSOpenPanel()
    panel.canChooseFiles = false
    panel.canChooseDirectories = true
    panel.allowsMultipleSelection = false
    panel.canCreateDirectories = true
    panel.directoryURL = downloadDirectory
    panel.prompt = "选择保存位置"
    panel.message = "选择更新包保存位置"
    WindowPlacement.prepareModal(panel, on: WindowPlacement.screenUnderMouse())
    guard panel.runModal() == .OK else { return nil }
    return panel.url
  }

  private func downloadUpdatePackage(
    _ diskImage: GitHubRelease.Asset,
    to targetDirectory: URL,
    revealInFinder: Bool
  ) {
    releasePackageDownloadTask?.cancel()
    transientMessage = "正在下载更新…"
    let scopedAccess = targetDirectory.startAccessingSecurityScopedResource()
    let fileName = (diskImage.name as NSString).lastPathComponent
    let expectedURL = targetDirectory.appendingPathComponent(fileName, isDirectory: false)
    let existedBeforeDownload = FileManager.default.fileExists(atPath: expectedURL.path)
    releasePackageDownloadTask = Task { [weak self, releasePackageDownloadService] in
      defer {
        if scopedAccess { targetDirectory.stopAccessingSecurityScopedResource() }
      }
      do {
        let destination = try await releasePackageDownloadService.download(
          asset: diskImage,
          to: targetDirectory
        )
        guard !Task.isCancelled else { return }
        if revealInFinder {
          NSWorkspace.shared.activateFileViewerSelecting([destination])
        }
        let action = existedBeforeDownload ? "更新包已在" : "更新包已下载到"
        self?.transientMessage = "\(action) \(destination.path)，请退出 zisla 后手动安装"
      } catch is CancellationError {
        return
      } catch {
        guard !Task.isCancelled else { return }
        self?.transientMessage = "下载更新失败：\(error.localizedDescription)"
      }
    }
  }

  func selectSystemMonitor() {
    guard settingsStore.settings.systemMonitorEnabled else { return }
    selectModule(.system)
    Task { await systemMonitor.sampleOnce() }
  }

  func presentMirror() {
    guard !isMirrorPresented else { return }
    wasPinnedBeforeMirror = isPinned
    isPinned = true
    isMirrorPresented = true
  }

  func dismissMirror() {
    guard isMirrorPresented else { return }
    isPinned = wasPinnedBeforeMirror
    isMirrorPresented = false
  }

  func presentTeleprompter() {
    guard !isTeleprompterPresented else { return }
    teleprompterPresentationPoint = NSEvent.mouseLocation
    wasPinnedBeforeTeleprompter = isPinned
    isPinned = true
    isTeleprompterPresented = true
  }

  func dismissTeleprompter() {
    guard isTeleprompterPresented else { return }
    isPinned = wasPinnedBeforeTeleprompter
    isTeleprompterPresented = false
  }

  func addToShelf(_ urls: [URL]) {
    let count = shelf.add(urls)
    guard count > 0 else { return }
    transientMessage = "已加入 \(count) 个项目"
    selectModule(.shelf)
  }

  func pasteFilesToShelf() {
    let urls = FileShelfPasteboard.readFileURLs()
    guard !urls.isEmpty else {
      transientMessage = "剪贴板没有可粘贴的文件"
      return
    }
    addToShelf(urls)
  }

  func copyShelfFiles(_ urls: [URL]) {
    guard FileShelfPasteboard.writeFileURLs(urls) else {
      transientMessage = "没有可复制的文件"
      return
    }
    transientMessage = "已复制 \(urls.count) 个文件"
  }

  func copyClipboardHistoryItem(_ item: ClipboardHistoryItem) {
    guard ClipboardHistoryPasteboard.write(item.content) else {
      transientMessage = "无法写入剪贴板"
      return
    }
    transientMessage = "已复制到剪贴板"
  }

  // MARK: - Clipboard Assistant

  /// Pasteboard changeCount written by an assistant action itself; the toast must not re-trigger
  /// for its own "copy result" writes.
  private var suppressedAssistantChangeCount: Int?
  private var clipboardAssistantContent: ClipboardHistoryContent?
  private var lastClipboardAssistantRoutingChangeCount: Int?

  private enum ClipboardAssistantPresentationResult {
    case presented
    case unavailable
    case ignored
  }

  private func clipboardAssistantMessage(_ key: String) -> String {
    AppLocalization.string(key, language: languageStore.language)
  }

  private func clipboardAssistantMessage(_ key: String, _ argument: CVarArg) -> String {
    AppLocalization.format(key, locale: languageStore.language.locale, [argument])
  }

  private func handleCapturedClipboardContent(_ content: ClipboardHistoryContent) {
    let downloadableURL: URL?
    if case .text(let text) = content,
       DownloadURLClassifier.isLikelyDownloadable(text) {
      downloadableURL = HTTPURLParser.url(from: text)
    } else {
      downloadableURL = nil
    }
    routeCapturedClipboardContent(content, downloadableURL: downloadableURL)
  }

  private func routeCapturedClipboardContent(
    _ content: ClipboardHistoryContent,
    downloadableURL: URL?
  ) {
    let changeCount = NSPasteboard.general.changeCount
    guard lastClipboardAssistantRoutingChangeCount != changeCount else { return }
    lastClipboardAssistantRoutingChangeCount = changeCount

    switch presentClipboardAssistant(for: content) {
    case .presented, .ignored:
      guard downloadableURL != nil else { return }
      detectedLinkTask?.cancel()
      detectedLink = nil
    case .unavailable:
      guard clipboardMonitor.isEnabled, let downloadableURL else { return }
      presentDetectedLink(downloadableURL)
    }
  }

  private func presentClipboardAssistant(
    for content: ClipboardHistoryContent
  ) -> ClipboardAssistantPresentationResult {
    let settings = settingsStore.settings
    guard settings.clipboardAssistantEnabled else { return .unavailable }
    guard !voiceInput.isRecording, !voiceInput.isPreparing, !isIslandVisible else {
      clipboardAssistant.dismiss(animated: false)
      return .unavailable
    }
    if let suppressed = suppressedAssistantChangeCount,
       suppressed == NSPasteboard.general.changeCount {
      return .ignored
    }
    // The frontmost app at capture time is the app the user copied from.
    let sourceApplication = NSWorkspace.shared.frontmostApplication
    if let bundleIdentifier = sourceApplication?.bundleIdentifier,
       settings.clipboardAssistantBlacklist.contains(bundleIdentifier) {
      return .unavailable
    }
    guard var detection = ClipboardAssistantDetector.detect(
      content: content,
      enabledKinds: settings.clipboardAssistantEnabledKinds.isEmpty
        ? Set(ClipboardAssistantKind.allCases)
        : settings.clipboardAssistantEnabledKinds,
      offersDownload: settings.downloaderEnabled
    ) else { return .unavailable }
    detection.actions.append(.addToQuickNote)
    detection.actions.append(.share)
    if case .text = content,
       [.text, .chineseText, .code, .math].contains(detection.kind) {
      detection.actions.append(.sendToTeleprompter)
    }
    if let bundleIdentifier = sourceApplication?.bundleIdentifier,
       !bundleIdentifier.isEmpty,
       bundleIdentifier != Bundle.main.bundleIdentifier {
      detection.actions.append(.blockSourceApp(
        bundleIdentifier: bundleIdentifier,
        appName: sourceApplication?.localizedName ?? bundleIdentifier
      ))
    }
    clipboardAssistant.present(detection, visualStyle: settings.islandVisualStyle)
    guard clipboardAssistant.presentation.detection == detection else { return .unavailable }
    clipboardAssistantContent = content
    return .presented
  }

  private func presentDetectedLink(_ url: URL) {
    downloadURL = url.absoluteString
    selectModule(.download)
    detectedLink = url
    detectedLinkTask?.cancel()
    detectedLinkTask = Task { [weak self] in
      do {
        try await Task.sleep(for: .seconds(6))
      } catch {
        return
      }
      self?.detectedLink = nil
    }
  }

  private func performClipboardAssistantAction(_ action: ClipboardAssistantAction) {
    switch action {
    case .openURL(let url):
      NSWorkspace.shared.open(url)
    case .openDownload(let url):
      downloadURL = url.absoluteString
      selectModule(.download)
    case .revealInFinder(let url):
      NSWorkspace.shared.activateFileViewerSelecting([url])
    case .compress(let url):
      compressAssistantFile(url)
    case .share:
      guard let content = clipboardAssistantContent else {
        transientMessage = clipboardAssistantMessage("无法完成操作")
        clipboardAssistant.dismiss()
        return
      }
      let items = transferItems(from: content)
      guard !items.isEmpty else {
        transientMessage = clipboardAssistantMessage("剪贴板没有可共享内容")
        clipboardAssistant.dismiss()
        return
      }
      guard let anchor = clipboardAssistant.sharingAnchorView else {
        transientMessage = clipboardAssistantMessage("无法打开系统共享菜单")
        clipboardAssistant.dismiss()
        return
      }
      share(items, from: anchor)
    case .search(let text):
      let settings = settingsStore.settings
      if let url = settings.clipboardAssistantSearchEngine.queryURL(
        for: text,
        customURL: settings.clipboardAssistantCustomSearchURL
      ) {
        NSWorkspace.shared.open(url)
      } else {
        transientMessage = clipboardAssistantMessage("无法完成操作")
      }
    case .translate(let text):
      // Translate in the browser using the interface language as the target.
      let code = languageStore.language.translateTargetCode
      translationTask?.cancel()
      translationTask = Task { @MainActor [weak self] in
        let provider = await Self.translationProviderForCurrentIP()
        guard let self, !Task.isCancelled else { return }
        if let url = ClipboardAssistantTranslate.url(
          text: text,
          targetLanguageCode: code,
          provider: provider
        ) {
          NSWorkspace.shared.open(url)
        } else {
          transientMessage = clipboardAssistantMessage("无法完成操作")
        }
      }
    case .composeMail(let address):
      if settingsStore.settings.mailEnabled {
        mailComposeRequest = MailComposeRequest(recipient: address)
        selectModule(.mail)
        // The assistant fires from a collapsed island, so the compose page only becomes reachable
        // once the island expands on its own.
        islandExpansionRequested = true
      } else {
        openSystemMail(to: address)
      }
    case .copyText(let text):
      guard ClipboardHistoryPasteboard.write(.text(text)) else {
        transientMessage = clipboardAssistantMessage("无法完成操作")
        return
      }
      suppressedAssistantChangeCount = NSPasteboard.general.changeCount
      transientMessage = clipboardAssistantMessage("已复制")
    case .callPhone(let number):
      if let url = URL(string: "tel:\(number)") {
        NSWorkspace.shared.open(url)
      } else {
        transientMessage = clipboardAssistantMessage("无法完成操作")
      }
    case .blockSourceApp(let bundleIdentifier, _):
      var settings = settingsStore.settings
      settings.clipboardAssistantBlacklist.insert(bundleIdentifier)
      settingsStore.settings = settings
      clipboardAssistant.dismiss()
    case .addToQuickNote:
      guard let content = clipboardAssistantContent else {
        transientMessage = clipboardAssistantMessage("无法完成操作")
        return
      }
      receiveQuickNoteTransferItems(transferItems(from: content))
    case .sendToTeleprompter:
      guard case .text(let text)? = clipboardAssistantContent else {
        transientMessage = clipboardAssistantMessage("无法完成操作")
        return
      }
      sendQuickNoteToTeleprompter(text)
    case .saveImage(let data):
      saveClipboardImage(data)
    case .saveText(let text):
      saveAssistantText(text)
    case .createCalendarEvent(let title, let date, let isAllDay):
      createAssistantCalendarEvent(title: title, date: date, isAllDay: isAllDay)
    }
  }

  private nonisolated static func translationProviderForCurrentIP() async -> ClipboardAssistantTranslate.Provider {
    guard let url = URL(string: "https://ipinfo.io/country") else { return .google }
    var request = URLRequest(url: url)
    request.timeoutInterval = 5
    do {
      let (data, response) = try await URLSession.shared.data(for: request)
      guard (response as? HTTPURLResponse)?.statusCode == 200 else { return .google }
      return ClipboardAssistantTranslate.provider(
        forCountryCode: String(data: data, encoding: .utf8)
      )
    } catch {
      return .google
    }
  }

  private func openSystemMail(to address: String) {
    guard let url = URL(string: "mailto:\(address)") else {
      transientMessage = clipboardAssistantMessage("无法完成操作")
      return
    }
    guard NSWorkspace.shared.open(url) else {
      transientMessage = clipboardAssistantMessage("无法完成操作")
      return
    }
  }

  private func compressAssistantFile(_ source: URL) {
    guard FileManager.default.fileExists(atPath: source.path) else {
      transientMessage = clipboardAssistantMessage("无法完成操作")
      return
    }
    let panel = NSSavePanel()
    panel.directoryURL = source.deletingLastPathComponent()
    panel.nameFieldStringValue = source.lastPathComponent + ".zip"
    panel.allowedContentTypes = [.zip]
    panel.canCreateDirectories = true
    panel.prompt = clipboardAssistantMessage("压缩为 ZIP")
    WindowPlacement.prepareModal(panel, on: WindowPlacement.screenUnderMouse())
    guard panel.runModal() == .OK, let destination = panel.url else { return }

    Task { @MainActor [weak self] in
      let error = await Task.detached(priority: .userInitiated) {
        await Self.zipArchiveError(source: source, destination: destination)
      }.value
      guard let self else { return }
      if let error {
        self.transientMessage = self.clipboardAssistantMessage("操作失败：%@", error)
      } else {
        self.transientMessage = self.clipboardAssistantMessage("已保存到 %@", destination.path)
      }
    }
  }

  nonisolated static func zipArchiveError(source: URL, destination: URL) async -> String? {
    var isDirectory: ObjCBool = false
    guard FileManager.default.fileExists(atPath: source.path, isDirectory: &isDirectory) else {
      return "源文件不存在"
    }
    let sourceAccess = source.startAccessingSecurityScopedResource()
    let destinationDirectory = destination.deletingLastPathComponent()
    let destinationAccess = destinationDirectory.startAccessingSecurityScopedResource()
    defer {
      if sourceAccess { source.stopAccessingSecurityScopedResource() }
      if destinationAccess { destinationDirectory.stopAccessingSecurityScopedResource() }
    }

    var arguments = ["-c", "-k", "--sequesterRsrc"]
    if isDirectory.boolValue { arguments.append("--keepParent") }
    arguments += [source.lastPathComponent, destination.path]
    do {
      let output = try await AIAgentProcessRunner.run(
        executableURL: URL(fileURLWithPath: "/usr/bin/ditto"),
        arguments: arguments,
        workingDirectoryURL: source.deletingLastPathComponent(),
        timeout: 5 * 60,
        maximumOutputBytes: 1,
        maximumErrorBytes: 256 * 1_024
      )
      if output.didTimeout {
        return "压缩操作超时"
      }
      guard output.status == 0 else {
        return output.standardError.isEmpty ? "无法创建 ZIP 文件" : output.standardError
      }
      return nil
    } catch {
      return error.localizedDescription
    }
  }

  private func saveClipboardImage(_ data: Data) {
    let formatter = DateFormatter()
    formatter.dateFormat = "yyyyMMdd-HHmmss"
    let name = "clipboard-\(formatter.string(from: Date())).png"
    let destination: URL
    if settingsStore.settings.clipboardAssistantPromptsForImageSaveLocation {
      let panel = NSSavePanel()
      panel.directoryURL = downloadDirectory
      panel.nameFieldStringValue = name
      panel.allowedContentTypes = [.png]
      panel.canCreateDirectories = true
      panel.prompt = clipboardAssistantMessage("保存图片")
      WindowPlacement.prepareModal(panel, on: WindowPlacement.screenUnderMouse())
      guard panel.runModal() == .OK, let url = panel.url else { return }
      destination = url
    } else {
      destination = downloadDirectory.appendingPathComponent(name)
    }

    let directory = destination.deletingLastPathComponent()
    let scopedAccess = directory.startAccessingSecurityScopedResource()
    defer { if scopedAccess { directory.stopAccessingSecurityScopedResource() } }
    do {
      try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
      try data.write(to: destination, options: .atomic)
      transientMessage = clipboardAssistantMessage("已保存到 %@", destination.path)
    } catch {
      transientMessage = clipboardAssistantMessage("操作失败：%@", error.localizedDescription)
    }
  }

  /// Saves long copied text as a standalone file in the download directory and reveals it.
  private func saveAssistantText(_ text: String) {
    let directory = downloadDirectory
    let scopedAccess = directory.startAccessingSecurityScopedResource()
    defer { if scopedAccess { directory.stopAccessingSecurityScopedResource() } }
    do {
      try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
      let formatter = DateFormatter()
      formatter.dateFormat = "yyyyMMdd-HHmmss"
      let url = directory.appendingPathComponent("clipboard-\(formatter.string(from: Date())).txt")
      try text.write(to: url, atomically: true, encoding: .utf8)
      NSWorkspace.shared.activateFileViewerSelecting([url])
      transientMessage = clipboardAssistantMessage("已保存到 %@", url.path)
    } catch {
      transientMessage = clipboardAssistantMessage("操作失败：%@", error.localizedDescription)
    }
  }

  /// Creates an all-day (or timed) calendar event from a recognized date; errors surface inline.
  private func createAssistantCalendarEvent(title: String, date: Date, isAllDay: Bool) {
    do {
      if isAllDay {
        try calendar.createEvent(
          title: title,
          startDate: date,
          endDate: date.addingTimeInterval(86_400),
          isAllDay: true
        )
      } else {
        try calendar.createEvent(
          title: title,
          startDate: date,
          endDate: date.addingTimeInterval(3_600),
          isAllDay: false
        )
      }
      transientMessage = clipboardAssistantMessage("已创建日程")
    } catch {
      transientMessage = clipboardAssistantMessage("操作失败：%@", error.localizedDescription)
    }
  }

  /// Applies the hold-left + right-click quick copy gesture from settings.
  private func applyAssistantMouseGesture() {
    let enabled = settingsStore.settings.clipboardAssistantEnabled
      && settingsStore.settings.clipboardAssistantMouseGestureEnabled
    // The gesture only simulates ⌘C; the shared pasteboard monitor picks up the new copy.
    let granted = clipboardAssistant.setMouseGesture(enabled: enabled, onQuickCopy: {})
    if enabled, !granted {
      refreshAssistantAccessibility()
    }
  }

  func sendQuickNoteToTeleprompter(_ content: String) {
    let content = content.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !content.isEmpty else {
      transientMessage = "随记没有可发送的内容"
      return
    }
    UserDefaults.standard.set(content, forKey: "toolbox.teleprompterScript")
    transientMessage = "已发送到提词器"
    presentTeleprompter()
  }

  func receiveQuickNoteTransferItems(_ items: [TransferDropItem]) {
    let content = transferableText(from: items)
    guard !content.isEmpty else {
      transientMessage = "没有可写入随记的内容"
      return
    }
    Task {
      if await quickNotes.create(markdown: content) {
        transientMessage = "已创建随记"
        selectModule(.quickNotes)
      }
    }
  }

  func sendClipboardHistoryItemToQuickNote(_ item: ClipboardHistoryItem) {
    receiveQuickNoteTransferItems(transferItems(from: item.content))
  }

  private func transferItems(from content: ClipboardHistoryContent) -> [TransferDropItem] {
    switch content {
    case let .text(value):
      [.text(value)]
    case let .file(reference):
      [.file(reference.url)]
    case let .image(data):
      [.image(data)]
    }
  }

  private func transferableText(from items: [TransferDropItem]) -> String {
    items.map { item in
      switch item {
      case let .text(value): value
      case let .link(url): url.absoluteString
      case let .file(url): "[\(url.lastPathComponent)](\(url.absoluteString))"
      case .image: "剪贴板图片"
      }
    }
    .joined(separator: "\n\n")
    .trimmingCharacters(in: .whitespacesAndNewlines)
  }

  func receiveTransferItems(_ items: [TransferDropItem]) {
    let files = items.compactMap { item -> URL? in
      if case .file(let url) = item { return url }
      return nil
    }
    if !files.isEmpty { addToShelf(files) }

    if let link = items.compactMap({ item -> URL? in
      if case .link(let url) = item { return url }
      return nil
    }).first {
      prepareDownload(link)
    } else if files.isEmpty {
      transientMessage = "中转站支持文件或媒体链接"
    }
  }

  func prepareDetectedLink() {
    guard let detectedLink else { return }
    prepareDownload(detectedLink)
  }

  func share(_ items: [TransferDropItem], from view: NSView? = nil) {
    guard !items.isEmpty else { return }
    let values = items.map(\.shareValue)
    let anchor = Self.sharingPickerAnchor(from: view)
    guard let anchor else {
      transientMessage = "无法打开系统共享菜单"
      return
    }
    let picker = NSSharingServicePicker(items: values)
    picker.delegate = sharingPickerDelegate
    let previousPicker = sharingPicker
    sharingPicker = picker
    sharingPickerDismissesClipboardAssistant = anchor.window is ClipboardAssistantWindow
    isSharingPickerVisible = anchor.window is IslandPanel
    previousPicker?.close()
    picker.show(relativeTo: anchor.bounds, of: anchor, preferredEdge: .minY)
  }

  static func sharingPickerAnchor(
    from view: NSView?,
    at point: CGPoint = NSEvent.mouseLocation,
    windows: [NSWindow] = NSApp.windows
  ) -> NSView? {
    if let view { return view }
    let interactivePanels = windows.compactMap { $0 as? IslandPanel }.filter {
      $0.isVisible && !$0.ignoresMouseEvents
    }
    return interactivePanels.first(where: { $0.frame.contains(point) })?.contentView
      ?? interactivePanels.first?.contentView
  }

  func shareFromPasteboard(from view: NSView? = nil) {
    let payloads = TransferPasteboard.readShareableItems()
    let items: [TransferDropItem] = payloads.map { payload in
      switch payload {
      case .file(let url): .file(url)
      case .text(let value): .text(value)
      }
    }
    guard !items.isEmpty else {
      transientMessage = "剪贴板没有可共享内容"
      return
    }
    share(items, from: view)
  }

  private func sharingPickerDidComplete(_ picker: NSSharingServicePicker) {
    guard sharingPicker === picker else { return }
    let dismissesClipboardAssistant = sharingPickerDismissesClipboardAssistant
    sharingPicker = nil
    sharingPickerDismissesClipboardAssistant = false
    isSharingPickerVisible = false
    if dismissesClipboardAssistant { clipboardAssistant.dismiss() }
  }

  private func prepareDownload(_ url: URL) {
    downloadURL = url.absoluteString
    selectModule(.download)
    detectedLinkTask?.cancel()
    detectedLink = nil
    transientMessage = "链接已放入下载中转"
  }

  func startDownload() {
    let request: DownloadRequest
    do {
      request = try DownloadRequest(
        urlString: downloadURL,
        mode: downloadMode,
        outputDirectory: downloadDirectory
      )
    } catch {
      if hasActiveDownloads {
        transientMessage = "链接或输出目录无效"
      } else {
        downloadState = .failed("链接或输出目录无效")
      }
      return
    }

    let taskID = UUID()
    activeDownloadID = taskID
    activeDownloadIDs.insert(taskID)
    downloadTaskStates[taskID] = .preparing
    downloadTaskURLs[taskID] = request.urlString
    downloadTaskOrder.append(taskID)
    refreshActiveDownloads()
    downloadState = .preparing
    beginVideoDownloadIsland(forURLString: request.urlString)
    let scopedAccess = downloadDirectory.startAccessingSecurityScopedResource()
    let task = Task { [weak self, downloadService] in
      defer {
        if scopedAccess { request.outputDirectory.stopAccessingSecurityScopedResource() }
      }
      do {
        let result = try await downloadService.download(
          request,
          taskID: taskID
        ) { [weak self] event in
          await MainActor.run {
            guard let self, self.activeDownloadIDs.contains(taskID) else { return }
            if case .progress(let fraction, let speed, let eta) = event {
              let state = DownloadUIState.downloading(
                fraction: fraction,
                speed: speed,
                eta: eta
              )
              self.downloadTaskStates[taskID] = state
              self.refreshActiveDownloads()
              guard self.activeDownloadID == taskID else { return }
              self.downloadState = state
              self.updateVideoDownloadIsland(fraction: fraction, isFinished: false)
            }
          }
        }
        guard !Task.isCancelled else {
          await MainActor.run {
            self?.finishDownloadTask(taskID, state: .idle, showsCompletion: false)
          }
          return
        }
        await MainActor.run {
          guard let self else { return }
          self.addToShelf([result.fileURL])
          self.notices.enqueue(
            IslandNotice(
              id: "download-\(taskID.uuidString)",
              title: "下载完成",
              detail: result.fileURL.lastPathComponent,
              kind: .success,
              side: .right
            ))
          self.finishDownloadTask(
            taskID,
            state: .completed(result.fileURL),
            showsCompletion: true
          )
        }
      } catch is CancellationError {
        await MainActor.run {
          self?.finishDownloadTask(taskID, state: .idle, showsCompletion: false)
        }
      } catch {
        await MainActor.run {
          self?.finishDownloadTask(
            taskID,
            state: .failed(Self.downloadErrorText(error)),
            showsCompletion: false
          )
        }
      }
    }
    downloadTasks[taskID] = task
  }

  func cancelDownload(taskID: UUID) {
    guard activeDownloadIDs.contains(taskID) else { return }
    downloadTasks[taskID]?.cancel()
    Task { [downloadService] in await downloadService.cancel(taskID: taskID) }
  }

  func cancelAllDownloads() {
    for task in downloadTasks.values { task.cancel() }
    Task { [downloadService] in await downloadService.cancelAll() }
  }

  private func finishDownloadTask(
    _ taskID: UUID,
    state: DownloadUIState,
    showsCompletion: Bool
  ) {
    guard activeDownloadIDs.remove(taskID) != nil else { return }
    downloadTasks[taskID] = nil
    downloadTaskStates[taskID] = state

    let wasActive = activeDownloadID == taskID
    if wasActive,
       let nextID = downloadTaskOrder.reversed().first(where: { activeDownloadIDs.contains($0) }),
       let nextState = downloadTaskStates[nextID],
       let nextURL = downloadTaskURLs[nextID] {
      activeDownloadID = nextID
      downloadState = nextState
      beginVideoDownloadIsland(forURLString: nextURL)
      if case .downloading(let fraction, _, _) = nextState {
        updateVideoDownloadIsland(fraction: fraction, isFinished: false)
      }
    } else if wasActive {
      activeDownloadID = nil
      downloadState = state
      if showsCompletion {
        updateVideoDownloadIsland(fraction: 1, isFinished: true)
      } else {
        endVideoDownloadIsland()
      }
    }

    downloadTaskStates[taskID] = nil
    downloadTaskURLs[taskID] = nil
    downloadTaskOrder.removeAll { $0 == taskID }
    refreshActiveDownloads()
  }

  private func refreshActiveDownloads() {
    activeDownloads = downloadTaskOrder.compactMap { taskID in
      guard activeDownloadIDs.contains(taskID),
            let state = downloadTaskStates[taskID],
            let urlString = downloadTaskURLs[taskID]
      else { return nil }
      return DownloadTaskSnapshot(id: taskID, urlString: urlString, state: state)
    }
  }

  private func apply(settings: FeatureSettings) {
    // Regular UI appearance is controlled by user settings; the island panel is separately pinned to dark at the window level (see IslandPanel).
    NSApp.appearance = settings.appearanceMode.nsAppearance
    media.setPreferredSource(settings.mediaSource)
    voiceInput.setContextualStrings(VoiceLexicon.contextualTerms(for: settings.voiceEnabledLexicons))
    pomodoro.notificationsMuted = settings.notificationsMuted
    configureUpdatePolling(enabled: settings.updateChecksEnabled)
    configureVoiceRecordingCleanup(policy: settings.voiceRecordingCleanupPolicy)
    if settings.aiProgressEnabled {
      aiMonitor.start()
      if selectedModule == .aiMonitor {
        aiMonitor.loadUsageHistory()
      }
    } else {
      aiMonitor.stop()
      clearActiveAINotices()
      powerAssertions.setAIActivityActive(false)
    }
    aiAgent.start()
    syncAIActivityPowerAssertion(aiMonitor.state)
    if settings.mediaEnabled {
      media.start()
      updateSpectrumMonitoring()
      consumeMediaSnapshot(media.snapshot)
    } else {
      media.stop()
      clearMediaNotices()
    }
    if !settings.weatherEnabled {
      weatherTask?.cancel()
      weatherSnapshotsByLocationID = [:]
    }
    if settings.systemMonitorEnabled {
      systemMonitor.start()
    } else {
      systemMonitor.stop()
    }
    backgroundSounds.apply(
      sound: settings.systemBackgroundSound,
      enabled: settings.systemBackgroundSoundEnabled,
      stopsWhenUnused: settings.systemBackgroundSoundStopsWhenUnused
    )
    consumeBackgroundSoundPlayback()
    if settings.sideNoticesEnabled {
      focusMode.start()
      audioOutput.start()
    } else {
      focusMode.stop()
      audioOutput.stop()
    }
    if settings.calendarEnabled {
      calendar.start()
    } else {
      calendar.stop()
    }
    if settings.sideNoticesEnabled, settings.browserDownloadIslandEnabled {
      browserDownloads.start()
      consumeBrowserDownloadSnapshot(browserDownloads.snapshot)
    } else {
      browserDownloads.stop()
      clearBrowserDownloadNotices()
    }
    if settings.lockScreenInfoEnabled || settings.batteryMonitorEnabled {
      battery.start()
    } else {
      battery.stop()
    }
    if !settings.batteryMonitorEnabled {
      networkBattery.stop()
    }
    if settings.mailEnabled {
      mail.start(accountNames: settings.mailAccountNames)
    } else {
      mail.stop()
      hasLoadedMail = false
      knownMailMessageIDs.removeAll()
    }
    if settings.toolboxEnabled {
      alarms.resume()
    } else {
      alarms.suspend()
      pomodoro.stop()
      screenCleaning.stopAll()
      cleaningPowerState = nil
      powerAssertions.releaseAll()
    }
    if selectedModule == .agenda { refreshAgendaIfEnabled() }
    clipboardMonitor.setEnabled(
      settings.downloaderEnabled && settings.clipboardDetectionEnabled
    )
    // The shared pasteboard monitor feeds both history recording and the copy assistant.
    clipboardHistoryMonitor.setEnabled(
      settings.clipboardHistoryEnabled || settings.clipboardAssistantEnabled
    )
    if settings.clipboardAssistantEnabled {
      clipboardAssistant.setTriggers(
        hotkey: settings.clipboardAssistantTriggerConfiguration.hotkey,
        mouseButton: settings.clipboardAssistantMouseButton
      )
      clipboardAssistant.isLightweightMode = settings.clipboardAssistantLightweightMode
      clipboardAssistant.displayDuration = settings.clipboardAssistantDisplayDuration
    } else {
      clipboardAssistant.setTriggers(hotkey: nil, mouseButton: nil)
      clipboardAssistant.dismiss()
    }
    applyAssistantMouseGesture()
    if !settings.downloaderEnabled, hasActiveDownloads {
      cancelAllDownloads()
    }
    let durationChanged =
      lastActivityNoticeDisplayDuration != settings.activityNoticeDisplayDuration
    lastActivityNoticeDisplayDuration = settings.activityNoticeDisplayDuration
    if settings.sideNoticesEnabled {
      if durationChanged {
        restartActivityNoticesForDurationChange()
      }
      consumeAIState(aiMonitor.state)
      consumeMediaSnapshot(media.snapshot)
      consumeFocusModeStatus(focusMode.status, showsTransition: false)
      refreshUpdateNotices()
    } else {
      notices.removeAll()
      activeAINoticeIDs.removeAll()
      activityNoticeShownIDs.removeAll()
      mediaActivityPresented = false
      notices.removeAll(withIDPrefix: updateNoticePrefix)
    }
    voiceInputInputMonitoringAccessGranted = GlobalHotkeyManager.hasInputMonitoringAccess
    if settings.voiceInputEnabled {
      let preset = settings.voiceInputHotkeyPreset
      let mode = settings.voiceInputMode
      let registration = hotkeyManager.register(
        hotkey: preset,
        onKeyDown: { [weak self] in
          guard let self else { return }
          switch mode {
          case .toggle:
            self.voiceInput.toggle()
          case .pushToTalk:
            self.voiceInput.start()
          }
        },
        onKeyUp: { [weak self] in
          guard let self else { return }
          if mode == .pushToTalk {
            self.voiceInput.stop()
          }
        }
      )
      if registration == .registrationFailed {
        transientMessage = "无法注册语音输入快捷键"
      }
    } else {
      voiceInput.cancel()
      hotkeyManager.unregister()
    }
    refreshToolboxReminderNotice()
  }

  private func configureUpdatePolling(enabled: Bool) {
    guard isUpdatePollingEnabled != enabled else { return }
    isUpdatePollingEnabled = enabled
    updatePollingTask?.cancel()
    updatePollingTask = nil
    guard enabled else {
      releaseTask?.cancel()
      releaseTask = nil
      return
    }

    updatePollingTask = Task { [weak self] in
      while !Task.isCancelled {
        guard let self else { return }
        await self.aiAgent.refreshCLIs()
        guard !Task.isCancelled else { return }
        self.checkForUpdates(manual: false)
        do {
          try await Task.sleep(for: .seconds(600))
        } catch {
          return
        }
      }
    }
  }

  private func configureVoiceRecordingCleanup(policy: VoiceRecordingCleanupPolicy) {
    guard appliedVoiceRecordingCleanupPolicy != policy else { return }
    appliedVoiceRecordingCleanupPolicy = policy
    voiceRecordingCleanupTask?.cancel()
    voiceRecordingCleanupTask = nil
    voiceHistory.cleanupOldRecordings(policy: policy)
    guard let days = policy.daysThreshold else { return }

    voiceRecordingCleanupTask = Task { [weak self] in
      while !Task.isCancelled {
        do {
          try await Task.sleep(for: .seconds(days * 24 * 60 * 60))
        } catch {
          return
        }
        guard let self, !Task.isCancelled else { return }
        self.voiceHistory.cleanupOldRecordings(policy: policy)
      }
    }
  }

  private func refreshUpdateNotices() {
    guard settingsStore.settings.sideNoticesEnabled else {
      notices.removeAll(withIDPrefix: updateNoticePrefix)
      return
    }

    let selectedUpdate: (id: String, title: String, symbol: String)?
    if productUpdateAvailable {
      selectedUpdate = ("product", "Zisla", "app.fill")
    } else if let update = aiAgent.cliUpdates.first {
      selectedUpdate = ("cli-\(update.kind.rawValue)", update.kind.displayName, "sparkles")
    } else {
      selectedUpdate = nil
    }
    guard let selectedUpdate else {
      notices.removeAll(withIDPrefix: updateNoticePrefix)
      return
    }

    let left = IslandNotice(
      id: "\(updateNoticePrefix)\(selectedUpdate.id)-left",
      title: selectedUpdate.title,
      kind: .info,
      side: .left,
      style: .status,
      symbolName: selectedUpdate.symbol
    )
    let right = IslandNotice(
      id: "\(updateNoticePrefix)\(selectedUpdate.id)-right",
      title: "查看更新",
      kind: .info,
      side: .right,
      style: .status,
      symbolName: "arrow.up.circle"
    )
    let activeIDs = Set([left.id, right.id])
    for notice in notices.left + notices.right where notice.id.hasPrefix(updateNoticePrefix) && !activeIDs.contains(notice.id) {
      notices.remove(id: notice.id)
    }
    if !notices.updateIfPresent(left) { notices.enqueue(left, expiresAfter: nil) }
    if !notices.updateIfPresent(right) { notices.enqueue(right, expiresAfter: nil) }
  }

  // MARK: - Voice model discovery

  private func deliverVoiceRecording(_ recording: VoiceRecordingResult) {
    let inputTarget = voiceInputTarget
    let targetProcessIdentifier = voiceInputTargetProcessIdentifier
    let targetMouseLocation = voiceInputTargetMouseLocation
    voiceInputTarget = nil
    voiceInputTargetProcessIdentifier = nil
    voiceInputTargetMouseLocation = nil
    let rawTranscript = recording.transcript.trimmingCharacters(in: .whitespacesAndNewlines)
    let retainsAudio = settingsStore.settings.voiceRecordingRetentionEnabled
    let enabledVoiceLexicons = settingsStore.settings.voiceEnabledLexicons
    let structuredFormattingEnabled = settingsStore.settings.voiceStructuredFormattingEnabled
    let historySaved = voiceHistory.record(recording, retainAudio: retainsAudio)
    guard !rawTranscript.isEmpty else {
      transientMessage = historySaved
        ? (retainsAudio ? "录音已保存，但未识别到文字" : "未识别到文字")
        : (retainsAudio ? "录音文件已保留，但记录索引保存失败" : "语音记录保存失败")
      return
    }
    let lexiconNormalizedTranscript = VoiceLexicon.normalizeTranscript(
      rawTranscript,
      for: enabledVoiceLexicons
    )
    let localTranscriptSaved = lexiconNormalizedTranscript == rawTranscript
      || voiceHistory.updateProcessedTranscript(
        id: recording.id,
        transcript: lexiconNormalizedTranscript
      )
    guard let target = voicePostProcessingTarget() else {
      deliverVoiceTranscript(
        lexiconNormalizedTranscript,
        to: targetProcessIdentifier,
        at: targetMouseLocation,
        target: inputTarget,
        message: historySaved && localTranscriptSaved ? "语音转写已保存" : "语音转写完成；记录保存失败"
      )
      return
    }
    // Recording already ended and the island HUD is gone, so without this the cleanup round-trip
    // looks like the shortcut simply swallowed the dictation.
    transientMessage = "正在整理语音…"
    beginVoiceProcessingIndicator()
    voicePostProcessingQueue.enqueue { [weak self] in
      guard let self else { return }
      defer { self.endVoiceProcessingIndicator() }
      do {
        let response = try await self.complete(
          using: target,
          systemPrompt: VoiceTranscriptPostProcessor.systemPrompt(
            enabledLexicons: enabledVoiceLexicons,
            structuredFormattingEnabled: structuredFormattingEnabled
          ),
          messages: VoiceTranscriptPostProcessor.messages(
            for: rawTranscript,
            lexiconNormalizedTranscript: lexiconNormalizedTranscript
          )
        )
        guard !Task.isCancelled else { return }
        let delivered = VoiceLexicon.normalizeTranscript(
          VoiceTranscriptPostProcessor.deliveredText(
            response,
            fallback: lexiconNormalizedTranscript
          ),
          for: enabledVoiceLexicons,
          contextualTranscript: rawTranscript
        )
        let processedTranscriptSaved = self.voiceHistory.updateProcessedTranscript(
          id: recording.id,
          transcript: delivered
        )
        self.deliverVoiceTranscript(
          delivered,
          to: targetProcessIdentifier,
          at: targetMouseLocation,
          target: inputTarget,
          message: historySaved && processedTranscriptSaved
            ? "语音整理结果已保存"
            : "语音整理完成；记录保存失败"
        )
      } catch is CancellationError {
        return
      } catch {
        guard !Task.isCancelled else { return }
        self.deliverVoiceTranscript(
          lexiconNormalizedTranscript,
          to: targetProcessIdentifier,
          at: targetMouseLocation,
          target: inputTarget,
          message: "语音转写完成；整理失败"
        )
      }
    }
  }

  /// Shows the collapsed-island "voice processing" wings (left: mic, right: a random thinking orb)
  /// for the duration of AI transcript cleanup. Each run picks a fresh random orb animation.
  private func beginVoiceProcessingIndicator() {
    voiceProcessingOperationCount += 1
    guard !isProcessingVoiceTranscript else { return }
    isProcessingVoiceTranscript = true
    let orbState = ThinkingOrbState.taskStates.randomElement() ?? .working
    let left = IslandNotice(
      id: "voice-processing-left",
      title: "正在整理语音",
      kind: .info,
      side: .left,
      style: .status,
      symbolName: "mic.fill",
      metadata: ["orbState": orbState.rawValue]
    )
    let right = IslandNotice(
      id: "voice-processing-right",
      title: "正在整理语音",
      kind: .info,
      side: .right,
      style: .status,
      metadata: ["orbState": orbState.rawValue]
    )
    for notice in [left, right] {
      if !notices.updateIfPresent(notice) {
        notices.enqueue(notice, expiresAfter: nil)
      }
    }
  }

  private func endVoiceProcessingIndicator() {
    voiceProcessingOperationCount = max(0, voiceProcessingOperationCount - 1)
    guard voiceProcessingOperationCount == 0, isProcessingVoiceTranscript else { return }
    isProcessingVoiceTranscript = false
    notices.remove(id: "voice-processing-left")
    notices.remove(id: "voice-processing-right")
  }

  private func voicePostProcessingTarget() -> AIProcessingTarget? {
    guard let reference = selectedVoiceModelConfiguration else { return nil }
    switch reference.source {
    case .local:
      guard let configuration = aiAgent.store.localModel(id: reference.id),
            configuration.isEnabled else {
        return nil
      }
      let model = configuration.modelName.trimmingCharacters(in: .whitespacesAndNewlines)
      guard !model.isEmpty else { return nil }
      return .http(
        endpoint: configuration.endpoint,
        protocolKind: .openAICompatible,
        model: model,
        apiKey: nil,
        effort: nil
      )
    case .channel:
      guard let channel = aiAgent.store.channel(id: reference.id),
            channel.isEnabled,
            channel.protocolKind == .openAICompatible || channel.protocolKind == .anthropicMessages,
            let endpointGroup = channel.endpointGroups.first,
            let baseURL = endpointGroup.baseURLs.first?.trimmingCharacters(in: .whitespacesAndNewlines),
            !baseURL.isEmpty,
            let accountID = endpointGroup.accountIDs.first,
            let account = aiAgent.store.account(id: accountID),
            account.credentialKind == .apiKey,
            let apiKey = try? aiAgent.store.secret(for: account),
            !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
        return nil
      }
      let model = channel.defaultModel.trimmingCharacters(in: .whitespacesAndNewlines)
      guard !model.isEmpty else { return nil }
      return .http(
        endpoint: AIEndpoint(name: channel.name, baseURL: baseURL, kind: .openAICompatible),
        protocolKind: channel.protocolKind,
        model: model,
        apiKey: apiKey.trimmingCharacters(in: .whitespacesAndNewlines),
        effort: channel.effort
      )
    }
  }

  private func complete(
    using target: AIProcessingTarget,
    systemPrompt: String,
    messages: [AIOutboundMessage]
  ) async throws -> String {
    switch target {
    case let .http(endpoint, protocolKind, model, apiKey, effort):
      return try await AIChatClient().complete(
        endpoint: endpoint,
        protocolKind: protocolKind,
        model: model,
        systemPrompt: systemPrompt,
        messages: messages,
        apiKey: apiKey,
        effort: effort
      ).content
    case let .cliProfile(accountID, model):
      return try await aiAgent.completeWithCLIProfile(
        accountID: accountID,
        systemPrompt: systemPrompt,
        messages: messages,
        model: model
      )
    }
  }

  private func deliverVoiceTranscript(
    _ transcript: String,
    to targetProcessIdentifier: pid_t?,
    at targetMouseLocation: CGPoint?,
    target: VoiceTranscriptDeliveryTarget?,
    message: String
  ) {
    switch voiceTranscriptDelivery.deliver(
      transcript,
      to: targetProcessIdentifier,
      at: targetMouseLocation,
      target: target
    ) {
    case .copiedAndPasted:
      transientMessage = "\(message)；已输入当前文本框并复制"
    case .copiedOnly:
      if targetProcessIdentifier != nil, !CGPreflightPostEventAccess() {
        transientMessage = "\(message)；已复制。请在系统弹出的授权界面允许 zisla 后重试"
      } else {
        transientMessage = "\(message)；已复制，未能输入原文本框"
      }
    case .copyFailed:
      transientMessage = "无法复制语音转写结果"
    }
  }

  private func requestVoiceInputPostEventAccessIfNeeded() {
    guard VoiceTranscriptDelivery.shouldRequestEventSynthesisAccess(
      hasAccess: CGPreflightPostEventAccess(),
      hasRequestedInCurrentLaunch: hasRequestedVoiceInputPostEventAccess
    ) else { return }

    hasRequestedVoiceInputPostEventAccess = true
    let authorizationHost = WindowPlacement.authorizationPromptHost()
    defer {
      authorizationHost?.orderOut(nil)
      authorizationHost?.close()
    }
    VoiceTranscriptDelivery.requestEventSynthesisAccess()
  }

  func playVoiceRecording(id: UUID) {
    guard let entry = voiceHistory.entries.first(where: { $0.id == id }),
          let url = voiceHistory.audioURL(for: entry) else {
      transientMessage = "无法播放该语音原文件"
      return
    }
    if voiceRecordingPlayer.play(id: id, url: url) {
      transientMessage = "正在播放原始录音"
    } else {
      transientMessage = "无法播放该语音原文件"
    }
  }

  func revealVoiceRecording(id: UUID) {
    guard let entry = voiceHistory.entries.first(where: { $0.id == id }),
          let url = voiceHistory.audioURL(for: entry) else {
      transientMessage = "未找到该语音原文件"
      return
    }
    NSWorkspace.shared.activateFileViewerSelecting([url])
  }

  func openVoiceRecordingsDirectory() {
    do {
      try FileManager.default.createDirectory(
        at: AppPaths.voiceRecordings,
        withIntermediateDirectories: true
      )
      NSWorkspace.shared.open(AppPaths.voiceRecordings)
    } catch {
      transientMessage = "无法打开语音记录目录：\(error.localizedDescription)"
    }
  }

  func removeVoiceRecording(id: UUID) {
    voiceRecordingPlayer.stop()
    voiceHistory.remove(id: id)
  }

  func removeVoiceRecordings(ids: Set<UUID>) {
    guard !ids.isEmpty else { return }
    voiceRecordingPlayer.stop()
    voiceHistory.removeBatch(ids: ids)
  }

  func removeAllVoiceRecordings() {
    voiceRecordingPlayer.stop()
    voiceHistory.removeAll()
  }

  private static func frontmostVoiceInputTargetProcessIdentifier() -> pid_t? {
    guard let application = NSWorkspace.shared.frontmostApplication,
          application.processIdentifier != NSRunningApplication.current.processIdentifier else {
      return nil
    }
    return application.processIdentifier
  }

  /// Restores focus to the target app immediately after recording ends, while AI processing may still delay delivery.
  /// The saved target PID remains available so delivery can verify frontmost status again before pasting.
  func restoreVoiceInputTargetFocus() {
    guard let pid = voiceInputTargetProcessIdentifier else { return }
    VoiceTranscriptDelivery.reactivateTargetApplication(pid)
    if let voiceInputTarget {
      _ = VoiceTranscriptDelivery.focusTarget(voiceInputTarget)
    }
  }

  /// Tests the current model endpoint and discovers available models.
  func discoverModels() {
    guard let target = voicePostProcessingTarget() else {
      voiceModelDiscoveryState = .failed("请先在上方添加、启用并选择一个模型配置")
      discoveredModels = []
      return
    }
    guard case let .http(endpoint, _, _, apiKey, _) = target else {
      voiceModelDiscoveryState = .failed("官方 CLI 档案不支持 API 模型发现")
      discoveredModels = []
      return
    }
    voiceModelDiscoveryState = .testing
    Task { @MainActor in
      let service = AIModelDiscoveryService()
      do {
        let models = try await service.models(for: endpoint, apiKey: apiKey)
        self.discoveredModels = models
        self.voiceModelDiscoveryState = .success(models.count)
      } catch {
        self.voiceModelDiscoveryState = .failed(error.localizedDescription)
        self.discoveredModels = []
      }
    }
  }

  var selectedVoiceModelConfiguration: AIModelConfigurationReference? {
    let reference = settingsStore.settings.voiceModelConfiguration
    guard let reference, isSelectableVoiceModelConfiguration(reference) else { return nil }
    return reference
  }

  func selectVoiceModelConfiguration(_ reference: AIModelConfigurationReference?) {
    guard let reference else {
      settingsStore.settings.voiceModelConfiguration = nil
      resetVoiceModelDiscovery()
      return
    }
    guard isSelectableVoiceModelConfiguration(reference) else {
      settingsStore.settings.voiceModelConfiguration = nil
      resetVoiceModelDiscovery()
      return
    }
    settingsStore.settings.voiceModelConfiguration = reference
    resetVoiceModelDiscovery()
  }

  private func isSelectableVoiceModelConfiguration(_ reference: AIModelConfigurationReference) -> Bool {
    switch reference.source {
    case .local:
      aiAgent.store.localModel(id: reference.id)?.isEnabled == true
    case .channel:
      aiAgent.store.channel(id: reference.id)?.isEnabled == true
    }
  }

  func voiceModelConfigurationTitle(_ reference: AIModelConfigurationReference) -> String {
    switch reference.source {
    case .local:
      guard let configuration = aiAgent.store.localModel(id: reference.id) else { return "本地模型" }
      let modelName = configuration.modelName.trimmingCharacters(in: .whitespacesAndNewlines)
      return modelName.isEmpty ? configuration.name : modelName
    case .channel:
      guard let channel = aiAgent.store.channel(id: reference.id) else { return "远端模型" }
      let modelName = channel.defaultModel.trimmingCharacters(in: .whitespacesAndNewlines)
      return modelName.isEmpty ? channel.name : modelName
    }
  }

  func voiceModelConfigurationDetail(_ reference: AIModelConfigurationReference) -> String {
    switch reference.source {
    case .local:
      guard let model = aiAgent.store.localModel(id: reference.id) else { return "" }
      return "本地 · \(model.endpoint.baseURL)"
    case .channel:
      guard let channel = aiAgent.store.channel(id: reference.id) else { return "" }
      let credentialKinds = channel.endpointGroups
        .flatMap(\.accountIDs)
        .compactMap { aiAgent.store.account(id: $0)?.credentialKind.displayName }
      let credential = credentialKinds.first ?? "未配置凭据"
      return "远端 · \(credential)"
    }
  }

  private func resetVoiceModelDiscovery() {
    discoveredModels = []
    voiceModelDiscoveryState = .idle
  }

  private func restartActivityNoticesForDurationChange() {
    for id in activeAINoticeIDs {
      notices.remove(id: id)
    }
    activityNoticeShownIDs.removeAll()
    clearMediaNotices()
  }

  private func consumeAIState(_ state: AIState) {
    let settings = settingsStore.settings
    syncAIActivityPowerAssertion(state)
    guard settings.aiProgressEnabled else { return }

    let activeTasks = state.tasks.filter(\.status.isActive)
    let nextActiveNoticeIDs = Set(activeTasks.map(activeAINoticeID(for:)))
    for id in activeAINoticeIDs.subtracting(nextActiveNoticeIDs) {
      notices.remove(id: id)
      activityNoticeShownIDs.remove(id)
    }
    activeAINoticeIDs = nextActiveNoticeIDs
    if settings.sideNoticesEnabled {
      let expiresAfter = settings.activityNoticeDisplayDuration.expiresAfter
      for task in activeTasks {
        let notice = IslandNotice(
          id: activeAINoticeID(for: task),
          title: task.title,
          detail: task.detail,
          kind: task.status.noticeKind,
          side: noticeSide(for: task.provider),
          createdAt: task.updatedAt,
          progress: task.progress
        )
        if notices.updateIfPresent(notice) {
          continue
        }
        let statusChanged = taskStatuses[task.id].map { $0 != task.status } ?? false
        guard !activityNoticeShownIDs.contains(notice.id) || statusChanged else { continue }
        notices.enqueue(notice, expiresAfter: expiresAfter)
        activityNoticeShownIDs.insert(notice.id)
      }
    }

    for notice in state.notices where notice.createdAt >= launchDate.addingTimeInterval(-2) {
      guard knownNoticeIDs.insert(notice.id).inserted else { continue }
      if settings.sideNoticesEnabled { notices.enqueue(notice) }
    }

    for task in state.tasks {
      let previous = taskStatuses[task.id]
      taskStatuses[task.id] = task.status
      guard previous != nil, previous != task.status else { continue }
      guard task.status == .succeeded || task.status == .failed else { continue }
      if settings.sideNoticesEnabled {
        notices.enqueue(
          IslandNotice(
            id: "task-\(task.id)-\(task.updatedAt.timeIntervalSince1970)",
            title: task.title,
            detail: task.status == .succeeded ? "任务已完成" : "任务执行失败",
            kind: task.status == .succeeded ? .success : .error,
            side: task.status == .succeeded ? .right : .left,
            createdAt: task.updatedAt
          ))
      }
    }
  }

  private func syncAIActivityPowerAssertion(_ state: AIState) {
    let isActive = settingsStore.settings.aiProgressEnabled
      && state.tasks.contains { $0.status.isActive }
    powerAssertions.setAIActivityActive(isActive)
  }

  private func clearActiveAINotices() {
    for id in activeAINoticeIDs {
      notices.remove(id: id)
      activityNoticeShownIDs.remove(id)
    }
    activeAINoticeIDs.removeAll()
  }

  private func consumeMailMessages(_ messages: [MailMessage]) {
    let currentIDs = Set(messages.map(\.id))
    defer { knownMailMessageIDs = currentIDs }
    notices.removeAll(withIDPrefix: "mail-notification-")
    guard settingsStore.settings.mailEnabled else {
      hasLoadedMail = false
      return
    }
    guard hasLoadedMail else {
      hasLoadedMail = true
      return
    }
    guard settingsStore.settings.sideNoticesEnabled else { return }

    let newMessages = messages.filter { !$0.isRead && !knownMailMessageIDs.contains($0.id) }
    guard let latest = newMessages.max(by: { $0.receivedAt < $1.receivedAt }) else { return }
    let pair = MailNotification(
      message: latest,
      newMessageCount: newMessages.count,
      pairID: latest.id
    ).makeNotices()
    notices.enqueue(pair.left)
    notices.enqueue(pair.right)
  }

  private func reportMailOperation(
    _ result: MailOperationResult,
    successMessage: String
  ) -> Bool {
    switch result {
    case .success:
      transientMessage = successMessage
      return true
    case .failed(let message):
      transientMessage = message
      return false
    }
  }

  private func consumeMediaSnapshot(_ snapshot: NowPlayingSnapshot?) {
    defer { refreshToolboxReminderNotice() }
    guard snapshot == media.snapshot else { return }
    let settings = settingsStore.settings
    updateSpectrumMonitoring()
    guard settings.mediaEnabled,
      settings.sideNoticesEnabled,
      let snapshot,
      snapshot.isPlaying
    else {
      clearMediaNotices()
      consumeBackgroundSoundPlayback()
      return
    }

    clearBackgroundSoundNotices()

    let source =
      snapshot.sourceApplication
      ?? snapshot.sourceBundleIdentifier
      ?? "媒体播放器"
    let leftNotice = IslandNotice(
      id: "media-active-left",
      title: source,
      detail: snapshot.title,
      kind: .info,
      side: .left,
      artworkData: snapshot.artworkData
    )
    let rightNotice = IslandNotice(
      id: "media-active-right",
      title: "正在播放",
      detail: [snapshot.title, snapshot.artist]
        .filter { !$0.isEmpty }
        .joined(separator: " · "),
      kind: .info,
      side: .right,
      artworkData: snapshot.artworkData
    )

    let leftVisible = notices.updateIfPresent(leftNotice)
    let rightVisible = notices.updateIfPresent(rightNotice)
    if leftVisible || rightVisible {
      return
    }
    guard !mediaActivityPresented else { return }

    let expiresAfter = settings.activityNoticeDisplayDuration.expiresAfter
    notices.enqueue(leftNotice, expiresAfter: expiresAfter)
    notices.enqueue(rightNotice, expiresAfter: expiresAfter)
    mediaActivityPresented = true
  }

  private func updateSpectrumMonitoring() {
    let settings = settingsStore.settings
    let isPlaying = media.snapshot?.isPlaying == true
    let hasVisiblePlaybackNotice = notices.left.contains {
      mediaNoticeIDs.contains($0.id) || backgroundSoundNoticeIDs.contains($0.id)
    } || notices.right.contains {
      mediaNoticeIDs.contains($0.id) || backgroundSoundNoticeIDs.contains($0.id)
    }
    // Background sound counts as media playback: its waveform animates while the island
    // is expanded even when no music app is playing.
    media.setSpectrumVisualizationEnabled(
      settings.mediaEnabled
        && (isPlaying || backgroundSounds.isPlaying)
        && (isIslandVisible || hasVisiblePlaybackNotice)
    )
    media.setSpectrumMonitoringEnabled(
      settings.mediaEnabled
        && (isIslandVisible || isPlaying || backgroundSounds.isPlaying)
    )
  }

  private func clearMediaNotices() {
    for id in mediaNoticeIDs { notices.remove(id: id) }
    mediaActivityPresented = false
  }

  private func consumeBackgroundSoundPlayback() {
    let settings = settingsStore.settings
    guard settings.sideNoticesEnabled,
          backgroundSounds.isPlaying,
          media.snapshot?.isPlaying != true
    else {
      clearBackgroundSoundNotices()
      return
    }

    let soundName = backgroundSounds.playingSound?.title ?? "背景音"
    let leftNotice = IslandNotice(
      id: "background-sound-left",
      title: soundName,
      kind: .info,
      side: .left
    )
    let rightNotice = IslandNotice(
      id: "background-sound-right",
      title: soundName,
      kind: .info,
      side: .right
    )

    if !notices.updateIfPresent(leftNotice) {
      notices.enqueue(leftNotice, expiresAfter: nil)
    }
    if !notices.updateIfPresent(rightNotice) {
      notices.enqueue(rightNotice, expiresAfter: nil)
    }
  }

  private func clearBackgroundSoundNotices() {
    for id in backgroundSoundNoticeIDs { notices.remove(id: id) }
  }

  private func consumeHeadphoneConnection(_ connection: HeadphoneConnection) {
    guard settingsStore.settings.sideNoticesEnabled else { return }
    notices.enqueue(
      IslandNotice(
        id: "headphone-connection-\(connection.id.uuidString)",
        title: connection.device.name,
        detail: "已连接",
        kind: .info,
        side: .right,
        style: .headphone,
        batteryLevels: connection.battery?.noticeLevels
      ),
      expiresAfter: 3
    )
  }

  private func consumeFocusModeStatus(
    _ status: FocusModeStatus,
    showsTransition: Bool
  ) {
    let settings = settingsStore.settings
    guard settings.sideNoticesEnabled else {
      clearFocusModeNotices()
      return
    }

    let presentation = status.presentation
    if status.isActive {
      let notices = [
        IslandNotice(
          id: "focus-mode-left",
          title: presentation.title,
          kind: .info,
          side: .left,
          style: .status,
          symbolName: presentation.symbolName
        ),
        IslandNotice(
          id: "focus-mode-right",
          title: "ON",
          kind: .success,
          side: .right,
          style: .status
        ),
      ]
      for notice in notices {
        self.notices.remove(id: notice.id)
        self.notices.enqueue(
          notice,
          expiresAfter: settings.focusModeNoticeDisplayDuration.expiresAfter
        )
      }
    } else {
      clearFocusModeNotices()
    }

    guard showsTransition else { return }
    notices.enqueue(
      IslandNotice(
        id: "focus-transition",
        title: presentation.title,
        detail: status.isActive ? "已开启" : "已关闭",
        kind: status.isActive ? .success : .info,
        side: .left,
        style: .status,
        symbolName: presentation.symbolName
      ),
      expiresAfter: 3
    )
  }

  private func clearFocusModeNotices() {
    for id in focusModeNoticeIDs { notices.remove(id: id) }
  }

  private func enablePowerAssertionsForCleaning() {
    if cleaningPowerState == nil {
      cleaningPowerState = (
        keepDisplayAwake: powerAssertions.keepDisplayAwake,
        preventIdleSystemSleep: powerAssertions.preventIdleSystemSleep
      )
    }
    powerAssertions.setKeepDisplayAwake(true)
    powerAssertions.setPreventIdleSystemSleep(true)
  }

  private func restorePowerAssertionsAfterCleaning() {
    guard let state = cleaningPowerState else { return }
    cleaningPowerState = nil
    powerAssertions.setKeepDisplayAwake(state.keepDisplayAwake)
    powerAssertions.setPreventIdleSystemSleep(state.preventIdleSystemSleep)
    refreshToolboxReminderNotice()
  }

  private func refreshToolboxReminderNotice() {
    let settings = settingsStore.settings
    guard !isFocusCountdownActive else {
      clearToolboxReminderNotices()
      return
    }
    guard settings.toolboxEnabled,
      settings.toolboxReminderEnabled,
      settings.sideNoticesEnabled,
      media.snapshot == nil,
      let content = ToolboxReminder.content(
        isScreenCleaning: screenCleaning.isScreenCleaning,
        isKeyboardCleaning: screenCleaning.isKeyboardCleaning,
        pomodoroMode: pomodoro.mode,
        pomodoroPhase: pomodoro.phase,
        pomodoroClock: pomodoro.displayClock,
        keepDisplayAwake: powerAssertions.keepDisplayAwake,
        preventIdleSystemSleep: powerAssertions.preventIdleSystemSleep
      )
    else {
      clearToolboxReminderNotices()
      return
    }

    let reminders = [
      IslandNotice(
        id: "toolbox-reminder-left",
        title: content.title,
        detail: content.compactTitle,
        kind: .info,
        side: .left
      ),
      IslandNotice(
        id: "toolbox-reminder-right",
        title: content.title,
        detail: content.compactTitle,
        kind: .info,
        side: .right
      ),
    ]
    for reminder in reminders where !notices.updateIfPresent(reminder) {
      notices.enqueue(reminder, expiresAfter: nil)
    }
  }

  private func clearToolboxReminderNotices() {
    for id in toolboxReminderIDs where noticeExists(id: id) {
      notices.remove(id: id)
    }
  }

  private var isFocusCountdownActive: Bool {
    pomodoro.mode == .focus
      && pomodoro.phase == .running
      && !screenCleaning.isScreenCleaning
      && !screenCleaning.isKeyboardCleaning
  }

  private func refreshFocusCountdownNotice() {
    guard settingsStore.settings.sideNoticesEnabled,
      settingsStore.settings.focusCountdownIslandEnabled,
      isFocusCountdownActive
    else {
      clearFocusCountdownNotices()
      return
    }

    let notices = [
      IslandNotice(
        id: "focus-countdown-left",
        title: "专注倒计时",
        detail: pomodoro.displayClockWithHours,
        kind: .info,
        side: .left
      ),
      IslandNotice(
        id: "focus-countdown-right",
        title: "专注倒计时",
        detail: pomodoro.displayClockWithHours,
        kind: .info,
        side: .right
      ),
    ]
    for notice in notices {
      let existing = (notice.side == .left ? self.notices.left : self.notices.right)
        .first { $0.id == notice.id }
      guard existing?.title != notice.title || existing?.detail != notice.detail else { continue }
      if !self.notices.updateIfPresent(notice) {
        self.notices.enqueue(notice, expiresAfter: nil)
      }
    }
  }

  private func clearFocusCountdownNotices() {
    for id in focusCountdownNoticeIDs where noticeExists(id: id) {
      notices.remove(id: id)
    }
  }

  /// The 3-second linger after completion is timed by `BrowserDownloadMonitor`; here we enqueue a persistent notice that clears together with it.
  private func consumeBrowserDownloadSnapshot(_ snapshot: BrowserDownloadSnapshot?) {
    guard settingsStore.settings.sideNoticesEnabled,
      settingsStore.settings.browserDownloadIslandEnabled,
      let snapshot
    else {
      clearBrowserDownloadNotices()
      return
    }

    let updates = [NoticeSide.left, .right].map { side in
      IslandNotice(
        id: side == .left ? "browser-download-left" : "browser-download-right",
        title: snapshot.fileName,
        detail: snapshot.progressText,
        kind: snapshot.isFinished ? .success : .info,
        side: side,
        progress: snapshot.fraction,
        appName: snapshot.agent?.displayName,
        appBundleIdentifier: snapshot.agent?.bundleIdentifier,
        symbolName: "arrow.down.circle.fill"
      )
    }
    for notice in updates where !notices.updateIfPresent(notice) {
      notices.enqueue(notice, expiresAfter: nil)
    }
  }

  private func clearBrowserDownloadNotices() {
    for id in browserDownloadNoticeIDs where noticeExists(id: id) {
      notices.remove(id: id)
    }
  }

  /// Progress strip for the native downloader in the collapsed island. The 3-second linger on completion is handled by the queue's own expiry timer.
  private func consumeVideoDownloadSnapshot(_ snapshot: VideoDownloadSnapshot?) {
    guard settingsStore.settings.sideNoticesEnabled,
      settingsStore.settings.videoDownloadIslandEnabled,
      let snapshot
    else {
      clearVideoDownloadNotices()
      return
    }

    let updates = [NoticeSide.left, .right].map { side in
      IslandNotice(
        id: side == .left ? "video-download-left" : "video-download-right",
        title: snapshot.sourceName,
        detail: snapshot.progressText,
        kind: snapshot.isFinished ? .success : .info,
        side: side,
        progress: snapshot.fraction,
        artworkData: videoDownloadFaviconData,
        appName: snapshot.platform?.displayName ?? snapshot.host,
        // Platform rawValue is passed through so the view can look up the bundled logo; falls back to artworkData favicon if no bundled logo is found.
        appBundleIdentifier: snapshot.platform?.rawValue,
        symbolName: "arrow.down.circle.fill"
      )
    }
    for notice in updates {
      let expiry: Double? = snapshot.isFinished ? 3 : nil
      if snapshot.isFinished {
        // Finished notices must be re-enqueued to attach the 3-second expiry; updateIfPresent does not schedule a timer.
        notices.enqueue(notice, expiresAfter: expiry)
      } else if !notices.updateIfPresent(notice) {
        notices.enqueue(notice, expiresAfter: nil)
      }
    }
  }

  private func clearVideoDownloadNotices() {
    for id in videoDownloadNoticeIDs where noticeExists(id: id) {
      notices.remove(id: id)
    }
  }

  private func beginVideoDownloadIsland(forURLString urlString: String) {
    videoDownloadPlatform = VideoDownloadPlatformResolver.platform(forURLString: urlString)
    videoDownloadHost = VideoDownloadPlatformResolver.bareHost(ofURLString: urlString)
    videoDownloadFaviconData = nil
    updateVideoDownloadIsland(fraction: nil, isFinished: false)

    // Platforms with a bundled logo don't need a network fetch; sites not in the bundled library (including long-tail sites) fetch their own favicon.
    guard videoDownloadPlatform?.bundledIconURL == nil, let host = videoDownloadHost else { return }
    Task { [weak self, videoDownloadFavicons] in
      let data = await videoDownloadFavicons.icon(forHost: host)
      await MainActor.run {
        guard let self, self.videoDownloadHost == host, let data else { return }
        self.videoDownloadFaviconData = data
        guard case .downloading(let fraction, _, _) = self.downloadState else {
          self.updateVideoDownloadIsland(fraction: nil, isFinished: false)
          return
        }
        self.updateVideoDownloadIsland(fraction: fraction, isFinished: false)
      }
    }
  }

  private func updateVideoDownloadIsland(fraction: Double?, isFinished: Bool) {
    guard videoDownloadPlatform != nil || videoDownloadHost != nil else { return }
    consumeVideoDownloadSnapshot(
      VideoDownloadSnapshot(
        platform: videoDownloadPlatform,
        host: videoDownloadHost,
        sourceName: videoDownloadPlatform?.displayName ?? videoDownloadHost ?? "下载",
        fraction: fraction,
        isFinished: isFinished
      )
    )
    if isFinished { resetVideoDownloadSource() }
  }

  private func endVideoDownloadIsland() {
    resetVideoDownloadSource()
    clearVideoDownloadNotices()
  }

  private func resetVideoDownloadSource() {
    videoDownloadPlatform = nil
    videoDownloadHost = nil
    videoDownloadFaviconData = nil
  }

  private func noticeExists(id: String) -> Bool {
    notices.left.contains { $0.id == id } || notices.right.contains { $0.id == id }
  }

  private func noticeSide(for provider: AIProvider) -> NoticeSide {
    switch provider {
    case .claude, .gemini, .qwen, .trae, .doubao: .left
    case .pi: .right
    case .codex, .grok, .gpt, .copilot, .kimi, .coder, .zcode, .opencode, .harness: .right
    }
  }

  private func activeAINoticeID(for task: AIProgressTask) -> String {
    "ai-active-\(task.provider.rawValue)-\(task.id)"
  }

  private func refreshAgendaIfEnabled() {
    let settings = settingsStore.settings
    if settings.weatherEnabled, isWeatherStale { refreshWeather() }
    if settings.calendarEnabled {
      Task { await calendar.refresh() }
    }
  }

  private func restoreDownloadDirectory() {
    guard let data = UserDefaults.standard.data(forKey: "download-directory-bookmark") else {
      return
    }
    var stale = false
    guard
      let url = try? URL(
        resolvingBookmarkData: data,
        options: [.withSecurityScope, .withoutUI],
        relativeTo: nil,
        bookmarkDataIsStale: &stale
      )
    else {
      return
    }
    downloadDirectory = url
    if stale,
      let bookmark = try? url.bookmarkData(
        options: .withSecurityScope,
        includingResourceValuesForKeys: nil,
        relativeTo: nil
      )
    {
      UserDefaults.standard.set(bookmark, forKey: "download-directory-bookmark")
    }
  }

  private static func downloadErrorText(_ error: Error) -> String {
    guard let error = error as? DownloadServiceError else {
      return error.localizedDescription
    }
    switch error {
    case .duplicateTask: return "下载任务已在运行"
    case .cannotPrepareDirectory: return "无法写入下载目录"
    case .launchFailed: return "无法启动下载任务"
    case .processFailed(_, let diagnostic): return diagnostic.isEmpty ? "下载失败" : diagnostic
    case .missingCompletedFile: return "未获得下载文件"
    case .unsafeCompletedFile: return "下载结果位于授权目录之外"
    case .completedFileDoesNotExist: return "下载文件不存在"
    }
  }
}

extension AppearanceMode {
  /// The corresponding NSApp-level appearance; `nil` means follow the system.
  var nsAppearance: NSAppearance? {
    switch self {
    case .system: nil
    case .light: NSAppearance(named: .aqua)
    case .dark: NSAppearance(named: .darkAqua)
    }
  }
}
