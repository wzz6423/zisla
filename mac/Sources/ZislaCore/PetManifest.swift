import Foundation

/// 一个桌面宠物的元数据：单张（或水平排列的）像素精灵图。
///
/// 为了把二进制体积压到极低，本 App 的宠物采用 **CC0 像素动物**
/// （Kenney Animal Pack Redux），每只一张小 PNG，编入 `Resources/Pets/<id>/`。
///
/// 动画不依赖逐帧图集，而是由 `PetSpriteView` 做程序化 idle
/// （轻微上下浮动 + 呼吸感 + 点击小跳），体积极小（KB 级）。
///
/// 包结构：
/// ```
/// <pet>/
/// ├── pet.json       // 本结构
/// └── sprite.png     // 单帧 PNG（或水平帧带）
/// ```
public struct PetManifest: Codable, Equatable, Sendable, Identifiable {
    public var id: String
    public var displayName: String
    public var description: String
    /// 精灵图文件名（相对宠物目录），如 `sprite.png`。
    public var spritePath: String
    /// 若为水平帧带（多帧），每帧宽度（px）；否则为单帧，留空。
    public var frameWidth: Int?
    /// 帧带总帧数（默认 1，即单帧静态图，靠程序化动画赋予生命）。
    public var frames: Int?
    /// 帧率（fps），仅帧带模式使用。
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
