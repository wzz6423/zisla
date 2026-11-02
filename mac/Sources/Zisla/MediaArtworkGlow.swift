import SwiftUI
import ZislaCore
import ZislaKit

struct MediaArtworkGlowState: Equatable {
    let energy: Double
    let observesSpectrum: Bool
    let usesSolidColor: Bool
    let opacity: Double
    let spread: Double

    var animates: Bool { energy > 0 }

    init(
        levels: [Float], isActive: Bool, isVisible: Bool, isAudible: Bool,
        reduceMotion: Bool, reduceTransparency: Bool
    ) {
        observesSpectrum = isActive && isVisible && !reduceMotion && !reduceTransparency
        usesSolidColor = reduceTransparency
        if observesSpectrum, isAudible, !levels.isEmpty {
            let squaredEnergy = levels.reduce(0.0) { total, level in
                let value = level.isFinite ? min(1, max(0, Double(level))) : 0
                return total + value * value
            }
            energy = sqrt(squaredEnergy / Double(levels.count))
        } else {
            energy = 0
        }
        opacity = isVisible ? (reduceTransparency ? 1 : 0.18 + energy * 0.48) : 0
        spread = 0.78 + energy * 0.48
    }
}

@MainActor
struct MediaArtworkGlow: View {
    let width: CGFloat
    let height: CGFloat
    let isActive: Bool
    let isVisible: Bool
    private let tint: Color
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    init(
        artworkData: Data?, width: CGFloat, height: CGFloat,
        isActive: Bool, isVisible: Bool = true
    ) {
        self.width = width
        self.height = height
        self.isActive = isActive
        self.isVisible = isVisible
        tint = MediaWaveformView.tintColor(for: artworkData, sampleBottomEdge: true)
    }

    var body: some View {
        let state = MediaArtworkGlowState(
            levels: [], isActive: isActive, isVisible: isVisible, isAudible: false,
            reduceMotion: reduceMotion, reduceTransparency: reduceTransparency
        )
        Group {
            if state.observesSpectrum {
                LiveMediaArtworkGlow(tint: tint, width: width, height: height)
            } else {
                MediaArtworkGlowField(tint: tint, width: width, height: height, state: state)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .transaction { transaction in
            if !state.observesSpectrum { transaction.disablesAnimations = true }
        }
    }
}

private struct LiveMediaArtworkGlow: View {
    let tint: Color
    let width: CGFloat
    let height: CGFloat
    @ObservedObject private var spectrum = AudioSpectrumService.shared

    var body: some View {
        let state = MediaArtworkGlowState(
            levels: spectrum.levels, isActive: true, isVisible: true, isAudible: spectrum.isAudible,
            reduceMotion: false, reduceTransparency: false
        )
        MediaArtworkGlowField(tint: tint, width: width, height: height, state: state)
            .animation(state.animates ? .easeOut(duration: 0.16) : nil, value: state.energy)
    }
}

struct MediaArtworkGlowField: View {
    let tint: Color
    let width: CGFloat
    let height: CGFloat
    let state: MediaArtworkGlowState

    var body: some View {
        Group {
            if state.usesSolidColor {
                Capsule()
                    .fill(tint)
                    .frame(width: width * 0.66, height: 2)
                    .offset(y: 3)
            } else {
                Ellipse()
                    .fill(tint)
                    .frame(width: width * state.spread, height: height * 0.48 * state.spread)
                    .blur(radius: height * (0.12 + state.energy * 0.06))
                    .offset(y: height * 0.12)
            }
        }
        .frame(width: width, height: height, alignment: .bottom)
        .opacity(state.opacity)
    }
}

@MainActor
struct CompactMediaArtwork: View {
    let artworkData: Data?
    var sourceIconData: Data? = nil
    var symbol = "music.note"
    let size: CGFloat
    let visualizationStyle: MediaVisualizationStyle
    let isActive: Bool
    var isVisible = true

    var body: some View {
        Group {
            if let image = MediaArtworkImageCache.image(from: artworkData, fallback: sourceIconData) {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Image(systemName: symbol)
                    .font(.system(size: size * 0.64, weight: .semibold))
                    .foregroundStyle(.white)
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
        .background(alignment: .bottom) {
            if visualizationStyle == .glow {
                MediaArtworkGlow(
                    artworkData: MediaArtworkImageCache.displayData(from: artworkData, fallback: sourceIconData),
                    width: size,
                    height: size,
                    isActive: isActive,
                    isVisible: isVisible
                )
            }
        }
    }
}
