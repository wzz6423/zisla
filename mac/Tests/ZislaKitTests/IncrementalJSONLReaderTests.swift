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

    @Test
    func rejectsARewrittenReadPrefixBeforeContinuing() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("Zisla-jsonl-rewrite-\(UUID().uuidString).jsonl")
        defer { try? FileManager.default.removeItem(at: url) }
        try Data("old-record\n".utf8).write(to: url)

        let reader = IncrementalJSONLReader(initialTailBytes: 64)
        var state = reader.initialState(fileSize: try fileSize(at: url))
        try reader.readLines(from: url, fileSize: fileSize(at: url), state: &state) { _ in }
        #expect(reader.hasUnchangedReadPrefix(at: url, state: state))

        try Data("new-record-with-a-larger-payload\n".utf8).write(to: url)
        #expect(!reader.hasUnchangedReadPrefix(at: url, state: state))
    }

    @Test
    func prefixVerificationHasAFixedByteBudgetAfterRepeatedAppends() throws {
        let url = temporaryLogURL()
        defer { try? FileManager.default.removeItem(at: url) }
        try Data("header\n".utf8).write(to: url)
        let reader = IncrementalJSONLReader(initialTailBytes: 64, chunkBytes: 307)
        var state = reader.initialState(fileSize: try fileSize(at: url))
        try reader.readLines(from: url, fileSize: fileSize(at: url), state: &state) { _ in }

        for iteration in 0..<8 {
            try append(Data(repeating: 0x0A, count: 64 * 1_024), to: url)
            try reader.readLines(from: url, fileSize: fileSize(at: url), state: &state) { _ in }
            var verifiedBytes = 0
            var largestChunk = 0
            #expect(reader.hasUnchangedReadPrefix(at: url, state: state, onChunk: {
                verifiedBytes += $0.count
                largestChunk = max(largestChunk, $0.count)
            }))
            try #require(verifiedBytes <= 8 * 1_024,
                         "iteration \(iteration) verified \(verifiedBytes) historical bytes")
            #expect(verifiedBytes > 0)
            #expect(largestChunk <= reader.chunkBytes)
            #expect(state.pendingBytes == 0)
            #expect(state.offset == (try fileSize(at: url)))
        }
    }

    @Test(arguments: [0, 4_095, 15_904, 19_999])
    func rejectsRewritesAtBothEdgesOfTheReadInterval(relativeOffset: Int) throws {
        let url = temporaryLogURL()
        defer { try? FileManager.default.removeItem(at: url) }
        try Data(repeating: 0x0A, count: 24_000).write(to: url)
        let reader = IncrementalJSONLReader(initialTailBytes: 20_000, chunkBytes: 513)
        var state = reader.initialState(fileSize: try fileSize(at: url))
        let initialOffset = state.offset
        try reader.readLines(from: url, fileSize: fileSize(at: url), state: &state) { _ in }

        try overwrite(Data([0x78]), at: initialOffset + UInt64(relativeOffset), in: url)
        try append(Data("next\n".utf8), to: url)
        #expect(!reader.hasUnchangedReadPrefix(at: url, state: state))
    }

    @Test
    func verifiesTheEntirePendingLineWithinTheConfiguredBudget() throws {
        let url = temporaryLogURL()
        defer { try? FileManager.default.removeItem(at: url) }
        let prefix = Data(repeating: 0x0A, count: 12 * 1_024)
        let pending = Data(repeating: 0x78, count: 16 * 1_024)
        try (prefix + pending).write(to: url)
        let reader = IncrementalJSONLReader(
            initialTailBytes: .max,
            chunkBytes: 1_023,
            maximumLineBytes: pending.count
        )
        var state = reader.initialState(fileSize: try fileSize(at: url))
        try reader.readLines(from: url, fileSize: fileSize(at: url), state: &state) { _ in }
        #expect(state.pendingBytes == pending.count)

        var verifiedBytes = 0
        #expect(reader.hasUnchangedReadPrefix(at: url, state: state, onChunk: {
            verifiedBytes += $0.count
        }))
        #expect(verifiedBytes <= 4 * 1_024 + pending.count)

        try overwrite(Data([0x79]), at: UInt64(prefix.count + 1_024), in: url)
        try append(Data("\nnext\n".utf8), to: url)
        #expect(!reader.hasUnchangedReadPrefix(at: url, state: state))
        state = reader.initialState(fileSize: try fileSize(at: url))
        var lines: [Data] = []
        try reader.readLines(from: url, fileSize: fileSize(at: url), state: &state) {
            lines.append($0)
        }
        var rewrittenPending = pending
        rewrittenPending[1_024] = 0x79
        #expect(lines == [rewrittenPending, Data("next".utf8)])
        #expect(state.pendingBytes == 0)
    }

    @Test
    func rejectsAnAtomicReplacementEvenWhenItsReadBytesMatch() throws {
        let url = temporaryLogURL()
        defer { try? FileManager.default.removeItem(at: url) }
        let original = Data("same-record\npartial".utf8)
        try original.write(to: url)
        let reader = IncrementalJSONLReader()
        var state = reader.initialState(fileSize: try fileSize(at: url))
        try reader.readLines(from: url, fileSize: fileSize(at: url), state: &state) { _ in }

        try (original + Data("-line\n".utf8)).write(to: url, options: .atomic)
        #expect(!reader.hasUnchangedReadPrefix(at: url, state: state))
        state = reader.initialState(fileSize: try fileSize(at: url))
        var lines: [String] = []
        try reader.readLines(from: url, fileSize: fileSize(at: url), state: &state) {
            lines.append(String(decoding: $0, as: UTF8.self))
        }
        #expect(lines == ["same-record", "partial-line"])
    }

    @Test
    func retainsTheIdentityOfTheOpenedFileDuringReplacement() throws {
        let url = temporaryLogURL()
        defer { try? FileManager.default.removeItem(at: url) }
        let original = Data("old-one\nold-two\n".utf8)
        try original.write(to: url)
        let reader = IncrementalJSONLReader(chunkBytes: 4)
        var state = reader.initialState(fileSize: UInt64(original.count))
        var replaced = false
        var replacementError: (any Error)?
        var lines: [String] = []
        try reader.readLines(
            from: url,
            fileSize: UInt64(original.count),
            state: &state,
            onChunk: { _ in
                if !replaced {
                    replaced = true
                    do {
                        try original.write(to: url, options: .atomic)
                    } catch {
                        replacementError = error
                    }
                }
            }
        ) {
            lines.append(String(decoding: $0, as: UTF8.self))
        }
        if let replacementError { throw replacementError }
        #expect(lines == ["old-one", "old-two"])
        #expect(!reader.hasUnchangedReadPrefix(at: url, state: state))
    }

    @Test
    func aReplacementBeforeAnAppendReadDoesNotBlessTheCachedIdentity() throws {
        let url = temporaryLogURL()
        defer { try? FileManager.default.removeItem(at: url) }
        let original = Data("old\npartial".utf8)
        try original.write(to: url)
        let reader = IncrementalJSONLReader(chunkBytes: 3)
        var state = reader.initialState(fileSize: UInt64(original.count))
        try reader.readLines(from: url, fileSize: fileSize(at: url), state: &state) { _ in }
        #expect(reader.hasUnchangedReadPrefix(at: url, state: state))

        // A writer can replace the path between prefix verification and the following read.
        try (original + Data("-line\n".utf8)).write(to: url, options: .atomic)
        try reader.readLines(from: url, fileSize: fileSize(at: url), state: &state) { _ in }
        #expect(!reader.hasUnchangedReadPrefix(at: url, state: state))
    }

    @Test
    func truncationResetsPendingAndOversizedLineDiscarding() throws {
        let url = temporaryLogURL()
        defer { try? FileManager.default.removeItem(at: url) }
        try Data("partial".utf8).write(to: url)
        let reader = IncrementalJSONLReader(initialTailBytes: 128, chunkBytes: 3, maximumLineBytes: 8)
        var state = reader.initialState(fileSize: try fileSize(at: url))
        try reader.readLines(from: url, fileSize: fileSize(at: url), state: &state) { _ in }
        #expect(state.pendingBytes == 7)
        try append(Data("-oversized-without-newline".utf8), to: url)
        try reader.readLines(from: url, fileSize: fileSize(at: url), state: &state) { _ in }
        #expect(state.pendingBytes == 0)

        try Data().write(to: url)
        #expect(!reader.hasUnchangedReadPrefix(at: url, state: state))
        try reader.readLines(from: url, fileSize: 0, state: &state) { _ in }
        #expect(state.offset == 0)
        #expect(state.pendingBytes == 0)
        try append(Data("new\n".utf8), to: url)
        var lines: [String] = []
        try reader.readLines(from: url, fileSize: fileSize(at: url), state: &state) {
            lines.append(String(decoding: $0, as: UTF8.self))
        }
        #expect(lines == ["new"])
        #expect(reader.hasUnchangedReadPrefix(at: url, state: state))
    }

    @Test
    func acceptedPendingRecordsKeepTheNextAppendSeparate() throws {
        let url = temporaryLogURL()
        defer { try? FileManager.default.removeItem(at: url) }
        try Data(#"{"record":1}"#.utf8).write(to: url)
        let reader = IncrementalJSONLReader(chunkBytes: 3)
        var state = reader.initialState(fileSize: try fileSize(at: url))
        var lines: [Data] = []
        try reader.readLines(from: url, fileSize: fileSize(at: url), state: &state) {
            lines.append($0)
        }
        state.consumePendingLineIfAccepted { _ in false }
        #expect(state.pendingBytes == 12)
        state.consumePendingLineIfAccepted {
            lines.append($0)
            return true
        }
        #expect(state.pendingBytes == 0)
        #expect(reader.hasUnchangedReadPrefix(at: url, state: state))

        try append(Data("{\"record\":2}\n".utf8), to: url)
        try reader.readLines(from: url, fileSize: fileSize(at: url), state: &state) {
            lines.append($0)
        }
        #expect(lines == [Data(#"{"record":1}"#.utf8), Data(#"{"record":2}"#.utf8)])
        #expect(reader.hasUnchangedReadPrefix(at: url, state: state))
    }

    @Test
    func missingFileFailurePreservesStateAndRecoversAfterRecreation() throws {
        let url = temporaryLogURL()
        defer { try? FileManager.default.removeItem(at: url) }
        let original = Data("ok\npartial".utf8)
        try original.write(to: url)
        let reader = IncrementalJSONLReader()
        var state = reader.initialState(fileSize: UInt64(original.count))
        try reader.readLines(from: url, fileSize: UInt64(original.count), state: &state) { _ in }
        let previousOffset = state.offset
        let previousPendingBytes = state.pendingBytes

        try FileManager.default.removeItem(at: url)
        #expect(!reader.hasUnchangedReadPrefix(at: url, state: state))
        #expect(throws: (any Error).self) {
            try reader.readLines(from: url, fileSize: previousOffset + 1, state: &state) { _ in }
        }
        #expect(state.offset == previousOffset)
        #expect(state.pendingBytes == previousPendingBytes)

        try (original + Data("-line\n".utf8)).write(to: url)
        state = reader.initialState(fileSize: try fileSize(at: url))
        var lines: [String] = []
        try reader.readLines(from: url, fileSize: fileSize(at: url), state: &state) {
            lines.append(String(decoding: $0, as: UTF8.self))
        }
        #expect(lines == ["ok", "partial-line"])
        #expect(reader.hasUnchangedReadPrefix(at: url, state: state))
    }

    @Test
    func rejectsTruncationDuringPrefixVerification() throws {
        let url = temporaryLogURL()
        defer { try? FileManager.default.removeItem(at: url) }
        try Data(repeating: 0x0A, count: 16 * 1_024).write(to: url)
        let reader = IncrementalJSONLReader(chunkBytes: 1_024)
        var state = reader.initialState(fileSize: try fileSize(at: url))
        try reader.readLines(from: url, fileSize: fileSize(at: url), state: &state) { _ in }
        let writer = try FileHandle(forWritingTo: url)
        defer { try? writer.close() }
        var truncated = false
        var truncationError: (any Error)?
        #expect(!reader.hasUnchangedReadPrefix(at: url, state: state, onChunk: { _ in
            if !truncated {
                truncated = true
                do {
                    try writer.truncate(atOffset: 0)
                } catch {
                    truncationError = error
                }
            }
        }))
        if let truncationError { throw truncationError }
        #expect(state.offset == 16 * 1_024)
        #expect(state.pendingBytes == 0)

        try reader.readLines(from: url, fileSize: 0, state: &state) { _ in }
        try append(Data("recovered\n".utf8), to: url)
        var lines: [String] = []
        try reader.readLines(from: url, fileSize: fileSize(at: url), state: &state) {
            lines.append(String(decoding: $0, as: UTF8.self))
        }
        #expect(lines == ["recovered"])
        #expect(reader.hasUnchangedReadPrefix(at: url, state: state))
    }

    @Test
    func aFailedParseCanRetryFromTheUnmodifiedCachedState() throws {
        enum ParseFailure: Error { case injected }
        let url = temporaryLogURL()
        defer { try? FileManager.default.removeItem(at: url) }
        try Data("first\npartial".utf8).write(to: url)
        let reader = IncrementalJSONLReader(chunkBytes: 5)
        var cachedState = reader.initialState(fileSize: try fileSize(at: url))
        try reader.readLines(from: url, fileSize: fileSize(at: url), state: &cachedState) { _ in }
        var attemptedState = cachedState
        try append(Data("-line\nlast\n".utf8), to: url)
        #expect(throws: ParseFailure.injected) {
            try reader.readLines(from: url, fileSize: fileSize(at: url), state: &attemptedState) { _ in
                throw ParseFailure.injected
            }
        }
        #expect(cachedState.offset == 13)
        #expect(cachedState.pendingBytes == 7)
        #expect(reader.hasUnchangedReadPrefix(at: url, state: cachedState))

        var lines: [String] = []
        try reader.readLines(from: url, fileSize: fileSize(at: url), state: &cachedState) {
            lines.append(String(decoding: $0, as: UTF8.self))
        }
        #expect(lines == ["partial-line", "last"])
        #expect(cachedState.pendingBytes == 0)
        #expect(reader.hasUnchangedReadPrefix(at: url, state: cachedState))
    }

    @Test
    func olderMiddleEditsAreOutsideTheBoundedVerificationContract() throws {
        let url = temporaryLogURL()
        defer { try? FileManager.default.removeItem(at: url) }
        try Data(repeating: 0x0A, count: 24 * 1_024).write(to: url)
        let reader = IncrementalJSONLReader(initialTailBytes: .max)
        var state = reader.initialState(fileSize: try fileSize(at: url))
        try reader.readLines(from: url, fileSize: fileSize(at: url), state: &state) { _ in }

        // Fixed I/O cannot detect an older same-inode edit that leaves both cached edges unchanged.
        try overwrite(Data([0x78]), at: 12 * 1_024, in: url)
        try append(Data("next\n".utf8), to: url)
        var verifiedBytes = 0
        #expect(reader.hasUnchangedReadPrefix(at: url, state: state, onChunk: {
            verifiedBytes += $0.count
        }))
        #expect(verifiedBytes == 8 * 1_024)
    }

    @Test
    func seededAppendPartitionsMatchWholeTailLineParsing() throws {
        let url = temporaryLogURL()
        defer { try? FileManager.default.removeItem(at: url) }
        var seed: UInt64 = 0xDA7E
        func random(_ bound: Int) -> Int {
            seed = seed &* 6_364_136_223_846_793_005 &+ 1
            return Int((seed >> 32) % UInt64(bound))
        }
        let alphabet: [UInt8] = [0, 0x0D, 0x20, 0x41, 0x7B, 0xC3, 0xA9, 0xF0, 0xA0]

        for scenario in 0..<64 {
            var input = Data()
            for line in 0..<12 {
                for _ in 0..<random(49) {
                    input.append(alphabet[random(alphabet.count)])
                }
                if line < 11 || random(2) == 0 { input.append(0x0A) }
            }
            try #require(input.count <= 1_024, "seed 0xDA7E exceeded the per-scenario input budget")
            let initialSize = random(input.count + 1)
            try input.prefix(initialSize).write(to: url)
            let maximumLineBytes = 24
            let reader = IncrementalJSONLReader(
                initialTailBytes: 1 + random(97),
                chunkBytes: 1 + random(11),
                maximumLineBytes: maximumLineBytes
            )
            var state = reader.initialState(fileSize: UInt64(initialSize))
            let initialOffset = Int(state.offset)
            var lines: [Data] = []
            var size = initialSize
            var steps = 0
            while true {
                try reader.readLines(from: url, fileSize: UInt64(size), state: &state) {
                    lines.append($0)
                }
                let expected = tailLines(in: input.prefix(size), startingAt: initialOffset,
                                         maximumLineBytes: maximumLineBytes)
                #expect(lines == expected.lines, "seed 0xDA7E scenario \(scenario), size \(size)")
                #expect(state.pendingBytes == expected.pendingBytes,
                        "seed 0xDA7E scenario \(scenario), size \(size)")
                #expect(state.pendingBytes <= maximumLineBytes)
                #expect(state.offset == UInt64(size))
                var verifiedBytes = 0
                #expect(reader.hasUnchangedReadPrefix(at: url, state: state, onChunk: {
                    verifiedBytes += $0.count
                }))
                #expect(verifiedBytes <= 8 * 1_024)
                if size == input.count { break }
                let nextSize = min(input.count, size + 1 + random(31))
                try append(input[size..<nextSize], to: url)
                size = nextSize
                steps += 1
                try #require(steps <= 1_024, "seed 0xDA7E exceeded the append-step budget")
            }
        }
    }
}

private func temporaryLogURL() -> URL {
    FileManager.default.temporaryDirectory
        .appendingPathComponent("Zisla-jsonl-prefix-\(UUID().uuidString).jsonl")
}

private func overwrite(_ data: Data, at offset: UInt64, in url: URL) throws {
    let handle = try FileHandle(forWritingTo: url)
    defer { try? handle.close() }
    try handle.seek(toOffset: offset)
    try handle.write(contentsOf: data)
}

private func tailLines(
    in input: Data,
    startingAt offset: Int,
    maximumLineBytes: Int
) -> (lines: [Data], pendingBytes: Int) {
    var bytes = Array(input.dropFirst(offset))
    if offset > 0, input[offset - 1] != 0x0A {
        guard let newline = bytes.firstIndex(of: 0x0A) else { return ([], 0) }
        bytes = Array(bytes.dropFirst(newline + 1))
    }
    let fragments = bytes.split(separator: 0x0A, omittingEmptySubsequences: false)
    let lines = fragments.dropLast().filter { !$0.isEmpty && $0.count <= maximumLineBytes }.map { Data($0) }
    let pendingBytes = fragments.last.map { $0.count <= maximumLineBytes ? $0.count : 0 } ?? 0
    return (lines, pendingBytes)
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
