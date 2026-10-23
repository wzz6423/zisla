import Foundation
import Testing
import ZislaCore
@testable import ZislaKit

struct ScreenRecordingProjectStoreTests {
    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("zisla-project-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
        return url
    }

    @Test func savesEditsAndCopiesOnlyOwnedMedia() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = ScreenRecordingProjectStore(root: root)
        let source = try store.createDirectory()
        try Data([1, 2, 3]).write(to: source.appendingPathComponent("screen.mp4"))
        try Data([9]).write(to: source.appendingPathComponent("unrelated.txt"))
        var project = ScreenRecordingProject(name: "Demo", videoFile: "screen.mp4", duration: 8, width: 64, height: 48)
        project.edits.segments = [.init(start: 2, end: 6, speed: 2)]
        project.captions = [.init(start: 3, end: 4, text: "Hello")]
        try store.save(project, in: source)
        #expect(try store.load(from: source) == project)
        let destination = root.appendingPathComponent("copy.zisla-recording")
        try store.copy(project, from: source, to: destination)
        #expect(try store.load(from: destination) == project)
        #expect(!FileManager.default.fileExists(atPath: destination.appendingPathComponent("unrelated.txt").path))
        #expect(try store.recentDirectories().count == 2)
    }

    @Test func failedSavePreservesPreviousProjectAndRejectsSymlinkEscape() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = ScreenRecordingProjectStore(root: root)
        let directory = try store.createDirectory()
        let outside = root.appendingPathComponent("outside.mp4")
        try Data([1]).write(to: outside)
        try Data([2]).write(to: directory.appendingPathComponent("screen.mp4"))
        let project = ScreenRecordingProject(name: "Demo", videoFile: "screen.mp4", duration: 5, width: 64, height: 48)
        try store.save(project, in: directory)
        var invalid = project
        invalid.duration = -1
        #expect(throws: ScreenRecordingProjectError.invalidProject) { try store.save(invalid, in: directory) }
        #expect(try store.load(from: directory) == project)
        try FileManager.default.createSymbolicLink(at: directory.appendingPathComponent("escape.mp4"), withDestinationURL: outside)
        invalid = project
        invalid.videoFile = "escape.mp4"
        #expect(throws: ScreenRecordingProjectError.unsafeMediaPath) { try store.save(invalid, in: directory) }
        #expect(try store.load(from: directory) == project)
    }

    @Test func existingCopyDestinationSurvivesFailure() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = ScreenRecordingProjectStore(root: root)
        let source = try store.createDirectory()
        try Data([1]).write(to: source.appendingPathComponent("screen.mp4"))
        let project = ScreenRecordingProject(name: "Demo", videoFile: "screen.mp4", duration: 5, width: 64, height: 48)
        let destination = root.appendingPathComponent("existing")
        try Data([42]).write(to: destination)
        #expect(throws: CocoaError.self) { try store.copy(project, from: source, to: destination) }
        #expect(try Data(contentsOf: destination) == Data([42]))
        #expect(try FileManager.default.contentsOfDirectory(atPath: root.path).count == 2)
    }
}
