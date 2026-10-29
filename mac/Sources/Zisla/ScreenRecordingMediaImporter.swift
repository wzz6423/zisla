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
    let duplicateCount: Int
    let restoredAssetIDs: [UUID]

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
        guard !urls.isEmpty else {
            throw ScreenRecordingProjectError.invalidProject
        }
        try checkCancellation()
        let folder = try directory ?? store.createDirectory()
        var files: [String] = []
        do {
            var timeline = project.map(RecordingMultitrackTimeline.migrating) ?? .init()
            var fileIndices = Dictionary(grouping: timeline.assets.indices, by: { timeline.assets[$0].file })
            var duplicateCount = 0
            var restoredAssetIDs: [UUID] = []
            let importedAt = Date()
            for url in urls {
                try checkCancellation()
                let scoped = url.startAccessingSecurityScopedResource()
                defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                let source = url.resolvingSymlinksInPath().standardizedFileURL
                guard source.isFileURL, try source.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true else {
                    throw ScreenRecordingProjectError.missingMedia
                }
                let size = try source.resourceValues(forKeys: [.fileSizeKey]).fileSize
                let digest = try RecordingMediaIdentity.digest(of: source, checkCancellation: checkCancellation)
                var matches: [Int] = []
                for file in fileIndices.keys {
                    let candidate = try store.mediaURL(file, in: folder)
                    guard try candidate.resourceValues(forKeys: [.fileSizeKey]).fileSize == size else { continue }
                    if try RecordingMediaIdentity.digest(of: candidate, checkCancellation: checkCancellation) == digest {
                        matches.append(contentsOf: fileIndices[file]!)
                    }
                }
                if let index = matches.first(where: { timeline.assets[$0].isHiddenFromLibrary != true }) ?? matches.first {
                    if timeline.assets[index].isHiddenFromLibrary == true {
                        timeline.assets[index].isHiddenFromLibrary = nil
                        restoredAssetIDs.append(timeline.assets[index].id)
                    } else { duplicateCount += 1 }
                    continue
                }
                let id = UUID()
                let file = id.uuidString + "." + source.pathExtension.lowercased()
                guard ScreenRecordingProject.isSafeMediaPath(file) else { throw ScreenRecordingProjectError.unsafeMediaPath }
                let target = folder.appendingPathComponent(file)
                try FileManager.default.copyItem(at: source, to: target)
                files.append(file)
                let copied = try store.mediaURL(file, in: folder)
                guard try RecordingMediaIdentity.digest(of: copied, checkCancellation: checkCancellation) == digest else {
                    throw ScreenRecordingExportError.unavailableMedia
                }
                let type = UTType(filenameExtension: source.pathExtension)
                let name = String(url.lastPathComponent.prefix(512))
                if type?.conforms(to: .image) == true {
                    let size = try RecordingMediaImageStore.dimensions(of: copied)
                    timeline.assets.append(.init(id: id, name: name, file: file, kind: .image,
                        duration: 5, width: Int(size.width), height: Int(size.height), importedAt: importedAt,
                        capturedAt: RecordingMediaMetadata.capturedAt(image: copied)))
                } else {
                    let asset = AVURLAsset(url: copied)
                    let duration = try await asset.load(.duration).seconds
                    let video = try await asset.loadTracks(withMediaType: .video).first
                    let audio = try await asset.loadTracks(withMediaType: .audio).first
                    let capturedAt = try await RecordingMediaMetadata.capturedAt(asset: asset)
                    if let video {
                        let natural = try await video.load(.naturalSize)
                        let transform = try await video.load(.preferredTransform)
                        let size = CGRect(origin: .zero, size: natural).applying(transform).size
                        timeline.assets.append(.init(id: id, name: name, file: file, kind: .video,
                            duration: duration, width: Int(abs(size.width)), height: Int(abs(size.height)), hasAudio: audio != nil,
                            importedAt: importedAt, capturedAt: capturedAt))
                    } else if audio != nil {
                        timeline.assets.append(.init(id: id, name: name, file: file, kind: .audio,
                            duration: duration, hasAudio: true, importedAt: importedAt, capturedAt: capturedAt))
                    } else { throw ScreenRecordingExportError.unavailableMedia }
                }
                fileIndices[file, default: []].append(timeline.assets.count - 1)
            }
            var candidate: ScreenRecordingProject
            if let project {
                candidate = project
                if !files.isEmpty || !restoredAssetIDs.isEmpty {
                    candidate.version = ScreenRecordingProject.currentVersion
                    candidate.timeline = timeline
                }
            } else {
                let first = timeline.assets[0]
                candidate = .init(name: String(urls[0].deletingPathExtension().lastPathComponent.prefix(512)),
                    videoFile: "", duration: first.duration,
                    width: first.kind == .audio ? 1_920 : first.width,
                    height: first.kind == .audio ? 1_080 : first.height,
                    edits: .init(segments: []), timeline: timeline)
            }
            try candidate.validate()
            try checkCancellation()
            return .init(project: candidate, directory: folder, addedFiles: files, createdDirectory: directory == nil,
                         duplicateCount: duplicateCount, restoredAssetIDs: restoredAssetIDs)
        } catch {
            if directory == nil { try? FileManager.default.removeItem(at: folder) }
            else { for file in files { try? FileManager.default.removeItem(at: folder.appendingPathComponent(file)) } }
            throw error
        }
    }
}
