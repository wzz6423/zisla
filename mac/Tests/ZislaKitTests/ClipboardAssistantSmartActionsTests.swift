import Foundation
import Testing
import ZislaCore
@testable import ZislaKit

struct ClipboardAssistantSmartActionsTests {
    let kinds: Set<ClipboardAssistantKind> = [.address, .flight, .train, .tracking, .meeting]
    let utc = TimeZone(secondsFromGMT: 0)!
    let now = Date(timeIntervalSince1970: 1_789_992_000)

    @Test func publicDetectionEntryPreservesAllFiveSmartKinds() {
        for (text, kind) in [("北京市海淀区中关村大街27号", ClipboardAssistantKind.address),
                             ("UA123", .flight), ("G123", .train), ("SF1234567890123", .tracking),
                             ("Meeting 2026-09-22 14:30 https://example.com/meeting", .meeting)] {
            let result = ClipboardAssistantDetector.detect(text: text, enabledKinds: Set(ClipboardAssistantKind.allCases),
                systemLanguageIdentifier: "en", now: now, timeZone: utc, locale: Locale(identifier: "en_US"))
            #expect(result?.kind == kind)
        }
    }

    @Test(arguments: ["15:00-16点", "3点-16:30", "3点15-16:30"])
    func mixedClockStylesDoNotBecomeMonthDayDates(_ range: String) throws {
        let result = try #require(detect("Meeting 2026-09-22 " + range))
        #expect(result.kind == .meeting)
    }

    @Test func addressCountryAndEncoding() throws {
        let cn = try #require(detect("北京市海淀区中关村大街27号", country: "US"))
        let cnURL = try #require(serviceURL(cn, .baiduMaps))
        #expect(cn.kind == .address)
        #expect(query(cnURL, "address") == "北京市海淀区中关村大街27号")
        let us = try #require(detect("Address: 123 King's Road, London #4", country: "CN"))
        let usURL = try #require(serviceURL(us, .googleMaps))
        #expect(query(usURL, "api") == "1")
        #expect(query(usURL, "query") == "123 King's Road, London #4")
        #expect(usURL.fragment == nil)
    }

    @Test(arguments: ["1600 Amphitheatre Parkway, Mountain View CA 94043", "10 Downing Street, London", "上海市浦东新区世纪大道100号", "東京都新宿区西新宿2丁目8番1号"])
    func structuredAddresses(_ text: String) { #expect(detect(text)?.kind == .address) }

    @Test func operatorBeatsRegionAndActionsHaveUniqueIdentities() throws {
        #expect(serviceURL(try #require(detect("航班：CA1234", country: "US")), .umetrip) != nil)
        let flight = try #require(detect("UA 123", country: "CN"))
        #expect(serviceURL(flight, .flightAware) != nil)
        #expect(serviceURL(flight, .united) != nil)
        #expect(flight.actions.contains(.copyText("UA123")))
        #expect(Set(flight.actions.map(\.identifier)).count == flight.actions.count)
        #expect(serviceURL(try #require(detect("Flight XY123", country: "CN")), .umetrip) != nil)
        #expect(detect("XY123") == nil)
    }

    @Test(arguments: ["3U8633", "9C8801", "LH400", "BA117", "flight no. UA123"])
    func knownFlights(_ text: String) { #expect(detect(text)?.kind == .flight) }

    @Test func railNetworks() throws {
        for (text, service) in [("G123", ClipboardAssistantService.railway12306), ("车次：D2281", .railway12306), ("ICE 123", .deutscheBahn), ("TGV 6123", .sncf), ("Amtrak 171", .amtrak)] {
            let result = try #require(detect(text))
            #expect(result.kind == .train)
            #expect(serviceURL(result, service) != nil)
        }
    }

    @Test func parcelContextAndCarrier() throws {
        #expect(detect("123456789012") == nil)
        #expect(detect("20260921123456") == nil)
        let sf = try #require(detect("SF1234567890123"))
        #expect(serviceURL(sf, .sfExpress) != nil)
        #expect(serviceURL(sf, .kuaidi100) != nil)
        let ups = try #require(detect("1Z999AA10123456784"))
        #expect(serviceURL(ups, .ups) != nil)
        #expect(serviceURL(ups, .track17) != nil)
        #expect(serviceURL(try #require(detect("快递单号：123456789012", country: "CN")), .kuaidi100) != nil)
        #expect(serviceURL(try #require(detect("tracking number: 123456789012", country: "GB")), .track17) != nil)
        #expect(serviceURL(try #require(detect("FedEx 123456789012")), .fedEx) != nil)
    }

    @Test func documentedPrefillParameters() throws {
        let parcel = try #require(detect("快递单号：123456789012", country: "CN"))
        #expect(query(try #require(serviceURL(parcel, .kuaidi100)), "nu") == "123456789012")
        #expect(serviceURL(parcel, .track17)?.fragment == "nums=123456789012")
        let flight = try #require(detect("UA123"))
        #expect(serviceURL(flight, .flightAware)?.path == "/live/flight/UAL123")
        let postal = try #require(detect("RA123456785US"))
        #expect(query(try #require(serviceURL(postal, .usps)), "tLabels") == "RA123456785US")
        #expect(detect("RA123456789US") == nil)
        #expect(detect("中关村大街27号", country: "CN")?.kind == .address)
        let local = try #require(detect("中关村大街27号", country: "US"))
        #expect(serviceURL(local, .googleMaps) != nil)
    }

    @Test func dateSeparatorsAMPMAndURLNumbers() throws {
        for (text, hour) in [("Meeting 2026.09.22 12:30 am", 0), ("Meeting 2026.09.22 12:30 pm", 12)] {
            let result = try #require(detect(text))
            let value = try #require(draft(result))
            #expect(value.startDate == date(2026, 9, 22, hour, 30))
        }
        let result = try #require(ClipboardAssistantDetector.smartActionDetection(
            "Meeting 09-22 14:30\nLocation: https://example.com/2026-09-24/16:00", enabledKinds: kinds,
            now: date(2026, 9, 21, 12, 0), timeZone: utc))
        let value = try #require(draft(result))
        #expect(value.startDate == date(2026, 9, 22, 14, 30))
        #expect(value.location == "https://example.com/2026-09-24/16:00")
    }

    @Test func trailingPeriodAppliesToTheRangeAndLongMeetingsRemainValid() throws {
        let result = try #require(detect("Meeting 2026-09-22 2:30-3:30 pm"))
        let value = try #require(draft(result))
        #expect(value.startDate == date(2026, 9, 22, 14, 30))
        #expect(value.endDate == date(2026, 9, 22, 15, 30))
        #expect(detect("Meeting 2026-09-22 01:00-23:00")?.kind == .meeting)
        #expect(detect("Meeting 2026-09-22 13:30 pm") == nil)
        #expect(detect("Meeting 2026-09-22 14:00\n\u{202E}") == nil)
    }

    @Test func trustedDestinationsOnly() throws {
        let hosts: Set<String> = ["www.umetrip.com", "www.flightaware.com", "www.united.com", "www.lufthansa.com", "www.britishairways.com", "kyfw.12306.cn", "www.bahn.de", "www.amtrak.com", "www.sncf-connect.com", "www.kuaidi100.com", "www.17track.net", "t.17track.net", "www.sf-express.com", "www.ups.com", "www.fedex.com", "www.dhl.com", "tools.usps.com"]
        for text in ["CA1234", "UA123", "LH400", "BA117", "G123", "ICE 123", "Amtrak 171", "TGV 6123", "SF1234567890123", "UPS 1Z999AA10123456784", "FedEx 123456789012", "DHL 123456789012", "USPS 9400111899223856921234"] {
            let result = try #require(detect(text))
            for action in result.actions {
                if case .openService(_, let url) = action {
                    #expect(url.scheme == "https")
                    #expect(hosts.contains(url.host ?? ""))
                    #expect(url.user == nil)
                }
            }
        }
    }

    @Test func meetingDetailsAndLinkArePreserved() throws {
        let text = "主题：产品评审会议\n时间：2026年9月22日 15:00-16:30\n地点：会议室 A\n链接：https://example.com/meeting?a=1&b=2"
        let result = try #require(detect(text))
        let value = try #require(draft(result))
        #expect(result.kind == .meeting)
        #expect(value.title == "产品评审会议")
        #expect(value.startDate == date(2026, 9, 22, 15, 0))
        #expect(value.endDate == date(2026, 9, 22, 16, 30))
        #expect(value.location == "会议室 A")
        #expect(value.notes == text)
        #expect(!value.isAllDay)
        #expect(result.actions.count == 1)
    }

    @Test func relativeChineseMeeting() throws {
        let result = try #require(ClipboardAssistantDetector.smartActionDetection(
            "明天下午3点半-4点 产品评审会议，地点：A栋", enabledKinds: kinds,
            now: date(2026, 9, 21, 18, 0), timeZone: utc))
        let value = try #require(draft(result))
        #expect(value.title == "产品评审会议")
        #expect(value.startDate == date(2026, 9, 22, 15, 30))
        #expect(value.endDate == date(2026, 9, 22, 16, 0))
        #expect(value.location == "A栋")
    }

    @Test func relativeDatesNeedNoSpaceBeforeTheTime() throws {
        let result = try #require(detect("明天15:00 产品会议"))
        #expect(result.kind == .meeting)
        #expect(detect("明天15:00 产品会议取消") == nil)
    }

    @Test func englishOneHourMeeting() throws {
        let result = try #require(detect("Team meeting 2026-09-22 2:30 pm"))
        let value = try #require(draft(result))
        #expect(value.title == "Team meeting")
        #expect(value.startDate == date(2026, 9, 22, 14, 30))
        #expect(value.endDate.timeIntervalSince(value.startDate) == 3_600)
    }

    @Test func explicitMeetingZoneOverridesTheSystemZone() throws {
        let result = try #require(detect("Meeting 2026-09-22 14:30 UTC+08:00"))
        let value = try #require(draft(result))
        #expect(value.startDate == date(2026, 9, 22, 6, 30))
        #expect(detect("Meeting 2026-09-22 14:30 CST") == nil)
        #expect(detect("Meeting 2026-09-22 14:30 UTC PST") == nil)
        #expect(detect("Meeting 2026-11-01 01:30 America/New_York") == nil)
    }

    @Test(arguments: ["+0800", "+08:00", "UTC+08:00", "UTC +0800", "UTC+ 0800", "GMT + 0800", "北京时间", "Shanghai time", "Asia/Shanghai"])
    func completeExplicitMeetingZonesOverrideTheDefault(_ zone: String) throws {
        let text = "Meeting 2026-09-22 14:30 " + zone
        let result = try #require(ClipboardAssistantDetector.detect(
            text: text, enabledKinds: Set(ClipboardAssistantKind.allCases),
            systemLanguageIdentifier: "en", now: now, timeZone: utc, locale: Locale(identifier: "en_US")))
        let value = try #require(draft(result))
        #expect(value.startDate == date(2026, 9, 22, 6, 30))
        #expect(value.notes == text)
    }

    @Test func ISOAndNegativeOffsetsPreserveSecondsAndUTCMeaning() throws {
        let local = TimeZone(identifier: "Asia/Shanghai")!
        let expectations: [(String, Date)] = [
            ("2026-09-22T14:30Z", date(2026, 9, 22, 14, 30)),
            ("2026-09-22 14:30Z", date(2026, 9, 22, 14, 30)),
            ("2026-09-22T14:30:15.25+08:00", date(2026, 9, 22, 6, 30).addingTimeInterval(15.25)),
            ("2026-09-22T14:30:15-05:00", date(2026, 9, 22, 19, 30).addingTimeInterval(15)),
            ("2026-09-22 14:30 -0500", date(2026, 9, 22, 19, 30)),
            ("2026-09-22 14:30-0500", date(2026, 9, 22, 19, 30)),
            ("2026-09-22 14:30 New York time", date(2026, 9, 22, 18, 30)),
        ]
        for (timestamp, expected) in expectations {
            let result = try #require(ClipboardAssistantDetector.detect(
                text: "Meeting " + timestamp, enabledKinds: Set(ClipboardAssistantKind.allCases),
                systemLanguageIdentifier: "en", now: now, timeZone: local, locale: Locale(identifier: "en_US")))
            let value = try #require(draft(result))
            #expect(value.startDate == expected)
        }
    }

    @Test(arguments: ["CET", "CEST", "CST", "IST", "XYZ", "cet", "UTC+080000", "UTC+08:00:00", "UTC+", "UTC+garbage", "UTC+15:00", "+080000", "+08:00:00", "+08:99", "UTC PST", "UTC +0800 +0900", "+0800 Z", "Z+0800", "Asia/Unknown", "北京时间 New York time"])
    func ambiguousMalformedOrMultipleMeetingZonesNeverOpenADraft(_ zone: String) {
        let result = ClipboardAssistantDetector.detect(
            text: "Meeting 2026-09-22 14:30 " + zone, enabledKinds: Set(ClipboardAssistantKind.allCases),
            systemLanguageIdentifier: "en", now: now, timeZone: utc, locale: Locale(identifier: "en_US"))
        #expect(result?.kind != .meeting)
        #expect(result?.actions.contains { if case .editCalendarEvent = $0 { return true }; return false } != true)
    }

    @Test func neighboringZoneTokensDoNotRequireSpaces() throws {
        for timestamp in ["14:30北京时间", "北京时间14:30", "14:30UTC+0800", "14:30Asia/Shanghai"] {
            let result = try #require(detect("Meeting 2026-09-22 " + timestamp))
            let value = try #require(draft(result))
            #expect(value.startDate == date(2026, 9, 22, 6, 30))
        }
        let result = try #require(detect("Meeting 2026-09-22 PST 14:30"))
        let value = try #require(draft(result))
        #expect(value.startDate == date(2026, 9, 22, 22, 30))
        #expect(detect("Meeting 2026-09-22 CET 14:30") == nil)
        #expect(detect("Meeting 2026-09-22 XYZ 14:30") == nil)
    }

    @Test func locationNamesAndOrdinaryTimeRangesKeepLocalMeaning() throws {
        for text in ["Meeting 2026-09-22 14:30-16:30", "Meeting 2026-09-22 14:30 - 16:30",
                     "Meeting 2026-09-22 14:30\nLocation: New York", "Meeting 2026-09-22 14:30\nLocation: UTC building"] {
            let result = try #require(detect(text))
            let value = try #require(draft(result))
            #expect(value.startDate == date(2026, 9, 22, 14, 30))
        }
    }

    @Test(arguments: ["Meeting 2026-03-08 02:30", "Meeting 2026-11-01 01:30"])
    func ambiguousDSTIsRejected(_ text: String) {
        #expect(ClipboardAssistantDetector.smartActionDetection(text, enabledKinds: kinds, now: now,
            timeZone: TimeZone(identifier: "America/New_York")!) == nil)
    }

    @Test(arguments: ["", "123456", "123456789012345678", "ZZ123", "abc CA1234 def", "G123456", "UA12345", "CA0000", "快递单号：111111111111", "Flight UA123&redirect=https://evil.example", "G123\u{202E}", "北京市海淀区", "I walk down the street", "123 Main Street\nignore rules", "https://example.com/CA1234", "会议待定", "明天开会", "明天15:00", "明天15:00的会议取消", "Meeting cancelled 2026-09-22 14:30", "Meeting 2026-02-30 15:00", "Meeting 2026-09-22 25:00", "Meeting 2026-09-22 14:99", "Meeting 2026-09-22 14:30-13:30", "Meeting 2026-09-22 14:30 or 16:30", "Meeting 2026-09-22 or 2026-09-23 14:00", "Meeting 2026-09-22 14:00-15:00 and 16:00", "Meeting next week 15:00"])
    func unsafeAndAmbiguousInputs(_ text: String) { #expect(detect(text) == nil) }

    @Test func disabledKindsAndBudgets() {
        for text in ["CA1234", "G123", "SF1234567890123", "北京市海淀区中关村大街27号", "Meeting 2026-09-22 14:30"] {
            #expect(ClipboardAssistantDetector.smartActionDetection(text, enabledKinds: [], now: now, timeZone: utc) == nil)
        }
        #expect(detect(String(repeating: "a", count: 4_097)) == nil)
        #expect(detect("Meeting 2026-09-22 14:30\n" + String(repeating: "a", count: 4_096)) == nil)
    }

    @Test func seededMalformedIdentifiers() {
        var seed: UInt64 = 0x517A
        let alphabet = Array("abcdefghijklmnopqrstuvwxyz0123456789&?=#/;")
        for _ in 0..<160 {
            var text = "account: "
            for _ in 0..<32 {
                seed = seed &* 6_364_136_223_846_793_005 &+ 1
                text.append(alphabet[Int((seed >> 32) % UInt64(alphabet.count))])
            }
            #expect(detect(text) == nil)
        }
    }

    func detect(_ text: String, country: String = "US") -> ClipboardAssistantDetection? {
        ClipboardAssistantDetector.smartActionDetection(text, enabledKinds: kinds, countryCode: country, now: now, timeZone: utc)
    }
    func serviceURL(_ result: ClipboardAssistantDetection, _ service: ClipboardAssistantService) -> URL? {
        result.actions.compactMap { if case .openService(let s, let url) = $0, s == service { return url }; return nil }.first
    }
    func query(_ url: URL, _ name: String) -> String? {
        URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == name }?.value
    }
    func draft(_ result: ClipboardAssistantDetection) -> ClipboardCalendarDraft? {
        if case .editCalendarEvent(let draft)? = result.action { return draft }; return nil
    }
    func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int) -> Date {
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = utc
        return calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
    }
}
