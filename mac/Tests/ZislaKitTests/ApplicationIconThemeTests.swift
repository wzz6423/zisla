import Testing
import ZislaCore

@testable import ZislaKit

struct ApplicationIconThemeTests {
    @Test
    func explicitAppearanceModesIgnoreSystemAppearance() {
        #expect(ApplicationIconTheme.resolve(mode: .light, systemIsDark: true) == .day)
        #expect(ApplicationIconTheme.resolve(mode: .dark, systemIsDark: false) == .night)
    }

    @Test
    func systemAppearanceSelectsMatchingIconTheme() {
        #expect(ApplicationIconTheme.resolve(mode: .system, systemIsDark: false) == .day)
        #expect(ApplicationIconTheme.resolve(mode: .system, systemIsDark: true) == .night)
    }
}
