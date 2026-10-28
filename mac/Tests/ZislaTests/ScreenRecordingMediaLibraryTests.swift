import AppKit
import AVFoundation
import CoreImage
import ImageIO
import Speech
import SwiftUI
import Testing
import ZislaCore
import ZislaKit
@testable import Zisla

@MainActor
@Suite(.serialized)
struct ScreenRecordingMediaLibraryTests {
    @Test(arguments: RecordingMediaKind.allCases)
    func removingAndRestoringEachKindKeepsItsIDAllClipsAndEveryFile(_ kind: RecordingMediaKind) async throws {
        let fixture = try RecordingMultitrackTestFixture()
        let model = try fixture.model()
        defer { model.shutdown(); fixture.remove() }
        _ = try await fixture.createVideo()
        let asset: RecordingMediaAsset
        switch kind {
        case .video:
            _ = try await fixture.createVideo("second.mp4", duration: 3)
            asset = .init(name: "Second video", file: "second.mp4", kind: kind, duration: 3, width: 64, height: 48)
        case .image:
            _ = try fixture.createImage()
            asset = .init(name: "Image", file: "picture.png", kind: kind, duration: 5, width: 64, height: 48)
        case .audio:
            _ = try fixture.createTone()
            asset = .init(name: "Tone", file: "tone.wav", kind: kind, duration: 2)
        }
        var project = fixture.project()
        var timeline = RecordingMultitrackTimeline.migrating(project)
        timeline.assets.append(asset)
        let addedClip = timeline.addAssetClip(asset.id, at: 0)
        let clipID = try #require(addedClip)
        let repeatedClip = timeline.addAssetClip(asset.id, at: asset.duration)
        _ = try #require(repeatedClip)
        project.timeline = timeline
        model.install(project, directory: fixture.directory)
        model.selectTimelineClip(clipID)
        var player = model.player
        let files = try fixture.files()
        let bytes = try Dictionary(uniqueKeysWithValues: files.map {
            ($0, try Data(contentsOf: fixture.directory.appendingPathComponent($0)))
        })

        model.removeMediaAsset(asset.id)
        let removed = try #require(model.project)
        #expect(model.mediaAssets.map(\.id) == [project.id])
        #expect(model.selectedRemovedMediaAsset?.id == asset.id && model.selectedMediaAssetID == asset.id)
        let selectedClip = try #require(model.selectedTimelineClip)
        #expect(model.sourceDuration == asset.duration && model.timelineClipTitle(selectedClip) == asset.name)
        #expect(model.timeline?.clips == timeline.clips && model.timeline?.tracks == timeline.tracks)
        #expect(removed.edits == project.edits && removed.captions == project.captions && removed.mediaFiles == project.mediaFiles)
        #expect(removed.outputDuration == project.outputDuration && model.isDirty && model.canUndo)
        #expect(model.player === player)
        model.selectTimelineClip(try #require(timeline.clips.first?.id))
        #expect(model.selectedRemovedMediaAsset == nil && model.selectedMediaAssetID == project.id)
        model.selectTimelineClip(clipID)
        #expect(model.selectedMediaAssetID == asset.id && model.selectedRemovedMediaAsset?.id == asset.id
            && model.sourceDuration == asset.duration)
        if kind != .image {
            #expect((model.player?.currentItem?.asset as? AVURLAsset)?.url.lastPathComponent == asset.file)
        } else { #expect(model.player == nil) }
        player = model.player
        model.removeMediaAsset(asset.id)
        #expect(model.project == removed, "Repeated removal must not create another history entry")
        model.undo()
        #expect(model.project == project && !model.canUndo && model.selectedRemovedMediaAsset == nil)
        model.redo()
        #expect(model.project == removed && model.selectedRemovedMediaAsset?.id == asset.id)
        model.restoreMediaAsset(asset.id)
        #expect(model.project == project && model.mediaAssets.map(\.id) == timeline.assets.map(\.id))
        #expect(model.selectedRemovedMediaAsset == nil && model.selectedTimelineClipID == clipID && model.player === player)
        model.undo()
        #expect(model.project == removed && model.selectedRemovedMediaAsset?.id == asset.id)
        model.redo()
        #expect(model.project == project && model.selectedRemovedMediaAsset == nil)
        #expect(try fixture.files() == files)
        for file in files { #expect(try Data(contentsOf: fixture.directory.appendingPathComponent(file)) == bytes[file]) }
    }

    @Test func removedOriginalRecordingRemainsSelectedPlayableAndRestoresAfterSavingAndReopening() async throws {
        let fixture = try RecordingMultitrackTestFixture()
        let model = try fixture.model()
        defer { model.shutdown(); fixture.remove() }
        let source = try await fixture.createVideo()
        let originalBytes = try Data(contentsOf: source)
        var project = fixture.project()
        project.version = 1
        model.install(project, directory: fixture.directory)
        model.removeMediaAsset(project.id)
        let removed = try #require(model.project)
        #expect(model.mediaAssets.isEmpty && model.selectedMediaAssetID == project.id && model.player != nil)
        #expect(model.selectedRemovedMediaAsset?.id == project.id && model.canGenerateCaptions && model.canExport)
        #expect(removed.version == 2 && removed.timeline?.clips.map(\.id) == project.edits.segments.map { $0.id.uuidString })
        model.undo()
        #expect(model.project == project && model.project?.timeline == nil && model.selectedRemovedMediaAsset == nil)
        model.redo()
        try model.save()
        #expect(!model.isDirty)
        #expect(try fixture.store.load(from: fixture.directory) == removed)
        let copy = fixture.root.appendingPathComponent("hidden-copy.zisla-recording")
        try fixture.store.copy(removed, from: fixture.directory, to: copy)
        #expect(try fixture.store.load(from: copy) == removed)
        #expect(try Data(contentsOf: copy.appendingPathComponent("screen.mp4")) == originalBytes)
        model.install(try fixture.store.load(from: fixture.directory), directory: fixture.directory)
        #expect(model.mediaAssets.isEmpty && model.selectedMediaAssetID == project.id && model.player != nil)
        #expect(model.selectedRemovedMediaAsset?.id == project.id && !model.canUndo && !model.isDirty)
        model.seekSource(to: 1.25)
        #expect(model.currentTime == 1.25 && model.isShowingSourcePlayback)
        model.restoreMediaAsset(project.id)
        #expect(model.mediaAssets.map(\.id) == [project.id] && model.selectedRemovedMediaAsset == nil)
        #expect(model.timeline?.clips == removed.timeline?.clips && model.timeline?.assets.count == 1)
        try model.save()
        let restored = try fixture.store.load(from: fixture.directory)
        #expect(restored.timeline?.assets.first?.isHiddenFromLibrary == nil && restored.timeline?.clips == removed.timeline?.clips)
        #expect(try fixture.files() == ["project.json", "screen.mp4"])
        #expect(try Data(contentsOf: source) == originalBytes)
    }

    @Test func legacyV2AssetsWithoutTheHiddenFieldRemainVisible() async throws {
        let fixture = try RecordingMultitrackTestFixture()
        let model = try fixture.model()
        defer { model.shutdown(); fixture.remove() }
        _ = try await fixture.createVideo()
        var project = fixture.project()
        project.timeline = .migrating(project)
        let encoder = JSONEncoder()
        var json = try #require(JSONSerialization.jsonObject(with: encoder.encode(project)) as? [String: Any])
        var timeline = try #require(json["timeline"] as? [String: Any])
        var assets = try #require(timeline["assets"] as? [[String: Any]])
        for index in assets.indices { assets[index].removeValue(forKey: "isHiddenFromLibrary") }
        timeline["assets"] = assets
        json["timeline"] = timeline
        try JSONSerialization.data(withJSONObject: json).write(to: fixture.directory.appendingPathComponent("project.json"))
        let reopened = try fixture.store.load(from: fixture.directory)
        #expect(reopened == project && reopened.timeline?.assets.first?.isHiddenFromLibrary == nil)
        model.install(reopened, directory: fixture.directory)
        #expect(model.mediaAssets.map(\.id) == [project.id] && model.selectedRemovedMediaAsset == nil)
        var explicit = project
        explicit.timeline?.assets[0].isHiddenFromLibrary = false
        model.install(explicit, directory: fixture.directory)
        #expect(model.mediaAssets.count == 1)
        model.restoreMediaAsset(project.id)
        #expect(model.project == explicit && !model.canUndo && !model.isDirty)
        var hidden = project
        hidden.timeline?.assets[0] = RecordingMediaAsset(id: project.id, name: project.name, file: project.videoFile,
            kind: .video, duration: project.duration, width: project.width, height: project.height,
            hasAudio: true, isHiddenFromLibrary: true)
        model.install(hidden, directory: fixture.directory)
        #expect(model.mediaAssets.isEmpty && model.selectedRemovedMediaAsset?.id == project.id)
        #expect(try JSONDecoder().decode(ScreenRecordingProject.self, from: encoder.encode(hidden)) == hidden)
    }

    @Test func emptyMissingAndRepeatedOperationsKeepTheProjectAndRedoHistory() async throws {
        let fixture = try RecordingMultitrackTestFixture()
        let model = try fixture.model()
        defer { model.shutdown(); fixture.remove() }
        let missing = UUID()
        model.removeMediaAsset(missing)
        model.restoreMediaAsset(missing)
        #expect(model.project == nil && model.mediaAssets.isEmpty && !model.canUndo)
        _ = try await fixture.createVideo()
        model.install(fixture.project(), directory: fixture.directory)
        model.removeMediaAsset(missing)
        #expect(model.project?.timeline == nil && !model.canUndo && !model.isDirty)
        model.removeMediaAsset(try #require(model.project?.id))
        model.undo()
        let original = model.project
        model.removeMediaAsset(missing)
        model.restoreMediaAsset(missing)
        model.restoreMediaAsset(try #require(model.project?.id))
        #expect(model.project == original && model.canRedo && !model.canUndo)
        model.redo()
        let removed = model.project
        model.restoreMediaAsset(try #require(model.project?.id))
        model.restoreMediaAsset(try #require(model.project?.id))
        model.undo()
        #expect(model.project == removed && model.canRedo)
        model.selectedTimelineClipID = nil
        #expect(model.selectedRemovedMediaAsset == nil)
        model.selectTimelineClip("missing")
        #expect(model.selectedTimelineClipID == nil)
    }

    @Test(arguments: ["missing", "empty", "directory", "symlink"])
    func unavailableOriginalFileRejectsRestorationWithoutChangingStateOrFiles(_ failure: String) async throws {
        let fixture = try RecordingMultitrackTestFixture()
        let model = try fixture.model()
        defer { model.shutdown(); fixture.remove() }
        _ = try await fixture.createVideo()
        let image = try fixture.createImage()
        var project = fixture.project()
        var timeline = RecordingMultitrackTimeline.migrating(project)
        let asset = RecordingMediaAsset(name: "Unavailable", file: image.lastPathComponent, kind: .image,
            duration: 2, width: 64, height: 48)
        timeline.assets.append(asset)
        let addedClip = timeline.addAssetClip(asset.id, at: 0)
        let clipID = try #require(addedClip)
        project.timeline = timeline
        model.install(project, directory: fixture.directory)
        model.selectTimelineClip(clipID)
        model.removeMediaAsset(asset.id)
        await model.previewTask?.value
        try FileManager.default.removeItem(at: image)
        let outside = fixture.root.appendingPathComponent("outside.png")
        let outsideBytes = Data([42, 23])
        if failure == "empty" { try Data().write(to: image) }
        if failure == "directory" { try FileManager.default.createDirectory(at: image, withIntermediateDirectories: false) }
        if failure == "symlink" {
            try outsideBytes.write(to: outside)
            try FileManager.default.createSymbolicLink(at: image, withDestinationURL: outside)
        }
        let before = model.project
        let files = try fixture.files()
        model.restoreMediaAsset(asset.id)
        #expect(model.project == before && model.selectedRemovedMediaAsset?.id == asset.id)
        #expect(model.errorMessage != nil && model.selectedTimelineClipID == clipID && model.timeline?.clips == timeline.clips)
        #expect(try fixture.files() == files)
        if failure == "symlink" { #expect(try Data(contentsOf: outside) == outsideBytes) }
        if failure != "missing" { try FileManager.default.removeItem(at: image) }
        _ = try fixture.createImage(image.lastPathComponent)
        model.restoreMediaAsset(asset.id)
        #expect(model.project == project && model.errorMessage == nil && model.selectedRemovedMediaAsset == nil,
            "Repairing the original file must restore the same asset and clear the failed attempt's error")
        model.undo()
        #expect(model.project == before)
        model.undo()
        #expect(model.project == project && !model.canUndo,
            "A failed restoration must leave the removal as the only undoable edit")
    }

    @Test func busyOperationsDisableRemoveAndRestoreWithoutClearingRedo() async throws {
        let fixture = try RecordingMultitrackTestFixture()
        defer { fixture.remove() }
        _ = try await fixture.createVideo()
        var completeRecognition: ScreenRecordingTranscriber.Completion?
        let transcriber = ScreenRecordingTranscriber(dependencies: .init(authorizationStatus: { .authorized },
            requestAuthorization: { _ in }, onDeviceAvailable: { _ in true }, recognize: { _, _, complete in
                completeRecognition = complete
                return {}
            }, scheduleDeadline: { _ in {} }))
        let model = ScreenRecordingStudioModel(transcriber: transcriber, projectStore: fixture.store)
        defer { model.shutdown() }
        model.install(fixture.project(), directory: fixture.directory)
        let releaseAccessibility = EnhancedAccessibilityTestScope.acquire()
        defer { releaseAccessibility() }
        let host = NSHostingView(rootView: HStack(spacing: 0) {
            ScreenRecordingMediaLibraryView(model: model).frame(width: 240)
            ScrollView { ScreenRecordingMultitrackClipInspector(model: model) }.frame(width: 420)
        })
        host.sizingOptions = []
        let window = NSPanel(contentRect: .init(x: -100_000, y: -100_000, width: 660, height: 760),
            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        window.orderFrontRegardless()
        defer { window.contentView = nil; window.close() }
        let id = try #require(model.project?.id)
        model.removeMediaAsset(id)
        model.undo()
        let before = model.project
        model.generateCaptions()
        #expect(model.isBusy && !model.canEdit)
        model.removeMediaAsset(id)
        model.restoreMediaAsset(id)
        #expect(model.project == before && !model.canUndo && !model.canRedo)
        await settle(host)
        let remove = try #require(element("screenRecording.removeMedia." + id.uuidString, in: host) as? NSObject)
        #expect(remove.value(forKey: "accessibilityEnabled") as? Bool == false)
        let disabledMenu = try contextMenu(for: "screenRecording.mediaAsset." + id.uuidString, in: host, window: window)
        #expect(try #require(disabledMenu.items.first).isEnabled == false)
        model.cancelOperation()
        await model.operationTask?.value
        #expect(model.project == before && model.canRedo)
        model.redo()
        let removed = model.project
        model.generateCaptions()
        #expect(model.isBusy)
        model.restoreMediaAsset(id)
        model.removeMediaAsset(id)
        #expect(model.project == removed && model.mediaAssets.isEmpty)
        await settle(host)
        let restore = try #require(element("screenRecording.restoreMedia." + id.uuidString, in: host) as? NSObject)
        #expect(restore.value(forKey: "accessibilityEnabled") as? Bool == false)
        for _ in 0..<100 where completeRecognition == nil { await Task.yield() }
        model.cancelOperation()
        await model.operationTask?.value
        #expect(model.project == removed && model.canUndo && model.selectedRemovedMediaAsset?.id == id)
    }

    @Test(arguments: [false, true])
    func hiddenAudioAndRecordingSourcesGenerateCaptionsFromTheirOriginalFile(_ recording: Bool) async throws {
        let fixture = try RecordingMultitrackTestFixture()
        defer { fixture.remove() }
        _ = try await fixture.createVideo()
        let sound = try fixture.createTone(recording ? "microphone.wav" : "tone.wav")
        var recognized: URL?
        let transcriber = ScreenRecordingTranscriber(dependencies: .init(authorizationStatus: { .authorized },
            requestAuthorization: { _ in }, onDeviceAvailable: { _ in true }, recognize: { url, _, complete in
                recognized = url
                complete(.success([.init(start: 0.5, end: 1.5, text: "Hidden source")]))
                return {}
            }, scheduleDeadline: { _ in {} }))
        let model = ScreenRecordingStudioModel(transcriber: transcriber, projectStore: fixture.store)
        defer { model.shutdown() }
        var project = fixture.project()
        if recording { project.microphoneFile = sound.lastPathComponent }
        var timeline = RecordingMultitrackTimeline.migrating(project)
        let id: UUID
        let clipID: String
        if recording {
            id = project.id
            clipID = try #require(timeline.clips.first?.id)
        } else {
            let asset = RecordingMediaAsset(name: "Hidden tone", file: sound.lastPathComponent, kind: .audio, duration: 2)
            id = asset.id
            timeline.assets.append(asset)
            let addedClip = timeline.addAssetClip(id, at: 1)
            clipID = try #require(addedClip)
        }
        project.timeline = timeline
        model.install(project, directory: fixture.directory)
        model.selectTimelineClip(clipID)
        model.removeMediaAsset(id)
        #expect(model.canGenerateCaptions && model.selectedMediaAssetID == id)
        model.generateCaptions()
        await model.operationTask?.value
        #expect(recognized?.standardizedFileURL == sound.standardizedFileURL)
        let caption = try #require(model.project?.captions.first)
        #expect(caption.text == "Hidden source" && caption.start == (recording ? 0.5 : 1.5)
            && caption.end == (recording ? 1.5 : 2.5))
        #expect(model.timeline?.assets.first { $0.id == id }?.isHiddenFromLibrary == true)
    }

    @Test func removingAllLibraryAssetsPreservesActualPreviewPlaybackMP4AndGIFPictureAndAudio() async throws {
        let fixture = try RecordingMultitrackTestFixture()
        let model = try fixture.model()
        defer { model.shutdown(); fixture.remove() }
        _ = try await fixture.createVideo(colors: [.init(red: 1, green: 0, blue: 0)])
        _ = try fixture.createImage(color: .init(red: 0, green: 1, blue: 0))
        _ = try fixture.createTone()
        var project = fixture.project()
        project.edits.padding = 0
        project.edits.cornerRadius = 0
        project.edits.shadow = 0
        var timeline = RecordingMultitrackTimeline.migrating(project)
        let image = RecordingMediaAsset(name: "Image", file: "picture.png", kind: .image, duration: 2, width: 64, height: 48)
        let audio = RecordingMediaAsset(name: "Sound", file: "tone.wav", kind: .audio, duration: 2)
        timeline.assets += [image, audio]
        let imageClip = timeline.addAssetClip(image.id, at: 0)
        _ = try #require(imageClip)
        timeline.clips[timeline.clips.count - 1].layout = .init(x: 0.5, y: 0, width: 0.5, height: 1)
        let audioClip = timeline.addAssetClip(audio.id, at: 0)
        _ = try #require(audioClip)
        project.timeline = timeline
        model.install(project, directory: fixture.directory)
        let files = try fixture.files()
        for asset in timeline.assets { model.removeMediaAsset(asset.id) }
        let hidden = try #require(model.project)
        #expect(model.mediaAssets.isEmpty && model.canExport && hidden.timeline?.clips == timeline.clips)
        let exporter = ScreenRecordingExporter()
        let preview = try await exporter.multitrackPreview(project: hidden, directory: fixture.directory, time: 0.5)
        try expectPicture(preview.image(project: hidden))
        let item = try await exporter.playbackItem(project: hidden, directory: fixture.directory)
        let frames = try await RecordingMultitrackTestFixture.decode(item.asset, composition: item.videoComposition)
        #expect(frames.count == 60)
        try expectPicture(try #require(frames.first { abs($0.0 - 0.5) < 0.001 }?.1))
        let playbackEnergy = try await audioEnergy(item.asset, mix: item.audioMix)
        #expect(playbackEnergy > 0.005)
        for format in [RecordingExportFormat.mp4, .gif] {
            let destination = fixture.root.appendingPathComponent("hidden." + format.rawValue)
            try await exporter.export(project: hidden, directory: fixture.directory, to: destination,
                configuration: .init(format: format, resolution: .source, frameRate: 4))
            if format == .mp4 {
                let exported = AVURLAsset(url: destination)
                let decoded = try await RecordingMultitrackTestFixture.decode(exported)
                #expect(decoded.count == 8)
                try expectPicture(decoded[2].1)
                let exportedEnergy = try await audioEnergy(exported)
                #expect((0.8...1.2).contains(exportedEnergy / playbackEnergy))
            } else {
                let gif = try #require(CGImageSourceCreateWithURL(destination as CFURL, nil))
                #expect(CGImageSourceGetCount(gif) == 8)
                try expectPicture(try #require(CGImageSourceCreateImageAtIndex(gif, 2, nil)))
            }
        }
        #expect(model.project == hidden)
        #expect(try fixture.files() == files)
    }

    @Test func hiddenHostRemoveRestoreButtonsShowExactFileDetailsAndNoFooter() async throws {
        let fixture = try RecordingMultitrackTestFixture()
        let model = try fixture.model()
        defer { model.shutdown(); fixture.remove() }
        _ = try await fixture.createVideo()
        let imageURL = try fixture.createImage("original-name.png")
        var project = fixture.project()
        var timeline = RecordingMultitrackTimeline.migrating(project)
        let image = RecordingMediaAsset(name: "Display title", file: imageURL.lastPathComponent, kind: .image,
            duration: 2, width: 64, height: 48)
        timeline.assets.append(image)
        let addedClip = timeline.addAssetClip(image.id, at: 0)
        let imageClip = try #require(addedClip)
        project.timeline = timeline
        model.install(project, directory: fixture.directory)
        model.selectTimelineClip(imageClip)
        let releaseAccessibility = EnhancedAccessibilityTestScope.acquire()
        defer { releaseAccessibility() }
        let host = NSHostingView(rootView: HStack(spacing: 0) {
            ScreenRecordingMediaLibraryView(model: model).frame(width: 240)
            ScrollView { ScreenRecordingMultitrackClipInspector(model: model) }.frame(width: 420)
        })
        host.sizingOptions = []
        let window = NSPanel(contentRect: .init(x: -100_000, y: -100_000, width: 660, height: 760),
            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        window.orderFrontRegardless()
        defer { window.contentView = nil; window.close() }
        await settle(host)
        #expect(labelled(translations("将素材拖到轨道中开始剪辑"), in: host) == nil)
        let menu = try contextMenu(for: "screenRecording.mediaAsset." + image.id.uuidString, in: host, window: window)
        let firstItem = try #require(menu.items.first)
        #expect(menu.items.count == 1 && translations("移除素材").contains(firstItem.title))
        let remove = try #require(element("screenRecording.removeMedia." + image.id.uuidString, in: host))
        #expect(translations("移除素材").contains(label(remove) ?? ""))
        try click(remove.accessibilityFrame(), in: window)
        await settle(host)
        #expect(element("screenRecording.mediaAsset." + image.id.uuidString, in: host) == nil)
        #expect(translations("素材已从素材库移除").contains(value(element("screenRecording.removedMediaNotice", in: host)) ?? ""))
        #expect(translations("文件名：%@", [imageURL.lastPathComponent]).contains(value(element("screenRecording.removedMediaName", in: host)) ?? ""))
        #expect(translations("文件路径：%@", [imageURL.path]).contains(value(element("screenRecording.removedMediaPath", in: host)) ?? ""))
        #expect(model.timeline?.clips == timeline.clips)
        let restore = try #require(element("screenRecording.restoreMedia." + image.id.uuidString, in: host))
        #expect(translations("重新导入").contains(label(restore) ?? ""))
        try click(restore.accessibilityFrame(), in: window)
        await settle(host)
        #expect(element("screenRecording.mediaAsset." + image.id.uuidString, in: host) != nil)
        #expect(element("screenRecording.removedMediaNotice", in: host) == nil && model.project == project)
        let restoredMenu = try contextMenu(for: "screenRecording.mediaAsset." + image.id.uuidString, in: host, window: window)
        let item = try #require(restoredMenu.items.first)
        let action = try #require(item.action)
        #expect(NSApp.sendAction(action, to: item.target, from: item))
        await settle(host)
        #expect(model.selectedRemovedMediaAsset?.id == image.id && model.timeline?.clips == timeline.clips)
        model.undo()
        #expect(model.project == project)
        model.undo()
        await settle(host)
        #expect(element("screenRecording.removedMediaNotice", in: host) != nil)
        try FileManager.default.removeItem(at: imageURL)
        try click(try #require(element("screenRecording.restoreMedia." + image.id.uuidString, in: host)).accessibilityFrame(), in: window)
        await settle(host)
        #expect(translations("文件路径：%@", [imageURL.path]).contains(value(element("screenRecording.removedMediaPath", in: host)) ?? ""))
        #expect(model.selectedRemovedMediaAsset?.id == image.id && model.errorMessage != nil && model.timeline?.clips == timeline.clips)
        model.selectedTimelineClipID = nil
        await settle(host)
        #expect(element("screenRecording.removedMediaNotice", in: host) == nil
            && labelled(translations("将素材拖到轨道中开始剪辑"), in: host) == nil)
        #expect(NSScreen.screens.allSatisfy { !$0.frame.intersects(window.frame) } && !window.isKeyWindow)
    }

    private func expectPicture(_ image: CGImage) throws {
        let left = try RecordingMultitrackTestFixture.pixel(image, x: 16, y: 24)
        let right = try RecordingMultitrackTestFixture.pixel(image, x: 48, y: 24)
        #expect(left[0] > 210 && left[1] < 50 && right[1] > 210 && right[0] < 50)
    }

    private func audioEnergy(_ asset: AVAsset, mix: AVAudioMix? = nil) async throws -> Double {
        let tracks = try await asset.loadTracks(withMediaType: .audio)
        try #require(!tracks.isEmpty)
        let reader = try AVAssetReader(asset: asset)
        let output = AVAssetReaderAudioMixOutput(audioTracks: tracks, audioSettings: [
            AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: 48_000, AVNumberOfChannelsKey: 2,
            AVLinearPCMBitDepthKey: 32, AVLinearPCMIsFloatKey: true, AVLinearPCMIsNonInterleaved: false,
        ])
        output.audioMix = mix
        reader.add(output)
        try #require(reader.startReading())
        defer { reader.cancelReading() }
        var energy = 0.0
        var samples = 0
        while let buffer = output.copyNextSampleBuffer() {
            let block = try #require(buffer.dataBuffer)
            let count = CMBlockBufferGetDataLength(block) / MemoryLayout<Float>.size
            var values = [Float](repeating: 0, count: count)
            let result = values.withUnsafeMutableBytes {
                CMBlockBufferCopyDataBytes(block, atOffset: 0, dataLength: count * MemoryLayout<Float>.size,
                    destination: $0.baseAddress!)
            }
            try #require(result == kCMBlockBufferNoErr)
            energy += values.reduce(0) { $0 + Double($1) * Double($1) }
            samples += count
        }
        try #require(reader.status == .completed && samples > 0)
        return energy / Double(samples)
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
            $0.responds(to: NSSelectorFromString("accessibilityIdentifier"))
                && $0.value(forKey: "accessibilityIdentifier") as? String == identifier
        } as? any NSAccessibilityElementProtocol
        return found ?? host.subviews.lazy.compactMap { element(identifier, in: $0) }.first
    }

    private func translations(_ key: String, _ arguments: [CVarArg] = []) -> Set<String> {
        Set(AppLanguage.allCases.map { AppLocalization.format(key, locale: $0.locale, arguments) })
    }

    private func labelled(_ labels: Set<String>, in host: NSView) -> NSObject? {
        objects(in: host).first {
            ($0.responds(to: NSSelectorFromString("accessibilityLabel")) && labels.contains($0.value(forKey: "accessibilityLabel") as? String ?? ""))
                || ($0.responds(to: NSSelectorFromString("accessibilityValue")) && labels.contains($0.value(forKey: "accessibilityValue") as? String ?? ""))
        }
    }

    private func label(_ element: (any NSAccessibilityElementProtocol)?) -> String? {
        (element as? NSObject)?.value(forKey: "accessibilityLabel") as? String
    }

    private func value(_ element: (any NSAccessibilityElementProtocol)?) -> String? {
        (element as? NSObject)?.value(forKey: "accessibilityValue") as? String
    }

    private func click(_ frame: CGRect, in window: NSWindow) throws {
        let point = window.convertPoint(fromScreen: CGPoint(x: frame.midX, y: frame.midY))
        for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
            window.sendEvent(try #require(NSEvent.mouseEvent(with: type, location: point, modifierFlags: [],
                timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber, context: nil,
                eventNumber: 0, clickCount: 1, pressure: type == .leftMouseDown ? 1 : 0)))
        }
    }

    private func contextMenu(for identifier: String, in host: NSView, window: NSWindow) throws -> NSMenu {
        let frame = try #require(element(identifier, in: host)).accessibilityFrame()
        let point = window.convertPoint(fromScreen: CGPoint(x: frame.midX, y: frame.midY))
        let event = try #require(NSEvent.mouseEvent(with: .rightMouseDown, location: point, modifierFlags: [],
            timestamp: 0, windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1))
        var target = host.hitTest(host.convert(point, from: nil))
        while let view = target {
            if let menu = view.menu(for: event) { return menu }
            target = view.superview
        }
        Issue.record("The library row must expose its removal action through the native context menu")
        throw ScreenRecordingProjectError.invalidProject
    }
}
