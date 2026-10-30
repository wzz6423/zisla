import Foundation
import Testing
@testable import Zisla

struct ScreenRecordingMediaIdentityTests {
    @Test(arguments: [
        (0, "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"),
        (1, "6e340b9cffb37a989ca544e6bb780a2c78901d3fb33738768511a30617afa01d"),
        (1_048_575, "8b55c6a2d3444092a316985030e00c1e6f8608eaf912c896dee7c374d440ed11"),
        (1_048_576, "631b84027d6b9e52b539c4e8373622d23032dfadc64d60af87339c9037e4f769"),
        (1_048_577, "5769f52bc3eef28afa39c6fc68cadb7d0bd69812ae3a3d71452f519ec3c7aa56"),
        (2_097_169, "b057f26faa652e9916aa08eed7e50906151f83de0e878173e9d06e359c0dd75e"),
    ])
    func completeContentMatchesIndependentSHA256Vectors(count: Int, expected: String) throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("fixture.bin")
        let data = Data((0..<count).map { UInt8($0 % 251) })
        try data.write(to: url)
        #expect(try RecordingMediaIdentity.digest(of: url) == expected)
        #expect(try Data(contentsOf: url) == data)
    }

    @Test func renamedCopiesMatchWhileEqualSizedMiddleChangesRemainDistinct() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let original = directory.appendingPathComponent("original.bin")
        let copy = directory.appendingPathComponent("renamed.bin")
        let changed = directory.appendingPathComponent("middle-change.bin")
        let data = Data(repeating: 42, count: 2_097_169)
        try data.write(to: original)
        try FileManager.default.copyItem(at: original, to: copy)
        var different = data
        different[different.count / 2] = 23
        try different.write(to: changed)
        let digest = try RecordingMediaIdentity.digest(of: original)
        #expect(try RecordingMediaIdentity.digest(of: copy) == digest)
        #expect(try RecordingMediaIdentity.digest(of: changed) != digest,
                "File name, size and matching edge bytes must not conceal changed content")
        #expect(try Data(contentsOf: original) == data)
        #expect(try Data(contentsOf: changed) == different)
    }

    @Test(arguments: [1, 3])
    func cancellationBeforeOrDuringStreamingPreservesInput(_ checkpoint: Int) throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("cancelled.bin")
        let data = Data(repeating: 42, count: 2_097_169)
        try data.write(to: url)
        let cancellation = CancellationCheckpoint(stopAt: checkpoint)
        #expect(throws: CancellationError.self) {
            try RecordingMediaIdentity.digest(of: url, checkCancellation: { try cancellation.check() })
        }
        #expect(try Data(contentsOf: url) == data)
        #expect(try FileManager.default.contentsOfDirectory(atPath: directory.path) == [url.lastPathComponent])
        #expect(try RecordingMediaIdentity.digest(of: url) == "5db2a5a626b727f03f1081bfbc04f16d2c22fd45b7509ceb3bb4f8f55a3fd4d2")
    }

    @Test func alreadyCancelledEmptyAndMissingInputsStopBeforeReading() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let empty = directory.appendingPathComponent("empty.bin")
        try Data().write(to: empty)
        for url in [empty, directory.appendingPathComponent("missing.bin")] {
            #expect(throws: CancellationError.self) {
                try RecordingMediaIdentity.digest(of: url, checkCancellation: { throw CancellationError() })
            }
        }
        #expect(try FileManager.default.contentsOfDirectory(atPath: directory.path) == [empty.lastPathComponent])
    }

    @Test func shortFileChecksCancellationAndEOFTerminatesWithinABoundedReadBudget() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("short.bin")
        try Data([0]).write(to: url)
        let cancelled = CancellationCheckpoint(stopAt: 2)
        #expect(throws: CancellationError.self) {
            try RecordingMediaIdentity.digest(of: url, checkCancellation: { try cancelled.check() })
        }
        let budget = CancellationCheckpoint(stopAt: 4)
        #expect(try RecordingMediaIdentity.digest(of: url, checkCancellation: { try budget.check() })
            == "6e340b9cffb37a989ca544e6bb780a2c78901d3fb33738768511a30617afa01d")
        try Data().write(to: url)
        let emptyBudget = CancellationCheckpoint(stopAt: 4)
        #expect(try RecordingMediaIdentity.digest(of: url, checkCancellation: { try emptyBudget.check() })
            == "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855")
        #expect(try Data(contentsOf: url).isEmpty)
    }

    @Test func missingAndUnreadableInputsPropagateErrorsWithoutCreatingFiles() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        #expect(throws: Error.self) {
            try RecordingMediaIdentity.digest(of: directory.appendingPathComponent("missing.bin"))
        }
        #expect(throws: Error.self) { try RecordingMediaIdentity.digest(of: directory) }
        #expect(try FileManager.default.contentsOfDirectory(atPath: directory.path).isEmpty)
    }

    private func temporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("zisla-media-identity-\(UUID())", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        return directory
    }

    private final class CancellationCheckpoint: @unchecked Sendable {
        private let lock = NSLock()
        private let stopAt: Int
        private var count = 0

        init(stopAt: Int) { self.stopAt = stopAt }

        func check() throws {
            let cancelled = lock.withLock { count += 1; return count == stopAt }
            if cancelled { throw CancellationError() }
        }
    }
}
