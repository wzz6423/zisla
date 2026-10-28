import AppKit
import AVFoundation
import SwiftUI
import Testing
import ZislaCore
import ZislaKit
@testable import Zisla

@MainActor
@Suite(.serialized)
struct ScreenRecordingMultitrackUITests {
    @Test(arguments: [AppLanguage.simplifiedChinese, .english, .arabic], [960.0, 1_280.0])
    func studioShowsTheLibraryUniversalTracksAndKeepsOutputControlsInTheToolbar(_ language: AppLanguage, _ width: Double) async throws {
        let previousArguments = UserDefaults.standard.volatileDomain(forName: UserDefaults.argumentDomain)
        var arguments = previousArguments
        arguments[AppLocalization.defaultsKey] = language.rawValue
        UserDefaults.standard.setVolatileDomain(arguments, forName: UserDefaults.argumentDomain)
        defer { UserDefaults.standard.setVolatileDomain(previousArguments, forName: UserDefaults.argumentDomain) }
        let fixture = try RecordingMultitrackTestFixture()
        let model = try fixture.model()
        defer { model.shutdown(); fixture.remove() }
        model.install(fixture.project(), directory: fixture.directory)
        let releaseAccessibility = EnhancedAccessibilityTestScope.acquire()
        defer { releaseAccessibility() }
        let host = NSHostingView(rootView: ScreenRecordingStudioView(model: model,
            languageStore: AppLanguageStore(), prepareCapture: {}))
        host.sizingOptions = []
        let window = mount(host, width: width, height: 800)
        defer { window.contentView = nil; window.close() }
        await settle(host)
        #expect(element("screenRecording.mediaLibrary", in: host) != nil)
        #expect(element("screenRecording.multitrackTimeline", in: host) != nil)
        #expect(element("screenRecording.clipStart", in: host) != nil,
            "A new recording must expose multitrack editing before timeline migration is persisted")
        #expect(element("screenRecording.detachAudio", in: host) != nil)
        #expect(labelled("导出设置", in: host) == nil,
            "Export settings belong to the export dialog rather than the editing inspector")
        #expect(element("screenRecording.export", in: host) != nil && labelled("录制设置", in: host) == nil)
        let projectMenu = try #require(element("screenRecording.projectMenu", in: host))
        let undo = try #require(element("screenRecording.undo", in: host))
        let redo = try #require(element("screenRecording.redo", in: host))
        let export = try #require(element("screenRecording.export", in: host))
        let title = try #require(labelled("录屏工作室", in: host) as? any NSAccessibilityElementProtocol)
        let frames = [title, projectMenu, undo, redo, export].map {
            host.convert(window.convertFromScreen($0.accessibilityFrame()), from: nil)
        }
        for (first, next) in zip(frames, frames.dropFirst()) {
            #expect(language.isRightToLeft ? first.minX > next.maxX : first.maxX < next.minX,
                "The project menu must stay beside the title, followed by undo, redo and export in the interface direction")
        }
        for frame in frames {
            #expect(frame.width > 0 && frame.height > 0 && host.bounds.insetBy(dx: -0.5, dy: -0.5).contains(frame),
                "Toolbar controls must remain inside the studio at its minimum width")
        }
        #expect(language.isRightToLeft ? frames[1].midX > host.bounds.midX : frames[1].midX < host.bounds.midX,
            "The project menu belongs to the title side of the studio")
        let naturalExport = NSHostingView(rootView: Button(AppLocalization.text("导出录屏")) {})
        #expect(frames[4].width + 0.5 >= naturalExport.fittingSize.width,
            "The export button must show its complete translation")
        #expect(try #require((export as? NSObject)?.value(forKey: "isAccessibilityEnabled") as? Bool))
        #expect(model.project?.timeline == nil && !model.isDirty && !model.canUndo)
        let add = try #require(element("screenRecording.multitrackAddTrack", in: host))
        try press(add)
        await settle(host)
        try press(try #require(element("screenRecording.multitrackAddTrack", in: host)))
        await settle(host)
        #expect(model.timeline?.tracks.count == 3 && Set(model.timeline?.tracks.map(\.id) ?? []).count == 3)
        #expect(model.selectedTimelineClipID == nil && model.selectedTimelineTrackID == model.timeline?.tracks.last?.id)
        #expect(element("screenRecording.clipStart", in: host) == nil && labelled("导出设置", in: host) == nil)
        #expect(element("screenRecording.multitrackAddText", in: host) == nil)
        #expect(element("screenRecording.multitrackDuplicate", in: host) == nil && labelled("播放原始素材", in: host) == nil)
        #expect(labelled("视频轨道", in: host) == nil && labelled("图片轨道", in: host) == nil
            && labelled("文字轨道", in: host) == nil && labelled("音频轨道", in: host) == nil)
        try press(try #require(element("screenRecording.undo", in: host)))
        await settle(host)
        #expect(model.timeline?.tracks.count == 2 && model.canRedo)
        try press(try #require(element("screenRecording.redo", in: host)))
        await settle(host)
        #expect(model.timeline?.tracks.count == 3 && !model.canRedo)
        #expect(NSScreen.screens.allSatisfy { !$0.frame.intersects(window.frame) } && !window.isKeyWindow)
    }

    @Test func toolbarExportDisablesEditingUntilTheDestinationDecisionIsCancelled() async throws {
        let fixture = try RecordingMultitrackTestFixture()
        var panels: [NSSavePanel] = []
        var complete: ((URL?) -> Void)?
        let model = ScreenRecordingStudioModel(projectStore: fixture.store,
            renderPreview: { _, _, _ in throw ScreenRecordingExportError.cannotRender },
            presentExportPanel: { panel, completion in panels.append(panel); complete = completion })
        defer { model.shutdown(); fixture.remove() }
        let releaseAccessibility = EnhancedAccessibilityTestScope.acquire()
        defer { releaseAccessibility() }
        let host = NSHostingView(rootView: ScreenRecordingStudioView(model: model,
            languageStore: AppLanguageStore(), prepareCapture: {}))
        host.sizingOptions = []
        let window = mount(host, width: 960, height: 800)
        defer { window.contentView = nil; window.close() }
        await settle(host)
        let export = try #require(element("screenRecording.export", in: host) as? NSObject)
        let emptyExportEnabled = try #require(export.value(forKey: "isAccessibilityEnabled") as? Bool)
        #expect(!emptyExportEnabled && panels.isEmpty)
        try press(try #require(element("screenRecording.export", in: host)))
        await settle(host)
        #expect(panels.isEmpty && model.project == nil && !model.isChoosingFile)
        model.install(fixture.project(), directory: fixture.directory)
        model.update { $0.name = "Unsaved" }
        let edited = try #require(model.project)
        let files = try fixture.files()
        await settle(host)
        try press(try #require(element("screenRecording.export", in: host)))
        #expect(panels.count == 1 && model.isChoosingFile && model.operationTask == nil)
        await settle(host)
        #expect(panels.count == 1 && model.isChoosingFile && model.operationTask == nil)
        #expect(panels.first?.accessoryView is NSHostingView<ScreenRecordingExportSettingsView>)
        for identifier in ["screenRecording.projectMenu", "screenRecording.undo", "screenRecording.redo", "screenRecording.export"] {
            let control = try #require(element(identifier, in: host) as? NSObject)
            let enabled = try #require(control.value(forKey: "isAccessibilityEnabled") as? Bool)
            #expect(!enabled, "Output destination selection must disable \(identifier)")
        }
        for identifier in ["screenRecording.undo", "screenRecording.redo", "screenRecording.export"] {
            try press(try #require(element(identifier, in: host)))
        }
        await settle(host)
        #expect(panels.count == 1 && model.project == edited && model.isChoosingFile)
        let cancelDestination = try #require(complete)
        cancelDestination(nil)
        await settle(host)
        #expect(model.project == edited && model.isDirty && model.canUndo && !model.isChoosingFile)
        #expect(model.canExport && model.operationTask == nil && panels.first?.accessoryView == nil)
        #expect(try fixture.files() == files, "Cancelling export must leave the project files untouched")
        #expect(NSScreen.screens.allSatisfy { !$0.frame.intersects(window.frame) } && !window.isKeyWindow)
    }

    @Test func libraryAddAndTimelineButtonsEditOnlyTheSelectedClipWithUndo() async throws {
        let fixture = try RecordingMultitrackTestFixture()
        let model = try fixture.model()
        defer { model.shutdown(); fixture.remove() }
        _ = try fixture.createImage()
        var project = fixture.project()
        var timeline = RecordingMultitrackTimeline.migrating(project)
        let image = RecordingMediaAsset(name: "Picture", file: "picture.png", kind: .image, duration: 2, width: 64, height: 48)
        timeline.assets.append(image)
        project.timeline = timeline
        model.install(project, directory: fixture.directory)
        let releaseAccessibility = EnhancedAccessibilityTestScope.acquire()
        defer { releaseAccessibility() }
        let host = NSHostingView(rootView: HStack(spacing: 0) {
            ScreenRecordingMediaLibraryView(model: model).frame(width: 220)
            ScreenRecordingMultitrackTimelineView(model: model).frame(width: 700)
        })
        host.sizingOptions = []
        let window = mount(host, width: 920, height: 240)
        defer { window.contentView = nil; window.close() }
        await settle(host)
        try press(try #require(element("screenRecording.addMedia." + image.id.uuidString, in: host)))
        await settle(host)
        let addedID = try #require(model.selectedTimelineClipID)
        #expect(model.timeline?.clips.count == 2 && model.selectedTimelineClip?.content == .image(image.id))
        model.seekTimeline(to: 1)
        await settle(host)
        try press(try #require(element("screenRecording.multitrackSplit", in: host)))
        await settle(host)
        let tail = try #require(model.selectedTimelineClip)
        #expect(tail.id != addedID && tail.sourceStart == 1 && tail.start == 1 && model.timeline?.clips.count == 3)
        #expect(model.copyTimelineClip(tail.id))
        #expect(model.timeline?.clips.count == 3 && model.selectedTimelineClip?.id == tail.id)
        model.seekTimeline(to: tail.end)
        #expect(model.pasteTimelineClip() != nil)
        await settle(host)
        #expect(model.selectedTimelineClip?.id != tail.id && model.selectedTimelineClip?.start == 2)
        try press(try #require(element("screenRecording.multitrackDelete", in: host)))
        await settle(host)
        #expect(model.timeline?.clips.count == 3)
        for _ in 0..<4 { model.undo() }
        #expect(model.project == project && !model.canUndo)
    }

    @Test(arguments: [false, true])
    func selectingTheSameTextAgainExplicitlyOpensItsInspectorAndCopyPasteButtonsHaveObservableFeedback(_ caption: Bool) async throws {
        let fixture = try RecordingMultitrackTestFixture()
        let model = try fixture.model()
        defer { model.shutdown(); fixture.remove() }
        var project = fixture.project()
        if caption { project.captions = [.init(start: 0, end: 1, text: "Caption")] }
        else { project.edits.annotations = [.init(kind: .text, start: 0, end: 1, text: "Annotation")] }
        project.timeline = .migrating(project)
        model.install(project, directory: fixture.directory)
        model.selectTimelineClip(try #require(model.timeline?.clips.first { $0.content.trackKind == .text }?.id))
        let releaseAccessibility = EnhancedAccessibilityTestScope.acquire()
        defer { releaseAccessibility() }
        let host = NSHostingView(rootView: ScreenRecordingStudioView(model: model,
            languageStore: AppLanguageStore(), prepareCapture: {}))
        host.sizingOptions = []
        let window = mount(host, width: 1_180, height: 800)
        defer { window.contentView = nil; window.close() }
        await settle(host)
        model.inspectorTab = 0
        model.seekTimeline(to: 0.5)
        await settle(host)
        try press(try #require(element("screenRecording.editClipText", in: host)))
        await settle(host)
        #expect(model.inspectorTab == (caption ? 2 : 1) && model.playbackTime == 0)
        model.inspectorTab = 0
        await settle(host)
        let original = model.project
        try press(try #require(element("screenRecording.copyClip", in: host)))
        await settle(host)
        #expect(model.project == original && !model.canUndo && model.canPasteTimelineClip)
        #expect(labelled("已复制", in: host) != nil)
        model.seekTimeline(to: 1)
        await settle(host)
        try press(try #require(element("screenRecording.pasteClip", in: host)))
        await settle(host)
        #expect(model.timeline?.clips.count == project.timeline!.clips.count + 1 && model.selectedTimelineClip?.start == 1)
        #expect(model.selectedTimelineClip?.content != project.timeline?.clips.first { $0.content.trackKind == .text }?.content)
        model.undo()
        #expect(model.project == original && !model.canUndo)
        #expect(!window.isKeyWindow && NSScreen.screens.allSatisfy { !$0.frame.intersects(window.frame) })
    }

    @Test
    func selectingATimelineClipAfterEditingTextMovesCopyPasteFocusToTheTimeline() async throws {
        let fixture = try RecordingMultitrackTestFixture()
        let model = try fixture.model()
        defer { model.shutdown(); fixture.remove() }
        model.install(fixture.project(), directory: fixture.directory)
        let releaseAccessibility = EnhancedAccessibilityTestScope.acquire()
        defer { releaseAccessibility() }
        let host = NSHostingView(rootView: ScreenRecordingMultitrackTimelineView(model: model))
        host.sizingOptions = []
        let window = ScreenRecordingStudioWindow(contentRect: .init(x: -100_000, y: -100_000, width: 700, height: 240),
            styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.studioModel = model
        window.contentView = host
        window.orderFrontRegardless()
        defer { window.contentView = nil; window.close() }
        let editor = TimelineTextActionProbe(frame: .init(x: -1_000, y: -1_000, width: 200, height: 60))
        host.addSubview(editor)
        try #require(window.makeFirstResponder(editor))
        await settle(host)
        let original = model.project
        let key = try #require(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: .command, timestamp: 0,
            windowNumber: window.windowNumber, context: nil, characters: "c", charactersIgnoringModifiers: "c",
            isARepeat: false, keyCode: 8))
        #expect(window.performKeyEquivalent(with: key) && editor.copies == 1 && !model.canPasteTimelineClip)
        let clip = try #require(model.selectedTimelineClip)
        let clipElement = try #require(element("screenRecording.multitrackClip." + clip.id, in: host))
        let frame = window.convertFromScreen(clipElement.accessibilityFrame())
        for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
            let event = try #require(NSEvent.mouseEvent(with: type, location: .init(x: frame.minX + 40, y: frame.midY),
                modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber, context: nil,
                eventNumber: 1, clickCount: 1, pressure: type == .leftMouseDown ? 1 : 0))
            window.sendEvent(event)
        }
        await settle(host)
        #expect(!(window.firstResponder is NSTextView), "Selecting a clip must end input focus before copying the clip")
        #expect(model.selectedTimelineClipID == clip.id, "The click must select the clip rather than the surrounding track")
        #expect(window.performKeyEquivalent(with: key) && model.canPasteTimelineClip && editor.copies == 1)
        #expect(model.project == original && !model.canUndo && !window.isKeyWindow)
        try #require(window.makeFirstResponder(editor))
        try press(try #require(element("screenRecording.multitrackAddTrack", in: host)))
        await settle(host)
        #expect(!(window.firstResponder is NSTextView) && model.selectedTimelineClipID == nil)
        let track = try #require(model.selectedTimelineTrackID)
        let paste = try #require(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: .command, timestamp: 0,
            windowNumber: window.windowNumber, context: nil, characters: "v", charactersIgnoringModifiers: "v",
            isARepeat: false, keyCode: 9))
        #expect(window.performKeyEquivalent(with: paste))
        #expect(model.selectedTimelineClip?.trackID == track && model.timeline?.clips.count == 2)
        model.undo()
        model.undo()
        #expect(model.project == original && !model.canUndo)
    }

    @Test
    func draggingAClipAndItsTwoEdgesCommitsOnlyOneUndoableEditAndEscapeCancelsTheGesture() async throws {
        let fixture = try RecordingMultitrackTestFixture()
        let model = try fixture.model()
        defer { model.shutdown(); fixture.remove() }
        model.install(fixture.project(), directory: fixture.directory)
        let releaseAccessibility = EnhancedAccessibilityTestScope.acquire()
        defer { releaseAccessibility() }
        let host = NSHostingView(rootView: ScreenRecordingMultitrackTimelineView(model: model))
        host.sizingOptions = []
        let window = ScreenRecordingStudioWindow(contentRect: .init(x: -100_000, y: -100_000, width: 700, height: 240),
            styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.studioModel = model
        window.contentView = host
        window.orderFrontRegardless()
        defer { window.contentView = nil; window.close() }
        await settle(host)
        let original = try #require(model.project)
        let clip = try #require(model.selectedTimelineClip)
        let clipElement = try #require(element("screenRecording.multitrackClip." + clip.id, in: host))
        let frame = window.convertFromScreen(clipElement.accessibilityFrame())
        let geometry = try #require(ScreenRecordingTimelineStripGeometry(segments: [.init(start: 0, end: 10)],
            viewportWidth: frame.width, zoom: 1))
        func send(_ type: NSEvent.EventType, _ point: CGPoint) throws {
            let event = try #require(NSEvent.mouseEvent(with: type, location: point, modifierFlags: [],
                timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber, context: nil,
                eventNumber: 1, clickCount: 1, pressure: type == .leftMouseUp ? 0 : 1))
            window.sendEvent(event)
        }
        for mode in [RecordingMultitrackClipDrag.Mode.trimStart, .trimEnd, .move] {
            let start = CGPoint(x: frame.minX + (mode == .trimStart ? 6 : mode == .trimEnd ? clip.duration * geometry.pointsPerSecond - 6 : 40),
                y: frame.midY)
            let delta = geometry.pointsPerSecond * (mode == .trimEnd ? -0.5 : 0.5)
            let end = CGPoint(x: start.x + delta, y: start.y)
            try send(.leftMouseDown, start)
            try send(.leftMouseDragged, end)
            await settle(host)
            #expect(model.project == original && !model.canUndo, "A drag must remain a preview until mouse-up")
            try send(.leftMouseUp, end)
            await settle(host)
            let changed = try #require(model.selectedTimelineClip)
            switch mode {
            case .trimStart:
                #expect(abs(changed.start - 0.5) < 0.000_001 && abs(changed.sourceStart - 0.5) < 0.000_001 && changed.end == 2)
            case .trimEnd:
                #expect(changed.start == 0 && abs(changed.sourceEnd - 1.5) < 0.000_001)
            case .move:
                #expect(abs(changed.start - 0.5) < 0.000_001 && changed.sourceStart == 0 && changed.sourceEnd == 2)
            }
            model.undo()
            #expect(model.project == original && !model.canUndo)
            await settle(host)
        }
        let start = CGPoint(x: frame.minX + 40, y: frame.midY)
        try send(.leftMouseDown, start)
        try send(.leftMouseDragged, .init(x: start.x + 30, y: start.y))
        await settle(host)
        let escape = try #require(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [],
            timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber, context: nil,
            characters: "\u{1b}", charactersIgnoringModifiers: "\u{1b}", isARepeat: false, keyCode: 53))
        window.sendEvent(escape)
        await settle(host)
        try send(.leftMouseDragged, .init(x: start.x + 50, y: start.y))
        try send(.leftMouseUp, .init(x: start.x + 50, y: start.y))
        await settle(host)
        #expect(model.project == original && !model.canUndo && !window.isKeyWindow,
            "Escape must keep later movement and release in the same gesture from changing the project")
    }

    @Test
    func previewClipStartButtonSeeksTheSelectedTextAndStartsTheCompositedTimelinePlayer() async throws {
        let fixture = try RecordingMultitrackTestFixture()
        let model = try fixture.model()
        defer { model.shutdown(); fixture.remove() }
        _ = try await fixture.createVideo()
        var project = fixture.project()
        project.edits.annotations = [.init(kind: .text, start: 0.25, end: 1.5, text: "Preview text")]
        project.timeline = .migrating(project)
        model.install(project, directory: fixture.directory)
        let text = try #require(model.timeline?.clips.first { $0.content.trackKind == .text })
        model.selectTimelineClip(text.id)
        model.seekTimeline(to: 1)
        let releaseAccessibility = EnhancedAccessibilityTestScope.acquire()
        defer { releaseAccessibility() }
        let host = NSHostingView(rootView: ScrollView { ScreenRecordingMultitrackClipInspector(model: model) })
        host.sizingOptions = []
        let window = mount(host, width: 400, height: 700)
        defer { window.contentView = nil; window.close() }
        await settle(host)
        try press(try #require(element("screenRecording.previewClipStart", in: host)))
        #expect(model.playbackTime == text.start)
        await model.operationTask?.value
        let item = try #require(model.activePlayer?.currentItem)
        #expect(model.isShowingTimelinePlayback && !model.isShowingSourcePlayback)
        #expect(item.videoComposition?.customVideoCompositorClass == RecordingMultitrackPlaybackCompositor.self)
        #expect(model.project == project && !model.canUndo)
        model.playTimeline()
        #expect(!model.isShowingTimelinePlayback && !window.isKeyWindow)
    }

    @Test func multitrackPinchScalesTheHorizontalDocumentWithoutMovingHeadersOrEditingTheProject() async throws {
        let fixture = try RecordingMultitrackTestFixture()
        let model = try fixture.model()
        defer { model.shutdown(); fixture.remove() }
        model.install(fixture.project(), directory: fixture.directory)
        model.seekTimeline(to: 1)
        let original = model.project
        let host = NSHostingView(rootView: ScreenRecordingMultitrackTimelineView(model: model).frame(width: 800))
        let window = mount(host, width: 800, height: 200)
        defer { window.contentView = nil; window.close() }
        await settle(host)
        func adapter(_ view: NSView) -> ScreenRecordingTimelineMagnificationView? {
            if let found = view as? ScreenRecordingTimelineMagnificationView { return found }
            return view.subviews.lazy.compactMap(adapter).first
        }
        let magnification = try #require(adapter(host))
        let scroll = try #require(magnification.magnificationRecognizer.view as? NSScrollView)
        let document = try #require(scroll.documentView)
        let width = document.frame.width
        let frame = scroll.convert(scroll.bounds, to: host)
        #expect(frame.minX >= 150, "Track headers must remain outside the horizontally scrolling document")
        magnification.magnify(by: 1, phase: .began, location: 208)
        await settle(host)
        #expect(abs(document.frame.width - ((width - 16) * 2 + 16)) < 1)
        #expect(abs(scroll.contentView.bounds.minX - 200) < 1)
        #expect(scroll.convert(scroll.bounds, to: host).minX == frame.minX)
        magnification.magnify(by: 1, phase: .ended, location: 408)
        #expect(model.project == original && !model.isDirty && !model.canUndo && model.playbackTime == 1)
    }

    private func mount(_ host: NSView, width: CGFloat, height: CGFloat) -> NSPanel {
        if let hosting = host as? NSHostingView<ScreenRecordingMultitrackTimelineView> { hosting.sizingOptions = [] }
        let window = NSPanel(contentRect: .init(x: -100_000, y: -100_000, width: width, height: height),
            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        window.orderFrontRegardless()
        return window
    }

    private func settle(_ host: NSView) async {
        for _ in 0..<3 {
            host.layoutSubtreeIfNeeded()
            host.displayIfNeeded()
            await withCheckedContinuation { continuation in DispatchQueue.main.async { continuation.resume() } }
        }
    }

    private func objects(in root: NSObject) -> [NSObject] {
        var values = [root]
        if root.responds(to: NSSelectorFromString("accessibilityChildren")) {
            for child in root.value(forKey: "accessibilityChildren") as? [NSObject] ?? [] { values += objects(in: child) }
        }
        return values
    }

    private func element(_ identifier: String, in host: NSView) -> (any NSAccessibilityElementProtocol)? {
        let found = objects(in: host).first {
            $0.responds(to: NSSelectorFromString("accessibilityIdentifier")) && $0.value(forKey: "accessibilityIdentifier") as? String == identifier
        } as? any NSAccessibilityElementProtocol
        if let found { return found }
        return host.subviews.lazy.compactMap { element(identifier, in: $0) }.first
    }

    private func labelled(_ label: String, in host: NSView) -> NSObject? {
        objects(in: host).first { object in
            ["accessibilityLabel", "accessibilityValue"].contains {
                object.responds(to: NSSelectorFromString($0)) && object.value(forKey: $0) as? String == AppLocalization.text(label)
            }
        }
    }

    private func press(_ element: any NSAccessibilityElementProtocol) throws {
        let object = try #require(element as? NSObject)
        let action = NSSelectorFromString("accessibilityPerformPress")
        try #require(object.responds(to: action))
        object.performSelector(onMainThread: action, with: nil, waitUntilDone: true)
    }
}

private final class TimelineTextActionProbe: NSTextView {
    var copies = 0
    override func copy(_ sender: Any?) { copies += 1 }
}
