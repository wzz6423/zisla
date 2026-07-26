import AppKit
import ZislaKit
import SwiftUI

@MainActor
enum MediaArtworkImageCache {
  private static let cache: NSCache<NSData, NSImage> = {
    let cache = NSCache<NSData, NSImage>()
    cache.countLimit = 24
    cache.totalCostLimit = 48 * 1_024 * 1_024
    return cache
  }()

  static func image(from data: Data?) -> NSImage? {
    guard let data else { return nil }
    let key = data as NSData
    if let cached = cache.object(forKey: key) { return cached }
    guard let image = NSImage(data: data) else { return nil }

    let decodedByteCost = image.representations.reduce(data.count) { cost, representation in
      max(cost, representation.pixelsWide * representation.pixelsHigh * 4)
    }
    cache.setObject(image, forKey: key, cost: decodedByteCost)
    return image
  }
}

@MainActor
struct MediaWaveformView: View {
  var artworkData: Data?
  var width: CGFloat
  var height: CGFloat
  var isActive: Bool

  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  private let tint: Color

  init(artworkData: Data?, width: CGFloat, height: CGFloat, isActive: Bool) {
    self.artworkData = artworkData
    self.width = width
    self.height = height
    self.isActive = isActive
    tint = ArtworkWaveformColor.color(from: artworkData)
  }

  var body: some View {
    if isActive && !reduceMotion {
      LiveMediaWaveform(tint: tint, width: width, height: height)
    } else {
      WaveformBars(
        values: Self.silentLevels,
        tint: tint,
        width: width,
        height: height
      )
    }
  }

  private static let silentLevels = Array(
    repeating: Float.zero,
    count: AudioSpectrumService.bandCount
  )
}

private struct LiveMediaWaveform: View {
  let tint: Color
  let width: CGFloat
  let height: CGFloat
  @ObservedObject private var spectrum = AudioSpectrumService.shared

  var body: some View {
    WaveformBars(
      values: spectrum.levels,
      tint: tint,
      width: width,
      height: height
    )
  }
}

private struct WaveformBars: View {
  let values: [Float]
  let tint: Color
  let width: CGFloat
  let height: CGFloat

  var body: some View {
    let count = AudioSpectrumService.bandCount
    let spacing = min(2.4, width * 0.055)
    let barWidth = max(2, (width - spacing * CGFloat(count - 1)) / CGFloat(count))

    HStack(alignment: .center, spacing: spacing) {
      ForEach(0..<count, id: \.self) { index in
        let level = values.indices.contains(index) ? CGFloat(values[index]) : 0
        RoundedRectangle(cornerRadius: barWidth / 2, style: .continuous)
          .fill(tint.opacity(0.94))
          .frame(
            width: barWidth,
            height: max(3, height * (0.16 + min(max(level, 0), 1) * 0.84))
          )
      }
    }
    .frame(width: width, height: height)
    .accessibilityHidden(true)
  }
}

@MainActor
private enum ArtworkWaveformColor {
  static let fallback = Color.white.opacity(0.9)
  private static let cache: NSCache<NSData, NSColor> = {
    let cache = NSCache<NSData, NSColor>()
    cache.countLimit = 32
    return cache
  }()

  static func color(from data: Data?) -> Color {
    guard let data else { return fallback }
    let key = data as NSData
    if let cached = cache.object(forKey: key) {
      return Color(nsColor: cached)
    }

    guard let representation = NSBitmapImageRep(data: data),
      representation.pixelsWide > 0,
      representation.pixelsHigh > 0
    else { return fallback }

    let stepX = max(1, representation.pixelsWide / 10)
    let stepY = max(1, representation.pixelsHigh / 10)
    var selected: (color: NSColor, score: CGFloat)?

    for y in stride(from: stepY / 2, to: representation.pixelsHigh, by: stepY) {
      for x in stride(from: stepX / 2, to: representation.pixelsWide, by: stepX) {
        guard
          let color = representation.colorAt(x: x, y: y)?
            .usingColorSpace(.deviceRGB)
        else { continue }
        let score =
          color.saturationComponent * 0.7
          + min(color.brightnessComponent, 0.82) * 0.3
        if selected == nil || score > selected!.score {
          selected = (color, score)
        }
      }
    }

    guard let selected else { return fallback }
    let source = selected.color
    let visible = NSColor(
      hue: source.hueComponent,
      saturation: max(0.52, source.saturationComponent),
      brightness: max(0.72, source.brightnessComponent),
      alpha: 1
    )
    cache.setObject(visible, forKey: key)
    return Color(nsColor: visible)
  }
}
