import Combine
import ZislaCore
import ZislaKit
import SwiftUI

/// Island pet controller: renders a pixel pet inside the Dynamic Island, playing animations in place.
///
/// No separate panel; `IslandRootView` renders the pet beside the expanded island and inside the collapsed island.
///
/// Pet sprites are bundled resources (compiled into the app); user import and network install are not supported.
/// Behavior follows AI task state: active → working, failed → failed, completed → succeeded.
@MainActor
final class IslandPetController: ObservableObject {
    @Published var sprite: PetSprite?
    let behavior = PetBehaviorController()
    private let model: AppModel
    private var cancellables: Set<AnyCancellable> = []
    private var loadedPetID: String?

    init(model: AppModel) {
        self.model = model
    }

    func start() {
        guard cancellables.isEmpty else { return }
        model.settingsStore.$settings
            .removeDuplicates()
            .sink { [weak self] _ in Task { @MainActor [weak self] in self?.refresh() } }
            .store(in: &cancellables)
        model.aiMonitor.$state
            .removeDuplicates()
            .sink { [weak self] _ in Task { @MainActor [weak self] in self?.updateActivityFromAI() } }
            .store(in: &cancellables)
        refresh()
    }

    func stop() {
        cancellables.removeAll()
        sprite = nil
        loadedPetID = nil
        behavior.setActivity(nil)
    }

    private func refresh() {
        let settings = model.settingsStore.settings
        guard settings.petEnabled else {
            sprite = nil
            return
        }
        let petID = settings.petID
        if petID != loadedPetID {
            loadedPetID = petID
            sprite = PetLibrary.loadSprite(for: petID)
        }
        updateActivityFromAI()
    }

    private func updateActivityFromAI() {
        guard model.settingsStore.settings.petEnabled else { return }
        let tasks = model.aiMonitor.state.tasks
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
