import CoreGraphics
import Testing

@testable import Zisla

struct WindowPreviewLayoutTests {
    private let screen = CGRect(x: 0, y: 0, width: 1200, height: 800)
    private let panel = CGSize(width: 420, height: 188)

    @Test
    func quartzWindowCoordinatesMatchAccessibilityCoordinates() {
        let quartz = CGRect(x: -800, y: 100, width: 400, height: 250)
        let result = WindowPreviewLayout.appKitFrame(for: quartz, mainScreenTop: 800)

        #expect(result == CGRect(x: -800, y: 450, width: 400, height: 250))
    }

    @Test
    func dockHitTestingUsesQuartzPointerCoordinatesAcrossDisplays() {
        #expect(WindowPreviewLayout.quartzPoint(for: CGPoint(x: 40, y: 50), mainScreenTop: 800)
            == CGPoint(x: 40, y: 750))
        #expect(WindowPreviewLayout.quartzPoint(for: CGPoint(x: -600, y: -100), mainScreenTop: 800)
            == CGPoint(x: -600, y: 900))
    }

    @Test
    func bottomDockPreviewAppearsAboveItsIcon() {
        let icon = CGRect(x: 550, y: 5, width: 48, height: 48)
        let result = WindowPreviewLayout.frame(anchor: icon, size: panel, visibleFrame: screen, isSwitcher: false)

        #expect(result.minY == icon.maxY + 10)
        #expect(result.midX == icon.midX)
    }

    @Test
    func sideDockPreviewAppearsInsideTheDisplay() {
        let icon = CGRect(x: 0, y: 370, width: 48, height: 48)
        let result = WindowPreviewLayout.frame(anchor: icon, size: panel, visibleFrame: screen, isSwitcher: false)

        #expect(result.minX == icon.maxX + 10)
        #expect(result.minY >= screen.minY)
        #expect(result.maxY <= screen.maxY)
    }

    @Test
    func switcherPreviewMovesBelowWhenThereIsNoRoomAbove() {
        let switcher = CGRect(x: 300, y: 620, width: 600, height: 120)
        let result = WindowPreviewLayout.frame(anchor: switcher, size: panel, visibleFrame: screen, isSwitcher: true)

        #expect(result.maxY == switcher.minY - 10)
    }

    @Test
    func previewIsClampedToOffsetScreenBounds() {
        let external = CGRect(x: -1600, y: -200, width: 1600, height: 900)
        let icon = CGRect(x: -20, y: -195, width: 48, height: 48)
        let result = WindowPreviewLayout.frame(anchor: icon, size: panel, visibleFrame: external, isSwitcher: false)

        #expect(result.minX >= external.minX)
        #expect(result.maxX <= external.maxX)
        #expect(result.minY >= external.minY)
        #expect(result.maxY <= external.maxY)
    }
}

struct WindowPreviewWindowMatchTests {
    @Test
    func currentWindowMetadataTracksRenamedAndMovedWindows() throws {
        let info: [[String: Any]] = [[
            kCGWindowNumber as String: 42,
            kCGWindowOwnerPID as String: 123,
            kCGWindowName as String: "Renamed document",
            kCGWindowBounds as String: CGRect(x: 500, y: 100, width: 300, height: 200).dictionaryRepresentation,
        ]]
        let target = try #require(WindowPreviewWindowMatch.currentTarget(
            windowID: 42, processIdentifier: 123, windowInfo: info, mainScreenTop: 800
        ))

        #expect(target.title == "Renamed document")
        #expect(target.frame == CGRect(x: 500, y: 500, width: 300, height: 200))
    }

    @Test(arguments: [[:], [kCGWindowNumber as String: 41, kCGWindowOwnerPID as String: 123],
                      [kCGWindowNumber as String: 42, kCGWindowOwnerPID as String: 999]])
    func closedOrReassignedWindowsAreNotActivationTargets(metadata: [String: Int]) {
        var info: [String: Any] = metadata
        info[kCGWindowBounds as String] = CGRect(x: 0, y: 0, width: 300, height: 200).dictionaryRepresentation
        #expect(WindowPreviewWindowMatch.currentTarget(
            windowID: 42, processIdentifier: 123, windowInfo: [info], mainScreenTop: 800
        ) == nil)
    }

    @Test
    func unavailableWindowGeometryDoesNotSelectAnotherWindow() {
        #expect(WindowPreviewWindowMatch.currentTarget(
            windowID: 42, processIdentifier: 123,
            windowInfo: [[kCGWindowNumber as String: 42, kCGWindowOwnerPID as String: 123]],
            mainScreenTop: 800
        ) == nil)
    }

    @Test
    func sameCenterWindowsResolveBySize() {
        let candidates: [(title: String?, frame: CGRect?)] = [
            ("Document", CGRect(x: 100, y: 100, width: 200, height: 100)),
            ("Document", CGRect(x: 0, y: 0, width: 400, height: 300)),
        ]

        #expect(WindowPreviewWindowMatch.index(
            title: "Document",
            frame: CGRect(x: 0, y: 0, width: 400, height: 300),
            candidates: candidates
        ) == 1)
    }

    @Test
    func indistinguishableWindowsDoNotRaiseAnArbitraryWindow() {
        let frame = CGRect(x: 0, y: 0, width: 300, height: 200)
        let candidates: [(title: String?, frame: CGRect?)] = [
            ("Document", frame),
            ("Document", frame),
        ]

        #expect(WindowPreviewWindowMatch.index(title: "Document", frame: frame, candidates: candidates) == nil)
    }

    @Test
    func missingFramesDoNotResolveDuplicateTitles() {
        let candidates: [(title: String?, frame: CGRect?)] = [("Document", nil), ("Document", nil)]

        #expect(WindowPreviewWindowMatch.index(
            title: "Document",
            frame: CGRect(x: 0, y: 0, width: 300, height: 200),
            candidates: candidates
        ) == nil)
    }

    @Test
    func sameTitleWindowsResolveByPosition() {
        let candidates: [(title: String?, frame: CGRect?)] = [
            ("Document", CGRect(x: 20, y: 20, width: 300, height: 200)),
            ("Document", CGRect(x: 600, y: 20, width: 300, height: 200)),
        ]

        #expect(WindowPreviewWindowMatch.index(
            title: "Document",
            frame: CGRect(x: 590, y: 20, width: 300, height: 200),
            candidates: candidates
        ) == 1)
    }

    @Test
    func unmatchedWindowDoesNotRaiseAnotherWindow() {
        let candidates: [(title: String?, frame: CGRect?)] = [
            ("Other", CGRect(x: 0, y: 0, width: 300, height: 200)),
        ]

        #expect(WindowPreviewWindowMatch.index(
            title: "Document",
            frame: CGRect(x: 0, y: 0, width: 300, height: 200),
            candidates: candidates
        ) == nil)
    }

    @Test
    func untitledWindowMatchesMissingAccessibilityTitle() {
        let candidates: [(title: String?, frame: CGRect?)] = [
            (nil, CGRect(x: 10, y: 10, width: 300, height: 200)),
        ]

        #expect(WindowPreviewWindowMatch.index(
            title: "",
            frame: CGRect(x: 10, y: 10, width: 300, height: 200),
            candidates: candidates
        ) == 0)
    }
}
