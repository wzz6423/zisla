import Foundation
import Testing
import ZislaCore
@testable import ZislaKit

struct ClipboardAssistantMoneyUnitConversionTests {
    @Test(arguments: [
        ("1元=?角", "元", "角", 10.0),
        ("0.1角=?分", "角", "分", 1.0),
        ("1元=?分", "元", "分", 100.0),
        ("100分=?元", "分", "元", 1.0),
        ("1分=?角", "分", "角", 0.1),
        ("1dollar=?cent", "dollar", "cent", 100.0),
        ("1cent=?dollar", "cent", "dollar", 0.01),
        ("0元=?分", "元", "分", 0.0),
        ("-1.25dollars to cents", "dollars", "cents", -125.0),
        ("1,000.50元换算成角", "元", "角", 10005.0),
    ])
    func convertsMoneyDenominations(_ query: String, source: String, target: String, expected: Double) throws {
        let conversion = try #require(ClipboardAssistantDetector.parseMoneyConversion(query, preferredCurrencyCode: "CNY"))
        #expect(conversion.source.name == source)
        #expect(conversion.target.name == target)
        #expect(abs(conversion.amount * conversion.unitRate(from: 1) - expected) < 0.000001)
    }

    @Test(arguments: [
        ("1人民币=？角", 10.0), ("1人民幣轉分", 100.0),
        ("1块=毛", 10.0), ("1塊=分", 100.0),
        ("1圆=角", 10.0), ("1圓=分", 100.0),
        ("1CNY to jiao", 10.0), ("1RMB to fen", 100.0),
        ("1yuan to fen", 100.0), ("1renminbi to jiao", 10.0),
        ("1毛=?分", 10.0), ("1jiao to fen", 10.0),
        ("1USD=?cent", 100.0), ("1美元换算成美分", 100.0),
        ("1美金=美分", 100.0), ("1DOLLARS TO CENTS", 100.0),
        ("1us dollar to cents", 100.0), ("100美分=美元", 1.0),
        ("100¢ to dollars", 1.0),
    ])
    func supportsCurrencyAliasesAndExistingConnectors(_ query: String, expected: Double) throws {
        let conversion = try #require(ClipboardAssistantDetector.parseMoneyConversion(query, preferredCurrencyCode: "CNY"))
        #expect(abs(conversion.amount * conversion.unitRate(from: 1) - expected) < 0.000001)
    }

    @Test(arguments: [
        ("1元=?角", "10 角", "1 元 → 角 = 10 角"),
        ("0.1角=?分", "1 分", "0.1 角 → 分 = 1 分"),
        ("1dollar=?cent", "100 cent", "1 dollar → cent = 100 cent"),
    ])
    func conversionKindOffersTheResultAndFullExpression(_ query: String, result: String, expression: String) throws {
        for enabledKinds in [Set([ClipboardAssistantKind.conversion]), Set(ClipboardAssistantKind.allCases)] {
            let detection = try #require(ClipboardAssistantDetector.detect(
                text: query, enabledKinds: enabledKinds, preferredCurrencyCode: "CNY",
                locale: Locale(identifier: "en_US"), countryCode: "US"
            ))
            #expect(detection.kind == .conversion)
            #expect(detection.title == result)
            #expect(detection.actions == [.copyText(result), .copyFullExpression(expression)])
            #expect(detection.fullContent == expression)
        }
        #expect(ClipboardAssistantDetector.detect(text: query, enabledKinds: [.math]) == nil)
    }

    @Test(arguments: [
        ("1分 to 秒", "min", "s", 60.0),
        ("1時間 to 分", "hr", "min", 60.0),
    ])
    func resolvesTheSharedFenAndMinuteTokenByCategory(_ query: String, source: String, target: String, expected: Double) throws {
        let conversion = try #require(ClipboardAssistantDetector.parseUnitConversion(query))
        #expect(conversion.sourceUnit == source)
        #expect(conversion.targetUnit == target)
        #expect(abs(conversion.result - expected) < 0.000001)
    }

    @Test(arguments: [
        "", "元=?角", "1元==角",
        "1元=?角 trailing", "请把1元=?角", "1元=?角=1", "1元=?角\u{0}",
        "1.2.3元=?角", "1,00元=?角", "NaN元=?角", "Infinity元=?角", "²元=?角", "Ⅷ元=?角",
        "1角=?kg", "1cent=?cm", "1分钟=?元", "1JPY=?JPY sen", "1KRW=?jeon",
        "1VND=?hào", "1VND=?VND xu", "1JPY=?銭", "1KRW=?전",
    ])
    func rejectsIncompleteInvalidAndIncompatibleConversions(_ query: String) {
        #expect(ClipboardAssistantDetector.parseUnitConversion(query) == nil)
        #expect(ClipboardAssistantDetector.parseMoneyConversion(query, preferredCurrencyCode: "CNY") == nil)
        #expect(ClipboardAssistantDetector.detect(text: query, enabledKinds: [.conversion], preferredCurrencyCode: "CNY", locale: Locale(identifier: "en_US")) == nil)
    }

    @Test
    func keepsLiveExchangeRatesAndAmbiguousDollarCurrencies() throws {
        for (query, preferred, source, target) in [
            ("100美元=？人民币", "CNY", "USD", "CNY"),
            ("100元=?USD", "USD", "CNY", "USD"),
            ("100 dollars to euros", "CAD", "CAD", "EUR"),
        ] {
            let detection = try #require(ClipboardAssistantDetector.detect(
                text: query, enabledKinds: [.conversion], preferredCurrencyCode: preferred
            ))
            #expect(detection.detail == .currencyExpression(
                amount: 100, amountText: "100", sourceCurrencyCode: source, targetCurrencyCode: target
            ))
            #expect(detection.actions.isEmpty)
        }
    }

    @Test(arguments: AppLanguage.allCases)
    func formatsMoneyResultsUsingEveryInterfaceLocale(language: AppLanguage) throws {
        let detection = try #require(ClipboardAssistantDetector.detect(
            text: "1分=?角", enabledKinds: [.conversion], preferredCurrencyCode: "CNY", locale: language.locale
        ))
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.locale = language.locale
        let expected = try #require(formatter.string(from: 0.1)) + " 角"
        #expect(detection.title == expected, "incorrect number formatting for \(language.rawValue)")
        #expect(detection.action == .copyText(expected))
    }

    @Test
    func boundsInputAndPreservesSeededRoundTrips() throws {
        let short = "1元=?角"
        let bounded = "1元" + String(repeating: " ", count: 200 - short.count) + "=?角"
        #expect(bounded.count == 200)
        #expect(ClipboardAssistantDetector.parseMoneyConversion(bounded, preferredCurrencyCode: "CNY") != nil)
        #expect(ClipboardAssistantDetector.parseMoneyConversion(bounded + "x", preferredCurrencyCode: "CNY") == nil)

        var seed: UInt64 = 0xC011
        for _ in 0..<32 {
            seed = seed &* 6_364_136_223_846_793_005 &+ 1
            let value = Int((seed >> 32) % 10000) - 5000
            for (source, target) in [("元", "分"), ("角", "分"), ("dollar", "cent")] {
                let query = "\(value)\(source)=?\(target)"
                let forward = try #require(ClipboardAssistantDetector.parseMoneyConversion(query, preferredCurrencyCode: "CNY"))
                let result = forward.amount * forward.unitRate(from: 1)
                let inverse = try #require(ClipboardAssistantDetector.parseMoneyConversion("\(result)\(target)=?\(source)", preferredCurrencyCode: "CNY"))
                #expect(abs(inverse.amount * inverse.unitRate(from: 1) - Double(value)) < 0.000001, "round trip failed: \(query)")
                #expect(ClipboardAssistantDetector.parseMoneyConversion(query + " trailing", preferredCurrencyCode: "CNY") == nil)
            }
        }
    }

    @Test(arguments: AppLanguage.allCases)
    func everyLanguageConvertsLocalSubunitsAndUsesItsNativeConnector(language: AppLanguage) throws {
        let examples: [AppLanguage: (query: String, code: String, expected: Double)] = [
            .simplifiedChinese: ("1元换算成角", "CNY", 10),
            .traditionalChinese: ("1新台幣換算成分", "TWD", 100),
            .english: ("1 dollar to cents", "USD", 100),
            .japanese: ("1米ドルをセントに変換", "USD", 100),
            .korean: ("1미국 달러를 센트로 변환", "USD", 100),
            .french: ("1 euro en centimes", "EUR", 100),
            .german: ("1 Euro in Cent", "EUR", 100),
            .spanish: ("1 euro a céntimos", "EUR", 100),
            .brazilianPortuguese: ("1 real para centavos", "BRL", 100),
            .italian: ("1 euro in centesimi", "EUR", 100),
            .dutch: ("1 euro naar cent", "EUR", 100),
            .russian: ("1 рубль в копейки", "RUB", 100),
            .arabic: ("١ جنيه إلى قروش", "EGP", 100),
            .thai: ("1บาทเป็นสตางค์", "THB", 100),
            .indonesian: ("1 rupiah ke sen", "IDR", 100),
            .vietnamese: ("1 Đô la Mỹ sang xu", "USD", 100),
            .turkish: ("1 Türk lirası kuruş'a çevir", "TRY", 100),
        ]
        #expect(examples.count == AppLanguage.allCases.count)
        let example = try #require(examples[language])
        let preferred = ClipboardAssistantDetector.currentPreferredCurrencyCode(language: language)
        let conversion = try #require(ClipboardAssistantDetector.parseMoneyConversion(
            example.query, preferredCurrencyCode: preferred, locale: language.locale
        ), "money conversion failed for \(language.rawValue): \(example.query)")
        #expect(conversion.source.currencyCode == example.code)
        #expect(conversion.target.currencyCode == example.code)
        #expect(conversion.amount * conversion.unitRate(from: 1) == example.expected)
        let detection = try #require(ClipboardAssistantDetector.detect(
            text: example.query, enabledKinds: [.conversion], preferredCurrencyCode: preferred, locale: language.locale
        ))
        #expect(detection.actions.count == 2)
        #expect(detection.moneyConversion == conversion)
    }

    @Test(arguments: AppLanguage.allCases)
    func allLocalizedCurrencyNamesRemainAvailableForLiveExchange(language: AppLanguage) throws {
        let sourceCode = ClipboardAssistantDetector.currentPreferredCurrencyCode(language: language)
        let sourceName = try #require(language.locale.localizedString(forCurrencyCode: sourceCode))
        let targetCode = sourceCode == "USD" ? "CNY" : "USD"
        let targetName = try #require(language.locale.localizedString(forCurrencyCode: targetCode))
        let detection = try #require(ClipboardAssistantDetector.detect(
            text: "1 \(sourceName)=?\(targetName)", enabledKinds: [.conversion],
            preferredCurrencyCode: sourceCode, locale: language.locale
        ))
        #expect(detection.detail == .currencyExpression(
            amount: 1, amountText: "1", sourceCurrencyCode: sourceCode, targetCurrencyCode: targetCode
        ))
        #expect(detection.moneyConversion == nil)
    }

    @Test(arguments: [
        ("0,1 euro en centimes", "fr", "EUR", 0.1),
        ("1.000,50 Euro in Cent", "de", "EUR", 1000.5),
        ("1\u{202F}000,50 euros en centimes", "fr", "EUR", 1000.5),
        ("1\u{00A0}000,50 рубля в копейки", "ru", "RUB", 1000.5),
        ("١٫٢٥ جنيه إلى قروش", "ar", "EGP", 1.25),
        ("١٬٠٠٠٫٥٠ جنيه إلى قروش", "ar", "EGP", 1000.5),
        ("１.２５米ドルをセントに変換", "ja", "USD", 1.25),
        ("1.000,50 rupiah ke sen", "id", "IDR", 1000.5),
    ])
    func parsesNativeDecimalGroupingAndDigitForms(_ query: String, localeID: String, code: String, expected: Double) throws {
        let conversion = try #require(ClipboardAssistantDetector.parseMoneyConversion(
            query, preferredCurrencyCode: code, locale: Locale(identifier: localeID)
        ))
        #expect(conversion.amount == expected)
        #expect(abs(conversion.amount * conversion.unitRate(from: 1) - expected * 100) < 0.000001)
    }

    @Test(arguments: [
        ("100分=?USD", "CNY", "USD", 1.0),
        ("100 US cents to EUR", "USD", "EUR", 1.0),
        ("100 centimes to CNY", "EUR", "CNY", 1.0),
        ("100 копеек в USD", "RUB", "USD", 1.0),
        ("100 قروش إلى USD", "EGP", "USD", 1.0),
        ("100สตางค์เป็นUSD", "THB", "USD", 1.0),
        ("100 sen ke USD", "IDR", "USD", 1.0),
        ("100 kuruş USD'ye çevir", "TRY", "USD", 1.0),
        ("100 centavos para USD", "BRL", "USD", 1.0),
        ("1000 مليم إلى USD", "EGP", "USD", 1.0),
    ])
    func normalizesSourceSubunitsForLiveQuotes(_ query: String, source: String, target: String, amount: Double) throws {
        let detection = try #require(ClipboardAssistantDetector.detect(
            text: query, enabledKinds: [.conversion], preferredCurrencyCode: source, locale: Locale(identifier: "en_US")
        ))
        #expect(detection.detail == .currencyExpression(
            amount: amount, amountText: "1", sourceCurrencyCode: source, targetCurrencyCode: target
        ))
        #expect(detection.actions.isEmpty)
        #expect(detection.moneyConversion != nil)
    }

    @Test(arguments: [
        ("1元=?USD cents", "CNY", "USD", 0.1, 10.0),
        ("100分=?USD cents", "CNY", "USD", 0.1, 10.0),
        ("100 US cents to CNY", "USD", "CNY", 7.0, 7.0),
        ("1 USD to EUR cents", "USD", "EUR", 0.9, 90.0),
        ("100 EUR cents to USD cents", "EUR", "USD", 1.1, 110.0),
        ("1000 مليم إلى USD", "EGP", "USD", 0.02, 0.02),
    ])
    func convertsLiveQuotesBackIntoTheRequestedTargetUnit(_ query: String, source: String, target: String, rate: Double, expected: Double) throws {
        let conversion = try #require(ClipboardAssistantDetector.parseMoneyConversion(query, preferredCurrencyCode: source))
        #expect(conversion.source.currencyCode == source)
        #expect(conversion.target.currencyCode == target)
        let detection = try #require(ClipboardAssistantDetector.completedMoneyConversion(
            conversion, rate: rate, locale: Locale(identifier: "en_US")
        ))
        let title = "\(ClipboardAssistantDetector.formatNumber(expected, locale: Locale(identifier: "en_US"))) \(conversion.target.name)"
        #expect(detection.title == title)
        #expect(detection.action == .copyText(title))
        #expect(detection.fullContent?.contains("\(conversion.amountText) \(conversion.source.name)") == true)
        #expect(detection.detail == .currencyRate(sourceCurrencyCode: source, targetCurrencyCode: target, rate: rate))
    }

    @Test
    func genericSubunitNamesFollowExplicitCurrenciesAndThenThePreference() throws {
        for (query, preferred, expected) in [
            ("1EUR to cents", "USD", "EUR"), ("1CAD to cent", "CNY", "CAD"),
            ("100 cents to AUD", "USD", "AUD"), ("1台幣=分", "CNY", "TWD"),
            ("1元=分", "TWD", "CNY"), ("100 cents to dollars", "CAD", "CAD"),
            ("100 cents", "EUR", "EUR"), ("100 centavos", "BRL", "BRL"),
            ("100 cents to ¢", "EUR", "EUR"), ("1角=?分", "TWD", "TWD"),
        ] {
            let conversion = try #require(ClipboardAssistantDetector.parseMoneyConversion(query, preferredCurrencyCode: preferred))
            #expect(conversion.source.currencyCode == expected)
            #expect(conversion.target.currencyCode == expected)
        }
        #expect(ClipboardAssistantDetector.parseMoneyConversion("100 cents to EUR cents", preferredCurrencyCode: "USD")?.source.currencyCode == "EUR")
        #expect(ClipboardAssistantDetector.parseMoneyConversion("100 USD cents to EUR cents", preferredCurrencyCode: "USD")?.source.currencyCode == "USD")
        for (query, preferred, source, target) in [
            ("100 centavos to CNY", "PHP", "PHP", "CNY"),
            ("1元=?cents", "EUR", "CNY", "EUR"),
            ("1cent=?CNY", "CNY", "USD", "CNY"),
        ] {
            let conversion = try #require(ClipboardAssistantDetector.parseMoneyConversion(query, preferredCurrencyCode: preferred))
            #expect(conversion.source.currencyCode == source)
            #expect(conversion.target.currencyCode == target)
        }
    }

    @Test(arguments: [0.0, -1.0, Double.nan, Double.infinity, Double.greatestFiniteMagnitude])
    func invalidAndOverflowingRatesNeverOfferACopyableResult(rate: Double) throws {
        let conversion = try #require(ClipboardAssistantDetector.parseMoneyConversion("100 USD cents to EUR cents", preferredCurrencyCode: "USD"))
        #expect(ClipboardAssistantDetector.completedMoneyConversion(conversion, rate: rate, locale: Locale(identifier: "en_US")) == nil)
    }

    @Test(arguments: [
        ("1USD to dimes", "USD", 10.0), ("1GBP to pence", "GBP", 100.0),
        ("1EGP to milliemes", "EGP", 1000.0), ("1EGP to piastres", "EGP", 100.0),
        ("1MYR to sen", "MYR", 100.0), ("1CNY to 人民币分", "CNY", 100.0),
        ("1TWD to 台角", "TWD", 10.0), ("1TWD to 臺分", "TWD", 100.0),
        ("1USD to cents", "USD", 100.0), ("1EUR to cents", "EUR", 100.0),
        ("1CAD to cents", "CAD", 100.0), ("1AUD to cents", "AUD", 100.0),
        ("1NZD to cents", "NZD", 100.0), ("1SGD to cents", "SGD", 100.0),
        ("1HKD to cents", "HKD", 100.0), ("1TWD to cents", "TWD", 100.0),
        ("1ZAR to cents", "ZAR", 100.0), ("1BRL to centavos", "BRL", 100.0),
        ("1MXN to centavos", "MXN", 100.0), ("1ARS to centavos", "ARS", 100.0),
        ("1COP to centavos", "COP", 100.0), ("1PHP to centavos", "PHP", 100.0),
    ])
    func usesEachSupportedCurrencyFamilyAndSubdivision(_ query: String, code: String, expected: Double) throws {
        let conversion = try #require(ClipboardAssistantDetector.parseMoneyConversion(query, preferredCurrencyCode: "CNY"))
        #expect(conversion.source.currencyCode == code)
        #expect(conversion.target.currencyCode == code)
        #expect(conversion.amount * conversion.unitRate(from: 1) == expected)
    }

    @Test(arguments: ["fr", "de", "es", "pt-BR", "it", "nl", "ru", "id", "vi", "tr"])
    func nativeDecimalParsingAlsoReachesExistingMajorCurrencyConversions(localeID: String) throws {
        let detection = try #require(ClipboardAssistantDetector.detect(
            text: "1,25 USD to CNY", enabledKinds: [.conversion], preferredCurrencyCode: "CNY", locale: Locale(identifier: localeID)
        ))
        #expect(detection.detail == .currencyExpression(
            amount: 1.25, amountText: "1,25", sourceCurrencyCode: "USD", targetCurrencyCode: "CNY"
        ))
        #expect(detection.moneyConversion == nil)
    }

    @Test(arguments: [
        ("$1=?cent", "USD", "USD", 100.0), ("US$1 to cents", "CNY", "USD", 100.0),
        ("C$1 to cents", "USD", "CAD", 100.0), ("¥1=?角", "CNY", "CNY", 10.0),
        ("NT$1=?台分", "CNY", "TWD", 100.0), ("€1,25 en centimes", "EUR", "EUR", 125.0),
        ("R$1,25 para centavos", "BRL", "BRL", 125.0),
    ])
    func prefixSymbolsKeepTheirCurrencyFamilyAndNativeAmount(_ query: String, preferred: String, expectedCode: String, expected: Double) throws {
        let locale = Locale(identifier: query.contains(",") ? "pt-BR" : "en_US")
        let conversion = try #require(ClipboardAssistantDetector.parseMoneyConversion(
            query, preferredCurrencyCode: preferred, locale: locale
        ))
        #expect(conversion.source.currencyCode == expectedCode)
        #expect(conversion.target.currencyCode == expectedCode)
        #expect(conversion.amount * conversion.unitRate(from: 1) == expected)
    }

    @Test
    func oversizedBareSubunitAmountsAreRejected() {
        let query = String(repeating: "1", count: 201) + " cents"
        #expect(ClipboardAssistantDetector.parseMoneyConversion(query, preferredCurrencyCode: "USD") == nil)
        #expect(ClipboardAssistantDetector.detect(text: query, enabledKinds: [.conversion], preferredCurrencyCode: "USD") == nil)
    }

    @Test
    func arabicMajorAmountsAndAsciiCompatibilityRemainAvailable() throws {
        for (query, locale, amount, expectedText) in [
            ("١٫٢٥ USD to CNY", "ar", 1.25, "١٫٢٥"),
            ("1,000.50 USD to CNY", "fr", 1000.5, "1,000.50"),
            ("100\u{00A0}USD to CNY", "en_US", 100, "100"),
        ] {
            let detection = try #require(ClipboardAssistantDetector.detect(
                text: query, enabledKinds: [.conversion], preferredCurrencyCode: "CNY", locale: Locale(identifier: locale)
            ))
            #expect(detection.detail == .currencyExpression(
                amount: amount, amountText: expectedText, sourceCurrencyCode: "USD", targetCurrencyCode: "CNY"
            ))
        }
    }

    @Test(arguments: [
        "100 cents", "100 cents=", "100 cents=?", "100 cents=؟",
    ])
    func bareSubunitAmountsUseThePreferredMajorCurrency(_ query: String) throws {
        let conversion = try #require(ClipboardAssistantDetector.parseMoneyConversion(query, preferredCurrencyCode: "EUR"))
        #expect(conversion.source.currencyCode == "EUR")
        #expect(conversion.target.currencyCode == "EUR")
        #expect(conversion.amount * conversion.unitRate(from: 1) == 1)
    }
}
