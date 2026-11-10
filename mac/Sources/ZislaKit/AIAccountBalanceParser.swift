import Foundation
import ZislaCore

// Wire schemas from CodexBar 7447bc77 and token-monitor 235a77c3 (MIT).
enum AIAccountBalanceParser {
    static func parse(_ data: Data, provider: AIProvider, now: Date) throws -> [AIAccountQuotaWindow] {
        if provider == .grok { return try AIAccountGrokQuotaParser.parse(data, now: now) }
        let root = try AIAccountBalanceCredentials.object(data)
        let windows: [AIAccountQuotaWindow]
        switch provider {
        case .copilot: windows = try copilot(root)
        case .coder: windows = try qoder(root)
        case .trae: windows = try trae(root)
        case .claude: windows = try claude(root)
        case .codex, .gpt: windows = try codex(root)
        case .gemini: windows = try gemini(root)
        case .kimi: windows = try kimi(root)
        case .cursor, .grokBot: windows = try cursor(root, now: now)
        case .zcode: windows = try zcode(root)
        case .zed: windows = try zed(root)
        case .workbuddy, .workbuddyAI: windows = try workbuddy(root)
        case .opencode: windows = try opencode(root)
        case .muse: windows = try muse(root)
        default: throw AIAccountBalanceError.noQuota
        }
        guard !windows.isEmpty else { throw AIAccountBalanceError.noQuota }
        guard windows.count <= 64, windows.allSatisfy(\.isValid), Set(windows.map(\.id)).count == windows.count else {
            throw AIAccountBalanceError.invalidResponse
        }
        return windows
    }

    static func date(_ value: Any?, milliseconds: Bool = false, acceptsDateOnly: Bool = false) throws -> Date? {
        guard let value, !(value is NSNull) else { return nil }
        let seconds: Double?
        if let numeric = AIAccountBalanceCredentials.number(value) { seconds = numeric / (milliseconds ? 1_000 : 1) }
        else if let text = value as? String {
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let timestamp = formatter.date(from: text) ?? ISO8601DateFormatter().date(from: text) {
                seconds = timestamp.timeIntervalSince1970
            } else if acceptsDateOnly, text.range(of: #"^\d{4}-\d{2}-\d{2}$"#, options: .regularExpression) != nil {
                let day = DateFormatter()
                day.locale = Locale(identifier: "en_US_POSIX")
                day.timeZone = TimeZone(secondsFromGMT: 0)
                day.dateFormat = "yyyy-MM-dd"
                day.isLenient = false
                let timestamp = day.date(from: text)
                seconds = timestamp.flatMap { day.string(from: $0) == text ? $0.timeIntervalSince1970 : nil }
            } else { seconds = nil }
        } else { seconds = nil }
        guard let seconds, seconds > 0, seconds < 253_402_300_800 else { throw AIAccountBalanceError.invalidResponse }
        return Date(timeIntervalSince1970: seconds)
    }

    static func number(_ value: Any?) throws -> Double {
        guard let number = AIAccountBalanceCredentials.number(value), number >= 0 else { throw AIAccountBalanceError.invalidResponse }
        return number
    }

    static func percent(_ value: Any?) throws -> Double {
        let value = try number(value)
        guard value <= 100 else { throw AIAccountBalanceError.invalidResponse }
        return value
    }

    static func kind(duration: Double?) -> AIAccountQuotaKind {
        switch duration {
        case 18_000: .fiveHours
        case 86_400: .daily
        case 604_800: .weekly
        default: duration.map { $0 < 86_400 ? .rolling : .all } ?? .all
        }
    }

    private static func object(_ value: Any?) throws -> [String: Any] {
        guard let object = value as? [String: Any] else { throw AIAccountBalanceError.invalidResponse }
        return object
    }

    private static func claude(_ root: [String: Any]) throws -> [AIAccountQuotaWindow] {
        var windows: [AIAccountQuotaWindow] = []
        for (key, kind, name) in [("five_hour", AIAccountQuotaKind.fiveHours, nil),
                                  ("seven_day", .weekly, nil), ("seven_day_opus", .model, "Opus"),
                                  ("seven_day_sonnet", .model, "Sonnet"), ("seven_day_oauth_apps", .model, "OAuth"),
                                  ("seven_day_routines", .model, "Routines")] as [(String, AIAccountQuotaKind, String?)] {
            guard let raw = root[key], !(raw is NSNull) else { continue }
            let value = try object(raw)
            windows.append(.init(id: key, kind: kind, remainingPercent: 100 - (try percent(value["utilization"])),
                resetsAt: try date(value["resets_at"]), durationSeconds: key == "five_hour" ? 18_000 : 604_800, name: name))
        }
        if let raw = root["extra_usage"], !(raw is NSNull) {
            let extra = try object(raw)
            if extra["is_enabled"] as? Bool == true {
                let used = try number(extra["used_credits"])
                let cap = try number(extra["monthly_limit"])
                windows.append(amount(id: "extra_usage", kind: .budget, used: used, cap: cap, unit: .usd, scale: 100))
            }
        }
        return windows
    }

    private static func codex(_ root: [String: Any]) throws -> [AIAccountQuotaWindow] {
        var windows: [AIAccountQuotaWindow] = []
        if let raw = root["rate_limit"], !(raw is NSNull) {
            windows += try codexWindows(object(raw))
        }
        if let raw = root["additional_rate_limits"], !(raw is NSNull) {
            guard let entries = raw as? [[String: Any]], entries.count <= 64 else { throw AIAccountBalanceError.invalidResponse }
            var features: Set<String> = []
            for entry in entries {
                guard let feature = entry["metered_feature"] as? String,
                      !feature.isEmpty, feature.utf8.count <= 160,
                      !feature.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains),
                      feature != "codex", features.insert(feature).inserted else { throw AIAccountBalanceError.invalidResponse }
                let name = entry["limit_name"] as? String ?? feature
                guard !name.isEmpty, name.utf8.count <= 160,
                      !name.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains) else {
                    throw AIAccountBalanceError.invalidResponse
                }
                if let limit = entry["rate_limit"], !(limit is NSNull) {
                    windows += try codexWindows(object(limit), prefix: "additional:" + feature + ":", name: name)
                }
            }
        }
        if let raw = root["credits"], !(raw is NSNull) {
            let credits = try object(raw)
            if credits["unlimited"] as? Bool == true {
                windows.append(.init(id: "credits", kind: .credits, unit: .credits, unlimited: true))
            } else if credits["has_credits"] as? Bool == true, let balance = credits["balance"], !(balance is NSNull) {
                windows.append(.init(id: "credits", kind: .credits, remaining: try number(balance), unit: .credits))
            }
        }
        if let raw = root["spend_control"], !(raw is NSNull) {
            let control = try object(raw)
            if let raw = control["individual_limit"], !(raw is NSNull) {
                let limit = try object(raw)
                let cap = try number(limit["limit"])
                let reset = try date(limit["reset_at"] ?? limit["resets_at"])
                if let raw = limit["used"], !(raw is NSNull) {
                    windows.append(amount(id: "spend_control", kind: .credits, used: try number(raw), cap: cap, unit: .credits, reset: reset))
                } else if let raw = limit["remaining_percent"], !(raw is NSNull) {
                    let left = try percent(raw)
                    windows.append(.init(id: "spend_control", kind: .credits, remainingPercent: left,
                        remaining: cap * left / 100, limit: cap, unit: .credits, resetsAt: reset))
                } else { throw AIAccountBalanceError.invalidResponse }
            }
        }
        return windows
    }

    private static func codexWindows(_ limits: [String: Any], prefix: String = "", name: String? = nil) throws -> [AIAccountQuotaWindow] {
        var windows: [AIAccountQuotaWindow] = []
        for key in ["primary_window", "secondary_window"] {
            guard let raw = limits[key], !(raw is NSNull) else { continue }
            let window = try object(raw)
            let rawDuration = window["limit_window_seconds"]
            let duration = try rawDuration == nil || rawDuration is NSNull ? nil : number(rawDuration)
            windows.append(.init(id: prefix + key, kind: kind(duration: duration),
                remainingPercent: 100 - (try percent(window["used_percent"])),
                resetsAt: try date(window["reset_at"]), durationSeconds: duration, name: name))
        }
        return windows
    }

    private static func gemini(_ root: [String: Any]) throws -> [AIAccountQuotaWindow] {
        guard let buckets = root["buckets"] as? [[String: Any]], buckets.count <= 128 else { throw AIAccountBalanceError.invalidResponse }
        var models: [String: AIAccountQuotaWindow] = [:]
        for bucket in buckets {
            guard let model = bucket["modelId"] as? String, !model.isEmpty, model.utf8.count <= 160,
                  !model.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains) else {
                throw AIAccountBalanceError.invalidResponse
            }
            let fraction = try number(bucket["remainingFraction"])
            guard fraction <= 1 else { throw AIAccountBalanceError.invalidResponse }
            let window = AIAccountQuotaWindow(id: "model:" + model, kind: .model, remainingPercent: fraction * 100,
                resetsAt: try date(bucket["resetTime"]), name: model)
            if models[model].map({ ($0.remainingPercent ?? 100) <= fraction * 100 }) != true { models[model] = window }
        }
        return models.keys.sorted().compactMap { models[$0] }
    }

    private static func kimi(_ root: [String: Any]) throws -> [AIAccountQuotaWindow] {
        var windows: [AIAccountQuotaWindow] = []
        if let raw = root["usages"], !(raw is NSNull) {
            let pools = try object(raw)
            for (key, kind, duration) in [("limit_5h", AIAccountQuotaKind.fiveHours, 18_000.0),
                                           ("limit_7d", .weekly, 604_800), ("limit_month_total", .monthly, nil)] as [(String, AIAccountQuotaKind, Double?)] {
                guard let raw = pools[key], !(raw is NSNull) else { continue }
                let pool = try object(raw)
                let ratio = try number(pool["used_ratio"])
                guard ratio <= 1 else { throw AIAccountBalanceError.invalidResponse }
                windows.append(.init(id: key, kind: kind, remainingPercent: 100 - ratio * 100,
                    resetsAt: try date(pool["reset_time"]), durationSeconds: duration))
            }
            if !windows.isEmpty { return windows }
        }
        if let raw = root["usage"], !(raw is NSNull) {
            windows.append(try kimiDetail(object(raw), id: "usage", kind: .all, duration: nil))
        }
        if let raw = root["limits"], !(raw is NSNull) {
            guard let limits = raw as? [[String: Any]], limits.count <= 32 else { throw AIAccountBalanceError.invalidResponse }
            for (index, limit) in limits.enumerated() {
                let window = try object(limit["window"])
                let duration = try number(window["duration"])
                let multiplier: Double
                switch window["timeUnit"] as? String {
                case "TIME_UNIT_MINUTE": multiplier = 60
                case "TIME_UNIT_HOUR": multiplier = 3_600
                case "TIME_UNIT_DAY": multiplier = 86_400
                default: throw AIAccountBalanceError.invalidResponse
                }
                guard duration > 0 else { throw AIAccountBalanceError.invalidResponse }
                let seconds = duration * multiplier
                windows.append(try kimiDetail(object(limit["detail"]), id: "limit:\(index)", kind: kind(duration: seconds), duration: seconds))
            }
        }
        return windows
    }

    private static func kimiDetail(_ detail: [String: Any], id: String, kind: AIAccountQuotaKind,
                                   duration: Double?) throws -> AIAccountQuotaWindow {
        let cap = try number(detail["limit"])
        let remaining: Double
        if let raw = detail["remaining"], !(raw is NSNull) { remaining = min(cap, try number(raw)) }
        else { remaining = max(0, cap - (try number(detail["used"]))) }
        return .init(id: id, kind: kind, remainingPercent: cap > 0 ? remaining / cap * 100 : nil,
            remaining: remaining, limit: cap, unit: .requests,
            resetsAt: try date(detail["resetTime"] ?? detail["resetAt"] ?? detail["reset_time"] ?? detail["reset_at"]),
            durationSeconds: duration)
    }

    static func cursor(_ root: [String: Any], now: Date, sand: [String: Any]? = nil,
                       unified: [String: Any]? = nil) throws -> [AIAccountQuotaWindow] {
        let isUnified = (root["membershipType"] as? String)?.lowercased().hasPrefix("unified_") == true
            && (root["limitType"] as? String)?.lowercased() == "user"
        var windows: [AIAccountQuotaWindow] = []
        if let sand, sand["hasNonZeroIncludedLimit"] as? Bool == true || sand["includedLimitZero"] as? Bool == false {
            windows.append(.init(id: "grok_bot", kind: .weekly,
                remainingPercent: 100 - (try percent(sand["usagePercent"])),
                resetsAt: try date(sand["nextResetTimestampUtc"]), durationSeconds: 604_800,
                name: isUnified || sand["isUnified"] as? Bool == true ? nil : "Grok Bot"))
        }
        if isUnified {
            guard let unified, unified["availability"] as? String == "available",
                  let usage = unified["monthlyUsage"] as? [String: Any],
                  let start = try date(usage["periodStart"]), let reset = try date(usage["resetsAt"]),
                  start <= now, now < reset else {
                if !windows.isEmpty { return windows }
                throw AIAccountBalanceError.noQuota
            }
            windows.append(amount(id: "monthly", kind: .budget, used: try number(usage["usedCents"]),
                cap: try number(usage["limitCents"]), unit: .usd, scale: 100, reset: reset))
            return windows
        }
        let reset = try date(root["billingCycleEnd"])
        if let start = try date(root["billingCycleStart"]), let reset, !(start <= now && now < reset) {
            throw AIAccountBalanceError.noQuota
        }
        let individual = try root["individualUsage"].map(object) ?? [:]
        let team = try root["teamUsage"].map(object) ?? [:]
        for (id, raw, nameKey) in [("plan", individual["plan"], nil), ("overall", individual["overall"], "账户上限"),
                                  ("onDemand", individual["onDemand"], "额外预算"), ("pooled", team["pooled"], "团队额度")] as [(String, Any?, String?)] {
            guard let raw, !(raw is NSNull) else { continue }
            let value = try object(raw)
            guard value["enabled"] as? Bool != false else { continue }
            if let cap = value["limit"], !(cap is NSNull) {
                windows.append(amount(id: id, kind: .budget, used: try number(value["used"]), cap: try number(cap),
                    unit: .usd, scale: 100, reset: reset, nameKey: nameKey))
            } else if id == "plan", let percentValue = value["totalPercentUsed"] {
                windows.append(.init(id: id, kind: .all, remainingPercent: 100 - (try percent(percentValue)), resetsAt: reset))
            }
        }
        if windows.isEmpty, root["isUnlimited"] as? Bool == true {
            windows.append(.init(id: "plan", kind: .all, unlimited: true))
        }
        return windows
    }

    private static func zcode(_ root: [String: Any]) throws -> [AIAccountQuotaWindow] {
        guard let data = root["data"] as? [String: Any], let limits = data["limits"] as? [[String: Any]], limits.count <= 32 else {
            throw AIAccountBalanceError.invalidResponse
        }
        var windows: [AIAccountQuotaWindow] = []
        for (index, limit) in limits.enumerated() {
            let type = limit["type"] as? String ?? limit["limit_type"] as? String
            guard ["TOKENS_LIMIT", "CREDIT_LIMIT", "TIME_LIMIT"].contains(type) else { continue }
            let remainingPercent: Double
            if let cap = AIAccountBalanceCredentials.number(limit["usage"]), cap > 0 {
                let remaining = try limit["remaining"].map(number)
                let used = try (limit["currentValue"] ?? limit["current_value"]).map(number)
                guard remaining != nil || used != nil else { throw AIAccountBalanceError.invalidResponse }
                let consumed = max(cap - min(cap, remaining ?? cap), used ?? 0)
                remainingPercent = max(0, 100 - consumed / cap * 100)
            } else { remainingPercent = 100 - (try percent(limit["percentage"] ?? limit["usedPercent"] ?? limit["used_percent"])) }
            var duration: Double?
            if type != "TIME_LIMIT", let count = AIAccountBalanceCredentials.number(limit["number"]), count > 0 {
                let multiplier: Double? = switch AIAccountBalanceCredentials.number(limit["unit"]) {
                case 5: 60
                case 3: 3_600
                case 1: 86_400
                case 6: 604_800
                default: nil
                }
                duration = multiplier.map { $0 * count }
            }
            windows.append(.init(id: "quota:\(index)", kind: type == "TIME_LIMIT" ? .monthly : kind(duration: duration),
                remainingPercent: remainingPercent, resetsAt: try date(limit["nextResetTime"] ?? limit["next_reset_time"], milliseconds: true),
                durationSeconds: duration, name: type == "TIME_LIMIT" ? "MCP" : nil))
        }
        return windows
    }

    private static func zed(_ root: [String: Any]) throws -> [AIAccountQuotaWindow] {
        if let current = root["current_usage"] as? [String: Any] {
            var windows: [AIAccountQuotaWindow] = []
            if let spend = current["token_spend"] as? [String: Any], let capValue = spend["limit_in_cents"], !(capValue is NSNull) {
                let cap = try number(capValue)
                if cap > 0 {
                    windows.append(amount(id: "token_spend", kind: .budget, used: try number(current["token_spend_in_cents"] ?? spend["spend_in_cents"]),
                        cap: cap, unit: .usd, scale: 100))
                }
            }
            if let predictions = current["edit_predictions"] as? [String: Any] {
                if predictions["limit"] is NSNull { windows.append(.init(id: "edit_predictions", kind: .predictions, unit: .requests, unlimited: true)) }
                else { windows.append(amount(id: "edit_predictions", kind: .predictions, used: try number(predictions["used"]),
                    cap: try number(predictions["limit"]), unit: .requests)) }
            }
            return windows
        }
        let plan = try object(root["plan"])
        let usage = try object(plan["usage"])
        let predictions = try object(usage["edit_predictions"])
        let used = try number(predictions["used"])
        if predictions["limit"] as? String == "unlimited" {
            return [.init(id: "edit_predictions", kind: .predictions, unit: .requests, unlimited: true)]
        }
        let raw = (predictions["limit"] as? [String: Any])?["limited"] ?? predictions["limit"]
        return [amount(id: "edit_predictions", kind: .predictions, used: used, cap: try number(raw), unit: .requests)]
    }

    private static func copilot(_ root: [String: Any]) throws -> [AIAccountQuotaWindow] {
        var windows: [AIAccountQuotaWindow] = []
        let reset = try date(root["quota_reset_date"], acceptsDateOnly: true)
        if let raw = root["quota_snapshots"], !(raw is NSNull) {
            let quotas = try object(raw)
            guard quotas.count <= 32 else { throw AIAccountBalanceError.invalidResponse }
            for key in quotas.keys.sorted() {
                guard !key.isEmpty, key.utf8.count <= 160,
                      !key.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains) else { throw AIAccountBalanceError.invalidResponse }
                let quota = try object(quotas[key])
                let label: String? = switch key { case "premium_interactions": "高级请求"; case "chat": "聊天额度"; case "completions": "代码补全"; default: nil }
                if quota["unlimited"] as? Bool == true {
                    windows.append(.init(id: key, kind: .model, name: label == nil ? key : nil, nameKey: label, unlimited: true))
                    continue
                }
                let cap = try quota["entitlement"].flatMap { $0 is NSNull ? nil : try number($0) }
                let remaining = try quota["remaining"].flatMap { $0 is NSNull ? nil : try number($0) }
                if cap == 0 && remaining == 0 { continue }
                let fraction: Double
                if let raw = quota["percent_remaining"], !(raw is NSNull) { fraction = try percent(raw) }
                else if let cap, cap > 0, let remaining { fraction = min(100, remaining / cap * 100) }
                else if cap == nil && remaining == nil { continue }
                else { throw AIAccountBalanceError.invalidResponse }
                windows.append(.init(id: key, kind: .model, remainingPercent: fraction,
                    remaining: remaining.map { min(cap ?? $0, $0) }, limit: cap,
                    unit: remaining == nil ? .percent : .requests, resetsAt: reset, name: label == nil ? key : nil, nameKey: label))
            }
        }
        if let monthly = root["monthly_quotas"] as? [String: Any], let remaining = root["limited_user_quotas"] as? [String: Any] {
            for (key, label) in [("chat", "聊天额度"), ("completions", "代码补全")] {
                guard !windows.contains(where: { $0.id == key || (key == "completions" && $0.id == "premium_interactions") }),
                      let capValue = monthly[key], let leftValue = remaining[key] else { continue }
                let cap = try number(capValue), left = try number(leftValue)
                guard cap > 0 else { continue }
                windows.append(.init(id: key, kind: .model, remainingPercent: min(100, left / cap * 100),
                    remaining: min(cap, left), limit: cap, unit: .requests, resetsAt: reset, nameKey: label))
            }
        }
        return windows
    }

    private static func qoder(_ root: [String: Any]) throws -> [AIAccountQuotaWindow] {
        let data = root["data"] as? [String: Any] ?? root
        var cap = 0.0, remaining = 0.0
        for (camel, snake) in [("totalQuota", "total_quota"), ("sharedQuota", "shared_quota")] {
            guard let raw = data[camel] ?? data[snake] else {
                if camel == "totalQuota" { throw AIAccountBalanceError.invalidResponse }
                continue
            }
            let quota = try object(raw)
            let summary = try object(quota["quotaSummary"] ?? quota["quota_summary"])
            let limit = try number(summary["limitValue"] ?? summary["limit_value"])
            let used = try number(summary["usedValue"] ?? summary["used_value"])
            let explicit = summary["remainingValue"] ?? summary["remaining_value"]
            cap += limit
            remaining += try explicit.map { min(limit, try number($0)) } ?? max(0, limit - used)
        }
        return [.init(id: "credits", kind: .credits, remainingPercent: cap > 0 ? remaining / cap * 100 : nil,
            remaining: remaining, limit: cap, unit: .credits, resetsAt: try date(data["nextResetAt"] ?? data["next_reset_at"]))]
    }

    private static func trae(_ root: [String: Any]) throws -> [AIAccountQuotaWindow] {
        if AIAccountBalanceCredentials.number(root["code"]) == 1001 { throw AIAccountBalanceError.credentialsExpired }
        guard root["is_credits_billing"] as? Bool == true, let summary = root["usage_summary"] as? [String: Any] else {
            throw AIAccountBalanceError.noQuota
        }
        return [amount(id: "credits", kind: .credits, used: try number(summary["consumed_amount"]),
            cap: try number(summary["total_amount"]), unit: .credits)]
    }

    private static func workbuddy(_ root: [String: Any]) throws -> [AIAccountQuotaWindow] {
        let data = (root["data"] as? [String: Any])?["data"] as? [String: Any] ?? root["data"] as? [String: Any] ?? root
        if let limitValue = data["limitNum"] ?? data["limit_num"] {
            guard let cap = AIAccountBalanceCredentials.number(limitValue), cap >= 0 || cap == -1 else { throw AIAccountBalanceError.invalidResponse }
            let used = try number(data["credit"] ?? data["used"] ?? data["usedNum"] ?? data["used_num"])
            let reset = try date(data["cycleResetTime"] ?? data["cycle_reset_time"], milliseconds: true)
            if cap == -1 { return [.init(id: "credits", kind: .credits, unit: .credits, resetsAt: reset, unlimited: true)] }
            return [amount(id: "credits", kind: .credits, used: used, cap: cap, unit: .credits, reset: reset)]
        }
        let responseData = (data["Response"] as? [String: Any])?["Data"] as? [String: Any]
        guard let rows = data["Accounts"] as? [[String: Any]] ?? responseData?["Accounts"] as? [[String: Any]], rows.count <= 100 else {
            throw AIAccountBalanceError.invalidResponse
        }
        var total = 0.0, remaining = 0.0, active = 0
        for row in rows {
            let status = try number(row["Status"] ?? row["status"])
            guard status == 0 else { continue }
            active += 1
            let cap = try number(row["CycleCapacitySizePrecise"] ?? row["cycleCapacitySizePrecise"])
            let left = try number(row["CycleCapacityRemainPrecise"] ?? row["cycleCapacityRemainPrecise"])
            total += cap
            remaining += min(cap, left)
        }
        guard active > 0 else { throw AIAccountBalanceError.noQuota }
        return [.init(id: "credits", kind: .credits, remainingPercent: total > 0 ? remaining / total * 100 : nil,
            remaining: remaining, limit: total, unit: .credits)]
    }

    private static func opencode(_ root: [String: Any]) throws -> [AIAccountQuotaWindow] {
        let usage = try object(root["usage"])
        var windows: [AIAccountQuotaWindow] = []
        for (key, kind) in [("rolling", AIAccountQuotaKind.rolling), ("weekly", .weekly), ("monthly", .monthly)] {
            guard let raw = usage[key], !(raw is NSNull) else {
                if key != "monthly" { throw AIAccountBalanceError.invalidResponse }
                continue
            }
            let window = try object(raw)
            let used: Double
            if let raw = window["percent"], !(raw is NSNull) { used = try percent(raw) }
            else if window["status"] as? String == "rate-limited" { used = 100 }
            else { throw AIAccountBalanceError.invalidResponse }
            windows.append(.init(id: key, kind: kind, remainingPercent: 100 - used, resetsAt: try date(window["resetsAt"])))
        }
        return windows
    }

    private static func muse(_ root: [String: Any]) throws -> [AIAccountQuotaWindow] {
        guard AIAccountBalanceCredentials.number(root["schemaVersion"]) == 1, let allowance = root["allowance"] else {
            throw AIAccountBalanceError.invalidResponse
        }
        if allowance is NSNull { throw AIAccountBalanceError.noQuota }
        let values = try object(allowance)
        _ = try date(values["asOfMs"], milliseconds: true)
        var windows: [AIAccountQuotaWindow] = []
        for (key, defaultKind) in [("window", AIAccountQuotaKind.rolling), ("weekly", .weekly)] {
            guard let raw = values[key], !(raw is NSNull) else { continue }
            let window = try object(raw)
            let duration = try window["windowDurationMins"].map(number).map { $0 * 60 }
            windows.append(.init(id: key, kind: key == "window" ? (duration.map { kind(duration: $0) } ?? defaultKind) : defaultKind,
                remainingPercent: 100 - (try percent(window["usedPercent"])),
                resetsAt: try date(window["resetsAtMs"], milliseconds: true), durationSeconds: duration))
        }
        return windows
    }

    private static func amount(id: String, kind: AIAccountQuotaKind, used: Double, cap: Double,
                               unit: AIAccountQuotaUnit, scale: Double = 1, reset: Date? = nil,
                               nameKey: String? = nil) -> AIAccountQuotaWindow {
        let remaining = max(0, cap - used)
        return .init(id: id, kind: kind, remainingPercent: cap > 0 ? remaining / cap * 100 : nil,
            remaining: remaining / scale, limit: cap / scale, unit: unit, resetsAt: reset, nameKey: nameKey)
    }
}
