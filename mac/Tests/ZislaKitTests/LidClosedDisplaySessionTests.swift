import Darwin
import Foundation
import Testing
@testable import ZislaKit

struct LidClosedDisplaySessionTests {
    @Test
    func sessionAcknowledgesRestoreAndReleasesItsConnection() throws {
        let connection = try Connection()
        defer { connection.closePeer() }
        try connection.reply("ready\n")
        let session = try PMSetLidClosedDisplaySession(pipe: connection.pipe)
        try connection.reply("restored\n")

        try session.stop()

        #expect(try connection.receive() == "stop\n")
        #expect(try connection.receive() == "")
        try session.stop()
    }

    @Test
    func connectionHasBoundedReadsAndCannotBeInheritedByAnotherExecutable() throws {
        let connection = try Connection()
        defer { connection.closePeer() }
        try connection.reply("ready\n")
        let session = try PMSetLidClosedDisplaySession(pipe: connection.pipe)
        defer { session.cancel() }

        #expect(fcntl(fileno(connection.pipe), F_GETFD) & FD_CLOEXEC != 0)
        var timeout = timeval()
        var size = socklen_t(MemoryLayout.size(ofValue: timeout))
        #expect(getsockopt(fileno(connection.pipe), SOL_SOCKET, SO_RCVTIMEO, &timeout, &size) == 0)
        #expect(timeout.tv_sec > 0 && timeout.tv_sec <= 5)
    }

    @Test
    func failedRestoreCanRetryOverTheSameConnection() throws {
        let connection = try Connection()
        defer { connection.closePeer() }
        try connection.reply("ready\n")
        let session = try PMSetLidClosedDisplaySession(pipe: connection.pipe)
        defer { session.cancel() }
        try connection.reply("failed\n")

        #expect(throws: (any Error).self) { try session.stop() }
        #expect(try connection.receive() == "stop\n")
        try connection.reply("restored\n")
        try session.stop()
        #expect(try connection.receive() == "stop\n")
        #expect(try connection.receive() == "")
    }

    @Test(arguments: [false, true])
    func cancelOrDeinitializationClosesTheLease(cancelExplicitly: Bool) throws {
        let connection = try Connection()
        defer { connection.closePeer() }
        try connection.reply("ready\n")
        var session: PMSetLidClosedDisplaySession? = try PMSetLidClosedDisplaySession(pipe: connection.pipe)
        if cancelExplicitly {
            session?.cancel()
            session?.cancel()
        }
        session = nil

        #expect(try connection.receive() == "")
    }

    @Test(arguments: ["failed\n", "", "rea", String(repeating: "x", count: 32)])
    func missingOrInvalidAcknowledgmentClosesTheConnection(reply: String) throws {
        let connection = try Connection()
        defer { connection.closePeer() }
        try connection.reply(reply)
        if reply.count < 32 { shutdown(connection.peer, SHUT_WR) }
        let start = ContinuousClock.now

        #expect(throws: (any Error).self) {
            try PMSetLidClosedDisplaySession(pipe: connection.pipe)
        }
        if reply.count == 32 { #expect(start.duration(to: .now) < .seconds(1)) }
        #expect(try connection.receive() == "")
    }

    @Test
    func disconnectedHelperReportsFailureWithoutRaisingSIGPIPE() throws {
        let connection = try Connection()
        try connection.reply("ready\n")
        let session = try PMSetLidClosedDisplaySession(pipe: connection.pipe)
        defer { session.cancel() }
        connection.closePeer()

        #expect(throws: (any Error).self) { try session.stop() }
    }

    @Test
    func unresponsiveHelperCannotKeepAnAuthorizationRequestPendingForever() throws {
        let connection = try Connection()
        defer { connection.closePeer() }
        let start = ContinuousClock.now

        #expect(throws: (any Error).self) {
            try PMSetLidClosedDisplaySession(pipe: connection.pipe)
        }

        #expect(start.duration(to: .now) < .seconds(10))
        #expect(try connection.receive() == "")
    }

    private struct Connection {
        let peer: Int32
        let pipe: UnsafeMutablePointer<FILE>

        init() throws {
            var descriptors: [Int32] = [0, 0]
            guard socketpair(AF_UNIX, SOCK_STREAM, 0, &descriptors) == 0 else {
                throw CocoaError(.fileReadUnknown)
            }
            peer = descriptors[1]
            pipe = fdopen(descriptors[0], "r+")!
            var timeout = timeval(tv_sec: 1, tv_usec: 0)
            setsockopt(peer, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout.size(ofValue: timeout)))
        }

        func reply(_ text: String) throws {
            let result = text.withCString { send(peer, $0, text.utf8.count, MSG_NOSIGNAL) }
            #expect(result == text.utf8.count)
        }

        func receive() throws -> String {
            var bytes = [UInt8](repeating: 0, count: 64)
            let count = recv(peer, &bytes, bytes.count, 0)
            guard count >= 0 else { throw CocoaError(.fileReadUnknown) }
            return String(decoding: bytes.prefix(count), as: UTF8.self)
        }

        func closePeer() { close(peer) }
    }
}
