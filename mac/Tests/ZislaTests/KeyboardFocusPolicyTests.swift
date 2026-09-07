import Testing

@testable import Zisla

struct KeyboardFocusPolicyTests {
    @Test
    func clipboardAndShelfSearchSurfacesRemainKeyboardEligible() {
        #expect(IslandModule.clipboard.allowsIslandKeyboardFocus)
        #expect(IslandModule.shelf.allowsIslandKeyboardFocus)
    }

    @Test
    func otherModulesKeepTheExistingKeyboardFocusPolicy() {
        let allowedModules: Set<IslandModule> = [.shelf, .clipboard, .mail, .quickNotes]
        for module in IslandModule.allCases {
            #expect(module.allowsIslandKeyboardFocus == allowedModules.contains(module))
        }
    }
}
