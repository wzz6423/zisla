import AppKit
import Foundation
import Testing
import ZislaCore
@testable import ZislaKit

@MainActor
struct PetLibraryTests {
    private let userPetsDirectory = FileManager.default.temporaryDirectory
        .appendingPathComponent("zisla-builtin-pets-\(UUID())", isDirectory: true)

    @Test
    func catalogRetainsChickAndBearAndIncludesCharactersAndNewAnimals() throws {
        let entries = PetLibrary.entries(userPetsDirectory: userPetsDirectory)
        let ids = Set(entries.map(\.id))
        #expect(entries.count == 46)
        #expect(ids.count == entries.count)
        #expect(ids.isSuperset(of: ["chick", "bear", "chiikawa", "kirby", "pikachu", "toothless"]))
        #expect(ids.isSuperset(of: [
            "orange-capybara", "coffee-capybara", "box-capybara", "mallow-cat", "orange-tabby",
            "calico-cat", "shiba-inu", "corgi", "golden-retriever", "lop-rabbit", "byte-bunny",
            "blue-button-bunny", "red-panda", "scarf-hamster", "penguin-chick", "blue-boba-axolotl",
            "milk-tea-koala", "mellow-otter", "moonlight-fox", "hedgehog",
        ]))
        #expect(ids.isDisjoint(with: [
            "cow", "dog", "duck", "frog", "horse", "monkey", "owl",
            "panda", "parrot", "penguin", "pig", "rabbit", "sloth", "whale",
        ]))
        #expect(ids.contains(FeatureSettings.default.petID))
        for id in PetLibrary.builtinPetIDs {
            let entry = try #require(PetLibrary.entry(for: id, userPetsDirectory: userPetsDirectory))
            #expect(entry.id == id)
            #expect(entry.origin == .builtin)
            #expect(!entry.manifest.displayName.isEmpty)
        }
    }

    @Test
    func everySpriteLoadsAndAnimationFramesStayVisible() throws {
        for entry in PetLibrary.entries(userPetsDirectory: userPetsDirectory) {
            let sprite = try #require(PetLibrary.loadSprite(for: entry.id, userPetsDirectory: userPetsDirectory), "Cannot load \(entry.id)")
            if ["bear", "chick"].contains(entry.id) {
                #expect(sprite.frames == 1)
                continue
            }
            #expect((6...8).contains(sprite.frames))
            #expect(sprite.frameSize == CGSize(width: 128, height: 128))
            #expect(sprite.image.size.width == 128 * CGFloat(sprite.frames))
            #expect(sprite.image.size.height == 128)
            #expect(sprite.fps == 6)
            var frames: [Data] = []
            for index in 0..<sprite.frames {
                let frame = sprite.frame(at: index)
                #expect(frame.size == sprite.frameSize)
                let pixels = try Self.pixels(in: frame)
                #expect(pixels[3] == 0, "Opaque background in \(entry.id) frame \(index)")
                #expect(
                    stride(from: 3, to: pixels.count, by: 4).contains { pixels[$0] > 0 },
                    "Empty frame in \(entry.id) at \(index)"
                )
                frames.append(pixels)
            }
            #expect(Set(frames).count > 1, "Static animation in \(entry.id)")
            #expect(try Self.pixels(in: sprite.frame(at: -1)) == frames.last)
            #expect(try Self.pixels(in: sprite.frame(at: sprite.frames)) == frames.first)
        }
    }

    @Test
    func missingOrCorruptSpritesFailWithoutInventingAPet() throws {
        #expect(PetLibrary.entry(for: "missing-pet", userPetsDirectory: userPetsDirectory) == nil)
        #expect(PetLibrary.loadSprite(for: "missing-pet", userPetsDirectory: userPetsDirectory) == nil)
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("zisla-pet-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let manifest = PetManifest(id: "broken", displayName: "Broken", description: "", spritePath: "sprite.png")
        #expect(PetLibrary.loadSprite(for: manifest, in: directory) == nil)
        try Data("invalid PNG".utf8).write(to: directory.appendingPathComponent("sprite.png"))
        #expect(PetLibrary.loadSprite(for: manifest, in: directory) == nil)
    }

    @Test
    func everyPetNameHasAnExplicitTranslationInEveryLanguage() throws {
        let root = try #require(PetLibrary.resourceURL(relativePath: "Localization"))
        #expect(AppLanguage.allCases.count == 17)
        for language in AppLanguage.allCases {
            let path = root.appendingPathComponent("\(language.rawValue).lproj/Localizable.strings")
            let table = try #require(NSDictionary(contentsOf: path) as? [String: String])
            for entry in PetLibrary.entries(userPetsDirectory: userPetsDirectory) {
                let key = entry.manifest.displayName
                let translation = try #require(table[key], "Missing \(key) in \(language.rawValue)")
                #expect(!translation.isEmpty)
                #expect(AppLocalization.string(key, language: language) == translation)
            }
        }
        #expect(AppLocalization.string("吉伊卡哇", language: .english) == "Chiikawa")
        #expect(AppLocalization.string("吉伊卡哇", language: .japanese) == "ちいかわ")
        #expect(AppLocalization.string("吉伊卡哇", language: .arabic) == "تشيكاوا")
        #expect(AppLocalization.string("橘子水豚", language: .english) == "Orange Capybara")
        #expect(AppLocalization.string("橘子水豚", language: .japanese) == "みかんカピバラ")
        #expect(AppLocalization.string("橘子水豚", language: .arabic) == "كابيبارا مع برتقالة")
    }

    private static func pixels(in image: NSImage) throws -> Data {
        let cgImage = try #require(image.cgImage(forProposedRect: nil, context: nil, hints: nil))
        var pixels = Data(count: cgImage.width * cgImage.height * 4)
        try pixels.withUnsafeMutableBytes { buffer in
            let context = try #require(CGContext(
                data: buffer.baseAddress, width: cgImage.width, height: cgImage.height,
                bitsPerComponent: 8, bytesPerRow: cgImage.width * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ))
            context.draw(cgImage, in: CGRect(x: 0, y: 0, width: cgImage.width, height: cgImage.height))
        }
        return pixels
    }
}
