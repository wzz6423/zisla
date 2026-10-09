import Foundation
import Testing

@testable import ZislaCore
@testable import ZislaKit

struct AIMascotLibraryTests {
    @Test
    func desktopAgentIconsResolveKnownBundlesAndOfflineAssets() {
        let examples: [(AIProvider, String, String, String)] = [
            (.delta, "com.zed-industries.delta", "Delta", "delta.icns"),
            (.orca, "com.stablyai.orca", "Orca", "orca.icns"),
            (.workbuddy, "com.workbuddy.workbuddy", "WorkBuddy", "workbuddy.icns"),
            (.workbuddyAI, "com.workbuddy.workbuddy-ai", "WorkBuddy AI", "workbuddy-ai.icns"),
        ]
        // Fixture paths must not infer directoryness from applications installed on the host.
        let applications = URL(fileURLWithPath: "/fixture/Applications", isDirectory: true)
        for (provider, identifier, name, asset) in examples {
            let url = applications.appendingPathComponent("\(name).app", isDirectory: true)
            #expect(AIMascotLibrary.installedDesktopAgentApplicationURL(for: provider,
                resolveBundleIdentifier: { $0 == identifier ? url : nil },
                applicationDirectories: [], fileExists: { _ in false }) == url)
            #expect(AIMascotLibrary.installedDesktopAgentApplicationURL(for: provider,
                resolveBundleIdentifier: { _ in nil },
                applicationDirectories: [applications], fileExists: { $0 == url }) == url)
            #expect(AIMascotLibrary.providerAssetName(for: provider) == asset)
        }
    }

    @Test
    func workBuddyProductsKeepBrandsAndNoticeProvidersSeparate() {
        #expect(AIMascotLibrary.providerDisplayName(for: .workbuddy) == "WorkBuddy")
        #expect(AIMascotLibrary.providerDisplayName(for: .workbuddyAI) == "WorkBuddy AI")
        #expect(AIMascotLibrary.providerAssetName(for: .workbuddy) == "workbuddy.icns")
        #expect(AIMascotLibrary.providerAssetName(for: .workbuddyAI) == "workbuddy-ai.icns")
        #expect(AIMascotLibrary.provider(fromNoticeID: "ai-active-workbuddy-workbuddy-session-id") == .workbuddy)
        #expect(AIMascotLibrary.provider(fromNoticeID: "ai-active-workbuddy-ai-workbuddy-ai-session-id") == .workbuddyAI)
        #expect(AIMascotLibrary.uniqueProviders(fromNoticeIDs: [
            "ai-active-workbuddy-workbuddy-session-id",
            "ai-active-workbuddy-ai-workbuddy-ai-session-id",
        ]) == [.workbuddy, .workbuddyAI])
        let directory = URL(fileURLWithPath: "/fixture/Applications", isDirectory: true)
        let onlyWorkBuddy = directory.appendingPathComponent("WorkBuddy.app", isDirectory: true)
        let onlyAI = directory.appendingPathComponent("WorkBuddy AI.app", isDirectory: true)
        #expect(AIMascotLibrary.installedDesktopAgentApplicationURL(for: .workbuddyAI,
            resolveBundleIdentifier: { _ in nil }, applicationDirectories: [directory],
            fileExists: { $0 == onlyWorkBuddy }) == nil)
        #expect(AIMascotLibrary.installedDesktopAgentApplicationURL(for: .workbuddy,
            resolveBundleIdentifier: { _ in nil }, applicationDirectories: [directory],
            fileExists: { $0 == onlyAI }) == nil)
    }

    @Test
    func workBuddyNoticeBoundaryDoesNotConfuseManualTaskIDs() {
        for id in ["ai-job", "workbuddy-ai-session-example", "example:with:colon"] {
            let workBuddy = AIProgressTask(id: id, provider: .workbuddy, title: "task",
                progress: nil, updatedAt: .distantPast)
            let ai = AIProgressTask(id: id, provider: .workbuddyAI, title: "task",
                progress: nil, updatedAt: .distantPast)
            let workBuddyID = AIMascotLibrary.activeNoticeID(for: workBuddy)
            let aiID = AIMascotLibrary.activeNoticeID(for: ai)
            #expect(workBuddyID != aiID)
            #expect(AIMascotLibrary.provider(fromNoticeID: workBuddyID) == .workbuddy)
            #expect(AIMascotLibrary.provider(fromNoticeID: aiID) == .workbuddyAI)
        }
    }

    @Test
    func coderResolutionCandidatesCoverKnownQoderHosts() {
        #expect(AIMascotLibrary.coderBundleIdentifiers.first == "com.qoder.work.cn")
        #expect(
            Set(AIMascotLibrary.coderBundleIdentifiers).count
                == AIMascotLibrary.coderBundleIdentifiers.count
        )
        #expect(AIMascotLibrary.coderApplicationNames.contains("QoderWork CN"))
        #expect(AIMascotLibrary.coderApplicationNames.contains("Qoder"))
    }

    @Test
    func installedCoderURLPrefersBundleIdentifierInPriorityOrder() {
        let matched = URL(fileURLWithPath: "/Applications/QoderWork CN.app")
        let url = AIMascotLibrary.installedCoderApplicationURL(
            resolveBundleIdentifier: { $0 == "com.qoder.work.cn" ? matched : nil },
            applicationDirectories: [],
            fileExists: { _ in false }
        )
        #expect(url == matched)
    }

    @Test
    func installedCoderURLFallsBackToApplicationNameWhenBundleMissing() {
        let directory = URL(fileURLWithPath: "/Applications")
        let expected = directory.appendingPathComponent("QoderWork CN.app", isDirectory: true)
        let url = AIMascotLibrary.installedCoderApplicationURL(
            resolveBundleIdentifier: { _ in nil },
            applicationDirectories: [directory],
            fileExists: { $0 == expected }
        )
        #expect(url == expected)
    }

    @Test
    func installedCoderURLReturnsNilWhenNothingInstalled() {
        let url = AIMascotLibrary.installedCoderApplicationURL(
            resolveBundleIdentifier: { _ in nil },
            applicationDirectories: [URL(fileURLWithPath: "/Applications")],
            fileExists: { _ in false }
        )
        #expect(url == nil)
    }

    @Test
    func traeResolutionCandidatesCoverInstalledClient() {
        #expect(AIMascotLibrary.traeBundleIdentifiers == ["cn.trae.solo.app"])
        #expect(AIMascotLibrary.traeApplicationNames == ["TRAE SOLO CN"])
    }

    @Test
    func installedTraeURLPrefersBundleIdentifierThenApplicationName() {
        let bundleMatched = URL(fileURLWithPath: "/Applications/TRAE SOLO CN.app", isDirectory: true)
        let byBundleIdentifier = AIMascotLibrary.installedTraeApplicationURL(
            resolveBundleIdentifier: { $0 == "cn.trae.solo.app" ? bundleMatched : nil },
            applicationDirectories: [],
            fileExists: { _ in false }
        )
        #expect(byBundleIdentifier == bundleMatched)

        let directory = URL(fileURLWithPath: "/Applications")
        let byName = AIMascotLibrary.installedTraeApplicationURL(
            resolveBundleIdentifier: { _ in nil },
            applicationDirectories: [directory],
            fileExists: {
                $0 == directory.appendingPathComponent("TRAE SOLO CN.app", isDirectory: true)
            }
        )
        #expect(byName == bundleMatched)
    }

    @Test
    func installedZedURLPrefersBundleIdentifierThenApplicationName() {
        let bundleMatched = URL(fileURLWithPath: "/Applications/Zed.app", isDirectory: true)
        let byBundleIdentifier = AIMascotLibrary.installedZedApplicationURL(
            resolveBundleIdentifier: { $0 == "dev.zed.Zed" ? bundleMatched : nil },
            applicationDirectories: [],
            fileExists: { _ in false }
        )
        #expect(byBundleIdentifier == bundleMatched)

        let directory = URL(fileURLWithPath: "/Applications")
        let byName = AIMascotLibrary.installedZedApplicationURL(
            resolveBundleIdentifier: { _ in nil },
            applicationDirectories: [directory],
            fileExists: {
                $0 == directory.appendingPathComponent("Zed.app", isDirectory: true)
            }
        )
        #expect(byName == bundleMatched)
    }

    @Test
    func installedWorkBuddyURLPrefersBundleIdentifierThenApplicationName() {
        let bundleMatched = URL(fileURLWithPath: "/Applications/WorkBuddy.app", isDirectory: true)
        let byBundleIdentifier = AIMascotLibrary.installedWorkBuddyApplicationURL(
            resolveBundleIdentifier: { $0 == "com.workbuddy.workbuddy" ? bundleMatched : nil },
            applicationDirectories: [],
            fileExists: { _ in false }
        )
        #expect(byBundleIdentifier == bundleMatched)

        let directory = URL(fileURLWithPath: "/Applications")
        let byName = AIMascotLibrary.installedWorkBuddyApplicationURL(
            resolveBundleIdentifier: { _ in nil },
            applicationDirectories: [directory],
            fileExists: {
                $0 == directory.appendingPathComponent("WorkBuddy.app", isDirectory: true)
            }
        )
        #expect(byName == bundleMatched)
    }

    @Test
    func installedGeminiURLPrefersBundleIdentifierThenApplicationName() {
        let bundleMatched = URL(fileURLWithPath: "/Applications/Gemini.app", isDirectory: true)
        let byBundleIdentifier = AIMascotLibrary.installedGeminiApplicationURL(
            resolveBundleIdentifier: { $0 == "com.google.GeminiMacOS" ? bundleMatched : nil },
            applicationDirectories: [],
            fileExists: { _ in false }
        )
        #expect(byBundleIdentifier == bundleMatched)

        let directory = URL(fileURLWithPath: "/Applications")
        let byName = AIMascotLibrary.installedGeminiApplicationURL(
            resolveBundleIdentifier: { _ in nil },
            applicationDirectories: [directory],
            fileExists: {
                $0 == directory.appendingPathComponent("Gemini.app", isDirectory: true)
            }
        )
        #expect(byName == bundleMatched)
    }

    @Test
    func mapsProvidersToBundledBrandAssets() {
        #expect(AIMascotLibrary.providerAssetName(for: .codex) == "codex-color.svg")
        #expect(AIMascotLibrary.providerAssetName(for: .gpt) == "openai.svg")
        #expect(AIMascotLibrary.providerAssetName(for: .claude) == "claude-color.svg")
        #expect(AIMascotLibrary.providerAssetName(for: .gemini) == "gemini-color.svg")
        #expect(AIMascotLibrary.providerAssetName(for: .grok) == "grok.svg")
        #expect(AIMascotLibrary.providerAssetName(for: .copilot) == "copilot.svg")
        #expect(AIMascotLibrary.providerAssetName(for: .kimi) == "kimi.png")
        #expect(AIMascotLibrary.providerAssetName(for: .qwen) == "qwen-color.svg")
        #expect(AIMascotLibrary.providerAssetName(for: .coder) == "qoder.icns")
        #expect(AIMascotLibrary.providerAssetName(for: .trae) == "trae.icns")
        #expect(AIMascotLibrary.providerAssetName(for: .opencode) == "opencode.svg")
        #expect(AIMascotLibrary.providerAssetName(for: .pi) == "pi.svg")
        #expect(AIMascotLibrary.providerAssetName(for: .harness) == "workbuddy.icns")
        #expect(AIMascotLibrary.providerAssetName(for: .doubao) == "doubao.png")
        #expect(AIMascotLibrary.providerAssetName(for: .zcode) == "zcode.icns")
        #expect(AIMascotLibrary.providerAssetName(for: .zed) == "zed.icns")
    }

    @Test
    func everyProviderHasAnOfflineBrandAsset() {
        let missing = AIProvider.allCases.filter {
            AIMascotLibrary.providerAssetName(for: $0) == nil
        }
        #expect(missing.isEmpty, "缺少离线品牌资源：\(missing.map(\.rawValue).joined(separator: ", "))")
    }

    @Test
    func resolvesOfficialBrandAssetFromSwiftPackageResourceRoot() {
        let appResources = URL(fileURLWithPath: "/App/Contents/Resources", isDirectory: true)
        let packageResources = URL(fileURLWithPath: "/Build/zisla_Zisla.bundle", isDirectory: true)
        let expected = packageResources
            .appendingPathComponent("BrandIcons/claude-color.svg", isDirectory: false)

        let resolved = AIMascotLibrary.providerAssetURL(
            for: .claude,
            resourceRoots: [appResources, packageResources],
            fileExists: { $0 == expected }
        )

        #expect(resolved == expected)
    }

    @Test
    func keepsCodexAndChatGPTIdentityDistinct() {
        #expect(AIMascotLibrary.providerDisplayName(for: .codex) == "Codex")
        #expect(AIMascotLibrary.providerDisplayName(for: .gpt) == "ChatGPT")
        #expect(
            AIMascotLibrary.providerAssetName(for: .codex)
                != AIMascotLibrary.providerAssetName(for: .gpt)
        )
        #expect(
            AIMascotLibrary.providerAssetName(for: .pi)
                != AIMascotLibrary.providerAssetName(for: .opencode)
        )
    }

    @Test
    func noticeProviderTakesPrecedenceOverTaskIdentifier() {
        #expect(
            AIMascotLibrary.provider(fromNoticeID: "ai-active-gpt-codex-turn-123") == .gpt
        )
        #expect(
            AIMascotLibrary.provider(fromNoticeID: "ai-active-codex-codex-turn-123") == .codex
        )
    }

    @Test
    func compactIdentityListKeepsDistinctProvidersInOrder() {
        #expect(
            AIMascotLibrary.uniqueProviders(fromNoticeIDs: [
                "ai-active-gpt-codex-turn-1",
                "ai-active-gpt-manual-2",
                "ai-active-claude-job-3",
                "ai-active-codex-codex-turn-4",
            ]) == [.gpt, .claude, .codex]
        )
    }
}
