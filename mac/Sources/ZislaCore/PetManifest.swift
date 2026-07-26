import Foundation

/// Metadata for a desktop pet: a single (or horizontally-laid-out) pixel sprite sheet.
///
/// To keep the binary size extremely small, the app uses **CC0 pixel animals**
/// (Kenney Animal Pack Redux) — one small PNG per pet, embedded in `Resources/Pets/<id>/`.
///
/// Animation does not rely on a frame atlas; instead `PetSpriteView` drives a
/// procedural idle (gentle bob + breathing feel + click-jump), keeping each asset
/// in the KB range.
///
/// Bundle layout:
/// ```
/// <pet>/
/// ├── pet.json       // this struct
/// └── sprite.png     // single-frame PNG (or horizontal strip)
/// ```
public struct PetManifest: Codable, Equatable, Sendable, Identifiable {
    public var id: String
    public var displayName: String
    public var description: String
    /// Sprite filename relative to the pet directory, e.g. `sprite.png`.
    public var spritePath: String
    /// Width of each frame (px) if this is a horizontal strip; omit for a single frame.
    public var frameWidth: Int?
    /// Total frame count (defaults to 1, i.e. a static single frame animated procedurally).
    public var frames: Int?
    /// Frame rate (fps); only used in strip mode.
    public var fps: Double?

    private enum CodingKeys: String, CodingKey {
        case id
        case displayName
        case description
        case spritePath
        case frameWidth
        case frames
        case fps
    }

    public init(
        id: String,
        displayName: String,
        description: String,
        spritePath: String,
        frameWidth: Int? = nil,
        frames: Int? = nil,
        fps: Double? = nil
    ) {
        self.id = id
        self.displayName = displayName
        self.description = description
        self.spritePath = spritePath
        self.frameWidth = frameWidth
        self.frames = frames
        self.fps = fps
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        displayName = try c.decodeIfPresent(String.self, forKey: .displayName) ?? id
        description = try c.decodeIfPresent(String.self, forKey: .description) ?? ""
        spritePath = try c.decodeIfPresent(String.self, forKey: .spritePath) ?? "sprite.png"
        frameWidth = try c.decodeIfPresent(Int.self, forKey: .frameWidth)
        frames = try c.decodeIfPresent(Int.self, forKey: .frames)
        fps = try c.decodeIfPresent(Double.self, forKey: .fps)
    }
}
