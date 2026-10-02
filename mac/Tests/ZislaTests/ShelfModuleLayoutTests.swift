import AppKit
import Foundation
import SwiftUI
import Testing
import ZislaKit

@testable import Zisla

struct ShelfModuleLayoutTests {
    @Test
    func shelfContentHeightMatchesItsOuterLayout() throws {
        let outerLayout = IslandModuleLayout.resolved(for: .shelf, dashboardCardCount: 0)
        let expectedContentHeight = outerLayout.islandSize.height
            - 121
            - IslandSurfaceGeometry.moduleInset * 2

        #expect(outerLayout == IslandModuleLayout.shelf)
        #expect(outerLayout == IslandModuleLayout.clipboard)
        #expect(IslandModuleLayout.shelfContentHeight == 355)
        #expect(outerLayout.islandSize.height == 500)
        #expect(outerLayout.panelSize.height == 504)
        #expect(expectedContentHeight == IslandModuleLayout.shelfContentHeight)

        let source = try String(contentsOf: Self.shelfSourceURL, encoding: .utf8)
        #expect(source.contains(".frame(height: IslandModuleLayout.shelfContentHeight)"))
        #expect(!source.contains(".frame(height: 320)"))
    }

    private static let shelfSourceURL = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent("Sources/Zisla/ShelfModuleView.swift")
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

    @MainActor
    private final class Fixture {
        let panel: NSPanel
        let host: NSHostingView<ShelfItemView>
        var opens = 0
        var removes = 0

        init() throws {
            _ = NSApplication.shared
            panel = NSPanel(
                contentRect: CGRect(x: -100_000, y: -100_000, width: 66, height: 84),
                styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false
            )
            panel.isReleasedWhenClosed = false
            let item = FileShelfItem(
                id: UUID(), url: URL(fileURLWithPath: "/synthetic-shelf-test/example.txt"),
                addedAt: Date(timeIntervalSince1970: 0), bookmarkData: Data()
            )
            host = NSHostingView(rootView: ShelfItemView(
                item: item, onOpen: {}, onCopy: {}, onSendToQuickNote: {}, onRemove: {}
            ))
            host.rootView.onOpen = { [weak self] in self?.opens += 1 }
            host.rootView.onRemove = { [weak self] in self?.removes += 1 }
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

        func close() {
            panel.close()
        }
    }
}
