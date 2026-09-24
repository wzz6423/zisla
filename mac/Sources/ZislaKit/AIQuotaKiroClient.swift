// Adapted from upstream Kiro ACP protocol; modified for Zisla cancellation and output limits.
// See Resources/ThirdPartyLicenses/AIQuota-LICENSE.txt.
import Foundation
import Darwin

actor AIQuotaKiroClient {
    enum Failure: Error, Equatable {
        case executableNotFound
        case startFailed
        case timedOut
        case closed
        case server(String)
    }

    private var process: Process?
    private var stdin: FileHandle?
    private var reader: FileHandle?
    private var errorReader: FileHandle?
    private var nextID = 1
    private struct PendingRequest {
        let continuation: CheckedContinuation<Data, Error>
        let timeout: Task<Void, Never>
    }
    private var pending: [Int: PendingRequest] = [:]
    private var buffer = Data()
    private let executable: URL?
    private let requestTimeout: Duration
    private let environment: [String: String]?

    init(executable: URL? = nil, requestTimeout: Duration = .seconds(20), environment: [String: String]? = nil) {
        self.executable = executable
        self.requestTimeout = requestTimeout
        self.environment = environment
    }

    func usage() async throws -> Data {
        try await withTaskCancellationHandler {
            try Task.checkCancellation()
            try start()
            defer { shutDown() }

            _ = try await send(
                method: "initialize",
                params: [
                    "protocolVersion": 1,
                    "clientCapabilities": [:],
                    "clientInfo": ["name": "Zisla", "version": "0.1"]
                ]
            )
            return try await send(method: "_kiro/account/getUsage")
        } onCancel: { Task { await self.shutDown() } }
    }

    func shutDown() {
        reader?.readabilityHandler = nil
        errorReader?.readabilityHandler = nil
        reader = nil
        errorReader = nil
        if let owned = process, owned.isRunning {
            owned.terminate()
            Task.detached {
                try? await Task.sleep(for: .milliseconds(500))
                if owned.isRunning {
                    Darwin.kill(owned.processIdentifier, SIGKILL)
                }
                owned.waitUntilExit()
            }
        }
        process = nil
        try? stdin?.close()
        stdin = nil
        buffer.removeAll(keepingCapacity: false)
        failAllPending(with: .closed)
    }

    private func start() throws {
        guard let executable = executable ?? Self.locateKiro() else { throw Failure.executableNotFound }

        let process = Process()
        process.executableURL = executable
        process.arguments = ["acp", "--agent-engine", "v3", "--auth-method", "cli"]
        process.environment = environment ?? ProcessInfo.processInfo.environment

        let input = Pipe(), output = Pipe(), errors = Pipe()
        process.standardInput = input
        process.standardOutput = output
        process.standardError = errors

        let reader = output.fileHandleForReading
        let errorReader = errors.fileHandleForReading
        startReading(reader)
        drain(errorReader)

        do {
            try process.run()
        } catch {
            shutDown()
            throw Failure.startFailed
        }

        self.process = process
        stdin = input.fileHandleForWriting
    }

    private static func locateKiro() -> URL? {
        let home = NSHomeDirectory()
        var candidates: [String] = []
        if let path = ProcessInfo.processInfo.environment["PATH"] {
            candidates += path.split(separator: ":").map { "\($0)/kiro-cli" }
        }
        candidates += [
            "/opt/homebrew/bin/kiro-cli",
            "/usr/local/bin/kiro-cli",
            "\(home)/bin/kiro-cli",
            "\(home)/.local/bin/kiro-cli",
            "/Applications/Kiro CLI.app/Contents/MacOS/kiro-cli",
            "/Applications/Kiro.app/Contents/Resources/app/bin/kiro-cli"
        ]
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0) }
            .map { URL(fileURLWithPath: $0) }
    }

    private func send(method: String, params: [String: Any] = [:]) async throws -> Data {
        let id = nextID
        nextID += 1
        let message: [String: Any] = [
            "jsonrpc": "2.0", "id": id, "method": method, "params": params
        ]
        let data: Data
        do {
            data = try JSONSerialization.data(withJSONObject: message)
        } catch {
            throw Failure.startFailed
        }

        return try await withCheckedThrowingContinuation { continuation in
            guard let stdin else {
                continuation.resume(throwing: Failure.closed)
                return
            }
            let timeout = Task { [self] in
                do { try await Task.sleep(for: requestTimeout) }
                catch { return }
                finish(id, with: .failure(Failure.timedOut))
            }
            pending[id] = PendingRequest(continuation: continuation, timeout: timeout)
            do {
                try stdin.write(contentsOf: data)
                try stdin.write(contentsOf: Data("\n".utf8))
            } catch {
                shutDown()
            }
        }
    }

    private func startReading(_ handle: FileHandle) {
        reader = handle
        handle.readabilityHandler = { [weak self] handle in
            let chunk = handle.availableData
            guard !chunk.isEmpty else {
                handle.readabilityHandler = nil
                Task { await self?.readerClosed(handle) }
                return
            }
            Task { await self?.consume(chunk, from: handle) }
        }
    }

    private func drain(_ handle: FileHandle) {
        errorReader = handle
        handle.readabilityHandler = { [weak self] handle in
            let chunk = handle.availableData
            guard !chunk.isEmpty else {
                handle.readabilityHandler = nil
                Task { await self?.errorReaderClosed(handle) }
                return
            }
        }
    }

    private func readerClosed(_ handle: FileHandle) {
        guard handle === reader else { return }
        shutDown()
    }

    private func errorReaderClosed(_ handle: FileHandle) {
        guard handle === errorReader else { return }
        errorReader = nil
    }

    private func consume(_ chunk: Data, from source: FileHandle) {
        guard source === reader else { return }
        guard buffer.count + chunk.count <= 2 * 1_024 * 1_024 else { shutDown(); return }
        buffer.append(chunk)
        while let newline = buffer.firstIndex(of: UInt8(ascii: "\n")) {
            let line = buffer[buffer.startIndex..<newline]
            buffer = buffer[buffer.index(after: newline)...]
            guard !line.isEmpty,
                  let message = try? JSONSerialization.jsonObject(with: Data(line)) as? [String: Any]
            else { continue }
            handle(message)
        }
    }

    private func handle(_ message: [String: Any]) {
        guard let id = message["id"] as? Int, pending[id] != nil else { return }

        if let error = message["error"] as? [String: Any] {
            finish(id, with: .failure(Failure.server(error["message"] as? String ?? "unknown")))
            return
        }
        let result = message["result"] as? [String: Any] ?? [:]
        let data = (try? JSONSerialization.data(withJSONObject: result)) ?? Data("{}".utf8)
        finish(id, with: .success(data))
    }

    private func finish(_ id: Int, with result: Result<Data, Error>) {
        guard let request = pending.removeValue(forKey: id) else { return }
        request.timeout.cancel()
        request.continuation.resume(with: result)
    }

    private func failAllPending(with failure: Failure) {
        for id in Array(pending.keys) { finish(id, with: .failure(failure)) }
    }
}
