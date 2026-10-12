import Darwin
import Foundation
import Testing
import ZislaPowerHelperSupport
@testable import ZislaKit

struct PowerHelperSessionHostTests {
    private static let script = #"""
    printf 'ready\n'
    while IFS= read -r request; do
        [ "$request" = stop ] || exit 1
        printf 'restored\n'
        exit 0
    done
    """#

    @Test
    func stoppingThenImmediatelyOpeningAnotherLeaseWaitsForThePreviousChild() throws {
        let directory = try TemporaryDirectory()
        defer { directory.remove() }
        let host = PowerHelperSessionHost(script: Self.script, lockPath: directory.lockPath)
        for _ in 0..<16 {
            let session = try makeSession(host: host)
            try session.stop()
        }
    }

    @Test
    func aSecondConcurrentLeaseCannotOverwriteTheOriginalSleepState() throws {
        let directory = try TemporaryDirectory()
        defer { directory.remove() }
        let host = PowerHelperSessionHost(script: Self.script, lockPath: directory.lockPath)
        let session = try makeSession(host: host)
        defer { session.cancel() }

        #expect(throws: CocoaError.self) { try host.openSession() }

        try session.stop()
        let subsequent = try makeSession(host: host)
        try subsequent.stop()
    }

    @Test
    func cancelledClientClosesEveryInheritedDescriptorAndReleasesTheLease() throws {
        let directory = try TemporaryDirectory()
        defer { directory.remove() }
        let host = PowerHelperSessionHost(script: Self.script, lockPath: directory.lockPath)
        let session = try makeSession(host: host)
        session.cancel()

        let subsequent = try makeSession(host: host)
        try subsequent.stop()
    }

    @Test
    func aChildThatCannotStartALeaseDoesNotBlockLaterRequests() throws {
        let directory = try TemporaryDirectory()
        defer { directory.remove() }
        let host = PowerHelperSessionHost(script: "exit 1", lockPath: directory.lockPath)
        for _ in 0..<2 {
            let handle = try host.openSession()
            var descriptor = pollfd(fd: handle.fileDescriptor, events: Int16(POLLIN | POLLHUP), revents: 0)
            #expect(poll(&descriptor, 1, 1_000) == 1, "An exited child must close its output without waiting for the five-second session timeout")
            #expect(throws: CocoaError.self) { try makeSession(handle: handle) }
        }
    }

    @Test
    func thePrivilegedChildDoesNotInheritCredentialsFromTheDaemonEnvironment() throws {
        let directory = try TemporaryDirectory()
        defer { directory.remove() }
        let variable = "ZISLA_HELPER_TEST_" + UUID().uuidString.replacingOccurrences(of: "-", with: "_")
        setenv(variable, "fake-test-credential", 1)
        defer { unsetenv(variable) }
        let host = PowerHelperSessionHost(
            script: "test -z \"${\(variable)+x}\" || exit 1\n" + Self.script,
            lockPath: directory.lockPath
        )

        let session = try makeSession(host: host)
        try session.stop()
    }

    @Test
    func separateDaemonInstancesShareOneLockUntilTheLeaseChildExits() throws {
        let directory = try TemporaryDirectory()
        defer { directory.remove() }
        var firstHost: PowerHelperSessionHost? = PowerHelperSessionHost(script: Self.script, lockPath: directory.lockPath)
        let session = try makeSession(host: firstHost!)
        firstHost = nil
        let secondHost = PowerHelperSessionHost(script: Self.script, lockPath: directory.lockPath)

        #expect(throws: CocoaError.self) { try secondHost.openSession() }

        try session.stop()
    }

    @Test(arguments: ["symlink", "hardlink", "permissions", "fifo", "missing-parent"])
    func unsafeLockFilesCannotStartAPrivilegedLease(kind: String) throws {
        let directory = try TemporaryDirectory()
        defer { directory.remove() }
        let path = directory.lockPath
        switch kind {
        case "symlink":
            let target = directory.url.appendingPathComponent("target")
            try Data("untouched".utf8).write(to: target)
            chmod(target.path, 0o600)
            try FileManager.default.createSymbolicLink(atPath: path, withDestinationPath: target.path)
        case "hardlink":
            let target = directory.url.appendingPathComponent("target")
            try Data("untouched".utf8).write(to: target)
            chmod(target.path, 0o600)
            #expect(link(target.path, path) == 0)
        case "permissions":
            FileManager.default.createFile(atPath: path, contents: Data(), attributes: [.posixPermissions: 0o666])
        case "fifo": #expect(mkfifo(path, 0o600) == 0)
        default: break
        }
        let host = PowerHelperSessionHost(
            script: Self.script,
            lockPath: kind == "missing-parent" ? directory.url.appendingPathComponent("missing/lease.lock").path : path
        )

        #expect(throws: CocoaError.self) { try host.openSession() }
        if ["symlink", "hardlink"].contains(kind) {
            #expect(try String(contentsOf: directory.url.appendingPathComponent("target"), encoding: .utf8) == "untouched")
        }
    }

    @Test
    func theDaemonRejectsClientsThatDoNotMatchItsAuthorizedSignature() throws {
        let listener = NSXPCListener.anonymous()
        let requirement = "identifier \"dev.wzz.zisla.invalid-test-client\""
        let directory = try TemporaryDirectory()
        defer { directory.remove() }
        let delegate = PowerHelperListener(
            requirement: requirement, host: PowerHelperSessionHost(script: Self.script, lockPath: directory.lockPath)
        )
        listener.delegate = delegate
        listener.resume()
        defer { listener.invalidate() }

        #expect(throws: (any Error).self) {
            try PrivilegedPowerHelperClient.openSession(
                connection: NSXPCConnection(listenerEndpoint: listener.endpoint), requirement: "true"
            )
        }
        withExtendedLifetime(delegate) {}
    }

    @Test
    func xpcDescriptorTransferSurvivesDisconnectUntilTheClientReleasesTheLease() throws {
        let directory = try TemporaryDirectory()
        defer { directory.remove() }
        let host = PowerHelperSessionHost(script: Self.script, lockPath: directory.lockPath)
        let listener = NSXPCListener.anonymous()
        let delegate = PowerHelperListener(requirement: "true", host: host)
        listener.delegate = delegate
        listener.resume()
        defer { listener.invalidate() }
        for _ in 0..<4 {
            let handle = try PrivilegedPowerHelperClient.openSession(
                connection: NSXPCConnection(listenerEndpoint: listener.endpoint), requirement: "true"
            )
            let session = try makeSession(handle: handle)
            try session.stop()
            let subsequent = try makeSession(host: host)
            try subsequent.stop()
        }
        withExtendedLifetime(delegate) {}
    }

    private struct TemporaryDirectory {
        let url: URL
        var lockPath: String { url.appendingPathComponent("lease.lock").path }

        init() throws {
            url = FileManager.default.temporaryDirectory.appendingPathComponent("zisla-helper-host-" + UUID().uuidString)
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
        }

        func remove() { try? FileManager.default.removeItem(at: url) }
    }

    private func makeSession(host: PowerHelperSessionHost) throws -> PMSetLidClosedDisplaySession {
        try makeSession(handle: host.openSession())
    }

    private func makeSession(handle: FileHandle) throws -> PMSetLidClosedDisplaySession {
        defer { try? handle.close() }
        let descriptor = fcntl(handle.fileDescriptor, F_DUPFD_CLOEXEC, 0)
        guard descriptor >= 0, let pipe = fdopen(descriptor, "r+") else {
            throw CocoaError(.fileReadUnknown)
        }
        return try PMSetLidClosedDisplaySession(pipe: pipe)
    }
}
