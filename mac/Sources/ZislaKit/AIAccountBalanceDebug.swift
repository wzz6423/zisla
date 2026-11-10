import Foundation
import ZislaCore

#if DEBUG
enum AIAccountBalanceDebug {
    static func balances(environment: [String: String], now: Date) -> [AIAccountBalance]? {
        guard let raw = environment["ZISLA_DEBUG_AI_ACCOUNT_BALANCE"] else { return nil }
        // A present but malformed fixture must never fall through to real credentials or requests.
        let entries = raw.split(separator: ",", omittingEmptySubsequences: false)
        var values: [AIProvider: [AIAccountQuotaWindow]] = [:]
        for entry in entries {
            let parts = entry.split(separator: ":", omittingEmptySubsequences: false)
            guard (2...3).contains(parts.count), let provider = AIProvider(rawValue: String(parts[0])),
                  let remaining = Double(parts[1]), remaining.isFinite, (0...100).contains(remaining) else { return [] }
            var windows: [AIAccountQuotaWindow] = []
            if parts.count == 3 {
                guard let all = Double(parts[2]), all.isFinite, (0...100).contains(all) else { return [] }
                windows.append(.init(id: "five_hour", kind: .fiveHours, remainingPercent: remaining,
                    resetsAt: now.addingTimeInterval(1_800), durationSeconds: 18_000))
                windows.append(.init(id: "all", kind: .weekly, remainingPercent: all,
                    resetsAt: now.addingTimeInterval(86_400), durationSeconds: 604_800))
            } else { windows.append(.init(id: "all", kind: .all, remainingPercent: remaining)) }
            guard values[provider] == nil else { return [] }
            values[provider] = windows
        }
        return AIAccountBalanceCatalog.groups.compactMap { group in
            guard let provider = group.first(where: { values[$0] != nil }), let windows = values[provider] else { return nil }
            return .init(id: "debug:" + group[0].rawValue, providers: group, status: .available,
                windows: windows, updatedAt: now, isDebug: true)
        }
    }
}
#endif
