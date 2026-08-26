import Foundation

/// Content kinds recognized by the clipboard assistant; each kind can be toggled in Settings.
public enum ClipboardAssistantKind: String, Codable, CaseIterable, Sendable, Equatable, Hashable {
    case url
    case filePath
    case email
    case phone
    case color
    case math
    case dateTime
    case chineseText
    case code
    case text
    case image
    case file

    /// SF Symbol shown in the toast and Settings; language-neutral on purpose.
    public var symbolName: String {
        switch self {
        case .url: "link"
        case .filePath: "doc.text"
        case .email: "envelope"
        case .phone: "phone"
        case .color: "paintpalette"
        case .math: "equal.square"
        case .dateTime: "calendar"
        case .chineseText: "character.book.closed"
        case .code: "chevron.left.forwardslash.chevron.right"
        case .text: "text.quote"
        case .image: "photo"
        case .file: "doc"
        }
    }
}

/// Search engines offered for the "search copied text" action.
public enum ClipboardAssistantSearchEngine: String, Codable, CaseIterable, Sendable, Equatable {
    case google
    case bing
    case baidu
    case sogou
    case quark
    case so360
    case duckduckgo
    case brave
    case yandex
    case custom

    /// Builds the search URL for a query; returns `nil` for queries that cannot be encoded.
    public func queryURL(for text: String, customURL: String = "") -> URL? {
        if self == .custom {
            return Self.customQueryURL(for: text, template: customURL)
        }
        guard let endpoint else { return nil }
        var components = URLComponents(string: endpoint)
        components?.queryItems = [URLQueryItem(name: queryParameter, value: text)]
        return components?.url
    }

    private var endpoint: String? {
        switch self {
        case .google: "https://www.google.com/search"
        case .bing: "https://www.bing.com/search"
        case .baidu: "https://www.baidu.com/s"
        case .sogou: "https://www.sogou.com/web"
        case .quark: "https://quark.sm.cn/s"
        case .so360: "https://www.so.com/s"
        case .duckduckgo: "https://duckduckgo.com/"
        case .brave: "https://search.brave.com/search"
        case .yandex: "https://yandex.com/search/"
        case .custom: nil
        }
    }

    private var queryParameter: String {
        switch self {
        case .baidu: "wd"
        case .sogou: "query"
        case .yandex: "text"
        default: "q"
        }
    }

    private static func customQueryURL(for text: String, template: String) -> URL? {
        let template = template.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !template.isEmpty else { return nil }

        if template.contains("{query}") {
            guard let encodedQuery = percentEncodedQuery(text) else { return nil }
            return webURL(from: template.replacingOccurrences(of: "{query}", with: encodedQuery))
        }

        guard var components = URLComponents(string: template),
              isWebURL(components) else {
            return nil
        }
        components.queryItems = (components.queryItems ?? []) + [URLQueryItem(name: "q", value: text)]
        return components.url
    }

    private static func percentEncodedQuery(_ text: String) -> String? {
        var components = URLComponents()
        components.queryItems = [URLQueryItem(name: "q", value: text)]
        return components.percentEncodedQuery.map { String($0.dropFirst(2)) }
    }

    private static func webURL(from value: String) -> URL? {
        guard let components = URLComponents(string: value), isWebURL(components) else {
            return nil
        }
        return components.url
    }

    private static func isWebURL(_ components: URLComponents) -> Bool {
        guard let scheme = components.scheme?.lowercased() else { return false }
        return (scheme == "http" || scheme == "https") && components.host != nil
    }
}

/// Builds a translation web URL for the given text and BCP-47-ish target language code.
public enum ClipboardAssistantTranslate {
    public enum Provider: Equatable, Sendable {
        case google
        case baidu
    }

    public static func provider(forCountryCode countryCode: String?) -> Provider {
        countryCode?.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() == "CN"
            ? .baidu
            : .google
    }

    public static func url(
        text: String,
        targetLanguageCode code: String,
        provider: Provider = .google
    ) -> URL? {
        switch provider {
        case .baidu:
            var components = URLComponents(string: "https://fanyi.baidu.com/mtpe-individual/transText")
            components?.queryItems = [
                URLQueryItem(name: "ext_channel", value: "Aldtype"),
                URLQueryItem(name: "query", value: text),
                URLQueryItem(name: "lang", value: "auto2\(baiduTargetLanguageCode(for: code))"),
            ]
            components?.fragment = "/"
            return components?.url
        case .google:
            var components = URLComponents(string: "https://translate.google.com/")
            let normalized = code.hasPrefix("zh") ? "zh-CN" : code
            components?.queryItems = [
                URLQueryItem(name: "sl", value: "auto"),
                URLQueryItem(name: "tl", value: normalized),
                URLQueryItem(name: "op", value: "translate"),
                URLQueryItem(name: "text", value: text),
            ]
            return components?.url
        }
    }

    private static func baiduTargetLanguageCode(for code: String) -> String {
        switch code {
        case "zh-CN": "zh"
        case "zh-TW": "cht"
        case "ja": "jp"
        case "ko": "kor"
        case "fr": "fra"
        case "es": "spa"
        case "pt-BR": "pot"
        case "ar": "ara"
        case "vi": "vie"
        default: code
        }
    }
}

/// Defaults for the clipboard assistant quick trigger.
public enum ClipboardAssistantDefaults {
    /// ⌘ N; ordinary combinations are registered through the system global hotkey API.
    public static let triggerHotkey = VoiceInputHotkeyPreset(
        keyCode: 45,              // kVK_ANSI_N
        carbonModifiers: 0x0100,  // cmdKey
        keyDisplayName: "N"
    )
    /// Text longer than this many characters offers a dedicated "save as file" action.
    public static let saveableTextLength = 50
}

/// Quick-trigger keyboard configuration. A dedicated enum (instead of an optional preset)
/// so a cleared trigger persists as `.none`: JSONEncoder omits nil optionals entirely,
/// which would resurrect the default hotkey on every relaunch.
public enum ClipboardAssistantTriggerConfiguration: Codable, Equatable, Sendable {
    case none
    case hotkey(VoiceInputHotkeyPreset)

    public var hotkey: VoiceInputHotkeyPreset? {
        if case .hotkey(let preset) = self { return preset }
        return nil
    }

    public static let `default` = ClipboardAssistantTriggerConfiguration.hotkey(
        ClipboardAssistantDefaults.triggerHotkey
    )
}

/// An executable next-step action offered by the clipboard assistant.
public enum ClipboardAssistantAction: Equatable, Sendable {
    case openURL(URL)
    case openDownload(URL)
    case revealInFinder(URL)
    case search(String)
    case translate(String)
    case composeMail(String)
    case copyText(String)
    case compress(URL)
    case share
    case callPhone(String)
    case blockSourceApp(bundleIdentifier: String, appName: String)
    case addToQuickNote
    case sendToTeleprompter
    case saveImage(Data)
    case saveText(String)
    case createCalendarEvent(title: String, date: Date, isAllDay: Bool)

    /// Stable identity used by SwiftUI to disambiguate buttons.
    public var identifier: String {
        switch self {
        case .openURL: "openURL"
        case .openDownload: "openDownload"
        case .revealInFinder: "revealInFinder"
        case .search: "search"
        case .translate: "translate"
        case .composeMail: "composeMail"
        case .copyText: "copyText"
        case .compress: "compress"
        case .share: "share"
        case .callPhone: "callPhone"
        case .blockSourceApp: "blockSourceApp"
        case .addToQuickNote: "addToQuickNote"
        case .sendToTeleprompter: "sendToTeleprompter"
        case .saveImage: "saveImage"
        case .saveText: "saveText"
        case .createCalendarEvent: "createCalendarEvent"
        }
    }
}

/// Structured secondary line of a detection result. The presentation layer renders it with
/// locale-aware formatters so the detector itself stays free of user-facing strings.
public enum ClipboardAssistantDetail: Equatable, Sendable {
    case characterCount(Int)
    case characterAndWordCount(characters: Int, words: Int)
    case chineseCharacterCount(Int)
    case codeLines(Int)
    case imageSize(pixelsWide: Int, pixelsHigh: Int, byteCount: Int)
    case fileSize(bytes: Int)
    case mathExpression(String)
    case rgb(red: Double, green: Double, blue: Double, hex: String)
    case path(String)
}

/// Detection result rendered by the assistant toast.
public struct ClipboardAssistantDetection: Equatable, Sendable {
    public var kind: ClipboardAssistantKind
    /// One-line preview shown as the toast title (content preview or intrinsic value).
    public var title: String
    /// Secondary structured line rendered by the presentation layer.
    public var detail: ClipboardAssistantDetail?
    /// Offered actions; the first entry is the primary one fired by the quick trigger.
    public var actions: [ClipboardAssistantAction]
    /// Fill color preview for CSS color values (sRGB components).
    public var colorComponents: ColorComponents?
    /// Full content available through the expandable preview; `nil` when there is nothing more
    /// to show than the one-line title.
    public var fullContent: String?

    public struct ColorComponents: Equatable, Sendable {
        public var red: Double
        public var green: Double
        public var blue: Double

        public init(red: Double, green: Double, blue: Double) {
            self.red = red
            self.green = green
            self.blue = blue
        }
    }

    public init(
        kind: ClipboardAssistantKind,
        title: String,
        detail: ClipboardAssistantDetail? = nil,
        actions: [ClipboardAssistantAction] = [],
        colorComponents: ColorComponents? = nil,
        fullContent: String? = nil
    ) {
        self.kind = kind
        self.title = title
        self.detail = detail
        self.actions = actions
        self.colorComponents = colorComponents
        self.fullContent = fullContent
    }

    /// The primary action fired by the action button or the quick trigger.
    public var action: ClipboardAssistantAction? { actions.first }

    /// Additional actions rendered after the primary button.
    public var secondaryActions: [ClipboardAssistantAction] { Array(actions.dropFirst()) }
}
