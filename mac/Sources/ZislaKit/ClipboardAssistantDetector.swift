import AppKit
import NaturalLanguage
import ZislaCore

/// Pure detection logic for the clipboard assistant. Text classification runs from most specific
/// to least specific so overlapping patterns resolve predictably. Detections carry structured
/// payloads only; the presentation layer renders user-facing strings with locale-aware formatters.
public enum ClipboardAssistantDetector {
    public static func detect(
        content: ClipboardHistoryContent,
        enabledKinds: Set<ClipboardAssistantKind>,
        offersDownload: Bool = false,
        preferredCurrencyCode: String? = nil,
        installedApplications: [InstalledApplication] = []
    ) -> ClipboardAssistantDetection? {
        switch content {
        case .image(let data):
            guard enabledKinds.contains(.image) else { return nil }
            return imageDetection(data)
        case .file(let reference):
            guard enabledKinds.contains(.file) else { return nil }
            return fileDetection(reference)
        case .text(let value):
            return detect(
                text: value,
                enabledKinds: enabledKinds,
                offersDownload: offersDownload,
                preferredCurrencyCode: preferredCurrencyCode,
                installedApplications: installedApplications
            )
        }
    }

    public static func detect(
        text rawText: String,
        enabledKinds: Set<ClipboardAssistantKind>,
        offersDownload: Bool = false,
        systemLanguageIdentifier: String? = Locale.preferredLanguages.first,
        preferredCurrencyCode: String? = nil,
        now: Date = Date(),
        timeZone: TimeZone = .current,
        locale: Locale = AppLocalization.currentLanguage.locale,
        installedApplications: [InstalledApplication] = []
    ) -> ClipboardAssistantDetection? {
        let text = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }

        if let detection = smartActionDetection(
            text, enabledKinds: enabledKinds, now: now, timeZone: timeZone
        ) {
            return detection
        }
        // Dot-separated dates and decimal currency amounts also resemble bare web hosts.
        // Strict whole-value grammars must get the first chance to classify them.
        if enabledKinds.contains(.conversion), var conversion = conversionDetection(
            text,
            enabledKinds: [.math, .dateTime],
            now: now,
            timeZone: timeZone,
            locale: locale
        ) {
            conversion.kind = .conversion
            return conversion
        }
        // Date/time runs before math and phone: dashed digit groups like "2024-03-05" parse as
        // both arithmetic and a phone shape, but the date reading is the one users mean.
        if enabledKinds.contains(.dateTime), let parsed = parseDateTime(text, now: now, timeZone: timeZone) {
            // Date-only values become all-day events; values carrying a time become timed ones.
            let isAllDay = parsed.isDateOnly
            // Copy offers the canonical rendering; calendar creates an event from the value.
            let actions: [ClipboardAssistantAction] = [
                .createCalendarEvent(title: text, date: parsed.date, isAllDay: isAllDay),
                .copyText(parsed.isoText),
            ]
            return ClipboardAssistantDetection(
                kind: .dateTime,
                title: text,
                actions: actions
            )
        }
        // Currency runs before math: values like "100$=" or "100dollar=cny" carry a currency
        // token the arithmetic parser cannot consume, but keep the order explicit anyway so
        // future overlaps resolve predictably. The live rate is fetched afterwards by the
        // presentation layer; this branch only recognizes the shape and defers the numbers.
        if enabledKinds.contains(.conversion),
           let conversion = parseCurrencyConversion(text, preferredCurrencyCode: preferredCurrencyCode),
           conversion.sourceCurrencyCode
              != (conversion.targetCurrencyCode ?? resolvedPreferredCurrencyCode(preferredCurrencyCode)) {
            let target = conversion.targetCurrencyCode ?? resolvedPreferredCurrencyCode(preferredCurrencyCode)
            return ClipboardAssistantDetection(
                kind: .conversion,
                title: text,
                detail: .currencyExpression(
                    amount: conversion.amount,
                    amountText: conversion.amountText,
                    sourceCurrencyCode: conversion.sourceCurrencyCode,
                    targetCurrencyCode: target
                ),
                actions: []
            )
        }
        if enabledKinds.contains(.url), let url = HTTPURLParser.url(from: text) {
            var actions: [ClipboardAssistantAction] = [.openURL(url)]
            if offersDownload, DownloadURLClassifier.isLikelyDownloadable(url.absoluteString) {
                actions.append(.openDownload(url))
            }
            return ClipboardAssistantDetection(
                kind: .url,
                title: url.host ?? text,
                actions: actions
            )
        }
        if enabledKinds.contains(.filePath), let candidate = filePathCandidate(from: text) {
            return ClipboardAssistantDetection(
                kind: .filePath,
                title: candidate.url.lastPathComponent,
                detail: .path(candidate.url.path),
                actions: filePathActions(for: candidate)
            )
        }
        if enabledKinds.contains(.email), isEmailAddress(text) {
            return ClipboardAssistantDetection(
                kind: .email,
                title: text,
                actions: [.composeMail(text)]
            )
        }
        if enabledKinds.contains(.color), let color = parseColor(text) {
            return color
        }
        if enabledKinds.contains(.math),
           let expression = arithmeticExpression(from: text),
           let result = evaluateArithmetic(expression) {
            let formatted = formatNumber(result)
            let fullExpression = "\(expression) = \(formatted)"
            return ClipboardAssistantDetection(
                kind: .math,
                title: formatted,
                detail: .mathExpression(expression),
                actions: [.copyText(formatted), .copyFullExpression(fullExpression)],
                fullContent: fullExpression
            )
        }
        if enabledKinds.contains(.phone), isPhoneNumber(text) {
            let normalized = "+\(text.filter(\.isNumber))"
            return ClipboardAssistantDetection(
                kind: .phone,
                title: text,
                actions: [.callPhone(normalized)]
            )
        }
        if enabledKinds.contains(.code), let code = codeDetection(text) {
            return code
        }
        // Installed-application names must run before the foreign-language branch:
        // on a Chinese system "Safari" is English text, but the user copied it to
        // launch the app, and an exact name match against a locally installed
        // application is a far stronger signal than a language guess.
        if enabledKinds.contains(.app),
           let application = InstalledApplicationCatalog.application(
            named: text, in: installedApplications
           ) {
            return ClipboardAssistantDetection(
                kind: .app,
                title: application.displayName,
                actions: [.openApp(
                    bundleIdentifier: application.bundleIdentifier,
                    appName: application.displayName
                )]
            )
        }
        // Emoji names run before language/text fallbacks. Exact aliases are primary; a concise
        // near match can expose related paste candidates without treating full sentences as names.
        if enabledKinds.contains(.emojiName), text.count <= 64 {
            let candidates = EmojiNameCatalog.emojiCandidates(
                for: text,
                language: EmojiNameCatalog.language(for: locale)
            )
            if let emoji = candidates.first {
                return ClipboardAssistantDetection(
                    kind: .emojiName,
                    title: text,
                    actions: candidates.map(ClipboardAssistantAction.copyEmoji),
                    emoji: emoji
                )
            }
        }
        if enabledKinds.contains(.nonSystemLanguageText),
           isNonCurrentSystemLanguageText(text, systemLanguageIdentifier: systemLanguageIdentifier) {
            let preview = previewText(text)
            var actions: [ClipboardAssistantAction] = [.translate(text)]
            if text.count <= ClipboardAssistantDefaults.saveableTextLength {
                actions.append(.search(text))
            } else {
                actions.append(.saveText(text))
            }
            return ClipboardAssistantDetection(
                kind: .nonSystemLanguageText,
                title: preview,
                detail: textDetail(for: text),
                actions: actions,
                fullContent: text
            )
        }
        guard enabledKinds.contains(.text) else { return nil }
        let preview = previewText(text)
        let detail = textDetail(for: text)
        var actions: [ClipboardAssistantAction]
        if text.count > ClipboardAssistantDefaults.saveableTextLength {
            // Long content gets a dedicated save-to-file action per the feature spec.
            actions = [.saveText(text)]
        } else {
            actions = [.search(text)]
        }
        actions.append(.translate(text))
        return ClipboardAssistantDetection(
            kind: .text,
            title: preview,
            detail: detail,
            actions: actions,
            fullContent: text
        )
    }

    /// Single-line preview of copied content used as the toast title.
    static func previewText(_ text: String) -> String {
        let flattened = text
            .replacingOccurrences(of: "\r\n", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespaces)
        guard flattened.count > 120 else { return flattened }
        return String(flattened.prefix(120)) + "…"
    }

    /// Counts whitespace-separated latin-ish words; returns 0 when the text has no such tokens
    /// (e.g. CJK-only content, where a word count would be meaningless).
    static func countWords(_ text: String) -> Int {
        let words = text.split(whereSeparator: \.isWhitespace)
        let latinWords = words.filter { word in
            word.contains { $0.isLetter && !isChineseCharacter($0) }
        }
        return latinWords.count
    }

    private static func imageDetection(_ data: Data) -> ClipboardAssistantDetection? {
        let rep = NSBitmapImageRep(data: data)
            ?? NSImage(data: data).flatMap { image in
                image.cgImage(forProposedRect: nil, context: nil, hints: nil)
                    .map { NSBitmapImageRep(cgImage: $0) }
            }
        guard let rep else { return nil }
        return ClipboardAssistantDetection(
            kind: .image,
            title: "\(rep.pixelsWide) × \(rep.pixelsHigh)",
            detail: .imageSize(pixelsWide: rep.pixelsWide, pixelsHigh: rep.pixelsHigh, byteCount: data.count),
            actions: [.saveImage(data)]
        )
    }

    private static func fileDetection(_ reference: ClipboardFileReference) -> ClipboardAssistantDetection? {
        var isDirectory: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: reference.url.path, isDirectory: &isDirectory)
        var byteCount: Int?
        if exists, !isDirectory.boolValue,
           let attributes = try? FileManager.default.attributesOfItem(atPath: reference.url.path),
           let size = attributes[.size] as? UInt64 {
            byteCount = Int(size)
        }
        return ClipboardAssistantDetection(
            kind: .file,
            title: reference.displayName,
            detail: byteCount.map(ClipboardAssistantDetail.fileSize),
            actions: [.revealInFinder(reference.url), .compress(reference.url)]
        )
    }

    /// A copied value that reads as a local path, plus whether it currently resolves on disk.
    struct FilePathCandidate: Equatable {
        var url: URL
        var exists: Bool
    }

    /// Recognizes local paths by shape. Existence is a strong signal but not a requirement:
    /// temporary files get cleaned up and other apps' container paths are unreachable, yet such
    /// values are still paths to the user — treating them as text sent them down the plain/Chinese
    /// text branch (a path ending in `image.png` came back as Chinese prose). Unresolvable paths keep
    /// the path kind and only lose the file-bound actions. Shape rules match the clipboard history
    /// categorization (`ClipboardHistoryItem.category`), tightened for values that do not resolve.
    static func filePathCandidate(from text: String) -> FilePathCandidate? {
        guard text.count <= 1024, !text.contains(where: \Character.isNewline) else { return nil }
        guard text == "~" || text.hasPrefix("~/") || text.hasPrefix("/") else { return nil }
        var expanded = NSString(string: text).expandingTildeInPath
        while expanded.hasSuffix("/") && expanded.count > 1 {
            expanded.removeLast()
        }
        let url = URL(fileURLWithPath: expanded).standardizedFileURL
        if FileManager.default.fileExists(atPath: url.path) {
            return FilePathCandidate(url: url, exists: true)
        }
        // Nothing on disk backs the guess, so require an unambiguous shape: no whitespace and at
        // least two components, keeping values like "/help" or a stray slashed sentence out.
        guard !text.contains(where: \Character.isWhitespace),
              url.pathComponents.filter({ $0 != "/" }).count >= 2 else {
            return nil
        }
        return FilePathCandidate(url: url, exists: false)
    }

    /// Existing items get the file-bound actions. Unresolvable ones reveal the nearest surviving
    /// ancestor instead, so a cleaned-up temp file still tells users where it lived.
    private static func filePathActions(for candidate: FilePathCandidate) -> [ClipboardAssistantAction] {
        guard !candidate.exists else {
            return [.revealInFinder(candidate.url), .compress(candidate.url)]
        }
        guard let ancestor = nearestExistingAncestor(of: candidate.url) else { return [] }
        return [.revealInFinder(ancestor)]
    }

    /// Walks up until a directory exists on disk. The volume root is excluded: opening it says
    /// nothing about the copied value.
    private static func nearestExistingAncestor(of url: URL) -> URL? {
        var current = url.deletingLastPathComponent()
        while current.path != "/" {
            if FileManager.default.fileExists(atPath: current.path) { return current }
            let parent = current.deletingLastPathComponent()
            guard parent.path != current.path else { return nil }
            current = parent
        }
        return nil
    }

    static func isEmailAddress(_ text: String) -> Bool {
        guard text.count <= 320, !text.contains(where: \Character.isWhitespace) else { return false }
        let pattern = #"^[A-Za-z0-9!#$%&'*+/=?^_`{|}~.-]+@[A-Za-z0-9](?:[A-Za-z0-9-]*[A-Za-z0-9])?(?:\.[A-Za-z0-9](?:[A-Za-z0-9-]*[A-Za-z0-9])?)+$"#
        return text.range(of: pattern, options: .regularExpression) != nil
    }

    static func isPhoneNumber(_ text: String) -> Bool {
        guard text.count <= 24 else { return false }
        let digits = text.filter(\.isNumber)
        guard digits.count >= 7, digits.count <= 18, digits.contains(where: { $0 != "0" } ) || digits.count > 1 else {
            return false
        }
        let pattern = #"^\+?[0-9][0-9\s\-().]*[0-9]$|^\+?[0-9]{7,}$"#
        return text.range(of: pattern, options: .regularExpression) != nil
    }

    // MARK: - Date and time

    struct ParsedDateTime: Equatable {
        var date: Date
        /// Pure-date input (e.g. "2024-03-05") becomes an all-day calendar event.
        var isDateOnly: Bool
        /// Canonical rendering used for the copy action.
        var isoText: String
    }

    /// Short month/day values are only accepted in an explicit interval or time expression,
    /// so arithmetic and version fragments do not become calendar events.
    static func parseDateTime(
        _ rawText: String,
        now: Date = Date(),
        timeZone: TimeZone = .current
    ) -> ParsedDateTime? {
        let text = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.count <= 200 else { return nil }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let date: Date
        let isDateOnly: Bool
        if let timestamp = unixDate(text) {
            date = timestamp
            isDateOnly = false
        } else if let rfc = rfcDate(text, now: now) {
            date = rfc
            isDateOnly = false
        } else if text.contains(":"), let source = timeZoneSource(text) {
            guard let parsed = zonedDate(source.dateText, now: now, timeZone: source.zone) else { return nil }
            date = parsed
            isDateOnly = false
        } else if text.contains(":"), let parsed = zonedDate(text, now: now, timeZone: timeZone) {
            date = parsed
            isDateOnly = false
        } else if text.range(of: #"^[0-9]{4}(?:[-/.]|\s*年|\s*년)"#, options: .regularExpression) != nil,
                  let parsed = intervalDate(text, now: now, calendar: calendar) {
            date = parsed
            isDateOnly = true
        } else if let parsed = namedDate(text, calendar: calendar) {
            date = parsed
            isDateOnly = true
        } else {
            return nil
        }
        return ParsedDateTime(date: date, isDateOnly: isDateOnly, isoText: isoText(date, timeZone: timeZone))
    }

    private static func unixDate(_ text: String) -> Date? {
        guard let parts = conversionCaptures(#"(?:(?:unix(?:\s+timestamp)?|timestamp|时间戳|時間戳)\s*[:：=]?\s*)?([1-9][0-9]{9}|[1-9][0-9]{12}|[1-9][0-9]{15}|[1-9][0-9]{18})"#, in: text),
              let integer = UInt64(parts[0]) else { return nil }
        let divisor: Double = switch parts[0].count {
        case 10: 1
        case 13: 1_000
        case 16: 1_000_000
        default: 1_000_000_000
        }
        let seconds = Double(integer) / divisor
        // Bound bare-number guesses; labelled phone and tracking values never match this grammar.
        guard (946_684_800..<4_102_444_800).contains(seconds) else { return nil }
        return Date(timeIntervalSince1970: seconds)
    }

    private static func rfcDate(_ text: String, now: Date) -> Date? {
        guard let parts = conversionCaptures(#"(?:(Mon|Tue|Wed|Thu|Fri|Sat|Sun),\s+)?([0-9]{1,2})\s+([A-Za-z]{3})\s+([0-9]{4})\s+([0-9]{2}:[0-9]{2}:[0-9]{2})\s+(GMT|UTC|[+-][0-9]{4})"#, in: text),
              let month = englishMonth(parts[2]),
              let zone = conversionTimeZone(parts[5]),
              let date = zonedDate("\(parts[3])-\(month)-\(parts[1]) \(parts[4])", now: now, timeZone: zone) else { return nil }
        if !parts[0].isEmpty {
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = zone
            let weekday = ["sun", "mon", "tue", "wed", "thu", "fri", "sat"][calendar.component(.weekday, from: date) - 1]
            guard parts[0].lowercased() == weekday else { return nil }
        }
        return date
    }

    private static func namedDate(_ text: String, calendar: Calendar) -> Date? {
        let parts: [String]
        if let monthFirst = conversionCaptures(#"([A-Za-z]+)\s+([0-9]{1,2}),\s+([0-9]{4})"#, in: text) {
            parts = monthFirst
        } else if let dayFirst = conversionCaptures(#"([0-9]{1,2})\s+([A-Za-z]+)\s+([0-9]{4})"#, in: text) {
            parts = [dayFirst[1], dayFirst[0], dayFirst[2]]
        } else {
            return nil
        }
        guard let month = englishMonth(parts[0]), let year = Int(parts[2]), year >= 1600 else { return nil }
        let components = DateComponents(year: year, month: month, day: Int(parts[1]))
        guard components.isValidDate(in: calendar) else { return nil }
        return calendar.date(from: components)
    }

    private static func englishMonth(_ text: String) -> Int? {
        let months = ["january", "february", "march", "april", "may", "june", "july", "august", "september", "october", "november", "december"]
        return months.firstIndex { $0 == text.lowercased() || String($0.prefix(3)) == text.lowercased() }.map { $0 + 1 }
    }

    private static func isoText(_ date: Date, timeZone: TimeZone) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        let seconds = date.timeIntervalSince1970.truncatingRemainder(dividingBy: 60)
        if abs(seconds) > 0.000001 {
            formatter.dateFormat += ":ss"
            if abs(seconds.rounded() - seconds) > 0.000001 {
                formatter.dateFormat += ".SSS"
            }
        }
        return formatter.string(from: date)
    }

    // MARK: - Currency conversion

    /// A copied value that reads as a currency conversion request: "100$", "100$=",
    /// "100dollar", "100dollar=", "100$=¥", "100$=CNY", "$100", "¥100=€" and friends.
    public struct ParsedCurrencyConversion: Equatable, Sendable {
        public var amount: Double
        /// Amount spelled exactly as copied (grouping separators preserved for display).
        public var amountText: String
        public var sourceCurrencyCode: String
        /// `nil` converts to the preferred currency of the current language.
        public var targetCurrencyCode: String?
    }

    /// Parses whole-string currency conversion requests. A trailing bare `=` (as in "100$=")
    /// asks for the default target; `=<token>` names the target explicitly. Symbols are
    /// resolved against the preferred currency when they are ambiguous (`$`, `¥`).
    static func parseCurrencyConversion(
        _ rawText: String,
        preferredCurrencyCode: String?
    ) -> ParsedCurrencyConversion? {
        let text = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard (1...200).contains(text.count) else { return nil }
        let preferred = (preferredCurrencyCode ?? currentPreferredCurrencyCode()).uppercased()

        let operands = conversionOperands(text)
        let head = operands?[0] ?? (text.hasSuffix("=") ? String(text.dropLast()).trimmingCharacters(in: .whitespaces) : text)
        let targetToken = operands.flatMap { $0[1].isEmpty ? nil : $0[1] }

        // Prefix symbol form first: "$100", "¥100.5", "US$1,000".
        if let prefixed = parsePrefixedCurrencyAmount(head, preferred: preferred) {
            return completedConversion(prefixed, targetToken: targetToken, preferred: preferred)
        }

        // Suffix token form: "100$", "100 dollar", "100dollar", "100CNY", "100元".
        guard let (amount, amountText, token) = parseSuffixedCurrencyAmount(head),
              let source = resolveCurrencyToken(token, preferred: preferred) else {
            return nil
        }
        return completedConversion(
            ParsedCurrencyConversion(
                amount: amount,
                amountText: amountText,
                sourceCurrencyCode: source,
                targetCurrencyCode: nil
            ),
            targetToken: targetToken,
            preferred: preferred
        )
    }

    /// Applies the optional target token to an already-parsed amount+source pair.
    private static func completedConversion(
        _ base: ParsedCurrencyConversion,
        targetToken: String?,
        preferred: String
    ) -> ParsedCurrencyConversion? {
        guard let targetToken else {
            return ParsedCurrencyConversion(
                amount: base.amount,
                amountText: base.amountText,
                sourceCurrencyCode: base.sourceCurrencyCode,
                targetCurrencyCode: nil
            )
        }
        guard let target = resolveCurrencyToken(targetToken, preferred: preferred),
              target != base.sourceCurrencyCode else {
            return nil
        }
        return ParsedCurrencyConversion(
            amount: base.amount,
            amountText: base.amountText,
            sourceCurrencyCode: base.sourceCurrencyCode,
            targetCurrencyCode: target
        )
    }

    /// The currency the current interface language maps to (zh-Hans → CNY, en → USD, …),
    /// falling back to the system region's currency, then USD.
    public static func currentPreferredCurrencyCode(
        language: AppLanguage = AppLocalization.currentLanguage
    ) -> String {
        let languageLocale = language.locale
        let languageRegion = Locale(identifier: languageLocale.language.maximalIdentifier)
        return languageRegion.currency?.identifier
            ?? languageLocale.currency?.identifier
            ?? Locale.current.currency?.identifier
            ?? "USD"
    }

    private static func resolvedPreferredCurrencyCode(_ injected: String?) -> String {
        (injected ?? currentPreferredCurrencyCode()).uppercased()
    }

    /// "<symbol><amount>" for bare and prefixed symbols. Longest symbol first so "US$" wins
    /// over a bare "$".
    private static func parsePrefixedCurrencyAmount(
        _ head: String,
        preferred: String
    ) -> ParsedCurrencyConversion? {
        for symbol in currencySymbols.sorted(by: { $0.count > $1.count }) where head.hasPrefix(symbol) {
            let rest = String(head.dropFirst(symbol.count))
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard let amountText = leadingAmount(in: rest),
                  rest.dropFirst(amountText.count).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  let amount = normalizedAmount(amountText) else {
                return nil
            }
            return ParsedCurrencyConversion(
                amount: amount,
                amountText: amountText,
                sourceCurrencyCode: currencySymbolCode(symbol, preferred: preferred),
                targetCurrencyCode: nil
            )
        }
        return nil
    }

    /// "<amount><token>" with optional whitespace between: (100, "100", "dollar").
    private static func parseSuffixedCurrencyAmount(_ head: String) -> (Double, String, String)? {
        guard let amountText = leadingAmount(in: head) else { return nil }
        let token = head.dropFirst(amountText.count).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty, let amount = normalizedAmount(amountText) else { return nil }
        return (amount, amountText, token)
    }

    /// Leading run of amount characters (digits, separators), validated afterwards.
    private static func leadingAmount(in text: String) -> String? {
        var end = text.startIndex
        if text.first == "+" || text.first == "-" { end = text.index(after: end) }
        while end < text.endIndex, "0123456789.,".contains(text[end]) {
            end = text.index(after: end)
        }
        guard end > text.startIndex else { return nil }
        return String(text[..<end])
    }

    /// Validates an amount's shape (`1,000` / `100.50` / `100`) and parses it.
    private static func normalizedAmount(_ text: String) -> Double? {
        guard text.range(
            of: "^" + conversionAmountPattern + "$",
            options: .regularExpression
        ) != nil else { return nil }
        return Double(text.replacingOccurrences(of: ",", with: ""))
    }

    /// Currency symbols recognized at the start or right after an amount. Bare `$`/`¥` are
    /// ambiguous across currency families, so the preferred currency resolves them.
    private static let currencySymbols = [
        "US$", "HK$", "NZ$", "MX$", "A$", "C$", "NT$", "R$", "$",
        "¥", "￥", "€", "£", "₩", "₽", "₹", "₫", "฿", "₺", "₱",
    ]

    private static let dollarFamilyCodes: Set<String> = [
        "USD", "CAD", "AUD", "NZD", "SGD", "HKD", "MXN", "TWD", "ARS", "CLP", "COP",
    ]

    /// Resolves a currency symbol, consulting the preferred currency for the ambiguous ones.
    static func currencySymbolCode(_ symbol: String, preferred: String) -> String {
        switch symbol {
        case "$":
            dollarFamilyCodes.contains(preferred) ? preferred : "USD"
        case "US$": "USD"
        case "NT$": "TWD"
        case "HK$": "HKD"
        case "NZ$": "NZD"
        case "MX$": "MXN"
        case "A$": "AUD"
        case "C$": "CAD"
        case "R$": "BRL"
        case "¥", "￥":
            ["CNY", "JPY"].contains(preferred) ? preferred : "CNY"
        case "€": "EUR"
        case "£": "GBP"
        case "₩": "KRW"
        case "₽": "RUB"
        case "₹": "INR"
        case "₫": "VND"
        case "฿": "THB"
        case "₺": "TRY"
        case "₱": "PHP"
        default: "USD"
        }
    }

    /// ISO 4217 codes and aliases recognized after uppercasing.
    private static let currencyAliases: [String: String] = {
        var table: [String: String] = [
            "RMB": "CNY", "NTD": "TWD", "CNH": "CNY", "STERLING": "GBP",
        ]
        for code in [
            "USD", "EUR", "GBP", "JPY", "CNY", "HKD", "TWD", "MOP", "KRW", "AUD", "CAD",
            "NZD", "CHF", "SEK", "NOK", "DKK", "RUB", "INR", "THB", "VND", "IDR", "MYR",
            "SGD", "PHP", "TRY", "BRL", "MXN", "ZAR", "SAR", "AED", "ILS", "PLN", "CZK",
            "HUF", "RON", "BGN", "UAH", "KZT", "PEN", "CLP", "COP", "ARS", "EGP", "NGN",
            "KES", "PKR", "BDT", "LKR", "MMK", "KHR", "LAK", "GEL", "AZN", "AMD", "JOD",
            "QAR", "KWD", "BHD", "OMR", "TND", "DZD", "MAD", "IQD", "BYN", "RSD", "ISK",
            "XOF", "XAF", "GHS", "TZS", "UGX", "MUR", "NPR", "BTN", "XCD", "DOP", "GTQ",
            "PYG", "UYU", "BOB", "CRC", "HRK",
        ] {
            table[code] = code
        }
        return table
    }()

    /// Common English currency names (lowercased) → ISO code. "dollar(s)" is handled
    /// separately because it resolves against the preferred currency.
    private static let currencyNames: [String: String] = [
        "euro": "EUR", "euros": "EUR",
        "yen": "JPY",
        "yuan": "CNY", "rmb": "CNY", "kuai": "CNY", "renminbi": "CNY",
        "pound": "GBP", "pounds": "GBP", "quid": "GBP", "sterling": "GBP",
        "won": "KRW",
        "rupee": "INR", "rupees": "INR",
        "ruble": "RUB", "rouble": "RUB", "rubles": "RUB",
        "baht": "THB",
        "dong": "VND",
        "rupiah": "IDR",
        "ringgit": "MYR",
        "peso": "MXN", "pesos": "MXN",
        "franc": "CHF", "francs": "CHF",
        "krona": "SEK", "krone": "DKK", "kroner": "DKK",
        "zloty": "PLN",
        "forint": "HUF",
        "leu": "RON",
        "lira": "TRY",
        "dirham": "AED", "dirhams": "AED",
        "riyal": "SAR", "riyals": "SAR",
        "shekel": "ILS", "shekels": "ILS",
        "hryvnia": "UAH",
        "rand": "ZAR",
        "naira": "NGN",
        "kip": "LAK",
        "shilling": "KES",
    ]

    /// CJK currency spellings matched verbatim.
    private static let cjkCurrencyNames: [String: String] = [
        "元": "CNY", "块": "CNY", "圆": "CNY", "人民币": "CNY", "人民幣": "CNY",
        "美元": "USD", "美金": "USD",
        "日元": "JPY", "円": "JPY",
        "欧元": "EUR",
        "英镑": "GBP",
        "韩元": "KRW", "港币": "HKD", "港元": "HKD", "台币": "TWD",
        "澳元": "AUD", "加元": "CAD",
        "卢布": "RUB", "泰铢": "THB", "卢比": "INR",
        "ドル": "USD", "원": "KRW", "달러": "USD", "엔": "JPY", "루피": "INR",
    ]

    /// Maps a currency token — symbol, ISO code, alias or common name — to an ISO 4217 code.
    static func resolveCurrencyToken(_ rawToken: String, preferred: String) -> String? {
        let token = rawToken.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty else { return nil }

        if let code = currencySymbolCodeIfWholeToken(token, preferred: preferred) {
            return code
        }
        if let code = currencyAliases[token.uppercased()] {
            return code
        }
        let lower = token.lowercased()
        if lower == "dollar" || lower == "dollars" {
            return dollarFamilyCodes.contains(preferred) ? preferred : "USD"
        }
        if let code = currencyNames[lower] {
            return code
        }
        return cjkCurrencyNames[token]
    }

    /// Full-token symbol match (single-character symbols or prefixed ones like "US$").
    private static func currencySymbolCodeIfWholeToken(_ token: String, preferred: String) -> String? {
        guard currencySymbols.contains(token) else { return nil }
        return currencySymbolCode(token, preferred: preferred)
    }

    // MARK: - Non-current-system-language text

    static func isNonCurrentSystemLanguageText(
        _ text: String,
        systemLanguageIdentifier: String?
    ) -> Bool {
        guard let systemLanguageCode = primaryLanguageCode(from: systemLanguageIdentifier) else {
            return false
        }
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(text)
        guard let (detectedLanguage, confidence) = recognizer
            .languageHypotheses(withMaximum: 1)
            .max(by: { $0.value < $1.value }),
              confidence >= 0.5,
              let detectedLanguageCode = primaryLanguageCode(from: detectedLanguage.rawValue) else {
            return false
        }
        return detectedLanguageCode != systemLanguageCode
    }

    private static func primaryLanguageCode(from identifier: String?) -> String? {
        identifier?
            .replacingOccurrences(of: "_", with: "-")
            .split(separator: "-", maxSplits: 1)
            .first
            .map { $0.lowercased() }
    }

    private static func textDetail(for text: String) -> ClipboardAssistantDetail {
        let words = countWords(text)
        return words > 0
            ? .characterAndWordCount(characters: text.count, words: words)
            : .characterCount(text.count)
    }

    private static func isCJKScalar(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.value {
        case 0x4E00...0x9FFF,
             0x3400...0x4DBF,
             0x20000...0x2A6DF,
             0xF900...0xFAFF:
            true
        default:
            false
        }
    }

    private static func isChineseCharacter(_ character: Character) -> Bool {
        character.unicodeScalars.contains { isCJKScalar($0) }
    }

    // MARK: - Code

    /// Heuristic code detection. Three independent signals, matching how snippets actually get
    /// copied: a language keyword opening the first line, an unmistakable syntax signature anywhere
    /// in the snippet, or enough structural punctuation across a multi-line block. Returns `nil` for
    /// ordinary prose.
    static func codeDetection(_ text: String) -> ClipboardAssistantDetection? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 8 else { return nil }
        let lines = trimmed.components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        guard looksLikeCode(trimmed, lines: lines) else { return nil }

        let preview = previewText(trimmed)
        return ClipboardAssistantDetection(
            kind: .code,
            title: preview,
            detail: .codeLines(lines.count),
            actions: [.saveText(trimmed)],
            fullContent: trimmed.count <= 20_000 ? trimmed : String(trimmed.prefix(20_000))
        )
    }

    private static func looksLikeCode(_ text: String, lines: [String]) -> Bool {
        let strongPrefixes = [
            "#include", "#import", "#define", "import ", "package ", "using ", "namespace ",
            "func ", "def ", "class ", "struct ", "enum ", "interface ", "public class", "<?xml", "<!DOCTYPE",
        ]
        if let first = lines.first, strongPrefixes.contains(where: first.hasPrefix) { return true }

        // Regex scanning is capped so a huge paste cannot stall the 1 Hz clipboard poll.
        let sample = text.count <= 20_000 ? text : String(text.prefix(20_000))
        if codeSignaturePatterns.contains(where: { sample.range(of: $0, options: .regularExpression) != nil }) {
            return true
        }
        if sample.range(of: #"\bselect\b[\s\S]*\bfrom\b"#, options: [.regularExpression, .caseInsensitive]) != nil {
            return true
        }

        // Long CJK prose and progress transcripts often include isolated command names, paths,
        // percentages and operators. Without a declaration/signature above, those fragments must
        // not let weak structural punctuation reclassify the whole passage as source code.
        let cjkCharacters = sample.filter(isChineseCharacter).count
        if cjkCharacters >= 20, cjkCharacters * 4 >= sample.count {
            return false
        }

        // Multi-line assignment-with-call is common in copied snippets (e.g. `x = compute(a, b)` /
        // `y = x * 2`) but rarely in prose, so a single such line among two or more is enough.
        if lines.count >= 2,
           lines.contains(where: {
               $0.range(of: #"^\s*[A-Za-z_$][\w$]*\s*=\s*[A-Za-z_$][\w$]*\("#,
                        options: .regularExpression) != nil
           }) {
            return true
        }

        // Compound assignments are equally strong signals in short two-line snippets.
        if lines.count >= 2,
           lines.filter({
               $0.range(of: #"^\s*[A-Za-z_$][\w$]*\s*(\+=|-=|\*=|/=|%=)\s*"#,
                        options: .regularExpression) != nil
           }).count >= 2 {
            return true
        }

        // Punctuation alone is a weak signal, so it needs at least three lines with markers on half
        // of them. The threshold and line count are deliberately conservative: code blocks copied to
        // the clipboard rarely span only two short lines, while step-by-step prose does.
        guard lines.count >= 3 else { return false }
        let markerLines = lines.filter(hasStructuralMarker).count
        return markerLines * 2 >= lines.count
    }

    private static func hasStructuralMarker(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        // A line ending in a semicolon without any other code punctuation is usually a natural-language
        // step ("Step 1: install;") rather than code, so it does not count toward the marker threshold.
        if trimmed.hasSuffix(";"),
           !trimmed.contains("="),
           !trimmed.contains("{") {
            return false
        }
        // Parentheses are excluded here: ordinary prose routinely has "(see chapter 3)" or
        // "(Cmd+F)" per line. Calls and signatures are caught by codeSignaturePatterns or the
        // multi-line assignment check above; this predicate only flags punctuation-dense blocks.
        return line.contains("{") || line.contains("}")
            || line.contains("=>") || line.contains("->")
            || line.contains("==") || line.contains(":=")
            || line.contains("!=") || line.contains(">=") || line.contains("<=")
            || line.contains("+=") || line.contains("-=")
            || line.contains("*=") || line.contains("/=")
            || line.contains("&&") || line.contains("||")
    }

    /// Signatures that appear in source code but not in prose. Case-sensitive on purpose: a
    /// sentence opening with "Let me…" must not read as a `let` declaration. Patterns anchor to the
    /// start of a line where the keyword doubles as an English word ("class", "let", "import"), and
    /// float freely where it does not ("def foo(").
    private static let codeSignaturePatterns = [
        // Function definitions: `func greet(`, `def main(`, `function handler(`, `fn run(`
        #"\b(func|fn|def|function)\s+[A-Za-z_$][\w$]*\s*[(<]"#,
        // Type declarations with optional access modifiers
        #"(?m)^\s*((public|private|internal|fileprivate|open|final|abstract|export|data)\s+)*(class|struct|enum|interface|protocol|trait|impl|record)\s+[A-Za-z_]\w*"#,
        // Declarations carrying an initializer or type annotation, behind any attributes or access
        // modifiers: `let items = …`, `const x: T`, `@State private var isOn = false`
        #"(?m)^\s*(@\w+(\([^)]*\))?\s+)*((public|private|internal|fileprivate|open|final|static|lazy|weak|unowned)\s+)*(let|var|const|val)\s+[A-Za-z_$][\w$]*\s*[:=]"#,
        // Imports and includes, each pinned to its language's shape so "from the start" stays prose
        #"(?m)^\s*(import|#include|#import)\s+[\w"'<@./{*]"#,
        #"(?m)^\s*from\s+[\w.]+\s+import\s"#,
        #"(?m)^\s*using\s+[\w.]+\s*;"#,
        #"(?m)^\s*package\s+[\w.]+\s*;?\s*$"#,
        #"(?m)^\s*export\s+(default|const|let|var|function|class|\{|\*)"#,
        #"\brequire\s*\(\s*['\"]"#,
        // Control flow opening a block
        #"(?m)^\s*(if|for|while|switch|foreach|elif|else|guard|match)\b.*[):{]\s*$"#,
        // Print and logging calls
        #"\b(print|println|printf|NSLog|echo|puts)\s*\("#,
        #"\b(console|logger|System\.out)\s*\.\s*\w+\s*\("#,
        #"\b[A-Za-z_$][\w$]*\s*\.\s*[A-Za-z_$][\w$]*\s*\("#,
        // Quoted keys of JSON and object literals
        #""[\w-]+"\s*:"#,
        // Lines made only of closing punctuation
        #"(?m)^\s*[}\])]+;?\s*$"#,
        // Markup, stylesheets and shebangs
        #"</[A-Za-z][\w:-]*>"#,
        #"<[A-Za-z][\w:-]*(\s+[\w:-]+\s*=\s*("[^"]*"|'[^']*'))+\s*/?>"#,
        #"(?m)^\s*[\w-]+\s*:\s*[^\s;{}]+;\s*$"#,
        #"@(media|import|keyframes|supports)\b"#,
        #"(?m)^\s*#!\s*\S*/"#,
    ]

    /// Guesses a file extension from code content so saved snippets land with a useful name.
    static func guessCodeFileExtension(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.contains("#include") || trimmed.contains("std::") { return "cpp" }
        if trimmed.contains("<?php") { return "php" }
        if trimmed.hasPrefix("<?xml") { return "xml" }
        if trimmed.contains("<!DOCTYPE html") || trimmed.contains("<html") { return "html" }
        if trimmed.hasPrefix("{") || trimmed.hasPrefix("["),
           trimmed.range(of: #""\s*:"#, options: .regularExpression) != nil {
            return "json"
        }
        if trimmed.contains("func ") && (trimmed.contains("let ") || trimmed.contains("var ")) { return "swift" }
        if trimmed.contains("fn ") && trimmed.contains("-> ") { return "rs" }
        if trimmed.contains("def ") || (trimmed.contains(":") && trimmed.contains("\n    ")) { return "py" }
        if trimmed.contains("=>") || trimmed.contains("const ") || trimmed.contains("console.log") { return "js" }
        if trimmed.contains("public ") || trimmed.contains("System.out") { return "java" }
        if trimmed.uppercased().contains("SELECT") && trimmed.uppercased().contains("FROM") { return "sql" }
        if trimmed.contains("@media") || (trimmed.contains("{") && trimmed.contains(":") && trimmed.contains(";")) { return "css" }
        if trimmed.contains("#!") && trimmed.contains("bash") { return "sh" }
        return "txt"
    }

    // MARK: - Colors

    /// Parses common CSS color notations into sRGB components.
    public static func parseColor(_ text: String) -> ClipboardAssistantDetection? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        let hexPattern = #"^#(?:[0-9a-f]{3}|[0-9a-f]{4}|[0-9a-f]{6}|[0-9a-f]{8})$"#
        if trimmed.range(of: hexPattern, options: .regularExpression) != nil {
            let hex = String(trimmed.dropFirst())
            var red = 0.0, green = 0.0, blue = 0.0
            switch hex.count {
            case 3, 4:
                let values = hex.prefix(3).compactMap(\.hexDigitValue).map { Double($0) / 15 }
                guard values.count == 3 else { return nil }
                (red, green, blue) = (values[0], values[1], values[2])
            default:
                let hexPairs = Array(hex.prefix(6))
                var values: [Double] = []
                for pair in stride(from: 0, to: hexPairs.count - 1, by: 2) {
                    guard let byte = UInt8(String(hexPairs[pair...pair + 1]), radix: 16) else { break }
                    values.append(Double(byte) / 255)
                }
                guard values.count == 3 else { return nil }
                (red, green, blue) = (values[0], values[1], values[2])
            }
            return makeColorDetection(text: trimmed, red: red, green: green, blue: blue)
        }

        if let inner = functionArgument(of: "rgb", in: trimmed) ?? functionArgument(of: "rgba", in: trimmed) {
            let parts = inner.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
            if parts.count >= 3,
               let red = Double(parts[0]), let green = Double(parts[1]), let blue = Double(parts[2]),
               (0...255).contains(red), (0...255).contains(green), (0...255).contains(blue) {
                return makeColorDetection(
                    text: trimmed,
                    red: red / 255,
                    green: green / 255,
                    blue: blue / 255
                )
            }
        }

        if let inner = functionArgument(of: "hsl", in: trimmed) ?? functionArgument(of: "hsla", in: trimmed) {
            let parts = inner.split(separator: ",").map {
                $0.trimmingCharacters(in: CharacterSet(charactersIn: "%deg").union(.whitespaces))
            }
            if parts.count >= 3,
               let hue = Double(parts[0]), let sat = Double(parts[1]), let light = Double(parts[2]),
               (0...360).contains(hue), (0...100).contains(sat), (0...100).contains(light) {
                let rgb = hslToRGB(h: hue, s: sat / 100, l: light / 100)
                return makeColorDetection(text: trimmed, red: rgb.red, green: rgb.green, blue: rgb.blue)
            }
        }
        return nil
    }

    /// Matches `name(...)` and returns the argument list inside the parentheses.
    private static func functionArgument(of name: String, in text: String) -> Substring? {
        guard text.hasPrefix(name), text.hasSuffix(")"),
              text.dropFirst(name.count).hasPrefix("(") else { return nil }
        return text.dropFirst(name.count + 1).dropLast(1)
    }

    private static func makeColorDetection(
        text: String,
        red: Double,
        green: Double,
        blue: Double
    ) -> ClipboardAssistantDetection {
        let hex = [red, green, blue]
            .map { UInt8(max(0, min(255, ($0 * 255).rounded()))) }
            .map { String(format: "%02x", $0) }
            .joined()
        return ClipboardAssistantDetection(
            kind: .color,
            title: text,
            detail: .rgb(red: red, green: green, blue: blue, hex: hex),
            actions: [.copyText("#" + hex)],
            colorComponents: ClipboardAssistantDetection.ColorComponents(
                red: red,
                green: green,
                blue: blue
            )
        )
    }

    private static func hslToRGB(h hue: Double, s: Double, l: Double) -> (red: Double, green: Double, blue: Double) {
        let c = (1 - abs(2 * l - 1)) * s
        let hp = hue / 60
        let x = c * (1 - abs(hp.truncatingRemainder(dividingBy: 2) - 1))
        let rgb: (Double, Double, Double)
        switch hp {
        case ..<1: rgb = (c, x, 0)
        case ..<2: rgb = (x, c, 0)
        case ..<3: rgb = (0, c, x)
        case ..<4: rgb = (0, x, c)
        case ..<5: rgb = (x, 0, c)
        default: rgb = (c, 0, x)
        }
        let m = l - c / 2
        return (rgb.0 + m, rgb.1 + m, rgb.2 + m)
    }

    /// Evaluates a plain arithmetic expression with a small recursive-descent parser.
    /// NSExpression is deliberately avoided: its initializer raises unrecoverable Objective-C
    /// exceptions on malformed input instead of returning an error.
    public static func evaluateArithmetic(_ text: String) -> Double? {
        guard var expression = arithmeticExpression(from: text) else { return nil }
        for (source, target) in [("×", "*"), ("÷", "/"), ("−", "-")] {
            expression = expression.replacingOccurrences(of: source, with: target)
        }
        // Must contain at least one binary operator to be worth treating as an expression.
        guard expression.dropFirst().contains(where: { "+-*/^".contains($0) }) else { return nil }
        var parser = ArithmeticParser(expression)
        guard let value = parser.parse(), value.isFinite else { return nil }
        return value
    }

    private static func arithmeticExpression(from text: String) -> String? {
        var expression = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard expression.count <= 200 else { return nil }
        if expression.last == "=" {
            expression.removeLast()
            expression = expression.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        guard !expression.isEmpty, !expression.contains("=") else { return nil }
        return expression
    }

    public static func formatNumber(_ value: Double, locale: Locale = .current) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.locale = locale
        formatter.groupingSeparator = ""
        formatter.maximumFractionDigits = abs(value.rounded() - value) < 1e-9 ? 0 : 6
        return formatter.string(from: NSNumber(value: value)) ?? String(value)
    }
}

/// Minimal recursive-descent arithmetic evaluator supporting + - * / ^ ** parentheses and decimals.
private struct ArithmeticParser {
    private let scalars: [Unicode.Scalar]
    private var index = 0

    init(_ expression: String) {
        scalars = Array(expression.unicodeScalars)
    }

    mutating func parse() -> Double? {
        guard !scalars.isEmpty else { return nil }
        let value = parseExpression()
        guard index == scalars.count else { return nil }
        return value
    }

    private mutating func parseExpression() -> Double? {
        var left = parseTerm()
        skipSpaces()
        while let op = currentOperator(where: { $0 == "+" || $0 == "-" }) {
            advance()
            guard let right = parseTerm(), let current = left else { return nil }
            left = op == "+" ? current + right : current - right
            skipSpaces()
        }
        return left
    }

    private mutating func parseTerm() -> Double? {
        var left = parseFactor()
        skipSpaces()
        while let op = currentOperator(where: { $0 == "*" || $0 == "/" }) {
            advance()
            guard let right = parseFactor(), let current = left else { return nil }
            guard op != "/" || right != 0 else { return nil }
            left = op == "*" ? current * right : current / right
            skipSpaces()
        }
        return left
    }

    private mutating func parseFactor() -> Double? {
        skipSpaces()
        if consume("+") { return parseFactor() }
        if consume("-") { return parseFactor().map(-) }
        return parsePower()
    }

    private mutating func parsePower() -> Double? {
        guard let base = parsePrimary() else { return nil }
        guard consumePowerOperator() else { return base }
        guard let exponent = parseFactor() else { return nil }
        let value = pow(base, exponent)
        return value.isFinite ? value : nil
    }

    private mutating func parsePrimary() -> Double? {
        skipSpaces()
        if consume("(") {
            let value = parseExpression()
            skipSpaces()
            guard consume(")"), let value else { return nil }
            return value
        }
        return parseNumber()
    }

    private mutating func consumePowerOperator() -> Bool {
        skipSpaces()
        if consume("^") { return true }
        guard index + 1 < scalars.count,
              scalars[index] == "*",
              scalars[index + 1] == "*" else {
            return false
        }
        index += 2
        return true
    }

    private mutating func parseNumber() -> Double? {
        skipSpaces()
        var hasDigit = false
        var hasDot = false
        var text = ""
        while index < scalars.count {
            let scalar = scalars[index]
            if scalar.properties.numericType == .decimal {
                hasDigit = true
                text.unicodeScalars.append(scalar)
                advance()
            } else if scalar == "." && !hasDot && hasDigit {
                hasDot = true
                text.unicodeScalars.append(scalar)
                advance()
            } else {
                break
            }
        }
        guard hasDigit, let value = Double(text) else { return nil }
        return value
    }

    private func currentOperator(where predicate: (Character) -> Bool) -> Character? {
        guard index < scalars.count else { return nil }
        let character = Character(scalars[index])
        return predicate(character) ? character : nil
    }

    private mutating func consume(_ expected: Character) -> Bool {
        guard index < scalars.count, Character(scalars[index]) == expected else { return false }
        advance()
        return true
    }

    private mutating func skipSpaces() {
        while index < scalars.count, scalars[index].properties.isWhitespace { advance() }
    }

    private mutating func advance() { index += 1 }
}
