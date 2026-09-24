// Adapted from upstream provider protocols, revision 86bcb54cff24d4a9c96b4f14066f0098f12e87a6.
// Modified for Zisla's independent credentials, transport and quota model.
// Apache-2.0; see Resources/ThirdPartyLicenses/AIQuota-LICENSE.txt.
import Foundation
import ZislaCore

enum AIQuotaRequestBuilder {
    static func credentialScope(_ configuration: AIQuotaConfiguration) -> String {
        [configuration.provider.rawValue, configuration.baseURL, configuration.organization,
         String(configuration.chinaSite)].map { "\($0.utf8.count):\($0)" }.joined()
    }

    static func validate(_ value: AIQuotaConfiguration) throws {
        guard !value.id.isEmpty, value.id.utf8.count <= 100,
              !value.label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              value.label.utf8.count <= 200,
              !value.localPath.contains("\0"),
              value.source != .localLogin || value.provider.supportsLocalLogin,
              !value.provider.requiresLocalClient || value.source == .localLogin else {
            throw AIQuotaError.invalidConfiguration
        }
        if value.provider.usesGateway { _ = try gateway(value.baseURL, path: "/v1/usage") }
        if value.provider == .devin {
            let organization = try devinOrganization(value.organization)
            guard organization.split(separator: "/").allSatisfy({ part in
                      !part.isEmpty && part != "." && part != ".."
                          && part.utf8.allSatisfy { (48...57).contains($0) || (65...90).contains($0) || (97...122).contains($0) || $0 == 45 || $0 == 95 }
                  }) else { throw AIQuotaError.invalidConfiguration }
        }
        if !value.organization.isEmpty { _ = try header(value.organization) }
    }

    static func devinOrganization(_ input: String) throws -> String {
        var value = input.trimmingCharacters(in: .whitespacesAndNewlines)
        if let url = URL(string: value), let host = url.host,
           host == "devin.ai" || host.hasSuffix(".devin.ai") {
            let parts = url.path.split(separator: "/")
            guard parts.count >= 2, parts[0] == "org" || parts[0] == "organizations" else { throw AIQuotaError.invalidConfiguration }
            value = parts.prefix(2).joined(separator: "/")
        }
        value = value.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard !value.isEmpty else { throw AIQuotaError.invalidConfiguration }
        if value.hasPrefix("org/") || value.hasPrefix("organizations/") { return value }
        return value.hasPrefix("org_") || value.hasPrefix("org-") ? "organizations/\(value)" : "org/\(value)"
    }

    static func header(_ input: String) throws -> String {
        guard !input.isEmpty, input.utf8.count <= 32_768,
              input.unicodeScalars.allSatisfy({ (32...126).contains($0.value) }) else {
            throw AIQuotaError.credentialInvalid
        }
        return input
    }

    static func validatedCredential(_ credential: AIQuotaCredential, provider: AIQuotaProvider) throws -> AIQuotaCredential {
        let token = credential.token.trimmingCharacters(in: .whitespaces)
        _ = try header(token)
        if provider.usesCookie {
            return AIQuotaCredential(token: try cookie(token, provider: provider))
        }
        guard !token.contains(" ") else { throw AIQuotaError.credentialInvalid }
        if provider == .volcengine {
            let secret = try header(credential.secret.trimmingCharacters(in: .whitespaces))
            guard !secret.contains(" ") else { throw AIQuotaError.credentialInvalid }
            return AIQuotaCredential(token: token, secret: secret)
        }
        return AIQuotaCredential(token: token)
    }

    static func cookie(_ value: String, provider: AIQuotaProvider) throws -> String {
        var raw = try header(value)
        if raw.lowercased().hasPrefix("cookie:") { raw = String(raw.dropFirst(7)).trimmingCharacters(in: .whitespaces) }
        let allowed: Set<String>
        let required: Set<String>
        switch provider {
        case .cursor, .grokBot:
            allowed = ["WorkosCursorSessionToken"]; required = allowed
        case .xiaomiMiMo:
            required = ["api-platform_serviceToken", "userId"]
            allowed = required.union(["api-platform_ph", "api-platform_slh"])
        case .ollamaCloud:
            allowed = ["wos-session", "__Secure-session", "__Secure-next-auth.session-token", "next-auth.session-token"]
            required = []
        default: allowed = []; required = []
        }
        let analytics = ["_ga", "_gid", "_gat", "_gcl", "_fb", "_cl", "_hj", "_uet", "_tt", "ajs_", "amp_", "mp_", "hm_", "hmaccount", "intercom-", "__stripe", "_rdt", "_pin"]
        var seen: Set<String> = []
        var pairs: [String] = []
        for part in raw.split(separator: ";") {
            let halves = part.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            guard halves.count == 2 else { throw AIQuotaError.credentialInvalid }
            let name = halves[0].trimmingCharacters(in: .whitespaces)
            let content = halves[1].trimmingCharacters(in: .whitespaces)
            let chunked = provider == .ollamaCloud && allowed.contains { base in
                name.hasPrefix(base + ".") && !name.dropFirst(base.count + 1).isEmpty
                    && name.dropFirst(base.count + 1).allSatisfy(\.isNumber)
            }
            if provider == .qoder {
                if analytics.contains(where: { name.lowercased().hasPrefix($0) }) { continue }
            } else if !allowed.contains(name), !chunked { continue }
            guard !name.isEmpty, !content.isEmpty,
                  !name.contains(" "), !content.contains(" "),
                  !content.contains("\""), !content.contains("\\") else { throw AIQuotaError.credentialInvalid }
            if seen.insert(name).inserted { pairs.append("\(name)=\(content)") }
        }
        guard !pairs.isEmpty, required.isSubset(of: seen) else { throw AIQuotaError.credentialInvalid }
        return pairs.joined(separator: "; ")
    }

    static func gateway(_ input: String, path: String) throws -> URL {
        guard var components = URLComponents(string: input.trimmingCharacters(in: .whitespacesAndNewlines)),
              components.scheme == "https", let host = components.host, !host.isEmpty,
              components.user == nil, components.password == nil,
              components.query == nil, components.fragment == nil else { throw AIQuotaError.invalidAddress }
        let decoded = components.percentEncodedPath.removingPercentEncoding ?? ""
        guard !decoded.split(separator: "/").contains(".."), !decoded.contains("\\") else { throw AIQuotaError.invalidAddress }
        var prefix = components.path
        while prefix.hasSuffix("/") { prefix.removeLast() }
        for suffix in ["/v1/dashboard/billing/subscription", "/v1/dashboard/billing/usage", "/v1/usage", "/v1"] {
            if prefix.hasSuffix(suffix) { prefix.removeLast(suffix.count); break }
        }
        components.path = prefix + path
        guard let url = components.url else { throw AIQuotaError.invalidAddress }
        return url
    }

    static func request(_ url: URL, credential: AIQuotaCredential?, provider: AIQuotaProvider,
                        configuration: AIQuotaConfiguration, post: Bool = false) throws -> URLRequest {
        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let credential {
            let credential = try validatedCredential(credential, provider: provider)
            if provider.usesCookie { request.setValue(credential.token, forHTTPHeaderField: "Cookie") }
            else { request.setValue("\(provider == .copilot ? "token" : "Bearer") \(credential.token)", forHTTPHeaderField: "Authorization") }
        }
        if post {
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = Data("{}".utf8)
        }
        switch provider {
        case .claudeCode:
            request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
            request.setValue("claude-cli (external, cli)", forHTTPHeaderField: "User-Agent")
        case .codex:
            if !configuration.organization.isEmpty { request.setValue(try header(configuration.organization), forHTTPHeaderField: "ChatGPT-Account-Id") }
        case .copilot:
            request.setValue("2025-04-01", forHTTPHeaderField: "X-Github-Api-Version")
            request.setValue("vscode/1.96.2", forHTTPHeaderField: "Editor-Version")
            request.setValue("copilot-chat/0.26.7", forHTTPHeaderField: "Editor-Plugin-Version")
        case .grok: request.setValue("xai-grok-cli", forHTTPHeaderField: "x-xai-token-auth")
        case .grokBot: request.setValue("https://cursor.com", forHTTPHeaderField: "Origin")
        case .ollamaCloud:
            request.setValue("text/html", forHTTPHeaderField: "Accept")
            request.setValue("en-US,en;q=0.9", forHTTPHeaderField: "Accept-Language")
        case .xiaomiMiMo, .qoder:
            let origin = "https://\(url.host ?? "")"
            request.setValue(origin, forHTTPHeaderField: "Origin")
            request.setValue(origin + (provider == .qoder ? "/account/usage" : "/#/console/balance"), forHTTPHeaderField: "Referer")
        case .devin:
            if configuration.organization.hasPrefix("organizations/") {
                request.setValue(String(configuration.organization.dropFirst(14)), forHTTPHeaderField: "x-cog-org-id")
            }
        default: break
        }
        return request
    }
}
