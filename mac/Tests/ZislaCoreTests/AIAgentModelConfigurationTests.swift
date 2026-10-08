import Foundation
import Testing
@testable import ZislaCore

struct AIAgentModelConfigurationTests {
    @Test
    func legacyLocalConfigurationKeepsItsEndpointAndModel() throws {
        let identifier = "1F9AB50C-5F4F-456A-9E61-6198B5DA017E"
        let data = Data("""
        {"id":"\(identifier)","name":"qwen3:8b","modelName":"qwen3:8b","isEnabled":true,
         "endpoint":{"id":"\(identifier)","name":"Ollama / LM Studio","baseURL":"http://127.0.0.1:11434/v1",
                     "kind":"openAICompatible","isEnabled":true}}
        """.utf8)

        let model = try JSONDecoder().decode(AIAgentLocalModel.self, from: data)
        #expect(model.endpoint.kind == .openAICompatible)
        #expect(model.endpoint.baseURL == "http://127.0.0.1:11434/v1")
        #expect(model.modelName == "qwen3:8b")
        #expect(model.secretReference == "local-model.\(identifier)")
        let encoded = try JSONEncoder().encode(model)
        #expect(try JSONDecoder().decode(AIAgentLocalModel.self, from: encoded) == model)
        #expect(!String(decoding: encoded, as: UTF8.self).contains("secret"))
    }

    @Test(arguments: AIEndpointKind.allCases)
    func serviceSelectionUpdatesDefaultAndEmptyURLs(kind: AIEndpointKind) {
        for source in [kind.defaultBaseURL, "  \n"] {
            var model = AIAgentLocalModel(
                name: kind.defaultEndpointName,
                endpoint: AIEndpoint(name: kind.defaultEndpointName, baseURL: source, kind: kind),
                modelName: "chosen-model"
            )
            let selected: AIEndpointKind = kind == .ollama ? .openAICompatible : .ollama
            model.selectEndpointKind(selected)
            #expect(model.endpoint.kind == selected)
            #expect(model.endpoint.baseURL == selected.defaultBaseURL)
            #expect(model.endpoint.name == selected.defaultEndpointName)
            #expect(model.name == selected.defaultEndpointName)
            #expect(model.modelName == "chosen-model")
        }
    }

    @Test
    func serviceSelectionPreservesCustomURLAndIdentity() {
        var model = AIAgentLocalModel(
            name: "custom",
            endpoint: AIEndpoint(name: "custom", baseURL: "https://models.example/custom/v1", kind: .ollama),
            modelName: "custom-model"
        )
        let original = model
        model.selectEndpointKind(.openAICompatible)
        #expect(model.endpoint.baseURL == original.endpoint.baseURL)
        #expect(model.id == original.id)
        #expect(model.endpoint.id == original.endpoint.id)
        #expect(model.secretReference == original.secretReference)
    }

    @Test
    func voiceModelConfigurationReferenceRoundTripsInSettings() throws {
        let reference = AIModelConfigurationReference.channel(UUID())
        var settings = FeatureSettings.default
        settings.voiceModelConfiguration = reference

        let decoded = try JSONDecoder().decode(
            FeatureSettings.self,
            from: JSONEncoder().encode(settings)
        )

        #expect(decoded.voiceModelConfiguration == reference)
    }
}
