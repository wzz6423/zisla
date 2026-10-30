import AVKit
import SwiftUI
import Testing
@testable import Zisla

@MainActor
struct ScreenRecordingPlayerViewTests {
    @Test func nativePlayerMountsAndReplacesMediaWithoutAddingTransportControls() throws {
        let first = AVPlayer()
        let host = NSHostingView(rootView: AnyView(ScreenRecordingPlayerView(player: first).frame(width: 320, height: 180)))
        let window = NSWindow(contentRect: .init(x: 0, y: 0, width: 320, height: 180),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        defer { window.contentView = nil; window.close() }
        host.layoutSubtreeIfNeeded()
        let native = try #require(Self.playerView(in: host), "Playback must mount the native AVKit view")
        #expect(native.player === first)
        #expect(native.controlsStyle == .none)
        #expect(native.videoGravity == .resizeAspect)
        #expect(native.bounds.width == 320 && native.bounds.height == 180)

        let second = AVPlayer()
        host.rootView = AnyView(ScreenRecordingPlayerView(player: second).frame(width: 320, height: 180))
        host.layoutSubtreeIfNeeded()
        #expect(native.player === second)
        #expect(Self.playerView(in: host) === native, "Replacing the player must keep the preview surface stable")

        host.rootView = AnyView(Color.clear.frame(width: 320, height: 180))
        host.layoutSubtreeIfNeeded()
        #expect(native.player == nil, "A removed preview must release its player")
    }

    private static func playerView(in view: NSView) -> AVPlayerView? {
        if let player = view as? AVPlayerView { return player }
        return view.subviews.lazy.compactMap { playerView(in: $0) }.first
    }
}
