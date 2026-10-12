import Darwin
import Foundation

public final class PowerHelperSessionHost: NSObject, PowerHelperProtocol, @unchecked Sendable {
    private let lock = NSLock()
    private let script: String
    private let lockPath: String
    private var completed: DispatchGroup?

    public init(
        script: String = LidClosedDisplaySessionScript.script,
        lockPath: String = "/var/run/dev.wzz.zisla.power-helper.lock"
    ) {
        self.script = script
        self.lockPath = lockPath
    }

    public func openSession() throws -> FileHandle {
        try lock.withLock {
            // Two leases cannot independently restore the same global pmset setting.
            guard completed?.wait(timeout: .now() + 1) != .timedOut else {
                throw CocoaError(.fileLocking)
            }
            let descriptor = open(lockPath, O_RDWR | O_CREAT | O_NOFOLLOW | O_CLOEXEC, 0o600)
            guard descriptor >= 0 else { throw CocoaError(.fileLocking) }
            let leaseLock = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
            defer { try? leaseLock.close() }
            var metadata = stat()
            guard fstat(descriptor, &metadata) == 0,
                  metadata.st_uid == geteuid(), metadata.st_nlink == 1,
                  metadata.st_mode & 0o077 == 0,
                  flock(descriptor, LOCK_EX | LOCK_NB) == 0
            else { throw CocoaError(.fileLocking) }
            var descriptors: [Int32] = [-1, -1]
            guard socketpair(AF_UNIX, SOCK_STREAM, 0, &descriptors) == 0 else {
                throw CocoaError(.fileReadUnknown)
            }
            let client = FileHandle(fileDescriptor: descriptors[0], closeOnDealloc: true)
            let child = FileHandle(fileDescriptor: descriptors[1], closeOnDealloc: true)
            defer { try? child.close() }
            guard fcntl(client.fileDescriptor, F_SETFD, FD_CLOEXEC) == 0,
                  fcntl(child.fileDescriptor, F_SETFD, FD_CLOEXEC) == 0
            else { throw CocoaError(.fileWriteUnknown) }

            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/sh")
            // The lease child keeps the global lock even if launchd restarts its daemon.
            process.arguments = ["-p", "-c", "exec 3>&2\nexec 2>/dev/null\n" + script]
            process.environment = ["PATH": "/usr/bin:/bin:/usr/sbin:/sbin", "LC_ALL": "C"]
            process.standardInput = child
            process.standardOutput = child
            process.standardError = leaseLock
            let completed = DispatchGroup()
            completed.enter()
            process.terminationHandler = { _ in completed.leave() }
            try process.run()
            self.completed = completed
            return client
        }
    }

    public func openSession(reply: @escaping (FileHandle?, NSError?) -> Void) {
        do {
            reply(try openSession(), nil)
        } catch {
            reply(nil, error as NSError)
        }
    }
}

public final class PowerHelperListener: NSObject, NSXPCListenerDelegate, @unchecked Sendable {
    private let host: PowerHelperSessionHost
    private let requirement: String

    public init(requirement: String, host: PowerHelperSessionHost = PowerHelperSessionHost()) {
        self.requirement = requirement
        self.host = host
    }

    public func listener(_ listener: NSXPCListener, shouldAcceptNewConnection connection: NSXPCConnection) -> Bool {
        connection.setCodeSigningRequirement(requirement)
        connection.exportedInterface = NSXPCInterface(with: PowerHelperProtocol.self)
        connection.exportedObject = host
        connection.resume()
        return true
    }
}
