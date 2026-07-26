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
    private let defaultUpdateChannel: UpdateChannel
    private var persistedSettings: FeatureSettings
    private var persistenceTask: Task<Void, Never>?

    public init(
        defaults: UserDefaults = .standard,
        persistenceDelay: Duration = .milliseconds(250),
        defaultUpdateChannel: UpdateChannel? = nil
    ) {
        self.defaults = defaults
        self.persistenceDelay = persistenceDelay
        self.defaultUpdateChannel = defaultUpdateChannel ?? Self.bundledDefaultUpdateChannel
        let initialSettings: FeatureSettings
        var shouldPersistMigration = false
        if
            let data = defaults.data(forKey: key),
            let value = try? JSONDecoder().decode(FeatureSettings.self, from: data)
        {
            var settings = value
            if !Self.containsUpdateChannel(in: data) {
                settings.updateChannel = self.defaultUpdateChannel
                shouldPersistMigration = true
            }
            initialSettings = settings
        } else {
            var settings = FeatureSettings.default
            settings.updateChannel = self.defaultUpdateChannel
            initialSettings = settings
        }
        settings = initialSettings
        persistedSettings = initialSettings
        if shouldPersistMigration, let data = try? JSONEncoder().encode(initialSettings) {
            defaults.set(data, forKey: key)
        }
    }

    public func reset() {
        var settings = FeatureSettings.default
        settings.updateChannel = defaultUpdateChannel
        self.settings = settings
    }

    /// Commits the last coalesced settings change before the app quits.
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

    public static var bundledDefaultUpdateChannel: UpdateChannel {
        guard let rawValue = Bundle.main.object(
            forInfoDictionaryKey: "ZislaDefaultUpdateChannel"
        ) as? String else {
            return .release
        }
        return UpdateChannel(rawValue: rawValue) ?? .release
    }

    private static func containsUpdateChannel(in data: Data) -> Bool {
        guard let object = try? JSONSerialization.jsonObject(with: data),
              let settings = object as? [String: Any]
        else {
            return false
        }
        return settings["updateChannel"] != nil
    }
}
