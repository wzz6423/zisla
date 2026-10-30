import AppKit
import SwiftUI
import Testing
import ZislaCore
import ZislaKit

@testable import ZislaKit
@testable import Zisla

struct IslandParticleLogoTests {
    @Test @MainActor
    func particleTargetsFollowTheWebsiteMarkWithoutItsBackground() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let bitmap = try #require(NSBitmapImageRep(data: Data(contentsOf:
            root.appendingPathComponent("web/public/assets/zisla-icon.png"))))
        let particles = IslandParticleLogoRenderer.renderedParticles(
            size: CGSize(width: 580, height: 580), time: 0, reduceMotion: true
        )
        var expected: [CGPoint] = []
        for y in stride(from: 0, to: bitmap.pixelsHigh, by: 16) {
            for x in stride(from: 0, to: bitmap.pixelsWide, by: 16) {
                let color = try #require(bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB))
                if color.alphaComponent > 250.0 / 255,
                   color.redComponent + color.greenComponent + color.blueComponent < 100.0 / 255 {
                    expected.append(CGPoint(x: x - 238, y: y - 201))
                }
            }
        }
        #expect(particles.map(\.center) == expected, "The particles must preserve the website's curved Z and both dots")
    }

    @Test
    func animationIsSubtleAndReduceMotionFreezesTheFrame() {
        let size = CGSize(width: 18, height: 18)
        let still = IslandParticleLogoRenderer.renderedParticles(size: size, time: 0, reduceMotion: true)
        let reducedAtLaterTime = IslandParticleLogoRenderer.renderedParticles(size: size, time: 12, reduceMotion: true)
        let animated = IslandParticleLogoRenderer.renderedParticles(size: size, time: 1.2, reduceMotion: false)
        #expect(still == reducedAtLaterTime)
        #expect(animated != still)
        #expect(zip(still, animated).allSatisfy {
            hypot($0.center.x - $1.center.x, $0.center.y - $1.center.y) < 0.2
        }, "Idle particles must drift subtly without changing the logo silhouette")
    }

    @Test
    func particlesStayInsideSmallAndRectangularCanvasesAndEmptySizesStayEmpty() {
        for size in [CGSize(width: 1, height: 1), CGSize(width: 12, height: 12),
                     CGSize(width: 32, height: 18), CGSize(width: 24, height: 80)] {
            for time in [0.0, 1.2, 12] {
                let particles = IslandParticleLogoRenderer.renderedParticles(size: size, time: time, reduceMotion: false)
                #expect(!particles.isEmpty)
                for particle in particles {
                    #expect(particle.center.x - particle.radius >= 0)
                    #expect(particle.center.y - particle.radius >= 0)
                    #expect(particle.center.x + particle.radius <= size.width)
                    #expect(particle.center.y + particle.radius <= size.height)
                }
            }
        }
        for size in [CGSize.zero, CGSize(width: 0, height: 24), CGSize(width: 24, height: -1)] {
            #expect(IslandParticleLogoRenderer.renderedParticles(size: size, time: 0, reduceMotion: true).isEmpty)
        }
    }

    @Test @MainActor
    func theSmallRenderedMarkKeepsTwoDotsAndASeparateZ() throws {
        let renderer = ImageRenderer(content: IslandParticleLogo.rendering(side: 18, time: 0, reduceMotion: true))
        renderer.scale = 4
        let bitmap = NSBitmapImageRep(cgImage: try #require(renderer.cgImage))
        var dotColumns: Set<Int> = []
        var bodyPixels = 0
        var gapPixels = 0
        for y in 0..<bitmap.pixelsHigh {
            for x in 0..<bitmap.pixelsWide {
                let alpha = try #require(bitmap.colorAt(x: x, y: y)).alphaComponent
                if alpha > 0.05 {
                    if y < 9 { dotColumns.insert(x) }
                    if (9..<11).contains(y) { gapPixels += 1 }
                    if y >= 12 { bodyPixels += 1 }
                }
            }
        }
        #expect(dotColumns.contains { (36..<41).contains($0) })
        #expect(dotColumns.contains { (45..<52).contains($0) })
        #expect(!(41..<45).contains { dotColumns.contains($0) }, "The two brand dots must stay distinct at 18pt")
        #expect(gapPixels == 0, "The dots must remain separated from the Z")
        #expect(bodyPixels > 280, "The curved Z must stay visible at the pill's actual size")
    }

    @Test @MainActor
    func onlyIdleCustomPillsRenderTheCenteredUprightParticleMark() throws {
        let fixture = try Fixture()
        defer { fixture.close() }
        for edge in IslandEdge.allCases {
            fixture.settings.settings.islandPlacement = IslandPlacement(mode: .custom, edge: edge)
            fixture.state.islandEdge = edge
            fixture.state.placementMode = .custom
            let size = edge.isVertical ? CGSize(width: 24, height: 80) : CGSize(width: 80, height: 24)
            let expected = try pixels(IslandParticleLogo(side: 18, time: fixture.date.timeIntervalSinceReferenceDate)
                .frame(width: size.width, height: size.height))
            let idle = try pixels(fixture.view.statusBarContent(at: fixture.date)
                .frame(width: size.width, height: size.height))
            #expect(idle == expected)
            #expect(!fixture.view.pausesCompactTimeline, "Idle logo frames must use the existing animation clock")
            let pixelWidth = Int(size.width * 2)
            let pixelHeight = Int(size.height * 2)
            let lit = idle.indices.filter { idle[$0] > 0 }
            #expect(!lit.isEmpty)
            #expect(lit.allSatisfy {
                $0 % pixelWidth >= 6 && $0 % pixelWidth < pixelWidth - 6
                    && $0 / pixelWidth >= 6 && $0 / pixelWidth < pixelHeight - 6
            }, "The 18pt mark must leave at least 3pt of whitespace on every side")
            let later = try pixels(fixture.view.statusBarContent(at: fixture.date.addingTimeInterval(3))
                .frame(width: size.width, height: size.height))
            #expect(later != idle, "The shared clock must advance the particles rather than freeze the logo")
            fixture.state.compactWingHeight = 12
            let shortSize = edge.isVertical ? CGSize(width: 12, height: 80) : CGSize(width: 80, height: 12)
            let shortMark = try pixels(IslandParticleLogo(side: 12, time: fixture.date.timeIntervalSinceReferenceDate)
                .frame(width: shortSize.width, height: shortSize.height))
            #expect(try pixels(fixture.view.statusBarContent(at: fixture.date)
                .frame(width: shortSize.width, height: shortSize.height)) == shortMark,
                    "A shortened pill must scale the whole brand mark instead of clipping the 18pt silhouette")
            fixture.state.compactWingHeight = 24

            fixture.queue.enqueue(IslandNotice(id: "toolbox-reminder-logo", title: "Reminder", detail: "Fixture"), expiresAfter: nil)
            #expect(try pixels(fixture.view.statusBarContent(at: fixture.date)
                .frame(width: size.width, height: size.height)) != expected, "Active status content must replace the idle mark")
            #expect(fixture.view.pausesCompactTimeline, "Static activity content must not keep the idle logo clock running")
            fixture.state.compactStatusHidden = true
            let hidden = try pixels(fixture.view.statusBarContent(at: fixture.date)
                .frame(width: size.width, height: size.height))
            #expect(hidden == expected, "Hiding an activity must restore the idle mark on \(edge)")
            #expect(!fixture.view.pausesCompactTimeline, "The hidden activity restores the animated idle mark")
            fixture.queue.removeAll()
            fixture.state.compactStatusHidden = false
            fixture.state.placementMode = .camera
            #expect(fixture.view.pausesCompactTimeline)
            #expect(try pixels(fixture.view.statusBarContent(at: fixture.date)
                .frame(width: size.width, height: size.height)).allSatisfy { $0 == 0 }, "Camera-aligned pills must not add a brand mark over the camera")
        }
        fixture.settings.settings.islandLayoutStyle = .notch
        fixture.state.placementMode = .custom
        #expect(try pixels(fixture.view.statusBarContent(at: fixture.date).frame(width: 80, height: 24))
            .allSatisfy { $0 == 0 })
    }

    @Test(arguments: IslandEdge.allCases) @MainActor
    func resultPlaybackReplacesTheIdleLogoEvenWhenStatusWasHidden(edge: IslandEdge) throws {
        let fixture = try Fixture()
        defer { fixture.close() }
        fixture.settings.settings.islandPlacement = IslandPlacement(mode: .custom, edge: edge)
        fixture.state.islandEdge = edge
        fixture.state.placementMode = .custom
        let size = edge.isVertical ? CGSize(width: 24, height: 80) : CGSize(width: 80, height: 24)
        let idle = try pixels(fixture.view.statusBarContent(at: fixture.date).frame(width: size.width, height: size.height))
        fixture.state.compactStatusHidden = true
        let task = AIProgressTask(id: "logo-result", provider: .codex, title: "Result", progress: nil,
                                  status: .succeeded, updatedAt: fixture.date)
        fixture.sweep.receive(previous: .running, task: task, observedSince: fixture.date,
                              settings: fixture.settings.settings)
        let sweep = try #require(fixture.sweep.current)
        let hidden = try pixels(fixture.view.statusBarContent(at: fixture.date).frame(width: size.width, height: size.height))
        #expect(hidden != idle, "Result playback must replace the idle mark")
        #expect(fixture.view.pausesCompactTimeline, "The result owns its own clock while the idle particles are absent")
        fixture.state.compactStatusHidden = false
        #expect(try pixels(fixture.view.statusBarContent(at: fixture.date).frame(width: size.width, height: size.height)) == hidden,
                "The visible result must be identical whether the preceding activity was hidden or shown")
        fixture.sweep.finish(id: sweep.id)
        #expect(try pixels(fixture.view.statusBarContent(at: fixture.date).frame(width: size.width, height: size.height)) == idle)
        #expect(!fixture.view.pausesCompactTimeline)
    }

    @Test(arguments: IslandEdge.allCases) @MainActor
    func recordingOperationsReplaceTheIdleLogoAndKeepTheirAdjacentStatusSlots(edge: IslandEdge) throws {
        let fixture = try Fixture()
        defer { fixture.close() }
        fixture.settings.settings.islandPlacement = IslandPlacement(mode: .custom, edge: edge)
        fixture.state.islandEdge = edge
        fixture.state.placementMode = .custom
        let size = edge.isVertical ? CGSize(width: 24, height: 54) : CGSize(width: 54, height: 24)
        let idle = try pixels(fixture.view.statusBarContent(at: fixture.date).frame(width: size.width, height: size.height))
        var notice = IslandNotice(id: "screen-recording-operation-logo", title: "Output", symbolName: "film")
        var frames: [[UInt8]] = []
        for (kind, progress): (NoticeKind, Double?) in [(.info, nil), (.info, 0.43), (.success, 1), (.error, nil)] {
            fixture.queue.removeAll()
            notice.kind = kind
            notice.progress = progress
            fixture.queue.enqueue(notice, expiresAfter: nil)
            let frame = try pixels(fixture.view.statusBarContent(at: fixture.date).frame(width: size.width, height: size.height))
            #expect(frame != idle, "Recording state must replace the idle mark")
            #expect(fixture.view.pausesCompactTimeline, "Recording status must not keep the idle particle clock running")
            let width = Int(size.width * 2)
            let first = frame.indices.filter { edge.isVertical ? $0 / width < 48 : $0 % width < 48 }
            let gap = frame.indices.filter { edge.isVertical ? (48..<60).contains($0 / width) : (48..<60).contains($0 % width) }
            let second = frame.indices.filter { edge.isVertical ? $0 / width >= 60 : $0 % width >= 60 }
            #expect(first.contains { frame[$0] > 0 })
            #expect(second.contains { frame[$0] > 0 }, "The progress or terminal indicator must remain visible in the second slot")
            #expect(gap.allSatisfy { frame[$0] == 0 }, "The two recording slots must keep their 6pt gap")
            if kind == .info, progress != nil {
                let layout = edge.isVertical ? AnyLayout(VStackLayout(spacing: 6)) : AnyLayout(HStackLayout(spacing: 6))
                let percentage = try pixels(layout {
                    Color.clear.frame(width: 24, height: 24)
                    Text(ScreenRecordingOperationNotice.progressText(for: notice))
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.65)
                        .foregroundStyle(.white)
                        .frame(width: 24, height: 24)
                }
                .frame(width: size.width, height: size.height)
                .clipShape(CompactIslandShape(layoutStyle: .pill)))
                #expect(second.map { frame[$0] } == second.map { percentage[$0] },
                        "The percentage must use the full 24pt slot without notch padding shrinking its text")
            }
            frames.append(frame)
        }
        #expect(frames[1] != frames[2] && frames[2] != frames[3], "Percentage, success, and failure must draw different indicators")
        fixture.queue.removeAll()
        #expect(try pixels(fixture.view.statusBarContent(at: fixture.date).frame(width: size.width, height: size.height)) == idle)
        #expect(!fixture.view.pausesCompactTimeline)
    }

    @Test(arguments: IslandEdge.allCases) @MainActor
    func recordingSlotsKeepThePillMaterialVisibleOutsideTheirSymbols(edge: IslandEdge) throws {
        let fixture = try Fixture()
        defer { fixture.close() }
        fixture.settings.settings.islandPlacement = IslandPlacement(mode: .custom, edge: edge)
        fixture.settings.settings.islandNotchBackground = .liquidGlass
        fixture.state.islandEdge = edge
        fixture.state.placementMode = .custom
        let size = edge.isVertical ? CGSize(width: 24, height: 54) : CGSize(width: 54, height: 24)
        let background = try pixels(IslandCollapsedMaterial(style: .liquidGlass)
            .frame(width: size.width, height: size.height)
            .clipShape(CompactIslandShape(layoutStyle: .pill))
            .background(.white))
        fixture.queue.enqueue(IslandNotice(id: "screen-recording-operation-material", title: "Output", progress: 0.43), expiresAfter: nil)
        let recording = try pixels(fixture.view.statusBarContent(at: fixture.date)
            .frame(width: size.width, height: size.height).background(.white))
        let width = Int(size.width * 2)
        let samples = edge.isVertical ? [44 * width + 24, 104 * width + 24] : [44 * width + 24, 44 * width + 84]
        for sample in samples {
            try #require(background[sample] > 0, "The fixture must expose the backing color to verify slot transparency")
            #expect(recording[sample] == background[sample], "Recording slots must preserve the existing glass crown without adding black wing backgrounds")
        }
    }

    @MainActor
    private func pixels<V: View>(_ view: V) throws -> [UInt8] {
        let renderer = ImageRenderer(content: view.background(.black))
        renderer.scale = 2
        // Gamma encoding can round nested Canvas frames differently by one grayscale value.
        renderer.colorMode = .linear
        let bitmap = NSBitmapImageRep(cgImage: try #require(renderer.cgImage))
        return try (0..<bitmap.pixelsHigh).flatMap { y in
            try (0..<bitmap.pixelsWide).map { x in
                let color = try #require(bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB))
                return UInt8((color.redComponent * 255).rounded())
            }
        }
    }

    @MainActor
    private final class Fixture {
        let suite = "IslandParticleLogoTests.\(UUID().uuidString)"
        let defaults: UserDefaults
        let settings: FeatureSettingsStore
        let queue = SideNoticeQueue()
        let state = SideNoticeDisplayState()
        let media = NowPlayingService(loadLyrics: { _, _, _ in
            LyricsSearchResult(lyrics: nil, artistName: nil)
        })
        let downloads = BrowserDownloadMonitor(directories: [], eventPaths: [])
        let sweep = AIResultSweepController(now: { Date(timeIntervalSince1970: 100) })
        let date = Date(timeIntervalSince1970: 100)

        init() throws {
            defaults = try #require(UserDefaults(suiteName: suite))
            settings = FeatureSettingsStore(defaults: defaults)
            settings.settings.islandLayoutStyle = .pill
            settings.settings.islandNotchBackground = .black
            settings.settings.collapsedProgressGlowEnabled = false
            settings.settings.toolboxReminderEnabled = true
            state.compactWingHeight = 24
        }

        var view: CompactStatusBarView {
            CompactStatusBarView(queue: queue, displayState: state, media: media, browserDownloads: downloads,
                settingsStore: settings, resultSweep: sweep, onStatusHidden: {})
        }

        func close() {
            queue.removeAll()
            sweep.cancel()
            media.stop()
            downloads.stop()
            settings.flushPendingChanges()
            defaults.removePersistentDomain(forName: suite)
        }
    }
}
