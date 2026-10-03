import Foundation

public enum ContextNoteLocation: Codable, Equatable, Sendable {
    case webPage(url: URL, title: String, applicationName: String)
    case window(bundleIdentifier: String, applicationName: String, title: String)
    case desktop(displayID: String, displayName: String)

    public func matches(_ other: Self) -> Bool {
        switch (self, other) {
        case let (.webPage(url, _, _), .webPage(otherURL, _, _)):
            url == otherURL
        case let (.window(bundle, _, title), .window(otherBundle, _, otherTitle)):
            bundle == otherBundle && title == otherTitle
        case let (.desktop(displayID, _), .desktop(otherID, _)):
            displayID == otherID
        default:
            false
        }
    }
}
