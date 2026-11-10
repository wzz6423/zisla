import Foundation

public enum MeetingLink {
    private static let links = try! NSRegularExpression(pattern: #"(?i)(?<![\p{L}\p{N}_/])https?://[^\s<>\"“”，；。！？）】》]+"#)
    private static let malformedEscape = try! NSRegularExpression(pattern: #"%(?![0-9a-fA-F]{2})"#)
    private static let trailingPunctuation = CharacterSet(charactersIn: ".,;!?)]}'，；。！？）】》")

    public static func extract(eventURL: URL?, notes: String?, location: String?) -> URL? {
        if let eventURL, let url = validated(eventURL.absoluteString) { return url }
        for text in [notes, location].compactMap({ $0 }) {
            if let url = extract(from: text) { return url }
        }
        return nil
    }

    public static func extract(from text: String) -> URL? {
        guard text.utf8.count <= 65_536 else { return nil }
        let range = NSRange(text.startIndex..., in: text)
        for match in links.matches(in: text, range: range) {
            let address = (text as NSString).substring(with: match.range)
                .trimmingCharacters(in: trailingPunctuation)
            if let url = validated(address) { return url }
        }
        return nil
    }

    public static func validated(_ address: String) -> URL? {
        guard address.utf8.count <= 4_096,
              !address.unicodeScalars.contains(where: { $0.properties.isWhitespace || isInvisible($0) }),
              malformedEscape.firstMatch(in: address, range: NSRange(address.startIndex..., in: address)) == nil,
              let components = URLComponents(string: address),
              components.scheme?.lowercased() == "https",
              components.user == nil,
              components.port == nil || components.port == 443,
              let host = components.host?.lowercased(),
              components.percentEncodedHost?.lowercased() == host,
              !components.percentEncodedPath.lowercased().contains("%2f"),
              ![components.query ?? "", components.fragment ?? ""].contains(where: {
                  $0.unicodeScalars.contains(where: isInvisible)
              }) else { return nil }

        let path = components.path
        let matchesRoute: Bool
        switch host {
        case "meet.google.com":
            matchesRoute = matches(#"^/[a-z]{3}-[a-z]{4}-[a-z]{3}/?$"#, path)
                || matches(#"^/lookup/[A-Za-z0-9_-]+/?$"#, path)
        case "teams.microsoft.com":
            matchesRoute = matches(#"^/l/meetup-join/19:meeting_[A-Za-z0-9_=-]+@thread\.v2/0/?$"#, path)
                || matches(#"^/meet/[0-9]{8,20}/?$"#, path)
        case "teams.live.com":
            matchesRoute = matches(#"^/meet/[0-9]{8,20}/?$"#, path)
        case "meeting.tencent.com":
            matchesRoute = matches(#"^/dm/[A-Za-z0-9]+/?$"#, path)
        default:
            if isHost(host, in: "zoom.us") || isHost(host, in: "zoomgov.com") {
                matchesRoute = matches(#"^/j/[0-9]{9,11}/?$"#, path)
                    || matches(#"^/my/[A-Za-z0-9][A-Za-z0-9._-]*/?$"#, path)
                    || matches(#"^/wc/[0-9]{9,11}/join/?$"#, path)
            } else if isHost(host, in: "webex.com"), host != "webex.com" {
                matchesRoute = matches(#"^/meet/[A-Za-z0-9][A-Za-z0-9._-]*/?$"#, path)
                    || (matches(#"^/[A-Za-z0-9_-]+/j\.php$"#, path)
                        && components.queryItems?.contains(where: {
                            $0.name == "MTID" && matches(#"^m[0-9a-fA-F]{32}$"#, $0.value ?? "")
                        }) == true)
            } else {
                matchesRoute = false
            }
        }
        return matchesRoute ? components.url : nil
    }

    private static func isHost(_ host: String, in domain: String) -> Bool {
        host == domain || host.hasSuffix("." + domain)
    }

    private static func matches(_ pattern: String, _ value: String) -> Bool {
        value.range(of: pattern, options: .regularExpression) != nil
    }

    private static func isInvisible(_ scalar: Unicode.Scalar) -> Bool {
        scalar.properties.generalCategory == .control || scalar.properties.generalCategory == .format
    }
}
