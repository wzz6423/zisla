import Foundation
import Testing
@testable import ZislaKit

struct MeetingLinkTests {
    @Test(arguments: [
        "https://us02web.zoom.us/j/12345678901?pwd=ExampleToken",
        "https://zoom.us/my/product.review",
        "https://zoomgov.com/wc/123456789/join",
        "https://meet.google.com/abc-defg-hij?authuser=1",
        "https://meet.google.com/lookup/weekly_review",
        "https://teams.microsoft.com/l/meetup-join/19%3ameeting_ABC123%40thread.v2/0?context=%7B%22Tid%22%3A%22example%22%7D",
        "https://teams.microsoft.com/meet/1234567890123?p=token",
        "https://teams.live.com/meet/1234567890123?p=token",
        "https://example.webex.com/meet/reviewer",
        "https://example.webex.com/example/j.php?MTID=m0123456789abcdef0123456789abcdef",
        "https://meeting.tencent.com/dm/AbC123Xy",
        "HTTPS://MEET.GOOGLE.COM/abc-defg-hij",
        "https://meet.google.com:443/abc-defg-hij",
    ])
    func supportedJoinAddressesPreserveTheActualDestination(address: String) throws {
        let url = try #require(MeetingLink.validated(address), "Supported meeting address rejected: \(address)")
        #expect(url == URL(string: address))
    }

    @Test(arguments: [
        "http://meet.google.com/abc-defg-hij", "zoommtg://zoom.us/join?confno=123456789",
        "javascript:alert(1)", "file:///tmp/meeting", "https://example.test/j/123456789",
        "https://zoom.us.evil.test/j/123456789", "https://evilzoom.us/j/123456789",
        "https://zoom.us@evil.test/j/123456789", "https://evil.test@zoom.us/j/123456789",
        "https://user:password@zoom.us/j/123456789", "https://zoom.us:8443/j/123456789",
        "https://zoom.us/", "https://zoom.us/pricing", "https://zoom.us/j/123",
        "https://meet.google.com/new", "https://meet.google.com/abc-defg-hi",
        "https://meeting.tencent.com/", "https://teams.microsoft.com/l/meetup-join/anything",
        "https://example.webex.com/example/j.php", "https://example.webex.com/example/j.php?MTID=other",
        "https://webex.com/meet/reviewer", "https://zoom.us./j/123456789",
        "https://%7Aoom.us/j/123456789", "https://zoom.us/j%2F123456789",
        "https://zoom.us/a/../j/123456789", "https://zoom.us/a/%2e%2e/j/123456789",
        "https://zoom.us/j/123456789?pwd=%", "https://zoom.us/j/123456789?pwd=%0aInjected",
        "https://zoom.us/j/123456789?pwd=%E2%80%AEabc",
        "https://zoom.us/j/123456789\n", "https://zoom.us/j/123456789\u{200B}",
        "https://zoom.us\\@evil.test/j/123456789", "https://zoom.us/j%5C123456789",
        "", "https://", "https://zoom.us/j/123456789?pwd=has space",
    ])
    func unsafeOrUnrecognizedAddressesHaveNoJoinAction(address: String) {
        #expect(MeetingLink.validated(address) == nil, "Unexpected join action for \(address)")
    }

    @Test
    func calendarURLThenNotesThenLocationHaveDeterministicPrecedence() throws {
        let direct = try #require(URL(string: "https://meet.google.com/abc-defg-hij"))
        let notes = "Join: https://zoom.us/j/123456789?pwd=token"
        let location = "https://meeting.tencent.com/dm/AbC123"
        #expect(MeetingLink.extract(eventURL: direct, notes: notes, location: location) == direct)
        #expect(MeetingLink.extract(eventURL: URL(string: "https://example.test"), notes: notes, location: location)
            == URL(string: "https://zoom.us/j/123456789?pwd=token"))
        #expect(MeetingLink.extract(eventURL: nil, notes: "https://zoom.us/help", location: location) == URL(string: location))
        #expect(MeetingLink.extract(eventURL: nil, notes: nil, location: nil) == nil)
    }

    @Test
    func copiedInvitationsSupportMarkdownPunctuationAndSkipUnsafeLinks() {
        let address = "https://meet.google.com/abc-defg-hij"
        for text in ["Join (\(address)).", "[Join](\(address))", "会议：\(address)，请准时", "Link: <\(address)>"] {
            #expect(MeetingLink.extract(from: text) == URL(string: address), "Failed invitation: \(text)")
        }
        #expect(MeetingLink.extract(from: "https://zoom.us.evil.test/j/123456789\nJoin: \(address)") == URL(string: address))
        #expect(MeetingLink.extract(from: "Meeting without a link") == nil)
        #expect(MeetingLink.extract(from: "xhttps://meet.google.com/abc-defg-hij") == nil)
    }

    @Test
    func inputBudgetsRejectOversizedInvitationsAndAddresses() {
        #expect(MeetingLink.extract(from: String(repeating: "a", count: 65_537) + " https://meet.google.com/abc-defg-hij") == nil)
        #expect(MeetingLink.validated("https://zoom.us/j/123456789?pwd=" + String(repeating: "a", count: 4_096)) == nil)
    }

    @Test
    func boundedMutationsCannotTurnAnUntrustedDomainIntoAJoinDestination() {
        let domains = ["zoom.us", "meet.google.com", "teams.microsoft.com", "meeting.tencent.com", "example.webex.com"]
        for domain in domains {
            for suffix in [".evil.test", "@evil.test", ".", "%00", "\u{202E}", "\\evil.test"] {
                let address = "https://\(domain)\(suffix)/j/123456789"
                #expect(MeetingLink.validated(address) == nil)
            }
        }
    }
}
