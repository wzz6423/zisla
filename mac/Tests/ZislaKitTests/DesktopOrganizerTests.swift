import AppKit
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

    @Test
    func trashEmptyingScriptCompilesAgainstTheFinderDictionaryWithoutRunningIt() async throws {
        var source = ""
        let result = await DesktopOrganizer.emptyTrash(execute: {
            source = $0
            return .success(())
        })
        if case .failure(let error) = result { Issue.record("Unexpected injected executor failure: \(error)") }
        let script = try #require(NSAppleScript(source: source))
        var error: NSDictionary?
        #expect(script.compileAndReturnError(&error))
        #expect(error == nil)
    }

    @Test(arguments: [false, true].flatMap { warns in
        [false, true].flatMap { fails in [0, 3].map { (warns, fails, $0) } }
    })
    func generatedEmptyingScriptRestoresWarningsAndPreservesFailures(
        initiallyWarns: Bool, fails: Bool, itemCount: Int
    ) async throws {
        var source = ""
        _ = await DesktopOrganizer.emptyTrash(execute: {
            source = $0
            return .success(())
        })
        // Replace Finder commands before execution so this case cannot touch real files or preferences.
        let fixtureSource = source
            .replacingOccurrences(of: "tell application \"Finder\"", with: "")
            .replacingOccurrences(of: "end tell", with: "")
            .replacingOccurrences(of: "warns before emptying of trash", with: "fixtureWarns")
            .replacingOccurrences(of: "empty trash", with: """
                set fixtureWarnsAtEmptying to fixtureWarns
                if \(fails ? "true" : "false") then error "Injected permission denial" number -1743
                set fixtureItems to 0
                """)
        #expect(!fixtureSource.contains("application \"Finder\""))
        #expect(!fixtureSource.contains("empty trash"))
        let script = try #require(NSAppleScript(source: """
            set fixtureWarns to \(initiallyWarns ? "true" : "false")
            set fixtureItems to \(itemCount)
            set fixtureWarnsAtEmptying to true
            set caughtNumber to 0
            set caughtMessage to ""
            try
                \(fixtureSource)
            on error errorMessage number errorNumber
                set caughtNumber to errorNumber
                set caughtMessage to errorMessage
            end try
            return {fixtureWarns, fixtureWarnsAtEmptying, fixtureItems, caughtNumber, caughtMessage}
            """))
        var error: NSDictionary?
        let result = script.executeAndReturnError(&error)
        #expect(error == nil)
        #expect(result.atIndex(1)?.booleanValue == initiallyWarns)
        #expect(result.atIndex(2)?.booleanValue == false)
        #expect(result.atIndex(3)?.int32Value == (fails ? Int32(itemCount) : 0))
        #expect(result.atIndex(4)?.int32Value == (fails ? -1743 : 0))
        #expect(result.atIndex(5)?.stringValue == (fails ? "Injected permission denial" : ""))
    }

    @Test
    func injectedAutomationFailureIsReturnedWithoutReportingSuccess() async {
        let result = await DesktopOrganizer.emptyTrash(execute: { _ in
            .failure(.failed("Automation permission denied"))
        })
        if case .failure(let error) = result {
            #expect(error == .failed("Automation permission denied"))
        } else { Issue.record("Automation failure must reach the caller") }
    }
}
