import Foundation
import ZislaCore

public enum ReleaseCheckResult: Equatable, Sendable {
    case upToDate
    case updateAvailable(GitHubRelease, source: ReleaseSource)
}

public enum ReleaseSource: Equatable, Sendable {
    case gitee
    case github

    public var displayName: String {
        switch self {
        case .gitee: "Gitee"
        case .github: "GitHub"
        }
    }
}

public enum GitHubReleaseServiceError: Error, LocalizedError, Sendable {
    case invalidCurrentVersion
    case invalidResponse
    case responseTooLarge
    case invalidReleaseVersion

    public var errorDescription: String? {
        switch self {
        case .invalidCurrentVersion: "当前应用版本无效"
        case .invalidResponse: "更新服务返回了无效响应"
        case .responseTooLarge: "更新服务响应超过大小限制"
        case .invalidReleaseVersion: "Release 版本号无效"
        }
    }
}

public actor GitHubReleaseService {
    public static let latestGiteeReleaseURL = URL(
        string: "https://gitee.com/api/v5/repos/wzz6423/zisla/releases/latest"
    )!
    public static let latestReleaseURL = URL(
        string: "https://api.github.com/repos/wzz6423/zisla/releases/latest"
    )!
    public static let giteeReleasesURL = URL(
        string: "https://gitee.com/api/v5/repos/wzz6423/zisla/releases?per_page=100"
    )!
    public static let githubReleasesURL = URL(
        string: "https://api.github.com/repos/wzz6423/zisla/releases?per_page=100"
    )!
    public typealias ReleaseDataLoader = @Sendable (URLRequest) async throws -> (Data, HTTPURLResponse)

    private enum SourceCheckResult {
        case upToDate
        case updateAvailable(GitHubRelease)
    }

    private let loadData: ReleaseDataLoader

    public init(session: URLSession? = nil) {
        let activeSession: URLSession
        if let session {
            activeSession = session
        } else {
            let configuration = URLSessionConfiguration.ephemeral
            configuration.timeoutIntervalForRequest = 15
            configuration.timeoutIntervalForResource = 25
            configuration.requestCachePolicy = .reloadRevalidatingCacheData
            activeSession = URLSession(configuration: configuration)
        }
        self.loadData = { request in
            let (data, response) = try await activeSession.data(for: request)
            guard let response = response as? HTTPURLResponse else {
                throw GitHubReleaseServiceError.invalidResponse
            }
            return (data, response)
        }
    }

    public init(loadData: @escaping ReleaseDataLoader) {
        self.loadData = loadData
    }

    public func check(
        currentVersion: String,
        channel: UpdateChannel = .release
    ) async throws -> ReleaseCheckResult {
        let current: SemanticVersion
        do {
            current = try SemanticVersion(currentVersion)
        } catch {
            throw GitHubReleaseServiceError.invalidCurrentVersion
        }

        let giteeResult = try? await checkLatestRelease(
            source: .gitee,
            currentVersion: current,
            currentVersionText: currentVersion,
            channel: channel
        )
        if case let .updateAvailable(release)? = giteeResult {
            return .updateAvailable(release, source: .gitee)
        }

        do {
            let githubResult = try await checkLatestRelease(
                source: .github,
                currentVersion: current,
                currentVersionText: currentVersion,
                channel: channel
            )
            switch githubResult {
            case .upToDate:
                return .upToDate
            case .updateAvailable(let release):
                return .updateAvailable(release, source: .github)
            }
        } catch {
            if case .upToDate? = giteeResult {
                return .upToDate
            }
            throw error
        }
    }

    private func checkLatestRelease(
        source: ReleaseSource,
        currentVersion: SemanticVersion,
        currentVersionText: String,
        channel: UpdateChannel
    ) async throws -> SourceCheckResult {
        let url: URL
        switch (source, channel) {
        case (.gitee, .release): url = Self.latestGiteeReleaseURL
        case (.github, .release): url = Self.latestReleaseURL
        case (.gitee, .preview): url = Self.giteeReleasesURL
        case (.github, .preview): url = Self.githubReleasesURL
        }
        var request = URLRequest(url: url)
        request.setValue("zisla/\(currentVersionText)", forHTTPHeaderField: "User-Agent")
        switch source {
        case .gitee:
            request.setValue("application/json", forHTTPHeaderField: "Accept")
        case .github:
            request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
            request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        }

        let (data, response) = try await loadData(request)
        guard data.count <= 1_048_576 else { throw GitHubReleaseServiceError.responseTooLarge }
        guard response.statusCode == 200 else {
            throw GitHubReleaseServiceError.invalidResponse
        }

        if channel == .preview {
            let releases = try JSONDecoder().decode([GitHubRelease].self, from: data)
            guard let release = latestPreviewRelease(in: releases) else { return .upToDate }
            guard let version = release.parsedVersion else {
                return .upToDate
            }
            return version > currentVersion ? .updateAvailable(release) : .upToDate
        }

        let release = try JSONDecoder().decode(GitHubRelease.self, from: data)
        guard !release.draft, !release.prerelease else { return .upToDate }
        guard let version = release.parsedVersion else {
            throw GitHubReleaseServiceError.invalidReleaseVersion
        }
        return version > currentVersion ? .updateAvailable(release) : .upToDate
    }

    private func latestPreviewRelease(in releases: [GitHubRelease]) -> GitHubRelease? {
        releases
            .filter { !$0.draft && $0.prerelease }
            .compactMap { release -> (release: GitHubRelease, version: SemanticVersion)? in
                guard let version = release.parsedVersion else { return nil }
                return (release, version)
            }
            .max { $0.version < $1.version }?
            .release
    }
}
