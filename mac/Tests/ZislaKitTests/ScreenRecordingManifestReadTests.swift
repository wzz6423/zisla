import Foundation
import Testing
import ZislaCore
@testable import ZislaKit

@Suite(.serialized, .timeLimit(.minutes(2)))
struct ScreenRecordingManifestReadTests {
    private let byteLimit = 128 * 1_024 * 1_024

    @Test(arguments: [false, true])
    func oversizedManifestIsRejectedBeforeDecodingAndPreservesFiles(_ linked: Bool) throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let manifest = fixture.directory.appendingPathComponent(ScreenRecordingProjectStore.manifestName)
        let target = linked ? fixture.root.appendingPathComponent("oversized.json") : manifest
        try JSONEncoder().encode(fixture.project).write(to: target)
        let handle = try FileHandle(forWritingTo: target)
        try handle.truncate(atOffset: UInt64(byteLimit + 1))
        try handle.close()
        if linked { try FileManager.default.createSymbolicLink(at: manifest, withDestinationURL: target) }
        let files = try FileManager.default.contentsOfDirectory(atPath: fixture.root.path).sorted()

        #expect(throws: ScreenRecordingProjectError.invalidProject) {
            try fixture.store.load(from: fixture.directory)
        }

        #expect(try FileManager.default.attributesOfItem(atPath: target.path)[.size] as? Int == byteLimit + 1)
        #expect(try FileManager.default.contentsOfDirectory(atPath: fixture.root.path).sorted() == files)
        #expect(try Data(contentsOf: fixture.directory.appendingPathComponent("screen.mp4")) == Data([1, 2, 3]))
    }

    @Test(arguments: [false, true])
    func directoryManifestIsRejectedWithoutReadingOrReplacingIt(_ linked: Bool) throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let manifest = fixture.directory.appendingPathComponent(ScreenRecordingProjectStore.manifestName)
        let target = linked ? fixture.root.appendingPathComponent("directory") : manifest
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: false)
        if linked { try FileManager.default.createSymbolicLink(at: manifest, withDestinationURL: target) }
        let originalType = try FileManager.default.attributesOfItem(atPath: target.path)[.type] as? FileAttributeType

        #expect(throws: ScreenRecordingProjectError.invalidProject) {
            try fixture.store.load(from: fixture.directory)
        }

        #expect(try FileManager.default.attributesOfItem(atPath: target.path)[.type] as? FileAttributeType == originalType)
        #expect(try Data(contentsOf: fixture.directory.appendingPathComponent("screen.mp4")) == Data([1, 2, 3]))
    }

    @Test(arguments: [false, true])
    func regularAndLinkedManifestsKeepLegacyProjectEditsAndCopyOwnedMedia(_ linked: Bool) throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        var project = fixture.project
        project.version = 1
        project.edits.segments = [.init(start: 1, end: 3, speed: 2)]
        project.captions = [.init(start: 0, end: 1, text: "项目 Hello العربية")]
        let manifest = fixture.directory.appendingPathComponent(ScreenRecordingProjectStore.manifestName)
        let target = linked ? fixture.root.appendingPathComponent("legacy.json") : manifest
        let data = try JSONEncoder().encode(project)
        try data.write(to: target)
        if linked { try FileManager.default.createSymbolicLink(at: manifest, withDestinationURL: target) }
        let directory = URL(fileURLWithPath: fixture.directory.path, isDirectory: false)

        #expect(try fixture.store.load(from: directory) == project)
        let destination = fixture.root.appendingPathComponent("copy.zisla-recording")
        try fixture.store.copy(project, from: directory, to: destination)
        #expect(try fixture.store.load(from: destination) == project)
        #expect(try Data(contentsOf: destination.appendingPathComponent("screen.mp4")) == Data([1, 2, 3]))
        #expect(try FileManager.default.contentsOfDirectory(atPath: destination.path).sorted() == ["project.json", "screen.mp4"])
        #expect(try Data(contentsOf: target) == data)
    }

    @Test(arguments: [false, true])
    func damagedAndEmptyManifestCanBeRepairedWithoutChangingMedia(_ linked: Bool) throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let manifest = fixture.directory.appendingPathComponent(ScreenRecordingProjectStore.manifestName)
        let target = linked ? fixture.root.appendingPathComponent("damaged.json") : manifest
        try Data().write(to: target)
        if linked { try FileManager.default.createSymbolicLink(at: manifest, withDestinationURL: target) }
        for data in [Data(), Data("{\"version\":2".utf8)] {
            try data.write(to: target)
            #expect(throws: DecodingError.self) { try fixture.store.load(from: fixture.directory) }
            #expect(try Data(contentsOf: target) == data)
        }

        try JSONEncoder().encode(fixture.project).write(to: target)
        #expect(try fixture.store.load(from: fixture.directory) == fixture.project)
        #expect(try Data(contentsOf: fixture.directory.appendingPathComponent("screen.mp4")) == Data([1, 2, 3]))
    }

    @Test func brokenLinkedManifestIsRejectedAndCanRecover() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let manifest = fixture.directory.appendingPathComponent(ScreenRecordingProjectStore.manifestName)
        let target = fixture.root.appendingPathComponent("missing.json")
        try FileManager.default.createSymbolicLink(at: manifest, withDestinationURL: target)

        #expect(throws: ScreenRecordingProjectError.invalidProject) { try fixture.store.load(from: fixture.directory) }
        #expect(try FileManager.default.destinationOfSymbolicLink(atPath: manifest.path) == target.path)
        #expect(!FileManager.default.fileExists(atPath: target.path))

        try JSONEncoder().encode(fixture.project).write(to: target)
        #expect(try fixture.store.load(from: fixture.directory) == fixture.project)
        #expect(try Data(contentsOf: fixture.directory.appendingPathComponent("screen.mp4")) == Data([1, 2, 3]))
    }

    @Test func boundedSeededManifestTruncationsFailAndRecoverWithoutWritingOutsideTheProject() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let manifest = fixture.directory.appendingPathComponent(ScreenRecordingProjectStore.manifestName)
        let target = fixture.root.appendingPathComponent("seeded.json")
        let data = try JSONEncoder().encode(fixture.project)
        try data.write(to: target)
        try FileManager.default.createSymbolicLink(at: manifest, withDestinationURL: target)
        var seed: UInt64 = 0x5A_15_1A_11
        for _ in 0..<64 {
            seed = seed &* 6_364_136_223_846_793_005 &+ 1
            let count = Int(seed % UInt64(data.count))
            let truncated = Data(data.prefix(count))
            try truncated.write(to: target)
            #expect(throws: DecodingError.self) { try fixture.store.load(from: fixture.directory) }
            #expect(try Data(contentsOf: target) == truncated)
            try data.write(to: target)
            #expect(try fixture.store.load(from: fixture.directory) == fixture.project)
        }
        #expect(try FileManager.default.contentsOfDirectory(atPath: fixture.root.path).sorted()
            == [fixture.directory.lastPathComponent, target.lastPathComponent].sorted())
        #expect(try Data(contentsOf: fixture.directory.appendingPathComponent("screen.mp4")) == Data([1, 2, 3]))
    }

    private struct Fixture {
        let root: URL
        let directory: URL
        let store: ScreenRecordingProjectStore
        let project: ScreenRecordingProject

        init() throws {
            let temporary = URL(fileURLWithPath: ProcessInfo.processInfo.environment["TMPDIR"]
                ?? FileManager.default.temporaryDirectory.path, isDirectory: true)
            root = temporary.appendingPathComponent("zisla-manifest-read-\(UUID())", isDirectory: true)
            store = .init(root: root)
            directory = try store.createDirectory()
            project = .init(name: "项目 Hello العربية", videoFile: "screen.mp4", duration: 4, width: 64, height: 48)
            try Data([1, 2, 3]).write(to: directory.appendingPathComponent("screen.mp4"))
        }

        func remove() { try? FileManager.default.removeItem(at: root) }
    }
}
