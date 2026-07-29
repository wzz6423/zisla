import AppKit
import Foundation

/// Renderable sprite for a pixel pet.
///
/// Supports two sources:
/// - Single-frame PNG: `PetSpriteView` animates it programmatically (float/breathe/occasional hop);
/// - Horizontal sprite sheet PNG (`frameWidth` + `frames` specified): plays back in a loop at `fps`.
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

    /// Returns the `NSImage` for frame at `index` (returns the full image for a single-frame sprite).
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
