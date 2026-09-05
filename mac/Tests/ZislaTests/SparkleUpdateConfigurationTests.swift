import Foundation
import Testing

@testable import Zisla

struct SparkleUpdateConfigurationTests {
    @Test @MainActor
    func primaryFeedErrorIsAcknowledgedWithoutShowingWhenFallbackCanRetry() {
        let driver = SparkleStandardUserDriver(
            hostBundle: Bundle.main,
            shouldSuppressUpdaterError: { true }
        )
        var acknowledged = false

        driver.showUpdaterError(NSError(domain: "test", code: 1)) {
            acknowledged = true
        }

        #expect(acknowledged)
    }

    @Test(arguments: ["arm64", "x86_64"])
    func resolvesEveryFeedToTheArchitectureAppcast(architecture: String) throws {
        let configuration = try #require(SparkleUpdateConfiguration(
            infoDictionary: [
                "SUFeedURL": "https://gitee.example.com/release/appcast.xml",
                "ZislaReleaseFallbackAppcastURL": "https://github.example.com/release/appcast.xml",
                "ZislaPreviewAppcastURL": "https://gitee.example.com/preview/appcast.xml",
                "ZislaPreviewFallbackAppcastURL": "https://github.example.com/preview/appcast.xml",
                "SUPublicEDKey": "RTy+qQHkv0VMQ/6VS/D/oyzOdRmRld7+3nqUywhuqNI=",
            ],
            architecture: architecture,
            installedSliceCount: 1
        ))

        #expect(configuration.feedURL(for: .release, source: .primary)?.absoluteString == "https://gitee.example.com/release/appcast-\(architecture).xml")
        #expect(configuration.feedURL(for: .release, source: .fallback)?.absoluteString == "https://github.example.com/release/appcast-\(architecture).xml")
        #expect(configuration.feedURL(for: .preview, source: .primary)?.absoluteString == "https://gitee.example.com/preview/appcast-\(architecture).xml")
        #expect(configuration.feedURL(for: .preview, source: .fallback)?.absoluteString == "https://github.example.com/preview/appcast-\(architecture).xml")
    }

    // A universal install keeps the shared appcast on both channels, so an in-app update
    // cannot quietly replace it with a build that runs on only one architecture.
    @Test(arguments: ["arm64", "x86_64"])
    func keepsTheSharedAppcastForAUniversalInstall(architecture: String) throws {
        let configuration = try #require(SparkleUpdateConfiguration(
            infoDictionary: [
                "SUFeedURL": "https://gitee.example.com/release/appcast.xml",
                "ZislaReleaseFallbackAppcastURL": "https://github.example.com/release/appcast.xml",
                "ZislaPreviewAppcastURL": "https://gitee.example.com/preview/appcast.xml",
                "ZislaPreviewFallbackAppcastURL": "https://github.example.com/preview/appcast.xml",
                "SUPublicEDKey": "RTy+qQHkv0VMQ/6VS/D/oyzOdRmRld7+3nqUywhuqNI=",
            ],
            architecture: architecture,
            installedSliceCount: 2
        ))

        #expect(configuration.feedURL(for: .release, source: .primary)?.absoluteString == "https://gitee.example.com/release/appcast.xml")
        #expect(configuration.feedURL(for: .release, source: .fallback)?.absoluteString == "https://github.example.com/release/appcast.xml")
        #expect(configuration.feedURL(for: .preview, source: .primary)?.absoluteString == "https://gitee.example.com/preview/appcast.xml")
        #expect(configuration.feedURL(for: .preview, source: .fallback)?.absoluteString == "https://github.example.com/preview/appcast.xml")
    }

    // The default keeps this Mac on its own slice, so a single-architecture install is
    // never replaced by the universal build. The slice count is passed explicitly because
    // the default reads the test bundle's own architectures.
    @Test
    func defaultsToAnAppcastForTheHostArchitecture() throws {
        let configuration = try #require(SparkleUpdateConfiguration(
            infoDictionary: [
                "SUFeedURL": "https://gitee.example.com/release/appcast.xml",
                "ZislaReleaseFallbackAppcastURL": "https://github.example.com/release/appcast.xml",
                "ZislaPreviewAppcastURL": "https://gitee.example.com/preview/appcast.xml",
                "ZislaPreviewFallbackAppcastURL": "https://github.example.com/preview/appcast.xml",
                "SUPublicEDKey": "RTy+qQHkv0VMQ/6VS/D/oyzOdRmRld7+3nqUywhuqNI=",
            ],
            installedSliceCount: 1
        ))

        #expect(["arm64", "x86_64"].contains(SparkleUpdateConfiguration.hostArchitecture))
        #expect(SparkleUpdateConfiguration.installedSliceCount >= 1)
        #expect(
            configuration.feedURL(for: .release, source: .primary)?.lastPathComponent
                == "appcast-\(SparkleUpdateConfiguration.hostArchitecture).xml"
        )
    }

    @Test
    func rejectsUnsignedOrInsecureConfigurations() {
        #expect(SparkleUpdateConfiguration(infoDictionary: [
            "SUFeedURL": "http://updates.example.com/appcast.xml",
            "ZislaReleaseFallbackAppcastURL": "https://updates.example.com/release-fallback/appcast.xml",
            "ZislaPreviewAppcastURL": "https://updates.example.com/preview/appcast.xml",
            "ZislaPreviewFallbackAppcastURL": "https://updates.example.com/preview-fallback/appcast.xml",
            "SUPublicEDKey": "RTy+qQHkv0VMQ/6VS/D/oyzOdRmRld7+3nqUywhuqNI=",
        ]) == nil)
        #expect(SparkleUpdateConfiguration(infoDictionary: [
            "SUFeedURL": "https://updates.example.com/appcast.xml",
            "ZislaReleaseFallbackAppcastURL": "http://updates.example.com/release-fallback/appcast.xml",
            "ZislaPreviewAppcastURL": "http://updates.example.com/preview/appcast.xml",
            "ZislaPreviewFallbackAppcastURL": "https://updates.example.com/preview-fallback/appcast.xml",
            "SUPublicEDKey": "RTy+qQHkv0VMQ/6VS/D/oyzOdRmRld7+3nqUywhuqNI=",
        ]) == nil)
        #expect(SparkleUpdateConfiguration(infoDictionary: [
            "SUFeedURL": "https://updates.example.com/appcast.xml",
            "ZislaReleaseFallbackAppcastURL": "https://updates.example.com/release-fallback/appcast.xml",
            "ZislaPreviewAppcastURL": "https://updates.example.com/preview/appcast.xml",
            "ZislaPreviewFallbackAppcastURL": "https://updates.example.com/preview-fallback/appcast.xml",
            "SUPublicEDKey": "invalid",
        ]) == nil)
    }
}
