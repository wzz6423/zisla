import Foundation
import ImageIO
import CoreGraphics

/// 把 Markdown 渲染出的 HTML 中 `<img src="...">` 指向本地文件的部分改写为
/// base64 data URL，使 `MarkdownWebView`（`WKWebView.loadHTMLString`）能正常显示图片。
///
/// `loadHTMLString(_:baseURL:)` 不会授予 baseURL 目录的文件读取权限，
/// 因此 `<img src="/Users/.../foo.jpg">` 这类本地引用会被 WKWebView 拒绝、
/// 显示为破图占位符（在透明背景 + 深色毛玻璃下呈现为"模糊蓝色"）。
/// 在原生侧把图片预读并内联进 HTML，能完全绕开 WKWebView 的 file:// 子资源限制，
/// 无需切换到 `loadFileURL(_:allowingReadAccessTo:)`。
///
/// 处理策略：
/// - `/abs/path`、`~/path`、`file://...` 视为本地文件，读取并内联。
/// - `http://`、`https://`、`data:` 保留原值（由 WKWebView 直接加载）。
/// - 读取失败、文件不存在或过大（内联后 >30 MB）的情况保留原值，不引入回归。
/// - 超过 2 MB 的图片用 ImageIO 解码后缩放至最长边 1600 px 并重编码为 JPEG，
///   避免 base64 字符串过大导致 WKWebView 渲染卡顿。
public enum MarkdownImageInliner {
    /// 内联后仍超过此体积则放弃，避免 HTML 文档过大。
    private static let maxInlineBytes = 30 * 1024 * 1024
    /// 超过此体积触发缩放。
    private static let downscaleThreshold = 2 * 1024 * 1024
    private static let downscaleMaxDimension = 1600

    /// 简单的 URL → data URL 缓存，避免每次重渲染都重新读盘。
    /// `NSCache` 自身线程安全，用 `nonisolated(unsafe)` 声明以满足严格并发检查。
    private nonisolated(unsafe) static let cache: NSCache<NSString, NSString> = {
        let c = NSCache<NSString, NSString>()
        c.countLimit = 32
        return c
    }()

    /// 扫描 HTML 中所有 `<img>` 标签，把本地文件 src 改写为 data URL；其余保持原样。
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
            // MarkdownHTMLRenderer 的 escapeHTML + attributeEscape 管线会把
            // URL 中的 & < > " 转义为 HTML 实体（如 &amp;），此处需还原
            // 才能正确读取本地文件。
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

    /// 清空进程内缓存（主要用于测试）。
    static func clearCache() {
        cache.removeAllObjects()
    }

    // MARK: - URL 解析

    /// 还原 escapeHTML / attributeEscape 产生的基本 HTML 实体。
    private static func unescapeHTMLEntities(_ string: String) -> String {
        string
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
    }

    /// 把 Markdown/HTML 里写的图片 src 解析成本地文件 URL；非本地来源返回 nil。
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

    /// 用 ImageIO 解码 → 生成最长边 1600 px 的缩略图 → 重编码为 JPEG。
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

    // MARK: - 正则替换

    /// 从后往前替换的简易正则助手（行为与 `MarkdownHTMLRenderer.replace` 一致）。
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
