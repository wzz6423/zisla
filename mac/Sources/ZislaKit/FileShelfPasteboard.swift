import AppKit

public enum FileShelfPasteboard {
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
