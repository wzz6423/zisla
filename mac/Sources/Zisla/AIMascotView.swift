import AppKit
import ZislaCore
import ZislaKit
import SwiftUI

@MainActor
final class AIMascotImageCache: ObservableObject {
    static let shared = AIMascotImageCache()

    private var values: [String: NSImage] = [:]
    private var retries: [String: Task<Void, Never>] = [:]
    private let waitForRetry: @MainActor () async throws -> Void

    init(waitForRetry: @escaping @MainActor () async throws -> Void = {
        try await Task.sleep(for: .seconds(1))
    }) {
        self.waitForRetry = waitForRetry
    }

    deinit {
        for retry in retries.values { retry.cancel() }
    }

    func image(for key: String, load: @escaping @MainActor () -> NSImage?) -> NSImage? {
        if let image = values[key] { return image }
        guard retries[key] == nil else { return nil }
        if let image = snapshot(load()) {
            values[key] = image
            return image
        }
        let waitForRetry = waitForRetry
        retries[key] = Task { [weak self] in
            defer { self?.retries[key] = nil }
            while true {
                do {
                    try await waitForRetry()
                } catch {
                    return
                }
                guard let self else { return }
                if let image = self.snapshot(load()) {
                    self.objectWillChange.send()
                    self.values[key] = image
                    return
                }
            }
        }
        return nil
    }

    func image(for key: String, url: @escaping @MainActor () -> URL?) -> NSImage? {
        image(for: key) {
            url().flatMap { NSImage(contentsOf: $0) }
        }
    }

    private func snapshot(_ image: NSImage?) -> NSImage? {
        guard let image,
              let bitmap = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        // AppKit can provide a drawable but empty bitmap; caching it would suppress all future retries.
        guard let alpha = CGContext(
            data: nil,
            width: bitmap.width,
            height: bitmap.height,
            bitsPerComponent: 8,
            bytesPerRow: bitmap.width,
            space: CGColorSpaceCreateDeviceGray(),
            bitmapInfo: CGImageAlphaInfo.alphaOnly.rawValue
        ), let data = alpha.data else { return nil }
        // Source-over can round a single alpha level down to zero, hiding a valid faint pixel.
        alpha.setBlendMode(.copy)
        alpha.draw(bitmap, in: CGRect(x: 0, y: 0, width: bitmap.width, height: bitmap.height))
        let pixels = UnsafeRawBufferPointer(start: data, count: alpha.bytesPerRow * alpha.height)
        guard pixels.contains(where: { $0 != 0 }) else { return nil }
        return NSImage(cgImage: bitmap, size: image.size)
    }
}

enum AIMascotIdentity: String, CaseIterable, Identifiable {
    case claude
    case codex
    case gemini
    case geminiDesktop
    case grok
    case gpt
    case copilot
    case kimi
    case qwen
    case coder
    case zcode
    case zed
    case delta
    case orca
    case workbuddy
    case workbuddyAI
    case trae
    case opencode
    case pi
    case harness
    case deepseekHarness
    case doubao

    var id: Self { self }

    init(provider: AIProvider, taskID: String, title: String? = nil) {
        if provider == .harness, title == "DeepSeek Harness" {
            self = .deepseekHarness
            return
        }
        // Historical WorkBuddy tasks used the shared harness provider. Preserve their brand
        // without relabelling unrelated Harnext/DeepSeek records or changing stored identifiers.
        if provider == .harness,
           taskID.hasPrefix("workbuddy-session-") || taskID.hasPrefix("ai-active-harness-workbuddy-session-") {
            self = .workbuddy
            return
        }
        // The desktop app and the CLI share one provider, so the task ID decides which logo applies.
        if provider == .gemini,
           taskID.contains(GeminiDesktopSessionActivityDetector.taskIDPrefix) {
            self = .geminiDesktop
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
        case .zed: self = .zed
        case .delta: self = .delta
        case .orca: self = .orca
        case .workbuddy: self = .workbuddy
        case .workbuddyAI: self = .workbuddyAI
        case .trae: self = .trae
        case .opencode: self = .opencode
        case .pi: self = .pi
        case .harness: self = .harness
        case .doubao: self = .doubao
        }
    }

    init(noticeID: String?) {
        if let provider = AIMascotLibrary.provider(fromNoticeID: noticeID) {
            self.init(provider: provider, taskID: noticeID ?? "")
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
        } else if id.contains("zed") {
            self = .zed
        } else if id.contains("trae") {
            self = .trae
        } else if id.contains("opencode") {
            self = .opencode
        } else if id == "pi" || id.contains("pi-coding") {
            self = .pi
        } else if id.contains("dsh") || id.contains("deepseek-harness") {
            self = .deepseekHarness
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
        case .geminiDesktop: .gemini
        case .grok: .grok
        case .gpt: .gpt
        case .copilot: .copilot
        case .kimi: .kimi
        case .qwen: .qwen
        case .coder: .coder
        case .zcode: .zcode
        case .zed: .zed
        case .delta: .delta
        case .orca: .orca
        case .workbuddy: .workbuddy
        case .workbuddyAI: .workbuddyAI
        case .trae: .trae
        case .opencode: .opencode
        case .pi: .pi
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
        self == .grok || self == .gpt || self == .copilot || self == .opencode || self == .pi
    }

}

struct AIMascotView: View {
    var identity: AIMascotIdentity
    var size: CGFloat
    @ObservedObject private var imageCache = AIMascotImageCache.shared
    @Environment(\.colorScheme) private var colorScheme

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
                    // Semantic primary is translucent and dims thin logo strokes against the notch.
                    .foregroundStyle(colorScheme == .dark ? Color.white : Color.black)
            } else {
                Color.clear
            }
        }
        .frame(width: size, height: size)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(identity.displayName)
    }

    private var providerImage: NSImage? {
        guard let assetName = identity.assetName else { return nil }
        let resourceRoots = providerResourceRoots
        return imageCache.image(
            for: "provider|\(assetName)",
            url: {
                AIMascotLibrary.providerAssetURL(named: assetName, resourceRoots: resourceRoots)
            }
        )
    }

    /// Installed client's official icon takes priority over the bundled offline asset.
    private var installedProviderImage: NSImage? {
        switch identity {
        case .geminiDesktop:
            return imageCache.image(for: "installed|gemini") {
                AIMascotLibrary.installedGeminiApplicationURL().map {
                    NSWorkspace.shared.icon(forFile: $0.path)
                }
            }
        case .coder:
            return imageCache.image(for: "installed|coder") {
                AIMascotLibrary.installedCoderApplicationURL().map {
                    NSWorkspace.shared.icon(forFile: $0.path)
                }
            }
        case .trae:
            return imageCache.image(for: "installed|trae") {
                AIMascotLibrary.installedTraeApplicationURL().map {
                    NSWorkspace.shared.icon(forFile: $0.path)
                }
            }
        case .zed:
            return imageCache.image(for: "installed|zed") {
                AIMascotLibrary.installedZedApplicationURL().map {
                    NSWorkspace.shared.icon(forFile: $0.path)
                }
            }
        case .delta, .orca, .workbuddy, .workbuddyAI:
            guard let provider = identity.provider else { return nil }
            return imageCache.image(for: "installed|desktop-\(provider.rawValue)") {
                AIMascotLibrary.installedDesktopAgentApplicationURL(for: provider).map {
                    NSWorkspace.shared.icon(forFile: $0.path)
                }
            }
        case .harness:
            return imageCache.image(for: "installed|workbuddy") {
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
