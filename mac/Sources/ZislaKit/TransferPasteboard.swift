import AppKit
import Foundation

/// Clipboard payloads accepted by the system share flow (files and plain text).
public enum TransferPasteboardPayload: Hashable, Sendable {
    case file(URL)
    case text(String)
}

/// Reads shareable items from a pasteboard without writing or clearing it.
public enum TransferPasteboard {
    /// Local file URLs that currently exist, then plain text if no files are present.
    /// Text HTTP(S) strings stay as text (not coerced into downloads).
    public static func readShareableItems(
        from pasteboard: NSPasteboard = .general
    ) -> [TransferPasteboardPayload] {
        let files = readExistingFileURLs(from: pasteboard)
        if !files.isEmpty {
            return files.map { .file($0) }
        }

        if let text = readPlainText(from: pasteboard) {
            return [.text(text)]
        }
        return []
    }

    private static func readExistingFileURLs(from pasteboard: NSPasteboard) -> [URL] {
        let options: [NSPasteboard.ReadingOptionKey: Any] = [
            .urlReadingFileURLsOnly: true
        ]
        let values = pasteboard.readObjects(
            forClasses: [NSURL.self],
            options: options
        ) as? [NSURL] ?? []

        var seen = Set<String>()
        var result: [URL] = []
        for value in values {
            let url = (value as URL).standardizedFileURL
            guard url.isFileURL else { continue }
            guard FileManager.default.fileExists(atPath: url.path) else { continue }
            let key = url.path
            guard seen.insert(key).inserted else { continue }
            result.append(url)
        }
        return result
    }

    private static func readPlainText(from pasteboard: NSPasteboard) -> String? {
        let raw = pasteboard.string(forType: .string)
            ?? pasteboard.string(forType: .init("public.utf8-plain-text"))
        guard let raw else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
