import Foundation
import Testing
import ZislaCore
@testable import ZislaKit

struct ClipboardAssistantNumericActionsTests {
    private let allKinds = Set(ClipboardAssistantKind.allCases)
    private let utc = TimeZone(secondsFromGMT: 0)!
    private let now = Date(timeIntervalSince1970: 1_790_035_200)

    @Test
    func publicEntryOffersTrackingBeforeBroadPhoneFallback() throws {
        let number = "123456789012"
        let detection = try #require(detect(number))
        #expect(detection.kind == .tracking)
        #expect(detection.title == number)
        #expect(detection.action?.kind == .openURL)
        #expect(detection.actions.contains(.copyText(number)))

        let contentDetection = try #require(ClipboardAssistantDetector.detect(
            content: .text(number), enabledKinds: allKinds
        ))
        #expect(contentDetection.kind == .tracking)
        #expect(contentDetection.actions.contains(.copyText(number)))
    }

    @Test(arguments: [
        "001234567890", "123456789012", "123456789012345678",
        "9007199254740993", "000123456789012345678901", "123456789012345678901234",
    ])
    func trackingAndCopyPreserveEveryOriginalDigit(_ number: String) throws {
        let detection = try #require(detect(" \n" + number + "\t "))
        #expect(detection.kind == .tracking)
        #expect(detection.title == number)
        #expect(detection.actions.contains(.copyText(number)))
        #expect(Set(detection.actions.map(\.identifier)).count == detection.actions.count)

        let services = detection.actions.compactMap { action -> (ClipboardAssistantService, URL)? in
            if case .openService(let service, let url) = action { return (service, url) }
            return nil
        }
        #expect(!services.isEmpty)
        for (service, url) in services {
            #expect(url.scheme == "https")
            #expect(url.user == nil && url.password == nil)
            switch service {
            case .kuaidi100:
                #expect(url.host == "www.kuaidi100.com")
                #expect(URLComponents(url: url, resolvingAgainstBaseURL: false)?
                    .queryItems?.first { $0.name == "nu" }?.value == number)
            case .track17:
                #expect(url.host == "t.17track.net")
                #expect(url.fragment == "nums=" + number)
            default:
                Issue.record("A bare number must not claim a carrier: \(service)")
            }
        }
    }

    @Test
    func trackingToggleRetainsOriginalFallbackActions() throws {
        let number = "123456789012"
        let withoutTracking = allKinds.subtracting([.tracking])
        let fallback = try #require(detect(number, kinds: withoutTracking))
        #expect(fallback.kind != .tracking)
        #expect(fallback.title == number)
        #expect(fallback.actions.contains { if case .openService = $0 { return true }; return false } == false)

        let text = try #require(detect(number, kinds: [.math, .text]))
        #expect(text.kind == .text)
        #expect(text.actions.contains(.search(number)))
        #expect(detect(number, kinds: []) == nil)
        #expect(detect(number, kinds: [.tracking])?.kind == .tracking)
    }

    @Test(arguments: [
        ("+8613800138000", "+8613800138000"), ("+86 138 0013 8000", "+8613800138000"),
        ("13800138000", "+8613800138000"), ("020 8123 4567", "+862081234567"),
    ])
    func explicitAndLocalPhoneNumbersUseTheRegionCallingCode(_ number: String, _ expected: String) throws {
        let detection = try #require(detect(number))
        #expect(detection.kind == .phone)
        #expect(detection.actions == [.callPhone(expected)])
    }

    @Test(arguments: ["１２３４５６７８９０１２", "١٢٣٤٥٦٧٨٩٠١٢"])
    func unicodeDigitsNormalizeQueriesAndPreserveCopiedText(_ number: String) throws {
        let detection = try #require(detect(number))
        #expect(detection.kind == .tracking)
        #expect(detection.title == "123456789012")
        #expect(detection.actions.contains(.copyText(number)))
        #expect(detection.actions.contains {
            if case .openService(.track17, let url) = $0 { return url.fragment == "nums=123456789012" }
            return false
        })
    }

    @Test(arguments: [
        "2026-09-22", "2026.09.22", "14:30", "1790035200", "1790035200000",
        "1790035200000000", "1790035200000000000", "timestamp: 1790035200000",
    ])
    func datesAndUnixTimestampsKeepCalendarPriority(_ value: String) throws {
        let detection = try #require(detect(value))
        #expect(detection.kind == .dateTime)
        #expect(detection.action?.kind == .createCalendarEvent)
        #expect(detection.actions.allSatisfy { $0.kind != .openURL })
    }

    @Test(arguments: [
        ("10-3", "7"), ("123456789012 + 1", "123456789013"),
        ("1 + 2 =", "3"), ("2 ** 3", "8"),
    ])
    func arithmeticStillOffersBothCopyActions(_ expression: String, result: String) throws {
        let detection = try #require(detect(expression))
        #expect(detection.kind == .math)
        #expect(detection.action == .copyText(result))
        #expect(detection.secondaryActions.first?.kind == .copyFullExpression)
        #expect(detection.actions.allSatisfy { $0.kind != .openURL })
    }

    @Test(arguments: [
        "", "123456", "12345678901", "1234567890123456789012345", "000000000000",
        "111111111111",
        "123456789012?redirect=https://evil.example", "123456789012\u{202E}",
        "123456\u{0}789012", "123456\n789012", "123456a789012", "123456789012.0", "123456789012=",
    ])
    func malformedOrOutOfBudgetNumbersNeverOfferTracking(_ value: String) {
        let detection = detect(value)
        #expect(detection?.kind != .tracking)
        #expect(detection?.actions.contains { if case .openService = $0 { return true }; return false } != true)
    }

    @Test(arguments: [ClipboardAssistantActionKind.copyText, .addToQuickNote, .share])
    @MainActor
    func existingActionPreferenceSurvivesStoreReopen(_ primary: ClipboardAssistantActionKind) throws {
        let number = "001234567890"
        let detection = try #require(detect(number))
        #expect(detection.kind == .tracking)
        let suiteName = "Zisla.ClipboardAssistantNumericActionsTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = FeatureSettingsStore(defaults: defaults, defaultUpdateChannel: .release)
        let order = [primary] + [ClipboardAssistantActionKind.share, .addToQuickNote, .copyText, .openURL]
            .filter { $0 != primary }
        store.settings.clipboardAssistantActionOrders[.tracking] = order
        store.flushPendingChanges()

        let reopened = FeatureSettingsStore(defaults: defaults, defaultUpdateChannel: .release)
        #expect(reopened.settings.clipboardAssistantActionOrders[.tracking] == order)
        let actions = ClipboardAssistantActionOrder.ordered(
            detection.actions + [.addToQuickNote, .share],
            for: detection.kind,
            using: reopened.settings.clipboardAssistantActionOrders
        )
        #expect(actions.first?.kind == primary)
        var seen = Set<ClipboardAssistantActionKind>()
        #expect(actions.compactMap(\.kind).filter { seen.insert($0).inserted } == order)
        #expect(actions.contains(.copyText(number)))
        #expect(actions.filter { $0.kind == .openURL } == detection.actions.filter { $0.kind == .openURL })
    }

    @Test
    func seededSingleCharacterMutationsDoNotBecomeTracking() {
        var seed: UInt64 = 0xD16175
        func next(_ bound: Int) -> Int {
            seed = seed &* 6_364_136_223_846_793_005 &+ 1
            return Int((seed >> 32) % UInt64(bound))
        }
        let invalid = Array("./;?&%=\u{0}\u{202E}²Ⅳab")
        for index in 0..<160 {
            let count = 12 + next(13)
            var digits = (0..<count).map { _ in Character(String(next(10))) }
            digits.insert(invalid[next(invalid.count)], at: 1 + next(count - 1))
            let input = String(digits)
            let detection = detect(input)
            #expect(detection?.kind != .tracking, "seed D16175, case \(index): \(input.debugDescription)")
            #expect(detection?.actions.contains { if case .openService = $0 { return true }; return false } != true)
        }
    }

    private func detect(
        _ text: String,
        kinds: Set<ClipboardAssistantKind>? = nil
    ) -> ClipboardAssistantDetection? {
        ClipboardAssistantDetector.detect(
            text: text, enabledKinds: kinds ?? allKinds, systemLanguageIdentifier: "en",
            now: now, timeZone: utc, locale: Locale(identifier: "en_US"), countryCode: "CN"
        )
    }
}
