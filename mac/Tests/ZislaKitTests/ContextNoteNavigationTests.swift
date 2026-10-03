import AppKit
import ApplicationServices
import Testing
import ZislaCore
@testable import ZislaKit

@MainActor
struct ContextNoteNavigationTests {
    @MainActor
    private final class Fixture {
        var trusted = true
        var canOpen = true
        var canMove = true
        var windows: [ContextNoteNavigator.Window]? = []
        var displays: [ContextNoteNavigator.Display] = []
        var events: [String] = []
        var opened: [URL] = []
        var points: [CGPoint] = []
        var navigator: ContextNoteNavigator {
            ContextNoteNavigator(dependencies: .init(
                isTrusted: { self.trusted },
                openURL: { self.opened.append($0); return self.canOpen },
                windows: { self.events.append($0); return self.windows },
                displays: { self.displays },
                movePointer: { self.points.append($0); return self.canMove },
                desktopDirectory: { URL(fileURLWithPath: "/synthetic/Desktop") }
            ))
        }

        func window(title: String = "Doc", minimized: Bool? = false, fails: String? = nil) -> ContextNoteNavigator.Window {
            .init(title: title, isMinimized: minimized,
                  restore: { self.events.append("restore"); return fails != "restore" },
                  activate: { self.events.append("activate"); return fails != "activate" },
                  raise: { self.events.append("raise"); return fails != "raise" })
        }
    }

    private let window = ContextNoteLocation.window(bundleIdentifier: "test.editor", applicationName: "Editor", title: "Doc")

    @Test
    func pagesOpenTheirCompleteAddressAndRejectNonWebSchemes() throws {
        let fixture = Fixture()
        fixture.trusted = false
        let address = try #require(URL(string: "https://user:secret@example.test/path?query=1#part"))
        #expect(fixture.navigator.navigate(to: .webPage(url: address, title: "Page", applicationName: "Browser")))
        #expect(fixture.opened.map(\.absoluteString) == ["https://example.test/path?query=1#part"])
        for value in ["file:///private/example", "javascript:alert(1)", "https://"] {
            #expect(!fixture.navigator.navigate(to: .webPage(url: try #require(URL(string: value)), title: "", applicationName: "")))
        }
        #expect(fixture.opened.count == 1)
        fixture.canOpen = false
        #expect(!fixture.navigator.navigate(to: .webPage(url: address, title: "", applicationName: "")))
        #expect(fixture.events.isEmpty)
        #expect(fixture.points.isEmpty)
    }

    @Test(arguments: [false, true])
    func onlyTheExactWindowIsRaisedAndRestoredWhenNeeded(minimized: Bool) {
        let fixture = Fixture()
        fixture.windows = [fixture.window(title: "Other"), fixture.window(minimized: minimized)]
        #expect(fixture.navigator.navigate(to: window))
        #expect(fixture.events == ["test.editor"] + (minimized ? ["restore"] : []) + ["activate", "raise"])
        #expect(fixture.opened.isEmpty)
    }

    @Test(arguments: [false, true], ["Renamed", ""])
    func renamedSingleWindowIsRaisedAndRestoredWhenNeeded(minimized: Bool, title: String) {
        let fixture = Fixture()
        fixture.windows = [fixture.window(title: title, minimized: minimized)]
        #expect(fixture.navigator.navigate(to: window))
        #expect(fixture.events == ["test.editor"] + (minimized ? ["restore"] : []) + ["activate", "raise"])
        #expect(fixture.opened.isEmpty)
    }

    @Test(arguments: [kAXFocusedWindowAttribute, kAXMainWindowAttribute], [false, true])
    func windowReferencesRecoverOmittedFullScreenWindows(attribute: String, listUnavailable: Bool) throws {
        let element = AXUIElementCreateApplication(100001)
        let discovered = try #require(ContextNoteNavigator.windowElements { name in
            if name == kAXWindowsAttribute { return listUnavailable ? nil : [] as CFArray }
            return name == attribute ? element : nil
        })
        #expect(discovered.count == 1)
        let candidate = try #require(discovered.first)
        #expect(CFEqual(candidate.element, element))
        #expect(candidate.requiresExactTitle)
        let fixture = Fixture()
        var target = fixture.window()
        target.requiresExactTitle = candidate.requiresExactTitle
        fixture.windows = [target]
        #expect(fixture.navigator.navigate(to: window))
        #expect(fixture.events == ["test.editor", "activate", "raise"])
        #expect(fixture.opened.isEmpty)
    }

    @Test
    func discoveredWindowReferencesAreDeduplicatedWithoutHidingOtherWindows() throws {
        let listed = AXUIElementCreateApplication(100001)
        let fullScreen = AXUIElementCreateApplication(100002)
        let discovered = try #require(ContextNoteNavigator.windowElements { name in
            switch name {
            case kAXWindowsAttribute: return [listed] as CFArray
            case kAXFocusedWindowAttribute: return fullScreen
            case kAXMainWindowAttribute: return AXUIElementCreateApplication(100002)
            default: return nil
            }
        })
        #expect(discovered.count == 2)
        #expect(discovered.filter { CFEqual($0.element, listed) }.map(\.requiresExactTitle) == [false])
        #expect(discovered.filter { CFEqual($0.element, fullScreen) }.map(\.requiresExactTitle) == [true])

        let repeated = try #require(ContextNoteNavigator.windowElements { name in
            if name == kAXWindowsAttribute { return [listed] as CFArray }
            return AXUIElementCreateApplication(100001)
        })
        #expect(repeated.count == 1)
        #expect(repeated.first?.requiresExactTitle == false)
    }

    @Test(arguments: [false, true], [false, true])
    func missingOrInvalidWindowReferencesDoNotInventCandidates(listUnavailable: Bool, invalidReference: Bool) {
        let discovered = ContextNoteNavigator.windowElements { name in
            if name == kAXWindowsAttribute { return listUnavailable ? nil : [] as CFArray }
            return invalidReference ? "invalid" as CFString : nil
        }
        if listUnavailable {
            #expect(discovered == nil)
        } else {
            #expect(discovered?.isEmpty == true)
        }
    }

    @Test(arguments: ["Renamed", ""])
    func incompleteWindowEnumerationDoesNotAuthorizeNavigatingToADifferentTitle(title: String) {
        let fixture = Fixture()
        var target = fixture.window(title: title)
        target.requiresExactTitle = true
        fixture.windows = [target]
        #expect(!fixture.navigator.navigate(to: window))
        #expect(fixture.events == ["test.editor"])
        #expect(fixture.opened.isEmpty)
    }

    @Test(arguments: ["Doc", "Other", "Missing"])
    func supplementalWindowsParticipateInExactAndAmbiguousTargetSelection(supplementalTitle: String) throws {
        let listed = AXUIElementCreateApplication(100001)
        let supplemental = AXUIElementCreateApplication(100002)
        let discovered = try #require(ContextNoteNavigator.windowElements { name in
            if name == kAXWindowsAttribute { return [listed] as CFArray }
            return supplemental
        })
        let fixture = Fixture()
        fixture.windows = discovered.map { candidate in
            let isSupplemental = CFEqual(candidate.element, supplemental)
            var target = fixture.window(title: isSupplemental ? supplementalTitle : "Other")
            target.requiresExactTitle = candidate.requiresExactTitle
            target.raise = { fixture.events.append(isSupplemental ? "target" : "wrong"); return true }
            return target
        }
        let destination = ContextNoteLocation.window(bundleIdentifier: "test.editor", applicationName: "Editor",
                                                     title: supplementalTitle == "Other" ? "Other" : "Doc")
        #expect(fixture.navigator.navigate(to: destination) == (supplementalTitle == "Doc"))
        #expect(fixture.events == (supplementalTitle == "Doc" ? ["test.editor", "activate", "target"] : ["test.editor"]))
        #expect(fixture.opened.isEmpty)
    }

    @Test
    func missingAmbiguousAndUntrustedWindowsNeverActivateAnArbitraryWindow() {
        let fixture = Fixture()
        for candidates in [nil, [], [fixture.window(title: "Other"), fixture.window(title: "Another")],
                           [fixture.window(), fixture.window()], [fixture.window(minimized: nil)],
                           [fixture.window(title: "Renamed", minimized: nil)]] as [[ContextNoteNavigator.Window]?] {
            fixture.windows = candidates
            fixture.events = []
            #expect(!fixture.navigator.navigate(to: window))
            #expect(fixture.events == ["test.editor"])
        }
        fixture.windows = [fixture.window(title: "Renamed")]
        fixture.events = []
        #expect(!fixture.navigator.navigate(to: .window(bundleIdentifier: "test.editor", applicationName: "Editor", title: " \n")))
        #expect(fixture.events.isEmpty)
        fixture.trusted = false
        fixture.events = []
        #expect(!fixture.navigator.navigate(to: window))
        #expect(fixture.events.isEmpty)
    }

    @Test(arguments: ["restore", "activate", "raise"], ["Doc", "Renamed"])
    func failedWindowActionsStopAndReportFailure(action: String, title: String) {
        let fixture = Fixture()
        fixture.windows = [fixture.window(title: title, minimized: true, fails: action)]
        #expect(!fixture.navigator.navigate(to: window))
        let actions = ["test.editor", "restore", "activate", "raise"]
        #expect(fixture.events == Array(actions.prefix(through: actions.firstIndex(of: action)!)))
    }

    @Test
    func desktopTargetsTheRecordedDisplayAndOpensItsFolder() {
        let fixture = Fixture()
        fixture.displays = [
            .init(id: "other", visibleFrame: CGRect(x: 0, y: 0, width: 1440, height: 900), mainScreenTop: 900),
            .init(id: "saved", visibleFrame: CGRect(x: -1920, y: -300, width: 1920, height: 1000), mainScreenTop: 900),
        ]
        #expect(fixture.navigator.navigate(to: .desktop(displayID: "saved", displayName: "Renamed display")))
        #expect(fixture.points == [CGPoint(x: -960, y: 700)])
        #expect(fixture.opened == [URL(fileURLWithPath: "/synthetic/Desktop")])
        #expect(fixture.events.isEmpty, "Desktop navigation must not alter other windows")
    }

    @Test
    func missingDisplayOrFailedPointerMovementDoesNotOpenTheWrongDesktop() {
        let fixture = Fixture()
        let location = ContextNoteLocation.desktop(displayID: "saved", displayName: "Screen")
        #expect(!fixture.navigator.navigate(to: location))
        #expect(fixture.points.isEmpty)
        fixture.displays = [.init(id: "saved", visibleFrame: .zero, mainScreenTop: 0)]
        fixture.trusted = false
        #expect(!fixture.navigator.navigate(to: location))
        #expect(fixture.points.isEmpty)
        fixture.trusted = true
        fixture.canMove = false
        #expect(!fixture.navigator.navigate(to: location))
        #expect(fixture.opened.isEmpty)
        fixture.canMove = true
        fixture.canOpen = false
        #expect(!fixture.navigator.navigate(to: location))
    }
}
