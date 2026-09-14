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
        let startText: String
        let endText: String
        if let parts = conversionCaptures(#"(?:how many days\s+)?(?:days\s+)?(?:until|till)\s+(.+?)\??"#, in: text)
            ?? conversionCaptures(#"(?:距离|距|离|到)\s*(.+?)\s*(?:还有|还剩|剩余)?\s*(?:多少天|几天)[？?]?"#, in: text) {
            startText = "today"
            endText = parts[0]
        } else if let parts = conversionCaptures(#"(?:days\s+)?between\s+(.+?)\s+and\s+(.+?)\??"#, in: text)
            ?? conversionCaptures(#"(.+?)\s*(?:\s+to\s+|\s+-\s+|到|至)\s*(.+?)(?:\s*(?:相差|间隔)?\s*(?:多少天|几天)[？?]?)?"#, in: text) {
            startText = parts[0]
            endText = parts[1]
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

    private static func intervalDate(_ text: String, now: Date, calendar: Calendar) -> Date? {
        let offsets = ["today": 0, "今天": 0, "tomorrow": 1, "明天": 1, "yesterday": -1, "昨天": -1]
        if let offset = offsets[text.lowercased()] {
            return calendar.date(byAdding: .day, value: offset, to: calendar.startOfDay(for: now))
        }
        guard let parts = conversionCaptures(#"(\d{4})-(\d{1,2})-(\d{1,2})"#, in: text)
            ?? conversionCaptures(#"(\d{4})/(\d{1,2})/(\d{1,2})"#, in: text)
            ?? conversionCaptures(#"(\d{4})年(\d{1,2})月(\d{1,2})日"#, in: text) else { return nil }
        let components = DateComponents(year: Int(parts[0]), month: Int(parts[1]), day: Int(parts[2]))
        guard components.isValidDate(in: calendar) else { return nil }
        return calendar.date(from: components)
    }

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
        guard let operands = conversionOperands(text),
              let source = conversionCaptures(#"(.+?)\s+([^\s]+)"#, in: operands[0]),
              let sourceZone = conversionTimeZone(source[1]),
              let targetZone = conversionTimeZone(operands[1]),
              let date = zonedDate(source[0], now: now, timeZone: sourceZone) else { return nil }
        func render(_ zone: TimeZone) -> String {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.calendar = Calendar(identifier: .gregorian)
            formatter.timeZone = zone
            formatter.dateFormat = "yyyy-MM-dd HH:mm:ss XXX"
            return "\(formatter.string(from: date)) [\(zone.identifier)]"
        }
        return ParsedTimeZoneConversion(sourceText: render(sourceZone), targetText: render(targetZone))
    }

    private static let timeZoneIdentifiers = Dictionary(
        uniqueKeysWithValues: TimeZone.knownTimeZoneIdentifiers.map { ($0.lowercased(), $0) }
    )

    private static func conversionTimeZone(_ text: String) -> TimeZone? {
        let key = text.lowercased()
        let aliases = ["北京时间": "Asia/Shanghai", "中国时间": "Asia/Shanghai", "北京": "Asia/Shanghai",
                       "东京时间": "Asia/Tokyo", "东京": "Asia/Tokyo", "纽约时间": "America/New_York", "纽约": "America/New_York",
                       "london": "Europe/London", "伦敦": "Europe/London", "shanghai": "Asia/Shanghai", "tokyo": "Asia/Tokyo"]
        if let identifier = aliases[key] ?? timeZoneIdentifiers[key] { return TimeZone(identifier: identifier) }
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
        if ["now", "现在"].contains(text.lowercased()) { return now }
        guard let parts = conversionCaptures(#"(?:(\d{4}-\d{1,2}-\d{1,2})[T ]+)?(\d{1,2}):(\d{2})(?::(\d{2}))?(?:\s*(am|pm))?"#, in: text),
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
}
