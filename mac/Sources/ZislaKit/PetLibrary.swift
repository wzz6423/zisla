import AppKit
import Foundation
import ZislaCore

/// Enumerates bundled and user-imported pets and loads their sprites.
///
/// Built-in pets live at bundle resource `Resources/Pets/<id>/` (in development, `#filePath`
/// is used to locate the source root; in a packaged build, `Bundle.main` is used).
///
/// Artwork sources and rights are recorded in `Resources/Pets/CREDITS.md`.
public enum PetLibrary {
    public static var userPetsDirectory: URL {
        AppPaths.applicationSupport.appendingPathComponent("pets/user_pets", isDirectory: true)
    }

    /// Slug list of pets bundled in the app: scans subdirectories of `Resources/Pets/` that contain a valid `pet.json`.
    ///
    /// This way "however many pets are bundled, that many appear" — no hardcoding needed here.
    /// Just drop a pet's `pet.json` + `sprite.png` into `mac/Resources/Pets/<slug>/` and it works.
    public static var builtinPetIDs: [String] {
        guard let root = petsRoot() else { return [] }
        let fm = FileManager.default
        guard let subs = try? fm.contentsOfDirectory(atPath: root.path) else { return [] }
        return subs
            .filter { name in
                let dir = root.appendingPathComponent(name, isDirectory: true)
                var isDir: ObjCBool = false
                fm.fileExists(atPath: dir.path, isDirectory: &isDir)
                guard isDir.boolValue else { return false }
                return loadManifest(at: dir) != nil
            }
            .sorted()
    }

    private static func petsRoot() -> URL? {
        resourceURL(relativePath: "Pets")
    }

    public struct Entry: Identifiable, Equatable, Sendable {
        public var id: String { manifest.id }
        public var manifest: PetManifest
        public var origin: Origin

        public enum Origin: String, Sendable {
            case builtin
            case imported
        }
    }

    public static func entries(userPetsDirectory: URL = userPetsDirectory) -> [Entry] {
        var seen = Set<String>()
        var result: [Entry] = []
        for id in builtinPetIDs {
            guard !seen.contains(id),
                  let dir = builtinDirectory(for: id),
                  let manifest = loadManifest(at: dir) else { continue }
            seen.insert(id)
            result.append(Entry(manifest: manifest, origin: .builtin))
        }
        let directories = (try? FileManager.default.contentsOfDirectory(
            at: userPetsDirectory, includingPropertiesForKeys: [.isSymbolicLinkKey], options: .skipsHiddenFiles
        )) ?? []
        for directory in directories.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            guard let manifest = importedManifest(in: directory), !seen.contains(manifest.id) else { continue }
            seen.insert(manifest.id)
            result.append(Entry(manifest: manifest, origin: .imported))
        }
        return result
    }

    public static func entry(for id: String, userPetsDirectory: URL = userPetsDirectory) -> Entry? {
        entries(userPetsDirectory: userPetsDirectory).first { $0.id == id }
    }

    @MainActor
    public static func loadSprite(for id: String, userPetsDirectory: URL = userPetsDirectory) -> PetSprite? {
        if isImportedID(id) {
            let directory = userPetsDirectory.appendingPathComponent(id, isDirectory: true)
            guard let manifest = importedManifest(in: directory) else { return nil }
            return loadSprite(for: manifest, in: directory)
        }
        guard let dir = builtinDirectory(for: id),
              let manifest = loadManifest(at: dir) else { return nil }
        return loadSprite(for: manifest, in: dir)
    }

    @MainActor
    public static func loadSelectedSprite(for id: String, userPetsDirectory: URL = userPetsDirectory) -> PetSprite? {
        loadSprite(for: id, userPetsDirectory: userPetsDirectory)
            ?? loadSprite(for: FeatureSettings.default.petID, userPetsDirectory: userPetsDirectory)
    }

    private static func isImportedID(_ id: String) -> Bool {
        id.hasPrefix("user-") && UUID(uuidString: String(id.dropFirst(5))) != nil
    }

    private static func importedManifest(in directory: URL) -> PetManifest? {
        guard isImportedID(directory.lastPathComponent),
              (try? directory.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) == false,
              let manifest = loadManifest(at: directory), manifest.id == directory.lastPathComponent,
              manifest.spritePath == "sprite.png",
              let width = manifest.frameWidth, (1...PetMediaImporter.maximumDimension).contains(width),
              let frames = manifest.frames, (1...Int(PetMediaImporter.maximumDuration * PetMediaImporter.frameRate)).contains(frames),
              let fps = manifest.fps, fps.isFinite, fps > 0, fps <= PetMediaImporter.frameRate,
              FileManager.default.fileExists(atPath: directory.appendingPathComponent("sprite.png").path) else { return nil }
        return manifest
    }

    @MainActor
    public static func loadSprite(for manifest: PetManifest, in directory: URL) -> PetSprite? {
        for candidate in spriteCandidates(for: manifest, in: directory) {
            if let image = NSImage(contentsOf: candidate) {
                return PetSprite(
                    image: image,
                    frameWidth: manifest.frameWidth,
                    frames: manifest.frames,
                    fps: manifest.fps
                )
            }
        }
        return nil
    }

    private static func loadManifest(at directory: URL?) -> PetManifest? {
        guard let directory else { return nil }
        let url = directory.appendingPathComponent("pet.json", isDirectory: false)
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(PetManifest.self, from: data)
    }

    private static func spriteCandidates(
        for manifest: PetManifest,
        in directory: URL
    ) -> [URL] {
        var candidates: [URL] = []
        let declared = manifest.spritePath
        if !declared.isEmpty {
            candidates.append(directory.appendingPathComponent(declared, isDirectory: false))
        }
        for name in ["sprite.png", "sprite.webp", "sprite.gif"] {
            candidates.append(directory.appendingPathComponent(name, isDirectory: false))
        }
        return candidates
    }

    private static func builtinDirectory(for id: String) -> URL? {
        let relative = "Pets/\(id)"
        return resourceURL(relativePath: relative)
    }

    /// Resource lookup: bundle resources take priority, source-tree Resources directory is the fallback.
    /// This file is at `mac/Sources/ZislaKit/`; go up 3 levels to `mac/`, then append `Resources`.
    static func resourceURL(relativePath: String) -> URL? {
        let sourceResources = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Resources", isDirectory: true)
        let candidates: [URL] = [
            Bundle.main.resourceURL,
            sourceResources,
        ].compactMap { $0 }
        return candidates
            .map { $0.appendingPathComponent(relativePath, isDirectory: false) }
            .first { FileManager.default.fileExists(atPath: $0.path) }
    }
}
