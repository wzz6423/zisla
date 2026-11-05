import AppKit
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers
import ZislaCore
@testable import ZislaKit

@MainActor
struct PetMediaImporterTests {
    @Test(arguments: [UTType.png, .jpeg, .tiff, .bmp])
    func stillImagesCopyAndRoundTripWithoutDependingOnTheSource(type: UTType) async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let source = try fixture.image(type: type)
        let original = try Data(contentsOf: source)
        let entry = try await PetMediaImporter.importPet(from: source, name: "  小宠物 🐾  ", directory: fixture.pets)
        #expect(entry.origin == .imported)
        #expect(entry.manifest.displayName == "小宠物 🐾")
        let directory = fixture.pets.appendingPathComponent(entry.id)
        #expect(try Data(contentsOf: directory.appendingPathComponent("original." + source.pathExtension)) == original)
        #expect(PetLibrary.entry(for: entry.id, userPetsDirectory: fixture.pets) == entry)
        try FileManager.default.removeItem(at: source)
        let sprite = try #require(PetLibrary.loadSprite(for: entry.id, userPetsDirectory: fixture.pets))
        #expect(sprite.frames == 1)
        #expect(sprite.frameSize == CGSize(width: 128, height: 64))
        #expect(try fixture.children() == [entry.id])
    }

    @Test(arguments: [UTType.gif, .png])
    func animatedImagesKeepFrameOrderTimingAndTransparency(type: UTType) async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let source = try fixture.image(type: type, delays: [0.25, 0.75])
        let entry = try await PetMediaImporter.importPet(from: source, name: "Animated", directory: fixture.pets)
        let sprite = try #require(PetLibrary.loadSprite(for: entry.id, userPetsDirectory: fixture.pets))
        #expect(sprite.frames == 12)
        #expect(sprite.fps == 12)
        let first = try fixture.pixel(sprite.frame(at: 0), x: 64, y: 32)
        let last = try fixture.pixel(sprite.frame(at: 6), x: 64, y: 32)
        #expect(first.redComponent > 0.9 && first.blueComponent < 0.1)
        #expect(last.blueComponent > 0.9 && last.redComponent < 0.1)
        #expect(try fixture.pixel(sprite.frame(at: 0), x: 0, y: 0).alphaComponent == 0)
    }

    @Test(arguments: [29.98, 30.0, 30.02])
    func animatedDurationLimitIncludesExactlyThirtySeconds(duration: Double) async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let source = try fixture.image(type: .gif, delays: [duration / 2, duration / 2])
        if duration > PetMediaImporter.maximumDuration {
            await #expect(throws: PetMediaImportError.tooLong) {
                try await PetMediaImporter.importPet(from: source, name: "Long", directory: fixture.pets)
            }
            #expect(try fixture.children().isEmpty)
        } else {
            let entry = try await PetMediaImporter.importPet(from: source, name: "Boundary", directory: fixture.pets)
            #expect(try #require(entry.manifest.frames) <= 360)
            #expect(try #require(entry.manifest.fps) <= 12)
            let sprite = try #require(PetLibrary.loadSprite(for: entry.id, userPetsDirectory: fixture.pets))
            #expect(sprite.frames == entry.manifest.frames)
            #expect(try fixture.pixel(sprite.frame(at: sprite.frames - 1), x: 64, y: 32).blueComponent > 0.9)
        }
    }

    @Test
    func repeatedFractionalFrameDelaysIncludeExactlyThirtySeconds() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let source = try fixture.image(type: .gif, delays: Array(repeating: 0.1, count: 300))
        let entry = try await PetMediaImporter.importPet(from: source, name: "30 seconds", directory: fixture.pets)
        #expect(entry.manifest.frames == 360)
        #expect(entry.manifest.fps == 12)
    }

    @Test(arguments: [CGSize(width: 16_385, height: 1), CGSize(width: 4_097, height: 4_096)])
    func sourceDimensionsAreBoundedBeforeDecoding(size: CGSize) async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let source = try fixture.image(size: size)
        await #expect(throws: PetMediaImportError.unsupportedMedia) {
            try await PetMediaImporter.importPet(from: source, name: "Oversized image", directory: fixture.pets)
        }
        #expect(try fixture.children().isEmpty)
    }

    @Test
    func symbolicLinksCannotSupplyImportedPetManifests() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let owned = fixture.root.appendingPathComponent("owned")
        let entry = try await PetMediaImporter.importPet(from: fixture.image(), name: "Linked", directory: owned)
        try FileManager.default.createDirectory(at: fixture.pets, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: fixture.pets.appendingPathComponent(entry.id),
            withDestinationURL: owned.appendingPathComponent(entry.id))
        #expect(PetLibrary.entry(for: entry.id, userPetsDirectory: fixture.pets) == nil)
        #expect(PetLibrary.loadSprite(for: entry.id, userPetsDirectory: fixture.pets) == nil)
    }

    @Test(arguments: ["", " \n\t", String(repeating: "a", count: 81)])
    func invalidNamesFailBeforeWriting(name: String) async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let source = try fixture.image()
        await #expect(throws: PetMediaImportError.invalidName) {
            try await PetMediaImporter.importPet(from: source, name: name, directory: fixture.pets)
        }
        #expect(!FileManager.default.fileExists(atPath: fixture.pets.path))
        #expect(FileManager.default.fileExists(atPath: source.path))
    }

    @Test
    func duplicateNamesAndPathLikeNamesDoNotOverwriteFiles() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let source = try fixture.image()
        let first = try await PetMediaImporter.importPet(from: source, name: "../../宠物", directory: fixture.pets)
        let second = try await PetMediaImporter.importPet(from: source, name: "../../宠物", directory: fixture.pets)
        #expect(first.id != second.id)
        #expect(first.manifest.displayName == second.manifest.displayName)
        #expect(Set(try fixture.children()) == [first.id, second.id])
        #expect(FileManager.default.fileExists(atPath: source.path))
    }

    @Test(arguments: ["sprite.png", "pet.json", "whole-library"])
    func deletedImportedFilesLeaveBuiltinsUsableAndAllowAnotherImport(file: String) async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let source = try fixture.image()
        let entry = try await PetMediaImporter.importPet(from: source, name: "Deleted", directory: fixture.pets)
        let target = file == "whole-library" ? fixture.pets : fixture.pets.appendingPathComponent(entry.id + "/" + file)
        try FileManager.default.removeItem(at: target)
        #expect(PetLibrary.entry(for: entry.id, userPetsDirectory: fixture.pets) == nil)
        #expect(PetLibrary.loadSprite(for: entry.id, userPetsDirectory: fixture.pets) == nil)
        let builtin = try #require(PetLibrary.loadSprite(for: FeatureSettings.default.petID, userPetsDirectory: fixture.pets))
        let fallback = try #require(PetLibrary.loadSelectedSprite(for: entry.id, userPetsDirectory: fixture.pets))
        #expect(fallback.image.tiffRepresentation == builtin.image.tiffRepresentation)
        #expect(PetLibrary.entries(userPetsDirectory: fixture.pets).count == PetLibrary.builtinPetIDs.count)
        let restored = try await PetMediaImporter.importPet(from: source, name: "Restored", directory: fixture.pets)
        #expect(PetLibrary.loadSprite(for: restored.id, userPetsDirectory: fixture.pets) != nil)
    }

    @Test(arguments: ["not media", "GIF89a", "RIFF0000WEBP", "\u{89}PNG\r\n", "<svg>", "ftypmp42", "{\"frames\":0}", ""])
    func boundedMalformedCorpusFailsAndCleansStaging(content: String) async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let source = fixture.root.appendingPathComponent("broken.gif")
        try Data(content.utf8).write(to: source)
        await #expect(throws: (any Error).self) {
            try await PetMediaImporter.importPet(from: source, name: "Broken", directory: fixture.pets)
        }
        #expect(try fixture.children().isEmpty)
        #expect(try String(contentsOf: source, encoding: .utf8) == content)
    }

    @Test
    func oversizedFilesAndNonFileURLsFailWithoutCopying() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let source = fixture.root.appendingPathComponent("oversized.mp4")
        try Data().write(to: source)
        let handle = try FileHandle(forWritingTo: source)
        defer { try? handle.close() }
        try handle.truncate(atOffset: UInt64(PetMediaImporter.maximumFileBytes + 1))
        await #expect(throws: PetMediaImportError.tooLarge) {
            try await PetMediaImporter.importPet(from: source, name: "Large", directory: fixture.pets)
        }
        await #expect(throws: PetMediaImportError.unsupportedMedia) {
            try await PetMediaImporter.importPet(from: URL(string: "https://example.invalid/pet.gif")!, name: "Remote", directory: fixture.pets)
        }
        await #expect(throws: PetMediaImportError.unsupportedMedia) {
            try await PetMediaImporter.importPet(from: fixture.root, name: "Directory", directory: fixture.pets)
        }
        #expect(!FileManager.default.fileExists(atPath: fixture.pets.path))
    }

    @Test
    func cancelledImportAndUnwritableDestinationPreserveTheSource() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let source = try fixture.image()
        let original = try Data(contentsOf: source)
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await PetMediaImporter.importPet(from: source, name: "Cancelled", directory: fixture.pets)
        }
        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(try fixture.children().isEmpty)
        try FileManager.default.removeItem(at: fixture.pets)
        try Data("blocked".utf8).write(to: fixture.pets)
        await #expect(throws: (any Error).self) {
            try await PetMediaImporter.importPet(from: source, name: "Blocked", directory: fixture.pets)
        }
        #expect(try Data(contentsOf: source) == original)
        #expect(try String(contentsOf: fixture.pets, encoding: .utf8) == "blocked")
    }

    @Test(arguments: ["id", "sprite", "width", "frames", "fps", "json"])
    func damagedImportedManifestsAreIgnored(field: String) async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let entry = try await PetMediaImporter.importPet(from: fixture.image(), name: "Damaged", directory: fixture.pets)
        let manifestURL = fixture.pets.appendingPathComponent(entry.id + "/pet.json")
        var manifest = entry.manifest
        switch field {
        case "id": manifest.id = "chiikawa"
        case "sprite": manifest.spritePath = "../../source.png"
        case "width": manifest.frameWidth = 1_000_000
        case "frames": manifest.frames = 1_000_000
        case "fps": manifest.fps = 1_000_000
        default: break
        }
        try (field == "json" ? Data("broken".utf8) : JSONEncoder().encode(manifest)).write(to: manifestURL)
        #expect(PetLibrary.entry(for: entry.id, userPetsDirectory: fixture.pets) == nil)
        #expect(PetLibrary.loadSprite(for: entry.id, userPetsDirectory: fixture.pets) == nil)
        #expect(PetLibrary.entry(for: "chiikawa", userPetsDirectory: fixture.pets)?.origin == .builtin)
    }

    private struct Fixture {
        let root: URL
        var pets: URL { root.appendingPathComponent("pets/user_pets", isDirectory: true) }

        init() throws {
            root = FileManager.default.temporaryDirectory.appendingPathComponent("zisla-pet-import-\(UUID())", isDirectory: true)
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        }

        func remove() { try? FileManager.default.removeItem(at: root) }
        func children() throws -> [String] { try FileManager.default.contentsOfDirectory(atPath: pets.path).sorted() }

        func image(type: UTType = .png, delays: [Double] = [], size: CGSize = CGSize(width: 256, height: 128)) throws -> URL {
            let url = root.appendingPathComponent("source." + (type.preferredFilenameExtension ?? "png"))
            let count = max(1, delays.count)
            let destination = try #require(CGImageDestinationCreateWithURL(url as CFURL, type.identifier as CFString, count, nil))
            for index in 0..<count {
                let context = try #require(CGContext(data: nil, width: Int(size.width), height: Int(size.height), bitsPerComponent: 8, bytesPerRow: 0,
                    space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
                context.setFillColor(index == 0 ? NSColor.red.cgColor : NSColor.blue.cgColor)
                context.fill(CGRect(x: 4, y: 4, width: 248, height: 120))
                let properties: [CFString: Any] = delays.isEmpty ? [:] : [
                    kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: delays[index]],
                    kCGImagePropertyPNGDictionary: [kCGImagePropertyAPNGDelayTime: delays[index]],
                ]
                CGImageDestinationAddImage(destination, try #require(context.makeImage()), properties as CFDictionary)
            }
            try #require(CGImageDestinationFinalize(destination))
            return url
        }

        func pixel(_ image: NSImage, x: Int, y: Int) throws -> NSColor {
            let cgImage = try #require(image.cgImage(forProposedRect: nil, context: nil, hints: nil))
            return try #require(NSBitmapImageRep(cgImage: cgImage).colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB))
        }
    }
}
