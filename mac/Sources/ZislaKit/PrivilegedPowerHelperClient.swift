import Darwin
import Foundation
import Security
import ServiceManagement
import ZislaPowerHelperSupport

final class PrivilegedPowerHelperClient: @unchecked Sendable {
    struct Configuration: Sendable {
        let label: String
        let requirement: String

        init(bundleIdentifier: String?, privilegedExecutables: [String: String]?) throws {
            guard let bundleIdentifier,
                  ["dev.wzz.zisla", "dev.wzz.zisla.debug"].contains(bundleIdentifier),
                  let requirement = privilegedExecutables?[bundleIdentifier + ".power-helper"]
            else { throw CocoaError(.executableNotLoadable) }
            var parsed: SecRequirement?
            guard SecRequirementCreateWithString(requirement as CFString, [], &parsed) == errSecSuccess else {
                throw CocoaError(.executableNotLoadable)
            }
            label = bundleIdentifier + ".power-helper"
            self.requirement = requirement
        }
    }

    static let shared = PrivilegedPowerHelperClient()

    private let lock = NSLock()
    private let configuration: @Sendable () throws -> Configuration
    private let isInstalled: @Sendable (String) -> Bool
    private let install: @Sendable (String) throws -> Void
    private let connect: @Sendable (Configuration) throws -> FileHandle

    init(
        configuration: @escaping @Sendable () throws -> Configuration = {
            try Configuration(
                bundleIdentifier: Bundle.main.bundleIdentifier,
                privilegedExecutables: Bundle.main.object(forInfoDictionaryKey: "SMPrivilegedExecutables") as? [String: String]
            )
        },
        isInstalled: @escaping @Sendable (String) -> Bool = {
            FileManager.default.fileExists(atPath: "/Library/PrivilegedHelperTools/" + $0)
        },
        install: @escaping @Sendable (String) throws -> Void = PrivilegedPowerHelperClient.install,
        connect: @escaping @Sendable (Configuration) throws -> FileHandle = PrivilegedPowerHelperClient.connect
    ) {
        self.configuration = configuration
        self.isInstalled = isInstalled
        self.install = install
        self.connect = connect
    }

    func openSession() throws -> UnsafeMutablePointer<FILE> {
        try lock.withLock {
            let configuration = try configuration()
            if !isInstalled(configuration.label) {
                try install(configuration.label)
            }
            let handle = try connect(configuration)
            defer { try? handle.close() }
            let descriptor = fcntl(handle.fileDescriptor, F_DUPFD_CLOEXEC, 0)
            guard descriptor >= 0 else { throw CocoaError(.fileReadUnknown) }
            guard let pipe = fdopen(descriptor, "r+") else {
                close(descriptor)
                throw CocoaError(.fileReadUnknown)
            }
            return pipe
        }
    }

    private static func install(label: String) throws {
        var authorization: AuthorizationRef?
        let status = kSMRightBlessPrivilegedHelper.withCString { name in
            var item = AuthorizationItem(name: name, valueLength: 0, value: nil, flags: 0)
            return withUnsafeMutablePointer(to: &item) { pointer in
                var rights = AuthorizationRights(count: 1, items: pointer)
                return AuthorizationCreate(&rights, nil, [.interactionAllowed, .extendRights, .preAuthorize], &authorization)
            }
        }
        guard status == errAuthorizationSuccess, let authorization else {
            throw CocoaError(.userCancelled)
        }
        defer { AuthorizationFree(authorization, []) }
        var error: Unmanaged<CFError>?
        guard SMJobBless(kSMDomainSystemLaunchd, label as CFString, authorization, &error) else {
            if let error { throw error.takeRetainedValue() as Error }
            throw CocoaError(.executableNotLoadable)
        }
    }

    private static func connect(configuration: Configuration) throws -> FileHandle {
        let connection = NSXPCConnection(machServiceName: configuration.label, options: .privileged)
        return try openSession(connection: connection, requirement: configuration.requirement)
    }

    static func openSession(connection: NSXPCConnection, requirement: String, timeout: TimeInterval = 5) throws -> FileHandle {
        connection.setCodeSigningRequirement(requirement)
        connection.remoteObjectInterface = NSXPCInterface(with: PowerHelperProtocol.self)
        let reply = SessionReply()
        connection.invalidationHandler = { reply.finish(.failure(CocoaError(.executableNotLoadable))) }
        connection.interruptionHandler = { reply.finish(.failure(CocoaError(.executableNotLoadable))) }
        connection.resume()
        defer { connection.invalidate() }
        let proxy = connection.remoteObjectProxyWithErrorHandler { error in
            reply.finish(.failure(error))
        } as! PowerHelperProtocol
        proxy.openSession { handle, error in
            if let error {
                try? handle?.close()
                reply.finish(.failure(error))
            } else if let handle {
                reply.finish(.success(handle))
            } else {
                reply.finish(.failure(CocoaError(.fileReadUnknown)))
            }
        }
        return try reply.wait(timeout: timeout)
    }

    final class SessionReply: @unchecked Sendable {
        private let lock = NSLock()
        private let received = DispatchSemaphore(value: 0)
        private var result: Result<FileHandle, Error>?

        func finish(_ result: Result<FileHandle, Error>) {
            lock.withLock {
                guard self.result == nil else {
                    if case .success(let handle) = result { try? handle.close() }
                    return
                }
                self.result = result
                received.signal()
            }
        }

        func wait(timeout: TimeInterval) throws -> FileHandle {
            if received.wait(timeout: .now() + timeout) == .timedOut {
                finish(.failure(CocoaError(.fileReadUnknown)))
            }
            return try lock.withLock { try result!.get() }
        }
    }
}
