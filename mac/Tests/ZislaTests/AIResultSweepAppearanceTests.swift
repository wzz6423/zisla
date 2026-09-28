import AppKit
import SwiftUI
import Testing
import ZislaCore

@testable import Zisla

struct AIResultSweepAppearanceTests {
    @Test @MainActor
    func resultColorsRemainDeepWithAVisibleGradient() throws {
        for status: AIProgressStatus in [.succeeded, .failed] {
            let bitmap = try renderedBand(status: status, progress: 0.5, width: 240, height: 34, reduceMotion: true)
            let values = try dominantPixels(bitmap, status: status)
            let lit = values.filter { $0 > 0.02 }
            let peak = try #require(lit.max())
            #expect(peak > 0.3, "深色光带仍需要可见的亮芯")
            #expect(peak < 0.53, "主带不能恢复成高亮荧光绿或鲜红")
            #expect(lit.reduce(0, +) / Double(lit.count) < 0.25)
        }
    }

    @Test @MainActor
    func particlesScatterAcrossTheBandInsteadOfFormingTwoEdgeLines() throws {
        for status: AIProgressStatus in [.succeeded, .failed] {
            for (width, height) in [(240, 34), (748, 324)] {
                let moving = try dominantPixels(renderedBand(
                    status: status, progress: 0.5, width: width, height: height
                ), status: status)
                let still = try dominantPixels(renderedBand(
                    status: status, progress: 0.5, width: width, height: height, reduceMotion: true
                ), status: status)
                let particlePixels = moving.indices.filter { moving[$0] - still[$0] > 0.015 }
                let occupiedBands = Set(particlePixels.map {
                    Int((Double($0 % width) / Double(width) - 0.29) / 0.42 * 6)
                })
                #expect(occupiedBands.count >= 4, "粒子必须散布在光带内，不能集中成两条竖线")
                #expect(occupiedBands.allSatisfy { (0..<6).contains($0) }, "两侧不能出现脱离光带的亮线")
                #expect(particlePixels.count < width * height / 25, "粒子面积必须稀疏")
                #expect(particlePixels.contains { $0 / width >= height - 2 }, "窄收起条底部也要保留粒子")
            }
        }
    }

    @Test @MainActor
    func particlesMoveWithTheBandDeterministically() throws {
        var centers: [Double] = []
        let width = 250
        for progress in [0.4, 0.6] {
            let first = try renderedBand(status: .succeeded, progress: progress, width: width, height: 34)
            let second = try renderedBand(status: .succeeded, progress: progress, width: width, height: 34)
            let pixels = try dominantPixels(first, status: .succeeded)
            #expect(pixels == (try dominantPixels(second, status: .succeeded)), "同一进度的粒子不能每帧随机闪跳")
            let contrasts = (0..<width).map { x in
                let column = stride(from: x, to: pixels.count, by: width).map { pixels[$0] }
                return column.max()! - column.min()!
            }
            let lit = contrasts.indices.filter { contrasts[$0] > 0.04 }
            #expect(!lit.isEmpty, "粒子必须产生局部亮点")
            centers.append(Double(lit.reduce(0, +)) / Double(max(1, lit.count)))
        }
        #expect(centers[1] - centers[0] > 60, "两侧粒子应跟随光带从左向右移动")
    }

    @Test @MainActor
    func particlesBrightenAndDimOnceWithoutReigniting() throws {
        let width = 500
        let height = 100
        let midpoint = try dominantPixels(renderedBand(
            status: .succeeded, progress: 0.5, width: width, height: height
        ), status: .succeeded)
        let background = try dominantPixels(renderedBand(
            status: .succeeded, progress: 0.5, width: width, height: height, reduceMotion: true
        ), status: .succeeded)
        let particle = try #require(midpoint.indices.max { midpoint[$0] - background[$0] < midpoint[$1] - background[$1] })
        #expect(midpoint[particle] - background[particle] > 0.04)
        var brightness: [Double] = []
        for progress in [0.3, 0.4, 0.5, 0.6, 0.7] {
            let pixels = try dominantPixels(renderedBand(
                status: .succeeded, progress: progress, width: width, height: height
            ), status: .succeeded)
            let translation = Int(((progress - 0.5) * 710).rounded())
            brightness.append(pixels[particle + translation])
        }
        #expect(brightness[0] < brightness[1] && brightness[1] < brightness[2])
        #expect(brightness[2] > brightness[3] && brightness[3] > brightness[4])
        #expect(abs(brightness[0] - brightness[4]) < 0.01)
        #expect(abs(brightness[1] - brightness[3]) < 0.01)
    }

    @Test @MainActor
    func glowHasABrightCenterAndDarkSymmetricShoulders() throws {
        for status: AIProgressStatus in [.succeeded, .failed] {
            for reduceMotion in [false, true] {
                let width = 240
                let pixels = try dominantPixels(renderedBand(
                    status: status, progress: 0.5, width: width, height: 34, reduceMotion: reduceMotion
                ), status: status)
                let center = pixels.indices.filter { (108..<132).contains($0 % width) }.map { pixels[$0] }.max()!
                let sides = pixels.indices.filter { !(84..<156).contains($0 % width) }.map { pixels[$0] }.max()!
                #expect(center > sides * 1.5, "中心应最亮，不能出现两缘亮、中间暗的双峰")
                if reduceMotion {
                    let row = Array(pixels[17 * width..<18 * width])
                    #expect(zip(row, row.reversed()).allSatisfy { abs($0 - $1) < 0.015 }, "渐变应以中间为峰值对称衰减")
                }
            }
        }
    }

    @Test @MainActor
    func reducedMotionAndFinishedSweepsHaveNoParticleTexture() throws {
        for (progress, reduceMotion) in [(0.5, true), (0.0, false), (1.0, false)] {
            let bitmap = try renderedBand(
                status: .failed, progress: progress, width: 240, height: 34, reduceMotion: reduceMotion
            )
            let pixels = try dominantPixels(bitmap, status: .failed)
            for x in 0..<240 {
                let column = stride(from: x, to: pixels.count, by: 240).map { pixels[$0] }
                #expect(column.max()! - column.min()! < 0.01)
            }
            if progress != 0.5 { #expect(pixels.max()! < 0.01) }
        }
    }

    @MainActor
    private func renderedBand(
        status: AIProgressStatus, progress: Double, width: Int, height: Int, reduceMotion: Bool = false
    ) throws -> NSBitmapImageRep {
        let renderer = ImageRenderer(content: AIResultSweepBand(
            status: status, progress: progress, reduceMotion: reduceMotion
        ).frame(width: CGFloat(width), height: CGFloat(height)).background(.black))
        return NSBitmapImageRep(cgImage: try #require(renderer.cgImage))
    }

    private func dominantPixels(_ bitmap: NSBitmapImageRep, status: AIProgressStatus) throws -> [Double] {
        try (0..<bitmap.pixelsHigh).flatMap { y in
            try (0..<bitmap.pixelsWide).map { x in
                let color = try #require(bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB))
                return Double(status == .succeeded ? color.greenComponent : color.redComponent)
            }
        }
    }
}
