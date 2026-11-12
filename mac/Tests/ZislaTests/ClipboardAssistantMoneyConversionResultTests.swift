import Foundation
import Testing
import ZislaCore
import ZislaKit
@testable import Zisla

@MainActor
struct ClipboardAssistantMoneyConversionResultTests {
    @Test(arguments: [
        ("100 USD cents to EUR cents", 0.9, "90 EUR cents"),
        ("1 USD to EUR cents", 0.9, "90 EUR cents"),
        ("100 USD cents to EUR", 0.9, "0.9 EUR"),
    ])
    func appResultUsesTheSubunitMetadata(_ query: String, rate: Double, expected: String) throws {
        let pending = try #require(ClipboardAssistantDetector.detect(
            text: query, enabledKinds: [.conversion], preferredCurrencyCode: "USD", locale: Locale(identifier: "en_US")
        ))
        guard case .currencyExpression(let amount, let text, let source, let target) = pending.detail else {
            Issue.record("Expected a pending live currency quote")
            return
        }
        let result = try #require(AppModel.currencyConversionResult(
            amount: amount, amountText: text, sourceCurrencyCode: source, targetCurrencyCode: target,
            quote: .init(sourceCurrencyCode: source, targetCurrencyCode: target, rate: rate, fetchedAt: .distantPast),
            moneyConversion: pending.moneyConversion, locale: Locale(identifier: "en_US")
        ))
        #expect(result.title == expected)
        #expect(result.action == .copyText(expected))
        #expect(result.moneyConversion == pending.moneyConversion)
    }

    @Test(arguments: [
        ("100 USD", 100.0, "USD", 7.0),
        ("JP¥14,500", 14500.0, "JPY", 0.05),
        ("PHP\u{00A0}5,339.84", 5339.84, "PHP", 0.125),
    ])
    func appResultPreservesTheExistingMajorCurrencyFormat(
        _ query: String, expectedAmount: Double, expectedSource: String, rate: Double
    ) throws {
        let pending = try #require(ClipboardAssistantDetector.detect(
            text: query, enabledKinds: [.conversion], preferredCurrencyCode: "CNY", locale: Locale(identifier: "en_US")
        ))
        guard case .currencyExpression(let amount, let text, let source, let target) = pending.detail else {
            Issue.record("Expected a pending live currency quote for \(query)")
            return
        }
        #expect(amount == expectedAmount)
        #expect(source == expectedSource)
        #expect(target == "CNY")
        let result = try #require(AppModel.currencyConversionResult(
            amount: amount, amountText: text, sourceCurrencyCode: source, targetCurrencyCode: target,
            quote: .init(sourceCurrencyCode: source, targetCurrencyCode: target, rate: rate, fetchedAt: .distantPast),
            moneyConversion: pending.moneyConversion, locale: Locale(identifier: "en_US")
        ))
        #expect(result.title == AppModel.currencyConversionTitle(for: expectedAmount * rate, currencyCode: "CNY"))
        #expect(result.detail == .currencyRate(sourceCurrencyCode: source, targetCurrencyCode: "CNY", rate: rate))
        #expect(result.action == .copyText(result.title))
        #expect(result.moneyConversion == nil)
    }

    @Test
    func appRejectsAnInvalidSubunitResult() throws {
        let pending = try #require(ClipboardAssistantDetector.detect(
            text: "100 USD cents to EUR cents", enabledKinds: [.conversion], preferredCurrencyCode: "USD"
        ))
        let result = AppModel.currencyConversionResult(
            amount: 1, amountText: "1", sourceCurrencyCode: "USD", targetCurrencyCode: "EUR",
            quote: .init(sourceCurrencyCode: "USD", targetCurrencyCode: "EUR", rate: .infinity, fetchedAt: .distantPast),
            moneyConversion: pending.moneyConversion, locale: Locale(identifier: "en_US")
        )
        #expect(result == nil)
    }
}
