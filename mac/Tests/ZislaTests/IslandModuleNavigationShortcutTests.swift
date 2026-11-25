import AppKit
import SwiftUI
import Testing
import WebKit
import ZislaCore

@testable import Zisla
@testable import ZislaKit

@Suite(.serialized)
@MainActor
struct IslandModuleNavigationShortcutTests {
    @Test(arguments: [false, true])
    func commandArrowsNavigatePagesWhileAnEditorHasFocus(webKit: Bool) async throws {
        let settings = FeatureSettings.default
        let order = IslandModule.enabledOrder(settings)
        let first = try #require(order.first)
        let last = try #require(order.last)
        var navigation = IslandModuleNavigation()
        var directions: [IslandModuleNavigation.Direction] = []
        let host = NSHostingView(rootView: ShortcutFixtureView { direction, layoutDirection in
            directions.append(direction)
            let target = navigation.adjacentTarget(
                in: direction, selectedModule: first, settings: settings, isRightToLeft: layoutDirection == .rightToLeft
            )
            _ = navigation.select(target, selectedModule: first, settings: settings, direction: direction)
        })
        let panel = IslandPanel(contentView: host, frame: CGRect(x: 0, y: 0, width: 320, height: 200))
        defer { panel.contentView = nil; panel.close() }
        let nativeEditor = NSTextView(frame: CGRect(x: 0, y: 0, width: 200, height: 100))
        nativeEditor.string = "Fixture note body"
        let editor: NSView
        if webKit {
            let configuration = WKWebViewConfiguration()
            configuration.websiteDataStore = .nonPersistent()
            editor = WKWebView(frame: nativeEditor.frame, configuration: configuration)
        } else {
            editor = nativeEditor
        }
        host.addSubview(editor)
        #expect(panel.makeFirstResponder(editor))
        await layout(host)

        let left = try event(in: panel, keyCode: 123)
        let right = try event(in: panel, keyCode: 124, isRepeat: true)
        #expect(panel.performKeyEquivalent(with: left))
        #expect(navigation.pendingSelection == last)
        #expect(navigation.direction == -1)
        #expect(panel.performKeyEquivalent(with: right))
        #expect(navigation.pendingSelection == first)
        #expect(navigation.direction == 1)
        #expect(panel.performKeyEquivalent(with: right))
        #expect(navigation.pendingSelection == order[1], "Repeated commands must advance from the pending page")
        #expect(panel.performKeyEquivalent(with: right))
        #expect(navigation.pendingSelection == order[2])
        #expect(directions == [.previous, .next, .next, .next])
        #expect(panel.firstResponder === editor)
        #expect(nativeEditor.string == "Fixture note body")
        #expect(!panel.isVisible, "Navigation must not present the fixture window")
    }

    @Test
    func shortcutsKeepOtherModifiersWindowsAndNoteArrowsOutOfPageNavigation() async throws {
        var directions: [IslandModuleNavigation.Direction] = []
        let host = NSHostingView(rootView: ShortcutFixtureView { direction, _ in directions.append(direction) })
        let panel = IslandPanel(contentView: host, frame: CGRect(x: 0, y: 0, width: 320, height: 200))
        defer { panel.contentView = nil; panel.close() }
        await layout(host)

        for modifiers: NSEvent.ModifierFlags in [[], .shift, .option, .control, [.command, .shift],
                                                 [.command, .option], [.command, .control]] {
            for keyCode: UInt16 in [123, 124] {
                _ = panel.performKeyEquivalent(with: try event(in: panel, keyCode: keyCode, modifiers: modifiers))
                #expect(directions.isEmpty, "Modifiers \(modifiers.rawValue) must not navigate pages")
            }
        }
        for keyCode: UInt16 in [125, 126, 12] {
            _ = panel.performKeyEquivalent(with: try event(in: panel, keyCode: keyCode))
            #expect(directions.isEmpty, "Only Command-left/right belong to page navigation")
        }
        let otherPanel = IslandPanel(contentView: NSView(), frame: panel.frame)
        defer { otherPanel.close() }
        _ = panel.performKeyEquivalent(with: try event(in: otherPanel, keyCode: 123))
        #expect(directions.isEmpty, "Events from another window must not navigate this island")
        let capsLock = NSEvent.ModifierFlags(rawValue: 0x8).union([.command, .capsLock, .numericPad, .function])
        #expect(panel.performKeyEquivalent(with: try event(in: panel, keyCode: 124, modifiers: capsLock)))
        #expect(directions == [.next], "Device flags and Caps Lock must not block command arrows")
    }

    @Test
    func replacingAndRemovingThePageSurfaceUpdatesShortcutOwnership() async throws {
        var original: [IslandModuleNavigation.Direction] = []
        var replacement: [IslandModuleNavigation.Direction] = []
        let host = NSHostingView(rootView: ShortcutFixtureView { direction, _ in original.append(direction) })
        let panel = IslandPanel(contentView: host, frame: CGRect(x: 0, y: 0, width: 320, height: 200))
        defer { panel.contentView = nil; panel.close() }
        await layout(host)
        let right = try event(in: panel, keyCode: 124)
        #expect(panel.performKeyEquivalent(with: right))
        #expect(original == [.next])

        host.rootView = ShortcutFixtureView { direction, _ in replacement.append(direction) }
        await layout(host)
        #expect(panel.performKeyEquivalent(with: right))
        #expect(replacement == [.next])
        #expect(original == [.next], "The replaced surface must no longer own navigation")

        host.rootView = ShortcutFixtureView(showsPages: false) { direction, _ in replacement.append(direction) }
        await layout(host)
        _ = panel.performKeyEquivalent(with: right)
        #expect(replacement == [.next], "Collapsed and replacement surfaces must remove page shortcuts")
        panel.contentView = NSView()
        _ = panel.performKeyEquivalent(with: right)
        #expect(replacement == [.next])
        #expect(!panel.isVisible)
    }

    @Test
    func movingTheShortcutSurfaceToAnotherWindowTransfersNavigationOwnership() throws {
        let firstContent = NSView()
        let secondContent = NSView()
        let firstPanel = IslandPanel(contentView: firstContent, frame: CGRect(x: 0, y: 0, width: 320, height: 200))
        let secondPanel = IslandPanel(contentView: secondContent, frame: firstPanel.frame)
        defer { firstPanel.contentView = nil; secondPanel.contentView = nil; firstPanel.close(); secondPanel.close() }
        var directions: [IslandModuleNavigation.Direction] = []
        let shortcuts = IslandModuleNavigationShortcuts.KeyView { directions.append($0) }
        firstContent.addSubview(shortcuts)
        #expect(firstPanel.pageNavigationShortcutView === shortcuts)
        #expect(firstPanel.performKeyEquivalent(with: try event(in: firstPanel, keyCode: 124)))
        #expect(directions == [.next])

        secondContent.addSubview(shortcuts)
        #expect(firstPanel.pageNavigationShortcutView == nil)
        #expect(secondPanel.pageNavigationShortcutView === shortcuts)
        _ = firstPanel.performKeyEquivalent(with: try event(in: firstPanel, keyCode: 124))
        #expect(directions == [.next], "The original window must not retain a transferred page shortcut")
        #expect(secondPanel.performKeyEquivalent(with: try event(in: secondPanel, keyCode: 123)))
        #expect(directions == [.next, .previous])
        _ = secondPanel.performKeyEquivalent(with: try event(in: firstPanel, keyCode: 124))
        #expect(directions == [.next, .previous], "The new window must reject events from the original window")

        shortcuts.removeFromSuperview()
        #expect(secondPanel.pageNavigationShortcutView == nil)
        _ = secondPanel.performKeyEquivalent(with: try event(in: secondPanel, keyCode: 124))
        #expect(directions == [.next, .previous], "Removing the page surface must remove navigation")
    }

    @Test
    func removingAnOutgoingSurfaceKeepsTheReplacementAndReleasesItsRoute() throws {
        let content = NSView()
        let panel = IslandPanel(contentView: content, frame: CGRect(x: 0, y: 0, width: 320, height: 200))
        defer { panel.contentView = nil; panel.close() }
        var outgoing: [IslandModuleNavigation.Direction] = []
        var replacement: [IslandModuleNavigation.Direction] = []
        let oldShortcuts = IslandModuleNavigationShortcuts.KeyView { outgoing.append($0) }
        content.addSubview(oldShortcuts)
        let right = try event(in: panel, keyCode: 124)
        weak var weakNewShortcuts: IslandModuleNavigationShortcuts.KeyView?
        autoreleasepool {
            let newShortcuts = IslandModuleNavigationShortcuts.KeyView { replacement.append($0) }
            weakNewShortcuts = newShortcuts
            content.addSubview(newShortcuts)
            oldShortcuts.removeFromSuperview()
            #expect(panel.pageNavigationShortcutView === newShortcuts,
                    "An outgoing view must not clear the replacement's registration")
            #expect(panel.performKeyEquivalent(with: right))
            #expect(outgoing.isEmpty)
            #expect(replacement == [.next])
            newShortcuts.removeFromSuperview()
        }
        #expect(weakNewShortcuts == nil, "The window must not retain a removed shortcut surface")
        #expect(panel.pageNavigationShortcutView == nil)
        _ = panel.performKeyEquivalent(with: right)
        #expect(replacement == [.next])

        weak var weakUnattachedShortcuts: IslandModuleNavigationShortcuts.KeyView?
        autoreleasepool {
            let unattachedShortcuts = IslandModuleNavigationShortcuts.KeyView { replacement.append($0) }
            weakUnattachedShortcuts = unattachedShortcuts
            panel.pageNavigationShortcutView = unattachedShortcuts
        }
        #expect(weakUnattachedShortcuts == nil, "The window must not own an unattached shortcut surface")
        #expect(panel.pageNavigationShortcutView == nil)
        _ = panel.performKeyEquivalent(with: right)
        #expect(replacement == [.next])
    }

    @Test
    func rightToLeftPagesFollowPhysicalArrowDirectionsAndWrap() async throws {
        var settings = FeatureSettings.default
        settings.fileShelfEnabled = false
        settings.contextNotesEnabled = false
        settings.aiProgressEnabled = false
        settings.downloaderEnabled = false
        settings.calendarEnabled = false
        settings.weatherEnabled = false
        settings.mailEnabled = false
        settings.quickNotesEnabled = false
        settings.volumeMixerEnabled = false
        settings.toolboxEnabled = false
        settings.systemMonitorEnabled = false
        settings.keyboardEnabled = true
        settings.clipboardHistoryEnabled = true
        let order = IslandModule.enabledOrder(settings)
        #expect(order == [.dashboard, .clipboard, .keyboardSound])
        var selectedModule: IslandModule = .clipboard
        var navigation = IslandModuleNavigation()
        var observedLayoutDirections: [LayoutDirection] = []
        let host = NSHostingView(rootView: ShortcutFixtureView { direction, layoutDirection in
            observedLayoutDirections.append(layoutDirection)
            let target = navigation.adjacentTarget(
                in: direction, selectedModule: selectedModule, settings: settings, isRightToLeft: layoutDirection == .rightToLeft
            )
            _ = navigation.select(target, selectedModule: selectedModule, settings: settings, direction: direction)
            if let pending = navigation.takePendingSelection() { selectedModule = pending }
        }.environment(\.layoutDirection, .rightToLeft))
        let panel = IslandPanel(contentView: host, frame: CGRect(x: 0, y: 0, width: 320, height: 200))
        defer { panel.contentView = nil; panel.close() }
        await layout(host)

        let scenarios: [(IslandModule, UInt16, IslandModule, CGFloat)] = [
            (.clipboard, 123, .keyboardSound, -1),
            (.clipboard, 124, .dashboard, 1),
            (.dashboard, 124, .keyboardSound, 1),
            (.keyboardSound, 123, .dashboard, -1),
        ]
        for (start, keyCode, expected, expectedDirection) in scenarios {
            selectedModule = start
            #expect(panel.performKeyEquivalent(with: try event(in: panel, keyCode: keyCode)))
            #expect(selectedModule == expected, "Arrow \(keyCode) must select the physically adjacent page in RTL")
            #expect(navigation.direction == expectedDirection, "The transition must retain the physical arrow direction")
        }
        #expect(observedLayoutDirections == [.rightToLeft, .rightToLeft, .rightToLeft, .rightToLeft])
        #expect(!panel.isVisible)
    }

    private func event(
        in window: NSWindow,
        keyCode: UInt16,
        modifiers: NSEvent.ModifierFlags = [.command, .numericPad, .function],
        isRepeat: Bool = false
    ) throws -> NSEvent {
        let character = switch keyCode {
        case 123: "\u{F702}"
        case 124: "\u{F703}"
        case 125: "\u{F701}"
        case 126: "\u{F700}"
        default: "q"
        }
        return try #require(NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: modifiers, timestamp: 0,
            windowNumber: window.windowNumber, context: nil, characters: character,
            charactersIgnoringModifiers: character, isARepeat: isRepeat, keyCode: keyCode
        ))
    }

    private func layout(_ host: NSView) async {
        for _ in 0..<4 {
            host.layoutSubtreeIfNeeded()
            await withCheckedContinuation { continuation in DispatchQueue.main.async { continuation.resume() } }
        }
        host.layoutSubtreeIfNeeded()
    }
}

private struct ShortcutFixtureView: View {
    @Environment(\.layoutDirection) private var layoutDirection
    var showsPages = true
    let onNavigate: (IslandModuleNavigation.Direction, LayoutDirection) -> Void

    var body: some View {
        Color.clear.background {
            if showsPages {
                IslandModuleNavigationShortcuts { direction in onNavigate(direction, layoutDirection) }
            }
        }
    }
}
