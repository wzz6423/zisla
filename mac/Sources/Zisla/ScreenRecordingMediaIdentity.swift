import CryptoKit
import Foundation

enum RecordingMediaIdentity {
    static func digest(of url: URL,
                       checkCancellation: @Sendable () throws -> Void = { try Task.checkCancellation() }) throws -> String {
        try checkCancellation()
        let handle = try FileHandle(forReadingFrom: url)
        var hash = SHA256()
        while let chunk = try handle.read(upToCount: 1_048_576) {
            try checkCancellation()
            hash.update(data: chunk)
        }
        return hash.finalize().map { String(format: "%02x", $0) }.joined()
    }
}
