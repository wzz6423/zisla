import AppKit
import Foundation
import SwiftUI
import Testing
import ZislaCore
@testable import ZislaKit

@testable import Zisla

struct ShelfModuleLayoutTests {
    @Test
    func shelfContentHeightMatchesItsOuterLayout() {
        let outerLayout = IslandModuleLayout.resolved(for: .shelf, dashboardCardCount: 0)
        let expectedContentHeight = outerLayout.islandSize.height
            - (IslandDashboardLayout.contentTopInset
                + IslandDashboardLayout.mediaHeaderHeight
                + IslandDashboardLayout.toolbarHeight
                + IslandDashboardLayout.toolbarBottomInset)
            - IslandSurfaceGeometry.moduleInset * 2

        #expect(outerLayout == IslandModuleLayout.shelf)
        #expect(outerLayout == IslandModuleLayout.clipboard)
        #expect(IslandModuleLayout.shelfContentHeight == 355)
        #expect(outerLayout.islandSize.height == 508)
        #expect(outerLayout.panelSize.height == 512)
        #expect(expectedContentHeight == IslandModuleLayout.shelfContentHeight)
    }

}

@Suite(.serialized)
@MainActor
struct ShelfItemInteractionTests {
    @Test(arguments: [
        CGPoint(x: 54, y: 14.5),
        CGPoint(x: 43, y: 3.5),
        CGPoint(x: 65, y: 3.5),
        CGPoint(x: 43, y: 25.5),
        CGPoint(x: 65, y: 25.5),
    ])
    func removeTargetIncludesItsEdgesWithoutOpeningTheFile(point: CGPoint) throws {
        let fixture = try Fixture()
        defer { fixture.close() }

        try fixture.click(at: point, count: 1)
        #expect(fixture.removes == 1, "The full 24pt remove target must accept a single click, including its corners")
        #expect(fixture.opens == 0)
        try fixture.click(at: point, count: 2)
        #expect(fixture.opens == 0, "A repeated remove click must never open the file")
    }

    @Test(arguments: [CGPoint(x: 33, y: 37), CGPoint(x: 33, y: 66), CGPoint(x: 33, y: 79)])
    func iconAndFilenameStillOpenOnlyOnDoubleClick(point: CGPoint) throws {
        let fixture = try Fixture()
        defer { fixture.close() }

        try fixture.click(at: point, count: 1)
        #expect(fixture.opens == 0)
        #expect(fixture.removes == 0)
        try fixture.click(at: point, count: 2)
        #expect(fixture.opens == 1)
        #expect(fixture.removes == 0)
    }

    @Test(arguments: [CGPoint(x: 33, y: 37), CGPoint(x: 33, y: 66), CGPoint(x: 33, y: 79)])
    func multiSelectionClicksDoNotOpenTheFileAndPreserveCardSize(point: CGPoint) throws {
        let fixture = try Fixture(selecting: true)
        defer { fixture.close() }
        #expect(fixture.host.bounds.size == CGSize(width: 66, height: 84))
        try fixture.click(at: point, count: 1)
        #expect(fixture.selections == 1)
        #expect(fixture.opens == 0 && fixture.removes == 0)
        try fixture.click(at: point, count: 2)
        #expect(fixture.opens == 0)
    }

    @Test(arguments: [true, false], ["button", "native menu"])
    func removingACardKeepsOtherItemsAndTheirSelectionOrder(targetIsSelected: Bool, entryPoint: String) throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("shelf-card-removal-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: root) }
        let storage = root.appendingPathComponent("shelf.json")
        let shelf = FileShelfStore(storageURL: storage)
        #expect(shelf.add(payloads: [.text("first"), .text("second"), .text("third")]) == 3)
        let items = shelf.items
        let target = items[targetIsSelected ? 0 : 2]
        let remaining = items.filter { $0.id != target.id }
        let bytes = try remaining.map { try Data(contentsOf: $0.url) }
        var selection = FileShelfSelection()
        selection.toggleMode()
        selection.toggle(items[1].id)
        selection.toggle(items[0].id)
        let expectedSelection = selection.ids.filter { $0 != target.id }
        let fixture = try Fixture(selecting: true, item: target,
                                  selectionIndex: selection.ids.firstIndex(of: target.id).map { $0 + 1 })
        defer { fixture.close() }
        var removedItem: FileShelfItem?
        fixture.host.rootView.onRemove = { item in
            removedItem = item
            shelf.remove(id: item.id)
            selection.retainVisible(shelf.items.map(\.id))
        }
        fixture.host.layoutSubtreeIfNeeded()

        if entryPoint == "button" {
            try fixture.click(at: CGPoint(x: 54, y: 14.5), count: 1)
        } else {
            try fixture.removeFromNativeMenu()
        }

        #expect(removedItem == target, "Card removal must pass the displayed item even while another item is selected")
        #expect(shelf.items == remaining)
        #expect(FileShelfStore(storageURL: storage).items == remaining)
        #expect(selection.isSelecting && selection.ids == expectedSelection)
        #expect(!FileManager.default.fileExists(atPath: target.url.path))
        #expect(try remaining.map { try Data(contentsOf: $0.url) } == bytes)
        #expect(fixture.opens == 0 && fixture.selections == 0)
    }

    @MainActor
    private final class Fixture {
        let panel: NSPanel
        let host: NSHostingView<ShelfItemView>
        var opens = 0
        var removes = 0
        var selections = 0

        init(selecting: Bool = false, item: FileShelfItem? = nil, selectionIndex: Int? = nil) throws {
            _ = NSApplication.shared
            panel = NSPanel(
                contentRect: CGRect(x: -100_000, y: -100_000, width: 66, height: 84),
                styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false
            )
            panel.isReleasedWhenClosed = false
            let item = item ?? FileShelfItem(
                id: UUID(), url: URL(fileURLWithPath: "/synthetic-shelf-test/example.txt"),
                addedAt: Date(timeIntervalSince1970: 0), bookmarkData: Data()
            )
            host = NSHostingView(rootView: ShelfItemView(
                item: item, onOpen: {}, onCopy: {}, onSendToQuickNote: {}, onRemove: { _ in },
                selectionIndex: selectionIndex
            ))
            host.rootView.onOpen = { [weak self] in self?.opens += 1 }
            host.rootView.onRemove = { [weak self] _ in self?.removes += 1 }
            if selecting { host.rootView.onSelect = { [weak self] in self?.selections += 1 } }
            host.sizingOptions = []
            panel.contentView = host
            #expect(NSScreen.screens.allSatisfy { !$0.frame.intersects(panel.frame) })
            // SwiftUI installs its event graph only after the window is ordered in.
            panel.orderFrontRegardless()
            host.layoutSubtreeIfNeeded()
            let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
            host.cacheDisplay(in: host.bounds, to: bitmap)
        }

        func click(at pointFromTop: CGPoint, count: Int) throws {
            let point = CGPoint(x: pointFromTop.x, y: host.bounds.height - pointFromTop.y)
            let timestamp = ProcessInfo.processInfo.systemUptime
            for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
                let event = try #require(NSEvent.mouseEvent(
                    with: type, location: point, modifierFlags: [],
                    timestamp: timestamp + (type == .leftMouseUp ? 0.01 : 0),
                    windowNumber: panel.windowNumber, context: nil,
                    eventNumber: 0, clickCount: count, pressure: type == .leftMouseDown ? 1 : 0
                ))
                panel.sendEvent(event)
            }
        }

        func removeFromNativeMenu() throws {
            func draggingView(in view: NSView) -> FileShelfDraggingView? {
                if let dragging = view as? FileShelfDraggingView { return dragging }
                return view.subviews.lazy.compactMap { draggingView(in: $0) }.first
            }
            let dragging = try #require(draggingView(in: host))
            let event = try #require(NSEvent.mouseEvent(with: .rightMouseDown, location: .zero, modifierFlags: [],
                timestamp: 0, windowNumber: panel.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1))
            let menu = try #require(dragging.menu(for: event))
            let index = try #require(menu.items.firstIndex { $0.title == AppLocalization.text("移除") })
            menu.performActionForItem(at: index)
        }

        func close() {
            panel.close()
        }
    }
}
