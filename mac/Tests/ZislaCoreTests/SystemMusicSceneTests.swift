import Foundation
import Testing
@testable import ZislaCore

struct SystemMusicSceneTests {
    @Test
    func scenesExposeExpectedTitlesAndSearchTerms() {
        let scenes = SystemMusicScene.allCases

        #expect(scenes == [.sleep, .focus, .relax, .balance])
        #expect(scenes.map(\.title) == ["安睡助眠", "提升效率", "放松减压", "平衡身心"])
        #expect(scenes.map(\.searchTerm) == ["睡眠音乐", "专注音乐", "放松音乐", "冥想音乐"])
    }

    @Test
    func scenesBuildMusicSearchURLs() throws {
        for scene in SystemMusicScene.allCases {
            let url = try #require(scene.searchURL)
            let components = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))

            #expect(components.scheme == "music")
            #expect(components.host == "music.apple.com")
            #expect(components.path == "/search")
            #expect(components.queryItems?.first?.name == "term")
            #expect(components.queryItems?.first?.value == scene.searchTerm)
        }
    }
}
