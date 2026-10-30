import AppKit
import CoreMedia
import ZislaCore

struct ScreenRecordingCaptureTimeline: Sendable {
    private(set) var epoch: Double?
    private(set) var pausedAt: Double?
    private var pauses: [(start: Double, end: Double)] = []

    mutating func begin(at hostTime: Double) {
        epoch = hostTime
    }

    mutating func pause(at hostTime: Double) {
        guard epoch != nil, pausedAt == nil else { return }
        pausedAt = hostTime
    }

    mutating func resume(at hostTime: Double) {
        guard let pausedAt else { return }
        pauses.append((pausedAt, max(pausedAt, hostTime)))
        self.pausedAt = nil
    }

    func time(for hostTime: Double) -> Double? {
        guard let epoch, hostTime.isFinite, hostTime >= epoch,
              pausedAt.map({ hostTime < $0 }) != false,
              !pauses.contains(where: { hostTime >= $0.start && hostTime < $0.end }) else { return nil }
        let offset = pauses.reduce(0) { result, pause in
            result + (hostTime >= pause.end ? pause.end - pause.start : 0)
        }
        return max(0, hostTime - epoch - offset)
    }

    func elapsed(at hostTime: Double) -> Double {
        guard let epoch, hostTime.isFinite else { return 0 }
        let end = pausedAt.map { min($0, hostTime) } ?? hostTime
        let offset = pauses.reduce(0) { result, pause in
            result + max(0, min(end, pause.end) - pause.start)
        }
        return max(0, end - epoch - offset)
    }
}

enum ScreenRecordingCaptureGeometry {
    static func region(_ region: RecordingRect, in displayFrame: CGRect) throws -> CGRect {
        guard region.isValid, region.x >= 0, region.y >= 0,
              region.x + region.width <= displayFrame.width,
              region.y + region.height <= displayFrame.height else {
            throw ScreenRecordingCaptureError.invalidRegion
        }
        return CGRect(x: displayFrame.minX + region.x, y: displayFrame.minY + region.y,
                      width: region.width, height: region.height)
    }

    static func normalizedPointer(_ point: CGPoint, in frame: CGRect) -> CGPoint? {
        guard frame.width > 0, frame.height > 0, point.x.isFinite, point.y.isFinite,
              point.x >= frame.minX, point.x <= frame.maxX,
              point.y >= frame.minY, point.y <= frame.maxY else { return nil }
        return CGPoint(x: (point.x - frame.minX) / frame.width, y: (point.y - frame.minY) / frame.height)
    }

    static func pixelDimensions(size: CGSize, scale: CGFloat) throws -> (width: Int, height: Int) {
        let width = size.width * scale
        let height = size.height * scale
        guard width.isFinite, height.isFinite, width >= 2, height >= 2,
              width <= 16_384, height <= 16_384 else { throw ScreenRecordingCaptureError.invalidSource }
        return (Int(width.rounded(.down)) / 2 * 2, Int(height.rounded(.down)) / 2 * 2)
    }
}

enum ScreenRecordingCaptureRetimer {
    static func copy(_ sample: CMSampleBuffer, presentationTime: CMTime) throws -> CMSampleBuffer {
        var count = 0
        guard CMSampleBufferGetSampleTimingInfoArray(sample, entryCount: 0, arrayToFill: nil,
                                                     entriesNeededOut: &count) == noErr, count > 0 else {
            throw ScreenRecordingCaptureError.writerUnavailable
        }
        var timings = Array(repeating: CMSampleTimingInfo(duration: .invalid, presentationTimeStamp: .invalid,
                                                        decodeTimeStamp: .invalid), count: count)
        guard CMSampleBufferGetSampleTimingInfoArray(sample, entryCount: count, arrayToFill: &timings,
                                                     entriesNeededOut: &count) == noErr else {
            throw ScreenRecordingCaptureError.writerUnavailable
        }
        let offset = presentationTime - CMSampleBufferGetPresentationTimeStamp(sample)
        for index in timings.indices {
            timings[index].presentationTimeStamp = timings[index].presentationTimeStamp + offset
            if timings[index].decodeTimeStamp.isNumeric {
                timings[index].decodeTimeStamp = timings[index].decodeTimeStamp + offset
            }
        }
        var result: CMSampleBuffer?
        let status = timings.withUnsafeBufferPointer {
            CMSampleBufferCreateCopyWithNewTiming(allocator: kCFAllocatorDefault, sampleBuffer: sample,
                                                  sampleTimingEntryCount: count, sampleTimingArray: $0.baseAddress!,
                                                  sampleBufferOut: &result)
        }
        guard status == noErr, let result else { throw ScreenRecordingCaptureError.writerUnavailable }
        return result
    }
}

struct ScreenRecordingCaptureFileOperations {
    var directoryExists: (URL) -> Bool
    var isSymbolicLink: (URL) throws -> Bool
    var createDirectory: (URL) throws -> Void
    var move: (URL, URL) throws -> Void
    var remove: (URL) throws -> Void

    static var live: Self {
        Self(
            directoryExists: { url in
                var isDirectory: ObjCBool = false
                return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) && isDirectory.boolValue
            },
            isSymbolicLink: { try $0.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink == true },
            createDirectory: { try FileManager.default.createDirectory(at: $0, withIntermediateDirectories: false,
                                                                       attributes: [.posixPermissions: 0o700]) },
            move: { try FileManager.default.moveItem(at: $0, to: $1) },
            remove: { try FileManager.default.removeItem(at: $0) }
        )
    }
}

final class ScreenRecordingCaptureFiles: @unchecked Sendable {
    let directory: URL
    let staging: URL
    let screenName: String
    let microphoneName: String
    let cameraName: String
    private let operations: ScreenRecordingCaptureFileOperations
    private var stagingExists = false
    private var published: [URL] = []

    init(directory: URL, identifier: UUID = UUID(), operations: ScreenRecordingCaptureFileOperations = .live) throws {
        guard directory.isFileURL, operations.directoryExists(directory), try !operations.isSymbolicLink(directory) else {
            throw ScreenRecordingCaptureError.invalidDirectory
        }
        self.directory = directory.standardizedFileURL
        self.operations = operations
        let suffix = identifier.uuidString.lowercased()
        staging = directory.appendingPathComponent(".capture-\(suffix)", isDirectory: true)
        screenName = "screen-\(suffix).mp4"
        microphoneName = "microphone-\(suffix).mp4"
        cameraName = "camera-\(suffix).mp4"
        try operations.createDirectory(staging)
        stagingExists = true
    }

    func url(for name: String) -> URL { staging.appendingPathComponent(name) }

    func publish(_ names: [String]) throws {
        for name in names {
            let output = directory.appendingPathComponent(name)
            try operations.move(url(for: name), output)
            published.append(output)
        }
        try operations.remove(staging)
        stagingExists = false
    }

    func discard() -> Error? {
        var failure: Error?
        published.removeAll { url in
            do {
                try operations.remove(url)
                return true
            } catch {
                failure = error
                return false
            }
        }
        if stagingExists {
            do {
                try operations.remove(staging)
                stagingExists = false
            } catch { failure = error }
        }
        return failure.map { ScreenRecordingCaptureError.saveFailed($0.localizedDescription) }
    }
}
