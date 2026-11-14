import AppKit
import SwiftUI
import Testing
import ZislaCore
@testable import ZislaKit
@testable import Zisla

@MainActor
@Suite(.serialized)
struct CompactPlaybackProgressTests {
    @Test(arguments: [false, true])
    func playbackSamplesReachTheTrackWithoutAnotherAnimation(showsInformation: Bool) async throws {
        let fixture = try StatusIconDestinationIntegrationTests.IconFixture(edge: .top)
        defer { fixture.close(); fixture.media.stop(); fixture.downloads.stop() }
        fixture.settings.settings.sideNoticesEnabled = true
        fixture.settings.settings.islandShowMoreInformation = showsInformation
        fixture.settings.settings.islandAppIconEnabled = false
        fixture.settings.settings.mediaCompactStyle = .compact
        fixture.settings.settings.collapsedProgressGlowEnabled = true
        fixture.settings.settings.mediaVisualizationStyle = .glow
        let date = Date(timeIntervalSince1970: 100)
        fixture.media.publishSnapshot(NowPlayingSnapshot(title: "Track", artist: "Artist", album: nil,
            artworkData: nil, duration: 60, elapsedTime: 15, timestamp: date, isPlaying: true))
        let notice = IslandNotice(id: "media-active-progress-samples", title: "Music")
        fixture.queue.enqueue(notice, expiresAfter: nil)
        let state = SideNoticeDisplayState()
        state.islandEdge = .top
        state.placementMode = .custom
        state.compactWingHeight = 32
        let size = try #require(fixture.presenter.compactFrame(for: fixture.screen, notices: [notice], at: date)).size
        let view = CompactStatusBarView(queue: fixture.queue, displayState: state, media: fixture.media,
            browserDownloads: fixture.downloads, settingsStore: fixture.settings, resultSweep: fixture.sweep,
            pomodoro: PomodoroService(notificationRequestHandler: { _ in }, defaults: fixture.defaults),
            onStatusHidden: {})
        let clock = PlaybackClock(date: date)
        let host = NSHostingView(rootView: PlaybackSurface(clock: clock, status: view, size: size))
        let expected = NSHostingView(rootView: view.statusBarContent(at: date.addingTimeInterval(30))
            .frame(width: size.width, height: size.height))
        host.sizingOptions = []
        expected.sizingOptions = []
        let windows = [host as NSView, expected as NSView].map { content in
            let window = NSWindow(contentRect: CGRect(origin: .zero, size: size),
                styleMask: [.borderless], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.contentView = content
            return window
        }
        defer { windows.forEach { $0.contentView = nil; $0.close() } }
        let initial = try pixels(host)
        let target = try pixels(expected)
        #expect(initial != target, "The fixture must expose the playback track advancing from 25% to 75%")
        clock.date = date.addingTimeInterval(30)
        try await Task.sleep(for: .milliseconds(40))
        let current = try pixels(host)
        let errors = zip(current, target).map { abs(Int($0) - Int($1)) }
        #expect(errors.allSatisfy { $0 <= 3 },
                "Already sampled playback progress must reach its current position without starting another ease-out")
        #expect(windows.allSatisfy { !$0.isVisible })
    }

    private func pixels(_ view: NSView) throws -> [UInt8] {
        view.layoutSubtreeIfNeeded()
        let bitmap = try #require(view.bitmapImageRepForCachingDisplay(in: view.bounds))
        view.cacheDisplay(in: view.bounds, to: bitmap)
        return try (0..<bitmap.pixelsHigh).flatMap { y in
            try (0..<bitmap.pixelsWide).map { x in
                let color = try #require(bitmap.colorAt(x: x, y: y)?.usingColorSpace(.sRGB))
                return UInt8((color.greenComponent * 255).rounded())
            }
        }
    }

    private final class PlaybackClock: ObservableObject {
        @Published var date: Date
        init(date: Date) { self.date = date }
    }

    private struct PlaybackSurface: View {
        @ObservedObject var clock: PlaybackClock
        let status: CompactStatusBarView
        let size: CGSize

        var body: some View {
            status.statusBarContent(at: clock.date).frame(width: size.width, height: size.height)
        }
    }
}
