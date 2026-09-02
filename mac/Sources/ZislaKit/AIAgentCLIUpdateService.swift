import Foundation
import ZislaCore

/// Checks only public package metadata for installed AI CLIs. Local command content and credentials never leave the device.
public actor AIAgentCLIUpdateService {
    public typealias LatestVersionLoader = @Sendable (AgentCLIKind) async -> String?

    private var loadLatestVersion: LatestVersionLoader
    private let usesDefaultSession: Bool

    public init(session: URLSession = .shared) {
        self.usesDefaultSession = true
        loadLatestVersion = Self.makeLoader(session: session)
    }

    private static func makeLoader(session: URLSession) -> LatestVersionLoader {
        { kind in
            guard let package = kind.npmPackageName else { return nil }
            let encodedPackage = package
                .replacingOccurrences(of: "@", with: "%40")
                .replacingOccurrences(of: "/", with: "%2F")
            guard let url = URL(string: "https://registry.npmjs.org/\(encodedPackage)/latest") else {
                return nil
            }
            var request = URLRequest(url: url)
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            request.timeoutInterval = 15
            do {
                let (data, response) = try await session.data(for: request)
                guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                    return nil
                }
                return try JSONDecoder().decode(NPMPackageMetadata.self, from: data).version
            } catch {
                return nil
            }
        }
    }

    public init(loadLatestVersion: @escaping LatestVersionLoader) {
        self.usesDefaultSession = false
        self.loadLatestVersion = loadLatestVersion
    }

    public func setNetworkProxyURL(_ value: String) {
        setNetworkProxy(url: value, enabled: true)
    }

    public func setNetworkProxy(url: String, enabled: Bool) {
        guard usesDefaultSession else { return }
        let session = URLSession(configuration: NetworkProxy.sessionConfiguration(from: url, enabled: enabled))
        loadLatestVersion = Self.makeLoader(session: session)
    }

    public func availableUpdates(for statuses: [AgentCLIStatus]) async -> [AIAgentCLIUpdate] {
        let statusesByKind = Dictionary(uniqueKeysWithValues: statuses.map { ($0.kind, $0) })
        var updates: [AIAgentCLIUpdate] = []

        await withTaskGroup(of: AIAgentCLIUpdate?.self) { group in
            for kind in AgentCLIKind.managedCases {
                guard kind.npmPackageName != nil,
                      let status = statusesByKind[kind],
                      status.executablePath != nil,
                      let installedVersion = status.version,
                      !Self.isHomebrewManaged(status)
                else { continue }
                group.addTask { [loadLatestVersion] in
                    guard let installed = Self.semanticVersion(in: installedVersion),
                          let latestVersion = await loadLatestVersion(kind),
                          let latest = Self.semanticVersion(in: latestVersion),
                          latest > installed
                    else { return nil }
                    return AIAgentCLIUpdate(
                        kind: kind,
                        installedVersion: installedVersion,
                        latestVersion: latestVersion
                    )
                }
            }
            for await update in group {
                if let update { updates.append(update) }
            }
        }

        return updates.sorted { AIAgentCLIService.cliKindOrder($0.kind, $1.kind) }
    }

    private static func isHomebrewManaged(_ status: AgentCLIStatus) -> Bool {
        guard let executablePath = status.executablePath else { return false }
        return AgentSkillPackageInstallation.detect(at: URL(fileURLWithPath: executablePath))?.manager == .brew
    }

    private static func semanticVersion(in rawValue: String) -> SemanticVersion? {
        let candidates = rawValue.split { character in
            !(character.isNumber || character == "." || character == "-" || character == "+" || character == "v")
        }
        return candidates.compactMap { try? SemanticVersion(String($0)) }.first
    }
}

private struct NPMPackageMetadata: Decodable {
    let version: String
}
