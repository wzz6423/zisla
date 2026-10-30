import AppKit
import SwiftUI
import Testing
import ZislaCore
import ZislaKit
@testable import Zisla

@Suite(.serialized) @MainActor
struct ScreenRecordingClipAnimationInspectorTests {
    @Test(arguments: [AppLanguage.simplifiedChinese, .english, .arabic])
    func animationControlsStartEmptyApplyOnlyOnUserSelectionAndPreserveDurationWithUndo(_ language: AppLanguage) async throws {
        let previous = UserDefaults.standard.volatileDomain(forName: UserDefaults.argumentDomain)
        var arguments = previous
        arguments[AppLocalization.defaultsKey] = language.rawValue
        UserDefaults.standard.setVolatileDomain(arguments, forName: UserDefaults.argumentDomain)
        defer { UserDefaults.standard.setVolatileDomain(previous, forName: UserDefaults.argumentDomain) }
        let fixture = try RecordingMultitrackTestFixture()
        let model = try fixture.model()
        defer { model.shutdown(); fixture.remove() }
        var project = fixture.project()
        project.edits.annotations = [.init(kind: .text, start: 0, end: 2, text: "字幕👩🏽‍💻")]
        project.timeline = .migrating(project)
        let text = try #require(project.timeline?.clips.first { $0.content.trackKind == .text })
        model.install(project, directory: fixture.directory)
        model.selectTimelineClip(text.id)
        let release = EnhancedAccessibilityTestScope.acquire()
        defer { release() }
        let host = NSHostingView(rootView: ScreenRecordingClipAnimationInspector(model: model, clip: text)
            .environment(\.locale, language.locale)
            .environment(\.layoutDirection, language.isRightToLeft ? .rightToLeft : .leftToRight))
        host.sizingOptions = []
        let panel = NSPanel(contentRect: .init(x: -100_000, y: -100_000, width: 280, height: 600),
            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isReleasedWhenClosed = false
        panel.contentView = host
        panel.orderFrontRegardless()
        defer { panel.contentView = nil; panel.close() }
        await settle(host)
        #expect(model.project == project && !model.isDirty && !model.canUndo)
        #expect(element("screenRecording.entranceAnimation.duration", in: host) == nil)
        #expect(element("screenRecording.exitAnimation.duration", in: host) == nil)
        #expect(element("screenRecording.transitionDuration", in: host) == nil)
        #expect(element("screenRecording.transitionOverlapNotice", in: host) != nil)
        let inspector = ScreenRecordingClipAnimationInspector(model: model, clip: text)
        let entrance = inspector.animationKind(\.entranceAnimation)
        let exit = inspector.animationKind(\.exitAnimation)
        #expect(entrance.wrappedValue == nil && exit.wrappedValue == nil)
        entrance.wrappedValue = .typewriter
        await settle(host)
        #expect(model.selectedTimelineClip?.entranceAnimation == .init(kind: .typewriter, duration: 0.5))
        #expect(model.selectedTimelineClip?.exitAnimation == nil && model.selectedTimelineClip?.transition == nil)
        #expect(element("screenRecording.entranceAnimation.duration", in: host) != nil && model.canUndo && model.isDirty)
        let duration = inspector.animationDuration(\.entranceAnimation,
            current: try #require(model.selectedTimelineClip?.entranceAnimation))
        duration.wrappedValue = 1.25
        #expect(duration.wrappedValue == 1.25)
        await settle(host)
        entrance.wrappedValue = .slideLeft
        await settle(host)
        #expect(model.selectedTimelineClip?.entranceAnimation == .init(kind: .slideLeft, duration: 1.25),
            "Changing the effect kind must keep the selected clip's saved duration")
        model.undo()
        #expect(model.selectedTimelineClip?.entranceAnimation == .init(kind: .typewriter, duration: 1.25))
        model.redo()
        #expect(model.selectedTimelineClip?.entranceAnimation?.kind == .slideLeft)
        entrance.wrappedValue = nil
        await settle(host)
        #expect(model.selectedTimelineClip?.entranceAnimation == nil)
        #expect(element("screenRecording.entranceAnimation.duration", in: host) == nil)
        exit.wrappedValue = .fade
        await settle(host)
        #expect(model.selectedTimelineClip?.exitAnimation == .init(kind: .fade, duration: 0.5))
        #expect(element("screenRecording.exitAnimation.duration", in: host) != nil)
        let exitDuration = inspector.animationDuration(\.exitAnimation,
            current: try #require(model.selectedTimelineClip?.exitAnimation))
        exitDuration.wrappedValue = 0.75
        exit.wrappedValue = .scale
        #expect(model.selectedTimelineClip?.exitAnimation == .init(kind: .scale, duration: 0.75))
        let valid = try #require(model.project)
        exitDuration.wrappedValue = -1
        #expect(model.project == valid && model.errorMessage != nil,
            "Invalid numeric animation input must preserve the last valid project")
        exit.wrappedValue = nil
        #expect(model.selectedTimelineClip?.exitAnimation == nil)
        #expect(NSScreen.screens.allSatisfy { !$0.frame.intersects(panel.frame) } && !panel.isKeyWindow)
    }

    @Test
    func transitionsRequireExistingOverlapAndCanStillBeRemovedAfterAClipIsTrimmedAway() async throws {
        let fixture = try RecordingMultitrackTestFixture()
        let model = try fixture.model()
        defer { model.shutdown(); fixture.remove() }
        var project = fixture.project()
        let source = RecordingMediaAsset(name: "Source", file: "screen.mp4", kind: .video, duration: 2, width: 64, height: 48)
        let first = RecordingTimelineClip(id: "first", trackID: "video", content: .video(source.id), start: 0, sourceEnd: 1.5)
        let incoming = RecordingTimelineClip(id: "incoming", trackID: "video", content: .video(source.id), start: 1, sourceEnd: 1)
        project.timeline = .init(assets: [source], tracks: [.init(id: "video")], clips: [incoming, first])
        model.install(project, directory: fixture.directory)
        model.selectTimelineClip(incoming.id)
        let release = EnhancedAccessibilityTestScope.acquire()
        defer { release() }
        let inspector = ScreenRecordingClipAnimationInspector(model: model, clip: incoming)
        let host = NSHostingView(rootView: inspector)
        host.sizingOptions = []
        let panel = NSPanel(contentRect: .init(x: -100_000, y: -100_000, width: 280, height: 600),
            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isReleasedWhenClosed = false
        panel.contentView = host
        panel.orderFrontRegardless()
        defer { panel.contentView = nil; panel.close() }
        await settle(host)
        #expect(element("screenRecording.transitionOverlapNotice", in: host) == nil)
        #expect(try #require(element("screenRecording.clipTransition", in: host)?.value(forKey: "isAccessibilityEnabled") as? Bool))
        inspector.transitionKind.wrappedValue = .dissolve
        await settle(host)
        #expect(model.selectedTimelineClip?.transition == .init(kind: .dissolve, duration: 0.5))
        #expect(model.timeline?.clips[1] == first && model.selectedTimelineClip?.start == incoming.start)
        #expect(element("screenRecording.transitionDuration", in: host) != nil)
        model.updateTimelineClip(incoming.id) { $0.transition?.duration = 1.25 }
        inspector.transitionKind.wrappedValue = .slideLeft
        #expect(model.selectedTimelineClip?.transition == .init(kind: .slideLeft, duration: 1.25))
        model.updateTimelineClip(first.id) { $0.sourceEnd = 0.5 }
        await settle(host)
        #expect(element("screenRecording.transitionOverlapNotice", in: host) != nil)
        #expect(try #require(element("screenRecording.clipTransition", in: host)?.value(forKey: "isAccessibilityEnabled") as? Bool),
            "A persisted effect must remain removable when it no longer overlaps a preceding clip")
        inspector.transitionKind.wrappedValue = nil
        await settle(host)
        #expect(model.selectedTimelineClip?.transition == nil)
        #expect(element("screenRecording.transitionDuration", in: host) == nil)
        let enabled = try #require(element("screenRecording.clipTransition", in: host)?.value(forKey: "isAccessibilityEnabled") as? Bool)
        #expect(!enabled, "Transitions cannot be enabled without existing overlap")
    }

    private func element(_ identifier: String, in view: NSView) -> NSObject? {
        func find(_ object: NSObject) -> NSObject? {
            if object.responds(to: NSSelectorFromString("accessibilityIdentifier")),
               object.value(forKey: "accessibilityIdentifier") as? String == identifier { return object }
            if object.responds(to: NSSelectorFromString("accessibilityChildren")) {
                for child in object.value(forKey: "accessibilityChildren") as? [NSObject] ?? [] {
                    if let match = find(child) { return match }
                }
            }
            return nil
        }
        return find(view) ?? view.subviews.lazy.compactMap { element(identifier, in: $0) }.first
    }

    private func settle(_ view: NSView) async {
        for _ in 0..<3 {
            view.layoutSubtreeIfNeeded()
            view.displayIfNeeded()
            await withCheckedContinuation { continuation in DispatchQueue.main.async { continuation.resume() } }
        }
    }
}
