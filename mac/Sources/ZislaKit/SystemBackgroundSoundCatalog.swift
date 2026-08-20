import Foundation
import ZislaCore

/// Discovers locally installed macOS Comfort Sounds (background ambient audio) by reading system asset directories.
/// Uses injected closures to remain pure Foundation and fully testable without accessing /System.
public enum SystemBackgroundSoundCatalog {
    /// Canonical ordering of known Comfort Sound names; assets not in this list are ignored.
    public static let knownSoundNames: [String] = SystemBackgroundSound.allCases.map(\.rawValue)

    /// Returns the sound names advertised by the local Apple asset manifest.
    public static func manifestSoundNames(
        at manifestURL: URL = SystemBackgroundSoundAssetDownloader.defaultManifestPath,
        readPlist: (URL) throws -> [String: Any] = { url in
            let data = try Data(contentsOf: url)
            guard let dict = try PropertyListSerialization.propertyList(
                from: data,
                options: [],
                format: nil
            ) as? [String: Any] else {
                throw CocoaError(.propertyListReadCorrupt)
            }
            return dict
        }
    ) -> Set<String> {
        guard let manifest = try? readPlist(manifestURL),
              let assets = manifest["Assets"] as? [[String: Any]] else {
            return []
        }
        let knownNames = Set(knownSoundNames)
        return Set(
            assets.compactMap { $0["SoundName"] as? String }
                .filter { knownNames.contains($0) }
        )
    }

    /// An installed Comfort Sound with its audio file.
    public struct InstalledSound: Equatable {
        public let name: String
        public let audioURLs: [URL]

        public var audioURL: URL { audioURLs[0] }

        public init(name: String, audioURL: URL) {
            self.name = name
            self.audioURLs = [audioURL]
        }

        public init(name: String, audioURLs: [URL]) {
            self.name = name
            self.audioURLs = audioURLs
        }
    }

    /// Discovers installed Comfort Sounds under the given asset root directory.
    /// Returns sounds in the order defined by `knownSoundNames`; unknown or incomplete assets are silently ignored.
    ///
    /// - Parameters:
    ///   - assetRoot: Root directory containing `.asset` subdirectories.
    ///   - contentsOfDirectory: Returns URLs of immediate children for a given directory URL
    ///   - readPlist: Reads and deserializes a plist file into a dictionary
    /// - Returns: Array of installed sounds in canonical order
    public static func installedSounds(
        in assetRoot: URL,
        contentsOfDirectory: (URL) throws -> [URL] = { url in
            try FileManager.default.contentsOfDirectory(
                at: url,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            )
        },
        readPlist: (URL) throws -> [String: Any] = { url in
            let data = try Data(contentsOf: url)
            guard let dict = try PropertyListSerialization.propertyList(
                from: data,
                options: [],
                format: nil
            ) as? [String: Any] else {
                throw CocoaError(.propertyListReadCorrupt)
            }
            return dict
        }
    ) -> [InstalledSound] {
        let assetDirs: [URL]
        do {
            assetDirs = try contentsOfDirectory(assetRoot)
                .filter { $0.pathExtension == "asset" }
        } catch {
            return []
        }

        var discovered: [String: [URL]] = [:]
        for assetDir in assetDirs {
            guard let sound = readAsset(
                assetDir: assetDir,
                contentsOfDirectory: contentsOfDirectory,
                readPlist: readPlist
            ) else {
                continue
            }
            discovered[sound.name] = sound.audioURLs
        }

        return knownSoundNames.compactMap { name in
            guard let audioURLs = discovered[name] else { return nil }
            return InstalledSound(name: name, audioURLs: audioURLs)
        }
    }

    private static func readAsset(
        assetDir: URL,
        contentsOfDirectory: (URL) throws -> [URL],
        readPlist: (URL) throws -> [String: Any]
    ) -> InstalledSound? {
        let infoPlistURL = assetDir.appendingPathComponent("Info.plist", isDirectory: false)
        guard let plist = try? readPlist(infoPlistURL),
              let mobileAssetProps = plist["MobileAssetProperties"] as? [String: Any],
              let soundName = mobileAssetProps["SoundName"] as? String else {
            return nil
        }

        let assetDataDir = assetDir.appendingPathComponent("AssetData", isDirectory: true)
        guard let contents = try? contentsOfDirectory(assetDataDir) else {
            return nil
        }

        let m4aURLs = contents
            .filter({ $0.pathExtension.caseInsensitiveCompare("m4a") == .orderedSame })
            .sorted(by: { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending })
        guard !m4aURLs.isEmpty else {
            return nil
        }

        return InstalledSound(name: soundName, audioURLs: m4aURLs)
    }
}
