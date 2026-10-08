import Combine
import Darwin
import Foundation
import Security

@_silgen_name("AuthorizationExecuteWithPrivileges")
private func zislaAuthorizationExecuteWithPrivileges(
    _ authorization: AuthorizationRef,
    _ pathToTool: UnsafePointer<CChar>,
    _ options: AuthorizationFlags,
    _ arguments: UnsafePointer<UnsafeMutablePointer<CChar>>,
    _ communicationsPipe: UnsafeMutablePointer<UnsafeMutablePointer<FILE>?>?
) -> OSStatus

final class BatteryPowerModeAuthorizationSession: @unchecked Sendable {
    static let shared = BatteryPowerModeAuthorizationSession()

    private let lock = NSLock()
    private var authorization: AuthorizationRef?

    deinit {
        if let authorization {
            AuthorizationFree(authorization, [])
        }
    }

    func execute(arguments: [String]) -> AIAgentProcessOutput {
        let (status, pipe) = launch(path: "/usr/bin/pmset", arguments: arguments)
        var output = Data()
        if let pipe {
            let fileHandle = FileHandle(fileDescriptor: fileno(pipe), closeOnDealloc: false)
            output = fileHandle.readDataToEndOfFile()
            fclose(pipe)
        }
        return AIAgentProcessOutput(
            status: status,
            standardOutput: output,
            standardError: "",
            didTimeout: false
        )
    }

    func openLidClosedDisplaySession() -> (OSStatus, UnsafeMutablePointer<FILE>?) {
        launch(path: "/bin/sh", arguments: ["-p", "-c", PMSetLidClosedDisplaySession.script])
    }

    private func launch(path: String, arguments: [String]) -> (OSStatus, UnsafeMutablePointer<FILE>?) {
        lock.lock()
        defer { lock.unlock() }

        guard let authorization = authorize() else {
            return (errAuthorizationDenied, nil)
        }

        let cArguments = arguments.map { strdup($0) }
        defer {
            for argument in cArguments {
                free(argument)
            }
        }

        var argv = cArguments.map { $0 }
        argv.append(nil)
        var pipe: UnsafeMutablePointer<FILE>?
        let status = argv.withUnsafeBufferPointer { buffer in
            buffer.baseAddress!.withMemoryRebound(
                to: UnsafeMutablePointer<CChar>.self,
                capacity: buffer.count
            ) { pointer in
                zislaAuthorizationExecuteWithPrivileges(
                    authorization,
                    path,
                    [],
                    pointer,
                    &pipe
                )
            }
        }

        return (status, pipe)
    }

    private func authorize() -> AuthorizationRef? {
        if let authorization {
            return authorization
        }

        var created: AuthorizationRef?
        guard AuthorizationCreate(nil, nil, [], &created) == errAuthorizationSuccess,
              let created
        else {
            return nil
        }

        let result = kAuthorizationRightExecute.withCString { name in
            var item = AuthorizationItem(name: name, valueLength: 0, value: nil, flags: 0)
            return withUnsafeMutablePointer(to: &item) { itemPointer in
                var rights = AuthorizationRights(count: 1, items: itemPointer)
                return AuthorizationCopyRights(
                    created,
                    &rights,
                    nil,
                    [.interactionAllowed, .extendRights],
                    nil
                )
            }
        }
        guard result == errAuthorizationSuccess else {
            AuthorizationFree(created, [])
            return nil
        }
        authorization = created
        return created
    }
}

public enum BatteryPowerMode: Int, CaseIterable, Sendable {
    case automatic = 0
    case lowPower = 1
    case highPower = 2
}

public enum BatteryPowerSource: String, Sendable {
    case battery = "Battery Power"
    case powerAdapter = "AC Power"

    fileprivate var argument: String {
        switch self {
        case .battery: "-b"
        case .powerAdapter: "-c"
        }
    }
}

public enum BatteryPowerModeError: Error, Equatable, Sendable {
    case stateUnavailable
    case unsupportedMode
    case authorizationCancelled
    case authorizationDenied
    case changeFailed
    case verificationFailed
    case timedOut
}

@MainActor
public final class BatteryPowerModeController: ObservableObject {
    @Published public private(set) var currentMode: BatteryPowerMode?
    @Published public private(set) var supportedModes: [BatteryPowerMode] = []
    @Published public private(set) var powerSource: BatteryPowerSource?
    @Published public private(set) var isChanging = false
    @Published public private(set) var error: BatteryPowerModeError?

    typealias CommandRunner = @MainActor (URL, [String], TimeInterval) async throws -> AIAgentProcessOutput

    private let runCommand: CommandRunner
    private let runPrivilegedCommand: CommandRunner
    private var refreshRevision = 0

    public convenience init() {
        self.init(
            runCommand: { executableURL, arguments, timeout in
                try await AIAgentProcessRunner.run(
                    executableURL: executableURL,
                    arguments: arguments,
                    timeout: timeout,
                    maximumOutputBytes: 16 * 1024,
                    maximumErrorBytes: 4 * 1024
                )
            },
            runPrivilegedCommand: { _, arguments, _ in
                await Task.detached(priority: .userInitiated) {
                    BatteryPowerModeAuthorizationSession.shared.execute(arguments: arguments)
                }.value
            }
        )
    }

    init(runCommand: @escaping CommandRunner) {
        self.runCommand = runCommand
        self.runPrivilegedCommand = runCommand
    }

    private init(
        runCommand: @escaping CommandRunner,
        runPrivilegedCommand: @escaping CommandRunner
    ) {
        self.runCommand = runCommand
        self.runPrivilegedCommand = runPrivilegedCommand
    }

    public func refresh() async {
        guard !isChanging else { return }
        refreshRevision += 1
        let revision = refreshRevision
        let result: Result<Snapshot, Error>
        do {
            result = .success(try await readSnapshot())
        } catch {
            result = .failure(error)
        }
        guard revision == refreshRevision else { return }
        switch result {
        case .success(let snapshot):
            apply(snapshot)
            error = nil
        case .failure(let failure):
            invalidateState()
            error = Self.presentedError(failure, fallback: .stateUnavailable)
        }
    }

    /// macOS saves each power source separately; authorization must not change the other profile.
    @discardableResult
    public func setMode(_ mode: BatteryPowerMode) async -> Bool {
        guard !isChanging else { return false }
        isChanging = true
        refreshRevision += 1
        error = nil
        defer { isChanging = false }

        let before: Snapshot
        do {
            before = try await readSnapshot()
            apply(before)
        } catch {
            invalidateState()
            self.error = Self.presentedError(error, fallback: .stateUnavailable)
            return false
        }
        guard before.supportedModes.contains(mode) else {
            error = .unsupportedMode
            return false
        }
        guard before.modes[before.powerSource] != mode else { return true }

        let setting = before.supportedModes.contains(.highPower) ? "powermode" : "lowpowermode"
        var changeError: BatteryPowerModeError?
        do {
            let output = try await runPrivilegedCommand(
                URL(fileURLWithPath: "/usr/bin/pmset"),
                [before.powerSource.argument, setting, String(mode.rawValue)],
                120
            )
            try Self.checkChangeResult(output)
        } catch {
            changeError = Self.presentedError(error, fallback: .changeFailed)
        }

        // Even a failed or interrupted command may have reached powerd before returning an error.
        let after: Snapshot
        do {
            after = try await readSnapshot()
            apply(after)
        } catch {
            invalidateState()
            self.error = changeError ?? Self.presentedError(error, fallback: .verificationFailed)
            return false
        }
        if let changeError {
            error = changeError
            return false
        }
        guard after.modes[before.powerSource] == mode else {
            error = .verificationFailed
            return false
        }
        return true
    }

    public func clearError() {
        error = nil
    }

    private func apply(_ snapshot: Snapshot) {
        powerSource = snapshot.powerSource
        currentMode = snapshot.modes[snapshot.powerSource]
        supportedModes = snapshot.supportedModes
    }

    private func invalidateState() {
        currentMode = nil
        supportedModes = []
        powerSource = nil
    }

    private func readSnapshot() async throws -> Snapshot {
        let capabilities = try await readPMSet("cap")
        let preferences = try await readPMSet("custom")
        return try Snapshot(capabilities: capabilities, preferences: preferences)
    }

    private func readPMSet(_ option: String) async throws -> String {
        let output = try await runCommand(
            URL(fileURLWithPath: "/usr/bin/pmset"), ["-g", option], 5
        )
        guard !output.didTimeout else { throw BatteryPowerModeError.timedOut }
        guard output.status == 0,
              let text = String(data: output.standardOutput, encoding: .utf8)
        else { throw BatteryPowerModeError.stateUnavailable }
        return text
    }

    private static func checkChangeResult(_ output: AIAgentProcessOutput) throws {
        guard !output.didTimeout else { throw BatteryPowerModeError.timedOut }
        let code: Int
        if output.status != 0 {
            code = Int(output.status)
        } else if let text = String(data: output.standardOutput, encoding: .utf8),
                  !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  let parsed = Int(text.trimmingCharacters(in: .whitespacesAndNewlines)) {
            code = parsed
        } else if output.standardOutput.isEmpty {
            return
        } else {
            throw BatteryPowerModeError.changeFailed
        }
        switch code {
        case 0: return
        case -128, -60006: throw BatteryPowerModeError.authorizationCancelled
        case -60005, -60007: throw BatteryPowerModeError.authorizationDenied
        default: throw BatteryPowerModeError.changeFailed
        }
    }

    private static func presentedError(
        _ error: any Error,
        fallback: BatteryPowerModeError
    ) -> BatteryPowerModeError {
        if error is CancellationError { return .authorizationCancelled }
        return (error as? BatteryPowerModeError) ?? fallback
    }

    private struct Snapshot {
        let powerSource: BatteryPowerSource
        let modes: [BatteryPowerSource: BatteryPowerMode]
        let supportedModes: [BatteryPowerMode]

        init(capabilities: String, preferences: String) throws {
            let lines = capabilities.split(whereSeparator: \.isNewline)
                .map { $0.trimmingCharacters(in: .whitespaces) }
            let prefix = "Capabilities for "
            guard let header = lines.first,
                  header.hasPrefix(prefix), header.hasSuffix(":"),
                  let source = BatteryPowerSource(rawValue: String(header.dropFirst(prefix.count).dropLast())),
                  !lines.dropFirst().contains(where: { $0.hasPrefix(prefix) })
            else { throw BatteryPowerModeError.stateUnavailable }
            powerSource = source

            var parsedModes: [BatteryPowerSource: BatteryPowerMode] = [:]
            var section: BatteryPowerSource?
            for rawLine in preferences.split(whereSeparator: \.isNewline) {
                let line = rawLine.trimmingCharacters(in: .whitespaces)
                if line.hasSuffix(":") {
                    section = BatteryPowerSource(rawValue: String(line.dropLast()))
                    continue
                }
                guard let section else { continue }
                let fields = line.split(whereSeparator: \.isWhitespace)
                // HighPowerMode is a capability marker, not the currently selected mode.
                guard let key = fields.first, key == "powermode" || key == "lowpowermode" else { continue }
                guard fields.count == 2,
                      let rawValue = Int(fields[1]),
                      let mode = BatteryPowerMode(rawValue: rawValue),
                      fields[1] == String(rawValue),
                      key != "lowpowermode" || mode != .highPower,
                      parsedModes[section] == nil
                else { throw BatteryPowerModeError.stateUnavailable }
                parsedModes[section] = mode
            }
            modes = parsedModes

            let features = Set(lines.dropFirst())
            var supported: [BatteryPowerMode] = []
            if features.contains("lowpowermode") || features.contains("highpowermode") {
                supported.append(.automatic)
                if features.contains("lowpowermode") { supported.append(.lowPower) }
                if features.contains("highpowermode") { supported.append(.highPower) }
                guard let current = modes[source], supported.contains(current)
                else { throw BatteryPowerModeError.stateUnavailable }
            }
            supportedModes = supported
        }
    }
}
