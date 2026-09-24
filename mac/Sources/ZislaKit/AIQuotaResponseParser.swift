// Adapted from upstream provider protocol implementations, revision 86bcb54cff24d4a9c96b4f14066f0098f12e87a6.
// Modified for Zisla's quota model and validation; see Resources/ThirdPartyLicenses/AIQuota-LICENSE.txt.
import CoreFoundation
import Foundation
import ZislaCore

struct AIQuotaParsedResponse: Sendable {
    var windows: [AIQuotaWindow] = []
    var balance: String?
}

enum AIQuotaResponseParser {
    static let maximumWindows = 128
    static func object(_ data: Data) throws -> [String: Any] {
        guard data.count <= AIQuotaURLSessionClient.maximumResponseBytes else { throw AIQuotaError.responseTooLarge }
        guard let result = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw AIQuotaError.invalidResponse
        }
        return result
    }

    static func number(_ value: Any?) -> Double? {
        if let value = value as? NSNumber, CFGetTypeID(value) == CFBooleanGetTypeID() { return nil }
        let value = (value as? NSNumber)?.doubleValue ?? (value as? String).flatMap(Double.init)
        return value.flatMap { $0.isFinite ? $0 : nil }
    }

    static func date(_ value: Any?) -> Date? {
        if let text = value as? String {
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = formatter.date(from: text) { return date }
            formatter.formatOptions = [.withInternetDateTime]
            if let date = formatter.date(from: text) { return date }
            let plain = DateFormatter()
            plain.locale = Locale(identifier: "en_US_POSIX")
            plain.timeZone = TimeZone(secondsFromGMT: 0)
            for format in ["yyyy-MM-dd", "yyyy-MM-dd HH:mm:ss"] {
                plain.dateFormat = format
                if let date = plain.date(from: text) { return date }
            }
        }
        guard let epoch = number(value), epoch > 0 else { return nil }
        return Date(timeIntervalSince1970: epoch > 10_000_000_000 ? epoch / 1_000 : epoch)
    }

    static func label(seconds: Double?) -> String {
        switch seconds {
        case 18_000: "5 小时"
        case 86_400: "每日"
        case 604_800: "每周"
        case 2_592_000: "每月"
        default: "额度"
        }
    }

    static func label(period: String) -> String {
        switch period.lowercased() {
        case "5h", "5-hour", "five_hour", "five-hour", "fivehour", "session", "rolling": "5 小时"
        case "daily", "day", "1d": "每日"
        case "weekly", "week", "7d", "seven_day", "weekly_all", "weekly_scoped": "每周"
        case "monthly", "month": "每月"
        default: "额度"
        }
    }

    static func percent(_ used: Any?, limit: Any?) -> Double? {
        guard let used = number(used), used >= 0, let limit = number(limit), limit > 0 else { return nil }
        return 100 * (1 - min(used / limit, 1))
    }

    private static func window(_ id: String, label: String, remaining: Double?, reset: Any? = nil, scope: String? = nil) -> AIQuotaWindow? {
        guard let remaining, remaining.isFinite, remaining <= 100 else { return nil }
        return AIQuotaWindow(id: id, label: label, remainingPercent: min(100, max(0, remaining)),
                             resetsAt: date(reset), scope: scope)
    }

    private static func money(_ amount: Double?, _ currency: String?) -> String? {
        guard let amount, amount.isFinite, let currency, !currency.isEmpty else { return nil }
        return "\(currency) \(amount.formatted(.number.precision(.fractionLength(2)).locale(AppLocalization.currentLanguage.locale)))"
    }

    static func parse(_ provider: AIQuotaProvider, replies: [String: Data], now: Date) throws -> AIQuotaParsedResponse {
        if provider == .ollamaCloud {
            guard let data = replies["main"] else { throw AIQuotaError.invalidResponse }
            let page = try AIQuotaOllamaPage.parse(data)
            return try current(.init(windows: [
                AIQuotaWindow(id: "session", label: "5 小时", remainingPercent: 100 * (1 - page.session.usedFraction), resetsAt: page.session.resetsAt),
                AIQuotaWindow(id: "weekly", label: "每周", remainingPercent: 100 * (1 - page.weekly.usedFraction), resetsAt: page.weekly.resetsAt),
            ]), at: now)
        }
        let objects = try replies.mapValues(object)
        let root = objects["main"] ?? [:]
        var result = AIQuotaParsedResponse()
        switch provider {
        case .claudeCode:
            for entry in root["limits"] as? [[String: Any]] ?? [] {
                guard let kind = entry["kind"] as? String,
                      ["session", "weekly_all", "weekly_scoped"].contains(kind) else { continue }
                let scope = ((entry["scope"] as? [String: Any])?["model"] as? [String: Any])?["display_name"] as? String
                if let value = window("\(kind).\(scope ?? "all")", label: label(period: kind), remaining: number(entry["percent"]).map { 100 - $0 }, reset: entry["resets_at"], scope: scope) { result.windows.append(value) }
            }
            if result.windows.isEmpty {
                for key in ["five_hour", "seven_day", "seven_day_sonnet", "seven_day_opus"] {
                    let value = root[key] as? [String: Any] ?? [:]
                    if let item = window(key, label: key == "five_hour" ? "5 小时" : "每周", remaining: number(value["utilization"]).map { 100 - $0 }, reset: value["resets_at"], scope: key.hasSuffix("sonnet") ? "Sonnet" : key.hasSuffix("opus") ? "Opus" : nil) { result.windows.append(item) }
                }
            }
        case .codex:
            var groups = [("account", root["rate_limit"] as? [String: Any] ?? [:], Optional<String>.none)]
            for extra in root["additional_rate_limits"] as? [[String: Any]] ?? [] {
                let name = extra["limit_name"] as? String
                groups.append((extra["metered_feature"] as? String ?? name ?? "extra", extra["rate_limit"] as? [String: Any] ?? [:], name))
            }
            for (id, group, scope) in groups {
                for key in ["primary_window", "secondary_window"] {
                    let value = group[key] as? [String: Any] ?? [:]
                    if let item = window("\(id).\(key)", label: label(seconds: number(value["limit_window_seconds"])), remaining: number(value["used_percent"]).map { 100 - $0 }, reset: value["reset_at"], scope: scope) { result.windows.append(item) }
                }
            }
            let credit = root["credits"] as? [String: Any] ?? [:]
            if credit["unlimited"] as? Bool != true, let amount = number(credit["balance"]) {
                result.balance = AppLocalization.text("%@ 积分", amount.formatted())
            }
        case .kiro:
            guard root["success"] as? Bool == true else { throw AIQuotaError.credentialUnavailable }
            let data = root["data"] as? [String: Any] ?? [:]
            for value in data["usageBreakdowns"] as? [[String: Any]] ?? [] {
                guard value["hasLimit"] as? Bool != false, let limit = number(value["limit"]), limit > 0 else { continue }
                let id = value["resourceType"] as? String ?? value["displayName"] as? String ?? "usage"
                let remaining = percent(value["used"], limit: limit) ?? number(value["percentage"]).map { 100 - $0 }
                if let item = window(id, label: "每月", remaining: remaining, reset: data["billingCycleReset"], scope: value["displayName"] as? String) { result.windows.append(item) }
            }
        case .antigravity:
            let data = root["response"] as? [String: Any] ?? [:]
            for group in data["groups"] as? [[String: Any]] ?? [] {
                for value in group["buckets"] as? [[String: Any]] ?? [] {
                    guard let id = value["bucketId"] as? String, let period = value["window"] as? String else { continue }
                    let title = label(period: period)
                    let timed = ["h", "d"].contains(period.suffix(1)) && (number(String(period.dropLast())) ?? 0) > 0
                    guard title != "额度" || timed else { continue }
                    if let item = window(id, label: title == "额度" ? period : title, remaining: number(value["remainingFraction"]).map { $0 * 100 }, reset: value["resetTime"], scope: group["displayName"] as? String) { result.windows.append(item) }
                }
            }
        case .cursor:
            let individual = root["individualUsage"] as? [String: Any] ?? [:]
            let team = root["teamUsage"] as? [String: Any] ?? [:]
            let plan = individual["plan"] as? [String: Any] ?? team["pooled"] as? [String: Any] ?? [:]
            for (key, title) in [("autoPercentUsed", "Cursor 模型"), ("apiPercentUsed", "其他模型")] {
                if let value = window(key, label: title, remaining: number(plan[key]).map { 100 - $0 }, reset: root["billingCycleEnd"]) { result.windows.append(value) }
            }
            if result.windows.isEmpty, plan["enabled"] as? Bool != false,
               let value = window("plan", label: "每月", remaining: percent(plan["used"], limit: plan["limit"]), reset: root["billingCycleEnd"]) { result.windows.append(value) }
            let extra = individual["onDemand"] as? [String: Any] ?? team["onDemand"] as? [String: Any] ?? [:]
            if extra["enabled"] as? Bool != false,
               let value = window("onDemand", label: "额外用量", remaining: percent(extra["used"], limit: extra["limit"]), reset: root["billingCycleEnd"]) { result.windows.append(value) }
            result.balance = money(number(plan["remaining"]).map { $0 / 100 }, "USD")
        case .openCodeGo:
            let usage = root["usage"] as? [String: Any] ?? [:]
            for key in ["rolling", "weekly", "monthly"] {
                let value = usage[key] as? [String: Any] ?? [:]
                if let item = window(key, label: label(period: key), remaining: number(value["percent"]).map { 100 - $0 }, reset: value["resetsAt"]) { result.windows.append(item) }
            }
        case .kimiCode:
            var values = (root["limits"] as? [[String: Any]] ?? []).compactMap { entry -> (String, String, [String: Any])? in
                let period = entry["window"] as? [String: Any] ?? [:]
                let multiplier: [String: Double] = ["TIME_UNIT_SECOND": 1, "TIME_UNIT_MINUTE": 60, "TIME_UNIT_HOUR": 3_600, "TIME_UNIT_DAY": 86_400]
                let seconds = number(period["duration"]).flatMap { duration in (period["timeUnit"] as? String).flatMap { multiplier[$0].map { $0 * duration } } }
                guard let seconds, seconds.isFinite, seconds > 0 else { return nil }
                return ("limit.\(seconds)", label(seconds: seconds), entry["detail"] as? [String: Any] ?? [:])
            }
            if let weekly = root["usage"] as? [String: Any] { values.append(("weekly", "每周", weekly)) }
            for (id, title, value) in values {
                let used = number(value["used"]) ?? number(value["limit"]).flatMap { limit in number(value["remaining"]).map { limit - $0 } }
                if let item = window(id, label: title, remaining: percent(used, limit: value["limit"]), reset: value["resetTime"]) { result.windows.append(item) }
            }
        case .zai, .glmCoding:
            guard root["success"] as? Bool == true, number(root["code"]) == 200 else {
                throw envelopeError(number(root["code"]))
            }
            let data = root["data"] as? [String: Any] ?? [:]
            for value in data["limits"] as? [[String: Any]] ?? [] {
                guard let type = value["type"] as? String, ["TOKENS_LIMIT", "CREDIT_LIMIT", "TIME_LIMIT"].contains(type) else { continue }
                let units: [Double: Double] = [1: 86_400, 3: 3_600, 5: 60, 6: 604_800]
                let seconds = number(value["unit"]).flatMap { units[$0] }.flatMap { unit in number(value["number"]).map { unit * $0 } }
                let total = number(value["usage"])
                let used = number(value["currentValue"]) ?? total.flatMap { total in number(value["remaining"]).map { total - $0 } }
                let remaining = percent(used, limit: total) ?? number(value["percentage"]).map { 100 - $0 }
                let title = type == "TIME_LIMIT" && seconds == 60 ? "每月" : label(seconds: seconds)
                let id = "\(type).\(number(value["unit"]) ?? 0).\(number(value["number"]) ?? 0)"
                if let item = window(id, label: title, remaining: remaining, reset: value["nextResetTime"], scope: type == "TIME_LIMIT" ? "MCP" : nil) { result.windows.append(item) }
            }
        case .minimax, .minimaxCN:
            let status = number((root["base_resp"] as? [String: Any])?["status_code"]) ?? 0
            guard status == 0 else { throw status == 1004 ? AIQuotaError.credentialRejected : AIQuotaError.server }
            let data = root["data"] as? [String: Any] ?? root
            for (index, value) in (data["model_remains"] as? [[String: Any]] ?? []).enumerated() {
                let model = value["model_name"] as? String ?? "\(index)"
                for period in ["interval", "weekly"] {
                    let prefix = "current_\(period)_"
                    let total = number(value[prefix + "total_count"])
                    let remaining = number(value[prefix + "remaining_percent"])
                        ?? total.flatMap { total in total > 0 ? number(value[prefix + "usage_count"]).map { 100 * $0 / total } : nil }
                    if number(value[prefix + "status"]) == 3 && (total ?? 0) == 0 && (remaining ?? 0) >= 100 { continue }
                    let title = period == "weekly" ? "每周" : label(seconds: number(value["end_time"]).flatMap { end in number(value["start_time"]).map { (end - $0) / 1_000 } })
                    if let item = window("\(model).\(period)", label: title, remaining: remaining, reset: value[period == "weekly" ? "weekly_end_time" : "end_time"], scope: model == "general" ? nil : model) { result.windows.append(item) }
                }
            }
        case .copilot:
            let quotas = root["quota_snapshots"] as? [String: Any] ?? [:]
            for (key, title) in [("premium_interactions", "高级请求"), ("chat", "对话"), ("completions", "补全")] {
                let value = quotas[key] as? [String: Any] ?? [:]
                guard value["has_quota"] as? Bool != false, value["unlimited"] as? Bool != true else { continue }
                let remaining = number(value["percent_remaining"])
                if value["has_quota"] == nil, (number(value["entitlement"]) ?? 0) <= 0, (number(value["remaining"]) ?? 0) <= 0, (remaining ?? 0) >= 100 { continue }
                if let item = window(key, label: title, remaining: remaining, reset: root["quota_reset_date_utc"] ?? root["quota_reset_date"]) { result.windows.append(item) }
            }
        case .grok:
            let config = root["config"] as? [String: Any] ?? [:]
            let period = config["currentPeriod"] as? [String: Any] ?? [:]
            guard let start = date(period["start"] ?? config["billingPeriodStart"]), let end = date(period["end"] ?? config["billingPeriodEnd"]), end > start else { throw AIQuotaError.noQuota }
            let used = number(config["creditUsagePercent"]) ?? ((start...end).contains(now) ? 0 : nil)
            if let item = window("pool", label: "额度", remaining: used.map { 100 - $0 }, reset: period["end"] ?? config["billingPeriodEnd"]) { result.windows.append(item) }
        case .grokBot:
            guard root["usesPooledEnterpriseAllowance"] as? Bool != true, root["includedLimitZero"] as? Bool != true,
                  root["hasNonZeroIncludedLimit"] as? Bool == true else { throw AIQuotaError.noQuota }
            if let item = window("weekly", label: "每周", remaining: number(root["usagePercent"]).map { 100 - $0 }, reset: root["nextResetTimestampUtc"]) { result.windows.append(item) }
        case .volcengine:
            let coding = objects["coding"]?["Result"] as? [String: Any] ?? [:]
            for value in coding["QuotaUsage"] as? [[String: Any]] ?? [] {
                guard let period = value["Level"] as? String,
                      ["5h", "5-hour", "five_hour", "session", "weekly", "week", "monthly", "month"].contains(period.lowercased()) else { continue }
                if let item = window("coding.\(period)", label: label(period: period), remaining: number(value["Percent"]).map { 100 - $0 }, reset: value["ResetTimestamp"], scope: "Coding Plan") { result.windows.append(item) }
            }
            let agent = objects["agent"]?["Result"] as? [String: Any] ?? [:]
            for (key, title) in [("AFPFiveHour", "5 小时"), ("AFPWeekly", "每周"), ("AFPMonthly", "每月")] {
                let value = agent[key] as? [String: Any] ?? [:]
                if let item = window(key, label: title, remaining: percent(value["Used"], limit: value["Quota"]), reset: value["ResetTime"], scope: "Agent Plan") { result.windows.append(item) }
            }
        case .commandCode:
            let limits = root["windowLimits"] as? [String: Any] ?? [:]
            if limits["limited"] as? Bool == true {
                for (key, title) in [("fiveHour", "5 小时"), ("weekly", "每周")] {
                    let value = limits[key] as? [String: Any] ?? [:]
                    if let item = window(key, label: title, remaining: percent(value["used"], limit: value["cap"]), reset: value["resetAt"]) { result.windows.append(item) }
                }
            }
            for value in objects["whoami"]?["orgLimits"] as? [[String: Any]] ?? [] {
                let scope = value["model"] as? String ?? "org"
                let period = value["resetInterval"] as? String ?? "total"
                if let item = window("org.\(scope).\(period)", label: label(period: period), remaining: percent(value["spent"], limit: value["limit"]), reset: value["resetAt"], scope: value["modelLabel"] as? String) { result.windows.append(item) }
            }
            let credits = root["credits"] as? [String: Any] ?? [:]
            let amounts = ["monthlyCredits", "purchasedCredits", "freeCredits"].compactMap { number(credits[$0]) }
            if !amounts.isEmpty { result.balance = money(amounts.reduce(0, +), "USD") }
        case .deepSeek:
            result.balance = (root["balance_infos"] as? [[String: Any]] ?? []).compactMap {
                money(number($0["total_balance"]), $0["currency"] as? String)
            }.joined(separator: " · ")
            if result.balance?.isEmpty == true { result.balance = nil }
        case .devin:
            if root["has_quota_allocation"] as? Bool != false {
                for (key, title) in [("daily", "每日"), ("weekly", "每周")] where root["hide_\(key)_quota"] as? Bool != true {
                    if let item = window(key, label: title, remaining: number(root["\(key)_percentage"]).map { 100 - $0 }, reset: root["\(key)_reset_at"]) { result.windows.append(item) }
                }
            }
            result.balance = money(number(root["overage_balance"]) ?? number(root["overage_balance_cents"]).map { $0 / 100 }, "USD")
        case .xiaomiMiMo:
            for object in objects.values {
                if let code = number(object["code"]), code != 0 { throw envelopeError(code) }
            }
            let detail = objects["detail"]?["data"] as? [String: Any] ?? [:]
            let month = (root["data"] as? [String: Any])?["monthUsage"] as? [String: Any] ?? [:]
            if detail["expired"] as? Bool != true, let first = (month["items"] as? [[String: Any]])?.first,
               let item = window("monthly", label: "每月", remaining: percent(first["used"], limit: first["limit"]), reset: detail["currentPeriodEnd"]) { result.windows.append(item) }
            let balance = objects["balance"]?["data"] as? [String: Any] ?? [:]
            result.balance = money(number(balance["balance"]), balance["currency"] as? String)
        case .sub2api:
            guard root["isValid"] as? Bool != false else { throw AIQuotaError.credentialRejected }
            for value in root["rate_limits"] as? [[String: Any]] ?? [] {
                guard let period = value["window"] as? String else { continue }
                if let item = window("rate.\(period)", label: label(period: period), remaining: percent(value["used"], limit: value["limit"]), reset: value["reset_at"]) { result.windows.append(item) }
            }
            let quota = root["quota"] as? [String: Any] ?? [:]
            if let item = window("quota", label: "额度", remaining: percent(quota["used"], limit: quota["limit"])) { result.windows.append(item) }
            let subscription = root["subscription"] as? [String: Any] ?? [:]
            for period in ["daily", "weekly", "monthly"] {
                if let item = window("subscription.\(period)", label: label(period: period), remaining: percent(subscription["\(period)_usage_usd"], limit: subscription["\(period)_limit_usd"])) { result.windows.append(item) }
            }
            let walletOnly = root["quota"] == nil && root["subscription"] == nil
            let amount = number(root["balance"]) ?? (walletOnly ? number(root["remaining"]) : nil)
            let reportedUnit = (root["unit"] as? String ?? quota["unit"] as? String ?? "USD")
                .trimmingCharacters(in: .whitespaces).uppercased()
            let currency = reportedUnit.isEmpty ? "USD" : reportedUnit
            if currency.utf8.count == 3, currency.utf8.allSatisfy({ (65...90).contains($0) }) {
                result.balance = money(amount, currency)
            }
        case .newAPI:
            let status = objects["status"] ?? [:]
            guard status["success"] as? Bool != false else { throw AIQuotaError.invalidResponse }
            if ["hard_limit_usd", "soft_limit_usd", "system_hard_limit_usd"].allSatisfy({ number(root[$0]) == 100_000_000 }) { throw AIQuotaError.noQuota }
            let settings = status["data"] as? [String: Any] ?? [:]
            let kind = (settings["quota_display_type"] as? String)?.uppercased()
                ?? (settings["display_in_currency"] as? Bool == true ? "USD" : "")
            if ["USD", "CNY"].contains(kind), let total = number(root["hard_limit_usd"]), let used = number(objects["usage"]?["total_usage"]) {
                result.balance = money(total - used / 100, kind)
            }
        case .v2ex:
            guard root["success"] as? Bool == true else { throw AIQuotaError.invalidResponse }
            let quota = root["result"] as? [String: Any] ?? [:]
            if let item = window("window", label: "5 小时", remaining: percent(quota["used_tokens"], limit: quota["total_tokens"]), reset: quota["active"] as? Bool == true ? quota["period_end"] : nil) { result.windows.append(item) }
            let extra = quota["extra_usage"] as? [String: Any] ?? [:]
            if (number(extra["pack_count"]) ?? 0) > 0, let item = window("extra", label: "额外用量", remaining: percent(extra["used_tokens"], limit: extra["total_tokens"])) { result.windows.append(item) }
        case .qoder:
            for (camel, snake, title) in [("totalQuota", "total_quota", "个人积分"), ("sharedQuota", "shared_quota", "团队积分")] {
                let container = root[camel] as? [String: Any] ?? root[snake] as? [String: Any] ?? [:]
                let value = container["quotaSummary"] as? [String: Any] ?? container["quota_summary"] as? [String: Any] ?? [:]
                if let item = window(camel, label: title, remaining: percent(value["usedValue"] ?? value["used_value"], limit: value["limitValue"] ?? value["limit_value"]), reset: camel == "totalQuota" ? root["nextResetAt"] ?? root["next_reset_at"] : nil) { result.windows.append(item) }
            }
        case .ollamaCloud: break
        }
        return try current(result, at: now)
    }

    private static func current(_ parsed: AIQuotaParsedResponse, at now: Date) throws -> AIQuotaParsedResponse {
        var result = parsed
        guard result.windows.count <= maximumWindows else { throw AIQuotaError.responseTooLarge }
        let groups = Dictionary(grouping: result.windows, by: \.id)
        var seen: Set<String> = []
        // Conflicting pools without distinct service IDs cannot safely share an alert baseline.
        result.windows.removeAll { item in
            groups[item.id]?.contains(where: { $0 != item }) == true || !seen.insert(item.id).inserted
        }
        result.windows.removeAll { $0.resetsAt.map { $0 <= now } ?? false }
        guard !result.windows.isEmpty || result.balance != nil else { throw AIQuotaError.noQuota }
        return result
    }

    private static func envelopeError(_ code: Double?) -> AIQuotaError {
        if code == 401 || code == 403 || (code.map { (1_000...1_099).contains($0) } ?? false) { return .credentialRejected }
        return code == 429 ? .rateLimited : .server
    }
}
