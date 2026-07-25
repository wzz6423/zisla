import AppKit
import Foundation
import ZislaCore

/// 宠物库：枚举内置（编入 App 包）像素宠物并加载其精灵。
///
/// 内置宠物位于包资源 `Resources/Pets/<id>/`（开发态用 `#filePath` 推导源码根，
/// 打包态走 `Bundle.main`）。
///
/// 本 App 不提供用户导入或网络安装：所有宠物均为预置打包的 CC0 像素动物，
/// 用户在设置里只能从内置列表选择。
public enum PetLibrary {
    /// 已编入包内的宠物 slug 列表：直接扫描 `Resources/Pets/` 下、含有效 `pet.json` 的子目录。
    ///
    /// 这样「打包了多少只就出现多少只」，无需在此硬编码——把任意宠物的
    /// `pet.json` + `sprite.png` 放进 `mac/Resources/Pets/<slug>/` 即生效。
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

    public static func entries() -> [Entry] {
        var seen = Set<String>()
        var result: [Entry] = []
        for id in builtinPetIDs {
            guard !seen.contains(id),
                  let dir = builtinDirectory(for: id),
                  let manifest = loadManifest(at: dir) else { continue }
            seen.insert(id)
            result.append(Entry(manifest: manifest, origin: .builtin))
        }
        return result
    }

    public static func entry(for id: String) -> Entry? {
        entries().first { $0.id == id }
    }

    /// 加载某个内置宠物的精灵。
    @MainActor
    public static func loadSprite(for id: String) -> PetSprite? {
        guard let dir = builtinDirectory(for: id),
              let manifest = loadManifest(at: dir) else { return nil }
        return loadSprite(for: manifest, in: dir)
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

    /// 资源定位：包资源优先，源码 Resources 兜底。
    /// 本文件位于 `mac/Sources/ZislaKit/`，向上 3 级到 `mac/`，再加 `Resources`。
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
