import AppKit
import AVFoundation
import Foundation
import Testing
import ZislaCore
import ZislaKit
@testable import Zisla

@MainActor
struct PetMediaImportIntegrationTests {
    @Test(arguments: ["mp4", "mov"])
    func videoContainersProducePlayableOwnedPetSprites(container: String) async throws {
        let fixture = try RecordingMultitrackTestFixture()
        defer { fixture.remove() }
        let movie = try await fixture.createVideo(duration: 1)
        let source: URL
        if container == "mov" {
            source = fixture.directory.appendingPathComponent("pet.mov")
            let exporter = try #require(AVAssetExportSession(asset: AVURLAsset(url: movie), presetName: AVAssetExportPresetPassthrough))
            exporter.outputURL = source
            exporter.outputFileType = .mov
            await exporter.export()
            try #require(exporter.status == .completed)
        } else { source = movie }
        let pets = fixture.root.appendingPathComponent("pets/user_pets")
        let original = try Data(contentsOf: source)
        let entry = try await PetMediaImporter.importPet(from: source, name: "Video Pet", directory: pets)
        #expect(try Data(contentsOf: pets.appendingPathComponent(entry.id + "/original." + container)) == original)
        try FileManager.default.removeItem(at: source)
        let sprite = try #require(PetLibrary.loadSelectedSprite(for: entry.id, userPetsDirectory: pets))
        #expect(sprite.frames == 12)
        #expect(sprite.frameSize == CGSize(width: 64, height: 48))
        #expect(sprite.fps == 12)
        let first = try #require(sprite.frame(at: 0).cgImage(forProposedRect: nil, context: nil, hints: nil))
        let last = try #require(sprite.frame(at: 8).cgImage(forProposedRect: nil, context: nil, hints: nil))
        #expect(try RecordingMultitrackTestFixture.pixel(first, x: 32, y: 24)[0] > 200)
        #expect(try RecordingMultitrackTestFixture.pixel(last, x: 32, y: 24)[2] > 200)
        #expect(try FileManager.default.contentsOfDirectory(atPath: pets.path) == [entry.id])
    }

    @Test(arguments: [30.0, 30.25])
    func videoDurationLimitIsEnforcedBeforeConversion(duration: Double) async throws {
        let fixture = try RecordingMultitrackTestFixture()
        defer { fixture.remove() }
        let source = try await fixture.createVideo(duration: duration)
        let pets = fixture.root.appendingPathComponent("pets/user_pets")
        if duration > PetMediaImporter.maximumDuration {
            await #expect(throws: PetMediaImportError.tooLong) {
                try await PetMediaImporter.importPet(from: source, name: "Long video", directory: pets)
            }
            #expect(try FileManager.default.contentsOfDirectory(atPath: pets.path).isEmpty)
        } else {
            let entry = try await PetMediaImporter.importPet(from: source, name: "30 seconds", directory: pets)
            let sprite = try #require(PetLibrary.loadSprite(for: entry.id, userPetsDirectory: pets))
            #expect(sprite.frames == 360)
            #expect(sprite.fps == 12)
        }
        #expect(FileManager.default.fileExists(atPath: source.path))
    }

    @Test
    func audioOnlyFilesAreRejectedAndCleanedUp() async throws {
        let fixture = try RecordingMultitrackTestFixture()
        defer { fixture.remove() }
        let source = try fixture.createTone()
        let pets = fixture.root.appendingPathComponent("pets/user_pets")
        await #expect(throws: PetMediaImportError.unsupportedMedia) {
            try await PetMediaImporter.importPet(from: source, name: "Audio", directory: pets)
        }
        #expect(try FileManager.default.contentsOfDirectory(atPath: pets.path).isEmpty)
        #expect(FileManager.default.fileExists(atPath: source.path))
    }

    @Test(arguments: AppLanguage.allCases)
    func petImportStringsResolveInEveryLanguage(language: AppLanguage) throws {
        let package = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let sources = try ["Zisla/PetImportView.swift", "ZislaKit/PetMediaImporter.swift"].map {
            try String(contentsOf: package.appendingPathComponent("Sources/" + $0), encoding: .utf8)
        }.joined(separator: "\n")
        let expression = try NSRegularExpression(pattern: #"AppLocalization\.text\("([^"]+)""#)
        let keys = Set(expression.matches(in: sources, range: NSRange(sources.startIndex..., in: sources)).compactMap {
            Range($0.range(at: 1), in: sources).map { String(sources[$0]) }
        })
        #expect(keys.count == 8)
        #expect(AppLanguage.allCases.count == 17)
        let localization = package.appendingPathComponent("Resources/Localization")
        let table = try #require(NSDictionary(contentsOf: localization.appendingPathComponent(language.rawValue + ".lproj/Localizable.strings")) as? [String: String])
        let english = try #require(NSDictionary(contentsOf: localization.appendingPathComponent("en.lproj/Localizable.strings")) as? [String: String])
        for key in keys {
            let value = try #require(table[key], "Missing \(key) in \(language.rawValue)")
            #expect(!value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            #expect(AppLocalization.string(key, language: language) == value)
            if language != .english, language != .simplifiedChinese, language != .traditionalChinese {
                #expect(value != english[key])
            }
        }
        #expect(AppLocalization.string("导入宠物", language: .english) == "Import Pet")
        #expect(AppLocalization.string("导入宠物", language: .arabic) == "استيراد حيوان أليف")
    }
}
