import AppKit
import Combine
import Foundation
import ZislaCore
import ZislaKit

enum IslandModule: String, CaseIterable, Identifiable {
  case dashboard
  case shelf
  case clipboard
  case aiMonitor
  case aiAgent
  case download
  case agenda
  case mail
  case quickNotes
  case pdf
  case toolbox
  case system
  case lockScreen

  var id: Self { self }

  var title: String {
    switch self {
    case .dashboard: "首页"
    case .shelf: "中转"
    case .clipboard: "剪贴板"
    case .aiMonitor: "AI 监控"
    case .aiAgent: "AI Agent"
    case .download: "下载"
    case .agenda: "日程"
    case .mail: "邮件"
    case .quickNotes: "随记"
    case .pdf: "PDF"
    case .toolbox: "小工具"
    case .system: "系统"
    case .lockScreen: "锁屏"
    }
  }

  var symbol: String {
    switch self {
    case .dashboard: "rectangle.grid.2x2.fill"
    case .shelf: "tray.full.fill"
    case .clipboard: "clipboard"
    case .aiMonitor: "chart.xyaxis.line"
    case .aiAgent: "sparkles"
    case .download: "arrow.down.circle.fill"
    case .agenda: "calendar"
    case .mail: "envelope.fill"
    case .quickNotes: "note.text"
    case .pdf: "doc.viewfinder"
    case .toolbox: "wrench.and.screwdriver.fill"
    case .system: "gauge.with.dots.needle.67percent"
    case .lockScreen: "lock.display"
    }
  }

  var layout: IslandModuleLayout {
    switch self {
    case .dashboard:
      .standard
    case .aiMonitor:
      .ai
    case .aiAgent:
      .agent
    case .system:
      .system
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
  /// 原为 IslandRootView 的私有扩展；AppModel 需要在设置变化时回退被禁用的选中模块，移到定义处共享。
  func isEnabled(in settings: FeatureSettings) -> Bool {
    switch self {
    case .dashboard: true
    case .shelf: settings.fileShelfEnabled
    case .clipboard: settings.clipboardHistoryEnabled
    case .aiMonitor: settings.aiProgressEnabled
    case .aiAgent: settings.aiAgentEnabled
    case .download: settings.downloaderEnabled
    case .agenda: settings.calendarEnabled || settings.weatherEnabled
    case .mail: settings.mailEnabled
    case .quickNotes: settings.quickNotesEnabled
    case .pdf: settings.pdfToolsEnabled
    case .toolbox: settings.toolboxEnabled
    case .system: settings.systemMonitorEnabled
    case .lockScreen: settings.lockScreenInfoEnabled
    }
  }
}

struct IslandModuleLayout: Equatable {
  let islandSize: CGSize
  let panelSize: CGSize

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

  /// Fixed-height modules size the surface to their rendered content instead of inheriting
  /// the standard panel's unused vertical space.
  private static func compactModule(contentHeight: CGFloat) -> IslandModuleLayout {
    let islandHeight = expandedChromeHeight + contentHeight + moduleVerticalInsets
    return IslandModuleLayout(
      islandSize: CGSize(width: 660, height: islandHeight),
      panelSize: CGSize(width: 860, height: islandHeight + panelHeightAllowance)
    )
  }

  static let toolbox = compactModule(contentHeight: 184)
  static let download = compactModule(contentHeight: 138)
  static let agenda = compactModule(contentHeight: 160)
  /// PDF tools need the full-width toolbar plus enough vertical room for the operation list.
  static let pdf = IslandModuleLayout(
    islandSize: CGSize(width: 660, height: 600),
    panelSize: CGSize(width: 860, height: 604)
  )
  /// Shelf content is fixed at 228pt and scrolls internally when it contains more files.
  static let shelf = compactModule(contentHeight: 228)
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
  static let agent = IslandModuleLayout(
    islandSize: CGSize(width: 860, height: 540),
    panelSize: CGSize(width: 860, height: 544)
  )
  static let system = compactModule(contentHeight: 401)
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
  /// Voice recording: expands to a single row showing the recording indicator and live transcription.
  static let voiceRecording = IslandModuleLayout(
    islandSize: CGSize(width: 660, height: 72),
    panelSize: CGSize(width: 660, height: 76)
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
    dashboardCardCount: Int
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

@MainActor
final class AppModel: ObservableObject {
  private enum AIProcessingTarget {
    case http(endpoint: AIEndpoint, model: String, apiKey: String?)
    case cliProfile(accountID: UUID, model: String)
  }

  static let shared = AppModel()

  @Published var selectedModule: IslandModule = .dashboard {
    didSet {
      // 卸载不能放在 default 分支：切到 agenda/mail 等具名 case 时会整体跳过，用量历史将常驻内存。
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
      case .aiAgent:
        Task { await aiAgent.refreshAll() }
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
  @Published var downloadURL = ""
  @Published var downloadMode: DownloadMode = .video
  @Published var downloadDirectory = AppPaths.downloads
  @Published var downloadState: DownloadUIState = .idle
  @Published var transientMessage: String?
  @Published var collapsedIslandSize = CGSize(width: 240, height: 34)
  /// Number of cards rendered below the dashboard summary.
  @Published private(set) var dashboardCardCount = 0
  @Published var isIslandOnPhysicalNotch = false
  @Published private(set) var isMirrorPresented = false
  @Published private(set) var isTeleprompterPresented = false
  @Published var isIslandVisible = false {
    didSet {
      guard oldValue != isIslandVisible else { return }
      updateSpectrumMonitoring()
    }
  }
  @Published var isExternalDragging = false
  @Published var detectedLink: URL?
  @Published private(set) var isSharingPickerVisible = false

  /// Signal to request the island to collapse after disk cleaning completes (toggled once per request).
  @Published var islandCollapseRequested = false

  /// Whether the disk-cleaning panel is visible: keeps the island expanded while visible to prevent it collapsing when the pointer leaves.
  @Published var isCleanupPanelVisible = false

  let settingsStore = FeatureSettingsStore()
  let languageStore = AppLanguageStore()
  let aiMonitor = AIStateMonitor()
  let notices = SideNoticeQueue()
  let media = NowPlayingService()
  let audioOutput = AudioOutputDeviceService()
  let calendar = CalendarService()
  let shelf = FileShelfStore()
  let weatherLocations = WeatherLocationStore()
  let clipboardMonitor = ClipboardLinkMonitor()
  let clipboardHistory = ClipboardHistoryStore()
  let clipboardHistoryMonitor = ClipboardHistoryMonitor()
  let pomodoro = PomodoroService()
  let alarms = AlarmService()
  let managedTools = ManagedToolService()
  let powerAssertions = PowerAssertionController()
  let screenCleaning = ScreenCleaningController()
  let systemMonitor = SystemMonitorService()
  let battery = BatteryMonitor()
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
  let aiAgent = AIAgentWorkspace()

  /// Model discovery state: used by the settings page to show connection test results and the available model list.
  @Published var voiceModelDiscoveryState: VoiceModelDiscoveryState = .idle
  @Published var discoveredModels: [AIDiscoveredModel] = []
  @Published private(set) var voiceInputInputMonitoringAccessGranted =
    GlobalHotkeyManager.hasInputMonitoringAccess
  /// Current device hardware profile, used to recommend suitable local small models.
  @Published var hardwareProfile: AIHardwareProfile?
  private var isRefreshingHardwareProfile = false

  private let weatherService = WeatherService()
  private let weatherLocationService = WeatherLocationService()
  private let releaseService = GitHubReleaseService()
  private let downloadService = DownloadService()
  private let hotkeyManager = GlobalHotkeyManager()
  private var voiceModelChannelRouter = AgentRouteRouter()
  private var cancellables: Set<AnyCancellable> = []
  private var weatherTask: Task<Void, Never>?
  private var releaseTask: Task<Void, Never>?
  private var downloadTask: Task<Void, Never>?
  private var voicePostProcessingTask: Task<Void, Never>?
  private var detectedLinkTask: Task<Void, Never>?
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
  private let mediaNoticeIDs: Set<String> = [
    "media-active-left",
    "media-active-right",
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
  private var cleaningPowerState:
    (
      keepDisplayAwake: Bool,
      preventIdleSystemSleep: Bool
    )?
  private let launchDate = Date()
  private let sharingPickerDelegate = SharingPickerDelegateProxy()
  private var sharingPicker: NSSharingServicePicker?

  private init() {
    sharingPickerDelegate.onCompletion = { [weak self] picker in
      self?.sharingPickerDidComplete(picker)
    }
    screenCleaning.onCleaningDidEnd = { [weak self] in
      self?.restorePowerAssertionsAfterCleaning()
    }
    restoreDownloadDirectory()
    aiAgent.startAutomation()
    clipboardHistoryMonitor.onContentCaptured = { [weak self] content in
      _ = self?.clipboardHistory.record(content)
    }
    clipboardMonitor.onLinkDetected = { [weak self] url in
      guard let self else { return }
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
      if settingsStore.settings.sideNoticesEnabled {
        notices.enqueue(
          IslandNotice(
            id: "clipboard-link-\(url.host ?? "media")",
            title: "发现可下载链接",
            detail: url.host ?? "媒体链接",
            kind: .info,
            side: .left
          ))
      }
    }
    voiceInput.onTranscriptCompleted = { [weak self] transcript in
      self?.deliverVoiceTranscript(transcript)
    }
    // The in-island transcript HUD only exists while recording, so a permission or start-up failure
    // would otherwise leave the shortcut looking like it did nothing at all.
    voiceInput.$errorDescription
      .compactMap { $0 }
      .sink { [weak self] message in
        Task { @MainActor [weak self] in self?.transientMessage = message }
      }
      .store(in: &cancellables)

    // 在设置里关掉"正打开的模块"时，岛面内容会回退成仪表盘，但面板尺寸管线只订阅
    // selectedModule；选中态不跟着回退会留下错位的 NSPanel 几何和失效的图标高亮。
    settingsStore.$settings
      .sink { [weak self] _ in
        Task { @MainActor [weak self] in
          guard let self else { return }
          // 读实时值而非发射快照：快速连开连关时不会因过期快照误回退。
          guard !self.selectedModule.isEnabled(in: self.settingsStore.settings) else { return }
          self.selectedModule = .dashboard
        }
      }
      .store(in: &cancellables)

    let childPublishers = [
      settingsStore.objectWillChange,
      notices.objectWillChange,
      audioOutput.objectWillChange,
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

    Publishers.CombineLatest(notices.$left, notices.$right)
      .map { left, right in
        left.contains { $0.id.hasPrefix("media-active-") }
          || right.contains { $0.id.hasPrefix("media-active-") }
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
          self?.consumeFocusModeStatus(status, showsTransition: true)
        }
      }
      .store(in: &cancellables)

    mail.$messages
      .dropFirst()
      .sink { [weak self] messages in
        Task { @MainActor [weak self] in self?.consumeMailMessages(messages) }
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
    let cardCount = [hasPomodoro, hasAITask, downloadState.isRunning].filter { $0 }.count
      + browserDownloads.snapshots.count
    if dashboardCardCount != cardCount {
      dashboardCardCount = cardCount
    }
  }

  func synchronizeDashboardCardCount(_ count: Int) {
    guard dashboardCardCount != count else { return }
    dashboardCardCount = count
  }

  func start() {
    apply(settings: settingsStore.settings)
    focusMode.start()
    audioOutput.start()
    alarms.rescheduleAll()
    if settingsStore.settings.updateChecksEnabled {
      checkForUpdates(manual: false)
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

  func refreshVoiceInputInputMonitoringAccess() {
    let granted = GlobalHotkeyManager.hasInputMonitoringAccess
    guard voiceInputInputMonitoringAccessGranted != granted else { return }
    voiceInputInputMonitoringAccessGranted = granted
    if granted, settingsStore.settings.voiceInputEnabled {
      apply(settings: settingsStore.settings)
    }
  }

  func stop() {
    settingsStore.flushPendingChanges()
    clipboardHistory.flushPendingChanges()
    weatherTask?.cancel()
    releaseTask?.cancel()
    downloadTask?.cancel()
    voicePostProcessingTask?.cancel()
    detectedLinkTask?.cancel()
    voiceInput.cancel()
    hotkeyManager.unregister()
    clipboardMonitor.setEnabled(false)
    clipboardHistoryMonitor.setEnabled(false)
    Task { [downloadService] in await downloadService.cancelAll() }
    aiMonitor.stop()
    media.stop()
    audioOutput.stop()
    pomodoro.stop()
    screenCleaning.stopAll()
    cleaningPowerState = nil
    powerAssertions.releaseAll()
    systemMonitor.stop()
    battery.stop()
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
    isSharingPickerVisible = false
    picker?.close()
  }

  func startScreenCleaning() {
    enablePowerAssertionsForCleaning()
    screenCleaning.startScreenCleaning()
    refreshFocusCountdownNotice()
    refreshToolboxReminderNotice()
  }

  func startKeyboardCleaning() {
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

  /// Updates App Store apps in one click. If `mas` is installed it upgrades in bulk; otherwise opens the App Store Updates page.
  func updateAppStoreApps() {
    Task { @MainActor [weak self] in
      guard let self else { return }
      switch await DesktopOrganizer.updateAppStoreApps(
        masExecutable: managedTools.resolvedExecutable(for: .mas)?.url
      ) {
      case .success(let message):
        transientMessage = message
      case .failure(let error):
        transientMessage = error.message
      }
    }
  }

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
      if settings.lockScreenInfoEnabled { self.battery.refresh() }
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

  func checkForUpdates(manual: Bool, channel: UpdateChannel? = nil) {
    let selectedChannel = channel ?? (manual ? settingsStore.settings.updateChannel : nil)
    if UpdateController.shared.checkForUpdates(manual: manual, channel: selectedChannel) {
      return
    }
    releaseTask?.cancel()
    updateState = .checking
    let version =
      Bundle.main.object(
        forInfoDictionaryKey: "CFBundleShortVersionString"
      ) as? String ?? "0.1.1"
    releaseTask = Task { [weak self, releaseService] in
      do {
        let result = try await releaseService.check(currentVersion: version)
        guard !Task.isCancelled else { return }
        switch result {
        case .upToDate:
          self?.updateState = .current
          if manual { self?.transientMessage = "当前已是最新版本" }
        case .updateAvailable(let release, let source):
          guard let self else { return }
          self.updateState = .available(release, source: source)
          self.notices.enqueue(
            IslandNotice(
              id: "release-\(source)-\(release.tagName)",
              title: "发现 \(source.displayName) 新版本 \(release.tagName)",
              detail: source == .github ? "可在设置中选择立即更新" : "可在设置中打开 Gitee Release 下载",
              kind: .info,
              side: .right
            ))
          if manual { self.presentUpdateAlert(for: release, source: source) }
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
    if source == .gitee {
      let alert = NSAlert()
      alert.messageText = "发现 Gitee 新版本 \(release.tagName)"
      alert.informativeText = "Gitee Release 需要在浏览器中下载安装。"
      alert.addButton(withTitle: "打开 Gitee Release")
      alert.addButton(withTitle: "稍后")
      NSApp.activate(ignoringOtherApps: true)
      WindowPlacement.prepareModal(alert.window, on: WindowPlacement.screenUnderMouse())
      guard alert.runModal() == .alertFirstButtonReturn else { return }
      NSWorkspace.shared.open(release.htmlURL)
      return
    }

    let updateController = UpdateController.shared
    let canInstall = updateController.isAvailable
    let alert = NSAlert()
    alert.messageText = "发现新版本 \(release.tagName)"
    alert.informativeText = canInstall ? "是否立即更新？" : "当前安装包不支持自动更新。"
    alert.addButton(withTitle: canInstall ? "立即更新" : "知道了")
    if canInstall { alert.addButton(withTitle: "稍后") }
    NSApp.activate(ignoringOtherApps: true)
    WindowPlacement.prepareModal(alert.window, on: WindowPlacement.screenUnderMouse())
    guard canInstall, alert.runModal() == .alertFirstButtonReturn else { return }
    guard !updateController.checkForUpdates(manual: true) else { return }
    transientMessage = "当前安装包不支持自动更新"
  }

  func selectSystemMonitor() {
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

  func sendQuickNoteToTeleprompter(_ content: String) {
    let content = content.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !content.isEmpty else {
      transientMessage = "随记没有可发送的内容"
      return
    }
    UserDefaults.standard.set(content, forKey: "toolbox.teleprompterScript")
    transientMessage = "已发送到提词器"
    selectModule(.toolbox)
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

  func sendQuickNoteToAIAgent(_ content: String) {
    sendTransferItemsToAIAgent([.text(content)])
  }

  func sendTransferItemsToAIAgent(_ items: [TransferDropItem]) {
    let content = transferableText(from: items)
    guard !content.isEmpty else {
      transientMessage = "没有可发送给 AI Agent 的内容"
      return
    }
    let profileAccount = aiAgent.store.state.accounts.first { aiAgent.store.hasCLIProfile(for: $0) }
    let thread = aiAgent.store.createThread(
      useMostRecentModel: true,
      channelID: aiAgent.store.state.channels.first(where: \.isEnabled)?.id,
      cliKind: profileAccount?.cliProfile?.cliKind,
      accountID: profileAccount?.id
    )
    // 设计上关闭开关只隐藏模块、不影响对话，所以照常发送；但不能跳到一个不可见的
    // 模块（会触发面板尺寸错位），改为提示去向。
    if settingsStore.settings.aiAgentEnabled {
      selectModule(.aiAgent)
    } else {
      transientMessage = "已发送给 AI Agent，可在设置中重新开启该模块查看"
    }
    Task { await aiAgent.send(content, to: thread.id) }
  }

  func sendClipboardHistoryItemToQuickNote(_ item: ClipboardHistoryItem) {
    receiveQuickNoteTransferItems(transferItems(from: item.content))
  }

  func sendClipboardHistoryItemToAIAgent(_ item: ClipboardHistoryItem) {
    sendTransferItemsToAIAgent(transferItems(from: item.content))
  }

  private func transferItems(from content: ClipboardHistoryContent) -> [TransferDropItem] {
    switch content {
    case let .text(value):
      [.text(value)]
    case let .file(reference):
      [.file(reference.url)]
    case let .image(data):
      [.text("剪贴板图片（PNG 数据，\(data.count) 字节）")]
    }
  }

  private func transferableText(from items: [TransferDropItem]) -> String {
    items.map { item in
      switch item {
      case let .text(value): value
      case let .link(url): url.absoluteString
      case let .file(url): "[\(url.lastPathComponent)](\(url.absoluteString))"
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
    let anchor =
      view
      ?? NSApp.windows.first(where: {
        $0 is IslandPanel && $0.isVisible
      })?.contentView
    guard let anchor else {
      transientMessage = "无法打开系统共享菜单"
      return
    }
    let picker = NSSharingServicePicker(items: values)
    picker.delegate = sharingPickerDelegate
    let previousPicker = sharingPicker
    sharingPicker = picker
    isSharingPickerVisible = true
    previousPicker?.close()
    picker.show(relativeTo: anchor.bounds, of: anchor, preferredEdge: .minY)
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
    sharingPicker = nil
    isSharingPickerVisible = false
  }

  private func prepareDownload(_ url: URL) {
    downloadURL = url.absoluteString
    selectModule(.download)
    detectedLinkTask?.cancel()
    detectedLink = nil
    transientMessage = "链接已放入下载中转"
  }

  func startDownload() {
    guard !downloadState.isRunning else { return }
    let request: DownloadRequest
    do {
      request = try DownloadRequest(
        urlString: downloadURL,
        mode: downloadMode,
        outputDirectory: downloadDirectory
      )
    } catch {
      downloadState = .failed("链接或输出目录无效")
      return
    }

    let taskID = UUID()
    activeDownloadID = taskID
    downloadState = .preparing
    beginVideoDownloadIsland(forURLString: request.urlString)
    let scopedAccess = downloadDirectory.startAccessingSecurityScopedResource()
    downloadTask = Task { [weak self, downloadService] in
      defer {
        if scopedAccess { request.outputDirectory.stopAccessingSecurityScopedResource() }
      }
      do {
        let result = try await downloadService.download(
          request,
          taskID: taskID
        ) { [weak self] event in
          await MainActor.run {
            guard let self, self.activeDownloadID == taskID else { return }
            if case .progress(let fraction, let speed, let eta) = event {
              self.downloadState = .downloading(
                fraction: fraction,
                speed: speed,
                eta: eta
              )
              self.updateVideoDownloadIsland(fraction: fraction, isFinished: false)
            }
          }
        }
        guard !Task.isCancelled, self?.activeDownloadID == taskID else { return }
        self?.downloadState = .completed(result.fileURL)
        self?.activeDownloadID = nil
        self?.updateVideoDownloadIsland(fraction: 1, isFinished: true)
        self?.addToShelf([result.fileURL])
        self?.notices.enqueue(
          IslandNotice(
            id: "download-\(taskID.uuidString)",
            title: "下载完成",
            detail: result.fileURL.lastPathComponent,
            kind: .success,
            side: .right
          ))
      } catch is CancellationError {
        if self?.activeDownloadID == taskID {
          self?.downloadState = .idle
          self?.activeDownloadID = nil
          self?.endVideoDownloadIsland()
        }
      } catch {
        guard self?.activeDownloadID == taskID else { return }
        self?.downloadState = .failed(Self.downloadErrorText(error))
        self?.activeDownloadID = nil
        self?.endVideoDownloadIsland()
      }
    }
  }

  func cancelDownload() {
    guard let taskID = activeDownloadID else { return }
    downloadTask?.cancel()
    Task { [downloadService] in await downloadService.cancel(taskID: taskID) }
  }

  private func apply(settings: FeatureSettings) {
    // Regular UI appearance is controlled by user settings; the island panel is separately pinned to dark at the window level (see IslandPanel).
    NSApp.appearance = settings.appearanceMode.nsAppearance
    media.setPreferredSource(settings.mediaSource)
    pomodoro.notificationsMuted = settings.notificationsMuted
    if settings.aiProgressEnabled {
      aiMonitor.start()
      if selectedModule == .aiMonitor {
        aiMonitor.loadUsageHistory()
      }
    } else {
      aiMonitor.stop()
      clearActiveAINotices()
    }
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
    if settings.sideNoticesEnabled, settings.browserDownloadIslandEnabled {
      browserDownloads.start()
      consumeBrowserDownloadSnapshot(browserDownloads.snapshot)
    } else {
      browserDownloads.stop()
      clearBrowserDownloadNotices()
    }
    if settings.lockScreenInfoEnabled {
      battery.start()
    } else {
      battery.stop()
    }
    if settings.mailEnabled {
      mail.start(accountNames: settings.mailAccountNames)
    } else {
      mail.stop()
      hasLoadedMail = false
      knownMailMessageIDs.removeAll()
    }
    if selectedModule == .agenda { refreshAgendaIfEnabled() }
    clipboardMonitor.setEnabled(
      settings.downloaderEnabled && settings.clipboardDetectionEnabled
    )
    clipboardHistoryMonitor.setEnabled(settings.clipboardHistoryEnabled)
    if !settings.downloaderEnabled, downloadState.isRunning {
      cancelDownload()
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
    } else {
      notices.removeAll()
      activeAINoticeIDs.removeAll()
      activityNoticeShownIDs.removeAll()
      mediaActivityPresented = false
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
      hotkeyManager.unregister()
    }
    refreshToolboxReminderNotice()
  }

  // MARK: - Voice model discovery

  private func deliverVoiceTranscript(_ transcript: String) {
    let rawTranscript = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !rawTranscript.isEmpty else { return }
    voicePostProcessingTask?.cancel()
    guard let target = voicePostProcessingTarget() else {
      copyVoiceTranscript(rawTranscript, message: "语音转写已复制")
      return
    }
    // Recording already ended and the island HUD is gone, so without this the cleanup round-trip
    // looks like the shortcut simply swallowed the dictation.
    transientMessage = "正在整理语音…"
    voicePostProcessingTask = Task { [weak self] in
      guard let self else { return }
      do {
        let response = try await self.complete(
          using: target,
          systemPrompt: VoiceTranscriptPostProcessor.systemPrompt,
          messages: VoiceTranscriptPostProcessor.messages(for: rawTranscript)
        )
        guard !Task.isCancelled else { return }
        let delivered = VoiceTranscriptPostProcessor.deliveredText(
          response,
          fallback: rawTranscript
        )
        copyVoiceTranscript(delivered, message: "语音整理后已复制")
      } catch is CancellationError {
        return
      } catch {
        guard !Task.isCancelled else { return }
        copyVoiceTranscript(rawTranscript, message: "语音转写已复制；整理失败")
      }
    }
  }

  private func voicePostProcessingTarget() -> AIProcessingTarget? {
    guard let reference = selectedVoiceModelConfiguration else { return nil }
    switch reference.source {
    case .local:
      guard let configuration = aiAgent.store.localModel(id: reference.id), configuration.isEnabled else {
        return nil
      }
      let model = configuration.modelName.trimmingCharacters(in: .whitespacesAndNewlines)
      guard !model.isEmpty else { return nil }
      return .http(endpoint: configuration.endpoint, model: model, apiKey: nil)
    case .channel:
      guard let channel = aiAgent.store.channel(id: reference.id), channel.isEnabled,
            let route = voiceModelChannelRouter.nextRoute(
              for: channel,
              accounts: aiAgent.store.state.accounts
            ),
            let account = aiAgent.store.account(id: route.accountID) else {
        return nil
      }
      switch account.credentialKind {
      case .apiKey:
        guard channel.protocolKind == .openAICompatible else { return nil }
        return .http(
          endpoint: AIEndpoint(name: channel.name, baseURL: route.baseURL, kind: .openAICompatible),
          model: route.model,
          apiKey: try? aiAgent.store.secret(for: account)
        )
      case .cliProfile:
        guard aiAgent.store.hasCLIProfile(for: account) else { return nil }
        return .cliProfile(accountID: account.id, model: route.model)
      }
    }
  }

  private func complete(
    using target: AIProcessingTarget,
    systemPrompt: String,
    messages: [AIOutboundMessage]
  ) async throws -> String {
    switch target {
    case let .http(endpoint, model, apiKey):
      return try await AIChatClient().complete(
        endpoint: endpoint,
        model: model,
        systemPrompt: systemPrompt,
        messages: messages,
        apiKey: apiKey
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

  private func copyVoiceTranscript(_ transcript: String, message: String) {
    guard ClipboardHistoryPasteboard.write(.text(transcript)) else {
      transientMessage = "无法复制语音转写结果"
      return
    }
    transientMessage = message
  }

  /// Tests the current model endpoint and discovers available models.
  func discoverModels() {
    guard let target = voicePostProcessingTarget() else {
      voiceModelDiscoveryState = .failed("请先在上方添加、启用并选择一个模型配置")
      discoveredModels = []
      return
    }
    guard case let .http(endpoint, _, apiKey) = target else {
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
    guard let reference else { return nil }
    switch reference.source {
    case .local:
      return aiAgent.store.localModel(id: reference.id)?.isEnabled == true ? reference : nil
    case .channel:
      return aiAgent.store.channel(id: reference.id)?.isEnabled == true ? reference : nil
    }
  }

  func selectVoiceModelConfiguration(_ reference: AIModelConfigurationReference?) {
    guard let reference else {
      settingsStore.settings.voiceModelConfiguration = nil
      resetVoiceModelDiscovery()
      return
    }
    let isEnabled = switch reference.source {
    case .local:
      aiAgent.store.localModel(id: reference.id)?.isEnabled == true
    case .channel:
      aiAgent.store.channel(id: reference.id)?.isEnabled == true
    }
    guard isEnabled else {
      settingsStore.settings.voiceModelConfiguration = nil
      resetVoiceModelDiscovery()
      return
    }
    settingsStore.settings.voiceModelConfiguration = reference
    resetVoiceModelDiscovery()
  }

  func voiceModelConfigurationTitle(_ reference: AIModelConfigurationReference) -> String {
    switch reference.source {
    case .local:
      return aiAgent.store.localModel(id: reference.id)?.name ?? "本地模型"
    case .channel:
      return aiAgent.store.channel(id: reference.id)?.name ?? "远端模型"
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

  /// Fetches the current device's hardware profile to recommend local models.
  func refreshHardwareProfile() {
    guard hardwareProfile == nil, !isRefreshingHardwareProfile else { return }
    isRefreshingHardwareProfile = true

    Task { [weak self] in
      let profile = await Task.detached(priority: .utility) {
        AIHardwareProfileDetector.current()
      }.value
      guard let self else { return }
      hardwareProfile = profile
      isRefreshingHardwareProfile = false
    }
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
    guard settingsStore.settings.mailEnabled else {
      hasLoadedMail = false
      return
    }
    guard hasLoadedMail else {
      hasLoadedMail = true
      return
    }
    guard settingsStore.settings.sideNoticesEnabled else { return }

    for message in messages where !message.isRead && !knownMailMessageIDs.contains(message.id) {
      notices.enqueue(
        IslandNotice(
          id: "mail-\(message.id)",
          title: "新邮件",
          detail:
            "\(message.accountName) · \(message.sender.isEmpty ? "未知发件人" : message.sender) · \(message.title)",
          kind: .info,
          side: .right,
          createdAt: message.receivedAt
        ))
    }
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
      return
    }

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
    let hasVisibleMediaNotice = notices.left.contains { mediaNoticeIDs.contains($0.id) }
      || notices.right.contains { mediaNoticeIDs.contains($0.id) }
    media.setSpectrumVisualizationEnabled(
      settings.mediaEnabled
        && isPlaying
        && (isIslandVisible || hasVisibleMediaNotice)
    )
    media.setSpectrumMonitoringEnabled(
      settings.mediaEnabled
        && (isIslandVisible || isPlaying)
    )
  }

  private func clearMediaNotices() {
    for id in mediaNoticeIDs { notices.remove(id: id) }
    mediaActivityPresented = false
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
        title: status.isActive ? presentation.title : "专注模式",
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
    case .codex, .grok, .gpt, .copilot, .kimi, .coder, .opencode, .harness: .right
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
