import Combine
import ZislaCore
import ZislaKit
import SwiftUI

/// 岛内宠物控制器：在灵动岛「内部」渲染一只像素宠物，原地播放动画。
///
/// 不另起面板、不贴岛边缘；宠物由 `IslandRootView` 直接嵌入 `IslandSurface`，
/// 受 `IslandSilhouette()` 裁剪，读起来像「就在岛里面」。
///
/// 宠物形象为内置资源（编译进 App 包），不支持用户导入或网络安装。
/// 行为跟随 AI 任务状态：运行中→working、失败→failed、完成→succeeded。
@MainActor
final class IslandPetController: ObservableObject {
    @Published var sprite: PetSprite?
    let behavior = PetBehaviorController()
    private let model: AppModel
    private var cancellables: Set<AnyCancellable> = []
    private var loadedPetID: String?

    init(model: AppModel) {
        self.model = model
        model.settingsStore.$settings
            .removeDuplicates()
            .sink { [weak self] _ in Task { @MainActor [weak self] in self?.refresh() } }
            .store(in: &cancellables)
        model.aiMonitor.$state
            .removeDuplicates()
            .sink { [weak self] _ in Task { @MainActor [weak self] in self?.updateActivityFromAI() } }
            .store(in: &cancellables)
    }

    func start() {
        refresh()
    }

    func stop() {
        cancellables.removeAll()
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
