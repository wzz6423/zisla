import Testing

@testable import Zisla

struct SparkleUpdateConfigurationTests {
    @Test
    func acceptsHTTPSPrimaryAndFallbackFeedsWithEd25519PublicKey() throws {
        let configuration = try #require(SparkleUpdateConfiguration(infoDictionary: [
            "SUFeedURL": "https://gitee.example.com/release/appcast.xml",
            "ZislaReleaseFallbackAppcastURL": "https://github.example.com/release/appcast.xml",
            "ZislaPreviewAppcastURL": "https://gitee.example.com/preview/appcast.xml",
            "ZislaPreviewFallbackAppcastURL": "https://github.example.com/preview/appcast.xml",
            "SUPublicEDKey": "RTy+qQHkv0VMQ/6VS/D/oyzOdRmRld7+3nqUywhuqNI=",
        ]))

        #expect(configuration.feedURL(for: .release, source: .primary)?.absoluteString == "https://gitee.example.com/release/appcast.xml")
        #expect(configuration.feedURL(for: .release, source: .fallback)?.absoluteString == "https://github.example.com/release/appcast.xml")
        #expect(configuration.feedURL(for: .preview, source: .primary)?.absoluteString == "https://gitee.example.com/preview/appcast.xml")
        #expect(configuration.feedURL(for: .preview, source: .fallback)?.absoluteString == "https://github.example.com/preview/appcast.xml")
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
