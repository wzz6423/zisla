import Foundation

public enum AIQuotaProvider: String, CaseIterable, Codable, Sendable, Identifiable {
    case claudeCode, codex, kiro, antigravity, cursor, openCodeGo, kimiCode, ollamaCloud
    case zai, glmCoding, minimax, minimaxCN, copilot, grok, grokBot, volcengine
    case commandCode, deepSeek, devin, xiaomiMiMo, sub2api, newAPI, v2ex, qoder

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .claudeCode: "Claude Code"
        case .codex: "Codex"
        case .kiro: "Kiro"
        case .antigravity: "Antigravity"
        case .cursor: "Cursor"
        case .openCodeGo: "OpenCode Go"
        case .kimiCode: "Kimi Code"
        case .ollamaCloud: "Ollama Cloud"
        case .zai: "z.ai"
        case .glmCoding: "Zhipu"
        case .minimax: "MiniMax"
        case .minimaxCN: "MiniMax CN"
        case .copilot: "GitHub Copilot"
        case .grok: "Grok"
        case .grokBot: "Grok Bot"
        case .volcengine: "Volcengine"
        case .commandCode: "Command Code"
        case .deepSeek: "DeepSeek"
        case .devin: "Devin"
        case .xiaomiMiMo: "Xiaomi Coding Plan"
        case .sub2api: "sub2api"
        case .newAPI: "New API"
        case .v2ex: "V2EX"
        case .qoder: "Qoder"
        }
    }

    public var requiresLocalClient: Bool { self == .kiro || self == .antigravity }
    public var supportsLocalLogin: Bool {
        requiresLocalClient || [.claudeCode, .codex, .cursor, .grokBot, .grok, .openCodeGo, .commandCode].contains(self)
    }
    public var usesCookie: Bool { [.cursor, .grokBot, .ollamaCloud, .xiaomiMiMo, .qoder].contains(self) }
    public var usesGateway: Bool { self == .sub2api || self == .newAPI }
}

public enum AIQuotaCredentialSource: String, Codable, Sendable {
    case manual, localLogin
}

public struct AIQuotaConfiguration: Codable, Equatable, Sendable, Identifiable {
    public var id: String
    public var provider: AIQuotaProvider
    public var label: String
    public var isEnabled: Bool
    public var source: AIQuotaCredentialSource
    public var baseURL: String
    public var organization: String
    public var localPath: String
    public var chinaSite: Bool

    public init(id: String = UUID().uuidString, provider: AIQuotaProvider) {
        self.id = id
        self.provider = provider
        label = provider.displayName
        isEnabled = true
        source = provider.supportsLocalLogin ? .localLogin : .manual
        baseURL = ""
        organization = ""
        localPath = ""
        chinaSite = false
    }
}

public enum AIQuotaError: String, Error, LocalizedError, Sendable {
    case credentialMissing, credentialInvalid, credentialUnavailable, credentialRejected
    case invalidAddress, invalidConfiguration, storageUnavailable, clientUnavailable
    case network, rateLimited, server, invalidResponse, noQuota, responseTooLarge

    public var localizationKey: String {
        switch self {
        case .credentialMissing: "请配置访问凭据"
        case .credentialInvalid: "凭据格式无效"
        case .credentialUnavailable: "无法读取客户端登录，请重新登录或手动配置"
        case .credentialRejected: "登录已过期或凭据被拒绝"
        case .invalidAddress: "请输入有效的 HTTPS 服务地址"
        case .invalidConfiguration: "额度配置无效，请检查必填项"
        case .storageUnavailable: "无法保存额度凭据，请检查钥匙串权限"
        case .clientUnavailable: "请安装并登录对应客户端后重试"
        case .network: "额度服务暂时无法连接"
        case .rateLimited: "请求过于频繁，请稍后重试"
        case .server: "额度服务返回错误"
        case .invalidResponse: "无法读取额度响应"
        case .noQuota: "服务未返回可用额度或余额"
        case .responseTooLarge: "额度响应超过大小限制"
        }
    }

    public var errorDescription: String? { AppLocalization.text(localizationKey) }
}
