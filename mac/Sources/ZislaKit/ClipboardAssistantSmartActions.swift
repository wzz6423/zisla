import Foundation
import ZislaCore

extension ClipboardAssistantDetector {
    public static func smartActionDetection(
        _ rawText: String,
        enabledKinds: Set<ClipboardAssistantKind>,
        countryCode: String? = Locale.current.region?.identifier,
        now: Date = Date(),
        timeZone: TimeZone = .current
    ) -> ClipboardAssistantDetection? {
        let text = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, text.count <= 4_096,
              !text.unicodeScalars.contains(where: {
                  ($0.properties.generalCategory == .control && $0 != "\n" && $0 != "\r" && $0 != "\t")
                      || $0.properties.generalCategory == .format
              }) else { return nil }
        if enabledKinds.contains(.meeting), let draft = meetingDraft(text, now: now, timeZone: timeZone) {
            return ClipboardAssistantDetection(
                kind: .meeting, title: draft.title, actions: [.editCalendarEvent(draft)], fullContent: text
            )
        }
        guard text.count <= 256 else { return nil }
        if enabledKinds.contains(.tracking), let tracking = trackingDetection(text, countryCode: countryCode) {
            return tracking
        }
        if enabledKinds.contains(.flight), let flight = flightDetection(text, countryCode: countryCode) {
            return flight
        }
        if enabledKinds.contains(.train), let train = trainDetection(text) {
            return train
        }
        if enabledKinds.contains(.address) {
            return addressDetection(text, countryCode: countryCode)
        }
        return nil
    }

    private static func addressDetection(_ text: String, countryCode: String?) -> ClipboardAssistantDetection? {
        let address = text.replacingOccurrences(
            of: #"(?i)^(?:地址|收货地址|address)\s*[:：]\s*"#, with: "", options: .regularExpression
        )
        guard !address.contains("\n"), !address.contains("://") else { return nil }
        let chinese = smartMatch(#"^(?:中国)?[\p{Han}]{2,}(?:省|市|自治区|特别行政区)[\p{Han}0-9（）()·\s-]{1,}(?:路|街|道|巷|弄)[0-9一二三四五六七八九十百]+号[\p{Han}0-9A-Za-z（）()·\s-]*$"#, address) != nil
        let western = smartMatch(#"(?i)^\d{1,6}[A-Z]?\s+[\p{L}\d .'-]{2,}\s(?:street|st\.?|road|rd\.?|avenue|ave\.?|boulevard|blvd\.?|drive|dr\.?|lane|ln\.?|way|court|ct\.?|place|pl\.?|parkway|pkwy\.?)(?:[ ,]+[\p{L}\d ,.#'-]+)?$"#, address) != nil
            || smartMatch(#"(?i)^(?:rue|avenue|boulevard|straße|strasse)\s+[\p{L} .'-]+\s+\d{1,5}(?:[ ,]+[\p{L}\d ,.'-]+)?$"#, address) != nil
        let japanese = smartMatch(#"^[\p{Han}ぁ-んァ-ヶ]{2,}(?:都|道|府|県)[\p{Han}ぁ-んァ-ヶ0-9-]+(?:丁目|番地|番|号)[\p{Han}ぁ-んァ-ヶ0-9-]*$"#, address) != nil
        let localChinese = smartMatch(#"^[\p{Han}]{2,}(?:路|街|道|巷|弄)[0-9一二三四五六七八九十百]+号[\p{Han}0-9A-Za-z（）()·\s-]*$"#, address) != nil
        let addressDetector = try! NSDataDetector(types: NSTextCheckingResult.CheckingType.address.rawValue)
        let detected = addressDetector.firstMatch(in: address, range: NSRange(address.startIndex..., in: address))
        let completeAddress = detected?.range == NSRange(address.startIndex..., in: address)
            && detected?.addressComponents?[.street] != nil
            && (detected?.addressComponents?[.city] != nil || detected?.addressComponents?[.zip] != nil)
        guard chinese || western || japanese || localChinese || completeAddress else { return nil }
        let overseasChinese = ["台湾", "台灣", "香港", "澳门", "澳門"].contains { address.contains($0) }
        let usesBaidu = !overseasChinese && (chinese || (localChinese && countryCode?.uppercased() == "CN"))
        let service: ClipboardAssistantService = usesBaidu ? .baiduMaps : .googleMaps
        var components = URLComponents(string: usesBaidu
            ? "https://api.map.baidu.com/geocoder"
            : "https://www.google.com/maps/search/")!
        components.queryItems = usesBaidu
            ? [URLQueryItem(name: "address", value: address), URLQueryItem(name: "output", value: "html"),
               URLQueryItem(name: "src", value: "webapp.zisla.clipboard")]
            : [URLQueryItem(name: "api", value: "1"), URLQueryItem(name: "query", value: address)]
        return ClipboardAssistantDetection(
            kind: .address, title: address, actions: [.openService(service: service, url: components.url!)]
        )
    }

    private static let chineseAirlines: Set<String> = ["CA", "MU", "CZ", "HU", "ZH", "MF", "SC", "3U", "8L", "9C", "HO", "KN", "GS", "G5", "EU", "PN", "JD", "TV", "AQ"]
    private static let internationalAirlines: Set<String> = ["UA", "AA", "DL", "WN", "B6", "AS", "AC", "BA", "LH", "AF", "KL", "LX", "OS", "IB", "AY", "SK", "EK", "QR", "EY", "SQ", "CX", "NH", "JL", "KE", "OZ", "QF", "NZ", "TK", "FR", "U2"]

    private static func flightDetection(_ text: String, countryCode: String?) -> ClipboardAssistantDetection? {
        guard let match = smartMatch(#"(?i)^(?:(航班(?:号)?|flight(?:\s*(?:number|no\.?))?)\s*[:：#]?\s*)?([A-Z][A-Z0-9]|[0-9][A-Z])\s?([1-9][0-9]{0,3})$"#, text) else { return nil }
        let carrier = match[2].uppercased()
        guard !match[1].isEmpty || chineseAirlines.contains(carrier) || internationalAirlines.contains(carrier) else { return nil }
        let number = carrier + match[3]
        let domestic = chineseAirlines.contains(carrier)
            || (!internationalAirlines.contains(carrier) && countryCode?.uppercased() == "CN")
        var actions: [ClipboardAssistantAction] = [serviceAction(domestic ? .umetrip : .flightAware, number: number)]
        let airline: ClipboardAssistantService? = switch carrier {
        case "UA": .united
        case "LH": .lufthansa
        case "BA": .britishAirways
        default: nil
        }
        if let airline { actions.append(serviceAction(airline)) }
        actions.append(.copyText(number))
        return ClipboardAssistantDetection(kind: .flight, title: number, actions: actions)
    }

    private static func trainDetection(_ text: String) -> ClipboardAssistantDetection? {
        guard let match = smartMatch(#"(?i)^(?:(?:车次|火车|高铁|train(?:\s*(?:number|no\.?))?)\s*[:：#]?\s*)?(G|D|C|Z|T|K|S|Y|ICE|IC|EC|RE|RB|TGV|EUROSTAR|AMTRAK|ACELA)\s?([1-9][0-9]{0,4})(?:次)?$"#, text) else { return nil }
        let prefix = match[1].uppercased()
        let service: ClipboardAssistantService
        switch prefix {
        case "ICE", "IC", "EC", "RE", "RB": service = .deutscheBahn
        case "TGV", "EUROSTAR": service = .sncf
        case "AMTRAK", "ACELA": service = .amtrak
        default:
            guard match[2].count <= 4 else { return nil }
            service = .railway12306
        }
        let number = prefix + (prefix.count > 1 ? " " : "") + match[2]
        return ClipboardAssistantDetection(
            kind: .train, title: number, actions: [serviceAction(service), .copyText(number)]
        )
    }

    private static func trackingDetection(_ text: String, countryCode: String?) -> ClipboardAssistantDetection? {
        guard let match = smartMatch(#"(?i)^(?:(顺丰|SF Express|UPS|FedEx|DHL|USPS|京东|圆通|中通|申通|韵达|极兔|邮政|EMS)\s*)?(?:(快递(?:单号)?|运单(?:号)?|物流(?:单号)?|tracking(?:\s*(?:number|no\.?))?)\s*)?[:：#]?\s*([A-Z0-9]{10,24})$"#, text) else { return nil }
        let brand = match[1].uppercased()
        let number = match[3].uppercased()
        let strongSF = smartMatch(#"^SF[0-9]{12,13}$"#, number) != nil
        let strongJD = smartMatch(#"^JD[0-9]{12,18}$"#, number) != nil
        let strongPostal = validPostalTrackingNumber(number)
        let strongUPS = smartMatch(#"^1Z[A-Z0-9]{16}$"#, number) != nil
        let contextual = !brand.isEmpty || !match[2].isEmpty
        guard strongSF || strongJD || strongUPS || strongPostal || contextual,
              number.contains(where: \.isNumber), Set(number).count > 2 else { return nil }
        let domestic = strongSF || strongJD || (!brand.isEmpty && brand.contains(where: { $0.unicodeScalars.contains { $0.value > 127 } }))
            || countryCode?.uppercased() == "CN"
        var actions = [serviceAction(domestic ? .kuaidi100 : .track17, number: number)]
        if domestic { actions.append(serviceAction(.track17, number: number)) }
        let carrier: ClipboardAssistantService? = switch brand {
        case "顺丰", "SF EXPRESS": .sfExpress
        case "UPS": .ups
        case "FEDEX": .fedEx
        case "DHL": .dhl
        case "USPS": .usps
        default: strongSF ? .sfExpress : (strongUPS ? .ups : (strongPostal && number.hasSuffix("US") ? .usps : nil))
        }
        if let carrier { actions.append(serviceAction(carrier, number: number)) }
        actions.append(.copyText(number))
        return ClipboardAssistantDetection(kind: .tracking, title: number, actions: actions)
    }

    private static func validPostalTrackingNumber(_ number: String) -> Bool {
        guard smartMatch(#"^[CELRV][A-Z][0-9]{9}[A-Z]{2}$"#, number) != nil else { return false }
        let digits = number.dropFirst(2).prefix(9).compactMap(\.wholeNumberValue)
        let sum = zip(digits.prefix(8), [8, 6, 4, 2, 3, 5, 9, 7]).reduce(0) { $0 + $1.0 * $1.1 }
        let remainder = 11 - sum % 11
        let expected = remainder == 10 ? 0 : (remainder == 11 ? 5 : remainder)
        return digits[8] == expected
    }

    private static func serviceAction(_ service: ClipboardAssistantService, number: String? = nil) -> ClipboardAssistantAction {
        let endpoint: String = switch service {
        case .umetrip: "https://www.umetrip.com/weixin/aliPay/flightSearch.html"
        case .flightAware: "https://www.flightaware.com/"
        case .united: "https://www.united.com/en/us/flightstatus/"
        case .lufthansa: "https://www.lufthansa.com/us/en/timetable-and-flight-status"
        case .britishAirways: "https://www.britishairways.com/travel/flightstatus/public/en_gb"
        case .railway12306: "https://kyfw.12306.cn/otn/queryTrainInfo/init"
        case .deutscheBahn: "https://www.bahn.de/service/fahrplaene/reiseauskunft"
        case .amtrak: "https://www.amtrak.com/train-status"
        case .sncf: "https://www.sncf-connect.com/outils/moteur-de-recherche"
        case .kuaidi100: "https://www.kuaidi100.com/"
        case .track17: "https://www.17track.net/en"
        case .sfExpress: "https://www.sf-express.com/chn/sc/waybill/list"
        case .ups: "https://www.ups.com/track"
        case .fedEx: "https://www.fedex.com/en-us/tracking.html"
        case .dhl: "https://www.dhl.com/us-en/home/tracking.html"
        case .usps: "https://tools.usps.com/go/TrackAction"
        case .baiduMaps, .googleMaps: preconditionFailure("Map actions require an encoded address")
        }
        var components = URLComponents(string: endpoint)!
        if let number {
            switch service {
            case .kuaidi100:
                components.queryItems = [URLQueryItem(name: "nu", value: number)]
            case .track17:
                components = URLComponents(string: "https://t.17track.net/en")!
                components.fragment = "nums=" + number
            case .flightAware:
                let prefixes = ["UA": "UAL", "LH": "DLH", "BA": "BAW", "AA": "AAL", "DL": "DAL", "AC": "ACA", "AF": "AFR", "KL": "KLM", "SQ": "SIA", "CX": "CPA", "NH": "ANA", "JL": "JAL", "EK": "UAE", "QR": "QTR", "QF": "QFA", "NZ": "ANZ", "TK": "THY", "WN": "SWA", "B6": "JBU", "AS": "ASA", "LX": "SWR", "OS": "AUA", "IB": "IBE", "AY": "FIN", "SK": "SAS", "EY": "ETD", "KE": "KAL", "OZ": "AAR", "FR": "RYR", "U2": "EZY"]
                if let prefix = prefixes[String(number.prefix(2))] {
                    components.path = "/live/flight/" + prefix + number.dropFirst(2)
                }
            case .usps:
                components.path = "/go/TrackConfirmAction.action"
                components.queryItems = [URLQueryItem(name: "tLabels", value: number)]
            default: break
            }
        }
        return .openService(service: service, url: components.url!)
    }

    private static func meetingDraft(_ text: String, now: Date, timeZone: TimeZone) -> ClipboardCalendarDraft? {
        guard smartMatch(#"(?i)(会议|开会|例会|评审会|研讨会|面试|日程|\bmeeting\b|\binterview\b|\bappointment\b|\bworkshop\b)"#, text) != nil else { return nil }
        var parsingText = text.replacingOccurrences(of: #"https?://[^\s]+"#, with: "", options: .regularExpression)
        parsingText = parsingText.replacingOccurrences(
            of: #"(?im)^\s*(?:地点|地址|location|where)\s*[:：][^\r\n]*"#, with: "", options: .regularExpression
        )
        let timePattern = #"(?i)(?<![0-9:：])(?:(上午|下午|晚上|中午|早上|凌晨)\s*)?([0-9]{1,2})(?:[:：]([0-9]{2})(?:[:：]([0-9]{2})(?:\.([0-9]{1,9}))?)?|点(?:([0-9]{1,2})分?|半)?)(?:\s*(am|pm))?(?![0-9:：])"#
        let timeRegex = try! NSRegularExpression(pattern: timePattern)
        let zonePattern = #"(?i)(?<![A-Z_])(?:(?:[A-Z_]+/[A-Z0-9_+.-]+(?:/[A-Z0-9_+.-]+)*|(?:UTC|GMT)(?:[ \t]*[+-][ \t]*[^\s,，;；)\]]*)?)(?![A-Z0-9_:])|(?:New York[ \t]+time|London[ \t]+time|Tokyo[ \t]+time|Beijing[ \t]+time|Shanghai[ \t]+time|(?:北京|上海|中国|中國|东京|東京|纽约|紐約|伦敦|倫敦)(?:时间|時間))(?![A-Z_]))"#
        let zoneRegex = try! NSRegularExpression(pattern: zonePattern)
        var zoneTexts: [String] = []
        for match in zoneRegex.matches(in: parsingText, range: NSRange(parsingText.startIndex..., in: parsingText)).reversed() {
            let range = Range(match.range, in: parsingText)!
            zoneTexts.append(String(parsingText[range]))
            parsingText.removeSubrange(range)
        }
        let abbreviations = TimeZone.abbreviationDictionary.keys.map(NSRegularExpression.escapedPattern(for:)).joined(separator: "|")
        let suffixPattern = #"^[ \t]*(?:\([ \t]*)?((?i:Z)(?:[+-][^\s,，;；)\]]*)?|[+-][^\s,，;；)\]]+|(?i:"# + abbreviations + #")|[A-Z]{2,5})(?![\p{L}0-9_])"#
        let suffixRegex = try! NSRegularExpression(pattern: suffixPattern)
        let prefixRegex = try! NSRegularExpression(pattern: #"(?:^|[ \t(])((?i:"# + abbreviations + #")|[A-Z]{2,5})[ \t]*$"#)
        var zoneRanges: [NSRange] = []
        for clock in timeRegex.matches(in: parsingText, range: NSRange(parsingText.startIndex..., in: parsingText)) {
            let clockRange = Range(clock.range, in: parsingText)!
            let prefix = String(parsingText[..<clockRange.lowerBound])
            if let match = prefixRegex.firstMatch(in: prefix, range: NSRange(prefix.startIndex..., in: prefix)) {
                zoneTexts.append(String(prefix[Range(match.range(at: 1), in: prefix)!]))
                zoneRanges.append(match.range(at: 1))
            }
            var cursor = clockRange.upperBound
            let isoClock = clockRange.lowerBound > parsingText.startIndex
                && parsingText[parsingText.index(before: clockRange.lowerBound)].uppercased() == "T"
            while cursor < parsingText.endIndex {
                let suffix = String(parsingText[cursor...])
                // A hyphen beside a non-ISO clock is the existing time-range syntax.
                if (suffix.range(of: #"^-[0-9]{1,2}[:：点]"#, options: .regularExpression) != nil && !isoClock)
                    || suffix.range(of: #"^[ \t]+-[ \t]+[0-9]"#, options: .regularExpression) != nil { break }
                guard let match = suffixRegex.firstMatch(in: suffix, range: NSRange(suffix.startIndex..., in: suffix)) else { break }
                let candidate = String(suffix[Range(match.range(at: 1), in: suffix)!])
                zoneTexts.append(candidate)
                let end = parsingText.index(cursor, offsetBy: suffix[Range(match.range, in: suffix)!].count)
                zoneRanges.append(NSRange(cursor..<end, in: parsingText))
                cursor = end
            }
        }
        guard zoneTexts.count <= 1 else { return nil }
        var meetingTimeZone = timeZone
        if let zoneText = zoneTexts.first {
            let normalized = zoneText.replacingOccurrences(of: #"(?i)^(UTC|GMT)[ \t]*([+-])[ \t]*"#, with: "$1$2", options: .regularExpression)
            guard let explicitZone = conversionTimeZone(normalized) else { return nil }
            meetingTimeZone = explicitZone
        }
        for range in zoneRanges.reversed() { parsingText.removeSubrange(Range(range, in: parsingText)!) }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = meetingTimeZone
        let datePattern = #"(?i)(?:(?<![0-9:：])(?:([0-9]{4})[-年/.]([0-9]{1,2})[-月/.]([0-9]{1,2})日?|([0-9]{1,2})[月./-]([0-9]{1,2})日?)(?![0-9:：])|今天|明天|后天|\btoday\b|\btomorrow\b)"#
        let dateRegex = try! NSRegularExpression(pattern: datePattern)
        let dateMatches = dateRegex.matches(in: parsingText, range: NSRange(parsingText.startIndex..., in: parsingText))
        // Multiple dates can describe alternatives, reschedules, or a cancellation.
        guard dateMatches.count == 1,
              smartMatch(#"(?i)(取消|改期|待定|取消会议|\bcancel(?:led|ed)?\b|\breschedul\w*\b|\btentative\b|\btbd\b)"#, text) == nil,
              let dateTokens = smartMatch(datePattern, parsingText) else { return nil }
        var day: Date
        if !dateTokens[1].isEmpty || !dateTokens[4].isEmpty {
            let year = Int(dateTokens[1]) ?? calendar.component(.year, from: now)
            let month = Int(dateTokens[2].isEmpty ? dateTokens[4] : dateTokens[2])!
            let dayNumber = Int(dateTokens[3].isEmpty ? dateTokens[5] : dateTokens[3])!
            let components = DateComponents(year: year, month: month, day: dayNumber)
            guard let parsed = calendar.date(from: components),
                  calendar.dateComponents([.year, .month, .day], from: parsed) == components else { return nil }
            day = parsed
        } else {
            let offset: Int
            switch dateTokens[0].lowercased() {
            case "明天", "tomorrow": offset = 1
            case "后天": offset = 2
            default: offset = 0
            }
            day = calendar.date(byAdding: .day, value: offset, to: calendar.startOfDay(for: now))!
        }
        let timeMatches = timeRegex.matches(in: parsingText, range: NSRange(parsingText.startIndex..., in: parsingText))
        guard (1...2).contains(timeMatches.count) else { return nil }
        let timeValues = timeMatches.map { String(parsingText[Range($0.range, in: parsingText)!]) }
        let commonPeriod = timeValues.compactMap { value -> String? in
            let tokens = smartMatch(timePattern, value)!
            let period = (tokens[1] + tokens[7]).lowercased()
            return period.isEmpty ? nil : period
        }.first ?? ""
        var times: [Date] = []
        for value in timeValues {
            let tokens = smartMatch(timePattern, value)!
            var hour = Int(tokens[2])!
            let minute = Int(tokens[3].isEmpty ? tokens[6] : tokens[3]) ?? (value.contains("半") ? 30 : 0)
            let period = (tokens[1] + tokens[7]).lowercased()
            let inheritedPeriod = period.isEmpty ? commonPeriod : period
            if !inheritedPeriod.isEmpty {
                guard (1...12).contains(hour) else { return nil }
                if ["下午", "晚上", "中午", "pm"].contains(inheritedPeriod) {
                    if hour < 12 { hour += 12 }
                } else if hour == 12 { hour = 0 }
            }
            let components = calendar.dateComponents([.year, .month, .day], from: day)
            var target = components
            target.hour = hour
            target.minute = minute
            let second = Int(tokens[4]) ?? 0
            let fraction = tokens[5].isEmpty ? "" : "." + tokens[5]
            let canonical = String(format: "%04d-%02d-%02d %02d:%02d:%02d", target.year!, target.month!, target.day!, hour, minute, second) + fraction
            guard let date = parseDateTime(canonical, now: now, timeZone: meetingTimeZone)?.date else { return nil }
            times.append(date)
        }
        let start = times[0]
        let end = times.count == 2 ? times[1] : start.addingTimeInterval(3_600)
        guard end > start else { return nil }
        if timeMatches.count == 2 {
            let first = Range(timeMatches[0].range, in: parsingText)!
            let second = Range(timeMatches[1].range, in: parsingText)!
            let between = String(parsingText[first.upperBound..<second.lowerBound])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard ["-", "–", "—", "~", "～", "至", "到", "to"].contains(between.lowercased()) else { return nil }
        }
        let locationPattern = #"(?i)(?:^|[\n，,；;]|\s)(?:地点|地址|location|where)\s*[:：]\s*([^\n，；;]+)"#
        let location = smartMatch(locationPattern, text)?[1].trimmingCharacters(in: .whitespaces)
        let explicitTitle = smartMatch(#"(?im)^(?:会议主题|主题|标题|subject|title)\s*[:：]\s*([^\r\n]+)"#, text)?[1]
        var title = explicitTitle ?? text.components(separatedBy: .newlines).first!
        if explicitTitle == nil {
            title = title.replacingOccurrences(of: datePattern, with: "", options: .regularExpression)
                .replacingOccurrences(of: timePattern, with: "", options: .regularExpression)
                .replacingOccurrences(of: locationPattern, with: "", options: .regularExpression)
                .replacingOccurrences(of: #"(?i)^(?:时间|日期|when|date)\s*[:：]\s*"#, with: "", options: .regularExpression)
                .trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: ",，;；:：-–—~～至到")))
        }
        guard !title.isEmpty, title.count <= 160,
              smartMatch(#"(?i)(会议|开会|例会|评审会|研讨会|面试|日程|\bmeeting\b|\binterview\b|\bappointment\b|\bworkshop\b)"#, title) != nil || explicitTitle != nil else { return nil }
        return ClipboardCalendarDraft(
            title: title, startDate: start, endDate: end, location: location, notes: text
        )
    }

    private static func smartMatch(_ pattern: String, _ text: String) -> [String]? {
        let expression = try! NSRegularExpression(pattern: pattern)
        guard let result = expression.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) else { return nil }
        return (0..<result.numberOfRanges).map {
            Range(result.range(at: $0), in: text).map { String(text[$0]) } ?? ""
        }
    }
}
