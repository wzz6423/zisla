import Foundation
import ZislaCore

extension ClipboardAssistantDetector {
    private struct MoneyUnitDefinition: Sendable {
        let currencyCode: String
        let majorUnitValue: Double
    }

    private static let moneyUnits: [String: [MoneyUnitDefinition]] = {
        var units: [String: [MoneyUnitDefinition]] = [:]
        func add(_ names: String, codes: [String], value: Double = 0.01) {
            for name in names.split(separator: "|").map(String.init) {
                for code in codes {
                    let definition = MoneyUnitDefinition(currencyCode: code, majorUnitValue: value)
                    units[name, default: []].append(definition)
                    units["\(code.lowercased()) \(name)"] = [definition]
                    units["\(name) \(code.lowercased())"] = [definition]
                }
            }
        }
        add("角|毛|jiao", codes: ["CNY", "TWD"], value: 0.1)
        add("分|fen", codes: ["CNY", "TWD"])
        add("人民币角|人民幣角", codes: ["CNY"], value: 0.1)
        add("人民币分|人民幣分", codes: ["CNY"])
        add("台角|臺角|新台幣角|新台币角", codes: ["TWD"], value: 0.1)
        add("台分|臺分|新台幣分|新台币分", codes: ["TWD"])

        let centCurrencies = ["USD", "EUR", "CAD", "AUD", "NZD", "SGD", "HKD", "TWD", "ZAR"]
        add("cent|cents|¢|セント|센트|цент|цента|центов|سنت|سنتات|เซนต์|sent|xu", codes: centCurrencies)
        add("美分|us cent|us cents|american cent|american cents", codes: ["USD"])
        add("dime|dimes", codes: ["USD"], value: 0.1)
        add("欧分|歐分|euro cent|euro cents|eurocent|eurocents|centime|centimes|céntimo|céntimos|cêntimo|cêntimos|centesimo|centesimi|centavo de euro|centavos de euro", codes: ["EUR"])
        add("penny|pennies|pence|пенни|بنس|بنسات", codes: ["GBP"])
        add("centavo|centavos", codes: ["BRL", "MXN", "ARS", "COP", "PHP"])
        add("分币|分幣|centavo brasileiro|centavos brasileiros", codes: ["BRL"])
        add("kopeck|kopecks|kopek|kopeks|копейка|копейки|копеек|копейку|戈比", codes: ["RUB"])
        add("piastre|piastres|piaster|piasters|قرش|قروش|قرشا|قرشًا|قرشان|قرشين", codes: ["EGP"])
        add("millieme|milliemes|مليم|مليمات", codes: ["EGP"], value: 0.001)
        add("satang|satangs|สตางค์|萨当|薩當", codes: ["THB"])
        add("sen", codes: ["IDR", "MYR"])
        add("kuruş|kurus|kuruşlar|kurush|库鲁什|庫魯什", codes: ["TRY"])
        return units
    }()

    static func parseMoneyConversion(
        _ rawText: String,
        preferredCurrencyCode: String?,
        locale: Locale = Locale(identifier: "en_US_POSIX")
    ) -> ClipboardAssistantMoneyConversion? {
        let text = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard (1...200).contains(text.count) else { return nil }
        let preferred = (preferredCurrencyCode ?? currentPreferredCurrencyCode()).uppercased()
        let operands = conversionOperands(text)
        let head = operands?[0] ?? (text.hasSuffix("=") ? String(text.dropLast()).trimmingCharacters(in: .whitespaces) : text)
        let targetToken = operands.flatMap { $0[1].isEmpty ? nil : $0[1] } ?? preferred
        let amount: Double
        let amountText: String
        let sourceToken: String
        if let prefixed = parsePrefixedCurrencyAmount(head, preferred: preferred, locale: locale) {
            amount = prefixed.amount
            amountText = prefixed.amountText
            sourceToken = prefixed.sourceCurrencyCode
        } else if let suffixed = parseSuffixedCurrencyAmount(head, locale: locale) {
            (amount, amountText, sourceToken) = suffixed
        } else {
            return nil
        }
        let sources = moneyUnitDefinitions(sourceToken, preferred: preferred)
        let targets = moneyUnitDefinitions(targetToken, preferred: preferred)
        guard !sources.isEmpty, !targets.isEmpty else { return nil }

        // An explicit currency at either end disambiguates shared names such as "cent".
        let commonCodes = sources.map(\.currencyCode).filter { code in targets.contains { $0.currencyCode == code } }
        let common = commonCodes.contains(preferred) ? preferred : commonCodes.first
        let source = sources.first { $0.currencyCode == common }
            ?? sources.first { $0.currencyCode == preferred } ?? sources[0]
        let target = targets.first { $0.currencyCode == common }
            ?? targets.first { $0.currencyCode == preferred } ?? targets[0]
        guard source.majorUnitValue != 1 || target.majorUnitValue != 1 else { return nil }
        return ClipboardAssistantMoneyConversion(
            amount: amount, amountText: amountText,
            source: .init(currencyCode: source.currencyCode, name: sourceToken, majorUnitValue: source.majorUnitValue),
            target: .init(currencyCode: target.currencyCode, name: targetToken, majorUnitValue: target.majorUnitValue)
        )
    }

    private static func moneyUnitDefinitions(_ token: String, preferred: String) -> [MoneyUnitDefinition] {
        if let definitions = moneyUnits[token.lowercased()] { return definitions }
        guard let code = resolveCurrencyToken(token, preferred: preferred) else { return [] }
        return [MoneyUnitDefinition(currencyCode: code, majorUnitValue: 1)]
    }

    public static func completedMoneyConversion(
        _ conversion: ClipboardAssistantMoneyConversion,
        rate: Double,
        locale: Locale
    ) -> ClipboardAssistantDetection? {
        let unitRate = conversion.unitRate(from: rate)
        let result = conversion.amount * unitRate
        guard rate > 0, result.isFinite else { return nil }
        let title = "\(formatNumber(result, locale: locale)) \(conversion.target.name)"
        let expression = "\(conversion.amountText) \(conversion.source.name) → \(conversion.target.name)"
        let usesLiveRate = conversion.source.currencyCode != conversion.target.currencyCode
        let fullExpression = "\(expression) = \(title)" + (usesLiveRate
            ? " · 1 \(conversion.source.name) = \(formatNumber(unitRate, locale: locale)) \(conversion.target.name)" : "")
        return ClipboardAssistantDetection(
            kind: .conversion, title: title,
            detail: usesLiveRate
                ? .currencyRate(sourceCurrencyCode: conversion.source.currencyCode, targetCurrencyCode: conversion.target.currencyCode, rate: rate)
                : .mathExpression(expression),
            actions: [.copyText(title), .copyFullExpression(fullExpression)],
            fullContent: fullExpression,
            moneyConversion: conversion
        )
    }
}
