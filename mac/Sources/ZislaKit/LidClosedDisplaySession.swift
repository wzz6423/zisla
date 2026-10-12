import Darwin
import Foundation

protocol LidClosedDisplaySession: AnyObject, Sendable {
    func stop() throws
    func cancel()
}

final class PMSetLidClosedDisplaySession: LidClosedDisplaySession, @unchecked Sendable {
    private let lock = NSLock()
    private var pipe: UnsafeMutablePointer<FILE>?

    static func start() throws -> PMSetLidClosedDisplaySession {
        let pipe = try PrivilegedPowerHelperClient.shared.openSession()
        return try PMSetLidClosedDisplaySession(pipe: pipe)
    }

    init(pipe: UnsafeMutablePointer<FILE>) throws {
        self.pipe = pipe
        let descriptor = fileno(pipe)
        var timeout = timeval(tv_sec: 5, tv_usec: 0)
        // Children must not inherit the lease and keep sleep disabled after the app exits.
        guard fcntl(descriptor, F_SETFD, FD_CLOEXEC) == 0,
              setsockopt(descriptor, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout.size(ofValue: timeout))) == 0,
              try readLine(from: descriptor) == "ready"
        else {
            throw CocoaError(.executableRuntimeMismatch)
        }
    }

    deinit {
        if let pipe { fclose(pipe) }
    }

    func stop() throws {
        lock.lock()
        defer { lock.unlock() }
        guard let pipe else { return }
        let sent = "stop\n".withCString { send(fileno(pipe), $0, 5, MSG_NOSIGNAL) }
        guard sent == 5, try readLine(from: fileno(pipe)) == "restored" else {
            throw CocoaError(.executableRuntimeMismatch)
        }
        fclose(pipe)
        self.pipe = nil
    }

    func cancel() {
        lock.lock()
        defer { lock.unlock() }
        if let pipe { fclose(pipe) }
        pipe = nil
    }

    private func readLine(from descriptor: Int32) throws -> String {
        var bytes: [UInt8] = []
        for _ in 0..<32 {
            var byte: UInt8 = 0
            guard recv(descriptor, &byte, 1, 0) == 1 else {
                throw CocoaError(.fileReadUnknown)
            }
            if byte == 10 { return String(decoding: bytes, as: UTF8.self) }
            bytes.append(byte)
        }
        throw CocoaError(.fileReadCorruptFile)
    }
}
