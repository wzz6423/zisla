import CoreFoundation
import Foundation

enum MailHTMLBody {
    private static let maximumBytes = 20 * 1_024 * 1_024

    static func html(from source: String) -> String? {
        guard source.utf8.count <= maximumBytes else { return nil }
        let normalized = source.replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        let content = parse(normalized, depth: 0)
        guard var html = content.html, !html.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }
        let references = /(?i)cid:([^\s"'<>\)]+)/
        var size = html.utf8.count
        for match in html.matches(of: references).reversed() {
            let identifier = String(match.1).removingPercentEncoding ?? String(match.1)
            if let image = content.images[identifier] {
                size += image.utf8.count - match.0.utf8.count
                guard size <= maximumBytes else { return nil }
                html.replaceSubrange(match.range, with: image)
            }
        }
        return html
    }

    private struct Content {
        var html: String?
        var images: [String: String] = [:]
    }

    private static func parse(_ source: String, depth: Int) -> Content {
        guard depth < 16, let separator = source.range(of: "\n\n") else { return Content() }
        var headers: [String: String] = [:]
        var name = ""
        for line in source[..<separator.lowerBound].components(separatedBy: "\n") {
            if line.first == " " || line.first == "\t" {
                headers[name, default: ""] += " " + line.trimmingCharacters(in: .whitespaces)
            } else if let colon = line.firstIndex(of: ":") {
                name = line[..<colon].lowercased()
                headers[name] = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            }
        }
        let (type, parameters) = headerValue(headers["content-type"] ?? "text/plain")
        let (disposition, _) = headerValue(headers["content-disposition"] ?? "")
        // Referenced images can be labelled attachments; attached HTML and messages are not the body.
        guard disposition != "attachment" || type.hasPrefix("image/") else { return Content() }
        let body = String(source[separator.upperBound...])
        if type.hasPrefix("multipart/") {
            guard let boundary = parameters["boundary"], !boundary.isEmpty else { return Content() }
            var result = Content()
            var lines: [String]?
            for line in body.components(separatedBy: "\n") {
                var delimiter = line
                while delimiter.last == " " || delimiter.last == "\t" { delimiter.removeLast() }
                if delimiter == "--" + boundary || delimiter == "--" + boundary + "--" {
                    if let lines {
                        let child = parse(lines.joined(separator: "\n"), depth: depth + 1)
                        if result.html == nil || type == "multipart/alternative" {
                            result.html = child.html ?? result.html
                        }
                        result.images.merge(child.images) { first, _ in first }
                    }
                    if delimiter == "--" + boundary + "--" { return result }
                    lines = []
                } else {
                    lines?.append(line)
                }
            }
            // An unfinished multipart may be a partially downloaded message; retain Mail's text instead.
            return Content()
        }
        guard type == "text/html" || type.hasPrefix("image/") else { return Content() }
        let transfer = headers["content-transfer-encoding"]?.lowercased() ?? "7bit"
        guard let data = decoded(body, transfer: transfer) else { return Content() }
        if type == "text/html" {
            let html: String?
            if transfer == "7bit" || transfer == "8bit" || transfer == "binary" {
                // AppleScript has already converted unencoded source into Unicode text.
                html = body
            } else {
                let charset = parameters["charset"] ?? "utf-8"
                let encoding = CFStringConvertIANACharSetNameToEncoding(charset as CFString)
                guard encoding != kCFStringEncodingInvalidId else { return Content() }
                html = String(data: data, encoding: String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(encoding)))
            }
            return Content(html: html)
        }
        guard ["image/png", "image/jpeg", "image/gif", "image/webp", "image/bmp"].contains(type),
              let identifier = headers["content-id"] else { return Content() }
        let cid = identifier.trimmingCharacters(in: CharacterSet(charactersIn: "<> \t"))
        return Content(images: [cid: "data:\(type);base64,\(data.base64EncodedString())"])
    }

    private static func headerValue(_ value: String) -> (String, [String: String]) {
        var fields: [String] = []
        var field = ""
        var quoted = false
        var escaped = false
        for character in value {
            if escaped {
                field.append(character)
                escaped = false
            } else if quoted && character == "\\" {
                escaped = true
            } else if character == "\"" {
                quoted.toggle()
            } else if character == ";" && !quoted {
                fields.append(field)
                field = ""
            } else {
                field.append(character)
            }
        }
        fields.append(field)
        var parameters: [String: String] = [:]
        for field in fields.dropFirst() {
            let pair = field.split(separator: "=", maxSplits: 1)
            if pair.count == 2 {
                parameters[pair[0].trimmingCharacters(in: .whitespaces).lowercased()] =
                    pair[1].trimmingCharacters(in: .whitespaces)
            }
        }
        return (fields[0].trimmingCharacters(in: .whitespaces).lowercased(), parameters)
    }

    private static func decoded(_ body: String, transfer: String) -> Data? {
        switch transfer {
        case "base64":
            return Data(base64Encoded: body.filter { !$0.isWhitespace })
        case "quoted-printable":
            let bytes = Array(body.utf8)
            var result = Data()
            var index = 0
            while index < bytes.count {
                if bytes[index] != 61 {
                    result.append(bytes[index])
                    index += 1
                } else if index + 1 < bytes.count, bytes[index + 1] == 10 {
                    index += 2
                } else {
                    guard index + 2 < bytes.count,
                          bytes[(index + 1)...(index + 2)].allSatisfy({ (48...57).contains($0) || (65...70).contains($0) || (97...102).contains($0) }),
                          let byte = UInt8(String(decoding: bytes[(index + 1)...(index + 2)], as: UTF8.self), radix: 16)
                    else { return nil }
                    result.append(byte)
                    index += 3
                }
            }
            return result
        case "7bit", "8bit", "binary":
            return Data(body.utf8)
        default:
            return nil
        }
    }
}
