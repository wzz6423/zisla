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
              !rawText.unicodeScalars.contains(where: {
                  ($0.properties.generalCategory == .control && $0 != "\n" && $0 != "\r" && $0 != "\t")
                      || $0.properties.generalCategory == .format
              }) else { return nil }
        if enabledKinds.contains(.meeting), let draft = meetingDraft(text, now: now, timeZone: timeZone) {
            return ClipboardAssistantDetection(
                kind: .meeting, title: draft.title, actions: [.editCalendarEvent(draft)], fullContent: text
            )
        }
        guard text.count <= 256,
              !text.unicodeScalars.contains(where: { $0.properties.generalCategory == .control && $0 != "\t" }) else { return nil }
        if enabledKinds.contains(.tracking), let tracking = trackingDetection(text, countryCode: countryCode) {
            return tracking
        }
        if enabledKinds.contains(.flight), let flight = flightDetection(text, countryCode: countryCode) {
            return flight
        }
        if enabledKinds.contains(.train), let train = trainDetection(text, countryCode: countryCode, now: now) {
            return train
        }
        if enabledKinds.contains(.address) {
            return addressDetection(text, countryCode: countryCode)
        }
        return nil
    }

    private static let addressLabels = #"地址|收[货貨]地址|address|shipping address|住所|配送先住所|주소|배송지|adresse|lieferadresse|dirección|direccion|endereço|endereco|indirizzo|adres|адрес|العنوان|عنوان|ที่อยู่|alamat|địa chỉ|dia chi"#

    private static func addressDetection(_ text: String, countryCode: String?) -> ClipboardAssistantDetection? {
        let address = text.replacingOccurrences(
            of: "(?i)^(?:" + addressLabels + #")\s*[:：]\s*"#, with: "", options: .regularExpression
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
            ? "https://api.map.baidu.com/place/search"
            : "https://www.google.com/maps/search/")!
        components.queryItems = usesBaidu
            ? [URLQueryItem(name: "query", value: address), URLQueryItem(name: "region", value: "全国"), URLQueryItem(name: "output", value: "html"),
               URLQueryItem(name: "src", value: "webapp.zisla.clipboard")]
            : [URLQueryItem(name: "api", value: "1"), URLQueryItem(name: "query", value: address)]
        return ClipboardAssistantDetection(
            kind: .address, title: address, actions: [.openService(service: service, url: components.url!)]
        )
    }

    private static let chineseAirlines: Set<String> = ["CA", "MU", "CZ", "HU", "ZH", "MF", "SC", "3U", "8L", "9C", "HO", "KN", "GS", "G5", "EU", "PN", "JD", "TV", "AQ"]
    private static let flightAwarePrefixes = [
        "CA": "CCA", "MU": "CES", "CZ": "CSN", "HU": "CHH", "ZH": "CSZ", "MF": "CXA", "SC": "CDG",
        "3U": "CSC", "8L": "LKE", "9C": "CQH", "HO": "DKH", "KN": "CUA", "GS": "GCR", "G5": "HXA",
        "EU": "UEA", "PN": "CHB", "JD": "CBJ", "TV": "TBA", "AQ": "JYH",
        "BR": "EVA", "CI": "CAL", "JX": "SJX", "IT": "TTW", "CX": "CPA", "HX": "CRK", "UO": "HKE", "NX": "AMU",
        "UA": "UAL", "AA": "AAL", "DL": "DAL", "WN": "SWA", "B6": "JBU", "AS": "ASA", "AC": "ACA", "WS": "WJA",
        "BA": "BAW", "VS": "VIR", "EI": "EIN", "LS": "EXS", "FR": "RYR", "U2": "EZY",
        "LH": "DLH", "EW": "EWG", "DE": "CFG", "X3": "TUI", "LX": "SWR", "OS": "AUA",
        "AF": "AFR", "TO": "TVF", "KL": "KLM", "HV": "TRA", "IB": "IBE", "VY": "VLG", "UX": "AEA",
        "TP": "TAP", "AD": "AZU", "G3": "GLO", "JJ": "TAM", "AZ": "ITY", "W6": "WZZ", "W9": "WUK",
        "AY": "FIN", "SK": "SAS", "SU": "AFL", "DP": "PBD", "S7": "SBI", "UT": "UTA", "U6": "SVR",
        "EK": "UAE", "QR": "QTR", "EY": "ETD", "SV": "SVA", "XY": "KNE", "F3": "FAD", "FZ": "FDB", "G9": "ABY", "MS": "MSR",
        "SQ": "SIA", "NH": "ANA", "JL": "JAL", "MM": "APJ", "GK": "JJP", "BC": "SKY",
        "KE": "KAL", "OZ": "AAR", "LJ": "JNA", "7C": "JJA", "TW": "TWB", "BX": "ABL", "ZE": "ESR", "RS": "ASV",
        "TG": "THA", "FD": "AIQ", "SL": "TLM", "PG": "BKP", "DD": "NOK", "XJ": "TAX",
        "GA": "GIA", "JT": "LNI", "QZ": "AWQ", "ID": "BTK", "QG": "CTV", "IU": "SJV", "SJ": "SJY",
        "VN": "HVN", "VJ": "VJC", "QH": "BAV", "BL": "PIC", "TK": "THY", "PC": "PGT", "VF": "AJT", "XQ": "SXS",
        "QF": "QFA", "NZ": "ANZ", "JQ": "JST",
    ]
    private static let flightIATAPrefixes = Dictionary(uniqueKeysWithValues: flightAwarePrefixes.map { ($0.value, $0.key) })

    private static func flightDetection(_ text: String, countryCode: String?) -> ClipboardAssistantDetection? {
        let labelled = ClipboardAssistantIdentifierPatterns.splitLabel(text, pattern: ClipboardAssistantIdentifierPatterns.flightLabel)
        guard let match = smartMatch(#"(?i)^([A-Z]{3}|[A-Z][A-Z0-9]|[0-9][A-Z])(\h*)(\p{Nd}{1,4})(?:便)?$"#, labelled.value) else { return nil }
        let carrier = match[1].uppercased()
        let digits = ClipboardAssistantIdentifierPatterns.decimalDigits(match[3])
        guard let numeric = Int(digits), numeric > 0 else { return nil }
        let iata = flightIATAPrefixes[carrier] ?? carrier
        let icao = flightAwarePrefixes[iata]
        let known = icao != nil || iata == "LA"
        guard labelled.label != nil || known else { return nil }
        if labelled.label == nil {
            // Compact G5/S7 numbers overlap Chinese railway codes; a space or an explicit
            // flight label disambiguates the airline. Italian FR with a space denotes a train.
            if countryCode?.uppercased() == "CN", smartMatch(#"^[GDCZTKSY][0-9]$"#, carrier) != nil,
               match[2].isEmpty, digits.count <= 3 { return nil }
            if countryCode?.uppercased() == "IT", carrier == "FR", !match[2].isEmpty { return nil }
        }
        let number = carrier + digits
        let domestic = chineseAirlines.contains(iata) || (!known && countryCode?.uppercased() == "CN")
        var actions: [ClipboardAssistantAction] = [icao.map {
            serviceAction(.flightAware, number: $0 + String(numeric))
        } ?? .search(number)]
        if domestic { actions.append(serviceAction(.umetrip, number: iata + digits)) }
        let airline: ClipboardAssistantService? = switch iata {
        case "UA": .united
        case "LH": .lufthansa
        case "BA": .britishAirways
        default: nil
        }
        if let airline { actions.append(serviceAction(airline)) }
        actions.append(.copyText(carrier + match[3]))
        return ClipboardAssistantDetection(kind: .flight, title: number, actions: actions)
    }

    private static func trainDetection(_ text: String, countryCode: String?, now: Date) -> ClipboardAssistantDetection? {
        let labelled = ClipboardAssistantIdentifierPatterns.splitLabel(text, pattern: ClipboardAssistantIdentifierPatterns.trainLabel)
        let value = labelled.value.replacingOccurrences(of: #"\h+"#, with: " ", options: .regularExpression)
        guard let match = smartMatch(#"(?i)^([\p{L} .'-]*?)[ ]*(\p{Nd}{1,5})([A-ZА-Я]?)(?:[ ]*(?:次|号|號|호))?$"#, value) else { return nil }
        let prefix = match[1].trimmingCharacters(in: .whitespaces).uppercased()
        let digits = ClipboardAssistantIdentifierPatterns.decimalDigits(match[2])
        guard let numeric = Int(digits), numeric > 0 else { return nil }
        let country = countryCode?.uppercased()
        var service: ClipboardAssistantService?
        var queryName: String?
        var official: String?
        let russian = ["САПСАН", "ЛАСТОЧКА", "РЖД", "SAPSAN"].contains(prefix)
        guard match[3].isEmpty || russian || (prefix.isEmpty && labelled.label != nil && country == "RU") else { return nil }
        switch prefix {
        case "G", "D", "C", "Z", "T", "K", "S", "Y":
            guard digits.count <= 4 else { return nil }
            service = .railway12306
        case "ICE", "RE", "RB", "IRE": service = .deutscheBahn; queryName = "Deutsche Bahn"
        case "IC", "EC", "INTERCITY":
            switch country {
            case "NL": queryName = "NS"; official = "https://www.ns.nl/"
            case "PT": queryName = "Comboios de Portugal"; official = "https://www.cp.pt/"
            case "IT": queryName = "Trenitalia"; official = "https://www.trenitalia.com/"
            case "AT": queryName = "ÖBB"; official = "https://www.oebb.at/"
            case "CH": queryName = "SBB"; official = "https://www.sbb.ch/"
            case "FR": service = .sncf; queryName = "SNCF"
            default: service = .deutscheBahn; queryName = "Deutsche Bahn"
            }
        case "TGV", "INOUI", "OUIGO", "TER", "INTERCITÉS", "SNCF": service = .sncf; queryName = "SNCF"
        case "AMTRAK", "ACELA": service = .amtrak; queryName = ""
        case "EUROSTAR": queryName = "Eurostar"; official = "https://www.eurostar.com/"
        case "AVE", "AVLO", "ALVIA", "EUROMED", "AVANT", "RENFE": queryName = "Renfe"; official = "https://www.renfe.com/"
        case "FR":
            guard labelled.label != nil || (country == "IT" && smartMatch(#"(?i)^FR[ ]+\p{Nd}"#, value) != nil) else { return nil }
            queryName = "Trenitalia Frecciarossa"; official = "https://www.trenitalia.com/"
        case "FRECCIAROSSA", "FRECCIARGENTO", "FRECCIABIANCA": queryName = "Trenitalia"; official = "https://www.trenitalia.com/"
        case "ITALO": queryName = "Italo"; official = "https://www.italotreno.com/"
        case "NS": queryName = "NS"; official = "https://www.ns.nl/"
        case "CP", "AP", "ALFA PENDULAR", "INTERCIDADES": queryName = "Comboios de Portugal"; official = "https://www.cp.pt/"
        case "RJ", "RJX", "RAILJET": queryName = "ÖBB"; official = "https://www.oebb.at/"
        case "のぞみ", "ひかり", "こだま", "NOZOMI", "HIKARI", "KODAMA": queryName = "JR"; official = "https://global.jr-central.co.jp/"
        case "はやぶさ", "やまびこ", "つばさ", "かがやき", "HAYABUSA": queryName = "JR"; official = "https://www.jreast.co.jp/"
        case "さくら", "みずほ", "SHINKANSEN": queryName = "新幹線"
        case "THSR", "台灣高鐵", "臺灣高鐵", "台湾高铁": queryName = "台灣高鐵"; official = "https://www.thsrc.com.tw/"
        case "TRA", "台鐵", "臺鐵", "台铁", "自強", "普悠瑪", "太魯閣", "區間": queryName = "臺鐵"; official = "https://www.railway.gov.tw/"
        case "KTX", "ITX", "ITX-청춘", "ITX-새마을", "무궁화", "새마을": queryName = "Korail"; official = "https://www.letskorail.com/"
        case "SRT":
            if country == "TH" { queryName = "การรถไฟแห่งประเทศไทย"; official = "https://www.railway.co.th/" }
            else { queryName = "SRT"; official = "https://etk.srail.kr/" }
        case "САПСАН", "ЛАСТОЧКА", "РЖД", "SAPSAN": queryName = "РЖД"; official = "https://www.rzd.ru/"
        case "SE", "SP", "SNT", "SQN": queryName = "Đường sắt Việt Nam"; official = "https://dsvn.vn/"
        case "KA", "KAI", "ARGO BROMO ANGGREK", "TAKSAKA": queryName = "KAI"; official = "https://www.kai.id/"
        case "SAR": queryName = "SAR"; official = "https://www.sar.com.sa/"
        case "YHT", "TCDD": queryName = "TCDD"; official = "https://www.tcddtasimacilik.gov.tr/"
        case "":
            guard let label = labelled.label else { return nil }
            if country == "CN", digits.count == 4, numeric >= 1_000 { service = .railway12306 }
            else { queryName = label }
        default: return nil
        }
        let compact = prefix.count == 1 || ["SE", "SP", "SNT", "SQN"].contains(prefix)
        let stem = prefix + (prefix.isEmpty || compact ? "" : " ")
        let number = stem + (service == .railway12306 ? String(numeric) : digits) + match[3].uppercased()
        var actions: [ClipboardAssistantAction] = []
        if let queryName { actions.append(.search((queryName.isEmpty ? "" : queryName + " ") + number)) }
        if let service { actions.append(serviceAction(service, number: number, now: now)) }
        if let official { actions.append(.openURL(URL(string: official)!)) }
        actions.append(.copyText(stem + match[2] + match[3].uppercased()))
        return ClipboardAssistantDetection(
            kind: .train, title: number, actions: actions
        )
    }

    static func trackingDetection(
        _ text: String, countryCode: String?, allowUnlabelledNumber: Bool = false
    ) -> ClipboardAssistantDetection? {
        guard text.count <= 256, !text.unicodeScalars.contains(where: {
            $0.properties.generalCategory == .control && $0 != "\t"
        }) else { return nil }
        var value = text
        var brand = ""
        var label: String?
        for _ in 0..<2 {
            let labelled = ClipboardAssistantIdentifierPatterns.splitLabel(value, pattern: ClipboardAssistantIdentifierPatterns.trackingLabel)
            if let found = labelled.label { label = found; value = labelled.value; continue }
            let branded = ClipboardAssistantIdentifierPatterns.splitLabel(value, pattern: trackingBrands)
            if let found = branded.label { brand = found.uppercased(); value = branded.value; continue }
            break
        }
        value = value.replacingOccurrences(of: #"\h+"#, with: " ", options: .regularExpression)
        guard smartMatch(#"(?i)^[A-Z\p{Nd}]+(?:[ -][A-Z\p{Nd}]+)*$"#, value) != nil else { return nil }
        let copiedNumber = value.replacingOccurrences(of: "[ -]", with: "", options: .regularExpression).uppercased()
        let number = ClipboardAssistantIdentifierPatterns.decimalDigits(copiedNumber)
        let contextual = !brand.isEmpty || label != nil
        guard (contextual ? 8...32 : 10...24).contains(number.count) else { return nil }
        let strongSF = smartMatch(#"^SF[0-9]{12,13}$"#, number) != nil
        let strongJD = smartMatch(#"^JD[0-9]{12,18}$"#, number) != nil
        let strongPostal = validPostalTrackingNumber(number)
        let strongUPS = smartMatch(#"^1Z[A-Z0-9]{16}$"#, number) != nil
        let postalShape = smartMatch(#"^[A-Z]{2}[0-9]{9}[A-Z]{2}$"#, number) != nil
        guard !postalShape || strongPostal else { return nil }
        let weakNumber = allowUnlabelledNumber && (12...24).contains(number.count)
            && number.utf8.allSatisfy { (48...57).contains($0) } && value == copiedNumber
        guard strongSF || strongJD || strongUPS || strongPostal || contextual || weakNumber,
              number.contains(where: \.isNumber), Set(number).count > 2 else { return nil }
        let domestic = strongSF || strongJD || mainlandTrackingBrands.contains(brand)
            || (brand.isEmpty && countryCode?.uppercased() == "CN")
        var actions = [serviceAction(domestic ? .kuaidi100 : .track17, number: number)]
        if domestic { actions.append(serviceAction(.track17, number: number)) }
        let carrier: ClipboardAssistantService? = switch brand {
        case "顺丰", "順豐", "SF EXPRESS": .sfExpress
        case "UPS": .ups
        case "FEDEX": .fedEx
        case "DHL": .dhl
        case "USPS": .usps
        default: strongSF ? .sfExpress : (strongUPS ? .ups : (strongPostal && number.hasSuffix("US") ? .usps : nil))
        }
        if let carrier { actions.append(serviceAction(carrier, number: number)) }
        actions.append(.copyText(copiedNumber))
        return ClipboardAssistantDetection(kind: .tracking, title: number, actions: actions)
    }

    private static func validPostalTrackingNumber(_ number: String) -> Bool {
        guard smartMatch(#"^[CELMRUV][A-Z][0-9]{9}[A-Z]{2}$"#, number) != nil,
              postalRegions.contains(String(number.suffix(2))) else { return false }
        let digits = number.dropFirst(2).prefix(9).compactMap(\.wholeNumberValue)
        let sum = zip(digits.prefix(8), [8, 6, 4, 2, 3, 5, 9, 7]).reduce(0) { $0 + $1.0 * $1.1 }
        let remainder = 11 - sum % 11
        let expected = remainder == 10 ? 0 : (remainder == 11 ? 5 : remainder)
        return digits[8] == expected
    }

    private static let postalRegions = Set(Locale.Region.isoRegions.map(\.identifier))
    private static let mainlandTrackingBrands: Set<String> = ["顺丰", "順豐", "SF EXPRESS", "京东", "京東", "JD LOGISTICS", "圆通", "圓通", "YTO", "中通", "ZTO", "申通", "STO", "韵达", "韻達", "YUNDA", "极兔", "極兔", "邮政", "中国邮政", "CHINA POST"]
    private static let trackingBrands = #"顺丰|順豐|SF Express|UPS|FedEx|DHL|USPS|京东|京東|JD Logistics|圆通|圓通|YTO|中通|ZTO|申通|STO|韵达|韻達|Yunda|极兔|極兔|邮政|中国邮政|China Post|EMS|日本郵便|Japan Post|ヤマト運輸|ヤマト|Yamato|佐川急便|Sagawa|黑貓宅急便|黑猫宅急便|新竹物流|HCT|中華郵政|Chunghwa Post|CJ대한통운|CJ Logistics|한진택배|Hanjin|우체국|La Poste|Colissimo|Chronopost|Mondial Relay|DPD|Hermes|GLS|Deutsche Post|Correos|SEUR|MRW|Correios|Jadlog|Total Express|Poste Italiane|SDA|BRT|PostNL|bpost|Почта России|СДЭК|CDEK|Boxberry|Aramex|أرامكس|البريد السعودي|SPL|سمسا|SMSA|Emirates Post|البريد المصري|ไปรษณีย์ไทย|Thailand Post|Kerry Express|Flash Express|JNE|J&T(?: Express)?|SiCepat|Pos Indonesia|TIKI|Viettel Post|Vietnam Post|VNPost|Giao Hàng Nhanh|GHN|GHTK|PTT(?: Kargo)?|Yurtiçi Kargo|Aras Kargo|MNG Kargo|Sürat Kargo|Royal Mail|Parcelforce|Canada Post|Australia Post|NZ Post|An Post|SingPost|Pos Malaysia|Pos Laju|India Post|Delhivery|Blue Dart"#

    private static func serviceAction(_ service: ClipboardAssistantService, number: String? = nil, now: Date = Date()) -> ClipboardAssistantAction {
        let endpoint: String = switch service {
        case .umetrip: "https://www.umetrip.com/weixin/aliPay/flightSearch.html"
        case .flightAware: "https://www.flightaware.com/"
        case .united: "https://www.united.com/en/us/flightstatus/"
        case .lufthansa: "https://www.lufthansa.com/us/en/timetable-and-flight-status"
        case .britishAirways: "https://www.britishairways.com/travel/flightstatus/public/en_gb"
        case .railway12306: "https://kyfw.12306.cn/otn/queryTrainInfo/init"
        case .deutscheBahn: "https://kursbuch.bahn.de/hafas/kbview.exe/dn"
        case .amtrak: "https://www.amtrak.com/train-status"
        case .sncf: "https://www.sncf-connect.com/outils/moteur-de-recherche"
        case .kuaidi100: "https://www.kuaidi100.com/"
        case .track17: "https://www.17track.net/en"
        case .sfExpress: "https://www.sf-express.com/chn/sc/waybill/list"
        case .ups: "https://www.ups.com/track"
        case .fedEx: "https://www.fedex.com/en-us/tracking.html"
        case .dhl: "https://www.dhl.com/us-en/home/tracking.html"
        case .usps: "https://tools.usps.com/go/TrackAction"
        case .baiduMaps, .googleMaps, .ipInfo: preconditionFailure("These service actions require their own URL")
        }
        var components = URLComponents(string: endpoint)!
        if let number {
            switch service {
            case .umetrip:
                components.queryItems = [URLQueryItem(name: "flightNo", value: number)]
            case .railway12306:
                var calendar = Calendar(identifier: .gregorian)
                calendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
                let date = calendar.dateComponents([.year, .month, .day], from: now)
                components.queryItems = [
                    URLQueryItem(name: "station_train_code", value: number),
                    URLQueryItem(name: "date", value: String(format: "%04d-%02d-%02d", date.year!, date.month!, date.day!)),
                ]
            case .deutscheBahn:
                components.queryItems = [
                    URLQueryItem(name: "train_nr", value: number), URLQueryItem(name: "searchmode", value: "train"),
                    URLQueryItem(name: "mainframe", value: "result"), URLQueryItem(name: "orig", value: "sZ"),
                    URLQueryItem(name: "dosearch", value: "1"),
                ]
            case .kuaidi100:
                components.queryItems = [URLQueryItem(name: "nu", value: number)]
            case .track17:
                components = URLComponents(string: "https://t.17track.net/en")!
                components.fragment = "nums=" + number
            case .flightAware:
                components.path = "/live/flight/" + number
            case .usps:
                components.path = "/go/TrackConfirmAction.action"
                components.queryItems = [URLQueryItem(name: "tLabels", value: number)]
            default: break
            }
        }
        return .openService(service: service, url: components.url!)
    }

    private static let meetingKeywords = smartPhrasePattern([
        "会议", "开会", "例会", "评审会", "研讨会", "面试", "日程", "會議", "開會", "例會", "評審會", "研討會", "面試",
        "meeting", "interview", "appointment", "workshop", "会議", "ミーティング", "面接", "打ち合わせ", "회의", "미팅", "면접",
        "réunion", "entretien", "rendez-vous", "atelier", "besprechung", "vorstellungsgespräch", "termin",
        "reunión", "entrevista", "cita", "taller", "reunião", "consulta", "riunione", "colloquio", "appuntamento",
        "vergadering", "sollicitatiegesprek", "afspraak", "совещание", "встреча", "собеседование",
        "اجتماع", "مقابلة", "موعد", "ประชุม", "สัมภาษณ์", "นัดหมาย", "rapat", "wawancara", "janji temu",
        "cuộc họp", "họp", "phỏng vấn", "cuộc hẹn", "toplantı", "mülakat", "randevu",
    ])
    private static let meetingLocationLabels = #"地点|地點|location|where|場所|会場|장소|위치|lieu|emplacement|ort|standort|ubicación|ubicacion|lugar|local|localização|luogo|sede|locatie|место|местоположение|المكان|مكان|الموقع|موقع|สถานที่|lokasi|tempat|địa điểm|dia diem|yer|konum|"# + addressLabels
    private static let meetingTitleLabels = #"会议主题|會議主題|主题|主題|标题|標題|subject|title|件名|議題|タイトル|주제|제목|sujet|objet|titre|thema|betreff|titel|asunto|tema|título|titulo|assunto|oggetto|titolo|onderwerp|тема|заголовок|الموضوع|موضوع|عنوان الاجتماع|หัวข้อ|ชื่อเรื่อง|subjek|judul|chủ đề|chu de|tiêu đề|tieu de|konu|başlık"#
    private static let meetingDateLabels = #"时间|時間|日期|when|date|time|日時|日付|일시|날짜|시간|quand|heure|datum|zeit|wann|fecha|hora|data|horário|quando|orario|tijd|wanneer|дата|время|когда|التاريخ|تاريخ|الوقت|وقت|วันที่|เวลา|tanggal|waktu|ngày|giờ|thời gian|tarih|saat"#
    private static let meetingRejectionPattern = #"(?i)(?:取消|改期|待定|暂定|暫定|没有会议|沒有會議|不[开開][会會]|中止|キャンセル|延期|未定|会議(?:は|が|を)?(?:なし|しない)|ยกเลิก|เลื่อน|ยังไม่กำหนด|ไม่(?:มี|จัด)?(?:การ)?ประชุม|(?<![\p{L}\p{M}])(?:cancel(?:led|ed|lation)?|reschedul\w*|tentative|tbd|no(?![.0-9])|not|취소|연기|미정|잠정|없음|annul(?:ée?s?|er|ation)|report(?:ée?s?|er)|provisoire|à confirmer|pas|abgesagt|absagen|verschoben|verschieben|vorläufig|kein(?:e|en|er|es)?|nicht|cancelad[oa]s?|cancelar|cancelación|aplazad[oa]s?|reprogramad[oa]s?|por confirmar|sin|cancelamento|adiad[oa]s?|remarcad[oa]s?|a confirmar|sem|não|annullat[oaie]|annullare|rinviat[oaie]|provvisori[oaie]|da confermare|nessun[oa]?|non|geannuleerd|annuleren|uitgesteld|verplaatst|voorlopig|geen|niet|отмен[а-яё]*|перенес[а-яё]*|предварительн[а-яё]*|не|нет|ملغي|ملغى|ملغاة|إلغاء|الغاء|مؤجل|تأجيل|غير مؤكد|لا|ليس|dibatalkan|batal|ditunda|tentatif|belum ditentukan|tidak|bukan|hủy|huỷ|hoãn|dời lịch|chưa xác định|không|iptal|ertelendi|belirsiz|yok|değil)(?![\p{L}\p{M}]))"#
    static let meetingPeriods: [String: Bool] = [
        "上午": false, "早上": false, "凌晨": false, "下午": true, "晚上": true, "中午": true,
        "am": false, "a.m.": false, "morning": false, "pm": true, "p.m.": true, "afternoon": true,
        "午前": false, "朝": false, "午後": true, "夕方": true, "夜": true,
        "오전": false, "아침": false, "오후": true, "저녁": true,
        "du matin": false, "de l'après-midi": true, "de l’après-midi": true, "du soir": true,
        "vormittags": false, "morgens": false, "nachmittags": true, "abends": true,
        "de la mañana": false, "de la tarde": true, "de la noche": true,
        "da manhã": false, "da tarde": true, "da noite": true,
        "di mattina": false, "del pomeriggio": true, "di sera": true,
        "'s ochtends": false, "’s ochtends": false, "'s middags": true, "’s middags": true, "'s avonds": true, "’s avonds": true,
        "утра": false, "дня": true, "вечера": true,
        "صباحًا": false, "صباحا": false, "مساءً": true, "مساء": true,
        "เช้า": false, "ก่อนเที่ยง": false, "บ่าย": true, "เย็น": true,
        "pagi": false, "siang": true, "sore": true,
        "sáng": false, "chiều": true, "tối": true,
        "sabah": false, "öğleden önce": false, "öğleden sonra": true, "akşam": true,
    ]
    static let meetingPeriodPattern = smartPhrasePattern(Array(meetingPeriods.keys))
    private static let meetingRangeSeparators: Set<String> = ["-", "–", "—", "~", "～", "〜", "至", "到", "to", "から", "부터", "à", "bis", "a", "até", "às", "alle", "tot", "до", "إلى", "الى", "ถึง", "sampai", "hingga", "đến", "ile"]
    private static let meetingRangePattern = meetingRangeSeparators.joined(separator: "|")
    private static let meetingRelativeDatePattern = smartPhrasePattern(Array(intervalDateOffsets.keys))
    private static let meetingZoneAliasPattern = smartPhrasePattern(Array(timeZoneAliases.keys))

    private static func meetingDraft(_ text: String, now: Date, timeZone: TimeZone) -> ClipboardCalendarDraft? {
        let locationPattern = #"(?i)(?:^|[\n，,；;]|\s)(?:"# + meetingLocationLabels + #")\h*[:：]\h*([^\n，；;]+)"#
        var parsingText = text.replacingOccurrences(of: #"https?://[^\s]+"#, with: "", options: .regularExpression)
        parsingText = parsingText.replacingOccurrences(of: locationPattern, with: "", options: .regularExpression)
        let meetingText = parsingText
        guard smartMatch("(?i)" + meetingKeywords, meetingText) != nil else { return nil }
        parsingText = parsingText.replacingOccurrences(
            of: #"(?im)^\h*(?:"# + meetingTitleLabels + #")\h*[:：][^\r\n]*"#, with: "", options: .regularExpression
        )
        let timePattern = #"(?i)(?<![0-9:：])(?:((?:"# + meetingPeriodPattern + #"))\h*)?([0-9]{1,2})(?:[:：]([0-9]{2})(?:[:：]([0-9]{2})(?:\.([0-9]{1,9}))?)?|点(?:([0-9]{1,2})分?|半)?)(?:\h*((?:"# + meetingPeriodPattern + #")))?(?![0-9:：])"#
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
        let suffixPattern = #"^[ \t]*(?:\([ \t]*)?((?i:Z)(?:[+-][^\s,，;；)\]]*)?|[+-][^\s,，;；)\]]+|(?i:"# + meetingZoneAliasPattern + "|" + abbreviations + #")|[A-Z]{2,5})(?![\p{L}0-9_])"#
        let suffixRegex = try! NSRegularExpression(pattern: suffixPattern)
        let prefixRegex = try! NSRegularExpression(pattern: #"(?:^|[ \t(])((?i:"# + meetingZoneAliasPattern + "|" + abbreviations + #")|[A-Z]{2,5})[ \t]*$"#)
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
                let end = parsingText.index(cursor, offsetBy: suffix[Range(match.range, in: suffix)!].count)
                let remainder = String(parsingText[end...].prefix { !$0.isNewline && !",，;；".contains($0) })
                    .trimmingCharacters(in: .whitespaces.union(CharacterSet(charactersIn: ")]")))
                if timeZoneAliases[candidate.lowercased()] != nil,
                   !timeZoneAliases.keys.contains(where: { alias in
                       alias.count < candidate.count
                           && smartMatch("(?i)" + smartPhrasePattern([alias]), candidate) != nil
                   }), !remainder.isEmpty,
                   suffixRegex.firstMatch(in: remainder, range: NSRange(remainder.startIndex..., in: remainder)) == nil,
                   smartMatch("^\\h*(?:" + meetingRangePattern + ")\\h*" + timePattern, remainder) == nil {
                    break
                }
                zoneTexts.append(candidate)
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
        let dateParsingText = parsingText.replacingOccurrences(of: timePattern, with: "", options: .regularExpression)
        let datePattern = #"(?i)(?:(?<![0-9:：])(?:[0-9]{4}[-年/.][0-9]{1,2}[-月/.][0-9]{1,2}日?|[0-9]{1,2}[月./-][0-9]{1,2}日?)(?![0-9:：])|"# + meetingRelativeDatePattern + ")"
        let dateRegex = try! NSRegularExpression(pattern: datePattern)
        let dateMatches = dateRegex.matches(in: dateParsingText, range: NSRange(dateParsingText.startIndex..., in: dateParsingText))
        // Multiple dates can describe alternatives, reschedules, or a cancellation.
        guard dateMatches.count == 1,
              smartMatch(meetingRejectionPattern, meetingText) == nil else { return nil }
        let dateValue = String(dateParsingText[Range(dateMatches[0].range, in: dateParsingText)!])
            .replacingOccurrences(of: #"(?<=[0-9])[年月/.]"#, with: "-", options: .regularExpression)
            .replacingOccurrences(of: #"(?<=[0-9])日$"#, with: "", options: .regularExpression)
        guard let day = intervalDate(dateValue, now: now, calendar: calendar) else { return nil }
        let timeMatches = timeRegex.matches(in: parsingText, range: NSRange(parsingText.startIndex..., in: parsingText))
        guard (1...2).contains(timeMatches.count) else { return nil }
        let timeValues = timeMatches.map { String(parsingText[Range($0.range, in: parsingText)!]) }
        let timeTokens = timeValues.map { smartMatch(timePattern, $0)! }
        for tokens in timeTokens {
            if let prefix = meetingPeriods[tokens[1].lowercased()], let suffix = meetingPeriods[tokens[7].lowercased()],
               prefix != suffix { return nil }
        }
        let commonPeriod = timeTokens.compactMap {
            meetingPeriods[$0[1].lowercased()] ?? meetingPeriods[$0[7].lowercased()]
        }.first
        var times: [Date] = []
        for (index, tokens) in timeTokens.enumerated() {
            var hour = Int(tokens[2])!
            let minute = Int(tokens[3].isEmpty ? tokens[6] : tokens[3]) ?? (timeValues[index].contains("半") ? 30 : 0)
            if let afternoon = meetingPeriods[tokens[1].lowercased()] ?? meetingPeriods[tokens[7].lowercased()] ?? commonPeriod {
                guard (1...12).contains(hour) else { return nil }
                if afternoon {
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
            guard meetingRangeSeparators.contains(between.lowercased()) else { return nil }
        }
        let location = smartMatch(locationPattern, text)?[1].trimmingCharacters(in: .whitespaces)
        let explicitTitle = smartMatch(#"(?im)^\h*(?:"# + meetingTitleLabels + #")\h*[:：]\h*([^\r\n]+)"#, text)?[1]
        var title = explicitTitle ?? text.components(separatedBy: .newlines).first!
        if explicitTitle == nil {
            title = title.replacingOccurrences(of: timePattern + #"(?:\h*(?:"# + meetingRangePattern + #")\h*"# + timePattern + ")?", with: "", options: .regularExpression)
                .replacingOccurrences(of: datePattern, with: "", options: .regularExpression)
                .replacingOccurrences(of: locationPattern, with: "", options: .regularExpression)
                .replacingOccurrences(of: #"(?i)^(?:"# + meetingDateLabels + #")\h*[:：]\h*"#, with: "", options: .regularExpression)
                .trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: ",，;；:：-–—~～至到")))
        }
        guard !title.isEmpty, title.count <= 160,
              smartMatch("(?i)" + meetingKeywords, title) != nil || explicitTitle != nil else { return nil }
        return ClipboardCalendarDraft(
            title: title, startDate: start, endDate: end, location: location, notes: text
        )
    }

    private static func smartPhrasePattern(_ phrases: [String]) -> String {
        phrases.sorted { $0.count > $1.count }.map { phrase in
            let pattern = NSRegularExpression.escapedPattern(for: phrase)
            let boundary = phrase.range(of: #"^[\p{Han}\p{Hiragana}\p{Katakana}\p{Thai}]+$"#, options: .regularExpression) != nil
                ? #"[\p{Latin}\p{Cyrillic}\p{Arabic}\p{Hangul}\p{M}]"# : #"[\p{L}\p{M}]"#
            return "(?<!" + boundary + ")" + pattern + "(?!" + boundary + ")"
        }.joined(separator: "|")
    }

    private static func smartMatch(_ pattern: String, _ text: String) -> [String]? {
        let expression = try! NSRegularExpression(pattern: pattern)
        guard let result = expression.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) else { return nil }
        return (0..<result.numberOfRanges).map {
            Range(result.range(at: $0), in: text).map { String(text[$0]) } ?? ""
        }
    }
}
