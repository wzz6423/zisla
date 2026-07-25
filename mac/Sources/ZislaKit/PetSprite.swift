import AppKit
import Foundation

/// 一只像素宠物的可渲染精灵。
///
/// 支持两种来源：
/// - 单帧 PNG：由 `PetSpriteView` 做程序化 idle（浮动/呼吸/偶尔小跳）赋予生命；
/// - 水平帧带 PNG（`frameWidth` + `frames` 指定）：按 `fps` 循环播放。
public struct PetSprite: Sendable {
    public let image: NSImage
    public let frameSize: CGSize
    public let frames: Int
    public let fps: Double

    public init(image: NSImage, frameWidth: Int? = nil, frames: Int? = nil, fps: Double? = nil) {
        self.image = image
        let w = image.size.width
        let h = image.size.height
        let fcount = max(1, frames ?? 1)
        if let fw = frameWidth, fw > 0, fcount > 1 {
            self.frameSize = CGSize(width: CGFloat(fw), height: h)
            self.frames = fcount
        } else {
            self.frameSize = CGSize(width: w, height: h)
            self.frames = 1
        }
        self.fps = max(1, fps ?? 6)
    }

    /// 取第 index 帧的 NSImage（单帧直接返回整图）。
    public func frame(at index: Int) -> NSImage {
        guard frames > 1 else { return image }
        let i = ((index % frames) + frames) % frames
        let fw = Int(frameSize.width)
        let fh = Int(frameSize.height)
        let x = i * fw
        guard let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil),
              let crop = cg.cropping(to: CGRect(x: x, y: 0, width: fw, height: fh)) else {
            return image
        }
        return NSImage(cgImage: crop, size: frameSize)
    }
}
