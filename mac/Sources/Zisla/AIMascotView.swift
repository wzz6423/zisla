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
    case trae
    case opencode
    case harness
    case doubao

    var id: Self { self }

    init(provider: AIProvider, taskID: String) {
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
        provider.map(AIMascotLibrary.providerDisplayName(for:)) ?? rawValue
    }

    fileprivate var symbolName: String {
        switch self {
        case .claude: "sparkle"
        case .codex: "chevron.left.forwardslash.chevron.right"
        case .gemini: "sparkles"
        case .grok: "bolt.fill"
        case .gpt: "brain.head.profile"
        case .copilot: "sparkles.rectangle.stack"
        case .kimi: "sparkles"
        case .qwen: "cloud.fill"
        case .coder: "terminal.fill"
        case .trae: "wand.and.stars"
        case .opencode: "curlybraces"
        case .harness: "h.square.fill"
        case .doubao: "bubble.left.and.bubble.right.fill"
        }
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
        case .trae: .trae
        case .opencode: .opencode
        case .harness: .harness
        case .doubao: .doubao
        }
    }

    fileprivate var tint: Color {
        guard let provider else { return .primary }
        return ProviderBrand.color(for: provider)
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
                Image(systemName: identity.symbolName)
                    .font(.system(size: size * 0.66, weight: .semibold))
                    .foregroundStyle(identity.tint)
            }
        }
        .frame(width: size, height: size)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(identity.displayName)
    }

    private var providerImage: NSImage? {
        guard let provider = identity.provider,
              let assetName = AIMascotLibrary.providerAssetName(for: provider),
              let url = resourceAssetURL(relativePath: "BrandIcons/\(assetName)")
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

    private func resourceAssetURL(relativePath: String) -> URL? {
        let sourceRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let candidates = [
            Bundle.main.resourceURL,
            sourceRoot.appendingPathComponent("Resources", isDirectory: true),
        ].compactMap { $0 }
        return candidates
            .map { $0.appendingPathComponent(relativePath, isDirectory: false) }
            .first { FileManager.default.fileExists(atPath: $0.path) }
    }
}
