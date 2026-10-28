import Foundation
import Testing
import ZislaCore
@testable import ZislaKit

struct ScreenRecordingMultitrackProjectStoreTests {
    private func fixture() throws -> (URL, URL, ScreenRecordingProjectStore, ScreenRecordingProject) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("zisla-multitrack-store-\(UUID())", isDirectory: true)
        let store = ScreenRecordingProjectStore(root: root)
        let folder = try store.createDirectory()
        var project = ScreenRecordingProject(name: "Multitrack", videoFile: "screen.mp4", cameraFile: "camera.mp4",
            microphoneFile: "microphone.wav", duration: 2, width: 64, height: 48)
        var timeline = RecordingMultitrackTimeline.migrating(project)
        timeline.assets += [.init(name: "Second video", file: "second.mp4", kind: .video, duration: 2, width: 48, height: 64),
            .init(name: "Unused image", file: "unused.png", kind: .image, duration: 5, width: 32, height: 32),
            .init(name: "Unused sound", file: "sound.wav", kind: .audio, duration: 2)]
        _ = timeline.addAssetClip(timeline.assets[1].id, at: 1)
        project.timeline = timeline
        for (index, file) in project.mediaFiles.enumerated() { try Data([UInt8(index + 1)]).write(to: folder.appendingPathComponent(file)) }
        try Data([99]).write(to: folder.appendingPathComponent("unrelated.bin"))
        try store.save(project, in: folder)
        return (root, folder, store, project)
    }

    @Test func saveAndCopyKeepEveryLibraryAssetIncludingUnusedMediaAndDeduplicateTheRecordingSource() throws {
        let (root, folder, store, project) = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        #expect(project.mediaFiles == ["camera.mp4", "microphone.wav", "screen.mp4", "second.mp4", "sound.wav", "unused.png"])
        #expect(try store.load(from: folder) == project)
        let copy = root.appendingPathComponent("copy.zisla-recording")
        try store.copy(project, from: folder, to: copy)
        #expect(try store.load(from: copy) == project)
        #expect(try FileManager.default.contentsOfDirectory(atPath: copy.path).sorted()
            == (project.mediaFiles + [ScreenRecordingProjectStore.manifestName]).sorted())
        for file in project.mediaFiles {
            #expect(try Data(contentsOf: copy.appendingPathComponent(file)) == Data(contentsOf: folder.appendingPathComponent(file)))
        }
    }

    @Test func libraryOnlyProjectSavesAndCopiesWithoutInventingAVideoFile() throws {
        let (root, folder, store, original) = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        var project = original
        project.videoFile = ""
        project.cameraFile = nil
        project.microphoneFile = nil
        project.edits.segments = []
        project.timeline = .init(assets: [original.timeline!.assets[2]])
        try store.save(project, in: folder)
        let copy = root.appendingPathComponent("library-copy.zisla-recording")
        try store.copy(project, from: folder, to: copy)
        #expect(try store.load(from: copy) == project && project.outputDuration == 0)
        #expect(try FileManager.default.contentsOfDirectory(atPath: copy.path).sorted() == ["project.json", "unused.png"])
    }

    @Test(arguments: [false, true])
    func missingOrEscapedUnusedAssetRejectsSavingWithoutReplacingTheManifest(_ symlink: Bool) throws {
        let (root, folder, store, original) = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let saved = try Data(contentsOf: folder.appendingPathComponent("project.json"))
        var invalid = original
        let file = "invalid.png"
        invalid.timeline?.assets.append(.init(name: "Invalid image", file: file, kind: .image, duration: 5, width: 32, height: 32))
        if symlink {
            let outside = root.appendingPathComponent("outside.png")
            try Data([27]).write(to: outside)
            try FileManager.default.createSymbolicLink(at: folder.appendingPathComponent(file), withDestinationURL: outside)
        }
        #expect(throws: Error.self) { try store.save(invalid, in: folder) }
        #expect(try Data(contentsOf: folder.appendingPathComponent("project.json")) == saved)
        #expect(try store.load(from: folder) == original)
        let copy = root.appendingPathComponent("failed-copy.zisla-recording")
        #expect(throws: Error.self) { try store.copy(invalid, from: folder, to: copy) }
        #expect(!FileManager.default.fileExists(atPath: copy.path))
        #expect(try FileManager.default.contentsOfDirectory(atPath: root.path).allSatisfy { !$0.hasPrefix(".zisla-recording-") })
    }

    @Test func cancellationAfterPartOfTheLibraryCopyRemovesStagingAndKeepsSourceBytes() throws {
        let (root, folder, store, project) = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let sourceFiles = try FileManager.default.contentsOfDirectory(atPath: folder.path).sorted()
        let copy = root.appendingPathComponent("cancelled-copy.zisla-recording")
        var stagedCount = 0
        #expect(throws: CancellationError.self) {
            try store.copy(project, from: folder, to: copy, checkCancellation: {
                let staging = try #require(try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)
                    .first { $0.lastPathComponent.hasPrefix(".zisla-recording-") })
                stagedCount = try FileManager.default.contentsOfDirectory(atPath: staging.path).count
                if stagedCount == 2 { throw CancellationError() }
            })
        }
        #expect(stagedCount == 2 && !FileManager.default.fileExists(atPath: copy.path))
        #expect(try FileManager.default.contentsOfDirectory(atPath: folder.path).sorted() == sourceFiles)
        #expect(try store.load(from: folder) == project)
        #expect(try FileManager.default.contentsOfDirectory(atPath: root.path) == [folder.lastPathComponent])
    }
}
