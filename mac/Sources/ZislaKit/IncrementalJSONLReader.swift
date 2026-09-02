import Foundation

struct IncrementalJSONLReader {
    struct State {
        var offset: UInt64
        fileprivate var observedStartOffset: UInt64
        fileprivate var observedHash: UInt64
        fileprivate var pending = Data()
        fileprivate var needsLeadingBoundaryCheck: Bool
        fileprivate var discardingCurrentLine = false

        var pendingBytes: Int { pending.count }

        mutating func consumePendingLineIfAccepted(
            _ body: (Data) throws -> Bool
        ) rethrows {
            guard !discardingCurrentLine, !pending.isEmpty, try body(pending) else { return }
            pending.removeAll(keepingCapacity: false)
        }
    }

    static let defaultInitialTailBytes = 1_024 * 1_024
    static let defaultChunkBytes = 256 * 1_024
    static let defaultMaximumLineBytes = 256 * 1_024
    private static let fnvOffsetBasis: UInt64 = 0xcbf29ce484222325
    private static let fnvPrime: UInt64 = 0x100000001b3

    let initialTailBytes: Int
    let chunkBytes: Int
    let maximumLineBytes: Int

    init(
        initialTailBytes: Int = defaultInitialTailBytes,
        chunkBytes: Int = defaultChunkBytes,
        maximumLineBytes: Int = defaultMaximumLineBytes
    ) {
        self.initialTailBytes = max(1, initialTailBytes)
        self.chunkBytes = max(1, chunkBytes)
        self.maximumLineBytes = max(1, maximumLineBytes)
    }

    func initialState(fileSize: UInt64) -> State {
        let tailBytes = UInt64(initialTailBytes)
        let offset = fileSize > tailBytes ? fileSize - tailBytes : 0
        return State(
            offset: offset,
            observedStartOffset: offset,
            observedHash: Self.fnvOffsetBasis,
            needsLeadingBoundaryCheck: offset > 0
        )
    }

    /// Checks that the bytes already reflected in a cached parser state have not been replaced in place.
    func hasUnchangedReadPrefix(at url: URL, state: State) -> Bool {
        guard state.observedStartOffset <= state.offset else { return false }
        guard state.observedStartOffset < state.offset else { return true }
        guard let handle = try? FileHandle(forReadingFrom: url) else { return false }
        defer { try? handle.close() }

        do {
            try handle.seek(toOffset: state.observedStartOffset)
            var offset = state.observedStartOffset
            var hash = Self.fnvOffsetBasis
            while offset < state.offset {
                let remaining = state.offset - offset
                let requested = requestedByteCount(for: remaining)
                guard let chunk = try handle.read(upToCount: requested), chunk.count == requested else {
                    return false
                }
                hash = Self.fnvHash(chunk, seed: hash)
                offset += UInt64(chunk.count)
            }
            return hash == state.observedHash
        } catch {
            return false
        }
    }

    func readLines(
        from url: URL,
        fileSize: UInt64,
        state: inout State,
        onChunk: ((Data) -> Void)? = nil,
        body: (Data) throws -> Void
    ) throws {
        if state.offset > fileSize {
            state = initialState(fileSize: fileSize)
        }
        guard state.offset < fileSize else { return }

        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        if state.needsLeadingBoundaryCheck {
            try handle.seek(toOffset: state.offset - 1)
            let previous = try handle.read(upToCount: 1)
            state.discardingCurrentLine = previous?.first != 0x0A
            state.needsLeadingBoundaryCheck = false
        }
        try handle.seek(toOffset: state.offset)

        while state.offset < fileSize {
            let remaining = fileSize - state.offset
            let requested = requestedByteCount(for: remaining)
            guard let chunk = try handle.read(upToCount: requested), !chunk.isEmpty else {
                break
            }
            state.offset += UInt64(chunk.count)
            state.observedHash = Self.fnvHash(chunk, seed: state.observedHash)
            onChunk?(chunk)
            try consume(chunk, state: &state, body: body)
        }
    }

    private func consume(
        _ chunk: Data,
        state: inout State,
        body: (Data) throws -> Void
    ) throws {
        var start = chunk.startIndex
        while let newline = chunk[start...].firstIndex(of: 0x0A) {
            try consume(
                chunk[start..<newline],
                endsLine: true,
                state: &state,
                body: body
            )
            start = chunk.index(after: newline)
        }
        if start < chunk.endIndex {
            try consume(
                chunk[start...],
                endsLine: false,
                state: &state,
                body: body
            )
        }
    }

    private func consume(
        _ fragment: Data.SubSequence,
        endsLine: Bool,
        state: inout State,
        body: (Data) throws -> Void
    ) throws {
        if state.discardingCurrentLine {
            if endsLine { state.discardingCurrentLine = false }
            return
        }

        if state.pending.count + fragment.count > maximumLineBytes {
            state.pending.removeAll(keepingCapacity: false)
            state.discardingCurrentLine = !endsLine
            return
        }
        state.pending.append(contentsOf: fragment)
        guard endsLine else { return }

        if !state.pending.isEmpty {
            try body(state.pending)
        }
        state.pending.removeAll(keepingCapacity: false)
    }

    private func requestedByteCount(for remaining: UInt64) -> Int {
        Int(min(remaining, UInt64(chunkBytes)))
    }

    private static func fnvHash(_ data: Data, seed: UInt64) -> UInt64 {
        var hash = seed
        for byte in data {
            hash ^= UInt64(byte)
            hash &*= fnvPrime
        }
        return hash
    }
}
