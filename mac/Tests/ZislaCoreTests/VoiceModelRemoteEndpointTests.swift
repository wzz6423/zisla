import Foundation
import Testing
@testable import ZislaCore

struct VoiceModelRemoteEndpointTests {
    @Test
    func loadBalancingRotatesEnabledEndpointsAndManualModeKeepsSelection() {
        let first = VoiceModelRemoteEndpoint(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
            name: "主服务",
            baseURL: "https://api.one.example/v1",
            modelName: "model-one"
        )
        let disabled = VoiceModelRemoteEndpoint(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!,
            name: "停用服务",
            baseURL: "https://api.disabled.example/v1",
            modelName: "model-disabled",
            isEnabled: false
        )
        let second = VoiceModelRemoteEndpoint(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000003")!,
            name: "备用服务",
            baseURL: "https://api.two.example/v1",
            modelName: "model-two"
        )
        let endpoints = [first, disabled, second]
        var router = VoiceModelEndpointRouter()

        #expect(router.next(
            from: endpoints,
            selectedID: second.id,
            loadBalancingEnabled: false
        )?.id == second.id)

        router.reset()
        #expect(router.next(
            from: endpoints,
            selectedID: second.id,
            loadBalancingEnabled: true
        )?.id == first.id)
        #expect(router.next(
            from: endpoints,
            selectedID: second.id,
            loadBalancingEnabled: true
        )?.id == second.id)
        #expect(router.next(
            from: endpoints,
            selectedID: second.id,
            loadBalancingEnabled: true
        )?.id == first.id)
    }

    @Test
    func legacySingleRemoteURLMigratesToEndpointGroup() throws {
        let data = Data(#"{"activityNoticeDisplayDuration":"threeSeconds","voiceModelRemoteBaseURL":"https://api.example.com/v1","voiceModelName":"qwen-plus"}"#.utf8)
        let settings = try JSONDecoder().decode(FeatureSettings.self, from: data)

        #expect(settings.voiceModelRemoteEndpoints.count == 1)
        #expect(settings.voiceModelSelectedRemoteEndpointID == settings.voiceModelRemoteEndpoints[0].id)
        #expect(settings.voiceModelRemoteEndpoints[0].baseURL == "https://api.example.com/v1")
        #expect(settings.voiceModelRemoteEndpoints[0].modelName == "qwen-plus")
        #expect(!settings.voiceModelRemoteLoadBalancingEnabled)
    }

    @Test
    func remoteEndpointGroupsAndAPIKeysRoundTripInSettings() throws {
        let endpoint = VoiceModelRemoteEndpoint(
            name: "推理服务",
            baseURL: "https://api.example.com/v1",
            modelName: "gpt-4.1-mini",
            apiKey: "sk-test"
        )
        var settings = FeatureSettings.default
        settings.voiceModelEndpointMode = .remote
        settings.voiceModelRemoteEndpoints = [endpoint]
        settings.voiceModelSelectedRemoteEndpointID = endpoint.id
        settings.voiceModelRemoteLoadBalancingEnabled = true

        let data = try JSONEncoder().encode(settings)
        let decoded = try JSONDecoder().decode(FeatureSettings.self, from: data)
        #expect(decoded.voiceModelRemoteEndpoints == [endpoint])
        #expect(decoded.voiceModelRemoteEndpoints[0].apiKey == "sk-test")
        #expect(decoded.voiceModelSelectedRemoteEndpointID == endpoint.id)
        #expect(decoded.voiceModelRemoteLoadBalancingEnabled)
    }

    @Test
    func existingRemoteEndpointWithoutAPIKeyRemainsReadable() throws {
        let data = Data(#"{"activityNoticeDisplayDuration":"threeSeconds","voiceModelRemoteEndpoints":[{"id":"00000000-0000-0000-0000-000000000001","name":"远端端点 1","baseURL":"https://api.example.com/v1","modelName":"gpt-4.1-mini","isEnabled":true}]}"#.utf8)

        let settings = try JSONDecoder().decode(FeatureSettings.self, from: data)

        #expect(settings.voiceModelRemoteEndpoints[0].apiKey == nil)
    }
}
