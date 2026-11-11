import AppKit
import Foundation
import SwiftUI
import Testing
import ZislaCore
@testable import ZislaKit
@testable import Zisla

struct StatusIconDestinationIntegrationTests {
    @Test(arguments: IslandEdge.allCases) @MainActor
    func pomodoroInformationRowsReceiveMouseEventsAndRestorePassiveIcons(edge: IslandEdge) throws {
        let fixture = try IconFixture(edge: edge)
        defer { fixture.close() }
        fixture.reducesMotion = true
        fixture.settings.settings.sideNoticesEnabled = true
        fixture.settings.settings.islandShowMoreInformation = true
        let icons = [IslandStatusIcon(id: "cpu", content: .metric(.cpu, text: "31%", image: nil,
            style: .detailed), tooltip: "CPU")]
        fixture.presenter.setStatusIcons(icons)
        fixture.presenter.setScreenLocked(false)
        let host = try #require(NSApplication.shared.windows.compactMap {
            $0.contentView as? NSHostingView<AppLanguageEnvironment<CompactStatusBarView>>
        }.first { $0.rootView.content.settingsStore === fixture.settings })
        let state = host.rootView.content.displayState
        #expect(host.window?.ignoresMouseEvents == true)
        fixture.queue.enqueue(IslandNotice(id: "focus-countdown-mouse", title: "Focus", detail: "00:12:30"),
            expiresAfter: nil)
        fixture.presenter.setStatusIcons(icons)
        #expect(state.statusIcons.map(\.id) == ["cpu"])
        #expect(host.window?.ignoresMouseEvents == false,
            "Visible Pomodoro buttons must receive mouse events alongside monitor icons")
        state.compactStatusHidden = true
        fixture.presenter.setStatusIcons(icons)
        #expect(host.window?.ignoresMouseEvents == true)
        state.compactStatusHidden = false
        fixture.presenter.setStatusIcons(icons)
        #expect(host.window?.ignoresMouseEvents == false)
        fixture.settings.settings.sideNoticesEnabled = false
        fixture.presenter.setStatusIcons(icons)
        #expect(host.window?.ignoresMouseEvents == true)
        fixture.settings.settings.sideNoticesEnabled = true
        fixture.presenter.setStatusIcons(icons)
        #expect(host.window?.ignoresMouseEvents == false)
        fixture.queue.removeAll()
        fixture.presenter.setStatusIcons(icons)
        #expect(host.window?.ignoresMouseEvents == true,
            "Removing the countdown must restore passive monitor icons")
    }

    @Test(arguments: IslandEdge.allCases, [false, true]) @MainActor
    func pomodoroProgressRendersInCustomPillsAndInformationRows(edge: IslandEdge, moreInformation: Bool) async throws {
        let fixture = try IconFixture(edge: edge)
        defer { fixture.close() }
        fixture.settings.settings.sideNoticesEnabled = true
        fixture.settings.settings.islandAppIconEnabled = false
        fixture.settings.settings.islandShowMoreInformation = moreInformation
        let date = Date(timeIntervalSince1970: 100)
        let notice = IslandNotice(id: "focus-countdown-progress", title: "Focus", detail: "00:12:30", progress: 0.5)
        fixture.queue.enqueue(notice, expiresAfter: nil)
        let icons = moreInformation ? [IslandStatusIcon(id: "cpu", content: .metric(.cpu, text: "31%",
            image: nil, style: .detailed), tooltip: "CPU")] : []
        let state = SideNoticeDisplayState()
        state.islandEdge = edge
        state.placementMode = .custom
        state.statusIcons = icons
        state.compactWingHeight = 32
        fixture.presenter.setStatusIcons(icons)
        let configuration = fixture.presenter.compactConfiguration(for: [notice], at: date)
        let size = ScreenLayoutEngine(configuration: configuration).layout(for: fixture.screen).collapsedFrame.size
        let service = PomodoroService(notificationRequestHandler: { _ in }, defaults: fixture.defaults)
        let view = CompactStatusBarView(queue: fixture.queue, displayState: state, media: fixture.media,
            browserDownloads: fixture.downloads, settingsStore: fixture.settings, resultSweep: fixture.sweep,
            pomodoro: service, onStatusHidden: {})
        func render(_ progress: Double?, enabled: Bool, hidden: Bool = false) async throws -> NSBitmapImageRep {
            fixture.settings.settings.collapsedProgressGlowEnabled = enabled
            state.compactStatusHidden = hidden
            var current = notice
            current.progress = progress
            fixture.queue.updateIfPresent(current)
            return try await renderOffscreen(view.statusBarContent(at: date)
                .environment(\._accessibilityReduceMotion, true)
                .transaction { $0.disablesAnimations = true }, size: size)
        }
        let baseline = try await render(0.5, enabled: false)
        let half = try await render(0.5, enabled: true)
        let full = try await render(1, enabled: true)
        let empty = try await render(nil, enabled: true)
        func orangePixels(_ bitmap: NSBitmapImageRep, comparedWith baseline: NSBitmapImageRep) throws -> Int {
            var count = 0
            for y in 0..<bitmap.pixelsHigh {
                for x in 0..<bitmap.pixelsWide {
                    let color = try #require(bitmap.colorAt(x: x, y: y)?.usingColorSpace(.sRGB))
                    let original = try #require(baseline.colorAt(x: x, y: y)?.usingColorSpace(.sRGB))
                    if color.redComponent - original.redComponent > 0.04,
                       color.greenComponent - original.greenComponent > 0.01,
                       color.redComponent > color.blueComponent + 0.03 {
                        count += 1
                    }
                }
            }
            return count
        }
        let halfPixels = try orangePixels(half, comparedWith: baseline)
        #expect(halfPixels > 10, "The countdown must paint the shared progress track on \(edge)")
        #expect(try orangePixels(full, comparedWith: baseline) > halfPixels)
        #expect(try orangePixels(empty, comparedWith: baseline) == 0)
        let zero = try await render(0, enabled: true)
        #expect(try orangePixels(zero, comparedWith: baseline) == 0)
        let hiddenBaseline = try await render(1, enabled: false, hidden: true)
        let hidden = try await render(1, enabled: true, hidden: true)
        #expect(try orangePixels(hidden, comparedWith: hiddenBaseline) == 0)
        #expect(fixture.queue.left.isEmpty && fixture.queue.right.count == 1,
            "Painting progress must preserve the countdown notice")
    }

    @Test(arguments: IslandEdge.allCases, [LayoutDirection.leftToRight, .rightToLeft]) @MainActor
    func customUpdatesRenderTheCLIBrandAndUpgradeSymbolWithOrWithoutMonitoring(
        edge: IslandEdge, direction: LayoutDirection
    ) async throws {
        let fixture = try IconFixture(edge: edge)
        defer { fixture.close() }
        fixture.settings.settings.sideNoticesEnabled = true
        fixture.settings.settings.collapsedProgressGlowEnabled = false
        let monitor = NSImage(size: CGSize(width: 24, height: 24), flipped: false) { rect in
            NSColor.red.setFill()
            rect.fill()
            return true
        }
        let icons = [IslandStatusIcon(id: "combined", content: .combined(monitor), tooltip: "Combined")]
        let brands: [(String, AIMascotIdentity)] = [
            ("claude", .claude), ("codex", .codex), ("gemini", .gemini),
            ("qoder", .coder), ("glm", .zcode), ("pi", .pi),
        ]
        let state = SideNoticeDisplayState()
        state.islandEdge = edge
        state.placementMode = .custom
        state.compactWingHeight = 32
        let view = CompactStatusBarView(queue: fixture.queue, displayState: state, media: fixture.media,
            browserDownloads: fixture.downloads, settingsStore: fixture.settings, resultSweep: fixture.sweep,
            pomodoro: PomodoroService(notificationRequestHandler: { _ in }, defaults: fixture.defaults), onStatusHidden: {})
        for (kind, identity) in brands {
            let left = IslandNotice(id: "update-available-cli-\(kind)-left", title: identity.displayName,
                side: .left, style: .status, symbolName: "sparkles")
            let right = IslandNotice(id: "update-available-cli-\(kind)-right", title: "查看更新",
                side: .right, style: .status, symbolName: "arrow.up.circle")
            fixture.queue.enqueue(left, expiresAfter: nil)
            fixture.queue.enqueue(right, expiresAfter: nil)
            for moreInformation in [false, true] {
                fixture.settings.settings.islandShowMoreInformation = moreInformation
                state.statusIcons = moreInformation ? icons : []
                let iconSize = moreInformation ? try #require(IslandStatusIconLayout.size(icons: icons, edge: edge)) : .zero
                let iconLength = edge.isVertical ? iconSize.height : iconSize.width
                let statusLength: CGFloat = moreInformation ? 66 : 78
                let length = iconLength + statusLength
                let size = edge.isVertical ? CGSize(width: 32, height: length) : CGSize(width: length, height: 32)
                let row = edge.isVertical ? AnyLayout(VStackLayout(spacing: 0)) : AnyLayout(HStackLayout(spacing: 0))
                let pair = edge.isVertical ? AnyLayout(VStackLayout(spacing: 6)) : AnyLayout(HStackLayout(spacing: 6))
                let reference = row {
                    if moreInformation {
                        IslandStatusIconStrip(icons: icons, edge: edge, date: .distantPast)
                            .frame(width: iconSize.width, height: iconSize.height)
                    }
                    pair {
                        AIMascotView(identity: identity, size: min(20, 32 * 0.62))
                            .frame(width: edge.isVertical ? 32 : 24, height: edge.isVertical ? 24 : 32)
                        Image(systemName: "arrow.up.circle")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.cyan)
                            .frame(width: edge.isVertical ? 32 : 24, height: edge.isVertical ? 24 : 32)
                    }
                    .padding(edge.isVertical ? .top : .leading, moreInformation ? 0 : 12)
                    .padding(edge.isVertical ? .bottom : .trailing, 12)
                    .frame(width: edge.isVertical ? 32 : statusLength, height: edge.isVertical ? statusLength : 32)
                }
                .frame(width: size.width, height: size.height)
                .background(.black)
                .clipShape(CompactIslandShape(layoutStyle: .pill))
                .environment(\.colorScheme, .dark)
                .environment(\.layoutDirection, direction)
                let expected = try await renderOffscreen(reference, size: size)
                let actual = try await renderOffscreen(view
                    .environment(\.layoutDirection, direction)
                    .environment(\._accessibilityReduceMotion, true), size: size)
                #expect(actual.pixelsWide == expected.pixelsWide && actual.pixelsHigh == expected.pixelsHigh)
                var changed = 0
                var upgradePixels = 0
                let updateStart = edge.isVertical || direction == .leftToRight ? iconLength : 0
                let upgradeStart = edge.isVertical || direction == .leftToRight
                    ? updateStart + (moreInformation ? 0 : 12) + 30 : 12
                let scale = CGFloat(actual.pixelsWide) / size.width
                for y in 0..<actual.pixelsHigh {
                    for x in 0..<actual.pixelsWide {
                        let a = try #require(actual.colorAt(x: x, y: y)?.usingColorSpace(.sRGB))
                        let b = try #require(expected.colorAt(x: x, y: y)?.usingColorSpace(.sRGB))
                        if max(abs(a.redComponent - b.redComponent), abs(a.greenComponent - b.greenComponent),
                               abs(a.blueComponent - b.blueComponent)) > 0.02 { changed += 1 }
                        let axis = CGFloat(edge.isVertical ? y : x) / scale
                        if axis >= upgradeStart && axis < upgradeStart + 24,
                           min(a.redComponent, a.greenComponent, a.blueComponent) > 0.2 {
                            upgradePixels += 1
                        }
                    }
                }
                #expect(changed == 0,
                        "\(kind) must render its logo and the notch's upgrade icon on \(edge), RTL=\(direction == .rightToLeft), monitoring=\(moreInformation); changed pixels: \(changed)")
                #expect(upgradePixels > 5,
                        "The upgrade arrow must remain visible next to \(kind) on \(edge), RTL=\(direction == .rightToLeft), monitoring=\(moreInformation)")
            }
            #expect(fixture.queue.left == [left] && fixture.queue.right == [right],
                    "Rendering an update must not consume or change either notice")
            fixture.queue.removeAll()
        }
    }

    @Test(arguments: IslandEdge.allCases,
          MediaCompactStyle.allCases.flatMap { style in [false, true].map { (style, $0) } }) @MainActor
    func moreInformationKeepsPlaybackProgressAlongTheWholeOutlineDespiteAIAndIcons(
        edge: IslandEdge, playback: (MediaCompactStyle, Bool)
    ) async throws {
        let (style, hasIcons) = playback
        let fixture = try IconFixture(edge: edge)
        defer { fixture.media.publishSnapshot(nil); fixture.close() }
        fixture.settings.settings.sideNoticesEnabled = true
        fixture.settings.settings.islandShowMoreInformation = true
        fixture.settings.settings.islandNotchBackground = .black
        fixture.settings.settings.mediaCompactStyle = style
        fixture.settings.settings.mediaVisualizationStyle = .glow
        let artwork = NSImage(size: CGSize(width: 24, height: 24), flipped: false) { rect in
            NSColor.blue.setFill()
            rect.fill()
            return true
        }
        let date = Date(timeIntervalSince1970: 100)
        let item = NowPlayingSnapshot(title: "Song", artist: "Artist", album: nil,
            artworkData: artwork.tiffRepresentation, duration: 100, elapsedTime: 100,
            timestamp: date, isPlaying: true)
        let notices = [IslandNotice(id: "ai-active-progress", title: "AI"),
                       IslandNotice(id: "media-active-progress", title: "Song", artworkData: item.artworkData)]
        for notice in notices { fixture.queue.enqueue(notice, expiresAfter: nil) }
        fixture.media.publishSnapshot(item)
        let icons = hasIcons ? [IslandStatusIcon(id: "cpu", content: .metric(.cpu, text: "31%",
            image: nil, style: .detailed), tooltip: "CPU")] : []
        let layout = try #require(FloatingIslandInformationLayout(notices: notices, icons: icons,
            settings: fixture.settings.settings, item: item, at: date))
        let state = SideNoticeDisplayState()
        state.islandEdge = edge
        state.placementMode = .custom
        state.statusIcons = icons
        state.compactWingHeight = edge.isVertical ? layout.size.width : layout.size.height
        let view = CompactStatusBarView(queue: fixture.queue, displayState: state, media: fixture.media,
            browserDownloads: fixture.downloads, settingsStore: fixture.settings,
            resultSweep: fixture.sweep, pomodoro: PomodoroService(notificationRequestHandler: { _ in }, defaults: fixture.defaults), onStatusHidden: {})
        #expect(view.selectedCompactStatusPriority == .aiActivity)
        #expect(!view.pausesCompactTimeline,
                "Visible playback progress must advance even when AI owns the normal priority")
        func render(enabled: Bool, elapsed: Double) async throws -> NSBitmapImageRep {
            fixture.settings.settings.collapsedProgressGlowEnabled = enabled
            var snapshot = item
            snapshot.elapsedTime = elapsed
            fixture.media.publishSnapshot(snapshot)
            return try await renderOffscreen(view.statusBarContent(at: date)
                .environment(\._accessibilityReduceMotion, true)
                .transaction { $0.disablesAnimations = true }, size: layout.size)
        }
        let baseline = try await render(enabled: false, elapsed: 100)
        let full = try await render(enabled: true, elapsed: 100)
        let half = try await render(enabled: true, elapsed: 50)
        let width = full.pixelsWide
        let height = full.pixelsHigh
        let scale = CGFloat(width) / layout.size.width
        let margin = Int(4 * scale)
        let middleX = width / 2
        let middleY = height / 2
        #expect(try blueProgress(full, baseline: baseline, x: middleX - 2...middleX + 2, y: 0...margin))
        #expect(try blueProgress(full, baseline: baseline, x: middleX - 2...middleX + 2, y: height - margin...height - 1))
        #expect(try blueProgress(full, baseline: baseline, x: 0...margin, y: middleY - 2...middleY + 2))
        #expect(try blueProgress(full, baseline: baseline, x: width - margin...width - 1, y: middleY - 2...middleY + 2))
        #expect(try blueProgress(half, baseline: baseline, x: width - margin...width - 1, y: middleY - 2...middleY + 2))
        #expect(try !blueProgress(half, baseline: baseline, x: 0...margin, y: middleY - 2...middleY + 2))
        #expect(fixture.queue.left + fixture.queue.right == notices)
    }

    @Test(arguments: ["information-disabled", "notifications-disabled", "status-hidden", "progress-disabled",
                      "paused", "missing-snapshot", "missing-duration", "invalid-duration", "zero-progress", "result-sweep"])
    @MainActor
    func hiddenOrUnavailableInformationPlaybackDoesNotPaintProgress(scenario: String) async throws {
        let fixture = try IconFixture(edge: .top)
        defer { fixture.media.publishSnapshot(nil); fixture.close() }
        fixture.settings.settings.sideNoticesEnabled = true
        fixture.settings.settings.islandShowMoreInformation = true
        fixture.settings.settings.mediaCompactStyle = .compact
        fixture.settings.settings.mediaVisualizationStyle = .glow
        fixture.settings.settings.islandAppIconEnabled = false
        let date = Date(timeIntervalSince1970: 100)
        let sweep = AIResultSweepController(now: { date })
        defer { sweep.cancel() }
        let notices = [IslandNotice(id: "ai-active-hidden", title: "AI"),
                       IslandNotice(id: "media-active-hidden", title: "Song")]
        for notice in notices { fixture.queue.enqueue(notice, expiresAfter: nil) }
        let state = SideNoticeDisplayState()
        state.placementMode = .custom
        state.statusIcons = [IslandStatusIcon(id: "cpu", content: .metric(.cpu, text: "31%",
            image: nil, style: .detailed), tooltip: "CPU")]
        var snapshot = NowPlayingSnapshot(title: "Song", artist: "Artist", album: nil, artworkData: nil,
            duration: 100, elapsedTime: 50, timestamp: date, isPlaying: true)
        switch scenario {
        case "information-disabled": fixture.settings.settings.islandShowMoreInformation = false
        case "notifications-disabled": fixture.settings.settings.sideNoticesEnabled = false
        case "status-hidden": state.compactStatusHidden = true
        case "progress-disabled": fixture.settings.settings.collapsedProgressGlowEnabled = false
        case "paused": snapshot.isPlaying = false
        case "missing-duration": snapshot.duration = nil
        case "invalid-duration": snapshot.duration = .nan
        case "zero-progress": snapshot.elapsedTime = 0
        case "result-sweep":
            sweep.receive(previous: .running,
                task: AIProgressTask(id: "hidden", provider: .codex, title: "AI", progress: nil,
                    status: .succeeded, updatedAt: date),
                observedSince: date, settings: fixture.settings.settings)
            #expect(sweep.current != nil)
        default: break
        }
        fixture.media.publishSnapshot(scenario == "missing-snapshot" ? nil : snapshot)
        let view = CompactStatusBarView(queue: fixture.queue, displayState: state, media: fixture.media,
            browserDownloads: fixture.downloads, settingsStore: fixture.settings,
            resultSweep: sweep, pomodoro: PomodoroService(notificationRequestHandler: { _ in }, defaults: fixture.defaults), onStatusHidden: {})
        #expect(view.pausesCompactTimeline == (scenario != "zero-progress"),
                "A track at zero progress must keep its clock running; hidden or unavailable progress must pause")
        func render(enabled: Bool) async throws -> NSBitmapImageRep {
            fixture.settings.settings.collapsedProgressGlowEnabled = enabled
            return try await renderOffscreen(view.statusBarContent(at: date)
                .environment(\._accessibilityReduceMotion, true)
                .transaction { $0.disablesAnimations = true }, size: CGSize(width: 200, height: 34))
        }
        let baseline = try await render(enabled: false)
        let actual = try await render(enabled: scenario != "progress-disabled")
        var changed = 0
        for y in 0..<actual.pixelsHigh {
            for x in 0..<actual.pixelsWide {
                let color = try #require(actual.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB))
                let previous = try #require(baseline.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB))
                if abs(color.greenComponent - previous.greenComponent) > 0.02 { changed += 1 }
            }
        }
        #expect(changed == 0, "\(scenario) must keep progress hidden without modifying the visible content")
    }

    @Test(arguments: IslandEdge.allCases, MediaCompactStyle.allCases) @MainActor
    func twoRowInformationUsesTheVoiceInputCornerRadius(edge: IslandEdge, style: MediaCompactStyle) async throws {
        let fixture = try IconFixture(edge: edge)
        defer {
            fixture.media.stop()
            fixture.close()
        }
        fixture.settings.settings.sideNoticesEnabled = true
        fixture.settings.settings.islandShowMoreInformation = true
        fixture.settings.settings.mediaCompactStyle = style
        fixture.settings.settings.collapsedProgressGlowEnabled = false
        let date = Date(timeIntervalSince1970: 100)
        let item = NowPlayingSnapshot(title: "Song", artist: "Artist", album: nil, artworkData: nil,
            duration: 60, elapsedTime: 0, timestamp: date, isPlaying: true)
        fixture.media.publishSnapshot(item)
        let icons = [IslandStatusIcon(id: "combined", content: .combined(nil), tooltip: "Combined")]
        let notices = [IslandNotice(id: "ai-active-openai", title: "AI"),
                       IslandNotice(id: "media-active-left", title: "Song")]
        for notice in notices { fixture.queue.enqueue(notice, expiresAfter: nil) }
        let layout = try #require(FloatingIslandInformationLayout(notices: notices, icons: icons,
            settings: fixture.settings.settings, item: item, at: date))
        let state = SideNoticeDisplayState()
        state.islandEdge = edge
        state.placementMode = .custom
        state.statusIcons = icons
        state.compactWingHeight = edge.isVertical ? layout.size.width : layout.size.height
        let view = CompactStatusBarView(queue: fixture.queue, displayState: state, media: fixture.media,
            browserDownloads: fixture.downloads, settingsStore: fixture.settings, resultSweep: fixture.sweep,
            pomodoro: PomodoroService(notificationRequestHandler: { _ in }, defaults: fixture.defaults), onStatusHidden: {})
        let bitmap = try await renderOffscreen(view.statusBarContent(at: date)
            .environment(\._accessibilityReduceMotion, true).background(.white), size: layout.size)
        let radius = style == .detailed ? VoiceRecordingIslandGeometry.bottomCornerRadius
            : min(layout.size.width, layout.size.height) / 2
        let expected = RoundedRectangle(cornerRadius: radius, style: style == .detailed ? .continuous : .circular)
        let rect = CGRect(origin: .zero, size: layout.size)
        let inside = expected.inset(by: 1).path(in: rect)
        let outside = expected.inset(by: -1).path(in: rect)
        let scale = CGFloat(bitmap.pixelsWide) / layout.size.width
        var probes = 0
        for x in [CGFloat(2.5), 4.5] {
            for y in stride(from: CGFloat(2.5), through: 29.5, by: 3) {
                let point = CGPoint(x: x, y: y)
                let color = try #require(bitmap.colorAt(x: Int(x * scale), y: Int(y * scale))?.usingColorSpace(.deviceRGB))
                if inside.contains(point) {
                    #expect(max(color.redComponent, color.greenComponent, color.blueComponent) < 0.15,
                            "The two-row shell must fill the tighter voice-input contour")
                    probes += 1
                } else if !outside.contains(point) {
                    #expect(min(color.redComponent, color.greenComponent, color.blueComponent) > 0.85,
                            "The shell must leave the area outside its selected contour clear")
                    probes += 1
                }
            }
        }
        #expect(probes > 10)
        if #available(macOS 26.0, *) {
            fixture.settings.settings.islandNotchBackground = .liquidGlass
            var nativeRadii: [CGFloat] = []
            _ = try await renderOffscreen(view.statusBarContent(at: date)
                .environment(\._accessibilityReduceTransparency, false), size: layout.size) { host in
                    var pending = [host]
                    while let current = pending.popLast() {
                        if let glass = current as? NSGlassEffectView { nativeRadii.append(glass.cornerRadius) }
                        pending.append(contentsOf: current.subviews)
                    }
                }
            #expect(nativeRadii.contains(style == .detailed ? VoiceRecordingIslandGeometry.bottomCornerRadius : 16))
        }
        if style == .detailed {
            fixture.settings.settings.islandNotchBackground = .black
            fixture.settings.settings.collapsedProgressGlowEnabled = true
            fixture.settings.settings.compactStatusPriority = CompactStatusPriority.normalized([.media])
            state.statusIcons = []
            let completed = NowPlayingSnapshot(title: "Song", artist: "Artist", album: nil, artworkData: nil,
                duration: 60, elapsedTime: 60, timestamp: date, isPlaying: true)
            fixture.media.publishSnapshot(completed)
            let progressLayout = try #require(FloatingIslandInformationLayout(notices: notices, icons: [],
                settings: fixture.settings.settings, item: completed, at: date))
            let actual = try await renderOffscreen(view.statusBarContent(at: date)
                .environment(\._accessibilityReduceMotion, true)
                .environment(\._accessibilityReduceTransparency, true), size: progressLayout.size)
            let reference = CompactIslandShape(layoutStyle: .pill,
                pillCornerRadius: VoiceRecordingIslandGeometry.bottomCornerRadius)
            let expected = try await renderOffscreen(reference.inset(by: CollapsedProgress.outlineInset)
                .trim(from: 0, to: 1)
                .stroke(MediaWaveformView.tintColor(for: nil), style: StrokeStyle(lineWidth: 1, lineCap: .round, lineJoin: .round))
                .clipShape(reference).environment(\.colorScheme, .dark), size: progressLayout.size)
            let scale = CGFloat(actual.pixelsWide) / progressLayout.size.width
            var mismatches: [String] = []
            var progressPixels = 0
            // The vertical provider icon starts 4pt from the edge, so sample only the perimeter before it.
            for y in 0..<Int(32 * scale) {
                for x in 0..<Int(3 * scale) {
                    let actualColor = try #require(actual.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB))
                    let expectedColor = try #require(expected.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB))
                    if abs(actualColor.greenComponent - expectedColor.greenComponent) > 0.05 {
                        mismatches.append("\(x),\(y): \(actualColor.greenComponent) vs \(expectedColor.greenComponent)")
                    }
                    if expectedColor.greenComponent > 0.1 { progressPixels += 1 }
                }
            }
            #expect(progressPixels > 0)
            #expect(mismatches.isEmpty,
                    "Playback progress must follow the same tighter corners as the two-row surface: \(mismatches)")
        }
    }

    @Test(arguments: IslandEdge.allCases, MediaCompactStyle.allCases.flatMap { style in [false, true].map { (style, $0) } }) @MainActor
    func theCompactSurfaceRendersMonitorAndPlaybackTogetherWithoutPausingLyrics(
        edge: IslandEdge, playback: (MediaCompactStyle, Bool)
    ) async throws {
        let (style, crowded) = playback
        let fixture = try IconFixture(edge: edge)
        defer { fixture.close() }
        fixture.settings.settings.sideNoticesEnabled = true
        fixture.settings.settings.islandShowMoreInformation = true
        fixture.settings.settings.mediaCompactStyle = style
        let artwork = NSImage(size: CGSize(width: 24, height: 24), flipped: false) { rect in
            NSColor.blue.setFill()
            rect.fill()
            return true
        }
        let monitor = NSImage(size: CGSize(width: 24, height: 24), flipped: false) { rect in
            NSColor.red.setFill()
            rect.fill()
            return true
        }
        let filler = NSImage(size: CGSize(width: 24, height: 24), flipped: false) { rect in
            NSColor.white.setFill()
            rect.fill()
            return true
        }
        let icons = (0..<(crowded ? 12 : 1)).map {
            IslandStatusIcon(id: "combined-\($0)", content: .combined($0 == 0 ? monitor : filler), tooltip: "Combined")
        }
        let date = Date(timeIntervalSince1970: 100)
        let item = NowPlayingSnapshot(title: "Song", artist: "Artist", album: nil,
            artworkData: artwork.tiffRepresentation, duration: 60, elapsedTime: 0,
            timestamp: date, isPlaying: true,
            lyrics: SyncedLyrics(lines: [.init(time: 0,
                text: crowded ? "" : "A long lyric line that needs the full music row width")]))
        fixture.media.publishSnapshot(item)
        let notices = [IslandNotice(id: "ai-active-openai", title: "AI"),
                       IslandNotice(id: "media-active-left", title: "Song", artworkData: item.artworkData),
                       IslandNotice(id: "toolbox-reminder-awake", title: "Awake", detail: "30:00")]
        for notice in notices { fixture.queue.enqueue(notice, expiresAfter: nil) }
        let layout = try #require(FloatingIslandInformationLayout(notices: notices, icons: icons,
            settings: fixture.settings.settings, item: item, at: date))
        if crowded { #expect(layout.primaryLength > ScreenLayoutConfiguration.quickActionRowWidth) }
        let state = SideNoticeDisplayState()
        state.islandEdge = edge
        state.placementMode = .custom
        state.statusIcons = icons
        state.compactWingHeight = edge.isVertical ? layout.size.width : layout.size.height
        var reportedLengths: [CGFloat] = []
        let view = CompactStatusBarView(queue: fixture.queue, displayState: state, media: fixture.media,
            browserDownloads: fixture.downloads, settingsStore: fixture.settings, resultSweep: fixture.sweep,
            pomodoro: PomodoroService(notificationRequestHandler: { _ in }, defaults: fixture.defaults), onStatusHidden: {}, onCompactLengthChanged: { reportedLengths.append($0) })
        #expect(!view.pausesCompactTimeline,
                "Visible playback progress and detailed lyrics must keep advancing while AI wins the normal priority")
        let bitmap = try await renderOffscreen(view.statusBarContent(at: date)
            .environment(\._accessibilityReduceMotion, true)
            .environment(\.layoutDirection, .leftToRight), size: layout.size)
        #expect(reportedLengths.last == (edge.isVertical ? layout.size.height : layout.size.width),
                "The surface must report its measured length to keep the panel geometry synchronized")
        var monitorPixels = 0
        var artworkPixels = 0
        var statusPixels = 0
        var monitorBounds = CGRect.null
        var artworkBounds = CGRect.null
        for y in 0..<bitmap.pixelsHigh {
            for x in 0..<bitmap.pixelsWide {
                let color = try #require(bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB))
                let point = CGRect(x: x, y: y, width: 1, height: 1)
                if color.redComponent > 0.8 && color.blueComponent < 0.2 {
                    monitorPixels += 1
                    monitorBounds = monitorBounds.union(point)
                }
                if color.blueComponent > 0.8 && color.redComponent < 0.2 {
                    artworkPixels += 1
                    artworkBounds = artworkBounds.union(point)
                }
                if min(color.redComponent, color.greenComponent, color.blueComponent) > 0.7 { statusPixels += 1 }
            }
        }
        #expect(monitorPixels > 100, "The monitor icon must stay visible while AI and music are active")
        #expect(artworkPixels > 100, "The playback row must render alongside the monitor icon")
        #expect(statusPixels > 10, "The task count and awake status must render alongside both colored icons")
        let length = edge.isVertical ? layout.size.height : layout.size.width
        let pixelScale = CGFloat(edge.isVertical ? bitmap.pixelsHigh : bitmap.pixelsWide) / length
        let rowScale = min(1, length / layout.primaryLength)
        let monitorStart = edge.isVertical ? monitorBounds.minY : monitorBounds.minX
        #expect(abs(monitorStart / pixelScale - 8 * rowScale) <= 1,
                "The monitor row must begin at its leading inset even when the music row is wider or the row is scaled")
        if style == .detailed {
            let artworkStart = edge.isVertical ? artworkBounds.minY : artworkBounds.minX
            #expect(abs(artworkStart / pixelScale - CompactPillStatusPresentation.trailingInset) <= 1,
                    "Short detailed music must begin at its leading inset instead of centering under the monitor row")
            #expect(edge.isVertical ? artworkBounds.minX > monitorBounds.maxX : artworkBounds.minY > monitorBounds.maxY,
                    "Detailed playback must occupy its own row or column")
        } else {
            #expect(abs(edge.isVertical ? artworkBounds.midX - monitorBounds.midX : artworkBounds.midY - monitorBounds.midY) < 2,
                    "Compact playback must share the monitor row or column")
        }
        fixture.media.stop()
    }

    @Test @MainActor
    func moreInformationYieldsToVoiceMessagesAndResultSweeps() throws {
        let fixture = try IconFixture(edge: .top)
        defer { fixture.close() }
        fixture.settings.settings.sideNoticesEnabled = true
        fixture.settings.settings.islandShowMoreInformation = true
        fixture.presenter.setStatusIcons([IslandStatusIcon(id: "cpu", content: .metric(.cpu,
            text: "20%", image: nil, style: .detailed), tooltip: "CPU")])
        let notices = [IslandNotice(id: "ai-active-openai", title: "AI")]
        let combined = fixture.presenter.compactConfiguration(for: notices, at: .distantPast)
        #expect(combined.statusIconSize != nil)
        fixture.presenter.setVoiceRecording(true)
        #expect(fixture.presenter.compactConfiguration(for: notices, at: .distantPast).statusIconSize == nil)
        fixture.presenter.setVoiceRecording(false)
        fixture.presenter.setTransientNoticePresented(true)
        #expect(fixture.presenter.compactConfiguration(for: notices, at: .distantPast).statusIconSize == nil)
        fixture.presenter.setTransientNoticePresented(false)
        #expect(fixture.presenter.compactConfiguration(for: notices, at: .distantPast) == combined)
        fixture.sweep.receive(previous: .running,
            task: AIProgressTask(id: "information", provider: .codex, title: "Test", progress: nil,
                status: .succeeded, updatedAt: .distantPast),
            observedSince: .distantFuture, settings: fixture.settings.settings)
        #expect(fixture.sweep.current != nil)
        #expect(fixture.presenter.compactConfiguration(for: notices, at: .distantPast).statusIconSize == nil)
        fixture.sweep.cancel()
        #expect(fixture.presenter.compactConfiguration(for: notices, at: .distantPast) == combined)
    }

    @Test(arguments: IslandEdge.allCases) @MainActor
    func defaultMoreInformationKeepsMonitorAIPlaybackAndAwakeStatusTogether(edge: IslandEdge) throws {
        let fixture = try IconFixture(edge: edge)
        defer { fixture.close() }
        fixture.settings.settings.sideNoticesEnabled = true
        fixture.settings.settings.mediaCompactStyle = .detailed
        var payload = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(fixture.settings.settings)) as? [String: Any])
        payload.removeValue(forKey: "islandShowMoreInformation")
        fixture.settings.settings = try JSONDecoder().decode(FeatureSettings.self,
            from: JSONSerialization.data(withJSONObject: payload))
        let icons = [IslandStatusIcon(id: "cpu", content: .metric(.cpu, text: "20%", image: nil, style: .detailed), tooltip: "CPU")]
        fixture.presenter.setStatusIcons(icons)
        let notices = [
            IslandNotice(id: "ai-active-openai", title: "AI"),
            IslandNotice(id: "media-active-left", title: "Music"),
            IslandNotice(id: "toolbox-reminder-awake", title: "Awake", detail: "30:00"),
        ]
        let combined = fixture.presenter.compactConfiguration(for: notices, at: .distantPast)
        let size = try #require(combined.statusIconSize, "More information must reserve the combined content size")
        let iconSize = try #require(IslandStatusIconLayout.size(icons: icons, edge: edge))
        let firstThickness = max(32, edge.isVertical ? iconSize.width : iconSize.height)
        #expect((edge.isVertical ? size.width : size.height) == firstThickness + 32,
                "Detailed playback needs a second row alongside the persistent first row")
        let frame = try #require(fixture.presenter.compactFrame(for: fixture.screen, notices: notices, at: .distantPast))
        #expect(frame.size == size)
        #expect(fixture.screen.frame.contains(frame))
        let hidden = fixture.presenter.compactConfiguration(for: notices, at: .distantPast, statusHidden: true)
        #expect(hidden.statusIconSize == IslandStatusIconLayout.size(icons: icons, edge: edge))
    }

    @Test(arguments: IslandEdge.allCases) @MainActor
    func monitorOrderChangesTheVisibleLayoutAndRestoresTheSameReadings(edge: IslandEdge) throws {
        let fixture = try IconFixture(edge: edge)
        defer { fixture.close() }
        fixture.settings.settings.sideNoticesEnabled = true
        fixture.settings.settings.mediaCompactStyle = .detailed
        let icons = [IslandStatusIcon(id: "cpu", content: .metric(.cpu, text: "20%", image: nil, style: .detailed), tooltip: "CPU")]
        let media = IslandNotice(id: "media-active-left", title: "Music", detail: "Track")
        let download = IslandNotice(id: "browser-download-left", title: "Download", progress: 0.5)
        fixture.presenter.setStatusIcons(icons)
        let monitor = fixture.presenter.compactConfiguration(for: [], at: .distantPast)
        #expect(monitor.statusIconSize == IslandStatusIconLayout.size(icons: icons, edge: edge))
        #expect(fixture.presenter.compactConfiguration(for: [media, download], at: .distantPast).statusIconSize == nil)
        fixture.settings.settings.compactStatusPriority = CompactStatusPriority.normalized([.systemMonitor])
        #expect(fixture.presenter.compactConfiguration(for: [media], at: .distantPast) == monitor)
        #expect(fixture.presenter.compactConfiguration(for: [media, download], at: .distantPast) == monitor)
        let frame = try #require(fixture.presenter.compactFrame(for: fixture.screen, notices: [media, download]))
        #expect(frame.size == monitor.statusIconSize)
        fixture.settings.settings.compactStatusPriority = CompactStatusPriority.normalized([.media, .systemMonitor])
        let playback = fixture.presenter.compactConfiguration(for: [media, download], at: .distantPast)
        #expect(playback.statusIconSize == nil && playback.expandsForDetailedStatus)
        #expect(fixture.presenter.compactConfiguration(for: [media, download], at: .distantPast, statusHidden: true) == monitor)
        fixture.presenter.setStatusIcons([])
        #expect(fixture.presenter.compactConfiguration(for: [media, download], at: .distantPast) == playback)
        #expect(fixture.presenter.compactConfiguration(for: [], at: .distantPast).statusIconSize == nil)
        fixture.presenter.setStatusIcons(icons)
        #expect(fixture.presenter.compactConfiguration(for: [], at: .distantPast) == monitor)
        fixture.settings.settings.systemMonitorEnabled = false
        #expect(fixture.presenter.compactConfiguration(for: [], at: .distantPast).statusIconSize == nil)
        #expect(fixture.presenter.compactConfiguration(for: [media, download], at: .distantPast) == playback)
        fixture.settings.settings.systemMonitorEnabled = true
        fixture.settings.settings.statusIconDestination = .menuBar
        #expect(fixture.presenter.compactConfiguration(for: [], at: .distantPast).statusIconSize == nil)
        fixture.settings.settings.statusIconDestination = .island
        #expect(fixture.presenter.compactConfiguration(for: [], at: .distantPast) == monitor)
    }

    @Test @MainActor
    func monitorPriorityKeepsSpecialTakeoversAndTheApplicationOnlyFallback() throws {
        let fixture = try IconFixture(edge: .left)
        defer { fixture.close() }
        fixture.settings.settings.sideNoticesEnabled = true
        fixture.settings.settings.compactStatusPriority = CompactStatusPriority.normalized([.systemMonitor])
        let application = IslandStatusIcon(id: "app", content: .application, tooltip: "zisla")
        let monitor = IslandStatusIcon(id: "cpu", content: .metric(.cpu, text: "20%", image: nil, style: .detailed), tooltip: "CPU")
        #expect(!application.isSystemMonitor && monitor.isSystemMonitor)
        fixture.presenter.setStatusIcons([application, monitor])
        let idle = fixture.presenter.compactConfiguration(for: [], at: .distantPast)
        let media = IslandNotice(id: "media-active-left", title: "Music")
        for notice in [IslandNotice(id: "voice-processing-left", title: "Voice"),
                       IslandNotice(id: "screen-recording-operation-left", title: "Recording"),
                       IslandNotice(id: "focus-transition", title: "Focus"),
                       IslandNotice(id: LowBatteryNoticeController.noticeID, title: "Battery")] {
            #expect(fixture.presenter.compactConfiguration(for: [media, notice], at: .distantPast).statusIconSize == nil)
        }
        fixture.presenter.setVoiceRecording(true)
        #expect(fixture.presenter.compactConfiguration(for: [media], at: .distantPast).statusIconSize == nil)
        fixture.presenter.setVoiceRecording(false)
        fixture.presenter.setTransientNoticePresented(true, message: "Saved")
        #expect(fixture.presenter.compactConfiguration(for: [media], at: .distantPast).statusIconSize == nil)
        fixture.presenter.setTransientNoticePresented(false)
        #expect(fixture.presenter.compactConfiguration(for: [media], at: .distantPast) == idle)
        fixture.sweep.receive(previous: .running,
            task: AIProgressTask(id: "monitor-priority", provider: .codex, title: "Test", progress: nil,
                status: .succeeded, updatedAt: .distantPast),
            observedSince: .distantFuture, settings: fixture.settings.settings)
        #expect(fixture.sweep.current != nil)
        #expect(fixture.presenter.compactConfiguration(for: [media], at: .distantPast).statusIconSize == nil)
        fixture.sweep.cancel()
        #expect(fixture.presenter.compactConfiguration(for: [media], at: .distantPast) == idle)
        fixture.settings.settings.systemMonitorEnabled = false
        #expect(fixture.presenter.compactConfiguration(for: [], at: .distantPast).statusIconSize
            == IslandStatusIconLayout.size(icons: [application], edge: .left))
        fixture.settings.settings.systemMonitorEnabled = true
        fixture.presenter.setStatusIcons([application])
        #expect(fixture.presenter.compactConfiguration(for: [media], at: .distantPast).statusIconSize == nil)
    }

    @Test @MainActor
    func monitorRowsUseActualRoutedContentAndKeepTheConfiguredOrderWhenHidden() throws {
        var settings = FeatureSettings.default
        settings.islandLayoutStyle = .pill
        settings.islandPlacement = IslandPlacement(mode: .custom, edge: .left)
        settings.statusIconDestination = .island
        let original = settings.compactStatusPriority
        let application = IslandStatusIcon(id: "app", content: .application, tooltip: "zisla")
        let monitor = IslandStatusIcon(id: "cpu", content: .metric(.cpu, text: "--", image: nil, style: .detailed), tooltip: "CPU")
        let stacked = IslandStatusIcon(id: "stacked", content: .stacked(image: nil,
            readings: [.init(metric: .cpu, text: "--")]), tooltip: "CPU")
        let combined = IslandStatusIcon(id: "combined", content: .combined(nil), tooltip: "Monitor")
        for icons in [[], [application], [monitor], [stacked], [combined], [application, monitor]] as [[IslandStatusIcon]] {
            let rows = SettingsView.compactStatusPriorities(settings: settings,
                hasSystemMonitorIcons: icons.contains(where: \.isSystemMonitor))
            #expect(rows.contains(.systemMonitor) == icons.contains(where: \.isSystemMonitor))
            #expect(rows.filter { $0 != .systemMonitor } == original.filter { $0 != .systemMonitor })
        }
        #expect(SettingsView.compactStatusPriorities(settings: settings, hasSystemMonitorIcons: true).last == .systemMonitor)
        settings.compactStatusPriority = CompactStatusPriority.normalized([.systemMonitor, .media])
        #expect(SettingsView.compactStatusPriorities(settings: settings, hasSystemMonitorIcons: true).first == .systemMonitor)
        let custom = settings.compactStatusPriority
        settings.systemMonitorEnabled = false
        #expect(!SettingsView.compactStatusPriorities(settings: settings, hasSystemMonitorIcons: true).contains(.systemMonitor))
        settings.systemMonitorEnabled = true
        settings.statusIconDestination = .menuBar
        #expect(!SettingsView.compactStatusPriorities(settings: settings, hasSystemMonitorIcons: true).contains(.systemMonitor))
        settings.statusIconDestination = .island
        settings.islandPlacement = IslandPlacement()
        #expect(!SettingsView.compactStatusPriorities(settings: settings, hasSystemMonitorIcons: true).contains(.systemMonitor))
        settings.islandPlacement = IslandPlacement(mode: .custom, edge: .left)
        #expect(SettingsView.compactStatusPriorities(settings: settings, hasSystemMonitorIcons: true) == custom)
        #expect(settings.compactStatusPriority == custom)
    }

    @Test @MainActor
    func compactViewUsesThePresenterMonitorAvailabilityWhenActivitiesAreQueued() throws {
        let fixture = try IconFixture(edge: .left)
        defer { fixture.close() }
        fixture.settings.settings.compactStatusPriority = CompactStatusPriority.normalized([.systemMonitor])
        fixture.queue.enqueue(IslandNotice(id: "media-active-left", title: "Music"), expiresAfter: nil)
        let state = SideNoticeDisplayState()
        let view = CompactStatusBarView(queue: fixture.queue, displayState: state, media: fixture.media,
            browserDownloads: fixture.downloads, settingsStore: fixture.settings, resultSweep: fixture.sweep,
            pomodoro: PomodoroService(notificationRequestHandler: { _ in }, defaults: fixture.defaults), onStatusHidden: {})
        #expect(view.selectedCompactStatusPriority == .media)
        state.systemMonitorAvailable = true
        #expect(view.selectedCompactStatusPriority == .systemMonitor)
        #expect(state.statusIcons.isEmpty)
        state.systemMonitorAvailable = false
        #expect(view.selectedCompactStatusPriority == .media)
    }

    @Test
    func monitorPriorityTitleUsesExistingTranslations() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        let key = CompactStatusPriority.systemMonitor.title
        #expect(key == "系统监控")
        #expect(AppLanguage.allCases.count == 17)
        for language in AppLanguage.allCases {
            let url = root.appendingPathComponent("Resources/Localization/\(language.rawValue).lproj/Localizable.strings")
            let table = try #require(NSDictionary(contentsOf: url) as? [String: String])
            let translated = try #require(table[key], "\(language.rawValue) missing \(key)")
            #expect(!translated.isEmpty)
            #expect(AppLocalization.string(key, locale: language.locale) == translated)
        }
        #expect(AppLocalization.string(key, language: .english) == "System Monitor")
        #expect(AppLocalization.string(key, language: .arabic) == "مراقب النظام")
    }

    @Test(arguments: IslandEdge.allCases) @MainActor
    func oversizedStatusIconsKeepTheQuickActionLengthLimitAndBothEndInsets(edge: IslandEdge) async throws {
        let fixture = try IconFixture(edge: edge)
        defer { fixture.close() }
        let image = NSImage(size: CGSize(width: 36, height: 36), flipped: false) { rect in
            NSColor(deviceRed: 1, green: 0, blue: 0, alpha: 1).setFill()
            rect.fill()
            return true
        }
        let icons = [IslandStatusIcon(id: "combined", content: .combined(image), tooltip: "Monitor")]
            + (0..<20).map { IslandStatusIcon(id: "cpu-\($0)",
                content: .metric(.cpu, text: "20%", image: nil, style: .detailed), tooltip: "CPU") }
        fixture.presenter.setStatusIcons(icons)
        for dimension: CGFloat in [280, 900] {
            let snapshot = ScreenSnapshot(displayID: 7,
                frame: CGRect(x: 20000, y: 0, width: dimension, height: dimension),
                visibleFrame: CGRect(x: 20000, y: 0, width: dimension, height: dimension))
            let frame = try #require(fixture.presenter.compactFrame(for: snapshot, notices: []))
            #expect((edge.isVertical ? frame.height : frame.width) == min(480, dimension - 16))
            let bitmap = try await renderOffscreen(IslandStatusIconStrip(icons: icons, edge: edge, date: .distantPast), size: frame.size)
            let scale = CGFloat(bitmap.pixelsWide) / frame.width
            let axisLength = edge.isVertical ? bitmap.pixelsHigh : bitmap.pixelsWide
            let crossLength = edge.isVertical ? bitmap.pixelsWide : bitmap.pixelsHigh
            var endPixels = 0
            var firstIconPixels = 0
            for axis in 0..<axisLength {
                for cross in 0..<crossLength {
                    let color = try #require(bitmap.colorAt(x: edge.isVertical ? cross : axis,
                        y: edge.isVertical ? axis : cross))
                    if max(color.redComponent, color.greenComponent, color.blueComponent) > 0.5 {
                        if axis < Int(8 * scale) || axis >= axisLength - Int(8 * scale) { endPixels += 1 }
                        if axis < Int(44 * scale), color.redComponent > 0.5 && color.greenComponent < 0.2 { firstIconPixels += 1 }
                    }
                }
            }
            #expect(endPixels == 0, "Clipping long icon rows must preserve both 8pt outer insets")
            #expect(firstIconPixels > 100, "The leading combined icon must remain visible at the fixed size")
        }
        #expect(fixture.presenter.compactConfiguration(for: [], at: .distantPast).statusIconSize != nil)
    }

    @Test(arguments: [true, false]) @MainActor
    func globalBindingPersistsWithoutChangingTheIndividualFeatureSelections(systemMonitorEnabled: Bool) throws {
        let suite = "StatusIconDestinationIntegrationTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        let store = FeatureSettingsStore(defaults: defaults, persistenceDelay: .seconds(60), defaultUpdateChannel: .release)
        defer {
            store.flushPendingChanges()
            defaults.removePersistentDomain(forName: suite)
        }
        store.settings.systemMonitorMenuBarMetrics = [.gpu, .fan]
        store.settings.systemMonitorMenuBarLayout = .both
        store.settings.systemMonitorMenuBarTopRow = [.network]
        store.settings.systemMonitorMenuBarBottomRow = [.cpu, .memory]
        store.settings.systemMonitorMenuBarCombinedIconEnabled = true
        store.settings.menuBarAppIconEnabled = true
        store.settings.systemMonitorEnabled = systemMonitorEnabled
        let original = store.settings
        let binding = Binding(get: { store.settings }, set: { store.settings = $0 })
        for destination in StatusIconDestination.allCases {
            binding.statusIconDestination.wrappedValue = destination
            store.flushPendingChanges()
            let reloaded = FeatureSettingsStore(defaults: defaults, defaultUpdateChannel: .release)
            #expect(reloaded.settings == store.settings)
            var expected = original
            expected.statusIconDestination = destination
            #expect(reloaded.settings == expected)
        }
    }

    @Test @MainActor
    func aDamagedDestinationDoesNotResetTheStoreAndTheNextWriteRepairsOnlyThatField() throws {
        let suite = "StatusIconDestinationRecoveryTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        var original = FeatureSettings.default
        original.mediaEnabled = false
        original.systemMonitorEnabled = false
        original.menuBarAppIconEnabled = false
        original.sideNoticesEnabled = false
        original.systemMonitorMenuBarMetrics = [.gpu, .fan]
        original.systemMonitorMenuBarLayout = .none
        original.systemMonitorMenuBarCombinedIconAppearance.iconSize = 36
        let invalidValues: [Any] = ["future-destination", true, 5, [String](), [String: String]()]
        for value in invalidValues {
            var payload = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(original)) as? [String: Any])
            payload["statusIconDestination"] = value
            defaults.set(try JSONSerialization.data(withJSONObject: payload), forKey: "feature-settings-v1")
            let store = FeatureSettingsStore(defaults: defaults, persistenceDelay: .seconds(60), defaultUpdateChannel: .release)
            #expect(store.settings == original)
            store.settings.statusIconDestination = .island
            store.flushPendingChanges()
            var expected = original
            expected.statusIconDestination = .island
            #expect(FeatureSettingsStore(defaults: defaults, defaultUpdateChannel: .release).settings == expected)
        }
    }

    @Test
    func allDestinationLabelsAreUniqueAndTranslatedInEveryLanguage() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        let source = try String(contentsOf: root.appendingPathComponent("Sources/Zisla/SettingsView.swift"), encoding: .utf8)
        #expect(source.components(separatedBy: "status-icon-destination-selection").count == 2)
        #expect(source.contains("settingsStore.settings.effectiveStatusIconDestination"))
        let row = try NSRegularExpression(pattern: #"settingRow\(symbol:\s*"menubar\.rectangle",\s*title:\s*"([^"]+)",\s*detail:\s*""\)\s*\{\s*IslandOutlinedPicker\([\s\S]*?selectionID:\s*"status-icon-destination-selection""#)
        let matches = row.matches(in: source, range: NSRange(source.startIndex..., in: source))
        #expect(matches.count == 1)
        let match = try #require(matches.first)
        let titleRange = try #require(Range(match.range(at: 1), in: source))
        let title = String(source[titleRange])
        let expectedTitle = "机器监控状态显示位置"
        #expect(title == expectedTitle)
        let keys = Set([title, expectedTitle, "常驻监控图标", "关闭后不影响已启用的监控图标"]
            + StatusIconDestination.allCases.map(\.menuTitle))
        let englishURL = root.appendingPathComponent("Resources/Localization/en.lproj/Localizable.strings")
        let english = try #require(NSDictionary(contentsOf: englishURL) as? [String: String])
        #expect(AppLanguage.allCases.count == 17)
        for language in AppLanguage.allCases {
            let url = root.appendingPathComponent("Resources/Localization/\(language.rawValue).lproj/Localizable.strings")
            let source = try String(contentsOf: url, encoding: .utf8)
            let table = try #require(NSDictionary(contentsOf: url) as? [String: String])
            for key in keys {
                let value = try #require(table[key], "\(language.rawValue) missing \(key)")
                #expect(!value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                #expect(!value.contains("%"), "Destination labels must not add format placeholders")
                let expression = try NSRegularExpression(pattern: "^\\s*\"" + NSRegularExpression.escapedPattern(for: key) + "\"\\s*=", options: .anchorsMatchLines)
                #expect(expression.numberOfMatches(in: source, range: NSRange(source.startIndex..., in: source)) == 1)
                #expect(AppLocalization.string(key, locale: language.locale) == value)
                if language != .simplifiedChinese {
                    #expect(value != key, "\(language.rawValue) did not translate \(key)")
                }
                if key == expectedTitle, language != .english, language != .simplifiedChinese,
                   language != .traditionalChinese {
                    #expect(value != english[key], "\(language.rawValue) copied the English destination label")
                }
            }
        }
        #expect(AppLocalization.string("状态栏", locale: Locale(identifier: "en")) == "Menu Bar")
        #expect(AppLocalization.string("灵动岛", locale: Locale(identifier: "ar")) == "الجزيرة الديناميكية")
        #expect(AppLocalization.string(expectedTitle, locale: Locale(identifier: "en")) == "System Monitor Status Display Location")
        #expect(AppLocalization.string(expectedTitle, locale: Locale(identifier: "zh-Hant")) == "機器監控狀態顯示位置")
        #expect(AppLocalization.string(expectedTitle, locale: Locale(identifier: "ar")) == "موضع عرض حالة مراقب النظام")
    }

    @Test
    func destinationControlHidesWithItsDividerAndRemainsOutsideConditionalMonitorOptions() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        let source = try String(contentsOf: root.appendingPathComponent("Sources/Zisla/SettingsView.swift"), encoding: .utf8)
        let workflowStart = try #require(source.range(of: "    private var workflowContent: some View {"))
        let featuresStart = try #require(source.range(of: "    private var featuresContent: some View {"))
        let keyboardStart = try #require(source.range(of: "    private var keyboardSoundContent: some View {"))
        let workflow = String(source[workflowStart.lowerBound..<featuresStart.lowerBound])
        let features = String(source[featuresStart.lowerBound..<keyboardStart.lowerBound])
        #expect(workflow.components(separatedBy: "status-icon-destination-selection").count == 2)
        #expect(!features.contains("status-icon-destination-selection"))
        #expect(!features.contains("图标显示位置"))
        #expect(!features.contains("机器监控状态显示位置"))
        let destination = try #require(workflow.range(of: "title: \"机器监控状态显示位置\""))
        let monitorOptions = try #require(workflow.range(of: "if model.settingsStore.settings.systemMonitorEnabled {"))
        #expect(destination.lowerBound < monitorOptions.lowerBound)
        let conditionalRow = try NSRegularExpression(pattern: #"if settingsStore\.settings\.supportsStatusIconsInIsland\s*\{\s*rowDivider\s*settingRow\(symbol: "menubar\.rectangle", title: "机器监控状态显示位置", detail: ""\)\s*\{[\s\S]*?\n                \}\n                if model\.settingsStore\.settings\.systemMonitorEnabled"#)
        #expect(conditionalRow.numberOfMatches(in: workflow, range: NSRange(workflow.startIndex..., in: workflow)) == 1,
                "The destination row and its divider must be absent when only the menu bar is supported")
    }

    @Test(arguments: AppLanguage.allCases)
    func iconDestinationSearchFollowsEditableLayoutsAndPreservesMonitorSearches(language: AppLanguage) {
        var settings = FeatureSettings.default
        settings.mediaEnabled = true
        let locale = language.locale
        let title = "机器监控状态显示位置"
        let localizedTitle = AppLocalization.string(title, locale: locale)
        #expect(SettingsSearchAnchor.row(title).localized(locale: locale) == .row(localizedTitle))
        for style in IslandLayoutStyle.allCases {
            settings.islandLayoutStyle = style
            for mode in IslandPlacementMode.allCases {
                settings.islandPlacement.mode = mode
                let editable = style == .pill && mode == .custom
                for enabled in [true, false] {
                    settings.systemMonitorEnabled = enabled
                    let items = SettingsSearchIndex.items(settings: settings)
                    #expect(items.filter { $0.title == title }.count == (editable ? 1 : 0))
                    #expect(!items.contains { $0.title == "图标显示位置" })
                    let matches = SettingsSearchIndex.results(for: localizedTitle, settings: settings, locale: locale)
                    if editable {
                        #expect(matches.first?.section == .info)
                        #expect(matches.first?.anchor == .row(title))
                    }
                    for query in [title, "状态栏", "灵动岛"].map({ AppLocalization.string($0, locale: locale) }) {
                        #expect(SettingsSearchIndex.results(for: query, settings: settings, locale: locale).contains {
                            $0.section == .info && $0.title == title && $0.anchor == .row(title)
                        } == editable)
                    }
                }
            }
        }
        settings.systemMonitorEnabled = true
        for query in ["常驻监控图标", "菜单栏常驻"] {
            #expect(SettingsSearchIndex.results(for: query, settings: settings, locale: locale).contains {
                $0.section == .info && $0.anchor == .row("常驻监控图标")
            })
        }
    }

    @Test @MainActor
    func routingMovesEveryEnabledIconAndPreservesTheirMenuAndReadings() throws {
        let application = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        let stacked = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        let combined = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        let metrics = SystemMonitorMenuBarMetric.allCases.map { metric in
            let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
            item.button?.title = "\(SystemMonitorMenuBarPresentation.label(for: metric)) --"
            return (metric, item, "--")
        }
        let items = [application, stacked, combined] + metrics.map { $0.1 }
        items.forEach { $0.isVisible = false }
        defer { items.forEach { NSStatusBar.system.removeStatusItem($0) } }
        let menu = NSMenu()
        menu.addItem(withTitle: "Settings", action: nil, keyEquivalent: "")
        application.menu = menu
        for item in [stacked, combined] + metrics.map({ $0.1 }) {
            item.button?.target = application
            item.button?.action = #selector(NSObject.description)
        }
        let readings = [IslandStatusIcon.Reading(metric: .cpu, text: "20%"),
                        IslandStatusIcon.Reading(metric: .memory, text: "2 GB/8 GB")]
        stacked.button?.image = SystemMonitorMenuBarImageRenderer.stacked(rows: ["C 20%", "M 2 GB/8 GB"], style: .compact)
        combined.button?.image = SystemMonitorMenuBarImageRenderer.combinedIcon(battery: nil, wifi: .off, level: nil,
            foreground: .white, configuration: SystemMonitorCombinedIconAppearance(iconSize: 36))
        for style in SystemMonitorMenuBarDisplayStyle.allCases {
            let titles = metrics.map { metric, item, compact in
                (metric, item, style == .detailed ? "\(SystemMonitorMenuBarPresentation.label(for: metric)) \(compact)" : compact)
            }
            let icons = IslandStatusIconRouting.update(destination: .island, application: application,
                metrics: titles, stacked: stacked, readings: readings, combined: combined, style: style)
            #expect(items.allSatisfy { !$0.isVisible })
            #expect(icons.map(\.id) == ["status-icon-application", "status-icon-combined"]
                + SystemMonitorMenuBarMetric.allCases.map { "status-icon-\($0.rawValue)" }
                + ["status-icon-stacked"])
            for icon in icons {
                if case let .metric(_, text, _, _) = icon.content { #expect(text == "--") }
            }
            let combinedIcon = try #require(icons.first { $0.id == "status-icon-combined" })
            #expect(combinedIcon.size(edge: .left) == CGSize(width: 36, height: 36))
            let stackedIcon = try #require(icons.first { $0.id == "status-icon-stacked" })
            let image = try #require(stacked.button?.image)
            for edge in IslandEdge.allCases {
                #expect(stackedIcon.size(edge: edge) == CGSize(width: image.size.width, height: 24),
                        "Merged monitors must retain the menu bar image's width and both horizontal rows")
            }
            let withoutCombined = IslandStatusIconRouting.update(destination: .island, application: application,
                metrics: titles, stacked: stacked, readings: readings, combined: nil, style: style)
            #expect(withoutCombined.map(\.id) == ["status-icon-application"]
                + SystemMonitorMenuBarMetric.allCases.map { "status-icon-\($0.rawValue)" }
                + ["status-icon-stacked"])
            #expect(application.menu === menu)
            #expect(IslandStatusIconRouting.update(destination: .menuBar, application: application,
                metrics: metrics, stacked: stacked, readings: readings, combined: combined, style: style).isEmpty)
            #expect(items.allSatisfy { $0.isVisible })
            #expect(application.menu === menu)
            #expect(([stacked, combined] + metrics.map({ $0.1 })).allSatisfy {
                $0.button?.target === application && $0.button?.action == #selector(NSObject.description)
            })
        }
        #expect(IslandStatusIconRouting.update(destination: .island, application: nil, metrics: [],
            stacked: nil, readings: [], combined: nil, style: .compact, islandAppIconEnabled: false).isEmpty)
    }

    @Test(arguments: IslandEdge.allCases, [LayoutDirection.leftToRight, .rightToLeft]) @MainActor
    func routedLogoRendersBeforeTheCombinedIconAndStackedReadings(edge: IslandEdge, direction: LayoutDirection) async throws {
        let application = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        let combined = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        let stacked = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        let items = [application, combined, stacked]
        items.forEach { $0.isVisible = false }
        defer { items.forEach { NSStatusBar.system.removeStatusItem($0) } }
        let image = NSImage(size: CGSize(width: 36, height: 36), flipped: false) { rect in
            NSColor.red.setFill()
            rect.fill()
            return true
        }
        combined.button?.image = image
        let readings = [IslandStatusIcon.Reading(metric: .cpu, text: "14%"),
                        IslandStatusIcon.Reading(metric: .gpu, text: "0%")]
        stacked.button?.image = SystemMonitorMenuBarImageRenderer.stacked(rows: ["C 14%", "G 0%"], style: .compact)
        let icons = IslandStatusIconRouting.update(destination: .island, application: application,
            metrics: [], stacked: stacked, readings: readings, combined: combined, style: .compact)
        let size = try #require(IslandStatusIconLayout.size(icons: icons, edge: edge))
        let bitmap = try await renderOffscreen(IslandStatusIconStrip(icons: icons, edge: edge, date: .distantPast)
            .environment(\.layoutDirection, direction)
            .environment(\._accessibilityReduceMotion, true), size: size)
        var combinedBounds = CGRect.null
        for y in 0..<bitmap.pixelsHigh {
            for x in 0..<bitmap.pixelsWide {
                let color = try #require(bitmap.colorAt(x: x, y: y))
                if color.redComponent > 0.5 && color.greenComponent < 0.2 {
                    combinedBounds = combinedBounds.union(CGRect(x: x, y: y, width: 1, height: 1))
                }
            }
        }
        #expect(!combinedBounds.isNull, "The combined status icon must remain visible")
        var logoPixels = 0
        var readingPixels = 0
        for y in 0..<bitmap.pixelsHigh {
            for x in 0..<bitmap.pixelsWide {
                let color = try #require(bitmap.colorAt(x: x, y: y))
                guard min(color.redComponent, color.greenComponent, color.blueComponent) > 0.1 else { continue }
                if edge.isVertical ? CGFloat(y) < combinedBounds.minY : CGFloat(x) < combinedBounds.minX { logoPixels += 1 }
                if edge.isVertical ? CGFloat(y) >= combinedBounds.maxY : CGFloat(x) >= combinedBounds.maxX { readingPixels += 1 }
            }
        }
        #expect(logoPixels > 10, "The logo must render first on every edge, including RTL languages")
        #expect(readingPixels > 10, "Both stacked readings must remain after the combined status icon")
        #expect(items.allSatisfy { !$0.isVisible })
        #expect(combined.button?.image === image && image.size == CGSize(width: 36, height: 36))
    }

    @Test @MainActor
    func detailedNetworkIconsRetainBothTransferRatesAndCompactIconsKeepTheirOriginalReading() throws {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.isVisible = false
        defer { NSStatusBar.system.removeStatusItem(item) }
        item.button?.title = "Network ↓12 MB/s ↑7 MB/s"
        for style in SystemMonitorMenuBarDisplayStyle.allCases {
            let title = style == .detailed ? "Network ↓12 MB/s ↑7 MB/s" : "↓12 MB/s"
            let icons = IslandStatusIconRouting.update(destination: .island, application: nil,
                metrics: [(.network, item, title)], stacked: nil, readings: [], combined: nil, style: style,
                islandAppIconEnabled: false)
            guard case let .metric(metric, text, _, selectedStyle) = try #require(icons.first).content else {
                Issue.record("The selected network metric must remain an individual icon")
                return
            }
            #expect(metric == .network && selectedStyle == style)
            #expect(text == (style == .detailed ? "↓12 MB/s ↑7 MB/s" : "↓12 MB/s"))
        }
    }

    @Test @MainActor
    func islandTooltipsKeepReadingsWithoutOfferingMenuBarClickActions() throws {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.isVisible = false
        defer { NSStatusBar.system.removeStatusItem(item) }
        item.button?.title = "CPU 20%"
        let action = AppLocalization.text("点击打开系统监控")
        let tooltip = "CPU: 20%\n\(action)"
        item.button?.toolTip = tooltip
        let icons = IslandStatusIconRouting.update(destination: .island, application: nil,
            metrics: [(.cpu, item, "20%")], stacked: item, readings: [], combined: item, style: .detailed,
            islandAppIconEnabled: false)
        #expect(icons.count == 3)
        #expect(icons.allSatisfy { $0.tooltip == "CPU: 20%" })
        #expect(item.button?.toolTip == tooltip, "Moving an icon must preserve its original menu bar behavior")
    }

    @Test @MainActor
    func theIslandLogoKeepsAnimatingWhileMonitorOnlyStripsPauseTheirTimeline() throws {
        let fixture = try IconFixture(edge: .left)
        defer { fixture.close() }
        let state = SideNoticeDisplayState()
        state.placementMode = .custom
        state.islandEdge = .left
        let view = CompactStatusBarView(queue: fixture.queue, displayState: state, media: fixture.media,
            browserDownloads: fixture.downloads, settingsStore: fixture.settings, resultSweep: fixture.sweep,
            pomodoro: PomodoroService(notificationRequestHandler: { _ in }, defaults: fixture.defaults), onStatusHidden: {})
        state.statusIcons = [IslandStatusIcon(id: "cpu", content: .metric(.cpu, text: "20%", image: nil, style: .detailed), tooltip: "CPU")]
        #expect(view.pausesCompactTimeline)
        state.statusIcons.append(IslandStatusIcon(id: "app", content: .application, tooltip: "zisla"))
        if !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            #expect(!view.pausesCompactTimeline, "The application logo must continue to use its existing animation clock")
        }
        state.statusIcons.removeAll()
        state.placementMode = .camera
        #expect(view.pausesCompactTimeline)
    }

    @Test(arguments: IslandEdge.allCases) @MainActor
    func iconImagesAndVerticalReadingsRenderInsideTheMeasuredStrip(edge: IslandEdge) async throws {
        let colorSpace = try #require(CGColorSpace(name: CGColorSpace.sRGB))
        let context = try #require(CGContext(data: nil, width: 72, height: 72, bitsPerComponent: 8,
            bytesPerRow: 0, space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(red: 1, green: 0, blue: 0, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: 72, height: 72))
        let image = NSImage(cgImage: try #require(context.makeImage()), size: NSSize(width: 36, height: 36))
        let icons = [IslandStatusIcon(id: "cpu", content: .metric(.cpu, text: "20%", image: nil, style: .detailed), tooltip: "CPU"),
                     IslandStatusIcon(id: "combined", content: .combined(image), tooltip: "Monitor")]
        let size = try #require(IslandStatusIconLayout.size(icons: icons, edge: edge))
        let bitmap = try await renderOffscreen(IslandStatusIconStrip(icons: icons, edge: edge, date: .distantPast), size: size)
        var redPixels = 0
        var textPixels = 0
        var redBounds = CGRect.null
        for y in 0..<bitmap.pixelsHigh {
            for x in 0..<bitmap.pixelsWide {
                let color = try #require(bitmap.colorAt(x: x, y: y))
                if color.redComponent > 0.5 && color.greenComponent < 0.2 {
                    redPixels += 1
                    redBounds = redBounds.union(CGRect(x: x, y: y, width: 1, height: 1))
                }
                if min(color.redComponent, color.greenComponent, color.blueComponent) > 0.5 { textPixels += 1 }
            }
        }
        let pixelsPerPoint = CGFloat(bitmap.pixelsWide * bitmap.pixelsHigh) / (size.width * size.height)
        #expect(CGFloat(redPixels) / pixelsPerPoint > 1000, "The original-color combined icon must render at its configured 36pt size")
        #expect(CGFloat(textPixels) / pixelsPerPoint > 5, "The CPU reading must remain visible next to or below its symbol")
        let scale = CGFloat(bitmap.pixelsWide) / size.width
        let endInset = edge.isVertical ? CGFloat(bitmap.pixelsHigh) - redBounds.maxY
            : CGFloat(bitmap.pixelsWide) - redBounds.maxX
        let crossInset = edge.isVertical ? min(redBounds.minX, CGFloat(bitmap.pixelsWide) - redBounds.maxX)
            : min(redBounds.minY, CGFloat(bitmap.pixelsHigh) - redBounds.maxY)
        #expect(endInset / scale >= 7.5, "The last icon must leave eight points at the end of the strip")
        #expect(crossInset / scale >= 3.5, "The widest icon must leave four points on both cross-axis sides")
    }

    @Test(arguments: IslandEdge.allCases) @MainActor
    func missingMonitorImagesKeepTheirReadingsOrPlaceholderVisible(edge: IslandEdge) async throws {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.isVisible = false
        defer { NSStatusBar.system.removeStatusItem(item) }
        item.button?.image = nil
        item.button?.toolTip = nil
        let readings = [IslandStatusIcon.Reading(metric: .cpu, text: "20%")]
        let icons = IslandStatusIconRouting.update(destination: .island, application: nil,
            metrics: [(.cpu, item, "20%")], stacked: item, readings: readings, combined: item, style: .compact,
            islandAppIconEnabled: false)
        #expect(icons.map(\.tooltip) == ["zisla", "20%", "20%"])
        for icon in icons {
            let size = try #require(IslandStatusIconLayout.size(icons: [icon], edge: edge))
            #expect(size.width >= 24 && size.height >= 24)
            if case .combined = icon.content { #expect(size == (edge.isVertical ? CGSize(width: 32, height: 40) : CGSize(width: 40, height: 32))) }
            let bitmap = try await renderOffscreen(IslandStatusIconStrip(icons: [icon], edge: edge, date: .distantPast), size: size)
            var foregroundPixels = 0
            for y in 0..<bitmap.pixelsHigh {
                for x in 0..<bitmap.pixelsWide {
                    let color = try #require(bitmap.colorAt(x: x, y: y))
                    if min(color.redComponent, color.greenComponent, color.blueComponent) > 0.5 { foregroundPixels += 1 }
                }
            }
            #expect(foregroundPixels > 5, "\(icon.id) must stay visible if AppKit cannot supply its image")
        }
    }

    @Test(arguments: IslandEdge.allCases) @MainActor
    func theCompactPanelPublishesIconsAndRestoresThemAfterAnActivity(edge: IslandEdge) async throws {
        let fixture = try IconFixture(edge: edge)
        fixture.reducesMotion = true
        defer { fixture.close() }
        let application = NSApplication.shared
        let existingWindows = Set(application.windows.map(ObjectIdentifier.init))
        let icons = [IslandStatusIcon(id: "cpu", content: .metric(.cpu, text: "20%", image: nil, style: .detailed), tooltip: "CPU")]
        fixture.presenter.setStatusIcons(icons)
        fixture.presenter.setScreenLocked(false)
        let host = try #require(application.windows.filter { !existingWindows.contains(ObjectIdentifier($0)) }
            .compactMap { $0.contentView as? NSHostingView<AppLanguageEnvironment<CompactStatusBarView>> }.first)
        let state = host.rootView.content.displayState
        #expect(state.statusIcons.map(\.id) == ["cpu"])
        #expect(state.islandEdge == edge)
        let size = try #require(IslandStatusIconLayout.size(icons: icons, edge: edge))
        #expect(host.window?.frame.size == size)
        #expect(host.window?.ignoresMouseEvents == true, "Persistent icons must not activate the app or open a module")
        let actual = try await renderOffscreen(host.rootView.content.statusBarContent(at: .distantPast), size: size)
        let expected = try await renderOffscreen(IslandStatusIconStrip(icons: icons, edge: edge, date: .distantPast)
            .clipShape(CompactIslandShape(layoutStyle: .pill)), size: size)
        var changed = 0
        for y in 0..<actual.pixelsHigh {
            for x in 0..<actual.pixelsWide {
                let a = try #require(actual.colorAt(x: x, y: y))
                let b = try #require(expected.colorAt(x: x, y: y))
                if abs(a.redComponent - b.redComponent) > 0.02 { changed += 1 }
            }
        }
        #expect(changed == 0, "The compact panel must display the same monitor symbols and readings as the measured strip")
        fixture.queue.enqueue(IslandNotice(id: "ai-active-test", title: "Codex"), expiresAfter: nil)
        fixture.presenter.setStatusIcons(icons)
        #expect(state.statusIcons.isEmpty)
        #expect(state.systemMonitorAvailable)
        #expect(host.rootView.content.selectedCompactStatusPriority == .aiActivity)
        #expect(host.window?.ignoresMouseEvents == false, "Activities keep their existing swipe interaction")
        fixture.settings.settings.compactStatusPriority = CompactStatusPriority.normalized([.systemMonitor])
        fixture.presenter.setStatusIcons(icons)
        #expect(state.statusIcons.map(\.id) == ["cpu"])
        #expect(host.rootView.content.selectedCompactStatusPriority == .systemMonitor)
        #expect(host.window?.frame.size == size)
        #expect(host.window?.ignoresMouseEvents == true)
        fixture.settings.settings.compactStatusPriority = CompactStatusPriority.normalized([.aiActivity, .systemMonitor])
        fixture.presenter.setStatusIcons(icons)
        #expect(state.statusIcons.isEmpty)
        fixture.settings.settings.systemMonitorEnabled = false
        fixture.presenter.setStatusIcons(icons)
        #expect(!state.systemMonitorAvailable)
        #expect(host.rootView.content.selectedCompactStatusPriority == .aiActivity)
        fixture.settings.settings.systemMonitorEnabled = true
        fixture.queue.removeAll()
        fixture.presenter.setStatusIcons(icons)
        #expect(state.statusIcons.map(\.id) == ["cpu"])
        #expect(host.window?.ignoresMouseEvents == true)
        let applicationIcon = IslandStatusIcon(id: "app", content: .application, tooltip: "zisla")
        fixture.settings.settings.systemMonitorEnabled = false
        fixture.presenter.setStatusIcons([applicationIcon] + icons)
        #expect(state.statusIcons.map(\.id) == ["app"])
        #expect(!state.systemMonitorAvailable)
        fixture.settings.settings.systemMonitorEnabled = true
        fixture.presenter.setStatusIcons([])
        #expect(state.statusIcons.isEmpty)
        #expect(!state.systemMonitorAvailable)
        #expect(host.window?.frame.size == CGSize(width: 24, height: 24))
        fixture.presenter.stop()
        #expect(host.window?.isVisible != true)
    }

    @Test(arguments: [IslandEdge.top, .bottom]) @MainActor
    func compactAndStackedImagesKeepTheirMenuBarAppearanceAndOrderInRTLLanguages(edge: IslandEdge) async throws {
        let metricImage = try #require(SystemMonitorMenuBarImageRenderer.stacked(rows: ["C 20%"], style: .compact))
        let image = try #require(SystemMonitorMenuBarImageRenderer.stacked(rows: ["C 20%", "M 2 GB/8 GB"], style: .compact))
        let icons = [IslandStatusIcon(id: "cpu", content: .metric(.cpu, text: "20%", image: metricImage, style: .compact), tooltip: "CPU"),
                     IslandStatusIcon(id: "stacked", content: .stacked(image: image,
                         readings: [.init(metric: .cpu, text: "20%"), .init(metric: .memory, text: "2 GB/8 GB")]), tooltip: "Monitors")]
        let size = try #require(IslandStatusIconLayout.size(icons: icons, edge: edge))
        #expect(size == CGSize(width: metricImage.size.width + image.size.width + 24, height: 32))
        let actual = try await renderOffscreen(IslandStatusIconStrip(icons: icons, edge: edge, date: .distantPast)
            .frame(width: size.width, height: size.height)
            .environment(\.layoutDirection, .rightToLeft), size: size)
        let expected = try await renderOffscreen(HStack(spacing: 8) {
            Image(nsImage: metricImage).renderingMode(.template).frame(width: metricImage.size.width, height: 24)
            Image(nsImage: image).renderingMode(.template).frame(width: image.size.width, height: 24)
        }.padding(.horizontal, 8).padding(.vertical, 4).foregroundStyle(.white), size: size)
        var changed = 0
        for y in 0..<actual.pixelsHigh {
            for x in 0..<actual.pixelsWide {
                let a = try #require(actual.colorAt(x: x, y: y))
                let b = try #require(expected.colorAt(x: x, y: y))
                if abs(a.redComponent - b.redComponent) > 0.02 { changed += 1 }
            }
        }
        #expect(changed == 0, "Compact and stacked images must preserve their original readings and image orientation")
    }

    @Test(arguments: IslandEdge.allCases, SystemMonitorMenuBarDisplayStyle.allCases) @MainActor
    func stackedImagesKeepTheSameMenuBarRowsOnEveryEdge(edge: IslandEdge, style: SystemMonitorMenuBarDisplayStyle) async throws {
        let rows = style == .compact ? ["C 14%", "G 30%"] : ["CPU 14%", "GPU 30%"]
        let image = try #require(SystemMonitorMenuBarImageRenderer.stacked(rows: rows, style: style))
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.isVisible = false
        item.button?.image = image
        defer { NSStatusBar.system.removeStatusItem(item) }
        let icons = IslandStatusIconRouting.update(destination: .island, application: nil,
            metrics: [], stacked: item, readings: [.init(metric: .cpu, text: "14%"), .init(metric: .gpu, text: "30%")],
            combined: nil, style: style, islandAppIconEnabled: false)
        let icon = try #require(icons.first)
        let size = try #require(IslandStatusIconLayout.size(icons: icons, edge: edge))
        let expectedSize = edge.isVertical ? CGSize(width: image.size.width + 8, height: 40)
            : CGSize(width: image.size.width + 16, height: 32)
        #expect(icon.size(edge: edge) == CGSize(width: image.size.width, height: 24))
        #expect(size == expectedSize)
        if case let .stacked(routedImage, _) = icon.content { #expect(routedImage === image) }
        else { Issue.record("The merged status item must remain one stacked image") }
        let actual = try await renderOffscreen(IslandStatusIconStrip(icons: icons, edge: edge, date: .distantPast)
            .environment(\.layoutDirection, .rightToLeft), size: expectedSize)
        let expected = try await renderOffscreen(Image(nsImage: image).renderingMode(.template)
            .frame(width: image.size.width, height: 24)
            .padding(edge.isVertical ? .vertical : .horizontal, 8)
            .padding(edge.isVertical ? .horizontal : .vertical, 4)
            .foregroundStyle(.white), size: expectedSize)
        var changed = 0
        var foregroundPixels = 0
        for y in 0..<actual.pixelsHigh {
            for x in 0..<actual.pixelsWide {
                let a = try #require(actual.colorAt(x: x, y: y))
                let b = try #require(expected.colorAt(x: x, y: y))
                if abs(a.redComponent - b.redComponent) > 0.02
                    || abs(a.greenComponent - b.greenComponent) > 0.02
                    || abs(a.blueComponent - b.blueComponent) > 0.02 { changed += 1 }
                if min(a.redComponent, a.greenComponent, a.blueComponent) > 0.5 { foregroundPixels += 1 }
            }
        }
        #expect(changed == 0, "Both configured menu bar rows must remain horizontal and preserve their template pixels")
        #expect(foregroundPixels > 10, "Merged monitor labels and readings must stay visible on the black island")
        #expect(item.button?.image === image && image.isTemplate && image.accessibilityDescription == rows.joined(separator: ", "))
        #expect(IslandStatusIconRouting.update(destination: .menuBar, application: nil, metrics: [],
            stacked: item, readings: [], combined: nil, style: style).isEmpty)
        #expect(item.isVisible && item.button?.image === image)
    }

    @Test @MainActor
    func hiddenPlaybackDoesNotDrawItsProgressOverTheMonitorIcons() async throws {
        let fixture = try IconFixture(edge: .left)
        defer { fixture.close() }
        let date = Date(timeIntervalSince1970: 100)
        fixture.queue.enqueue(IslandNotice(id: "media-active-left", title: "Music"), expiresAfter: nil)
        fixture.media.publishSnapshot(NowPlayingSnapshot(title: "Music", artist: "Artist", album: nil, artworkData: nil,
            duration: 100, elapsedTime: 50, timestamp: date, isPlaying: true))
        fixture.settings.settings.collapsedProgressGlowEnabled = true
        let state = SideNoticeDisplayState()
        state.islandEdge = .left
        state.placementMode = .custom
        state.compactWingHeight = 32
        state.compactStatusHidden = true
        state.statusIcons = [IslandStatusIcon(id: "cpu", content: .metric(.cpu, text: "20%", image: nil, style: .detailed), tooltip: "CPU")]
        let size = try #require(IslandStatusIconLayout.size(icons: state.statusIcons, edge: .left))
        let view = CompactStatusBarView(queue: fixture.queue, displayState: state, media: fixture.media,
            browserDownloads: fixture.downloads, settingsStore: fixture.settings, resultSweep: fixture.sweep, pomodoro: PomodoroService(notificationRequestHandler: { _ in }, defaults: fixture.defaults), onStatusHidden: {})
        let actual = try await renderOffscreen(view.statusBarContent(at: date), size: size)
        let expected = try await renderOffscreen(IslandStatusIconStrip(icons: state.statusIcons, edge: .left, date: date)
            .clipShape(CompactIslandShape(layoutStyle: .pill)), size: size)
        var changed = 0
        for y in 0..<actual.pixelsHigh {
            for x in 0..<actual.pixelsWide {
                let a = try #require(actual.colorAt(x: x, y: y))
                let b = try #require(expected.colorAt(x: x, y: y))
                if abs(a.redComponent - b.redComponent) > 0.02 { changed += 1 }
            }
        }
        #expect(changed == 0, "A dismissed playback activity must not leave its progress glow over the persistent monitor icons")
    }

    @Test(arguments: IslandEdge.allCases) @MainActor
    func monitorCountChangesTheLongAxisAndRestoresTheIdleCircle(edge: IslandEdge) throws {
        let fixture = try IconFixture(edge: edge)
        defer { fixture.close() }
        let icons = [IslandStatusIcon(id: "cpu", content: .metric(.cpu, text: "20%", image: nil, style: .detailed), tooltip: "CPU"),
                     IslandStatusIcon(id: "memory", content: .metric(.memory, text: "2 GB/8 GB", image: nil, style: .detailed), tooltip: "Memory")]
        let idle = try #require(fixture.presenter.compactFrame(for: fixture.screen, notices: []))
        #expect(idle.size == CGSize(width: 24, height: 24))
        fixture.presenter.setStatusIcons(Array(icons.prefix(1)))
        let first = try #require(fixture.presenter.compactFrame(for: fixture.screen, notices: []))
        fixture.presenter.setStatusIcons(icons)
        let more = try #require(fixture.presenter.compactFrame(for: fixture.screen, notices: []))
        #expect((edge.isVertical ? more.height : more.width) > (edge.isVertical ? first.height : first.width))
        #expect((edge.isVertical ? more.width : more.height) == (edge.isVertical ? 40 : 32))
        #expect(fixture.screen.frame.contains(more))
        let pet = try #require(CollapsedPetLayout.petFrame(for: ScreenLayoutEngine(configuration:
            fixture.presenter.compactConfiguration(for: [], at: .now)).layout(for: fixture.screen), side: .left))
        #expect(!pet.intersects(more))
        fixture.presenter.setStatusIcons(Array(icons.prefix(1)))
        #expect(fixture.presenter.compactFrame(for: fixture.screen, notices: []) == first)
        fixture.presenter.setStatusIcons([])
        #expect(fixture.presenter.compactFrame(for: fixture.screen, notices: []) == idle)
        #expect(fixture.presenter.compactConfiguration(for: [], at: .now).statusIconSize == nil)
    }

    @Test(arguments: IslandEdge.allCases) @MainActor
    func monitorPetAnchorsUseThePublishedFrameEvenWhenAnActivityIsHidden(edge: IslandEdge) throws {
        let fixture = try IconFixture(edge: edge)
        defer { fixture.close() }
        fixture.presenter.setStatusIcons([IslandStatusIcon(id: "cpu", content: .metric(.cpu, text: "20%", image: nil, style: .detailed), tooltip: "CPU")])
        let layout = ScreenLayoutEngine(configuration: fixture.presenter.compactConfiguration(for: [], at: .now)).layout(for: fixture.screen)
        let notices = [IslandNotice(id: "voice-processing-left", title: "Voice", detail: "A previous activity is hidden")]
        let frame = try #require(SideNoticeLayoutEngine().compactBarFrame(for: layout, notices: notices, settings: fixture.settings.settings))
        #expect(frame == layout.collapsedFrame, "The pet must use the published monitor frame instead of recalculating a dismissed activity")
        for side in [PetSide.left, .right] {
            let pet = try #require(CollapsedPetLayout.petFrame(for: layout, compactBarFrame: frame, side: side))
            #expect(!pet.intersects(layout.collapsedFrame))
        }
        fixture.settings.settings.statusIconDestination = .menuBar
        let activity = try #require(SideNoticeLayoutEngine().compactBarFrame(for: layout, notices: notices, settings: fixture.settings.settings))
        #expect(activity != layout.collapsedFrame)
    }

    @Test(arguments: IslandEdge.allCases) @MainActor
    func combinedIconSizeAndCoordinatorUpdatesUseTheSameCollapsedFrame(edge: IslandEdge) throws {
        let fixture = try IconFixture(edge: edge)
        defer { fixture.close() }
        fixture.settings.settings.islandPlacement.inwardDistance = 120
        let coordinator = OverlayCoordinator(contentView: NSView(),
            layoutEngine: ScreenLayoutEngine(configuration: fixture.settings.settings.islandScreenConfiguration))
        defer { coordinator.stop() }
        coordinator.screenSnapshotProvider = { [fixture] in [fixture.screen] }
        coordinator.updateScreens([fixture.screen])
        coordinator.selectActiveDisplay(at: CGPoint(x: fixture.screen.frame.midX, y: fixture.screen.frame.midY))
        fixture.presenter.onCompactLayoutChanged = { displayID, detailed, length, sideWidth, size in
            guard coordinator.activeDisplayID == displayID else { return }
            coordinator.updateCompactStatus(expandsForDetailedStatus: detailed, compactStatusLength: length,
                                            compactStatusSideWidth: sideWidth, statusIconSize: size)
        }
        for pointSize in [16.0, 36.0] {
            let image = try #require(SystemMonitorMenuBarImageRenderer.combinedIcon(battery: nil, wifi: .off, level: nil,
                foreground: .white, configuration: SystemMonitorCombinedIconAppearance(iconSize: pointSize)))
            fixture.presenter.setStatusIcons([IslandStatusIcon(id: "combined", content: .combined(image), tooltip: "Monitor")])
            let frame = try #require(fixture.presenter.compactFrame(for: fixture.screen, notices: []))
            let thickness = edge.isVertical ? frame.width : frame.height
            let expectedThickness = max(CGFloat(24), CGFloat(pointSize) + 8)
            #expect(thickness == expectedThickness)
            #expect(ScreenLayoutEngine.edgeDistance(of: frame, in: fixture.screen.frame, edge: edge)
                == min(120, expectedThickness * 3))
            #expect(coordinator.activeLayout?.collapsedFrame == frame)
            coordinator.updateCompactStatus(expandsForDetailedStatus: false)
            #expect(coordinator.activeLayout?.collapsedFrame.size == CGSize(width: 24, height: 24))
            #expect(ScreenLayoutEngine.edgeDistance(of: try #require(coordinator.activeLayout).collapsedFrame,
                in: fixture.screen.frame, edge: edge) == 72)
            fixture.presenter.publishCompactLayout(on: fixture.screen.displayID)
            #expect(coordinator.activeLayout?.collapsedFrame == frame, "A screen switch must republish the current icon dimensions")
            fixture.settings.settings.sideNoticesEnabled = true
            fixture.queue.enqueue(IslandNotice(id: "ai-active-placement", title: "Codex"), expiresAfter: nil)
            fixture.presenter.publishCompactLayout(on: fixture.screen.displayID)
            let activity = try #require(coordinator.activeLayout).collapsedFrame
            #expect((edge.isVertical ? activity.width : activity.height) == 32)
            #expect(ScreenLayoutEngine.edgeDistance(of: activity, in: fixture.screen.frame, edge: edge) == 96)
            fixture.queue.removeAll()
            fixture.presenter.publishCompactLayout(on: fixture.screen.displayID)
            #expect(coordinator.activeLayout?.collapsedFrame == frame)
            #expect(fixture.settings.settings.islandPlacement.inwardDistance == 120)
        }
        let stackedImage = try #require(SystemMonitorMenuBarImageRenderer.stacked(
            rows: ["C 20%", "M 2 GB/8 GB"], style: .compact))
        let stacked = IslandStatusIcon(id: "stacked", content: .stacked(image: stackedImage,
            readings: [.init(metric: .cpu, text: "20%"), .init(metric: .memory, text: "2 GB/8 GB")]), tooltip: "Monitors")
        fixture.presenter.setStatusIcons([stacked])
        let stackedFrame = try #require(coordinator.activeLayout).collapsedFrame
        let stackedThickness = edge.isVertical ? stackedFrame.width : stackedFrame.height
        #expect(stackedThickness == (edge.isVertical ? stackedImage.size.width + 8 : 32))
        #expect(ScreenLayoutEngine.edgeDistance(of: stackedFrame, in: fixture.screen.frame, edge: edge)
            == min(120, stackedThickness * 3))
        #expect(fixture.presenter.compactFrame(for: fixture.screen, notices: []) == stackedFrame)
        fixture.presenter.setStatusIcons([])
        #expect(coordinator.activeLayout?.collapsedFrame.size == CGSize(width: 24, height: 24))
        #expect(ScreenLayoutEngine.edgeDistance(of: try #require(coordinator.activeLayout).collapsedFrame,
            in: fixture.screen.frame, edge: edge) == 72)
        fixture.settings.flushPendingChanges()
        #expect(FeatureSettingsStore(defaults: fixture.defaults).settings.islandPlacement.inwardDistance == 120)
    }

    @Test @MainActor
    func activitiesAndTemporarySuppressionRestoreTheSameMonitorLayout() throws {
        let fixture = try IconFixture(edge: .left)
        defer { fixture.close() }
        fixture.presenter.setStatusIcons([IslandStatusIcon(id: "cpu", content: .metric(.cpu, text: "30%", image: nil, style: .detailed), tooltip: "CPU")])
        let idle = fixture.presenter.compactConfiguration(for: [], at: .now)
        #expect(idle.statusIconSize != nil)
        let notice = IslandNotice(id: "ai-active-test", title: "Codex")
        #expect(fixture.presenter.compactConfiguration(for: [notice], at: .now).statusIconSize == nil)
        #expect(fixture.presenter.compactConfiguration(for: [notice], at: .now, statusHidden: true) == idle)
        fixture.presenter.setVoiceRecording(true)
        #expect(fixture.presenter.compactConfiguration(for: [], at: .now).statusIconSize == nil)
        fixture.presenter.setVoiceRecording(false)
        #expect(fixture.presenter.compactConfiguration(for: [], at: .now) == idle)
        fixture.presenter.setTransientNoticePresented(true, message: "Done")
        #expect(fixture.presenter.compactConfiguration(for: [], at: .now).statusIconSize == nil)
        fixture.presenter.setTransientNoticePresented(false)
        fixture.presenter.setTransientNoticePresented(true)
        #expect(fixture.presenter.compactConfiguration(for: [], at: .now).statusIconSize == nil)
        fixture.presenter.setTransientNoticePresented(false)
        fixture.sweep.receive(previous: .running,
            task: AIProgressTask(id: "test", provider: .codex, title: "Test", progress: nil, status: .succeeded, updatedAt: .now),
            observedSince: .distantFuture, settings: fixture.settings.settings)
        #expect(fixture.sweep.current != nil)
        #expect(fixture.presenter.compactConfiguration(for: [], at: .now).statusIconSize == nil)
        fixture.sweep.cancel()
        #expect(fixture.presenter.compactConfiguration(for: [], at: .now) == idle)
        fixture.presenter.setScreenshotActive(true)
        fixture.presenter.setScreenshotActive(false)
        fixture.presenter.setIslandExpanded(true)
        fixture.presenter.setIslandExpanded(false)
        #expect(fixture.presenter.compactConfiguration(for: [], at: .now) == idle)
        fixture.settings.settings.statusIconDestination = .menuBar
        #expect(fixture.presenter.compactConfiguration(for: [], at: .now).statusIconSize == nil)
        fixture.settings.settings.statusIconDestination = .island
        #expect(fixture.presenter.compactConfiguration(for: [], at: .now) == idle)
        fixture.presenter.stop()
        fixture.presenter.setStatusIcons([])
        #expect(fixture.presenter.compactConfiguration(for: [], at: .now).statusIconSize == nil)
    }

    @MainActor
    private func blueProgress(_ actual: NSBitmapImageRep, baseline: NSBitmapImageRep,
                              x: ClosedRange<Int>, y: ClosedRange<Int>) throws -> Bool {
        for row in y {
            for column in x {
                let color = try #require(actual.colorAt(x: column, y: row)?.usingColorSpace(.deviceRGB))
                let previous = try #require(baseline.colorAt(x: column, y: row)?.usingColorSpace(.deviceRGB))
                if color.blueComponent > previous.blueComponent + 0.2,
                   color.blueComponent > color.redComponent + 0.2,
                   color.blueComponent > color.greenComponent + 0.2 {
                    return true
                }
            }
        }
        return false
    }

    @MainActor
    func renderOffscreen(_ content: some View, size: CGSize,
                                 inspect: (NSView) -> Void = { _ in }) async throws -> NSBitmapImageRep {
        let host = NSHostingView(rootView: content.frame(width: size.width, height: size.height).background(.black))
        host.sizingOptions = []
        let window = NSWindow(contentRect: CGRect(origin: CGPoint(x: 20000, y: 0), size: size),
            styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.alphaValue = 0
        window.contentView = host
        window.orderFrontRegardless()
        defer { window.close() }
        host.layoutSubtreeIfNeeded()
        host.displayIfNeeded()
        await withCheckedContinuation { continuation in
            DispatchQueue.main.async { continuation.resume() }
        }
        let cachedBitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: cachedBitmap)
        inspect(host)
        #expect(host.bounds.size == size && window.alphaValue == 0)
        return try #require(cachedBitmap.converting(to: .sRGB, renderingIntent: .default))
    }

    @Test @MainActor
    func cameraRoutesOnlyToTheMenuBarAndReturningToTheSideRestoresThePreference() throws {
        let fixture = try IconFixture(edge: .right)
        defer { fixture.close() }
        let icons = [IslandStatusIcon(id: "cpu", content: .metric(.cpu, text: "20%", image: nil, style: .detailed), tooltip: "CPU")]
        fixture.presenter.setStatusIcons(icons)
        let side = fixture.presenter.compactConfiguration(for: [], at: .now)
        #expect(side.statusIconSize != nil)
        fixture.settings.settings.islandPlacement = IslandPlacement()
        #expect(fixture.settings.settings.effectiveStatusIconDestination == .menuBar)
        #expect(fixture.presenter.compactConfiguration(for: [], at: .now).statusIconSize == nil)
        #expect(fixture.settings.settings.statusIconDestination == .island)
        fixture.settings.settings.islandPlacement = IslandPlacement(mode: .custom, edge: .right)
        #expect(fixture.presenter.compactConfiguration(for: [], at: .now) == side)
        fixture.settings.settings.islandLayoutStyle = .notch
        #expect(fixture.settings.settings.effectiveStatusIconDestination == .menuBar)
        #expect(fixture.presenter.compactConfiguration(for: [], at: .now).statusIconSize == nil)
        fixture.settings.settings.islandLayoutStyle = .pill
        fixture.presenter.setStatusIcons([IslandStatusIcon(id: "network", content: .metric(.network,
            text: String(repeating: "1", count: 1000), image: nil, style: .detailed), tooltip: "Network")])
        let frame = try #require(fixture.presenter.compactFrame(for: fixture.screen, notices: []))
        #expect(frame.height == ScreenLayoutConfiguration.quickActionRowWidth)
        #expect(fixture.screen.frame.contains(frame))
    }

    @MainActor
    final class IconFixture {
        let suite = "StatusIconPresentation.\(UUID().uuidString)"
        let defaults: UserDefaults
        let settings: FeatureSettingsStore
        let language: AppLanguageStore
        let queue = SideNoticeQueue()
        let sweep = AIResultSweepController()
        let media = NowPlayingService(loadLyrics: { _, _, _ in LyricsSearchResult(lyrics: nil, artistName: nil) })
        let downloads = BrowserDownloadMonitor(directories: [], eventPaths: [])
        var reducesMotion = false
        let screen = ScreenSnapshot(displayID: 7, frame: CGRect(x: 20000, y: 0, width: 1440, height: 900),
            visibleFrame: CGRect(x: 20000, y: 0, width: 1440, height: 876))
        lazy var presenter = SideNoticePresenter(queue: queue, resultSweep: sweep, media: media,
            pomodoro: PomodoroService(notificationRequestHandler: { _ in }, defaults: defaults),
            browserDownloads: downloads, settingsStore: settings, languageStore: language, isScreenLocked: true,
            reduceMotion: { [unowned self] in reducesMotion },
            screenSnapshotProvider: { [unowned self] in [screen] })

        init(edge: IslandEdge) throws {
            defaults = try #require(UserDefaults(suiteName: suite))
            settings = FeatureSettingsStore(defaults: defaults)
            language = AppLanguageStore(defaults: defaults)
            settings.settings.islandLayoutStyle = .pill
            settings.settings.islandPlacement = IslandPlacement(mode: .custom, edge: edge)
            settings.settings.statusIconDestination = .island
            settings.settings.sideNoticesEnabled = false
            settings.settings.islandShowMoreInformation = false
            settings.settings.islandNotchBackground = .black
        }

        func close() {
            presenter.stop()
            queue.removeAll()
            sweep.cancel()
            settings.flushPendingChanges()
            defaults.removePersistentDomain(forName: suite)
        }
    }
}
