import Foundation
import Testing

@testable import ZislaKit

struct SystemBackgroundSoundCatalogTests {
    @Test
    func knownSoundNamesMatchesSystemComfortSoundsInventory() {
        let expected: Set<String> = [
            "PinkNoise", "BrownNoise", "WhiteNoise",
            "BalancedNoise", "BrightNoise", "DarkNoise",
            "Ocean", "Rain", "Stream",
            "Night", "Fire", "Babble", "Steam",
            "Airplane", "Boat", "Bus", "Train",
            "RainOnRoof", "QuietNight",
        ]
        #expect(Set(SystemBackgroundSoundCatalog.knownSoundNames) == expected)
        #expect(SystemBackgroundSoundCatalog.knownSoundNames.count == 19)
    }

    @Test
    func knownSoundNamesIsFixedOrder() {
        #expect(SystemBackgroundSoundCatalog.knownSoundNames.first == "PinkNoise")
        #expect(SystemBackgroundSoundCatalog.knownSoundNames.last == "QuietNight")
        let snapshot = SystemBackgroundSoundCatalog.knownSoundNames
        #expect(snapshot == SystemBackgroundSoundCatalog.knownSoundNames)
    }

    @Test
    func readsKnownSoundNamesFromManifest() throws {
        let manifest: [String: Any] = [
            "Assets": [
                ["SoundName": "Rain"],
                ["SoundName": "PinkNoise"],
                ["SoundName": "UnknownSound"],
            ],
        ]
        let manifestData = try PropertyListSerialization.data(
            fromPropertyList: manifest,
            format: .xml,
            options: 0
        )
        let names = SystemBackgroundSoundCatalog.manifestSoundNames(
            at: URL(fileURLWithPath: "/unused-manifest.xml"),
            readPlist: { _ in
                try PropertyListSerialization.propertyList(
                    from: manifestData,
                    options: [],
                    format: nil
                ) as! [String: Any]
            }
        )

        #expect(names == ["Rain", "PinkNoise"])
    }

    @Test
    func discoversInstalledSoundsFromAssetDirectory() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(
            "SystemBackgroundSoundCatalogTests-\(UUID().uuidString)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let oceanAsset = tempDir.appendingPathComponent("Ocean.asset", isDirectory: true)
        let oceanAssetData = oceanAsset.appendingPathComponent("AssetData", isDirectory: true)
        try FileManager.default.createDirectory(at: oceanAssetData, withIntermediateDirectories: true)

        let oceanInfoPlist = oceanAsset.appendingPathComponent("Info.plist")
        let oceanPlistData: [String: Any] = [
            "MobileAssetProperties": [
                "SoundName": "Ocean",
            ],
        ]
        let oceanData = try PropertyListSerialization.data(
            fromPropertyList: oceanPlistData,
            format: .xml,
            options: 0
        )
        try oceanData.write(to: oceanInfoPlist)

        let oceanAudio = oceanAssetData.appendingPathComponent("ocean.m4a")
        try Data().write(to: oceanAudio)

        let rainAsset = tempDir.appendingPathComponent("Rain.asset", isDirectory: true)
        let rainAssetData = rainAsset.appendingPathComponent("AssetData", isDirectory: true)
        try FileManager.default.createDirectory(at: rainAssetData, withIntermediateDirectories: true)

        let rainInfoPlist = rainAsset.appendingPathComponent("Info.plist")
        let rainPlistData: [String: Any] = [
            "MobileAssetProperties": [
                "SoundName": "Rain",
            ],
        ]
        let rainData = try PropertyListSerialization.data(
            fromPropertyList: rainPlistData,
            format: .xml,
            options: 0
        )
        try rainData.write(to: rainInfoPlist)

        let rainAudio = rainAssetData.appendingPathComponent("rain.m4a")
        try Data().write(to: rainAudio)

        let sounds = SystemBackgroundSoundCatalog.installedSounds(in: tempDir)

        #expect(sounds.count == 2)
        #expect(sounds[0].name == "Ocean")
        #expect(sounds[0].audioURL.standardizedFileURL == oceanAudio.standardizedFileURL)
        #expect(sounds[1].name == "Rain")
        #expect(sounds[1].audioURL.standardizedFileURL == rainAudio.standardizedFileURL)
    }

    @Test
    func preservesAllAudioFragmentsInNaturalOrder() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(
            "SystemBackgroundSoundCatalogTests-\(UUID().uuidString)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let asset = tempDir.appendingPathComponent("Rain.asset", isDirectory: true)
        let dataDir = asset.appendingPathComponent("AssetData", isDirectory: true)
        try FileManager.default.createDirectory(at: dataDir, withIntermediateDirectories: true)
        let plist: [String: Any] = ["MobileAssetProperties": ["SoundName": "Rain"]]
        let plistData = try PropertyListSerialization.data(
            fromPropertyList: plist,
            format: .xml,
            options: 0
        )
        try plistData.write(to: asset.appendingPathComponent("Info.plist"))
        for name in ["Rain_10.m4a", "Rain_2.m4a", "Rain_1.m4a"] {
            try Data().write(to: dataDir.appendingPathComponent(name))
        }

        let sounds = SystemBackgroundSoundCatalog.installedSounds(in: tempDir)
        #expect(sounds.first?.audioURLs.map(\.lastPathComponent) == [
            "Rain_1.m4a", "Rain_2.m4a", "Rain_10.m4a",
        ])
    }

    @Test
    func returnsEmptyWhenAssetRootDoesNotExist() {
        let nonExistent = URL(fileURLWithPath: "/nonexistent-\(UUID().uuidString)")
        let sounds = SystemBackgroundSoundCatalog.installedSounds(in: nonExistent)
        #expect(sounds.isEmpty)
    }

    @Test
    func ignoresAssetsMissingSoundNameInPlist() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(
            "SystemBackgroundSoundCatalogTests-\(UUID().uuidString)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let brokenAsset = tempDir.appendingPathComponent("Broken.asset", isDirectory: true)
        let brokenAssetData = brokenAsset.appendingPathComponent("AssetData", isDirectory: true)
        try FileManager.default.createDirectory(at: brokenAssetData, withIntermediateDirectories: true)

        let brokenInfoPlist = brokenAsset.appendingPathComponent("Info.plist")
        let brokenPlistData: [String: Any] = [
            "MobileAssetProperties": [:],
        ]
        let brokenData = try PropertyListSerialization.data(
            fromPropertyList: brokenPlistData,
            format: .xml,
            options: 0
        )
        try brokenData.write(to: brokenInfoPlist)

        let brokenAudio = brokenAssetData.appendingPathComponent("audio.m4a")
        try Data().write(to: brokenAudio)

        let sounds = SystemBackgroundSoundCatalog.installedSounds(in: tempDir)
        #expect(sounds.isEmpty)
    }

    @Test
    func ignoresAssetsMissingM4AFile() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(
            "SystemBackgroundSoundCatalogTests-\(UUID().uuidString)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let noAudioAsset = tempDir.appendingPathComponent("NoAudio.asset", isDirectory: true)
        let noAudioAssetData = noAudioAsset.appendingPathComponent("AssetData", isDirectory: true)
        try FileManager.default.createDirectory(at: noAudioAssetData, withIntermediateDirectories: true)

        let noAudioInfoPlist = noAudioAsset.appendingPathComponent("Info.plist")
        let noAudioPlistData: [String: Any] = [
            "MobileAssetProperties": [
                "SoundName": "Fire",
            ],
        ]
        let noAudioData = try PropertyListSerialization.data(
            fromPropertyList: noAudioPlistData,
            format: .xml,
            options: 0
        )
        try noAudioData.write(to: noAudioInfoPlist)

        let sounds = SystemBackgroundSoundCatalog.installedSounds(in: tempDir)
        #expect(sounds.isEmpty)
    }

    @Test
    func ignoresUnknownSoundNames() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(
            "SystemBackgroundSoundCatalogTests-\(UUID().uuidString)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let unknownAsset = tempDir.appendingPathComponent("Unknown.asset", isDirectory: true)
        let unknownAssetData = unknownAsset.appendingPathComponent("AssetData", isDirectory: true)
        try FileManager.default.createDirectory(at: unknownAssetData, withIntermediateDirectories: true)

        let unknownInfoPlist = unknownAsset.appendingPathComponent("Info.plist")
        let unknownPlistData: [String: Any] = [
            "MobileAssetProperties": [
                "SoundName": "UnknownSound",
            ],
        ]
        let unknownData = try PropertyListSerialization.data(
            fromPropertyList: unknownPlistData,
            format: .xml,
            options: 0
        )
        try unknownData.write(to: unknownInfoPlist)

        let unknownAudio = unknownAssetData.appendingPathComponent("unknown.m4a")
        try Data().write(to: unknownAudio)

        let sounds = SystemBackgroundSoundCatalog.installedSounds(in: tempDir)
        #expect(sounds.isEmpty)
    }

    @Test
    func returnsInstalledSoundsInCanonicalOrder() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(
            "SystemBackgroundSoundCatalogTests-\(UUID().uuidString)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let soundNames = ["Train", "BalancedNoise", "Ocean", "Fire"]
        for name in soundNames {
            let asset = tempDir.appendingPathComponent("\(name).asset", isDirectory: true)
            let assetData = asset.appendingPathComponent("AssetData", isDirectory: true)
            try FileManager.default.createDirectory(at: assetData, withIntermediateDirectories: true)

            let infoPlist = asset.appendingPathComponent("Info.plist")
            let plistData: [String: Any] = [
                "MobileAssetProperties": [
                    "SoundName": name,
                ],
            ]
            let data = try PropertyListSerialization.data(
                fromPropertyList: plistData,
                format: .xml,
                options: 0
            )
            try data.write(to: infoPlist)

            let audio = assetData.appendingPathComponent("\(name.lowercased()).m4a")
            try Data().write(to: audio)
        }

        let sounds = SystemBackgroundSoundCatalog.installedSounds(in: tempDir)

        #expect(sounds.count == 4)
        #expect(sounds[0].name == "BalancedNoise")
        #expect(sounds[1].name == "Ocean")
        #expect(sounds[2].name == "Fire")
        #expect(sounds[3].name == "Train")
    }

    @Test
    func ignoresNonAssetDirectories() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(
            "SystemBackgroundSoundCatalogTests-\(UUID().uuidString)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let regularDir = tempDir.appendingPathComponent("NotAnAsset", isDirectory: true)
        try FileManager.default.createDirectory(at: regularDir, withIntermediateDirectories: true)

        let regularFile = tempDir.appendingPathComponent("readme.txt")
        try Data("test".utf8).write(to: regularFile)

        let sounds = SystemBackgroundSoundCatalog.installedSounds(in: tempDir)
        #expect(sounds.isEmpty)
    }
}
