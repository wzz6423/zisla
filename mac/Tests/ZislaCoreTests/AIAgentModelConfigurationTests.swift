import Foundation
import Testing
@testable import ZislaCore

struct AIAgentModelConfigurationTests {
    @Test(arguments: [false, true])
    func localThinkingPreferenceRoundTrips(thinkingEnabled: Bool) throws {
        let model = AIAgentLocalModel(
            name: "Ollama",
            endpoint: AIEndpoint(name: "Ollama", baseURL: AIEndpointKind.ollama.defaultBaseURL, kind: .ollama),
            modelName: "qwen3.5:4b"
        )
        #expect(!model.thinkingEnabled)
        var configuration = try #require(try JSONSerialization.jsonObject(with: JSONEncoder().encode(model)) as? [String: Any])
        configuration["thinkingEnabled"] = thinkingEnabled
        let decoded = try JSONDecoder().decode(
            AIAgentLocalModel.self,
            from: JSONSerialization.data(withJSONObject: configuration)
        )
        let persisted = try #require(try JSONSerialization.jsonObject(with: JSONEncoder().encode(decoded)) as? [String: Any])
        #expect(decoded.thinkingEnabled == thinkingEnabled)
        #expect(persisted["thinkingEnabled"] as? Bool == thinkingEnabled, "Each local configuration must retain its thinking preference")
    }

    @Test(arguments: ["null", "\"true\"", "1", "[]", "{}"])
    func thinkingPreferenceValidatesItsPersistedType(value: String) throws {
        let model = AIAgentLocalModel(
            name: "LM Studio",
            endpoint: AIEndpoint(name: "LM Studio", baseURL: AIEndpointKind.openAICompatible.defaultBaseURL),
            modelName: "",
            thinkingEnabled: true
        )
        var configuration = try #require(try JSONSerialization.jsonObject(with: JSONEncoder().encode(model)) as? [String: Any])
        configuration["thinkingEnabled"] = try JSONSerialization.jsonObject(with: Data(value.utf8), options: .fragmentsAllowed)
        let data = try JSONSerialization.data(withJSONObject: configuration)
        if value == "null" {
            let decoded = try JSONDecoder().decode(AIAgentLocalModel.self, from: data)
            #expect(!decoded.thinkingEnabled)
            #expect(decoded.id == model.id)
            #expect(decoded.endpoint == model.endpoint)
        } else {
            #expect(throws: DecodingError.self) {
                try JSONDecoder().decode(AIAgentLocalModel.self, from: data)
            }
        }
    }

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
        #expect(!model.thinkingEnabled)
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
                modelName: "chosen-model",
                thinkingEnabled: true
            )
            let selected: AIEndpointKind = kind == .ollama ? .openAICompatible : .ollama
            model.selectEndpointKind(selected)
            #expect(model.endpoint.kind == selected)
            #expect(model.endpoint.baseURL == selected.defaultBaseURL)
            #expect(model.endpoint.name == selected.defaultEndpointName)
            #expect(model.name == selected.defaultEndpointName)
            #expect(model.modelName == "chosen-model")
            #expect(model.thinkingEnabled)
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
