import Foundation
import Testing
import ZislaCore
@testable import ZislaKit

extension ClipboardAssistantSmartActionsTests {
    struct LocalizedSample: Sendable {
        let language: AppLanguage
        let meeting: String
        let labels: (title: String, date: String, location: String, address: String)
        let relativeDates: (today: String, tomorrow: String, yesterday: String, afterTomorrow: String)
        let periods: (morning: String, afternoon: String)
        let range: String
        let zone: String
        let rejected: [String]
        let negated: String
    }

    static let localizedSamples: [LocalizedSample] = [
        .init(language: .simplifiedChinese, meeting: "产品会议", labels: ("主题", "时间", "地点", "收货地址"), relativeDates: ("今天", "明天", "昨天", "后天"), periods: ("上午", "下午"), range: "至", zone: "北京时间", rejected: ["取消", "改期", "待定"], negated: "没有会议"),
        .init(language: .traditionalChinese, meeting: "產品會議", labels: ("主題", "時間", "地點", "收貨地址"), relativeDates: ("今天", "明天", "昨天", "後天"), periods: ("上午", "下午"), range: "到", zone: "北京時間", rejected: ["取消", "改期", "暫定"], negated: "沒有會議"),
        .init(language: .english, meeting: "Team meeting", labels: ("Subject", "Date", "Location", "Address"), relativeDates: ("today", "tomorrow", "yesterday", "day after tomorrow"), periods: ("morning", "afternoon"), range: "to", zone: "Beijing time", rejected: ["cancelled", "rescheduled", "tentative"], negated: "No meeting"),
        .init(language: .japanese, meeting: "会議", labels: ("件名", "日時", "場所", "住所"), relativeDates: ("今日", "明日", "昨日", "明後日"), periods: ("午前", "午後"), range: "〜", zone: "ペキン", rejected: ["中止", "延期", "未定"], negated: "会議なし"),
        .init(language: .korean, meeting: "회의", labels: ("제목", "일시", "장소", "주소"), relativeDates: ("오늘", "내일", "어제", "모레"), periods: ("오전", "오후"), range: "~", zone: "베이징 시간", rejected: ["취소", "연기", "미정"], negated: "회의 없음"),
        .init(language: .french, meeting: "Réunion", labels: ("Objet", "Date", "Lieu", "Adresse"), relativeDates: ("aujourd’hui", "demain", "hier", "après-demain"), periods: ("du matin", "de l’après-midi"), range: "à", zone: "heure de pékin", rejected: ["annulée", "reportée", "provisoire"], negated: "Pas de réunion"),
        .init(language: .german, meeting: "Besprechung", labels: ("Betreff", "Datum", "Ort", "Adresse"), relativeDates: ("heute", "morgen", "gestern", "übermorgen"), periods: ("vormittags", "nachmittags"), range: "bis", zone: "Peking", rejected: ["abgesagt", "verschoben", "vorläufig"], negated: "Keine Besprechung"),
        .init(language: .spanish, meeting: "Reunión", labels: ("Asunto", "Fecha", "Lugar", "Dirección"), relativeDates: ("hoy", "mañana", "ayer", "pasado mañana"), periods: ("de la mañana", "de la tarde"), range: "a", zone: "hora de pekín", rejected: ["cancelada", "aplazada", "por confirmar"], negated: "No hay reunión"),
        .init(language: .brazilianPortuguese, meeting: "Reunião", labels: ("Assunto", "Data", "Local", "Endereço"), relativeDates: ("hoje", "amanhã", "ontem", "depois de amanhã"), periods: ("da manhã", "da tarde"), range: "até", zone: "horário de pequim", rejected: ["cancelada", "adiada", "a confirmar"], negated: "Sem reunião"),
        .init(language: .italian, meeting: "Riunione", labels: ("Oggetto", "Data", "Luogo", "Indirizzo"), relativeDates: ("oggi", "domani", "ieri", "dopodomani"), periods: ("di mattina", "del pomeriggio"), range: "alle", zone: "ora di pechino", rejected: ["annullata", "rinviata", "provvisoria"], negated: "Nessuna riunione"),
        .init(language: .dutch, meeting: "Vergadering", labels: ("Onderwerp", "Datum", "Locatie", "Adres"), relativeDates: ("vandaag", "morgen", "gisteren", "overmorgen"), periods: ("’s ochtends", "’s middags"), range: "tot", zone: "tijd van peking", rejected: ["geannuleerd", "uitgesteld", "voorlopig"], negated: "Geen vergadering"),
        .init(language: .russian, meeting: "Совещание", labels: ("Тема", "Дата", "Место", "Адрес"), relativeDates: ("сегодня", "завтра", "вчера", "послезавтра"), periods: ("утра", "дня"), range: "до", zone: "время пекина", rejected: ["отменено", "перенесено", "предварительно"], negated: "Нет совещания"),
        .init(language: .arabic, meeting: "اجتماع", labels: ("الموضوع", "التاريخ", "المكان", "العنوان"), relativeDates: ("اليوم", "غدًا", "أمس", "بعد غد"), periods: ("صباحًا", "مساءً"), range: "إلى", zone: "توقيت بكين", rejected: ["ملغى", "مؤجل", "غير مؤكد"], negated: "لا اجتماع"),
        .init(language: .thai, meeting: "ประชุม", labels: ("หัวข้อ", "วันที่", "สถานที่", "ที่อยู่"), relativeDates: ("วันนี้", "พรุ่งนี้", "เมื่อวาน", "มะรืนนี้"), periods: ("เช้า", "บ่าย"), range: "ถึง", zone: "เวลาปักกิ่ง", rejected: ["ยกเลิก", "เลื่อน", "ยังไม่กำหนด"], negated: "ไม่มีประชุม"),
        .init(language: .indonesian, meeting: "Rapat", labels: ("Judul", "Tanggal", "Lokasi", "Alamat"), relativeDates: ("hari ini", "besok", "kemarin", "lusa"), periods: ("pagi", "sore"), range: "sampai", zone: "waktu beijing", rejected: ["dibatalkan", "ditunda", "tentatif"], negated: "Tidak ada rapat"),
        .init(language: .vietnamese, meeting: "Cuộc họp", labels: ("Chủ đề", "Ngày", "Địa điểm", "Địa chỉ"), relativeDates: ("hôm nay", "ngày mai", "hôm qua", "ngày kia"), periods: ("sáng", "chiều"), range: "đến", zone: "giờ bắc kinh", rejected: ["hủy", "hoãn", "chưa xác định"], negated: "Không có cuộc họp"),
        .init(language: .turkish, meeting: "Toplantı", labels: ("Konu", "Tarih", "Yer", "Adres"), relativeDates: ("bugün", "yarın", "dün", "öbür gün"), periods: ("sabah", "öğleden sonra"), range: "ile", zone: "pekin saati", rejected: ["iptal", "ertelendi", "belirsiz"], negated: "Toplantı yok"),
    ]

    @Test func smartActionLanguageMatrixCoversTheSupportedSet() {
        #expect(Self.localizedSamples.count == 17)
        #expect(Set(Self.localizedSamples.map(\.language)) == Set(AppLanguage.allCases))
    }

    @Test(arguments: localizedSamples)
    func localizedMeetingFieldsPreserveTheCompleteDraft(_ sample: LocalizedSample) throws {
        let title = sample.meeting + " Alpha"
        let location = "Room 2026-09-24 16:00 UTC"
        let text = "\(sample.labels.title): \(title)\n\(sample.labels.date): 2026-09-22 14:30-16:00\n\(sample.labels.location): \(location)\nhttps://example.com/meeting?ref=2026-09-24"
        let result = try #require(detect(text), "\(sample.language.rawValue): \(text)")
        let value = try #require(draft(result))
        #expect(result.kind == .meeting)
        #expect(value.title == title)
        #expect(value.startDate == date(2026, 9, 22, 14, 30))
        #expect(value.endDate == date(2026, 9, 22, 16, 0))
        #expect(value.location == location)
        #expect(value.notes == text)
        #expect(result.fullContent == text)
        #expect(result.actions.count == 1)
        #expect(!value.isAllDay)
        let datedTitle = title + " Tokyo office 2026-09-23 16:00 " + sample.relativeDates.tomorrow
        let titledText = "\(sample.labels.title): \(datedTitle)\n\(sample.labels.date): 2026-09-22 14:30\n\(sample.labels.location): Room A"
        let titled = try #require(detect(titledText))
        #expect(draft(titled)?.title == datedTitle)
        #expect(draft(titled)?.startDate == date(2026, 9, 22, 14, 30))
        #expect(draft(titled)?.location == "Room A")
        let dated = try #require(detect("\(sample.labels.date): \(title) 2026-09-22 14:30"))
        #expect(draft(dated)?.title == title)
        let locationWithCancellationWord = sample.rejected[0] + " Room No. 4"
        for text in ["\(title) 2026-09-22 14:30\n\(sample.labels.location): \(locationWithCancellationWord)",
                     "\(title) 2026-09-22 14:30; \(sample.labels.location): Room 2026-09-24 16:00 UTC"] {
            let located = try #require(detect(text))
            #expect(draft(located)?.title == title)
            #expect(draft(located)?.startDate == date(2026, 9, 22, 14, 30))
            #expect(draft(located)?.location == (text.contains("Room No. 4") ? locationWithCancellationWord : "Room 2026-09-24 16:00 UTC"))
        }
    }

    @Test(arguments: localizedSamples)
    func localizedSmartInputsAreIndependentOfTheUILanguage(_ sample: LocalizedSample) throws {
        let title = sample.meeting + " Alpha"
        for uiLanguage in AppLanguage.allCases {
            for text in ["\(title) 2026-09-22 14:30", "2026-09-22 14:30 \(title)"] {
                let result = try #require(ClipboardAssistantDetector.detect(text: text,
                    enabledKinds: Set(ClipboardAssistantKind.allCases), systemLanguageIdentifier: uiLanguage.rawValue,
                    now: now, timeZone: utc, locale: uiLanguage.locale, countryCode: "US"))
                #expect(result.kind == .meeting, "Input \(sample.language.rawValue), UI \(uiLanguage.rawValue)")
                let value = try #require(draft(result))
                #expect(value.title == title)
                #expect(value.startDate == date(2026, 9, 22, 14, 30))
            }
            let address = "10 Downing Street, London #4"
            let result = try #require(ClipboardAssistantDetector.detect(text: "\(sample.labels.address): \(address)",
                enabledKinds: Set(ClipboardAssistantKind.allCases), systemLanguageIdentifier: uiLanguage.rawValue,
                now: now, timeZone: utc, locale: uiLanguage.locale, countryCode: "CN"))
            #expect(result.kind == .address)
            #expect(result.title == address)
            let url = try #require(serviceURL(result, .googleMaps))
            #expect(query(url, "query") == address)
            #expect(url.host == "www.google.com")
            #expect(url.fragment == nil)
        }
    }

    @Test(arguments: localizedSamples)
    func localizedRelativeDatesResolveInTheMeetingTimeZone(_ sample: LocalizedSample) throws {
        for (word, offset) in [(sample.relativeDates.today, 0), (sample.relativeDates.tomorrow, 1),
                               (sample.relativeDates.yesterday, -1), (sample.relativeDates.afterTomorrow, 2)] {
            let text = "\(sample.meeting) \(word) 14:30"
            let result = try #require(ClipboardAssistantDetector.smartActionDetection(text, enabledKinds: kinds,
                now: date(2026, 9, 21, 18, 0), timeZone: utc), "\(sample.language.rawValue): \(text)")
            #expect(draft(result)?.startDate == date(2026, 9, 21 + offset, 14, 30))
            #expect(draft(result)?.title == sample.meeting)
            let zoned = try #require(ClipboardAssistantDetector.smartActionDetection(
                text + " " + sample.zone, enabledKinds: kinds,
                now: date(2026, 9, 21, 18, 0), timeZone: utc))
            #expect(draft(zoned)?.startDate == date(2026, 9, 22 + offset, 6, 30))
        }
    }

    @Test(arguments: localizedSamples)
    func localizedTimeRangesAndPeriodsKeepTheirMeaning(_ sample: LocalizedSample) throws {
        let title = sample.meeting + " Alpha"
        for (period, expectedHour) in [(sample.periods.morning, 9), (sample.periods.afternoon, 21)] {
            for clock in ["\(period) 9:30", "9:30 \(period)"] {
                let result = try #require(detect("\(title) 2026-09-22 \(clock)"), "\(sample.language.rawValue): \(clock)")
                #expect(draft(result)?.startDate == date(2026, 9, 22, expectedHour, 30))
                #expect(draft(result)?.title == title)
            }
            #expect(detect("\(title) 2026-09-22 13:30 \(period)") == nil)
        }
        let result = try #require(detect("\(title) 2026-09-22 14:30 \(sample.range) 16:00"))
        #expect(draft(result)?.title == title)
        #expect(draft(result)?.startDate == date(2026, 9, 22, 14, 30))
        #expect(draft(result)?.endDate == date(2026, 9, 22, 16, 0))
        let inherited = try #require(detect("\(title) 2026-09-22 9:30 \(sample.range) 10:30 \(sample.periods.afternoon)"))
        #expect(draft(inherited)?.title == title)
        #expect(draft(inherited)?.startDate == date(2026, 9, 22, 21, 30))
        #expect(draft(inherited)?.endDate == date(2026, 9, 22, 22, 30))
        let inheritedPrefix = try #require(detect("\(title) 2026-09-22 \(sample.periods.afternoon) 9:30 \(sample.range) 10:30"))
        #expect(draft(inheritedPrefix)?.startDate == date(2026, 9, 22, 21, 30))
        #expect(draft(inheritedPrefix)?.endDate == date(2026, 9, 22, 22, 30))
        for clock in ["\(sample.periods.morning) 11:30 \(sample.range) \(sample.periods.afternoon) 1:30",
                      "11:30 \(sample.periods.morning) \(sample.range) 1:30 \(sample.periods.afternoon)"] {
            let crossingNoon = try #require(detect("\(title) 2026-09-22 \(clock)"))
            #expect(draft(crossingNoon)?.startDate == date(2026, 9, 22, 11, 30))
            #expect(draft(crossingNoon)?.endDate == date(2026, 9, 22, 13, 30))
        }
        let dual = try #require(detect("\(title) 2026-09-22 \(sample.periods.afternoon) 9:30 pm"))
        #expect(draft(dual)?.startDate == date(2026, 9, 22, 21, 30))
        #expect(detect("\(title) 2026-09-22 \(sample.periods.morning) 9:30 pm") == nil)
        #expect(detect("\(title) 2026-09-22 \(sample.periods.afternoon) 9:30 am") == nil)
        for (period, hour) in [(sample.periods.morning, 0), (sample.periods.afternoon, 12)] {
            let noonOrMidnight = try #require(detect("\(title) 2026-09-22 12:30 \(period)"))
            #expect(draft(noonOrMidnight)?.startDate == date(2026, 9, 22, hour, 30))
        }
    }

    @Test(arguments: localizedSamples)
    func localizedZoneAliasesApplyOnlyBesideAClock(_ sample: LocalizedSample) throws {
        for clock in ["14:30 \(sample.zone)", "\(sample.zone) 14:30"] {
            let result = try #require(detect("\(sample.meeting) 2026-09-22 \(clock)"))
            #expect(draft(result)?.startDate == date(2026, 9, 22, 6, 30))
        }
        let result = try #require(detect("\(sample.meeting) 2026-09-22 14:30\n\(sample.labels.location): \(sample.zone)"))
        #expect(draft(result)?.startDate == date(2026, 9, 22, 14, 30))
        #expect(draft(result)?.location == sample.zone)
        #expect(detect("\(sample.meeting) 2026-09-22 14:30 \(sample.zone) UTC") == nil)
    }

    @Test(arguments: localizedSamples)
    func localizedMeetingAndAddressTogglesRemoveTheirActions(_ sample: LocalizedSample) {
        let meeting = "\(sample.meeting) 2026-09-22 14:30"
        let address = "\(sample.labels.address): 10 Downing Street, London"
        for (text, kind) in [(meeting, ClipboardAssistantKind.meeting), (address, .address)] {
            #expect(ClipboardAssistantDetector.detect(text: text,
                enabledKinds: Set(ClipboardAssistantKind.allCases).subtracting([kind]),
                systemLanguageIdentifier: "en", now: now, timeZone: utc, locale: Locale(identifier: "en_US"),
                countryCode: "US")?.kind != kind)
            #expect(ClipboardAssistantDetector.smartActionDetection(text, enabledKinds: [], now: now, timeZone: utc) == nil)
        }
    }

    @Test(arguments: localizedSamples)
    func localizedCancellationAndNegationNeverOfferCalendarActions(_ sample: LocalizedSample) {
        let texts = sample.rejected.map { "\(sample.meeting) \($0) 2026-09-22 14:30" }
            + ["\(sample.negated) 2026-09-22 14:30"]
        for text in texts {
            let result = ClipboardAssistantDetector.detect(text: text, enabledKinds: Set(ClipboardAssistantKind.allCases),
                systemLanguageIdentifier: "en", now: now, timeZone: utc, locale: Locale(identifier: "en_US"))
            #expect(result?.kind != .meeting, "\(sample.language.rawValue): \(text)")
            #expect(result?.actions.contains { if case .editCalendarEvent = $0 { return true }; return false } != true)
        }
    }

    @Test(arguments: localizedSamples)
    func localizedMeetingKeywordsAndDateWordsCannotHideInsideLatinWords(_ sample: LocalizedSample) {
        #expect(detect("pre\(sample.meeting)post 2026-09-22 14:30") == nil)
        #expect(detect("\(sample.meeting) pre\(sample.relativeDates.today)post 14:30") == nil)
        #expect(detect("\(sample.meeting) \(sample.relativeDates.today)post 14:30") == nil)
    }

    @Test(arguments: localizedSamples)
    func localizedEmptyMalformedAndAmbiguousInputsRemainRejected(_ sample: LocalizedSample) {
        for text in [sample.meeting, "\(sample.meeting) 2026-09-22", "\(sample.meeting) 14:30",
                     "\(sample.meeting) 2026-02-30 14:30", "\(sample.meeting) 2026-09-22 25:00",
                     "\(sample.meeting) 2026-09-22 14:99", "\(sample.meeting) 2026-09-22 14:30-13:30",
                     "\(sample.meeting) 2026-09-22 14:30 or 16:00",
                     "\(sample.meeting) 2026-09-22 14:30-16:00 and 17:00",
                     "\(sample.meeting) 2026-09-22 2026-09-23 14:30",
                     "\(sample.meeting) \(sample.relativeDates.today) \(sample.relativeDates.tomorrow) 14:30",
                     "\(sample.meeting) 2026-09-22 14:30 UTC PST",
                     "\(sample.meeting) 2026-09-22 14:30 CST",
                     "\(sample.meeting) 2026-09-22 14:30 +08:99",
                     "\(sample.labels.address):", "\(sample.labels.address): unstructured text",
                     "\(sample.labels.address): https://evil.example/10-Downing-Street"] {
            #expect(detect(text) == nil, "\(sample.language.rawValue): \(text)")
        }
        for text in ["\(sample.meeting) 2026-03-08 02:30", "\(sample.meeting) 2026-11-01 01:30"] {
            #expect(ClipboardAssistantDetector.smartActionDetection(text, enabledKinds: kinds,
                now: now, timeZone: TimeZone(identifier: "America/New_York")!) == nil)
        }
    }

    @Test(arguments: localizedSamples)
    func localizedInputLimitsAndUnsafeSuffixesDoNotAddActions(_ sample: LocalizedSample) {
        for suffix in ["\u{0}", "\u{202E}", "\u{200B}", String(repeating: "a", count: 4_096)] {
            let text = "\(sample.meeting) 2026-09-22 14:30" + suffix
            #expect(detect(text) == nil, "\(sample.language.rawValue): suffix \(suffix.debugDescription)")
            #expect(ClipboardAssistantDetector.detect(text: text, enabledKinds: Set(ClipboardAssistantKind.allCases),
                systemLanguageIdentifier: "en", now: now, timeZone: utc, locale: Locale(identifier: "en_US"))?.kind != .meeting)
        }
        for suffix in ["\u{0}", "\u{202E}", "\n123", "&next=https://evil.example", String(repeating: "a", count: 256)] {
            #expect(detect("\(sample.labels.address): 10 Downing Street, London" + suffix) == nil)
        }
    }

    @Test func seededLocalizedLabelMutationsKeepWholeValueContracts() {
        var seed: UInt64 = 0x514D
        let alphabet = Array("abc012&?=#;\u{202E}")
        for sample in Self.localizedSamples {
            for _ in 0..<8 {
                var suffix = "&"
                for _ in 0..<12 {
                    seed = seed &* 6_364_136_223_846_793_005 &+ 1
                    suffix.append(alphabet[Int((seed >> 32) % UInt64(alphabet.count))])
                }
                #expect(detect("\(sample.labels.address): 10 Downing Street, London" + suffix) == nil)
                #expect(detect("\(sample.meeting) \(sample.relativeDates.tomorrow)post 14:30" + suffix) == nil)
            }
        }
    }

    @Test func cityNamesInsideMeetingTitlesKeepTheDefaultZone() throws {
        for title in ["Meeting Tokyo office", "Meeting New York team", "Meeting Beijing office", "Meeting Peking office"] {
            let result = try #require(detect(title + " 2026-09-22 14:30"))
            #expect(draft(result)?.title == title)
            #expect(draft(result)?.startDate == date(2026, 9, 22, 14, 30))
        }
    }

    @Test func ordinaryNumberedMeetingTitlesAndLocationsRemainValid() throws {
        for title in ["Meeting project No. 4", "Meeting project No4"] {
            let result = try #require(detect(title + " 2026-09-22 14:30\nLocation: Room No. 4"))
            #expect(draft(result)?.title == title)
            #expect(draft(result)?.location == "Room No. 4")
            #expect(draft(result)?.startDate == date(2026, 9, 22, 14, 30))
        }
        #expect(detect("Subject: Invoice\nDate: 2026-09-22 14:30\nLocation: Meeting room") == nil)
        #expect(detect("Subject: Invoice\nDate: 2026-09-22 14:30\nhttps://example.com/meeting") == nil)
    }

    @Test func chineseOptionalDaySuffixAndMixedSeparatorsKeepCompatibility() throws {
        for token in ["2026年9月22", "9月22", "2026年9月22日", "9月22日", "2026年9/22", "2026.9-22"] {
            let result = try #require(detect("产品会议 " + token + " 14:30"))
            #expect(draft(result)?.startDate == date(2026, 9, 22, 14, 30))
        }
    }

    @Test func arabicMeetingTitleAndAddressLabelsHaveDistinctPayloads() throws {
        let text = "عنوان الاجتماع: اجتماع Alpha\nالتاريخ: 2026-09-22 14:30\nالعنوان: 10 Downing Street, London"
        let result = try #require(detect(text))
        #expect(draft(result)?.title == "اجتماع Alpha")
        #expect(draft(result)?.location == "10 Downing Street, London")
        #expect(draft(result)?.startDate == date(2026, 9, 22, 14, 30))
    }

    @Test func cityNamesAfterTheClockKeepTheDefaultZoneAndTitle() throws {
        for tail in ["Tokyo office", "New York team", "Peking office", "北京办公室", "베이징 사무실", "ペキン事務所", "bắc kinh office", "بكين مكتب"] {
            let text = "Meeting 2026-09-22 14:30 " + tail
            let result = try #require(detect(text))
            let value = try #require(draft(result))
            #expect(value.startDate == date(2026, 9, 22, 14, 30), "\(tail)")
            #expect(value.title.hasSuffix(tail))
            #expect(value.notes == text)
        }
    }

    @Test func completeZonePhrasesCanPrecedeOrdinaryTitleContent() throws {
        for (zone, hour) in [("tokyo saati", 5), ("waktu beijing", 6), ("베이징 시간", 6),
                             ("giờ bắc kinh", 6), ("توقيت بكين", 6), ("heure de pékin", 6), ("東京時間", 5)] {
            let tail = zone + " project review"
            let text = "Meeting 2026-09-22 14:30 " + tail
            let result = try #require(detect(text))
            let value = try #require(draft(result))
            #expect(value.startDate == date(2026, 9, 22, hour, 30), "\(zone)")
            #expect(value.title.hasSuffix(tail))
            #expect(value.notes == text)
        }
        let result = try #require(detect("Meeting 2026-09-22 14:30 JST project review"))
        let abbreviation = try #require(draft(result))
        #expect(abbreviation.startDate == date(2026, 9, 22, 5, 30))
        #expect(detect("Meeting 2026-09-22 14:30 XYZ project review") == nil)
    }

    @Test func consecutiveZoneAliasesCannotHideAfterAMultiwordPhrase() {
        for zones in ["tokyo saati peking", "베이징 시간 도쿄", "waktu tokyo beijing", "new york time tokyo",
                      "hora de nueva york tokio", "giờ bắc kinh london", "توقيت بكين طوكيو", "beijing time UTC", "Tokyo Peking", "Peking Tokyo"] {
            #expect(detect("Meeting 2026-09-22 14:30 " + zones) == nil, "\(zones)")
        }
    }

    @Test func bareCityAliasesApplyAcrossTheCompleteTimeRange() throws {
        for clock in ["14:30 Tokyo to 16:00", "Tokyo 14:30 to 16:00", "14:30 to 16:00 Tokyo",
                      "14:30 Tokyo-16:00", "14:30-16:00 Tokyo", "14:30 to 16:00 (Tokyo)"] {
            let result = try #require(detect("Meeting 2026-09-22 " + clock))
            let value = try #require(draft(result))
            #expect(value.startDate == date(2026, 9, 22, 5, 30), "\(clock)")
            #expect(value.endDate == date(2026, 9, 22, 7, 0), "\(clock)")
        }
    }

    @Test func periodLookalikesRemainOrdinaryTitleWords() throws {
        for word in ["pXmY", "aXmY", "amber", "pmish", "morningstar"] {
            let text = "Meeting 2026-09-22 9:30 " + word
            let result = try #require(detect(text))
            let value = try #require(draft(result))
            #expect(value.startDate == date(2026, 9, 22, 9, 30))
            #expect(value.title.hasSuffix(word))
            #expect(value.notes == text)
        }
    }

    @Test func periodsOnAnotherLineRemainOrdinaryNotes() throws {
        for period in ["afternoon", "nachmittags", "sore"] {
            let text = "Meeting 2026-09-22 9:30\n" + period + " notes"
            let result = try #require(detect(text))
            let value = try #require(draft(result))
            #expect(value.startDate == date(2026, 9, 22, 9, 30))
            #expect(value.title == "Meeting")
            #expect(value.notes == text)
        }
    }

    @Test func cityAliasesAtTheEndOfAFieldKeepTheirTimeZone() throws {
        for suffix in ["\nAgenda notes", "\r\nAgenda notes", "; Agenda notes", ", Agenda notes", "，Agenda notes", "；Agenda notes"] {
            let text = "Meeting 2026-09-22 14:30 Tokyo" + suffix
            let result = try #require(detect(text))
            let value = try #require(draft(result))
            #expect(value.startDate == date(2026, 9, 22, 5, 30), "\(suffix.debugDescription)")
            #expect(value.notes == text)
        }
    }

    @Test func englishTimeFieldsKeepTheMeetingTitle() throws {
        let text = "Time: Meeting Alpha 2026-09-22 14:30"
        let result = try #require(detect(text))
        let value = try #require(draft(result))
        #expect(value.title == "Meeting Alpha")
        #expect(value.startDate == date(2026, 9, 22, 14, 30))
        #expect(value.notes == text)
    }
}
