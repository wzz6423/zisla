import Foundation
import Testing
@testable import ZislaCore

struct FirstLaunchOnboardingStateTests {
    private func withDefaults(_ body: (UserDefaults) -> Void) {
        let name = "FirstLaunchOnboardingStateTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        body(defaults)
    }

    @Test func firstLaunchCompletionAndRepeat() {
        withDefaults { defaults in
            let state = FirstLaunchOnboardingState(defaults: defaults, bundleIdentifier: "dev.wzz.zisla", environment: [:], hasExistingInstallation: false)
            #expect(state.shouldPresent)
            state.recordStarted()
            state.recordCompleted()
            #expect(!state.shouldPresent)
            let next = FirstLaunchOnboardingState(defaults: defaults, bundleIdentifier: "dev.wzz.zisla", environment: [:], hasExistingInstallation: true)
            #expect(!next.shouldPresent)
        }
    }

    @Test func upgradeDoesNotPresentOrWriteMarkers() {
        withDefaults { defaults in
            let state = FirstLaunchOnboardingState(defaults: defaults, bundleIdentifier: "dev.wzz.zisla", environment: ["ZISLA_FIRST": "1"], hasExistingInstallation: true)
            #expect(!state.shouldPresent)
            state.recordStarted()
            state.recordCompleted()
            #expect(defaults.object(forKey: FirstLaunchOnboardingState.startedKey) == nil)
            #expect(defaults.object(forKey: FirstLaunchOnboardingState.completedKey) == nil)
        }
    }

    @Test func interruptedNewInstallSurvivesServicePersistence() {
        withDefaults { defaults in
            let state = FirstLaunchOnboardingState(defaults: defaults, bundleIdentifier: "dev.wzz.zisla", environment: [:], hasExistingInstallation: false)
            state.recordStarted()
            defaults.set(Data([1]), forKey: "feature-settings-v1")
            let resumed = FirstLaunchOnboardingState(defaults: defaults, bundleIdentifier: "dev.wzz.zisla", environment: [:], hasExistingInstallation: true)
            #expect(resumed.shouldPresent)
            resumed.recordCompleted()
            #expect(!resumed.shouldPresent)
        }
    }

    @Test(arguments: ["1", "0", "", "true", "01", " 1", "1 ", "invalid"], [false, true])
    func debugOverrideIsStrictAndDoesNotWrite(value: String, completed: Bool) {
        withDefaults { defaults in
            defaults.set(completed, forKey: FirstLaunchOnboardingState.completedKey)
            defaults.set("preserved", forKey: "unrelated")
            let before = defaults.dictionaryRepresentation() as NSDictionary
            let state = FirstLaunchOnboardingState(defaults: defaults, bundleIdentifier: "dev.wzz.zisla.debug", environment: ["ZISLA_FIRST": value], hasExistingInstallation: true)
            #expect(state.shouldPresent == (value == "1"))
            state.recordStarted()
            state.recordCompleted()
            #expect(before == defaults.dictionaryRepresentation() as NSDictionary)
        }
    }

    @Test func debugWithoutOverrideNeverPresents() {
        withDefaults { defaults in
            let state = FirstLaunchOnboardingState(defaults: defaults, bundleIdentifier: "dev.wzz.zisla.debug", environment: [:], hasExistingInstallation: false)
            #expect(!state.shouldPresent)
            state.recordStarted()
            state.recordCompleted()
            #expect(defaults.object(forKey: FirstLaunchOnboardingState.startedKey) == nil)
            #expect(defaults.object(forKey: FirstLaunchOnboardingState.completedKey) == nil)
        }
    }

    @Test(arguments: ["0", "", "invalid", "1"])
    func releaseIgnoresOverride(value: String) {
        withDefaults { defaults in
            let state = FirstLaunchOnboardingState(defaults: defaults, bundleIdentifier: "dev.wzz.zisla", environment: ["ZISLA_FIRST": value], hasExistingInstallation: false)
            #expect(state.shouldPresent)
            state.recordCompleted()
            #expect(!state.shouldPresent)
        }
    }
}
