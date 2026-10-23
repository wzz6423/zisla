import AppKit
import Foundation
import SwiftUI
import Testing
import ZislaCore

@testable import Zisla
@testable import ZislaKit

struct ApplicationVolumeMixerModuleTests {
    @Test(arguments: [false, true], [false, true])
    func moduleUsesOnlyVolumeToggle(pdfEnabled: Bool, volumeEnabled: Bool) {
        let settings = FeatureSettings(pdfToolsEnabled: pdfEnabled, volumeMixerEnabled: volumeEnabled)
        #expect(IslandModule.volumeMixer.isEnabled(in: settings) == volumeEnabled)
        #expect(IslandModule.enabledOrder(settings).contains(.volumeMixer) == volumeEnabled)
        #expect(!IslandModule.configuredOrder(settings).contains { $0.rawValue == "pdf" })
    }

    @Test
    func legacyPDFNavigationPositionResolvesToMixer() {
        var settings = FeatureSettings.default
        settings.moduleOrder = [.mail, .pdf, .dashboard, .volumeMixer]
        #expect(Array(IslandModule.configuredOrder(settings).prefix(3)) == [.mail, .volumeMixer, .dashboard])
        #expect(IslandModule.configuredOrder(settings).filter { $0 == .volumeMixer }.count == 1)
        #expect(!IslandModule.allCases.contains { $0.rawValue == "pdf" })
    }

    @Test
    func mixerSharesTheDownloadsPanelHeight() {
        #expect(IslandModule.volumeMixer.layout == IslandModule.download.layout)
        #expect(IslandModuleLayout.resolved(for: .volumeMixer, dashboardCardCount: 0)
            == IslandModuleLayout.resolved(for: .download, dashboardCardCount: 0))
    }

    @Test(arguments: [false, true], [160.0, 300.0]) @MainActor
    func unavailableMessagesStayCenteredWithoutAPageHeading(isSupported: Bool, height: Double) throws {
        let backend = VolumeLayoutBackend(isSupported: isSupported)
        let service = ApplicationVolumeMixerService(
            monitor: VolumeLayoutMonitor(), backend: backend,
            ownProcessIdentifier: -1, ownBundleIdentifier: "fixture.zisla"
        )
        let renderer = ImageRenderer(content: ApplicationVolumeMixerModuleView(service: service)
            .frame(width: 752, height: height)
            .background(.black)
            .environment(\.colorScheme, .dark))
        renderer.scale = 1
        let bitmap = NSBitmapImageRep(cgImage: try #require(renderer.cgImage))
        var minX = bitmap.pixelsWide
        var maxX = 0
        var minY = bitmap.pixelsHigh
        var maxY = 0
        for y in 0..<bitmap.pixelsHigh {
            for x in 0..<bitmap.pixelsWide {
                let color = try #require(bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB))
                if max(color.redComponent, color.greenComponent, color.blueComponent) > 0.1 {
                    minX = min(minX, x)
                    maxX = max(maxX, x)
                    minY = min(minY, y)
                    maxY = max(maxY, y)
                }
            }
        }
        try #require(maxX > minX && maxY > minY)
        #expect(abs(Double(minX + maxX) / 2 - 376) <= 3,
                "The message must be centered across the entire module width")
        #expect(abs(Double(minY + maxY) / 2 - height / 2) <= 5,
                "The message must be vertically centered without a separate heading")
    }

    @Test(arguments: [false, true]) @MainActor
    func compactListsKeepScrollingAndPreserveVolumeState(hasFailure: Bool) async throws {
        let monitor = VolumeLayoutMonitor()
        monitor.sources = (0..<20).map { index in
            AudioPlaybackSource(
                id: "fixture.\(index)", processIdentifiers: [pid_t(index + 100)],
                bundleIdentifier: "fixture.\(index)", applicationName: "Fixture \(index)",
                iconData: nil, isFrontmost: false
            )
        }
        let backend = VolumeLayoutBackend(isSupported: true)
        let service = ApplicationVolumeMixerService(
            monitor: monitor, backend: backend,
            ownProcessIdentifier: -1, ownBundleIdentifier: "fixture.zisla"
        )
        service.start()
        defer { service.stop() }
        service.setVolume(0.4, for: "fixture.0")
        if hasFailure { backend.onControlFailure?("fixture.0", .permissionDenied) }
        let applications = service.applications
        #expect((service.errorMessage != nil) == hasFailure)

        _ = NSApplication.shared
        let host = NSHostingView(rootView: ApplicationVolumeMixerModuleView(service: service)
            .environment(\.colorScheme, .dark))
        host.sizingOptions = []
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 752, height: 160),
                              styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        defer { window.close() }
        host.layoutSubtreeIfNeeded()
        await withCheckedContinuation { continuation in
            DispatchQueue.main.async { continuation.resume() }
        }
        host.layoutSubtreeIfNeeded()

        func scrollViews(in view: NSView) -> [NSScrollView] {
            (view as? NSScrollView).map { [$0] } ?? view.subviews.flatMap { scrollViews(in: $0) }
        }
        let scrollView = try #require(scrollViews(in: host).first)
        let document = try #require(scrollView.documentView)
        #expect(abs(scrollView.frame.width - 728) <= 1)
        if hasFailure {
            #expect(scrollView.frame.height > 50 && scrollView.frame.height < 136)
        } else {
            #expect(abs(scrollView.frame.height - 136) <= 1)
        }
        #expect(document.bounds.height > scrollView.contentView.bounds.height)
        let initialOffset = scrollView.contentView.bounds.minY
        scrollView.contentView.scroll(to: CGPoint(
            x: 0, y: document.bounds.height - scrollView.contentView.bounds.height
        ))
        scrollView.reflectScrolledClipView(scrollView.contentView)
        #expect(scrollView.contentView.bounds.minY > initialOffset)
        #expect(service.applications == applications)
        #expect(!window.isVisible)
    }

    @Test(arguments: [
        (volume: 1.0, muted: false, controlled: false, error: nil as String?, expected: nil as String?),
        (volume: 0.4, muted: false, controlled: false, error: nil, expected: "等待应用音量控制生效"),
        (volume: 1.0, muted: true, controlled: false, error: nil, expected: "等待应用音量控制生效"),
        (volume: 0.4, muted: false, controlled: false, error: "denied", expected: "音量调整未生效"),
        (volume: 0.4, muted: false, controlled: true, error: "other application failed", expected: nil),
        (volume: 1.0, muted: false, controlled: false, error: "other application failed", expected: nil),
    ])
    func rowsDistinguishDefaultOutputFromPendingAndFailedControl(
        sample: (volume: Double, muted: Bool, controlled: Bool, error: String?, expected: String?)
    ) {
        let application = ApplicationVolumeApplication(
            id: "fixture.player", name: "Fixture Player", bundleIdentifier: "fixture.player",
            iconData: nil, volume: sample.volume, isMuted: sample.muted, isControlled: sample.controlled
        )
        #expect(ApplicationVolumeMixerModuleView.controlStatus(
            for: application, errorMessage: sample.error
        ) == sample.expected)
    }
}

@MainActor
private final class VolumeLayoutMonitor: ApplicationVolumeSourceMonitoring {
    var sources: [AudioPlaybackSource] = []
    var onSourcesChanged: (@MainActor ([AudioPlaybackSource]) -> Void)?
    func start() {}
    func stop() {}
}

@MainActor
private final class VolumeLayoutBackend: ApplicationVolumeMixing {
    let isSupported: Bool
    var onOutputChanged: (@MainActor () -> Void)?
    var onControlFailure: (@MainActor (String, ApplicationVolumeFailure) -> Void)?

    init(isSupported: Bool) { self.isSupported = isSupported }
    func start() {}
    func stop() {}
    func apply(
        _ requests: [ApplicationVolumeRequest], retryingApplication: String?,
        completion: @escaping @MainActor ([String: ApplicationVolumeFailure]) -> Void
    ) {
        completion([:])
    }
}
