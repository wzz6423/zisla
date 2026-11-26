import Foundation
import ZislaCore

// Wire schemas from CodexBar 7447bc77 and token-monitor 5915414 (MIT).
enum AIAccountBalanceParser {
    /// Publishes only a complete provider schema with valid, unique windows within the shared 64-window bound.
    /// Missing quota is an unavailable reading; it must never be interpreted as zero remaining allowance.
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
        case .antigravity: windows = try antigravityQuotaSummary(root)
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

    /// Converts the provider's stated timestamp unit; absent resets stay absent rather than being guessed.
    /// Date-only input is opt-in for Copilot and must round-trip as a valid UTC calendar date.
    static func date(_ value: Any?, milliseconds: Bool = false, acceptsDateOnly: Bool = false,
                     autoMilliseconds: Bool = false, ignoreNonPositive: Bool = false) throws -> Date? {
        guard let value, !(value is NSNull) else { return nil }
        if ignoreNonPositive, let text = value as? String, text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return nil
        }
        let seconds: Double?
        if let numeric = AIAccountBalanceCredentials.number(value) {
            if ignoreNonPositive, numeric <= 0 { return nil }
            let divisor: Double = autoMilliseconds ? (numeric > 20_000_000_000 ? 1_000 : 1) : (milliseconds ? 1_000 : 1)
            seconds = numeric / divisor
        } else if let text = value as? String {
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

    /// Requires an observed nonnegative finite value so null, booleans, and missing usage cannot imply zero.
    static func number(_ value: Any?) throws -> Double {
        guard let number = AIAccountBalanceCredentials.number(value), number >= 0 else { throw AIAccountBalanceError.invalidResponse }
        return number
    }

    /// Rejects out-of-range percentages before they can distort remaining-quota alert thresholds.
    static func percent(_ value: Any?) throws -> Double {
        let value = try number(value)
        guard value <= 100 else { throw AIAccountBalanceError.invalidResponse }
        return value
    }

    /// Labels 5h only for an explicit 18,000-second window; unknown durations keep a neutral quota label.
    static func kind(duration: Double?) -> AIAccountQuotaKind {
        switch duration {
        case 18_000: .fiveHours
        case 86_400: .daily
        case 604_800: .weekly
        default: duration.map { $0 < 86_400 ? .rolling : .all } ?? .all
        }
    }

    /// Rejects a present malformed quota object instead of treating it as an optional absent window.
    private static func object(_ value: Any?) throws -> [String: Any] {
        guard let object = value as? [String: Any] else { throw AIAccountBalanceError.invalidResponse }
        return object
    }

    /// Keeps Claude's independent weekly/model limits and handles capped or uncapped extra usage.
    private static func claude(_ root: [String: Any]) throws -> [AIAccountQuotaWindow] {
        var windows: [AIAccountQuotaWindow] = []
        let primaryKeys: [([String], String, AIAccountQuotaKind, String?)] = [
            (["five_hour", "fiveHour"], "five_hour", .fiveHours, nil),
            (["seven_day", "sevenDay"], "seven_day", .weekly, nil),
            (["seven_day_opus", "sevenDayOpus"], "seven_day_opus", .model, "Opus"),
            (["seven_day_sonnet", "sevenDaySonnet"], "seven_day_sonnet", .model, "Sonnet"),
            (["seven_day_oauth_apps", "sevenDayOauthApps"], "seven_day_oauth_apps", .model, "OAuth"),
            (["seven_day_routines", "sevenDayRoutines"], "seven_day_routines", .model, "Routines"),
        ]
        for (aliases, id, kind, name) in primaryKeys {
            guard let raw = aliases.compactMap({ root[$0] }).first, !(raw is NSNull) else { continue }
            let value = try object(raw)
            let utilization = value["usedPercent"] ?? value["used_percent"] ?? value["utilization"] ?? value["percent"]
            windows.append(.init(id: id, kind: kind, remainingPercent: 100 - (try percent(utilization)),
                                 resetsAt: try date(value["resets_at"] ?? value["resetsAt"]),
                                 durationSeconds: id == "five_hour" ? 18_000 : 604_800, name: name))
        }
        if let limits = root["limits"] as? [[String: Any]] {
            for entry in limits {
                guard entry["kind"] as? String == "weekly_scoped",
                      let displayName = (((entry["scope"] as? [String: Any])?["model"] as? [String: Any])?["display_name"] as? String)?
                          .trimmingCharacters(in: .whitespacesAndNewlines),
                      displayName.lowercased() == "fable" else { continue }
                let utilization = entry["usedPercent"] ?? entry["used_percent"] ?? entry["utilization"] ?? entry["percent"]
                windows.append(.init(id: "weekly_scoped:fable", kind: .model, remainingPercent: 100 - (try percent(utilization)),
                                     resetsAt: try date(entry["resets_at"] ?? entry["resetsAt"]),
                                     durationSeconds: 604_800, name: displayName))
                break
            }
        }
        let spend = (root["spend"] as? [String: Any])
        let rawExtra = root["extra_usage"] ?? root["extraUsage"]
        let extra: [String: Any]? = try rawExtra.flatMap { $0 is NSNull ? nil : try object($0) }
        let extraEnabled = spend?["enabled"] as? Bool == true
            || (extra?["is_enabled"] as? Bool == true)
            || (extra?["isEnabled"] as? Bool == true)
        if extraEnabled {
            if let spend, let usedObject = spend["used"] as? [String: Any] {
                let used = try claudeSpendAmount(usedObject)
                if let limitObject = spend["limit"] as? [String: Any] {
                    let cap = try claudeSpendAmount(limitObject)
                    windows.append(amount(id: "extra_usage", kind: .budget, used: used, cap: cap, unit: .usd))
                } else {
                    windows.append(.init(id: "extra_usage", kind: .budget, unit: .usd, unlimited: true))
                }
            } else if let extra {
                let places = AIAccountBalanceCredentials.number(extra["decimal_places"] ?? extra["decimalPlaces"]) ?? 2
                let scale = places >= 0 && places <= 6 ? pow(10.0, places) : 100
                let used = try number(extra["used_credits"] ?? extra["usedCredits"])
                let rawCap = extra["monthly_limit"] ?? extra["monthlyLimit"]
                if let rawCap, !(rawCap is NSNull) {
                    let cap = try number(rawCap)
                    windows.append(amount(id: "extra_usage", kind: .budget, used: used, cap: cap, unit: .usd, scale: scale))
                } else {
                    windows.append(.init(id: "extra_usage", kind: .budget, unit: .usd, unlimited: true))
                }
            }
        }
        return windows
    }

    private static func claudeSpendAmount(_ money: [String: Any]) throws -> Double {
        let minor = try number(money["amount_minor"] ?? money["amountMinor"])
        let exponent = AIAccountBalanceCredentials.number(money["exponent"]) ?? 2
        let scale = exponent >= 0 && exponent <= 6 ? pow(10.0, exponent) : 100
        return minor / scale
    }

    /// Preserves nullable primary limits, independent named features, and credits as separate allowances.
    /// Feature IDs are stable and bounded; spend control requires usage or a stated remaining percentage.
    private static func codex(_ root: [String: Any]) throws -> [AIAccountQuotaWindow] {
        var windows: [AIAccountQuotaWindow] = []
        if let raw = root["rate_limit"] ?? root["rateLimit"], !(raw is NSNull) {
            windows += try codexWindows(object(raw))
        }
        if let raw = root["additional_rate_limits"] ?? root["additionalRateLimits"], !(raw is NSNull) {
            guard let entries = raw as? [[String: Any]], entries.count <= 64 else { throw AIAccountBalanceError.invalidResponse }
            var features: Set<String> = []
            for entry in entries {
                guard let feature = entry["metered_feature"] as? String ?? entry["meteredFeature"] as? String,
                      !feature.isEmpty, feature.utf8.count <= 160,
                      !feature.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains),
                      feature != "codex", features.insert(feature).inserted else { throw AIAccountBalanceError.invalidResponse }
                let name = entry["limit_name"] as? String ?? entry["limitName"] as? String ?? feature
                guard !name.isEmpty, name.utf8.count <= 160,
                      !name.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains) else {
                    throw AIAccountBalanceError.invalidResponse
                }
                if let limit = entry["rate_limit"] ?? entry["rateLimit"], !(limit is NSNull) {
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

    /// Uses actual window seconds and a feature prefix, avoiding fabricated 5h labels or colliding window IDs.
    private static func codexWindows(_ limits: [String: Any], prefix: String = "", name: String? = nil) throws -> [AIAccountQuotaWindow] {
        var windows: [AIAccountQuotaWindow] = []
        for (snake, camel) in [("primary_window", "primaryWindow"), ("secondary_window", "secondaryWindow")] {
            guard let raw = limits[snake] ?? limits[camel], !(raw is NSNull) else { continue }
            let window = try object(raw)
            let rawDuration = window["limit_window_seconds"] ?? window["limitWindowSeconds"]
            let duration = try rawDuration == nil || rawDuration is NSNull ? nil : number(rawDuration)
            windows.append(.init(id: prefix + snake, kind: kind(duration: duration),
                                 remainingPercent: 100 - (try percent(window["used_percent"] ?? window["usedPercent"])),
                                 resetsAt: try date(window["reset_at"] ?? window["resets_at"] ?? window["resetsAt"]),
                                 durationSeconds: duration, name: name))
        }
        return windows
    }

    /// Parses grouped Antigravity quota summaries (Gemini, Gemini 4 Argon, Claude/GPT, and custom service groups).
    /// Disabled buckets and buckets without a finite remaining fraction are omitted rather than turning into zero.
    static func antigravityQuotaSummary(_ root: [String: Any]) throws -> [AIAccountQuotaWindow] {
        let summary = (root["response"] as? [String: Any]) ?? (root["summary"] as? [String: Any]) ?? root
        guard let groups = summary["groups"] as? [[String: Any]], groups.count <= 32 else {
            throw AIAccountBalanceError.invalidResponse
        }
        let indexed = groups.enumerated().map { index, group -> (index: Int, name: String, rank: Int, buckets: [[String: Any]]) in
            let name = antigravityGroupName(group["displayName"] as? String)
            let rank = antigravityGroupRank(name)
            return (index, name, rank, group["buckets"] as? [[String: Any]] ?? [])
        }.sorted { lhs, rhs in
            lhs.rank != rhs.rank ? lhs.rank < rhs.rank : lhs.index < rhs.index
        }
        var windows: [AIAccountQuotaWindow] = []
        var usedIDs: Set<String> = []
        for group in indexed {
            var session: [AIAccountQuotaWindow] = []
            var weekly: [AIAccountQuotaWindow] = []
            let slug = group.name.lowercased().map { $0.isLetter || $0.isNumber ? String($0) : "-" }.joined()
            for bucket in group.buckets {
                guard let cadence = antigravityBucketKind(bucket) else { continue }
                if bucket["disabled"] as? Bool == true { continue }
                guard let fraction = antigravityRemainingFraction(bucket) else { continue }
                let clamped = min(1, max(0, fraction))
                let reset = try? date(bucket["resetTime"], autoMilliseconds: true, ignoreNonPositive: true)
                let period = cadence == .fiveHours ? "five_hour" : "weekly"
                var windowID = "additional:\(slug):\(period)"
                if !usedIDs.insert(windowID).inserted {
                    var suffix = 2
                    while !usedIDs.insert("\(windowID):\(suffix)").inserted { suffix += 1 }
                    windowID = "\(windowID):\(suffix)"
                }
                let window = AIAccountQuotaWindow(
                    id: windowID,
                    kind: cadence,
                    remainingPercent: clamped * 100,
                    resetsAt: reset,
                    durationSeconds: cadence == .fiveHours ? 18_000 : 604_800,
                    name: group.name
                )
                if cadence == .fiveHours { session.append(window) } else { weekly.append(window) }
            }
            windows += session + weekly
        }
        guard !windows.isEmpty else { throw AIAccountBalanceError.noQuota }
        guard windows.count <= 64, windows.allSatisfy(\.isValid) else { throw AIAccountBalanceError.invalidResponse }
        return windows
    }

    private static func antigravityGroupName(_ displayName: String?) -> String {
        let collapsed = (displayName ?? "")
            .split(whereSeparator: { $0.isWhitespace || $0.isNewline })
            .joined(separator: " ")
        let lower = collapsed.lowercased()
        if lower.range(of: #"^gemini(?:\s+models)?$"#, options: .regularExpression) != nil { return "Gemini" }
        if lower.range(of: #"^claude\s*(?:and|&|/)\s*gpt(?:\s+models)?$"#, options: .regularExpression) != nil { return "Claude/GPT" }
        if lower == "gemini 4 argon" { return "Gemini 4 Argon" }
        let sanitized = String(String.UnicodeScalarView(collapsed.unicodeScalars.filter {
            !CharacterSet.controlCharacters.contains($0) && !CharacterSet.newlines.contains($0)
        })).trimmingCharacters(in: .whitespaces)
        return sanitized.isEmpty ? "Quota" : String(sanitized.prefix(32))
    }

    private static func antigravityGroupRank(_ name: String) -> Int {
        switch name.lowercased() {
        case "gemini": 0
        case "gemini 4 argon": 1
        case "claude/gpt": 2
        default: 3
        }
    }

    private static func antigravityBucketKind(_ bucket: [String: Any]) -> AIAccountQuotaKind? {
        let sessionAliases: Set<String> = ["session", "5h", "5-hour", "five hour", "five-hour"]
        var candidates: [String] = []
        for raw in [bucket["window"], bucket["bucketId"], bucket["displayName"]] {
            guard let text = raw as? String else { continue }
            let normalized = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased().replacingOccurrences(of: "_", with: "-")
            guard !normalized.isEmpty else { continue }
            candidates.append(normalized)
            if normalized.hasSuffix(" limit") {
                candidates.append(String(normalized.dropLast(" limit".count)))
            }
        }
        for candidate in candidates {
            if candidate == "weekly" || candidate.hasSuffix("-weekly") { return .weekly }
            if sessionAliases.contains(candidate) || sessionAliases.contains(where: { candidate.hasSuffix("-" + $0) }) {
                return .fiveHours
            }
        }
        return nil
    }

    private static func antigravityRemainingFraction(_ bucket: [String: Any]) -> Double? {
        if let direct = AIAccountBalanceCredentials.number(bucket["remainingFraction"]) { return direct }
        guard let remaining = bucket["remaining"] as? [String: Any] else { return nil }
        if let nested = AIAccountBalanceCredentials.number(remaining["remainingFraction"]) { return nested }
        if remaining["case"] as? String == "remainingFraction",
           let value = AIAccountBalanceCredentials.number(remaining["value"]) {
            return value
        }
        return nil
    }

    /// Collapses duplicate model buckets to the most restrictive remaining fraction rather than summing limits.
    /// Accepts grouped quota summaries when present and skips individual buckets lacking a remaining fraction.
    private static func gemini(_ root: [String: Any]) throws -> [AIAccountQuotaWindow] {
        if root["groups"] != nil
            || (root["response"] as? [String: Any])?["groups"] != nil
            || (root["summary"] as? [String: Any])?["groups"] != nil {
            return try antigravityQuotaSummary(root)
        }
        guard let buckets = root["buckets"] as? [[String: Any]], buckets.count <= 128 else { throw AIAccountBalanceError.invalidResponse }
        var models: [String: AIAccountQuotaWindow] = [:]
        for bucket in buckets {
            guard let model = bucket["modelId"] as? String, !model.isEmpty, model.utf8.count <= 160,
                  !model.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains) else {
                throw AIAccountBalanceError.invalidResponse
            }
            guard let rawFraction = bucket["remainingFraction"], !(rawFraction is NSNull) else { continue }
            let fraction = try number(rawFraction)
            guard fraction <= 1 else { throw AIAccountBalanceError.invalidResponse }
            let window = AIAccountQuotaWindow(id: "model:" + model, kind: .model, remainingPercent: fraction * 100,
                                              resetsAt: try date(bucket["resetTime"], ignoreNonPositive: true), name: model)
            if models[model].map({ ($0.remainingPercent ?? 100) <= fraction * 100 }) != true { models[model] = window }
        }
        return models.keys.sorted().compactMap { models[$0] }
    }

    /// Prefers canonical usage/limits before ratio pools, clamping over-consumed ratios to zero remaining.
    /// Does not count Kimi's monthly Code subset as an independent alert window.
    private static func kimi(_ root: [String: Any]) throws -> [AIAccountQuotaWindow] {
        let body = root["data"] as? [String: Any] ?? root
        var windows: [AIAccountQuotaWindow] = []
        var seenKinds: Set<AIAccountQuotaKind> = []
        if let raw = body["usage"], !(raw is NSNull) {
            let detail = try object(raw)
            let name = (detail["name"] as? String ?? detail["label"] as? String ?? detail["title"] as? String)?.lowercased() ?? ""
            // Use Unicode escapes so the localization-key source scanner does not treat this regex as Chinese UI copy.
            let windowKind: AIAccountQuotaKind = name.range(of: "(hour|\u{5C0F}\u{65F6}|\u{6642}\u{9593}|\u{C2DC}\u{AC04})", options: .regularExpression) != nil ? .rolling : .weekly
            let duration: Double? = windowKind == .weekly ? 604_800 : nil
            windows.append(try kimiDetail(detail, id: "usage", kind: windowKind, duration: duration))
            seenKinds.insert(windowKind)
        }
        if let raw = body["limits"], !(raw is NSNull) {
            guard let limits = raw as? [[String: Any]], limits.count <= 32 else { throw AIAccountBalanceError.invalidResponse }
            for (index, limit) in limits.enumerated() {
                let window = try object(limit["window"])
                let duration = try number(window["duration"])
                let unit = (window["timeUnit"] as? String ?? window["time_unit"] as? String ?? "").uppercased()
                let multiplier: Double
                if unit.contains("MIN") { multiplier = 60 }
                else if unit.contains("HOUR") { multiplier = 3_600 }
                else if unit.contains("DAY") { multiplier = 86_400 }
                else if unit.contains("WEEK") { multiplier = 604_800 }
                else if unit.contains("MONTH") { multiplier = 2_592_000 }
                else { throw AIAccountBalanceError.invalidResponse }
                guard duration > 0 else { throw AIAccountBalanceError.invalidResponse }
                let seconds = duration * multiplier
                let windowKind = kind(duration: seconds)
                let detail = try object(limit["detail"] ?? limit["usage"] ?? limit["quota"])
                windows.append(try kimiDetail(detail, id: "limit:\(index)", kind: windowKind, duration: seconds))
                seenKinds.insert(windowKind)
            }
        }
        if let raw = body["usages"], !(raw is NSNull) {
            let pools = try object(raw)
            for (key, kind, duration) in [("limit_5h", AIAccountQuotaKind.fiveHours, 18_000.0),
                                          ("limit_7d", .weekly, 604_800), ("limit_month_total", .monthly, nil)] as [(String, AIAccountQuotaKind, Double?)] {
                guard !seenKinds.contains(kind), let raw = pools[key], !(raw is NSNull) else { continue }
                let pool = try object(raw)
                let ratio = try number(pool["used_ratio"] ?? pool["usedRatio"])
                let remainingPercent = max(0, 100 - ratio * 100)
                windows.append(.init(id: key, kind: kind, remainingPercent: remainingPercent,
                                     resetsAt: try date(pool["reset_time"] ?? pool["resetTime"], autoMilliseconds: true, ignoreNonPositive: true),
                                     durationSeconds: duration))
                seenKinds.insert(kind)
            }
        }
        return windows
    }

    /// Derives request allowance from explicit remaining, used, or percentage fields; a zero cap does not invent a percentage.
    private static func kimiDetail(_ detail: [String: Any], id: String, kind: AIAccountQuotaKind,
                                   duration: Double?) throws -> AIAccountQuotaWindow {
        let reset = try date(detail["resetTime"] ?? detail["resetAt"] ?? detail["reset_time"] ?? detail["reset_at"],
                             autoMilliseconds: true, ignoreNonPositive: true)
        if let rawCap = detail["limit"] ?? detail["limitValue"] ?? detail["limit_value"], !(rawCap is NSNull) {
            let cap = try number(rawCap)
            let remaining: Double
            if let raw = detail["remaining"] ?? detail["remainingValue"] ?? detail["remaining_value"], !(raw is NSNull) {
                remaining = min(cap, try number(raw))
            } else {
                remaining = max(0, cap - (try number(detail["used"] ?? detail["usedValue"] ?? detail["used_value"])))
            }
            return .init(id: id, kind: kind, remainingPercent: cap > 0 ? remaining / cap * 100 : nil,
                         remaining: remaining, limit: cap, unit: .requests, resetsAt: reset, durationSeconds: duration)
        }
        let usedPercent = try percent(detail["usedPercent"] ?? detail["used_percent"] ?? detail["percent"] ?? detail["percentage"])
        return .init(id: id, kind: kind, remainingPercent: 100 - usedPercent, resetsAt: reset, durationSeconds: duration)
    }

    /// Determines whether a Cursor account uses the unified X Subscription pool.
    static func cursorIsUnified(root: [String: Any], sand: [String: Any]? = nil, planInfo: [String: Any]? = nil) -> Bool {
        if let merged = planInfo?["isMerged"] as? Bool { return merged }
        if sand?["isUnified"] as? Bool == true { return true }
        return (root["membershipType"] as? String)?.lowercased().hasPrefix("unified_") == true
            && (root["limitType"] as? String)?.lowercased() == "user"
    }

    /// Unified plans use GetCurrentPeriodUsage, unified sand status, and prepaid billing instead of legacy placeholders.
    /// Legacy plans retain dollar budgets, Cursor/Other model pools, Grok Bot weekly allowance, and request caps.
    static func cursor(_ root: [String: Any], now: Date, sand: [String: Any]? = nil,
                       unified: [String: Any]? = nil, planInfo: [String: Any]? = nil,
                       currentPeriod: [String: Any]? = nil, prepaid: [String: Any]? = nil,
                       requestUsage: [String: Any]? = nil) throws -> [AIAccountQuotaWindow] {
        let isUnified = cursorIsUnified(root: root, sand: sand, planInfo: planInfo)
        let info = planInfo?["planInfo"] as? [String: Any]
        let periodName = info?["includedUsagePeriod"] as? String
        let isExplicitMonthly = periodName == "INCLUDED_USAGE_PERIOD_MONTHLY"
        let infoReset = try? date(info?["includedUsageResetsAt"], milliseconds: true, ignoreNonPositive: true)
        let billingCycleReset = (try? date(root["billingCycleEnd"])) ?? (try? date(info?["billingCycleEnd"], milliseconds: true, ignoreNonPositive: true))
        var windows: [AIAccountQuotaWindow] = []

        if isUnified {
            let periodUsage = (currentPeriod?["planUsage"] as? [String: Any])?["totalPercentUsed"]
            let periodPercent = periodUsage.flatMap(AIAccountBalanceCredentials.number).map { min(100, max(0, $0)) }
            let sandHasLimit = sand?["hasNonZeroIncludedLimit"] as? Bool == true || sand?["includedLimitZero"] as? Bool == false || sand?["isUnified"] as? Bool == true
            let sandPercent = sandHasLimit ? sand?["usagePercent"].flatMap(AIAccountBalanceCredentials.number).map { min(100, max(0, $0)) } : nil
            let summaryPlan = (root["individualUsage"] as? [String: Any])?["plan"] as? [String: Any]
            let summaryPercent = isExplicitMonthly
                ? summaryPlan?["totalPercentUsed"].flatMap(AIAccountBalanceCredentials.number).map { min(100, max(0, $0)) }
                : nil
            if let used = periodPercent ?? sandPercent ?? summaryPercent {
                let reset = isExplicitMonthly ? billingCycleReset : (infoReset ?? (try? date(sand?["nextResetTimestampUtc"])))
                windows.append(.init(id: "included", kind: isExplicitMonthly ? .monthly : .weekly,
                                     remainingPercent: 100 - used, resetsAt: reset,
                                     durationSeconds: isExplicitMonthly ? nil : 604_800))
            }
            if let prepaid, let cents = AIAccountBalanceCredentials.number(prepaid["availableCents"]), cents > 0 {
                windows.append(.init(id: "prepaid", kind: .budget, remaining: cents / 100, unit: .usd))
            }
            if let unified, unified["availability"] as? String == "available",
               let usage = unified["monthlyUsage"] as? [String: Any],
               let start = try date(usage["periodStart"]), let reset = try date(usage["resetsAt"]),
               start <= now, now < reset {
                windows.append(amount(id: "monthly", kind: .budget, used: try number(usage["usedCents"]),
                                      cap: try number(usage["limitCents"]), unit: .usd, scale: 100, reset: reset))
            }
            guard !windows.isEmpty else { throw AIAccountBalanceError.noQuota }
            return windows
        }

        if let sand, sand["hasNonZeroIncludedLimit"] as? Bool == true || sand["includedLimitZero"] as? Bool == false {
            windows.append(.init(id: "grok_bot", kind: .weekly,
                                 remainingPercent: 100 - (try percent(sand["usagePercent"])),
                                 resetsAt: try date(sand["nextResetTimestampUtc"]), durationSeconds: 604_800,
                                 name: "Grok Bot"))
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
            } else if id == "plan" {
                if let percentValue = value["totalPercentUsed"], !(percentValue is NSNull) {
                    windows.append(.init(id: id, kind: .all, remainingPercent: 100 - (try percent(percentValue)), resetsAt: reset))
                } else {
                    if let autoValue = value["autoPercentUsed"], !(autoValue is NSNull) {
                        windows.append(.init(id: "auto", kind: .model, remainingPercent: 100 - (try percent(autoValue)), resetsAt: reset, name: "Cursor Models"))
                    }
                    if let apiValue = value["apiPercentUsed"], !(apiValue is NSNull) {
                        windows.append(.init(id: "api", kind: .model, remainingPercent: 100 - (try percent(apiValue)), resetsAt: reset, name: "Other Models"))
                    }
                }
            }
        }
        if let requestUsage,
           let gpt4 = (requestUsage["gpt-4"] as? [String: Any]) ?? (requestUsage["gpt4"] as? [String: Any]),
           let limit = AIAccountBalanceCredentials.number(gpt4["maxRequestUsage"]), limit > 0,
           let used = AIAccountBalanceCredentials.number(gpt4["numRequestsTotal"] ?? gpt4["numRequests"]), used >= 0,
           !windows.contains(where: { $0.id == "plan" }) {
            windows.append(amount(id: "requests", kind: .monthly, used: used, cap: limit, unit: .requests, reset: reset))
        }
        if windows.isEmpty, root["isUnlimited"] as? Bool == true {
            windows.append(.init(id: "plan", kind: .all, unlimited: true))
        }
        return windows
    }

    /// Reads ZCode coding-plan quota pools and Start/Weekend billing balances, checking HTTP 200 business errors.
    /// When both used and remaining are reported, the stricter observation determines remaining allowance.
    private static func zcode(_ root: [String: Any]) throws -> [AIAccountQuotaWindow] {
        if let code = AIAccountBalanceCredentials.number(root["code"]) {
            if code == 401 || code == 403 { throw AIAccountBalanceError.credentialsExpired }
            if code == 429 { throw AIAccountBalanceError.httpStatus(429) }
        }
        guard let data = root["data"] as? [String: Any] else {
            throw AIAccountBalanceError.invalidResponse
        }
        if let balances = data["balances"] as? [[String: Any]] {
            return try zcodeStartPlanBalances(balances, plans: data["plans"] as? [[String: Any]] ?? [])
        }
        guard let limits = data["limits"] as? [[String: Any]], limits.count <= 32 else {
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
                                 remainingPercent: remainingPercent,
                                 resetsAt: try date(limit["nextResetTime"] ?? limit["next_reset_time"], milliseconds: true, ignoreNonPositive: true),
                                 durationSeconds: duration, name: type == "TIME_LIMIT" ? "MCP" : nil))
        }
        return windows
    }

    private static func zcodeStartPlanBalances(_ balances: [[String: Any]], plans: [[String: Any]]) throws -> [AIAccountQuotaWindow] {
        guard balances.count <= 64 else { throw AIAccountBalanceError.invalidResponse }
        var periodByEntitlement: [String: String] = [:]
        for plan in plans {
            let planKeys = [plan["user_plan_id"] as? String, plan["plan_id"] as? String]
                .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            for entitlement in plan["entitlements"] as? [[String: Any]] ?? [] {
                guard let id = (entitlement["entitlement_id"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), !id.isEmpty,
                      let period = (entitlement["period"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), !period.isEmpty else { continue }
                for key in planKeys { periodByEntitlement["\(key)::\(id)"] = period }
            }
        }
        var windows: [AIAccountQuotaWindow] = []
        for (index, entry) in balances.enumerated() {
            let total = AIAccountBalanceCredentials.number(entry["total_units"])
            var used = AIAccountBalanceCredentials.number(entry["used_units"])
            var remaining = AIAccountBalanceCredentials.number(entry["remaining_units"])
            if used == nil, let total, let remaining { used = max(0, total - remaining) }
            if remaining == nil, let total, let used { remaining = max(0, total - used) }
            guard total != nil || used != nil || remaining != nil else { continue }
            var remainingPercent: Double?
            if let total, total > 0 {
                if let remaining { remainingPercent = min(100, max(0, remaining / total * 100)) }
                else if let used { remainingPercent = min(100, max(0, 100 - used / total * 100)) }
            } else if let pct = AIAccountBalanceCredentials.number(entry["percentage"]) {
                remainingPercent = min(100, max(0, 100 - pct))
            }
            let entitlementID = (entry["entitlement_id"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let period = [entry["user_plan_id"] as? String, entry["plan_id"] as? String]
                .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
                .compactMap { periodByEntitlement["\($0)::\(entitlementID)"] }
                .first ?? (entry["period"] as? String) ?? ""
            let label = (entry["show_name"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
            let name = label?.isEmpty == false ? String(label!.prefix(80)) : "Start Plan"
            let reset = (try? date(entry["expires_at"], ignoreNonPositive: true)) ?? (try? date(entry["period_end"], ignoreNonPositive: true))
            let windowKind: AIAccountQuotaKind = period == "daily" ? .daily : .credits
            let safeLimit = total.map { max(0, $0) }
            let safeRemaining = remaining.map { value in safeLimit.map { min($0, max(0, value)) } ?? max(0, value) }
            windows.append(.init(id: "start:\(index)", kind: windowKind, remainingPercent: remainingPercent,
                                 remaining: safeRemaining, limit: safeLimit, unit: safeRemaining == nil ? .percent : .credits,
                                 resetsAt: reset, durationSeconds: period == "daily" ? 86_400 : nil, name: name))
        }
        return windows
    }

    /// Website spend limits are USD budgets; zero or null budgets do not imply exhausted model allowance.
    /// Native login exposes only edit predictions, whose unlimited state remains separate from a percentage.
    static func zed(_ root: [String: Any], subscription: [String: Any]? = nil) throws -> [AIAccountQuotaWindow] {
        if let current = root["current_usage"] as? [String: Any] {
            var windows: [AIAccountQuotaWindow] = []
            let subscriptionReset = ((subscription?["subscription"] as? [String: Any])?["period"] as? [String: Any])?["end_at"]
            let reset = try? date(subscriptionReset, ignoreNonPositive: true)
            if let spend = current["token_spend"] as? [String: Any], let capValue = spend["limit_in_cents"], !(capValue is NSNull) {
                let cap = try number(capValue)
                if cap > 0 {
                    windows.append(amount(id: "token_spend", kind: .budget, used: try number(current["token_spend_in_cents"] ?? spend["spend_in_cents"]),
                                          cap: cap, unit: .usd, scale: 100, reset: reset))
                }
            }
            if let predictions = current["edit_predictions"] as? [String: Any], predictions["limit"] != nil {
                if predictions["limit"] is NSNull {
                    windows.append(.init(id: "edit_predictions", kind: .predictions, unit: .requests, unlimited: true))
                } else {
                    let cap = try number(predictions["limit"])
                    if cap > 0 {
                        windows.append(amount(id: "edit_predictions", kind: .predictions, used: try number(predictions["used"]),
                                              cap: cap, unit: .requests))
                    }
                }
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

    /// Prefers current snapshots, ignores 0/0 placeholders, clamps overage to 0% remaining, and fills missing legacy quotas.
    /// Request counts and UTC reset dates remain explicit, including unlimited entitlements.
    private static func copilot(_ root: [String: Any]) throws -> [AIAccountQuotaWindow] {
        var windows: [AIAccountQuotaWindow] = []
        let reset = try date(root["quota_reset_date"] ?? root["quotaResetDate"], acceptsDateOnly: true)
        if let raw = root["quota_snapshots"] ?? root["quotaSnapshots"], !(raw is NSNull) {
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
                let remaining: Double? = try quota["remaining"].flatMap { value in
                    if value is NSNull { return nil }
                    guard let parsed = AIAccountBalanceCredentials.number(value) else { throw AIAccountBalanceError.invalidResponse }
                    return max(0, parsed)
                }
                if cap == 0 && remaining == 0 { continue }
                let fraction: Double
                if let raw = quota["percent_remaining"] ?? quota["percentRemaining"], !(raw is NSNull) {
                    guard let parsed = AIAccountBalanceCredentials.number(raw), parsed <= 100 else {
                        throw AIAccountBalanceError.invalidResponse
                    }
                    fraction = max(0, parsed)
                } else if let cap, cap > 0, let remaining {
                    fraction = min(100, remaining / cap * 100)
                } else if cap == nil && remaining == nil {
                    continue
                } else {
                    throw AIAccountBalanceError.invalidResponse
                }
                windows.append(.init(id: key, kind: .model, remainingPercent: fraction,
                                     remaining: remaining.map { min(cap ?? $0, $0) }, limit: cap,
                                     unit: remaining == nil ? .percent : .requests, resetsAt: reset, name: label == nil ? key : nil, nameKey: label))
            }
        }
        if let monthly = (root["monthly_quotas"] ?? root["monthlyQuotas"]) as? [String: Any],
           let remaining = (root["limited_user_quotas"] ?? root["limitedUserQuotas"]) as? [String: Any] {
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

    /// Parses personal and optional separate or inline team credit pools; ignores non-positive reset timestamps.
    static func qoder(_ root: [String: Any], shared: [String: Any]? = nil) throws -> [AIAccountQuotaWindow] {
        let data = root["data"] as? [String: Any] ?? root
        let personal = try qoderSummary(data["totalQuota"] ?? data["total_quota"], required: true)!
        let reset = try date(data["nextResetAt"] ?? data["next_reset_at"], ignoreNonPositive: true)
        if let shared {
            let sharedPayload = shared["data"] as? [String: Any] ?? shared
            let team = try qoderSummary(sharedPayload["sharedQuota"] ?? sharedPayload["shared_quota"], required: false)
            var windows: [AIAccountQuotaWindow] = []
            if personal.limit > 0 || team == nil || team?.limit == 0 {
                windows.append(.init(id: "credits", kind: .credits,
                                     remainingPercent: personal.limit > 0 ? personal.remaining / personal.limit * 100 : nil,
                                     remaining: personal.remaining, limit: personal.limit, unit: .credits, resetsAt: reset))
            }
            if let team, team.limit > 0 {
                let teamReset = try date(sharedPayload["nextResetAt"] ?? sharedPayload["next_reset_at"], ignoreNonPositive: true)
                windows.append(.init(id: "team_credits", kind: .credits,
                                     remainingPercent: team.remaining / team.limit * 100,
                                     remaining: team.remaining, limit: team.limit, unit: .credits,
                                     resetsAt: teamReset, nameKey: "团队额度"))
            }
            return windows
        }
        var cap = personal.limit
        var remaining = personal.remaining
        if let inlineShared = try qoderSummary(data["sharedQuota"] ?? data["shared_quota"], required: false) {
            cap += inlineShared.limit
            remaining += inlineShared.remaining
        }
        return [.init(id: "credits", kind: .credits, remainingPercent: cap > 0 ? remaining / cap * 100 : nil,
                      remaining: remaining, limit: cap, unit: .credits, resetsAt: reset)]
    }

    private static func qoderSummary(_ raw: Any?, required: Bool) throws -> (limit: Double, remaining: Double)? {
        guard let raw, !(raw is NSNull) else {
            if required { throw AIAccountBalanceError.invalidResponse }
            return nil
        }
        let quota = try object(raw)
        let summary = try object(quota["quotaSummary"] ?? quota["quota_summary"])
        let limit = try number(summary["limitValue"] ?? summary["limit_value"])
        let used = try number(summary["usedValue"] ?? summary["used_value"])
        let explicit = summary["remainingValue"] ?? summary["remaining_value"]
        let remaining = try explicit.map { min(limit, try number($0)) } ?? max(0, limit - used)
        return (limit, remaining)
    }

    /// Accepts only TRAE's confirmed credits-billing schema, preserving expired-session and absent-quota failures.
    private static func trae(_ root: [String: Any]) throws -> [AIAccountQuotaWindow] {
        if AIAccountBalanceCredentials.number(root["code"]) == 1001 { throw AIAccountBalanceError.credentialsExpired }
        guard root["is_credits_billing"] as? Bool == true, let summary = root["usage_summary"] as? [String: Any] else {
            throw AIAccountBalanceError.noQuota
        }
        return [amount(id: "credits", kind: .credits, used: try number(summary["consumed_amount"]),
                       cap: try number(summary["total_amount"]), unit: .credits)]
    }

    /// Checks HTTP 200 business codes, treats -1 as unlimited, and sums active complete credit packages.
    /// Inactive packages or missing numeric fields cannot contribute fabricated remaining credits.
    private static func workbuddy(_ root: [String: Any]) throws -> [AIAccountQuotaWindow] {
        if let rawCode = root["code"], !(rawCode is NSNull) {
            guard let code = AIAccountBalanceCredentials.number(rawCode) else { throw AIAccountBalanceError.invalidResponse }
            if code == 401 || code == 403 { throw AIAccountBalanceError.credentialsExpired }
            if code == 429 { throw AIAccountBalanceError.httpStatus(429) }
            if code != 0 && code != 200 { throw AIAccountBalanceError.invalidResponse }
        }
        let data = (root["data"] as? [String: Any])?["data"] as? [String: Any]
            ?? root["data"] as? [String: Any]
            ?? root["Data"] as? [String: Any]
            ?? root
        if let limitValue = data["limitNum"] ?? data["limit_num"] {
            guard let cap = AIAccountBalanceCredentials.number(limitValue), cap >= 0 || cap == -1 else { throw AIAccountBalanceError.invalidResponse }
            let used = try number(data["credit"] ?? data["used"] ?? data["usedNum"] ?? data["used_num"])
            let reset = try date(data["cycleResetTime"] ?? data["cycle_reset_time"], milliseconds: true, ignoreNonPositive: true)
            if cap == -1 { return [.init(id: "credits", kind: .credits, unit: .credits, resetsAt: reset, unlimited: true)] }
            return [amount(id: "credits", kind: .credits, used: used, cap: cap, unit: .credits, reset: reset)]
        }
        let rows = workbuddyAccounts(root) ?? workbuddyAccounts(data)
        guard let rows, rows.count <= 100 else {
            throw AIAccountBalanceError.invalidResponse
        }
        var total = 0.0, remaining = 0.0, active = 0
        for row in rows {
            if let rawStatus = row["Status"] ?? row["status"], !(rawStatus is NSNull) {
                let status = try number(rawStatus)
                guard status == 0 else { continue }
            }
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

    private static func workbuddyAccounts(_ source: [String: Any]) -> [[String: Any]]? {
        if let direct = source["Accounts"] as? [[String: Any]] ?? source["accounts"] as? [[String: Any]] {
            return direct
        }
        let response = (source["Response"] as? [String: Any]) ?? (source["response"] as? [String: Any])
        let nestedData = (response?["Data"] as? [String: Any]) ?? (response?["data"] as? [String: Any])
        return nestedData?["Accounts"] as? [[String: Any]] ?? nestedData?["accounts"] as? [[String: Any]]
    }

    /// Requires both rolling and weekly windows; an explicit rate-limited state means zero remaining allowance.
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

    /// Accepts the versioned CLI allowance schema and preserves millisecond resets and real window durations.
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
            let rawDuration = window["windowDurationMins"]
            let duration = try rawDuration == nil || rawDuration is NSNull ? nil : number(rawDuration) * 60
            windows.append(.init(id: key, kind: key == "window" ? (duration.map { kind(duration: $0) } ?? defaultKind) : defaultKind,
                                 remainingPercent: 100 - (try percent(window["usedPercent"])),
                                 resetsAt: try date(window["resetsAtMs"], milliseconds: true), durationSeconds: duration))
        }
        return windows
    }

    /// Converts the stated amount scale and clamps overspend to zero; a zero cap leaves percentage unknown.
    private static func amount(id: String, kind: AIAccountQuotaKind, used: Double, cap: Double,
                               unit: AIAccountQuotaUnit, scale: Double = 1, reset: Date? = nil,
                               nameKey: String? = nil) -> AIAccountQuotaWindow {
        let remaining = max(0, cap - used)
        return .init(id: id, kind: kind, remainingPercent: cap > 0 ? remaining / cap * 100 : nil,
                     remaining: remaining / scale, limit: cap / scale, unit: unit, resetsAt: reset, nameKey: nameKey)
    }
}
