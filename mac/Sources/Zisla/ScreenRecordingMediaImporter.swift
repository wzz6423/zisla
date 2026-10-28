import AVFoundation
import Foundation
import UniformTypeIdentifiers
import ZislaCore
import ZislaKit

struct RecordingMediaImportResult: Sendable {
    let project: ScreenRecordingProject
    let directory: URL
    let addedFiles: [String]
    let createdDirectory: Bool

    func discard() {
        if createdDirectory { try? FileManager.default.removeItem(at: directory) }
        else {
            for file in addedFiles { try? FileManager.default.removeItem(at: directory.appendingPathComponent(file)) }
        }
    }
}

enum RecordingMediaImporter {
    static func prepare(urls: [URL], project: ScreenRecordingProject?, directory: URL?,
                        store: ScreenRecordingProjectStore,
                        checkCancellation: @Sendable () throws -> Void = { try Task.checkCancellation() }) async throws -> RecordingMediaImportResult {
        guard !urls.isEmpty, urls.count + (project.map { RecordingMultitrackTimeline.migrating($0).assets.count } ?? 0) <= 2_000 else {
            throw ScreenRecordingProjectError.invalidProject
        }
        try checkCancellation()
        let folder = try directory ?? store.createDirectory()
        var files: [String] = []
        do {
            var assets: [RecordingMediaAsset] = []
            for url in urls {
                try checkCancellation()
                let scoped = url.startAccessingSecurityScopedResource()
                defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                let source = url.resolvingSymlinksInPath().standardizedFileURL
                guard source.isFileURL, try source.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true else {
                    throw ScreenRecordingProjectError.missingMedia
                }
                let id = UUID()
                let file = id.uuidString + "." + source.pathExtension.lowercased()
                guard ScreenRecordingProject.isSafeMediaPath(file) else { throw ScreenRecordingProjectError.unsafeMediaPath }
                let target = folder.appendingPathComponent(file)
                try FileManager.default.copyItem(at: source, to: target)
                files.append(file)
                let copied = try store.mediaURL(file, in: folder)
                let type = UTType(filenameExtension: source.pathExtension)
                let name = String(url.lastPathComponent.prefix(512))
                if type?.conforms(to: .image) == true {
                    let size = try RecordingMediaImageStore.dimensions(of: copied)
                    assets.append(.init(id: id, name: name, file: file, kind: .image,
                        duration: 5, width: Int(size.width), height: Int(size.height)))
                } else {
                    let asset = AVURLAsset(url: copied)
                    let duration = try await asset.load(.duration).seconds
                    let video = try await asset.loadTracks(withMediaType: .video).first
                    let audio = try await asset.loadTracks(withMediaType: .audio).first
                    if let video {
                        let natural = try await video.load(.naturalSize)
                        let transform = try await video.load(.preferredTransform)
                        let size = CGRect(origin: .zero, size: natural).applying(transform).size
                        assets.append(.init(id: id, name: name, file: file, kind: .video,
                            duration: duration, width: Int(abs(size.width)), height: Int(abs(size.height)), hasAudio: audio != nil))
                    } else if audio != nil {
                        assets.append(.init(id: id, name: name, file: file, kind: .audio,
                            duration: duration, hasAudio: true))
                    } else { throw ScreenRecordingExportError.unavailableMedia }
                }
            }
            var candidate: ScreenRecordingProject
            if let project {
                candidate = project
                candidate.timeline = .migrating(project)
            } else {
                let first = assets[0]
                candidate = .init(name: String(urls[0].deletingPathExtension().lastPathComponent.prefix(512)),
                    videoFile: "", duration: first.duration,
                    width: first.kind == .audio ? 1_920 : first.width,
                    height: first.kind == .audio ? 1_080 : first.height,
                    edits: .init(segments: []), timeline: .init())
            }
            candidate.version = ScreenRecordingProject.currentVersion
            candidate.timeline!.assets.append(contentsOf: assets)
            try candidate.validate()
            try checkCancellation()
            return .init(project: candidate, directory: folder, addedFiles: files, createdDirectory: directory == nil)
        } catch {
            if directory == nil { try? FileManager.default.removeItem(at: folder) }
            else { for file in files { try? FileManager.default.removeItem(at: folder.appendingPathComponent(file)) } }
            throw error
        }
    }
}
