import Foundation
import Testing
import ZislaCore
@testable import ZislaKit

struct ClipboardAssistantConversionRegressionTests {
    @Test(arguments: [
        "10 in to cm", "10 in in cm", "10 in = cm", "10 in -> cm",
        "10 IN to cm", "10 in to cm=",
    ])
    func convertsInchAbbreviationsBeforeTheConversionSeparator(_ query: String) throws {
        let conversion = try #require(ClipboardAssistantDetector.parseUnitConversion(query))
        #expect(abs(conversion.result - 25.4) < 0.000001)
        #expect(conversion.targetUnit == "cm")
    }

    @Test
    func inchConversionOffersTheConvertedValueToCopy() throws {
        let detection = try #require(ClipboardAssistantDetector.detect(
            text: "10 in to cm", enabledKinds: Set(ClipboardAssistantKind.allCases),
            systemLanguageIdentifier: "en", locale: Locale(identifier: "en_US")
        ))
        #expect(detection.kind == .math)
        #expect(detection.action == .copyText("25.4 cm"))
    }

    @Test(arguments: [
        "$100 in CNY", "$100 to CNY", "$100 in CNY=", "$100 to CNY=",
        "100 USD in CNY=", "100 USD to CNY=", "100$ in CNY=", "US$100 to cny=",
    ])
    func currencySymbolsComposeWithNaturalLanguageAndTrailingEquals(_ query: String) throws {
        let conversion = try #require(ClipboardAssistantDetector.parseCurrencyConversion(
            query, preferredCurrencyCode: "CNY"
        ))
        #expect(conversion.amount == 100)
        #expect(conversion.sourceCurrencyCode == "USD")
        #expect(conversion.targetCurrencyCode == "CNY")
    }

    @Test
    func currencyCompositionPreservesGroupedAmountsAndExistingSignedInputs() throws {
        let grouped = try #require(ClipboardAssistantDetector.parseCurrencyConversion(
            "$1,000.50 in CNY=", preferredCurrencyCode: "CNY"
        ))
        #expect(grouped.amount == 1000.5)
        #expect(grouped.amountText == "1,000.50")
        let signed = try #require(ClipboardAssistantDetector.parseCurrencyConversion(
            "-100 USD in CNY", preferredCurrencyCode: "CNY"
        ))
        #expect(signed.amount == -100)
    }

    @Test(arguments: [
        "$100 in CNY==", "$100==CNY", "$100 in XYZ", "$100 in USD",
        "$100 in CNY and 20 EUR", "100$=CNY=",
    ])
    func currencyCompositionRejectsInvalidWholeValues(_ query: String) {
        #expect(ClipboardAssistantDetector.parseCurrencyConversion(
            query, preferredCurrencyCode: "CNY"
        ) == nil)
    }

    @Test(arguments: ["10 in to kg", "10 in to cm of prose", "10 in to cm=="])
    func inchConversionStillRejectsInvalidDimensionsAndTrailingText(_ query: String) {
        #expect(ClipboardAssistantDetector.parseUnitConversion(query) == nil)
    }

    @Test(arguments: [
        "2026-11-01 01:30 America/New_York to UTC",
        "2026-04-05 01:30 Australia/Lord_Howe to UTC",
        "2026-04-05 01:45 Australia/Lord_Howe to UTC",
        "2026-03-08 02:30 America/New_York to UTC",
        "2026-10-04 02:15 Australia/Lord_Howe to UTC",
    ])
    func timeZoneConversionRejectsRepeatedAndSkippedWallTimes(_ query: String) {
        #expect(ClipboardAssistantDetector.parseTimeZoneConversion(query) == nil)
    }

    @Test(arguments: [
        ("2026-11-01 00:30 America/New_York to UTC", "2026-11-01 04:30:00"),
        ("2026-11-01 02:30 America/New_York to UTC", "2026-11-01 07:30:00"),
        ("2026-04-05 01:29:59 Australia/Lord_Howe to UTC", "2026-04-04 14:29:59"),
        ("2026-04-05 02:00 Australia/Lord_Howe to UTC", "2026-04-04 15:30:00"),
        ("2026-04-05 01:45 UTC+11:00 to UTC", "2026-04-04 14:45:00"),
        ("2026-04-05 01:45 UTC+10:30 to UTC", "2026-04-04 15:15:00"),
        ("2026-11-01 01:30 UTC-04:00 to UTC", "2026-11-01 05:30:00"),
        ("2026-11-01 01:30 UTC-05:00 to UTC", "2026-11-01 06:30:00"),
    ])
    func unambiguousTimesAndExplicitOffsetsStillConvert(_ query: String, expectedUTC: String) throws {
        let conversion = try #require(ClipboardAssistantDetector.parseTimeZoneConversion(query))
        #expect(conversion.targetText == "\(expectedUTC) Z [GMT]")
    }
}
