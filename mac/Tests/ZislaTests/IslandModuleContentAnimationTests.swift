import AppKit
import SwiftUI
import Testing

@testable import Zisla

@Suite(.serialized)
@MainActor
struct IslandModuleContentAnimationTests {
    @Test
    func newlyMountedPageFadesItsContentAfterTheDeferredPass() async throws {
        let fixture = Fixture(samplesAnimation: true)
        defer { fixture.close() }
        fixture.host.layoutSubtreeIfNeeded()
        #expect(fixture.recorder.constructedIDs.isEmpty,
                "The expensive page must remain deferred during the initial update")
        let placeholder = try fixture.color(x: 28, y: 60)
        #expect(placeholder.redComponent < 0.01)

        await fixture.drain()
        let incoming = try fixture.sampleUntil(x: 28, y: 60) { $0.redComponent > 0.1 }
        #expect(incoming.redComponent < 0.9,
                "The mounted content must pass through an intermediate opacity instead of appearing fully opaque")
        try fixture.expectHeader()
        #expect(fixture.recorder.constructedIDs == [0])
        #expect(!fixture.window.isVisible)
    }

    @Test
    func pageReplacementFadesBothContentLayersWithoutFadingTheHeader() async throws {
        let fixture = Fixture()
        defer { fixture.close() }
        await fixture.drain()
        #expect(try fixture.color(x: 28, y: 60).redComponent > 0.95)
        fixture.input.samplesAnimation = true
        fixture.input.pageID = 1

        await fixture.drain()
        let incoming = try fixture.sampleUntil(x: 104, y: 60) { $0.greenComponent > 0.1 }
        let outgoing = try fixture.color(x: 16, y: 60)
        #expect(incoming.greenComponent < 0.9,
                "The new page's real content must fade in after mounting")
        #expect(outgoing.redComponent > 0.1 && outgoing.redComponent < 0.9,
                "The previously mounted page must fade out while the new content fades in")
        try fixture.expectHeader()
        #expect(fixture.input.pageID == 1,
                "Selection must reach its destination while the animation remains at its sampled midpoint")
        #expect(!fixture.window.isVisible)
    }

    @Test
    func rapidSelectionsRenderTheLatestPageWithoutWaitingForTheFade() async throws {
        let fixture = Fixture()
        defer { fixture.close() }
        await fixture.drain()
        fixture.recorder.constructedIDs.removeAll()
        fixture.input.samplesAnimation = true
        fixture.input.pageID = 1
        fixture.input.pageID = 2
        fixture.input.pageID = 3
        #expect(fixture.input.pageID == 3)

        await fixture.drain()
        _ = try fixture.sampleUntil(x: 104, y: 60) { $0.greenComponent > 0.1 }
        #expect(fixture.recorder.constructedIDs.contains(3) && fixture.recorder.constructedIDs.isDisjoint(with: [1, 2]),
                "Coalesced page commands must construct the latest page without queuing intermediate content")
        try fixture.expectHeader()

        fixture.input.showsPages = false
        await fixture.drain()
        #expect(fixture.pageProbes.isEmpty,
                "Unmounting the page region must remove both active and outgoing content layers")
        #expect(try fixture.color(x: 104, y: 60).greenComponent < 0.01,
                "A cancelled fade must not leave an invisible or stale page layer behind")
        try fixture.expectHeader()
        #expect(!fixture.window.isVisible)
    }

    @Test
    func cancellingAQueuedSelectionPreservesTheCurrentPage() async throws {
        let fixture = Fixture()
        defer { fixture.close() }
        await fixture.drain()
        fixture.recorder.constructedIDs.removeAll()
        fixture.input.samplesAnimation = true
        fixture.input.pageID = 1
        fixture.input.pageID = 0

        await fixture.drain()
        #expect(!fixture.recorder.constructedIDs.contains(1),
                "Opposite commands in one update must not mount the cancelled destination")
        #expect(try fixture.color(x: 28, y: 60).redComponent > 0.95)
        #expect(try fixture.color(x: 104, y: 60).greenComponent < 0.01)
        try fixture.expectHeader()
        #expect(!fixture.window.isVisible)
    }

    @Test
    func removingTheSurfaceBeforeItsDeferredPassCancelsContentConstruction() async throws {
        let fixture = Fixture()
        defer { fixture.close() }
        fixture.host.layoutSubtreeIfNeeded()
        fixture.input.showsPages = false
        fixture.host.layoutSubtreeIfNeeded()

        await fixture.drain()
        #expect(fixture.recorder.constructedIDs.isEmpty,
                "A surface removed before its mounting task resumes must never construct the page")
        #expect(fixture.pageProbes.isEmpty)
        try fixture.expectHeader()
        #expect(!fixture.window.isVisible)
    }

    @Test(arguments: [false, true])
    func defaultDeferredContentAndReduceMotionRemainImmediate(defaultMount: Bool) async throws {
        let fixture = Fixture(samplesAnimation: true, reduceMotion: !defaultMount, defaultMount: defaultMount)
        defer { fixture.close() }
        await fixture.drain()
        #expect(try fixture.color(x: 28, y: 60).redComponent > 0.95,
                "Default deferred content and Reduce Motion must mount without a new fade")
        fixture.input.pageID = 1
        await fixture.drain()
        let incoming = try fixture.sampleUntil(x: 104, y: 60) { $0.greenComponent > 0.1 }
        #expect(incoming.greenComponent > 0.95)
        #expect(try fixture.color(x: 28, y: 60).redComponent < 0.01)
        #expect(fixture.pageProbes.map(\.pageID) == [1])
        try fixture.expectHeader()
        #expect(!fixture.window.isVisible)
    }

    @Test
    func completingTheFadeRemovesItsOutgoingPageLayer() async throws {
        let fixture = Fixture(finishesAnimation: true)
        defer { fixture.close() }
        await fixture.drain()
        fixture.input.samplesAnimation = true
        fixture.input.pageID = 1
        await fixture.drain()
        _ = try fixture.sampleUntil(x: 104, y: 60) { $0.greenComponent > 0.1 }
        try #require(fixture.pageProbes.contains { $0.pageID == 0 })
        _ = try fixture.sampleUntil(x: 104, y: 60) { $0.greenComponent > 0.95 && fixture.pageProbes.map(\.pageID) == [1] }
        #expect(fixture.pageProbes.map(\.pageID) == [1],
                "The finished fade must release its superseded page layer")
        try fixture.expectHeader()
        #expect(!fixture.window.isVisible)
    }

    @Test
    func changingReduceMotionPreservesTheMountedEditorIdentity() async throws {
        let fixture = Fixture()
        defer { fixture.close() }
        await fixture.drain()
        let editor = try #require(fixture.pageProbes.first)
        fixture.input.reduceMotion = true
        await fixture.drain()
        #expect(fixture.pageProbes.first === editor,
                "Changing Reduce Motion must not reconstruct the active page or its editor")
        fixture.input.reduceMotion = false
        await fixture.drain()
        #expect(fixture.pageProbes.first === editor)
        #expect(try fixture.color(x: 28, y: 60).redComponent > 0.95)
        try fixture.expectHeader()
        #expect(!fixture.window.isVisible)
    }

    private final class Input: ObservableObject {
        @Published var pageID = 0
        @Published var showsPages = true
        @Published var samplesAnimation: Bool
        @Published var reduceMotion: Bool
        let finishesAnimation: Bool

        init(samplesAnimation: Bool, reduceMotion: Bool, finishesAnimation: Bool) {
            self.samplesAnimation = samplesAnimation
            self.reduceMotion = reduceMotion
            self.finishesAnimation = finishesAnimation
        }
    }

    @MainActor
    private final class Recorder {
        var constructedIDs: Set<Int> = []

        func content(for pageID: Int) -> some View {
            constructedIDs.insert(pageID)
            return HStack(spacing: 0) {
                if pageID > 0 { Spacer(minLength: 0) }
                Color(.sRGB, red: pageID == 0 ? 1 : 0, green: pageID > 0 ? 1 : 0, blue: 0)
                    .frame(width: 40, height: 48)
                if pageID == 0 { Spacer(minLength: 0) }
            }
            .padding(.horizontal, 8)
            .frame(width: 128, height: 72)
            .background(PageProbe(pageID: pageID))
        }
    }

    private struct PageProbe: NSViewRepresentable {
        let pageID: Int

        func makeNSView(context: Context) -> ProbeView { ProbeView(pageID: pageID) }
        func updateNSView(_ nsView: ProbeView, context: Context) {}

        final class ProbeView: NSView {
            let pageID: Int

            init(pageID: Int) {
                self.pageID = pageID
                super.init(frame: .zero)
            }

            @available(*, unavailable)
            required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
        }
    }

    private struct PageSurface: View {
        @ObservedObject var input: Input
        let recorder: Recorder
        let defaultMount: Bool

        private var pageAnimation: Animation {
            if input.samplesAnimation, input.finishesAnimation { return ZislaMotion.moduleSwitch }
            return Animation(FrozenProgress(progress: input.samplesAnimation ? 0.5 : 1))
        }

        var body: some View {
            HStack(spacing: 0) {
                VStack(spacing: 0) {
                    Color(.sRGB, red: 0, green: 0, blue: 1).frame(height: 24)
                    if input.showsPages {
                        ZStack {
                            let pageID = input.pageID
                            if defaultMount {
                                DeferredMount { recorder.content(for: pageID) }
                                    .id(pageID)
                            } else {
                                DeferredMount(animation: pageAnimation) { recorder.content(for: pageID) }
                                    .id(pageID)
                                    .transition(input.reduceMotion ? .identity : .asymmetric(insertion: .identity, removal: .opacity))
                            }
                        }
                        .frame(width: 128, height: 72)
                        .animation(input.reduceMotion || defaultMount ? nil : pageAnimation, value: input.pageID)
                    } else {
                        Color.clear.frame(width: 128, height: 72)
                    }
                }
                .frame(width: 128, height: 96)
                Color(.sRGB, red: 1, green: 0, blue: 0).frame(width: 4)
                Color(.sRGB, red: 0, green: 1, blue: 0).frame(width: 4)
                Color(.sRGB, red: 0, green: 0, blue: 1).frame(width: 4)
                Color.black.frame(width: 4)
            }
            .frame(width: 144, height: 96)
            .background(.black)
            .environment(\._accessibilityReduceMotion, input.reduceMotion)
            .transaction { transaction in
                if !input.showsPages { transaction.animation = nil }
            }
        }
    }

    private struct FrozenProgress: CustomAnimation {
        var progress: Double = 0.5
        func animate<V: VectorArithmetic>(value: V, time: TimeInterval, context: inout AnimationContext<V>) -> V? {
            progress >= 1 ? nil : value.scaled(by: progress)
        }
    }

    @MainActor
    private final class Fixture {
        let input: Input
        let recorder = Recorder()
        let host: NSHostingView<PageSurface>
        let window: NSWindow

        init(samplesAnimation: Bool = false, reduceMotion: Bool = false, defaultMount: Bool = false, finishesAnimation: Bool = false) {
            _ = NSApplication.shared
            input = Input(samplesAnimation: samplesAnimation, reduceMotion: reduceMotion, finishesAnimation: finishesAnimation)
            host = NSHostingView(rootView: PageSurface(input: input, recorder: recorder, defaultMount: defaultMount))
            host.sizingOptions = []
            window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 144, height: 96),
                              styleMask: .borderless, backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.contentView = host
        }

        var pageProbes: [PageProbe.ProbeView] {
            func descendants(_ view: NSView) -> [PageProbe.ProbeView] {
                (view as? PageProbe.ProbeView).map { [$0] } ?? view.subviews.flatMap(descendants)
            }
            return descendants(host)
        }

        func close() { window.contentView = nil; window.close() }

        func drain() async {
            for _ in 0..<12 {
                host.layoutSubtreeIfNeeded()
                await withCheckedContinuation { continuation in
                    DispatchQueue.main.async { continuation.resume() }
                }
            }
            host.layoutSubtreeIfNeeded()
        }

        func color(x: CGFloat, y: CGFloat) throws -> NSColor {
            host.layoutSubtreeIfNeeded()
            let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
            host.cacheDisplay(in: host.bounds, to: bitmap)
            let scale = CGFloat(bitmap.pixelsWide) / host.bounds.width
            func rawColor(x: CGFloat, y: CGFloat) throws -> NSColor {
                let bitmapY = host.isFlipped ? y : host.bounds.height - y
                return try #require(bitmap.colorAt(x: Int(x * scale), y: Int(bitmapY * scale))?.usingColorSpace(.sRGB))
            }
            let sample = try rawColor(x: x, y: y)
            let red = try rawColor(x: 130, y: 48)
            let green = try rawColor(x: 134, y: 48)
            let blue = try rawColor(x: 138, y: 48)
            let black = try rawColor(x: 142, y: 48)
            func opacity(_ channel: CGFloat, reference: CGFloat, background: CGFloat) throws -> CGFloat {
                try #require(reference - background > 0.1, "The color reference must remain fully visible")
                return min(1, max(0, (channel - background) / (reference - background)))
            }
            // Same-image references remove the display profile from the alpha measurement.
            return try NSColor(srgbRed: opacity(sample.redComponent, reference: red.redComponent, background: black.redComponent),
                               green: opacity(sample.greenComponent, reference: green.greenComponent, background: black.greenComponent),
                               blue: opacity(sample.blueComponent, reference: blue.blueComponent, background: black.blueComponent), alpha: 1)
        }

        func sampleUntil(x: CGFloat, y: CGFloat, predicate: (NSColor) -> Bool) throws -> NSColor {
            let deadline = Date().addingTimeInterval(1)
            var sample = try color(x: x, y: y)
            while !predicate(sample), Date() < deadline {
                RunLoop.main.run(mode: .default, before: min(deadline, Date().addingTimeInterval(1.0 / 120)))
                sample = try color(x: x, y: y)
            }
            try #require(predicate(sample), "The hidden renderer must reach the sampled content frame")
            return sample
        }

        func expectHeader() throws {
            let header = try color(x: 64, y: 12)
            let reference = try color(x: 138, y: 48)
            #expect(header.blueComponent > 0.95
                && abs(header.redComponent - reference.redComponent) < 0.01
                && abs(header.greenComponent - reference.greenComponent) < 0.01
                && abs(header.blueComponent - reference.blueComponent) < 0.01,
                "Page fades must leave the fixed header fully visible")
        }
    }
}
