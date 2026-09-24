import Foundation
import Testing

@testable import ZislaCore
@testable import ZislaKit

final class AIQuotaMemoryCredentials: AIQuotaCredentialStoring, @unchecked Sendable {
    private let lock = NSLock()
    private var values: [String: AIQuotaCredential] = [:]
    private var reads: [String] = []
    private var writes: [String] = []
    var rejectWrites = false
    var rejectReads = false
    var rejectRemovals = false

    var readIDs: [String] { lock.withLock { reads } }
    var writeIDs: [String] { lock.withLock { writes } }
    var stored: [String: AIQuotaCredential] { lock.withLock { values } }

    func read(id: String) throws -> AIQuotaCredential? {
        try lock.withLock {
            reads.append(id)
            if rejectReads { throw AIQuotaError.storageUnavailable }
            return values[id]
        }
    }

    func write(_ credential: AIQuotaCredential, id: String) throws {
        try lock.withLock {
            if rejectWrites { throw AIQuotaError.storageUnavailable }
            writes.append(id)
            values[id] = credential
        }
    }

    func remove(id: String) throws {
        try lock.withLock {
            if rejectRemovals { throw AIQuotaError.storageUnavailable }
            values.removeValue(forKey: id)
        }
    }
}

actor AIQuotaMockHTTP: AIQuotaHTTPClient {
    let replies: [Result<Data, AIQuotaError>]
    private(set) var requests: [URLRequest] = []
    private(set) var trustedLoopback: [Bool] = []

    init(_ replies: [Result<Data, AIQuotaError>]) { self.replies = replies }

    func data(for request: URLRequest, trustLoopback: Bool) async throws -> Data {
        requests.append(request)
        trustedLoopback.append(trustLoopback)
        guard replies.indices.contains(requests.count - 1) else { throw AIQuotaError.invalidResponse }
        return try replies[requests.count - 1].get()
    }
}

actor AIQuotaSleepGate {
    private var continuations: [Int: CheckedContinuation<Void, Never>] = [:]
    private(set) var durations: [Duration] = []
    private var closed = false

    func sleep(_ duration: Duration) async {
        guard !closed else { return }
        let index = durations.count
        durations.append(duration)
        await withCheckedContinuation { continuations[index] = $0 }
    }

    func release(_ index: Int) { continuations.removeValue(forKey: index)?.resume() }
    func releaseAll() {
        closed = true
        let pending = continuations.values
        continuations.removeAll()
        for continuation in pending { continuation.resume() }
    }
}

func aiQuotaEventually(_ condition: @escaping @Sendable () async -> Bool) async -> Bool {
    for _ in 0..<500 {
        if await condition() { return true }
        try? await Task.sleep(for: .milliseconds(2))
    }
    return false
}

extension AIQuotaFixtures {
    static func replies(_ provider: AIQuotaProvider) -> [String: Data] {
        func fixture(_ name: String) -> [String: Data] { ["main": reference[name]!] }
        func main(_ value: String) -> [String: Data] { ["main": Data(value.utf8)] }
        switch provider {
        case .claudeCode:
            return main(#"{"five_hour":{"utilization":20,"resets_at":"2030-01-01T00:00:00Z"},"seven_day":{"utilization":45}}"#)
        case .codex:
            return main(#"{"rate_limit":{"primary_window":{"used_percent":25,"limit_window_seconds":86400},"secondary_window":{"used_percent":90,"limit_window_seconds":604800}}}"#)
        case .kiro: return fixture("kiro-pro-plus-usage")
        case .antigravity: return fixture("antigravity-quota")
        case .cursor:
            return main(#"{"individualUsage":{"plan":{"autoPercentUsed":25,"apiPercentUsed":40,"remaining":1250}},"billingCycleEnd":"2030-01-01T00:00:00Z"}"#)
        case .openCodeGo:
            return main(#"{"usage":{"rolling":{"percent":20},"weekly":{"percent":30},"monthly":{"percent":40}}}"#)
        case .kimiCode:
            return main(#"{"limits":[{"window":{"duration":5,"timeUnit":"TIME_UNIT_HOUR"},"detail":{"limit":100,"used":25}}],"usage":{"limit":100,"remaining":20}}"#)
        case .ollamaCloud:
            return main(#"<html><body><div data-usage-meter="session"><h2>Session usage</h2><span>25% used</span><span data-time="2030-01-01T00:00:00Z"></span></div><div data-usage-meter="weekly"><h2>Weekly usage</h2><span>60% used</span></div></body></html>"#)
        case .zai, .glmCoding: return fixture("glm-coding-plan-quota")
        case .minimax, .minimaxCN:
            return main(#"{"base_resp":{"status_code":0},"model_remains":[{"model_name":"general","start_time":1800000000000,"end_time":1800018000000,"current_interval_total_count":100,"current_interval_usage_count":60,"current_weekly_total_count":1000,"current_weekly_usage_count":850}]}"#)
        case .copilot:
            return main(#"{"quota_snapshots":{"premium_interactions":{"has_quota":true,"percent_remaining":75},"chat":{"unlimited":true,"percent_remaining":100}}}"#)
        case .grok:
            return main(#"{"config":{"creditUsagePercent":25,"currentPeriod":{"start":"2023-01-01T00:00:00Z","end":"2030-01-01T00:00:00Z"}}}"#)
        case .grokBot:
            return main(#"{"hasNonZeroIncludedLimit":true,"usagePercent":25,"nextResetTimestampUtc":"2030-01-01T00:00:00Z"}"#)
        case .volcengine:
            return ["coding": reference["volcengine-coding-plan"]!, "agent": reference["volcengine-agent-plan"]!]
        case .commandCode:
            return ["main": reference["command-code-credits"]!, "whoami": reference["command-code-whoami"]!]
        case .deepSeek: return fixture("deepseek-balance")
        case .devin: return fixture("devin-quota-usage")
        case .xiaomiMiMo:
            return ["main": reference["xiaomi-plan-usage"]!, "detail": reference["xiaomi-plan-detail"]!, "balance": reference["xiaomi-balance"]!]
        case .sub2api: return fixture("sub2api-quota")
        case .newAPI:
            return ["main": reference["newapi-subscription"]!, "usage": reference["newapi-usage"]!, "status": reference["newapi-status-usd"]!]
        case .v2ex: return fixture("v2ex-quota")
        case .qoder: return fixture("qoder-credits")
        }
    }

    static func configuration(_ provider: AIQuotaProvider) -> AIQuotaConfiguration {
        var value = AIQuotaConfiguration(id: "test-\(provider.rawValue)", provider: provider)
        if !provider.requiresLocalClient { value.source = .manual }
        if provider.usesGateway { value.baseURL = "https://quota.example.test/prefix/v1" }
        if provider == .devin { value.organization = "https://app.devin.ai/org/example/settings" }
        if provider == .codex { value.organization = "acct-test" }
        return value
    }

    static func credential(_ configuration: AIQuotaConfiguration) -> AIQuotaCredential {
        let token: String
        switch configuration.provider {
        case .cursor, .grokBot: token = "WorkosCursorSessionToken=fictional"
        case .ollamaCloud: token = "wos-session=fictional"
        case .xiaomiMiMo: token = "api-platform_serviceToken=fictional; userId=42"
        case .qoder: token = "qoder-session=fictional"
        default: token = "fictional-token"
        }
        return AIQuotaCredential(token: token, secret: "fictional-secret", scope: AIQuotaRequestBuilder.credentialScope(configuration))
    }
}
