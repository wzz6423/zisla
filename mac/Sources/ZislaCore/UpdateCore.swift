import Foundation

public enum SemanticVersionError: Error, Equatable, Sendable {
    case invalid(String)
}

/// Semantic version with optional `v` prefix, 1–3 numeric components, and prerelease identifiers.
public struct SemanticVersion: Equatable, Comparable, Sendable {
    public let major: Int
    public let minor: Int
    public let patch: Int
    public let prerelease: [String]

    public init(major: Int, minor: Int, patch: Int, prerelease: [String] = []) {
        self.major = major
        self.minor = minor
        self.patch = patch
        self.prerelease = prerelease
    }

    public init(_ string: String) throws {
        var text = string.trimmingCharacters(in: .whitespaces)
        if text.hasPrefix("v") || text.hasPrefix("V") {
            text.removeFirst()
        }

        let buildSplit = text.split(separator: "+", maxSplits: 1)
        let withoutBuild = buildSplit.first.map(String.init) ?? text

        let preSplit = withoutBuild.split(separator: "-", maxSplits: 1)
        guard let core = preSplit.first else { throw SemanticVersionError.invalid(string) }
        let prerelease = preSplit.count > 1 ? String(preSplit[1]) : ""

        let parts = core.split(separator: ".", omittingEmptySubsequences: false)
        guard (1...3).contains(parts.count) else { throw SemanticVersionError.invalid(string) }
        var numbers = [0, 0, 0]
        for (index, part) in parts.enumerated() {
            guard let value = Int(part), value >= 0 else {
                throw SemanticVersionError.invalid(string)
            }
            numbers[index] = value
        }

        self.major = numbers[0]
        self.minor = numbers[1]
        self.patch = numbers[2]
        self.prerelease = prerelease.isEmpty
            ? []
            : prerelease.split(separator: ".").map(String.init)
    }

    public static func < (lhs: SemanticVersion, rhs: SemanticVersion) -> Bool {
        if lhs.major != rhs.major { return lhs.major < rhs.major }
        if lhs.minor != rhs.minor { return lhs.minor < rhs.minor }
        if lhs.patch != rhs.patch { return lhs.patch < rhs.patch }
        return comparePrerelease(lhs.prerelease, rhs.prerelease) < 0
    }

    /// SemVer rule: a version with a prerelease identifier is lower than the same core version without one.
    private static func comparePrerelease(_ lhs: [String], _ rhs: [String]) -> Int {
        if lhs.isEmpty && rhs.isEmpty { return 0 }
        if lhs.isEmpty { return 1 }   // release > pre-release
        if rhs.isEmpty { return -1 }

        for (a, b) in zip(lhs, rhs) {
            let na = Int(a), nb = Int(b)
            switch (na, nb) {
            case let (.some(x), .some(y)) where x != y:
                return x < y ? -1 : 1
            case (.some, .none):
                return -1          // numeric identifiers have lower precedence than alphanumeric
            case (.none, .some):
                return 1
            case (.none, .none) where a != b:
                return a < b ? -1 : 1
            default:
                continue
            }
        }
        if lhs.count != rhs.count { return lhs.count < rhs.count ? -1 : 1 }
        return 0
    }
}

/// Minimal decode model for a GitHub/Gitee Release JSON.
public struct GitHubRelease: Decodable, Equatable, Sendable {
    public struct Asset: Decodable, Equatable, Sendable {
        public var name: String
        public var downloadURL: URL
        public var size: Int

        private enum CodingKeys: String, CodingKey {
            case name
            case downloadURL = "browser_download_url"
            case size
        }
    }

    public struct MacUpdateAssets: Equatable, Sendable {
        public var archive: Asset
        public var checksum: Asset?
    }

    public var tagName: String
    public var htmlURL: URL
    public var draft: Bool
    public var prerelease: Bool
    public var assets: [Asset]

    private enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case htmlURL = "html_url"
        case draft
        case prerelease
        case assets
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        tagName = try container.decode(String.self, forKey: .tagName)
        htmlURL = try container.decode(URL.self, forKey: .htmlURL)
        draft = try container.decodeIfPresent(Bool.self, forKey: .draft) ?? false
        prerelease = try container.decodeIfPresent(Bool.self, forKey: .prerelease) ?? false
        assets = try container.decodeIfPresent([Asset].self, forKey: .assets) ?? []
    }

    /// Version parsed from the tag; falls back to 0.0.0 on invalid tags so callers don't need to try.
    public var version: SemanticVersion {
        (try? SemanticVersion(tagName)) ?? SemanticVersion(major: 0, minor: 0, patch: 0)
    }

    /// Picks the macOS .zip archive and its accompanying .sha256 checksum file from the assets.
    public var macUpdateAssets: MacUpdateAssets? {
        guard let archive = assets.first(where: {
            let name = $0.name.lowercased()
            return name.contains("macos") && name.hasSuffix(".zip")
        }) else {
            return nil
        }
        let checksum = assets.first { $0.name == archive.name + ".sha256" }
        return MacUpdateAssets(archive: archive, checksum: checksum)
    }
}
