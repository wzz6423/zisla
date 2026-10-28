import AppKit
import Testing
import ZislaCore
import ZislaKit

@testable import Zisla

@Suite
struct ScreenRecordingCaptureBarTests {
    @MainActor
    @Test(arguments: [RecordingCaptureMode.display, .region])
    func switchingModesResizesTheExistingPanelWithoutTrailingSpace(initialMode: RecordingCaptureMode) async throws {
        var dependencies = ScreenRecordingCaptureDependencies.live
        dependencies.loadSources = { [.init(id: .max, name: "内建视网膜显示器", mode: .display,
                                            frame: .init(x: 0, y: 0, width: 1920, height: 1080))] }
        dependencies.loadDevices = { .init() }
        let model = ScreenRecordingStudioModel(capture: .init(dependencies: dependencies))
        await model.loadSources()
        model.selectMode(initialMode)
        defer { model.shutdown() }
        var presentationRequested = false
        let controller = ScreenRecordingCaptureBarController(model: model, languageStore: AppLanguageStore(),
            selectRegion: {}, start: {}, openStudio: {}, cancel: {},
            presentPanel: { _ in presentationRequested = true })
        defer { controller.shutdown() }
        let window = try #require(controller.hostingView.window)
        func settleLayout() async {
            for _ in 0..<6 {
                await withCheckedContinuation { continuation in DispatchQueue.main.async { continuation.resume() } }
                controller.hostingView.layoutSubtreeIfNeeded()
            }
        }
        controller.present()
        await settleLayout()
        let original = window.frame
        #expect(presentationRequested)
        #expect(!window.isVisible, "The presentation boundary must keep automated layout tests off screen")
        for _ in 0..<2 {
            model.selectMode(initialMode == .display ? .region : .display)
            await settleLayout()
            let changed = window.frame
            let difference: CGFloat = initialMode == .display ? 30 : -30
            #expect(abs(changed.width - original.width - difference) < 0.5,
                    "The whole panel must follow its 28pt region button and 2pt spacing: \(original.width) -> \(changed.width)")
            #expect(changed.midX == original.midX && changed.midY == original.midY)
            model.selectMode(initialMode)
            await settleLayout()
            #expect(abs(window.frame.width - original.width) < 0.5,
                    "Restoring the original mode must restore the panel width without leaving trailing space")
            #expect(window.frame.height == original.height)
            #expect(!window.isVisible)
        }
    }

    @MainActor
    @Test
    func setupWidthTracksItsContentAndRegionButtonWithoutReservingTrailingSpace() async throws {
        let compact = try await measuredSetupWidth(sourceName: "A", mode: .display, viewportWidth: 604)
        let region = try await measuredSetupWidth(sourceName: "A", mode: .region, viewportWidth: 604)
        let long = try await measuredSetupWidth(sourceName: String(repeating: "Long display name ", count: 20),
                                               mode: .display, viewportWidth: 604)
        #expect(compact > 0 && compact < ScreenRecordingCaptureBarGeometry.setupWidth)
        #expect(abs(region - compact - 30) < 0.5, "Only the 28pt region button and normal 2pt spacing should be added")
        #expect(long > compact, "A short source name must reduce the panel width rather than leave trailing space")
        #expect(long - compact < 152, "Long source labels must retain their existing maximum width")
    }

    @MainActor
    @Test
    func narrowViewportPreservesScrollableContentWidth() async throws {
        let regular = try await measuredSetupWidth(sourceName: "A", mode: .region, viewportWidth: 604)
        let narrow = try await measuredSetupWidth(sourceName: "A", mode: .region, viewportWidth: 240)
        #expect(abs(regular - narrow) < 0.5, "A narrow panel must scroll the same contents instead of squeezing controls")
        let screen = CGRect(x: -500, y: -100, width: 240, height: 300)
        let panel = ScreenRecordingCaptureBarGeometry.panelFrame(size: .init(width: narrow, height: 38), in: screen)
        #expect(panel.width == 240)
        #expect(screen.contains(panel))
    }

    @MainActor
    private func measuredSetupWidth(sourceName: String, mode: RecordingCaptureMode, viewportWidth: CGFloat) async throws -> CGFloat {
        var dependencies = ScreenRecordingCaptureDependencies.live
        dependencies.loadSources = { [.init(id: 1, name: sourceName, mode: .display,
                                            frame: .init(x: 0, y: 0, width: 1920, height: 1080))] }
        dependencies.loadDevices = { .init() }
        let model = ScreenRecordingStudioModel(capture: .init(dependencies: dependencies))
        await model.loadSources()
        model.selectMode(mode)
        defer { model.shutdown() }
        let controller = ScreenRecordingCaptureBarController(model: model, languageStore: AppLanguageStore(),
            selectRegion: {}, start: {}, openStudio: {}, cancel: {})
        defer { controller.shutdown() }
        let host = controller.hostingView
        host.window?.setContentSize(.init(width: viewportWidth, height: 38))
        for _ in 0..<3 {
            host.layoutSubtreeIfNeeded()
            await withCheckedContinuation { continuation in DispatchQueue.main.async { continuation.resume() } }
        }
        #expect(host.window?.isVisible == false, "Layout tests must not present a toolbar")
        return controller.preferredSize.width
    }

    @Test
    func setupLeadingControlsUseCompactSpacing() {
        #expect(ScreenRecordingCaptureBarGeometry.dragHandleWidth == 24)
        #expect(ScreenRecordingCaptureBarGeometry.dragHandleWidth < ScreenshotToolbarLayout.dragHandleWidth)
        #expect(ScreenRecordingCaptureBarGeometry.closeButtonWidth == 24)
        #expect(ScreenRecordingCaptureBarGeometry.separatorHorizontalPadding == 1)
        #expect(ScreenRecordingCaptureBarGeometry.fixedSetupWidth == 440)
    }

    @Test
    func captureBarStartsInsideTheChosenScreenAndClampsDraggedPositions() {
        let screen = CGRect(x: -1_920, y: -500, width: 1_920, height: 1_055)
        let size = CGSize(width: ScreenRecordingCaptureBarGeometry.setupWidth, height: ScreenshotToolbarLayout.height)
        let initial = ScreenRecordingCaptureBarGeometry.panelFrame(size: size, in: screen)
        #expect(screen.contains(initial))
        #expect(initial.midX == screen.midX)
        #expect(initial.minY == screen.minY + 80)
        let outside = ScreenRecordingCaptureBarGeometry.panelFrame(size: size, in: screen,
            center: CGPoint(x: -10_000, y: 10_000))
        #expect(outside.minX == screen.minX)
        #expect(outside.maxY == screen.maxY)
        #expect(screen.contains(outside))
    }

    @Test
    func captureBarCanFitSmallerDisplaysAndKeepsItsCenterWhenRecordingBegins() {
        let smallScreen = CGRect(x: 0, y: 0, width: 640, height: 400)
        let setup = ScreenRecordingCaptureBarGeometry.panelFrame(
            size: .init(width: ScreenRecordingCaptureBarGeometry.setupWidth, height: ScreenshotToolbarLayout.height), in: smallScreen)
        #expect(setup.width == ScreenRecordingCaptureBarGeometry.setupWidth)
        #expect(smallScreen.contains(setup))
        let recording = ScreenRecordingCaptureBarGeometry.panelFrame(
            size: .init(width: ScreenRecordingCaptureBarGeometry.recordingWidth, height: ScreenshotToolbarLayout.height),
            in: smallScreen, center: CGPoint(x: setup.midX, y: setup.midY))
        #expect(recording.midX == setup.midX)
        #expect(recording.midY == setup.midY)
        #expect(recording.height == setup.height)
        #expect(smallScreen.contains(recording))
    }

    @Test(arguments: [600.0, 640.0, 704.0, 1_024.0], [false, true])
    func sourceTitleYieldsWidthSoTheSingleRowControlsStayInsideTheScreen(screenWidth: Double, showingError: Bool) {
        let screen = CGRect(x: 0, y: 0, width: screenWidth, height: 600).insetBy(dx: 12, dy: 12)
        let panel = ScreenRecordingCaptureBarGeometry.panelFrame(
            size: .init(width: ScreenRecordingCaptureBarGeometry.setupWidth, height: ScreenshotToolbarLayout.height), in: screen)
        let rowWidth = panel.width - (showingError ? 30 : 0)
        let sourceWidth = ScreenRecordingCaptureBarGeometry.sourceWidth(availableWidth: rowWidth)
        #expect(screen.contains(panel))
        #expect(panel.height == ScreenshotToolbarLayout.height)
        #expect(sourceWidth >= 32)
        #expect(sourceWidth <= 152)
        #expect(ScreenRecordingCaptureBarGeometry.fixedSetupWidth + sourceWidth <= rowWidth)
    }

    @Test
    func regionSelectionIsEnabledForValidWindowAndDisplaySourcesOnly() {
        let window = RecordingCaptureSource(id: 42, name: "Example", mode: .window,
            frame: .init(x: 10, y: 20, width: 800, height: 600))
        let display = RecordingCaptureSource(id: 7, name: "Display", mode: .display,
            frame: .init(x: 0, y: 0, width: 1_920, height: 1_080))

        #expect(ScreenRecordingCaptureBarGeometry.canSelectRegion(
            configuration: .init(mode: .window, sourceID: 42), sources: [window], displayIDs: [7]))
        #expect(!ScreenRecordingCaptureBarGeometry.canSelectRegion(
            configuration: .init(mode: .window, sourceID: 42), sources: [window], displayIDs: []))
        #expect(!ScreenRecordingCaptureBarGeometry.canSelectRegion(
            configuration: .init(mode: .window, sourceID: 42), sources: [
                .init(id: 42, name: "Gone", mode: .window, frame: .init(x: 0, y: 0, width: -1, height: 10)),
            ], displayIDs: [7]))
        #expect(ScreenRecordingCaptureBarGeometry.canSelectRegion(
            configuration: .init(mode: .display, sourceID: 7), sources: [display], displayIDs: [7]))
        #expect(!ScreenRecordingCaptureBarGeometry.canSelectRegion(
            configuration: .init(mode: .display, sourceID: 8), sources: [display], displayIDs: [7]))
    }

    @Test
    func selectedDisplayOutlineUsesTheMatchingAppKitScreen() {
        let primary = CGRect(x: 0, y: 0, width: 1_920, height: 1_080)
        let secondary = CGRect(x: -1_280, y: -200, width: 1_280, height: 1_024)
        let sources: [RecordingCaptureSource] = [
            .init(id: 1, name: "Primary", mode: .display, frame: .init(x: 0, y: 0, width: 1_920, height: 1_080)),
            .init(id: 2, name: "Secondary", mode: .display, frame: .init(x: -1_280, y: 256, width: 1_280, height: 1_024))
        ]
        #expect(ScreenRecordingCaptureBarGeometry.targetFrame(configuration: .init(sourceID: 2), sources: sources,
            screenFrames: [1: primary, 2: secondary], primaryScreenFrame: primary) == secondary)
        #expect(ScreenRecordingCaptureBarGeometry.targetFrame(configuration: .init(sourceID: 3), sources: sources,
            screenFrames: [1: primary, 2: secondary], primaryScreenFrame: primary) == nil)
        #expect(ScreenRecordingCaptureBarGeometry.targetFrame(configuration: .init(sourceID: 2), sources: sources,
            screenFrames: [1: primary], primaryScreenFrame: primary) == nil)
    }

    @Test
    func regionOutlineConvertsTopLeftCoordinatesAndClipsToTheSelectedScreen() {
        let primary = CGRect(x: 0, y: 0, width: 1_920, height: 1_080)
        let screen = CGRect(x: -1_280, y: -200, width: 1_280, height: 1_024)
        let source = RecordingCaptureSource(id: 2, name: "Secondary", mode: .display,
            frame: .init(x: -1_280, y: 256, width: 1_280, height: 1_024))
        func frame(_ region: RecordingRect?) -> CGRect? {
            ScreenRecordingCaptureBarGeometry.targetFrame(configuration: .init(mode: .region, sourceID: 2, region: region),
                sources: [source], screenFrames: [2: screen], primaryScreenFrame: primary)
        }
        #expect(frame(.init(x: 100, y: 40, width: 500, height: 300))
            == CGRect(x: -1_180, y: 484, width: 500, height: 300))
        #expect(frame(.init(x: 1_200, y: 900, width: 200, height: 200))
            == CGRect(x: -80, y: -200, width: 80, height: 124))
        #expect(frame(nil) == nil)
        #expect(frame(.init(x: 0, y: 0, width: 0, height: 100)) == nil)
        #expect(frame(.init(x: .infinity, y: 0, width: 100, height: 100)) == nil)
        #expect(frame(.init(x: 2_000, y: 0, width: 100, height: 100))?.isNull == true)
    }

    @Test
    func windowOutlineUsesQuartzGlobalCoordinatesWithoutMatchingASeparateScreenID() {
        let primary = CGRect(x: 0, y: 0, width: 1_920, height: 1_080)
        let window = RecordingCaptureSource(id: 42, name: "Example", mode: .window,
            frame: .init(x: -1_000, y: 200, width: 800, height: 600))
        let displayWithSameID = RecordingCaptureSource(id: 42, name: "Display", mode: .display,
            frame: .init(x: 0, y: 0, width: 1_920, height: 1_080))
        #expect(ScreenRecordingCaptureBarGeometry.targetFrame(configuration: .init(mode: .window, sourceID: 42),
            sources: [displayWithSameID, window], screenFrames: [:], primaryScreenFrame: primary)
            == CGRect(x: -1_000, y: 280, width: 800, height: 600))
        #expect(ScreenRecordingCaptureBarGeometry.targetFrame(configuration: .init(mode: .display, sourceID: 42),
            sources: [window], screenFrames: [:], primaryScreenFrame: primary) == nil)
        let invalid = RecordingCaptureSource(id: 43, name: "Gone", mode: .window,
            frame: .init(x: 0, y: 0, width: -10, height: 100))
        #expect(ScreenRecordingCaptureBarGeometry.targetFrame(configuration: .init(mode: .window, sourceID: 43),
            sources: [invalid], screenFrames: [:], primaryScreenFrame: primary) == nil)
    }
}
