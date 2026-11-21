import Foundation
import ZislaCore

public enum AIAccountBalanceWebsite: String, CaseIterable, Identifiable, Sendable {
    case qoder, qoderChina, trae, zed
    public var id: String { rawValue }
    public var provider: AIProvider { switch self { case .qoder, .qoderChina: .coder; case .trae: .trae; case .zed: .zed } }
    public var title: String { switch self { case .qoder: "Qoder"; case .qoderChina: "Qoder 中国"; case .trae: "TRAE 中国"; case .zed: "Zed" } }
    public var dashboard: URL {
        switch self {
        case .qoder: URL(string: "https://qoder.com/account/usage")!
        case .qoderChina: URL(string: "https://qoder.com.cn/account/usage")!
        case .trae: URL(string: "https://www.trae.cn/account-setting")!
        case .zed: URL(string: "https://dashboard.zed.dev/")!
        }
    }

    var cookieRequestURLs: [URL] {
        switch self {
        case .qoder: [URL(string: "https://qoder.com/api/v2/me/usages/big_model_credits")!]
        case .qoderChina: [URL(string: "https://qoder.com.cn/api/v2/me/usages/big_model_credits")!]
        case .trae: [URL(string: "https://api.trae.cn/cloudide/api/v3/common/GetUserToken")!,
                     URL(string: "https://api.trae.cn/trae/api/v2/pay/user_current_entitlement_list")!]
        case .zed: [URL(string: "https://cloud.zed.dev/frontend/billing/usage")!]
        }
    }

    var cookieDomain: String {
        switch self { case .qoder: "qoder.com"; case .qoderChina: "qoder.com.cn"; case .trae: "trae.cn"; case .zed: "zed.dev" }
    }

    public static func selected(for monitoredProviders: Set<AIProvider>, qoderRegions: Set<AIAccountBalanceQoderRegion>) -> [Self] {
        allCases.filter { website in
            guard monitoredProviders.contains(website.provider) else { return false }
            return switch website {
            case .qoder: qoderRegions.contains(.global)
            case .qoderChina: qoderRegions.contains(.china)
            case .trae, .zed: true
            }
        }
    }
}

public struct AIAccountBalanceCookieStore: Sendable {
    private let secrets: any AIAgentSecretStoring

    public init(secrets: any AIAgentSecretStoring = DatabaseAIAgentSecretStore()) { self.secrets = secrets }

    public func setCookie(_ value: String, for website: AIAccountBalanceWebsite) throws {
        try secrets.setSecret(Self.normalizedCookie(value, website: website), for: reference(website))
    }

    public func removeCookie(for website: AIAccountBalanceWebsite) throws { try secrets.removeSecret(for: reference(website)) }

    func cookie(for website: AIAccountBalanceWebsite) throws -> String? {
        try secrets.secret(for: reference(website)).map { try Self.normalizedCookie($0, website: website) }
    }

    /// Accepts one Cookie request header, tolerating its prefix and empty semicolon segments.
    /// Control bytes and malformed nonempty pairs fail before storage; Zed forwards only known session cookies.
    static func normalizedCookie(_ value: String, website: AIAccountBalanceWebsite) throws -> String {
        var value = value.trimmingCharacters(in: .whitespaces)
        if value.lowercased().hasPrefix("cookie:") { value = String(value.dropFirst(7)).trimmingCharacters(in: .whitespaces) }
        _ = try AIAccountBalanceCredentials.header(value)
        let parts = value.split(separator: ";", omittingEmptySubsequences: false)
            .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        guard !parts.isEmpty else { throw AIAccountBalanceError.invalidCredentials }
        let pairs = try parts.map { part -> (String, String) in
            guard let index = part.firstIndex(of: "=") else { throw AIAccountBalanceError.invalidCredentials }
            let name = part[..<index].trimmingCharacters(in: .whitespaces)
            let value = part[part.index(after: index)...].trimmingCharacters(in: .whitespaces)
            guard !name.isEmpty, !value.isEmpty, name.unicodeScalars.allSatisfy({
                CharacterSet.alphanumerics.contains($0) || "!#$%&'*+.^_`|~-".unicodeScalars.contains($0)
            }) else { throw AIAccountBalanceError.invalidCredentials }
            return (name, value)
        }
        if website == .zed {
            guard pairs.contains(where: { $0.0.lowercased() == "zed.session" }) else { throw AIAccountBalanceError.invalidCredentials }
            return pairs.filter { ["zed.session", "c15t", "__cf_bm", "cf_clearance"].contains($0.0.lowercased()) }
                .map { $0.0 + "=" + $0.1 }.joined(separator: "; ")
        }
        return pairs.map { $0.0 + "=" + $0.1 }.joined(separator: "; ")
    }

    private func reference(_ website: AIAccountBalanceWebsite) -> String { "ai-account-balance-cookie:" + website.rawValue }
}
