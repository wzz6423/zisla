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
        #expect(detection.kind == .conversion)
        #expect(detection.action == .copyText("25.4 cm"))
    }

    @Test
    func conversionKindControlsEveryConversionWithoutChangingMathOrDateTime() throws {
        let now = Date(timeIntervalSince1970: 0)
        let timeZone = try #require(TimeZone(secondsFromGMT: 0))
        let conversionKinds: Set<ClipboardAssistantKind> = [.conversion, .text]
        for text in [
            "10 ft = m",
            "100 USD = CNY",
            "2026-09-17 - 2026-10-01",
            "2026-09-17 09:30 UTC+08:00 = UTC",
        ] {
            let detection = try #require(ClipboardAssistantDetector.detect(
                text: text,
                enabledKinds: conversionKinds,
                preferredCurrencyCode: "CNY",
                now: now,
                timeZone: timeZone
            ))
            #expect(detection.kind == .conversion, "expected \(text) to use the conversion kind")
        }

        let standardKinds: Set<ClipboardAssistantKind> = [.math, .dateTime, .text]
        for text in [
            "10 ft = m",
            "100 USD = CNY",
            "2026-09-17 - 2026-10-01",
            "2026-09-17 09:30 UTC+08:00 = UTC",
        ] {
            #expect(ClipboardAssistantDetector.detect(
                text: text,
                enabledKinds: standardKinds,
                preferredCurrencyCode: "CNY",
                now: now,
                timeZone: timeZone
            )?.kind != .conversion)
        }

        #expect(ClipboardAssistantDetector.detect(
            text: "2+2=",
            enabledKinds: [.math],
            now: now
        )?.kind == .math)
        #expect(ClipboardAssistantDetector.detect(
            text: "2026-09-17",
            enabledKinds: [.dateTime],
            now: now
        )?.kind == .dateTime)
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

    @Test(arguments: AppLanguage.allCases)
    func parsesLocalizedDateIntervalsForEveryInterfaceLanguage(language: AppLanguage) throws {
        let examples: [AppLanguage: (until: String, between: String, relative: String)] = [
            .simplifiedChinese: ("距离2026-09-20还有几天", "2026-09-14到2026-09-20相差几天", "今天到明天相差几天"),
            .traditionalChinese: ("距離2026-09-20還有幾天", "2026-09-14至2026-09-20相差幾天", "今天至明天相差幾天"),
            .english: ("how many days until 2026-09-20?", "how many days between 2026-09-14 and 2026-09-20?", "between today and tomorrow"),
            .japanese: ("2026-09-20まであと何日", "2026-09-14から2026-09-20まで何日", "今日から明日まで何日"),
            .korean: ("2026-09-20까지 며칠 남았어", "2026-09-14부터 2026-09-20까지 며칠", "오늘부터 내일까지 며칠"),
            .french: ("combien de jours jusqu'au 2026-09-20", "combien de jours entre 2026-09-14 et 2026-09-20", "combien de jours entre aujourd'hui et demain"),
            .german: ("wie viele Tage bis 2026-09-20", "wie viele Tage zwischen 2026-09-14 und 2026-09-20", "wie viele Tage zwischen heute und morgen"),
            .spanish: ("cuántos días hasta 2026-09-20", "cuántos días entre 2026-09-14 y 2026-09-20", "cuántos días entre hoy y mañana"),
            .brazilianPortuguese: ("quantos dias até 2026-09-20", "quantos dias entre 2026-09-14 e 2026-09-20", "quantos dias entre hoje e amanhã"),
            .italian: ("quanti giorni fino al 2026-09-20", "quanti giorni tra 2026-09-14 e 2026-09-20", "quanti giorni tra oggi e domani"),
            .dutch: ("hoeveel dagen tot 2026-09-20", "hoeveel dagen tussen 2026-09-14 en 2026-09-20", "hoeveel dagen tussen vandaag en morgen"),
            .russian: ("сколько дней до 2026-09-20", "сколько дней между 2026-09-14 и 2026-09-20", "сколько дней между сегодня и завтра"),
            .arabic: ("كم يومًا حتى 2026-09-20", "كم يومًا بين 2026-09-14 و 2026-09-20", "كم يومًا بين اليوم و غدًا"),
            .thai: ("อีกกี่วันถึง 2026-09-20", "ระหว่าง 2026-09-14 ถึง 2026-09-20 กี่วัน", "ระหว่าง วันนี้ ถึง พรุ่งนี้ กี่วัน"),
            .indonesian: ("berapa hari sampai 2026-09-20", "berapa hari antara 2026-09-14 dan 2026-09-20", "berapa hari antara hari ini dan besok"),
            .vietnamese: ("còn bao nhiêu ngày đến 2026-09-20", "bao nhiêu ngày giữa 2026-09-14 và 2026-09-20", "bao nhiêu ngày giữa hôm nay và ngày mai"),
            .turkish: ("2026-09-20 tarihine kaç gün kaldı", "2026-09-14 ile 2026-09-20 arasında kaç gün", "bugün ile yarın arasında kaç gün"),
        ]
        let example = try #require(examples[language])
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(secondsFromGMT: 0))
        let now = try #require(calendar.date(from: DateComponents(year: 2026, month: 9, day: 14, hour: 12)))

        let until = try #require(ClipboardAssistantDetector.parseDateInterval(example.until, now: now, timeZone: calendar.timeZone))
        #expect(until.days == 6, "until expression failed for \(language.rawValue)")
        let between = try #require(ClipboardAssistantDetector.parseDateInterval(example.between, now: now, timeZone: calendar.timeZone))
        #expect(between.days == 6, "between expression failed for \(language.rawValue)")
        let relative = try #require(ClipboardAssistantDetector.parseDateInterval(example.relative, now: now, timeZone: calendar.timeZone))
        #expect(relative.days == 1, "relative expression failed for \(language.rawValue)")
    }

    @Test(arguments: AppLanguage.allCases)
    func parsesLocalizedTimeZoneConnectorsAndCityAliasesForEveryInterfaceLanguage(language: AppLanguage) throws {
        let examples: [AppLanguage: (query: String, source: String, target: String)] = [
            .simplifiedChinese: ("2026-01-01 12:00 上海 转 纽约", "Asia/Shanghai", "America/New_York"),
            .traditionalChinese: ("2026-01-01 12:00 上海 轉 紐約", "Asia/Shanghai", "America/New_York"),
            .english: ("2026-01-01 12:00 Beijing to New York", "Asia/Shanghai", "America/New_York"),
            .japanese: ("2026-01-01 12:00 東京 から ニューヨーク に", "Asia/Tokyo", "America/New_York"),
            .korean: ("2026-01-01 12:00 상하이에서 뉴욕으로", "Asia/Shanghai", "America/New_York"),
            .french: ("2026-01-01 12:00 Pékin vers Londres", "Asia/Shanghai", "Europe/London"),
            .german: ("2026-01-01 12:00 Tokio nach London", "Asia/Tokyo", "Europe/London"),
            .spanish: ("2026-01-01 12:00 Pekín a Nueva York", "Asia/Shanghai", "America/New_York"),
            .brazilianPortuguese: ("2026-01-01 12:00 Pequim para Tóquio", "Asia/Shanghai", "Asia/Tokyo"),
            .italian: ("2026-01-01 12:00 Pechino a Londra", "Asia/Shanghai", "Europe/London"),
            .dutch: ("2026-01-01 12:00 Peking naar Londen", "Asia/Shanghai", "Europe/London"),
            .russian: ("2026-01-01 12:00 Пекин в Токио", "Asia/Shanghai", "Asia/Tokyo"),
            .arabic: ("2026-01-01 12:00 بكين إلى لندن", "Asia/Shanghai", "Europe/London"),
            .thai: ("2026-01-01 12:00 ปักกิ่ง เป็น โตเกียว", "Asia/Shanghai", "Asia/Tokyo"),
            .indonesian: ("2026-01-01 12:00 Beijing ke New York", "Asia/Shanghai", "America/New_York"),
            .vietnamese: ("2026-01-01 12:00 Bắc Kinh sang Luân Đôn", "Asia/Shanghai", "Europe/London"),
            .turkish: ("2026-01-01 12:00 Şanghay'dan New York'a", "Asia/Shanghai", "America/New_York"),
        ]
        let example = try #require(examples[language])
        let conversion = try #require(ClipboardAssistantDetector.parseTimeZoneConversion(example.query))
        #expect(conversion.sourceText.hasSuffix("[\(example.source)]"), "time-zone source failed for \(language.rawValue)")
        #expect(conversion.targetText.hasSuffix("[\(example.target)]"), "time-zone expression failed for \(language.rawValue)")
    }

    @Test
    func recognizesMultiWordCityNamesAtBothEndsOfATimeZoneConversion() throws {
        let fromNewYork = try #require(ClipboardAssistantDetector.parseTimeZoneConversion(
            "2026-01-01 12:00 New York to UTC"
        ))
        #expect(fromNewYork.sourceText.hasSuffix("[America/New_York]"))

        let toNewYork = try #require(ClipboardAssistantDetector.parseTimeZoneConversion(
            "2026-01-01 12:00 UTC to New York"
        ))
        #expect(toNewYork.targetText.hasSuffix("[America/New_York]"))
    }
}
