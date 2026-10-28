import AppKit
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
        try click(add.accessibilityFrame(), in: window)
        await settle(host)
        try click(try #require(element("screenRecording.multitrackAddTrack", in: host)).accessibilityFrame(), in: window)
        await settle(host)
        #expect(model.timeline?.tracks.count == 3 && Set(model.timeline?.tracks.map(\.id) ?? []).count == 3)
        #expect(element("screenRecording.clipStart", in: host) != nil && labelled("导出设置", in: host) == nil)
        #expect(labelled("视频轨道", in: host) == nil && labelled("图片轨道", in: host) == nil
            && labelled("文字轨道", in: host) == nil && labelled("音频轨道", in: host) == nil)
        try click(try #require(element("screenRecording.undo", in: host)).accessibilityFrame(), in: window)
        await settle(host)
        #expect(model.timeline?.tracks.count == 2 && model.canRedo)
        try click(try #require(element("screenRecording.redo", in: host)).accessibilityFrame(), in: window)
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
        model.install(fixture.project(), directory: fixture.directory)
        model.update { $0.name = "Unsaved" }
        let edited = try #require(model.project)
        let files = try fixture.files()
        await settle(host)
        try click(try #require(element("screenRecording.export", in: host)).accessibilityFrame(), in: window)
        await settle(host)
        #expect(panels.count == 1 && model.isChoosingFile && model.operationTask == nil)
        #expect(panels.first?.accessoryView is NSHostingView<ScreenRecordingExportSettingsView>)
        for identifier in ["screenRecording.projectMenu", "screenRecording.undo", "screenRecording.redo", "screenRecording.export"] {
            let control = try #require(element(identifier, in: host) as? NSObject)
            let enabled = try #require(control.value(forKey: "isAccessibilityEnabled") as? Bool)
            #expect(!enabled, "Output destination selection must disable \(identifier)")
        }
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
        try click(try #require(element("screenRecording.addMedia." + image.id.uuidString, in: host)).accessibilityFrame(), in: window)
        await settle(host)
        let addedID = try #require(model.selectedTimelineClipID)
        #expect(model.timeline?.clips.count == 2 && model.selectedTimelineClip?.content == .image(image.id))
        model.seekTimeline(to: 1)
        await settle(host)
        try click(try #require(element("screenRecording.multitrackSplit", in: host)).accessibilityFrame(), in: window)
        await settle(host)
        let tail = try #require(model.selectedTimelineClip)
        #expect(tail.id != addedID && tail.sourceStart == 1 && tail.start == 1 && model.timeline?.clips.count == 3)
        try click(try #require(element("screenRecording.multitrackDuplicate", in: host)).accessibilityFrame(), in: window)
        await settle(host)
        #expect(model.selectedTimelineClip?.id != tail.id && model.selectedTimelineClip?.start == 2)
        try click(try #require(element("screenRecording.multitrackDelete", in: host)).accessibilityFrame(), in: window)
        await settle(host)
        #expect(model.timeline?.clips.count == 3)
        for _ in 0..<4 { model.undo() }
        #expect(model.project == project && !model.canUndo)
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

    private func click(_ frame: CGRect, in window: NSWindow) throws {
        let point = window.convertPoint(fromScreen: CGPoint(x: frame.midX, y: frame.midY))
        for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
            window.sendEvent(try #require(NSEvent.mouseEvent(with: type, location: point, modifierFlags: [],
                timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber, context: nil,
                eventNumber: 0, clickCount: 1, pressure: type == .leftMouseDown ? 1 : 0)))
        }
    }
}
