import Foundation
import ZislaCore

public struct ScreenRecordingProjectStore: Sendable {
    public let root: URL
    public static let manifestName = "project.json"
    public static let projectExtension = "zisla-recording"

    public init(root: URL = AppPaths.downloads) {
        self.root = root
    }

    public func createDirectory(id: UUID = UUID()) throws -> URL {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let directory = root.appendingPathComponent(id.uuidString)
            .appendingPathExtension(Self.projectExtension)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        return directory
    }

    public func save(_ project: ScreenRecordingProject, in directory: URL) throws {
        try project.validate()
        try validateMedia(project, in: directory)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        try encoder.encode(project).write(
            to: directory.appendingPathComponent(Self.manifestName), options: .atomic
        )
    }

    public func load(from directory: URL) throws -> ScreenRecordingProject {
        let manifest = directory.appendingPathComponent(Self.manifestName)
        let attributes = try FileManager.default.attributesOfItem(atPath: manifest.path)
        guard (attributes[.size] as? NSNumber)?.intValue ?? Int.max <= 128 * 1_024 * 1_024 else {
            throw ScreenRecordingProjectError.invalidProject
        }
        let project = try JSONDecoder().decode(ScreenRecordingProject.self, from: Data(contentsOf: manifest))
        try project.validate()
        try validateMedia(project, in: directory)
        return project
    }

    public func copy(_ project: ScreenRecordingProject, from source: URL, to destination: URL) throws {
        try project.validate()
        try validateMedia(project, in: source)
        guard !FileManager.default.fileExists(atPath: destination.path) else {
            throw CocoaError(.fileWriteFileExists)
        }
        let staging = destination.deletingLastPathComponent()
            .appendingPathComponent(".zisla-recording-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: staging) }
        for name in mediaNames(project) {
            try FileManager.default.copyItem(at: mediaURL(name, in: source), to: staging.appendingPathComponent(name))
        }
        try save(project, in: staging)
        try FileManager.default.moveItem(at: staging, to: destination)
    }

    public func recentDirectories() throws -> [URL] {
        guard FileManager.default.fileExists(atPath: root.path) else { return [] }
        return try FileManager.default.contentsOfDirectory(
            at: root, includingPropertiesForKeys: [.contentModificationDateKey], options: [.skipsHiddenFiles]
        )
        .filter { $0.pathExtension == Self.projectExtension }
        .sorted {
            let left = (try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            let right = (try? $1.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            return left > right
        }
    }

    public func mediaURL(_ name: String, in directory: URL) throws -> URL {
        guard ScreenRecordingProject.isSafeMediaPath(name) else {
            throw ScreenRecordingProjectError.unsafeMediaPath
        }
        let root = directory.resolvingSymlinksInPath().standardizedFileURL
        let url = directory.appendingPathComponent(name).resolvingSymlinksInPath().standardizedFileURL
        guard url.deletingLastPathComponent().path == root.path else {
            throw ScreenRecordingProjectError.unsafeMediaPath
        }
        let values = try url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
        guard values.isRegularFile == true, (values.fileSize ?? 0) > 0 else {
            throw ScreenRecordingProjectError.missingMedia
        }
        return url
    }

    private func validateMedia(_ project: ScreenRecordingProject, in directory: URL) throws {
        for name in mediaNames(project) { _ = try mediaURL(name, in: directory) }
    }

    private func mediaNames(_ project: ScreenRecordingProject) -> [String] {
        Array(Set([project.videoFile, project.cameraFile, project.microphoneFile].compactMap { $0 })).sorted()
    }
}
