import Darwin
import Foundation
import Testing
import ZislaPowerHelperSupport
@testable import ZislaKit

struct PrivilegedPowerHelperClientTests {
    private static let label = "dev.wzz.zisla.power-helper"

    @Test
    func oneInstallationSurvivesRepeatedSessionsAndNewClients() throws {
        let system = InstalledHelper()
        let firstClient = try makeClient(system: system)
        for client in [firstClient, firstClient, try makeClient(system: system)] {
            let pipe = try client.openSession()
            #expect(fcntl(fileno(pipe), F_GETFD) & FD_CLOEXEC != 0)
            let session = try PMSetLidClosedDisplaySession(pipe: pipe)
            try session.stop()
            #expect(try system.takeRequest() == "stop\n")
            #expect(try system.takeRequest() == "", "A stopped session must not leave an inherited or transferred lease open")
        }

        #expect(system.installations == 1, "Turning keep-awake on again or recreating the app client must not ask for another installation authorization")
        #expect(system.connections == 3)
    }

    @Test
    func deniedInstallationDoesNotConnectOrRememberApprovalAndCanRetry() throws {
        let system = InstalledHelper()
        system.denyInstallation = true
        let client = try makeClient(system: system)

        #expect(throws: CocoaError.self) { try client.openSession() }
        #expect(!system.installed)
        #expect(system.connections == 0)
        system.denyInstallation = false

        let session = try PMSetLidClosedDisplaySession(pipe: client.openSession())
        session.cancel()
        #expect(system.installed)
        #expect(system.installations == 2)
    }

    @Test
    func installedButUnavailableHelperDoesNotFallBackToAnotherAuthorization() throws {
        let system = InstalledHelper()
        system.installed = true
        system.failConnection = true
        let client = try makeClient(system: system)

        #expect(throws: CocoaError.self) { try client.openSession() }
        #expect(system.installations == 0)
    }

    @Test(arguments: [nil, "dev.wzz.other", "../../tmp/helper"])
    func missingOrUnexpectedApplicationIdentityCannotRequestInstallation(identifier: String?) {
        #expect(throws: CocoaError.self) {
            try PrivilegedPowerHelperClient.Configuration(bundleIdentifier: identifier, privilegedExecutables: nil)
        }
    }

    @Test(arguments: [nil, "not a code signing requirement("])
    func missingOrMalformedSigningMetadataCannotRequestInstallation(requirement: String?) {
        #expect(throws: CocoaError.self) {
            try PrivilegedPowerHelperClient.Configuration(
                bundleIdentifier: "dev.wzz.zisla",
                privilegedExecutables: requirement.map { [Self.label: $0] }
            )
        }
    }

    @Test
    func invalidDescriptorIsRejectedAndTransferredHandleIsClosed() throws {
        let closed = FileHandle(fileDescriptor: -1, closeOnDealloc: true)
        let client = PrivilegedPowerHelperClient(
            configuration: { try Self.configuration() },
            isInstalled: { _ in true },
            install: { _ in Issue.record("Invalid transport must never request authorization") },
            connect: { _ in closed }
        )

        #expect(throws: CocoaError.self) { try client.openSession() }
    }

    @Test(arguments: [false, true])
    func repliesAfterFailureOrTimeoutCloseTheTransferredLease(timedOut: Bool) throws {
        let response = PrivilegedPowerHelperClient.SessionReply()
        if timedOut {
            #expect(throws: CocoaError.self) { try response.wait(timeout: 0) }
        } else {
            response.finish(.failure(CocoaError(.executableNotLoadable)))
        }
        let (handle, peer) = try socketHandles()
        defer { try? peer.close() }

        response.finish(.success(handle))

        #expect(try peer.read(upToCount: 1) == nil, "A late XPC reply must not keep the power override alive")
    }

    @Test
    func disconnectionAfterAReplyDoesNotDiscardTheTransferredSocket() throws {
        let response = PrivilegedPowerHelperClient.SessionReply()
        let (handle, peer) = try socketHandles()
        defer { try? peer.close() }
        response.finish(.success(handle))
        response.finish(.failure(CocoaError(.executableNotLoadable)))

        let received = try response.wait(timeout: 0)
        defer { try? received.close() }
        try peer.write(contentsOf: Data("ready\n".utf8))
        #expect(try received.read(upToCount: 6) == Data("ready\n".utf8))
    }

    @Test
    func xpcTransfersASocketAndRejectsAnUnexpectedHelperSignature() throws {
        let fixture = XPCFixture(mode: .socket)
        defer { fixture.listener.invalidate() }
        let handle = try PrivilegedPowerHelperClient.openSession(
            connection: NSXPCConnection(listenerEndpoint: fixture.listener.endpoint), requirement: "true"
        )
        defer { try? handle.close() }
        #expect(try handle.read(upToCount: 6) == Data("ready\n".utf8))

        #expect(throws: (any Error).self) {
            try PrivilegedPowerHelperClient.openSession(
                connection: NSXPCConnection(listenerEndpoint: fixture.listener.endpoint),
                requirement: "identifier \"dev.wzz.zisla.invalid-test-helper\""
            )
        }
    }

    @Test(arguments: [ReplyMode.failure, .empty, .unresponsive])
    func invalidXPCRepliesAndTimeoutsFailWithoutAUsableLease(mode: ReplyMode) {
        let fixture = XPCFixture(mode: mode)
        defer { fixture.listener.invalidate() }
        #expect(throws: (any Error).self) {
            try PrivilegedPowerHelperClient.openSession(
                connection: NSXPCConnection(listenerEndpoint: fixture.listener.endpoint), requirement: "true", timeout: 0.2
            )
        }
    }

    private func makeClient(system: InstalledHelper) throws -> PrivilegedPowerHelperClient {
        PrivilegedPowerHelperClient(
            configuration: { try Self.configuration() },
            isInstalled: { _ in system.installed },
            install: { _ in try system.install() },
            connect: { _ in try system.connect() }
        )
    }

    private static func configuration() throws -> PrivilegedPowerHelperClient.Configuration {
        try PrivilegedPowerHelperClient.Configuration(
            bundleIdentifier: "dev.wzz.zisla",
            privilegedExecutables: [label: "identifier \"\(label)\""]
        )
    }

    private final class InstalledHelper: @unchecked Sendable {
        var installed = false
        var denyInstallation = false
        var failConnection = false
        var installations = 0
        var connections = 0
        private var peers: [FileHandle] = []
        private var transferredHandles: [FileHandle] = []

        func install() throws {
            installations += 1
            if denyInstallation { throw CocoaError(.userCancelled) }
            installed = true
        }

        func connect() throws -> FileHandle {
            connections += 1
            if failConnection { throw CocoaError(.executableNotLoadable) }
            let (handle, peer) = try socketHandles()
            peers.append(peer)
            transferredHandles.append(handle)
            try peer.write(contentsOf: Data("ready\nrestored\n".utf8))
            return handle
        }

        func takeRequest() throws -> String {
            let peer = peers.last!
            let data = try peer.read(upToCount: 64) ?? Data()
            return String(decoding: data, as: UTF8.self)
        }
    }

    enum ReplyMode: Sendable {
        case socket, failure, empty, unresponsive
    }

    private final class XPCFixture: NSObject, NSXPCListenerDelegate, PowerHelperProtocol, @unchecked Sendable {
        let listener = NSXPCListener.anonymous()
        private let mode: ReplyMode
        private var handles: [FileHandle] = []

        init(mode: ReplyMode) {
            self.mode = mode
            super.init()
            listener.delegate = self
            listener.resume()
        }

        func listener(_ listener: NSXPCListener, shouldAcceptNewConnection connection: NSXPCConnection) -> Bool {
            connection.exportedInterface = NSXPCInterface(with: PowerHelperProtocol.self)
            connection.exportedObject = self
            connection.resume()
            return true
        }

        func openSession(reply: @escaping (FileHandle?, NSError?) -> Void) {
            switch mode {
            case .socket:
                do {
                    let (handle, peer) = try socketHandles()
                    handles += [handle, peer]
                    try peer.write(contentsOf: Data("ready\n".utf8))
                    reply(handle, nil)
                } catch { reply(nil, error as NSError) }
            case .failure: reply(nil, CocoaError(.fileReadUnknown) as NSError)
            case .empty: reply(nil, nil)
            case .unresponsive: break
            }
        }
    }
}

private func socketHandles() throws -> (FileHandle, FileHandle) {
    var descriptors: [Int32] = [-1, -1]
    guard socketpair(AF_UNIX, SOCK_STREAM, 0, &descriptors) == 0 else {
        throw CocoaError(.fileReadUnknown)
    }
    var timeout = timeval(tv_sec: 1, tv_usec: 0)
    setsockopt(descriptors[1], SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout.size(ofValue: timeout)))
    return (
        FileHandle(fileDescriptor: descriptors[0], closeOnDealloc: true),
        FileHandle(fileDescriptor: descriptors[1], closeOnDealloc: true)
    )
}
