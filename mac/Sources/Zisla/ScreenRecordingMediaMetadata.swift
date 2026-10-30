import AVFoundation
import Foundation
import ImageIO

enum RecordingMediaMetadata {
    static func capturedAt(image url: URL) -> Date? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any] else { return nil }
        let exif = properties[kCGImagePropertyExifDictionary as String] as? [String: Any] ?? [:]
        if let original = exif[kCGImagePropertyExifDateTimeOriginal as String] as? String,
           let date = exifDate(original, offset: exif[kCGImagePropertyExifOffsetTimeOriginal as String] as? String,
                               subseconds: exif[kCGImagePropertyExifSubsecTimeOriginal as String] as? String) {
            return date
        }
        let tiff = properties[kCGImagePropertyTIFFDictionary as String] as? [String: Any]
        return (tiff?[kCGImagePropertyTIFFDateTime as String] as? String).flatMap { exifDate($0) }
    }

    static func capturedAt(asset: AVAsset) async throws -> Date? {
        let common = try await asset.load(.commonMetadata)
        let creation = AVMetadataItem.metadataItems(from: common, filteredByIdentifier: .commonIdentifierCreationDate)
        if let date = try await metadataDate(creation) { return date }
        let metadata = try await asset.load(.metadata)
        return try await metadataDate(AVMetadataItem.metadataItems(from: metadata, filteredByIdentifier: .quickTimeMetadataCreationDate))
    }

    static func exifDate(_ value: String, offset: String? = nil, subseconds: String? = nil,
                         timeZone: TimeZone = .current) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.isLenient = false
        formatter.dateFormat = offset == nil ? "yyyy:MM:dd HH:mm:ss" : "yyyy:MM:dd HH:mm:ssXXXXX"
        guard let date = formatter.date(from: value + (offset ?? "")) else { return nil }
        let fraction: Double
        if let subseconds {
            guard !subseconds.isEmpty, subseconds.allSatisfy({ $0.isASCII && $0.isNumber }),
                  let parsed = Double("0." + subseconds) else { return nil }
            fraction = parsed
        } else { fraction = 0 }
        return date.addingTimeInterval(fraction)
    }

    static func metadataDate(_ items: [AVMetadataItem]) async throws -> Date? {
        for item in items {
            if let date = try await item.load(.dateValue) { return date }
        }
        return nil
    }
}
