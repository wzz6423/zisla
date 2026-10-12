import Darwin
import Foundation
import Testing
@testable import ZislaKit

struct LidClosedDisplayAuthorizationTests {
    @Test
    func oneInstallationIsReusedAfterRepeatedTogglesAndNewAppClients() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let first = fixture.authorization()

        try first.authorize()
        try first.authorize()
        try fixture.authorization().authorize()

        #expect(fixture.installations == 1)
    }

    @Test
    func rejectedAuthorizationDoesNotPersistAndCanBeRetried() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        fixture.rejectInstallation = true
        let authorization = fixture.authorization()

        #expect(throws: CocoaError.self) { try authorization.authorize() }
        #expect(!FileManager.default.fileExists(atPath: fixture.rule.path))
        fixture.rejectInstallation = false
        try authorization.authorize()
        try fixture.authorization().authorize()

        #expect(fixture.installations == 2)
    }

    @Test
    func simultaneousRequestsShareOneInstallation() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let authorization = fixture.authorization()

        DispatchQueue.concurrentPerform(iterations: 16) { _ in
            do { try authorization.authorize() }
            catch { Issue.record(error) }
        }

        #expect(fixture.installations == 1)
    }

    @Test
    func anInstallerThatDoesNotPersistThePermissionCannotReportSuccess() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let authorization = LidClosedDisplayAuthorization(
            userID: 501, ownerID: getuid(), directory: fixture.directory.path, install: { _ in }
        )

        #expect(throws: CocoaError.self) { try authorization.authorize() }
    }

    @Test(arguments: ["symlink", "hardlink", "writable", "directory", "fifo", "owner"])
    func untrustedPolicyFilesAreRejectedWithoutRequestingAnotherPassword(kind: String) throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        switch kind {
        case "directory":
            try FileManager.default.createDirectory(at: fixture.rule, withIntermediateDirectories: false)
            chmod(fixture.rule.path, 0o440)
        case "fifo":
            #expect(mkfifo(fixture.rule.path, 0o440) == 0)
        case "symlink", "hardlink":
            let target = fixture.directory.appendingPathComponent("target")
            try Data().write(to: target)
            chmod(target.path, 0o440)
            if kind == "symlink" {
                try FileManager.default.createSymbolicLink(at: fixture.rule, withDestinationURL: target)
            } else {
                #expect(link(target.path, fixture.rule.path) == 0)
            }
        default:
            try Data().write(to: fixture.rule)
            chmod(fixture.rule.path, kind == "writable" ? 0o666 : 0o440)
        }
        let authorization = fixture.authorization(ownerID: kind == "owner" ? getuid() + 1 : getuid())

        #expect(throws: CocoaError.self) { try authorization.authorize() }
        #expect(fixture.installations == 0)
    }

    @Test
    func rootCannotReceiveAPersistentUserGrant() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }

        #expect(throws: CocoaError.self) { try fixture.authorization(userID: 0).authorize() }
        #expect(fixture.installations == 0)
    }

    @Test(arguments: [Int32(-60006), 0])
    func denialOrMissingInstallerConnectionReportsAnError(status: Int32) {
        #expect(throws: CocoaError.self) {
            try LidClosedDisplayAuthorization.install(userID: 501, launch: { _ in (status, nil) })
        }
    }

    @Test(arguments: ["installed\n", "", "failed\n", "installed", String(repeating: "x", count: 32)])
    func installationRequiresTheExactAcknowledgmentAndClosesItsConnection(response: String) throws {
        var descriptors: [Int32] = [-1, -1]
        guard socketpair(AF_UNIX, SOCK_STREAM, 0, &descriptors) == 0 else { throw CocoaError(.fileReadUnknown) }
        let peer = FileHandle(fileDescriptor: descriptors[1], closeOnDealloc: true)
        defer { try? peer.close() }
        var timeout = timeval(tv_sec: 1, tv_usec: 0)
        setsockopt(descriptors[1], SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout.size(ofValue: timeout)))
        let pipe = fdopen(descriptors[0], "r+")!
        try peer.write(contentsOf: Data(response.utf8))
        shutdown(descriptors[1], SHUT_WR)
        let install = {
            try LidClosedDisplayAuthorization.install(userID: 501, launch: { userID in
                #expect(userID == 501)
                return (0, pipe)
            })
        }

        if response == "installed\n" {
            try install()
        } else {
            #expect(throws: CocoaError.self) { try install() }
        }
        var byte: UInt8 = 0
        let count = recv(descriptors[1], &byte, 1, 0)
        #expect(count == 0 || (count == -1 && errno == ECONNRESET), "The installer connection must close on success and failure")
    }

    @Test
    func anUnresponsiveInstallerCannotLeaveAuthorizationPendingForever() throws {
        var descriptors: [Int32] = [-1, -1]
        guard socketpair(AF_UNIX, SOCK_STREAM, 0, &descriptors) == 0 else { throw CocoaError(.fileReadUnknown) }
        defer { close(descriptors[1]) }
        let pipe = fdopen(descriptors[0], "r+")!
        let started = ContinuousClock.now

        #expect(throws: CocoaError.self) {
            try LidClosedDisplayAuthorization.install(userID: 501, launch: { _ in (0, pipe) })
        }
        #expect(started.duration(to: .now) < .seconds(10))
    }

    private final class Fixture: @unchecked Sendable {
        let directory: URL
        var rule: URL { directory.appendingPathComponent("zisla-keep-awake-501") }
        var rejectInstallation = false
        private(set) var installations = 0

        init() throws {
            directory = FileManager.default.temporaryDirectory.appendingPathComponent("zisla-permission-" + UUID().uuidString)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        }

        func authorization(userID: uid_t = 501, ownerID: uid_t = getuid()) -> LidClosedDisplayAuthorization {
            LidClosedDisplayAuthorization(userID: userID, ownerID: ownerID, directory: directory.path) { [self] _ in
                installations += 1
                if rejectInstallation { throw CocoaError(.userCancelled) }
                try Data("isolated policy fixture".utf8).write(to: rule)
                guard chmod(rule.path, 0o440) == 0 else { throw CocoaError(.fileWriteNoPermission) }
            }
        }

        func remove() { try? FileManager.default.removeItem(at: directory) }
    }
}
