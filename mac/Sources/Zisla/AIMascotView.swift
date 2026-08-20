import AppKit
import ZislaCore
import ZislaKit
import SwiftUI

@MainActor
private final class AIMascotImageCache {
    static let shared = AIMascotImageCache()

    private var values: [String: NSImage?] = [:]

    func image(for key: String, load: () -> NSImage?) -> NSImage? {
        if let value = values[key] { return value }
        let image = load()
        values[key] = image
        return image
    }

    func image(for key: String, url: URL) -> NSImage? {
        image(for: key) { NSImage(contentsOf: url) }
    }
}

enum AIMascotIdentity: String, CaseIterable, Identifiable {
    case claude
    case codex
    case gemini
    case grok
    case gpt
    case copilot
    case kimi
    case qwen
    case coder
    case zcode
    case trae
    case opencode
    case harness
    case deepseekHarness
    case doubao

    var id: Self { self }

    init(provider: AIProvider, taskID _: String, title: String? = nil) {
        if provider == .harness, title == "DeepSeek Harness" {
            self = .deepseekHarness
            return
        }
        switch provider {
        case .claude: self = .claude
        case .codex: self = .codex
        case .gemini: self = .gemini
        case .grok: self = .grok
        case .gpt: self = .gpt
        case .copilot: self = .copilot
        case .kimi: self = .kimi
        case .qwen: self = .qwen
        case .coder: self = .coder
        case .zcode: self = .zcode
        case .trae: self = .trae
        case .opencode: self = .opencode
        case .harness: self = .harness
        case .doubao: self = .doubao
        }
    }

    init(noticeID: String?) {
        if let provider = AIMascotLibrary.provider(fromNoticeID: noticeID) {
            self.init(provider: provider, taskID: "")
            return
        }
        let id = noticeID?.lowercased() ?? ""
        if id.contains("claude") {
            self = .claude
        } else if id.contains("codex") {
            self = .codex
        } else if id.contains("gemini") {
            self = .gemini
        } else if id.contains("grok") {
            self = .grok
        } else if id.contains("copilot") {
            self = .copilot
        } else if id.contains("kimi") {
            self = .kimi
        } else if id.contains("qwen") {
            self = .qwen
        } else if id.contains("coder") {
            self = .coder
        } else if id.contains("zcode") {
            self = .zcode
        } else if id.contains("trae") {
            self = .trae
        } else if id.contains("opencode") {
            self = .opencode
        } else if id.contains("harness") || id.contains("harnext") {
            self = .harness
        } else if id.contains("doubao") {
            self = .doubao
        } else {
            self = .gpt
        }
    }

    var displayName: String {
        if self == .deepseekHarness { return "DeepSeek Harness" }
        return provider.map(AIMascotLibrary.providerDisplayName(for:)) ?? rawValue
    }

    fileprivate var provider: AIProvider? {
        switch self {
        case .claude: .claude
        case .codex: .codex
        case .gemini: .gemini
        case .grok: .grok
        case .gpt: .gpt
        case .copilot: .copilot
        case .kimi: .kimi
        case .qwen: .qwen
        case .coder: .coder
        case .zcode: .zcode
        case .trae: .trae
        case .opencode: .opencode
        case .harness: .harness
        case .deepseekHarness: nil
        case .doubao: .doubao
        }
    }

    fileprivate var assetName: String? {
        if self == .deepseekHarness { return "deepseek.svg" }
        return provider.flatMap { AIMascotLibrary.providerAssetName(for: $0) }
    }

    fileprivate var usesMonochromeProviderAsset: Bool {
        self == .grok || self == .gpt || self == .copilot || self == .opencode
    }

}

struct AIMascotView: View {
    var identity: AIMascotIdentity
    var size: CGFloat

    init(
        identity: AIMascotIdentity,
        size: CGFloat
    ) {
        self.identity = identity
        self.size = size
    }

    var body: some View {
        Group {
            if let installedProviderImage {
                Image(nsImage: installedProviderImage)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
            } else if let providerImage {
                Image(nsImage: providerImage)
                    .renderingMode(identity.usesMonochromeProviderAsset ? .template : .original)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
                    .foregroundStyle(.primary)
            } else {
                Color.clear
            }
        }
        .frame(width: size, height: size)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(identity.displayName)
    }

    private var providerImage: NSImage? {
        guard let assetName = identity.assetName,
              let url = AIMascotLibrary.providerAssetURL(
                  named: assetName,
                  resourceRoots: providerResourceRoots
              )
        else { return nil }
        return AIMascotImageCache.shared.image(
            for: "provider|\(assetName)",
            url: url
        )
    }

    /// Installed client's official icon takes priority over the bundled offline asset.
    private var installedProviderImage: NSImage? {
        switch identity {
        case .coder:
            return AIMascotImageCache.shared.image(for: "installed|coder") {
                AIMascotLibrary.installedCoderApplicationURL().map {
                    NSWorkspace.shared.icon(forFile: $0.path)
                }
            }
        case .trae:
            return AIMascotImageCache.shared.image(for: "installed|trae") {
                AIMascotLibrary.installedTraeApplicationURL().map {
                    NSWorkspace.shared.icon(forFile: $0.path)
                }
            }
        case .harness:
            return AIMascotImageCache.shared.image(for: "installed|workbuddy") {
                AIMascotLibrary.installedWorkBuddyApplicationURL().map {
                    NSWorkspace.shared.icon(forFile: $0.path)
                }
            }
        default:
            return nil
        }
    }

    private var providerResourceRoots: [URL] {
        let sourceRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        var roots = [URL]()
        if let appResources = Bundle.main.resourceURL {
            roots.append(appResources)
        }
        // Bundle.module traps in the hand-built app because that layout copies resources into Bundle.main.
        roots.append(
            Bundle.main.bundleURL.appendingPathComponent("zisla_Zisla.bundle", isDirectory: true)
        )
        roots.append(sourceRoot.appendingPathComponent("Resources", isDirectory: true))
        return roots
    }
}
