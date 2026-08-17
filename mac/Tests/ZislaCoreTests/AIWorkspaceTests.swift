import Testing

@testable import ZislaCore

struct AIEndpointTests {
    @Test
    func localEndpointDefaultsCoverOllamaAndLMStudio() {
        #expect(AIEndpointKind.ollama.defaultBaseURL == "http://127.0.0.1:11434/v1")
        #expect(AIEndpointKind.openAICompatible.defaultBaseURL == "http://127.0.0.1:1234/v1")
    }
}
