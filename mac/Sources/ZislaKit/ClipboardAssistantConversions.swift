import Foundation
import ZislaCore

extension ClipboardAssistantDetector {
    static func conversionDetection(
        _ text: String,
        enabledKinds: Set<ClipboardAssistantKind>,
        now: Date,
        timeZone: TimeZone,
        locale: Locale
    ) -> ClipboardAssistantDetection? {
        guard text.count <= 200 else { return nil }
        let kind: ClipboardAssistantKind
        let title: String
        let expression: String
        if enabledKinds.contains(.math), let conversion = parseUnitConversion(text) {
            kind = .math
            title = "\(formatNumber(conversion.result, locale: locale)) \(conversion.targetUnit)"
            expression = "\(conversion.amountText) \(conversion.sourceUnit) → \(conversion.targetUnit)"
        } else if enabledKinds.contains(.dateTime),
                  let interval = parseDateInterval(text, now: now, timeZone: timeZone) {
            kind = .dateTime
            title = AppLocalization.format("%@ 天", locale: locale, [String(interval.days)])
            expression = "\(dateText(interval.startDate, timeZone: timeZone)) → \(dateText(interval.targetDate, timeZone: timeZone))"
        } else if enabledKinds.contains(.dateTime), let conversion = parseTimeZoneConversion(text, now: now) {
            kind = .dateTime
            title = conversion.targetText
            expression = conversion.sourceText
        } else {
            return nil
        }
        let fullExpression = "\(expression) = \(title)"
        return ClipboardAssistantDetection(
            kind: kind,
            title: title,
            detail: .mathExpression(expression),
            actions: [.copyText(title), .copyFullExpression(fullExpression)],
            fullContent: fullExpression
        )
    }

    // Each grammar consumes the whole clipboard value; embedded prose must not trigger a conversion.
    static func conversionCaptures(_ pattern: String, in text: String) -> [String]? {
        guard text.count <= 200,
              let regex = try? NSRegularExpression(pattern: "^(?:" + pattern + ")$", options: .caseInsensitive),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) else { return nil }
        return (1..<match.numberOfRanges).map { index in
            Range(match.range(at: index), in: text).map { String(text[$0]) } ?? ""
        }
    }

    static func conversionOperands(_ text: String) -> [String]? {
        conversionCaptures(#"(.+)\s*(?:\s+(?:in|to)\s+|=|->|→|换算成|转)\s*(.+?)\s*=?"#, in: text)?
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
    }

    static let conversionAmountPattern = #"[+-]?(?:\d{1,3}(?:,\d{3})+(?:\.\d+)?|\d+(?:\.\d+)?|\.\d+)"#

    struct ParsedUnitConversion {
        let amountText: String
        let sourceUnit: String
        let targetUnit: String
        let result: Double
    }

    private struct UnitDefinition: Sendable {
        let unit: Dimension
        let category: String
    }

    private static let conversionUnits: [String: UnitDefinition] = {
        var table: [String: UnitDefinition] = [:]
        func add(_ names: String, _ unit: Dimension, _ category: String) {
            for name in names.split(separator: "|") {
                table[String(name)] = UnitDefinition(unit: unit, category: category)
            }
        }
        add("m|meter|meters|metre|metres|米", UnitLength.meters, "length")
        add("km|kilometer|kilometers|kilometre|kilometres|千米|公里", UnitLength.kilometers, "length")
        add("cm|centimeter|centimeters|centimetre|centimetres|厘米", UnitLength.centimeters, "length")
        add("mm|millimeter|millimeters|millimetre|millimetres|毫米", UnitLength.millimeters, "length")
        add("in|inch|inches|英寸", UnitLength.inches, "length")
        add("ft|foot|feet|英尺", UnitLength.feet, "length")
        add("yd|yard|yards|码", UnitLength.yards, "length")
        add("mi|mile|miles|英里", UnitLength.miles, "length")
        add("g|gram|grams|克", UnitMass.grams, "mass")
        add("kg|kilogram|kilograms|千克|公斤", UnitMass.kilograms, "mass")
        add("mg|milligram|milligrams|毫克", UnitMass.milligrams, "mass")
        add("lb|lbs|pound|pounds|磅", UnitMass.pounds, "mass")
        add("oz|ounce|ounces|盎司", UnitMass.ounces, "mass")
        add("t|tonne|tonnes|吨", UnitMass.metricTons, "mass")
        add("l|liter|liters|litre|litres|升", UnitVolume.liters, "volume")
        add("ml|milliliter|milliliters|millilitre|millilitres|毫升", UnitVolume.milliliters, "volume")
        add("c|°c|celsius|摄氏度", UnitTemperature.celsius, "temperature")
        add("f|°f|fahrenheit|华氏度", UnitTemperature.fahrenheit, "temperature")
        add("k|kelvin|开尔文", UnitTemperature.kelvin, "temperature")
        add("s|sec|second|seconds|秒", UnitDuration.seconds, "duration")
        add("min|minute|minutes|分钟", UnitDuration.minutes, "duration")
        add("h|hr|hour|hours|小时", UnitDuration.hours, "duration")
        add("m/s|米/秒", UnitSpeed.metersPerSecond, "speed")
        add("km/h|kph|公里/小时", UnitSpeed.kilometersPerHour, "speed")
        add("mph|英里/小时", UnitSpeed.milesPerHour, "speed")
        return table
    }()

    static func parseUnitConversion(_ text: String) -> ParsedUnitConversion? {
        guard let operands = conversionOperands(text),
              let amount = conversionCaptures("(" + conversionAmountPattern + #")\s*(.+)"#, in: operands[0]),
              let value = Double(amount[0].replacingOccurrences(of: ",", with: "")),
              let source = conversionUnits[amount[1].lowercased()],
              let target = conversionUnits[operands[1].lowercased()],
              source.category == target.category else { return nil }
        let result = Measurement(value: value, unit: source.unit).converted(to: target.unit).value
        guard result.isFinite else { return nil }
        return ParsedUnitConversion(amountText: amount[0], sourceUnit: source.unit.symbol, targetUnit: target.unit.symbol, result: result)
    }

    struct ParsedDateInterval {
        let days: Int
        let startDate: Date
        let targetDate: Date
    }

    static func parseDateInterval(_ text: String, now: Date = Date(), timeZone: TimeZone = .current) -> ParsedDateInterval? {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let startText: String
        let endText: String
        if let parts = firstConversionCaptures(dateIntervalBetweenPatterns, in: text) {
            startText = parts[0]
            endText = parts[1]
        } else if let parts = firstConversionCaptures(dateIntervalUntilPatterns, in: text) {
            startText = "today"
            endText = parts[0]
        } else {
            return nil
        }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        guard let start = intervalDate(startText, now: now, calendar: calendar),
              let end = intervalDate(endText, now: now, calendar: calendar),
              let days = calendar.dateComponents([.day], from: start, to: end).day else { return nil }
        return ParsedDateInterval(days: days, startDate: start, targetDate: end)
    }

    private static let dateIntervalUntilPatterns = [
        #"(?:how many days\s+)?(?:days\s+)?(?:until|till)\s+(.+?)\??"#,
        #"(?:距离|距離|距|离|離|到)\s*(.+?)\s*(?:还有|还剩|剩余|還有|還剩|剩餘)?\s*(?:多少天|几天|幾天)[？?]?"#,
        #"(.+?)\s*まで\s*(?:あと\s*)?何日(?:ですか)?[？?]?"#,
        #"(.+?)\s*까지\s*(?:몇\s*일|며칠)(?:\s+남았(?:어|나요|습니까)?)?[？?]?"#,
        #"combien\s+de\s+jours\s+(?:jusqu(?:'|’)au|avant)\s+(.+?)\??"#,
        #"wie\s+viele\s+tage\s+bis\s+(.+?)\??"#,
        #"cu[aá]ntos\s+d[ií]as\s+(?:hasta|para)\s+(.+?)\??"#,
        #"quantos\s+dias\s+at[eé]\s+(.+?)\??"#,
        #"quanti\s+giorni\s+fino\s+(?:al|alla)\s+(.+?)\??"#,
        #"hoeveel\s+dagen\s+tot\s+(.+?)\??"#,
        #"сколько\s+дней\s+до\s+(.+?)\??"#,
        #"كم\s+يوم(?:ً?ا)?\s+(?:حتى|إلى|الى)\s+(.+?)[؟?]?"#,
        #"อีก\s*กี่วัน\s*(?:จะ\s*)?ถึง\s*(.+?)[？?]?"#,
        #"berapa\s+hari\s+(?:sampai|hingga)\s+(.+?)\??"#,
        #"c[oò]n\s+bao\s+nhi[eê]u\s+ng[aà]y\s+(?:đ[eế]n|tới)\s+(.+?)\??"#,
        #"(.+?)\s+tarih(?:ine|e)\s+ka[cç]\s+g[uü]n\s+kald[ıi]\??"#,
    ]

    private static let dateIntervalBetweenPatterns = [
        #"(?:how\s+many\s+)?(?:days\s+)?between\s+(.+?)\s+and\s+(.+?)\??"#,
        #"(.+?)\s*(?:\s+to\s+|\s+-\s+|到|至)\s*(.+?)(?:\s*(?:相差|间隔|間隔)?\s*(?:多少天|几天|幾天)[？?]?)?"#,
        #"(.+?)\s*から\s*(.+?)\s*まで(?:\s*(?:の間)?\s*(?:何日(?:間)?|何日ですか)?)?[？?]?"#,
        #"(.+?)\s*(?:부터|에서)\s*(.+?)\s*(?:까지|사이)(?:\s*(?:며칠|몇\s*일))?[？?]?"#,
        #"combien\s+de\s+jours\s+entre\s+(.+?)\s+et\s+(.+?)\??"#,
        #"wie\s+viele\s+tage\s+zwischen\s+(.+?)\s+und\s+(.+?)\??"#,
        #"cu[aá]ntos\s+d[ií]as\s+entre\s+(.+?)\s+y\s+(.+?)\??"#,
        #"quantos\s+dias\s+entre\s+(.+?)\s+e\s+(.+?)\??"#,
        #"quanti\s+giorni\s+tra\s+(.+?)\s+e\s+(.+?)\??"#,
        #"hoeveel\s+dagen\s+tussen\s+(.+?)\s+en\s+(.+?)\??"#,
        #"сколько\s+дней\s+между\s+(.+?)\s+и\s+(.+?)\??"#,
        #"كم\s+يوم(?:ً?ا)?\s+بين\s+(.+?)\s+و\s+(.+?)[؟?]?"#,
        #"ระหว่าง\s+(.+?)\s+(?:ถึง|และ)\s+(.+?)\s+กี่วัน[？?]?"#,
        #"berapa\s+hari\s+antara\s+(.+?)\s+dan\s+(.+?)\??"#,
        #"bao\s+nhi[eê]u\s+ng[aà]y\s+gi(?:ữ|u)a\s+(.+?)\s+v[aà]\s+(.+?)\??"#,
        #"(.+?)\s+ile\s+(.+?)\s+aras[ıi]nda\s+ka[cç]\s+g[uü]n\??"#,
    ]

    private static func firstConversionCaptures(_ patterns: [String], in text: String) -> [String]? {
        patterns.lazy.compactMap { conversionCaptures($0, in: text) }.first
    }

    private static func intervalDate(_ text: String, now: Date, calendar: Calendar) -> Date? {
        if let offset = intervalDateOffsets[text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()] {
            return calendar.date(byAdding: .day, value: offset, to: calendar.startOfDay(for: now))
        }
        guard let parts = conversionCaptures(#"(\d{4})-(\d{1,2})-(\d{1,2})"#, in: text)
            ?? conversionCaptures(#"(\d{4})/(\d{1,2})/(\d{1,2})"#, in: text)
            ?? conversionCaptures(#"(\d{4})\.(\d{1,2})\.(\d{1,2})"#, in: text)
            ?? conversionCaptures(#"(\d{4})\s*(?:年|년)\s*(\d{1,2})\s*(?:月|월)\s*(\d{1,2})\s*(?:日|일)"#, in: text) else { return nil }
        let components = DateComponents(year: Int(parts[0]), month: Int(parts[1]), day: Int(parts[2]))
        guard components.isValidDate(in: calendar) else { return nil }
        return calendar.date(from: components)
    }

    private static let intervalDateOffsets = [
        "today": 0, "今天": 0, "今日": 0, "오늘": 0, "aujourd'hui": 0, "aujourd’hui": 0,
        "heute": 0, "hoy": 0, "hoje": 0, "oggi": 0, "vandaag": 0, "сегодня": 0,
        "اليوم": 0, "วันนี้": 0, "hari ini": 0, "hôm nay": 0, "hom nay": 0, "bugün": 0, "bugun": 0,
        "tomorrow": 1, "明天": 1, "明日": 1, "내일": 1, "demain": 1, "morgen": 1,
        "mañana": 1, "amanhã": 1, "domani": 1, "завтра": 1, "غدًا": 1, "غدا": 1,
        "พรุ่งนี้": 1, "besok": 1, "ngày mai": 1, "ngay mai": 1, "yarın": 1, "yarin": 1,
        "yesterday": -1, "昨天": -1, "昨日": -1, "어제": -1, "hier": -1, "gestern": -1,
        "ayer": -1, "ontem": -1, "ieri": -1, "gisteren": -1, "вчера": -1, "أمس": -1,
        "امس": -1, "เมื่อวาน": -1, "kemarin": -1, "hôm qua": -1, "hom qua": -1, "dün": -1, "dun": -1,
    ]

    private static func dateText(_ date: Date, timeZone: TimeZone) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    struct ParsedTimeZoneConversion {
        let sourceText: String
        let targetText: String
    }

    static func parseTimeZoneConversion(_ text: String, now: Date = Date()) -> ParsedTimeZoneConversion? {
        guard let operands = timeZoneConversionOperands(text),
              let source = timeZoneSource(operands[0]),
              let targetZone = conversionTimeZone(operands[1]),
              let date = zonedDate(source.dateText, now: now, timeZone: source.zone) else { return nil }
        func render(_ zone: TimeZone) -> String {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.calendar = Calendar(identifier: .gregorian)
            formatter.timeZone = zone
            formatter.dateFormat = "yyyy-MM-dd HH:mm:ss XXX"
            return "\(formatter.string(from: date)) [\(zone.identifier)]"
        }
        return ParsedTimeZoneConversion(sourceText: render(source.zone), targetText: render(targetZone))
    }

    private static func timeZoneConversionOperands(_ text: String) -> [String]? {
        if let operands = conversionOperands(text) { return operands }
        return firstConversionCaptures(timeZoneConversionOperandPatterns, in: text)?
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
    }

    private static let timeZoneConversionOperandPatterns = [
        #"(.+?)\s*(?:換算(?:成|為)?|轉換(?:成|為)?|轉)\s*(.+?)"#,
        #"(.+?)\s+(?:から|より)\s+(.+?)\s*(?:に|へ)(?:\s*変換)?"#,
        #"(.+?)\s+を\s+(.+?)\s+に(?:\s*変換)?"#,
        #"(.+?)(?:에서|부터)\s+(.+?)(?:으?로)(?:\s*변환)?"#,
        #"(.+?)\s+(?:vers|en)\s+(.+?)"#,
        #"(.+?)\s+(?:nach|zu)\s+(.+?)"#,
        #"(.+?)\s+(?:a|hacia)\s+(.+?)"#,
        #"(.+?)\s+(?:para|em)\s+(.+?)"#,
        #"(.+?)\s+(?:a|in)\s+(.+?)"#,
        #"(.+?)\s+(?:naar|in)\s+(.+?)"#,
        #"(.+?)\s+(?:в|во)\s+(.+?)"#,
        #"(.+?)\s+(?:إلى|الى)\s+(.+?)"#,
        #"(.+?)\s+(?:เป็น|ไป(?:ยัง)?)\s+(.+?)"#,
        #"(.+?)\s+(?:ke|menjadi)\s+(.+?)"#,
        #"(.+?)\s+(?:sang|đến)\s+(.+?)"#,
        #"(.+?)(?:'?(?:den|dan|ten|tan))\s+(.+?)(?:'?(?:e|a|ye|ya))(?:\s+[çc]evir)?"#,
    ]

    private static let timeZoneIdentifiers = Dictionary(
        uniqueKeysWithValues: TimeZone.knownTimeZoneIdentifiers.map { ($0.lowercased(), $0) }
    )

    private static let timeZoneAliases: [String: String] = {
        var aliases: [String: String] = [:]
        func add(_ names: [String], _ identifier: String) {
            for name in names {
                aliases[name.lowercased()] = identifier
            }
        }
        add([
            "beijing", "beijing time", "shanghai", "shanghai time", "北京时间", "中国时间", "北京", "上海时间", "上海",
            "北京時間", "中國時間", "上海時間", "ペキン", "베이징", "베이징 시간", "상하이", "상하이 시간",
            "pékin", "heure de pékin", "pekin", "heure de pekin", "peking", "schanghai", "pekín", "hora de pekín",
            "shanghái", "pequim", "horário de pequim", "xangai", "pechino", "ora di pechino", "tijd van peking",
            "пекин", "время пекина", "шанхай", "بكين", "توقيت بكين", "شنغهاي", "توقيت شنغهاي",
            "ปักกิ่ง", "เวลาปักกิ่ง", "เซี่ยงไฮ้", "เวลาเซี่ยงไฮ้", "bắc kinh", "giờ bắc kinh", "thượng hải",
            "giờ thượng hải", "pekin saati", "şanghay", "şanghay saati",
        ], "Asia/Shanghai")
        add([
            "tokyo", "tokyo time", "东京", "东京时间", "東京", "東京時間", "도쿄", "도쿄 시간", "tokio", "tóquio",
            "токио", "طوكيو", "โตเกียว", "tokyo saati",
        ], "Asia/Tokyo")
        add([
            "new york", "new york time", "纽约", "纽约时间", "紐約", "紐約時間", "ニューヨーク", "ニューヨーク時間",
            "뉴욕", "뉴욕 시간", "nueva york", "hora de nueva york", "nova york", "horário de nova york",
            "ora di new york", "tijd van new york", "нью-йорк", "время нью-йорка", "نيويورك", "توقيت نيويورك",
            "นิวยอร์ก", "เวลานิวยอร์ก", "new york saati",
        ], "America/New_York")
        add([
            "london", "london time", "伦敦", "倫敦", "ロンドン", "ロンドン時間", "런던", "런던 시간", "londres",
            "heure de londres", "londra", "ora di londra", "londen", "tijd van londen", "лондон", "время лондона",
            "لندن", "توقيت لندن", "ลอนดอน", "เวลาลอนดอน", "luân đôn", "giờ luân đôn", "londra saati",
        ], "Europe/London")
        return aliases
    }()

    private static let timeZoneAliasNames = timeZoneAliases.keys.sorted {
        $0.count == $1.count ? $0 > $1 : $0.count > $1.count
    }

    private static func timeZoneSource(_ text: String) -> (dateText: String, zone: TimeZone)? {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if let source = conversionCaptures(#"(.+?)\s+([^\s]+)"#, in: text),
           let zone = conversionTimeZone(source[1]) {
            return (source[0], zone)
        }
        let lowercasedText = text.lowercased()
        for alias in timeZoneAliasNames where lowercasedText.hasSuffix(alias) {
            let end = text.index(text.endIndex, offsetBy: -alias.count)
            let dateText = String(text[..<end]).trimmingCharacters(in: .whitespacesAndNewlines)
            if !dateText.isEmpty, let zone = conversionTimeZone(alias) {
                return (dateText, zone)
            }
        }
        return nil
    }

    private static func conversionTimeZone(_ text: String) -> TimeZone? {
        let key = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if let identifier = timeZoneAliases[key] ?? timeZoneIdentifiers[key] { return TimeZone(identifier: identifier) }
        // Ambiguous abbreviations such as CST and IST deliberately require an IANA zone or offset.
        let offsets = ["utc": 0, "gmt": 0, "z": 0, "est": -5, "edt": -4, "pst": -8, "pdt": -7, "jst": 9]
        if let hours = offsets[key] { return TimeZone(secondsFromGMT: hours * 3600) }
        guard let parts = conversionCaptures(#"(?:UTC|GMT)?([+-])(\d{1,2})(?::?(\d{2}))?"#, in: text),
              let hours = Int(parts[1]), hours <= 14 else { return nil }
        let minutes = Int(parts[2]) ?? 0
        guard minutes < 60, hours < 14 || minutes == 0 else { return nil }
        return TimeZone(secondsFromGMT: (parts[0] == "-" ? -1 : 1) * (hours * 3600 + minutes * 60))
    }

    private static func zonedDate(_ text: String, now: Date, timeZone: TimeZone) -> Date? {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if timeZoneNowWords.contains(text.lowercased()) { return now }
        guard let parts = conversionCaptures(#"(?:(.+?)[T ]+)?(\d{1,2}):(\d{2})(?::(\d{2}))?(?:\s*(am|pm))?"#, in: text),
              var hour = Int(parts[1]), let minute = Int(parts[2]), minute < 60 else { return nil }
        if !parts[4].isEmpty {
            guard (1...12).contains(hour) else { return nil }
            hour = hour % 12 + (parts[4].lowercased() == "pm" ? 12 : 0)
        }
        let second = Int(parts[3]) ?? 0
        guard hour < 24, second < 60 else { return nil }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        guard let day = intervalDate(parts[0].isEmpty ? "today" : parts[0], now: now, calendar: calendar) else { return nil }
        var components = calendar.dateComponents([.year, .month, .day], from: day)
        components.hour = hour
        components.minute = minute
        components.second = second
        let before = day.addingTimeInterval(-1)
        guard let first = calendar.nextDate(after: before, matching: components, matchingPolicy: .strict, repeatedTimePolicy: .first) else { return nil }
        // Foundation's repeated-time policy misses sub-hour rollbacks. Test the following
        // day's actual offset against the requested wall time instead of assuming a one-hour fold.
        let offset = timeZone.secondsFromGMT(for: first)
        let followingDayOffset = timeZone.secondsFromGMT(for: first.addingTimeInterval(86_400))
        let alternate = first.addingTimeInterval(TimeInterval(offset - followingDayOffset))
        if alternate != first,
           calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: alternate) == components {
            return nil
        }
        return first
    }

    private static let timeZoneNowWords: Set<String> = [
        "now", "现在", "此刻", "今", "지금", "maintenant", "jetzt", "ahora", "agora", "adesso", "ora", "nu",
        "сейчас", "الآن", "الان", "ตอนนี้", "sekarang", "bây giờ", "bay gio", "şimdi", "simdi",
    ]
}
