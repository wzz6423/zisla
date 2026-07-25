import Foundation
import Testing
@testable import ZislaKit

struct IncrementalJSONLReaderTests {
    @Test
    func readsOnlyTheConfiguredTailThenConsumesAppendedBytes() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("Zisla-jsonl-tail-\(UUID().uuidString).jsonl")
        defer { try? FileManager.default.removeItem(at: url) }
        try Data("old-one\nold-two\nrecent-one\nrecent-two\n".utf8).write(to: url)

        let reader = IncrementalJSONLReader(
            initialTailBytes: 24,
            chunkBytes: 5,
            maximumLineBytes: 64
        )
        var state = reader.initialState(fileSize: try fileSize(at: url))
        var lines: [String] = []

        try reader.readLines(from: url, fileSize: fileSize(at: url), state: &state) {
            lines.append(String(decoding: $0, as: UTF8.self))
        }
        #expect(lines == ["recent-one", "recent-two"])

        try append(Data("partial".utf8), to: url)
        try reader.readLines(from: url, fileSize: fileSize(at: url), state: &state) {
            lines.append(String(decoding: $0, as: UTF8.self))
        }
        #expect(lines == ["recent-one", "recent-two"])

        try append(Data("-line\n".utf8), to: url)
        try reader.readLines(from: url, fileSize: fileSize(at: url), state: &state) {
            lines.append(String(decoding: $0, as: UTF8.self))
        }
        #expect(lines == ["recent-one", "recent-two", "partial-line"])
    }

    @Test
    func skipsOversizedLinesWithoutRetainingTheirContents() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("Zisla-jsonl-oversized-\(UUID().uuidString).jsonl")
        defer { try? FileManager.default.removeItem(at: url) }
        try Data("1234567890\nok\n".utf8).write(to: url)

        let reader = IncrementalJSONLReader(
            initialTailBytes: 64,
            chunkBytes: 3,
            maximumLineBytes: 8
        )
        var state = reader.initialState(fileSize: try fileSize(at: url))
        var lines: [String] = []

        try reader.readLines(from: url, fileSize: fileSize(at: url), state: &state) {
            lines.append(String(decoding: $0, as: UTF8.self))
        }

        #expect(lines == ["ok"])
        #expect(state.pendingBytes == 0)
    }
}

private func fileSize(at url: URL) throws -> UInt64 {
    let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
    return try #require(attributes[.size] as? NSNumber).uint64Value
}

private func append(_ data: Data, to url: URL) throws {
    let handle = try FileHandle(forWritingTo: url)
    defer { try? handle.close() }
    try handle.seekToEnd()
    try handle.write(contentsOf: data)
}
