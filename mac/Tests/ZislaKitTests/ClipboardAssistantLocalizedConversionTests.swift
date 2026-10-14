import Foundation
import Testing
import ZislaCore
@testable import ZislaKit

struct ClipboardAssistantLocalizedConversionTests {
    private let utc = TimeZone(secondsFromGMT: 0)!
    private let now = Date(timeIntervalSince1970: 1_790_035_200)

    private struct Example {
        let before: String
        let after: String
        let unit: String
        let currency: String
        let date: String
        let timestamp: String
        let dayAfterTomorrow: String
    }

    private static let examples: [AppLanguage: Example] = [
        .simplifiedChinese: Example(before: "2026.10.28往前15天", after: "2026.10.28往后15天", unit: "10英寸换算成厘米", currency: "100美元换算成欧元", date: "2026年1月23日", timestamp: "时间戳", dayAfterTomorrow: "后天"),
        .traditionalChinese: Example(before: "2026.10.28往前15天", after: "2026.10.28往後15天", unit: "10英吋換算成公分", currency: "100美元換算成歐元", date: "2026年1月23日", timestamp: "時間戳", dayAfterTomorrow: "後天"),
        .english: Example(before: "15 days before 2026.10.28", after: "15 days after 2026.10.28", unit: "10 inches to centimeters", currency: "100 US dollars to euros", date: "January 23, 2026", timestamp: "Unix timestamp", dayAfterTomorrow: "day after tomorrow"),
        .japanese: Example(before: "2026.10.28の15日前", after: "2026.10.28の15日後", unit: "10インチをセンチメートルに変換", currency: "100米ドルをユーロに変換", date: "2026年1月23日", timestamp: "Unixタイムスタンプ", dayAfterTomorrow: "明後日"),
        .korean: Example(before: "2026.10.28에서 15일 전", after: "2026.10.28에서 15일 후", unit: "10인치를 센티미터로 변환", currency: "100미국 달러를 유로로 변환", date: "2026년1월23일", timestamp: "유닉스 타임스탬프", dayAfterTomorrow: "모레"),
        .french: Example(before: "15 jours avant le 2026.10.28", after: "15 jours après le 2026.10.28", unit: "10 pouces en centimètres", currency: "100 dollars américains en euros", date: "23 janvier 2026", timestamp: "horodatage Unix", dayAfterTomorrow: "après-demain"),
        .german: Example(before: "15 Tage vor dem 2026.10.28", after: "15 Tage nach dem 2026.10.28", unit: "10 Zoll in Zentimeter", currency: "100 US-Dollar in Euro", date: "23. Januar 2026", timestamp: "Unix-Zeitstempel", dayAfterTomorrow: "übermorgen"),
        .spanish: Example(before: "15 días antes del 2026.10.28", after: "15 días después del 2026.10.28", unit: "10 pulgadas a centímetros", currency: "100 dólares estadounidenses a euros", date: "23 de enero de 2026", timestamp: "marca de tiempo Unix", dayAfterTomorrow: "pasado mañana"),
        .brazilianPortuguese: Example(before: "15 dias antes de 2026.10.28", after: "15 dias depois de 2026.10.28", unit: "10 polegadas em centímetros", currency: "100 dólares americanos para euros", date: "23 de janeiro de 2026", timestamp: "carimbo de data/hora Unix", dayAfterTomorrow: "depois de amanhã"),
        .italian: Example(before: "15 giorni prima del 2026.10.28", after: "15 giorni dopo il 2026.10.28", unit: "10 pollici in centimetri", currency: "100 dollari statunitensi in euro", date: "23 gennaio 2026", timestamp: "timestamp Unix", dayAfterTomorrow: "dopodomani"),
        .dutch: Example(before: "15 dagen voor 2026.10.28", after: "15 dagen na 2026.10.28", unit: "10 inch naar centimeter", currency: "100 Amerikaanse dollars naar euro", date: "23 januari 2026", timestamp: "Unix-tijdstempel", dayAfterTomorrow: "overmorgen"),
        .russian: Example(before: "15 дней до 2026.10.28", after: "15 дней после 2026.10.28", unit: "10 дюймов в сантиметры", currency: "100 долларов США в евро", date: "23 января 2026 г.", timestamp: "метка времени Unix", dayAfterTomorrow: "послезавтра"),
        .arabic: Example(before: "15 يومًا قبل 2026.10.28", after: "15 يومًا بعد 2026.10.28", unit: "10 بوصات إلى سنتيمتر", currency: "100 دولار أمريكي إلى يورو", date: "23 يناير 2026", timestamp: "الطابع الزمني Unix", dayAfterTomorrow: "بعد غد"),
        .thai: Example(before: "15 วันก่อน 2026.10.28", after: "15 วันหลัง 2026.10.28", unit: "10 นิ้วเป็นเซนติเมตร", currency: "100 ดอลลาร์สหรัฐเป็นยูโร", date: "23 มกราคม 2026", timestamp: "ประทับเวลา Unix", dayAfterTomorrow: "มะรืนนี้"),
        .indonesian: Example(before: "15 hari sebelum 2026.10.28", after: "15 hari setelah 2026.10.28", unit: "10 inci ke sentimeter", currency: "100 dolar Amerika Serikat ke euro", date: "23 Januari 2026", timestamp: "stempel waktu Unix", dayAfterTomorrow: "lusa"),
        .vietnamese: Example(before: "15 ngày trước 2026.10.28", after: "15 ngày sau 2026.10.28", unit: "10 inch sang xentimét", currency: "100 đô la Mỹ sang euro", date: "23 tháng 1 2026", timestamp: "dấu thời gian Unix", dayAfterTomorrow: "ngày kia"),
        .turkish: Example(before: "2026.10.28'den 15 gün önce", after: "2026.10.28'den 15 gün sonra", unit: "10 inç santimetreye çevir", currency: "100 ABD doları Euro'ya çevir", date: "23 Ocak 2026", timestamp: "Unix zaman damgası", dayAfterTomorrow: "öbür gün"),
    ]

    private static let offsetQuestions: [AppLanguage: String] = [
        .simplifiedChinese: "2026.10.28往前15天是哪天？",
        .traditionalChinese: "2026.10.28往前15天是哪一天？",
        .english: "what date is 15 days before 2026.10.28?",
        .japanese: "2026.10.28の15日前は何日ですか？",
        .korean: "2026.10.28에서 15일 전은 언제인가요?",
        .french: "quelle est la date 15 jours avant le 2026.10.28 ?",
        .german: "welches Datum liegt 15 Tage vor dem 2026.10.28?",
        .spanish: "¿qué fecha es 15 días antes del 2026.10.28?",
        .brazilianPortuguese: "qual é a data 15 dias antes de 2026.10.28?",
        .italian: "qual è la data 15 giorni prima del 2026.10.28?",
        .dutch: "welke datum is 15 dagen voor 2026.10.28?",
        .russian: "какая дата будет за 15 дней до 2026.10.28?",
        .arabic: "ما هو التاريخ قبل 2026.10.28 بـ15 يومًا؟",
        .thai: "15 วันก่อน 2026.10.28 เป็นวันที่เท่าไหร่?",
        .indonesian: "tanggal berapa 15 hari sebelum 2026.10.28?",
        .vietnamese: "15 ngày trước 2026.10.28 là ngày nào?",
        .turkish: "2026.10.28'den 15 gün önce hangi tarih olur?",
    ]

    private static let offsetVerbs: [AppLanguage: (addition: String, subtraction: String)] = [
        .simplifiedChinese: ("2026.10.28加15天", "2026.10.28减15天"),
        .traditionalChinese: ("2026.10.28加15天", "2026.10.28減15天"),
        .english: ("2026.10.28 add 15days", "2026.10.28 subtract 15days"),
        .japanese: ("2026.10.28に15日を加える", "2026.10.28から15日を引く"),
        .korean: ("2026.10.28에 15일을 더하기", "2026.10.28에서 15일을 빼기"),
        .french: ("2026.10.28 ajouter 15 jours", "2026.10.28 soustraire 15 jours"),
        .german: ("2026.10.28 addieren 15 Tage", "2026.10.28 subtrahieren 15 Tage"),
        .spanish: ("2026.10.28 sumar 15 días", "2026.10.28 restar 15 días"),
        .brazilianPortuguese: ("2026.10.28 adicionar 15 dias", "2026.10.28 subtrair 15 dias"),
        .italian: ("2026.10.28 aggiungere 15 giorni", "2026.10.28 sottrarre 15 giorni"),
        .dutch: ("2026.10.28 15 dagen optellen", "2026.10.28 15 dagen aftrekken"),
        .russian: ("2026.10.28 добавить 15 дней", "2026.10.28 вычесть 15 дней"),
        .arabic: ("2026.10.28 أضف 15 يومًا", "2026.10.28 اطرح 15 يومًا"),
        .thai: ("2026.10.28เพิ่ม15วัน", "2026.10.28ลบ15วัน"),
        .indonesian: ("2026.10.28 tambah 15 hari", "2026.10.28 kurangi 15 hari"),
        .vietnamese: ("2026.10.28 cộng 15 ngày", "2026.10.28 trừ 15 ngày"),
        .turkish: ("2026.10.28 15 gün ekle", "2026.10.28 15 gün çıkar"),
    ]

    private static let clocks: [AppLanguage: (morning: String, afternoon: String, now: String)] = [
        .simplifiedChinese: ("上午03:15", "下午03:15", "现在"),
        .traditionalChinese: ("上午03:15", "下午03:15", "現在"),
        .english: ("03:15 am", "03:15 pm", "now"),
        .japanese: ("午前03:15", "午後03:15", "今"),
        .korean: ("오전 03:15", "오후 03:15", "지금"),
        .french: ("03:15 du matin", "03:15 de l'après-midi", "maintenant"),
        .german: ("03:15 vormittags", "03:15 nachmittags", "jetzt"),
        .spanish: ("03:15 de la mañana", "03:15 de la tarde", "ahora"),
        .brazilianPortuguese: ("03:15 da manhã", "03:15 da tarde", "agora"),
        .italian: ("03:15 di mattina", "03:15 del pomeriggio", "adesso"),
        .dutch: ("03:15 's ochtends", "03:15 's middags", "nu"),
        .russian: ("03:15 утра", "03:15 дня", "сейчас"),
        .arabic: ("03:15 صباحًا", "03:15 مساءً", "الآن"),
        .thai: ("03:15 เช้า", "บ่าย03:15", "ตอนนี้"),
        .indonesian: ("03:15 pagi", "03:15 sore", "sekarang"),
        .vietnamese: ("03:15 sáng", "03:15 chiều", "bây giờ"),
        .turkish: ("03:15 sabah", "03:15 öğleden sonra", "şimdi"),
    ]

    @Test(arguments: AppLanguage.allCases)
    func localizedDateOffsetsPreserveBothDirectionsRegardlessOfInterfaceLanguage(language: AppLanguage) throws {
        let example = try #require(Self.examples[language])
        for (query, expected, days) in [(example.before, "2026-10-13", -15), (example.after, "2026-11-12", 15)] {
            let parsed = try #require(ClipboardAssistantDetector.parseDateOffset(query, now: now, timeZone: utc), "date offset failed for \(language.rawValue): \(query)")
            #expect(parsed.days == days)
            let detection = try #require(ClipboardAssistantDetector.detect(
                text: query, enabledKinds: [.dateTime], now: now, timeZone: utc,
                locale: language == .english ? Locale(identifier: "ja") : Locale(identifier: "en")
            ))
            #expect(detection.kind == .dateTime)
            #expect(detection.actions.first == .copyText(expected))
            #expect(ClipboardAssistantDetector.detect(text: query, enabledKinds: [.conversion], now: now, timeZone: utc) == nil)
            #expect(ClipboardAssistantDetector.parseDateOffset(query + "=?", now: now, timeZone: utc)?.days == days)
        }
        let question = try #require(Self.offsetQuestions[language])
        #expect(ClipboardAssistantDetector.detect(text: question, enabledKinds: [.dateTime], now: now, timeZone: utc)?.action == .copyText("2026-10-13"))
    }

    @Test(arguments: [
        ("2026.10.28 add 15days", "2026-11-12", 15),
        ("2026.10.28 subtract 15days", "2026-10-13", -15),
        ("2026.10.28 ADD 15DAYS=?", "2026-11-12", 15),
        ("2026.10.28 SUBTRACT 15DAYS=？", "2026-10-13", -15),
        ("what date is 2026.10.28 add 15days?", "2026-11-12", 15),
        ("what date is 2026.10.28 subtract 15days?", "2026-10-13", -15),
        ("2026.10.28 15days add", "2026-11-12", 15),
        ("2026.10.28 15days subtract", "2026-10-13", -15),
        ("2024.02.28 add 1day", "2024-02-29", 1),
        ("2026.10.28 subtract 0days", "2026-10-28", 0),
    ])
    func dateOffsetAddSubtractVerbsRecognizeCompactDaysAndExactResults(_ query: String, expected: String, days: Int) throws {
        let offset = try #require(ClipboardAssistantDetector.parseDateOffset(query, now: now, timeZone: utc), "date verb failed: \(query)")
        #expect(offset.days == days)
        let detection = try #require(ClipboardAssistantDetector.detect(
            text: query, enabledKinds: [.dateTime], now: now, timeZone: utc, locale: Locale(identifier: "en")
        ))
        #expect(detection.actions.first == .copyText(expected))
        #expect(detection.kind == .dateTime)
    }

    @Test(arguments: [
        ("2026.10.28 sub 15days", "2026-10-13", -15),
        ("2026.10.28 SUB 15 DAYS=?", "2026-10-13", -15),
        ("what date is 2026.10.28 sub 15days?", "2026-10-13", -15),
        ("2026.10.28 sub 15", "2026-10-13", -15),
        ("2026.10.28 15days sub", "2026-10-13", -15),
        ("2026.10.28 sub15d", "2026-10-13", -15),
        ("2026.10.28 add15d", "2026-11-12", 15),
        ("2026.10.28-15d", "2026-10-13", -15),
        ("2026.10.28+15D", "2026-11-12", 15),
        ("15d before 2026.10.28", "2026-10-13", -15),
        ("15d after 2026.10.28", "2026-11-12", 15),
        ("2024.03.01 sub 1d", "2024-02-29", -1),
        ("2026.10.28 sub 0d", "2026-10-28", 0),
    ])
    func dateOffsetAbbreviationsKeepDirectionsAndCopyResultsAcrossInterfaceLanguages(_ query: String, expected: String, days: Int) throws {
        for language in AppLanguage.allCases {
            let detection = try #require(ClipboardAssistantDetector.detect(
                text: query, enabledKinds: [.dateTime], now: now, timeZone: utc, locale: language.locale
            ), "date abbreviation failed for \(language.rawValue): \(query)")
            #expect(detection.kind == .dateTime)
            #expect(detection.action == .copyText(expected))
            let amount = AppLocalization.format("%@ 天", locale: language.locale, [String(abs(days))])
            let start = query.contains("2024") ? "2024-03-01" : "2026-10-28"
            #expect(detection.actions.last == .copyFullExpression("\(start) \(days < 0 ? "-" : "+") \(amount) = \(expected)"))
            #expect(ClipboardAssistantDetector.detect(text: query, enabledKinds: [.conversion], now: now, timeZone: utc) == nil)
        }
    }

    @Test(arguments: [
        "2026.10.28 submarine 15days", "2026.10.28 subtraction 15d", "2026.10.28 subbing 15d",
        "2026.10.28 add 15dollars", "2026.10.28 sub 15dayss", "2026.10.28 sub 15d trailing",
        "2026.10.28 sub -15d", "2026.10.28 sub +15d", "2026.10.28 sub add 15d",
        "2026.10.28 sub 15d after", "2026.10.28 sub 1.5d", "2026.10.28 sub 15d==?",
        "2026.10.28 sub 15d\u{0}", "2026.10.28 sub 15d\u{202E}",
    ])
    func dateOffsetAbbreviationsRejectPrefixCollisionsAndMalformedRequests(_ query: String) {
        #expect(ClipboardAssistantDetector.detect(text: query, enabledKinds: [.dateTime], now: now, timeZone: utc) == nil)
    }

    @Test(arguments: AppLanguage.allCases)
    func localizedDateOffsetAdditionAndSubtractionVerbsKeepExplicitDirections(language: AppLanguage) throws {
        let verbs = try #require(Self.offsetVerbs[language])
        for (query, expected, days) in [(verbs.addition, "2026-11-12", 15), (verbs.subtraction, "2026-10-13", -15)] {
            let offset = try #require(ClipboardAssistantDetector.parseDateOffset(query, now: now, timeZone: utc), "date verb failed for \(language.rawValue): \(query)")
            #expect(offset.days == days)
            let detection = try #require(ClipboardAssistantDetector.detect(
                text: query + "=?", enabledKinds: [.dateTime], now: now, timeZone: utc, locale: Locale(identifier: "en")
            ))
            #expect(detection.actions.first == .copyText(expected))
            #expect(detection.kind == .dateTime)
            #expect(ClipboardAssistantDetector.detect(text: query, enabledKinds: [.conversion], now: now, timeZone: utc) == nil)
            #expect(ClipboardAssistantDetector.parseDateOffset(query.replacingOccurrences(of: "15", with: "-15"), now: now, timeZone: utc) == nil)
            #expect(ClipboardAssistantDetector.parseDateOffset(query + " add subtract", now: now, timeZone: utc) == nil)
        }
    }

    @Test(arguments: [
        "2026.10.28 add -15days", "2026.10.28 subtract -15days", "2026.10.28 add +15days",
        "2026.10.28 add subtract 15days", "2026.10.28 subtract add 15days",
        "2026.10.28 add 15days before", "2026.10.28 subtract 15days after",
        "2026.10.28 before 15days add", "2026.10.28 after 15days subtract",
        "2026.10.28 add 15days trailing", "2026.10.28 add 15days==?", "2026.10.28 add 15days=1",
        "2026.10.28 add 15months", "2026.10.28 add 1.5days", "2026.10.28 addition 15days",
        "2026.10.28 subtracting 15days", "2026.10.28 add 9223372036854775807days",
        "2026.10.28 add 15days\u{0}", "2026.10.28 subtract 15days\u{202E}",
    ])
    func dateOffsetAddSubtractVerbsRejectSignedAmountsAndMixedDirections(_ query: String) {
        #expect(ClipboardAssistantDetector.parseDateOffset(query, now: now, timeZone: utc) == nil)
        #expect(ClipboardAssistantDetector.detect(text: query, enabledKinds: [.dateTime], now: now, timeZone: utc) == nil)
    }

    @Test(arguments: AppLanguage.allCases)
    func localizedUnitAndCurrencyNamesComposeWithNativeConnectors(language: AppLanguage) throws {
        let example = try #require(Self.examples[language])
        let unit = try #require(ClipboardAssistantDetector.parseUnitConversion(example.unit), "unit conversion failed for \(language.rawValue): \(example.unit)")
        #expect(abs(unit.result - 25.4) < 0.000001)
        #expect(unit.sourceUnit == "in")
        #expect(unit.targetUnit == "cm")
        let detectedUnit = try #require(ClipboardAssistantDetector.detect(text: example.unit, enabledKinds: [.conversion], locale: Locale(identifier: "en")))
        #expect(detectedUnit.actions.first == .copyText("25.4 cm"))
        let currency = try #require(ClipboardAssistantDetector.parseCurrencyConversion(example.currency, preferredCurrencyCode: "CNY"), "currency conversion failed for \(language.rawValue): \(example.currency)")
        #expect(currency.amount == 100)
        #expect(currency.sourceCurrencyCode == "USD")
        #expect(currency.targetCurrencyCode == "EUR")
        #expect(ClipboardAssistantDetector.detect(text: example.currency, enabledKinds: [.conversion], preferredCurrencyCode: "CNY", locale: Locale(identifier: "en"))?.detail == .currencyExpression(amount: 100, amountText: "100", sourceCurrencyCode: "USD", targetCurrencyCode: "EUR"))
        #expect(ClipboardAssistantDetector.detect(text: example.unit, enabledKinds: [], locale: Locale(identifier: "en")) == nil)
        #expect(ClipboardAssistantDetector.detect(text: example.currency, enabledKinds: [], locale: Locale(identifier: "en")) == nil)
        for suffix in ["=?", "=？", " = ؟", " = \t ? "] {
            let suffixedUnit = try #require(ClipboardAssistantDetector.parseUnitConversion(example.unit + suffix))
            #expect(abs(suffixedUnit.result - 25.4) < 0.000001)
            #expect(suffixedUnit.targetUnit == "cm")
            let suffixedCurrency = try #require(ClipboardAssistantDetector.parseCurrencyConversion(example.currency + suffix, preferredCurrencyCode: "CNY"))
            #expect(suffixedCurrency.sourceCurrencyCode == "USD")
            #expect(suffixedCurrency.targetCurrencyCode == "EUR")
        }
    }

    @Test(arguments: AppLanguage.allCases)
    func localizedMonthNamesUnixLabelsAndRelativeDatesRemainGregorian(language: AppLanguage) throws {
        let example = try #require(Self.examples[language])
        let date = try #require(ClipboardAssistantDetector.parseDateTime(example.date, now: now, timeZone: utc), "named date failed for \(language.rawValue)")
        #expect(date.isoText == "2026-01-23 00:00")
        #expect(date.isDateOnly)
        let timestamp = try #require(ClipboardAssistantDetector.parseDateTime("\(example.timestamp): 1790035200", now: now, timeZone: utc), "timestamp label failed for \(language.rawValue)")
        #expect(timestamp.date == now)
        #expect(!timestamp.isDateOnly)
        let interval = try #require(ClipboardAssistantDetector.parseDateInterval("2026-09-22～\(example.dayAfterTomorrow)", now: now, timeZone: utc))
        #expect(interval.days == 2)
    }

    @Test(arguments: AppLanguage.allCases)
    func localizedClockPeriodsPreserveDatesAndTimeZoneCalculations(language: AppLanguage) throws {
        let example = try #require(Self.clocks[language])
        for (clock, localHour, convertedHour) in [(example.morning, "03", "11"), (example.afternoon, "15", "23")] {
            let bare = try #require(ClipboardAssistantDetector.parseDateTime(clock, now: now, timeZone: utc), "bare localized clock failed for \(language.rawValue): \(clock)")
            #expect(bare.isoText == "2026-09-22 \(localHour):15")
            #expect(!bare.isDateOnly)
            let dated = try #require(ClipboardAssistantDetector.parseDateTime("2026-10-28 \(clock)", now: now, timeZone: utc))
            #expect(dated.isoText == "2026-10-28 \(localHour):15")
            let converted = try #require(ClipboardAssistantDetector.parseTimeZoneConversion("2026-10-28 \(clock) UTC to UTC+08:00", now: now))
            #expect(converted.targetText == "2026-10-28 \(convertedHour):15:00 +08:00 [GMT+0800]")
            #expect(ClipboardAssistantDetector.parseTimeZoneConversion("2026-10-28 \(clock) UTC to UTC+08:00 = ؟", now: now)?.targetText == converted.targetText)
            #expect(ClipboardAssistantDetector.detect(text: clock, enabledKinds: [.dateTime], now: now, timeZone: utc, locale: Locale(identifier: "en"))?.kind == .dateTime)
        }
        let current = try #require(ClipboardAssistantDetector.parseTimeZoneConversion("\(example.now) UTC to UTC+08:00", now: now))
        #expect(current.targetText == "2026-09-22 08:00:00 +08:00 [GMT+0800]")
    }

    @Test(arguments: [
        "morning 03:15 pm", "午後03:15 am", "오전03:15 오후", "sabah 03:15 öğleden sonra",
        "de la mañana 03:15 de la tarde", "13:15 de l'après-midi", "00:15 am",
        "03:15 de la tarde du matin", "03:15 vormittags trailing",
    ])
    func localizedClocksRejectConflictingPeriodsAndInvalidHours(_ query: String) {
        #expect(ClipboardAssistantDetector.parseDateTime(query, now: now, timeZone: utc) == nil)
        #expect(ClipboardAssistantDetector.parseTimeZoneConversion("\(query) UTC to UTC+08:00", now: now) == nil)
    }

    @Test
    func localizedClocksKeepSecondsFractionsNoonMidnightAndDSTRejections() throws {
        let precise = try #require(ClipboardAssistantDetector.parseTimeZoneConversion("2026-10-28 03:15:30.25 de l'après-midi UTC to UTC+08:00", now: now))
        #expect(precise.targetText == "2026-10-28 23:15:30.250 +08:00 [GMT+0800]")
        #expect(ClipboardAssistantDetector.parseDateTime("12:00 du matin", now: now, timeZone: utc)?.isoText == "2026-09-22 00:00")
        #expect(ClipboardAssistantDetector.parseDateTime("12:00 de l'après-midi", now: now, timeZone: utc)?.isoText == "2026-09-22 12:00")
        for query in [
            "2026-11-01 01:30 утра America/New_York to UTC",
            "2026-03-08 morning 02:30 America/New_York to UTC",
            "2026-04-05 오전 01:45 Australia/Lord_Howe to UTC",
        ] {
            #expect(ClipboardAssistantDetector.parseTimeZoneConversion(query, now: now) == nil)
        }
    }

    @Test(arguments: [
        ("waktu Beijing", "waktu New York", "Asia/Shanghai", "America/New_York"),
        ("waktu Shanghai", "waktu London", "Asia/Shanghai", "Europe/London"),
        ("waktu Tokyo", "UTC", "Asia/Tokyo", "GMT"),
    ])
    func nativeIndonesianCityPhrasesResolveAsWholeTimeZones(_ source: String, target: String, sourceID: String, targetID: String) throws {
        let conversion = try #require(ClipboardAssistantDetector.parseTimeZoneConversion("2026-01-01 12:00 \(source) ke \(target)", now: now))
        #expect(conversion.sourceText.hasSuffix("[\(sourceID)]"))
        #expect(conversion.targetText.hasSuffix("[\(targetID)]"))
    }

    @Test(arguments: [
        ("2026.10.28 earlier 15 days", -15), ("2026.10.28 later 15 days", 15),
        ("15 days earlier than 2026.10.28", -15), ("15 days later than 2026.10.28", 15),
        ("2026.10.28 15 days earlier?", -15), ("2026.10.28 15 days later=?", 15),
        ("2026.10.28-15 jours?", -15), ("2026.10.28+15 jours?", 15),
        ("2026.10.28 15日前", -15), ("2026.10.28 15日後", 15),
        ("2026년10월28일에서 15일 전", -15), ("2026년10월28일에서 15일 후", 15),
        ("2026.10.28 15 Tage früher", -15), ("2026.10.28 15 Tage später", 15),
        ("2026.10.28 15 giorni prima", -15), ("2026.10.28 15 giorni dopo", 15),
        ("2026.10.28 15 jours plus tôt", -15), ("2026.10.28 15 jours plus tard", 15),
        ("2026.10.28 15 días antes", -15), ("2026.10.28 15 días después", 15),
        ("2026.10.28 15 dias antes", -15), ("2026.10.28 15 dias depois", 15),
        ("2026.10.28 15 дней раньше", -15), ("2026.10.28 15 дней позже", 15),
        ("2026.10.28 15 hari sebelumnya", -15), ("2026.10.28 15 hari setelahnya", 15),
        ("2026.10.28 sebelum 15 hari", -15), ("2026.10.28 setelah 15 hari", 15),
        ("2026.10.28 trước 15 ngày", -15), ("2026.10.28 sau 15 ngày", 15),
        ("2026.10.28 قبل 15 يومًا؟", -15), ("2026.10.28 بعد 15 يومًا؟", 15),
        ("قبل 2026.10.28 بـ15 يومًا", -15), ("بعد 2026.10.28 بـ15 يومًا", 15),
    ])
    func localizedOffsetWordOrdersUseAnExplicitDirection(_ query: String, days: Int) throws {
        #expect(try #require(ClipboardAssistantDetector.parseDateOffset(query, now: now, timeZone: utc)).days == days)
    }

    @Test(arguments: [
        "15 days before after 2026.10.28", "2026.10.28 before -15 days", "2026.10.28 after -15 days",
        "2026.10.28 15 days before after", "2026.10.28 forwardish 15 days", "15 jours avant 2026.10.28 trailing",
        "2026.10.28+15 days==?", "2026.10.28+15 days??", "15 months before 2026.10.28",
        "15 days before 2026.02.29", "1 day before 1600.01.01", "1 day after 9999.12.31",
        "9223372036854775807 days before 2026.10.28", "999999999999999999999999 days after 2026.10.28",
        "15日後2026.10.28\u{0}", "2026.10.28ก่อน15วัน\u{202E}",
    ])
    func localizedOffsetGrammarRejectsMixedDirectionsAndWholeInputViolations(_ query: String) {
        #expect(ClipboardAssistantDetector.parseDateOffset(query, now: now, timeZone: utc) == nil)
        #expect(ClipboardAssistantDetector.detect(text: query, enabledKinds: [.dateTime], now: now, timeZone: utc) == nil)
    }

    @Test(arguments: [
        "10 pouces en kilogrammes", "10インチをキログラムに変換", "10인치를 킬로그램으로 변환",
        "10 inç kilograma çevir", "10 นิ้วเป็นกิโลกรัม", "10 pouces en centimètres et plus",
        "10インチをセンチメートルに変換==", "10인치를 센티미터로 변환 trailing",
        "100 dollars américains en euros et plus", "100 دولار أمريكي إلى يورو=1", "100 ABD doları Euro'ya çevir trailing",
        "100米ドルをに変換", "100미국 달러를로 변환",
        "10 pouces en centimètres==?", "10インチをセンチメートルに変換=1",
        "100 dollars américains en euros==؟", "100미국 달러를 유로로 변환=1",
    ])
    func localizedConversionsRejectDimensionMismatchAndAppendedProse(_ query: String) {
        #expect(ClipboardAssistantDetector.parseUnitConversion(query) == nil)
        #expect(ClipboardAssistantDetector.parseCurrencyConversion(query, preferredCurrencyCode: "CNY") == nil)
    }

    @Test(arguments: [
        ("2 mètres en centimètres", 200.0), ("2 метра в сантиметры", 200.0), ("1 метр в сантиметры", 100.0),
        ("5 метров в сантиметры", 500.0), ("2 小時換算成分鐘", 120.0),
        ("2 Stunden in Minuten", 120.0), ("2 килограмма в граммы", 2000.0),
        ("2 ลิตรเป็นมิลลิลิตร", 2000.0), ("32 華氏度換算成攝氏度", 0.0),
        ("32華氏度を摂氏度に変換", 0.0),
    ])
    func nativeUnitInflectionsAndOtherDimensionsRemainCompatible(_ query: String, expected: Double) throws {
        let conversion = try #require(ClipboardAssistantDetector.parseUnitConversion(query))
        #expect(abs(conversion.result - expected) < 0.000001)
    }

    @Test(arguments: [
        ("10 метров в секунду в километры в час", "m/s", "km/h", 36.0),
        ("36 километров в час в метры в секунду", "km/h", "m/s", 10.0),
    ])
    func nativeRateNamesDoNotSplitAtInternalConnectors(_ query: String, source: String, target: String, expected: Double) throws {
        for suffix in ["", "?", "=?"] {
            let conversion = try #require(ClipboardAssistantDetector.parseUnitConversion(query + suffix), "rate conversion failed: \(query + suffix)")
            #expect(conversion.sourceUnit == source)
            #expect(conversion.targetUnit == target)
            #expect(abs(conversion.result - expected) < 0.0001)
        }
    }

    @Test
    func localizedCurrencyNamesSupportOtherCurrenciesWithoutChangingSymbolAmbiguity() throws {
        let conversion = try #require(ClipboardAssistantDetector.parseCurrencyConversion("100 Schweizer Franken in Euro", preferredCurrencyCode: "CNY"))
        #expect(conversion.sourceCurrencyCode == "CHF")
        #expect(conversion.targetCurrencyCode == "EUR")
        #expect(ClipboardAssistantDetector.parseCurrencyConversion("100 dollars to euros", preferredCurrencyCode: "CAD")?.sourceCurrencyCode == "CAD")
        #expect(ClipboardAssistantDetector.parseCurrencyConversion("100美元换算成美元", preferredCurrencyCode: "CNY") == nil)
        for (query, source, target) in [
            ("100塊換算成歐元", "CNY", "EUR"), ("100圓換算成英鎊", "CNY", "GBP"),
            ("100韓元換算成港幣", "KRW", "HKD"), ("100台幣換算成盧布", "TWD", "RUB"),
            ("100泰銖換算成盧比", "THB", "INR"), ("100 دولارات أمريكية إلى يورو", "USD", "EUR"),
        ] {
            let localized = try #require(ClipboardAssistantDetector.parseCurrencyConversion(query, preferredCurrencyCode: "CNY"))
            #expect(localized.sourceCurrencyCode == source)
            #expect(localized.targetCurrencyCode == target)
        }
    }

    @Test
    func terminalCurrencyQuestionsKeepDefaultAndExplicitTargets() throws {
        for query in ["100美元=？", "100 USD = ?", "100 US dollars = ؟"] {
            let conversion = try #require(ClipboardAssistantDetector.parseCurrencyConversion(query, preferredCurrencyCode: "CNY"))
            #expect(conversion.sourceCurrencyCode == "USD")
            #expect(conversion.targetCurrencyCode == nil)
        }
        for query in ["100美元=？欧元", "100 USD = ? EUR", "100 US dollars = ؟ EUR"] {
            let conversion = try #require(ClipboardAssistantDetector.parseCurrencyConversion(query, preferredCurrencyCode: "CNY"))
            #expect(conversion.sourceCurrencyCode == "USD")
            #expect(conversion.targetCurrencyCode == "EUR")
        }
    }

    @Test
    func localizedGrammarKeepsInputBudgetsAndSeededInverseProperties() throws {
        let short = "15 days before 2026.10.28"
        let bounded = "15 days" + String(repeating: " ", count: 200 - short.count + 1) + "before 2026.10.28"
        #expect(bounded.count == 200)
        #expect(ClipboardAssistantDetector.parseDateOffset(bounded, now: now, timeZone: utc)?.days == -15)
        #expect(ClipboardAssistantDetector.parseDateOffset(bounded + " ", now: now, timeZone: utc) == nil)
        #expect(ClipboardAssistantDetector.parseUnitConversion("10 pouces" + String(repeating: " ", count: 201) + "en centimètres") == nil)
        #expect(ClipboardAssistantDetector.parseCurrencyConversion("100 dollars" + String(repeating: " ", count: 201) + "en euros", preferredCurrencyCode: "CNY") == nil)
        #expect(ClipboardAssistantDetector.parseDateTime("horodatage:" + String(repeating: " ", count: 201) + "1790035200", now: now, timeZone: utc) == nil)
        #expect(ClipboardAssistantDetector.parseDateTime("31 février 2026", now: now, timeZone: utc) == nil)
        #expect(ClipboardAssistantDetector.parseDateTime("23 janvier 2026 trailing", now: now, timeZone: utc) == nil)
        #expect(ClipboardAssistantDetector.parseDateTime("horodatage: 1790035200 trailing", now: now, timeZone: utc) == nil)
        #expect(ClipboardAssistantDetector.parseDateTime("Sep 23, 2026", now: now, timeZone: utc)?.isoText == "2026-09-23 00:00")
        #expect(ClipboardAssistantDetector.parseDateTime("23 Sep 2026", now: now, timeZone: utc)?.isoText == "2026-09-23 00:00")

        var seed: UInt64 = 0x10CA1
        for _ in 0..<24 {
            seed = seed &* 6_364_136_223_846_793_005 &+ 1
            let days = Int((seed >> 32) % 366)
            let before = try #require(ClipboardAssistantDetector.parseDateOffset("\(days) days before 2026.10.28", now: now, timeZone: utc))
            let after = try #require(ClipboardAssistantDetector.parseDateOffset("2026.10.28 \(days)日前", now: now, timeZone: utc))
            #expect(before.targetDate == after.targetDate)
            #expect(before.startDate.timeIntervalSince(before.targetDate) == Double(days) * 86_400)
            #expect(ClipboardAssistantDetector.parseDateOffset("\(days) days before 2026.10.28=1", now: now, timeZone: utc) == nil)
        }
    }
}
