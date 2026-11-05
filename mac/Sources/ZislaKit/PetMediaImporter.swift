import AVFoundation
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers
import ZislaCore

public enum PetMediaImportError: LocalizedError, Equatable {
    case invalidName
    case unsupportedMedia
    case tooLong
    case tooLarge

    public var errorDescription: String? {
        switch self {
        case .invalidName: AppLocalization.text("宠物名称须为 1–80 个字符。")
        case .unsupportedMedia: AppLocalization.text("无法读取此图片或视频，请选择系统支持的媒体文件。")
        case .tooLong: AppLocalization.text("宠物动画不能超过 30 秒。")
        case .tooLarge: AppLocalization.text("宠物文件不能超过 100 MB。")
        }
    }
}

public enum PetMediaImporter {
    public static let maximumDuration: TimeInterval = 30
    static let maximumFileBytes = 100 * 1_024 * 1_024
    static let frameRate: Double = 12
    static let maximumDimension = 128

    public static func importPet(
        from url: URL, name: String, directory: URL = PetLibrary.userPetsDirectory
    ) async throws -> PetLibrary.Entry {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard (1...80).contains(name.count) else { throw PetMediaImportError.invalidName }
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        guard url.isFileURL else { throw PetMediaImportError.unsupportedMedia }
        let values = try url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
        guard values.isRegularFile == true else { throw PetMediaImportError.unsupportedMedia }
        guard let bytes = values.fileSize, bytes <= maximumFileBytes else { throw PetMediaImportError.tooLarge }

        let id = "user-" + UUID().uuidString.lowercased()
        let staging = directory.appendingPathComponent(".import-" + id, isDirectory: true)
        let fm = FileManager.default
        try fm.createDirectory(at: staging, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: staging) }
        let original = staging.appendingPathComponent("original." + url.pathExtension.lowercased())
        try fm.copyItem(at: url, to: original)
        let result: (image: CGImage, frames: Int, fps: Double)
        // ImageIO can return an untyped placeholder source for movie files.
        if let source = CGImageSourceCreateWithURL(original as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary),
           CGImageSourceGetType(source) != nil {
            result = try await imageSprite(from: source)
        } else {
            result = try await videoSprite(from: original)
        }
        let spriteURL = staging.appendingPathComponent("sprite.png")
        guard let destination = CGImageDestinationCreateWithURL(spriteURL as CFURL, UTType.png.identifier as CFString, 1, nil) else {
            throw PetMediaImportError.unsupportedMedia
        }
        CGImageDestinationAddImage(destination, result.image, nil)
        guard CGImageDestinationFinalize(destination) else { throw PetMediaImportError.unsupportedMedia }
        let manifest = PetManifest(
            id: id, displayName: name, description: "", spritePath: "sprite.png",
            frameWidth: result.image.width / result.frames, frames: result.frames, fps: result.fps
        )
        try JSONEncoder().encode(manifest).write(to: staging.appendingPathComponent("pet.json"), options: .atomic)
        try Task.checkCancellation()
        try fm.moveItem(at: staging, to: directory.appendingPathComponent(id, isDirectory: true))
        return PetLibrary.Entry(manifest: manifest, origin: .imported)
    }

    private static func imageSprite(from source: CGImageSource) async throws -> (image: CGImage, frames: Int, fps: Double) {
        let count = CGImageSourceGetCount(source)
        guard CGImageSourceGetStatus(source) == .statusComplete, count > 0 else {
            throw PetMediaImportError.unsupportedMedia
        }
        let timingKeys = [
            (kCGImagePropertyGIFDictionary, kCGImagePropertyGIFUnclampedDelayTime, kCGImagePropertyGIFDelayTime),
            (kCGImagePropertyPNGDictionary, kCGImagePropertyAPNGUnclampedDelayTime, kCGImagePropertyAPNGDelayTime),
            (kCGImagePropertyWebPDictionary, kCGImagePropertyWebPUnclampedDelayTime, kCGImagePropertyWebPDelayTime),
            (kCGImagePropertyHEICSDictionary, kCGImagePropertyHEICSUnclampedDelayTime, kCGImagePropertyHEICSDelayTime),
        ]
        var ends: [Double] = []
        var duration: Double = 0
        for index in 0..<count {
            guard let properties = CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [CFString: Any],
                  let width = (properties[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue,
                  let height = (properties[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue,
                  (1...16_384).contains(width), (1...16_384).contains(height),
                  width * height <= 16_777_216 else {
                throw PetMediaImportError.unsupportedMedia
            }
            var delay = count == 1 ? 1 / frameRate : 0.1
            for (dictionaryKey, unclampedKey, clampedKey) in timingKeys {
                if let dictionary = properties[dictionaryKey] as? [CFString: Any],
                   let value = (dictionary[unclampedKey] ?? dictionary[clampedKey]) as? NSNumber {
                    delay = value.doubleValue
                    break
                }
            }
            guard delay.isFinite, delay >= 0 else { throw PetMediaImportError.unsupportedMedia }
            duration += max(1 / 120, delay)
            guard duration <= maximumDuration + 0.000_001 else { throw PetMediaImportError.tooLong }
            ends.append(duration)
        }
        var index = 0
        return try await sprite(duration: duration) { time in
            while index + 1 < count, time >= ends[index] { index += 1 }
            let options: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: maximumDimension,
            ]
            guard let image = CGImageSourceCreateThumbnailAtIndex(source, index, options as CFDictionary),
                  CGImageSourceGetStatusAtIndex(source, index) == .statusComplete else {
                throw PetMediaImportError.unsupportedMedia
            }
            return image
        }
    }

    private static func videoSprite(from url: URL) async throws -> (image: CGImage, frames: Int, fps: Double) {
        let asset = AVURLAsset(url: url)
        let duration: Double
        do {
            duration = try await asset.load(.duration).seconds
            guard try await !asset.loadTracks(withMediaType: .video).isEmpty else {
                throw PetMediaImportError.unsupportedMedia
            }
        } catch {
            throw PetMediaImportError.unsupportedMedia
        }
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: maximumDimension, height: maximumDimension)
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero
        return try await sprite(duration: duration) { time in
            try await generator.image(at: CMTime(seconds: time, preferredTimescale: 60_000)).image
        }
    }

    private static func sprite(
        duration: Double, imageAt: (Double) async throws -> CGImage
    ) async throws -> (image: CGImage, frames: Int, fps: Double) {
        guard duration.isFinite, duration > 0 else { throw PetMediaImportError.unsupportedMedia }
        guard duration <= maximumDuration + 0.000_001 else { throw PetMediaImportError.tooLong }
        let duration = max(1 / frameRate, min(maximumDuration, duration))
        let count = max(1, Int((duration * frameRate).rounded(.down)))
        let fps = Double(count) / duration
        let first = try await imageAt(0)
        let width = first.width
        let height = first.height
        guard let context = CGContext(
            data: nil, width: width * count, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { throw PetMediaImportError.unsupportedMedia }
        context.interpolationQuality = .high
        for index in 0..<count {
            let image = index == 0 ? first : try await imageAt(Double(index) / fps)
            context.draw(image, in: CGRect(x: index * width, y: 0, width: width, height: height))
        }
        guard let image = context.makeImage() else { throw PetMediaImportError.unsupportedMedia }
        return (image, count, fps)
    }
}
