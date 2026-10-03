import AppKit
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

    @Test
    func missingAmbiguousAndUntrustedWindowsNeverActivateAnArbitraryWindow() {
        let fixture = Fixture()
        for candidates in [nil, [], [fixture.window(title: "Other")], [fixture.window(), fixture.window()], [fixture.window(minimized: nil)]] as [[ContextNoteNavigator.Window]?] {
            fixture.windows = candidates
            fixture.events = []
            #expect(!fixture.navigator.navigate(to: window))
            #expect(fixture.events == ["test.editor"])
        }
        fixture.trusted = false
        fixture.events = []
        #expect(!fixture.navigator.navigate(to: window))
        #expect(fixture.events.isEmpty)
    }

    @Test(arguments: ["restore", "activate", "raise"])
    func failedWindowActionsStopAndReportFailure(action: String) {
        let fixture = Fixture()
        fixture.windows = [fixture.window(minimized: true, fails: action)]
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
