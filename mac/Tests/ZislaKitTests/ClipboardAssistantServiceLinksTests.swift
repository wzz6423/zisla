import Foundation
import Testing
import ZislaCore
@testable import ZislaKit

struct ClipboardAssistantServiceLinksTests {
    let now = Date(timeIntervalSince1970: 1_790_006_400)

    @Test func baiduUsesTheDocumentedKeywordSearch() throws {
        let address = "北京市海淀区中关村大街27号"
        let result = try #require(detect(address))
        let url = try #require(serviceURL(result, .baiduMaps))
        #expect(url.host == "api.map.baidu.com")
        #expect(url.path == "/place/search")
        #expect(query(url, "query") == address)
        #expect(query(url, "region") == "全国")
        #expect(query(url, "output") == "html")
        #expect(query(url, "src") == "webapp.zisla.clipboard")
        #expect(url.fragment == nil)
    }

    @Test func railwayActionRetainsNumberAndChinaCalendarDate() throws {
        let result = try #require(detect("车次：G123"))
        let url = try #require(serviceURL(result, .railway12306))
        #expect(query(url, "station_train_code") == "G123")
        #expect(query(url, "date") == "2026-09-22")
        #expect(query(url, "train_no") == nil)
        #expect(result.actions.contains(.copyText("G123")))
    }

    @Test func umetripRetainsTheVerifiedPrefillParameter() throws {
        let result = try #require(detect("航班：CA1234"))
        let url = try #require(serviceURL(result, .umetrip))
        #expect(url.path == "/weixin/aliPay/flightSearch.html")
        #expect(query(url, "flightNo") == "CA1234")
        #expect(result.actions.contains(.copyText("CA1234")))
    }

    @Test func knownFlightIdentifiersOpenStatusPagesAndUnknownOnesSearch() throws {
        for (number, identifier) in [("CA1234", "CCA1234"), ("MU5101", "CES5101"), ("CZ3101", "CSN3101"),
                                     ("UA123", "UAL123")] {
            let result = try #require(detect(number))
            let url = try #require(serviceURL(result, .flightAware))
            #expect(result.actions.first == .openService(service: .flightAware, url: url))
            #expect(url.path == "/live/flight/" + identifier)
        }
        let unknown = try #require(detect("flight ZZ123"))
        #expect(unknown.actions.first == .search("ZZ123"))
        #expect(serviceURL(unknown, .flightAware) == nil)
    }

    @Test func railwayDateChangesAtMidnightInChina() throws {
        for (instant, expected) in [(now.addingTimeInterval(-1), "2026-09-21"), (now, "2026-09-22")] {
            let result = try #require(ClipboardAssistantDetector.smartActionDetection("D2281", enabledKinds: [.train],
                countryCode: "US", now: instant, timeZone: TimeZone(identifier: "America/Los_Angeles")!))
            let url = try #require(serviceURL(result, .railway12306))
            #expect(query(url, "date") == expected)
        }
    }

    @Test func dbSecondaryActionSubmitsTheOfficialTrainForm() throws {
        let result = try #require(detect("ICE 123"))
        let url = try #require(serviceURL(result, .deutscheBahn))
        #expect(url.host == "kursbuch.bahn.de")
        #expect(url.path == "/hafas/kbview.exe/dn")
        #expect(query(url, "train_nr") == "ICE 123")
        #expect(query(url, "searchmode") == "train")
        #expect(query(url, "mainframe") == "result")
        #expect(query(url, "orig") == "sZ")
        #expect(query(url, "dosearch") == "1")
    }

    @Test func unsupportedRailDeepLinksOfferAnExplicitNumberSearch() throws {
        for (text, expected) in [("ICE 123", "Deutsche Bahn ICE 123"), ("TGV 6123", "SNCF TGV 6123"),
                                 ("Amtrak 171", "AMTRAK 171")] {
            let result = try #require(detect(text))
            #expect(result.actions.first == .search(expected))
        }
    }

    @Test func legacyDefaultsPromoteSearchWithoutOverwritingCustomPriorities() {
        let oldDefault: [ClipboardAssistantActionKind] = [.openURL, .copyText, .addToQuickNote, .share]
        let migrated = ClipboardAssistantActionOrder.normalized([.flight: oldDefault, .train: oldDefault])
        #expect(migrated[.train]?.first == .search)
        #expect(migrated[.flight]?.first == .search)
        let custom: [ClipboardAssistantActionKind] = [.copyText, .openURL, .addToQuickNote, .share]
        let preserved = ClipboardAssistantActionOrder.normalized([.flight: custom, .train: custom])
        #expect(preserved[.train]?.first == .copyText)
        #expect(preserved[.flight]?.first == .copyText)
    }

    @Test func invalidIdentifierSuffixesCannotBecomeURLParameters() {
        var seed: UInt64 = 0x12306
        for _ in 0..<64 {
            seed = seed &* 6_364_136_223_846_793_005 &+ 1
            let number = String(seed % 9_999 + 1)
            for text in ["CA\(number)&flightNo=evil", "G\(number)?date=2000-01-01", "ICE \(number)#evil", "TGV \(number)/../evil"] {
                let result = ClipboardAssistantDetector.smartActionDetection(text, enabledKinds: [.flight, .train],
                    countryCode: "CN", now: now, timeZone: TimeZone(secondsFromGMT: 0)!)
                #expect(result == nil, "编号后的URL控制字符必须拒绝：\(text)")
            }
        }
        #expect(detect("") == nil)
        #expect(detect("G0") == nil)
        #expect(detect("CA12☃34") == nil)
    }

    private func detect(_ text: String) -> ClipboardAssistantDetection? {
        ClipboardAssistantDetector.smartActionDetection(text, enabledKinds: [.address, .flight, .train],
            countryCode: "CN", now: now, timeZone: TimeZone(secondsFromGMT: 0)!)
    }

    private func serviceURL(_ result: ClipboardAssistantDetection, _ service: ClipboardAssistantService) -> URL? {
        result.actions.compactMap { if case .openService(let candidate, let url) = $0, candidate == service { return url }; return nil }.first
    }

    private func query(_ url: URL, _ name: String) -> String? {
        URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == name }?.value
    }
}
