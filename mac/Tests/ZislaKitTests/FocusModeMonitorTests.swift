import Testing
@testable import ZislaKit

struct FocusModeMonitorTests {
    @Test
    func knownSystemModeUsesLocalizedPresentation() {
        let status = FocusModeStatus(
            isActive: true,
            identifier: "com.apple.donotdisturb.mode.work"
        )

        #expect(status.presentation == FocusModePresentation(
            title: "工作",
            symbolName: "briefcase.fill"
        ))
    }

    @Test
    func customDisplayNameTakesPriorityOverIdentifierFallback() {
        let status = FocusModeStatus(
            isActive: true,
            identifier: "com.example.deep-work",
            displayName: " 深度工作 "
        )

        #expect(status.presentation == FocusModePresentation(
            title: "深度工作",
            symbolName: "briefcase.fill"
        ))
    }

    @Test
    func unknownModeFallsBackToGenericFocusPresentation() {
        let status = FocusModeStatus(isActive: true, identifier: "com.example.custom")

        #expect(status.presentation == FocusModePresentation(
            title: "专注模式",
            symbolName: "moon.fill"
        ))
    }
}
