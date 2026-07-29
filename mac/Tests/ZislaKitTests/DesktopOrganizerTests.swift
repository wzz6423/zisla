import Foundation
import Testing

@testable import ZislaKit

@MainActor
struct DesktopOrganizerTests {
    @Test
    func stacksAreOffWhenFinderGroupsByNothing() {
        #expect(DesktopOrganizer.isStacksEnabled(groupBy: nil) == false)
        #expect(DesktopOrganizer.isStacksEnabled(groupBy: "") == false)
        #expect(DesktopOrganizer.isStacksEnabled(groupBy: "None") == false)
        // Finder writes casing inconsistently; comparisons must be case-insensitive.
        #expect(DesktopOrganizer.isStacksEnabled(groupBy: "none") == false)
    }

    @Test
    func stacksAreOnForEveryGroupingCriterion() {
        for groupBy in ["Kind", "DateAdded", "DateModified", "DateCreated", "Tags"] {
            #expect(DesktopOrganizer.isStacksEnabled(groupBy: groupBy))
        }
    }

    @Test
    func stacksReadMissingDefaultsAsOff() {
        let suite = "com.zisla.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)
        defer { defaults?.removePersistentDomain(forName: suite) }

        #expect(DesktopOrganizer.isStacksEnabled(defaults: defaults) == false)

        defaults?.set(["GroupBy": "Kind"], forKey: "DesktopViewSettings")
        #expect(DesktopOrganizer.isStacksEnabled(defaults: defaults))

        defaults?.set(["GroupBy": "None"], forKey: "DesktopViewSettings")
        #expect(DesktopOrganizer.isStacksEnabled(defaults: defaults) == false)
    }

    @Test
    func errorMessageUnwrapsTheFailureReason() {
        #expect(DesktopOrganizerError.failed("Finder 没有响应").message == "Finder 没有响应")
    }
}
