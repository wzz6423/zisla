import AppKit
import Combine
import Foundation
import ZislaCore
import ZislaKit

enum IslandModule: String, CaseIterable, Identifiable {
  case shelf
  case clipboard
  case aiMonitor
  case download
  case agenda
  case mail
  case quickNotes
  case toolbox
  case system
  case lockScreen

  var id: Self { self }

  var title: String {
    switch self {
    case .shelf: "中转"
    case .clipboard: "剪贴板"
    case .aiMonitor: "AI 监控"
    case .download: "下载"
    case .agenda: "日程"
    case .mail: "邮件"
    case .quickNotes: "随记"
    case .toolbox: "小工具"
    case .system: "系统"
    case .lockScreen: "锁屏"
    }
  }

  var symbol: String {
    switch self {
    case .shelf: "tray.full.fill"
    case .clipboard: "clipboard"
    case .aiMonitor: "chart.xyaxis.line"
    case .download: "arrow.down.circle.fill"
    case .agenda: "calendar"
    case .mail: "envelope.fill"
    case .quickNotes: "note.text"
    case .toolbox: "wrench.and.screwdriver.fill"
    case .system: "gauge.with.dots.needle.67percent"
    case .lockScreen: "lock.display"
    }
  }

  var layout: IslandModuleLayout {
    switch self {
    case .aiMonitor:
      .ai
    case .system:
      .system
    case .clipboard:
      .clipboard
    case .shelf:
      .shelf
    case .toolbox:
      .toolbox
    case .download, .agenda, .lockScreen:
      .standard
    case .mail:
      .mail
    case .quickNotes:
      .notes
    }
  }
}

struct IslandModuleLayout: Equatable {
  let islandSize: CGSize
  let panelSize: CGSize

  /// 标准岛宽需容纳整排工具栏（模块图标 + 系统监控条 + 功能按钮），
  /// 过窄会让 HStack 居中溢出、首图标被岛面裁切，故放宽到 660。
  /// panelSize 同步加宽以保留中转/共享双肩的 200pt 余量。
  static let standard = IslandModuleLayout(
    islandSize: CGSize(width: 660, height: 340),
    panelSize: CGSize(width: 860, height: 344)
  )
  /// 工具箱只包含专注卡与两行快捷操作，使用紧凑高度避免留下无意义留白。
  static let toolbox = IslandModuleLayout(
    islandSize: CGSize(width: 660, height: 300),
    panelSize: CGSize(width: 860, height: 304)
  )
  /// 中转站需同时容纳两行文件，避免挤压顶部播放与工具栏。
  static let shelf = IslandModuleLayout(
    islandSize: CGSize(width: 660, height: 390),
    panelSize: CGSize(width: 860, height: 394)
  )
  /// 剪贴板：比标准布局更高，列表可同时展示更多条目，减少滚动。
  /// 宽度与标准一致（panelSize 保留 200pt 双肩余量），仅加高岛身。
  static let clipboard = IslandModuleLayout(
    islandSize: CGSize(width: 660, height: 500),
    panelSize: CGSize(width: 860, height: 504)
  )
  static let ai = IslandModuleLayout(
    islandSize: CGSize(width: 820, height: 470),
    panelSize: CGSize(width: 820, height: 474)
  )
  static let system = IslandModuleLayout(
    islandSize: CGSize(width: 660, height: 560),
    panelSize: CGSize(width: 660, height: 564)
  )
  /// 随记：需要更大的编辑/预览区域，并承载图片、表格等富内容，故比标准布局更宽更高。
  static let notes = IslandModuleLayout(
    islandSize: CGSize(width: 720, height: 560),
    panelSize: CGSize(width: 720, height: 564)
  )
  /// 邮件：加宽加高，列表列宽扩至 232pt，发件人/主题/预览不再过早截断，同时可见更多邮件。
  static let mail = IslandModuleLayout(
    islandSize: CGSize(width: 860, height: 520),
    panelSize: CGSize(width: 1060, height: 524)
  )
  /// 语音录音：仅展开一行，显示录音指示与实时转写。
  static let voiceRecording = IslandModuleLayout(
    islandSize: CGSize(width: 660, height: 72),
    panelSize: CGSize(width: 660, height: 76)
  )
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
  static let shared = AppModel()

  @Published var selectedModule: IslandModule = .shelf {
    didSet {
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
        if oldValue == .aiMonitor {
          aiMonitor.unloadUsageHistory()
        }
        break
      }
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
  @Published var isIslandVisible = false {
    didSet {
      guard oldValue != isIslandVisible else { return }
      updateSpectrumMonitoring()
    }
  }
  @Published var isExternalDragging = false
  @Published var detectedLink: URL?
  @Published private(set) var isSharingPickerVisible = false

  /// 磁盘清理完成后请求灵动岛收起的信号（每次 toggle 触发一次）。
  @Published var islandCollapseRequested = false

  /// 磁盘清理弹窗是否可见：可见时保持灵动岛展开，避免指针离开导致提前收起。
  @Published var isCleanupPanelVisible = false

  let settingsStore = FeatureSettingsStore()
  let aiMonitor = AIStateMonitor()
  let notices = SideNoticeQueue()
  let media = NowPlayingService()
  let calendar = CalendarService()
  let shelf = FileShelfStore()
  let weatherLocations = WeatherLocationStore()
  let clipboardMonitor = ClipboardLinkMonitor()
  let clipboardHistory = ClipboardHistoryStore()
  let clipboardHistoryMonitor = ClipboardHistoryMonitor()
  let pomodoro = PomodoroService()
  let powerAssertions = PowerAssertionController()
  let screenCleaning = ScreenCleaningController()
  let systemMonitor = SystemMonitorService()
  let battery = BatteryMonitor()
  let focusMode = FocusModeMonitor()
  let quickNotes = QuickNotesService()
  let mail = MailService()
  let voiceInput = VoiceInputController()

  /// 模型发现状态：用于设置页面展示连接测试结果和可选模型列表。
  @Published var voiceModelDiscoveryState: VoiceModelDiscoveryState = .idle
  @Published var discoveredModels: [AIDiscoveredModel] = []
  @Published private(set) var voiceInputInputMonitoringAccessGranted =
    GlobalHotkeyManager.hasInputMonitoringAccess
  /// 当前设备硬件档案，用于推荐合适的本地小模型。
  @Published var hardwareProfile: AIHardwareProfile?

  private let weatherService = WeatherService()
  private let weatherLocationService = WeatherLocationService()
  private let releaseService = GitHubReleaseService()
  private let downloadService = DownloadService()
  private let hotkeyManager = GlobalHotkeyManager()
  private var voiceModelEndpointRouter = VoiceModelEndpointRouter()
  private var cancellables: Set<AnyCancellable> = []
  private var weatherTask: Task<Void, Never>?
  private var releaseTask: Task<Void, Never>?
  private var downloadTask: Task<Void, Never>?
  private var detectedLinkTask: Task<Void, Never>?
  private var activeDownloadID: UUID?
  private var knownNoticeIDs: Set<String> = []
  private var taskStatuses: [String: AIProgressStatus] = [:]
  private var activeAINoticeIDs: Set<String> = []
  /// 本轮活动已展示过的 AI 通知；超时隐藏后同轮刷新不再入队。
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
    clipboardHistoryMonitor.onContentCaptured = { [weak self] content in
      _ = self?.clipboardHistory.record(content)
    }
    clipboardMonitor.onLinkDetected = { [weak self] url in
      guard let self else { return }
      downloadURL = url.absoluteString
      selectedModule = .download
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

    let childPublishers = [
      settingsStore.objectWillChange,
      notices.objectWillChange,
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
        Task { @MainActor [weak self] in self?.consumeMediaSnapshot(snapshot) }
      }
      .store(in: &cancellables)

    focusMode.$status
      .dropFirst()
      .sink { [weak self] status in
        Task { @MainActor [weak self] in self?.consumeFocusModeStatus(status) }
      }
      .store(in: &cancellables)

    mail.$messages
      .dropFirst()
      .sink { [weak self] messages in
        Task { @MainActor [weak self] in self?.consumeMailMessages(messages) }
      }
      .store(in: &cancellables)
  }

  func start() {
    apply(settings: settingsStore.settings)
    focusMode.start()
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
    detectedLinkTask?.cancel()
    clipboardMonitor.setEnabled(false)
    clipboardHistoryMonitor.setEnabled(false)
    Task { [downloadService] in await downloadService.cancelAll() }
    aiMonitor.stop()
    media.stop()
    pomodoro.stop()
    screenCleaning.stopAll()
    cleaningPowerState = nil
    powerAssertions.releaseAll()
    systemMonitor.stop()
    battery.stop()
    focusMode.stop()
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
      guard let url = URL(
        string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
      ), NSWorkspace.shared.open(url) else {
        transientMessage = "清洁键盘需要在系统设置中允许辅助功能"
        break
      }
      transientMessage = "请打开 zisla 的辅助功能开关后重新开启清洁键盘"
    case .registrationFailed:
      transientMessage = "无法接管键盘输入"
    case .alreadyActive:
      break
    }
    refreshToolboxReminderNotice()
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

  func checkForUpdates(manual: Bool) {
    releaseTask?.cancel()
    updateState = .checking
    let version =
      Bundle.main.object(
        forInfoDictionaryKey: "CFBundleShortVersionString"
      ) as? String ?? "0.1.0"
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
      WindowPlacement.center(alert.window, on: WindowPlacement.screenUnderMouse())
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
    WindowPlacement.center(alert.window, on: WindowPlacement.screenUnderMouse())
    guard canInstall, alert.runModal() == .alertFirstButtonReturn else { return }
    guard !updateController.checkForUpdates() else { return }
    transientMessage = "当前安装包不支持自动更新"
  }

  func selectSystemMonitor() {
    selectedModule = .system
    Task { await systemMonitor.sampleOnce() }
  }

  func addToShelf(_ urls: [URL]) {
    let count = shelf.add(urls)
    guard count > 0 else { return }
    transientMessage = "已加入 \(count) 个项目"
    selectedModule = .shelf
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
    selectedModule = .download
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
            }
          }
        }
        guard !Task.isCancelled, self?.activeDownloadID == taskID else { return }
        self?.downloadState = .completed(result.fileURL)
        self?.activeDownloadID = nil
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
        }
      } catch {
        guard self?.activeDownloadID == taskID else { return }
        self?.downloadState = .failed(Self.downloadErrorText(error))
        self?.activeDownloadID = nil
      }
    }
  }

  func cancelDownload() {
    guard let taskID = activeDownloadID else { return }
    downloadTask?.cancel()
    Task { [downloadService] in await downloadService.cancel(taskID: taskID) }
  }

  private func apply(settings: FeatureSettings) {
    // 常规界面外观由用户设置决定；岛面板在窗口级单独固定深色（见 IslandPanel）。
    NSApp.appearance = settings.appearanceMode.nsAppearance
    media.setPreferredSource(settings.mediaSource)
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
      consumeFocusModeStatus(focusMode.status)
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

  // MARK: - 语音模型发现

  /// 测试当前模型端点并发现可用模型。
  func discoverModels() {
    let settings = settingsStore.settings
    let isRemote = settings.voiceModelEndpointMode == .remote
    let remoteEndpoint = isRemote
      ? voiceModelEndpointRouter.next(
        from: settings.voiceModelRemoteEndpoints,
        selectedID: settings.voiceModelSelectedRemoteEndpointID,
        loadBalancingEnabled: settings.voiceModelRemoteLoadBalancingEnabled
      )
      : nil
    if isRemote, remoteEndpoint == nil {
      voiceModelDiscoveryState = .failed("请添加并启用至少一个远端端点")
      discoveredModels = []
      return
    }

    let apiKey = remoteEndpoint?.apiKey
    if remoteEndpoint != nil {
      guard !(apiKey?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true) else {
        voiceModelDiscoveryState = .failed("请先填写当前远端端点的 API Key")
        discoveredModels = []
        return
      }
    }
    let endpoint = AIEndpoint(
      name: remoteEndpoint?.name ?? settings.voiceModelEndpointKind.defaultEndpointName,
      baseURL: remoteEndpoint?.baseURL ?? settings.voiceModelBaseURL,
      kind: isRemote ? .openAICompatible : settings.voiceModelEndpointKind
    )
    voiceModelDiscoveryState = .testing
    Task { @MainActor in
      let service = AIModelDiscoveryService()
      do {
        let models = try await service.models(for: endpoint, apiKey: apiKey)
        self.discoveredModels = models
        self.voiceModelDiscoveryState = .success(models.count)
        if !isRemote, settings.voiceModelName.isEmpty, let first = models.first {
          self.settingsStore.settings.voiceModelName = first.name
        }
      } catch {
        self.voiceModelDiscoveryState = .failed(error.localizedDescription)
        self.discoveredModels = []
      }
    }
  }

  func updateVoiceModelRemoteAPIKey(_ apiKey: String) {
    updateSelectedVoiceModelRemoteEndpoint { $0.apiKey = apiKey }
  }

  var selectedVoiceModelRemoteEndpoint: VoiceModelRemoteEndpoint? {
    let settings = settingsStore.settings
    if let id = settings.voiceModelSelectedRemoteEndpointID,
       let endpoint = settings.voiceModelRemoteEndpoints.first(where: { $0.id == id }) {
      return endpoint
    }
    return settings.voiceModelRemoteEndpoints.first
  }

  var currentVoiceModelName: String {
    if settingsStore.settings.voiceModelEndpointMode == .remote {
      return selectedVoiceModelRemoteEndpoint?.modelName ?? ""
    }
    return settingsStore.settings.voiceModelName
  }

  func selectVoiceModelRemoteEndpoint(_ id: UUID) {
    guard settingsStore.settings.voiceModelRemoteEndpoints.contains(where: { $0.id == id }) else { return }
    settingsStore.settings.voiceModelSelectedRemoteEndpointID = id
    voiceModelEndpointRouter.reset()
    resetVoiceModelDiscovery()
  }

  func addVoiceModelRemoteEndpoint() {
    var settings = settingsStore.settings
    let endpoint = VoiceModelRemoteEndpoint(name: "远端端点 \(settings.voiceModelRemoteEndpoints.count + 1)")
    settings.voiceModelRemoteEndpoints.append(endpoint)
    settings.voiceModelSelectedRemoteEndpointID = endpoint.id
    settingsStore.settings = settings
    voiceModelEndpointRouter.reset()
    resetVoiceModelDiscovery()
  }

  func removeSelectedVoiceModelRemoteEndpoint() {
    guard let endpoint = selectedVoiceModelRemoteEndpoint else { return }
    var settings = settingsStore.settings
    settings.voiceModelRemoteEndpoints.removeAll { $0.id == endpoint.id }
    settings.voiceModelSelectedRemoteEndpointID = settings.voiceModelRemoteEndpoints.first?.id
    settingsStore.settings = settings
    voiceModelEndpointRouter.reset()
    resetVoiceModelDiscovery()
  }

  func updateSelectedVoiceModelRemoteEndpoint(
    _ update: (inout VoiceModelRemoteEndpoint) -> Void
  ) {
    guard let endpointID = selectedVoiceModelRemoteEndpoint?.id else { return }
    var settings = settingsStore.settings
    guard let index = settings.voiceModelRemoteEndpoints.firstIndex(where: { $0.id == endpointID }) else {
      return
    }
    update(&settings.voiceModelRemoteEndpoints[index])
    settingsStore.settings = settings
    voiceModelEndpointRouter.reset()
    resetVoiceModelDiscovery()
  }

  func setVoiceModelRemoteLoadBalancingEnabled(_ enabled: Bool) {
    settingsStore.settings.voiceModelRemoteLoadBalancingEnabled = enabled
    voiceModelEndpointRouter.reset()
    resetVoiceModelDiscovery()
  }

  func updateCurrentVoiceModelName(_ name: String) {
    if settingsStore.settings.voiceModelEndpointMode == .remote {
      updateSelectedVoiceModelRemoteEndpoint { $0.modelName = name }
    } else {
      settingsStore.settings.voiceModelName = name
    }
  }

  private func resetVoiceModelDiscovery() {
    discoveredModels = []
    voiceModelDiscoveryState = .idle
  }

  /// 获取当前设备的硬件档案，用于推荐模型。
  func refreshHardwareProfile() {
    guard hardwareProfile == nil else { return }
    let machineName = Host.current().localizedName ?? "Mac"
    var size = 0
    if sysctlbyname("hw.memsize", nil, &size, nil, 0) == 0, size > 0 {
      var memory = UInt64(0)
      if sysctlbyname("hw.memsize", &memory, &size, nil, 0) == 0 {
        hardwareProfile = AIHardwareProfile(
          machineName: machineName,
          memoryBytes: memory
        )
      }
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
    media.setSpectrumMonitoringEnabled(
      settingsStore.settings.mediaEnabled
        && (isIslandVisible || media.snapshot?.isPlaying == true)
    )
  }

  private func clearMediaNotices() {
    for id in mediaNoticeIDs { notices.remove(id: id) }
    mediaActivityPresented = false
  }

  private func consumeFocusModeStatus(_ status: FocusModeStatus) {
    let settings = settingsStore.settings
    guard settings.sideNoticesEnabled, status.isActive else {
      clearFocusModeNotices()
      return
    }

    let presentation = status.presentation
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

  private func noticeExists(id: String) -> Bool {
    notices.left.contains { $0.id == id } || notices.right.contains { $0.id == id }
  }

  private func noticeSide(for provider: AIProvider) -> NoticeSide {
    switch provider {
    case .claude, .gemini, .qwen, .trae, .doubao: .left
    case .codex, .grok, .gpt, .coder, .opencode, .harness: .right
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
  /// 对应的 NSApp 级外观；`nil` 表示跟随系统。
  var nsAppearance: NSAppearance? {
    switch self {
    case .system: nil
    case .light: NSAppearance(named: .aqua)
    case .dark: NSAppearance(named: .darkAqua)
    }
  }
}
