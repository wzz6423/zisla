import AppKit
import Testing

@testable import Zisla
@testable import ZislaKit

@MainActor
@Suite(.serialized)
struct ShelfShareRegressionTests {
    @Test
    func sharingAnchorFallsBackToInteractivePanelAfterPointerMoves() {
        let persistent = makePanel(
            frame: CGRect(x: 0, y: 0, width: 320, height: 180),
            ignoresMouseEvents: true
        )
        let interactive = makePanel(
            frame: CGRect(x: 2_000, y: 400, width: 640, height: 360),
            ignoresMouseEvents: false
        )
        defer {
            persistent.panel.orderOut(nil)
            interactive.panel.orderOut(nil)
        }

        let anchor = AppModel.sharingPickerAnchor(
            from: nil,
            at: CGPoint(x: 10_000, y: 10_000),
            windows: [persistent.panel, interactive.panel]
        )

        #expect(anchor === interactive.contentView)
    }

    @Test
    func sharingAnchorUsesPanelOnTriggerScreenWhenMultipleAreInteractive() {
        let first = makePanel(
            frame: CGRect(x: -1_920, y: 0, width: 640, height: 360),
            ignoresMouseEvents: false
        )
        let second = makePanel(
            frame: CGRect(x: 1_440, y: 0, width: 640, height: 360),
            ignoresMouseEvents: false
        )
        defer {
            first.panel.orderOut(nil)
            second.panel.orderOut(nil)
        }

        let anchor = AppModel.sharingPickerAnchor(
            from: nil,
            at: CGPoint(x: 1_600, y: 180),
            windows: [first.panel, second.panel]
        )

        #expect(anchor === second.contentView)
    }

    @Test
    func explicitSharingAnchorTakesPriority() {
        let explicitView = NSView()

        let anchor = AppModel.sharingPickerAnchor(
            from: explicitView,
            at: .zero,
            windows: []
        )

        #expect(anchor === explicitView)
    }

    private func makePanel(
        frame: CGRect,
        ignoresMouseEvents: Bool
    ) -> (panel: IslandPanel, contentView: NSView) {
        let contentView = NSView()
        let panel = IslandPanel(contentView: contentView, frame: frame)
        panel.alphaValue = 0
        panel.ignoresMouseEvents = ignoresMouseEvents
        panel.orderFrontRegardless()
        return (panel, contentView)
    }
}
