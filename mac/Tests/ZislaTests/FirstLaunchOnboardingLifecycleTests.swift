import Foundation
import Testing
import ZislaCore
@testable import Zisla

@MainActor
struct FirstLaunchOnboardingLifecycleTests {
    private func withDefaults(_ body: (UserDefaults) -> Void) {
        let name = "FirstLaunchOnboardingLifecycleTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        body(defaults)
    }

    @Test func completedFlowStartsOneNormalApplication() {
        withDefaults { defaults in
            let state = FirstLaunchOnboardingState(defaults: defaults, bundleIdentifier: "dev.wzz.zisla", environment: [:], hasExistingInstallation: false)
            var runningApplications: [UUID] = []
            let lifecycle = FirstLaunchOnboardingLifecycle(state: state) { runningApplications.append(UUID()) }
            #expect(lifecycle.begin())
            #expect(defaults.bool(forKey: FirstLaunchOnboardingState.startedKey))
            #expect(runningApplications.isEmpty)
            lifecycle.finish(completed: true)
            let firstApplication = runningApplications
            lifecycle.finish(completed: true)
            lifecycle.finish(completed: false)
            #expect(!lifecycle.begin())
            #expect(runningApplications.count == 1)
            #expect(runningApplications == firstApplication)
            #expect(!state.shouldPresent)
        }
    }

    @Test func repeatedBeginAndLateFinishCannotStartAfterTermination() {
        withDefaults { defaults in
            let state = FirstLaunchOnboardingState(defaults: defaults, bundleIdentifier: "dev.wzz.zisla", environment: [:], hasExistingInstallation: false)
            var startupCount = 0
            let lifecycle = FirstLaunchOnboardingLifecycle(state: state) { startupCount += 1 }
            #expect(lifecycle.begin())
            #expect(!lifecycle.begin())
            #expect(startupCount == 0)
            lifecycle.terminate()
            lifecycle.terminate()
            lifecycle.finish(completed: false)
            lifecycle.finish(completed: true)
            #expect(!lifecycle.begin())
            #expect(startupCount == 0)
            #expect(!defaults.bool(forKey: FirstLaunchOnboardingState.completedKey))
        }
    }

    @Test func closingStartsNormallyButInterruptedInstallRemainsEligible() {
        withDefaults { defaults in
            let state = FirstLaunchOnboardingState(defaults: defaults, bundleIdentifier: "dev.wzz.zisla", environment: [:], hasExistingInstallation: false)
            var normalApplicationIsRunning = false
            let lifecycle = FirstLaunchOnboardingLifecycle(state: state) { normalApplicationIsRunning = true }
            #expect(lifecycle.begin())
            lifecycle.finish(completed: false)
            #expect(normalApplicationIsRunning)
            #expect(!defaults.bool(forKey: FirstLaunchOnboardingState.completedKey))
            let relaunched = FirstLaunchOnboardingState(defaults: defaults, bundleIdentifier: "dev.wzz.zisla", environment: [:], hasExistingInstallation: true)
            #expect(relaunched.shouldPresent)
        }
    }

    @Test func terminationDoesNotStartServicesOrMarkCompleted() {
        withDefaults { defaults in
            let state = FirstLaunchOnboardingState(defaults: defaults, bundleIdentifier: "dev.wzz.zisla", environment: [:], hasExistingInstallation: false)
            var normalApplicationIsRunning = false
            let lifecycle = FirstLaunchOnboardingLifecycle(state: state) { normalApplicationIsRunning = true }
            #expect(lifecycle.begin())
            lifecycle.terminate()
            lifecycle.finish(completed: true)
            #expect(!normalApplicationIsRunning)
            #expect(!defaults.bool(forKey: FirstLaunchOnboardingState.completedKey))
            #expect(state.shouldPresent)
        }
    }

    @Test func upgradeBypassesOnboardingWithoutChangingPreferences() {
        withDefaults { defaults in
            defaults.set(Data([1, 2, 3]), forKey: "feature-settings-v1")
            let before = defaults.dictionaryRepresentation()
            let state = FirstLaunchOnboardingState(defaults: defaults, bundleIdentifier: "dev.wzz.zisla", environment: [:], hasExistingInstallation: true)
            var normalApplicationIsRunning = false
            let lifecycle = FirstLaunchOnboardingLifecycle(state: state) { normalApplicationIsRunning = true }
            #expect(!lifecycle.begin())
            #expect(normalApplicationIsRunning)
            #expect(NSDictionary(dictionary: defaults.dictionaryRepresentation()).isEqual(to: before))
        }
    }
}
