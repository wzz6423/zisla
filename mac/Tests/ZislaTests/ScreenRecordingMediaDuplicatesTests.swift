import AppKit
import AVFoundation
import CoreImage
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers
import ZislaCore
import ZislaKit
@testable import Zisla

@MainActor
@Suite(.serialized)
struct ScreenRecordingMediaDuplicatesTests {
    @Test func repeatedURLRenamedCopyAndSymlinkInOneBatchCreateOnlyOneAssetAndFile() async throws {
        let fixture = try RecordingMultitrackTestFixture()
        defer { fixture.remove() }
        let image = try fixture.createImage()
        let copy = fixture.directory.appendingPathComponent("renamed.png")
        let link = fixture.directory.appendingPathComponent("linked.png")
        try FileManager.default.copyItem(at: image, to: copy)
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: image)
        let result = try await RecordingMediaImporter.prepare(urls: [image, image, copy, link],
            project: nil, directory: nil, store: fixture.store)
        defer { result.discard() }
        let asset = try #require(result.project.timeline?.assets.first)
        #expect(result.project.timeline?.assets.count == 1 && result.addedFiles == [asset.file])
        #expect(result.duplicateCount == 3 && result.restoredAssetIDs.isEmpty)
        #expect(try FileManager.default.contentsOfDirectory(atPath: result.directory.path) == [asset.file])
        #expect(result.project.timeline?.clips.isEmpty == true && result.project.timeline?.tracks.isEmpty == true)
        #expect(try Data(contentsOf: result.directory.appendingPathComponent(asset.file)) == Data(contentsOf: image))
    }

    @Test func duplicateAcrossBatchesReturnsTheExactProjectAndCreatesNoFile() async throws {
        let fixture = try RecordingMultitrackTestFixture()
        defer { fixture.remove() }
        let image = try fixture.createImage()
        let first = try await RecordingMediaImporter.prepare(urls: [image], project: nil, directory: nil, store: fixture.store)
        defer { first.discard() }
        let files = try FileManager.default.contentsOfDirectory(atPath: first.directory.path).sorted()
        let copy = fixture.directory.appendingPathComponent("renamed.png")
        try FileManager.default.copyItem(at: image, to: copy)
        let repeated = try await RecordingMediaImporter.prepare(urls: [copy], project: first.project,
            directory: first.directory, store: fixture.store)
        defer { repeated.discard() }
        #expect(repeated.project == first.project && repeated.addedFiles.isEmpty && !repeated.createdDirectory)
        #expect(repeated.duplicateCount == 1 && repeated.restoredAssetIDs.isEmpty)
        #expect(try FileManager.default.contentsOfDirectory(atPath: first.directory.path).sorted() == files)
    }

    @Test func duplicateOfLegacyRecordingPreservesVersionDirtySelectionAndRedo() async throws {
        let fixture = try RecordingMultitrackTestFixture()
        let model = try fixture.model()
        defer { model.shutdown(); fixture.remove() }
        let source = try await fixture.createVideo()
        var original = fixture.project()
        original.version = 1
        try fixture.store.save(original, in: fixture.directory)
        model.install(original, directory: fixture.directory)
        model.addTimelineTrack()
        let edited = model.project
        model.undo()
        let dirty = model.isDirty
        let selectedMedia = model.selectedMediaAssetID
        let selectedClip = model.selectedTimelineClipID
        let player = model.player
        let files = try fixture.files()
        model.importMedia([source])
        await model.operationTask?.value
        #expect(model.errorMessage == nil && model.project == original && model.project?.timeline == nil)
        #expect(model.isDirty == dirty && !model.canUndo && model.canRedo)
        #expect(model.selectedMediaAssetID == selectedMedia && model.selectedTimelineClipID == selectedClip && model.player === player)
        #expect(try fixture.files() == files && fixture.store.load(from: fixture.directory) == original)
        model.redo()
        #expect(model.project == edited)
    }

    @Test(arguments: RecordingMediaKind.allCases)
    func reimportingRemovedAssetRestoresItsOriginalIDFileAndAllRepeatedTimelineClips(_ kind: RecordingMediaKind) async throws {
        let fixture = try RecordingMultitrackTestFixture()
        let model = try fixture.model()
        defer { model.shutdown(); fixture.remove() }
        let source: URL
        switch kind {
        case .image: source = try fixture.createImage()
        case .video: source = try await fixture.createVideo()
        case .audio: source = try fixture.createTone()
        }
        model.importMedia([source])
        await model.operationTask?.value
        model.update {
            $0.timeline?.assets[0].capturedAt = Date(timeIntervalSince1970: 1_600_000_000)
        }
        try model.save()
        model.install(try #require(model.project), directory: try #require(model.directory))
        let asset = try #require(model.mediaAssets.first)
        let firstClip = try #require(model.addAssetToTimeline(asset.id, at: 0))
        _ = try #require(model.addAssetToTimeline(asset.id, at: asset.duration))
        model.selectTimelineClip(firstClip)
        let visible = try #require(model.project)
        let directory = try #require(model.directory)
        model.removeMediaAsset(asset.id)
        try model.save()
        let hidden = try #require(model.project)
        let files = try FileManager.default.contentsOfDirectory(atPath: directory.path).sorted()
        let copy = fixture.directory.appendingPathComponent("restored-name." + source.pathExtension)
        try FileManager.default.copyItem(at: source, to: copy)
        model.importMedia([copy])
        await model.operationTask?.value
        #expect(model.errorMessage == nil && model.project == visible && model.mediaAssets == [asset])
        #expect(model.timeline?.clips == hidden.timeline?.clips && model.timeline?.tracks == hidden.timeline?.tracks)
        #expect(model.selectedTimelineClipID == firstClip && model.selectedMediaAssetID == asset.id && model.selectedRemovedMediaAsset == nil)
        #expect(try FileManager.default.contentsOfDirectory(atPath: directory.path).sorted() == files)
        #expect(try fixture.store.load(from: directory) == hidden, "Import changes remain unsaved until the user saves")
        model.undo()
        #expect(model.project == hidden && model.selectedRemovedMediaAsset?.id == asset.id)
        model.redo()
        #expect(model.project == visible)
        try model.save()
        model.install(try fixture.store.load(from: directory), directory: directory)
        #expect(model.project == visible && model.mediaAssets == [asset] && !model.isDirty && !model.canUndo)
    }

    @Test(arguments: [false, true])
    func visibleDuplicatePreservesCleanStateAndExistingUndoRedo(_ history: Bool) async throws {
        let fixture = try RecordingMultitrackTestFixture()
        let model = try fixture.model()
        defer { model.shutdown(); fixture.remove() }
        let image = try fixture.createImage()
        model.importMedia([image])
        await model.operationTask?.value
        let asset = try #require(model.mediaAssets.first)
        if history {
            _ = try #require(model.addAssetToTimeline(asset.id, at: 0))
            _ = try #require(model.addAssetToTimeline(asset.id, at: asset.duration))
            model.undo()
        }
        let original = model.project
        let directory = try #require(model.directory)
        let files = try FileManager.default.contentsOfDirectory(atPath: directory.path).sorted()
        let dirty = model.isDirty
        let undo = model.canUndo
        let redo = model.canRedo
        let selectedClip = model.selectedTimelineClipID
        let selectedMedia = model.selectedMediaAssetID
        model.importMedia([image, image])
        await model.operationTask?.value
        #expect(model.project == original && model.isDirty == dirty && model.canUndo == undo && model.canRedo == redo)
        #expect(model.selectedTimelineClipID == selectedClip && model.selectedMediaAssetID == selectedMedia && model.errorMessage == nil)
        #expect(try FileManager.default.contentsOfDirectory(atPath: directory.path).sorted() == files)
        if history {
            model.redo()
            #expect(model.timeline?.clips.count == 2)
            model.undo()
            #expect(model.project == original)
            model.undo()
            #expect(model.timeline?.clips.isEmpty == true)
        } else { #expect(!model.isDirty && !model.canUndo && !model.canRedo) }
    }

    @Test func duplicateImportReportsSkippedCountWithoutSettingAnError() async throws {
        let fixture = try RecordingMultitrackTestFixture()
        let notices = SideNoticeQueue()
        let preview = try #require(CIContext().createCGImage(CIImage(color: .black), from: .init(x: 0, y: 0, width: 64, height: 48)))
        let model = ScreenRecordingStudioModel(projectStore: fixture.store, renderPreview: { _, _, _ in preview }, notices: notices)
        defer { model.shutdown(); notices.removeAll(); fixture.remove() }
        let image = try fixture.createImage()
        model.importMedia([image])
        await model.operationTask?.value
        #expect(notices.left.isEmpty && notices.right.isEmpty)
        let original = model.project
        model.importMedia([image, image])
        await model.operationTask?.value
        #expect(model.project == original && model.errorMessage == nil && !model.isDirty && !model.canUndo)
        let notice = try #require(notices.left.first)
        #expect(notices.left.count == 1 && notices.right.isEmpty && notice.kind == .info)
        #expect(notice.title == AppLocalization.text("已跳过 %d 个重复素材", 2))
    }

    @Test func importPersistsTheImageCaptureDateAndDuplicateRestorationKeepsBothDates() async throws {
        let fixture = try RecordingMultitrackTestFixture()
        defer { fixture.remove() }
        let image = try fixture.createImage()
        let source = try #require(CGImageSourceCreateWithURL(image as CFURL, nil))
        let pixels = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
        let dated = fixture.directory.appendingPathComponent("dated.jpg")
        let destination = try #require(CGImageDestinationCreateWithURL(dated as CFURL, UTType.jpeg.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, pixels, [kCGImagePropertyExifDictionary as String: [
            kCGImagePropertyExifDateTimeOriginal as String: "2026:10:29 09:30:45",
            kCGImagePropertyExifOffsetTimeOriginal as String: "+08:00",
        ]] as CFDictionary)
        try #require(CGImageDestinationFinalize(destination))
        let result = try await RecordingMediaImporter.prepare(urls: [dated], project: nil, directory: nil, store: fixture.store)
        defer { result.discard() }
        let asset = try #require(result.project.timeline?.assets.first)
        #expect(asset.importedAt != nil && asset.capturedAt == ISO8601DateFormatter().date(from: "2026-10-29T01:30:45Z"))
        var hidden = result.project
        hidden.timeline?.assets[0].isHiddenFromLibrary = true
        let restored = try await RecordingMediaImporter.prepare(urls: [dated], project: hidden,
            directory: result.directory, store: fixture.store)
        #expect(restored.project == result.project && restored.project.timeline?.assets.first == asset)
        #expect(restored.restoredAssetIDs == [asset.id] && restored.duplicateCount == 0 && restored.addedFiles.isEmpty)
    }

    @Test(arguments: [RecordingMediaKind.video, .audio])
    func audiovisualImportsPersistEmbeddedCreationDatesAndRestoreTheirOriginalAssets(_ kind: RecordingMediaKind) async throws {
        let fixture = try RecordingMultitrackTestFixture()
        defer { fixture.remove() }
        let source = kind == .video ? try await fixture.createVideo() : try fixture.createTone()
        let dated = fixture.directory.appendingPathComponent("dated.mov")
        let session = try #require(AVAssetExportSession(asset: AVURLAsset(url: source), presetName: AVAssetExportPresetPassthrough))
        let metadata = AVMutableMetadataItem()
        metadata.identifier = .quickTimeMetadataCreationDate
        metadata.dataType = kCMMetadataBaseDataType_UTF8 as String
        metadata.value = "2026-10-29T09:30:45+08:00" as NSString
        session.metadata = [metadata]
        session.outputURL = dated
        session.outputFileType = .mov
        await withCheckedContinuation { continuation in
            session.exportAsynchronously { continuation.resume() }
        }
        try #require(session.status == .completed)
        let embedded = try await AVURLAsset(url: dated).load(.metadata)
        let creationDate = try #require(embedded.first { $0.identifier == .quickTimeMetadataCreationDate })
        #expect(try await creationDate.load(.stringValue) == "2026-10-29T09:30:45+08:00")
        let result = try await RecordingMediaImporter.prepare(urls: [dated], project: nil, directory: nil, store: fixture.store)
        defer { result.discard() }
        let asset = try #require(result.project.timeline?.assets.first)
        #expect(asset.kind == kind && asset.importedAt != nil && asset.capturedAt == ISO8601DateFormatter().date(from: "2026-10-29T01:30:45Z"))
        #expect(try RecordingMediaIdentity.digest(of: result.directory.appendingPathComponent(asset.file))
            == RecordingMediaIdentity.digest(of: dated))
        try fixture.store.save(result.project, in: result.directory)
        #expect(try fixture.store.load(from: result.directory) == result.project)
        var hidden = result.project
        hidden.timeline?.assets[0].isHiddenFromLibrary = true
        let restored = try await RecordingMediaImporter.prepare(urls: [dated], project: hidden,
            directory: result.directory, store: fixture.store)
        #expect(restored.project == result.project && restored.project.timeline?.assets.first == asset)
        #expect(restored.restoredAssetIDs == [asset.id] && restored.addedFiles.isEmpty)
    }

    @Test func identicalNamesWithDifferentContentsCreateIndependentAssets() async throws {
        let fixture = try RecordingMultitrackTestFixture()
        defer { fixture.remove() }
        for name in ["first", "second"] {
            try FileManager.default.createDirectory(at: fixture.directory.appendingPathComponent(name), withIntermediateDirectories: false)
        }
        let first = try fixture.createImage("first/picture.png")
        let second = try fixture.createImage("second/picture.png", color: .init(red: 1, green: 0, blue: 0))
        let result = try await RecordingMediaImporter.prepare(urls: [first, second], project: nil, directory: nil, store: fixture.store)
        defer { result.discard() }
        let assets = try #require(result.project.timeline?.assets)
        try #require(assets.count == 2)
        #expect(assets.map(\.name) == ["picture.png", "picture.png"])
        #expect(Set(assets.map(\.id)).count == 2 && Set(assets.map(\.file)).count == 2)
        #expect(result.duplicateCount == 0 && result.restoredAssetIDs.isEmpty)
        #expect(assets[0].importedAt != nil && assets[0].importedAt == assets[1].importedAt)
        for (asset, source) in zip(assets, [first, second]) {
            #expect(try Data(contentsOf: result.directory.appendingPathComponent(asset.file)) == Data(contentsOf: source))
            #expect(try RecordingMediaIdentity.digest(of: result.directory.appendingPathComponent(asset.file))
                == RecordingMediaIdentity.digest(of: source))
        }
    }

    @Test func mixedVisibleRemovedAndNewAssetsImportOnceAndDiscardOnlyNewFiles() async throws {
        let fixture = try RecordingMultitrackTestFixture()
        defer { fixture.remove() }
        let visible = try fixture.createImage()
        let removed = try fixture.createImage("removed.png", color: .init(red: 1, green: 0, blue: 0))
        let new = try fixture.createImage("new.png", color: .init(red: 0, green: 0, blue: 1))
        let first = try await RecordingMediaImporter.prepare(urls: [visible, removed], project: nil, directory: nil, store: fixture.store)
        defer { first.discard() }
        var original = first.project
        let removedID = try #require(original.timeline?.assets.last?.id)
        let clip = original.timeline?.addAssetClip(removedID, at: 1)
        _ = try #require(clip)
        original.timeline?.assets[1].isHiddenFromLibrary = true
        original.timeline?.assets[1].capturedAt = Date(timeIntervalSince1970: 1_600_000_000)
        try fixture.store.save(original, in: first.directory)
        let files = try FileManager.default.contentsOfDirectory(atPath: first.directory.path).sorted()
        let manifest = try Data(contentsOf: first.directory.appendingPathComponent("project.json"))
        let result = try await RecordingMediaImporter.prepare(urls: [visible, removed, removed, new, new],
            project: original, directory: first.directory, store: fixture.store)
        let assets = try #require(result.project.timeline?.assets)
        var restored = try #require(original.timeline?.assets[1])
        restored.isHiddenFromLibrary = nil
        try #require(assets.count == 3)
        #expect(assets[0] == original.timeline?.assets[0] && assets[1] == restored)
        #expect(result.duplicateCount == 3 && result.restoredAssetIDs == [removedID] && result.addedFiles == [assets[2].file])
        #expect(result.project.timeline?.clips == original.timeline?.clips && result.project.timeline?.tracks == original.timeline?.tracks)
        #expect(try Data(contentsOf: first.directory.appendingPathComponent("project.json")) == manifest)
        #expect(try fixture.store.load(from: first.directory) == original)
        result.discard()
        #expect(try FileManager.default.contentsOfDirectory(atPath: first.directory.path).sorted() == files)
        #expect(try fixture.store.load(from: first.directory) == original)
    }

    @Test(arguments: [false, true])
    func failureOrCancellationAfterRestoreAndCopyPreservesOriginalFilesAndManifest(_ cancel: Bool) async throws {
        let fixture = try RecordingMultitrackTestFixture()
        defer { fixture.remove() }
        let removed = try fixture.createImage()
        let new = try fixture.createImage("new.png", color: .init(red: 1, green: 0, blue: 0))
        let invalid = fixture.directory.appendingPathComponent("corrupt.png")
        try Data([1, 2, 3]).write(to: invalid)
        let first = try await RecordingMediaImporter.prepare(urls: [removed], project: nil, directory: nil, store: fixture.store)
        defer { first.discard() }
        var original = first.project
        original.timeline?.assets[0].isHiddenFromLibrary = true
        try fixture.store.save(original, in: first.directory)
        let files = try FileManager.default.contentsOfDirectory(atPath: first.directory.path).sorted()
        let bytes = try files.map { try Data(contentsOf: first.directory.appendingPathComponent($0)) }
        let cancellation = try RecordingImportCopyCancellation(root: fixture.root)
        if cancel {
            await #expect(throws: CancellationError.self) {
                _ = try await RecordingMediaImporter.prepare(urls: [removed, new], project: original,
                    directory: first.directory, store: fixture.store, checkCancellation: { try cancellation.check() })
            }
            #expect(try cancellation.copiedFiles.count == 1 && cancellation.copiedBytes == Data(contentsOf: new))
        } else {
            await #expect(throws: Error.self) {
                _ = try await RecordingMediaImporter.prepare(urls: [removed, new, invalid], project: original,
                    directory: first.directory, store: fixture.store)
            }
        }
        #expect(try FileManager.default.contentsOfDirectory(atPath: first.directory.path).sorted() == files)
        for (file, expected) in zip(files, bytes) {
            #expect(try Data(contentsOf: first.directory.appendingPathComponent(file)) == expected)
        }
        #expect(try fixture.store.load(from: first.directory) == original && original.timeline?.assets[0].isHiddenFromLibrary == true)
    }

    @Test func repeatedURLsAtTheLimitDoNotConsumeNewAssetSlots() async throws {
        let fixture = try RecordingMultitrackTestFixture()
        defer { fixture.remove() }
        let old = try fixture.createImage()
        let new = try fixture.createImage("new.png", color: .init(red: 1, green: 0, blue: 0))
        var project = ScreenRecordingProject(name: "Limit", videoFile: "", duration: 5, width: 64, height: 48,
            edits: .init(segments: []), timeline: .init(assets: (0..<1_999).map {
                .init(name: "Old \($0)", file: old.lastPathComponent, kind: .image, duration: 5, width: 64, height: 48)
            }))
        try fixture.store.save(project, in: fixture.directory)
        let result = try await RecordingMediaImporter.prepare(urls: Array(repeating: new, count: 2_001),
            project: project, directory: fixture.directory, store: fixture.store)
        defer { result.discard() }
        #expect(result.project.timeline?.assets.count == 2_000 && result.addedFiles.count == 1 && result.duplicateCount == 2_000)
        project = result.project
        let files = try fixture.files()
        let duplicate = try await RecordingMediaImporter.prepare(urls: Array(repeating: old, count: 2_001),
            project: project, directory: fixture.directory, store: fixture.store)
        #expect(duplicate.project == project && duplicate.addedFiles.isEmpty && duplicate.duplicateCount == 2_001)
        #expect(try fixture.files() == files)
        let overflow = try fixture.createImage("overflow.png", color: .init(red: 0, green: 0, blue: 1))
        let beforeOverflow = try fixture.files()
        await #expect(throws: ScreenRecordingProjectError.invalidProject) {
            _ = try await RecordingMediaImporter.prepare(urls: [overflow], project: project,
                directory: fixture.directory, store: fixture.store)
        }
        #expect(try fixture.files() == beforeOverflow)
    }

    @Test func restoringAtTheLimitKeepsTheOriginalAssetWithoutAllocatingAFile() async throws {
        let fixture = try RecordingMultitrackTestFixture()
        defer { fixture.remove() }
        let hidden = try fixture.createImage()
        let other = try fixture.createImage("other.png", color: .init(red: 1, green: 0, blue: 0))
        let asset = RecordingMediaAsset(name: "Removed", file: hidden.lastPathComponent, kind: .image,
            duration: 5, width: 64, height: 48, isHiddenFromLibrary: true,
            importedAt: Date(timeIntervalSince1970: 1_600_000_000), capturedAt: Date(timeIntervalSince1970: 1_500_000_000))
        var project = ScreenRecordingProject(name: "Limit", videoFile: "", duration: 5, width: 64, height: 48,
            edits: .init(segments: []), timeline: .init(assets: [asset] + (0..<1_999).map {
                .init(name: "Other \($0)", file: other.lastPathComponent, kind: .image, duration: 5, width: 64, height: 48)
            }))
        let clip = project.timeline?.addAssetClip(asset.id, at: 0)
        _ = try #require(clip)
        try fixture.store.save(project, in: fixture.directory)
        let files = try fixture.files()
        let result = try await RecordingMediaImporter.prepare(urls: [hidden, hidden], project: project,
            directory: fixture.directory, store: fixture.store)
        var restored = asset
        restored.isHiddenFromLibrary = nil
        #expect(result.project.timeline?.assets.count == 2_000 && result.project.timeline?.assets.first == restored)
        #expect(result.project.timeline?.tracks == project.timeline?.tracks && result.project.timeline?.clips == project.timeline?.clips)
        #expect(result.addedFiles.isEmpty && result.restoredAssetIDs == [asset.id] && result.duplicateCount == 1)
        #expect(try fixture.files() == files && fixture.store.load(from: fixture.directory) == project)
    }

    @Test func existingMatchesRejectAnEscapingMediaSymlinkWithoutReplacingIt() async throws {
        let fixture = try RecordingMultitrackTestFixture()
        defer { fixture.remove() }
        let image = try fixture.createImage()
        let first = try await RecordingMediaImporter.prepare(urls: [image], project: nil, directory: nil, store: fixture.store)
        defer { first.discard() }
        var hidden = first.project
        hidden.timeline?.assets[0].isHiddenFromLibrary = true
        try fixture.store.save(hidden, in: first.directory)
        let target = first.directory.appendingPathComponent(try #require(hidden.timeline?.assets.first?.file))
        try FileManager.default.removeItem(at: target)
        try FileManager.default.createSymbolicLink(at: target, withDestinationURL: image)
        let bytes = try Data(contentsOf: image)
        let manifest = try Data(contentsOf: first.directory.appendingPathComponent("project.json"))
        let files = try FileManager.default.contentsOfDirectory(atPath: first.directory.path).sorted()
        await #expect(throws: ScreenRecordingProjectError.unsafeMediaPath) {
            _ = try await RecordingMediaImporter.prepare(urls: [image], project: hidden,
                directory: first.directory, store: fixture.store)
        }
        #expect(try FileManager.default.destinationOfSymbolicLink(atPath: target.path) == image.path)
        #expect(try Data(contentsOf: image) == bytes && Data(contentsOf: first.directory.appendingPathComponent("project.json")) == manifest)
        #expect(try FileManager.default.contentsOfDirectory(atPath: first.directory.path).sorted() == files)
    }

    @Test func duplicateOfTwoLegacyAssetsRestoresOnlyTheOriginalVisibleMatch() async throws {
        let fixture = try RecordingMultitrackTestFixture()
        defer { fixture.remove() }
        let source = try fixture.createImage()
        let hidden = RecordingMediaAsset(name: "Removed", file: source.lastPathComponent, kind: .image, duration: 5,
            width: 64, height: 48, isHiddenFromLibrary: true)
        let visible = RecordingMediaAsset(name: "Visible", file: source.lastPathComponent, kind: .image, duration: 5,
            width: 64, height: 48)
        let project = ScreenRecordingProject(name: "Legacy duplicates", videoFile: "", duration: 5, width: 64, height: 48,
            edits: .init(segments: []), timeline: .init(assets: [hidden, visible]))
        let result = try await RecordingMediaImporter.prepare(urls: [source], project: project,
            directory: fixture.directory, store: fixture.store)
        #expect(result.project == project && result.duplicateCount == 1 && result.restoredAssetIDs.isEmpty && result.addedFiles.isEmpty)
    }

    @Test(arguments: [false, true])
    func replacingStoredMediaComparesItsActualContentsInsteadOfThePreviousImport(_ sameAsReplacement: Bool) async throws {
        let fixture = try RecordingMultitrackTestFixture()
        defer { fixture.remove() }
        let originalSource = try fixture.createImage()
        let replacement = try fixture.createImage("replacement.png", color: .init(red: 1, green: 0, blue: 0))
        let first = try await RecordingMediaImporter.prepare(urls: [originalSource], project: nil, directory: nil, store: fixture.store)
        defer { first.discard() }
        let asset = try #require(first.project.timeline?.assets.first)
        try Data(contentsOf: replacement).write(to: first.directory.appendingPathComponent(asset.file))
        let incoming = sameAsReplacement ? replacement : originalSource
        let result = try await RecordingMediaImporter.prepare(urls: [incoming], project: first.project,
            directory: first.directory, store: fixture.store)
        defer { result.discard() }
        if sameAsReplacement {
            #expect(result.project == first.project && result.duplicateCount == 1 && result.addedFiles.isEmpty)
        } else {
            #expect(result.project.timeline?.assets.count == 2 && result.duplicateCount == 0 && result.addedFiles.count == 1)
            let added = try #require(result.project.timeline?.assets.last)
            #expect(try Data(contentsOf: first.directory.appendingPathComponent(added.file)) == Data(contentsOf: originalSource))
        }
        #expect(try Data(contentsOf: first.directory.appendingPathComponent(asset.file)) == Data(contentsOf: replacement))
    }

    @Test func aDifferentSizeCandidateCanBeSkippedWhenItsFileIsTemporarilyUnreadable() async throws {
        let fixture = try RecordingMultitrackTestFixture()
        defer { fixture.remove() }
        let incoming = try fixture.createImage()
        let existing = try fixture.createImage("existing.png", size: .init(width: 127, height: 95),
            color: .init(red: 1, green: 0, blue: 0))
        let bytes = try Data(contentsOf: existing)
        let incomingBytes = try Data(contentsOf: incoming)
        try #require(bytes.count != incomingBytes.count)
        let original = ScreenRecordingProject(name: "Temporarily unreadable candidate", videoFile: "", duration: 5,
            width: 64, height: 48, edits: .init(segments: []), timeline: .init(assets: [
                .init(name: "Existing", file: existing.lastPathComponent, kind: .image, duration: 5, width: 127, height: 95),
            ]))
        try fixture.store.save(original, in: fixture.directory)
        try FileManager.default.setAttributes([.posixPermissions: 0], ofItemAtPath: existing.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: existing.path) }
        #expect(throws: Error.self) { try FileHandle(forReadingFrom: existing) }
        let result = try await RecordingMediaImporter.prepare(urls: [incoming], project: original,
            directory: fixture.directory, store: fixture.store)
        defer { result.discard() }
        #expect(result.project.timeline?.assets.count == 2 && result.addedFiles.count == 1 && result.duplicateCount == 0)
        #expect(result.project.timeline?.assets.first == original.timeline?.assets.first)
        #expect(try fixture.store.load(from: fixture.directory) == original)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: existing.path)
        #expect(try Data(contentsOf: existing) == bytes)
    }

    @Test func replacingSourceBetweenHashAndCopyRollsBackTheMismatchedSnapshot() async throws {
        let fixture = try RecordingMultitrackTestFixture()
        defer { fixture.remove() }
        let source = try fixture.createImage()
        let replacement = try fixture.createImage("replacement.png", color: .init(red: 1, green: 0, blue: 0))
        let bytes = try Data(contentsOf: replacement)
        let mutation = try RecordingImportSourceMutation(source: source, replacement: bytes, root: fixture.root,
                                                         afterChecks: 4)
        let directories = try FileManager.default.contentsOfDirectory(atPath: fixture.root.path).sorted()
        await #expect(throws: ScreenRecordingExportError.unavailableMedia) {
            _ = try await RecordingMediaImporter.prepare(urls: [source], project: nil, directory: nil,
                store: fixture.store, checkCancellation: { try mutation.check() })
        }
        #expect(mutation.didMutate && mutation.copiedFiles.isEmpty)
        #expect(try Data(contentsOf: source) == bytes)
        #expect(try FileManager.default.contentsOfDirectory(atPath: fixture.root.path).sorted() == directories)
    }

    @Test func replacingTheSameSourceAfterItsFirstCopyImportsTheTwoActualContents() async throws {
        let fixture = try RecordingMultitrackTestFixture()
        defer { fixture.remove() }
        let source = try fixture.createImage()
        let original = try Data(contentsOf: source)
        let originalDigest = try RecordingMediaIdentity.digest(of: source)
        let replacement = try fixture.createImage("replacement.png", color: .init(red: 1, green: 0, blue: 0))
        let bytes = try Data(contentsOf: replacement)
        let replacementDigest = try RecordingMediaIdentity.digest(of: replacement)
        let mutation = try RecordingImportSourceMutation(source: source, replacement: bytes, root: fixture.root)
        let result = try await RecordingMediaImporter.prepare(urls: [source, source], project: nil, directory: nil,
            store: fixture.store, checkCancellation: { try mutation.check() })
        defer { result.discard() }
        let assets = try #require(result.project.timeline?.assets)
        #expect(mutation.didMutate && assets.count == 2 && result.addedFiles.count == 2 && result.duplicateCount == 0)
        if assets.count == 2 {
            for (asset, expected) in zip(assets, [original, bytes]) {
                let copied = result.directory.appendingPathComponent(asset.file)
                #expect(try Data(contentsOf: copied) == expected)
                #expect(try RecordingMediaIdentity.digest(of: copied) == (expected == original ? originalDigest : replacementDigest))
            }
        }
        #expect(try Data(contentsOf: source) == bytes)
    }
}

final class RecordingImportCopyCancellation: @unchecked Sendable {
    private let root: URL
    private let originalPaths: Set<String>
    private let lock = NSLock()
    private var observedFiles: [String] = []
    private var observedBytes: Data?
    var copiedFiles: [String] { lock.withLock { observedFiles } }
    var copiedBytes: Data? { lock.withLock { observedBytes } }

    init(root: URL) throws {
        self.root = root
        originalPaths = Set(try FileManager.default.subpathsOfDirectory(atPath: root.path))
    }

    func check() throws {
        let files = try FileManager.default.subpathsOfDirectory(atPath: root.path).filter {
            !originalPaths.contains($0) &&
                (try? root.appendingPathComponent($0).resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true
        }.sorted()
        guard let first = files.first else { return }
        let data = try Data(contentsOf: root.appendingPathComponent(first))
        lock.withLock { observedFiles = files; observedBytes = data }
        throw CancellationError()
    }
}

private final class RecordingImportSourceMutation: @unchecked Sendable {
    private let source: URL
    private let replacement: Data
    private let root: URL
    private let afterChecks: Int?
    private let originalPaths: Set<String>
    private let lock = NSLock()
    private var checks = 0
    private var mutated = false
    private var files: [String] = []
    var didMutate: Bool { lock.withLock { mutated } }
    var copiedFiles: [String] { lock.withLock { files } }

    init(source: URL, replacement: Data, root: URL, afterChecks: Int? = nil) throws {
        self.source = source
        self.replacement = replacement
        self.root = root
        self.afterChecks = afterChecks
        originalPaths = Set(try FileManager.default.subpathsOfDirectory(atPath: root.path))
    }

    func check() throws {
        try lock.withLock {
            checks += 1
            guard !mutated else { return }
            files = try FileManager.default.subpathsOfDirectory(atPath: root.path).filter {
                !originalPaths.contains($0) &&
                    (try? root.appendingPathComponent($0).resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true
            }.sorted()
            guard afterChecks.map({ checks == $0 }) ?? !files.isEmpty else { return }
            try replacement.write(to: source)
            mutated = true
        }
    }
}
