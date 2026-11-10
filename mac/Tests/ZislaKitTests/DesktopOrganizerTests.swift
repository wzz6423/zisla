import AppKit
import Foundation
import Testing

@testable import ZislaKit

@Suite(.serialized)
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

    @Test(arguments: [false, true].flatMap { warns in
        [false, true].flatMap { fails in [false, true].map { (warns, fails, $0) } }
    })
    func overlappingTrashRequestsRestoreWarningsInSubmissionOrder(
        initiallyWarns: Bool, firstFails: Bool, cancelFirst: Bool
    ) async {
        let firstStarted = TrashOperationTestGate()
        let releaseFirst = TrashOperationTestGate()
        let secondSubmitted = TrashOperationTestGate()
        let secondStarted = TrashOperationTestGate()
        let releaseSecond = TrashOperationTestGate()
        let thirdSubmitted = TrashOperationTestGate()
        let fourthSubmitted = TrashOperationTestGate()
        var warns = initiallyWarns
        var events: [String] = []
        let first = Task { @MainActor in
            await DesktopOrganizer.emptyTrash(execute: { _ in
                let saved = warns
                warns = false
                events.append("first-start")
                firstStarted.signal()
                await releaseFirst.wait()
                warns = saved
                events.append("first-end")
                return firstFails ? .failure(.failed("Injected Finder failure")) : .success(())
            })
        }
        await firstStarted.wait()
        if cancelFirst { first.cancel() }
        let second = Task { @MainActor in
            secondSubmitted.signal()
            return await DesktopOrganizer.emptyTrash(execute: { _ in
                events.append("second-start")
                #expect(warns == initiallyWarns, "A queued operation must see the restored Finder warning")
                let saved = warns
                warns = false
                secondStarted.signal()
                await releaseSecond.wait()
                warns = saved
                events.append("second-end")
                return .success(())
            })
        }
        await secondSubmitted.wait()
        let third = Task { @MainActor in
            thirdSubmitted.signal()
            return await DesktopOrganizer.emptyTrash(execute: { _ in
                events.append("third")
                #expect(warns == initiallyWarns, "A queued request must observe the restored warning")
                return .success(())
            })
        }
        await thirdSubmitted.wait()
        #expect(events == ["first-start"], "Cancellation cannot release an operation still running in Finder")
        #expect(!warns)
        releaseFirst.signal()
        await secondStarted.wait()
        let fourth = Task { @MainActor in
            fourthSubmitted.signal()
            return await DesktopOrganizer.emptyTrash(execute: { _ in
                events.append("fourth")
                #expect(warns == initiallyWarns, "A new request cannot bypass a resumed queue owner")
                return .success(())
            })
        }
        await fourthSubmitted.wait()
        #expect(events == ["first-start", "first-end", "second-start"])
        releaseSecond.signal()
        if case .failure(let error) = await first.value {
            #expect(firstFails)
            #expect(error == .failed("Injected Finder failure"))
        } else { #expect(!firstFails) }
        if case .failure(let error) = await second.value { Issue.record("Queued operation failed: \(error)") }
        if case .failure(let error) = await third.value { Issue.record("Third operation failed: \(error)") }
        if case .failure(let error) = await fourth.value { Issue.record("Fourth operation failed: \(error)") }
        #expect(events == ["first-start", "first-end", "second-start", "second-end", "third", "fourth"])
        #expect(warns == initiallyWarns)
    }

    @Test(arguments: [false, true])
    func cancelledQueuedTrashRequestSkipsFinderAndAllowsTheNextRequest(cancelFirst: Bool) async {
        let firstStarted = TrashOperationTestGate()
        let releaseFirst = TrashOperationTestGate()
        let cancelledSubmitted = TrashOperationTestGate()
        let lastSubmitted = TrashOperationTestGate()
        var events: [String] = []
        let first = Task { @MainActor in
            await DesktopOrganizer.emptyTrash(execute: { _ in
                events.append("first-start")
                firstStarted.signal()
                await releaseFirst.wait()
                events.append("first-end")
                return .success(())
            })
        }
        await firstStarted.wait()
        if cancelFirst { first.cancel() }
        let cancelled = Task { @MainActor in
            cancelledSubmitted.signal()
            return await DesktopOrganizer.emptyTrash(execute: { _ in
                events.append("cancelled")
                return .success(())
            })
        }
        await cancelledSubmitted.wait()
        cancelled.cancel()
        let last = Task { @MainActor in
            lastSubmitted.signal()
            return await DesktopOrganizer.emptyTrash(execute: { _ in
                events.append("last")
                return .success(())
            })
        }
        await lastSubmitted.wait()
        #expect(events == ["first-start"])
        releaseFirst.signal()
        _ = await first.value
        if case .failure(let error) = await cancelled.value {
            #expect(error == .failed(CocoaError(.userCancelled).localizedDescription))
        } else { Issue.record("A cancelled queued request must not report successful deletion") }
        if case .failure(let error) = await last.value { Issue.record("The next request failed: \(error)") }
        #expect(events == ["first-start", "first-end", "last"])
        let next = await DesktopOrganizer.emptyTrash(execute: { _ in
            events.append("next")
            return .success(())
        })
        if case .failure(let error) = next { Issue.record("Idle queue did not recover: \(error)") }
        #expect(events.last == "next")
    }

    @Test
    func alreadyCancelledTrashRequestNeverExecutesFinder() async {
        let begin = TrashOperationTestGate()
        var executed = false
        let task = Task { @MainActor in
            await begin.wait()
            return await DesktopOrganizer.emptyTrash(execute: { _ in
                executed = true
                return .success(())
            })
        }
        task.cancel()
        begin.signal()
        if case .failure(let error) = await task.value {
            #expect(error == .failed(CocoaError(.userCancelled).localizedDescription))
        } else { Issue.record("A cancelled request must not report successful deletion") }
        #expect(!executed)
    }
}

@MainActor
private final class TrashOperationTestGate {
    private var signaled = false
    private var waiter: CheckedContinuation<Void, Never>?

    func wait() async {
        if signaled { return }
        await withCheckedContinuation { waiter = $0 }
    }

    func signal() {
        signaled = true
        waiter?.resume()
        waiter = nil
    }
}
