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

    @Test(arguments: IslandEdge.allCases, [false, true])
    func aPanelSizeUnionDoesNotMoveTheCollapseAnchor(edge: IslandEdge, sideAnchorsAtTop: Bool) {
        let panel = CGSize(width: 900, height: 600)
        let surface = CGSize(width: 776, height: 340)
        let origin = CGPoint(x: edge == .right ? panel.width - surface.width : edge == .left ? 0 : (panel.width - surface.width) / 2,
            y: edge == .bottom || (edge.isVertical && !sideAnchorsAtTop) ? panel.height - surface.height : 0)
        let anchor = CGRect(x: edge == .right ? 858 : edge == .left ? 0 : 405,
            y: edge == .bottom ? 568 : edge.isVertical && !sideAnchorsAtTop ? 530 : 0,
            width: edge.isVertical ? 32 : 70, height: edge.isVertical ? 70 : 32)
        let expanded = CGRect(x: 50, y: -90, width: panel.width, height: panel.height)
        let collapsed = CGRect(x: expanded.minX + anchor.minX,
            y: expanded.maxY - anchor.maxY, width: anchor.width, height: anchor.height)
        let layout = ScreenOverlayLayout(displayID: 7, screenFrame: expanded, topBarHeight: 24,
            topology: .simulated(frame: collapsed), triggerFrame: collapsed,
            transferDragTriggerFrame: collapsed, expandedFrame: expanded,
            style: .pill, edge: edge, placementMode: .custom)
        let local = IslandRootView.pillCollapsedFrame(for: layout, in: surface, panelSize: panel, direction: .leftToRight)
        #expect(equal(local.offsetBy(dx: origin.x, dy: origin.y), anchor))
    }

    @Test(arguments: [IslandEdge.left, .right], [Double(0.499), 0.5, 0.501])
    @MainActor
    func aShrinkingSideSurfaceKeepsItsRenderedPillAtThePhysicalAnchor(edge: IslandEdge, offset: Double) throws {
        let screen = ScreenSnapshot(displayID: 7,
            frame: CGRect(x: -1600, y: 880, width: 1600, height: 900),
            visibleFrame: CGRect(x: -1600, y: 880, width: 1600, height: 876))
        let layout = ScreenLayoutEngine(configuration: ScreenLayoutConfiguration(
            expandedSize: CGSize(width: 900, height: 600), layoutStyle: .pill,
            placement: IslandPlacement(mode: .custom, edge: edge, offset: offset)
        )).layout(for: screen)
        let panel = layout.expandedFrame.size
        let surface = CGSize(width: 776, height: 340)
        let local = IslandRootView.pillCollapsedFrame(for: layout, in: surface, panelSize: panel, direction: .leftToRight)
        let anchor = layout.collapsedFrameInExpandedTopLeading
        for direction in [LayoutDirection.leftToRight, .rightToLeft] {
            let alignment = IslandRootView.pillAlignment(edge: edge, direction: direction,
                sideAnchorsAtTop: layout.collapsedFrame.midY >= screen.frame.midY)
            let renderer = ImageRenderer(content: IslandSurface(isCollapsed: true,
                collapsedSize: local.size, expandedSize: surface, notchBackground: .black,
                layoutStyle: .pill, collapsedFrame: local, edge: edge
            ) { Color.clear }
                .transaction { $0.disablesAnimations = true }
                .frame(width: surface.width, height: surface.height)
                .frame(width: panel.width, height: panel.height, alignment: alignment)
                .environment(\.layoutDirection, direction))
            renderer.scale = 1
            let bitmap = NSBitmapImageRep(cgImage: try #require(renderer.cgImage))
            #expect(try #require(bitmap.colorAt(x: Int(anchor.midX), y: Int(anchor.midY))).alphaComponent > 0.95,
                    "A smaller side surface must fold back into its screen anchor for either interface direction")
            #expect(try #require(bitmap.colorAt(x: Int(anchor.midX), y: Int(panel.height - anchor.midY))).alphaComponent == 0,
                    "The fold cannot move to the opposite vertical end of the union panel")
        }
    }

    @Test(arguments: IslandLayoutStyle.allCases)
    @MainActor
    func thePhysicalSurfaceKeepsItsContentInTheOriginalInterfaceDirection(style: IslandLayoutStyle) throws {
        let size = CGSize(width: 120, height: 80)
        for direction in [LayoutDirection.leftToRight, .rightToLeft] {
            let renderer = ImageRenderer(content: IslandSurface(expandedSize: size, layoutStyle: style) {
                HStack(spacing: 0) {
                    Color(.sRGB, red: 1, green: 0, blue: 0, opacity: 1).frame(width: 20)
                    Spacer(minLength: 0)
                    Color(.sRGB, red: 0, green: 0, blue: 1, opacity: 1).frame(width: 20)
                }
            }
                .transaction { $0.disablesAnimations = true }
                .frame(width: size.width, height: size.height)
                .environment(\.layoutDirection, direction))
            renderer.scale = 1
            let bitmap = NSBitmapImageRep(cgImage: try #require(renderer.cgImage))
            let firstX = direction == .leftToRight ? 10 : 110
            let lastX = direction == .leftToRight ? 110 : 10
            let first = try #require(bitmap.colorAt(x: firstX, y: 40)?.usingColorSpace(.sRGB))
            let last = try #require(bitmap.colorAt(x: lastX, y: 40)?.usingColorSpace(.sRGB))
            #expect(first.redComponent > 0.95 && first.blueComponent < 0.05,
                    "Fixing physical pill coordinates must preserve the content's leading side")
            #expect(last.blueComponent > 0.95 && last.redComponent < 0.05)
        }
    }

    @Test(arguments: [IslandEdge.left, .right], [Double(0), 0.25, 0.75, 1])
    @MainActor
    func transientContentKeepsTheOriginalPillPositionInEitherInterfaceDirection(edge: IslandEdge, offset: Double) throws {
        let screen = ScreenSnapshot(displayID: 7,
            frame: CGRect(x: -1600, y: 880, width: 1600, height: 900),
            visibleFrame: CGRect(x: -1600, y: 880, width: 1600, height: 876))
        let layout = ScreenLayoutEngine(configuration: ScreenLayoutConfiguration(
            expandedSize: CGSize(width: 900, height: 600), layoutStyle: .pill,
            placement: IslandPlacement(mode: .custom, edge: edge, offset: offset)
        )).layout(for: screen)
        let panel = layout.expandedFrame.size
        let surface = CGSize(width: 776, height: 340)
        let physical = IslandRootView.pillCollapsedFrame(for: layout, in: surface, panelSize: panel, direction: .leftToRight)
        let anchor = layout.collapsedFrameInExpandedTopLeading
        let presentation = CompactPillStatusContent.transientPresentation(message: "جاهز")
        for direction in [LayoutDirection.leftToRight, .rightToLeft] {
            let frame = IslandRootView.pillCollapsedFrame(for: layout, in: surface, panelSize: panel, direction: direction)
            let alignment = IslandRootView.pillAlignment(edge: edge, direction: direction,
                sideAnchorsAtTop: layout.collapsedFrame.midY >= screen.frame.midY)
            let renderer = ImageRenderer(content: IslandSurface(isCollapsed: true,
                collapsedSize: physical.size, expandedSize: surface, notchBackground: .black,
                layoutStyle: .pill, collapsedFrame: physical, edge: edge
            ) {
                CompactPillStatusContent(presentation: presentation, text: presentation.text,
                    edge: edge, visualizationStyle: .waveform, item: nil)
                    .frame(width: frame.width, height: frame.height)
                    .position(x: frame.midX, y: frame.midY)
            }
                .transaction { $0.disablesAnimations = true }
                .frame(width: surface.width, height: surface.height)
                .frame(width: panel.width, height: panel.height, alignment: alignment)
                .environment(\.layoutDirection, direction))
            renderer.scale = 1
            let bitmap = NSBitmapImageRep(cgImage: try #require(renderer.cgImage))
            let colors = try (Int(anchor.minY)..<Int(anchor.maxY)).flatMap { y in
                try (Int(anchor.minX)..<Int(anchor.maxX)).map { x in
                    try #require(bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB))
                }
            }
            #expect(colors.contains { $0.redComponent > 0.5 },
                    "The real transient icon and text must stay visible inside the physical pill in RTL")
        }
    }

    @Test
    @MainActor
    func theNotchKeepsItsExistingRTLRenderingForAnOffsetPetSlot() throws {
        let size = CGSize(width: 240, height: 80)
        let renderer = ImageRenderer(content: IslandSurface(isCollapsed: true,
            collapsedSize: CGSize(width: 60, height: 24), expandedSize: size,
            notchBackground: .black, collapsedCenterOffsetX: 36
        ) { Color.clear }
            .transaction { $0.disablesAnimations = true }
            .frame(width: size.width, height: size.height)
            .environment(\.layoutDirection, .rightToLeft))
        renderer.scale = 1
        let bitmap = NSBitmapImageRep(cgImage: try #require(renderer.cgImage))
        #expect(try #require(bitmap.colorAt(x: 100, y: 12)).alphaComponent > 0.95)
        #expect(try #require(bitmap.colorAt(x: 140, y: 12)).alphaComponent == 0,
                "Physical pill coordinates must not change the existing notch and pet-slot direction")
    }

    @Test(arguments: [false, true])
    func physicalSideAlignmentDoesNotFlipWhenTheInterfaceUsesArabic(sideAnchorsAtTop: Bool) {
        #expect(IslandRootView.pillAlignment(edge: .top, direction: .rightToLeft, sideAnchorsAtTop: sideAnchorsAtTop) == .top)
        #expect(IslandRootView.pillAlignment(edge: .bottom, direction: .rightToLeft, sideAnchorsAtTop: sideAnchorsAtTop) == .bottom)
        #expect(IslandRootView.pillAlignment(edge: .left, direction: .leftToRight, sideAnchorsAtTop: sideAnchorsAtTop)
            == (sideAnchorsAtTop ? .topLeading : .bottomLeading))
        #expect(IslandRootView.pillAlignment(edge: .left, direction: .rightToLeft, sideAnchorsAtTop: sideAnchorsAtTop)
            == (sideAnchorsAtTop ? .topTrailing : .bottomTrailing))
        #expect(IslandRootView.pillAlignment(edge: .right, direction: .leftToRight, sideAnchorsAtTop: sideAnchorsAtTop)
            == (sideAnchorsAtTop ? .topTrailing : .bottomTrailing))
        #expect(IslandRootView.pillAlignment(edge: .right, direction: .rightToLeft, sideAnchorsAtTop: sideAnchorsAtTop)
            == (sideAnchorsAtTop ? .topLeading : .bottomLeading))
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
