import Darwin
import Foundation

struct IncrementalJSONLReader {
    struct State {
        var offset: UInt64
        fileprivate var observedStartOffset: UInt64
        fileprivate var observedHead = Data()
        fileprivate var observedTail = Data()
        fileprivate var fileIdentity: FileIdentity?
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
    private static let verificationBytesPerEdge = 4 * 1_024

    fileprivate struct FileIdentity: Equatable {
        var device: dev_t
        var inode: ino_t
    }

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
            needsLeadingBoundaryCheck: offset > 0
        )
    }

    /// Checks the read interval's edges and any pending line, with a budget independent of file growth.
    /// Older edits that preserve both edges are outside this bounded check.
    func hasUnchangedReadPrefix(
        at url: URL,
        state: State,
        onChunk: ((Data) -> Void)? = nil
    ) -> Bool {
        guard state.observedStartOffset <= state.offset else { return false }
        guard state.observedStartOffset < state.offset else { return true }
        guard let handle = try? FileHandle(forReadingFrom: url) else { return false }
        defer { try? handle.close() }

        do {
            guard try Self.fileIdentity(of: handle) == state.fileIdentity,
                  try matches(state.observedHead, at: state.observedStartOffset,
                              handle: handle, onChunk: onChunk) else { return false }

            // The entire pending line must match before an append can safely complete it.
            let trailing = state.pending.count > state.observedTail.count ? state.pending : state.observedTail
            return try matches(trailing, at: state.offset - UInt64(trailing.count),
                               handle: handle, onChunk: onChunk)
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
        if state.fileIdentity == nil {
            state.fileIdentity = try Self.fileIdentity(of: handle)
        }
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
            state.observedHead.append(contentsOf: chunk.prefix(
                Self.verificationBytesPerEdge - state.observedHead.count
            ))
            var tail = Data()
            tail.append(contentsOf: state.observedTail.suffix(max(0, Self.verificationBytesPerEdge - chunk.count)))
            tail.append(contentsOf: chunk.suffix(Self.verificationBytesPerEdge))
            state.observedTail = tail
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

    private func matches(
        _ expected: Data,
        at offset: UInt64,
        handle: FileHandle,
        onChunk: ((Data) -> Void)?
    ) throws -> Bool {
        try handle.seek(toOffset: offset)
        var index = expected.startIndex
        while index < expected.endIndex {
            let requested = min(chunkBytes, expected.endIndex - index)
            guard let chunk = try handle.read(upToCount: requested) else {
                return false
            }
            onChunk?(chunk)
            let next = index + requested
            guard chunk.elementsEqual(expected[index..<next]) else { return false }
            index = next
        }
        return true
    }

    private static func fileIdentity(of handle: FileHandle) throws -> FileIdentity {
        var info = stat()
        guard fstat(handle.fileDescriptor, &info) == 0 else {
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
        }
        return FileIdentity(device: info.st_dev, inode: info.st_ino)
    }
}
