import Foundation
import ZislaCore
import Testing

@testable import ZislaKit

struct GitHubReleaseServiceTests {
    @Test
    func giteeUpdateTakesPriorityOverGitHub() async throws {
        let stub = ReleaseRequestStub(responses: [
            GitHubReleaseService.latestGiteeReleaseURL: .success(Self.release(tag: "v1.2.0")),
            GitHubReleaseService.latestReleaseURL: .success(Self.release(tag: "v1.3.0")),
        ])
        let service = GitHubReleaseService(loadData: { request in
            try await stub.load(request)
        })

        let result = try await service.check(currentVersion: "1.0.0")

        #expect(result == .updateAvailable(Self.decodedRelease(tag: "v1.2.0"), source: .gitee))
        #expect(await stub.requestedURLs() == [GitHubReleaseService.latestGiteeReleaseURL])
    }

    @Test
    func githubUpdateIsUsedWhenGiteeIsCurrent() async throws {
        let stub = ReleaseRequestStub(responses: [
            GitHubReleaseService.latestGiteeReleaseURL: .success(Self.release(tag: "v1.0.0")),
            GitHubReleaseService.latestReleaseURL: .success(Self.release(tag: "v1.1.0")),
        ])
        let service = GitHubReleaseService(loadData: { request in
            try await stub.load(request)
        })

        let result = try await service.check(currentVersion: "1.0.0")

        #expect(result == .updateAvailable(Self.decodedRelease(tag: "v1.1.0"), source: .github))
        #expect(await stub.requestedURLs() == [
            GitHubReleaseService.latestGiteeReleaseURL,
            GitHubReleaseService.latestReleaseURL,
        ])
    }

    @Test
    func githubIsUsedWhenGiteeReleaseEndpointIsUnavailable() async throws {
        let stub = ReleaseRequestStub(responses: [
            GitHubReleaseService.latestGiteeReleaseURL: .status(404),
            GitHubReleaseService.latestReleaseURL: .success(Self.release(tag: "v1.1.0")),
        ])
        let service = GitHubReleaseService(loadData: { request in
            try await stub.load(request)
        })

        let result = try await service.check(currentVersion: "1.0.0")

        #expect(result == .updateAvailable(Self.decodedRelease(tag: "v1.1.0"), source: .github))
    }

    @Test
    func giteeReleaseWithoutGitHubOnlyFieldsStillDetectsUpdate() async throws {
        let giteeRelease = Data(
            #"{"tag_name":"v1.1.0","html_url":"https://gitee.com/wzz6423/zisla/releases/tag/v1.1.0"}"#.utf8
        )
        let stub = ReleaseRequestStub(responses: [
            GitHubReleaseService.latestGiteeReleaseURL: .success(giteeRelease),
        ])
        let service = GitHubReleaseService(loadData: { request in
            try await stub.load(request)
        })

        let result = try await service.check(currentVersion: "1.0.0")

        switch result {
        case .updateAvailable(let release, .gitee):
            #expect(release.tagName == "v1.1.0")
            #expect(!release.draft)
            #expect(release.assets.isEmpty)
        default:
            Issue.record("应使用缺少 GitHub 专有字段的 Gitee Release")
        }
    }

    @Test
    func previewChannelAcceptsGiteeAssetsWithoutPageURLOrSize() async throws {
        let giteeReleases = Data(
            """
            [{"tag_name":"v1.1.0-preview.1","html_url":null,"draft":false,"prerelease":true,"assets":[
              {"name":"zisla-v1.1.0-preview.1-macOS-universal.zip","browser_download_url":"https://gitee.com/wzz6423/zisla/releases/download/v1.1.0-preview.1/zisla.zip"}
            ]}]
            """.utf8
        )
        let stub = ReleaseRequestStub(responses: [
            GitHubReleaseService.giteeReleasesURL: .success(giteeReleases),
        ])
        let service = GitHubReleaseService(loadData: { request in
            try await stub.load(request)
        })

        let result = try await service.check(currentVersion: "1.0.0", channel: .preview)

        switch result {
        case .updateAvailable(let release, .gitee):
            #expect(release.htmlURL == nil)
            #expect(release.assets.first?.size == 0)
            #expect(release.macUpdateAssets?.archive.downloadURL.absoluteString == "https://gitee.com/wzz6423/zisla/releases/download/v1.1.0-preview.1/zisla.zip")
        default:
            Issue.record("Preview 应识别 Gitee 的简化 Release 响应")
        }
    }

    @Test
    func previewChannelFallsBackToGitHubReleaseList() async throws {
        let githubReleases = Data(
            """
            [
              {"tag_name":"preview","html_url":"https://github.com/wzz6423/zisla/releases/tag/preview","draft":false,"prerelease":true,"assets":[]},
              {"tag_name":"v1.2.0-preview.1","html_url":"https://github.com/wzz6423/zisla/releases/tag/v1.2.0-preview.1","draft":false,"prerelease":true,"assets":[]}
            ]
            """.utf8
        )
        let stub = ReleaseRequestStub(responses: [
            GitHubReleaseService.giteeReleasesURL: .status(503),
            GitHubReleaseService.githubReleasesURL: .success(githubReleases),
        ])
        let service = GitHubReleaseService(loadData: { request in
            try await stub.load(request)
        })

        let result = try await service.check(currentVersion: "1.0.0", channel: .preview)

        switch result {
        case .updateAvailable(let release, .github):
            #expect(release.tagName == "v1.2.0-preview.1")
            #expect(release.prerelease)
        default:
            Issue.record("Preview 应在 Gitee 不可用时从 GitHub 发布列表选择最新预览版本")
        }
        #expect(await stub.requestedURLs() == [
            GitHubReleaseService.giteeReleasesURL,
            GitHubReleaseService.githubReleasesURL,
        ])
    }

    private static func release(tag: String) -> Data {
        Data(
            """
            {"tag_name":"\(tag)","html_url":"https://example.com/releases/tag/\(tag)","draft":false,"prerelease":false,"assets":[]}
            """.utf8
        )
    }

    private static func decodedRelease(tag: String) -> GitHubRelease {
        try! JSONDecoder().decode(GitHubRelease.self, from: Self.release(tag: tag))
    }
}

private actor ReleaseRequestStub {
    enum Response: Sendable {
        case success(Data)
        case status(Int)
    }

    private let responses: [URL: Response]
    private var requests: [URL] = []

    init(responses: [URL: Response]) {
        self.responses = responses
    }

    func load(_ request: URLRequest) throws -> (Data, HTTPURLResponse) {
        guard let url = request.url, let response = responses[url] else {
            throw StubError.missingResponse
        }
        requests.append(url)
        switch response {
        case .success(let data):
            return (data, httpResponse(url: url, statusCode: 200))
        case .status(let statusCode):
            return (Data(), httpResponse(url: url, statusCode: statusCode))
        }
    }

    func requestedURLs() -> [URL] {
        requests
    }
}

private enum StubError: Error {
    case missingResponse
}

private func httpResponse(url: URL, statusCode: Int) -> HTTPURLResponse {
    HTTPURLResponse(url: url, statusCode: statusCode, httpVersion: nil, headerFields: nil)!
}
