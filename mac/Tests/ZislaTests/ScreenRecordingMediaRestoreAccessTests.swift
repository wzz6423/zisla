import AppKit
import AVFoundation
import SwiftUI
import Testing
import ZislaCore
@testable import Zisla

@MainActor
@Suite(.serialized)
struct ScreenRecordingMediaRestoreAccessTests {
    @Test(arguments: RecordingMediaKind.allCases, [false, true])
    func removedMediaCanRestoreWithoutAnyClipAfterSavingAndReopening(_ kind: RecordingMediaKind,
                                                                    hadClip: Bool) async throws {
        let fixture = try RecordingMultitrackTestFixture()
        let model = try fixture.model()
        defer { model.shutdown(); fixture.remove() }
        let asset = try await makeAsset(kind, in: fixture)
        let originalBytes = try Data(contentsOf: fixture.directory.appendingPathComponent(asset.file))
        let track = RecordingTimelineTrack(id: "restore-track")
        var original = fixture.project()
        original.videoFile = ""
        original.edits.segments = []
        original.timeline = .init(assets: [asset], tracks: [track])
        if hadClip { _ = original.timeline?.addAssetClip(asset.id, at: 0, trackID: track.id) }
        model.install(original, directory: fixture.directory)
        let originalClips = model.timeline?.clips
        let player = model.player
        model.removeMediaAsset(asset.id)
        #expect(model.mediaAssets.isEmpty && model.timeline?.clips == originalClips)
        #expect(model.timeline?.assets.map(\.id) == [asset.id] && model.player === player)
        if let clipID = model.timeline?.clips.first?.id { model.deleteTimelineClip(clipID) }
        let removed = try #require(model.project)
        #expect(model.timeline?.clips.isEmpty == true && model.timeline?.tracks == [track])
        #expect(model.selectedTimelineClip == nil && !model.canExport && model.canEdit)
        try model.save()
        model.install(try fixture.store.load(from: fixture.directory), directory: fixture.directory)
        #expect(model.project == removed && !model.canUndo && model.mediaAssets.isEmpty)
        let files = try fixture.files()
        let releaseAccessibility = EnhancedAccessibilityTestScope.acquire()
        defer { releaseAccessibility() }
        let host = RestoreAccessHost(model)
        defer { host.close() }
        await host.settle()
        let restoreID = "screenRecording.libraryRestoreMedia." + asset.id.uuidString
        #expect(host.element(restoreID) == nil, "Removed media must start collapsed")
        let disclosure = try #require(host.disclosure(),
            "A removed asset without timeline clips needs a library restoration entry after reopen")
        #expect(host.element("screenRecording.removedMediaLibrary") != nil)
        try host.press(disclosure)
        await host.settle()
        let restore = try #require(host.element(restoreID))
        #expect(try host.isEnabled(restore))
        #expect(host.label(restore) == AppLocalization.text("重新导入"))
        try host.press(disclosure)
        await host.settle()
        #expect(host.element(restoreID) == nil, "Collapsing removed media must hide its actions")
        try host.press(try #require(host.disclosure()))
        await host.settle()
        try host.press(try #require(host.element(restoreID)))
        await host.settle()
        var restored = removed
        restored.timeline?.assets[0].isHiddenFromLibrary = nil
        #expect(model.project == restored && model.mediaAssets == [asset])
        #expect(model.timeline?.clips.isEmpty == true && model.timeline?.tracks == [track])
        #expect(host.element("screenRecording.removedMediaLibrary") == nil,
            "Restoring the final removed asset must remove the empty restoration entry")
        #expect(try fixture.files() == files)
        #expect(try Data(contentsOf: fixture.directory.appendingPathComponent(asset.file)) == originalBytes)
        model.undo()
        #expect(model.project == removed && model.mediaAssets.isEmpty)
        model.redo()
        #expect(model.project == restored && model.mediaAssets == [asset])
        let first = try #require(model.addAssetToTimeline(asset.id, at: 0, trackID: track.id))
        let second = try #require(model.addAssetToTimeline(asset.id, at: asset.duration, trackID: track.id))
        #expect(first != second && model.timeline?.assets.count == 1)
        #expect(model.timeline?.clips.map(\.content.assetID) == [asset.id, asset.id],
            "Library restoration must allow the same media to be reused in the timeline")
        #expect(model.canExport && model.timeline?.tracks == [track])
        let added = model.project
        model.undo()
        #expect(model.timeline?.clips.map(\.id) == [first])
        model.redo()
        #expect(model.project == added)
        try model.save()
        model.install(try fixture.store.load(from: fixture.directory), directory: fixture.directory)
        #expect(model.project == added && model.mediaAssets == [asset] && model.canExport)
        #expect(try fixture.files() == files)
        #expect(try Data(contentsOf: fixture.directory.appendingPathComponent(asset.file)) == originalBytes)
        #expect(NSScreen.screens.allSatisfy { !$0.frame.intersects(host.window.frame) } && !host.window.isKeyWindow)
    }

    @Test func libraryWithoutRemovedMediaHasNoRestorationEntry() async throws {
        let fixture = try RecordingMultitrackTestFixture()
        let model = try fixture.model()
        defer { model.shutdown(); fixture.remove() }
        let releaseAccessibility = EnhancedAccessibilityTestScope.acquire()
        defer { releaseAccessibility() }
        let host = RestoreAccessHost(model)
        defer { host.close() }
        await host.settle()
        #expect(host.element("screenRecording.removedMediaLibrary") == nil)
        let asset = try await makeAsset(.image, in: fixture)
        var project = fixture.project()
        project.videoFile = ""
        project.edits.segments = []
        project.timeline = .init(assets: [asset])
        model.install(project, directory: fixture.directory)
        await host.settle()
        #expect(host.element("screenRecording.removedMediaLibrary") == nil)
        #expect(host.element("screenRecording.mediaAsset." + asset.id.uuidString) != nil)
    }

    @Test func libraryRestorationIsDisabledWhileGeneratingCaptionsAndKeepsHistory() async throws {
        let fixture = try RecordingMultitrackTestFixture()
        defer { fixture.remove() }
        let asset = try await makeAsset(.audio, in: fixture)
        let transcriber = ScreenRecordingTranscriber(dependencies: .init(authorizationStatus: { .authorized },
            requestAuthorization: { _ in }, onDeviceAvailable: { _ in true }, recognize: { _, _, _ in {} },
            scheduleDeadline: { _ in {} }))
        let model = ScreenRecordingStudioModel(transcriber: transcriber, projectStore: fixture.store)
        defer { model.shutdown() }
        var original = fixture.project()
        original.videoFile = ""
        original.edits.segments = []
        original.timeline = .init(assets: [asset])
        model.install(original, directory: fixture.directory)
        model.removeMediaAsset(asset.id)
        let removed = try #require(model.project)
        let files = try fixture.files()
        let releaseAccessibility = EnhancedAccessibilityTestScope.acquire()
        defer { releaseAccessibility() }
        let host = RestoreAccessHost(model)
        defer { host.close() }
        await host.settle()
        try host.press(try #require(host.disclosure()))
        await host.settle()
        model.generateCaptions()
        await host.settle()
        #expect(model.isBusy && !model.canEdit)
        let restoreID = "screenRecording.libraryRestoreMedia." + asset.id.uuidString
        let disabled = try #require(host.element(restoreID))
        #expect(try !host.isEnabled(disabled))
        try host.press(disabled)
        await host.settle()
        #expect(model.project == removed && model.mediaAssets.isEmpty && model.isBusy)
        model.cancelOperation()
        await model.operationTask?.value
        await host.settle()
        #expect(model.canEdit && model.canUndo && !model.canRedo)
        let enabled = try #require(host.element(restoreID))
        #expect(try host.isEnabled(enabled))
        try host.press(enabled)
        await host.settle()
        #expect(model.project == original && model.mediaAssets == [asset])
        model.undo()
        #expect(model.project == removed)
        model.undo()
        #expect(model.project == original && !model.canUndo,
            "A disabled restoration must not add an undo entry")
        #expect(try fixture.files() == files)
    }

    @Test func switchingProjectsResetsTheRemovedMediaSectionToCollapsed() async throws {
        let fixture = try RecordingMultitrackTestFixture()
        let model = try fixture.model()
        defer { model.shutdown(); fixture.remove() }
        var asset = try await makeAsset(.image, in: fixture)
        asset.isHiddenFromLibrary = true
        var first = fixture.project()
        first.videoFile = ""
        first.edits.segments = []
        first.timeline = .init(assets: [asset])
        model.install(first, directory: fixture.directory)
        let releaseAccessibility = EnhancedAccessibilityTestScope.acquire()
        defer { releaseAccessibility() }
        let host = RestoreAccessHost(model)
        defer { host.close() }
        await host.settle()
        let restoreID = "screenRecording.libraryRestoreMedia." + asset.id.uuidString
        try host.press(try #require(host.disclosure()))
        await host.settle()
        #expect(host.element(restoreID) != nil)
        var second = first
        second.id = UUID()
        model.install(second, directory: fixture.directory)
        await host.settle()
        #expect(host.disclosure() != nil && host.element(restoreID) == nil)
        try host.press(try #require(host.disclosure()))
        await host.settle()
        #expect(host.element(restoreID) != nil)
        var visible = second
        visible.id = UUID()
        visible.timeline?.assets[0].isHiddenFromLibrary = nil
        model.install(visible, directory: fixture.directory)
        await host.settle()
        #expect(host.disclosure() == nil)
        model.install(first, directory: fixture.directory)
        await host.settle()
        #expect(host.disclosure() != nil && host.element(restoreID) == nil,
            "Visiting a project without removed media must not preserve another project's expanded section")
    }

    @Test(arguments: ["missing", "empty", "directory", "symlink"])
    func libraryRestorationFailureKeepsTheEntryAndAllowsRetry(_ failure: String) async throws {
        let fixture = try RecordingMultitrackTestFixture()
        let model = try fixture.model()
        defer { model.shutdown(); fixture.remove() }
        let asset = try await makeAsset(.image, in: fixture)
        var original = fixture.project()
        original.videoFile = ""
        original.edits.segments = []
        original.timeline = .init(assets: [asset])
        model.install(original, directory: fixture.directory)
        model.removeMediaAsset(asset.id)
        await model.previewTask?.value
        let removed = model.project
        let file = fixture.directory.appendingPathComponent(asset.file)
        let bytes = try Data(contentsOf: file)
        try FileManager.default.removeItem(at: file)
        let outside = fixture.root.appendingPathComponent("outside.png")
        if failure == "empty" { try Data().write(to: file) }
        if failure == "directory" { try FileManager.default.createDirectory(at: file, withIntermediateDirectories: false) }
        if failure == "symlink" {
            try bytes.write(to: outside)
            try FileManager.default.createSymbolicLink(at: file, withDestinationURL: outside)
        }
        let files = try fixture.files()
        let releaseAccessibility = EnhancedAccessibilityTestScope.acquire()
        defer { releaseAccessibility() }
        let host = RestoreAccessHost(model)
        defer { host.close() }
        await host.settle()
        try host.press(try #require(host.disclosure()))
        await host.settle()
        let restoreID = "screenRecording.libraryRestoreMedia." + asset.id.uuidString
        try host.press(try #require(host.element(restoreID)))
        await host.settle()
        #expect(model.project == removed && model.mediaAssets.isEmpty && model.errorMessage != nil)
        #expect(host.element(restoreID) != nil && host.disclosure() != nil)
        #expect(try fixture.files() == files)
        if failure == "symlink" { #expect(try Data(contentsOf: outside) == bytes) }
        if failure != "missing" { try FileManager.default.removeItem(at: file) }
        try bytes.write(to: file)
        try host.press(try #require(host.element(restoreID)))
        await host.settle()
        #expect(model.project == original && model.mediaAssets == [asset] && model.errorMessage == nil)
        #expect(host.element("screenRecording.removedMediaLibrary") == nil)
        #expect(try Data(contentsOf: file) == bytes)
        model.undo()
        #expect(model.project == removed)
        model.undo()
        #expect(model.project == original && !model.canUndo,
            "A failed restoration must leave the removal as the only undoable edit")
    }

    private func makeAsset(_ kind: RecordingMediaKind, in fixture: RecordingMultitrackTestFixture) async throws -> RecordingMediaAsset {
        let url: URL
        switch kind {
        case .video: url = try await fixture.createVideo("restore-source.mp4")
        case .image: url = try fixture.createImage("restore-source.png")
        case .audio: url = try fixture.createTone("restore-source.wav")
        }
        return .init(name: "Restore source", file: url.lastPathComponent, kind: kind,
            duration: 2, width: kind == .audio ? 0 : 64, height: kind == .audio ? 0 : 48,
            hasAudio: kind == .audio)
    }
}

@MainActor
private final class RestoreAccessHost {
    let host: NSView
    let window: NSPanel

    init(_ model: ScreenRecordingStudioModel) {
        let hosting = NSHostingView(rootView: ScreenRecordingMediaLibraryView(model: model))
        hosting.sizingOptions = []
        host = hosting
        window = NSPanel(contentRect: CGRect(x: -100_000, y: -100_000, width: 260, height: 800),
            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = hosting
        window.orderFrontRegardless()
    }

    func close() { window.contentView = nil; window.close() }

    func settle() async {
        for _ in 0..<3 {
            host.layoutSubtreeIfNeeded()
            host.displayIfNeeded()
            await withCheckedContinuation { continuation in DispatchQueue.main.async { continuation.resume() } }
        }
    }

    func element(_ identifier: String) -> NSObject? {
        objects(host).first { value($0, "accessibilityIdentifier") as? String == identifier }
    }

    func disclosure() -> NSObject? {
        objects(host).first { object in
            value(object, "accessibilityRole") as? String == NSAccessibility.Role.disclosureTriangle.rawValue
                && ["accessibilityLabel", "accessibilityTitle"].contains { key in
                    value(object, key) as? String == AppLocalization.text("素材已从素材库移除")
                }
        }
    }

    func isEnabled(_ element: NSObject) throws -> Bool {
        try #require(element.responds(to: NSSelectorFromString("isAccessibilityEnabled")))
        return try #require(element.value(forKey: "accessibilityEnabled") as? Bool)
    }
    func label(_ element: NSObject) -> String? { value(element, "accessibilityLabel") as? String }

    func press(_ element: NSObject) throws {
        let action = NSSelectorFromString("accessibilityPerformPress")
        try #require(element.responds(to: action))
        element.performSelector(onMainThread: action, with: nil, waitUntilDone: true)
    }

    private func objects(_ root: NSObject) -> [NSObject] {
        [root] + (value(root, "accessibilityChildren") as? [NSObject] ?? []).flatMap(objects)
    }

    private func value(_ element: NSObject, _ key: String) -> Any? {
        element.responds(to: NSSelectorFromString(key)) ? element.value(forKey: key) : nil
    }
}
