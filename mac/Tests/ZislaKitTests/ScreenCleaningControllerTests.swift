import Testing
@testable import ZislaKit

@MainActor
struct ScreenCleaningControllerTests {
    @Test
    func startsWhenEventTapWasInstalledEvenIfAccessibilityPreflightIsStale() {
        let result = ScreenCleaningController.keyboardCleaningStartResult(
            eventTapInstalled: true,
            hasAccessibilityAccess: false
        )

        #expect(result == .started)
    }

    @Test
    func reportsAccessibilityPermissionWhenEventTapCannotBeInstalled() {
        let result = ScreenCleaningController.keyboardCleaningStartResult(
            eventTapInstalled: false,
            hasAccessibilityAccess: false
        )

        #expect(result == .accessibilityPermissionRequired)
    }

    @Test
    func reportsRegistrationFailureWhenAccessibilityIsGrantedButEventTapFails() {
        let result = ScreenCleaningController.keyboardCleaningStartResult(
            eventTapInstalled: false,
            hasAccessibilityAccess: true
        )

        #expect(result == .registrationFailed)
    }
}
