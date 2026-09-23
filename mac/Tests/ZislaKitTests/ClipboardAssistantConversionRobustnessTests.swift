import Foundation
import Testing
import ZislaCore
@testable import ZislaKit

struct ClipboardAssistantConversionRobustnessTests {
    private let utc = TimeZone(secondsFromGMT: 0)!
    private let now = Date(timeIntervalSince1970: 1_790_035_200) // 2026-09-22 00:00 UTC.

    @Test(arguments: [
        ("09-21到09-23", 2), ("09-21～09-23", 2), ("09/21 ~ 09/23", 2),
        ("2026.1.23-2026.1.23", 0), ("2026.1.23～2026.1.23", 0),
        ("2026.1.23到2026.1.23", 0), ("2026-1-23～2026-1-23", 0),
        ("2026-1-23-2026-1-24", 1), ("2026/1/23—2026/1/24", 1),
        ("2024-02-28～2024-03-01", 2), ("2026-03-01至2026-02-28", -1),
        ("9月21日到9月23日", 2), ("12-31到01-01", -364),
    ])
    func parsesCompleteAndCurrentYearIntervals(_ query: String, days: Int) throws {
        let result = try #require(ClipboardAssistantDetector.parseDateInterval(query, now: now, timeZone: utc))
        #expect(result.days == days)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = utc
        #expect(calendar.component(.year, from: result.startDate) == (query.hasPrefix("2024") ? 2024 : 2026))
        let detection = try #require(ClipboardAssistantDetector.detect(
            text: query, enabledKinds: Set(ClipboardAssistantKind.allCases), now: now, timeZone: utc, locale: Locale(identifier: "en_US")
        ))
        #expect(detection.kind == .conversion)
        #expect(detection.actions.first == .copyText("\(days) days"))
    }

    @Test(arguments: [
        "2026-02-29到2026-03-01", "02-30～03-01", "2026.13.1-2026.1.1",
        "10-3", "1.2.3-1.2.4", "v2026.1.23-v2026.1.24", "09-21-09-23",
        "https://example.com/2026-01-23", "2026-1/23到2026-1-24", "2026-1-1到2026-1-2 note",
    ])
    func refusesInvalidAndNonDateIntervals(_ query: String) {
        #expect(ClipboardAssistantDetector.parseDateInterval(query, now: now, timeZone: utc) == nil)
    }

    @Test(arguments: [
        "100美元是多少人民币", "100美元=？", "100美元=？人民币", "100美元=?人民币",
        "100美元等于多少人民币？", "100美元换算成人民币", "100美元換算成人民幣",
        "100 USD = ? CNY", "100 USD to CNY?", "$100 in CNY？", "100美元是多少？",
    ])
    func parsesNaturalCurrencyRequests(_ query: String) throws {
        let parsed = try #require(ClipboardAssistantDetector.parseCurrencyConversion(query, preferredCurrencyCode: "CNY"))
        #expect(parsed.amount == 100)
        #expect(parsed.sourceCurrencyCode == "USD")
        #expect(parsed.targetCurrencyCode == nil || parsed.targetCurrencyCode == "CNY")
        let detection = try #require(ClipboardAssistantDetector.detect(
            text: query, enabledKinds: Set(ClipboardAssistantKind.allCases), preferredCurrencyCode: "CNY", now: now, timeZone: utc
        ))
        #expect(detection.detail == .currencyExpression(amount: 100, amountText: "100", sourceCurrencyCode: "USD", targetCurrencyCode: "CNY"))
        #expect(detection.actions.isEmpty)
    }

    @Test(arguments: [
        ("10英寸是多少厘米", 25.4), ("10英寸=？厘米", 25.4), ("10 in to cm?", 25.4),
        ("1公里等于多少米？", 1000), ("32华氏度换算成摄氏度", 0), ("1小时轉換成分鐘", 60),
    ])
    func parsesNaturalUnitRequests(_ query: String, result: Double) throws {
        let parsed = try #require(ClipboardAssistantDetector.parseUnitConversion(query))
        #expect(abs(parsed.result - result) < 0.000001)
        #expect(ClipboardAssistantDetector.detect(text: query, enabledKinds: Set(ClipboardAssistantKind.allCases), now: now, timeZone: utc)?.kind == .conversion)
    }

    @Test(arguments: [
        ("北京时间09:30是多少纽约时间？", "2026-09-21 21:30:00 -04:00 [America/New_York]"),
        ("2026-01-23 09:30上海=？纽约", "2026-01-22 20:30:00 -05:00 [America/New_York]"),
        ("2026-01-23T09:30:00+08:00 to UTC", "2026-01-23 01:30:00 Z [GMT]"),
        ("2026-01-23T01:30:00Z to 北京", "2026-01-23 09:30:00 +08:00 [Asia/Shanghai]"),
        ("纽约时间2026-01-23 09:30是北京时间几点？", "2026-01-23 22:30:00 +08:00 [Asia/Shanghai]"),
        ("2026-01-23T09:30:45.123Z to UTC+08:00", "2026-01-23 17:30:45.123 +08:00 [GMT+0800]"),
    ])
    func parsesNaturalTimeZoneRequests(_ query: String, expected: String) throws {
        let parsed = try #require(ClipboardAssistantDetector.parseTimeZoneConversion(query, now: now))
        #expect(parsed.targetText == expected)
        #expect(ClipboardAssistantDetector.detect(text: query, enabledKinds: Set(ClipboardAssistantKind.allCases), now: now, timeZone: utc)?.kind == .conversion)
    }

    @Test(arguments: [
        "2026-02-30", "2026-02-29 12:00", "2026-02-30T12:00:00Z", "2026-01-01T24:00:00Z",
        "23:59:60", "2026-01-01 12:99", "2026-1/23", "10-3", "09-21", "v2026.1.23",
        "2026-1-23+1", "https://example.com/2026-01-23", "13800138000", "+8613800138000",
        "SF1790035200000", "timestamp: 9999999999999", "phone: 1790035200", "运单1790035200000",
        "timestamp: 179003520000", "timestamp: -1790035200", "timestamp: 0000000000",
        "Tue, 23 Jan 2026 09:30:00 GMT", "Fri, 30 Feb 2026 09:30:00 GMT",
        "February 30, 2026", "29 February 2026", "32 Jan 2026", "23 Invalid 2026", "Jan 1, 1599",
        "1599-01-01", "0000-01-01", "2026-01-23T09:30:00+14:01", "2026-01-23T09:30:00+08:60",
    ])
    func rejectsInvalidDatesIdentifiersAndOutOfRangeEpochs(_ query: String) {
        #expect(ClipboardAssistantDetector.parseDateTime(query) == nil)
    }

    @Test(arguments: [
        ("2026.1.23", "2026-01-23 00:00", true), ("2026/1/23 9:30", "2026-01-23 09:30", false),
        ("2026-01-23T09:30:00Z", "2026-01-23 09:30", false),
        ("2026-01-23T09:30:00+08:00", "2026-01-23 01:30", false),
        ("Fri, 23 Jan 2026 09:30:00 GMT", "2026-01-23 09:30", false),
        ("Fri, 23 Jan 2026 09:30:00 +0800", "2026-01-23 01:30", false),
        ("09:30", "2026-09-22 09:30", false),
        ("timestamp: 1790035200", "2026-09-22 00:00", false),
        ("1790035200", "2026-09-22 00:00", false), ("1790035200000", "2026-09-22 00:00", false),
        ("时间戳：1790035200000", "2026-09-22 00:00", false),
        ("unix: 1790035200000000", "2026-09-22 00:00", false),
        ("unix: 1790035200000000000", "2026-09-22 00:00", false),
        ("2026-01-23T09:30:45.123Z", "2026-01-23 09:30:45.123", false),
        ("1790035200123", "2026-09-22 00:00:00.123", false),
        ("23 January 2026", "2026-01-23 00:00", true), ("Jan 23, 2026", "2026-01-23 00:00", true),
        ("2026年1月23日", "2026-01-23 00:00", true), ("23 Jan 2026 09:30:45 +0800", "2026-01-23 01:30:45", false),
    ])
    func detectsStrictDateTimesWithInjectedClock(_ query: String, expected: String, allDay: Bool) throws {
        let detection = try #require(ClipboardAssistantDetector.detect(
            text: query, enabledKinds: Set(ClipboardAssistantKind.allCases), now: now, timeZone: utc, locale: Locale(identifier: "ar")
        ))
        #expect(detection.kind == .dateTime)
        #expect(detection.actions.last == .copyText(expected))
        guard case .createCalendarEvent(_, _, let isAllDay) = detection.action else {
            Issue.record("expected calendar action for \(query)")
            return
        }
        #expect(isAllDay == allDay)
    }

    @Test(arguments: [
        "100美元==？人民币", "100美元=?人民币? trailing", "100美元=？未知币", "100美元是多少美元",
        "100美元=？人民币=", "100美元是多少人民币 and 20 EUR", "100美元是多少人民币??",
        "1,00美元是多少人民币", "100+50美元是多少人民币", "100美元?人民币",
    ])
    func rejectsMalformedCurrencyQueries(_ query: String) {
        #expect(ClipboardAssistantDetector.parseCurrencyConversion(query, preferredCurrencyCode: "CNY") == nil)
    }

    @Test
    func respectsFeatureSwitchesAndInjectedLocalDay() throws {
        let shanghai = try #require(TimeZone(identifier: "Asia/Shanghai"))
        let beforeUTCNewYear = Date(timeIntervalSince1970: 1_798_675_200 + 16 * 3600)
        let interval = try #require(ClipboardAssistantDetector.parseDateInterval(
            "01-01到01-02", now: beforeUTCNewYear, timeZone: shanghai
        ))
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = shanghai
        #expect(calendar.component(.year, from: interval.startDate) == calendar.component(.year, from: beforeUTCNewYear))
        for query in ["09-21～09-23", "100美元=？人民币", "10英寸是多少厘米", "北京时间09:30是多少纽约时间？"] {
            #expect(ClipboardAssistantDetector.detect(text: query, enabledKinds: [.conversion], preferredCurrencyCode: "CNY", now: now, timeZone: utc)?.kind == .conversion)
            #expect(ClipboardAssistantDetector.detect(text: query, enabledKinds: [.dateTime], now: now, timeZone: utc) == nil)
        }
        for query in ["1790035200", "2026-01-23T09:30:00Z", "09:30"] {
            #expect(ClipboardAssistantDetector.detect(text: query, enabledKinds: [.conversion], now: now, timeZone: utc) == nil)
            #expect(ClipboardAssistantDetector.detect(text: query, enabledKinds: [.dateTime], now: now, timeZone: utc)?.kind == .dateTime)
        }
    }

    @Test(arguments: [
        ("2026-03-08 02:30", "America/New_York"), ("2026-11-01 01:30", "America/New_York"),
        ("2026-04-05 01:45", "Australia/Lord_Howe"), ("2026-10-04 02:15", "Australia/Lord_Howe"),
    ])
    func directDateParserRejectsMissingAndRepeatedWallTimes(_ query: String, identifier: String) throws {
        let zone = try #require(TimeZone(identifier: identifier))
        #expect(ClipboardAssistantDetector.parseDateTime(query, now: now, timeZone: zone) == nil)
    }

    @Test
    func detectionPriorityKeepsIdentifiersAndCalendarDayIntervalsSeparate() throws {
        let kinds = Set(ClipboardAssistantKind.allCases)
        for query in ["1790035200", "1790035200000", "2026.1.23", "09:30"] {
            #expect(ClipboardAssistantDetector.detect(text: query, enabledKinds: kinds, now: now, timeZone: utc)?.kind == .dateTime)
        }
        for (query, kind) in [
            ("13800138000", ClipboardAssistantKind.phone), ("+8613800138000", .phone),
            ("SF1790035200000", .tracking), ("运单1790035200000", .tracking),
            ("https://example.com/2026-01-23", .url), ("example.com", .url),
            ("//example.com/path", .url),
            ("http://2026.1.23/", .url), ("https://example.com/?amount=100.5USD", .url), ("10-3", .math),
        ] {
            #expect(ClipboardAssistantDetector.detect(text: query, enabledKinds: kinds, now: now, timeZone: utc, countryCode: "CN")?.kind == kind)
        }
        #expect(ClipboardAssistantDetector.detect(text: "100.5USD", enabledKinds: kinds, preferredCurrencyCode: "CNY", now: now, timeZone: utc)?.kind == .conversion)
        let zone = try #require(TimeZone(identifier: "America/New_York"))
        let interval = try #require(ClipboardAssistantDetector.parseDateInterval("2026-03-07～2026-03-09", now: now, timeZone: zone))
        #expect(interval.days == 2)
        #expect(interval.targetDate.timeIntervalSince(interval.startDate) == 47 * 3600)
    }

    @Test
    func epochPrecisionBoundsAndLocaleRemainDeterministic() throws {
        for query in ["1790035200", "1790035200000", "1790035200000000", "1790035200000000000"] {
            let parsed = try #require(ClipboardAssistantDetector.parseDateTime(query, now: now, timeZone: utc))
            #expect(parsed.date == now)
        }
        for query in ["4102444799", "4102444799000", "1000000000"] {
            #expect(ClipboardAssistantDetector.parseDateTime(query, now: now, timeZone: utc) != nil)
        }
        for query in ["4102444800", "4102444800000", "0999999999", "17900352000000", "9999999999999999999"] {
            #expect(ClipboardAssistantDetector.parseDateTime(query, now: now, timeZone: utc) == nil)
        }
        let fraction = try #require(ClipboardAssistantDetector.parseDateTime("1790035200123", now: now, timeZone: utc))
        #expect(abs(fraction.date.timeIntervalSince(now) - 0.123) < 0.000001)
        let french = try #require(ClipboardAssistantDetector.detect(
            text: "10 in to cm?", enabledKinds: [.conversion], now: now, timeZone: utc, locale: Locale(identifier: "fr_FR")
        ))
        #expect(french.title == "25,4 cm")
        let newYear = Date(timeIntervalSince1970: 1_798_675_200 + 16 * 3600)
        let shanghai = try #require(TimeZone(identifier: "Asia/Shanghai"))
        let local = try #require(ClipboardAssistantDetector.parseDateTime("09:30", now: newYear, timeZone: shanghai))
        #expect(local.isoText == "2027-01-01 09:30")
    }

    @Test
    func boundedSeededIntervalPropertiesAndInvalidSuffixFuzz() throws {
        var seed: UInt64 = 0x5A17
        func next(_ bound: Int) -> Int {
            seed = seed &* 6_364_136_223_846_793_005 &+ 1
            return Int((seed >> 32) % UInt64(bound))
        }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = utc
        let separators = ["-", "/", "."]
        let connectors = ["～", "到", "~", "—"]
        for _ in 0..<96 {
            let year = 2000 + next(80), month = 1 + next(12), day = 1 + next(28)
            let separator = separators[next(separators.count)]
            let start = "\(year)\(separator)\(month)\(separator)\(day)"
            let end = "\(year)\(separator)\(month)\(separator)\(day + 1)"
            let query = "\(start)\(connectors[next(connectors.count)])\(end)"
            let parsed = try #require(ClipboardAssistantDetector.parseDateInterval(query, now: now, timeZone: utc))
            #expect(parsed.days == 1, "seeded interval failed: \(query)")
            #expect(calendar.component(.year, from: parsed.startDate) == year)
            let corrupt = query + ["x", "? trailing", "\u{0}", "=1"][next(4)]
            #expect(ClipboardAssistantDetector.parseDateInterval(corrupt, now: now, timeZone: utc) == nil)
            #expect(ClipboardAssistantDetector.parseCurrencyConversion("100美元=？人民币" + String(next(10)), preferredCurrencyCode: "CNY") == nil)
        }
        let oversized = String(repeating: "1", count: 201)
        #expect(ClipboardAssistantDetector.parseDateInterval(oversized, now: now, timeZone: utc) == nil)
        #expect(ClipboardAssistantDetector.parseUnitConversion(oversized) == nil)
        #expect(ClipboardAssistantDetector.parseDateTime(oversized) == nil)
    }
}
