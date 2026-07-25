import Combine
import Foundation
import ZislaCore

@MainActor
public final class FeatureSettingsStore: ObservableObject {
    @Published public var settings: FeatureSettings {
        didSet { schedulePersistence() }
    }

    private let defaults: UserDefaults
    private let key = "feature-settings-v1"
    private let persistenceDelay: Duration
    private var persistedSettings: FeatureSettings
    private var persistenceTask: Task<Void, Never>?

    public init(
        defaults: UserDefaults = .standard,
        persistenceDelay: Duration = .milliseconds(250)
    ) {
        self.defaults = defaults
        self.persistenceDelay = persistenceDelay
        let initialSettings: FeatureSettings
        if
            let data = defaults.data(forKey: key),
            let value = try? JSONDecoder().decode(FeatureSettings.self, from: data)
        {
            initialSettings = value
        } else {
            initialSettings = .default
        }
        settings = initialSettings
        persistedSettings = initialSettings
    }

    public func reset() {
        settings = .default
    }

    /// 应用退出前提交被合并的最后一次配置修改。
    public func flushPendingChanges() {
        persistenceTask?.cancel()
        persistenceTask = nil
        persist(settings)
    }

    private func schedulePersistence() {
        guard settings != persistedSettings else {
            persistenceTask?.cancel()
            persistenceTask = nil
            return
        }
        persistenceTask?.cancel()
        let snapshot = settings
        let delay = persistenceDelay
        persistenceTask = Task { [weak self] in
            do {
                try await Task.sleep(for: delay)
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            self?.persist(snapshot)
        }
    }

    private func persist(_ settings: FeatureSettings) {
        guard settings != persistedSettings,
              let data = try? JSONEncoder().encode(settings) else { return }
        defaults.set(data, forKey: key)
        persistedSettings = settings
    }
}
