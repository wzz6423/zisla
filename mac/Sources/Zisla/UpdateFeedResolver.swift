import ZislaCore

@MainActor
final class UpdateFeedResolver {
    private(set) var preference: UpdateFeedPreference?
    private let loadPreference: () async -> UpdateFeedPreference
    private var task: Task<Void, Never>?
    private var automaticConfiguration: ((UpdateFeedPreference) -> Void)?
    private var manualCheck: ((UpdateFeedPreference) -> Void)?

    init(loadPreference: @escaping () async -> UpdateFeedPreference) {
        self.loadPreference = loadPreference
    }

    @discardableResult
    func resolve(
        manual: Bool,
        apply: @escaping (UpdateFeedPreference) -> Void
    ) -> Task<Void, Never>? {
        if let preference {
            apply(preference)
            return nil
        }
        if manual {
            manualCheck = apply
        } else {
            automaticConfiguration = apply
        }
        if let task { return task }

        let task = Task { [weak self, loadPreference] in
            let preference = await loadPreference()
            guard !Task.isCancelled, let self else { return }
            self.preference = preference
            self.task = nil
            let automaticConfiguration = self.automaticConfiguration
            let manualCheck = self.manualCheck
            self.automaticConfiguration = nil
            self.manualCheck = nil
            // Apply settings before the pending user request starts Sparkle's check.
            automaticConfiguration?(preference)
            manualCheck?(preference)
        }
        self.task = task
        return task
    }

    func cancelAutomaticConfiguration() {
        automaticConfiguration = nil
    }

    func cancel() {
        task?.cancel()
        task = nil
        automaticConfiguration = nil
        manualCheck = nil
    }
}
