import AppKit
import SwiftUI
import Testing
import ZislaCore
import ZislaKit
@testable import Zisla

@MainActor
struct CompactStatusBarAnimationTests {
    @Test(arguments: ["AirPods Pro Left 100% Right 97% Case 98%", "AirPods", "", String(repeating: "天", count: 30)], [false, true])
    func statusTextKeepsItsOwnScrollAnimationInsideTheSurface(text: String, reduceMotion: Bool) async throws {
        let size = CGSize(width: 120, height: 32)
        let frame = CGRect(origin: .zero, size: size)
        func host(progress: Double?, reference: Bool = false) -> NSHostingView<some View> {
            NSHostingView(rootView: CompactStatusBarSurface(frame: frame, panelFrame: frame) { _ in
                let marquee = MarqueeText(text, font: .system(size: 11, weight: .medium), textColor: .white,
                    pointsPerSecond: TransientNoticeMetrics.pointsPerSecond, repeats: false, scrollProgress: progress)
                Group {
                    if reference {
                        if reduceMotion {
                            marquee.marqueeLabel
                                .truncationMode(.tail)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        } else {
                            ViewThatFits(in: .horizontal) {
                                marquee.marqueeLabel.fixedSize(horizontal: true, vertical: false)
                                marquee.marqueeLabel.fixedSize(horizontal: true, vertical: false)
                                    .offset(x: -32)
                                    .frame(width: size.width, alignment: .leading).clipped()
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    } else {
                        marquee
                    }
                }
                .frame(width: size.width, height: size.height)
                .transaction { transaction in
                    if transaction.animation != nil {
                        transaction.animation = Animation(FrozenDistance(distance: 32))
                    }
                }
            }
            .frame(width: size.width, height: size.height)
            .background(.black)
            .environment(\._accessibilityReduceMotion, reduceMotion))
        }
        let actual = host(progress: nil)
        let expected = host(progress: 0, reference: true)
        let head = host(progress: 0)
        let tail = host(progress: 1)
        let windows = [actual, expected, head, tail].map { content in
            let window = NSWindow(contentRect: frame, styleMask: [.borderless], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            content.sizingOptions = []
            window.contentView = content
            return window
        }
        defer { windows.forEach { $0.contentView = nil; $0.close() } }
        func pixels(_ host: NSView) throws -> [UInt8] {
            host.layoutSubtreeIfNeeded()
            let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
            host.cacheDisplay(in: host.bounds, to: bitmap)
            var pixels: [UInt8] = []
            for y in 0..<bitmap.pixelsHigh {
                for x in 0..<bitmap.pixelsWide {
                    let red = try #require(bitmap.colorAt(x: x, y: y)?.usingColorSpace(.sRGB)).redComponent
                    pixels.append(UInt8((red * 255).rounded()))
                }
            }
            return pixels
        }
        var matches = false
        var referenceDifferences = [Int.max, Int.max, Int.max]
        for _ in 0..<20 {
            await withCheckedContinuation { continuation in
                DispatchQueue.main.async { continuation.resume() }
            }
            let rendered = try pixels(actual)
            let reference = try pixels(expected)
            matches = zip(rendered, reference).allSatisfy { abs(Int($0) - Int($1)) <= 3 }
                && (text.isEmpty || reference.contains { $0 > 64 })
            referenceDifferences = try [head, expected, tail].map { sample in
                zip(rendered, try pixels(sample)).filter { abs(Int($0) - Int($1)) > 3 }.count
            }
            if matches { break }
        }
        #expect(matches, "Status text must retain its own animation and honor Reduce Motion; head/half/tail pixel differences: \(referenceDifferences)")
        #expect(windows.allSatisfy { !$0.isVisible })
    }

    @Test(arguments: IslandLayoutStyle.allCases, IslandEdge.allCases)
    func collapsedOutlinePassesThroughAnIntermediateFrameWithoutScalingItsContent(
        style: IslandLayoutStyle, edge: IslandEdge
    ) throws {
        for shrinking in [false, true] {
            let vertical = edge.isVertical
            let short = CGRect(x: vertical ? 10 : 80, y: vertical ? 80 : 10,
                width: vertical ? 32 : 80, height: vertical ? 80 : 32)
            let long = CGRect(x: vertical ? 10 : 20, y: vertical ? 20 : 10,
                width: vertical ? 32 : 200, height: vertical ? 200 : 32)
            let previous = shrinking ? long : short
            let target = shrinking ? short : long
            let panel = CGRect(x: 0, y: 0, width: vertical ? 52 : 240, height: vertical ? 240 : 52)
            let window = NSWindow(contentRect: panel, styleMask: [.borderless], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            defer { window.close() }
            let host = NSHostingView(rootView: SampledSurface(frame: previous, panelFrame: panel, style: style))
            host.sizingOptions = []
            window.contentView = host
            host.layoutSubtreeIfNeeded()
            let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
            host.cacheDisplay(in: host.bounds, to: bitmap)
            host.rootView = SampledSurface(frame: target, panelFrame: panel, style: style)

            let expected = CGRect(x: (short.minX + long.minX) / 2, y: (short.minY + long.minY) / 2,
                width: (short.width + long.width) / 2, height: (short.height + long.height) / 2)
            var bounds = CGRect.null
            let deadline = Date().addingTimeInterval(1)
            repeat {
                RunLoop.main.run(mode: .default, before: min(deadline, Date().addingTimeInterval(1.0 / 120)))
                host.layoutSubtreeIfNeeded()
                host.cacheDisplay(in: host.bounds, to: bitmap)
                bounds = try foregroundBounds(bitmap, panel: panel)
            } while (abs(bounds.width - expected.width) > 1 || abs(bounds.height - expected.height) > 1)
                    && Date() < deadline

            #expect(abs(bounds.width - expected.width) <= 1 && abs(bounds.height - expected.height) <= 1,
                    "The collapsed outline must reach the sampled size instead of snapping to its destination")
            #expect(abs(bounds.midX - expected.midX) <= 1 && abs(bounds.midY - expected.midY) <= 1,
                    "Its physical anchor must stay fixed while the canvas size changes")
            let pixelSize = CGSize(width: panel.width / CGFloat(bitmap.pixelsWide), height: panel.height / CGFloat(bitmap.pixelsHigh))
            var green = 0
            for y in 0..<bitmap.pixelsHigh {
                for x in 0..<bitmap.pixelsWide {
                    let color = try #require(bitmap.colorAt(x: x, y: y)?.usingColorSpace(.sRGB))
                    if color.greenComponent > color.redComponent + 0.3 && color.greenComponent > color.blueComponent + 0.3 { green += 1 }
                }
            }
            #expect(abs(CGFloat(green) * pixelSize.width * pixelSize.height - 64) <= 16,
                    "The status glyph keeps its size while the surrounding outline resizes")
            #expect(!window.isVisible)
        }
    }

    @Test(arguments: [LayoutDirection.leftToRight, .rightToLeft])
    func compactContentKeepsItsPhysicalPositionWhileTheInterfaceDirectionIsPreserved(direction: LayoutDirection) throws {
        let defaultsName = "Zisla.CompactAnimation.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: defaultsName))
        let settings = FeatureSettingsStore(defaults: defaults)
        defer { settings.flushPendingChanges(); defaults.removePersistentDomain(forName: defaultsName) }
        settings.settings.islandLayoutStyle = .pill
        settings.settings.islandNotchBackground = .black
        let state = SideNoticeDisplayState()
        state.placementMode = .custom
        state.compactStatusHidden = true
        state.compactLayout = CompactStatusBarLayout(frame: CGRect(x: 10, y: 10, width: 80, height: 32),
            panelFrame: CGRect(x: 0, y: 0, width: 240, height: 52), animation: nil)
        let view = CompactStatusBarView(queue: SideNoticeQueue(), displayState: state,
            media: NowPlayingService(), browserDownloads: BrowserDownloadMonitor(), settingsStore: settings,
            resultSweep: AIResultSweepController(), pomodoro: PomodoroService(notificationRequestHandler: { _ in }, defaults: defaults), onStatusHidden: {})
        let renderer = ImageRenderer(content: view.statusBarContent(at: Date(timeIntervalSince1970: 100))
            .environment(\.layoutDirection, direction)
            .transaction { $0.disablesAnimations = true }
            .frame(width: 240, height: 52).background(.white))
        renderer.scale = 1
        let bitmap = NSBitmapImageRep(cgImage: try #require(renderer.cgImage))
        #expect(try #require(bitmap.colorAt(x: 30, y: 20)).redComponent < 0.1)
        #expect(try #require(bitmap.colorAt(x: 200, y: 20)).redComponent > 0.9,
                "RTL text cannot mirror the physical screen frame inside the union panel")
    }

    @Test(arguments: [IslandEdge.top, .left])
    func growingThePanelCanvasKeepsTheAnimatedSurfaceAtItsPhysicalAnchor(edge: IslandEdge) throws {
        let vertical = edge.isVertical
        let previous = CGRect(x: 80, y: 80, width: vertical ? 32 : 80, height: vertical ? 80 : 32)
        let target = CGRect(x: vertical ? 80 : 20, y: vertical ? 20 : 80,
            width: vertical ? 32 : 200, height: vertical ? 200 : 32)
        let canvas = previous.union(target)
        let window = NSWindow(contentRect: previous, styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        let host = NSHostingView(rootView: SampledSurface(frame: previous, panelFrame: previous, style: .pill))
        host.sizingOptions = []
        window.contentView = host
        host.layoutSubtreeIfNeeded()
        let initial = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: initial)
        window.setFrame(canvas, display: true)
        host.rootView = SampledSurface(frame: target, panelFrame: canvas, style: .pill)
        let expected = CGRect(x: (previous.minX + target.minX) / 2, y: (previous.minY + target.minY) / 2,
            width: (previous.width + target.width) / 2, height: (previous.height + target.height) / 2)
        let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        var rendered = CGRect.null
        let deadline = Date().addingTimeInterval(1)
        repeat {
            RunLoop.main.run(mode: .default, before: min(deadline, Date().addingTimeInterval(1.0 / 120)))
            host.layoutSubtreeIfNeeded()
            host.cacheDisplay(in: host.bounds, to: bitmap)
            rendered = try foregroundBounds(bitmap, panel: canvas).offsetBy(dx: canvas.minX, dy: canvas.minY)
        } while (abs(rendered.width - expected.width) > 1 || abs(rendered.height - expected.height) > 1)
                && Date() < deadline
        #expect(abs(rendered.midX - expected.midX) <= 1 && abs(rendered.midY - expected.midY) <= 1,
                "The animated frame must not inherit the panel canvas's immediate origin change")
    }

    private func foregroundBounds(_ bitmap: NSBitmapImageRep, panel: CGRect) throws -> CGRect {
        let pixel = CGSize(width: panel.width / CGFloat(bitmap.pixelsWide), height: panel.height / CGFloat(bitmap.pixelsHigh))
        var bounds = CGRect.null
        for y in 0..<bitmap.pixelsHigh {
            for x in 0..<bitmap.pixelsWide {
                let color = try #require(bitmap.colorAt(x: x, y: y)?.usingColorSpace(.sRGB))
                if color.redComponent < 0.5 {
                    bounds = bounds.union(CGRect(x: CGFloat(x) * pixel.width,
                        y: panel.height - CGFloat(y + 1) * pixel.height, width: pixel.width, height: pixel.height))
                }
            }
        }
        return bounds
    }

    private struct FrozenDistance: CustomAnimation {
        let distance: Double

        func animate<V: VectorArithmetic>(value: V, time: TimeInterval, context: inout AnimationContext<V>) -> V? {
            value.scaled(by: min(1, distance / sqrt(value.magnitudeSquared)))
        }
    }

    private struct FrozenProgress: CustomAnimation {
        func animate<V: VectorArithmetic>(value: V, time: TimeInterval, context: inout AnimationContext<V>) -> V? {
            value.scaled(by: 0.5)
        }
    }

    private struct SampledSurface: View {
        let frame: CGRect
        let panelFrame: CGRect
        let style: IslandLayoutStyle

        var body: some View {
            CompactStatusBarSurface(frame: frame, panelFrame: panelFrame) { size in
                Color.black
                    .frame(width: size.width, height: size.height)
                    .overlay { Color(.sRGB, red: 0, green: 1, blue: 0).frame(width: 8, height: 8) }
                    .clipShape(CompactIslandShape(layoutStyle: style))
            }
            .animation(Animation(FrozenProgress()), value: frame)
            .frame(width: panelFrame.width, height: panelFrame.height)
            .background(.white)
        }
    }
}
