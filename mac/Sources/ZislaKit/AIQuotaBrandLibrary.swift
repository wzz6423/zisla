import Foundation

public enum AIQuotaBrandLibrary {
    public static let providerIDs: [String] = [
        "claudeCode", "codex", "kiro", "antigravity", "cursor", "openCodeGo",
        "kimiCode", "ollamaCloud", "zai", "glmCoding", "minimax", "minimaxCN",
        "copilot", "grok", "grokBot", "volcengine", "commandCode", "deepSeek",
        "devin", "xiaomiMiMo", "sub2api", "newAPI", "v2ex", "qoder",
    ]

    public static func assetName(for providerID: String) -> String? {
        switch providerID {
        case "claudeCode": "claude-color.svg"
        case "codex": "codex-color.svg"
        case "kiro": "kiro.svg"
        case "antigravity": "antigravity.png"
        case "cursor": "cursor.svg"
        case "openCodeGo": "opencode.svg"
        case "kimiCode": "kimi.png"
        case "ollamaCloud": "ollama.svg"
        case "zai", "glmCoding": "zai.svg"
        case "minimax", "minimaxCN": "minimax.svg"
        case "copilot": "copilot.svg"
        case "grok": "grok.svg"
        case "grokBot": "xai.svg"
        case "volcengine": "volcengine.svg"
        case "commandCode": "commandcode.svg"
        case "deepSeek": "deepseek.svg"
        case "devin": "devin.svg"
        case "xiaomiMiMo": "xiaomimimo.svg"
        case "sub2api": "sub2api.svg"
        case "newAPI": "newapi.svg"
        case "v2ex": "v2ex.svg"
        case "qoder": "qoder.icns"
        default: nil
        }
    }
}
