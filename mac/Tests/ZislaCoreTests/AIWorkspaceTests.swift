import Foundation
import Testing
@testable import ZislaCore

struct AIModelRecommendationTests {
    @Test
    func hardwareTierSelectsModelsThatFitTheMachineClass() {
        let gibibyte = UInt64(1 << 30)
        let entry = AIHardwareProfile(
            machineName: "轻量 Mac", memoryBytes: 16 * gibibyte,
            cpuCoreCount: 8, gpuCoreCount: 8
        )
        let highPerformance = AIHardwareProfile(
            machineName: "高配 Mac", memoryBytes: 48 * gibibyte,
            cpuCoreCount: 12, gpuCoreCount: 16
        )
        let memoryRichButWeakCompute = AIHardwareProfile(
            machineName: "高内存低算力 Mac", memoryBytes: 48 * gibibyte,
            cpuCoreCount: 4, gpuCoreCount: 4
        )

        #expect(entry.tier == .entry)
        #expect(highPerformance.tier == .highPerformance)
        #expect(memoryRichButWeakCompute.tier == .balanced)

        let entryModels = AIModelRecommendations.recommended(for: entry)
        #expect(entryModels.contains { $0.ollamaModelName.contains("qwen") || $0.ollamaModelName.contains("gemma") })
        #expect(entryModels.contains { $0.ollamaModelName.contains("whisper") } == false)

        let highPerfModels = AIModelRecommendations.recommended(for: highPerformance)
        #expect(highPerfModels.contains { $0.ollamaModelName.contains("qwen") || $0.ollamaModelName.contains("mistral") })
        #expect(highPerfModels.contains { $0.ollamaModelName.contains("whisper") } == false)

        let balancedModels = AIModelRecommendations.recommended(for: memoryRichButWeakCompute)
        #expect(balancedModels.contains { $0.ollamaModelName.contains("qwen") || $0.ollamaModelName.contains("gemma") })
    }

    @Test
    func recommendationsIncludeOllamaCommandsAndLMStudioSearch() {
        let gibibyte = UInt64(1 << 30)
        let profile = AIHardwareProfile(
            machineName: "测试 Mac", memoryBytes: 16 * gibibyte,
            cpuCoreCount: 8, gpuCoreCount: 8
        )
        let recommendations = AIModelRecommendations.recommended(for: profile)

        #expect(!recommendations.isEmpty)
        for rec in recommendations {
            #expect(rec.ollamaPullCommand.hasPrefix("ollama pull "))
            #expect(rec.ollamaPullCommand.contains(rec.ollamaModelName))
            #expect(rec.ollamaRunCommand.hasPrefix("ollama run "))
            #expect(rec.ollamaRunCommand.contains(rec.ollamaModelName))

            #expect(rec.lmStudioSearchQuery.contains("GGUF"))
        }
    }

    @Test
    func recommendationsSpanMultipleTiersAndProviders() {
        let gibibyte = UInt64(1 << 30)
        let profiles: [(AIHardwareProfile, AIHardwareTier)] = [
            (AIHardwareProfile(machineName: "轻量", memoryBytes: 16 * gibibyte, cpuCoreCount: 8, gpuCoreCount: 8), .entry),
            (AIHardwareProfile(machineName: "均衡", memoryBytes: 24 * gibibyte, cpuCoreCount: 8, gpuCoreCount: 10), .balanced),
            (AIHardwareProfile(machineName: "性能", memoryBytes: 36 * gibibyte, cpuCoreCount: 10, gpuCoreCount: 14), .performance),
            (AIHardwareProfile(machineName: "高配", memoryBytes: 64 * gibibyte, cpuCoreCount: 14, gpuCoreCount: 30), .highPerformance),
        ]

        for (profile, expectedTier) in profiles {
            #expect(profile.tier == expectedTier)
            let models = AIModelRecommendations.recommended(for: profile)
            #expect(!models.isEmpty)

            if expectedTier == .highPerformance {
                #expect(models.contains { $0.ollamaModelName == "qwen3:32b" })
                #expect(models.contains { $0.ollamaModelName == "gemma3:27b" })
                #expect(models.contains { $0.ollamaModelName == "mistral-small3.1:24b" })
            }
        }
    }

    @Test
    func hardwareProfileDisplaysCollectedCPUAndGPUDetails() {
        let profile = AIHardwareProfile(
            machineName: "MacBook Pro",
            memoryBytes: UInt64(48) << 30,
            cpuName: "Apple M5 Pro",
            cpuCoreCount: 15,
            cpuPerformanceCoreCount: 5,
            cpuEfficiencyCoreCount: 10,
            gpuName: "Apple M5 Pro",
            gpuCoreCount: 16
        )

        #expect(profile.cpuDescription == "Apple M5 Pro · 15 核（5 性能 + 10 能效）")
        #expect(profile.gpuDescription == "Apple M5 Pro · 16 核")
        #expect(profile.memoryDescription == "48GB 统一内存")
        #expect(profile.compactHardwareDescription.contains("MacBook Pro"))
        #expect(profile.compactHardwareDescription.contains("Apple M5 Pro"))
        #expect(profile.compactHardwareDescription.contains("CPU 15 核（5 性能 + 10 能效）"))
        #expect(profile.compactHardwareDescription.contains("GPU 16 核"))
        #expect(profile.compactHardwareDescription.contains("48GB 统一内存"))
    }

    @Test
    func recommendationDescriptionIncludesPreferredModelAndTier() {
        let profile = AIHardwareProfile(
            machineName: "MacBook Pro",
            memoryBytes: UInt64(48) << 30,
            cpuCoreCount: 15,
            gpuCoreCount: 16
        )
        let recommendations = AIModelRecommendations.recommended(for: profile)
        let preferredModel = recommendations.first

        #expect(preferredModel != nil)
        #expect(profile.recommendationDescription.contains(preferredModel?.name ?? ""))
        #expect(profile.recommendationDescription.contains(profile.tier.displayName))
        #expect(profile.recommendationDescription.contains("CPU、GPU 与统一内存"))
    }

    @Test
    func localEndpointDefaultsCoverOllamaAndLMStudio() {
        #expect(AIEndpointKind.ollama.defaultBaseURL == "http://127.0.0.1:11434/v1")
        #expect(AIEndpointKind.openAICompatible.defaultBaseURL == "http://127.0.0.1:1234/v1")
    }
}
