import CoreGraphics
import Foundation
import ImageIO
import ZislaCore
import ZislaKit

final class RecordingMediaImageStore: @unchecked Sendable {
    private struct Key: Hashable {
        let assetID: UUID
        let width: Int
        let height: Int
    }

    private struct FileVersion: Equatable {
        let path: String
        let identifier: AnyHashable?
        let bytes: Int
        let modified: Date?
    }

    private struct Entry {
        let image: CGImage
        let version: FileVersion
        var access: UInt64
        var bytes: Int { image.bytesPerRow * image.height }
    }

    private static let maximumFileBytes = 256 * 1_024 * 1_024
    private static let maximumSourceDimension = 16_384
    private static let maximumDecodedPixels = 4_096 * 4_096
    private let files: [UUID: String]
    private let directory: URL
    private let cacheByteLimit: Int
    private let lock = NSLock()
    private var cache: [Key: Entry] = [:]
    private var cachedBytes = 0
    private var access: UInt64 = 0

    init(project: ScreenRecordingProject, directory: URL, cacheByteLimit: Int = 64 * 1_024 * 1_024) {
        var files: [UUID: String] = [:]
        for asset in project.timeline?.assets ?? [] where asset.kind == .image { files[asset.id] = asset.file }
        self.files = files
        self.directory = directory
        self.cacheByteLimit = max(0, cacheByteLimit)
    }

    static func dimensions(of url: URL) throws -> CGSize {
        _ = try version(of: url)
        return try source(at: url).size
    }

    func image(for assetID: UUID, maximumSize: CGSize) throws -> CGImage {
        guard maximumSize.width.isFinite, maximumSize.height.isFinite,
              maximumSize.width >= 1, maximumSize.height >= 1 else {
            throw ScreenRecordingExportError.invalidConfiguration
        }
        guard let file = files[assetID] else { throw ScreenRecordingExportError.unavailableMedia }
        let url = try ScreenRecordingProjectStore(root: directory).mediaURL(file, in: directory)
        let version = try Self.version(of: url)
        let key = Key(assetID: assetID,
            width: Int(min(CGFloat(Self.maximumSourceDimension), maximumSize.width.rounded(.down))),
            height: Int(min(CGFloat(Self.maximumSourceDimension), maximumSize.height.rounded(.down))))
        return try lock.withLock {
            access &+= 1
            if var entry = cache[key], entry.version == version {
                entry.access = access
                cache[key] = entry
                return entry.image
            }
            if let old = cache.removeValue(forKey: key) { cachedBytes -= old.bytes }
            let (source, size) = try Self.source(at: url)
            let scale = min(1, min(CGFloat(key.width) / size.width, CGFloat(key.height) / size.height),
                sqrt(CGFloat(Self.maximumDecodedPixels) / (size.width * size.height)))
            let longestSide = max(1, Int((max(size.width, size.height) * scale).rounded(.down)))
            let options: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceShouldCacheImmediately: true,
                kCGImageSourceThumbnailMaxPixelSize: longestSide,
            ]
            guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary),
                  CGImageSourceGetStatusAtIndex(source, 0) == .statusComplete else {
                throw ScreenRecordingExportError.unavailableMedia
            }
            let entry = Entry(image: image, version: version, access: access)
            if entry.bytes <= cacheByteLimit {
                while cachedBytes + entry.bytes > cacheByteLimit || cache.count >= 64 {
                    guard let oldest = cache.min(by: { $0.value.access < $1.value.access }) else { break }
                    cachedBytes -= oldest.value.bytes
                    cache.removeValue(forKey: oldest.key)
                }
                cache[key] = entry
                cachedBytes += entry.bytes
            }
            return image
        }
    }

    private static func version(of url: URL) throws -> FileVersion {
        let values = try url.resourceValues(forKeys: [.fileResourceIdentifierKey, .fileSizeKey, .contentModificationDateKey])
        guard let bytes = values.fileSize, bytes <= maximumFileBytes else {
            throw ScreenRecordingExportError.unavailableMedia
        }
        return FileVersion(path: url.path, identifier: values.fileResourceIdentifier as? AnyHashable,
                           bytes: bytes, modified: values.contentModificationDate)
    }

    private static func source(at url: URL) throws -> (source: CGImageSource, size: CGSize) {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary),
              CGImageSourceGetStatus(source) == .statusComplete,
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = (properties[kCGImagePropertyPixelWidth] as? NSNumber)?.doubleValue,
              let height = (properties[kCGImagePropertyPixelHeight] as? NSNumber)?.doubleValue,
              (1...Double(maximumSourceDimension)).contains(width),
              (1...Double(maximumSourceDimension)).contains(height) else {
            throw ScreenRecordingExportError.unavailableMedia
        }
        let orientation = (properties[kCGImagePropertyOrientation] as? NSNumber)?.intValue ?? 1
        let rotated = (5...8).contains(orientation)
        return (source, CGSize(width: rotated ? height : width, height: rotated ? width : height))
    }
}
