import Foundation

/// Tool management for the download page: locating, checking for updates, and installing managed components.
@MainActor
public final class ManagedToolService: ObservableObject {
    @Published public private(set) var states: [ManagedTool: ManagedToolState] = [:]

    private let toolsDirectory: URL
    private let bundleURL: URL
    private var session: URLSession
    private var releaseLoader: (String) async throws -> Data
    private let usesDefaultReleaseLoader: Bool
    private var networkProxyURL = ""
    private var networkProxyEnabled = false
    private let defaults: UserDefaults
    private let homebrewExecutable: URL?
    private var refreshedInstalledVersions = Set<ManagedTool>()
    private var latestVersionCheckedAt: [ManagedTool: Date] = [:]

    private static let cacheKey = "managed-tool-state-cache-v1"
    private static let latestVersionCacheLifetime: TimeInterval = 5 * 60

    public init(
        toolsDirectory: URL = AppPaths.managedTools,
        bundleURL: URL = Bundle.main.bundleURL,
        session: URLSession = .shared,
        defaults: UserDefaults = .standard,
        releaseLoader: ((String) async throws -> Data)? = nil,
        homebrewExecutable: URL? = nil
    ) {
        self.toolsDirectory = toolsDirectory
        self.bundleURL = bundleURL
        self.session = session
        self.usesDefaultReleaseLoader = releaseLoader == nil
        self.defaults = defaults
        self.homebrewExecutable = homebrewExecutable ?? Self.defaultHomebrewExecutable()
        self.releaseLoader = releaseLoader ?? Self.makeReleaseLoader(session: session)
        for tool in ManagedTool.allCases { states[tool] = ManagedToolState() }
        restoreCachedStates()
    }

    public func setNetworkProxyURL(_ value: String) {
        setNetworkProxy(url: value, enabled: true)
    }

    public func setNetworkProxy(url: String, enabled: Bool) {
        networkProxyURL = url
        networkProxyEnabled = enabled
        guard usesDefaultReleaseLoader else { return }
        session = URLSession(configuration: NetworkProxy.sessionConfiguration(from: url, enabled: enabled))
        releaseLoader = Self.makeReleaseLoader(session: session)
    }

    private var processEnvironment: [String: String] {
        NetworkProxy.environment(
            from: networkProxyURL,
            enabled: networkProxyEnabled,
            base: ProcessInfo.processInfo.environment
        )
    }

    private static func makeReleaseLoader(session: URLSession) -> (String) async throws -> Data {
        { repository in
            let url = URL(string: "https://api.github.com/repos/\(repository)/releases/latest")!
            var request = URLRequest(url: url)
            request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
            request.timeoutInterval = 20
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                let code = (response as? HTTPURLResponse)?.statusCode ?? -1
                throw ManagedToolError.releaseUnavailable("HTTP \(code)")
            }
            return data
        }
    }

    // MARK: - Locating

    /// Resolution order: Zisla-downloaded > bundled > system-installed.
    /// The downloaded build wins, otherwise clicking "Update" would be pointless.
    public func resolvedExecutable(for tool: ManagedTool) -> (url: URL, location: ManagedToolState.Location)? {
        if !tool.usesHomebrew {
            let managed = toolsDirectory.appendingPathComponent(tool.executableName, isDirectory: false)
            if let trusted = trustedExecutable(managed) {
                return (trusted, .managed)
            }
            let bundled = bundleURL
                .appendingPathComponent("Contents/Helpers", isDirectory: true)
                .appendingPathComponent(tool.executableName, isDirectory: false)
            if let trusted = trustedExecutable(bundled) {
                return (trusted, .bundled)
            }
        }
        for path in Self.externalPaths(for: tool) {
            if let trusted = trustedExecutable(URL(fileURLWithPath: path)) {
                return (trusted, tool.usesHomebrew ? .homebrew : .external(path))
            }
        }
        return nil
    }

    static func externalPaths(for tool: ManagedTool) -> [String] {
        // Paths for Cask applications.
        if tool == .libreOffice {
            return [
                "/Applications/LibreOffice.app/Contents/MacOS/soffice",
                "/Applications/OpenOffice.app/Contents/MacOS/soffice",
                "/opt/homebrew/bin/soffice",
                "/usr/local/bin/soffice",
            ]
        }
        if tool == .kaku {
            return [
                "/opt/homebrew/bin/kaku",
                "/Applications/Kaku.app/Contents/MacOS/kaku",
            ]
        }
        if tool == .kero {
            return ["/Applications/Kero.app/Contents/MacOS/kero"]
        }
        if tool == .markdownPreview {
            return [
                "/opt/homebrew/bin/mdp",
                "/Applications/Markdown Preview.app/Contents/Resources/bin/markdown-preview",
            ]
        }
        if tool == .keka {
            return [
                "/opt/homebrew/bin/keka",
                "/Applications/Keka.app/Contents/MacOS/Keka",
            ]
        }

        // Common paths for command-line tools.
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let commonPaths = [
            "/opt/homebrew/bin/\(tool.executableName)",
            "/usr/local/bin/\(tool.executableName)",
            "\(home)/.local/bin/\(tool.executableName)",
        ]
        switch tool {
        case .curl:
            return [
                "/opt/homebrew/opt/curl/bin/curl",
                "/usr/local/opt/curl/bin/curl",
            ] + commonPaths
        case .openJDK17:
            return [
                "/opt/homebrew/opt/openjdk@17/bin/java",
                "/usr/local/opt/openjdk@17/bin/java",
            ] + commonPaths
        default:
            return commonPaths
        }
    }

    private func trustedExecutable(_ url: URL) -> URL? {
        // Shares the same trusted directory chain check as the existing yt-dlp resolution, so no file writable by others gets executed.
        YTDLPResolver.isTrustedExecutable(url) ? url.resolvingSymlinksInPath() : nil
    }

    /// Refreshes every tool's install status and version (no network access).
    public func refreshInstalledVersions() async {
        for tool in ManagedTool.allCases {
            // install() writes its own final state; stale resolution results must not overwrite it during installation.
            guard states[tool]?.isBusy != true else { continue }
            guard !refreshedInstalledVersions.contains(tool) else { continue }
            guard let resolved = resolvedExecutable(for: tool) else {
                states[tool]?.installedVersion = nil
                states[tool]?.location = nil
                refreshedInstalledVersions.insert(tool)
                persistCachedStates()
                continue
            }
            let version = await installedVersion(of: tool, at: resolved.url)
            // Version reads take about a second, during which installation may finish; discard stale resolution results and let the next refresh correct them.
            guard states[tool]?.isBusy != true,
                  resolvedExecutable(for: tool)?.url == resolved.url
            else { continue }
            states[tool]?.location = resolved.location
            states[tool]?.installedVersion = version
            refreshedInstalledVersions.insert(tool)
            persistCachedStates()
        }
    }

    private func installedVersion(of tool: ManagedTool, at executableURL: URL) async -> String? {
        guard case .homebrewFormula(let formulaName) = tool.installationSource else {
            return await Self.readVersion(of: tool, at: executableURL, environment: processEnvironment)
        }
        if let output = try? await runHomebrew(["list", "--versions", "--formula", formulaName]),
           let version = Self.parseHomebrewInstalledVersion(output, tool: tool) {
            return version
        }
        return await Self.readVersion(of: tool, at: executableURL, environment: processEnvironment)
    }

    static func readVersion(
        of tool: ManagedTool,
        at url: URL,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) async -> String? {
        if tool.usesNativeApplicationVersion {
            return nativeApplicationVersion(at: url)
        }
        guard case .success(let output) = await runProcess(url, arguments: tool.versionArguments, environment: environment) else {
            return nil
        }
        return tool.normalizedInstalledVersion(from: output)
    }

    private static func nativeApplicationVersion(at executableURL: URL) -> String? {
        guard let appPath = executableURL.pathComponents.first(where: { $0.hasSuffix(".app") }) else {
            return nil
        }
        guard let appIndex = executableURL.pathComponents.firstIndex(of: appPath) else { return nil }
        let appURL = URL(fileURLWithPath: String(
            executableURL.pathComponents.prefix(appIndex + 1).joined(separator: "/")
        ))
        return Bundle(url: appURL)?.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
    }

    /// Normalize a version by trimming whitespace and stripping a leading v.
    nonisolated static func normalizeVersion(_ raw: String) -> String? {
        let trimmed = raw
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .components(separatedBy: .newlines)
            .first?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let trimmed, !trimmed.isEmpty else { return nil }
        return trimmed.hasPrefix("v") ? String(trimmed.dropFirst()) : trimmed
    }

    static func parseHomebrewCaskInfo(_ data: Data, caskName: String, tool: ManagedTool) throws -> String {
        let token = caskName.split(separator: "/").last.map(String.init)
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let casks = root["casks"] as? [[String: Any]],
              let cask = casks.first(where: {
                  ($0["token"] as? String) == caskName
                      || ($0["full_token"] as? String) == caskName
                      || ($0["token"] as? String) == token
              }),
              let version = cask["version"] as? String,
              let normalized = tool.normalizedInstalledVersion(from: version)
        else {
            throw ManagedToolError.homebrewFailed("无法读取 \(caskName) 的版本信息")
        }
        return normalized
    }

    static func parseHomebrewFormulaInfo(_ data: Data, formulaName: String, tool: ManagedTool) throws -> String {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let formulae = root["formulae"] as? [[String: Any]],
              let formula = formulae.first(where: {
                  ($0["name"] as? String) == formulaName
                      || ($0["full_name"] as? String) == formulaName
                      || (($0["aliases"] as? [String])?.contains(formulaName) == true)
              }),
              let versions = formula["versions"] as? [String: Any],
              let version = versions["stable"] as? String,
              let normalized = tool.normalizedInstalledVersion(from: version)
        else {
            throw ManagedToolError.homebrewFailed("无法读取 \(formulaName) 的版本信息")
        }
        let revision = formula["revision"] as? Int ?? 0
        return revision > 0 ? "\(normalized)_\(revision)" : normalized
    }

    static func parseHomebrewInstalledVersion(_ output: String, tool: ManagedTool) -> String? {
        guard let line = output.split(whereSeparator: \.isNewline).first,
              let version = line.split(whereSeparator: \.isWhitespace).last
        else { return nil }
        return tool.normalizedInstalledVersion(from: String(version))
    }

    // MARK: - Latest version lookup

    struct Release: Sendable, Equatable {
        let version: String
        let assetURL: URL
    }

    /// The GitHub API is used only to obtain the version number and asset URL, never to download content.
    static func parseRelease(
        _ data: Data,
        tool: ManagedTool
    ) throws -> Release {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ManagedToolError.releaseUnavailable("响应不是合法 JSON")
        }
        guard let tag = root["tag_name"] as? String,
              let version = normalizeVersion(tag)
        else {
            throw ManagedToolError.releaseUnavailable("响应缺少版本号")
        }
        let assets = root["assets"] as? [[String: Any]] ?? []
        let matched = assets.first { asset in
            guard let name = asset["name"] as? String else { return false }
            return tool.matchesAsset(name: name)
        }
        guard let matched,
              let urlString = matched["browser_download_url"] as? String,
              let url = URL(string: urlString)
        else {
            throw ManagedToolError.assetNotFound(tool: tool.displayName)
        }
        try validate(url)
        return Release(version: version, assetURL: url)
    }

    /// Without checksum verification, provenance rests entirely on GitHub's TLS, so HTTPS is required and hosts are restricted.
    static func validate(_ url: URL) throws {
        guard url.scheme?.lowercased() == "https", let host = url.host?.lowercased() else {
            throw ManagedToolError.untrustedHost(url.host ?? "非 HTTPS 地址")
        }
        let trusted = host == "github.com"
            || host == "objects.githubusercontent.com"
            || host.hasSuffix(".githubusercontent.com")
        guard trusted else { throw ManagedToolError.untrustedHost(host) }
    }

    /// `quietly` supports automatic background checks when entering Settings: failures (such as being offline) do not write errorMessage,
    /// preventing inline version information from being replaced by an error the user did not trigger.
    @discardableResult
    public func checkLatest(_ tool: ManagedTool, quietly: Bool = false) async -> String? {
        guard states[tool]?.isBusy != true else { return states[tool]?.latestVersion }
        if quietly,
           let latestVersion = states[tool]?.latestVersion,
           let checkedAt = latestVersionCheckedAt[tool],
           Date().timeIntervalSince(checkedAt) < Self.latestVersionCacheLifetime {
            return latestVersion
        }
        if !quietly { states[tool]?.errorMessage = nil }
        states[tool]?.phase = .checking
        defer { states[tool]?.phase = .idle }
        do {
            let latestVersion: String
            switch tool.installationSource {
            case .githubRelease(let repository):
                let data = try await releaseLoader(repository)
                latestVersion = try Self.parseRelease(data, tool: tool).version
            case .homebrewCask(let caskName):
                let output = try await runHomebrew(["info", "--cask", "--json=v2", caskName])
                latestVersion = try Self.parseHomebrewCaskInfo(
                    Data(output.utf8),
                    caskName: caskName,
                    tool: tool
                )
            case .homebrewFormula(let formulaName):
                let output = try await runHomebrew(["info", "--formula", "--json=v2", formulaName])
                latestVersion = try Self.parseHomebrewFormulaInfo(
                    Data(output.utf8),
                    formulaName: formulaName,
                    tool: tool
                )
            }
            states[tool]?.latestVersion = latestVersion
            latestVersionCheckedAt[tool] = Date()
            persistCachedStates()
            return latestVersion
        } catch let error as ManagedToolError {
            if !quietly { states[tool]?.errorMessage = error.message }
        } catch {
            if !quietly {
                states[tool]?.errorMessage = ManagedToolError
                    .releaseUnavailable(error.localizedDescription).message
            }
        }
        return nil
    }

    // MARK: - Download and install

    /// Installs or updates a component using its declared source.
    public func install(_ tool: ManagedTool) async {
        // Rendering may lag behind state, allowing repeated taps; discard later installs to prevent two tasks from racing over files and state.
        guard states[tool]?.isBusy != true else { return }
        states[tool]?.errorMessage = nil
        states[tool]?.phase = .checking
        do {
            if let tap = tool.requiredHomebrewTap {
                _ = try await runHomebrew(["tap", tap])
            }
            switch tool.installationSource {
            case .githubRelease(let repository):
                try await installGitHubRelease(tool, repository: repository)
            case .homebrewCask(let caskName):
                try await installHomebrewCask(tool, caskName: caskName)
            case .homebrewFormula(let formulaName):
                try await installHomebrewFormula(tool, formulaName: formulaName)
            }
            states[tool]?.phase = .idle
        } catch let error as ManagedToolError {
            states[tool]?.errorMessage = error.message
            states[tool]?.phase = .idle
        } catch {
            states[tool]?.errorMessage = ManagedToolError
                .downloadFailed(error.localizedDescription).message
            states[tool]?.phase = .idle
        }
    }

    private static func defaultHomebrewExecutable() -> URL? {
        let candidates = [
            URL(fileURLWithPath: "/opt/homebrew/bin/brew"),
            URL(fileURLWithPath: "/usr/local/bin/brew"),
        ]
        return candidates.first { YTDLPResolver.isTrustedExecutable($0) }
    }

    private func runHomebrew(_ arguments: [String]) async throws -> String {
        guard let homebrewExecutable else { throw ManagedToolError.homebrewUnavailable }
        switch await Self.runProcess(homebrewExecutable, arguments: arguments, environment: processEnvironment) {
        case .success(let output):
            return output
        case .failure(let error):
            throw ManagedToolError.homebrewFailed(error.message)
        }
    }

    private func installGitHubRelease(_ tool: ManagedTool, repository: String) async throws {
        let data = try await releaseLoader(repository)
        let release = try Self.parseRelease(data, tool: tool)
        states[tool]?.latestVersion = release.version

        states[tool]?.phase = .downloading(0)
        let downloaded = try await download(release.assetURL)
        defer { try? FileManager.default.removeItem(at: downloaded.deletingLastPathComponent()) }

        states[tool]?.phase = .installing
        let (_, version) = try await install(downloaded, as: tool)
        states[tool]?.installedVersion = version
        states[tool]?.location = .managed
        refreshedInstalledVersions.insert(tool)
        persistCachedStates()
    }

    private func installHomebrewCask(_ tool: ManagedTool, caskName: String) async throws {
        let metadata = try await runHomebrew(["info", "--cask", "--json=v2", caskName])
        states[tool]?.latestVersion = try Self.parseHomebrewCaskInfo(
            Data(metadata.utf8),
            caskName: caskName,
            tool: tool
        )

        states[tool]?.phase = .installing
        let action = states[tool]?.isInstalled == true ? "upgrade" : "install"
        _ = try await runHomebrew([action, "--cask", caskName])
        refreshedInstalledVersions.remove(tool)

        guard let resolved = resolvedExecutable(for: tool) else {
            throw ManagedToolError.notExecutable(tool.displayName)
        }
        guard let version = await installedVersion(of: tool, at: resolved.url) else {
            throw ManagedToolError.notExecutable(tool.displayName)
        }
        states[tool]?.installedVersion = version
        states[tool]?.location = resolved.location
        states[tool]?.latestVersion = version
        refreshedInstalledVersions.insert(tool)
        persistCachedStates()
    }

    private func installHomebrewFormula(_ tool: ManagedTool, formulaName: String) async throws {
        let metadata = try await runHomebrew(["info", "--formula", "--json=v2", formulaName])
        states[tool]?.latestVersion = try Self.parseHomebrewFormulaInfo(
            Data(metadata.utf8),
            formulaName: formulaName,
            tool: tool
        )

        states[tool]?.phase = .installing
        let action = states[tool]?.isInstalled == true ? "upgrade" : "install"
        _ = try await runHomebrew([action, "--formula", formulaName])
        refreshedInstalledVersions.remove(tool)

        guard let resolved = resolvedExecutable(for: tool) else {
            throw ManagedToolError.notExecutable(tool.displayName)
        }
        guard let version = await installedVersion(of: tool, at: resolved.url) else {
            throw ManagedToolError.notExecutable(tool.displayName)
        }
        states[tool]?.installedVersion = version
        states[tool]?.location = resolved.location
        states[tool]?.latestVersion = version
        refreshedInstalledVersions.insert(tool)
        persistCachedStates()
    }

    // MARK: - Cached state

    private func restoreCachedStates() {
        guard let data = defaults.data(forKey: Self.cacheKey),
              let cachedStates = try? JSONDecoder().decode(
                  [String: CachedToolState].self,
                  from: data
              )
        else { return }

        for tool in ManagedTool.allCases {
            guard let cached = cachedStates[tool.rawValue] else { continue }
            var state = states[tool] ?? ManagedToolState()
            state.installedVersion = cached.installedVersion
            state.location = cached.location?.stateLocation
            state.latestVersion = cached.latestVersion
            states[tool] = state
            latestVersionCheckedAt[tool] = cached.latestVersionCheckedAt
        }
    }

    private func persistCachedStates() {
        let pairs: [(String, CachedToolState)] = ManagedTool.allCases.compactMap { tool in
            let state = states[tool] ?? ManagedToolState()
            guard state.location != nil || state.latestVersion != nil else { return nil }
            return (
                tool.rawValue,
                CachedToolState(
                    installedVersion: state.installedVersion,
                    location: state.location.map(CachedToolState.Location.init),
                    latestVersion: state.latestVersion,
                    latestVersionCheckedAt: latestVersionCheckedAt[tool] ?? .distantPast
                )
            )
        }
        let cachedStates = Dictionary(uniqueKeysWithValues: pairs)
        guard let data = try? JSONEncoder().encode(cachedStates) else { return }
        defaults.set(data, forKey: Self.cacheKey)
    }

    private struct CachedToolState: Codable {
        enum Location: Codable {
            case managed
            case bundled
            case external(String)
            case homebrew

            init(_ location: ManagedToolState.Location) {
                switch location {
                case .managed: self = .managed
                case .bundled: self = .bundled
                case .external(let path): self = .external(path)
                case .homebrew: self = .homebrew
                }
            }

            var stateLocation: ManagedToolState.Location {
                switch self {
                case .managed: .managed
                case .bundled: .bundled
                case .external(let path): .external(path)
                case .homebrew: .homebrew
                }
            }
        }

        let installedVersion: String?
        let location: Location?
        let latestVersion: String?
        let latestVersionCheckedAt: Date
    }

    private func download(_ url: URL) async throws -> URL {
        try Self.validate(url)
        var request = URLRequest(url: url)
        request.timeoutInterval = 300
        let (temporaryURL, response) = try await session.download(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw ManagedToolError.downloadFailed(
                "HTTP \((response as? HTTPURLResponse)?.statusCode ?? -1)"
            )
        }
        // The temporary file from download(for:) is reclaimed right after this await, so move it into a directory we own first.
        let workDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("zisla-tool-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: workDirectory, withIntermediateDirectories: true)
        let destination = workDirectory.appendingPathComponent(url.lastPathComponent)
        do {
            try FileManager.default.moveItem(at: temporaryURL, to: destination)
            return destination
        } catch {
            try? FileManager.default.removeItem(at: workDirectory)
            throw error
        }
    }

    private func install(_ executable: URL, as tool: ManagedTool) async throws -> (URL, String) {
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: toolsDirectory, withIntermediateDirectories: true)
        let destination = toolsDirectory.appendingPathComponent(
            tool.executableName,
            isDirectory: false
        )
        // Land on a temporary name in the same directory and then replace, so a half-finished overwrite cannot leave a broken file behind.
        let staging = toolsDirectory.appendingPathComponent(
            ".\(tool.executableName).\(UUID().uuidString)",
            isDirectory: false
        )
        if fileManager.fileExists(atPath: staging.path) {
            try fileManager.removeItem(at: staging)
        }
        defer { try? fileManager.removeItem(at: staging) }
        try fileManager.copyItem(at: executable, to: staging)
        try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: staging.path)
        Self.clearQuarantine(staging)
        guard let version = await Self.readVersion(of: tool, at: staging, environment: processEnvironment) else {
            throw ManagedToolError.notExecutable(tool.displayName)
        }

        if fileManager.fileExists(atPath: destination.path) {
            _ = try fileManager.replaceItemAt(destination, withItemAt: staging)
        } else {
            try fileManager.moveItem(at: staging, to: destination)
        }
        guard let trusted = trustedExecutable(destination) else {
            throw ManagedToolError.notExecutable(destination.lastPathComponent)
        }
        return (trusted, version)
    }

    /// Clear a quarantine flag should the download source add one.
    static func clearQuarantine(_ url: URL) {
        url.withUnsafeFileSystemRepresentation { path in
            guard let path else { return }
            removexattr(path, "com.apple.quarantine", 0)
        }
    }

    static func runProcess(
        _ executable: URL,
        arguments: [String],
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) async -> Result<String, ManagedToolError> {
        await Task.detached(priority: .userInitiated) { () -> Result<String, ManagedToolError> in
            let fileManager = FileManager.default
            let directory = fileManager.temporaryDirectory
                .appendingPathComponent("zisla-process-\(UUID().uuidString)", isDirectory: true)
            let stdoutURL = directory.appendingPathComponent("stdout")
            let stderrURL = directory.appendingPathComponent("stderr")
            do {
                try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
                defer { try? fileManager.removeItem(at: directory) }
                fileManager.createFile(atPath: stdoutURL.path, contents: nil)
                fileManager.createFile(atPath: stderrURL.path, contents: nil)
                let stdout = try FileHandle(forWritingTo: stdoutURL)
                let stderr = try FileHandle(forWritingTo: stderrURL)
                defer {
                    try? stdout.close()
                    try? stderr.close()
                }

                let process = Process()
                process.executableURL = executable
                process.arguments = arguments
                process.environment = environment
                process.standardOutput = stdout
                process.standardError = stderr
                do {
                    try process.run()
                } catch {
                    return .failure(.notExecutable(
                        "\(executable.lastPathComponent)：\(error.localizedDescription)"
                    ))
                }
                process.waitUntilExit()
                try? stdout.close()
                try? stderr.close()

                let data = try Data(contentsOf: stdoutURL)
                let errorData = try Data(contentsOf: stderrURL)
                guard process.terminationStatus == 0 else {
                    let message = [errorData, data]
                        .compactMap { String(data: $0, encoding: .utf8)?
                            .trimmingCharacters(in: .whitespacesAndNewlines) }
                        .first { !$0.isEmpty }
                    return .failure(.notExecutable(
                        message ?? "\(executable.lastPathComponent) 退出码 \(process.terminationStatus)"
                    ))
                }
                return .success(String(data: data, encoding: .utf8) ?? "")
            } catch {
                return .failure(.notExecutable(error.localizedDescription))
            }
        }.value
    }
}
