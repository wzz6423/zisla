import Foundation
import Testing
@testable import ZislaCore

struct AIModelRecommendationTests {
    @Test
    func memoryTierSelectsModelsThatFitTheMachineClass() {
        let gibibyte = UInt64(1 << 30)
        let entry = AIHardwareProfile(machineName: "轻量 Mac", memoryBytes: 16 * gibibyte)
        let highPerformance = AIHardwareProfile(machineName: "高配 Mac", memoryBytes: 48 * gibibyte)

        #expect(entry.tier == .entry)
        #expect(highPerformance.tier == .highPerformance)
        #expect(AIModelRecommendations.recommended(for: entry).contains {
            $0.ollamaModelName == "qwen3:4b"
        })
        #expect(AIModelRecommendations.recommended(for: entry).contains {
            $0.ollamaModelName == "qwen3:32b"
        } == false)
        #expect(AIModelRecommendations.recommended(for: highPerformance).contains {
            $0.ollamaModelName == "qwen3:32b"
        })
    }

    @Test
    func localEndpointDefaultsCoverOllamaAndLMStudio() {
        #expect(AIEndpointKind.ollama.defaultBaseURL == "http://127.0.0.1:11434/v1")
        #expect(AIEndpointKind.openAICompatible.defaultBaseURL == "http://127.0.0.1:1234/v1")
    }
}
