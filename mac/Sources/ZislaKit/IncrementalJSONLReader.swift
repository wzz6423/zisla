import Foundation

struct IncrementalJSONLReader {
    struct State {
        var offset: UInt64
        fileprivate var pending = Data()
        fileprivate var needsLeadingBoundaryCheck: Bool
        fileprivate var discardingCurrentLine = false

        var pendingBytes: Int { pending.count }
    }

    static let defaultInitialTailBytes = 1_024 * 1_024
    static let defaultChunkBytes = 256 * 1_024
    static let defaultMaximumLineBytes = 256 * 1_024

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
            needsLeadingBoundaryCheck: offset > 0
        )
    }

    func readLines(
        from url: URL,
        fileSize: UInt64,
        state: inout State,
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
            let requested = min(chunkBytes, Int(min(remaining, UInt64(Int.max))))
            guard let chunk = try handle.read(upToCount: requested), !chunk.isEmpty else {
                break
            }
            state.offset += UInt64(chunk.count)
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
}
