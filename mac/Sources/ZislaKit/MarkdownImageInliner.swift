import Foundation
import ImageIO
import CoreGraphics

/// Rewrites `<img src="...">` tags in Markdown-rendered HTML that reference local files
/// to base64 data URLs, so `MarkdownWebView` (`WKWebView.loadHTMLString`) can display images correctly.
///
/// `loadHTMLString(_:baseURL:)` does not grant read access to the baseURL directory,
/// so local references like `<img src="/Users/.../foo.jpg">` are rejected by WKWebView and
/// shown as broken-image placeholders (appearing as "blurry blue" on transparent dark-frosted-glass backgrounds).
/// Pre-reading images on the native side and inlining them into the HTML completely bypasses
/// WKWebView's file:// sub-resource restriction without switching to `loadFileURL(_:allowingReadAccessTo:)`.
///
/// Processing strategy:
/// - `/abs/path`, `~/path`, `file://...` are treated as local files, read and inlined.
/// - `http://`, `https://`, `data:` are left as-is (loaded directly by WKWebView).
/// - Files that fail to read, do not exist, or would exceed 30 MB inline are left as-is to avoid regressions.
/// - Images larger than 2 MB are decoded with ImageIO, scaled to a 1600 px long edge, and re-encoded as JPEG
///   to prevent oversized base64 strings from causing WKWebView rendering stalls.
public enum MarkdownImageInliner {
    /// If the inlined size still exceeds this limit, abandon inlining to avoid an oversized HTML document.
    private static let maxInlineBytes = 30 * 1024 * 1024
    /// Images above this size trigger downscaling.
    private static let downscaleThreshold = 2 * 1024 * 1024
    private static let downscaleMaxDimension = 1600

    /// Simple URL → data URL cache to avoid re-reading from disk on every re-render.
    /// `NSCache` is thread-safe; declared with `nonisolated(unsafe)` to satisfy strict concurrency checking.
    private nonisolated(unsafe) static let cache: NSCache<NSString, NSString> = {
        let c = NSCache<NSString, NSString>()
        c.countLimit = 32
        return c
    }()

    /// Scans all `<img>` tags in the HTML and rewrites local file src values to data URLs; others are left unchanged.
    public static func inlineLocalImages(in html: String) -> String {
        replace(html, pattern: #"(?i)<img\b([^>]*)>"#) { match, _ in
            let attrs = match[1]
            guard let regex = try? NSRegularExpression(pattern: #"(?i)\bsrc\s*=\s*(?:"([^"]+)"|'([^']+)')"#),
                  let srcMatch = regex.firstMatch(
                    in: attrs,
                    range: NSRange(attrs.startIndex..., in: attrs)
                  )
            else { return match[0] }

            let sourceRange = srcMatch.range(at: srcMatch.range(at: 1).location == NSNotFound ? 2 : 1)
            let raw = (attrs as NSString).substring(with: sourceRange)
            // The escapeHTML + attributeEscape pipeline in MarkdownHTMLRenderer encodes
            // & < > " in URLs as HTML entities (e.g. &amp;); unescape here to correctly
            // read the local file.
            let unescaped = unescapeHTMLEntities(raw)
            guard let resolved = resolveLocalFileURL(unescaped),
                  let dataURL = dataURL(for: resolved)
            else { return match[0] }

            let updated = (attrs as NSString).replacingCharacters(
                in: sourceRange,
                with: dataURL
            )
            return "<img \(updated)>"
        }
    }

    /// Clears the in-process cache (mainly for tests).
    static func clearCache() {
        cache.removeAllObjects()
    }

    // MARK: - URL resolution

    /// Restores basic HTML entities produced by escapeHTML / attributeEscape.
    private static func unescapeHTMLEntities(_ string: String) -> String {
        string
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
    }

    /// Resolves an image src from Markdown/HTML to a local file URL; returns nil for non-local sources.
    private static func resolveLocalFileURL(_ raw: String) -> URL? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if trimmed.hasPrefix("http://") || trimmed.hasPrefix("https://") || trimmed.hasPrefix("data:") {
            return nil
        }
        if trimmed.hasPrefix("file://") {
            guard let url = URL(string: trimmed), url.isFileURL else { return nil }
            return url
        }
        if trimmed.hasPrefix("~") {
            return URL(fileURLWithPath: (trimmed as NSString).expandingTildeInPath)
        }
        if trimmed.hasPrefix("/") {
            return URL(fileURLWithPath: trimmed)
        }
        return nil
    }

    // MARK: - data URL

    private static func dataURL(for url: URL) -> String? {
        let key = url.standardizedFileURL.path as NSString
        if let cached = cache.object(forKey: key) {
            return cached as String
        }
        guard let data = try? Data(contentsOf: url) else { return nil }

        let mime = mimeType(for: url.pathExtension.lowercased())
        let processed: Data
        let processedMime: String

        if data.count > downscaleThreshold,
           let downsized = downscale(data: data, maxDimension: downscaleMaxDimension) {
            processed = downsized
            processedMime = "image/jpeg"
        } else {
            processed = data
            processedMime = mime
        }

        guard processed.count <= maxInlineBytes else { return nil }

        let encoded = processed.base64EncodedString()
        let result = "data:\(processedMime);base64,\(encoded)"
        cache.setObject(result as NSString, forKey: key)
        return result
    }

    private static func mimeType(for ext: String) -> String {
        switch ext {
        case "jpg", "jpeg": return "image/jpeg"
        case "png":         return "image/png"
        case "gif":         return "image/gif"
        case "webp":        return "image/webp"
        case "heic", "heif": return "image/heic"
        case "tiff", "tif": return "image/tiff"
        case "bmp":         return "image/bmp"
        case "svg":         return "image/svg+xml"
        default:            return "application/octet-stream"
        }
    }

    /// Decodes with ImageIO → creates a thumbnail with the long edge at 1600 px → re-encodes as JPEG.
    private static func downscale(data: Data, maxDimension: Int) -> Data? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxDimension,
        ]
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
        else { return nil }
        let mutable = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(
            mutable,
            "public.jpeg" as CFString,
            1,
            nil
        ) else { return nil }
        let destOptions: [CFString: Any] = [
            kCGImageDestinationLossyCompressionQuality: 0.85,
        ]
        CGImageDestinationAddImage(dest, cgImage, destOptions as CFDictionary)
        guard CGImageDestinationFinalize(dest) else { return nil }
        return mutable as Data
    }

    // MARK: - Regex replacement

    /// Simple back-to-front regex replacement helper (same behavior as `MarkdownHTMLRenderer.replace`).
    private static func replace(
        _ string: String,
        pattern: String,
        _ handler: ([String], String) -> String
    ) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return string }
        let ns = string as NSString
        let matches = regex.matches(in: string, range: NSRange(string.startIndex..., in: string))
        var result = string
        for match in matches.reversed() {
            let whole = ns.substring(with: match.range)
            var groups: [String] = [whole]
            for i in 1..<match.numberOfRanges {
                let range = match.range(at: i)
                groups.append(range.location == NSNotFound ? "" : ns.substring(with: range))
            }
            let replacement = handler(groups, whole)
            result = (result as NSString).replacingCharacters(in: match.range, with: replacement)
        }
        return result
    }
}
