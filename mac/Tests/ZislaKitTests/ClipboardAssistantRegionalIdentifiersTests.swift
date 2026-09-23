import Foundation
import Testing
import ZislaCore
@testable import ZislaKit

struct ClipboardAssistantRegionalIdentifiersTests {
    struct Sample: Sendable {
        let language: AppLanguage
        let country: String
        let flightLabel: String
        let flight: String
        let trainLabel: String
        let train: String
        let trackingLabel: String
        let phoneLabel: String
        let phone: String
    }

    static let samples: [Sample] = [
        .init(language: .simplifiedChinese, country: "CN", flightLabel: "航班号", flight: "CA1234", trainLabel: "车次", train: "G123", trackingLabel: "运单号", phoneLabel: "电话", phone: "+8613800138000"),
        .init(language: .traditionalChinese, country: "TW", flightLabel: "航班號", flight: "BR0006", trainLabel: "車次", train: "台鐵 123", trackingLabel: "運單號", phoneLabel: "電話", phone: "+886912345678"),
        .init(language: .english, country: "US", flightLabel: "Flight no.", flight: "UA123", trainLabel: "Train", train: "Amtrak 171", trackingLabel: "Tracking number", phoneLabel: "Phone", phone: "+12015550123"),
        .init(language: .japanese, country: "JP", flightLabel: "便名", flight: "JL001", trainLabel: "列車番号", train: "のぞみ 001号", trackingLabel: "追跡番号", phoneLabel: "電話番号", phone: "+819012345678"),
        .init(language: .korean, country: "KR", flightLabel: "항공편", flight: "KE001", trainLabel: "열차 번호", train: "KTX 001", trackingLabel: "운송장 번호", phoneLabel: "전화번호", phone: "+821020000000"),
        .init(language: .french, country: "FR", flightLabel: "numéro de vol", flight: "AF0123", trainLabel: "numéro du train", train: "TGV 6123", trackingLabel: "numéro de suivi", phoneLabel: "téléphone", phone: "+33612345678"),
        .init(language: .german, country: "DE", flightLabel: "Flugnummer", flight: "LH0400", trainLabel: "Zugnummer", train: "ICE 123", trackingLabel: "Sendungsnummer", phoneLabel: "Telefonnummer", phone: "+4915123456789"),
        .init(language: .spanish, country: "ES", flightLabel: "número de vuelo", flight: "IB0123", trainLabel: "número de tren", train: "AVE 0311", trackingLabel: "número de seguimiento", phoneLabel: "teléfono", phone: "+34612345678"),
        .init(language: .brazilianPortuguese, country: "BR", flightLabel: "número do voo", flight: "AD0123", trainLabel: "número do trem", train: "123", trackingLabel: "código de rastreamento", phoneLabel: "telefone", phone: "+5511961234567"),
        .init(language: .italian, country: "IT", flightLabel: "numero del volo", flight: "AZ0123", trainLabel: "numero treno", train: "Frecciarossa 9615", trackingLabel: "numero di tracciamento", phoneLabel: "telefono", phone: "+393123456789"),
        .init(language: .dutch, country: "NL", flightLabel: "vluchtnummer", flight: "KL0123", trainLabel: "treinnummer", train: "NS 123", trackingLabel: "zendingsnummer", phoneLabel: "telefoonnummer", phone: "+31612345678"),
        .init(language: .russian, country: "RU", flightLabel: "номер рейса", flight: "SU0123", trainLabel: "номер поезда", train: "Сапсан 754А", trackingLabel: "трек-номер", phoneLabel: "телефон", phone: "+79123456789"),
        .init(language: .arabic, country: "SA", flightLabel: "رقم الرحلة", flight: "SV٠١٢٣", trainLabel: "رقم القطار", train: "١٢٣", trackingLabel: "رقم التتبع", phoneLabel: "رقم الهاتف", phone: "+966512345678"),
        .init(language: .thai, country: "TH", flightLabel: "หมายเลขเที่ยวบิน", flight: "TG0123", trainLabel: "ขบวนรถไฟที่", train: "9", trackingLabel: "เลขพัสดุ", phoneLabel: "เบอร์โทรศัพท์", phone: "+66812345678"),
        .init(language: .indonesian, country: "ID", flightLabel: "nomor penerbangan", flight: "GA0123", trainLabel: "nomor kereta api", train: "KA 1", trackingLabel: "nomor resi", phoneLabel: "nomor telepon", phone: "+62812345678"),
        .init(language: .vietnamese, country: "VN", flightLabel: "số hiệu chuyến bay", flight: "VN0123", trainLabel: "số hiệu tàu", train: "SE1", trackingLabel: "mã vận đơn", phoneLabel: "số điện thoại", phone: "+84912345678"),
        .init(language: .turkish, country: "TR", flightLabel: "uçuş numarası", flight: "PC0123", trainLabel: "tren numarası", train: "YHT 81201", trackingLabel: "kargo takip numarası", phoneLabel: "telefon numarası", phone: "+905012345678"),
    ]

    @Test func matrixMatchesEverySupportedLanguage() {
        #expect(Set(Self.samples.map(\.language)) == Set(AppLanguage.allCases))
        #expect(Self.samples.count == 17)
    }

    @Test(arguments: samples)
    func everyLanguageRecognizesExplicitLabels(_ sample: Sample) throws {
        for (label, number, kind) in [
            (sample.flightLabel, sample.flight, ClipboardAssistantKind.flight),
            (sample.trainLabel, sample.train, .train),
            (sample.trackingLabel, "123456789012", .tracking),
            (sample.phoneLabel, sample.phone, .phone),
        ] {
            let result = try #require(detect(label + ": " + number, sample: sample), "\(sample.language.rawValue): \(label)")
            #expect(result.kind == kind, "\(sample.language.rawValue): \(label)")
            if kind == .phone { #expect(result.action == .callPhone(sample.phone)) }
        }
    }

    @Test(arguments: samples)
    func labelWithoutAnIdentifierNeverOffersAnAction(_ sample: Sample) {
        for label in [sample.flightLabel, sample.trainLabel, sample.trackingLabel, sample.phoneLabel] {
            #expect(detect(label + ":", sample: sample, kinds: [.flight, .train, .tracking, .phone]) == nil)
        }
    }

    @Test(arguments: samples)
    func identifierSuffixesCannotInjectActions(_ sample: Sample) {
        for (label, number) in [(sample.flightLabel, sample.flight), (sample.trainLabel, sample.train),
                                (sample.trackingLabel, "123456789012"), (sample.phoneLabel, sample.phone)] {
            for suffix in ["&next=https://evil.example", "\u{202E}", "\n123", ";123", "\u{0}"] {
                #expect(detect(label + ": " + number + suffix, sample: sample,
                    kinds: [.flight, .train, .tracking, .phone]) == nil)
            }
        }
    }

    @Test func explicitInternationalPhonesMustNotBecomeSubtraction() {
        let result = ClipboardAssistantDetector.detect(text: "+86-138-0013-8000",
            enabledKinds: Set(ClipboardAssistantKind.allCases), now: Date(timeIntervalSince1970: 1_790_035_200),
            timeZone: TimeZone(secondsFromGMT: 0)!, locale: Locale(identifier: "en_US"))
        #expect(result?.kind == .phone)
        #expect(result?.action == .callPhone("+8613800138000"))
    }

    @Test(arguments: samples)
    func everyLanguageRejectsOutOfRangeAndZeroIdentifiers(_ sample: Sample) {
        for (label, number, kind) in [
            (sample.flightLabel, "UA0000", ClipboardAssistantKind.flight),
            (sample.flightLabel, "UA12345", .flight),
            (sample.trainLabel, "0", .train), (sample.trainLabel, "123456", .train),
            (sample.trackingLabel, "111111111111", .tracking),
            (sample.trackingLabel, String(repeating: "1234567890", count: 4), .tracking),
            (sample.phoneLabel, "+999123456789", .phone),
        ] {
            #expect(detect(label + ": " + number, sample: sample, kinds: [kind]) == nil)
        }
    }

    @Test(arguments: [
        ("BR", "EVA"), ("CI", "CAL"), ("TG", "THA"), ("FD", "AIQ"), ("GA", "GIA"), ("JT", "LNI"),
        ("QZ", "AWQ"), ("VN", "HVN"), ("VJ", "VJC"), ("SU", "AFL"), ("DP", "PBD"), ("AD", "AZU"),
        ("G3", "GLO"), ("AZ", "ITY"), ("PC", "PGT"), ("SV", "SVA"), ("XY", "KNE"), ("TP", "TAP"),
        ("JX", "SJX"), ("NX", "AMU"), ("JQ", "JST"), ("7C", "JJA"), ("HV", "TRA"),
    ])
    func majorRegionalAirlinesSupportIATAICAOAndLeadingZeros(_ iata: String, _ icao: String) throws {
        for (text, copied) in [(iata + "0001", iata + "0001"), (iata.lowercased() + "   0123", iata + "0123"),
                                (icao + " 0123", icao + "0123")] {
            let result = try #require(smart(text, country: "US"))
            #expect(result.kind == .flight)
            let expectedDigits = text.hasSuffix("0001") ? "1" : "123"
            #expect(result.actions.contains {
                if case .openService(.flightAware, let url) = $0 { return url.path == "/live/flight/" + icao + expectedDigits }
                return false
            })
            #expect(result.actions.contains(.copyText(copied)))
        }
        #expect(smart(iata + "0000", country: "US") == nil)
        #expect(smart(icao + "12345", country: "US", kinds: [.flight]) == nil)
    }

    @Test func flightsWithSharedOrUnknownICAOCodesUseANumberSearch() {
        #expect(smart("LA1234", country: "BR")?.action == .search("LA1234"))
        #expect(smart("Flight ZZZ0123", country: "US")?.action == .search("ZZZ0123"))
        #expect(smart("ZZZ0123", country: "US") == nil)
    }

    @Test(arguments: [
        ("のぞみ 1号", "JP"), ("新幹線 123", "JP"), ("THSR 0613", "TW"), ("台鐵 123", "TW"),
        ("KTX 101", "KR"), ("SRT 301", "KR"), ("AVE 03113", "ES"), ("Renfe 3131", "ES"),
        ("Frecciarossa 9615", "IT"), ("Eurostar 9014", "GB"), ("NS 1234", "NL"), ("CP 123", "PT"),
        ("Сапсан 754А", "RU"), ("SE1", "VN"), ("KA 1", "ID"), ("SAR 12", "SA"), ("YHT 81201", "TR"),
    ])
    func regionalRailOperatorsHaveQueriesContainingTheirNumber(_ text: String, _ country: String) throws {
        let result = try #require(smart(text, country: country))
        #expect(result.kind == .train)
        let number = text.filter(\.isNumber)
        if case .search(let query)? = result.action { #expect(query.contains(number)) }
        else { Issue.record("A railway without a verified deep link must expose a number search") }
        #expect(result.actions.contains { if case .copyText(let text) = $0 { return text.contains(number) }; return false })
        #expect(Set(result.actions.map(\.identifier)).count == result.actions.count)
    }

    @Test func explicitTransportLabelsAndLocalShapeResolveCollisions() {
        for (text, country, kind) in [
            ("FR9615", "IT", ClipboardAssistantKind.flight), ("FR 9615", "IT", .train),
            ("FR 9615", "GB", .flight), ("Flight FR 9615", "IT", .flight), ("Treno FR9615", "GB", .train),
            ("G5123", "CN", .train), ("G5 123", "CN", .flight), ("航班 G5123", "CN", .flight),
            ("车次 G5123", "US", .train), ("G3123", "CN", .train), ("G3123", "BR", .flight),
        ] {
            #expect(smart(text, country: country)?.kind == kind, "\(country): \(text)")
        }
    }

    @Test func chineseNumericTrainsAndLeadingZerosUseCanonicalQueries() throws {
        for (text, expected, copied) in [("车次 1461", "1461", "1461"), ("G0001", "G1", "G0001")] {
            let result = try #require(smart(text, country: "CN"))
            #expect(result.kind == .train)
            #expect(result.actions.contains(.copyText(copied)))
            #expect(result.actions.contains {
                if case .openService(.railway12306, let url) = $0 {
                    return URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?
                        .first { $0.name == "station_train_code" }?.value == expected
                }
                return false
            })
        }
        #expect(smart("1461", country: "CN", kinds: [.train]) == nil)
        #expect(smart("AVE 03113", country: "ES")?.action == .search("Renfe AVE 03113"))
    }

    @Test func trainSuffixesRequireRussianContextAndChineseCodesStopAtFourDigits() {
        for text in ["G123A", "ICE 123A", "TGV 6123А", "车次 G12345", "车次 K12345"] {
            #expect(smart(text, country: "CN", kinds: [.train]) == nil, "\(text)")
        }
        #expect(smart("Train 754А", country: "US", kinds: [.train]) == nil)
        #expect(smart("Поезд 754А", country: "RU", kinds: [.train])?.actions.contains(.copyText("754А")) == true)
        #expect(smart("Сапсан 754А", country: "US", kinds: [.train])?.actions.contains(.copyText("САПСАН 754А")) == true)
        #expect(smart("车次 G9999", country: "CN", kinds: [.train])?.kind == .train)
        #expect(smart("YHT 81201", country: "TR", kinds: [.train])?.kind == .train)
    }

    @Test(arguments: [("NL", "NS"), ("PT", "Comboios de Portugal"), ("IT", "Trenitalia"),
                      ("AT", "ÖBB"), ("CH", "SBB"), ("FR", "SNCF"), ("DE", "Deutsche Bahn")])
    func sharedIntercityPrefixesUseTheActualRegion(_ country: String, _ provider: String) {
        #expect(smart("IC 123", country: country)?.action == .search(provider + " IC 123"))
    }

    @Test(arguments: samples)
    func unidentifiedRailOperatorsKeepTheExplicitLocalQuery(_ sample: Sample) {
        let result = detect(sample.trainLabel + ": 123", sample: sample, kinds: [.train])
        #expect(result?.action == .search(sample.trainLabel + " 123"))
        #expect(result?.actions.contains(.copyText("123")) == true)
        #expect(smart("123", country: sample.country, kinds: [.train]) == nil)
    }

    @Test(arguments: [
        "顺丰", "黑貓宅急便", "Royal Mail", "ヤマト運輸", "CJ대한통운", "Colissimo", "DHL", "Correos",
        "Correios", "Poste Italiane", "PostNL", "СДЭК", "أرامكس", "ไปรษณีย์ไทย", "JNE", "Viettel Post", "PTT Kargo",
    ])
    func regionalCourierAliasesSupportGroupedNumbers(_ brand: String) throws {
        let result = try #require(smart(brand + " 1234 5678 9012", country: "US"))
        #expect(result.kind == .tracking)
        #expect(result.actions.contains(.copyText("123456789012")))
        #expect(result.actions.contains {
            if case .openService(.track17, let url) = $0 { return url.fragment == "nums=123456789012" }
            return false
        })
    }

    @Test func courierContextWorksInEitherOrderWithoutGuessingFromScript() throws {
        for text in ["DHL tracking number: 1234-5678-9012", "Tracking number: DHL 1234-5678-9012"] {
            #expect(smart(text, country: "US")?.kind == .tracking)
        }
        let japanese = try #require(smart("日本郵便 123456789012", country: "US"))
        #expect(japanese.actions.first.map {
            if case .openService(.track17, _) = $0 { return true }; return false
        } == true)
        #expect(japanese.actions.contains { if case .openService(.kuaidi100, _) = $0 { return true }; return false } == false)
    }

    @Test func trackingContextCannotBypassInputBudgetOrLineBoundaries() {
        for text in ["Tracking:" + String(repeating: " ", count: 257) + "123456789012",
                     "Tracking\nnumber: 123456789012", "DHL\n123456789012"] {
            #expect(ClipboardAssistantDetector.detect(text: text, enabledKinds: [.tracking], countryCode: "US") == nil)
        }
    }

    @Test(arguments: ["RA123456785US", "CP123456785BR", "LX123456785FR", "EE123456785JP", "UA123456785CN", "VA123456785DE", "MA123456785IT", "RA000000080GB", "RA000000005GB"])
    func postalS10NumbersKeepChecksumAndIssuingRegion(_ number: String) {
        #expect(smart(number, country: "US")?.kind == .tracking)
        #expect(smart("Tracking: " + number, country: "US")?.kind == .tracking)
        let invalid = String(number.prefix(10)) + "9" + number.suffix(2)
        #expect(smart(invalid, country: "US") == nil)
        #expect(smart("Tracking: " + invalid, country: "US") == nil)
        #expect(smart(String(number.prefix(11)) + "ZZ", country: "US") == nil)
    }

    @Test func groupedAndUnicodeIdentifiersPreserveCopySemantics() throws {
        #expect(smart("RA 123 456 785 GB", country: "US")?.actions.contains(.copyText("RA123456785GB")) == true)
        let flight = try #require(smart("航班：CA１２３４", country: "CN"))
        #expect(flight.title == "CA1234")
        #expect(flight.actions.contains(.copyText("CA１２３４")))
        let train = try #require(smart("G１２３", country: "CN"))
        #expect(train.title == "G123")
        #expect(train.actions.contains(.copyText("G１２３")))
        let parcel = try #require(smart("رقم التتبع: ١٢٣٤٥٦٧٨٩٠١٢", country: "SA"))
        #expect(parcel.title == "123456789012")
        #expect(parcel.actions.contains(.copyText("١٢٣٤٥٦٧٨٩٠١٢")))
    }

    @Test(arguments: samples)
    func disablingEachKindRemovesItsActions(_ sample: Sample) {
        for (label, number, kind) in [(sample.flightLabel, sample.flight, ClipboardAssistantKind.flight),
                                     (sample.trainLabel, sample.train, .train),
                                     (sample.trackingLabel, "123456789012", .tracking),
                                     (sample.phoneLabel, sample.phone, .phone)] {
            let result = detect(label + ": " + number, sample: sample,
                kinds: Set([ClipboardAssistantKind.flight, .train, .tracking, .phone]).subtracting([kind]))
            #expect(result == nil)
        }
    }

    private func smart(_ text: String, country: String, kinds: Set<ClipboardAssistantKind> = [.flight, .train, .tracking]) -> ClipboardAssistantDetection? {
        ClipboardAssistantDetector.smartActionDetection(text, enabledKinds: kinds, countryCode: country,
            now: Date(timeIntervalSince1970: 1_790_035_200), timeZone: TimeZone(secondsFromGMT: 0)!)
    }

    private func detect(_ text: String, sample: Sample, kinds: Set<ClipboardAssistantKind>? = nil) -> ClipboardAssistantDetection? {
        ClipboardAssistantDetector.detect(text: text, enabledKinds: kinds ?? Set(ClipboardAssistantKind.allCases),
            systemLanguageIdentifier: "en", now: Date(timeIntervalSince1970: 1_790_035_200),
            timeZone: TimeZone(secondsFromGMT: 0)!, locale: sample.language.locale, countryCode: sample.country)
    }
}
