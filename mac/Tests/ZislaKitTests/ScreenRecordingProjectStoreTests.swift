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

    @Test func newProjectsDefaultToDownloads() {
        #expect(ScreenRecordingProjectStore().root == AppPaths.downloads)
    }

    @Test(arguments: [true, false])
    func equivalentDirectoryURLsAllowSavingAndOpening(_ isDirectory: Bool) throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let directory = root.appendingPathComponent("录屏 project.zisla-recording", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        try Data([1]).write(to: directory.appendingPathComponent("screen.mp4"))
        let equivalent = URL(fileURLWithPath: directory.path, isDirectory: isDirectory)
        let project = ScreenRecordingProject(name: "Demo", videoFile: "screen.mp4", duration: 5, width: 64, height: 48)
        let store = ScreenRecordingProjectStore(root: root)

        #expect(try store.mediaURL("screen.mp4", in: equivalent).path == directory.appendingPathComponent("screen.mp4").path)
        try store.save(project, in: equivalent)
        #expect(try store.load(from: equivalent) == project)
        let copy = root.appendingPathComponent("copied.zisla-recording", isDirectory: false)
        try store.copy(project, from: equivalent, to: copy)
        #expect(try store.load(from: copy) == project)
    }

    @Test func resolvingEquivalentDirectoryDoesNotAcceptSiblingPrefixEscape() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let directory = root.appendingPathComponent("project", isDirectory: false)
        let sibling = root.appendingPathComponent("project-other", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        try FileManager.default.createDirectory(at: sibling, withIntermediateDirectories: false)
        let outside = sibling.appendingPathComponent("screen.mp4")
        try Data([2]).write(to: outside)
        try FileManager.default.createSymbolicLink(at: directory.appendingPathComponent("screen.mp4"),
            withDestinationURL: outside)
        let store = ScreenRecordingProjectStore(root: root)

        #expect(throws: ScreenRecordingProjectError.unsafeMediaPath) {
            try store.mediaURL("screen.mp4", in: directory)
        }
        #expect(try Data(contentsOf: outside) == Data([2]))
        #expect(!FileManager.default.fileExists(atPath: directory.appendingPathComponent(ScreenRecordingProjectStore.manifestName).path))
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
