import AppKit
import SwiftUI
import Testing
import ZislaCore
import ZislaKit
@testable import Zisla

struct IslandPillAnimationTests {
    @Test(arguments: IslandEdge.allCases, [Double(0), 0.27, 0.5, 1])
    func theRevealAndRecycleUseTheActualPillFrameOnEveryEdge(edge: IslandEdge, offset: Double) {
        let screen = ScreenSnapshot(displayID: 7,
            frame: CGRect(x: -1800, y: -240, width: 1800, height: 1100),
            visibleFrame: CGRect(x: -1800, y: -240, width: 1800, height: 1076))
        let layout = ScreenLayoutEngine(configuration: ScreenLayoutConfiguration(
            expandedSize: CGSize(width: 776, height: 340), layoutStyle: .pill,
            placement: IslandPlacement(mode: .custom, edge: edge, offset: offset),
            compactStatusLength: 70
        )).layout(for: screen)
        let canvas = CGRect(origin: CGPoint(x: 11, y: 23), size: layout.expandedFrame.size)
        let start = layout.collapsedFrameInExpandedTopLeading.offsetBy(dx: canvas.minX, dy: canvas.minY)
        var mask = IslandRevealMask(collapsedSize: layout.collapsedFrame.size,
            expandedSize: canvas.size, isCollapsed: true, layoutStyle: .pill, collapsedFrame: start)
        #expect(equal(mask.path(in: canvas).boundingRect, start))
        mask.animatableData = 0.5
        let middle = mask.path(in: canvas).boundingRect
        #expect(equal(middle, CGRect(x: (start.minX + canvas.minX) / 2,
            y: (start.minY + canvas.minY) / 2,
            width: (start.width + canvas.width) / 2, height: (start.height + canvas.height) / 2)))
        #expect(canvas.contains(middle))
        mask.animatableData = 1
        #expect(equal(mask.path(in: canvas).boundingRect, canvas))
        mask.animatableData = 0
        #expect(equal(mask.path(in: canvas).boundingRect, start),
                "The recycle must return to the same pill instead of the screen top center")
    }

    @Test(arguments: IslandEdge.allCases)
    func aPanelSizeUnionDoesNotMoveTheCollapseAnchor(edge: IslandEdge) {
        let panel = CGSize(width: 900, height: 600)
        let surface = CGSize(width: 776, height: 340)
        let origin = CGPoint(x: edge == .right ? panel.width - surface.width : edge == .left ? 0 : (panel.width - surface.width) / 2,
            y: edge == .bottom ? panel.height - surface.height : edge.isVertical ? (panel.height - surface.height) / 2 : 0)
        let anchor = CGRect(x: edge == .right ? 858 : edge == .left ? 0 : 405,
            y: edge == .bottom ? 568 : edge.isVertical ? 265 : 0,
            width: edge.isVertical ? 32 : 70, height: edge.isVertical ? 70 : 32)
        let expanded = CGRect(x: 50, y: -90, width: panel.width, height: panel.height)
        let collapsed = CGRect(x: expanded.minX + anchor.minX,
            y: expanded.maxY - anchor.maxY, width: anchor.width, height: anchor.height)
        let layout = ScreenOverlayLayout(displayID: 7, screenFrame: expanded, topBarHeight: 24,
            topology: .simulated(frame: collapsed), triggerFrame: collapsed,
            transferDragTriggerFrame: collapsed, expandedFrame: expanded,
            style: .pill, edge: edge, placementMode: .custom)
        let local = IslandRootView.pillCollapsedFrame(for: layout, in: surface, panelSize: panel)
        #expect(equal(local.offsetBy(dx: origin.x, dy: origin.y), anchor))
    }

    @Test
    func physicalSideAlignmentDoesNotFlipWhenTheInterfaceUsesArabic() {
        #expect(IslandRootView.pillAlignment(edge: .top, direction: .rightToLeft) == .top)
        #expect(IslandRootView.pillAlignment(edge: .bottom, direction: .rightToLeft) == .bottom)
        #expect(IslandRootView.pillAlignment(edge: .left, direction: .leftToRight) == .leading)
        #expect(IslandRootView.pillAlignment(edge: .left, direction: .rightToLeft) == .trailing)
        #expect(IslandRootView.pillAlignment(edge: .right, direction: .leftToRight) == .trailing)
        #expect(IslandRootView.pillAlignment(edge: .right, direction: .rightToLeft) == .leading)
    }

    @Test
    func theNotchStillRevealsFromItsOriginalTopCenterAndPetOffset() {
        let canvas = CGRect(x: 0, y: 0, width: 776, height: 340)
        let expanded = canvas.size
        var mask = IslandRevealMask(collapsedSize: CGSize(width: 240, height: 34),
            expandedSize: expanded, isCollapsed: true, collapsedCenterOffsetX: 22)
        #expect(equal(mask.path(in: canvas).boundingRect, CGRect(x: 290, y: 0, width: 240, height: 34)))
        mask.animatableData = 1
        #expect(equal(mask.path(in: canvas).boundingRect, canvas))
    }

    @Test
    func overshootCannotLeaveThePillOrExpandedFrame() {
        let canvas = CGRect(x: 0, y: 0, width: 776, height: 340)
        let start = CGRect(x: 0, y: 140, width: 32, height: 70)
        var mask = IslandRevealMask(collapsedSize: start.size, expandedSize: canvas.size,
            isCollapsed: true, layoutStyle: .pill, collapsedFrame: start)
        mask.animatableData = -0.2
        #expect(equal(mask.path(in: canvas).boundingRect, start))
        mask.animatableData = 1.2
        #expect(equal(mask.path(in: canvas).boundingRect, canvas))
    }

    @Test(arguments: IslandEdge.allCases)
    @MainActor
    func theSurfaceActuallyFoldsIntoTheProvidedPillInsteadOfTheTopCenter(edge: IslandEdge) throws {
        let canvas = CGSize(width: 240, height: 180)
        let size = edge.isVertical ? CGSize(width: 32, height: 70) : CGSize(width: 70, height: 32)
        let anchor = CGRect(x: edge == .right ? canvas.width - size.width : edge == .left ? 0 : 18,
            y: edge == .bottom ? canvas.height - size.height : edge.isVertical ? 23 : 0,
            width: size.width, height: size.height)
        let renderer = ImageRenderer(content: IslandSurface(isCollapsed: true,
            collapsedSize: size, expandedSize: canvas, layoutStyle: .pill, collapsedFrame: anchor, edge: edge
        ) { Color.clear }
            .transaction { $0.disablesAnimations = true }
            .frame(width: canvas.width, height: canvas.height))
        renderer.scale = 1
        let bitmap = NSBitmapImageRep(cgImage: try #require(renderer.cgImage))
        #expect(try #require(bitmap.colorAt(x: Int(anchor.midX), y: Int(anchor.midY))).alphaComponent > 0.95)
        #expect(try #require(bitmap.colorAt(x: 120, y: 90)).alphaComponent == 0)
        #expect(try #require(bitmap.colorAt(x: Int(anchor.minX) + 1, y: Int(anchor.minY) + 1)).alphaComponent < 0.05,
                "The collapsed outline must stay a capsule on every edge")
    }

    @Test
    func fullModulesRetainTheOriginalHorizontalChromeAndContentLayout() throws {
        let source = try String(contentsOf: sourceURL("IslandRootView.swift"), encoding: .utf8)
        let header = try #require(source.range(of: "NowPlayingHeader(model: model)"))
        let rail = try #require(source.range(of: "                            toolRail", range: header.upperBound..<source.endIndex))
        let content = try #require(source.range(of: "                            Group {", range: rail.upperBound..<source.endIndex))
        #expect(header.lowerBound < rail.lowerBound && rail.lowerBound < content.lowerBound)
        #expect(!source.contains("sideChrome") && !source.contains("return .side"))
        let selector = try #require(source.range(of: "private struct ModuleSelector"))
        #expect(source[selector.lowerBound...].contains("HStack(spacing: 2)"))
        let app = try String(contentsOf: sourceURL("ZislaApp.swift"), encoding: .utf8)
        #expect(!app.contains("return .side"))
        let surface = try String(contentsOf: sourceURL("IslandSurface.swift"), encoding: .utf8)
        #expect(surface.contains("if usesCompactGlassSurface, layoutStyle == .pill, edge.isVertical"),
                "Side crowns belong only to compact recording surfaces; full modules keep their top chrome")
        #expect(source.contains("showsCompactTransientNotice && customTransientPresentation == nil"))
        #expect(source.contains(".position(x: frame.midX, y: frame.midY)"),
                "A custom transient message must be placed inside the current pill instead of its former transcript row")
        #expect(app.contains("setTransientNoticePresented(message != nil, message: message)"),
                "Changing the transient text must resize the animation anchor while the message remains visible")
    }

    private func equal(_ lhs: CGRect, _ rhs: CGRect) -> Bool {
        abs(lhs.minX - rhs.minX) < 0.001 && abs(lhs.minY - rhs.minY) < 0.001
            && abs(lhs.width - rhs.width) < 0.001 && abs(lhs.height - rhs.height) < 0.001
    }

    private func sourceURL(_ name: String) -> URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("Sources/Zisla/\(name)")
    }
}
