import Foundation
import Testing
@testable import ZislaKit

@MainActor
private final class FakeOnboardingPermissions {
    var statuses: [OnboardingPermissionID: OnboardingPermissionStatus] = [:]
    var requests: [OnboardingPermissionID] = []
    var completions: [OnboardingPermissionCoordinator.RequestCompletion] = []
    var cancellations = 0
    var activeResources = 0
    var opened: [URL] = []
    var delayedReads: [OnboardingPermissionCoordinator.Completion] = []
    var delayReads = false

    func coordinator() -> OnboardingPermissionCoordinator {
        OnboardingPermissionCoordinator(dependencies: .init(
            read: { id, completion in
                if self.delayReads { self.delayedReads.append(completion) }
                else { completion(self.statuses[id] ?? (id.requiresManualSetup ? .manual : .notDetermined)) }
            },
            request: { id, completion in
                self.requests.append(id)
                self.activeResources += 1
                self.completions.append(completion)
            },
            cancel: {
                self.cancellations += 1
                self.activeResources = 0
            },
            openSettings: { self.opened.append($0); return true }
        ))
    }
}

@MainActor
struct OnboardingPermissionCoordinatorTests {
    private func status(_ id: OnboardingPermissionID, _ coordinator: OnboardingPermissionCoordinator) -> OnboardingPermissionStatus? {
        coordinator.permissions.first(where: { $0.id == id })?.status
    }

    @Test func initializationAndRefreshNeverRequest() {
        let fake = FakeOnboardingPermissions()
        fake.statuses[.camera] = .restricted
        fake.statuses[.microphone] = .denied
        fake.statuses[.location] = .granted
        fake.statuses[.bluetooth] = .unavailable
        let coordinator = fake.coordinator()
        defer { coordinator.close() }
        #expect(fake.requests.isEmpty)
        coordinator.refresh()
        #expect(fake.requests.isEmpty)
        #expect(coordinator.permissions.count == 15)
        #expect(status(.camera, coordinator) == .restricted)
        #expect(status(.microphone, coordinator) == .denied)
        #expect(status(.location, coordinator) == .granted)
        #expect(status(.bluetooth, coordinator) == .unavailable)
        #expect(status(.automation, coordinator) == .manual)
        #expect(status(.files, coordinator) == .manual)
        #expect(status(.systemAudio, coordinator) == .manual)
        #expect(status(.fullDiskAccess, coordinator) == .manual)
    }

    @Test func duplicateAndConcurrentRequestsAreRejected() {
        let fake = FakeOnboardingPermissions()
        let coordinator = fake.coordinator()
        defer { coordinator.close() }
        #expect(coordinator.request(.camera))
        #expect(!coordinator.request(.camera))
        #expect(!coordinator.request(.microphone))
        coordinator.refresh()
        #expect(status(.camera, coordinator) == .requesting)
        #expect(fake.requests == [.camera])
        fake.completions[0](.success(.granted))
        #expect(coordinator.requesting == nil)
        #expect(!coordinator.request(.camera))
        #expect(coordinator.request(.microphone))
    }

    @Test func refusalAndDependencyFailureReleaseRequestSlot() {
        let fake = FakeOnboardingPermissions()
        let coordinator = fake.coordinator()
        defer { coordinator.close() }
        #expect(coordinator.request(.microphone))
        fake.completions[0](.success(.denied))
        #expect(status(.microphone, coordinator) == .denied)
        #expect(coordinator.requesting == nil)
        #expect(!coordinator.request(.microphone))
        #expect(coordinator.request(.camera))
        fake.completions[1](.failure(CancellationError()))
        #expect(coordinator.requesting == nil)
        #expect(fake.activeResources == 0)
        #expect(status(.camera, coordinator) == .notDetermined)
        #expect(coordinator.request(.camera))
    }

    @Test func cancelReleasesResourcesAndIgnoresOldCompletion() {
        let fake = FakeOnboardingPermissions()
        let coordinator = fake.coordinator()
        defer { coordinator.close() }
        #expect(coordinator.request(.location))
        let old = fake.completions[0]
        coordinator.cancelCurrentRequest()
        #expect(fake.activeResources == 0)
        #expect(coordinator.requesting == nil)
        #expect(coordinator.request(.bluetooth))
        old(.success(.granted))
        #expect(coordinator.requesting == .bluetooth)
        #expect(status(.location, coordinator) == .notDetermined)
    }

    @Test func closeIgnoresLateRequestsAndRefreshes() {
        let fake = FakeOnboardingPermissions()
        let coordinator = fake.coordinator()
        #expect(coordinator.request(.bluetooth))
        fake.delayReads = true
        coordinator.refresh()
        coordinator.close()
        let closed = coordinator.permissions
        fake.completions[0](.success(.granted))
        for read in fake.delayedReads { read(.granted) }
        coordinator.refresh()
        #expect(coordinator.permissions == closed)
        #expect(coordinator.requesting == nil)
        #expect(fake.activeResources == 0)
        #expect(fake.cancellations == 1)
        #expect(!coordinator.request(.camera))
        coordinator.close()
        #expect(fake.cancellations == 1)
    }

    @Test func settingsDoNotPretendToGrantManualPermissions() {
        let fake = FakeOnboardingPermissions()
        let coordinator = fake.coordinator()
        defer { coordinator.close() }
        coordinator.refresh()
        let manualPermissions = OnboardingPermissionID.allCases.filter(\.requiresManualSetup)
        #expect(Set(manualPermissions) == [.systemAudio, .automation, .files, .fullDiskAccess])
        for id in manualPermissions {
            #expect(!coordinator.request(id))
            #expect(coordinator.openSettings(for: id))
            #expect(status(id, coordinator) == .manual)
        }
        #expect(fake.opened == manualPermissions.map(\.settingsURL))
        #expect(fake.requests.isEmpty)
    }

    @Test func requestRechecksActualAuthorizationBeforePrompting() {
        let fake = FakeOnboardingPermissions()
        fake.statuses[.camera] = .granted
        let coordinator = fake.coordinator()
        defer { coordinator.close() }
        #expect(coordinator.request(.camera))
        #expect(status(.camera, coordinator) == .granted)
        #expect(fake.requests.isEmpty)
        #expect(coordinator.requesting == nil)
    }

    @Test(arguments: [OnboardingPermissionID.accessibility, .inputMonitoring, .screenRecording])
    func deniedBooleanPermissionsKeepTheirSettingsActionAfterRefresh(id: OnboardingPermissionID) {
        let fake = FakeOnboardingPermissions()
        let coordinator = fake.coordinator()
        defer { coordinator.close() }
        #expect(coordinator.request(id))
        fake.completions[0](.success(.denied))
        coordinator.refresh()
        #expect(status(id, coordinator) == .denied)
        #expect(coordinator.permissions.first(where: { $0.id == id })?.actionKey == "onboarding.open_settings")
        #expect(!coordinator.request(id))
        fake.statuses[id] = .granted
        coordinator.refresh()
        #expect(status(id, coordinator) == .granted)
    }

    @Test func staleRefreshCannotOverwriteCompletedRequest() {
        let fake = FakeOnboardingPermissions()
        let coordinator = fake.coordinator()
        defer { coordinator.close() }
        fake.delayReads = true
        coordinator.refresh()
        let oldReads = fake.delayedReads
        fake.delayReads = false
        #expect(coordinator.request(.camera))
        fake.completions[0](.success(.granted))
        for read in oldReads { read(.denied) }
        #expect(status(.camera, coordinator) == .granted)
    }
}
