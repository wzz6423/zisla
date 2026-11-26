import Darwin
import Foundation
import ZislaCore

// Native read-only adaptation of token-monitor's Antigravity local RPC probe (MIT).
struct AIAccountAntigravitySnapshot: Sendable, Equatable {
    let windows: [AIAccountQuotaWindow]
    let accountID: String?
    let accountName: String?
    let sourceDetail: AIAccountAntigravityProbe.ProcessKind
}

struct AIAccountAntigravityProbe: Sendable {
    enum ProcessKind: String, Sendable, CaseIterable {
        case app, cli, ide

        var rank: Int {
            switch self {
            case .app: 0
            case .cli: 1
            case .ide: 2
            }
        }
    }

    struct DesktopHubDescriptor: Sendable, Equatable {
        let pid: Int
        let httpPort: Int
        let csrfToken: String
        let modifiedAt: TimeInterval
    }

    struct ProcessEntry: Sendable, Equatable {
        let pid: Int
        let kind: ProcessKind
        let csrfToken: String
        let desktopRPCPort: Int?
        let extensionPort: Int?
        let extensionCsrfToken: String?
        let hubPort: Int?
    }

    struct EndpointCandidate: Sendable, Equatable {
        let scheme: String
        let port: Int
        let csrfToken: String
        let desktopPID: Int?
    }

    struct RPCResponse: Sendable, Equatable {
        let statusCode: Int
        let body: Data
    }

    static let servicePath = "/exa.language_server_pb.LanguageServerService/"
    private static let maximumDescriptorBytes = 4_096
    private static let maximumResponseBytes = 1_024 * 1_024
    private static let maximumCommandOutputBytes = 512 * 1_024

    let home: URL
    var runCommand: @Sendable (String, [String], TimeInterval) async throws -> (status: Int32, stdout: String, stderr: String)
    var readDesktopHubs: @Sendable (URL) -> [Int: DesktopHubDescriptor]
    var rpcCall: @Sendable (EndpointCandidate, String, Data, TimeInterval) async throws -> RPCResponse
    var sleep: @Sendable (TimeInterval) async throws -> Void

    init(
        home: URL = FileManager.default.homeDirectoryForCurrentUser,
        runCommand: (@Sendable (String, [String], TimeInterval) async throws -> (status: Int32, stdout: String, stderr: String))? = nil,
        readDesktopHubs: (@Sendable (URL) -> [Int: DesktopHubDescriptor])? = nil,
        rpcCall: (@Sendable (EndpointCandidate, String, Data, TimeInterval) async throws -> RPCResponse)? = nil,
        sleep: @escaping @Sendable (TimeInterval) async throws -> Void = { seconds in
            try await Task.sleep(nanoseconds: UInt64(max(0, seconds) * 1_000_000_000))
        }
    ) {
        self.home = home
        let commandRunner = runCommand ?? Self.defaultRunCommand
        self.runCommand = commandRunner
        self.readDesktopHubs = readDesktopHubs ?? { Self.defaultReadDesktopHubs(home: $0) }
        self.sleep = sleep
        self.rpcCall = rpcCall ?? { candidate, method, payload, timeout in
            try await Self.defaultRPCCall(
                candidate: candidate,
                method: method,
                payload: payload,
                timeout: timeout,
                verifySocketOwner: { port, pid, localPort in
                    try await Self.verifyDesktopSocketOwned(
                        port: port,
                        pid: pid,
                        localPort: localPort,
                        runCommand: commandRunner,
                        sleep: sleep
                    )
                }
            )
        }
    }

    /// Probes running Antigravity or Gemini desktop/CLI/IDE language servers on loopback only.
    /// Returns nil when no local process is running; throws classified errors when a running server fails.
    func probe() async throws -> AIAccountAntigravitySnapshot? {
        try Task.checkCancellation()
        let ps = try await runCommand("/bin/ps", ["-ax", "-o", "pid=,command="], 5)
        guard ps.status == 0 else { throw AIAccountBalanceError.noQuota }
        let desktopHubs = ps.stdout.contains("--read_host_bridge_token_from_stdin")
            ? readDesktopHubs(home)
            : [:]
        let processes = try Self.parseProcessList(ps.stdout, desktopHubs: desktopHubs)
        guard !processes.isEmpty else { return nil }

        var lastError: Error = AIAccountBalanceError.noQuota
        for kind in ProcessKind.allCases {
            let group = processes.filter { $0.kind == kind }
            for info in group {
                try Task.checkCancellation()
                let candidates = await discoverCandidates(for: info)
                guard !candidates.isEmpty else {
                    lastError = Self.preferError(lastError, AIAccountBalanceError.noQuota)
                    continue
                }
                let ordered = await resolveWorkingEndpoint(candidates)
                for candidate in ordered {
                    try Task.checkCancellation()
                    do {
                        let summaryBody = try JSONSerialization.data(withJSONObject: ["forceRefresh": true])
                        let summary = try await invoke(candidate, method: "RetrieveUserQuotaSummary", payload: summaryBody, timeout: 6)
                        let windows = try AIAccountBalanceParser.antigravityQuotaSummary(summary)
                        guard !windows.isEmpty, windows.allSatisfy(\.isValid) else {
                            lastError = Self.preferError(lastError, AIAccountBalanceError.noQuota)
                            continue
                        }
                        let identity = await fetchIdentity(candidate)
                        let email = identity?.email
                        return AIAccountAntigravitySnapshot(
                            windows: windows,
                            accountID: email,
                            accountName: email ?? identity?.plan,
                            sourceDetail: kind
                        )
                    } catch is CancellationError {
                        throw CancellationError()
                    } catch {
                        let classified: Error
                        if case AIAccountBalanceError.credentialsExpired = error, candidate.csrfToken != info.csrfToken {
                            classified = AIAccountBalanceError.noQuota
                        } else {
                            classified = error
                        }
                        lastError = Self.preferError(lastError, classified)
                    }
                }
            }
        }
        throw lastError
    }

    private func discoverCandidates(for info: ProcessEntry) async -> [EndpointCandidate] {
        let ipv4Only = info.desktopRPCPort != nil
        let ports: [Int]
        do {
            let lsof = try await runCommand(
                "/usr/sbin/lsof",
                ["-nP", ipv4Only ? "-i4TCP" : "-iTCP", "-sTCP:LISTEN", "-a", "-p", String(info.pid)],
                4
            )
            ports = lsof.status == 0 ? Self.parseListeningPorts(lsof.stdout, ipv4LoopbackOnly: ipv4Only) : []
        } catch {
            ports = []
        }
        return Self.endpointCandidates(for: info, listeningPorts: ports)
    }

    /// Preflights GetUnleashData so the reachable endpoint moves to the front without dropping fallbacks.
    private func resolveWorkingEndpoint(_ candidates: [EndpointCandidate]) async -> [EndpointCandidate] {
        guard candidates.count > 1 else { return candidates }
        let body = (try? JSONSerialization.data(withJSONObject: [
            "context": [
                "properties": [
                    "devMode": "false",
                    "extensionVersion": "unknown",
                    "hasAnthropicModelAccess": "true",
                    "ide": "antigravity",
                    "ideVersion": "unknown",
                    "installationId": "zisla",
                    "language": "UNSPECIFIED",
                    "os": "darwin",
                    "requestedModelId": "MODEL_UNSPECIFIED",
                ],
            ],
        ])) ?? Data("{}".utf8)
        for candidate in candidates {
            if Task.isCancelled { break }
            do {
                _ = try await rpcCall(candidate, "GetUnleashData", body, 2)
                return [candidate] + candidates.filter { $0 != candidate }
            } catch {
                continue
            }
        }
        return candidates
    }

    private func fetchIdentity(_ candidate: EndpointCandidate) async -> (email: String?, plan: String?)? {
        let body = (try? JSONSerialization.data(withJSONObject: [
            "metadata": [
                "ideName": "antigravity",
                "extensionName": "antigravity",
                "ideVersion": "unknown",
                "locale": "en",
            ],
        ])) ?? Data("{}".utf8)
        guard let root = try? await invoke(candidate, method: "GetUserStatus", payload: body, timeout: 1.5),
              let status = root["userStatus"] as? [String: Any] else {
            return nil
        }
        let email = (status["email"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        let planInfo = (status["planStatus"] as? [String: Any])?["planInfo"] as? [String: Any]
        let planCandidates: [String?] = [
            (status["userTier"] as? [String: Any])?["name"] as? String,
            planInfo?["planDisplayName"] as? String,
            planInfo?["displayName"] as? String,
            planInfo?["productName"] as? String,
            planInfo?["planName"] as? String,
            planInfo?["planShortName"] as? String,
        ]
        let plan = planCandidates.compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }.first { !$0.isEmpty }
        return (email: email?.isEmpty == false ? email : nil, plan: plan)
    }

    private func invoke(_ candidate: EndpointCandidate, method: String, payload: Data, timeout: TimeInterval) async throws -> [String: Any] {
        let response = try await rpcCall(candidate, method, payload, timeout)
        if response.statusCode == 200 {
            return try AIAccountBalanceCredentials.object(response.body)
        }
        if let object = try? AIAccountBalanceCredentials.object(response.body) {
            let message = ((object["message"] as? String) ?? (object["error"] as? String) ?? "").lowercased()
            if message.contains("csrf") {
                throw AIAccountBalanceError.credentialsExpired
            }
        }
        if response.statusCode == 401 || response.statusCode == 403 {
            throw AIAccountBalanceError.credentialsExpired
        }
        throw AIAccountBalanceError.httpStatus(response.statusCode)
    }

    private static func preferError(_ previous: Error, _ next: Error) -> Error {
        if case AIAccountBalanceError.credentialsExpired = previous { return previous }
        return next
    }

    // MARK: - Process & Descriptor Parsing

    static func defaultReadDesktopHubs(
        home: URL,
        fileRead: (URL) throws -> Data? = AIAccountBalanceCredentials.readRegularFile,
        listEntries: (URL) -> [(name: String, modifiedAt: TimeInterval)]? = { directory in
            guard let items = try? FileManager.default.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey, .contentModificationDateKey],
                options: [.skipsHiddenFiles]
            ) else { return nil }
            return items.compactMap { url in
                guard let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .contentModificationDateKey]),
                      values.isRegularFile == true, values.isSymbolicLink != true else { return nil }
                return (url.lastPathComponent, values.contentModificationDate?.timeIntervalSince1970 ?? 0)
            }
        }
    ) -> [Int: DesktopHubDescriptor] {
        let directory = home.appendingPathComponent(".gemini/antigravity/daemon", isDirectory: true)
        guard let entries = listEntries(directory) else { return [:] }
        var hubs: [Int: DesktopHubDescriptor] = [:]
        for entry in entries {
            guard let port = hubFilenamePort(entry.name) else { continue }
            let fileURL = directory.appendingPathComponent(entry.name)
            guard let data = try? fileRead(fileURL),
                  data.count <= maximumDescriptorBytes,
                  let root = try? AIAccountBalanceCredentials.object(data),
                  let rawPID = AIAccountBalanceCredentials.number(root["pid"]),
                  let rawPort = AIAccountBalanceCredentials.number(root["httpPort"]),
                  rawPID > 0, rawPID.rounded() == rawPID, rawPID <= Double(Int32.max),
                  rawPort == Double(port),
                  let csrfToken = root["csrfToken"] as? String,
                  isValidHubCSRFToken(csrfToken) else { continue }
            let pid = Int(rawPID)
            if let existing = hubs[pid], existing.modifiedAt >= entry.modifiedAt { continue }
            hubs[pid] = DesktopHubDescriptor(pid: pid, httpPort: port, csrfToken: csrfToken, modifiedAt: entry.modifiedAt)
        }
        return hubs
    }

    private static func hubFilenamePort(_ filename: String) -> Int? {
        guard filename.hasPrefix("hub_"), filename.hasSuffix(".json") else { return nil }
        let digits = filename.dropFirst(4).dropLast(5)
        guard !digits.isEmpty, digits.allSatisfy(\.isASCII), digits.allSatisfy(\.isNumber),
              let port = Int(digits), (1..<65_536).contains(port) else { return nil }
        return port
    }

    private static func isValidHubCSRFToken(_ token: String) -> Bool {
        guard token.utf8.count >= 32, token.utf8.count <= 256 else { return false }
        return token.unicodeScalars.allSatisfy { scalar in
            (0x30...0x39).contains(scalar.value)
                || (0x41...0x46).contains(scalar.value)
                || (0x61...0x66).contains(scalar.value)
                || scalar.value == 0x2d
        }
    }

    static func parseProcessList(_ stdout: String, desktopHubs: [Int: DesktopHubDescriptor] = [:]) throws -> [ProcessEntry] {
        var infos: [ProcessEntry] = []
        var sawTokenlessCsrfClient = false
        for rawLine in stdout.split(whereSeparator: \.isNewline) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty else { continue }
            if let entry = parseProcessLine(line, desktopHubs: desktopHubs) {
                infos.append(entry)
                continue
            }
            if let space = line.firstIndex(of: " ") {
                let command = String(line[line.index(after: space)...]).trimmingCharacters(in: .whitespaces)
                let lower = commandForMatching(command)
                if let kind = processKind(lower), extractFlag("--csrf_token", from: command) == nil,
                   kind != .cli || isHubModeCommand(lower) {
                    sawTokenlessCsrfClient = true
                }
            }
        }
        if !infos.isEmpty {
            return infos.sorted { $0.kind.rank != $1.kind.rank ? $0.kind.rank < $1.kind.rank : $0.pid < $1.pid }
        }
        if sawTokenlessCsrfClient {
            throw AIAccountBalanceError.credentialsUnavailable
        }
        return []
    }

    static func parseProcessLine(_ line: String, desktopHubs: [Int: DesktopHubDescriptor] = [:]) -> ProcessEntry? {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let space = trimmed.firstIndex(of: " ") else { return nil }
        guard let pid = Int(trimmed[..<space]), pid > 0 else { return nil }
        let command = String(trimmed[trimmed.index(after: space)...]).trimmingCharacters(in: .whitespaces)
        guard !command.isEmpty else { return nil }
        let lower = commandForMatching(command)
        guard let kind = processKind(lower) else { return nil }
        let csrfToken = extractFlag("--csrf_token", from: command)
        let desktopHub: DesktopHubDescriptor? = csrfToken == nil && kind == .app && isDesktopHubCommand(lower)
            ? desktopHubs[pid]
            : nil
        let isHubMode = isHubModeCommand(command)
        if (kind != .cli || isHubMode) && csrfToken == nil && desktopHub == nil {
            return nil
        }
        let resolvedToken = csrfToken ?? desktopHub?.csrfToken ?? ""
        if !resolvedToken.isEmpty, (try? AIAccountBalanceCredentials.header(resolvedToken)) == nil {
            return nil
        }
        let extensionToken = extractFlag("--extension_server_csrf_token", from: command).flatMap {
            try? AIAccountBalanceCredentials.header($0)
        }
        return ProcessEntry(
            pid: pid,
            kind: kind,
            csrfToken: resolvedToken,
            desktopRPCPort: desktopHub?.httpPort,
            extensionPort: extractPortFlag("--extension_server_port", from: command),
            extensionCsrfToken: extensionToken,
            hubPort: extractPortFlag("--hub-port", from: command)
        )
    }

    private static func commandForMatching(_ command: String) -> String {
        if command.hasPrefix("\""), let end = command.dropFirst().firstIndex(of: "\"") {
            let after = command.index(after: end)
            if after == command.endIndex || command[after].isWhitespace {
                let unwrapped = String(command[command.index(after: command.startIndex)..<end]) + String(command[after...])
                return unwrapped.lowercased()
            }
        }
        return command.lowercased()
    }

    private static func isLanguageServerCommand(_ lower: String) -> Bool {
        lower.range(of: #"(?:^|[\s/\\])language(?:_|-)server(?:[_-][a-z0-9]+)*(?:\.exe)?(?:\s|$)"#, options: .regularExpression) != nil
    }

    private static func isAntigravityCommand(_ lower: String) -> Bool {
        if lower.contains("--app_data_dir"), lower.contains("antigravity") { return true }
        if lower.contains("/antigravity/") || lower.contains("\\antigravity\\") { return true }
        if lower.contains("/antigravity.app/") { return true }
        return false
    }

    private static func isHubModeCommand(_ command: String) -> Bool {
        command.range(of: #"(?:^|\s)--hub(?:\s|=|$)"#, options: [.regularExpression, .caseInsensitive]) != nil
    }

    private static func isAntigravityCLICommand(_ lower: String) -> Bool {
        if lower.range(of: #"(?:^|[/\\])(antigravity-cli|antigravity_cli)(?:[\s/\\]|$)"#, options: .regularExpression) != nil {
            return true
        }
        if lower.range(of: #"(?:^|[/\\])agy(?:\.exe)?(?:\s|$)"#, options: .regularExpression) != nil {
            return isLanguageServerCommand(lower) || isHubModeCommand(lower)
        }
        return false
    }

    private static func isAntigravityIDECommand(_ lower: String) -> Bool {
        let markers = [
            "antigravity ide.app/",
            "antigravity ide.app\\",
            "--app_data_dir antigravity-ide",
            "--app_data_dir=antigravity-ide",
            "/extensions/antigravity/bin/language_server",
            "\\extensions\\antigravity\\bin\\language_server",
        ]
        return markers.contains { lower.contains($0) }
    }

    private static func processKind(_ lower: String) -> ProcessKind? {
        if isLanguageServerCommand(lower), isAntigravityCommand(lower) {
            return isAntigravityIDECommand(lower) ? .ide : .app
        }
        if isAntigravityCLICommand(lower) { return .cli }
        return nil
    }

    private static func isDesktopHubCommand(_ lower: String) -> Bool {
        lower.range(of: #"(?:^|\s)--read_host_bridge_token_from_stdin(?:\s|$)"#, options: .regularExpression) != nil
            && extractFlag("--app_data_dir", from: lower) == "antigravity"
    }

    static func extractFlag(_ flag: String, from command: String) -> String? {
        let escaped = NSRegularExpression.escapedPattern(for: flag)
        guard let regex = try? NSRegularExpression(pattern: "(?:^|\\s)\(escaped)[=\\s]+([^\\s]+)", options: .caseInsensitive) else {
            return nil
        }
        let range = NSRange(command.startIndex..., in: command)
        guard let match = regex.firstMatch(in: command, range: range),
              let valueRange = Range(match.range(at: 1), in: command) else { return nil }
        return String(command[valueRange])
    }

    private static func extractPortFlag(_ flag: String, from command: String) -> Int? {
        guard let raw = extractFlag(flag, from: command), let port = Int(raw), (1..<65_536).contains(port) else {
            return nil
        }
        return port
    }

    static func parseListeningPorts(_ stdout: String, ipv4LoopbackOnly: Bool) -> [Int] {
        let pattern = ipv4LoopbackOnly ? #"\s127\.0\.0\.1:(\d+)\s+\(LISTEN\)"# : #":(\d+)\s+\(LISTEN\)"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let range = NSRange(stdout.startIndex..., in: stdout)
        var ports: Set<Int> = []
        for match in regex.matches(in: stdout, range: range) {
            guard let portRange = Range(match.range(at: 1), in: stdout),
                  let port = Int(stdout[portRange]), (1..<65_536).contains(port) else { continue }
            ports.insert(port)
        }
        return ports.sorted()
    }

    static func endpointCandidates(for info: ProcessEntry, listeningPorts: [Int]) -> [EndpointCandidate] {
        if let port = info.desktopRPCPort {
            guard listeningPorts.contains(port) else { return [] }
            return [EndpointCandidate(scheme: "http", port: port, csrfToken: info.csrfToken, desktopPID: info.pid)]
        }
        var raw: [EndpointCandidate] = []
        if let hubPort = info.hubPort {
            raw.append(.init(scheme: "https", port: hubPort, csrfToken: info.csrfToken, desktopPID: nil))
            raw.append(.init(scheme: "http", port: hubPort, csrfToken: info.csrfToken, desktopPID: nil))
        }
        for port in listeningPorts {
            raw.append(.init(scheme: "https", port: port, csrfToken: info.csrfToken, desktopPID: nil))
            raw.append(.init(scheme: "http", port: port, csrfToken: info.csrfToken, desktopPID: nil))
        }
        if let extensionPort = info.extensionPort {
            raw.append(.init(scheme: "http", port: extensionPort, csrfToken: info.extensionCsrfToken ?? info.csrfToken, desktopPID: nil))
        }
        var unique: [EndpointCandidate] = []
        for candidate in raw where !unique.contains(candidate) {
            unique.append(candidate)
        }
        return unique
    }

    // MARK: - Verified Loopback Transport

    private static func defaultRunCommand(_ path: String, _ arguments: [String], _ timeout: TimeInterval) async throws -> (status: Int32, stdout: String, stderr: String) {
        let output = try await AIAgentProcessRunner.run(
            executableURL: URL(fileURLWithPath: path),
            arguments: arguments,
            environment: ["PATH": "/usr/sbin:/usr/bin:/bin"],
            workingDirectoryURL: FileManager.default.temporaryDirectory,
            timeout: timeout,
            maximumOutputBytes: maximumCommandOutputBytes,
            maximumErrorBytes: 16 * 1_024
        )
        guard !output.didTimeout else { throw AIAccountBalanceError.noQuota }
        return (
            output.status,
            String(data: output.standardOutput, encoding: .utf8) ?? "",
            output.standardError
        )
    }

    static func verifyDesktopSocketOwned(
        port: Int,
        pid: Int,
        localPort: Int,
        runCommand: @Sendable (String, [String], TimeInterval) async throws -> (status: Int32, stdout: String, stderr: String),
        sleep: @Sendable (TimeInterval) async throws -> Void
    ) async throws -> Bool {
        let expected = "n127.0.0.1:\(port)->127.0.0.1:\(localPort)"
        func check() async throws -> Bool {
            let result = try await runCommand(
                "/usr/sbin/lsof",
                ["-nP", "-a", "-p", String(pid), "-i4TCP", "-sTCP:ESTABLISHED", "-Fn"],
                3
            )
            guard result.status == 0 else { return false }
            return result.stdout.split(whereSeparator: \.isNewline).contains { $0 == expected }
        }
        if try await check() { return true }
        try await sleep(0.02)
        return try await check()
    }

    private static func defaultRPCCall(
        candidate: EndpointCandidate,
        method: String,
        payload: Data,
        timeout: TimeInterval,
        verifySocketOwner: @escaping @Sendable (Int, Int, Int) async throws -> Bool
    ) async throws -> RPCResponse {
        try Task.checkCancellation()
        if let desktopPID = candidate.desktopPID {
            guard candidate.scheme == "http", desktopPID > 0, (1..<65_536).contains(candidate.port) else {
                throw AIAccountBalanceError.noQuota
            }
            return try await callVerifiedLoopbackHTTP(
                port: candidate.port,
                pid: desktopPID,
                csrfToken: candidate.csrfToken,
                method: method,
                payload: payload,
                timeout: timeout,
                verifySocketOwner: verifySocketOwner
            )
        }
        guard candidate.scheme == "http" || candidate.scheme == "https",
              (1..<65_536).contains(candidate.port),
              let url = URL(string: "\(candidate.scheme)://127.0.0.1:\(candidate.port)\(servicePath)\(method)") else {
            throw AIAccountBalanceError.noQuota
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = timeout
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("1", forHTTPHeaderField: "Connect-Protocol-Version")
        request.setValue(candidate.csrfToken, forHTTPHeaderField: "x-codeium-csrf-token")
        request.httpBody = payload
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpShouldSetCookies = false
        configuration.httpCookieStorage = nil
        configuration.urlCache = nil
        configuration.timeoutIntervalForRequest = timeout
        configuration.timeoutIntervalForResource = timeout
        let session = URLSession(configuration: configuration, delegate: LoopbackRPCDelegate(), delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        let (bytes, response) = try await session.bytes(for: request)
        guard let http = response as? HTTPURLResponse, http.url == url else {
            throw AIAccountBalanceError.invalidResponse
        }
        guard http.expectedContentLength <= Int64(maximumResponseBytes) else {
            throw AIAccountBalanceError.invalidResponse
        }
        var data = Data()
        for try await byte in bytes {
            try Task.checkCancellation()
            guard data.count < maximumResponseBytes else { throw AIAccountBalanceError.invalidResponse }
            data.append(byte)
        }
        return RPCResponse(statusCode: http.statusCode, body: data)
    }

    /// Connects to 127.0.0.1, verifies the server socket belongs to the descriptor PID, and only then writes headers/body.
    static func callVerifiedLoopbackHTTP(
        port: Int,
        pid: Int,
        csrfToken: String,
        method: String,
        payload: Data,
        timeout: TimeInterval,
        verifySocketOwner: @escaping @Sendable (Int, Int, Int) async throws -> Bool
    ) async throws -> RPCResponse {
        let fd = try await connectLoopbackSocket(port: port, timeout: timeout)
        defer { close(fd) }
        guard let localPort = localSocketPort(fd) else {
            throw AIAccountBalanceError.noQuota
        }
        let owned = try await verifySocketOwner(port, pid, localPort)
        try Task.checkCancellation()
        guard owned else {
            throw AIAccountBalanceError.noQuota
        }
        let requestText = [
            "POST \(servicePath)\(method) HTTP/1.1",
            "Host: 127.0.0.1:\(port)",
            "Content-Type: application/json",
            "Content-Length: \(payload.count)",
            "Connect-Protocol-Version: 1",
            "x-codeium-csrf-token: \(csrfToken)",
            "Connection: close",
            "",
            "",
        ].joined(separator: "\r\n")
        var wire = Data(requestText.utf8)
        wire.append(payload)
        return try await exchangeOnSocket(fd: fd, request: wire)
    }

    private static func connectLoopbackSocket(port: Int, timeout: TimeInterval) async throws -> Int32 {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                let fd = socket(AF_INET, SOCK_STREAM, 0)
                guard fd >= 0 else {
                    continuation.resume(throwing: AIAccountBalanceError.noQuota)
                    return
                }
                var noSigPipe: Int32 = 1
                _ = setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &noSigPipe, socklen_t(MemoryLayout<Int32>.size))
                let clamped = max(1, min(15, timeout))
                var tv = timeval(tv_sec: Int(clamped), tv_usec: __darwin_suseconds_t((clamped - floor(clamped)) * 1_000_000))
                _ = setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))
                _ = setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))

                var address = sockaddr_in()
                address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
                address.sin_family = sa_family_t(AF_INET)
                address.sin_port = in_port_t(UInt16(port).bigEndian)
                address.sin_addr = in_addr(s_addr: inet_addr("127.0.0.1"))
                let connected = withUnsafePointer(to: &address) { pointer in
                    pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                        Darwin.connect(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
                    }
                }
                guard connected == 0 else {
                    close(fd)
                    continuation.resume(throwing: AIAccountBalanceError.noQuota)
                    return
                }
                continuation.resume(returning: fd)
            }
        }
    }

    private static func localSocketPort(_ fd: Int32) -> Int? {
        var address = sockaddr_in()
        var length = socklen_t(MemoryLayout<sockaddr_in>.size)
        let result = withUnsafeMutablePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                getsockname(fd, $0, &length)
            }
        }
        guard result == 0 else { return nil }
        return Int(UInt16(bigEndian: address.sin_port))
    }

    private static func exchangeOnSocket(fd: Int32, request: Data) async throws -> RPCResponse {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                let wroteAll = request.withUnsafeBytes { rawBuffer -> Bool in
                    guard let base = rawBuffer.baseAddress else { return true }
                    var sent = 0
                    while sent < rawBuffer.count {
                        let written = Darwin.send(fd, base.advanced(by: sent), rawBuffer.count - sent, 0)
                        if written <= 0 {
                            if errno == EINTR { continue }
                            return false
                        }
                        sent += written
                    }
                    return true
                }
                guard wroteAll else {
                    continuation.resume(throwing: AIAccountBalanceError.noQuota)
                    return
                }
                var received = Data()
                var buffer = [UInt8](repeating: 0, count: 16 * 1_024)
                let limit = maximumResponseBytes + 32 * 1_024
                while true {
                    let count = Darwin.recv(fd, &buffer, buffer.count, 0)
                    if count < 0 {
                        if errno == EINTR { continue }
                        continuation.resume(throwing: AIAccountBalanceError.noQuota)
                        return
                    }
                    if count == 0 { break }
                    if received.count + count > limit {
                        continuation.resume(throwing: AIAccountBalanceError.invalidResponse)
                        return
                    }
                    received.append(contentsOf: buffer.prefix(count))
                }
                do {
                    continuation.resume(returning: try parseHTTPResponse(received))
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    static func parseHTTPResponse(_ raw: Data) throws -> RPCResponse {
        let separator = Data("\r\n\r\n".utf8)
        guard let split = raw.range(of: separator) else {
            throw AIAccountBalanceError.invalidResponse
        }
        guard let headerText = String(data: raw[..<split.lowerBound], encoding: .utf8) else {
            throw AIAccountBalanceError.invalidResponse
        }
        let lines = headerText.components(separatedBy: "\r\n")
        guard let statusLine = lines.first else { throw AIAccountBalanceError.invalidResponse }
        let parts = statusLine.split(separator: " ", maxSplits: 2)
        guard parts.count >= 2, parts[0].hasPrefix("HTTP/1."),
              let statusCode = Int(parts[1]), (100...599).contains(statusCode) else {
            throw AIAccountBalanceError.invalidResponse
        }
        var headers: [String: String] = [:]
        for line in lines.dropFirst() {
            guard let colon = line.firstIndex(of: ":") else { continue }
            let name = line[..<colon].trimmingCharacters(in: .whitespaces).lowercased()
            let value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            headers[name] = value
        }
        let rawBody = Data(raw[split.upperBound...])
        let body: Data
        if headers["transfer-encoding"]?.lowercased().contains("chunked") == true {
            body = try decodeChunkedBody(rawBody)
        } else if let lengthText = headers["content-length"], let length = Int(lengthText) {
            guard length >= 0, length <= maximumResponseBytes, rawBody.count >= length else {
                throw AIAccountBalanceError.invalidResponse
            }
            body = Data(rawBody.prefix(length))
        } else {
            guard rawBody.count <= maximumResponseBytes else { throw AIAccountBalanceError.invalidResponse }
            body = rawBody
        }
        return RPCResponse(statusCode: statusCode, body: body)
    }

    private static func decodeChunkedBody(_ data: Data) throws -> Data {
        var result = Data()
        var index = data.startIndex
        let crlf = Data("\r\n".utf8)
        while index < data.endIndex {
            guard let lineEnd = data.range(of: crlf, in: index..<data.endIndex),
                  let sizeText = String(data: data[index..<lineEnd.lowerBound], encoding: .ascii)?
                      .split(separator: ";").first?.trimmingCharacters(in: .whitespaces),
                  let chunkSize = Int(sizeText, radix: 16), chunkSize >= 0 else {
                throw AIAccountBalanceError.invalidResponse
            }
            index = lineEnd.upperBound
            if chunkSize == 0 { return result }
            guard result.count + chunkSize <= maximumResponseBytes,
                  index + chunkSize + 2 <= data.endIndex else {
                throw AIAccountBalanceError.invalidResponse
            }
            result.append(data[index..<(index + chunkSize)])
            index += chunkSize
            guard data[index..<(index + 2)] == crlf else {
                throw AIAccountBalanceError.invalidResponse
            }
            index += 2
        }
        throw AIAccountBalanceError.invalidResponse
    }
}

/// Blocks redirects and permits self-signed TLS certificates exclusively on loopback 127.0.0.1.
private final class LoopbackRPCDelegate: NSObject, URLSessionTaskDelegate, URLSessionDelegate, Sendable {
    func urlSession(
        _: URLSession,
        task _: URLSessionTask,
        willPerformHTTPRedirection _: HTTPURLResponse,
        newRequest _: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        completionHandler(nil)
    }

    func urlSession(
        _: URLSession,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        if challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
           challenge.protectionSpace.host == "127.0.0.1",
           let trust = challenge.protectionSpace.serverTrust {
            completionHandler(.useCredential, URLCredential(trust: trust))
            return
        }
        completionHandler(.performDefaultHandling, nil)
    }
}
