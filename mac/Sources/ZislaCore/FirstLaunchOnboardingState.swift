import Foundation

public final class FirstLaunchOnboardingState {
    public static let startedKey = "zisla.onboarding.started-v1"
    public static let completedKey = "zisla.onboarding.completed-v1"

    private let defaults: UserDefaults
    private let isDebugBundle: Bool
    private let forceDebugPresentation: Bool
    private let hasExistingInstallation: Bool

    /// Capture existing-installation evidence before creating any settings stores or services.
    public init(
        defaults: UserDefaults = .standard,
        bundleIdentifier: String? = Bundle.main.bundleIdentifier,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        hasExistingInstallation: Bool
    ) {
        self.defaults = defaults
        isDebugBundle = bundleIdentifier == "dev.wzz.zisla.debug"
        forceDebugPresentation = environment["ZISLA_FIRST"] == "1"
        self.hasExistingInstallation = hasExistingInstallation
    }

    public var shouldPresent: Bool {
        if isDebugBundle { return forceDebugPresentation }
        if defaults.bool(forKey: Self.completedKey) { return false }
        if defaults.bool(forKey: Self.startedKey) { return true }
        return !hasExistingInstallation
    }

    /// Persist before initializing services, so interrupted new installs remain eligible.
    public func recordStarted() {
        guard !isDebugBundle, shouldPresent else { return }
        defaults.set(true, forKey: Self.startedKey)
    }

    public func recordCompleted() {
        guard !isDebugBundle, shouldPresent else { return }
        defaults.set(true, forKey: Self.completedKey)
    }
}
