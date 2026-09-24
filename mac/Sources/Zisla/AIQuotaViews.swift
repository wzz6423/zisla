import AppKit
import SwiftUI
import ZislaCore
import ZislaKit

struct AIQuotaIcon: View {
    let providerID: String
    var size: CGFloat = 18

    private var identity: AIMascotIdentity? {
        switch providerID {
        case "claudeCode": .claude
        case "codex": .codex
        case "antigravity": .antigravity
        case "copilot": .copilot
        case "grok": .grok
        case "kimiCode": .kimi
        case "openCodeGo": .opencode
        case "qoder": .coder
        default: nil
        }
    }

    var body: some View {
        Group {
            if let identity {
                AIMascotView(identity: identity, size: size)
            } else if let asset = AIQuotaBrandLibrary.assetName(for: providerID),
                      let url = AIMascotLibrary.providerAssetURL(named: asset, resourceRoots: resourceRoots),
                      let image = AIMascotImageCache.shared.image(for: "provider|\(asset)", url: url) {
                Image(nsImage: image).resizable().scaledToFit()
            } else {
                Image(systemName: "sparkles")
            }
        }
        .frame(width: size, height: size)
        .accessibilityLabel(AIQuotaProvider(rawValue: providerID)?.displayName ?? providerID)
    }

    private var resourceRoots: [URL] {
        let source = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Resources")
        return [Bundle.main.resourceURL,
                Bundle.main.bundleURL.appendingPathComponent("zisla_Zisla.bundle"), source].compactMap { $0 }
    }
}

struct AIQuotaPanel: View {
    @ObservedObject var monitor: AIQuotaMonitor
    @ObservedObject var store: AIQuotaConfigurationStore
    var configure: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label(AppLocalization.text("余额与额度"), systemImage: "gauge.with.dots.needle.67percent")
                    .font(.system(size: 10, weight: .semibold))
                Spacer()
                Button { Task { await monitor.refresh() } } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .disabled(monitor.isRefreshing)
                .help(AppLocalization.text("刷新额度"))
                Button(action: configure) { Image(systemName: "slider.horizontal.3") }
                    .help(AppLocalization.text("配置额度账户"))
            }
            .buttonStyle(.plain)
            if store.configurations.filter(\.isEnabled).isEmpty {
                Button(AppLocalization.text("添加额度账户"), action: configure)
                    .buttonStyle(.plain)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 52)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        ForEach(store.configurations.filter(\.isEnabled)) { configuration in
                            accountRow(configuration)
                        }
                    }
                }
                .scrollIndicators(.visible)
                .thinScrollChrome()
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private func accountRow(_ configuration: AIQuotaConfiguration) -> some View {
        let account = monitor.snapshot.accounts.first { $0.id == configuration.id }
        return VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                AIQuotaIcon(providerID: configuration.provider.rawValue, size: 14)
                Text(configuration.label).font(.system(size: 10, weight: .semibold)).lineLimit(1)
                Spacer(minLength: 2)
                if let balance = account?.balanceText {
                    Text(balance).font(.system(size: 9, design: .monospaced)).lineLimit(1)
                }
            }
            if let error = monitor.errors[configuration.id] {
                Text(AppLocalization.text(error.localizationKey))
                    .font(.system(size: 9)).foregroundStyle(.secondary).lineLimit(2)
            } else if let account {
                ForEach(account.windows) { window in
                    if let percent = window.remainingPercent {
                        HStack(spacing: 6) {
                            Text(window.displayLabel).lineLimit(1)
                            Spacer(minLength: 2)
                            Text(AppLocalization.text("剩余 %@", percent.formatted(.number.precision(.fractionLength(0))) + "%"))
                                .monospacedDigit()
                                .foregroundStyle(percent <= 10 ? Color.orange : Color.secondary)
                        }
                        .font(.system(size: 9))
                        .help(window.resetsAt.map { AppLocalization.text("重置于 %@", $0.formatted()) } ?? window.displayLabel)
                    }
                }
            } else {
                Text(AppLocalization.text(monitor.isRefreshing ? "正在读取额度…" : "等待刷新额度"))
                    .font(.system(size: 9)).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}

@MainActor
final class AIQuotaSettingsController {
    private var window: NSWindow?

    func show(store: AIQuotaConfigurationStore, monitor: AIQuotaMonitor, languageStore: AppLanguageStore) {
        if window == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 640, height: 480),
                                  styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.minSize = NSSize(width: 520, height: 380)
            window.contentView = NSHostingView(rootView: AppLanguageEnvironment(languageStore: languageStore,
                content: AIQuotaSettingsView(store: store, monitor: monitor)))
            window.center()
            self.window = window
        }
        window?.title = AppLocalization.text("配置额度账户")
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func close() { window?.close() }
}

private struct AIQuotaSettingsView: View {
    @ObservedObject var store: AIQuotaConfigurationStore
    @ObservedObject var monitor: AIQuotaMonitor
    @State private var editing: AIQuotaConfiguration?
    @State private var error: AIQuotaError?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(AppLocalization.text("余额与额度")).font(.title2.bold())
                Spacer()
                Menu(AppLocalization.text("添加额度账户")) {
                    ForEach(AIQuotaProvider.allCases) { provider in
                        Button(provider.displayName) { editing = AIQuotaConfiguration(provider: provider) }
                    }
                }
            }
            Text(AppLocalization.text("凭据保存在 macOS 钥匙串中；只读取已启用账户的额度。"))
                .font(.callout).foregroundStyle(.secondary)
            if let error = error ?? store.loadError {
                Text(AppLocalization.text(error.localizationKey)).foregroundStyle(.orange)
            }
            List(store.configurations) { configuration in
                HStack(spacing: 10) {
                    AIQuotaIcon(providerID: configuration.provider.rawValue, size: 24)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(configuration.label).font(.headline)
                        if let failure = monitor.errors[configuration.id] {
                            Text(AppLocalization.text(failure.localizationKey)).foregroundStyle(.orange)
                        } else {
                            Text(configuration.provider.displayName).foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    Toggle(AppLocalization.text("启用"), isOn: Binding(get: { configuration.isEnabled }, set: { enabled in
                        var updated = configuration
                        updated.isEnabled = enabled
                        do { try store.save(updated, credential: nil); error = nil }
                        catch { self.error = error as? AIQuotaError ?? .storageUnavailable }
                    }))
                    .labelsHidden().help(AppLocalization.text("启用"))
                    Button(AppLocalization.text("编辑")) { editing = configuration }
                    Button(role: .destructive) {
                        do { try store.remove(configuration); error = nil }
                        catch { self.error = error as? AIQuotaError ?? .storageUnavailable }
                    } label: { Image(systemName: "trash") }
                    .help(AppLocalization.text("删除"))
                }
                .padding(.vertical, 5)
            }
            .overlay {
                if store.configurations.isEmpty {
                    Text(AppLocalization.text("添加额度账户")).foregroundStyle(.secondary)
                }
            }
            HStack {
                Text(AppLocalization.text("额度降至 80/60/40/20/10/5/0% 时提示 5 秒。"))
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button(AppLocalization.text("刷新额度")) { Task { await monitor.refresh() } }
                    .disabled(monitor.isRefreshing)
            }
        }
        .padding(20)
        .sheet(item: $editing) { configuration in
            AIQuotaAccountEditor(store: store, configuration: configuration)
        }
    }
}

private struct AIQuotaAccountEditor: View {
    @ObservedObject var store: AIQuotaConfigurationStore
    @State var configuration: AIQuotaConfiguration
    @State private var token = ""
    @State private var secret = ""
    @State private var error: AIQuotaError?
    @Environment(\.dismiss) private var dismiss

    private var provider: AIQuotaProvider { configuration.provider }
    private var isExisting: Bool { store.configurations.contains { $0.id == configuration.id } }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                AIQuotaIcon(providerID: provider.rawValue, size: 26)
                Text(provider.displayName).font(.title2.bold())
            }
            Form {
                TextField(AppLocalization.text("名称"), text: $configuration.label)
                if provider.supportsLocalLogin && !provider.requiresLocalClient {
                    Picker(AppLocalization.text("凭据来源"), selection: $configuration.source) {
                        Text(AppLocalization.text("本机客户端登录")).tag(AIQuotaCredentialSource.localLogin)
                        Text(AppLocalization.text("手动输入")).tag(AIQuotaCredentialSource.manual)
                    }
                }
                if configuration.source == .localLogin {
                    Text(AppLocalization.text(provider == .antigravity ? "额度仅在 Antigravity 运行时可用。" : "读取对应客户端的登录状态；请先在客户端登录。"))
                        .font(.callout).foregroundStyle(.secondary)
                    if provider != .antigravity {
                        TextField(AppLocalization.text("客户端或凭据路径（可选）"), text: $configuration.localPath)
                    }
                } else {
                    SecureField(AppLocalization.text(provider.usesCookie ? "会话 Cookie" : provider == .volcengine ? "访问密钥 ID" : "API Key / 访问令牌"), text: $token)
                    if provider == .volcengine {
                        SecureField(AppLocalization.text("秘密访问密钥"), text: $secret)
                    }
                    Text(AppLocalization.text(provider.usesCookie
                        ? "从该服务已登录网页的开发者工具复制 Cookie 请求头。"
                        : [.claudeCode, .codex, .copilot, .grok, .devin].contains(provider)
                            ? "使用该服务的登录访问令牌，不是模型 API Key。"
                            : "使用对应服务的 API Key；火山引擎使用访问密钥对。"))
                        .font(.callout).foregroundStyle(.secondary)
                    if isExisting {
                        Text(AppLocalization.text("留空保留现有凭据；更换服务地址或账户范围时必须重新输入。"))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                if provider.usesGateway {
                    TextField(AppLocalization.text("HTTPS 服务地址"), text: $configuration.baseURL)
                }
                if provider == .devin || provider == .codex {
                    TextField(AppLocalization.text(provider == .devin ? "组织 ID 或组织页面地址" : "ChatGPT 账户 ID（可选）"), text: $configuration.organization)
                }
                if provider == .qoder { Toggle(AppLocalization.text("中国站点"), isOn: $configuration.chinaSite) }
            }
            .textFieldStyle(.roundedBorder)
            if let error { Text(AppLocalization.text(error.localizationKey)).foregroundStyle(.orange) }
            HStack {
                Spacer()
                Button(AppLocalization.text("取消")) { dismiss() }.keyboardShortcut(.cancelAction)
                Button(AppLocalization.text("保存")) {
                    do {
                        let credential = token.isEmpty && secret.isEmpty ? nil : AIQuotaCredential(token: token, secret: secret)
                        try store.save(configuration, credential: credential)
                        token = ""; secret = ""
                        dismiss()
                    } catch { self.error = error as? AIQuotaError ?? .storageUnavailable }
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 510)
    }
}
