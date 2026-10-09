import AppKit

public enum FileShelfPasteboard {
    @discardableResult
    public static func writeItems(_ items: [FileShelfItem], screenshotData: [UUID: Data] = [:], to pasteboard: NSPasteboard = .general) -> Bool {
        guard !items.isEmpty else { return false }
        var writers: [any NSPasteboardWriting] = []
        for item in items {
            if item.screenshotMetadata != nil {
                guard let data = screenshotData[item.id], let image = NSImage(data: data),
                      let tiff = image.tiffRepresentation else { return false }
                let writer = NSPasteboardItem()
                guard writer.setData(data, forType: .png), writer.setData(tiff, forType: .tiff) else { return false }
                writers.append(writer)
            } else {
                writers.append(pasteboardWriter(for: item.payload))
            }
        }
        pasteboard.clearContents()
        return pasteboard.writeObjects(writers)
    }

    public static func pasteboardWriter(for payload: TransferPasteboardPayload) -> any NSPasteboardWriting {
        switch payload {
        case .file(let url): return url as NSURL
        case .text(let text):
            let item = NSPasteboardItem()
            item.setString(text, forType: .string)
            if let url = TransferPasteboard.webURL(from: text) {
                item.setString(url.absoluteString, forType: .URL)
            }
            return item
        }
    }

    @discardableResult
    public static func writeFileURLs(
        _ urls: [URL],
        to pasteboard: NSPasteboard = .general
    ) -> Bool {
        var seen = Set<String>()
        let writers = urls.compactMap { url -> NSURL? in
            let normalized = url.standardizedFileURL
            guard normalized.isFileURL, seen.insert(normalized.path).inserted else { return nil }
            return normalized as NSURL
        }
        guard !writers.isEmpty else { return false }
        pasteboard.clearContents()
        return pasteboard.writeObjects(writers)
    }

    public static func readFileURLs(
        from pasteboard: NSPasteboard = .general
    ) -> [URL] {
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
}
