import Foundation
import Testing
import ZislaCore
@testable import ZislaKit

struct ClipboardAssistantIPAddressTests {
    @Test(arguments: ["192.168.1.1", "8.8.8.8", "2001:db8::1"])
    func disabledIPDoesNotOfferWebActions(text: String) {
        let detection = ClipboardAssistantDetector.detect(
            text: text, enabledKinds: [.url, .text], offersDownload: true,
            locale: Locale(identifier: "en"), countryCode: nil
        )
        #expect(detection?.kind != .url, "Pure IP must not be classified as a web URL: \(text)")
        #expect(detection?.actions.contains(where: { action in
            switch action {
            case .openURL, .openDownload: true
            default: false
            }
        }) != true, "Pure IP must not offer web navigation: \(text)")
    }

    @Test(arguments: [
        "192.168.1.1", "8.8.8.8", "0.0.0.0", "255.255.255.255", "212.222.12.34",
        "::", "::1", "2001:db8::1", "FE80::ABCD", "2001:db8:0:1:2:3:4:5",
        "ffff:ffff:ffff:ffff:ffff:ffff:ffff:ffff", "::ffff:192.0.2.128",
        "2001:db8::1:8080", " \t192.0.2.1\r\n", "\n 2001:DB8::1 \t",
    ])
    func completeIPAddressHasItsOwnKindAndCopyAction(text: String) throws {
        let detection = try #require(ClipboardAssistantDetector.detect(
            text: text, enabledKinds: Set(ClipboardAssistantKind.allCases), offersDownload: true,
            systemLanguageIdentifier: "en", now: .distantPast, timeZone: TimeZone(secondsFromGMT: 0)!,
            locale: Locale(identifier: "en"), countryCode: "US"
        ))
        let address = text.trimmingCharacters(in: .whitespacesAndNewlines)
        #expect(detection.kind == .ipAddress, "Expected a complete IP address: \(text)")
        #expect(detection.title == address)
        #expect(detection.actions.contains(.copyText(address)))
    }

    @Test(arguments: [
        ("192.168.1.1", "https://192.168.1.1"),
        ("0.0.0.0", "https://0.0.0.0"),
        ("::", "https://[::]"),
        ("::1", "https://[::1]"),
        (" \n2001:DB8::1\t", "https://[2001:DB8::1]"),
        ("::ffff:192.0.2.128", "https://[::ffff:192.0.2.128]"),
    ])
    func bareIPOffersAnIndependentDirectLink(text: String, expectedURL: String) throws {
        let detection = try #require(ClipboardAssistantDetector.detect(
            text: text, enabledKinds: [.ipAddress], locale: Locale(identifier: "en"), countryCode: nil
        ))
        let directURL = try #require(URL(string: expectedURL))
        let lookup = try #require(detection.action)
        #expect(detection.kind == .ipAddress)
        #expect(detection.actions.contains(.openURL(directURL)))
        #expect(lookup.kind != ClipboardAssistantAction.openURL(directURL).kind,
                "Lookup and navigation must be independently selectable")
        #expect(detection.actions.contains(.copyText(text.trimmingCharacters(in: .whitespacesAndNewlines))))
        let ordered = ClipboardAssistantActionOrder.ordered(
            detection.actions, for: .ipAddress, using: [.ipAddress: [.openURL]]
        )
        #expect(ordered.first == .openURL(directURL))
        #expect(ordered.count == detection.actions.count)
    }

    @Test(arguments: ["192.0.2.1", " \n2001:DB8::1\t", "::ffff:192.0.2.128"])
    func IPLookupRemainsPrimaryWithLinkAndCopySecondary(text: String) throws {
        let detection = try #require(ClipboardAssistantDetector.detect(
            text: text, enabledKinds: [.ipAddress], locale: Locale(identifier: "en"), countryCode: nil
        ))
        let address = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let primary = try #require(detection.action)
        guard case .openService(let service, let url) = primary else {
            Issue.record("IP lookup must be the primary action: \(address)")
            return
        }
        #expect(service.rawValue == "ipInfo")
        #expect(primary.kind == .lookupIP)
        #expect(primary.identifier == "openService:ipInfo")
        #expect(url.absoluteString == "https://ipinfo.io/\(address)")
        #expect(url.scheme == "https")
        #expect(url.host == "ipinfo.io")
        #expect(url.path == "/\(address)")
        #expect(url.query == nil)
        #expect(url.fragment == nil)
        #expect(url.user == nil && url.password == nil && url.port == nil)
        let navigation = try #require(detection.secondaryActions.first)
        guard case .openURL = navigation else {
            Issue.record("Direct navigation must remain available after IP lookup")
            return
        }
        #expect(detection.secondaryActions == [navigation, .copyText(address)])
    }

    @Test(arguments: [
        "", " \n\t", "256.0.0.1", "999.1.1.1", "1.2.3", "127.1", "2130706433", "0x7f000001",
        "001.2.3.4", "1.2.3.4.", "1.2.3.4.5", "2001:::1", "2001:db8::g", "12345::1",
        "1:2:3:4:5:6:7", "1:2:3:4:5:6:7:8:9", "2001:db8::1::2", "fe80::1%en0",
        "[2001:db8::1]", "192.0.2.1:80", "[2001:db8::1]:8080", "http://192.0.2.1",
        "https://[2001:db8::1]", "192.0.2.1/path", "192.0.2.1?x=1", "192.0.2.1#fragment",
        "IP: 192.0.2.1", "server 192.0.2.1", "192.0.2.1 extra", "192.0.2.1\n198.51.100.1",
        "192.0.2.1\u{0}extra", "2001:db8::1\u{0}extra", "192.0.2.1\u{202E}", "\u{200B}192.0.2.1",
        "192.0.2.1; echo injected", "<script>192.0.2.1</script>", "[IP](https://192.0.2.1)",
        "１９２.０.２.１", "192.0.\t2.1",
    ])
    func rejectsInvalidEmbeddedAndDecoratedIPValues(text: String) {
        #expect(ClipboardAssistantDetector.detect(
            text: text, enabledKinds: [.ipAddress], locale: Locale(identifier: "en"), countryCode: nil
        ) == nil, "Only complete IP literals are accepted: \(text)")
    }

    @Test(arguments: [
        ("http://192.0.2.1", "http://192.0.2.1", false),
        ("https://192.0.2.1:443/api?token=mock", "https://192.0.2.1:443/api?token=mock", false),
        ("192.0.2.1:8080", "https://192.0.2.1:8080", false),
        ("192.0.2.1/path?x=1", "https://192.0.2.1/path?x=1", false),
        ("192.0.2.1?x=1", "https://192.0.2.1?x=1", false),
        ("[2001:db8::1]:8080", "https://[2001:db8::1]:8080", false),
        ("https://[2001:db8::1]/video.mp4", "https://[2001:db8::1]/video.mp4", true),
        ("http://[::1]:80/?x=1", "http://[::1]:80/?x=1", false),
        ("Download https://192.0.2.1/video.mp4 today", "https://192.0.2.1/video.mp4", true),
        ("[IP server](https://192.0.2.1/path)", "https://192.0.2.1/path", false),
    ])
    func IPLinksKeepTheirURLAndDownloadBehavior(text: String, expectedURL: String, downloadable: Bool) throws {
        let url = try #require(URL(string: expectedURL))
        for kinds in [Set(ClipboardAssistantKind.allCases), Set<ClipboardAssistantKind>([.url, .text])] {
            let detection = try #require(ClipboardAssistantDetector.detect(
                text: text, enabledKinds: kinds, offersDownload: true,
                locale: Locale(identifier: "en"), countryCode: nil
            ))
            #expect(detection.kind == .url)
            #expect(detection.actions == (downloadable ? [.openURL(url), .openDownload(url)] : [.openURL(url)]))
        }
    }

    @Test(arguments: ["192.168.1.1", "212.222.12.34", "0.0.0.0", "2001:db8::1", "::", "fe80::abcd"])
    func disabledIPFallsBackToTextOrNoDetection(text: String) {
        let kinds = Set(ClipboardAssistantKind.allCases).subtracting([.ipAddress])
        let detection = ClipboardAssistantDetector.detect(
            text: text, enabledKinds: kinds, locale: Locale(identifier: "en"), countryCode: "US"
        )
        #expect(detection?.kind == .text, "Disabled IP must use the text fallback: \(text)")
        #expect(ClipboardAssistantDetector.detect(
            text: text, enabledKinds: kinds.subtracting([.text]), locale: Locale(identifier: "en"), countryCode: "US"
        ) == nil, "Disabled IP must stay unclassified when text is disabled: \(text)")
        #expect(ClipboardAssistantDetector.detect(
            text: text, enabledKinds: [.url], locale: Locale(identifier: "en"), countryCode: "US"
        ) == nil)
    }

    @MainActor
    @Test(arguments: [" \n192.0.2.1\t", "2001:db8::1"])
    func backgroundContentDetectionPreservesIPClassification(text: String) async throws {
        let kinds: Set<ClipboardAssistantKind> = [.ipAddress, .url, .text]
        let expected = ClipboardAssistantDetector.detect(
            content: .text(text), enabledKinds: kinds, offersDownload: true,
            locale: Locale(identifier: "en"), countryCode: nil
        )
        let actual = try #require(await ClipboardAssistantDetector.detectInBackground(
            content: .text(text), enabledKinds: kinds, offersDownload: true,
            locale: Locale(identifier: "en"), countryCode: nil
        ))
        #expect(actual.kind == .ipAddress)
        #expect(actual == expected)
    }

    @Test
    func boundedSeededIPAddressPropertiesRejectInvalidMutations() {
        var seed: UInt64 = 0x1AADD355
        func next(_ bound: Int) -> Int {
            seed = seed &* 6_364_136_223_846_793_005 &+ 1
            return Int((seed >> 32) % UInt64(bound))
        }
        for _ in 0..<24 {
            let octets = (0..<4).map { _ in next(256) }
            let ipv4 = octets.map(String.init).joined(separator: ".")
            let ipv6 = (0..<8).map { _ in String(next(65_536), radix: 16) }.joined(separator: ":")
            for address in [ipv4, ipv6] {
                let detection = ClipboardAssistantDetector.detect(
                    text: address, enabledKinds: [.ipAddress], locale: Locale(identifier: "en"), countryCode: nil
                )
                #expect(detection?.kind == .ipAddress, "Seeded valid address: \(address)")
                #expect(detection?.actions.contains(.copyText(address)) == true)
            }
            let invalidOctet = "\(256 + next(256)).\(octets[1]).\(octets[2]).\(octets[3])"
            for invalid in [invalidOctet, ipv4 + "\u{0}mock", ipv6 + "\u{202E}", ipv6 + "g"] {
                #expect(ClipboardAssistantDetector.detect(
                    text: invalid, enabledKinds: [.ipAddress], locale: Locale(identifier: "en"), countryCode: nil
                ) == nil, "Seeded invalid address: \(invalid)")
            }
        }
    }
}
