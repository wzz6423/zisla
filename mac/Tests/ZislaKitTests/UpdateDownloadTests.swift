import Foundation
import ZislaCore
import Testing

@testable import ZislaKit

struct UpdateDownloadTests {
    @Test
    func dmgAssetIsExtractedCorrectly() throws {
        let release = try JSONDecoder().decode(
            GitHubRelease.self,
            from: Data(
                """
                {
                    "tag_name": "v1.2.0",
                    "html_url": "https://github.com/wzz6423/zisla/releases/tag/v1.2.0",
                    "draft": false,
                    "prerelease": false,
                    "assets": [
                        {
                            "name": "zisla-v1.2.0-macOS-universal.zip",
                            "browser_download_url": "https://example.com/zisla.zip",
                            "size": 10485760
                        },
                        {
                            "name": "zisla-v1.2.0-macOS-universal.dmg",
                            "browser_download_url": "https://example.com/zisla.dmg",
                            "size": 20971520
                        }
                    ]
                }
                """.utf8
            )
        )

        #expect(release.macDiskImage != nil)
        #expect(release.macDiskImage?.name == "zisla-v1.2.0-macOS-universal.dmg")
        #expect(release.macDiskImage?.downloadURL.absoluteString == "https://example.com/zisla.dmg")
        #expect(release.macDiskImage?.size == 20971520)
    }

    @Test
    func dmgAssetIsNilWhenNotPresent() throws {
        let release = try JSONDecoder().decode(
            GitHubRelease.self,
            from: Data(
                """
                {
                    "tag_name": "v1.2.0",
                    "html_url": "https://github.com/wzz6423/zisla/releases/tag/v1.2.0",
                    "draft": false,
                    "prerelease": false,
                    "assets": [
                        {
                            "name": "zisla-v1.2.0-macOS-universal.zip",
                            "browser_download_url": "https://example.com/zisla.zip",
                            "size": 10485760
                        }
                    ]
                }
                """.utf8
            )
        )

        #expect(release.macDiskImage == nil)
    }

    @Test
    func dmgPrefersLowercaseMatching() throws {
        let release = try JSONDecoder().decode(
            GitHubRelease.self,
            from: Data(
                """
                {
                    "tag_name": "v1.2.0",
                    "html_url": "https://github.com/wzz6423/zisla/releases/tag/v1.2.0",
                    "draft": false,
                    "prerelease": false,
                    "assets": [
                        {
                            "name": "Zisla-macOS.DMG",
                            "browser_download_url": "https://example.com/zisla-upper.dmg",
                            "size": 10485760
                        },
                        {
                            "name": "zisla-macOS-universal.dmg",
                            "browser_download_url": "https://example.com/zisla-lower.dmg",
                            "size": 20971520
                        }
                    ]
                }
                """.utf8
            )
        )

        #expect(release.macDiskImage?.name == "Zisla-macOS.DMG")
    }

    @Test
    func updateChannelHasCorrectDetails() {
        #expect(UpdateChannel.release.menuTitle == "Release")
        #expect(UpdateChannel.preview.menuTitle == "Preview")
        #expect(UpdateChannel.release.detail.contains("正式发布"))
        #expect(UpdateChannel.preview.detail.contains("预览"))
    }
}
