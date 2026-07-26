import Foundation
import Testing
import ZislaCore
@testable import ZislaKit

struct VideoDownloadPlatformResolverTests {
    @Test
    func resolvesEachBundledPlatformFromItsPrimaryHost() {
        let cases: [(String, VideoDownloadPlatform)] = [
            ("https://www.youtube.com/watch?v=abc", .youtube),
            ("https://www.bilibili.com/video/BV1xx", .bilibili),
            ("https://www.douyin.com/video/123", .douyin),
            ("https://www.xiaohongshu.com/explore/abc", .xiaohongshu),
            ("https://weibo.com/tv/show/1034:abc", .weibo),
            ("https://www.tiktok.com/@user/video/123", .tiktok),
            ("https://www.instagram.com/reel/abc/", .instagram),
        ]
        for (urlString, expected) in cases {
            #expect(VideoDownloadPlatformResolver.platform(forURLString: urlString) == expected)
        }
    }

    @Test
    func resolvesShortLinkDomains() {
        #expect(VideoDownloadPlatformResolver.platform(forURLString: "https://youtu.be/abc") == .youtube)
        #expect(VideoDownloadPlatformResolver.platform(forURLString: "https://b23.tv/abc") == .bilibili)
        #expect(VideoDownloadPlatformResolver.platform(forURLString: "https://xhslink.com/abc") == .xiaohongshu)
        #expect(VideoDownloadPlatformResolver.platform(forURLString: "https://t.cn/abc") == .weibo)
        #expect(VideoDownloadPlatformResolver.platform(forURLString: "https://vt.tiktok.com/abc") == .tiktok)
    }

    @Test
    func resolvesSubdomainsOfKnownHosts() {
        #expect(VideoDownloadPlatformResolver.platform(forURLString: "https://m.bilibili.com/video/BV1") == .bilibili)
        #expect(VideoDownloadPlatformResolver.platform(forURLString: "https://music.youtube.com/watch?v=a") == .youtube)
    }

    /// Suffix matching must use a dot boundary, or `notyoutube.com` would false-match.
    @Test
    func doesNotMatchHostThatMerelyEndsWithBrandText() {
        #expect(VideoDownloadPlatformResolver.platform(forURLString: "https://notyoutube.com/x") == nil)
        #expect(VideoDownloadPlatformResolver.platform(forURLString: "https://evil-tiktok.com/x") == nil)
    }

    @Test
    func longTailHostFallsBackToBareHost() {
        #expect(VideoDownloadPlatformResolver.platform(forURLString: "https://v.qq.com/x/cover/a") == nil)
        #expect(VideoDownloadPlatformResolver.bareHost(ofURLString: "https://v.qq.com/x/cover/a") == "v.qq.com")
        #expect(VideoDownloadPlatformResolver.displayName(forURLString: "https://v.qq.com/x/a") == "v.qq.com")
    }

    @Test
    func bareHostStripsWWWAndLowercases() {
        #expect(VideoDownloadPlatformResolver.bareHost(ofURLString: "https://WWW.Youku.com/v") == "youku.com")
    }

    @Test
    func bareHostIsNilForNonURLText() {
        #expect(VideoDownloadPlatformResolver.bareHost(ofURLString: "") == nil)
        #expect(VideoDownloadPlatformResolver.bareHost(ofURLString: "not a url") == nil)
    }

    @Test
    func displayNameUsesPlatformNameWhenRecognized() {
        #expect(VideoDownloadPlatformResolver.displayName(forURLString: "https://b23.tv/x") == "哔哩哔哩")
    }

    /// Every built-in platform must have a unique bundled asset name.
    @Test
    func everyPlatformHasUniqueAssetName() {
        let names = VideoDownloadPlatform.allCases.map(\.assetName)
        #expect(names.allSatisfy { $0.hasSuffix(".svg") })
        #expect(Set(names).count == names.count)
    }

    /// The upstream icon library does not include Douyin, so its bundledIconURL must be nil for the site's own favicon fallback to kick in;
    /// every other platform must have a bundled logo, otherwise each download would incur three extra network requests.
    @Test
    func bundledIconExistsForEveryPlatformExceptDouyin() {
        for platform in VideoDownloadPlatform.allCases {
            let url = platform.bundledIconURL
            if platform == .douyin {
                #expect(url == nil, "抖音应无随包 logo，改由运行时 favicon 提供")
            } else {
                #expect(url != nil, "\(platform.rawValue) 缺少随包 logo：\(platform.assetName)")
            }
        }
    }

    /// Each platform's first host is the fetch target for the favicon fallback, so it must be a real, resolvable domain.
    @Test
    func douyinPrimaryHostIsUsableForFaviconFallback() {
        #expect(VideoDownloadPlatform.douyin.hosts.first == "douyin.com")
        #expect(
            VideoDownloadPlatformResolver.bareHost(ofURLString: "https://www.douyin.com/video/1")
                == "douyin.com"
        )
    }
}

struct VideoDownloadSnapshotTests {
    @Test
    func progressCapsAtNinetyNineWhileDownloading() {
        let snapshot = VideoDownloadSnapshot(
            platform: .youtube,
            host: "youtube.com",
            sourceName: "YouTube",
            fraction: 0.999,
            isFinished: false
        )
        #expect(snapshot.progressText == "99%")
    }

    @Test
    func finishedSnapshotReportsFullProgress() {
        let snapshot = VideoDownloadSnapshot(
            platform: .youtube,
            host: "youtube.com",
            sourceName: "YouTube",
            fraction: 1,
            isFinished: true
        )
        #expect(snapshot.progressText == "100%")
    }

    @Test
    func missingFractionShowsEllipsisWhileRunning() {
        let snapshot = VideoDownloadSnapshot(
            platform: nil,
            host: "v.qq.com",
            sourceName: "v.qq.com",
            fraction: nil,
            isFinished: false
        )
        #expect(snapshot.progressText == "…")
    }

    @Test
    func fractionIsClampedIntoUnitRange() {
        let low = VideoDownloadSnapshot(
            platform: nil, host: "a.com", sourceName: "a.com", fraction: -3, isFinished: false
        )
        let high = VideoDownloadSnapshot(
            platform: nil, host: "a.com", sourceName: "a.com", fraction: 4, isFinished: false
        )
        #expect(low.fraction == 0)
        #expect(high.fraction == 1)
    }
}
