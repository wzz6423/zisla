import CoreFoundation
import Foundation
import ZislaCore

enum AIAccountGeminiAppQuotaParser {
    private static let assetPrefix = "https://www.gstatic.com/bg3/boq-bard-web/islands/assets/"

    static func usageScriptURL(_ data: Data) throws -> URL {
        guard let html = String(data: data, encoding: .utf8) else { throw AIAccountBalanceError.invalidResponse }
        let pattern = #""@messages/assets/(UsagePageSurface-[A-Za-z0-9_-]+\.js)"\s*:"#
        guard let name = firstCapture(pattern, in: html) else { throw AIAccountBalanceError.invalidResponse }
        return URL(string: assetPrefix + name)!
    }

    static func querySignature(_ data: Data) throws -> String {
        guard let script = String(data: data, encoding: .utf8),
              let signature = firstCapture(#"id:\s*[`"'](2/[A-Za-z0-9+/=_-]{1,128})[`"'],\s*metadata:\s*\{\},\s*name:\s*[`"']UsagePageQuery[`"']"#, in: script) else {
            throw AIAccountBalanceError.invalidResponse
        }
        return signature
    }

    static func parse(_ data: Data) throws -> [AIAccountQuotaWindow] {
        let payload: Any
        do { payload = try JSONSerialization.jsonObject(with: data) }
        catch { throw AIAccountBalanceError.invalidResponse }
        let fragments = (payload as? [Any]) ?? [payload]
        guard fragments.count <= 64 else { throw AIAccountBalanceError.invalidResponse }
        var windows: [AIAccountQuotaWindow] = []
        for fragment in fragments {
            guard let root = fragment as? [String: Any] else { throw AIAccountBalanceError.invalidResponse }
            if let value = root["errors"] {
                guard let errors = value as? [Any], errors.isEmpty else { throw AIAccountBalanceError.invalidResponse }
            }
            guard let viewer = (root["data"] as? [String: Any])?["viewer"] as? [String: Any],
                  let usage = (viewer["rpcs"] as? [String: Any])?["getUsageInfo"] as? [String: Any] else { continue }
            guard let pools = usage["pools"] as? [[String: Any]], pools.count <= 64 else { throw AIAccountBalanceError.invalidResponse }
            for pool in pools {
                let kind: AIAccountQuotaKind
                let id: String
                let duration: Double
                switch pool["poolType"] as? String {
                case "GXU_FIVE_HOURLY": kind = .fiveHours; id = "five_hour"; duration = 18_000
                case "GXU_WEEKLY": kind = .weekly; id = "weekly"; duration = 604_800
                default: continue
                }
                guard let number = pool["percentageUsed"] as? NSNumber,
                      CFGetTypeID(number) != CFBooleanGetTypeID(),
                      number.doubleValue.isFinite, number.doubleValue >= 0,
                      let reset = (pool["gxu"] as? [String: Any])?["windowRefreshesAt"] as? String else {
                    throw AIAccountBalanceError.invalidResponse
                }
                let formatter = ISO8601DateFormatter()
                formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
                var resetDate = formatter.date(from: reset)
                if resetDate == nil {
                    formatter.formatOptions = [.withInternetDateTime]
                    resetDate = formatter.date(from: reset)
                }
                guard let resetsAt = resetDate else { throw AIAccountBalanceError.invalidResponse }
                let window = AIAccountQuotaWindow(id: id, kind: kind,
                                                  remainingPercent: max(0, 1 - number.doubleValue) * 100,
                                                  resetsAt: resetsAt, durationSeconds: duration)
                guard window.isValid, !windows.contains(where: { $0.id == id }) else { throw AIAccountBalanceError.invalidResponse }
                windows.append(window)
            }
        }
        guard !windows.isEmpty else { throw AIAccountBalanceError.noQuota }
        return windows.sorted { $0.kind == .fiveHours && $1.kind != .fiveHours }
    }

    private static func firstCapture(_ pattern: String, in value: String) -> String? {
        let regex = try! NSRegularExpression(pattern: pattern)
        guard let match = regex.firstMatch(in: value, range: NSRange(value.startIndex..., in: value)),
              let range = Range(match.range(at: 1), in: value) else { return nil }
        return String(value[range])
    }
}
