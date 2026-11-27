import AppKit
import Combine
import ZislaCore
import ZislaKit

extension Notification.Name {
    static let petLibraryDidChange = Notification.Name("dev.wzz.zisla.petLibraryDidChange")
}

/// Island pet controller: renders a pixel pet inside the Dynamic Island, playing animations in place.
///
/// No separate panel; `IslandRootView` renders the pet beside the expanded island and inside the collapsed island.
///
/// Behavior follows AI task state: active → working, failed → failed, completed → succeeded.
@MainActor
final class IslandPetController: ObservableObject {
    @Published var sprite: PetSprite?
    @Published private(set) var currentPetID: String?
    let behavior = PetBehaviorController()
    private let settingsStore: FeatureSettingsStore
    private let aiMonitor: AIStateMonitor
    private let userPetsDirectory: URL
    private let now: () -> Date
    private let debugInterval: TimeInterval?
    private var cancellables: Set<AnyCancellable> = []
    private var catalogIDs: [String]?
    private var debugSelection: PetRotationSelection?
    private var rotationTask: Task<Void, Never>?

    init(settingsStore: FeatureSettingsStore, aiMonitor: AIStateMonitor,
         userPetsDirectory: URL = PetLibrary.userPetsDirectory,
         environment: [String: String] = ProcessInfo.processInfo.environment,
         isDebugBuild: Bool = LegacyAppDataMigration.isDebugBuild, now: @escaping () -> Date = Date.init) {
        self.settingsStore = settingsStore
        self.aiMonitor = aiMonitor
        self.userPetsDirectory = userPetsDirectory
        self.now = now
        debugInterval = Self.debugRotationInterval(environment: environment, isDebugBuild: isDebugBuild)
    }

    static func debugRotationInterval(environment: [String: String], isDebugBuild: Bool) -> TimeInterval? {
        guard isDebugBuild, let raw = environment["ZISLA_DEBUG_PET_ROTATION_SECONDS"],
              let value = UInt64(raw), value > 0, value <= UInt64.max / 1_000_000_000 else { return nil }
        return TimeInterval(value)
    }

    deinit { rotationTask?.cancel() }

    func start(notificationCenter: NotificationCenter = .default,
               workspaceNotificationCenter: NotificationCenter = NSWorkspace.shared.notificationCenter) {
        guard cancellables.isEmpty else { return }
        settingsStore.$settings
            .removeDuplicates {
                $0.petEnabled == $1.petEnabled && $0.petID == $1.petID &&
                    $0.petSelectionMode == $1.petSelectionMode && $0.petRandomPool == $1.petRandomPool &&
                    $0.petRotationInterval == $1.petRotationInterval
            }
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.refresh() }
            .store(in: &cancellables)
        aiMonitor.$state
            .removeDuplicates()
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.updateActivityFromAI() }
            .store(in: &cancellables)
        for (center, name) in [
            (notificationCenter, Notification.Name.NSCalendarDayChanged),
            (notificationCenter, .NSSystemClockDidChange),
            (notificationCenter, .NSSystemTimeZoneDidChange),
            (notificationCenter, .petLibraryDidChange),
            (workspaceNotificationCenter, NSWorkspace.didWakeNotification),
        ] {
            center.publisher(for: name)
                .receive(on: DispatchQueue.main)
                .sink { [weak self] _ in
                    self?.catalogIDs = nil
                    self?.refresh()
                }
                .store(in: &cancellables)
        }
        refresh()
    }

    func stop() {
        cancellables.removeAll()
        rotationTask?.cancel()
        rotationTask = nil
        catalogIDs = nil
        debugSelection = nil
        sprite = nil
        currentPetID = nil
        behavior.setActivity(nil)
    }

    private func refresh() {
        rotationTask?.cancel()
        rotationTask = nil
        var settings = settingsStore.settings
        guard settings.petEnabled else {
            sprite = nil
            currentPetID = nil
            return
        }
        let petID: String?
        switch settings.petSelectionMode {
        case .fixed:
            petID = settings.petID
        case .randomRotation:
            let ids = catalogIDs ?? PetLibrary.entries(userPetsDirectory: userPetsDirectory).map(\.id)
            catalogIDs = ids
            let candidates = settings.petRotationCandidates(availableIDs: ids)
            if settings.petRandomPool != settingsStore.settings.petRandomPool {
                settingsStore.settings.petRandomPool = settings.petRandomPool
            }
            let date = now()
            let previous = debugSelection ?? settingsStore.petRotationSelection
            let next = PetRotationSelection.resolve(previous: previous, candidates: candidates,
                                                    interval: debugInterval ?? settings.petRotationInterval, at: date)
            if debugInterval != nil {
                debugSelection = next
            } else if next != previous {
                settingsStore.petRotationSelection = next
            }
            petID = next?.petID
            if candidates.count > 1, let deadline = next?.nextRotation(after: date) {
                let wake = ContinuousClock.now.advanced(by: .seconds(deadline.timeIntervalSince(date)))
                rotationTask = Task { [weak self] in
                    do { try await Task.sleep(until: wake, clock: .continuous) } catch { return }
                    guard !Task.isCancelled else { return }
                    self?.refresh()
                }
            }
        }
        if petID != currentPetID || sprite == nil {
            currentPetID = petID
            sprite = petID.flatMap { PetLibrary.loadSelectedSprite(for: $0, userPetsDirectory: userPetsDirectory) }
        }
        updateActivityFromAI()
    }

    private func updateActivityFromAI() {
        guard settingsStore.settings.petEnabled else { return }
        let tasks = aiMonitor.state.tasks
        let active = tasks.filter(\.status.isActive)
        if tasks.contains(where: { $0.status == .failed || $0.status == .error }) {
            behavior.setActivity(.failed)
        } else if active.contains(where: { $0.status == .blocked }) {
            behavior.setActivity(.waiting)
        } else if !active.isEmpty {
            behavior.setActivity(.working)
        } else if tasks.contains(where: { $0.status == .succeeded }) {
            behavior.setActivity(.succeeded)
        } else {
            behavior.setActivity(nil)
        }
    }
}
