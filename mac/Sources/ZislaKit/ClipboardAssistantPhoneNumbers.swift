import Foundation

enum ClipboardAssistantPhoneNumbers {
    struct Region: Sendable {
        let callingCode: String
        let nationalPrefix: String?
        let internationalPrefix: String
        let prefixPattern: String?
        let prefixTransform: String?
        let numberPattern: String
    }

    struct Number: Equatable {
        let e164: String
        let prefersBareNumber: Bool
    }

    private static let callingCodes = Dictionary(grouping: ClipboardAssistantPhoneMetadata.regions.values, by: \.callingCode)

    static func parse(_ text: String, countryCode: String?) -> Number? {
        guard text.count <= 128,
              !text.unicodeScalars.contains(where: {
                  $0.properties.generalCategory == .control && $0 != "\t"
              }) else { return nil }
        let labelled = ClipboardAssistantIdentifierPatterns.splitLabel(text, pattern: ClipboardAssistantIdentifierPatterns.phoneLabel)
        var value = ClipboardAssistantIdentifierPatterns.decimalDigits(labelled.value)
        for (source, target) in [("＋", "+"), ("（", "("), ("）", ")"), ("－", "-")] {
            value = value.replacingOccurrences(of: source, with: target)
        }
        value = value.replacingOccurrences(of: #"\h"#, with: " ", options: .regularExpression)
        guard value.range(of: #"^\+?(?:[0-9]|\([0-9]{1,5}\))(?:[0-9 .-]|\([0-9]{1,5}\))*[0-9)]$"#, options: .regularExpression) != nil,
              value.range(of: #"[.-][ ]*[.-]"#, options: .regularExpression) == nil else { return nil }
        if labelled.label == nil, !value.hasPrefix("+") {
            guard value.range(of: #"^[0-9]{4}[-./][0-9]{1,2}[-./][0-9]{1,2}$|[ ]-[ ]"#, options: .regularExpression) == nil,
                  value.filter({ $0 == "." }).count != 1 else { return nil }
        }
        let digits = value.filter(\.isNumber)
        if value.hasPrefix("+") {
            return international(digits, formatted: value)
        }
        guard let region = countryCode.flatMap({ ClipboardAssistantPhoneMetadata.regions[$0.uppercased()] }) else { return nil }
        if let range = digits.range(of: "^(?:" + region.internationalPrefix + ")", options: .regularExpression) {
            return international(String(digits[range.upperBound...]), formatted: nil)
        }
        let national: String
        if valid(digits, in: region) {
            national = digits
        } else if let pattern = region.prefixPattern ?? region.nationalPrefix {
            let regex = try! NSRegularExpression(pattern: "^(?:" + pattern + ")")
            guard let match = regex.firstMatch(in: digits, range: NSRange(digits.startIndex..., in: digits)) else { return nil }
            if let transform = region.prefixTransform,
               match.range(at: regex.numberOfCaptureGroups).location != NSNotFound {
                national = regex.stringByReplacingMatches(in: digits, range: NSRange(digits.startIndex..., in: digits), withTemplate: transform)
            } else {
                national = String(digits[Range(match.range, in: digits)!.upperBound...])
            }
            guard valid(national, in: region) else { return nil }
        } else {
            return nil
        }
        let e164 = "+" + region.callingCode + national
        // A trunk-less national significant number can also be a Unix timestamp. Only a
        // customary local dial string wins that ambiguity without an explicit phone label.
        let locallyDialled = region.nationalPrefix == nil || ["1", "55"].contains(region.callingCode) || national != digits
            || (region.callingCode == "86" && national.hasPrefix("400"))
        return Number(e164: e164, prefersBareNumber: locallyDialled)
    }

    private static func international(_ digits: String, formatted: String?) -> Number? {
        for length in 1...3 {
            let code = String(digits.prefix(length))
            guard let regions = callingCodes[code] else { continue }
            let national = String(digits.dropFirst(length))
            for region in regions {
                if valid(national, in: region) {
                    return Number(e164: "+" + digits, prefersBareNumber: true)
                }
                // Parenthesized trunk prefixes are printed for domestic callers but are not
                // dialled after a calling code. Italy's significant leading zero stays intact.
                if let formatted, region.nationalPrefix == "0",
                   formatted.range(of: "^\\+" + code + #"[ ]*\(0\)"#, options: .regularExpression) != nil,
                   valid(String(national.dropFirst()), in: region) {
                    return Number(e164: "+" + code + national.dropFirst(), prefersBareNumber: true)
                }
            }
            return nil
        }
        return nil
    }

    private static func valid(_ number: String, in region: Region) -> Bool {
        number.count + region.callingCode.count <= 15
            && number.range(of: "^(?:" + region.numberPattern + ")$", options: .regularExpression) != nil
    }
}
