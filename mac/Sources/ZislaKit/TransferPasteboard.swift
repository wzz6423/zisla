import AppKit
import Foundation

/// Clipboard payloads accepted by the system share flow (files and plain text).
public enum TransferPasteboardPayload: Hashable, Sendable {
    case file(URL)
    case text(String)
}

/// Reads shareable items from a pasteboard without writing or clearing it.
public enum TransferPasteboard {
    public static let shelfDropTypes: [NSPasteboard.PasteboardType] =
        [.fileURL, .URL, .string, .png, .tiff]
        + NSFilePromiseReceiver.readableDraggedTypes.map { NSPasteboard.PasteboardType($0) }

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

    /// A drag may contain separate files, links, and text; alternatives on one item are read once.
    public static func readShelfItems(
        from pasteboard: NSPasteboard = .general
    ) -> [TransferPasteboardPayload] {
        var seen = Set<TransferPasteboardPayload>()
        return (pasteboard.pasteboardItems ?? []).compactMap { item in
            guard let payload = shelfPayload(from: item) else { return nil }
            return seen.insert(payload).inserted ? payload : nil
        }
    }

    public static func readShelfDropItems(from pasteboard: NSPasteboard) -> [FileShelfDropItem] {
        var promises = (pasteboard.readObjects(forClasses: [NSFilePromiseReceiver.self]) as? [NSFilePromiseReceiver] ?? []).makeIterator()
        return (pasteboard.pasteboardItems ?? []).compactMap { item in
            if item.types.contains(where: { NSFilePromiseReceiver.readableDraggedTypes.contains($0.rawValue) }) {
                return promises.next().map(FileShelfDropItem.promise)
            }
            if let payload = shelfPayload(from: item) { return .content(payload) }
            for type in [NSPasteboard.PasteboardType.png, .tiff] {
                if let data = item.data(forType: type) { return .image(data) }
            }
            return nil
        }
    }

    private static func shelfPayload(from item: NSPasteboardItem) -> TransferPasteboardPayload? {
        if item.types.contains(where: { NSFilePromiseReceiver.readableDraggedTypes.contains($0.rawValue) }) {
            return nil
        }
        if let raw = item.string(forType: .fileURL) {
            guard let url = URL(string: raw), url.isFileURL,
                  FileManager.default.fileExists(atPath: url.path) else { return nil }
            return .file(url.standardizedFileURL)
        }
        if let raw = item.string(forType: .URL), let url = webURL(from: raw) {
            return .text(url.absoluteString)
        }
        if let raw = item.string(forType: .string),
           !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return .text(raw)
        }
        return nil
    }

    public static func webURL(from text: String) -> URL? {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.contains(where: { $0.isWhitespace || $0.isNewline }),
              let url = URL(string: value),
              ["http", "https"].contains(url.scheme?.lowercased()),
              let host = url.host, !host.isEmpty else { return nil }
        return url
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
