import Foundation
import Testing

@testable import ZislaCore

struct MediaVisualizationStyleTests {
    @Test
    func defaultAndLegacySettingsKeepWaveform() throws {
        #expect(FeatureSettings.default.mediaVisualizationStyle == .waveform)
        for payload in ["{}", #"{"mediaVisualizationStyle":null}"#, #"{"mediaCompactStyle":"detailed"}"#] {
            let settings = try JSONDecoder().decode(FeatureSettings.self, from: Data(payload.utf8))
            #expect(settings.mediaVisualizationStyle == .waveform)
        }
    }

    @Test(arguments: MediaVisualizationStyle.allCases)
    func selectionSurvivesRestartWithoutChangingOtherMediaSettings(style: MediaVisualizationStyle) throws {
        var settings = FeatureSettings.default
        settings.mediaVisualizationStyle = style
        settings.mediaCompactStyle = .detailed
        settings.mediaShowLyricsAndInfo = false

        let restored = try JSONDecoder().decode(FeatureSettings.self, from: JSONEncoder().encode(settings))

        #expect(restored.mediaVisualizationStyle == style)
        #expect(restored.mediaCompactStyle == .detailed)
        #expect(!restored.mediaShowLyricsAndInfo)
    }

    @Test(arguments: [#""pulse""#, "1", "true", "{}", "[]"])
    func invalidVisualizationSettingsAreRejected(value: String) {
        let payload = "{\"mediaVisualizationStyle\":\(value)}"
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(FeatureSettings.self, from: Data(payload.utf8))
        }
    }

    @Test
    func styleNamesAndOrderRemainStable() {
        #expect(MediaVisualizationStyle.allCases == [.waveform, .glow])
        #expect(MediaVisualizationStyle.waveform.rawValue == "waveform")
        #expect(MediaVisualizationStyle.glow.rawValue == "glow")
        #expect(MediaVisualizationStyle.waveform.title == "音浪模式")
        #expect(MediaVisualizationStyle.glow.title == "光晕模式")
    }
}
