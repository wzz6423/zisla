// Adapted from upstream provider protocols, revision 86bcb54cff24d4a9c96b4f14066f0098f12e87a6.
// Modified for Zisla; Apache-2.0. See Resources/ThirdPartyLicenses/AIQuota-LICENSE.txt.
import CryptoKit
import Foundation

enum AIQuotaVolcengineSigner {
    struct Credentials: Sendable, Equatable {
        let accessKeyID: String
        let secretAccessKey: String
        var region = "cn-beijing"
    }

    private static let algorithm = "HMAC-SHA256"
    private static let service = "ark"
    private static let terminator = "request"
    private static let signedHeaders = "content-type;host;x-content-sha256;x-date"

    static func headers(
        method: String,
        url: URL,
        body: Data,
        contentType: String,
        credentials: Credentials,
        date: Date
    ) -> [String: String] {
        let timestamp = stamp(date, format: "yyyyMMdd'T'HHmmss'Z'")
        let day = stamp(date, format: "yyyyMMdd")
        let payloadHash = hex(SHA256.hash(data: body))
        let host = url.host ?? ""

        let canonicalRequest = [
            method,
            canonicalPath(url),
            canonicalQuery(url),
            "content-type:\(contentType)",
            "host:\(host)",
            "x-content-sha256:\(payloadHash)",
            "x-date:\(timestamp)",
            "",
            signedHeaders,
            payloadHash
        ].joined(separator: "\n")

        let scope = "\(day)/\(credentials.region)/\(service)/\(terminator)"
        let stringToSign = [
            algorithm,
            timestamp,
            scope,
            hex(SHA256.hash(data: Data(canonicalRequest.utf8)))
        ].joined(separator: "\n")

        var key = SymmetricKey(data: Data(credentials.secretAccessKey.utf8))
        for step in [day, credentials.region, service, terminator] {
            key = SymmetricKey(data: Data(HMAC<SHA256>.authenticationCode(for: Data(step.utf8), using: key)))
        }
        let signature = hex(HMAC<SHA256>.authenticationCode(for: Data(stringToSign.utf8), using: key))

        return [
            "Content-Type": contentType,
            "Host": host,
            "X-Date": timestamp,
            "X-Content-Sha256": payloadHash,
            "Authorization": "\(algorithm) Credential=\(credentials.accessKeyID)/\(scope), "
                + "SignedHeaders=\(signedHeaders), Signature=\(signature)"
        ]
    }


    private static func canonicalPath(_ url: URL) -> String {
        let path = url.path.isEmpty ? "/" : url.path
        return encode(path, keepingSlashes: true)
    }

    private static func canonicalQuery(_ url: URL) -> String {
        guard
            let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems,
            !items.isEmpty
        else { return "" }

        let pairs: [(name: String, value: String)] = items.map {
            (encode($0.name), encode($0.value ?? ""))
        }
        let sorted = pairs.sorted { lhs, rhs in
            lhs.name == rhs.name ? lhs.value < rhs.value : lhs.name < rhs.name
        }
        return sorted.map { "\($0.name)=\($0.value)" }.joined(separator: "&")
    }

    private static func encode(_ value: String, keepingSlashes: Bool = false) -> String {
        var allowed = unreserved
        if keepingSlashes { allowed.insert("/") }
        return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
    }

    private static let unreserved: CharacterSet = {
        var set = CharacterSet()
        set.insert(charactersIn: "A"..."Z")
        set.insert(charactersIn: "a"..."z")
        set.insert(charactersIn: "0"..."9")
        set.insert(charactersIn: "-_.~")
        return set
    }()

    private static func hex<D: Sequence>(_ bytes: D) -> String where D.Element == UInt8 {
        bytes.map { String(format: "%02x", $0) }.joined()
    }

    private static func stamp(_ date: Date, format: String) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = format
        return formatter.string(from: date)
    }
}
