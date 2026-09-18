import Testing

@testable import Zisla

struct KeyboardFocusPolicyTests {
    @Test
    func clipboardShelfAndDownloadTextSurfacesRemainKeyboardEligible() {
        #expect(IslandModule.clipboard.allowsIslandKeyboardFocus)
        #expect(IslandModule.shelf.allowsIslandKeyboardFocus)
        #expect(IslandModule.download.allowsIslandKeyboardFocus)
    }

    @Test
    func otherModulesKeepTheExistingKeyboardFocusPolicy() {
        let allowedModules: Set<IslandModule> = [.shelf, .clipboard, .download, .mail, .quickNotes]
        for module in IslandModule.allCases {
            #expect(module.allowsIslandKeyboardFocus == allowedModules.contains(module))
        }
    }
}
