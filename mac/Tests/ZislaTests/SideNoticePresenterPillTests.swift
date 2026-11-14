import AppKit
import Foundation
import SwiftUI
import Testing
import ZislaCore
import ZislaKit
@testable import ZislaKit
@testable import Zisla

@MainActor
// Pixel velocity sampling needs an uncontended AppKit run loop, beyond MainActor isolation.
@Suite(.serialized)
struct SideNoticePresenterPillTests {
    @Test(arguments: IslandEdge.allCases, [AIProgressStatus.succeeded, .failed, .error])
    func resultSweepsSizeToAIContentAndRestoreFloatingInformation(edge: IslandEdge, status: AIProgressStatus) throws {
        let fixture = try Fixture(edge: edge)
        defer { fixture.close() }
        fixture.settings.settings.islandShowMoreInformation = true
        fixture.settings.settings.mediaCompactStyle = .detailed
        let task = AIProgressTask(id: "floating-result", provider: .codex, title: "Task",
            progress: nil, status: status, updatedAt: fixture.date)
        fixture.queue.enqueue(IslandNotice(id: AIMascotLibrary.activeNoticeID(for: task), title: task.title),
            expiresAfter: nil)
        fixture.queue.enqueue(IslandNotice(id: "media-active-fixture", title: "Music"), expiresAfter: nil)
        let icons = [
            IslandStatusIcon(id: "cpu", content: .metric(.cpu, text: "20%", image: nil, style: .detailed), tooltip: "CPU"),
        ]
        fixture.presenter.setStatusIcons(icons)
        let notices = fixture.queue.left + fixture.queue.right
        let initial = try #require(fixture.presenter.compactFrame(for: fixture.screen, notices: notices, at: fixture.date))

        fixture.sweep.receive(previous: .running, task: task, observedSince: .distantPast, settings: fixture.settings.settings)
        let sweep = try #require(fixture.sweep.current)
        let sweeping = try #require(fixture.presenter.compactFrame(for: fixture.screen,
            notices: fixture.sweep.presentationNotices(from: notices), at: fixture.date))

        let expected = edge.isVertical ? CGSize(width: 32, height: 68) : CGSize(width: 60, height: 32)
        #expect(sweeping.size == expected, "A result sweep must fit the visible AI icon and count without reserving hidden information")
        #expect((edge.isVertical ? sweeping.height : sweeping.width) < (edge.isVertical ? initial.height : initial.width))
        fixture.presenter.setStatusIcons(icons)
        #expect(fixture.presenter.compactFrame(for: fixture.screen,
            notices: fixture.sweep.presentationNotices(from: notices), at: fixture.date) == sweeping)
        var publishedConfiguration = fixture.settings.settings.islandScreenConfiguration
        fixture.presenter.onCompactLayoutChanged = { _, detailed, length, sideWidth, size in
            publishedConfiguration.expandsForDetailedStatus = detailed
            publishedConfiguration.compactStatusLength = length
            publishedConfiguration.compactStatusSideWidth = sideWidth
            publishedConfiguration.statusIconSize = size
        }
        fixture.presenter.publishCompactLayout(on: fixture.screen.displayID)
        #expect(ScreenLayoutEngine(configuration: publishedConfiguration).layout(for: fixture.screen).collapsedFrame == sweeping,
                "The main island and status surface must shrink to the same AI content frame")
        fixture.sweep.finish(id: sweep.id)
        fixture.presenter.setStatusIcons(icons)
        #expect(fixture.presenter.compactFrame(for: fixture.screen, notices: notices, at: fixture.date) == initial)
    }

    @Test(arguments: IslandEdge.allCases)
    func queuedResultsKeepOnlyAIContentAfterClientsExitAndCancellationRestoresIdle(edge: IslandEdge) throws {
        let fixture = try Fixture(edge: edge)
        defer { fixture.close() }
        fixture.settings.settings.islandShowMoreInformation = true
        fixture.settings.settings.mediaCompactStyle = .detailed
        let firstTask = AIProgressTask(id: "finished", provider: .gpt, title: "Task",
            progress: nil, status: .succeeded, updatedAt: fixture.date)
        fixture.queue.enqueue(IslandNotice(id: AIMascotLibrary.activeNoticeID(for: firstTask), title: firstTask.title),
            expiresAfter: nil)
        fixture.queue.enqueue(IslandNotice(id: "media-active-fixture", title: "Music"), expiresAfter: nil)
        fixture.presenter.setStatusIcons([])
        let initial = try #require(fixture.presenter.compactFrame(for: fixture.screen,
            notices: fixture.queue.left + fixture.queue.right, at: fixture.date))

        fixture.queue.remove(id: AIMascotLibrary.activeNoticeID(for: firstTask))
        fixture.sweep.receive(previous: .running, task: firstTask, observedSince: .distantPast, settings: fixture.settings.settings)
        let first = try #require(fixture.sweep.current)
        fixture.queue.removeAll()
        fixture.presenter.setStatusIcons([])
        let sweeping = try #require(fixture.presenter.compactFrame(for: fixture.screen,
            notices: fixture.sweep.presentationNotices(from: []), at: fixture.date))
        let expected = edge.isVertical ? CGSize(width: 32, height: 68) : CGSize(width: 60, height: 32)
        #expect(sweeping.size == expected)
        #expect(sweeping != initial, "A vanished information row must not leave empty space during a result sweep")

        let secondTask = AIProgressTask(id: "failed", provider: .codex, title: "Task",
            progress: nil, status: .failed, updatedAt: fixture.date)
        fixture.sweep.receive(previous: .running, task: secondTask, observedSince: .distantPast, settings: fixture.settings.settings)
        fixture.sweep.finish(id: first.id)
        let second = try #require(fixture.sweep.current)
        fixture.presenter.setStatusIcons([])
        #expect(fixture.presenter.compactFrame(for: fixture.screen,
            notices: fixture.sweep.presentationNotices(from: []), at: fixture.date) == sweeping)

        fixture.sweep.cancel()
        fixture.sweep.finish(id: second.id)
        fixture.presenter.setStatusIcons([])
        let idle = try #require(fixture.presenter.compactFrame(for: fixture.screen, notices: [], at: fixture.date))
        #expect(idle.size == CGSize(width: 24, height: 24), "Cancelling playback must restore the idle circle")
        fixture.sweep.receive(previous: .running, task: secondTask, observedSince: .distantPast, settings: fixture.settings.settings)
        fixture.presenter.setStatusIcons([])
        let next = try #require(fixture.presenter.compactFrame(for: fixture.screen,
            notices: fixture.sweep.presentationNotices(from: []), at: fixture.date))
        #expect(next.size == expected, "A fresh sweep must fit only its current AI icon and task count")
    }

    @Test(arguments: IslandEdge.allCases)
    func hiddenActivityResultsSizeToVisibleAIContentAndRestoreHiddenState(edge: IslandEdge) throws {
        let fixture = try Fixture(edge: edge)
        defer { fixture.close() }
        fixture.settings.settings.islandShowMoreInformation = true
        fixture.settings.settings.activityNoticeDisplayDuration = .threeSeconds
        let task = AIProgressTask(id: "hidden-result", provider: .codex, title: "Task",
            progress: nil, status: .succeeded, updatedAt: fixture.date)
        let notice = IslandNotice(id: AIMascotLibrary.activeNoticeID(for: task), title: task.title)
        let state = SideNoticeDisplayState()
        _ = SideNoticePresenter.updateCompactVisibility(notices: [notice], settings: fixture.settings.settings, displayState: state)
        state.compactStatusHidden = true
        let hidden = try #require(fixture.presenter.compactFrame(for: fixture.screen,
            notices: [notice], at: fixture.date, statusHidden: state.compactStatusHidden))
        #expect(hidden.size == CGSize(width: 24, height: 24))

        fixture.sweep.receive(previous: .running, task: task, observedSince: .distantPast, settings: fixture.settings.settings)
        let sweep = try #require(fixture.sweep.current)
        let notices = fixture.sweep.presentationNotices(from: [notice])
        #expect(!SideNoticePresenter.updateCompactVisibility(notices: notices, settings: fixture.settings.settings, displayState: state))
        #expect(state.compactStatusHidden)
        let sweeping = try #require(fixture.presenter.compactFrame(for: fixture.screen,
            notices: notices, at: fixture.date, statusHidden: state.compactStatusHidden))
        #expect(sweeping.size == (edge.isVertical ? CGSize(width: 32, height: 68) : CGSize(width: 60, height: 32)),
                "A result sweep must fit its visible AI content even when the same activity was hidden")
        #expect(fixture.presenter.compactFrame(for: fixture.screen, notices: notices, at: fixture.date) == sweeping)
        #expect(fixture.presenter.compactConfiguration(for: notices, at: fixture.date,
            statusHidden: state.compactStatusHidden).statusIconSize == nil)

        fixture.sweep.finish(id: sweep.id)
        #expect(state.compactStatusHidden)
        #expect(fixture.presenter.compactFrame(for: fixture.screen, notices: [notice],
            at: fixture.date, statusHidden: state.compactStatusHidden) == hidden,
                "Finishing a result sweep must restore the activity's hidden frame")
    }

    @Test(arguments: IslandEdge.allCases)
    func aFirstResultWithoutAPreviousLayoutUsesNormalAISizing(edge: IslandEdge) throws {
        let fixture = try Fixture(edge: edge)
        defer { fixture.close() }
        let task = AIProgressTask(id: "first-result", provider: .codex, title: "Task",
            progress: nil, status: .succeeded, updatedAt: fixture.date)
        fixture.sweep.receive(previous: .running, task: task, observedSince: .distantPast, settings: fixture.settings.settings)
        let frame = try #require(fixture.presenter.compactFrame(for: fixture.screen,
            notices: fixture.sweep.presentationNotices(from: []), at: fixture.date))
        #expect((edge.isVertical ? frame.width : frame.height) == 32)
        #expect((edge.isVertical ? frame.height : frame.width) == (edge.isVertical ? 68 : 60))
    }

    @Test(arguments: [IslandLayoutStyle.pill, .notch])
    func switchingToCameraOrNotchDoesNotRetainACustomResultFrame(style: IslandLayoutStyle) throws {
        let fixture = try Fixture(edge: .top)
        defer { fixture.close() }
        fixture.settings.settings.islandShowMoreInformation = true
        fixture.settings.settings.mediaCompactStyle = .detailed
        fixture.settings.settings.mediaShowLyricsAndInfo = true
        fixture.queue.enqueue(IslandNotice(id: "media-active-fixture", title: "Music"), expiresAfter: nil)
        fixture.media.publishSnapshot(NowPlayingSnapshot(title: String(repeating: "Long title ", count: 8), artist: "Artist", album: nil,
            artworkData: nil, duration: 60, elapsedTime: 0, timestamp: fixture.date, isPlaying: false))
        fixture.presenter.setStatusIcons([IslandStatusIcon(id: "cpu",
            content: .metric(.cpu, text: String(repeating: "1234567890", count: 8), image: nil, style: .detailed), tooltip: "CPU")])
        let initial = try #require(fixture.presenter.compactFrame(for: fixture.screen,
            notices: fixture.queue.left + fixture.queue.right, at: fixture.date))
        #expect(initial.width > ScreenLayoutConfiguration.cameraPillMaximumWidth)
        let task = AIProgressTask(id: "switched-result", provider: .codex, title: "Task",
            progress: nil, status: .succeeded, updatedAt: fixture.date)
        fixture.sweep.receive(previous: .running, task: task, observedSince: .distantPast, settings: fixture.settings.settings)
        fixture.settings.settings.islandLayoutStyle = style
        fixture.settings.settings.islandPlacement = IslandPlacement(mode: style == .pill ? .camera : .custom)
        let notices = fixture.sweep.presentationNotices(from: [])
        let frame = try #require(fixture.presenter.compactFrame(for: fixture.screen, notices: notices, at: fixture.date))
        if style == .pill {
            #expect(frame.size == CGSize(width: 200, height: 32))
        } else {
            let engine = SideNoticeLayoutEngine()
            #expect(frame == engine.compactBarFrame(for: fixture.screen, notices: notices, settings: fixture.settings.settings))
        }
    }

    @Test
    func changingTheEdgeDuringPlaybackDoesNotRotateTheOldDimensions() throws {
        let fixture = try Fixture(edge: .left)
        defer { fixture.close() }
        fixture.settings.settings.islandShowMoreInformation = true
        fixture.presenter.setStatusIcons([IslandStatusIcon(id: "cpu",
            content: .metric(.cpu, text: "20%", image: nil, style: .detailed), tooltip: "CPU")])
        let task = AIProgressTask(id: "edge-change", provider: .codex, title: "Task",
            progress: nil, status: .succeeded, updatedAt: fixture.date)
        fixture.sweep.receive(previous: .running, task: task, observedSince: .distantPast, settings: fixture.settings.settings)
        fixture.settings.settings.islandPlacement.edge = .top
        let frame = try #require(fixture.presenter.compactFrame(for: fixture.screen,
            notices: fixture.sweep.presentationNotices(from: []), at: fixture.date))
        #expect(frame.size == CGSize(width: 60, height: 32))
    }

    @Test(arguments: [IslandLayoutStyle.pill, .notch])
    func startingCustomPlacementDuringPlaybackUsesNormalAISizing(style: IslandLayoutStyle) throws {
        let fixture = try Fixture(edge: .top)
        defer { fixture.close() }
        fixture.settings.settings.islandShowMoreInformation = true
        fixture.settings.settings.islandLayoutStyle = style
        fixture.settings.settings.islandPlacement = IslandPlacement()
        let task = AIProgressTask(id: "placement-change", provider: .codex, title: "Task",
            progress: nil, status: .succeeded, updatedAt: fixture.date)
        let notice = IslandNotice(id: AIMascotLibrary.activeNoticeID(for: task), title: task.title)
        fixture.queue.enqueue(notice, expiresAfter: nil)
        fixture.presenter.setStatusIcons([])
        fixture.sweep.receive(previous: .running, task: task, observedSince: .distantPast, settings: fixture.settings.settings)
        fixture.settings.settings.islandLayoutStyle = .pill
        fixture.settings.settings.islandPlacement = IslandPlacement(mode: .custom)
        let frame = try #require(fixture.presenter.compactFrame(for: fixture.screen,
            notices: fixture.sweep.presentationNotices(from: [notice]), at: fixture.date))
        #expect(frame.size == CGSize(width: 60, height: 32))
    }

    @Test(arguments: IslandEdge.allCases)
    func compactResultFramesRenderOnlyAIAtItsExistingIconSize(edge: IslandEdge) async throws {
        let fixture = try Fixture(edge: edge)
        defer { fixture.close() }
        fixture.screen.frame.origin.x = 20_000
        fixture.screen.visibleFrame.origin.x = 20_000
        fixture.reducesMotion = true
        fixture.settings.settings.islandShowMoreInformation = true
        fixture.settings.settings.islandNotchBackground = .black
        fixture.settings.settings.collapsedProgressGlowEnabled = false
        fixture.settings.settings.mediaCompactStyle = .detailed
        let host = try activeHost(fixture)
        let icons = [IslandStatusIcon(id: "cpu",
            content: .metric(.cpu, text: "20%", image: nil, style: .detailed), tooltip: "CPU")]
        let task = AIProgressTask(id: "rendered-result", provider: .gpt, title: "Task",
            progress: nil, status: .succeeded, updatedAt: fixture.date)
        fixture.queue.enqueue(IslandNotice(id: AIMascotLibrary.activeNoticeID(for: task), title: task.title),
            expiresAfter: nil)
        fixture.queue.enqueue(IslandNotice(id: "media-active-fixture", title: "Music"), expiresAfter: nil)
        fixture.presenter.setStatusIcons(icons)
        let initial = try #require(host.rootView.content.displayState.compactLayout).frame

        fixture.sweep.receive(previous: .running, task: task, observedSince: .distantPast, settings: fixture.settings.settings)
        fixture.presenter.setStatusIcons(icons)
        let view = host.rootView.content
        let sweeping = try #require(view.displayState.compactLayout).frame
        #expect(sweeping.size == (edge.isVertical ? CGSize(width: 32, height: 68) : CGSize(width: 60, height: 32)))
        #expect(sweeping != initial, "The AI-only result must not retain the hidden information frame")
        #expect(view.displayState.statusIcons.isEmpty, "The result sweep must keep the monitor strip hidden")
        #expect(view.selectedCompactStatusPriority == .aiActivity)
        let presentation = try #require(SideNoticeLayoutEngine().compactPillPresentations(
            for: fixture.sweep.presentationNotices(from: fixture.queue.left + fixture.queue.right),
            settings: fixture.settings.settings).first)
        let thickness = CompactPillStatusPresentation.minimumThickness
        let expected = CompactPillStatusContent(presentation: presentation, text: presentation.text, edge: edge,
            visualizationStyle: fixture.settings.settings.mediaVisualizationStyle, item: nil, date: fixture.date)
            .frame(width: edge.isVertical ? thickness : nil, height: edge.isVertical ? nil : thickness)
            .frame(width: sweeping.width, height: sweeping.height)
            .environment(\.colorScheme, .dark)
            .environment(\.layoutDirection, .leftToRight)
        let actualPixels = try await renderOffscreen(view.statusBarContent(at: fixture.date)
            .environment(\._accessibilityReduceMotion, true), size: sweeping.size)
        let expectedPixels = try await renderOffscreen(expected
            .environment(\._accessibilityReduceMotion, true), size: sweeping.size)
        var foregroundPixels = 0
        var differingPixels = 0
        for x in 0..<actualPixels.pixelsWide {
            for y in 0..<actualPixels.pixelsHigh {
                let actual = try #require(actualPixels.colorAt(x: x, y: y))
                let expected = try #require(expectedPixels.colorAt(x: x, y: y))
                let isForeground = min(actual.redComponent, actual.greenComponent, actual.blueComponent) > 0.5
                let expectedForeground = min(expected.redComponent, expected.greenComponent, expected.blueComponent) > 0.5
                if isForeground { foregroundPixels += 1 }
                if isForeground != expectedForeground { differingPixels += 1 }
            }
        }
        #expect(foregroundPixels > 30, "The compact frame must still render its AI icon and count")
        #expect(differingPixels == 0, "Only standard-sized AI content may appear within the compact frame")
    }

    @Test(arguments: [IslandLayoutStyle.pill, .notch])
    func cameraAIContentMovesTenPointsInwardWithoutResizingTheIcons(style: IslandLayoutStyle) async throws {
        let fixture = try Fixture(edge: .top)
        defer { fixture.close() }
        fixture.settings.settings.islandLayoutStyle = .notch
        fixture.settings.settings.islandPlacement = IslandPlacement()
        fixture.settings.settings.islandNotchBackground = .black
        fixture.queue.enqueue(IslandNotice(id: "ai-active-gpt-fixture", title: "GPT"), expiresAfter: nil)
        let state = SideNoticeDisplayState()
        state.placementMode = .camera
        state.islandEdge = .top
        state.compactWingHeight = 32
        state.compactBarCenterInset = 185
        let view = CompactStatusBarView(queue: fixture.queue, displayState: state, media: fixture.media,
            browserDownloads: fixture.downloads, settingsStore: fixture.settings, resultSweep: fixture.sweep,
            pomodoro: PomodoroService(notificationRequestHandler: { _ in }, defaults: fixture.defaults), onStatusHidden: {})
        let size = CGSize(width: 265, height: 32)
        let reference = try await renderOffscreen(view.statusBarContent(at: fixture.date), size: size)
        let referenceBounds = try foregroundBounds(reference, scale: CGFloat(reference.pixelsWide) / size.width)
        fixture.settings.settings.islandLayoutStyle = style
        let bitmap = try await renderOffscreen(view.statusBarContent(at: fixture.date), size: size)
        let scale = CGFloat(bitmap.pixelsWide) / size.width
        let bounds = try foregroundBounds(bitmap, scale: scale)
        let movement: CGFloat = style == .pill ? 10 : 0
        #expect(abs(bounds[0].minX - referenceBounds[0].minX - movement) <= 0.5,
                "Only camera pills move the provider icon inward by 10pt")
        #expect(abs(referenceBounds[1].maxX - bounds[1].maxX - movement) <= 0.5,
                "The task count moves inward by the same 10pt")
        #expect(bounds[0].maxX <= 40 && bounds[1].minX >= 225,
                "Both sides must remain outside the real 185pt hardware occlusion")
        #expect(abs(bounds[0].width - 22) <= 1, "The provider icon retains its original size")
        #expect(bounds[1].size == referenceBounds[1].size, "The count retains the original font and size")
    }

    @Test(arguments: [CGFloat(120), 185, 200])
    func cameraDetailedMediaKeepsTheShortCenterClearForLongTitlesAndLyrics(centerWidth: CGFloat) async throws {
        let fixture = try Fixture(edge: .top)
        defer { fixture.close() }
        fixture.settings.settings.islandPlacement = IslandPlacement()
        fixture.settings.settings.islandNotchBackground = .black
        fixture.settings.settings.mediaCompactStyle = .detailed
        fixture.settings.settings.mediaShowLyricsAndInfo = true
        let title = String(repeating: "Long title ", count: 30)
        let notice = IslandNotice(id: "media-active-camera", title: title, side: .left)
        fixture.media.publishSnapshot(NowPlayingSnapshot(title: title, artist: "Artist", album: nil,
            artworkData: nil, duration: 60, elapsedTime: 0, timestamp: fixture.date, isPlaying: true,
            lyrics: SyncedLyrics(lines: [.init(time: 0, text: String(repeating: "Lyrics ", count: 30))])))
        fixture.queue.enqueue(notice, expiresAfter: nil)
        let state = SideNoticeDisplayState()
        state.placementMode = .camera
        state.islandEdge = .top
        state.compactWingHeight = 32
        state.compactBarCenterInset = centerWidth
        let view = CompactStatusBarView(queue: fixture.queue, displayState: state, media: fixture.media,
            browserDownloads: fixture.downloads, settingsStore: fixture.settings, resultSweep: fixture.sweep,
            pomodoro: PomodoroService(notificationRequestHandler: { _ in }, defaults: fixture.defaults), onStatusHidden: {})
        let width = max(240, centerWidth + 80)
        let sideWidth = (width - centerWidth) / 2
        let bitmap = try await renderOffscreen(view.statusBarContent(at: fixture.date), size: CGSize(width: width, height: 32))
        let scale = CGFloat(bitmap.pixelsWide) / width
        var centerPixels = 0
        for x in Int(sideWidth * scale)..<Int((width - sideWidth) * scale) {
            for y in 0..<bitmap.pixelsHigh {
                let color = try #require(bitmap.colorAt(x: x, y: y))
                if max(color.redComponent, color.greenComponent, color.blueComponent) > 0.4 { centerPixels += 1 }
            }
        }
        #expect(centerPixels == 0, "Long media text must not overflow the camera slot in a 240pt detailed pill")
    }

    @Test(arguments: [CGFloat(0), 16, 200])
    func cameraPanelsReserveTheShortCenterAndKeepTheExistingTwoWings(reservedWidth: CGFloat) async throws {
        let fixture = try Fixture(edge: .top)
        defer { fixture.close() }
        fixture.settings.settings.islandPlacement = IslandPlacement()
        fixture.settings.settings.islandNotchBackground = .black
        fixture.screen.visibleFrame.size.height = fixture.screen.frame.height - 44
        if reservedWidth > 0 {
            let frame = fixture.screen.frame
            fixture.screen.safeAreaInsets = ScreenInsets(top: 44)
            fixture.screen.auxiliaryTopLeftArea = CGRect(x: frame.minX, y: frame.maxY - 44,
                width: frame.width / 2 - reservedWidth / 2, height: 44)
            fixture.screen.auxiliaryTopRightArea = CGRect(x: frame.midX + reservedWidth / 2, y: frame.maxY - 44,
                width: frame.width / 2 - reservedWidth / 2, height: 44)
        }
        fixture.presenter.setScreenLocked(false)
        let host = try #require(NSApp.windows.compactMap {
            $0.contentView as? NSHostingView<AppLanguageEnvironment<CompactStatusBarView>>
        }.first { $0.rootView.content.settingsStore === fixture.settings })
        let state = host.rootView.content.displayState
        let centerWidth = max(120, reservedWidth)
        #expect(state.compactBarCenterInset == centerWidth)
        #expect(host.window?.frame.size == CGSize(width: centerWidth + 80, height: 32))
        for count in [1, 2, 3] {
            fixture.queue.removeAll()
            for index in 0..<count {
                fixture.queue.enqueue(IslandNotice(id: "ai-active-openai-\(index)", title: "OpenAI"), expiresAfter: nil)
            }
            fixture.presenter.setDisplayIDs([7])
            fixture.presenter.setStatusIcons([])
            #expect(state.compactBarCenterInset == centerWidth)
            #expect(host.window?.frame.size == CGSize(width: centerWidth + 80, height: 32))
            let bitmap = try await renderOffscreen(host.rootView.content.statusBarContent(at: fixture.date),
                size: CGSize(width: centerWidth + 80, height: 32))
            let wingWidth = Int(40 * CGFloat(bitmap.pixelsWide) / (centerWidth + 80))
            var wingPixels = [0, 0]
            var centerPixels = 0
            for x in 0..<bitmap.pixelsWide {
                for y in 0..<bitmap.pixelsHigh {
                    let color = try #require(bitmap.colorAt(x: x, y: y))
                    if max(color.redComponent, color.greenComponent, color.blueComponent) > 0.4 {
                        if x < wingWidth { wingPixels[0] += 1 }
                        else if x >= bitmap.pixelsWide - wingWidth { wingPixels[1] += 1 }
                        else { centerPixels += 1 }
                    }
                }
            }
            #expect(wingPixels.allSatisfy { $0 > 10 }, "The icon and task count must stay in their original two wings")
            #expect(centerPixels == 0, "The short camera slot must remain clear between both wings")
        }
        fixture.settings.settings.islandPlacement = IslandPlacement(mode: .custom, edge: .left)
        fixture.presenter.setStatusIcons([])
        #expect(state.compactBarCenterInset == 0)
        #expect(try #require(host.window).frame.width == 32)
        fixture.settings.settings.islandLayoutStyle = .notch
        fixture.presenter.setStatusIcons([])
        #expect(state.compactBarCenterInset == reservedWidth)
    }

    @Test
    func cameraNormalActivitiesKeepTheShortDefaultBeforeAndAfterDetails() throws {
        let fixture = try Fixture(edge: .top)
        defer { fixture.close() }
        fixture.settings.settings.islandPlacement = IslandPlacement()
        fixture.settings.settings.mediaCompactStyle = .compact
        let idle = try #require(fixture.presenter.compactFrame(for: fixture.screen, notices: [], at: fixture.date))
        #expect(idle.size == CGSize(width: 200, height: 32))
        let ai = (0..<3).map { IslandNotice(id: "ai-active-codex-\($0)", title: "Codex") }
        let ordinary = [IslandNotice(id: "media-active-camera", title: "Music"),
                        IslandNotice(id: "browser-download-camera", title: "Download", progress: 0.4),
                        IslandNotice(id: "video-download-camera", title: "Download", progress: 0.4),
                        IslandNotice(id: "voice-processing-camera", title: "Voice", detail: "Processing"),
                        IslandNotice(id: "screen-recording-operation-camera", title: "Recording", progress: 0.4)]
        for notices in [Array(ai.prefix(1)), Array(ai.prefix(2)), ai] + ordinary.map({ [$0] }) {
            #expect(try #require(fixture.presenter.compactFrame(for: fixture.screen, notices: notices,
                at: fixture.date)) == idle)
        }
        fixture.settings.settings.mediaCompactStyle = .detailed
        let long = try #require(fixture.presenter.compactFrame(for: fixture.screen,
            notices: [ordinary[0]], at: fixture.date))
        #expect(long.size == CGSize(width: 240, height: 32))
        #expect(long.midX == idle.midX && long.midY == idle.midY)
        #expect(try #require(fixture.presenter.compactFrame(for: fixture.screen, notices: [], at: fixture.date)) == idle)
        #expect(try #require(fixture.presenter.compactFrame(for: fixture.screen, notices: [ordinary[0]],
            at: fixture.date, statusHidden: true)) == idle)
    }

    @Test(arguments: IslandEdge.allCases)
    func eachLiveLyricUsesItsNaturalFrameAndReturnsFromLongToShortWithoutACache(edge: IslandEdge) throws {
        let fixture = try Fixture(edge: edge)
        defer { fixture.close() }
        let notice = IslandNotice(id: "media-active-left", title: "Music", side: .left,
            metadata: ["compactLyric": "旧内容"])
        let base = fixture.date
        var snapshot = NowPlayingSnapshot(title: "fixture", artist: "artist", album: nil, artworkData: nil,
            duration: 60, elapsedTime: 0, timestamp: base, isPlaying: true,
            lyrics: SyncedLyrics(lines: [.init(time: 0, text: "短"), .init(time: 10, text: "长一些的歌词"),
                                        .init(time: 20, text: "短")]))
        fixture.media.publishSnapshot(snapshot)
        fixture.settings.settings.mediaCompactStyle = .detailed
        let first = try #require(fixture.presenter.compactFrame(for: fixture.screen, notices: [notice], at: base))
        let long = try #require(fixture.presenter.compactFrame(for: fixture.screen, notices: [notice], at: base.addingTimeInterval(10)))
        let returned = try #require(fixture.presenter.compactFrame(for: fixture.screen, notices: [notice], at: base.addingTimeInterval(20)))
        #expect(returned == first)
        #expect((edge.isVertical ? long.height : long.width) > (edge.isVertical ? first.height : first.width))
        let configuration = fixture.presenter.compactConfiguration(for: [notice], at: base.addingTimeInterval(10))
        #expect(configuration.compactStatusLength == (edge.isVertical ? long.height : long.width))
        #expect(notice.metadata?["compactLyric"] == "旧内容")
        snapshot.isPlaying = false
        fixture.media.publishSnapshot(snapshot)
        fixture.settings.settings.mediaShowLyricsAndInfo = false
        let paused = fixture.presenter.compactConfiguration(for: [notice], at: base)
        #expect(paused.compactStatusLength == 78)
        fixture.settings.settings.mediaVisualizationStyle = .glow
        let compact = fixture.presenter.compactConfiguration(for: [notice], at: base)
        #expect(compact.compactStatusLength == 48)
    }

    @Test(arguments: IslandEdge.allCases, [MediaVisualizationStyle.waveform, .glow])
    func lyricPlaybackProgressKeepsTheCurrentLineFrameAndCapsLongLines(
        edge: IslandEdge, visualizationStyle: MediaVisualizationStyle
    ) throws {
        let fixture = try Fixture(edge: edge)
        defer { fixture.close() }
        fixture.settings.settings.mediaCompactStyle = .detailed
        fixture.settings.settings.mediaShowLyricsAndInfo = true
        fixture.settings.settings.mediaVisualizationStyle = visualizationStyle
        let notice = IslandNotice(id: "media-active-progress", title: "Music",
            metadata: ["compactLyric": "旧内容"])
        let lyrics = SyncedLyrics(lines: [.init(time: 0, text: "短"),
            .init(time: 10, text: String(repeating: "长", count: 100)),
            .init(time: 20, text: String(repeating: "长", count: 1000)), .init(time: 30, text: "短")])
        let snapshot = NowPlayingSnapshot(title: "Track", artist: "Artist", album: nil, artworkData: nil,
            duration: 40, elapsedTime: 0, timestamp: fixture.date, isPlaying: true, lyrics: lyrics)
        fixture.media.publishSnapshot(snapshot)
        let short = try #require(fixture.presenter.compactFrame(for: fixture.screen, notices: [notice], at: fixture.date))
        let long = try #require(fixture.presenter.compactFrame(for: fixture.screen, notices: [notice],
            at: fixture.date.addingTimeInterval(10)))
        let maximumLength: CGFloat = visualizationStyle == .waveform ? 252 : 222
        #expect((edge.isVertical ? long.height : long.width) == maximumLength)
        #expect(maximumLength <= ScreenLayoutConfiguration.quickActionRowWidth)
        #expect((edge.isVertical ? short.height : short.width) < maximumLength)
        #expect(short.midX == long.midX && short.midY == long.midY)
        for elapsed in [0.0, 2.5, 5, 7.5, 9.999] {
            #expect(fixture.presenter.compactFrame(for: fixture.screen, notices: [notice],
                at: fixture.date.addingTimeInterval(elapsed)) == short,
                "A short lyric's playback progress cannot resize the island")
        }
        for elapsed in [10.0, 12.5, 15, 17.5, 19.999, 20, 25, 29.999] {
            let sampledDate = fixture.date.addingTimeInterval(elapsed)
            #expect(fixture.presenter.compactFrame(for: fixture.screen, notices: [notice], at: sampledDate) == long,
                    "Long lyrics may only move inside the bounded frame")
            #expect(fixture.presenter.compactConfiguration(for: [notice], at: sampledDate).compactStatusLength == maximumLength)
        }
        #expect(fixture.presenter.compactFrame(for: fixture.screen, notices: [notice],
            at: fixture.date.addingTimeInterval(30)) == short,
            "Switching back to a short line restores its natural length")
    }

    @Test
    func cameraDetailsUseTheShorterFrameAndNotchSizingStaysUnchanged() throws {
        let fixture = try Fixture(edge: .top)
        defer { fixture.close() }
        let notice = IslandNotice(id: "media-active-left", title: "Music", side: .left)
        fixture.settings.settings.mediaCompactStyle = .detailed
        fixture.settings.settings.islandPlacement = IslandPlacement()
        let camera = try #require(fixture.presenter.compactFrame(for: fixture.screen, notices: [notice], at: fixture.date))
        #expect(camera.midX == fixture.screen.frame.midX)
        #expect(camera.midY == fixture.screen.frame.maxY - 18)
        #expect(camera.size == CGSize(width: 240, height: 32))
        fixture.settings.settings.islandLayoutStyle = .notch
        #expect(fixture.presenter.compactFrame(for: fixture.screen, notices: [notice], at: fixture.date)
            == SideNoticeLayoutEngine().compactBarFrame(for: fixture.screen, notices: [notice], settings: fixture.settings.settings))
    }

    @Test
    func cameraIdleAndHiddenContentLeaveNoStatusLengthAndRestoreAfterRemoval() throws {
        let fixture = try Fixture(edge: .top)
        defer { fixture.close() }
        fixture.settings.settings.islandPlacement = IslandPlacement()
        let snapshot = ScreenSnapshot(displayID: 7,
            frame: CGRect(x: 0, y: 0, width: 1512, height: 982),
            visibleFrame: CGRect(x: 0, y: 0, width: 1512, height: 938),
            safeAreaInsets: ScreenInsets(top: 44),
            auxiliaryTopLeftArea: CGRect(x: 0, y: 938, width: 656, height: 44),
            auxiliaryTopRightArea: CGRect(x: 856, y: 938, width: 656, height: 44))
        let idleConfiguration = fixture.presenter.compactConfiguration(for: [], at: fixture.date)
        #expect(idleConfiguration.compactStatusLength == nil)
        let idle = try #require(fixture.presenter.compactFrame(for: snapshot, notices: [], at: fixture.date))
        #expect(idle.size == CGSize(width: 280, height: 32))
        let notice = IslandNotice(id: "ai-active-test", title: "Codex")
        let active = try #require(fixture.presenter.compactFrame(for: snapshot, notices: [notice], at: fixture.date))
        #expect(active.width == 280)
        let hidden = fixture.presenter.compactConfiguration(for: [notice], at: fixture.date, statusHidden: true)
        #expect(hidden.compactStatusLength == nil)
        #expect(try #require(fixture.presenter.compactFrame(for: snapshot, notices: [notice], at: fixture.date, statusHidden: true)) == idle)
        #expect(fixture.presenter.compactConfiguration(for: [], at: fixture.date) == idleConfiguration)
        #expect(try #require(fixture.presenter.compactFrame(for: snapshot, notices: [], at: fixture.date)) == idle)
    }

    @Test(arguments: IslandEdge.allCases)
    func idleCustomPillsKeepTheFixedSizeBeforeAndAfterAnActivity(edge: IslandEdge) throws {
        let fixture = try Fixture(edge: edge)
        defer { fixture.close() }
        let expected = CGSize(width: 24, height: 24)
        let idle = try #require(fixture.presenter.compactFrame(for: fixture.screen, notices: [], at: fixture.date))
        #expect(idle.size == expected)
        #expect(fixture.presenter.compactConfiguration(for: [], at: fixture.date).compactStatusLength == nil)
        let notice = IslandNotice(id: "ai-active-test", title: "Codex")
        let active = try #require(fixture.presenter.compactFrame(for: fixture.screen, notices: [notice], at: fixture.date))
        #expect(active.size == (edge.isVertical ? CGSize(width: 32, height: 68) : CGSize(width: 60, height: 32)))
        #expect(try #require(fixture.presenter.compactFrame(
            for: fixture.screen, notices: [notice], at: fixture.date, statusHidden: true
        )) == idle)
        #expect(try #require(fixture.presenter.compactFrame(for: fixture.screen, notices: [], at: fixture.date)) == idle)
    }

    @Test
    func hidingContentShrinksTheCustomPillAndAStatusSwitchRestoresItsNaturalLength() throws {
        let fixture = try Fixture(edge: .left)
        defer { fixture.close() }
        let state = SideNoticeDisplayState()
        let notice = IslandNotice(id: "toolbox-reminder-left", title: "亮屏", detail: "保持屏幕开启")
        _ = SideNoticePresenter.updateCompactVisibility(notices: [notice], settings: fixture.settings.settings, displayState: state)
        state.compactStatusHidden = true
        #expect(!SideNoticePresenter.updateCompactVisibility(notices: [notice], settings: fixture.settings.settings, displayState: state))
        #expect(state.compactStatusHidden)
        let configuration = fixture.presenter.compactConfiguration(for: [notice], at: fixture.date, statusHidden: state.compactStatusHidden)
        #expect(configuration.compactStatusLength == nil)
        let frame = try #require(fixture.presenter.compactFrame(for: fixture.screen, notices: [notice], at: fixture.date, statusHidden: true))
        #expect(frame.size == CGSize(width: 24, height: 24))
        let next = IslandNotice(id: "ai-active-codex", title: "Codex")
        #expect(SideNoticePresenter.updateCompactVisibility(notices: [next], settings: fixture.settings.settings, displayState: state))
        #expect(!state.compactStatusHidden)
        #expect(fixture.presenter.compactConfiguration(for: [next], at: fixture.date).compactStatusLength == 68)
        _ = SideNoticePresenter.updateCompactVisibility(notices: [], settings: fixture.settings.settings, displayState: state)
        #expect(!state.compactStatusHidden && state.compactStatusIDs.isEmpty)
    }

    @Test
    func alwaysVisibleActivitiesCannotLeaveAHiddenCompactStatus() {
        let state = SideNoticeDisplayState()
        let notice = IslandNotice(id: "ai-active-codex", title: "Codex")
        var settings = FeatureSettings.default
        settings.activityNoticeDisplayDuration = .always
        _ = SideNoticePresenter.updateCompactVisibility(notices: [notice], settings: settings, displayState: state)
        state.compactStatusHidden = true
        #expect(!SideNoticePresenter.updateCompactVisibility(notices: [notice], settings: settings, displayState: state))
        #expect(!state.compactStatusHidden)
    }

    @Test
    func voiceProcessingDimensionsRemainScopedToTheRecordedDisplay() throws {
        let fixture = try Fixture(edge: .top)
        defer { fixture.close() }
        fixture.queue.enqueue(IslandNotice(id: "voice-processing-left", title: "语音", detail: "整理中"), expiresAfter: nil)
        fixture.presenter.setVoiceProcessingDisplayID(7)
        var dimensions: [UInt32: CGFloat?] = [:]
        fixture.presenter.onCompactLayoutChanged = { displayID, _, length, _, _ in dimensions[displayID] = length }
        fixture.presenter.publishCompactLayout(on: 7)
        fixture.presenter.publishCompactLayout(on: 8)
        #expect(try #require(dimensions[7] ?? nil) > 24)
        #expect(dimensions[8] == .some(nil))
    }

    @Test
    func stoppingThePresenterPreventsQueuedStateChangesFromRecreatingPanels() async throws {
        let fixture = try Fixture(edge: .right)
        var published = 0
        fixture.presenter.onCompactLayoutChanged = { _, _, _, _, _ in published += 1 }
        fixture.presenter.stop()
        fixture.queue.enqueue(IslandNotice(id: "ai-active-fixture", title: "Fixture"), expiresAfter: nil)
        for _ in 0..<6 { await Task.yield() }
        #expect(published == 0)
        fixture.close()
    }

    @Test(arguments: IslandEdge.allCases)
    func publishingLayoutDuringAScreenSwitchSettlesOnTheSameLivePill(edge: IslandEdge) throws {
        let fixture = try Fixture(edge: edge)
        defer { fixture.close() }
        let other = ScreenSnapshot(displayID: 8,
            frame: CGRect(x: 0, y: 0, width: 1440, height: 900),
            visibleFrame: CGRect(x: 0, y: 0, width: 1440, height: 876))
        let coordinator = OverlayCoordinator(contentView: NSView(),
            layoutEngine: ScreenLayoutEngine(configuration: fixture.settings.settings.islandScreenConfiguration))
        coordinator.screenSnapshotProvider = { [fixture.screen, other] }
        defer { coordinator.stop() }
        coordinator.updateScreens([fixture.screen, other])
        var published = 0
        coordinator.onActiveLayoutChanged = { layout in
            published += 1
            if let displayID = layout?.displayID { fixture.presenter.publishCompactLayout(on: displayID) }
        }
        fixture.presenter.onCompactLayoutChanged = { displayID, details, length, sideWidth, iconSize in
            guard coordinator.activeDisplayID == displayID else { return }
            coordinator.updateCompactStatus(expandsForDetailedStatus: details, compactStatusLength: length,
                                            compactStatusSideWidth: sideWidth, statusIconSize: iconSize)
        }
        fixture.queue.enqueue(IslandNotice(id: "voice-processing-left", title: "语音", detail: "正在处理"), expiresAfter: nil)
        fixture.presenter.setVoiceProcessingDisplayID(7)
        coordinator.selectActiveDisplay(at: CGPoint(x: fixture.screen.frame.midX, y: fixture.screen.frame.midY))
        let recordingLayout = try #require(coordinator.activeLayout)
        #expect(recordingLayout.collapsedFrame.size == (edge.isVertical
            ? CGSize(width: 32, height: 110) : CGSize(width: 98, height: 32)))
        #expect(published <= 2, "Reentrant layout callbacks must converge without repeatedly resizing")
        coordinator.selectActiveDisplay(at: CGPoint(x: other.frame.midX, y: other.frame.midY))
        #expect(coordinator.activeLayout?.displayID == 8)
        #expect(coordinator.activeLayout?.collapsedFrame.size == CGSize(width: 24, height: 24))
        #expect(published <= 4)
        fixture.presenter.publishCompactLayout(on: 7)
        #expect(coordinator.activeLayout?.collapsedFrame.size == CGSize(width: 24, height: 24),
                "A notification from another display cannot change the current animation anchor")
    }

    @Test
    func cameraHeadphoneLayoutFollowsItsNoticeAcrossScreensAndRestoresThePreviousStatus() throws {
        let fixture = try Fixture(edge: .top)
        defer { fixture.close() }
        fixture.settings.settings.islandPlacement = IslandPlacement()
        fixture.screen = Self.notchedScreen
        fixture.screen.auxiliaryTopLeftArea?.size.width = 820
        fixture.screen.auxiliaryTopRightArea?.origin.x = 20_980
        fixture.screen.auxiliaryTopRightArea?.size.width = 820
        let other = ScreenSnapshot(displayID: 8,
            frame: CGRect(x: 22_000, y: 0, width: 1440, height: 900),
            visibleFrame: CGRect(x: 22_000, y: 0, width: 1440, height: 876))
        let coordinator = OverlayCoordinator(contentView: NSView(),
            layoutEngine: ScreenLayoutEngine(configuration: fixture.settings.settings.islandScreenConfiguration))
        coordinator.screenSnapshotProvider = { [fixture.screen, other] }
        defer { coordinator.stop() }
        coordinator.updateScreens([fixture.screen, other])
        var published = 0
        coordinator.onActiveLayoutChanged = { layout in
            published += 1
            if let displayID = layout?.displayID { fixture.presenter.publishCompactLayout(on: displayID) }
        }
        fixture.presenter.onCompactLayoutChanged = { displayID, details, length, sideWidth, iconSize in
            guard coordinator.activeDisplayID == displayID else { return }
            coordinator.updateCompactStatus(expandsForDetailedStatus: details, compactStatusLength: length,
                                            compactStatusSideWidth: sideWidth, statusIconSize: iconSize)
        }
        var notice = IslandNotice(id: "headphone-connection-camera", title: "AirPods Pro", createdAt: fixture.date,
            style: .headphone, batteryLevels: [NoticeBatteryLevel(label: "耳机", level: 100)])
        fixture.queue.enqueue(notice, expiresAfter: nil)
        let configuration = fixture.presenter.compactConfiguration(for: [notice], at: fixture.date)
        #expect(configuration.compactStatusSideWidth != nil)
        #expect(fixture.presenter.compactConfiguration(for: [notice], at: fixture.date, statusHidden: true).compactStatusSideWidth == nil)
        coordinator.selectActiveDisplay(at: CGPoint(x: fixture.screen.frame.midX, y: fixture.screen.frame.midY))
        let expected = try #require(fixture.presenter.compactFrame(for: fixture.screen, notices: [notice], at: fixture.date))
        #expect(coordinator.activeLayout?.collapsedFrame == expected,
            "The pet and hover anchor must use the same earphone content width as its overlay")
        let sizing = try #require(SideNoticeLayoutEngine().compactBarSizing(for: [notice], settings: fixture.settings.settings))
        #expect(configuration.compactStatusSideWidth == sizing.compactStatusSideWidth)
        let shortWidth = expected.width
        let activeLayoutChanged = coordinator.onActiveLayoutChanged
        coordinator.onActiveLayoutChanged = nil
        coordinator.updateCompactStatus(expandsForDetailedStatus: configuration.expandsForDetailedStatus,
            compactStatusLength: configuration.compactStatusLength,
            compactStatusSideWidth: try #require(configuration.compactStatusSideWidth) + 8)
        #expect(coordinator.activeLayout?.collapsedFrame.width == shortWidth + 16,
            "A changed side budget must invalidate the coordinator's layout even when its text length is unchanged")
        fixture.presenter.setStatusIcons([])
        #expect(coordinator.activeLayout?.collapsedFrame == expected,
            "Publishing a panel update must restore the notice's measured side budget")
        coordinator.updateCompactStatus(expandsForDetailedStatus: configuration.expandsForDetailedStatus,
            compactStatusLength: configuration.compactStatusLength,
            compactStatusSideWidth: try #require(configuration.compactStatusSideWidth) + 8)
        fixture.presenter.publishCompactLayout(on: fixture.screen.displayID)
        #expect(coordinator.activeLayout?.collapsedFrame == expected)
        coordinator.onActiveLayoutChanged = activeLayoutChanged
        coordinator.selectActiveDisplay(at: CGPoint(x: other.frame.midX, y: other.frame.midY))
        let external = try #require(fixture.presenter.compactFrame(for: other, notices: [notice], at: fixture.date))
        #expect(coordinator.activeLayout?.collapsedFrame == external)
        #expect(shortWidth - external.width == 40,
            "Each screen must supply its own measured camera clearance")
        fixture.queue.removeAll()
        notice.title = "三年后的 AirPods Pro 第二代"
        fixture.queue.enqueue(notice, expiresAfter: nil)
        fixture.presenter.publishCompactLayout(on: other.displayID)
        #expect(try #require(coordinator.activeLayout).collapsedFrame.width > external.width)
        #expect(published < 12, "Layout callbacks must settle after a content or screen change")
        let focus = IslandNotice(id: "focus-transition-camera", title: "Work", createdAt: fixture.date.addingTimeInterval(1))
        fixture.queue.enqueue(focus, expiresAfter: nil)
        fixture.presenter.publishCompactLayout(on: other.displayID)
        #expect(fixture.presenter.compactConfiguration(for: [notice, focus], at: fixture.date).compactStatusSideWidth == nil)
        #expect(coordinator.activeLayout?.collapsedFrame
            == fixture.presenter.compactFrame(for: other, notices: [focus], at: fixture.date))
        #expect(fixture.presenter.compactConfiguration(for: [], at: fixture.date).compactStatusSideWidth == nil)
    }

    @Test(arguments: [false, true])
    func cameraHeadphoneSurfaceKeepsItsFullNameAndSixPointOuterMargins(physical: Bool) async throws {
        let fixture = try Fixture(edge: .top)
        defer { fixture.close() }
        fixture.settings.settings.islandPlacement = IslandPlacement()
        fixture.settings.settings.islandNotchBackground = .black
        fixture.settings.settings.collapsedProgressGlowEnabled = false
        if physical { fixture.screen = Self.notchedScreen }
        let notice = IslandNotice(id: "headphone-connection-camera", title: "AirPods Pro", detail: "已连接",
            createdAt: fixture.date, style: .headphone, batteryLevels: [NoticeBatteryLevel(label: "左", level: 100)])
        fixture.queue.enqueue(notice, expiresAfter: nil)
        let configuration = fixture.presenter.compactConfiguration(for: [notice], at: fixture.date)
        let layout = ScreenLayoutEngine(configuration: configuration).layout(for: fixture.screen)
        let centerInset = max(120, layout.centerOcclusionWidth)
        let state = SideNoticeDisplayState()
        state.placementMode = .camera
        state.compactWingHeight = layout.collapsedFrame.height
        state.compactBarCenterInset = centerInset
        let view = CompactStatusBarView(queue: fixture.queue, displayState: state, media: fixture.media,
            browserDownloads: fixture.downloads, settingsStore: fixture.settings, resultSweep: fixture.sweep,
            pomodoro: PomodoroService(notificationRequestHandler: { _ in }, defaults: fixture.defaults), onStatusHidden: {})
        let actual = try await renderOffscreen(AppLanguageEnvironment(languageStore: fixture.language,
            content: view.statusBarContent(at: fixture.date))
            .environment(\.locale, Locale(identifier: "en-US"))
            .environment(\._accessibilityReduceMotion, true).transaction { $0.disablesAnimations = true },
            size: layout.collapsedFrame.size)
        let expected = try await renderOffscreen(CompactHeadphoneConnectionBar(notice: notice,
            height: layout.collapsedFrame.height, centerInset: centerInset)
            .background(.black)
            .clipShape(CompactIslandShape(layoutStyle: .pill))
            .environment(\.colorScheme, .dark).environment(\.locale, fixture.language.language.locale)
            .environment(\._accessibilityReduceMotion, true).transaction { $0.disablesAnimations = true },
            size: layout.collapsedFrame.size)
        var differences = 0
        for y in 0..<actual.pixelsHigh {
            for x in 0..<actual.pixelsWide {
                let value = try #require(actual.colorAt(x: x, y: y))
                let reference = try #require(expected.colorAt(x: x, y: y))
                if abs(value.redComponent - reference.redComponent) > 0.02 { differences += 1 }
            }
        }
        #expect(differences == 0, "Camera surfaces must use the headphone row's six-point margins without another padding layer")
    }

    @Test(arguments: IslandEdge.allCases)
    func transientMessagesUseOneNaturalPillAndRestoreThePreviousStatus(edge: IslandEdge) throws {
        let fixture = try Fixture(edge: edge)
        defer { fixture.close() }
        let notices = [IslandNotice(id: "ai-active-codex", title: "Codex")]
        let previous = fixture.presenter.compactConfiguration(for: notices, at: fixture.date)
        fixture.presenter.setTransientNoticePresented(true, message: "已保存")
        let short = fixture.presenter.compactConfiguration(for: notices, at: fixture.date)
        let text = CompactPillStatusContent.transientPresentation(message: "已保存")
        #expect(short.compactStatusLength == text.length(thickness: 32, edge: edge))
        #expect(!short.expandsForDetailedStatus)
        fixture.presenter.setTransientNoticePresented(true, message: "操作结果稍长一些")
        let long = fixture.presenter.compactConfiguration(for: notices, at: fixture.date)
        #expect(try #require(long.compactStatusLength) > #require(short.compactStatusLength))
        fixture.presenter.setTransientNoticePresented(false)
        #expect(fixture.presenter.compactConfiguration(for: notices, at: fixture.date) == previous)
        fixture.settings.settings.islandPlacement = IslandPlacement()
        let camera = fixture.presenter.compactConfiguration(for: notices, at: fixture.date)
        fixture.presenter.setTransientNoticePresented(true, message: "操作结果稍长一些")
        #expect(fixture.presenter.compactConfiguration(for: notices, at: fixture.date) == camera)
        fixture.settings.settings.islandLayoutStyle = .notch
        let notch = fixture.presenter.compactConfiguration(for: notices, at: fixture.date)
        fixture.presenter.setTransientNoticePresented(false)
        #expect(fixture.presenter.compactConfiguration(for: notices, at: fixture.date) == notch)
    }

    @Test
    func headphoneTextFillsEachViewportDuringTheRealPanelReveal() async throws {
        let fixture = try Fixture(edge: .top)
        defer { fixture.close() }
        fixture.screen.frame.origin.x = 20_000
        fixture.screen.visibleFrame.origin.x = 20_000
        fixture.settings.settings.islandNotchBackground = .black
        fixture.settings.settings.collapsedProgressGlowEnabled = false
        let host = try activeHost(fixture)
        let panel = try #require(host.window)
        let notice = IslandNotice(id: "headphone-connection-fill", title: String(repeating: "█", count: 100),
            createdAt: fixture.date, style: .headphone,
            batteryLevels: [NoticeBatteryLevel(label: "左", level: 100)])
        fixture.queue.enqueue(notice, expiresAfter: nil)
        fixture.presenter.setStatusIcons([])
        var samples: [String] = []
        var incomplete = 0
        func advanceFrame() {
            RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(1.0 / 120))
        }
        for _ in 0..<60 {
            advanceFrame()
            host.layoutSubtreeIfNeeded()
            let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
            host.cacheDisplay(in: host.bounds, to: bitmap)
            let scale = CGFloat(bitmap.pixelsWide) / host.bounds.width
            let center = bitmap.pixelsHigh / 2
            let background = try (0..<bitmap.pixelsWide).filter { x in
                try #require(bitmap.colorAt(x: x, y: center)?.usingColorSpace(.sRGB)).alphaComponent > 0.9
            }
            let leading = try #require(background.first)
            let trailing = try #require(background.last)
            let textLeading = leading + Int(42 * scale)
            let textTrailing = trailing - Int(12 * scale)
            guard textTrailing > textLeading else { continue }
            let occupied = try (textLeading..<textTrailing).filter { x in
                try (0..<bitmap.pixelsHigh).contains { y in
                    try #require(bitmap.colorAt(x: x, y: y)?.usingColorSpace(.sRGB)).redComponent > 0.3
                }
            }
            let headGap = occupied.first.map { CGFloat($0 - textLeading) / scale } ?? .infinity
            let tailGap = occupied.last.map { CGFloat(textTrailing - $0) / scale } ?? .infinity
            let filledFraction = CGFloat(occupied.count) / CGFloat(textTrailing - textLeading)
            if headGap > 4 || tailGap > 4 || filledFraction < 0.95 { incomplete += 1 }
            samples.append("\(CGFloat(trailing - leading) / scale):\(headGap),\(tailGap),\(filledFraction)")
            await withCheckedContinuation { continuation in
                DispatchQueue.main.async { continuation.resume() }
            }
        }
        #expect(!samples.isEmpty && incomplete == 0,
            "Every revealed headphone viewport must begin filled; width:head-gap,tail-gap samples: \(samples)")
        #expect(panel.alphaValue == 0 && NSScreen.screens.allSatisfy { !$0.frame.intersects(panel.frame) })
    }

    @Test
    func headphoneTextKeepsAConstantReadingSpeedWhileThePanelReveals() async throws {
        let fixture = try Fixture(edge: .top)
        defer { fixture.close() }
        fixture.screen.frame.origin.x = 20_000
        fixture.screen.visibleFrame.origin.x = 20_000
        fixture.settings.settings.islandNotchBackground = .black
        fixture.settings.settings.collapsedProgressGlowEnabled = false
        let originalHost = try activeHost(fixture)
        let panel = try #require(originalHost.window)
        let clock = ReadingClock()
        let host = NSHostingView(rootView: ReadingAnimationClock(clock: clock,
            content: originalHost.rootView.environment(\._accessibilityReduceMotion, false)))
        host.sizingOptions = []
        panel.contentView = host
        host.layoutSubtreeIfNeeded()
        let notice = IslandNotice(id: "headphone-connection-speed", title: String(repeating: "█    ", count: 20),
            createdAt: fixture.date, style: .headphone,
            batteryLevels: [NoticeBatteryLevel(label: "左", level: 100)])
        fixture.queue.enqueue(notice, expiresAfter: nil)
        fixture.presenter.setStatusIcons([])
        let result = try await readingSpeeds(host) { clock.progress = $0 }
        let speeds = result.speeds
        #expect(speeds.count >= 6, "The real panel must provide at least six independent velocity windows")
        #expect(speeds.allSatisfy { abs($0 - 32) <= 8 },
            "Each 250ms window must move at 32pt/s relative to the expanding text viewport; observed speeds: \(speeds)")
        #expect(abs(result.slope - 32) <= 1 && result.residual <= 1.5,
            "The complete trajectory must be linear at 32pt/s; slope \(result.slope), residual \(result.residual)")
        #expect(panel.alphaValue == 0 && NSScreen.screens.allSatisfy { !$0.frame.intersects(panel.frame) })
    }

    @Test(arguments: [false, true])
    func velocitySamplerDistinguishesConstantAndVaryingExternalProgress(varies: Bool) async throws {
        let clock = ReadingClock()
        let text = String(repeating: "█    ", count: 100)
        let host = NSHostingView(rootView: ReadingClockText(clock: clock, text: text))
        host.sizingOptions = []
        let window = NSWindow(contentRect: CGRect(x: 20_000, y: 0, width: 222, height: 32),
            styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        defer { window.contentView = nil; window.close() }
        let scale = window.backingScaleFactor
        let textWidth = ceil((text as NSString).size(withAttributes: [
            .font: NSFont.systemFont(ofSize: 11, weight: .regular)
        ]).width * scale) / scale
        let result = try await readingSpeeds(host) { elapsed in
            let distance = elapsed * 32 + (varies ? 10 * sin(elapsed * 2 * .pi) : 0)
            clock.progress = distance / Double(textWidth - 168)
        }
        let speeds = result.speeds
        #expect(speeds.count >= 6)
        if varies {
            #expect(speeds.contains { abs($0 - 32) > 8 },
                "The pixel sampler must detect an intentionally nonuniform driver: \(speeds)")
        } else {
            #expect(speeds.allSatisfy { abs($0 - 32) <= 8 },
                "The same offscreen sampler must read a known 32pt/s external driver: \(speeds)")
            #expect(abs(result.slope - 32) <= 1 && result.residual <= 1.5,
                "Linear calibration slope \(result.slope), residual \(result.residual)")
        }
        #expect(!window.isVisible)
    }

    @Test(arguments: [IslandLayoutStyle.pill, .notch])
    func shorteningACollapsedBarKeepsThePreviousDrawingAreaUntilTheFoldFinishes(style: IslandLayoutStyle) throws {
        let fixture = try Fixture(edge: .top)
        defer { fixture.close() }
        fixture.settings.settings.islandLayoutStyle = style
        fixture.settings.settings.islandNotchBackground = .black
        fixture.settings.settings.collapsedProgressGlowEnabled = false
        fixture.settings.settings.mediaCompactStyle = .detailed
        fixture.screen = ScreenSnapshot(displayID: 7,
            frame: CGRect(x: 20_000, y: 0, width: 1800, height: 1100),
            visibleFrame: CGRect(x: 20_000, y: 0, width: 1800, height: 1076))
        fixture.media.publishSnapshot(NowPlayingSnapshot(title: "A longer media title", artist: "Artist", album: nil,
            artworkData: nil, duration: 60, elapsedTime: 0, timestamp: fixture.date, isPlaying: true))
        let notice = IslandNotice(id: "media-active-resize", title: "Music", side: .left)
        fixture.queue.enqueue(notice, expiresAfter: nil)
        fixture.presenter.setScreenLocked(false)
        let host = try #require(NSApp.windows.compactMap {
            $0.contentView as? NSHostingView<AppLanguageEnvironment<CompactStatusBarView>>
        }.first { $0.rootView.content.settingsStore === fixture.settings })
        let panel = try #require(host.window)
        panel.alphaValue = 0
        host.layoutSubtreeIfNeeded()
        let previous = panel.frame

        fixture.settings.settings.mediaCompactStyle = .compact
        fixture.presenter.setStatusIcons([])
        let target = try #require(fixture.presenter.compactFrame(for: fixture.screen, notices: [notice], at: fixture.date))

        #expect(previous.width > target.width)
        #expect(panel.frame.contains(previous), "Shrinking the window immediately clips the visible recycle animation")
        #expect(host.rootView.content.displayState.compactLayout?.animation == ZislaMotion.islandRecycle)
        #expect(!panel.isKeyWindow)
    }

    @Test(arguments: IslandEdge.allCases)
    func fractionalMediaFramesStayInsideTheNativeCanvasThroughEveryResize(edge: IslandEdge) async throws {
        let fixture = try Fixture(edge: edge)
        defer { fixture.close() }
        fixture.screen = ScreenSnapshot(displayID: 7,
            frame: CGRect(x: 20_000, y: 0, width: 1800, height: 1100),
            visibleFrame: CGRect(x: 20_000, y: 0, width: 1800, height: 1076))
        fixture.settings.settings.islandPlacement.offset = 0.537
        fixture.settings.settings.mediaCompactStyle = .detailed
        fixture.settings.settings.mediaVisualizationStyle = .glow
        var item = NowPlayingSnapshot(title: "Track", artist: "Artist", album: nil, artworkData: nil,
            duration: 60, elapsedTime: 0, timestamp: fixture.date, isPlaying: true,
            lyrics: SyncedLyrics(lines: []))
        fixture.media.publishSnapshot(item)
        fixture.queue.enqueue(IslandNotice(id: "media-active-canvas", title: "Music"), expiresAfter: nil)
        fixture.presenter.setScreenLocked(false)
        let host = try #require(NSApp.windows.compactMap {
            $0.contentView as? NSHostingView<AppLanguageEnvironment<CompactStatusBarView>>
        }.first { $0.rootView.content.settingsStore === fixture.settings })
        let panel = try #require(host.window)
        panel.alphaValue = 0
        let state = host.rootView.content.displayState
        let initial = try #require(state.compactLayout)
        #expect(initial.frame != initial.frame.integral, "The fixture must exercise a fractional visual frame")
        #expect(panel.frame.contains(initial.frame), "The first native canvas must contain the complete visual frame")
        #expect(initial.panelFrame == panel.frame && panel.frame == initial.frame.integral)

        item.title = String(repeating: "Long title ", count: 40)
        fixture.media.publishSnapshot(item)
        fixture.presenter.setStatusIcons([])
        let grown = try #require(state.compactLayout)
        #expect(panel.frame.contains(initial.frame) && panel.frame.contains(grown.frame))
        #expect(grown.panelFrame == panel.frame)

        item.title = "Track"
        fixture.media.publishSnapshot(item)
        fixture.presenter.setStatusIcons([])
        let shrinking = try #require(state.compactLayout)
        #expect(panel.frame.contains(grown.frame) && panel.frame.contains(shrinking.frame))
        try await fixture.resizeClock.finishPendingResize()
        let settled = try #require(state.compactLayout)
        #expect(settled.frame == initial.frame, "Canvas alignment must preserve the visual position and size")
        #expect(panel.frame.contains(settled.frame))
        #expect(settled.panelFrame == panel.frame && panel.frame == settled.frame.integral)

        fixture.reducesMotion = true
        fixture.settings.settings.islandPlacement.offset = 0.419
        fixture.presenter.setStatusIcons([])
        let immediate = try #require(state.compactLayout)
        #expect(immediate.animation == nil)
        #expect(panel.frame.contains(immediate.frame))
        #expect(immediate.panelFrame == panel.frame && panel.frame == immediate.frame.integral)
        fixture.resizeClock.advance()
        for _ in 0..<10 { await Task.yield() }
        #expect(fixture.resizeClock.waiters.isEmpty && panel.frame == immediate.frame.integral)
    }

    @Test(arguments: [IslandLayoutStyle.pill, .notch], [false, true])
    func continuousCollapsedResizingUsesRevealThenRecycleAndSettlesOnTheNewestFrame(
        style: IslandLayoutStyle, physicalNotch: Bool
    ) async throws {
        let fixture = try Fixture(edge: .top)
        defer { fixture.close() }
        fixture.settings.settings.islandLayoutStyle = style
        if physicalNotch { fixture.screen = Self.notchedScreen }
        let host = try activeHost(fixture)
        let state = host.rootView.content.displayState
        let panel = try #require(host.window)
        let ai = IslandNotice(id: "ai-active-resize", title: "Codex")
        fixture.queue.enqueue(ai, expiresAfter: nil)
        fixture.presenter.setStatusIcons([])
        let short = try #require(state.compactLayout).frame
        host.layoutSubtreeIfNeeded()

        fixture.settings.settings.mediaCompactStyle = .detailed
        fixture.queue.removeAll()
        fixture.queue.enqueue(IslandNotice(id: "media-active-resize", title: "Music"), expiresAfter: nil)
        fixture.media.publishSnapshot(NowPlayingSnapshot(title: "A longer media title", artist: "Artist", album: nil,
            artworkData: nil, duration: 60, elapsedTime: 0, timestamp: fixture.date, isPlaying: true))
        fixture.presenter.setStatusIcons([])
        let long = try #require(state.compactLayout).frame
        #expect(long.width > short.width)
        #expect(state.compactLayout?.animation == ZislaMotion.islandReveal)
        #expect(panel.frame.contains(short) && panel.frame.contains(long))

        fixture.settings.settings.mediaCompactStyle = .compact
        fixture.presenter.setStatusIcons([])
        let final = try #require(state.compactLayout).frame
        #expect(final.width < long.width)
        #expect(state.compactLayout?.animation == ZislaMotion.islandRecycle)
        #expect(panel.frame.contains(long))
        try await fixture.resizeClock.finishPendingResize()
        #expect(panel.frame == final)
        #expect(!panel.isKeyWindow)
    }

    @Test
    func theFirstNotchStatusRevealsFromItsIdleAnchor() throws {
        let fixture = try Fixture(edge: .top)
        defer { fixture.close() }
        fixture.settings.settings.islandLayoutStyle = .notch
        fixture.screen = Self.notchedScreen
        let host = try activeHost(fixture)
        let layout = try #require(host.rootView.content.displayState.compactLayout)
        let idle = ScreenLayoutEngine(configuration: fixture.settings.settings.islandScreenConfiguration)
            .layout(for: fixture.screen).collapsedFrame
        #expect(layout.frame.width > idle.width)
        #expect(layout.animation == ZislaMotion.islandReveal,
                "The first status needs a rendered idle baseline so its wings can grow out of the notch")
        #expect(layout.panelFrame.contains(idle) && layout.panelFrame.contains(layout.frame))
    }

    @Test
    func theLastNotchStatusRecyclesBeforeItsPanelIsRemovedAndCanBeInterrupted() async throws {
        let fixture = try Fixture(edge: .top)
        defer { fixture.close() }
        fixture.settings.settings.islandLayoutStyle = .notch
        fixture.screen = Self.notchedScreen
        let host = try activeHost(fixture)
        let panel = try #require(host.window)
        fixture.queue.enqueue(IslandNotice(id: "ai-active-first", title: "Codex"), expiresAfter: nil)
        fixture.presenter.setStatusIcons([])
        let active = try #require(host.rootView.content.displayState.compactLayout).frame
        fixture.queue.removeAll()
        fixture.presenter.setStatusIcons([])
        #expect(panel.isVisible, "The last status must fold back into the notch before its panel is hidden")
        #expect(host.rootView.content.displayState.compactLayout?.animation == ZislaMotion.islandRecycle)

        try await fixture.resizeClock.waitForPendingResize()
        fixture.queue.enqueue(IslandNotice(id: "ai-active-next", title: "Codex"), expiresAfter: nil)
        fixture.presenter.setStatusIcons([])
        fixture.resizeClock.advance()
        for _ in 0..<10 { await Task.yield() }
        #expect(panel.isVisible && panel.frame == active, "A stale recycle task cannot remove a new status")
        fixture.queue.removeAll()
        fixture.presenter.setStatusIcons([])
        try await fixture.resizeClock.finishPendingResize()
        #expect(!panel.isVisible)
        #expect(host.rootView.content.displayState.compactLayout == nil)
    }

    @Test(arguments: [IslandLayoutStyle.pill, .notch])
    func reducedMotionResizesImmediatelyWithoutADeferredWindowChange(style: IslandLayoutStyle) async throws {
        let fixture = try Fixture(edge: .top)
        defer { fixture.close() }
        fixture.settings.settings.islandLayoutStyle = style
        let host = try activeHost(fixture)
        let panel = try #require(host.window)
        fixture.queue.enqueue(IslandNotice(id: "media-active-resize", title: "Music"), expiresAfter: nil)
        fixture.settings.settings.mediaCompactStyle = .detailed
        fixture.media.publishSnapshot(NowPlayingSnapshot(title: "A longer media title", artist: "Artist", album: nil,
            artworkData: nil, duration: 60, elapsedTime: 0, timestamp: fixture.date, isPlaying: true))
        fixture.presenter.setStatusIcons([])
        fixture.reducesMotion = true
        fixture.settings.settings.mediaCompactStyle = .compact
        fixture.presenter.setStatusIcons([])
        let target = try #require(host.rootView.content.displayState.compactLayout).frame
        #expect(panel.frame == target)
        #expect(host.rootView.content.displayState.compactLayout?.animation == nil)
        fixture.resizeClock.advance()
        for _ in 0..<10 { await Task.yield() }
        #expect(panel.frame == target)
        #expect(fixture.resizeClock.waiters.isEmpty)
    }

    @Test
    func movingToAnotherScreenOrPlacementDoesNotAnimateAcrossTheDesktop() throws {
        let fixture = try Fixture(edge: .top)
        defer { fixture.close() }
        let host = try activeHost(fixture)
        let panel = try #require(host.window)
        fixture.settings.settings.islandPlacement = IslandPlacement(mode: .custom, edge: .right, offset: 0.7)
        fixture.presenter.setStatusIcons([])
        var layout = try #require(host.rootView.content.displayState.compactLayout)
        #expect(layout.animation == nil && panel.frame == layout.frame,
                "Changing an edge is a reposition, not a collapsed length change")
        fixture.screen.frame.origin.x -= 1800
        fixture.screen.visibleFrame.origin.x -= 1800
        fixture.presenter.setStatusIcons([])
        layout = try #require(host.rootView.content.displayState.compactLayout)
        #expect(layout.animation == nil && panel.frame == layout.frame,
                "Moving the display cannot interpolate through unrelated screen coordinates")
    }

    @Test
    func stoppingDuringAResizeCancelsThePendingPanelChange() async throws {
        let fixture = try Fixture(edge: .top)
        defer { fixture.close() }
        let host = try activeHost(fixture)
        let panel = try #require(host.window)
        fixture.queue.enqueue(IslandNotice(id: "media-active-resize", title: "Music"), expiresAfter: nil)
        fixture.settings.settings.mediaCompactStyle = .detailed
        fixture.media.publishSnapshot(NowPlayingSnapshot(title: "A longer media title", artist: "Artist", album: nil,
            artworkData: nil, duration: 60, elapsedTime: 0, timestamp: fixture.date, isPlaying: true))
        fixture.presenter.setStatusIcons([])
        fixture.settings.settings.mediaCompactStyle = .compact
        fixture.presenter.setStatusIcons([])
        try await fixture.resizeClock.waitForPendingResize()
        fixture.presenter.stop()
        let stopped = panel.frame
        fixture.resizeClock.advance()
        for _ in 0..<10 { await Task.yield() }
        #expect(!panel.isVisible && panel.frame == stopped)
        #expect(host.rootView.content.displayState.compactLayout == nil)
    }

    private func readingSpeeds(_ host: NSView, beforeFrame: @MainActor (Double) throws -> Void) async throws
        -> (speeds: [Double], slope: Double, residual: Double) {
        var previousPhase: CGFloat?
        var period: CGFloat?
        var displacement: CGFloat = 0
        var anchor: (time: Double, displacement: CGFloat)?
        var motionOrigin: (time: Double, displacement: CGFloat)?
        var speeds: [Double] = []
        var positions: [(time: Double, distance: Double)] = []
        // Frame time keeps slow commits from shifting pixels or consuming velocity windows.
        for frame in 0...50 {
            let time = Double(frame) / 20
            try beforeFrame(time)
            if frame == 0 { try await Task.sleep(for: .milliseconds(800)) }
            if (frame + 1).isMultiple(of: 4) { try await Task.sleep(for: .milliseconds(100)) }
            await withCheckedContinuation { continuation in
                DispatchQueue.main.async { continuation.resume() }
            }
            host.layoutSubtreeIfNeeded()
            let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
            host.cacheDisplay(in: host.bounds, to: bitmap)
            let scale = CGFloat(bitmap.pixelsWide) / host.bounds.width
            let center = bitmap.pixelsHigh / 2
            let background = try (0..<bitmap.pixelsWide).filter { x in
                try #require(bitmap.colorAt(x: x, y: center)?.usingColorSpace(.sRGB)).alphaComponent > 0.9
            }
            let leading = try #require(background.first) + Int(42 * scale)
            let trailing = try #require(background.last) - Int(12 * scale)
            var edges: [CGFloat] = []
            var previousInk = true
            if trailing > leading {
                for x in leading..<trailing {
                    let ink = try (0..<bitmap.pixelsHigh).contains { y in
                        try #require(bitmap.colorAt(x: x, y: y)?.usingColorSpace(.sRGB)).redComponent > 0.3
                    }
                    if ink && !previousInk { edges.append(CGFloat(x - leading) / scale) }
                    previousInk = ink
                }
            }
            if edges.count >= 2 {
                if period == nil { period = (edges.last! - edges[0]) / CGFloat(edges.count - 1) }
                let phase = edges[0]
                if let previousPhase, let period {
                    var movement = previousPhase - phase
                    // Unwrap the pattern so a marker crossing the clip does not look like reverse motion.
                    if movement < -period / 2 { movement += period }
                    if movement > period / 2 { movement -= period }
                    displacement += movement
                }
                previousPhase = phase
                if anchor == nil {
                    if let origin = motionOrigin, displacement > origin.displacement {
                        if displacement - origin.displacement >= 1 {
                            anchor = origin
                            positions.append((origin.time, Double(origin.displacement)))
                        }
                    } else {
                        motionOrigin = (time, displacement)
                    }
                }
                if let checkpoint = anchor {
                    positions.append((time, Double(displacement)))
                    if time - checkpoint.time >= 0.25 {
                        speeds.append(Double(displacement - checkpoint.displacement) / (time - checkpoint.time))
                        anchor = (time, displacement)
                    }
                }
            }
        }
        try #require(positions.count >= 2, "The text must begin a measurable forward pass")
        let count = Double(positions.count)
        let meanTime = positions.reduce(0) { $0 + $1.time } / count
        let meanDistance = positions.reduce(0) { $0 + $1.distance } / count
        let covariance = positions.reduce(0) { $0 + ($1.time - meanTime) * ($1.distance - meanDistance) }
        let variance = positions.reduce(0) { $0 + pow($1.time - meanTime, 2) }
        let slope = covariance / variance
        let residual = positions.map { abs($0.distance - meanDistance - slope * ($0.time - meanTime)) }.max()!
        return (speeds, slope, residual)
    }

    @MainActor
    private final class ReadingClock: ObservableObject {
        @Published var progress: Double = 0
    }

    private struct ReadingAnimationClock<Content: View>: View {
        @ObservedObject var clock: ReadingClock
        let content: Content

        var body: some View {
            let sampleTime = clock.progress
            content
                .environment(\.sampledReadingTime, sampleTime)
                .transaction { transaction in
                    if let animation = transaction.animation {
                        transaction.animation = Animation(SampledReadingAnimation(base: animation, startedAt: sampleTime))
                    }
                }
        }
    }

    private struct SampledReadingAnimation: CustomAnimation {
        let base: Animation
        let startedAt: TimeInterval

        func animate<V: VectorArithmetic>(value: V, time: TimeInterval, context: inout AnimationContext<V>) -> V? {
            let elapsed = context.environment.sampledReadingTime - startedAt
            return base.animate(value: value, time: elapsed, context: &context)
        }
    }

    private struct ReadingClockText: View {
        @ObservedObject var clock: ReadingClock
        let text: String

        var body: some View {
            MarqueeText(text, font: .system(size: 11, weight: .medium), textColor: .white,
                repeats: false, scrollProgress: clock.progress)
                .frame(width: 168, height: 32)
                .padding(.leading, 42)
                .padding(.trailing, 12)
                .background(.black)
        }
    }

    private static let notchedScreen = ScreenSnapshot(displayID: 7,
        frame: CGRect(x: 20_000, y: 0, width: 1800, height: 1100),
        visibleFrame: CGRect(x: 20_000, y: 0, width: 1800, height: 1056),
        safeAreaInsets: ScreenInsets(top: 44),
        auxiliaryTopLeftArea: CGRect(x: 20_000, y: 1056, width: 840, height: 44),
        auxiliaryTopRightArea: CGRect(x: 20_960, y: 1056, width: 840, height: 44))

    private func activeHost(_ fixture: Fixture) throws -> NSHostingView<AppLanguageEnvironment<CompactStatusBarView>> {
        fixture.queue.enqueue(IslandNotice(id: "ai-active-initial", title: "Codex"), expiresAfter: nil)
        fixture.presenter.setScreenLocked(false)
        let host = try #require(NSApp.windows.compactMap {
            $0.contentView as? NSHostingView<AppLanguageEnvironment<CompactStatusBarView>>
        }.first { $0.rootView.content.settingsStore === fixture.settings })
        host.window?.alphaValue = 0
        host.layoutSubtreeIfNeeded()
        fixture.queue.removeAll()
        return host
    }

    @MainActor
    private final class Fixture {
        let suiteName = "Zisla.PillPresenter.\(UUID().uuidString)"
        let defaults: UserDefaults
        let settings: FeatureSettingsStore
        let language: AppLanguageStore
        let media = NowPlayingService()
        let downloads = BrowserDownloadMonitor()
        let queue = SideNoticeQueue()
        let sweep = AIResultSweepController(now: { Date(timeIntervalSince1970: 100) })
        let date = Date(timeIntervalSince1970: 100)
        var reducesMotion = false
        let resizeClock = ResizeClock()
        var screen = ScreenSnapshot(displayID: 7,
            frame: CGRect(x: -1800, y: -240, width: 1800, height: 1100),
            visibleFrame: CGRect(x: -1800, y: -240, width: 1800, height: 1076))
        lazy var presenter = SideNoticePresenter(queue: queue, resultSweep: sweep, media: media,
            pomodoro: PomodoroService(notificationRequestHandler: { _ in }, defaults: defaults),
            browserDownloads: downloads, settingsStore: settings, languageStore: language,
            isScreenLocked: true, now: { [unowned self] in date }, reduceMotion: { [unowned self] in reducesMotion },
            waitForCompactResize: { [resizeClock] in try await resizeClock.wait(for: $0) },
            screenSnapshotProvider: { [unowned self] in [screen] })

        init(edge: IslandEdge) throws {
            defaults = try #require(UserDefaults(suiteName: suiteName))
            settings = FeatureSettingsStore(defaults: defaults)
            language = AppLanguageStore(defaults: defaults)
            settings.settings.islandLayoutStyle = .pill
            settings.settings.islandPlacement = IslandPlacement(mode: .custom, edge: edge)
            settings.settings.islandShowMoreInformation = false
        }

        func close() {
            presenter.stop()
            resizeClock.advance()
            queue.removeAll()
            sweep.cancel()
            settings.flushPendingChanges()
            defaults.removePersistentDomain(forName: suiteName)
        }
    }

    @MainActor
    private final class ResizeClock {
        var waiters: [CheckedContinuation<Void, Error>] = []

        func wait(for duration: Duration) async throws {
            try Task.checkCancellation()
            #expect(duration == ZislaMotion.islandRecycleSettleDelay)
            try await withCheckedThrowingContinuation { waiters.append($0) }
        }

        func advance() {
            let pending = waiters
            waiters.removeAll()
            for waiter in pending { waiter.resume() }
        }

        func waitForPendingResize() async throws {
            let deadline = ContinuousClock.now + .seconds(1)
            while waiters.isEmpty && ContinuousClock.now < deadline { await Task.yield() }
            try #require(!waiters.isEmpty, "The resize must wait until the visible animation has settled")
        }

        func finishPendingResize() async throws {
            try await waitForPendingResize()
            advance()
            for _ in 0..<10 { await Task.yield() }
        }
    }

    private func foregroundBounds(_ bitmap: NSBitmapImageRep, scale: CGFloat) throws -> [CGRect] {
        var bounds = [CGRect.null, CGRect.null]
        for x in 0..<bitmap.pixelsWide {
            for y in 0..<bitmap.pixelsHigh {
                let color = try #require(bitmap.colorAt(x: x, y: y))
                if min(color.redComponent, color.greenComponent, color.blueComponent) > 0.5 {
                    let side = x < bitmap.pixelsWide / 2 ? 0 : 1
                    bounds[side] = bounds[side].union(CGRect(x: CGFloat(x) / scale, y: CGFloat(y) / scale,
                        width: 1 / scale, height: 1 / scale))
                }
            }
        }
        #expect(bounds.allSatisfy { !$0.isNull }, "Both the provider icon and task count must be visible")
        return bounds
    }

    private func renderOffscreen(_ content: some View, size: CGSize) async throws -> NSBitmapImageRep {
        let host = NSHostingView(rootView: content.frame(width: size.width, height: size.height)
            .background(.black))
        host.sizingOptions = []
        let window = NSWindow(contentRect: CGRect(origin: CGPoint(x: 20_000, y: 0), size: size),
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
        let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: bitmap)
        #expect(host.bounds.size == size && window.alphaValue == 0)
        return try #require(bitmap.converting(to: .sRGB, renderingIntent: .default))
    }
}

private enum SampledReadingTimeKey: EnvironmentKey {
    static let defaultValue: TimeInterval = 0
}

private extension EnvironmentValues {
    var sampledReadingTime: TimeInterval {
        get { self[SampledReadingTimeKey.self] }
        set { self[SampledReadingTimeKey.self] = newValue }
    }
}
