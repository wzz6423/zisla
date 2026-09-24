// Adapted from upstream provider protocols, revision 86bcb54cff24d4a9c96b4f14066f0098f12e87a6.
// Modified for Zisla; Apache-2.0. See Resources/ThirdPartyLicenses/AIQuota-LICENSE.txt.
import Foundation
import ZislaCore

struct AIQuotaOllamaSnapshot: Sendable {
    struct Window: Sendable {
        let usedFraction: Double
        let resetsAt: Date?
    }
    let session: Window
    let weekly: Window
}

enum AIQuotaOllamaPage {
    static let maximumBytes = 2 * 1024 * 1024

    static func parse(_ data: Data) throws -> AIQuotaOllamaSnapshot {
        guard data.count <= maximumBytes,
              let html = String(data: data, encoding: .utf8),
              !html.localizedCaseInsensitiveContains("<!ENTITY") else {
            throw AIQuotaError.invalidResponse
        }
        let document: XMLDocument
        do {
            document = try XMLDocument(data: data, options: [.documentTidyHTML, .nodeLoadExternalEntitiesNever])
        } catch { throw AIQuotaError.invalidResponse }
        for node in (try? document.nodes(forXPath: "//script | //style | //template")) ?? [] { node.detach() }
        if let forms = try? document.nodes(forXPath: "//form"), forms.contains(where: { node in
            guard let form = node as? XMLElement else { return false }
            let action = form.attribute(forName: "action")?.stringValue?.lowercased() ?? ""
            return action.contains("signin") || action.contains("login")
        }) { throw AIQuotaError.credentialRejected }

        return try AIQuotaOllamaSnapshot(
            session: window("Session usage", in: document),
            weekly: window("Weekly usage", in: document)
        )
    }

    private static func window(_ label: String, in document: XMLDocument) throws -> AIQuotaOllamaSnapshot.Window {
        let labels = (try? document.nodes(forXPath: "//*[normalize-space(text())='\(label)']")) ?? []
        guard labels.count == 1, let labelNode = labels.first else { throw AIQuotaError.invalidResponse }
        var result: AIQuotaOllamaSnapshot.Window?
        var candidate = labelNode.parent
        while let container = candidate as? XMLElement {
            let other = label == "Session usage" ? "Weekly usage" : "Session usage"
            if !((try? container.nodes(forXPath: ".//*[normalize-space(text())='\(other)']")) ?? []).isEmpty { break }
            if let percent = try percentage(in: container) {
                let times = ((try? container.nodes(forXPath: ".//*[@data-time]")) ?? [])
                    .compactMap { ($0 as? XMLElement)?.attribute(forName: "data-time")?.stringValue }
                guard times.count <= 1 else { throw AIQuotaError.invalidResponse }
                let reset: Date?
                if let time = times.first {
                    let formatter = ISO8601DateFormatter()
                    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
                    let fractional = formatter.date(from: time)
                    formatter.formatOptions = [.withInternetDateTime]
                    guard let date = fractional ?? formatter.date(from: time) else { throw AIQuotaError.invalidResponse }
                    reset = date
                } else { reset = nil }
                result = .init(usedFraction: percent / 100, resetsAt: reset)
                if container.attribute(forName: "data-usage-meter") != nil { break }
            }
            candidate = container.parent
        }
        guard let result else { throw AIQuotaError.invalidResponse }
        return result
    }

    private static func percentage(in element: XMLElement) throws -> Double? {
        let texts = ((try? element.nodes(forXPath: ".//text()")) ?? []).compactMap(\.stringValue)
        let expression = try NSRegularExpression(pattern: #"^\s*([0-9]+(?:\.[0-9]+)?)\s*%\s*used\s*$"#, options: .caseInsensitive)
        var values: [Double] = []
        for text in texts {
            if let match = expression.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
               let range = Range(match.range(at: 1), in: text), let number = Double(text[range]) {
                guard number.isFinite, (0...100).contains(number) else { throw AIQuotaError.invalidResponse }
                values.append(number)
            }
        }
        guard values.count <= 1 else { throw AIQuotaError.invalidResponse }
        return values.first
    }
}
