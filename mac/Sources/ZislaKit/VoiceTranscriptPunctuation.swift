import Foundation
import ZislaCore

package enum VoiceTranscriptPunctuation {
    private static let punctuation = try! NSRegularExpression(pattern: #"[,.;:!?，。；：！？](?:[,.;:!?，。；：！？]|\h+(?=[,.;:!?，。；：！？]))*"#)
    private static let cjk = try! NSRegularExpression(pattern: #"[\p{Han}\p{Hiragana}\p{Katakana}]"#)
    private static let newlines = try! NSRegularExpression(pattern: #"\r\n|[\r\n]"#)
    private static let technical = try! NSRegularExpression(pattern:
        #"\p{N}+(?:[.,:/-]\p{N}+)+|(?m:^\h*\p{N}+[.)、])|(?i:\b(?:Mr|Mrs|Ms|Dr|Prof|Sr|Jr|St|vs|etc)\.)|(?:\b[A-Za-z]\.){2,}|\b[A-Za-z_]\w*\([^()\r\n]*\)"#
    )
    private static let commandNames: Set<String> = ["git", "curl", "echo", "printf", "ssh", "npm", "pnpm", "swift", "python", "python3", "make"]
    private static let fullWidth: [Character: Character] = [
        ",": "，", ".": "。", ";": "；", ":": "：", "?": "？", "!": "！",
    ]

    package static func normalize(_ text: String, customHotwords: [String] = []) -> String {
        let source = text as NSString
        let range = NSRange(location: 0, length: source.length)
        var protected = VoiceLexicon.normalizationProtectedRanges(in: text)
        for term in VoiceLexicon.normalizedCustomTerms(customHotwords) {
            let expression = try! NSRegularExpression(
                pattern: "(?<![A-Za-z0-9])\(NSRegularExpression.escapedPattern(for: term))(?![A-Za-z0-9])",
                options: [.caseInsensitive]
            )
            for match in expression.matches(in: text, range: range) {
                protected.insert(integersIn: match.range.location..<NSMaxRange(match.range))
            }
        }
        // Literal contents must not make a prose sentence look like executable source code.
        let codeSample = NSMutableString(string: text)
        for span in protected.rangeView.reversed() {
            codeSample.replaceCharacters(
                in: NSRange(location: span.lowerBound, length: span.count), with: "\"literal\""
            )
        }
        guard ClipboardAssistantDetector.codeDetection(codeSample as String) == nil else { return text }
        guard ClipboardAssistantDetector.shellCommand(from: codeSample as String, commandExists: commandNames.contains) == nil else { return text }
        for match in technical.matches(in: text, range: range) {
            protected.insert(integersIn: match.range.location..<NSMaxRange(match.range))
        }
        var editable = IndexSet()
        for match in punctuation.matches(in: text, range: range) {
            editable.insert(integersIn: match.range.location..<NSMaxRange(match.range))
        }
        editable.subtract(protected)
        let matches = editable.rangeView.compactMap { span -> NSRange? in
            var start = span.lowerBound
            let end = span.upperBound
            while start < end, isHorizontalSpace(source.character(at: start)) { start += 1 }
            return start < end ? NSRange(location: start, length: end - start) : nil
        }
        // Sentence-local script detection keeps English sentences beside Chinese prose in English.
        let boundaries = ([0, source.length]
            + newlines.matches(in: text, range: range).filter {
                !protected.contains($0.range.location)
            }.map { NSMaxRange($0.range) }
            + matches.filter {
                source.substring(with: $0).contains(where: { ".。!?！？".contains($0) })
            }.map { NSMaxRange($0) }).sorted()
        var cjkCharacters = IndexSet()
        for match in cjk.matches(in: text, range: range)
            where !protected.intersects(integersIn: match.range.location..<NSMaxRange(match.range)) {
            cjkCharacters.insert(integersIn: match.range.location..<NSMaxRange(match.range))
        }
        var cjkSentences = IndexSet()
        for (start, end) in zip(boundaries, boundaries.dropFirst())
            where cjkCharacters.intersects(integersIn: start..<end) {
            cjkSentences.insert(integersIn: start..<end)
        }

        let result = NSMutableString(string: text)
        // Apply UTF-16 ranges backwards so edits never shift later matches or Unicode literals.
        for match in matches.reversed() {
            let original = source.substring(with: match).filter { !$0.isWhitespace }
            if original.contains("..") { continue }
            if original.contains("::") { continue }
            let usesCJK = cjkSentences.contains(match.location)
            var marks = original.map { usesCJK ? fullWidth[$0, default: $0] : $0 }
            if let terminal = marks.firstIndex(where: { ".。!?！？".contains($0) }) {
                marks.removeFirst(terminal)
            }
            if marks.contains(where: { "!?！？".contains($0) }) {
                marks.removeAll { ".。".contains($0) }
            }
            let first = marks[0]
            if ",，;；。".contains(first), marks.allSatisfy({ $0 == first }) {
                marks = [first]
            }
            var start = match.location
            while start > 0, isHorizontalSpace(source.character(at: start - 1)) {
                start -= 1
            }
            if start == 0 || "\r\n".utf16.contains(source.character(at: start - 1)) {
                start = match.location
            }
            var end = NSMaxRange(match)
            while end < source.length, isHorizontalSpace(source.character(at: end)) {
                end += 1
            }
            // Trailing spaces and indentation can encode Markdown line breaks and list layout.
            if end == source.length || "\r\n".utf16.contains(source.character(at: end)) {
                end = NSMaxRange(match)
            }
            var replacement = String(marks)
            if marks.allSatisfy({ ",.;:!?".contains($0) }), end < source.length,
               let next = UnicodeScalar(source.character(at: end)),
               CharacterSet.alphanumerics.contains(next) || "\"'“‘([{".unicodeScalars.contains(next) {
                replacement += " "
            }
            result.replaceCharacters(
                in: NSRange(location: start, length: end - start), with: replacement
            )
        }
        return result as String
    }

    private static func isHorizontalSpace(_ value: unichar) -> Bool {
        UnicodeScalar(value).map(CharacterSet.whitespaces.contains) ?? false
    }
}
