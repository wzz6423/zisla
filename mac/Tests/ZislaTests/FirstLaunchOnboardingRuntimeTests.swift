import Testing
@testable import Zisla

struct FirstLaunchOnboardingRuntimeTests {
    @Test func idleCollapsedSurfaceRemainsVisibleUntilTutorialEnds() {
        for active in [true, false, true] {
            #expect(IslandRootView.hidesIslandSurface(
                isOnboardingActive: active,
                isIslandVisible: false,
                isCapturingInput: false,
                showsTransientNotice: false,
                isMirrorPresented: false,
                isTeleprompterPresented: false
            ) == !active)
        }
    }

    @Test(arguments: 0..<5)
    func activeSurfaceRemainsVisibleAfterTutorialEnds(activity: Int) {
        for active in [true, false] {
            #expect(!IslandRootView.hidesIslandSurface(
                isOnboardingActive: active,
                isIslandVisible: activity == 0,
                isCapturingInput: activity == 1,
                showsTransientNotice: activity == 2,
                isMirrorPresented: activity == 3,
                isTeleprompterPresented: activity == 4
            ))
        }
    }

    @Test(arguments: 0..<8)
    func tutorialKeepsRealCoordinatorRunningRegardlessOfPreferences(flags: Int) {
        let hover = flags & 1 != 0
        let pet = flags & 2 != 0
        let pinned = flags & 4 != 0
        let active = FirstLaunchOnboardingRuntimePolicy(
            isOnboardingActive: true, hoverActivationEnabled: hover, petEnabled: pet, isPinned: pinned
        )
        #expect(active.shouldRun)
        let finished = FirstLaunchOnboardingRuntimePolicy(
            isOnboardingActive: false, hoverActivationEnabled: hover, petEnabled: pet, isPinned: pinned
        )
        #expect(finished.shouldRun == (hover || pet || pinned))
    }

    @Test func closingTutorialUsesCurrentPreferences() {
        let initial = FirstLaunchOnboardingRuntimePolicy(
            isOnboardingActive: true, hoverActivationEnabled: false, petEnabled: false, isPinned: false
        )
        #expect(initial.shouldRun)
        let changedDuringTutorial = FirstLaunchOnboardingRuntimePolicy(
            isOnboardingActive: false, hoverActivationEnabled: true, petEnabled: false, isPinned: false
        )
        #expect(changedDuringTutorial.shouldRun)
    }

    @Test func tutorialDefersPassiveKeyboardPermissionButAllowsGrantedServices() {
        #expect(!FirstLaunchOnboardingRuntimePolicy.allowsKeyboardServices(isOnboardingActive: true, hasInputMonitoringAccess: false))
        #expect(FirstLaunchOnboardingRuntimePolicy.allowsKeyboardServices(isOnboardingActive: true, hasInputMonitoringAccess: true))
        #expect(FirstLaunchOnboardingRuntimePolicy.allowsKeyboardServices(isOnboardingActive: false, hasInputMonitoringAccess: false))
    }
}
